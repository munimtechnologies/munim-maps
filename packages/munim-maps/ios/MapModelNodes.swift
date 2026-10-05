import CryptoKit
import Foundation
import ModelIO
import SceneKit
import SceneKit.ModelIO
import UIKit

enum MapModelNodes {
  /// Builds the node for a built-in shape, `width` x `height` x `length`
  /// metres, with its base centred on the origin.
  static func shapeNode(for model: NativeMapModel) -> SCNNode? {
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

  /// Loads a USDZ, USD, SCN or OBJ file. Remote files are downloaded once
  /// into the caches directory.
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
          completion(Result { try loadScene(at: url) })
        }
      }
    }
  }

  private static func loadScene(at url: URL) throws -> SCNNode {
    let scene: SCNScene
    if url.pathExtension.lowercased() == "obj" {
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

  private static func resolveLocalURL(
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
