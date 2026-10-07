#if canImport(MapboxMaps)
@_spi(Experimental) import MapboxMaps
import MapKit
import UIKit
import simd

/// munim-maps' models drawn by Mapbox itself (`mapbox.modelRendering`):
/// glTF / GLB models become entries of a Mapbox `model` source drawn by
/// `model` layers, so Mapbox lights, shadows and hides them behind its 3D
/// buildings and terrain. Position, altitude (ground or sea level),
/// heading, spin, `motion`, `scale`, `screenSize` and `tint` (a colour
/// override on the model's `paint*` materials) are applied; everything the
/// model layer cannot draw (avatars, labels, stems, effects, occluders,
/// USDZ and built-in shapes, plus zones and paths) stays on munim-maps' 3D
/// layer.
///
/// - `auto` (default): models that are only a glTF body are native.
/// - `native`: every glTF model is native; its label, stem and effects stay
///   on the 3D layer.
/// - `overlay`: everything on the 3D layer.
final class MapboxNativeModels {
  static let sourceId = "munim-native-models"
  static let groundLayerId = "munim-native-models"
  static let seaLayerId = "munim-native-models-sea"

  weak var engine: MapboxMapEngine?
  private var all: [MunimModel] = []
  private(set) var native: [MunimModel] = []
  private(set) var overlay: [MunimModel] = []
  private var infos: [String: MapboxGLBInfo] = [:]
  private var loading = Set<String>()
  private var link: CADisplayLink?
  private var installed = false
  private var lastJSON = ""

  init(engine: MapboxMapEngine) { self.engine = engine }

  var mode: String {
    let value = engine?.mapboxOptions["modelRendering"] as? String
    return value == "native" || value == "overlay" ? value! : "auto"
  }

  var nativeIds: Set<String> { Set(native.map(\.id)) }

  static func isGLTF(_ uri: String) -> Bool {
    let path = (URL(string: uri)?.path ?? uri).lowercased()
    return path.hasSuffix(".glb") || path.hasSuffix(".gltf")
  }

  /// Splits the models; returns the ones the 3D layer draws.
  func setModels(_ models: [MunimModel]) -> [MunimModel] {
    all = models
    split()
    update()
    return overlay
  }

  /// `modelRendering` changed: re-split and hand the 3D layer its share.
  func modeChanged() {
    let before = nativeIds
    split()
    if before != nativeIds || native.isEmpty != before.isEmpty {
      engine?.modelLayer.models = overlay
    }
    update()
  }

  private func split() {
    let mode = self.mode
    native = []
    overlay = []
    for model in all {
      guard mode != "overlay", model.visible, Self.isGLTF(model.uri) else {
        overlay.append(model)
        continue
      }
      let extras = !model.label.isEmpty || model.stem || model.effect != .none || model.occluder
      if mode == "auto" {
        // The model layer does not play glTF animations: animated files stay on the 3D layer.
        let animated = model.playAnimations && infos[model.uri]?.hasAnimations == true
        if extras || model.liftPoints != 0 || animated {
          overlay.append(model)
        } else {
          native.append(model)
        }
      } else {
        native.append(model)
        if extras {
          // The 3D layer keeps the label, stem and effects without the body.
          var rest = model
          rest.uri = ""
          rest.shape = .none
          overlay.append(rest)
        }
      }
    }
    for model in native where infos[model.uri] == nil { loadInfo(model.uri) }
    updateClock()
  }

  /// Downloaded models: munim-maps' own disk cache (Caches/munim-maps), so
  /// remote models (`munim-maps-vehicles`) work offline after the first load.
  private var files: [String: String] = [:]

  /// The URI Mapbox reads: the cached file once there is one.
  private func local(_ uri: String) -> String { files[uri] ?? uri }

  private func loadInfo(_ uri: String) {
    guard !loading.contains(uri) else { return }
    loading.insert(uri)
    MapboxGLBInfo.load(uri: uri) { [weak self] info, file in
      guard let self else { return }
      self.loading.remove(uri)
      if let file, uri.hasPrefix("http") { self.files[uri] = file.absoluteString }
      if let info { self.infos[uri] = info }
      // An animated file moves its models back to the 3D layer.
      if info?.hasAnimations == true { self.modeChanged() } else { self.update() }
    }
  }

  /// `getNativeModels`: who draws what, and the model source as Mapbox has it.
  func describe() -> [String: Any] {
    var json: [String: Any] = [
      "mode": mode, "native": native.map(\.id), "overlay": overlay.map(\.id), "installed": installed,
      "heights": infos.mapValues { $0.height },
      "uris": Dictionary(all.map { ($0.id, $0.uri) }, uniquingKeysWith: { a, _ in a }),
      "positions": Dictionary(native.map { model -> (String, [Double]) in
        let pose = model.pose(at: Date().timeIntervalSince1970)
        return (model.id, [pose.latitude, pose.longitude, pose.altitude, pose.heading])
      }, uniquingKeysWith: { a, _ in a }),
    ]
    if let map = engine?.mapboxMap, map.sourceExists(withId: Self.sourceId) {
      json["source"] = (try? map.sourceProperties(for: Self.sourceId)) ?? NSNull()
      json["layers"] = [Self.groundLayerId, Self.seaLayerId].filter { map.layerExists(withId: $0) }
    }
    return json
  }

  // MARK: Drawing
  //
  // Three paths, because Mapbox reloads a `model` source's models whenever
  // its `models` change, and a GeoJSON source updated every frame never
  // settles long enough to draw:
  // - Still models are entries of a `model` source; their `tint` overrides
  //   only the `paint*` materials.
  // - Screen-sized models (`screenSize`, no motion) are GeoJSON points drawn
  //   by `model` layers whose `model-id` names a style model, updated when
  //   the camera moves; `tint` is mixed over the whole model.
  // - Moving or spinning models are entries of a second `model` source
  //   drawn with `model-type: location-indicator` (placed every frame, not
  //   tiled), as in Mapbox's own animated-model example: their `models`
  //   (position, orientation) change every frame, altitude and scale go
  //   through feature state; `tint` overrides the `paint*` materials.

  static let movingSourceId = "munim-native-moving"
  static let movingLayerId = "munim-native-moving"
  static let movingSeaLayerId = "munim-native-moving-sea"
  static var layerIds: [String] { [groundLayerId, seaLayerId, movingLayerId, movingSeaLayerId] }

  private var styleModels = Set<String>()
  private var lastMovingJSON = ""

  private func animated(_ model: MunimModel) -> Bool {
    model.motion.count > 1 || model.spinDegreesPerSecond != 0
  }

  private func changesEveryFrame(_ model: MunimModel) -> Bool {
    animated(model) || model.screenSize > 0
  }

  static let animatedSourceId = "munim-native-animated"
  static let animatedLayerId = "munim-native-animated"
  static let animatedSeaLayerId = "munim-native-animated-sea"
  private var animatedLayerIds: [String] { [Self.animatedLayerId, Self.animatedSeaLayerId] }

  func styleReloaded() {
    installed = false
    lastJSON = ""
    lastMovingJSON = ""
    styleModels = []
    update()
  }

  /// Draws the native models as they are now.
  func update() {
    guard let engine, engine.styleReady else { return }
    let map = engine.mapboxMap
    guard !native.isEmpty else {
      if installed || map.sourceExists(withId: Self.sourceId) || map.sourceExists(withId: Self.movingSourceId) {
        uninstall()
      }
      return
    }
    do {
      if !installed {
        uninstall()
        try map.addSource(withId: Self.sourceId, properties: ["type": "model", "models": [String: Any]()])
        try map.addSource(withId: Self.movingSourceId, properties: [
          "type": "geojson", "data": ["type": "FeatureCollection", "features": [Any]()],
        ])
        try addLayer(Self.groundLayerId, source: Self.sourceId, sea: false, moving: false)
        try addLayer(Self.seaLayerId, source: Self.sourceId, sea: true, moving: false)
        try addLayer(Self.movingLayerId, source: Self.movingSourceId, sea: false, moving: true)
        try addLayer(Self.movingSeaLayerId, source: Self.movingSourceId, sea: true, moving: true)
        installed = true
      }
      let still = native.filter { !changesEveryFrame($0) }
      let moving = native.filter { !animated($0) && $0.screenSize > 0 }
      try updateAnimated(native.filter(animated))
      let models = stillEntries(still)
      let json = MapboxJSON.key(models)
      if json != lastJSON {
        lastJSON = json
        try map.setSourceProperty(for: Self.sourceId, property: "models", value: models)
      }
      for uri in Set(moving.map(\.uri)) where !styleModels.contains(uri) {
        styleModels.insert(uri)
        let id = Self.styleModelId(uri)
        if map.hasStyleModel(modelId: id) { try? map.removeStyleModel(modelId: id) }
        try map.addStyleModel(modelId: id, modelUri: local(uri))
      }
      let features = movingFeatures(moving)
      let ids = moving.map(\.id).joined(separator: "|")
      if ids != lastMovingJSON {
        // A different set of models: replace the data.
        lastMovingJSON = ids
        try map.setSourceProperty(
          for: Self.movingSourceId, property: "data", value: ["type": "FeatureCollection", "features": features])
      } else if !features.isEmpty, map.sourceExists(withId: Self.movingSourceId) {
        // The same models moved: a partial update, cheap enough every frame.
        let turf = features.compactMap { try? MapboxJSON.decode(Feature.self, from: $0) }
        map.updateGeoJSONSourceFeatures(forSourceId: Self.movingSourceId, features: turf)
      }
    } catch {
      engine.onError?("Mapbox: native models: \(error.localizedDescription)")
    }
  }

  /// Moving models: a `model` source of location-indicator models, updated every frame.
  private func updateAnimated(_ models: [MunimModel]) throws {
    guard let engine else { return }
    let map = engine.mapboxMap
    if !map.sourceExists(withId: Self.animatedSourceId) {
      try map.addSource(withId: Self.animatedSourceId, properties: ["type": "model", "models": [String: Any]()])
      for (id, sea) in [(Self.animatedLayerId, false), (Self.animatedSeaLayerId, true)] {
        var layer: [String: Any] = [
          "id": id, "type": "model", "source": Self.animatedSourceId,
          "filter": sea ? ["==", ["get", "sea"], true] : ["!=", ["get", "sea"], true],
          "paint": [
            "model-type": "location-indicator",
            "model-scale": ["coalesce", ["feature-state", "scale"], ["literal", [1, 1, 1]]],
            "model-translation": ["literal", [0, 0, 0]],
            "model-cast-shadows": true,
            "model-receive-shadows": true,
            "model-emissive-strength": ["get", "emissive"],
            "model-elevation-reference": sea ? "sea" : "ground",
          ] as [String: Any],
        ]
        layer["paint"] = (layer["paint"] as? [String: Any] ?? [:]).merging([
          "model-translation": ["array", "number", 3,
                                ["coalesce", ["feature-state", "translation"], ["literal", [0, 0, 0]]]],
        ]) { $1 }
        if engine.hasSlots { layer["slot"] = "middle" }
        try map.addLayer(with: layer, layerPosition: nil)
      }
    }
    let now = Date().timeIntervalSince1970
    let camera = engine.cameraSource.cameraState(previous: nil)
    var entries: [String: Any] = [:]
    var states: [(String, [String: Any])] = []
    for model in models {
      let p = placement(model, now: now, camera: camera)
      var entry: [String: Any] = [
        "uri": local(model.uri),
        "position": [p.pose.longitude, p.pose.latitude],
        "orientation": [0, 0, p.heading],
        "featureProperties": properties(model, p),
      ]
      if let overrides = tintOverrides(model) { entry["materialOverrides"] = overrides }
      entries[model.id] = entry
      states.append((model.id, ["scale": [p.scale, p.scale, p.scale], "translation": [0, 0, p.pose.altitude]]))
    }
    try map.setSourceProperty(for: Self.animatedSourceId, property: "models", value: entries)
    for (id, state) in states {
      _ = map.setFeatureState(sourceId: Self.animatedSourceId, featureId: id, state: state) { _ in }
    }
  }

  private func tintOverrides(_ model: MunimModel) -> [String: Any]? {
    guard !model.tintColor.isEmpty, let color = UIColor(mapModelHex: model.tintColor),
          let names = infos[model.uri]?.paintMaterials, !names.isEmpty else { return nil }
    return Dictionary(uniqueKeysWithValues: names.map {
      ($0, ["model-color": color.styleString, "model-color-mix-intensity": 1.0] as [String: Any])
    })
  }

  static func styleModelId(_ uri: String) -> String {
    "munim-model-" + String(UInt(bitPattern: uri.hashValue), radix: 36)
  }

  private func addLayer(_ id: String, source: String, sea: Bool, moving: Bool) throws {
    guard let engine else { return }
    var paint: [String: Any] = [
      "model-type": "common-3d",
      "model-scale": ["get", "scale"],
      "model-translation": ["get", "translation"],
      "model-cast-shadows": true,
      "model-receive-shadows": true,
      "model-emissive-strength": ["get", "emissive"],
      "model-opacity": ["get", "opacity"],
      "model-elevation-reference": sea ? "sea" : "ground",
    ]
    var layer: [String: Any] = [
      "id": id, "type": "model", "source": source,
      "filter": sea ? ["==", ["get", "sea"], true] : ["!=", ["get", "sea"], true],
    ]
    if moving {
      paint["model-rotation"] = ["get", "rotation"]
      paint["model-color"] = ["get", "tint"]
      paint["model-color-mix-intensity"] = ["get", "tintMix"]
      layer["layout"] = ["model-id": ["get", "modelId"]]
    }
    layer["paint"] = paint
    if engine.hasSlots { layer["slot"] = "middle" }
    try engine.mapboxMap.addLayer(with: layer, layerPosition: nil)
  }

  private func uninstall() {
    guard let map = engine?.mapboxMap else { return }
    for id in Self.layerIds + animatedLayerIds where map.layerExists(withId: id) { try? map.removeLayer(withId: id) }
    for id in [Self.sourceId, Self.movingSourceId, Self.animatedSourceId] where map.sourceExists(withId: id) {
      try? map.removeSource(withId: id)
    }
    installed = false
    lastJSON = ""
    lastMovingJSON = ""
  }

  /// Pose, heading and scale of a model now.
  private func placement(_ model: MunimModel, now: Double, camera: MapCameraState?) -> (pose: MunimPose, heading: Double, scale: Double) {
    let pose = model.pose(at: now)
    var heading = pose.heading
    if model.spinDegreesPerSecond != 0 {
      heading += (model.spinDegreesPerSecond * now).truncatingRemainder(dividingBy: 360)
    }
    // munim-maps' glTF models face -Z; Mapbox turns +Z to north. Measured on
    // the iPad: heading 90 drew the fire truck's cab west without this.
    heading += 180
    heading = (heading.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    var scale = model.scale
    if model.screenSize > 0, let camera, let height = infos[model.uri]?.height, height > 0 {
      // Same rule as the 3D layer: `screenSize` points tall on screen.
      let position = camera.scenePosition(latitude: pose.latitude, longitude: pose.longitude, altitude: pose.altitude)
      if let depth = camera.project(position)?.depth, depth > 0 {
        scale *= model.screenSize * Double(depth) / camera.focalLength / height
      }
    }
    return (pose, heading, scale)
  }

  private func properties(_ model: MunimModel, _ p: (pose: MunimPose, heading: Double, scale: Double)) -> [String: Any] {
    [
      "id": model.id,
      "scale": [p.scale, p.scale, p.scale],
      "translation": [0, 0, p.pose.altitude],
      "sea": model.altitudeReference == .sea,
      "emissive": model.emissive ? 1 : 0,
      "opacity": 1,
    ]
  }

  private func stillEntries(_ models: [MunimModel]) -> [String: Any] {
    let now = Date().timeIntervalSince1970
    var result: [String: Any] = [:]
    for model in models {
      let p = placement(model, now: now, camera: nil)
      var entry: [String: Any] = [
        "uri": local(model.uri),
        "position": [p.pose.longitude, p.pose.latitude],
        "orientation": [0, 0, p.heading],
        "featureProperties": properties(model, p),
      ]
      if let overrides = tintOverrides(model) { entry["materialOverrides"] = overrides }
      result[model.id] = entry
    }
    return result
  }

  private func movingFeatures(_ models: [MunimModel]) -> [[String: Any]] {
    guard let engine else { return [] }
    let now = Date().timeIntervalSince1970
    let camera = engine.cameraSource.cameraState(previous: nil)
    return models.map { model in
      let p = placement(model, now: now, camera: camera)
      var props = properties(model, p)
      props["modelId"] = Self.styleModelId(model.uri)
      props["rotation"] = [0, 0, p.heading]
      let tint = UIColor(mapModelHex: model.tintColor)
      props["tint"] = (tint ?? .white).styleString
      props["tintMix"] = tint == nil ? 0 : 0.6
      return [
        "type": "Feature", "id": model.id, "properties": props,
        "geometry": ["type": "Point", "coordinates": [p.pose.longitude, p.pose.latitude]],
      ]
    }
  }

  // MARK: Clock

  /// Moving, spinning or screen-sized models are updated every frame.
  private func updateClock() {
    let needsFrames = native.contains { $0.motion.count > 1 || $0.spinDegreesPerSecond != 0 }
    if needsFrames, link == nil {
      let link = CADisplayLink(target: MapboxNativeModelsTarget(self), selector: #selector(MapboxNativeModelsTarget.tick))
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
      link.add(to: .main, forMode: .common)
      self.link = link
    } else if !needsFrames {
      link?.invalidate()
      link = nil
    }
  }

  /// The camera moved: screen-sized models change size.
  func cameraChanged() {
    if link == nil, native.contains(where: { $0.screenSize > 0 }) { update() }
  }

  fileprivate func tick() { update() }

  func stop() {
    link?.invalidate()
    link = nil
  }

  /// The native model under a point, for `onModelPress`.
  func hit(at point: CGPoint, completion: @escaping (String?) -> Void) {
    guard let engine, installed else { return completion(nil) }
    let box = CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16)
    _ = engine.mapboxMap.queryRenderedFeatures(
      with: box, options: RenderedQueryOptions(layerIds: Self.layerIds + animatedLayerIds, filter: nil)
    ) { result in
      guard case .success(let features) = result, let first = features.first else { return completion(nil) }
      if case .string(let id)? = first.queriedFeature.feature.properties?["id"] {
        completion(id)
      } else if case .string(let id)? = first.queriedFeature.feature.identifier {
        completion(id)
      } else {
        completion(nil)
      }
    }
  }
}

private final class MapboxNativeModelsTarget: NSObject {
  weak var owner: MapboxNativeModels?
  init(_ owner: MapboxNativeModels) { self.owner = owner }
  @objc func tick() { owner?.tick() }
}

/// What the native renderer needs from a glTF file: its height (for
/// `screenSize`) and the names of its `paint*` materials (for `tint`).
struct MapboxGLBInfo {
  var height: Double
  var paintMaterials: [String]
  var hasAnimations = false

  /// Reads the model (downloading it into munim-maps' cache if remote):
  /// its info and the local file.
  static func load(uri: String, completion: @escaping (MapboxGLBInfo?, URL?) -> Void) {
    MapModelNodes.resolveLocalURL(uri: uri) { result in
      DispatchQueue.global(qos: .utility).async {
        var info: MapboxGLBInfo?
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
  static func parse(_ data: Data) -> MapboxGLBInfo? {
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
    return MapboxGLBInfo(height: height, paintMaterials: paint, hasAnimations: animated)
  }
}
#endif
