import CryptoKit
import Foundation
import ModelIO
import SceneKit
import SceneKit.ModelIO
import UIKit

enum MapModelNodes {
  /// Builds the node for a built-in shape, `width` x `height` x `length`
  /// metres, with its base centred on the origin.
  static func shapeNode(for model: MunimModel) -> SCNNode? {
    let geometry: SCNGeometry
    switch model.shape {
    case .none:
      return nil
    case .box:
      geometry = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.04)
    case .sphere:
      geometry = SCNSphere(radius: 0.5)
    case .cylinder:
      geometry = SCNCylinder(radius: 0.5, height: 1)
    case .cone:
      geometry = SCNCone(topRadius: 0, bottomRadius: 0.5, height: 1)
    case .capsule:
      geometry = SCNCapsule(capRadius: 0.5, height: 1)
    case .pyramid:
      geometry = SCNPyramid(width: 1, height: 1, length: 1)
    case .gem:
      geometry = gemGeometry()
    }

    let material = SCNMaterial()
    material.lightingModel = .physicallyBased
    let color = UIColor(mapModelHex: model.color) ?? .systemBlue
    material.diffuse.contents = color
    material.metalness.contents = 0.1
    material.roughness.contents = 0.45
    if model.emissive {
      material.emission.contents = color
    }
    if color.cgColor.alpha < 1 {
      material.transparency = color.cgColor.alpha
      material.blendMode = .alpha
    }
    geometry.materials = [material]

    let shape = SCNNode(geometry: geometry)
    shape.simdScale = SIMD3(
      Float(max(0.01, model.width)),
      Float(max(0.01, model.height)),
      Float(max(0.01, model.length))
    )
    let holder = SCNNode()
    holder.addChildNode(shape)
    return normalized(holder)
  }

  /// A cut gem: a six-sided double pyramid, taller above the girdle than
  /// below, flat shaded. Fits a 1 x 1 x 1 box.
  private static func gemGeometry() -> SCNGeometry {
    let sides = 6
    let girdleY: Float = 0.35
    var ring: [SIMD3<Float>] = []
    for i in 0..<sides {
      let angle = Float(i) / Float(sides) * 2 * .pi
      ring.append(SIMD3(cos(angle) * 0.5, girdleY, sin(angle) * 0.5))
    }
    let top = SIMD3<Float>(0, 1, 0)
    let bottom = SIMD3<Float>(0, 0, 0)
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    func face(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) {
      let normal = simd_normalize(simd_cross(b - a, c - a))
      positions += [a, b, c]
      normals += [normal, normal, normal]
    }
    for i in 0..<sides {
      let a = ring[i]
      let b = ring[(i + 1) % sides]
      face(top, b, a)
      face(bottom, a, b)
    }
    let vertexSource = SCNGeometrySource(vertices: positions.map { SCNVector3($0.x, $0.y, $0.z) })
    let normalSource = SCNGeometrySource(normals: normals.map { SCNVector3($0.x, $0.y, $0.z) })
    let indices = (0..<UInt32(positions.count)).map { $0 }
    let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
    return SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
  }

  /// A text pill on a plane that always faces the camera, 1 unit tall with
  /// its base on the origin.
  static func labelNode(text: String) -> SCNNode {
    let font = UIFont.systemFont(ofSize: 40, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
    let string = text as NSString
    let textSize = string.size(withAttributes: attributes)
    let height: CGFloat = 64
    let size = CGSize(width: ceil(textSize.width) + 40, height: height)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
      let pill = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
      let path = UIBezierPath(roundedRect: pill, cornerRadius: pill.height / 2)
      UIColor(white: 0.08, alpha: 0.85).setFill()
      path.fill()
      UIColor(white: 1, alpha: 0.9).setStroke()
      path.lineWidth = 3
      path.stroke()
      string.draw(
        at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
        withAttributes: attributes)
    }
    let plane = SCNPlane(width: size.width / height, height: 1)
    let material = SCNMaterial()
    material.lightingModel = .constant
    material.diffuse.contents = image
    material.blendMode = .alpha
    material.isDoubleSided = true
    material.readsFromDepthBuffer = false
    material.writesToDepthBuffer = false
    plane.materials = [material]
    let node = SCNNode(geometry: plane)
    node.renderingOrder = 110
    let billboard = SCNBillboardConstraint()
    billboard.freeAxes = .all
    node.constraints = [billboard]
    let holder = SCNNode()
    holder.addChildNode(node)
    return normalized(holder)
  }

  /// Loads a USDZ, USD, SCN, glTF / GLB, OBJ, PLY, STL or ABC file. Remote
  /// files are downloaded once into the caches directory (keeping their
  /// extension).
  static func loadAsset(
    uri: String,
    completion: @escaping (Result<SCNNode, Error>) -> Void
  ) {
    resolveLocalURL(uri: uri) { result in
      switch result {
      case .failure(let error):
        completion(.failure(error))
      case .success(let url):
        DispatchQueue.global(qos: .userInitiated).async {
          completion(Result { try loadScene(at: url, sourceURI: uri) })
        }
      }
    }
  }

  private static func loadScene(at url: URL, sourceURI: String) throws -> SCNNode {
    let scene: SCNScene
    if GLTFLoader.canLoad(url) {
      scene = try GLTFLoader.loadScene(at: url, sourceURI: sourceURI)
    } else if ["obj", "ply", "stl", "abc"].contains(url.pathExtension.lowercased()) {
      let asset = MDLAsset(url: url)
      asset.loadTextures()
      scene = SCNScene(mdlAsset: asset)
    } else {
      scene = try SCNScene(url: url, options: [
        .checkConsistency: false,
        .convertToYUp: true,
      ])
    }
    let holder = SCNNode()
    for child in scene.rootNode.childNodes {
      holder.addChildNode(child)
    }
    guard subtreeBounds(holder) != nil else {
      throw MapModelError.message("\(url.lastPathComponent) has no geometry")
    }
    return normalized(holder)
  }

  static func resolveLocalURL(
    uri: String,
    completion: @escaping (Result<URL, Error>) -> Void
  ) {
    let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("/") {
      completion(.success(URL(fileURLWithPath: trimmed)))
      return
    }
    guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
      completion(.failure(MapModelError.message("Invalid model uri: \(uri)")))
      return
    }
    if scheme == "file" {
      completion(.success(url))
      return
    }
    guard scheme == "http" || scheme == "https" else {
      completion(.failure(MapModelError.message("Unsupported model uri scheme: \(scheme)")))
      return
    }

    let ext = url.pathExtension.isEmpty ? "usdz" : url.pathExtension
    let digest = SHA256.hash(data: Data(trimmed.utf8))
      .map { String(format: "%02x", $0) }.joined()
    let directory = FileManager.default
      .urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("munim-maps", isDirectory: true)
    let destination = directory.appendingPathComponent("\(digest).\(ext)")
    // Metro serves development assets over http; those change on reload,
    // so only cache files that are not from the dev server.
    let isDevServer = url.port == 8081
    if !isDevServer, FileManager.default.fileExists(atPath: destination.path) {
      completion(.success(destination))
      return
    }

    URLSession.shared.downloadTask(with: url) { location, response, error in
      if let error {
        completion(.failure(error))
        return
      }
      if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
        completion(.failure(MapModelError.message("Downloading \(uri) failed with HTTP \(http.statusCode)")))
        return
      }
      guard let location else {
        completion(.failure(MapModelError.message("Downloading \(uri) returned no file")))
        return
      }
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: location, to: destination)
        completion(.success(destination))
      } catch {
        completion(.failure(error))
      }
    }.resume()
  }

  /// Loads a PNG or JPEG for an avatar model.
  static func loadImage(
    uri: String,
    completion: @escaping (Result<UIImage, Error>) -> Void
  ) {
    resolveLocalURL(uri: uri) { result in
      switch result {
      case .failure(let error):
        completion(.failure(error))
      case .success(let url):
        DispatchQueue.global(qos: .userInitiated).async {
          if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
            completion(.success(image))
          } else {
            completion(.failure(MapModelError.message("\(url.lastPathComponent) is not a PNG or JPEG")))
          }
        }
      }
    }
  }

  /// A round picture with an optional ring and badge, on a plane that always
  /// faces the camera. The plane is 1 unit tall with its base on the origin.
  static func avatarNode(image: UIImage, model: MunimModel) -> SCNNode {
    let texture = avatarTexture(image: image, model: model)
    let aspect = texture.size.width / max(1, texture.size.height)
    let plane = SCNPlane(width: aspect, height: 1)
    let material = SCNMaterial()
    material.lightingModel = .constant
    material.diffuse.contents = texture
    material.blendMode = .alpha
    material.isDoubleSided = true
    // Drawn last and over everything, like a marker.
    material.readsFromDepthBuffer = false
    material.writesToDepthBuffer = false
    plane.materials = [material]

    let node = SCNNode(geometry: plane)
    node.renderingOrder = 100
    node.castsShadow = false
    let billboard = SCNBillboardConstraint()
    billboard.freeAxes = .all
    node.constraints = [billboard]
    let holder = SCNNode()
    holder.addChildNode(node)
    return normalized(holder)
  }

  private static func avatarTexture(image: UIImage, model: MunimModel) -> UIImage {
    let diameter: CGFloat = 192
    // Points on screen to pixels in the texture.
    let pixelsPerPoint = diameter / CGFloat(model.screenSize > 0 ? model.screenSize : 44)
    let badge = model.imageBadge
    let badgeHeight: CGFloat = badge.isEmpty ? 0 : 64
    let font = UIFont.systemFont(ofSize: 40, weight: .heavy)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
    let textSize = (badge as NSString).size(withAttributes: attributes)
    let pillWidth = badge.isEmpty ? 0 : textSize.width + 36
    // Wider than the picture when the badge needs it ("Floor 103").
    let size = CGSize(width: max(diameter, pillWidth + 6), height: diameter + badgeHeight * 0.6)
    let ringColor = UIColor(mapModelHex: model.imageBorderColor)
    let ring = ringColor == nil ? 0 : CGFloat(max(0, model.imageBorderWidth)) * pixelsPerPoint

    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
      let cg = context.cgContext
      let circle = CGRect(x: (size.width - diameter) / 2, y: 0, width: diameter, height: diameter)
      if let ringColor, ring > 0 {
        ringColor.setFill()
        cg.fillEllipse(in: circle)
      }
      let photo = circle.insetBy(dx: ring, dy: ring)
      cg.saveGState()
      cg.addEllipse(in: photo)
      cg.clip()
      UIColor(white: 0.9, alpha: 1).setFill()
      cg.fill(photo)
      // Aspect-fill the picture into the circle.
      let scale = max(photo.width / max(1, image.size.width), photo.height / max(1, image.size.height))
      let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
      image.draw(in: CGRect(
        x: photo.midX - drawn.width / 2, y: photo.midY - drawn.height / 2,
        width: drawn.width, height: drawn.height))
      cg.restoreGState()

      guard !badge.isEmpty else { return }
      let text = badge as NSString
      let pill = CGRect(
        x: (size.width - pillWidth) / 2, y: size.height - badgeHeight,
        width: pillWidth, height: badgeHeight - 6)
      // White text needs a dark pill: light rings (white, pale grey) get a
      // near-black pill outlined in the ring colour instead.
      let pillColor = ringColor.flatMap { $0.mapModelLuminance < 0.6 ? $0 : nil }
        ?? UIColor(white: 0.11, alpha: 1)
      let pillPath = UIBezierPath(roundedRect: pill, cornerRadius: pill.height / 2)
      pillColor.setFill()
      pillPath.fill()
      (ringColor ?? .white).setStroke()
      pillPath.lineWidth = 5
      pillPath.stroke()
      text.draw(
        at: CGPoint(x: pill.midX - textSize.width / 2, y: pill.midY - textSize.height / 2),
        withAttributes: attributes)
    }
  }

  /// A unit cylinder (radius 0.5, height 1, centred) in a flat colour.
  static func stemNode(color: UIColor) -> SCNNode {
    let cylinder = SCNCylinder(radius: 0.5, height: 1)
    cylinder.radialSegmentCount = 8
    let material = SCNMaterial()
    material.lightingModel = .constant
    material.diffuse.contents = color
    cylinder.materials = [material]
    let node = SCNNode(geometry: cylinder)
    node.castsShadow = false
    return node
  }

  /// Wraps `node` so its bounding box sits with the base centred on the
  /// origin, which is where a model meets the map.
  static func normalized(_ node: SCNNode) -> SCNNode {
    let wrapper = SCNNode()
    wrapper.addChildNode(node)
    if let (minimum, maximum) = subtreeBounds(node) {
      let center = (minimum + maximum) / 2
      node.simdPosition -= SIMD3(center.x, minimum.y, center.z)
    }
    return wrapper
  }

  /// Bounds of every geometry under `node`, in `node`'s parent space.
  static func subtreeBounds(_ node: SCNNode) -> (SIMD3<Float>, SIMD3<Float>)? {
    var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
    var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
    var found = false
    let reference = node.parent
    node.enumerateHierarchy { child, _ in
      guard let geometry = child.geometry else { return }
      let (low, high) = geometry.boundingBox
      for i in 0..<8 {
        let corner = SIMD3<Float>(
          Float(i & 1 == 0 ? low.x : high.x),
          Float(i & 2 == 0 ? low.y : high.y),
          Float(i & 4 == 0 ? low.z : high.z)
        )
        let converted = reference.map { child.simdConvertPosition(corner, to: $0) }
          ?? child.simdConvertPosition(corner, to: nil)
        minimum = simd_min(minimum, converted)
        maximum = simd_max(maximum, converted)
        found = true
      }
    }
    return found ? (minimum, maximum) : nil
  }

  /// Turns embedded animations on or off and makes them loop.
  static func setAnimationsPlaying(_ playing: Bool, in node: SCNNode) {
    node.enumerateHierarchy { child, _ in
      for key in child.animationKeys {
        guard let player = child.animationPlayer(forKey: key) else { continue }
        player.animation.repeatCount = .greatestFiniteMagnitude
        if playing { player.play() } else { player.stop() }
      }
    }
  }

  static func hasAnimations(_ node: SCNNode) -> Bool {
    var found = false
    node.enumerateHierarchy { child, stop in
      if !child.animationKeys.isEmpty {
        found = true
        stop.pointee = true
      }
    }
    return found
  }

  /// A soft round shadow, `diameter` metres across, lying on the ground.
  // MARK: Effects

  /// Particle systems for an effect, in the model's own units (base at the
  /// origin, y up), so they scale and turn with the model.
  static func effectNode(_ effect: MunimEffect, height: Float, width: Float, origins: [SIMD3<Float>] = []) -> SCNNode {
    let holder = EffectNode()
    switch effect {
    case .none:
      break
    case .exhaust:
      // A methane engine cluster like Starship's: a long, clean flame,
      // white-hot at the nozzles and yellow-orange further out, with pinkish
      // shock diamonds just below the engines and only a faint trail.
      let h = CGFloat(height)
      // The engine skirt, not the fins or flaps: rockets are about 8% as
      // wide as they are tall.
      let w = min(CGFloat(width), h * 0.08)
      let plumeLength = h * 0.45
      // Main flame: about as wide as the engine skirt, barely spreading.
      let flame = particles(
        birthRate: 1600, life: 0.3, lifeVariation: 0.04, size: w * 0.8, growth: 1.3,
        speed: plumeLength / 0.3, spread: 1.0, blend: .alpha,
        colors: [(0, UIColor(red: 1, green: 0.97, blue: 0.9, alpha: 1)),
                 (0.25, UIColor(red: 1, green: 0.88, blue: 0.5, alpha: 0.95)),
                 (0.6, UIColor(red: 1, green: 0.6, blue: 0.22, alpha: 0.75)),
                 (1, UIColor(red: 0.95, green: 0.42, blue: 0.15, alpha: 0))])
      flame.emittingDirection = SCNVector3(0, -1, 0)
      flame.emitterShape = SCNSphere(radius: w * 0.3)
      flame.sortingMode = .projectedDepth
      holder.add(flame, at: SIMD3(0, Float(h) * 0.005, 0), stopsAtGround: true)
      // A brighter core so the flame glows on any map.
      let core = particles(
        birthRate: 800, life: 0.18, lifeVariation: 0.03, size: w * 0.5, growth: 0.8,
        speed: plumeLength / 0.3, spread: 0.6, blend: .additive,
        colors: [(0, UIColor(red: 1, green: 0.95, blue: 0.85, alpha: 0.9)),
                 (1, UIColor(red: 1, green: 0.7, blue: 0.4, alpha: 0))])
      core.emittingDirection = SCNVector3(0, -1, 0)
      core.emitterShape = SCNSphere(radius: w * 0.18)
      holder.add(core, at: SIMD3(0, Float(h) * 0.005, 0), stopsAtGround: true)
      // Shock diamonds.
      for i in 0..<4 {
        let depth = Float(w) * (0.55 + Float(i) * 0.75)
        let diamond = SCNNode(geometry: SCNSphere(radius: 0.5))
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor(red: 1, green: 0.78, blue: 0.86, alpha: 1)
        material.blendMode = .add
        material.transparency = CGFloat(0.55 - Double(i) * 0.1)
        material.writesToDepthBuffer = false
        diamond.geometry?.firstMaterial = material
        let size = Float(w) * (0.32 - Float(i) * 0.04)
        diamond.simdScale = SIMD3(size, size * 1.6, size)
        diamond.simdPosition = SIMD3(0, -depth, 0)
        diamond.castsShadow = false
        holder.addGlow(diamond, depth: depth)
      }
      // A faint condensation trail behind the flame.
      let trail = particles(
        birthRate: 40, life: 1.4, lifeVariation: 0.3, size: w * 0.5, growth: 2.4,
        speed: h * 0.35, spread: 3, blend: .alpha,
        colors: [(0, UIColor(white: 0.97, alpha: 0)),
                 (0.2, UIColor(white: 0.95, alpha: 0.16)),
                 (1, UIColor(white: 0.9, alpha: 0))])
      trail.emittingDirection = SCNVector3(0, -1, 0)
      trail.emitterShape = SCNSphere(radius: w * 0.25)
      holder.add(trail, at: SIMD3(0, -Float(plumeLength) * 0.9, 0), stopsAtGround: true)
    case .contrail:
      // One trail per engine. Particles are thrown backwards at the model's
      // own speed (see `EffectNode.speed`), so they hang in the sky.
      let w = CGFloat(width)
      let engines = origins.isEmpty
        ? [SIMD3(-Float(w) * 0.17, height * 0.3, 0), SIMD3(Float(w) * 0.17, height * 0.3, 0)]
        : origins
      for origin in engines {
        let trail = particles(
          birthRate: 120, life: 7, lifeVariation: 0.5, size: w * 0.06, growth: 5,
          speed: 0, spread: 0.4, blend: .alpha,
          colors: [(0, UIColor(white: 1, alpha: 0)),
                   (0.03, UIColor(white: 1, alpha: 0.85)),
                   (0.5, UIColor(white: 0.98, alpha: 0.45)),
                   (1, UIColor(white: 0.97, alpha: 0))])
        trail.emittingDirection = SCNVector3(0, 0, 1)
        trail.emitterShape = SCNSphere(radius: w * 0.01)
        holder.add(trail, at: origin, followsMotion: true)
      }
    case .smoke:
      // A launch-pad cloud: steam and dust that boils up low and then rolls
      // out sideways across the ground, light grey with a sandy tint.
      let h = CGFloat(height)
      let w = CGFloat(width)
      let billow = particles(
        birthRate: 14, life: 4.5, lifeVariation: 1.2, size: w * 0.09, growth: 2.2,
        speed: h * 0.22, spread: 40, blend: .alpha,
        colors: [(0, UIColor(white: 0.96, alpha: 0)),
                 (0.12, UIColor(white: 0.93, alpha: 0.65)),
                 (0.6, UIColor(red: 0.86, green: 0.85, blue: 0.83, alpha: 0.4)),
                 (1, UIColor(white: 0.85, alpha: 0))])
      billow.emittingDirection = SCNVector3(0, 1, 0)
      billow.emitterShape = SCNBox(width: w * 0.12, height: h * 0.05, length: w * 0.12, chamferRadius: 0)
      billow.acceleration = SCNVector3(0, Float(h) * 0.015, 0)
      billow.dampingFactor = 0.3
      holder.add(billow, at: SIMD3(0, Float(h) * 0.08, 0))
      // Rolling out along the ground, faster and lower.
      let roll = particles(
        birthRate: 16, life: 3.5, lifeVariation: 1, size: w * 0.06, growth: 2.4,
        speed: w * 0.42, spread: 90, blend: .alpha,
        colors: [(0, UIColor(white: 0.95, alpha: 0)),
                 (0.1, UIColor(red: 0.88, green: 0.86, blue: 0.83, alpha: 0.6)),
                 (1, UIColor(white: 0.86, alpha: 0))])
      roll.emittingDirection = SCNVector3(0, 0.05, 0)
      roll.emitterShape = SCNSphere(radius: w * 0.04)
      roll.dampingFactor = 0.9
      holder.add(roll, at: SIMD3(0, Float(h) * 0.04, 0))
    }
    return holder
  }

  static func setEffectIntensity(_ intensity: Float, in node: SCNNode) {
    (node as? EffectNode)?.intensity = max(0, min(1, intensity))
  }

  /// Tells an effect how fast the model moves, in its own units per second.
  static func setEffectSpeed(_ speed: Float, in node: SCNNode) {
    (node as? EffectNode)?.speed = speed
  }

  /// Tells an effect how high above the ground the model is, in the model's
  /// own units, so plumes stop at the ground.
  static func setEffectGroundDistance(_ distance: Float, in node: SCNNode) {
    (node as? EffectNode)?.groundDistance = distance
  }

  private static func particles(
    birthRate: CGFloat, life: CGFloat, lifeVariation: CGFloat, size: CGFloat, growth: CGFloat,
    speed: CGFloat, spread: CGFloat, blend: SCNParticleBlendMode,
    colors: [(Double, UIColor)]
  ) -> SCNParticleSystem {
    let system = SCNParticleSystem()
    system.particleImage = softParticle
    system.birthRate = birthRate
    system.particleLifeSpan = life
    system.particleLifeSpanVariation = lifeVariation
    system.particleSize = size
    system.particleSizeVariation = size * 0.25
    system.particleVelocity = speed
    system.particleVelocityVariation = speed * 0.2
    system.spreadingAngle = spread
    system.particleAngleVariation = 180
    system.particleAngularVelocityVariation = 40
    system.blendMode = blend
    system.isLightingEnabled = false
    system.isLocal = true
    system.sortingMode = blend == .alpha ? .distance : .none
    system.loops = true

    let sizeAnimation = CAKeyframeAnimation()
    sizeAnimation.values = [1, growth]
    sizeAnimation.keyTimes = [0, 1]
    system.propertyControllers = [
      .size: SCNParticlePropertyController(animation: sizeAnimation),
      .color: SCNParticlePropertyController(animation: {
        let animation = CAKeyframeAnimation()
        animation.values = colors.map(\.1)
        animation.keyTimes = colors.map { NSNumber(value: $0.0) }
        return animation
      }()),
    ]
    return system
  }

  /// A soft round puff, white so the colour animation tints it.
  private static let softParticle: UIImage = {
    let size = CGSize(width: 64, height: 64)
    return UIGraphicsImageRenderer(size: size).image { context in
      let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0.55).cgColor,
                    UIColor.white.withAlphaComponent(0).cgColor] as CFArray
      guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                      locations: [0, 0.45, 1]) else { return }
      let center = CGPoint(x: 32, y: 32)
      context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                                           endCenter: center, endRadius: 32, options: [])
    }
  }()

  static func groundShadowNode(diameter: Float) -> SCNNode {
    let plane = SCNPlane(width: 1, height: 1)
    let material = SCNMaterial()
    material.lightingModel = .constant
    material.diffuse.contents = shadowImage
    material.blendMode = .alpha
    material.writesToDepthBuffer = false
    material.isDoubleSided = true
    plane.materials = [material]
    let node = SCNNode(geometry: plane)
    node.eulerAngles.x = -.pi / 2
    node.simdScale = SIMD3(diameter, diameter, 1)
    node.simdPosition.y = 0.05
    node.renderingOrder = -10
    node.castsShadow = false
    return node
  }

  private static let shadowImage: UIImage = {
    let size = CGSize(width: 128, height: 128)
    return UIGraphicsImageRenderer(size: size).image { context in
      let colors = [
        UIColor(white: 0, alpha: 0.38).cgColor,
        UIColor(white: 0, alpha: 0).cgColor,
      ] as CFArray
      guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])
      else { return }
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      context.cgContext.drawRadialGradient(
        gradient, startCenter: center, startRadius: 0,
        endCenter: center, endRadius: size.width / 2, options: [])
    }
  }()

  /// A simple sky-over-ground image used as image-based lighting, so
  /// physically based USDZ materials are not black.
  static let environmentImage: UIImage = {
    let size = CGSize(width: 64, height: 32)
    return UIGraphicsImageRenderer(size: size).image { context in
      let colors = [
        UIColor(red: 0.78, green: 0.86, blue: 1, alpha: 1).cgColor,
        UIColor(white: 0.95, alpha: 1).cgColor,
        UIColor(white: 0.45, alpha: 1).cgColor,
      ] as CFArray
      guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])
      else { return }
      context.cgContext.drawLinearGradient(
        gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
    }
  }()
}

enum MapModelError: LocalizedError {
  case message(String)

  var errorDescription: String? {
    switch self {
    case .message(let message): return message
    }
  }
}

extension UIColor {
  /// Relative luminance, 0 (black) to 1 (white).
  var mapModelLuminance: CGFloat {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0.5 }
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
  }

  /// Parses `#RGB`, `#RRGGBB` or `#RRGGBBAA`.
  convenience init?(mapModelHex hex: String) {
    var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("#") { value.removeFirst() }
    if value.count == 3 {
      value = value.map { "\($0)\($0)" }.joined()
    }
    guard value.count == 6 || value.count == 8, let number = UInt64(value, radix: 16)
    else { return nil }
    let hasAlpha = value.count == 8
    let r = CGFloat((number >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
    let g = CGFloat((number >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
    let b = CGFloat((number >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
    let a = hasAlpha ? CGFloat(number & 0xFF) / 255 : 1
    self.init(red: r, green: g, blue: b, alpha: a)
  }
}

/// Holds an effect's particle systems and their full birth rates, so the
/// effect can be throttled.
final class EffectNode: SCNNode {
  private struct Emitter {
    let system: SCNParticleSystem
    let birthRate: CGFloat
    let life: CGFloat
    let lifeVariation: CGFloat
    /// Height of the emitter above the model's base, in the model's units.
    let height: Float
    /// Plumes pointing down stop at the ground instead of going through it.
    let stopsAtGround: Bool
  }

  private var emitters: [Emitter] = []

  var intensity: Float = 1 {
    didSet { if intensity != oldValue { apply() } }
  }

  /// How far the model's base is above the ground, in the model's own units.
  var groundDistance: Float = .greatestFiniteMagnitude {
    didSet { if abs(groundDistance - oldValue) > 0.01 { apply() } }
  }

  private var glows: [(node: SCNNode, depth: Float)] = []

  /// A glowing shape `depth` below the base, hidden once it would be underground.
  func addGlow(_ node: SCNNode, depth: Float) {
    addChildNode(node)
    glows.append((node, depth))
  }

  private var motionTrails: [SCNParticleSystem] = []

  /// How fast the model moves, in its own units per second: trails that
  /// follow motion are thrown backwards this fast, so they stay put.
  var speed: Float = 0 {
    didSet {
      guard abs(speed - oldValue) > 0.01 else { return }
      for trail in motionTrails {
        trail.particleVelocity = CGFloat(speed)
        trail.particleVelocityVariation = 0
      }
    }
  }

  func add(_ system: SCNParticleSystem, at position: SIMD3<Float>, followsMotion: Bool) {
    add(system, at: position)
    if followsMotion { motionTrails.append(system) }
  }

  func add(_ system: SCNParticleSystem, at position: SIMD3<Float>, stopsAtGround: Bool = false) {
    let emitter = SCNNode()
    emitter.simdPosition = position
    emitter.addParticleSystem(system)
    addChildNode(emitter)
    emitters.append(Emitter(
      system: system, birthRate: system.birthRate, life: system.particleLifeSpan,
      lifeVariation: system.particleLifeSpanVariation, height: position.y, stopsAtGround: stopsAtGround))
  }

  private func apply() {
    for glow in glows {
      glow.node.isHidden = intensity < 0.3 || glow.depth > groundDistance
      glow.node.opacity = CGFloat(intensity)
    }
    for emitter in emitters {
      var rate = emitter.birthRate * CGFloat(intensity)
      if emitter.stopsAtGround {
        // Room between the emitter and the ground; particles die before
        // they would reach it (the smoke on the pad shows the exhaust
        // spreading out instead).
        let room = CGFloat(groundDistance + emitter.height)
        let fastest = emitter.system.particleVelocity + emitter.system.particleVelocityVariation
        if room <= 0.5 || fastest <= 0 {
          rate = 0
        } else {
          let scale = min(1, room / (fastest * (emitter.life + emitter.lifeVariation)))
          emitter.system.particleLifeSpan = emitter.life * scale
          emitter.system.particleLifeSpanVariation = emitter.lifeVariation * scale
        }
      }
      emitter.system.birthRate = rate
    }
  }
}
