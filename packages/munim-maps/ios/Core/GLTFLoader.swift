import CoreGraphics
import Foundation
import ImageIO
import QuartzCore
import SceneKit
import simd

/// Reads glTF 2.0 models into SceneKit without third-party code: a `.glb`
/// (one binary file) or a `.gltf` with its buffers and images next to it,
/// either as relative files, `data:` URIs or, for a remote `.gltf`, URLs
/// relative to where it was downloaded from (they are downloaded and cached
/// too).
///
/// Supported: the default scene's node tree (TRS or matrix transforms),
/// meshes with any number of primitives (triangles, strips, fans, lines and
/// points), POSITION / NORMAL / TEXCOORD_0 / TEXCOORD_1 / COLOR_0 in float or
/// normalized integer form (so KHR_mesh_quantization too), interleaved
/// buffers, sparse accessors, metallic-roughness PBR materials with every
/// texture slot, alpha modes, double-sided materials, skins (JOINTS_0 /
/// WEIGHTS_0) and the first animation's translation / rotation / scale
/// tracks. Extensions: KHR_materials_emissive_strength,
/// KHR_texture_transform, KHR_materials_unlit,
/// KHR_materials_pbrSpecularGlossiness (approximated) and EXT_texture_webp.
///
/// Not supported: Draco and meshopt compression, KTX2 / Basis textures,
/// morph targets, cameras and lights (both ignored).
enum GLTFLoader {
  /// Whether `url` is glTF: a `.gltf` or `.glb` file, or a file that starts
  /// like one. Remote models without an extension are cached as `.usdz`, so
  /// the contents are checked as well.
  static func canLoad(_ url: URL) -> Bool {
    switch url.pathExtension.lowercased() {
    case "gltf", "glb": return true
    default: break
    }
    guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
    defer { try? handle.close() }
    guard let head = try? handle.read(upToCount: 16), !head.isEmpty else { return false }
    // A GLB starts with the ASCII magic "glTF".
    if head.starts(with: [0x67, 0x6C, 0x54, 0x46]) { return true }
    // A .gltf is JSON; none of the formats SceneKit reads start with "{".
    let text = head.drop { [0x20, 0x09, 0x0A, 0x0D, 0xEF, 0xBB, 0xBF].contains($0) }
    return text.first == UInt8(ascii: "{")
  }

  /// Loads the glTF file at `url`. `sourceURI` is the uri the app gave; when
  /// it is remote, relative buffer and image URIs resolve against it rather
  /// than against the cached copy.
  static func loadScene(at url: URL, sourceURI: String) throws -> SCNScene {
    let trimmed = sourceURI.trimmingCharacters(in: .whitespacesAndNewlines)
    var baseURL = url
    var isRemote = false
    if let remote = URL(string: trimmed), let scheme = remote.scheme?.lowercased(),
       scheme == "http" || scheme == "https" {
      baseURL = remote
      isRemote = true
    }
    let sourceName = URL(string: trimmed)?.lastPathComponent ?? ""
    let name = sourceName.isEmpty || sourceName == "/" ? url.lastPathComponent : sourceName
    let data: Data
    do {
      data = try Data(contentsOf: url, options: .mappedIfSafe)
    } catch {
      throw MapModelError.message("\(name): could not be read (\(error.localizedDescription))")
    }
    let document = try GLTFDocument(data: data, baseURL: baseURL, isRemote: isRemote, name: name)
    return try document.makeScene()
  }

  static let dracoMessage = "Draco-compressed glTF is not supported; export without compression"
  static let meshoptMessage = "Meshopt-compressed glTF is not supported; export without compression"
}

// MARK: - Document

private final class GLTFDocument {
  let name: String
  let json: [String: Any]
  let binaryChunk: Data?
  let baseURL: URL
  let isRemote: Bool

  private lazy var accessors = json.jsonObjects("accessors")
  private lazy var bufferViews = json.jsonObjects("bufferViews")
  private lazy var buffers = json.jsonObjects("buffers")
  private lazy var images = json.jsonObjects("images")
  private lazy var textures = json.jsonObjects("textures")
  private lazy var samplers = json.jsonObjects("samplers")
  private lazy var materials = json.jsonObjects("materials")
  private lazy var meshes = json.jsonObjects("meshes")
  private lazy var nodes = json.jsonObjects("nodes")
  private lazy var skins = json.jsonObjects("skins")

  private var bufferCache: [Int: Data] = [:]
  private var imageCache: [Int: CGImage] = [:]
  private var failedImages: Set<Int> = []
  private var materialCache: [Int: SCNMaterial] = [:]
  private var meshCache: [Int: [Primitive]] = [:]
  private var nodeMap: [Int: SCNNode] = [:]
  private var skinBindings: [(node: SCNNode, primitive: Primitive, skin: Int)] = []
  private var warnings: [String] = []
  private lazy var defaultMaterial: SCNMaterial = {
    // The glTF default material: white, metallic 1, roughness 1.
    let material = SCNMaterial()
    material.lightingModel = .physicallyBased
    material.diffuse.contents = GLTFDocument.linearColor(SIMD4(1, 1, 1, 1))
    material.metalness.contents = NSNumber(value: 1)
    material.roughness.contents = NSNumber(value: 1)
    return material
  }()

  struct Primitive {
    let geometry: SCNGeometry
    /// Four joint indices and weights per vertex, when the mesh is skinned.
    let joints: [UInt32]?
    let weights: [Float]?
  }

  init(data: Data, baseURL: URL, isRemote: Bool, name: String) throws {
    self.name = name
    self.baseURL = baseURL
    self.isRemote = isRemote

    var jsonData = data
    var binary: Data?
    if data.count >= 4, data.starts(with: [0x67, 0x6C, 0x54, 0x46]) {
      guard data.count >= 12 else { throw MapModelError.message("\(name): the GLB header is truncated") }
      let version = data.gltfU32(at: 4)
      guard version == 2 else {
        throw MapModelError.message("\(name): GLB version \(version) is not supported; export as glTF 2.0")
      }
      let length = min(Int(data.gltfU32(at: 8)), data.count)
      var foundJSON: Data?
      var offset = 12
      while offset + 8 <= length {
        let chunkLength = Int(data.gltfU32(at: offset))
        let chunkType = data.gltfU32(at: offset + 4)
        let start = offset + 8
        guard chunkLength >= 0, start + chunkLength <= length else {
          throw MapModelError.message("\(name): the GLB file is truncated")
        }
        if chunkType == 0x4E4F534A, foundJSON == nil {  // "JSON"
          foundJSON = data.subdata(in: start..<start + chunkLength)
        } else if chunkType == 0x004E4942, binary == nil {  // "BIN\0"
          binary = data.subdata(in: start..<start + chunkLength)
        }
        offset = start + chunkLength
      }
      guard let foundJSON else { throw MapModelError.message("\(name): the GLB file has no JSON chunk") }
      jsonData = foundJSON
    }
    binaryChunk = binary

    let object: Any
    do {
      object = try JSONSerialization.jsonObject(with: jsonData)
    } catch {
      throw MapModelError.message("\(name): is not valid glTF JSON (\(error.localizedDescription))")
    }
    guard let root = object as? [String: Any] else {
      throw MapModelError.message("\(name): is not valid glTF JSON")
    }
    json = root
    let version = root.jsonObject("asset")?.jsonString("version") ?? ""
    guard version.hasPrefix("2") else {
      throw MapModelError.message(
        "\(name): glTF \(version.isEmpty ? "1.0" : version) is not supported; re-export as glTF 2.0")
    }
    try checkRequiredExtensions()
  }

  private func fail(_ message: String) -> Error {
    MapModelError.message("\(name): \(message)")
  }

  private func warn(_ message: String) {
    if !warnings.contains(message) { warnings.append(message) }
  }

  private func checkRequiredExtensions() throws {
    let supported: Set<String> = [
      "KHR_materials_emissive_strength", "KHR_texture_transform", "KHR_materials_unlit",
      "KHR_mesh_quantization", "KHR_materials_pbrSpecularGlossiness", "EXT_texture_webp",
    ]
    for name in json["extensionsRequired"] as? [String] ?? [] {
      switch name {
      case "KHR_draco_mesh_compression":
        throw fail(GLTFLoader.dracoMessage)
      case "EXT_meshopt_compression", "KHR_meshopt_compression":
        throw fail(GLTFLoader.meshoptMessage)
      case "KHR_texture_basisu":
        throw fail("KTX2 (Basis Universal) textures are not supported; export with PNG or JPEG textures")
      default:
        guard supported.contains(name) else {
          throw fail("needs the glTF extension \(name), which munim-maps does not support")
        }
      }
    }
  }

  // MARK: Scene

  func makeScene() throws -> SCNScene {
    var roots: [Int]
    if let scene = json.jsonObjects("scenes").gltfElement(at: json.jsonInt("scene") ?? 0) {
      roots = scene.jsonInts("nodes")
    } else {
      // No scenes: show every node that is not another node's child.
      let children = Set(nodes.flatMap { $0.jsonInts("children") })
      roots = nodes.indices.filter { !children.contains($0) }
    }

    let root = SCNNode()
    root.name = "glTF"
    // glTF is Y-up, right-handed and in metres, like SceneKit, but a glTF
    // model's front faces +Z while munim-maps models face -Z (north at
    // heading 0). Turning the whole model 180 degrees about Y makes a glTF
    // exported facing +Z face north at heading 0, like the bundled vehicles.
    root.simdOrientation = simd_quatf(angle: .pi, axis: SIMD3(0, 1, 0))
    for index in roots {
      if let node = try buildNode(index, depth: 0) { root.addChildNode(node) }
    }
    bindSkins()
    addAnimations()

    if json["cameras"] != nil { warn("cameras are ignored") }
    if json.jsonObject("extensions")?["KHR_lights_punctual"] != nil { warn("lights are ignored") }
    for warning in warnings { NSLog("munim-maps glTF %@: %@", name, warning) }

    let scene = SCNScene()
    scene.rootNode.addChildNode(root)
    return scene
  }

  private func buildNode(_ index: Int, depth: Int) throws -> SCNNode? {
    guard depth < 512 else { throw fail("the node hierarchy is cyclic or too deep") }
    guard let info = nodes.gltfElement(at: index) else { throw fail("node \(index) does not exist") }
    guard nodeMap[index] == nil else {
      warn("node \(index) has more than one parent; only the first is used")
      return nil
    }
    let node = SCNNode()
    node.name = info.jsonString("name") ?? "node\(index)"
    nodeMap[index] = node

    if let m = info.jsonFloats("matrix"), m.count == 16 {
      node.simdTransform = simd_float4x4(columns: (
        SIMD4(m[0], m[1], m[2], m[3]), SIMD4(m[4], m[5], m[6], m[7]),
        SIMD4(m[8], m[9], m[10], m[11]), SIMD4(m[12], m[13], m[14], m[15])))
    } else {
      if let t = info.jsonFloats("translation"), t.count == 3 {
        node.simdPosition = SIMD3(t[0], t[1], t[2])
      }
      if let r = info.jsonFloats("rotation"), r.count == 4 {
        let q = simd_quatf(ix: r[0], iy: r[1], iz: r[2], r: r[3])
        if simd_length(q.vector) > 0 { node.simdOrientation = simd_normalize(q) }
      }
      if let s = info.jsonFloats("scale"), s.count == 3 {
        node.simdScale = SIMD3(s[0], s[1], s[2])
      }
    }

    if let meshIndex = info.jsonInt("mesh") {
      let primitives = try meshPrimitives(meshIndex)
      let skin = info.jsonInt("skin")
      if primitives.count == 1 {
        node.geometry = primitives[0].geometry
        if let skin { skinBindings.append((node, primitives[0], skin)) }
      } else {
        for (i, primitive) in primitives.enumerated() {
          let child = SCNNode(geometry: primitive.geometry)
          child.name = "\(node.name ?? "node")-\(i)"
          node.addChildNode(child)
          if let skin { skinBindings.append((child, primitive, skin)) }
        }
      }
    }
    for child in info.jsonInts("children") {
      if let childNode = try buildNode(child, depth: depth + 1) { node.addChildNode(childNode) }
    }
    return node
  }

  // MARK: Meshes

  private func meshPrimitives(_ index: Int) throws -> [Primitive] {
    if let cached = meshCache[index] { return cached }
    guard let mesh = meshes.gltfElement(at: index) else { throw fail("mesh \(index) does not exist") }
    var result: [Primitive] = []
    for (i, info) in mesh.jsonObjects("primitives").enumerated() {
      if let primitive = try makePrimitive(info, label: "mesh \(index) primitive \(i)", meshName: mesh.jsonString("name")) {
        result.append(primitive)
      }
    }
    meshCache[index] = result
    return result
  }

  private func makePrimitive(_ info: [String: Any], label: String, meshName: String?) throws -> Primitive? {
    let attributes = info.jsonObject("attributes") ?? [:]
    let isDraco = info.jsonObject("extensions")?["KHR_draco_mesh_compression"] != nil
    guard let positionIndex = attributes.jsonInt("POSITION") else {
      if isDraco { throw fail(GLTFLoader.dracoMessage) }
      warn("\(label) has no POSITION and was skipped")
      return nil
    }
    // Draco primitives may carry uncompressed fallback data; without it the
    // accessors have no bufferView.
    if isDraco, accessors.gltfElement(at: positionIndex)?.jsonInt("bufferView") == nil {
      throw fail(GLTFLoader.dracoMessage)
    }
    if info["targets"] != nil { warn("morph targets are ignored") }
    if attributes["JOINTS_1"] != nil { warn("only the first four joint influences per vertex are used") }

    let positions = try floats(positionIndex)
    guard positions.components == 3 else { throw fail("\(label) POSITION is not VEC3") }
    let vertexCount = positions.count
    guard vertexCount > 0 else { return nil }

    var indices: [UInt32]
    if let indicesIndex = info.jsonInt("indices") {
      indices = try uints(indicesIndex).values
      if let bad = indices.first(where: { Int($0) >= vertexCount }) {
        throw fail("\(label) has index \(bad) but only \(vertexCount) vertices")
      }
    } else {
      indices = (0..<UInt32(vertexCount)).map { $0 }
    }

    let primitiveType: SCNGeometryPrimitiveType
    switch info.jsonInt("mode") ?? 4 {
    case 4:
      primitiveType = .triangles
      indices.removeLast(indices.count % 3)
    case 5:  // Triangle strip: alternate the winding so every face keeps its front.
      primitiveType = .triangles
      var triangles: [UInt32] = []
      if indices.count >= 3 {
        triangles.reserveCapacity((indices.count - 2) * 3)
        for i in 0..<(indices.count - 2) {
          if i % 2 == 0 {
            triangles += [indices[i], indices[i + 1], indices[i + 2]]
          } else {
            triangles += [indices[i + 1], indices[i], indices[i + 2]]
          }
        }
      }
      indices = triangles
    case 6:  // Triangle fan.
      primitiveType = .triangles
      var triangles: [UInt32] = []
      if indices.count >= 3 {
        for i in 1..<(indices.count - 1) { triangles += [indices[0], indices[i], indices[i + 1]] }
      }
      indices = triangles
    case 1:
      primitiveType = .line
      indices.removeLast(indices.count % 2)
    case 3, 2:  // Line strip, or loop when mode is 2.
      primitiveType = .line
      var lines: [UInt32] = []
      if indices.count >= 2 {
        for i in 0..<(indices.count - 1) { lines += [indices[i], indices[i + 1]] }
        if info.jsonInt("mode") == 2 { lines += [indices[indices.count - 1], indices[0]] }
      }
      indices = lines
    case 0:
      primitiveType = .point
    default:
      warn("\(label) has an unknown primitive mode and was skipped")
      return nil
    }
    guard !indices.isEmpty else { return nil }

    func attribute(_ key: String, components allowed: Set<Int>) throws -> (values: [Float], components: Int)? {
      guard let index = attributes.jsonInt(key) else { return nil }
      let result = try floats(index)
      guard allowed.contains(result.components), result.count >= vertexCount else {
        warn("\(label) \(key) has the wrong type or count and was ignored")
        return nil
      }
      return (result.values, result.components)
    }

    var normals = try attribute("NORMAL", components: [3])?.values
    // Without normals glTF asks for flat shading, which needs a vertex per
    // face corner: un-index the triangles and give each face its normal.
    var remap: [UInt32]?
    if normals == nil, primitiveType == .triangles {
      remap = indices
      var flat = [Float](repeating: 0, count: indices.count * 3)
      let p = positions.values
      for t in stride(from: 0, to: indices.count, by: 3) {
        func point(_ i: UInt32) -> SIMD3<Float> {
          let k = Int(i) * 3
          return SIMD3(p[k], p[k + 1], p[k + 2])
        }
        let a = point(indices[t]), b = point(indices[t + 1]), c = point(indices[t + 2])
        let cross = simd_cross(b - a, c - a)
        let length = simd_length(cross)
        let n = length > 0 ? cross / length : SIMD3<Float>(0, 1, 0)
        for corner in 0..<3 {
          flat[(t + corner) * 3] = n.x
          flat[(t + corner) * 3 + 1] = n.y
          flat[(t + corner) * 3 + 2] = n.z
        }
      }
      normals = flat
      indices = (0..<UInt32(indices.count)).map { $0 }
    }

    func expand<T>(_ values: [T], _ components: Int) -> [T] {
      guard let remap else { return values }
      var out: [T] = []
      out.reserveCapacity(remap.count * components)
      for i in remap {
        let base = Int(i) * components
        out.append(contentsOf: values[base..<base + components])
      }
      return out
    }

    var sources: [SCNGeometrySource] = []
    sources.append(Self.source(expand(positions.values, 3), semantic: .vertex, components: 3))
    if let normals {
      // Flat normals are already one per corner.
      sources.append(Self.source(normals, semantic: .normal, components: 3))
    }
    if let uv0 = try attribute("TEXCOORD_0", components: [2]) {
      sources.append(Self.source(expand(uv0.values, 2), semantic: .texcoord, components: 2))
      if let uv1 = try attribute("TEXCOORD_1", components: [2]) {
        sources.append(Self.source(expand(uv1.values, 2), semantic: .texcoord, components: 2))
      }
    }
    if let colors = try attribute("COLOR_0", components: [3, 4]) {
      var rgba = colors.values
      if colors.components == 3 {
        rgba = []
        rgba.reserveCapacity(vertexCount * 4)
        for i in 0..<vertexCount {
          rgba += [colors.values[i * 3], colors.values[i * 3 + 1], colors.values[i * 3 + 2], 1]
        }
      }
      sources.append(Self.source(expand(rgba, 4), semantic: .color, components: 4))
    }

    let indexData = indices.withUnsafeBufferPointer { Data(buffer: $0) }
    let primitiveCount: Int
    switch primitiveType {
    case .triangles: primitiveCount = indices.count / 3
    case .line: primitiveCount = indices.count / 2
    default: primitiveCount = indices.count
    }
    let element = SCNGeometryElement(
      data: indexData, primitiveType: primitiveType,
      primitiveCount: primitiveCount, bytesPerIndex: 4)
    if primitiveType == .point {
      element.pointSize = 2
      element.minimumPointScreenSpaceRadius = 1
      element.maximumPointScreenSpaceRadius = 4
    }

    let geometry = SCNGeometry(sources: sources, elements: [element])
    geometry.name = meshName
    if let materialIndex = info.jsonInt("material") {
      geometry.materials = [material(materialIndex)]
    } else {
      geometry.materials = [defaultMaterial]
    }

    var joints: [UInt32]?
    var weights: [Float]?
    if let jointsIndex = attributes.jsonInt("JOINTS_0"), let weightsIndex = attributes.jsonInt("WEIGHTS_0") {
      let j = try uints(jointsIndex)
      let w = try floats(weightsIndex)
      if j.components == 4, w.components == 4, j.count >= vertexCount, w.count >= vertexCount {
        joints = expand(j.values, 4)
        weights = expand(w.values, 4)
      } else {
        warn("\(label) has unusable JOINTS_0 / WEIGHTS_0; it is not skinned")
      }
    }
    return Primitive(geometry: geometry, joints: joints, weights: weights)
  }

  private static func source(_ values: [Float], semantic: SCNGeometrySource.Semantic, components: Int) -> SCNGeometrySource {
    let data = values.withUnsafeBufferPointer { Data(buffer: $0) }
    return SCNGeometrySource(
      data: data, semantic: semantic, vectorCount: values.count / components,
      usesFloatComponents: true, componentsPerVector: components,
      bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
      dataStride: MemoryLayout<Float>.size * components)
  }

  // MARK: Skins and animation

  private func bindSkins() {
    for binding in skinBindings {
      guard let skin = skins.gltfElement(at: binding.skin),
            let jointIndices = binding.primitive.joints,
            let jointWeights = binding.primitive.weights,
            let geometry = binding.node.geometry
      else { continue }
      let jointNodes = skin.jsonInts("joints")
      let bones = jointNodes.compactMap { nodeMap[$0] }
      guard !bones.isEmpty, bones.count == jointNodes.count else {
        warn("skin \(binding.skin) uses joints outside the scene; it is shown unskinned")
        continue
      }
      var inverseBind = [simd_float4x4](repeating: matrix_identity_float4x4, count: bones.count)
      if let ibmIndex = skin.jsonInt("inverseBindMatrices") {
        guard let m = try? floats(ibmIndex), m.components == 16 else {
          warn("skin \(binding.skin) has unreadable inverseBindMatrices; it is shown unskinned")
          continue
        }
        for i in 0..<min(bones.count, m.count) {
          let v = Array(m.values[i * 16..<i * 16 + 16])
          inverseBind[i] = simd_float4x4(columns: (
            SIMD4(v[0], v[1], v[2], v[3]), SIMD4(v[4], v[5], v[6], v[7]),
            SIMD4(v[8], v[9], v[10], v[11]), SIMD4(v[12], v[13], v[14], v[15])))
        }
      }

      let vertexCount = jointIndices.count / 4
      let lastBone = UInt32(bones.count - 1)
      var boneIndices = [UInt16](repeating: 0, count: vertexCount * 4)
      var boneWeights = [Float](repeating: 0, count: vertexCount * 4)
      for v in 0..<vertexCount {
        var sum: Float = 0
        for k in 0..<4 { sum += max(0, jointWeights[v * 4 + k]) }
        for k in 0..<4 {
          boneIndices[v * 4 + k] = UInt16(min(jointIndices[v * 4 + k], lastBone))
          boneWeights[v * 4 + k] = sum > 0 ? max(0, jointWeights[v * 4 + k]) / sum : (k == 0 ? 1 : 0)
        }
      }
      let indexSource = SCNGeometrySource(
        data: boneIndices.withUnsafeBufferPointer { Data(buffer: $0) },
        semantic: .boneIndices, vectorCount: vertexCount, usesFloatComponents: false,
        componentsPerVector: 4, bytesPerComponent: 2, dataOffset: 0, dataStride: 8)
      let weightSource = Self.source(boneWeights, semantic: .boneWeights, components: 4)
      let skinner = SCNSkinner(
        baseGeometry: geometry, bones: bones,
        boneInverseBindTransforms: inverseBind.map { NSValue(scnMatrix4: SCNMatrix4($0)) },
        boneWeights: weightSource, boneIndices: indexSource)
      if let skeleton = skin.jsonInt("skeleton").flatMap({ nodeMap[$0] }) {
        skinner.skeleton = skeleton
      }
      binding.node.skinner = skinner
    }
  }

  /// Plays the first animation's node tracks as looping SceneKit animations,
  /// which `MapModelNodes.setAnimationsPlaying` starts and stops.
  private func addAnimations() {
    let animations = json.jsonObjects("animations")
    guard let animation = animations.first else { return }
    if animations.count > 1 { warn("only the first of \(animations.count) animations is played") }
    let samplers = animation.jsonObjects("samplers")

    struct Track {
      let node: SCNNode
      let path: String
      var times: [Float]
      var values: [SIMD4<Float>]
    }
    var tracks: [Track] = []
    var duration: Float = 0
    for channel in animation.jsonObjects("channels") {
      guard let target = channel.jsonObject("target"),
            let path = target.jsonString("path"),
            let node = target.jsonInt("node").flatMap({ nodeMap[$0] }),
            let sampler = samplers.gltfElement(at: channel.jsonInt("sampler") ?? -1),
            let inputIndex = sampler.jsonInt("input"),
            let outputIndex = sampler.jsonInt("output")
      else { continue }
      guard path == "translation" || path == "rotation" || path == "scale" else {
        if path == "weights" { warn("morph target animations are ignored") }
        continue
      }
      guard let input = try? floats(inputIndex), let output = try? floats(outputIndex) else { continue }
      let components = path == "rotation" ? 4 : 3
      let interpolation = sampler.jsonString("interpolation") ?? "LINEAR"
      let cubic = interpolation == "CUBICSPLINE"
      let keyCount = input.values.count
      guard keyCount > 0, output.components == components,
            output.count >= keyCount * (cubic ? 3 : 1)
      else { continue }

      var values: [SIMD4<Float>] = (0..<keyCount).map { k in
        // Cubic spline keys are (in-tangent, value, out-tangent); use the value.
        let base = (cubic ? k * 3 + 1 : k) * components
        let o = output.values
        return SIMD4(o[base], o[base + 1], o[base + 2], components == 4 ? o[base + 3] : 0)
      }
      if path == "rotation" {
        // Keep neighbouring quaternions in the same hemisphere so the
        // interpolation takes the short way round.
        for k in 1..<max(1, values.count) where simd_dot(values[k], values[k - 1]) < 0 {
          values[k] = -values[k]
        }
      }
      var times = input.values.map { max(0, $0) }
      if interpolation == "STEP", keyCount > 1 {
        var stepTimes: [Float] = []
        var stepValues: [SIMD4<Float>] = []
        for k in 0..<keyCount {
          stepTimes.append(times[k])
          stepValues.append(values[k])
          if k + 1 < keyCount {
            stepTimes.append(times[k + 1])
            stepValues.append(values[k])
          }
        }
        times = stepTimes
        values = stepValues
      }
      duration = max(duration, times.last ?? 0)
      tracks.append(Track(node: node, path: path, times: times, values: values))
    }
    guard duration > 0 else { return }

    // Every track spans the whole animation so they all loop together.
    for (i, var track) in tracks.enumerated() {
      if let first = track.times.first, first > 0 {
        track.times.insert(0, at: 0)
        track.values.insert(track.values[0], at: 0)
      }
      if let last = track.times.last, last < duration {
        track.times.append(duration)
        track.values.append(track.values[track.values.count - 1])
      }
      let keyPath: String
      let values: [NSValue]
      switch track.path {
      case "rotation":
        keyPath = "orientation"
        values = track.values.map { NSValue(scnVector4: SCNVector4($0.x, $0.y, $0.z, $0.w)) }
      case "scale":
        keyPath = "scale"
        values = track.values.map { NSValue(scnVector3: SCNVector3($0.x, $0.y, $0.z)) }
      default:
        keyPath = "position"
        values = track.values.map { NSValue(scnVector3: SCNVector3($0.x, $0.y, $0.z)) }
      }
      let keyframes = CAKeyframeAnimation(keyPath: keyPath)
      keyframes.values = values
      keyframes.keyTimes = track.times.map { NSNumber(value: Double(min(1, $0 / duration))) }
      keyframes.duration = CFTimeInterval(duration)
      keyframes.calculationMode = .linear
      keyframes.repeatCount = .greatestFiniteMagnitude
      let sceneAnimation = SCNAnimation(caAnimation: keyframes)
      sceneAnimation.repeatCount = .greatestFiniteMagnitude
      sceneAnimation.isRemovedOnCompletion = false
      track.node.addAnimationPlayer(SCNAnimationPlayer(animation: sceneAnimation), forKey: "gltf-\(i)")
    }
  }

  // MARK: Materials

  private func material(_ index: Int) -> SCNMaterial {
    if let cached = materialCache[index] { return cached }
    let made = makeMaterial(materials.gltfElement(at: index) ?? [:])
    materialCache[index] = made
    return made
  }

  private func makeMaterial(_ info: [String: Any]) -> SCNMaterial {
    let material = SCNMaterial()
    // Kept as-is so `tintColor` finds materials named `paint…`.
    material.name = info.jsonString("name")
    material.lightingModel = .physicallyBased
    material.isDoubleSided = info.jsonBool("doubleSided") ?? false
    material.transparencyMode = .aOne
    let extensions = info.jsonObject("extensions") ?? [:]
    if extensions["KHR_materials_unlit"] != nil { material.lightingModel = .constant }

    let alphaMode = info.jsonString("alphaMode") ?? "OPAQUE"
    let cutoff = Float(info.jsonDouble("alphaCutoff") ?? 0.5)
    var baseFactor = SIMD4<Float>(1, 1, 1, 1)
    var baseTexture: [String: Any]?
    var metallic: Float = 1
    var roughness: Float = 1
    var metallicRoughnessTexture: [String: Any]?
    if let pbr = info.jsonObject("pbrMetallicRoughness") {
      if let f = pbr.jsonFloats("baseColorFactor"), f.count == 4 { baseFactor = SIMD4(f[0], f[1], f[2], f[3]) }
      baseTexture = pbr.jsonObject("baseColorTexture")
      metallic = Float(pbr.jsonDouble("metallicFactor") ?? 1)
      roughness = Float(pbr.jsonDouble("roughnessFactor") ?? 1)
      metallicRoughnessTexture = pbr.jsonObject("metallicRoughnessTexture")
    } else if let sg = extensions.jsonObject("KHR_materials_pbrSpecularGlossiness") {
      // Approximation: diffuse as base colour, a non-metal, roughness from
      // glossiness. The specular-glossiness texture is not used.
      if let f = sg.jsonFloats("diffuseFactor"), f.count == 4 { baseFactor = SIMD4(f[0], f[1], f[2], f[3]) }
      baseTexture = sg.jsonObject("diffuseTexture")
      metallic = 0
      roughness = 1 - Float(sg.jsonDouble("glossinessFactor") ?? 1)
    }

    // Base colour. The factor is baked into the texture (in linear space),
    // and the alpha is fixed up for the alpha mode so opaque models never
    // let the map show through.
    switch alphaMode {
    case "BLEND":
      material.blendMode = .alpha
    case "MASK":
      // Visible texels have alpha 1 after baking; filtered edges are cut at
      // half way.
      material.shaderModifiers = [
        .fragment: "#pragma body\nif (_output.color.a < 0.5) { discard_fragment(); }\n_output.color.a = 1.0;",
      ]
    default:
      break
    }
    if let (image, textureInfo) = texture(baseTexture) {
      let baked = Self.bakeColor(image, factor: baseFactor, alphaMode: alphaMode, cutoff: cutoff)
      bind(baked, info: textureInfo, to: material.diffuse)
    } else {
      var color = baseFactor
      if alphaMode == "OPAQUE" { color.w = 1 }
      if alphaMode == "MASK" { color.w = color.w >= cutoff ? 1 : 0 }
      material.diffuse.contents = Self.linearColor(color)
    }

    // Metalness in blue, roughness in green, both from one texture.
    if let (image, textureInfo) = texture(metallicRoughnessTexture) {
      let baked = Self.bakeData(image, factors: SIMD4(1, roughness, metallic, 1))
      bind(baked, info: textureInfo, to: material.metalness)
      material.metalness.textureComponents = .blue
      bind(baked, info: textureInfo, to: material.roughness)
      material.roughness.textureComponents = .green
    } else {
      material.metalness.contents = NSNumber(value: metallic)
      material.roughness.contents = NSNumber(value: roughness)
    }

    if let normalInfo = info.jsonObject("normalTexture"), let (image, textureInfo) = texture(normalInfo) {
      bind(Self.linearImage(image), info: textureInfo, to: material.normal)
      material.normal.intensity = CGFloat(normalInfo.jsonDouble("scale") ?? 1)
    }
    if let occlusionInfo = info.jsonObject("occlusionTexture"), let (image, textureInfo) = texture(occlusionInfo) {
      bind(Self.linearImage(image), info: textureInfo, to: material.ambientOcclusion)
      material.ambientOcclusion.textureComponents = .red
      material.ambientOcclusion.intensity = CGFloat(occlusionInfo.jsonDouble("strength") ?? 1)
    }

    var emissive = SIMD3<Float>(0, 0, 0)
    if let f = info.jsonFloats("emissiveFactor"), f.count == 3 { emissive = SIMD3(f[0], f[1], f[2]) }
    let strength = extensions.jsonObject("KHR_materials_emissive_strength")?.jsonDouble("emissiveStrength") ?? 1
    if emissive != .zero {
      if let (image, textureInfo) = texture(info.jsonObject("emissiveTexture")) {
        let baked = Self.bakeColor(image, factor: SIMD4(emissive, 1), alphaMode: "OPAQUE", cutoff: 0)
        bind(baked, info: textureInfo, to: material.emission)
      } else {
        material.emission.contents = Self.linearColor(SIMD4(emissive, 1))
      }
      material.emission.intensity = CGFloat(strength)
    }
    return material
  }

  /// The image behind a textureInfo, or nil (with a warning) when it cannot
  /// be used.
  private func texture(_ info: [String: Any]?) -> (CGImage, [String: Any])? {
    guard let info, let textureIndex = info.jsonInt("index") else { return nil }
    guard let texture = textures.gltfElement(at: textureIndex) else {
      warn("texture \(textureIndex) does not exist")
      return nil
    }
    // ImageIO decodes WebP, so EXT_texture_webp sources work as-is.
    let source = texture.jsonObject("extensions")?.jsonObject("EXT_texture_webp")?.jsonInt("source")
      ?? texture.jsonInt("source")
    guard let source else {
      warn("texture \(textureIndex) has no PNG, JPEG or WebP image (KTX2 is not supported)")
      return nil
    }
    guard let image = image(source) else { return nil }
    return (image, info)
  }

  private func bind(_ image: CGImage, info: [String: Any], to property: SCNMaterialProperty) {
    property.contents = image
    let texture = textures.gltfElement(at: info.jsonInt("index") ?? -1) ?? [:]
    let sampler = samplers.gltfElement(at: texture.jsonInt("sampler") ?? -1) ?? [:]
    property.wrapS = Self.wrapMode(sampler.jsonInt("wrapS"))
    property.wrapT = Self.wrapMode(sampler.jsonInt("wrapT"))
    property.magnificationFilter = sampler.jsonInt("magFilter") == 9728 ? .nearest : .linear
    switch sampler.jsonInt("minFilter") {
    case 9728: property.minificationFilter = .nearest; property.mipFilter = .none
    case 9729: property.minificationFilter = .linear; property.mipFilter = .none
    case 9984: property.minificationFilter = .nearest; property.mipFilter = .nearest
    case 9985: property.minificationFilter = .linear; property.mipFilter = .nearest
    case 9986: property.minificationFilter = .nearest; property.mipFilter = .linear
    default: property.minificationFilter = .linear; property.mipFilter = .linear
    }
    property.mappingChannel = info.jsonInt("texCoord") ?? 0

    if let transform = info.jsonObject("extensions")?.jsonObject("KHR_texture_transform") {
      // uv' = T * R * S * uv (KHR_texture_transform). The rotation matrix is
      // the one three.js and the Khronos TextureTransformTest sample agree
      // on; it was checked against that sample's arrows.
      let offset = transform.jsonFloats("offset") ?? [0, 0]
      let scale = transform.jsonFloats("scale") ?? [1, 1]
      let rotation = Float(transform.jsonDouble("rotation") ?? 0)
      let c = cos(rotation), s = sin(rotation)
      let translate = simd_float3x3(columns: (
        SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(offset.count > 0 ? offset[0] : 0, offset.count > 1 ? offset[1] : 0, 1)))
      let rotate = simd_float3x3(columns: (SIMD3(c, -s, 0), SIMD3(s, c, 0), SIMD3(0, 0, 1)))
      let scaling = simd_float3x3(diagonal: SIMD3(scale.count > 0 ? scale[0] : 1, scale.count > 1 ? scale[1] : 1, 1))
      let m = translate * rotate * scaling
      property.contentsTransform = SCNMatrix4(simd_float4x4(columns: (
        SIMD4(m[0][0], m[0][1], 0, 0),
        SIMD4(m[1][0], m[1][1], 0, 0),
        SIMD4(0, 0, 1, 0),
        SIMD4(m[2][0], m[2][1], 0, 1))))
      if let channel = transform.jsonInt("texCoord") { property.mappingChannel = channel }
    }
  }

  private static func wrapMode(_ value: Int?) -> SCNWrapMode {
    switch value {
    case 33071: return .clamp
    case 33648: return .mirror
    default: return .repeat
    }
  }

  // MARK: Images

  private func image(_ index: Int) -> CGImage? {
    if let cached = imageCache[index] { return cached }
    if failedImages.contains(index) { return nil }
    do {
      guard let info = images.gltfElement(at: index) else { throw fail("image \(index) does not exist") }
      let data: Data
      if let view = info.jsonInt("bufferView") {
        let slice = try viewSlice(view)
        data = slice.data.subdata(in: slice.offset..<slice.offset + slice.length)
      } else if let uri = info.jsonString("uri") {
        data = try resource(uri)
      } else {
        throw fail("image \(index) has no data")
      }
      guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(
              source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
      else {
        let type = info.jsonString("mimeType") ?? "unknown type"
        throw fail("image \(index) (\(type)) could not be decoded; use PNG or JPEG")
      }
      imageCache[index] = image
      return image
    } catch {
      warn("\(error.localizedDescription); the texture is skipped")
      failedImages.insert(index)
      return nil
    }
  }

  private static let linearSRGB = CGColorSpace(name: CGColorSpace.linearSRGB) ?? CGColorSpaceCreateDeviceRGB()
  private static let linearGray = CGColorSpace(name: CGColorSpace.linearGray) ?? CGColorSpaceCreateDeviceGray()
  private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

  /// glTF colour factors are linear.
  static func linearColor(_ c: SIMD4<Float>) -> CGColor {
    CGColor(colorSpace: linearSRGB, components: [CGFloat(c.x), CGFloat(c.y), CGFloat(c.z), CGFloat(c.w)])
      ?? CGColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: CGFloat(c.w))
  }

  /// Marks a data texture (normals, occlusion, metal-roughness) as linear so
  /// SceneKit does not sRGB-decode its values.
  private static func linearImage(_ image: CGImage) -> CGImage {
    switch image.colorSpace?.model {
    case .rgb?: return image.copy(colorSpace: linearSRGB) ?? image
    case .monochrome?: return image.copy(colorSpace: linearGray) ?? image
    default: return image
    }
  }

  private static func hasAlpha(_ image: CGImage) -> Bool {
    switch image.alphaInfo {
    case .none, .noneSkipFirst, .noneSkipLast: return false
    default: return true
    }
  }

  /// Draws `image` into RGBA8 premultiplied pixels in `space`, lets `edit`
  /// change them, and returns the result.
  private static func editPixels(
    _ image: CGImage, space: CGColorSpace, edit: (UnsafeMutablePointer<UInt8>, Int) -> Void
  ) -> CGImage? {
    let width = image.width, height = image.height
    guard width > 0, height > 0,
          let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = context.data else { return nil }
    edit(data.bindMemory(to: UInt8.self, capacity: width * height * 4), width * height)
    return context.makeImage()
  }

  /// Multiplies an sRGB colour texture by a linear factor and applies the
  /// alpha mode: OPAQUE drops alpha, MASK makes it 0 or 1 at `cutoff`.
  private static func bakeColor(_ image: CGImage, factor: SIMD4<Float>, alphaMode: String, cutoff: Float) -> CGImage {
    let alpha = hasAlpha(image)
    let needsFactor = factor != SIMD4(repeating: 1)
    let needsAlpha = (alpha && alphaMode != "BLEND") || (alphaMode == "MASK" && factor.w < 1)
    guard needsFactor || needsAlpha else { return image }

    func decode(_ v: Float) -> Float { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    func encode(_ v: Float) -> Float { v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055 }
    var lut = [[UInt8]](repeating: [UInt8](repeating: 0, count: 256), count: 3)
    for c in 0..<3 {
      for v in 0..<256 {
        let scaled = encode(min(1, max(0, decode(Float(v) / 255) * factor[c])))
        lut[c][v] = UInt8(min(255, max(0, scaled * 255 + 0.5)))
      }
    }
    let space = image.colorSpace?.model == .rgb ? image.colorSpace! : sRGB
    return editPixels(image, space: space) { pixels, count in
      for i in 0..<count {
        let p = pixels + i * 4
        let a = Int(p[3])
        var straight = (0..<3).map { c -> Int in
          a == 0 ? 0 : min(255, (Int(p[c]) * 255 + a / 2) / a)
        }
        for c in 0..<3 { straight[c] = Int(lut[c][straight[c]]) }
        var newAlpha = Float(a) / 255 * factor.w
        switch alphaMode {
        case "OPAQUE": newAlpha = 1
        case "MASK": newAlpha = newAlpha >= cutoff ? 1 : 0
        default: break
        }
        let a8 = Int(min(255, max(0, newAlpha * 255 + 0.5)))
        for c in 0..<3 { p[c] = UInt8((straight[c] * a8 + 127) / 255) }
        p[3] = UInt8(a8)
      }
    } ?? image
  }

  /// Multiplies the channels of a linear data texture, then marks it linear.
  private static func bakeData(_ image: CGImage, factors: SIMD4<Float>) -> CGImage {
    guard factors != SIMD4(repeating: 1) else { return linearImage(image) }
    // Draw in the image's own space so the values are not colour-converted.
    let space = image.colorSpace?.model == .rgb ? image.colorSpace! : CGColorSpaceCreateDeviceRGB()
    let baked = editPixels(image, space: space) { pixels, count in
      for i in 0..<count {
        let p = pixels + i * 4
        for c in 0..<3 where factors[c] != 1 {
          p[c] = UInt8(min(255, max(0, Float(p[c]) * factors[c] + 0.5)))
        }
      }
    }
    return linearImage(baked ?? image)
  }

  // MARK: Buffers and accessors

  private func resource(_ uri: String) throws -> Data {
    if uri.hasPrefix("data:") {
      guard let data = Self.decodeDataURI(uri) else { throw fail("has an unreadable data: URI") }
      return data
    }
    guard let url = URL(string: uri, relativeTo: baseURL)
      ?? uri.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed).flatMap({ URL(string: $0, relativeTo: baseURL) })
    else { throw fail("cannot resolve the URI \(uri)") }
    let absolute = url.absoluteURL
    let scheme = absolute.scheme?.lowercased()
    if scheme == "http" || scheme == "https" {
      return try download(absolute, uri: uri)
    }
    // A remote model may only pull in other remote files, never local ones.
    guard absolute.isFileURL, !isRemote else { throw fail("cannot load \(uri); use a relative or http(s) URI") }
    do {
      return try Data(contentsOf: absolute, options: .mappedIfSafe)
    } catch {
      throw fail("could not read \(uri) next to the model; a .gltf needs its .bin and image files beside it (or use .glb)")
    }
  }

  private final class DownloadBox {
    var result: Result<URL, Error>?
  }

  /// Downloads (and caches) a resource through the same cache as models.
  /// Runs on the loader's background queue, so waiting is fine.
  private func download(_ url: URL, uri: String) throws -> Data {
    let semaphore = DispatchSemaphore(value: 0)
    let box = DownloadBox()
    MapModelNodes.resolveLocalURL(uri: url.absoluteString) { result in
      box.result = result
      semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 120) == .success, let result = box.result else {
      throw fail("timed out downloading \(uri)")
    }
    do {
      return try Data(contentsOf: try result.get())
    } catch {
      throw fail("could not download \(uri) (\(error.localizedDescription))")
    }
  }

  private static func decodeDataURI(_ uri: String) -> Data? {
    guard let comma = uri.firstIndex(of: ",") else { return nil }
    let header = uri[..<comma]
    let payload = String(uri[uri.index(after: comma)...])
    if header.hasSuffix(";base64") {
      return Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
    }
    return payload.removingPercentEncoding.map { Data($0.utf8) }
  }

  private func buffer(_ index: Int) throws -> Data {
    if let cached = bufferCache[index] { return cached }
    guard let info = buffers.gltfElement(at: index) else { throw fail("buffer \(index) does not exist") }
    let data: Data
    if let uri = info.jsonString("uri") {
      data = try resource(uri)
    } else if let binaryChunk {
      data = binaryChunk
    } else {
      throw fail("buffer \(index) has no data")
    }
    let length = info.jsonInt("byteLength") ?? data.count
    guard data.count >= length else {
      throw fail("buffer \(index) is \(data.count) bytes but should be \(length)")
    }
    bufferCache[index] = data
    return data
  }

  private func viewSlice(_ index: Int) throws -> (data: Data, offset: Int, length: Int, stride: Int?) {
    guard let view = bufferViews.gltfElement(at: index) else { throw fail("bufferView \(index) does not exist") }
    let extensions = view.jsonObject("extensions") ?? [:]
    if extensions["EXT_meshopt_compression"] != nil || extensions["KHR_meshopt_compression"] != nil {
      throw fail(GLTFLoader.meshoptMessage)
    }
    let data = try buffer(view.jsonInt("buffer") ?? -1)
    let offset = view.jsonInt("byteOffset") ?? 0
    let length = view.jsonInt("byteLength") ?? 0
    guard offset >= 0, length >= 0, offset <= data.count, length <= data.count - offset else {
      throw fail("bufferView \(index) lies outside its buffer")
    }
    let stride = view.jsonInt("byteStride").flatMap { $0 > 0 ? $0 : nil }
    return (data, offset, length, stride)
  }

  struct Layout {
    let data: Data
    let start: Int
    let stride: Int
    let count: Int
    let components: Int
    let componentType: Int
    let componentSize: Int
    let normalized: Bool
  }

  private func layout(
    view: Int, byteOffset: Int, count: Int, components: Int, componentType: Int,
    normalized: Bool, label: String
  ) throws -> Layout {
    guard let size = Self.componentSize(componentType) else {
      throw fail("\(label) has an unknown component type \(componentType)")
    }
    let slice = try viewSlice(view)
    let elementSize = size * components
    let stride = slice.stride ?? elementSize
    let start = slice.offset + byteOffset
    guard byteOffset >= 0, stride <= 1024 else { throw fail("\(label) has a bad offset or stride") }
    if count > 0 {
      let end = start + stride * (count - 1) + elementSize
      guard end <= slice.offset + slice.length else { throw fail("\(label) reads past the end of bufferView \(view)") }
    }
    return Layout(
      data: slice.data, start: start, stride: stride, count: count, components: components,
      componentType: componentType, componentSize: size, normalized: normalized)
  }

  private static func componentSize(_ type: Int) -> Int? {
    switch type {
    case 5120, 5121: return 1
    case 5122, 5123: return 2
    case 5125, 5126: return 4
    default: return nil
    }
  }

  private static func componentCount(_ type: String) -> Int? {
    switch type {
    case "SCALAR": return 1
    case "VEC2": return 2
    case "VEC3": return 3
    case "VEC4", "MAT2": return 4
    case "MAT3": return 9
    case "MAT4": return 16
    default: return nil
    }
  }

  private func floats(_ index: Int) throws -> (values: [Float], components: Int, count: Int) {
    try readAccessor(index, read: Self.readFloats)
  }

  private func uints(_ index: Int) throws -> (values: [UInt32], components: Int, count: Int) {
    try readAccessor(index, read: Self.readUInts)
  }

  private func readAccessor<T: Numeric>(
    _ index: Int, read: (Layout) -> [T]
  ) throws -> (values: [T], components: Int, count: Int) {
    guard let accessor = accessors.gltfElement(at: index) else { throw fail("accessor \(index) does not exist") }
    let label = "accessor \(index)"
    guard let components = Self.componentCount(accessor.jsonString("type") ?? "") else {
      throw fail("\(label) has an unknown type")
    }
    let count = accessor.jsonInt("count") ?? 0
    guard count >= 0, count <= 1 << 26 else { throw fail("\(label) has a bad count") }
    let componentType = accessor.jsonInt("componentType") ?? 0
    let normalized = accessor.jsonBool("normalized") ?? false
    var values: [T]
    if let view = accessor.jsonInt("bufferView") {
      values = read(try layout(
        view: view, byteOffset: accessor.jsonInt("byteOffset") ?? 0, count: count,
        components: components, componentType: componentType, normalized: normalized, label: label))
    } else {
      // No data: all zeros, possibly overridden by sparse values.
      guard Self.componentSize(componentType) != nil else {
        throw fail("\(label) has an unknown component type \(componentType)")
      }
      values = [T](repeating: 0, count: count * components)
    }

    if let sparse = accessor.jsonObject("sparse"), let sparseCount = sparse.jsonInt("count"), sparseCount > 0,
       let indicesInfo = sparse.jsonObject("indices"), let valuesInfo = sparse.jsonObject("values") {
      let targets = Self.readUInts(try layout(
        view: indicesInfo.jsonInt("bufferView") ?? -1, byteOffset: indicesInfo.jsonInt("byteOffset") ?? 0,
        count: sparseCount, components: 1, componentType: indicesInfo.jsonInt("componentType") ?? 0,
        normalized: false, label: "\(label) sparse indices"))
      let replacements = read(try layout(
        view: valuesInfo.jsonInt("bufferView") ?? -1, byteOffset: valuesInfo.jsonInt("byteOffset") ?? 0,
        count: sparseCount, components: components, componentType: componentType,
        normalized: normalized, label: "\(label) sparse values"))
      for (k, target) in targets.enumerated() where Int(target) < count {
        for c in 0..<components {
          values[Int(target) * components + c] = replacements[k * components + c]
        }
      }
    }
    return (values, components, count)
  }

  private static func readFloats(_ layout: Layout) -> [Float] {
    var out = [Float](repeating: 0, count: layout.count * layout.components)
    layout.data.withUnsafeBytes { raw in
      out.withUnsafeMutableBufferPointer { dst in
        var k = 0
        for i in 0..<layout.count {
          var offset = layout.start + i * layout.stride
          for _ in 0..<layout.components {
            let value: Float
            switch layout.componentType {
            case 5126:
              value = raw.loadUnaligned(fromByteOffset: offset, as: Float.self)
            case 5121:
              let v = Float(raw[offset])
              value = layout.normalized ? v / 255 : v
            case 5120:
              let v = Float(Int8(bitPattern: raw[offset]))
              value = layout.normalized ? max(v / 127, -1) : v
            case 5123:
              let v = Float(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
              value = layout.normalized ? v / 65535 : v
            case 5122:
              let v = Float(raw.loadUnaligned(fromByteOffset: offset, as: Int16.self))
              value = layout.normalized ? max(v / 32767, -1) : v
            default:
              let v = Float(raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
              value = layout.normalized ? v / Float(UInt32.max) : v
            }
            dst[k] = value
            k += 1
            offset += layout.componentSize
          }
        }
      }
    }
    return out
  }

  private static func readUInts(_ layout: Layout) -> [UInt32] {
    var out = [UInt32](repeating: 0, count: layout.count * layout.components)
    layout.data.withUnsafeBytes { raw in
      out.withUnsafeMutableBufferPointer { dst in
        var k = 0
        for i in 0..<layout.count {
          var offset = layout.start + i * layout.stride
          for _ in 0..<layout.components {
            switch layout.componentType {
            case 5121, 5120:
              dst[k] = UInt32(raw[offset])
            case 5123, 5122:
              dst[k] = UInt32(raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
            case 5126:
              let v = raw.loadUnaligned(fromByteOffset: offset, as: Float.self)
              dst[k] = v.isFinite && v > 0 ? (v >= Float(UInt32.max) ? UInt32.max : UInt32(v)) : 0
            default:
              dst[k] = raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            }
            k += 1
            offset += layout.componentSize
          }
        }
      }
    }
    return out
  }
}

// MARK: - JSON helpers

private extension Dictionary where Key == String, Value == Any {
  func jsonInt(_ key: String) -> Int? { (self[key] as? NSNumber)?.intValue }
  func jsonDouble(_ key: String) -> Double? { (self[key] as? NSNumber)?.doubleValue }
  func jsonBool(_ key: String) -> Bool? { (self[key] as? NSNumber)?.boolValue }
  func jsonString(_ key: String) -> String? { self[key] as? String }
  func jsonObject(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }
  func jsonObjects(_ key: String) -> [[String: Any]] { (self[key] as? [Any] ?? []).map { $0 as? [String: Any] ?? [:] } }
  func jsonInts(_ key: String) -> [Int] { (self[key] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.intValue } }
  func jsonFloats(_ key: String) -> [Float]? {
    guard let array = self[key] as? [Any] else { return nil }
    return array.map { ($0 as? NSNumber)?.floatValue ?? 0 }
  }
}

private extension Array {
  func gltfElement(at index: Int) -> Element? {
    index >= 0 && index < count ? self[index] : nil
  }
}

private extension Data {
  func gltfU32(at offset: Int) -> UInt32 {
    withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
  }
}
