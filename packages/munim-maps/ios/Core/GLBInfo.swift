import Foundation
import simd

/// What the native renderer needs from a glTF file: its height (for
/// `screenSize`) and the names of its `paint*` materials (for `tint`).
struct GLBInfo {
  var height: Double
  var paintMaterials: [String]
  var hasAnimations = false

  /// Reads the model (downloading it into munim-maps' cache if remote):
  /// its info and the local file.
  static func load(uri: String, completion: @escaping (GLBInfo?, URL?) -> Void) {
    MapModelNodes.resolveLocalURL(uri: uri) { result in
      DispatchQueue.global(qos: .utility).async {
        var info: GLBInfo?
        var file: URL?
        if case .success(let url) = result, let data = try? Data(contentsOf: url) {
          info = parse(data)
          file = url
        }
        DispatchQueue.main.async { completion(info, file) }
      }
    }
  }

  /// Reads the JSON chunk of a GLB (or a .gltf file).
  static func parse(_ data: Data) -> GLBInfo? {
    var jsonData = data
    if data.count >= 20, data.prefix(4) == Data("glTF".utf8) {
      let length = data.subdata(in: 12..<16).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
      let end = 20 + Int(length)
      guard end <= data.count else { return nil }
      jsonData = data.subdata(in: 20..<end)
    }
    guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return nil }
    let accessors = json["accessors"] as? [[String: Any]] ?? []
    let meshes = json["meshes"] as? [[String: Any]] ?? []
    let nodes = json["nodes"] as? [[String: Any]] ?? []
    let materials = (json["materials"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }

    func bounds(ofMesh index: Int) -> [SIMD3<Double>] {
      guard index < meshes.count else { return [] }
      var corners: [SIMD3<Double>] = []
      for primitive in meshes[index]["primitives"] as? [[String: Any]] ?? [] {
        guard let attributes = primitive["attributes"] as? [String: Any],
              let position = attributes["POSITION"] as? Int, position < accessors.count,
              let lo = accessors[position]["min"] as? [Double], let hi = accessors[position]["max"] as? [Double],
              lo.count == 3, hi.count == 3 else { continue }
        for x in [lo[0], hi[0]] { for y in [lo[1], hi[1]] { for z in [lo[2], hi[2]] { corners.append(SIMD3(x, y, z)) } } }
      }
      return corners
    }

    func transform(_ node: [String: Any]) -> simd_double4x4 {
      if let m = node["matrix"] as? [Double], m.count == 16 {
        return simd_double4x4(columns: (
          SIMD4(m[0], m[1], m[2], m[3]), SIMD4(m[4], m[5], m[6], m[7]),
          SIMD4(m[8], m[9], m[10], m[11]), SIMD4(m[12], m[13], m[14], m[15])))
      }
      var result = matrix_identity_double4x4
      if let s = node["scale"] as? [Double], s.count == 3 {
        result = simd_double4x4(diagonal: SIMD4(s[0], s[1], s[2], 1))
      }
      if let r = node["rotation"] as? [Double], r.count == 4 {
        result = simd_double4x4(simd_quatd(ix: r[0], iy: r[1], iz: r[2], r: r[3])) * result
      }
      if let t = node["translation"] as? [Double], t.count == 3 {
        var translation = matrix_identity_double4x4
        translation.columns.3 = SIMD4(t[0], t[1], t[2], 1)
        result = translation * result
      }
      return result
    }

    var minY = Double.infinity
    var maxY = -Double.infinity
    func visit(_ index: Int, _ parent: simd_double4x4, depth: Int) {
      guard index < nodes.count, depth < 64 else { return }
      let node = nodes[index]
      let world = parent * transform(node)
      if let mesh = node["mesh"] as? Int {
        for corner in bounds(ofMesh: mesh) {
          let p = world * SIMD4(corner, 1)
          minY = min(minY, p.y)
          maxY = max(maxY, p.y)
        }
      }
      for child in node["children"] as? [Int] ?? [] { visit(child, world, depth: depth + 1) }
    }
    let scenes = json["scenes"] as? [[String: Any]] ?? []
    let sceneIndex = json["scene"] as? Int ?? 0
    let roots = sceneIndex < scenes.count ? scenes[sceneIndex]["nodes"] as? [Int] ?? [] : Array(0..<nodes.count)
    for root in roots { visit(root, matrix_identity_double4x4, depth: 0) }
    if !minY.isFinite {
      // No scene graph: the meshes as they are.
      for mesh in meshes.indices {
        for corner in bounds(ofMesh: mesh) {
          minY = min(minY, corner.y)
          maxY = max(maxY, corner.y)
        }
      }
    }
    let height = maxY > minY ? maxY - minY : 0
    let paint = materials.filter { $0.lowercased().hasPrefix("paint") }
    let animated = !((json["animations"] as? [Any]) ?? []).isEmpty
    return GLBInfo(height: height, paintMaterials: paint, hasAnimations: animated)
  }
}

extension GLBInfo {
  /// A copy of a GLB file whose `paint*` materials are `rgba` (sRGB, 0...1)
  /// instead of their own colour and texture: `tint` for renderers that
  /// take a model file and nothing else (Google's 3D map). Nil when the
  /// file is not a GLB or has no `paint*` material.
  static func tinted(_ data: Data, rgba: [Double]) -> Data? {
    guard data.count >= 20, data.prefix(4) == Data("glTF".utf8), rgba.count == 4 else { return nil }
    func uint32(_ at: Int) -> Int {
      Int(data.subdata(in: at..<(at + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
    }
    let jsonLength = uint32(12)
    guard uint32(16) == 0x4E4F_534A, 20 + jsonLength <= data.count,
          var json = try? JSONSerialization.jsonObject(with: data.subdata(in: 20..<(20 + jsonLength))) as? [String: Any],
          var materials = json["materials"] as? [[String: Any]]
    else { return nil }
    // glTF colours are linear.
    func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    let factor = [linear(rgba[0]), linear(rgba[1]), linear(rgba[2]), rgba[3]]
    var changed = false
    for i in materials.indices {
      guard let name = materials[i]["name"] as? String, name.lowercased().hasPrefix("paint") else { continue }
      var pbr = materials[i]["pbrMetallicRoughness"] as? [String: Any] ?? [:]
      pbr["baseColorFactor"] = factor
      pbr.removeValue(forKey: "baseColorTexture")
      materials[i]["pbrMetallicRoughness"] = pbr
      changed = true
    }
    guard changed else { return nil }
    json["materials"] = materials
    guard var chunk = try? JSONSerialization.data(withJSONObject: json) else { return nil }
    while chunk.count % 4 != 0 { chunk.append(0x20) }
    let rest = data.subdata(in: (20 + jsonLength)..<data.count)
    func le(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) } }
    var out = Data()
    out.append(data.prefix(8))  // magic and version
    out.append(le(12 + 8 + chunk.count + rest.count))
    out.append(le(chunk.count))
    out.append(le(0x4E4F_534A))
    out.append(chunk)
    out.append(rest)
    return out
  }
}
