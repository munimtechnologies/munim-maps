#if canImport(MapboxMaps)
@_spi(Experimental) import MapboxMaps
import MapKit
import UIKit

/// What the Mapbox engine has put into the current style, to diff against
/// the next `mapbox={{…}}` options.
struct MapboxStyleState {
  var options: [String: Any] = [:]
  /// The style that is loaded (URL or JSON); nil forces a reload.
  var loadedStyleKey: String?
  /// Canonical JSON of what was applied, by key, for this style.
  var applied: [String: String] = [:]
  var sources: [String: [String: Any]] = [:]
  var layers: [String: [String: Any]] = [:]
  var layerOrder: [String] = []
  var images: [String: String] = [:]
  var models: [String: String] = [:]
  var imports: [String: [String: Any]] = [:]
  var basemapConfig: [String: String] = [:]
  var importConfig: [String: String] = [:]
  var isGlobe = false
  var hasTerrain = false
  var isDarkPreset = false

  mutating func styleReloaded() {
    applied = [:]
    sources = [:]
    layers = [:]
    layerOrder = []
    images = [:]
    models = [:]
    imports = [:]
    basemapConfig = [:]
    importConfig = [:]
  }
}

enum MapboxJSON {
  /// Canonical text for diffing.
  static func key(_ value: Any?) -> String {
    guard let value, !(value is NSNull) else { return "null" }
    let clean = MunimProviderJSON.sanitize(value)
    if let data = try? JSONSerialization.data(withJSONObject: clean, options: [.fragmentsAllowed, .sortedKeys]) {
      return String(decoding: data, as: UTF8.self)
    }
    return String(describing: value)
  }

  static func decode<T: Decodable>(_ type: T.Type, from value: Any) throws -> T {
    let data = try JSONSerialization.data(withJSONObject: MunimProviderJSON.sanitize(value), options: [.fragmentsAllowed])
    return try JSONDecoder().decode(T.self, from: data)
  }

  /// Any `Encodable` (Turf features, JSONObject…) as plain JSON values.
  static func plain<T: Encodable>(_ value: T) -> Any {
    guard let data = try? JSONEncoder().encode(value),
          let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    else { return NSNull() }
    return object
  }

  static func double(_ value: Any?) -> Double? {
    if let n = value as? NSNumber { return n.doubleValue }
    if let d = value as? Double { return d }
    return nil
  }

  static func bool(_ value: Any?) -> Bool? {
    if let b = value as? Bool { return b }
    if let n = value as? NSNumber { return n.boolValue }
    return nil
  }

  static func coordinate(_ value: Any?) -> CLLocationCoordinate2D? {
    guard let d = value as? [String: Any],
          let lat = double(d["latitude"]), let lng = double(d["longitude"]) else { return nil }
    return CLLocationCoordinate2D(latitude: lat, longitude: lng)
  }

  static func insets(_ value: Any?) -> UIEdgeInsets? {
    guard let d = value as? [String: Any] else { return nil }
    return UIEdgeInsets(
      top: double(d["top"]) ?? 0, left: double(d["left"]) ?? 0,
      bottom: double(d["bottom"]) ?? 0, right: double(d["right"]) ?? 0)
  }

  static func color(_ value: Any?) -> UIColor? {
    guard let s = value as? String, !s.isEmpty else { return nil }
    return UIColor(mapModelHex: s) ?? UIColor(cssLike: s)
  }
}

extension UIColor {
  /// `rgb(…)`, `rgba(…)` or a few names, for options written like CSS.
  convenience init?(cssLike text: String) {
    let s = text.trimmingCharacters(in: .whitespaces).lowercased()
    let names: [String: (CGFloat, CGFloat, CGFloat)] = [
      "white": (1, 1, 1), "black": (0, 0, 0), "red": (1, 0, 0), "green": (0, 0.5, 0), "blue": (0, 0, 1),
      "orange": (1, 0.65, 0), "yellow": (1, 1, 0), "gray": (0.5, 0.5, 0.5), "grey": (0.5, 0.5, 0.5),
    ]
    if let rgb = names[s] { self.init(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1); return }
    guard s.hasPrefix("rgb"), let open = s.firstIndex(of: "("), let close = s.lastIndex(of: ")") else { return nil }
    let parts = s[s.index(after: open)..<close].split(separator: ",").compactMap {
      Double($0.trimmingCharacters(in: .whitespaces))
    }
    guard parts.count >= 3 else { return nil }
    self.init(red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, alpha: parts.count > 3 ? parts[3] : 1)
  }

  /// `rgba(r, g, b, a)` for style JSON.
  var styleString: String {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    getRed(&r, green: &g, blue: &b, alpha: &a)
    return "rgba(\(Int((r * 255).rounded())), \(Int((g * 255).rounded())), \(Int((b * 255).rounded())), \(a))"
  }
}

extension MapboxMapEngine {
  var mapboxOptions: [String: Any] { style.options }

  // MARK: Which style

  /// Mapbox Standard for `standard` and `muted`, Standard Satellite for
  /// `hybrid` and `imagery`, unless `styleUrl`, `mapbox.styleJson` or the
  /// configured default style say otherwise.
  private func desiredStyle() -> (key: String, uri: StyleURI?, json: String?) {
    if let json = mapboxOptions["styleJson"] {
      let text = (json as? String) ?? MunimProviderJSON.string(json)
      return ("json:" + text, nil, text)
    }
    let configured = MunimMapsConfiguration.shared.mapboxStyleURL
    let url = !styleURL.isEmpty ? styleURL : !configured.isEmpty ? configured
      : (mapStyle == .hybrid || mapStyle == .imagery) ? StyleURI.standardSatellite.rawValue : StyleURI.standard.rawValue
    return ("url:" + url, StyleURI(rawValue: url), nil)
  }

  func loadStyleIfNeeded() {
    let wanted = desiredStyle()
    guard wanted.key != style.loadedStyleKey else { return }
    style.loadedStyleKey = wanted.key
    style.styleReloaded()
    if let json = wanted.json {
      mapboxMap.styleJSON = json
    } else if let uri = wanted.uri {
      mapboxMap.styleURI = uri
    } else {
      onError?("Mapbox: \(styleURL) is not a style URL")
    }
  }

  /// Whether the style has Mapbox Standard's slots.
  var hasSlots: Bool { !mapboxMap.allSlotIdentifiers.isEmpty }

  // MARK: Applying `mapbox={{…}}` to the style

  func applyStyleOptions(reloaded: Bool) {
    guard mapboxMap.isStyleLoaded else { return }
    if reloaded { style.styleReloaded() }
    applyBasemapConfig()
    applyImportConfig()
    applyImports()
    applyProjection()
    applyAtmosphere()
    applyTerrain()
    applyLights()
    applyWeather()
    applyColorTheme()
    applyImages()
    applyModels()
    applySourcesAndLayers()
    applyTraffic()
    if reloaded { applyMapOptions() }
  }

  /// Runs `body` when `value` differs from what was applied under `key`.
  private func ifChanged(_ key: String, _ value: Any?, _ body: () throws -> Void) {
    let canonical = MapboxJSON.key(value)
    guard style.applied[key] != canonical else { return }
    style.applied[key] = canonical
    do {
      try body()
    } catch {
      onError?("Mapbox: \(key): \(error.localizedDescription)")
    }
  }

  private var standardOptions: [String: Any] { mapboxOptions["standard"] as? [String: Any] ?? [:] }

  /// Mapbox Standard's config from the shared props, then `mapbox.standard`.
  private func basemapConfig() -> [String: Any] {
    var config: [String: Any] = [:]
    config["lightPreset"] = isDark ? "night" : "day"
    config["show3dObjects"] = showsBuildings
    if mapStyle == .muted { config["theme"] = "faded" }
    if !poiLabelsVisible { config["showPointOfInterestLabels"] = false }
    if mapStyle == .imagery {
      for key in ["showRoadsAndTransit", "showPlaceLabels", "showPointOfInterestLabels", "showTransitLabels",
                  "showRoadLabels", "showPedestrianRoads"] {
        config[key] = false
      }
    }
    for (key, value) in standardOptions { config[key] = value }
    if let preset = mapboxOptions["lightPreset"] as? String { config["lightPreset"] = preset }
    return config
  }

  /// False when `pointsOfInterest` is `none`.
  private var poiLabelsVisible: Bool {
    let sample: [MKPointOfInterestCategory] = [.restaurant, .cafe, .park, .museum, .hotel, .store, .airport, .hospital, .school]
    return sample.contains { pointOfInterestFilter.includes($0) }
  }

  private func applyBasemapConfig() {
    let config = basemapConfig()
    let preset = config["lightPreset"] as? String ?? "day"
    style.isDarkPreset = preset == "night" || preset == "dusk"
    guard mapboxMap.styleImports.contains(where: { $0.id == "basemap" }) else { return }
    for (key, value) in config {
      let canonical = MapboxJSON.key(value)
      if style.basemapConfig[key] == canonical { continue }
      style.basemapConfig[key] = canonical
      // One by one: a key this Standard version does not know fails alone.
      try? mapboxMap.setStyleImportConfigProperty(for: "basemap", config: key, value: value)
    }
  }

  private func applyImportConfig() {
    guard let all = mapboxOptions["importConfig"] as? [String: Any] else { return }
    for (importId, configs) in all {
      guard let configs = configs as? [String: Any] else { continue }
      for (key, value) in configs {
        let id = importId + "/" + key
        let canonical = MapboxJSON.key(value)
        if style.importConfig[id] == canonical { continue }
        style.importConfig[id] = canonical
        do {
          try mapboxMap.setStyleImportConfigProperty(for: importId, config: key, value: value)
        } catch {
          onError?("Mapbox: importConfig \(importId).\(key): \(error.localizedDescription)")
        }
      }
    }
  }

  private func applyImports() {
    let wanted = (mapboxOptions["imports"] as? [[String: Any]] ?? []).filter { $0["id"] is String }
    let wantedIds = Set(wanted.compactMap { $0["id"] as? String })
    for id in style.imports.keys where !wantedIds.contains(id) {
      try? mapboxMap.removeStyleImport(withId: id)
      style.imports[id] = nil
    }
    for item in wanted {
      guard let id = item["id"] as? String else { continue }
      if let old = style.imports[id], MapboxJSON.key(old) == MapboxJSON.key(item) { continue }
      let config = item["config"] as? [String: Any]
      let position = (item["beforeId"] as? String).map { ImportPosition.below($0) }
      do {
        let exists = style.imports[id] != nil
        if let url = item["url"] as? String, let uri = StyleURI(rawValue: url) {
          if exists {
            try mapboxMap.updateStyleImport(withId: id, uri: uri, config: config)
          } else {
            try mapboxMap.addStyleImport(withId: id, uri: uri, config: config, importPosition: position)
          }
        } else if let json = item["json"] {
          let text = (json as? String) ?? MunimProviderJSON.string(json)
          if exists {
            try mapboxMap.updateStyleImport(withId: id, json: text, config: config)
          } else {
            try mapboxMap.addStyleImport(withId: id, json: text, config: config, importPosition: position)
          }
        }
        style.imports[id] = item
      } catch {
        onError?("Mapbox: import \(id): \(error.localizedDescription)")
      }
    }
  }

  private func applyProjection() {
    let name = (mapboxOptions["projection"] as? String) ?? (globe ? "globe" : "mercator")
    style.isGlobe = name == "globe"
    ifChanged("projection", name) {
      try mapboxMap.setProjection(StyleProjection(name: name == "globe" ? .globe : .mercator))
    }
  }

  private func applyAtmosphere() {
    let value = mapboxOptions["atmosphere"]
    ifChanged("atmosphere", value) {
      if let properties = value as? [String: Any] {
        try mapboxMap.setAtmosphere(properties: properties)
      } else if MapboxJSON.bool(value) == false {
        try mapboxMap.removeAtmosphere()
      }
    }
  }

  static let demSourceId = "munim-mapbox-dem"

  private func applyTerrain() {
    var properties: [String: Any]?
    let option = mapboxOptions["terrain"]
    let exaggeration = MapboxJSON.double(mapboxOptions["terrainExaggeration"])
    if let dict = option as? [String: Any] {
      properties = dict
    } else if let on = MapboxJSON.bool(option) {
      properties = on ? [:] : nil
    } else if let exaggeration {
      properties = exaggeration > 0 ? [:] : nil
    } else if (mapStyle == .hybrid || mapStyle == .imagery) && elevation == .realistic {
      properties = [:]
    }
    if var p = properties {
      if p["exaggeration"] == nil { p["exaggeration"] = exaggeration ?? 1 }
      properties = p
    }
    style.hasTerrain = properties != nil
    ifChanged("terrain", properties) {
      guard var p = properties else {
        mapboxMap.removeTerrain()
        return
      }
      if p["source"] == nil {
        if !mapboxMap.sourceExists(withId: Self.demSourceId) {
          try mapboxMap.addSource(withId: Self.demSourceId, properties: [
            "type": "raster-dem", "url": "mapbox://mapbox.mapbox-terrain-dem-v1", "tileSize": 514, "maxzoom": 14,
          ])
        }
        p["source"] = Self.demSourceId
      }
      try mapboxMap.setTerrain(properties: p)
    }
  }

  private func applyLights() {
    guard let lights = mapboxOptions["lights"] as? [[String: Any]] else { return }
    ifChanged("lights", lights) {
      if let flat = lights.first(where: { $0["type"] as? String == "flat" }) {
        try mapboxMap.setLights(MapboxJSON.decode(FlatLight.self, from: flat))
      } else if let ambient = lights.first(where: { $0["type"] as? String == "ambient" }),
                let directional = lights.first(where: { $0["type"] as? String == "directional" }) {
        try mapboxMap.setLights(
          ambient: MapboxJSON.decode(AmbientLight.self, from: ambient),
          directional: MapboxJSON.decode(DirectionalLight.self, from: directional))
      } else {
        throw MunimMapEngineError("one flat light, or an ambient and a directional light")
      }
    }
  }

  private func applyWeather() {
    let snow = mapboxOptions["snow"]
    ifChanged("snow", snow) {
      if let p = snow as? [String: Any] {
        try mapboxMap.setSnow(MapboxJSON.decode(Snow.self, from: p))
      } else if style.applied["snowSet"] != nil {
        try mapboxMap.removeSnow()
      }
      style.applied["snowSet"] = snow is [String: Any] ? "1" : nil
    }
    let rain = mapboxOptions["rain"]
    ifChanged("rain", rain) {
      if let p = rain as? [String: Any] {
        try mapboxMap.setRain(MapboxJSON.decode(Rain.self, from: p))
      } else if style.applied["rainSet"] != nil {
        try mapboxMap.removeRain()
      }
      style.applied["rainSet"] = rain is [String: Any] ? "1" : nil
    }
  }

  private func applyColorTheme() {
    let theme = mapboxOptions["colorTheme"]
    ifChanged("colorTheme", theme) {
      if let data = (theme as? [String: Any])?["data"] as? String {
        try mapboxMap.setColorTheme(ColorTheme(base64: data))
      } else if MapboxJSON.bool(theme) == false {
        try mapboxMap.removeColorTheme()
      }
    }
  }

  // MARK: Images and models

  private func applyImages() {
    let wanted = mapboxOptions["images"] as? [String: Any] ?? [:]
    for id in style.images.keys where wanted[id] == nil {
      try? mapboxMap.removeImage(withId: id)
      style.images[id] = nil
    }
    for (id, value) in wanted {
      guard let spec = value as? [String: Any], let uri = spec["uri"] as? String else { continue }
      let canonical = MapboxJSON.key(spec)
      if style.images[id] == canonical { continue }
      style.images[id] = canonical
      MapboxImages.load(uri: uri) { [weak self] image in
        guard let self, let image else {
          self?.onError?("Mapbox: image \(id) could not be loaded from \(uri)")
          return
        }
        self.addStyleImage(image, id: id, spec: spec)
      }
    }
  }

  private func addStyleImage(_ loaded: UIImage, id: String, spec: [String: Any]) {
    var image = loaded
    if let scale = MapboxJSON.double(spec["scale"]), scale > 0, let cg = loaded.cgImage {
      image = UIImage(cgImage: cg, scale: scale, orientation: .up)
    }
    func stretches(_ value: Any?) -> [ImageStretches] {
      (value as? [[Any]] ?? []).compactMap { pair in
        guard pair.count == 2, let a = MapboxJSON.double(pair[0]), let b = MapboxJSON.double(pair[1]) else { return nil }
        return ImageStretches(first: Float(a), second: Float(b))
      }
    }
    var content: ImageContent?
    if let c = spec["content"] as? [Any], c.count == 4 {
      let v = c.compactMap(MapboxJSON.double)
      if v.count == 4 { content = ImageContent(left: Float(v[0]), top: Float(v[1]), right: Float(v[2]), bottom: Float(v[3])) }
    }
    do {
      try mapboxMap.addImage(
        image, id: id, sdf: MapboxJSON.bool(spec["sdf"]) ?? false,
        stretchX: stretches(spec["stretchX"]), stretchY: stretches(spec["stretchY"]), content: content)
    } catch {
      onError?("Mapbox: image \(id): \(error.localizedDescription)")
    }
  }

  private func applyModels() {
    let wanted = mapboxOptions["models"] as? [String: Any] ?? [:]
    for id in style.models.keys where wanted[id] == nil {
      try? mapboxMap.removeStyleModel(modelId: id)
      style.models[id] = nil
    }
    for (id, value) in wanted {
      guard let uri = value as? String, style.models[id] != uri else { continue }
      style.models[id] = uri
      MapboxImages.resolveModelURI(uri) { [weak self] resolved in
        guard let self else { return }
        do {
          if self.mapboxMap.hasStyleModel(modelId: id) { try self.mapboxMap.removeStyleModel(modelId: id) }
          try self.mapboxMap.addStyleModel(modelId: id, modelUri: resolved)
        } catch {
          self.onError?("Mapbox: model \(id): \(error.localizedDescription)")
        }
      }
    }
  }

  // MARK: Sources and layers

  /// munim-maps' placement keys, not part of the style spec.
  private static let positionKeys: Set<String> = ["beforeId", "aboveId", "index"]

  static func layerPosition(_ spec: [String: Any]) -> LayerPosition? {
    if let id = spec["beforeId"] as? String { return .below(id) }
    if let id = spec["aboveId"] as? String { return .above(id) }
    if let index = MapboxJSON.double(spec["index"]) { return .at(Int(index)) }
    return nil
  }

  static func styleLayer(_ spec: [String: Any]) -> [String: Any] {
    spec.filter { !positionKeys.contains($0.key) }
  }

  private func applySourcesAndLayers() {
    let wantedSources = mapboxOptions["sources"] as? [String: Any] ?? [:]
    let wantedLayers = (mapboxOptions["layers"] as? [[String: Any]] ?? []).filter { $0["id"] is String }
    let wantedLayerIds = Set(wantedLayers.compactMap { $0["id"] as? String })

    // Layers that went away, and layers on sources that must be rebuilt.
    var rebuildSources = Set<String>()
    for (id, value) in wantedSources {
      guard let spec = value as? [String: Any], let old = style.sources[id] else { continue }
      if MapboxJSON.key(old) == MapboxJSON.key(spec) { continue }
      var oldRest = old
      var newRest = spec
      oldRest["data"] = nil
      newRest["data"] = nil
      if MapboxJSON.key(oldRest) != MapboxJSON.key(newRest) { rebuildSources.insert(id) }
    }
    for id in style.layerOrder {
      let layer = style.layers[id]
      let source = layer?["source"] as? String
      if !wantedLayerIds.contains(id) || source.map(rebuildSources.contains) == true
        || source.map({ wantedSources[$0] == nil && style.sources[$0] != nil }) == true {
        try? mapboxMap.removeLayer(withId: id)
        style.layers[id] = nil
      }
    }
    style.layerOrder.removeAll { style.layers[$0] == nil }

    // Sources.
    for id in style.sources.keys where wantedSources[id] == nil || rebuildSources.contains(id) {
      try? mapboxMap.removeSource(withId: id)
      style.sources[id] = nil
    }
    for (id, value) in wantedSources {
      guard let spec = value as? [String: Any] else { continue }
      do {
        if let old = style.sources[id] {
          if MapboxJSON.key(old) == MapboxJSON.key(spec) { continue }
          // Only the data changed (rebuilds were removed above).
          if let data = spec["data"] { try mapboxMap.setSourceProperty(for: id, property: "data", value: data) }
        } else {
          if mapboxMap.sourceExists(withId: id) { try? mapboxMap.removeSource(withId: id) }
          try mapboxMap.addSource(withId: id, properties: spec)
        }
        style.sources[id] = spec
      } catch {
        onError?("Mapbox: source \(id): \(error.localizedDescription)")
      }
    }

    // Layers, in order.
    for spec in wantedLayers {
      guard let id = spec["id"] as? String else { continue }
      let properties = Self.styleLayer(spec)
      do {
        if let old = style.layers[id] {
          if MapboxJSON.key(old) == MapboxJSON.key(spec) { continue }
          let oldProperties = Self.styleLayer(old)
          let structural = ["type", "source", "source-layer"].contains {
            MapboxJSON.key(oldProperties[$0]) != MapboxJSON.key(properties[$0])
          }
          if structural {
            try mapboxMap.removeLayer(withId: id)
            try mapboxMap.addLayer(with: properties, layerPosition: Self.layerPosition(spec))
          } else {
            var update = properties
            update["id"] = nil
            update["type"] = nil
            update["source"] = nil
            update["source-layer"] = nil
            // Removed paint / layout keys go back to their defaults.
            for group in ["paint", "layout"] {
              var merged = update[group] as? [String: Any] ?? [:]
              for key in (oldProperties[group] as? [String: Any] ?? [:]).keys where merged[key] == nil {
                merged[key] = NSNull()
              }
              if !merged.isEmpty { update[group] = merged }
            }
            try mapboxMap.setLayerProperties(for: id, properties: update)
            if MapboxJSON.key(Self.layerPosition(old).map(String.init(describing:)))
              != MapboxJSON.key(Self.layerPosition(spec).map(String.init(describing:))),
              let position = Self.layerPosition(spec) {
              try mapboxMap.moveLayer(withId: id, to: position)
            }
          }
        } else {
          if mapboxMap.layerExists(withId: id) { try? mapboxMap.removeLayer(withId: id) }
          try mapboxMap.addLayer(with: properties, layerPosition: Self.layerPosition(spec))
          style.layerOrder.append(id)
        }
        style.layers[id] = spec
      } catch {
        onError?("Mapbox: layer \(id): \(error.localizedDescription)")
      }
    }
  }

  // MARK: Traffic

  static let trafficId = "munim-traffic"

  private func applyTraffic() {
    ifChanged("traffic", showsTraffic) {
      if mapboxMap.layerExists(withId: Self.trafficId) { try mapboxMap.removeLayer(withId: Self.trafficId) }
      if mapboxMap.sourceExists(withId: Self.trafficId) { try mapboxMap.removeSource(withId: Self.trafficId) }
      guard showsTraffic else { return }
      try mapboxMap.addSource(withId: Self.trafficId, properties: [
        "type": "vector", "url": "mapbox://mapbox.mapbox-traffic-v1",
      ])
      var layer: [String: Any] = [
        "id": Self.trafficId, "type": "line", "source": Self.trafficId, "source-layer": "traffic",
        "layout": ["line-cap": "round", "line-join": "round"],
        "paint": [
          "line-color": ["match", ["get", "congestion"],
                         "low", "#30D158", "moderate", "#FF9F0A", "heavy", "#FF453A", "severe", "#8B0000", "#30D158"],
          "line-width": ["interpolate", ["exponential", 1.5], ["zoom"], 10, 1, 15, 3, 20, 10],
          "line-emissive-strength": 1,
        ] as [String: Any],
      ]
      if hasSlots { layer["slot"] = "middle" }
      try mapboxMap.addLayer(with: layer, layerPosition: nil)
    }
  }

  // MARK: Map (not style) options

  func applyMapOptions() {
    applyGestures()
    applyOrnaments()
    applyLocation()
    applyCameraBounds()
    applyRendering()
    applyEvents()
    applyInteractions()
  }

  func applyGestures() {
    var o = mapView.gestures.options
    o.pinchZoomEnabled = isZoomEnabled
    o.doubleTapToZoomInEnabled = isZoomEnabled
    o.doubleTouchToZoomOutEnabled = isZoomEnabled
    o.quickZoomEnabled = isZoomEnabled
    o.panEnabled = isScrollEnabled
    o.pinchPanEnabled = isScrollEnabled
    o.rotateEnabled = isRotateEnabled
    o.pitchEnabled = isPitchEnabled
    o.pinchEnabled = isZoomEnabled || isScrollEnabled || isRotateEnabled
    if let g = mapboxOptions["gestures"] as? [String: Any] {
      func flag(_ key: String, _ apply: (Bool) -> Void) { if let v = MapboxJSON.bool(g[key]) { apply(v) } }
      flag("panEnabled") { o.panEnabled = $0 }
      flag("pinchEnabled") { o.pinchEnabled = $0 }
      flag("rotateEnabled") { o.rotateEnabled = $0 }
      flag("pitchEnabled") { o.pitchEnabled = $0 }
      flag("pinchZoomEnabled") { o.pinchZoomEnabled = $0 }
      flag("pinchPanEnabled") { o.pinchPanEnabled = $0 }
      flag("simultaneousRotateAndPinchZoomEnabled") { o.simultaneousRotateAndPinchZoomEnabled = $0 }
      flag("doubleTapToZoomInEnabled") { o.doubleTapToZoomInEnabled = $0 }
      flag("doubleTouchToZoomOutEnabled") { o.doubleTouchToZoomOutEnabled = $0 }
      flag("quickZoomEnabled") { o.quickZoomEnabled = $0 }
      switch g["panMode"] as? String {
      case "horizontal": o.panMode = .horizontal
      case "vertical": o.panMode = .vertical
      case "horizontalAndVertical": o.panMode = .horizontalAndVertical
      default: break
      }
      if let f = MapboxJSON.double(g["panDecelerationFactor"]) { o.panDecelerationFactor = CGFloat(f) }
      if let p = g["focalPoint"] as? [String: Any], let x = MapboxJSON.double(p["x"]), let y = MapboxJSON.double(p["y"]) {
        o.focalPoint = CGPoint(x: x, y: y)
      } else {
        o.focalPoint = nil
      }
    }
    mapView.gestures.options = o
  }

  private static func ornamentPosition(_ value: Any?) -> OrnamentPosition? {
    switch value as? String {
    case "top-left": return .topLeft
    case "top-right": return .topRight
    case "bottom-left": return .bottomLeft
    case "bottom-right": return .bottomRight
    default: return nil
    }
  }

  private static func margins(_ value: Any?) -> CGPoint? {
    guard let a = value as? [Any], a.count == 2, let x = MapboxJSON.double(a[0]), let y = MapboxJSON.double(a[1]) else { return nil }
    return CGPoint(x: x, y: y)
  }

  private static func visibility(_ value: Any?) -> OrnamentVisibility? {
    switch value as? String {
    case "adaptive": return .adaptive
    case "visible": return .visible
    case "hidden": return .hidden
    default: return nil
    }
  }

  static func visibility(_ v: MunimFeatureVisibility) -> OrnamentVisibility {
    switch v {
    case .adaptive: return .adaptive
    case .visible: return .visible
    case .hidden: return .hidden
    }
  }

  func applyOrnaments() {
    var o = mapView.ornaments.options
    o.compass.visibility = Self.visibility(compassVisibility)
    o.scaleBar.visibility = Self.visibility(scaleVisibility)
    if let all = mapboxOptions["ornaments"] as? [String: Any] {
      if let c = all["compass"] as? [String: Any] {
        if let p = Self.ornamentPosition(c["position"]) { o.compass.position = p }
        if let m = Self.margins(c["margins"]) { o.compass.margins = m }
        if let v = Self.visibility(c["visibility"]) { o.compass.visibility = v }
      }
      if let s = all["scaleBar"] as? [String: Any] {
        if let p = Self.ornamentPosition(s["position"]) { o.scaleBar.position = p }
        if let m = Self.margins(s["margins"]) { o.scaleBar.margins = m }
        if let v = Self.visibility(s["visibility"]) { o.scaleBar.visibility = v }
        switch s["units"] as? String {
        case "metric": o.scaleBar.units = .metric
        case "imperial": o.scaleBar.units = .imperial
        case "nautical": o.scaleBar.units = .nautical
        default: break
        }
      }
      if let l = all["logo"] as? [String: Any] {
        if let p = Self.ornamentPosition(l["position"]) { o.logo.position = p }
        if let m = Self.margins(l["margins"]) { o.logo.margins = m }
      }
      if let a = all["attributionButton"] as? [String: Any] {
        if let p = Self.ornamentPosition(a["position"]) { o.attributionButton.position = p }
        if let m = Self.margins(a["margins"]) { o.attributionButton.margins = m }
        if let t = MapboxJSON.color(a["tintColor"]) { o.attributionButton.tintColor = t }
      }
    }
    mapView.ornaments.options = o
  }

  func applyCameraBounds() {
    var options = CameraBoundsOptions()
    if let range = cameraDistanceRange {
      let latitude = mapboxMap.cameraState.center.latitude
      if range.lowerBound > 0 { options.maxZoom = zoom(distance: range.lowerBound, latitude: latitude) }
      if range.upperBound < .greatestFiniteMagnitude {
        options.minZoom = max(0, zoom(distance: range.upperBound, latitude: latitude))
      }
    }
    if let region = cameraBoundary {
      options.bounds = CoordinateBounds(
        southwest: CLLocationCoordinate2D(
          latitude: region.center.latitude - region.span.latitudeDelta / 2,
          longitude: region.center.longitude - region.span.longitudeDelta / 2),
        northeast: CLLocationCoordinate2D(
          latitude: region.center.latitude + region.span.latitudeDelta / 2,
          longitude: region.center.longitude + region.span.longitudeDelta / 2))
    }
    if let b = mapboxOptions["cameraBounds"] as? [String: Any] {
      if let bounds = b["bounds"] as? [String: Any],
         let sw = MapboxJSON.coordinate(bounds["southwest"]), let ne = MapboxJSON.coordinate(bounds["northeast"]) {
        options.bounds = CoordinateBounds(southwest: sw, northeast: ne)
      }
      if let v = MapboxJSON.double(b["minZoom"]) { options.minZoom = v }
      if let v = MapboxJSON.double(b["maxZoom"]) { options.maxZoom = v }
      if let v = MapboxJSON.double(b["minPitch"]) { options.minPitch = CGFloat(v) }
      if let v = MapboxJSON.double(b["maxPitch"]) { options.maxPitch = CGFloat(v) }
    }
    if options.maxPitch == nil { options.maxPitch = 85 }
    do {
      try mapboxMap.setCameraBounds(with: options)
    } catch {
      onError?("Mapbox: camera bounds: \(error.localizedDescription)")
    }
  }

  private func applyRendering() {
    let r = mapboxOptions["rendering"] as? [String: Any] ?? [:]
    if let fps = MapboxJSON.double(r["preferredFramesPerSecond"]) {
      mapView.preferredFrameRateRange = CAFrameRateRange(minimum: 1, maximum: Float(fps), preferred: Float(fps))
    }
    if let delta = MapboxJSON.double(r["prefetchZoomDelta"]) { mapboxMap.prefetchZoomDelta = UInt8(max(0, min(255, delta))) }
    if let megabytes = MapboxJSON.double(r["tileCacheBudgetMegabytes"]) {
      mapboxMap.setTileCacheBudget(size: .megabytes(Int(max(0, megabytes))))
    }
    if let flag = MapboxJSON.bool(r["presentsWithTransaction"]) { mapView.presentationTransactionMode = flag ? .sync : .async }
    if let duration = MapboxJSON.double(r["transitionDuration"]) {
      mapboxMap.styleTransition = TransitionOptions(
        duration: duration / 1000, delay: (MapboxJSON.double(r["transitionDelay"]) ?? 0) / 1000, enablePlacementTransitions: true)
    }
    if let mode = r["northOrientation"] as? String {
      let value: NorthOrientation = mode == "rightwards" ? .rightwards : mode == "downwards" ? .downwards
        : mode == "leftwards" ? .leftwards : .upwards
      mapboxMap.setNorthOrientation(value)
    }
    if let mode = r["constrainMode"] as? String {
      mapboxMap.setConstrainMode(mode == "none" ? .none : mode == "widthAndHeight" ? .widthAndHeight : .heightOnly)
    }
    if let mode = r["viewportMode"] as? String {
      mapboxMap.setViewportMode(mode == "flippedY" ? .flippedY : .default)
    }
    let debug = (mapboxOptions["debug"] as? [String] ?? []).compactMap(Self.debugOption)
    mapView.debugOptions = MapViewDebugOptions(debug)
  }

  private static func debugOption(_ name: String) -> MapViewDebugOptions? {
    switch name {
    case "tileBorders": return .tileBorders
    case "parseStatus": return .parseStatus
    case "timestamps": return .timestamps
    case "collision": return .collision
    case "overdraw": return .overdraw
    case "stencilClip": return .stencilClip
    case "depthBuffer": return .depthBuffer
    case "modelBounds": return .modelBounds
    // terrainWireframe, layers2DWireframe, layers3DWireframe: Android only
    // (the iOS SDK's MapViewDebugOptions does not offer them).
    case "light": return .light
    case "camera": return .camera
    case "padding": return .padding
    default: return nil
    }
  }

  // MARK: Location puck and tracking

  func applyLocation() {
    guard showsUserLocation || userTrackingMode != .none else {
      mapView.location.options = LocationOptions(puckType: nil)
      return
    }
    let p = mapboxOptions["puck"] as? [String: Any] ?? [:]
    let bearingName = p["bearing"] as? String ?? (userTrackingMode == .followWithHeading ? "heading" : "none")
    let bearing: PuckBearing = bearingName == "course" ? .course : .heading
    let puckType: PuckType?
    switch p["type"] as? String {
    case "none":
      puckType = nil
    case "3d":
      guard let uri = p["modelUri"] as? String, let url = MapboxImages.url(for: uri) else {
        onError?("Mapbox: a 3D puck needs puck.modelUri")
        puckType = .puck2D(.makeDefault(showBearing: bearingName != "none"))
        break
      }
      var config = Puck3DConfiguration(model: Model(id: "munim-puck", uri: url))
      if let v = p["modelScale"] as? [Double] { config.modelScale = .constant(v) }
      if let v = p["modelRotation"] as? [Double] { config.modelRotation = .constant(v) }
      if let v = MapboxJSON.double(p["modelOpacity"]) { config.modelOpacity = .constant(v) }
      if let v = MapboxJSON.bool(p["modelCastShadows"]) { config.modelCastShadows = .constant(v) }
      if let v = MapboxJSON.bool(p["modelReceiveShadows"]) { config.modelReceiveShadows = .constant(v) }
      if let v = p["modelScaleMode"] as? String { config.modelScaleMode = .constant(v == "map" ? .map : .viewport) }
      if let v = MapboxJSON.double(p["modelEmissiveStrength"]) { config.modelEmissiveStrength = .constant(v) }
      if let v = p["modelElevationReference"] as? String {
        config.modelElevationReference = .constant(v == "sea" ? .sea : .ground)
      }
      if let t = p["modelTranslation"] as? [Double], t.count == 3 {
        config.model.position = [t[0], t[1]]
      }
      puckType = .puck3D(config)
    default:
      var config = Puck2DConfiguration.makeDefault(showBearing: bearingName != "none")
      if let uri = p["topImage"] as? String { config.topImage = MapboxImages.loadSync(uri) ?? config.topImage }
      if let uri = p["bearingImage"] as? String { config.bearingImage = MapboxImages.loadSync(uri) ?? config.bearingImage }
      if let uri = p["shadowImage"] as? String { config.shadowImage = MapboxImages.loadSync(uri) ?? config.shadowImage }
      if let v = MapboxJSON.double(p["scale"]) { config.scale = .constant(v) }
      if let v = MapboxJSON.bool(p["showsAccuracyRing"]) { config.showsAccuracyRing = v }
      if let c = MapboxJSON.color(p["accuracyRingColor"]) { config.accuracyRingColor = c }
      if let c = MapboxJSON.color(p["accuracyRingBorderColor"]) { config.accuracyRingBorderColor = c }
      if let v = MapboxJSON.double(p["opacity"]) { config.opacity = v }
      if let pulse = p["pulsing"] as? [String: Any] {
        var pulsing = Puck2DConfiguration.Pulsing()
        pulsing.isEnabled = MapboxJSON.bool(pulse["enabled"]) ?? true
        if let c = MapboxJSON.color(pulse["color"]) { pulsing.color = c }
        if pulse["radius"] as? String == "accuracy" {
          pulsing.radius = .accuracy
        } else if let r = MapboxJSON.double(pulse["radius"]) {
          pulsing.radius = .constant(r)
        }
        config.pulsing = pulsing
      }
      puckType = .puck2D(config)
    }
    mapView.location.options = LocationOptions(
      puckType: showsUserLocation || userTrackingMode != .none ? puckType : nil,
      puckBearing: bearing,
      puckBearingEnabled: bearingName != "none")
  }

  /// `follow` and `followWithHeading` are Mapbox's follow-puck viewport.
  func applyTrackingMode() {
    applyLocation()
    updateTrackingButton()
    switch userTrackingMode {
    case .none:
      if case .idle = mapView.viewport.status {} else { mapView.viewport.idle() }
    case .follow, .followWithHeading:
      let state = mapboxMap.cameraState
      let follow = mapView.viewport.makeFollowPuckViewportState(options: FollowPuckViewportStateOptions(
        padding: mapPadding,
        zoom: max(state.zoom, 15),
        bearing: userTrackingMode == .followWithHeading ? .heading : .constant(state.bearing),
        pitch: state.pitch))
      mapView.viewport.transition(to: follow)
    @unknown default:
      break
    }
  }

  // MARK: Events

  /// Subscribes to the Mapbox events listed in `mapbox.events`.
  func applyEvents() {
    let wanted = Set(mapboxOptions["events"] as? [String] ?? [])
    for name in eventCancelables.keys where !wanted.contains(name) {
      eventCancelables[name]?.cancel()
      eventCancelables[name] = nil
    }
    func interval(_ i: EventTimeInterval) -> [String: Any] {
      ["begin": i.begin.timeIntervalSince1970 * 1000, "end": i.end.timeIntervalSince1970 * 1000]
    }
    func tile(_ t: CanonicalTileID?) -> Any {
      guard let t else { return NSNull() }
      return ["z": Int(t.z), "x": Int(t.x), "y": Int(t.y)]
    }
    for name in wanted where eventCancelables[name] == nil {
      let send: (Any) -> Void = { [weak self] payload in self?.emit(name, payload) }
      let cancelable: AnyCancelable?
      switch name {
      case "mapLoaded":
        cancelable = mapboxMap.onMapLoaded.observe { send(["timeInterval": interval($0.timeInterval)]) }
      case "mapIdle":
        cancelable = mapboxMap.onMapIdle.observe { send(["timestamp": $0.timestamp.timeIntervalSince1970 * 1000]) }
      case "mapLoadingError":
        cancelable = mapboxMap.onMapLoadingError.observe { e in
          send(["type": ["style", "sprite", "source", "glyphs", "tile"][safe: e.type.rawValue] ?? "unknown",
                "message": e.message, "sourceId": e.sourceId ?? NSNull(), "tileId": tile(e.tileId)])
        }
      case "styleLoaded":
        cancelable = mapboxMap.onStyleLoaded.observe { send(["timeInterval": interval($0.timeInterval)]) }
      case "styleDataLoaded":
        cancelable = mapboxMap.onStyleDataLoaded.observe { e in
          send(["type": ["style", "sprite", "sources"][safe: e.type.rawValue] ?? "unknown",
                "timeInterval": interval(e.timeInterval)])
        }
      case "styleImageMissing":
        cancelable = mapboxMap.onStyleImageMissing.observe { send(["imageId": $0.imageId]) }
      case "styleImageRemoveUnused":
        cancelable = mapboxMap.onStyleImageRemoveUnused.observe { send(["imageId": $0.imageId]) }
      case "sourceDataLoaded":
        cancelable = mapboxMap.onSourceDataLoaded.observe { e in
          send(["sourceId": e.sourceId, "type": ["metadata", "tile"][safe: e.type.rawValue] ?? "unknown",
                "loaded": e.loaded ?? NSNull(), "tileId": tile(e.tileId), "dataId": e.dataId ?? NSNull()])
        }
      case "sourceAdded":
        cancelable = mapboxMap.onSourceAdded.observe { send(["sourceId": $0.sourceId]) }
      case "sourceRemoved":
        cancelable = mapboxMap.onSourceRemoved.observe { send(["sourceId": $0.sourceId]) }
      case "cameraChanged":
        cancelable = mapboxMap.onCameraChanged.observe { [weak self] _ in
          guard let self else { return }
          send(MapboxCalls.cameraStateJSON(self.mapboxMap.cameraState))
        }
      case "renderFrameStarted":
        cancelable = mapboxMap.onRenderFrameStarted.observe { send(["timestamp": $0.timestamp.timeIntervalSince1970 * 1000]) }
      case "renderFrameFinished":
        cancelable = mapboxMap.onRenderFrameFinished.observe { e in
          send(["renderMode": e.renderMode == .full ? "full" : "partial",
                "needsRepaint": e.needsRepaint, "placementChanged": e.placementChanged])
        }
      case "resourceRequest":
        cancelable = mapboxMap.onResourceRequest.observe { e in
          send(["url": e.request.url, "cancelled": e.cancelled,
                "source": ["asset", "database", "fileSystem", "network", "resourceLoader"][safe: e.source.rawValue] ?? "unknown",
                "size": e.response.map { Double($0.size) } ?? NSNull(),
                "timeInterval": interval(e.timeInterval)])
        }
      default:
        cancelable = nil
        onError?("Mapbox: unknown event \(name)")
      }
      if let cancelable { eventCancelables[name] = cancelable }
    }
  }
}

extension Array {
  subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// `optional ?? NSNull()` for JSON payloads.
func ?? <T>(lhs: T?, rhs: @autoclosure () -> NSNull) -> Any {
  if let value = lhs { return value }
  return rhs()
}
#endif
