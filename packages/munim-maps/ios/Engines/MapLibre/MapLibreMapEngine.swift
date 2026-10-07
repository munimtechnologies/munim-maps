#if canImport(MapLibre)
import MapKit
import MapLibre
import UIKit

enum MapLibreMapEngineFactory: MunimMapEngineFactory {
  static let isImplemented = true
  static func make() -> MunimMapEngine { MapLibreMapEngine() }
}

/// The MapLibre engine on iOS: MapLibre Native's `MLNMapView` with an
/// OpenFreeMap style by default (OpenStreetMap data, no key), munim-maps'
/// markers and shapes as style layers (`MapLibreFeatures`), the whole
/// style spec at runtime (`MapLibreStyleSpec`), offline packs
/// (`MapLibreOffline`) and the SceneKit 3D layer over it, driven by
/// MapLibre's camera.
///
/// MapLibre-only options arrive as `providerOptions` (`maplibre={{…}}` in
/// JavaScript, `MapLibreMapOptions` in src/providers/maplibre.ts) and
/// commands through `providerCommand`; the list is in docs/providers.md.
final class MapLibreMapEngine: UIView, MunimMapEngine, MunimMapEngineDefaults, MLNMapViewDelegate, UIGestureRecognizerDelegate {
  let provider = MunimMapProvider.maplibre
  var view: UIView { self }
  let modelLayer = MunimModelLayer()

  fileprivate let mapView: MLNMapView
  private lazy var cameraSource = MapLibreCameraSource(self)
  private let features = MapLibreFeatures()
  private let trackingButton = UIButton(type: .system)
  fileprivate var styleLoaded = false
  private var readySent = false
  private var appliedInitialCamera = false
  private var loadedStyleKey = ""
  private var userSources: [String] = []
  private var userLayers: [String] = []
  private var appliedRuntimeKey = ""
  private var originalPoiPredicates: [String: NSPredicate?] = [:]
  private var options: [String: Any] = [:]

  // MARK: Events

  var onMapReady: (() -> Void)?
  var onPress: ((CLLocationCoordinate2D, CGPoint) -> Void)?
  var onLongPress: ((CLLocationCoordinate2D, CGPoint) -> Void)?
  var onCameraMove: ((MunimCamera) -> Void)?
  var onCameraChange: ((MunimCamera) -> Void)?
  var onMarkerPress: ((String) -> Void)?
  var onMarkerDeselect: ((String) -> Void)?
  var onCalloutPress: ((String) -> Void)?
  var onCalloutAccessoryPress: ((String, String) -> Void)?
  var onClusterPress: ((String, [String], CLLocationCoordinate2D) -> Void)?
  var onOverlayPress: ((String, String, CLLocationCoordinate2D) -> Void)?
  var onMarkerDragStart: ((String, CLLocationCoordinate2D) -> Void)?
  var onMarkerDragEnd: ((String, CLLocationCoordinate2D) -> Void)?
  /// Each move while a marker is dragged (for a shared `onMarkerDrag` event).
  var onMarkerDrag: ((String, CLLocationCoordinate2D) -> Void)?
  var onUserLocationChange: ((CLLocation) -> Void)?
  var onMapFeaturePress: ((MunimMapFeature) -> Void)?
  var onUserTrackingModeChange: ((MKUserTrackingMode) -> Void)?
  var onError: ((String) -> Void)?
  /// Engine-only events (`onProviderEvent`): a name and a JSON payload.
  private var onProviderEvent: ((String, String) -> Void)?

  func setProviderEventHandler(_ handler: ((String, Any) -> Void)?) {
    guard let handler else { onProviderEvent = nil; return }
    onProviderEvent = { name, json in
      let data = (try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])) ?? NSNull()
      handler(name, data)
    }
  }

  init() {
    mapView = MLNMapView(frame: .zero, styleURL: nil)
    super.init(frame: .zero)
    mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    mapView.delegate = self
    mapView.maximumPitch = 85
    mapView.showsScale = false
    mapView.logoView.isHidden = true
    mapView.showsLogoView = false
    addSubview(mapView)
    modelLayer.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(modelLayer.view)
    modelLayer.onError = { [weak self] in self?.onError?($0) }
    modelLayer.attach(to: cameraSource)
    wireFeatures()
    addGestures()
    trackingButton.setImage(UIImage(systemName: "location"), for: .normal)
    trackingButton.backgroundColor = .systemBackground
    trackingButton.layer.cornerRadius = 10
    trackingButton.layer.shadowOpacity = 0.15
    trackingButton.layer.shadowRadius = 4
    trackingButton.isHidden = true
    trackingButton.addTarget(self, action: #selector(cycleTracking), for: .touchUpInside)
    addSubview(trackingButton)
    MapLibreOffline.shared.add(sink: self) { [weak self] name, payload in
      DispatchQueue.main.async { self?.onProviderEvent?(name, payload) }
    }
    loadStyle(force: true)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  deinit {
    MapLibreOffline.shared.remove(sink: self)
    flightLink?.invalidate()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    mapView.frame = bounds
    modelLayer.view.frame = bounds
    trackingButton.frame = CGRect(x: bounds.width - 56, y: bounds.height - 96, width: 44, height: 44)
    applyInitialCameraIfReady()
    features.positionCallout()
  }

  private func wireFeatures() {
    features.mapView = mapView
    features.onError = { [weak self] in self?.onError?($0) }
    features.onMarkerPress = { [weak self] in self?.onMarkerPress?($0) }
    features.onMarkerDeselect = { [weak self] in self?.onMarkerDeselect?($0) }
    features.onCalloutPress = { [weak self] in self?.onCalloutPress?($0) }
    features.onCalloutAccessoryPress = { [weak self] in self?.onCalloutAccessoryPress?($0, $1) }
    features.onClusterPress = { [weak self] in self?.onClusterPress?($0, $1, $2) }
    features.onMarkerDragStart = { [weak self] in self?.onMarkerDragStart?($0, $1) }
    features.onMarkerDragEnd = { [weak self] in self?.onMarkerDragEnd?($0, $1) }
    features.onMarkerDrag = { [weak self] in self?.onMarkerDrag?($0, $1) }
  }

  private func event(_ name: String, _ payload: [String: Any] = [:]) {
    guard let onProviderEvent else { return }
    let json = (try? JSONSerialization.data(withJSONObject: payload)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    onProviderEvent(name, json)
  }

  // MARK: Gestures

  private func addGestures() {
    let tap = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
    tap.delegate = self
    for recognizer in mapView.gestureRecognizers ?? [] {
      if let other = recognizer as? UITapGestureRecognizer, other.numberOfTapsRequired == 2 {
        tap.require(toFail: other)
      }
    }
    mapView.addGestureRecognizer(tap)
    let press = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
    press.delegate = self
    mapView.addGestureRecognizer(press)
  }

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    !(gestureRecognizer is UILongPressGestureRecognizer && features.isDragging)
  }

  @objc private func tapped(_ gesture: UITapGestureRecognizer) {
    let point = gesture.location(in: mapView)
    if let id = modelLayer.modelHit(at: point) {
      modelLayer.onModelPress?(id)
      return
    }
    if features.handleTap(at: point) { return }
    let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
    if onOverlayPress != nil, let hit = features.overlay(at: point) {
      onOverlayPress?(hit.id, hit.kind, coordinate)
      return
    }
    if mapFeatureTap(at: point) { return }
    onPress?(coordinate, point)
  }

  private var scrollWasEnabled = true

  @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
    if gesture.state == .began {
      scrollWasEnabled = mapView.isScrollEnabled
    }
    if features.handleLongPress(gesture) {
      mapView.isScrollEnabled = !features.isDragging && scrollWasEnabled
      if !features.isDragging { mapView.isScrollEnabled = scrollWasEnabled }
      return
    }
    if gesture.state == .began {
      let point = gesture.location(in: mapView)
      onLongPress?(mapView.convert(point, toCoordinateFrom: mapView), point)
    }
  }

  /// A tap on a place of the base map (OpenMapTiles layers).
  private func mapFeatureTap(at point: CGPoint) -> Bool {
    guard !selectableFeatures.isEmpty, let style = mapView.style else { return false }
    let kinds: [String: String] = [
      "poi": "pointOfInterest", "place": "territory", "water_name": "physicalFeature",
      "mountain_peak": "physicalFeature", "park": "physicalFeature",
    ]
    func wanted(_ kind: String) -> Bool {
      (kind == "pointOfInterest" && selectableFeatures.contains(.pointsOfInterest))
        || (kind == "territory" && selectableFeatures.contains(.territories))
        || (kind == "physicalFeature" && selectableFeatures.contains(.physicalFeatures))
    }
    var layerKinds: [String: String] = [:]
    for layer in style.layers {
      guard let symbol = layer as? MLNSymbolStyleLayer, let sourceLayer = symbol.sourceLayerIdentifier,
            let kind = kinds[sourceLayer], wanted(kind) else { continue }
      layerKinds[symbol.identifier] = kind
    }
    guard !layerKinds.isEmpty else { return false }
    let rect = CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)
    for (layerId, kind) in layerKinds {
      guard let hit = mapView.visibleFeatures(in: rect, styleLayerIdentifiers: [layerId]).first else { continue }
      let name = hit.attribute(forKey: "name") as? String ?? hit.attribute(forKey: "name_en") as? String ?? ""
      let id = hit.identifier.map { "\($0)" } ?? "\(layerId):\(name)"
      onMapFeaturePress?(MunimMapFeature(
        title: name, coordinate: hit.coordinate, kind: kind,
        category: hit.attribute(forKey: "class") as? String ?? "", id: id))
      return true
    }
    return false
  }

  // MARK: Style

  private static let presets: [String: String] = [
    "liberty": "https://tiles.openfreemap.org/styles/liberty",
    "bright": "https://tiles.openfreemap.org/styles/bright",
    "positron": "https://tiles.openfreemap.org/styles/positron",
    "dark": "https://tiles.openfreemap.org/styles/dark",
    "fiord": "https://tiles.openfreemap.org/styles/fiord",
    "demotiles": "https://demotiles.maplibre.org/style.json",
    "maptiler-streets": "https://api.maptiler.com/maps/streets-v2/style.json?key={key}",
    "maptiler-outdoor": "https://api.maptiler.com/maps/outdoor-v2/style.json?key={key}",
    "maptiler-satellite": "https://api.maptiler.com/maps/satellite/style.json?key={key}",
    "maptiler-hybrid": "https://api.maptiler.com/maps/hybrid/style.json?key={key}",
    "maptiler-dataviz": "https://api.maptiler.com/maps/dataviz/style.json?key={key}",
    "stadia-alidade-smooth": "https://tiles.stadiamaps.com/styles/alidade_smooth.json?api_key={key}",
    "stadia-alidade-smooth-dark": "https://tiles.stadiamaps.com/styles/alidade_smooth_dark.json?api_key={key}",
    "stadia-outdoors": "https://tiles.stadiamaps.com/styles/outdoors.json?api_key={key}",
    "stadia-osm-bright": "https://tiles.stadiamaps.com/styles/osm_bright.json?api_key={key}",
  ]

  private func string(_ key: String) -> String { options[key] as? String ?? "" }

  private func preset(_ name: String) -> String? {
    guard !name.isEmpty else { return nil }
    guard let url = Self.presets[name] else { return name.contains("://") ? name : nil }
    if url.contains("{key}") {
      let key = string("apiKey")
      guard !key.isEmpty else {
        onError?("MapLibre: the '\(name)' style needs maplibre.apiKey")
        return nil
      }
      return url.replacingOccurrences(of: "{key}", with: key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key)
    }
    return url
  }

  fileprivate var isDark: Bool {
    switch colorScheme {
    case .dark: return true
    case .light: return false
    default: return traitCollection.userInterfaceStyle == .dark
    }
  }

  /// The style to show: JSON, URL, preset, dark, muted.
  private func resolveStyle() -> (key: String, url: URL?, json: String?) {
    if let json = options["styleJson"], !(json is NSNull) {
      let text: String
      if let s = json as? String {
        text = s
      } else {
        text = (try? JSONSerialization.data(withJSONObject: json)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
      }
      return ("json:\(text.hashValue)", nil, text)
    }
    let explicit = styleURL.isEmpty ? (preset(string("style")) ?? "") : styleURL
    let wantsDark = isDark && styleURL.isEmpty && (string("style").isEmpty || !string("darkStyle").isEmpty)
    let url: String
    if wantsDark {
      url = preset(string("darkStyle").isEmpty ? "dark" : string("darkStyle")) ?? explicit
    } else if !explicit.isEmpty {
      url = explicit
    } else if mapStyle == .muted {
      url = Self.presets["positron"]!
    } else {
      url = MunimMapsConfiguration.shared.maplibreStyleURL
    }
    return (url, URL(string: url), nil)
  }

  private func loadStyle(force: Bool = false) {
    let resolved = resolveStyle()
    if !force && resolved.key == loadedStyleKey && styleLoaded { return }
    loadedStyleKey = resolved.key
    styleLoaded = false
    if let json = resolved.json {
      mapView.styleJSON = json
    } else {
      mapView.styleURL = resolved.url
    }
  }

  func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
    styleLoaded = true
    originalPoiPredicates.removeAll()
    userSources.removeAll()
    userLayers.removeAll()
    applyImagery(style)
    applyRuntimeStyle(style)
    applyBuildings()
    applyPointsOfInterest()
    applyLabelLanguage(style)
    features.restore(style)
    if let placement = options["placementTransitions"] as? Bool { style.performsPlacementTransitions = placement }
    modelLayer.setNeedsRender()
    event("styleLoaded", ["style": loadedStyleKey])
    if !readySent {
      readySent = true
      onMapReady?()
    }
  }

  func mapViewDidFailLoadingMap(_ mapView: MLNMapView, withError error: Error) {
    onError?("MapLibre: the map failed to load: \(error.localizedDescription)")
    event("mapLoadFailed", ["message": error.localizedDescription])
  }

  /// `mapStyle` imagery / hybrid: satellite tiles from `maplibre.satelliteTilesUrl`.
  private func applyImagery(_ style: MLNStyle) {
    guard mapStyle == .imagery || mapStyle == .hybrid else { return }
    let tiles = string("satelliteTilesUrl")
    guard !tiles.isEmpty else {
      onError?("MapLibre: mapStyle '\(mapStyle.rawValue)' needs maplibre.satelliteTilesUrl (there is no keyless satellite imagery)")
      return
    }
    let source = MLNRasterTileSource(identifier: "munim-imagery", tileURLTemplates: [tiles], options: [.tileSize: 256])
    style.addSource(source)
    let layer = MLNRasterStyleLayer(identifier: "munim-imagery", source: source)
    if mapStyle == .imagery {
      for l in style.layers { l.isVisible = false }
      style.addLayer(layer)
    } else {
      if let first = style.layers.first(where: { $0 is MLNLineStyleLayer || $0 is MLNSymbolStyleLayer }) {
        style.insertLayer(layer, below: first)
      } else {
        style.addLayer(layer)
      }
      for l in style.layers where l is MLNFillStyleLayer || l is MLNFillExtrusionStyleLayer { l.isVisible = false }
    }
  }

  private func runtimeKey() -> String {
    ["sources", "layers", "images", "light", "transition", "hillshade", "colorRelief"].map { key in
      guard let value = options[key] else { return "" }
      return (try? JSONSerialization.data(withJSONObject: ["v": value], options: [.sortedKeys]))
        .flatMap { String(data: $0, encoding: .utf8) } ?? "\(value)"
    }.joined(separator: "|")
  }

  /// `maplibre.sources`, `layers`, `images`, `light`, `transition`, `hillshade`, `colorRelief`.
  private func applyRuntimeStyle(_ style: MLNStyle) {
    appliedRuntimeKey = runtimeKey()
    for id in userLayers { if let layer = style.layer(withIdentifier: id) { style.removeLayer(layer) } }
    for id in userSources { if let source = style.source(withIdentifier: id) { style.removeSource(source) } }
    userLayers.removeAll()
    userSources.removeAll()
    if let t = options["transition"] as? [String: Any] {
      style.transition = MLNTransition(
        duration: ((t["duration"] as? NSNumber)?.doubleValue ?? 300) / 1000,
        delay: ((t["delay"] as? NSNumber)?.doubleValue ?? 0) / 1000)
    }
    if let light = options["light"] as? [String: Any] { applyLight(style, light) }
    if let images = options["images"] as? [String: Any] {
      for (name, value) in images {
        let uri = (value as? [String: Any])?["uri"] as? String ?? value as? String ?? ""
        let sdf = (value as? [String: Any])?["sdf"] as? Bool ?? false
        loadStyleImage(name, uri: uri, sdf: sdf)
      }
    }
    if let sources = options["sources"] as? [String: Any] {
      for (id, value) in sources {
        guard let json = value as? [String: Any] else { continue }
        do {
          if let existing = style.source(withIdentifier: id) { style.removeSource(existing) }
          style.addSource(try MapLibreStyleSpec.source(id: id, json))
          userSources.append(id)
        } catch {
          onError?("MapLibre: source '\(id)': \(error.localizedDescription)")
        }
      }
    }
    hillshade(style, below: firstRoadLayer(style))
    for json in options["layers"] as? [[String: Any]] ?? [] {
      do {
        let layer = try MapLibreStyleSpec.layer(json, in: style)
        if let existing = style.layer(withIdentifier: layer.identifier) { style.removeLayer(existing) }
        MapLibreStyleSpec.add(layer, to: style, below: json["beforeId"] as? String, fallback: MapLibreFeatures.slotUser)
        userLayers.append(layer.identifier)
      } catch {
        onError?("MapLibre: layer '\(json["id"] ?? "")': \(error.localizedDescription)")
      }
    }
  }

  private func applyLight(_ style: MLNStyle, _ json: [String: Any]) {
    let light = style.light
    if let anchor = json["anchor"] as? String { light.anchor = MapLibreStyleSpec.expression(anchor) }
    if let p = json["position"] as? [NSNumber], p.count == 3 {
      light.position = NSExpression(forConstantValue: NSValue(mlnSphericalPosition: MLNSphericalPositionMake(
        CGFloat(p[0].doubleValue), CLLocationDirection(p[1].doubleValue), CLLocationDirection(p[2].doubleValue))))
    }
    if let color = json["color"] as? String { light.color = NSExpression(forConstantValue: MapLibreMarkerArt.color(color, .white)) }
    if let intensity = json["intensity"] as? NSNumber { light.intensity = NSExpression(forConstantValue: intensity) }
    style.light = light
  }

  private func firstRoadLayer(_ style: MLNStyle) -> String? {
    let words = ["road", "highway", "street", "transport", "tunnel", "bridge", "aeroway", "rail"]
    return style.layers.first { layer in
      layer is MLNSymbolStyleLayer
        || (layer is MLNLineStyleLayer && words.contains { layer.identifier.lowercased().contains($0) })
    }?.identifier
  }

  private static let terrariumTiles = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"

  private func demSource(_ style: MLNStyle, id: String, _ json: [String: Any]?) -> MLNSource {
    if let existing = style.source(withIdentifier: id) { return existing }
    let tiles = json?["tiles"] as? [String] ?? [Self.terrariumTiles]
    let encoding: MLNDEMEncoding = (json?["encoding"] as? String) == "mapbox" ? .mapbox : .terrarium
    let source = MLNRasterDEMSource(identifier: id, tileURLTemplates: tiles, options: [
      .tileSize: 256, .maximumZoomLevel: 15, .demEncoding: NSNumber(value: encoding.rawValue),
    ])
    style.addSource(source)
    userSources.append(id)
    return source
  }

  private func hillshade(_ style: MLNStyle, below: String?) {
    let shade = options["hillshade"]
    if (shade as? Bool) == true || shade is [String: Any] {
      let json = shade as? [String: Any]
      let layer = MLNHillshadeStyleLayer(identifier: "munim-hillshade", source: demSource(style, id: "munim-dem", json))
      var props: [String: Any] = [:]
      if let v = json?["exaggeration"] { props["hillshade-exaggeration"] = v }
      if let v = json?["shadowColor"] { props["hillshade-shadow-color"] = v }
      if let v = json?["highlightColor"] { props["hillshade-highlight-color"] = v }
      if let v = json?["accentColor"] { props["hillshade-accent-color"] = v }
      if let v = json?["illuminationDirection"] { props["hillshade-illumination-direction"] = v }
      try? MapLibreStyleSpec.setProperties(layer, props)
      MapLibreStyleSpec.add(layer, to: style, below: json?["beforeId"] as? String, fallback: below ?? MapLibreFeatures.slotUser)
      userLayers.append(layer.identifier)
    }
    let relief = options["colorRelief"]
    if (relief as? Bool) == true || relief is [String: Any] {
      let json = relief as? [String: Any]
      let layer = MLNColorReliefStyleLayer(identifier: "munim-color-relief", source: demSource(style, id: "munim-dem-relief", json))
      let stops = json?["stops"] as? [Any] ?? [0, "#2f6b3a", 500, "#9cba6a", 1500, "#e2c98f", 2500, "#a87c56", 4000, "#ffffff"]
      try? MapLibreStyleSpec.setProperties(layer, [
        "color-relief-color": ["interpolate", ["linear"], ["elevation"]] + stops,
        "color-relief-opacity": json?["opacity"] ?? 0.6,
      ])
      MapLibreStyleSpec.add(layer, to: style, below: json?["beforeId"] as? String, fallback: below ?? MapLibreFeatures.slotUser)
      userLayers.append(layer.identifier)
    }
  }

  private func loadStyleImage(_ name: String, uri: String, sdf: Bool) {
    let url = uri.hasPrefix("/") ? URL(fileURLWithPath: uri) : URL(string: uri)
    guard let url else { return }
    URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
      let image = data.flatMap { UIImage(data: $0) }
      DispatchQueue.main.async {
        guard let self else { return }
        guard let image else {
          self.onError?("MapLibre: image '\(name)': \(error?.localizedDescription ?? "not an image")")
          return
        }
        self.mapView.style?.setImage(sdf ? image.withRenderingMode(.alwaysTemplate) : image, forName: name)
      }
    }.resume()
  }

  private func layers(ofSourceLayer name: String) -> [MLNVectorStyleLayer] {
    (mapView.style?.layers ?? []).compactMap { $0 as? MLNVectorStyleLayer }.filter { $0.sourceLayerIdentifier == name }
  }

  private func applyBuildings() {
    for layer in layers(ofSourceLayer: "building") { layer.isVisible = showsBuildings }
  }

  private func applyPointsOfInterest() {
    for layer in layers(ofSourceLayer: "poi") {
      if originalPoiPredicates[layer.identifier] == nil { originalPoiPredicates[layer.identifier] = .some(layer.predicate) }
      let original = originalPoiPredicates[layer.identifier] ?? nil
      if pointOfInterestFilter == .includingAll {
        layer.isVisible = true
        layer.predicate = original
      } else if pointOfInterestFilter == .excludingAll {
        layer.isVisible = false
      } else {
        let classes = Self.allCategories.filter { pointOfInterestFilter.includes($0) }.map(Self.className)
        let wanted = NSPredicate(mglJSONObject: ["match", ["get", "class"], classes.isEmpty ? ["none"] : classes, true, false])
        layer.isVisible = true
        layer.predicate = original.map { NSCompoundPredicate(andPredicateWithSubpredicates: [$0, wanted]) } ?? wanted
      }
    }
  }

  /// MapKit categories, for `pointsOfInterest` lists, mapped to OpenMapTiles `class` names.
  private static let allCategories: [MKPointOfInterestCategory] = [
    .airport, .amusementPark, .aquarium, .atm, .bakery, .bank, .beach, .brewery, .cafe, .campground, .carRental,
    .evCharger, .fireStation, .fitnessCenter, .foodMarket, .gasStation, .hospital, .hotel, .laundry, .library,
    .marina, .movieTheater, .museum, .nationalPark, .nightlife, .park, .parking, .pharmacy, .police, .postOffice,
    .publicTransport, .restaurant, .restroom, .school, .stadium, .store, .theater, .university, .winery, .zoo,
  ]

  private static func className(_ category: MKPointOfInterestCategory) -> String {
    switch category {
    case .atm: return "atm"
    case .cafe: return "cafe"
    case .evCharger: return "charging_station"
    case .fitnessCenter: return "fitness"
    case .foodMarket: return "grocery"
    case .gasStation: return "fuel"
    case .movieTheater: return "cinema"
    case .nationalPark: return "park"
    case .nightlife: return "bar"
    case .postOffice: return "post"
    case .publicTransport: return "bus"
    case .restroom: return "toilets"
    case .store: return "shop"
    case .university: return "college"
    default:
      let raw = category.rawValue.replacingOccurrences(of: "MKPOICategory", with: "")
      return raw.prefix(1).lowercased() + raw.dropFirst()
    }
  }

  private func applyLabelLanguage(_ style: MLNStyle) {
    let language = string("labelLanguage").trimmingCharacters(in: .whitespaces)
    guard !language.isEmpty else { return }
    let localized = NSExpression(mglJSONObject: ["coalesce", ["get", "name:\(language)"], ["get", "name_int"], ["get", "name"]])
    for layer in style.layers {
      guard let symbol = layer as? MLNSymbolStyleLayer, !symbol.identifier.hasPrefix("munim-"),
            let text = symbol.text, "\(text.mgl_jsonExpressionObject)".contains("name") else { continue }
      symbol.text = localized
    }
  }

  // MARK: Provider settings

  var styleURL = "" {
    didSet { if styleURL != oldValue { loadStyle() } }
  }

  var providerOptions: [String: Any] {
    get { options }
    set {
      let previous = options
      options = newValue
      func changed(_ key: String) -> Bool {
        "\(previous[key] ?? "")" != "\(newValue[key] ?? "")"
      }
      if (newValue["projection"] as? String) == "globe" {
        onError?("MapLibre: globe projection is not in MapLibre Native (only MapLibre GL JS); the map stays flat")
      }
      applyGlobalOptions(previous: previous)
      applyMapOptions()
      applyGestures()
      applyLimits()
      applyControls()
      if ["styleJson", "style", "darkStyle", "apiKey", "satelliteTilesUrl"].contains(where: changed) {
        loadStyle(force: changed("satelliteTilesUrl"))
      } else if let style = mapView.style, styleLoaded {
        if runtimeKey() != appliedRuntimeKey { applyRuntimeStyle(style) }
        if changed("labelLanguage") { loadStyle(force: true) }
        if let placement = options["placementTransitions"] as? Bool { style.performsPlacementTransitions = placement }
      }
      if showsUserLocation && changed("location") { mapView.updateUserLocationAnnotationView() }
    }
  }

  /// Process-wide settings: HTTP headers, log level.
  private func applyGlobalOptions(previous: [String: Any]) {
    let headers = options["httpHeaders"] as? [String: String]
    if "\(headers ?? [:])" != "\((previous["httpHeaders"] as? [String: String]) ?? [:])" {
      let configuration = URLSessionConfiguration.default
      configuration.httpAdditionalHeaders = headers
      MLNNetworkConfiguration.sharedManager.sessionConfiguration = configuration
    }
    let logging = MLNLoggingConfiguration.shared
    switch string("logLevel") {
    case "none": logging.loggingLevel = .none
    case "error": logging.loggingLevel = .error
    case "warning": logging.loggingLevel = .warning
    case "info": logging.loggingLevel = .info
    case "debug": logging.loggingLevel = .debug
    case "verbose": logging.loggingLevel = .verbose
    default: break
    }
  }

  private func applyMapOptions() {
    let r = options["rendering"] as? [String: Any] ?? [:]
    if let fps = r["maxFps"] as? NSNumber { mapView.preferredFramesPerSecond = MLNMapViewPreferredFramesPerSecond(rawValue: fps.intValue) }
    if let v = r["prefetchTiles"] as? Bool { mapView.prefetchesTiles = v }
    if let v = r["tileCache"] as? Bool { mapView.tileCacheEnabled = v }
    if let v = r["tileLodScale"] as? NSNumber { mapView.tileLodScale = v.doubleValue }
    if let v = r["tileLodMinRadius"] as? NSNumber { mapView.tileLodMinRadius = v.doubleValue }
    if let v = r["tileLodPitchThreshold"] as? NSNumber { mapView.tileLodPitchThreshold = v.doubleValue }
    if let v = r["tileLodZoomShift"] as? NSNumber { mapView.tileLodZoomShift = v.doubleValue }
    if let f = r["frustumOffset"] as? [String: Any] {
      func n(_ k: String) -> CGFloat { CGFloat((f[k] as? NSNumber)?.doubleValue ?? 0) }
      mapView.frustumOffset = UIEdgeInsets(top: n("top"), left: n("left"), bottom: n("bottom"), right: n("right"))
    }
    var mask: MLNMapDebugMaskOptions = []
    for option in r["debug"] as? [String] ?? [] {
      switch option {
      case "tileBoundaries": mask.insert(.tileBoundariesMask)
      case "tileInfo": mask.insert(.tileInfoMask)
      case "timestamps": mask.insert(.timestampsMask)
      case "collisionBoxes": mask.insert(.collisionBoxesMask)
      case "overdraw": mask.insert(.overdrawVisualizationMask)
      default: break
      }
    }
    mapView.debugMask = mask
    if let stats = r["renderingStats"] as? Bool { mapView.enableRenderingStatsView(stats) }
  }

  // MARK: 2D content

  var markers: [MunimMarker] {
    get { features.markers }
    set { features.setMarkers(newValue) }
  }
  var polylines: [MunimPolyline] {
    get { features.polylines }
    set { features.polylines = newValue }
  }
  var polygons: [MunimPolygon] {
    get { features.polygons }
    set { features.polygons = newValue }
  }
  var circles: [MunimCircle] {
    get { features.circles }
    set { features.circles = newValue }
  }
  var tileOverlays: [MunimTileOverlay] {
    get { features.tileOverlays }
    set { features.tileOverlays = newValue }
  }
  var clusterStyles: [MunimClusterStyle] {
    get { features.clusterStyles }
    set { features.clusterStyles = newValue }
  }
  func setViewMarker(_ marker: MunimMarker, image: UIImage?) { features.setViewMarker(marker, image: image) }
  func setViewMarkerImage(_ image: UIImage?, id: String) { features.setViewMarkerImage(image, id: id) }
  func removeViewMarker(_ id: String) { features.removeViewMarker(id) }
  func selectMarker(_ id: String) { features.select(id) }
  func deselectMarker(_ id: String) { features.deselect(id) }
  func overlayHit(at point: CGPoint) -> (id: String, kind: String)? { features.overlay(at: point) }

  // MARK: Look

  var initialCamera: MunimCamera? {
    didSet { applyInitialCameraIfReady() }
  }

  private func applyInitialCameraIfReady() {
    guard !appliedInitialCamera, let camera = initialCamera, bounds.height > 0 else { return }
    appliedInitialCamera = true
    setMapCamera(camera, duration: 0)
  }

  var mapStyle: MunimMapStyle = .standard {
    didSet { if mapStyle != oldValue { loadStyle(force: true) } }
  }

  var globe = false {
    didSet { if globe { onError?("MapLibre: globe projection is not in MapLibre Native (only MapLibre GL JS); the map stays flat") } }
  }

  var colorScheme: UIUserInterfaceStyle = .unspecified {
    didSet { if colorScheme != oldValue { loadStyle() } }
  }

  override func traitCollectionDidChange(_ previous: UITraitCollection?) {
    super.traitCollectionDidChange(previous)
    if colorScheme == .unspecified, previous?.userInterfaceStyle != traitCollection.userInterfaceStyle { loadStyle() }
  }

  var showsBuildings = true { didSet { applyBuildings() } }

  var showsTraffic = false {
    didSet {
      if showsTraffic { onError?("MapLibre: there is no traffic data in OpenStreetMap; showsTraffic needs a traffic tile source (maplibre.sources)") }
    }
  }

  var pointOfInterestFilter: MKPointOfInterestFilter = .includingAll { didSet { applyPointsOfInterest() } }

  var selectableFeatures: Set<MunimMapFeatureKind> = []

  var showsUserLocation = false {
    didSet { mapView.showsUserLocation = showsUserLocation }
  }

  func mapView(styleForDefaultUserLocationAnnotationView mapView: MLNMapView) -> MLNUserLocationAnnotationViewStyle {
    let style = MLNUserLocationAnnotationViewStyle()
    let o = options["location"] as? [String: Any] ?? [:]
    if let c = o["puckColor"] as? String {
      style.puckFillColor = MapLibreMarkerArt.color(c, .systemBlue)
      style.puckArrowFillColor = MapLibreMarkerArt.color(c, .systemBlue)
    }
    if let c = o["accuracyColor"] as? String {
      style.haloFillColor = MapLibreMarkerArt.color(c, .systemBlue)
      style.approximateHaloFillColor = MapLibreMarkerArt.color(c, .systemBlue)
    }
    return style
  }

  // MARK: Controls

  private func position(_ name: String?, _ fallback: MLNOrnamentPosition) -> MLNOrnamentPosition {
    switch name {
    case "topLeft": return .topLeft
    case "topRight": return .topRight
    case "bottomLeft": return .bottomLeft
    case "bottomRight": return .bottomRight
    default: return fallback
    }
  }

  private func margin(_ o: [String: Any]?, _ fallback: CGPoint) -> CGPoint {
    guard let m = o?["margin"] as? [String: Any] else { return fallback }
    return CGPoint(x: (m["x"] as? NSNumber)?.doubleValue ?? fallback.x, y: (m["y"] as? NSNumber)?.doubleValue ?? fallback.y)
  }

  var compassVisibility: MunimFeatureVisibility = .adaptive { didSet { applyControls() } }
  var scaleVisibility: MunimFeatureVisibility = .hidden { didSet { applyControls() } }
  var showsUserTrackingButton = false { didSet { trackingButton.isHidden = !showsUserTrackingButton } }

  private func applyControls() {
    let ornaments = options["ornaments"] as? [String: Any] ?? [:]
    let compass = ornaments["compass"] as? [String: Any]
    let compassOn = compass?["visible"] as? Bool ?? (compassVisibility != .hidden)
    mapView.showsCompassView = compassOn
    mapView.compassView.compassVisibility = !compassOn ? .hidden : (compassVisibility == .visible ? .visible : .adaptive)
    mapView.compassViewPosition = position(compass?["position"] as? String, .topRight)
    mapView.compassViewMargins = margin(compass, CGPoint(x: 8, y: 8))
    let scale = ornaments["scaleBar"] as? [String: Any]
    mapView.showsScale = scale?["visible"] as? Bool ?? (scaleVisibility != .hidden)
    mapView.scaleBarPosition = position(scale?["position"] as? String, .topLeft)
    mapView.scaleBarMargins = margin(scale, CGPoint(x: 8, y: 8))
    if let metric = scale?["metric"] as? Bool { mapView.scaleBarUsesMetricSystem = metric }
    let logo = ornaments["logo"] as? [String: Any]
    mapView.showsLogoView = logo?["visible"] as? Bool ?? false
    mapView.logoView.isHidden = !(logo?["visible"] as? Bool ?? false)
    mapView.logoViewPosition = position(logo?["position"] as? String, .bottomLeft)
    mapView.logoViewMargins = margin(logo, CGPoint(x: 8, y: 8))
    let attribution = ornaments["attribution"] as? [String: Any]
    mapView.showsAttributionButton = attribution?["visible"] as? Bool ?? true
    mapView.attributionButtonPosition = position(attribution?["position"] as? String, .bottomRight)
    mapView.attributionButtonMargins = margin(attribution, CGPoint(x: 8, y: 8))
  }

  @objc private func cycleTracking() {
    let next: MKUserTrackingMode
    switch userTrackingMode {
    case .none: next = .follow
    case .follow: next = .followWithHeading
    default: next = .none
    }
    userTrackingMode = next
    onUserTrackingModeChange?(next)
  }

  // MARK: Gestures and limits

  var userTrackingMode: MKUserTrackingMode = .none {
    didSet {
      if userTrackingMode != .none { showsUserLocation = true }
      let course = (options["location"] as? [String: Any])?["course"] as? Bool ?? false
      let mode: MLNUserTrackingMode
      switch userTrackingMode {
      case .follow: mode = .follow
      case .followWithHeading: mode = course ? .followWithCourse : .followWithHeading
      default: mode = .none
      }
      if mapView.userTrackingMode != mode { mapView.setUserTrackingMode(mode, animated: true, completionHandler: nil) }
      trackingButton.setImage(UIImage(systemName: userTrackingMode == .none ? "location" : userTrackingMode == .follow ? "location.fill" : "location.north.line.fill"), for: .normal)
    }
  }

  func mapView(_ mapView: MLNMapView, didChange mode: MLNUserTrackingMode, animated: Bool) {
    let munim: MKUserTrackingMode
    switch mode {
    case .follow: munim = .follow
    case .followWithHeading, .followWithCourse: munim = .followWithHeading
    default: munim = .none
    }
    guard munim != userTrackingMode else { return }
    userTrackingMode = munim
    onUserTrackingModeChange?(munim)
  }

  func mapView(_ mapView: MLNMapView, didUpdate userLocation: MLNUserLocation?) {
    guard let location = userLocation?.location else { return }
    onUserLocationChange?(location)
  }

  func mapView(_ mapView: MLNMapView, didFailToLocateUserWithError error: Error) {
    onError?("MapLibre: location: \(error.localizedDescription)")
  }

  var isZoomEnabled = true { didSet { mapView.isZoomEnabled = isZoomEnabled } }
  var isScrollEnabled = true { didSet { mapView.isScrollEnabled = isScrollEnabled } }
  var isRotateEnabled = true { didSet { mapView.isRotateEnabled = isRotateEnabled } }
  var isPitchEnabled = true { didSet { mapView.isPitchEnabled = isPitchEnabled } }

  private func applyGestures() {
    guard let g = options["gestures"] as? [String: Any] else { return }
    if let v = g["quickZoomReversed"] as? Bool { mapView.isQuickZoomReversed = v }
    switch g["panScrollingMode"] as? String {
    case "horizontal": mapView.panScrollingMode = .horizontal
    case "vertical": mapView.panScrollingMode = .vertical
    case "default": mapView.panScrollingMode = .default
    default: break
    }
    if let v = g["snapToNorthTolerance"] as? NSNumber { mapView.toleranceForSnappingToNorth = CGFloat(v.doubleValue) }
    if let v = g["decelerationRate"] as? NSNumber { mapView.decelerationRate = CGFloat(v.doubleValue) }
    if let v = g["anchorToCenter"] as? Bool { mapView.anchorRotateOrZoomGesturesToCenterCoordinate = v }
    if let v = g["hapticFeedback"] as? Bool { mapView.isHapticFeedbackEnabled = v }
    for recognizer in mapView.gestureRecognizers ?? [] {
      if let tap = recognizer as? UITapGestureRecognizer, tap.numberOfTapsRequired == 2, let v = g["doubleTapZoom"] as? Bool {
        tap.isEnabled = v
      }
    }
  }

  var cameraDistanceRange: ClosedRange<Double>? { didSet { applyLimits() } }

  var cameraBoundary: MKCoordinateRegion? { didSet { applyLimits() } }

  private func applyLimits() {
    let c = options["camera"] as? [String: Any] ?? [:]
    let latitude = mapView.centerCoordinate.latitude
    var minZoom = (c["minZoom"] as? NSNumber)?.doubleValue ?? 0
    var maxZoom = (c["maxZoom"] as? NSNumber)?.doubleValue ?? 25.5
    if let range = cameraDistanceRange {
      if range.upperBound.isFinite, range.upperBound < .greatestFiniteMagnitude { minZoom = max(minZoom, zoom(distance: range.upperBound, latitude: latitude)) }
      if range.lowerBound > 0 { maxZoom = min(maxZoom, zoom(distance: range.lowerBound, latitude: latitude)) }
    }
    mapView.minimumZoomLevel = minZoom
    mapView.maximumZoomLevel = maxZoom
    mapView.minimumPitch = CGFloat((c["minPitch"] as? NSNumber)?.doubleValue ?? 0)
    mapView.maximumPitch = CGFloat((c["maxPitch"] as? NSNumber)?.doubleValue ?? 85)
    if let region = cameraBoundary {
      mapView.maximumScreenBounds = MLNCoordinateBounds(
        sw: CLLocationCoordinate2D(latitude: region.center.latitude - region.span.latitudeDelta / 2,
                                   longitude: region.center.longitude - region.span.longitudeDelta / 2),
        ne: CLLocationCoordinate2D(latitude: region.center.latitude + region.span.latitudeDelta / 2,
                                   longitude: region.center.longitude + region.span.longitudeDelta / 2))
    } else {
      mapView.maximumScreenBounds = MLNCoordinateBounds(
        sw: CLLocationCoordinate2D(latitude: -90, longitude: -180), ne: CLLocationCoordinate2D(latitude: 90, longitude: 180))
    }
  }

  var mapPadding: UIEdgeInsets = .zero {
    didSet {
      mapView.automaticallyAdjustsContentInset = false
      mapView.setContentInset(mapPadding, animated: false, completionHandler: nil)
      modelLayer.setNeedsRender()
    }
  }

  // MARK: Camera: MapLibre zooms; munim-maps speaks metres from the camera.

  /// MapLibre's vertical field of view: 2 atan(1/3), about 36.87°.
  fileprivate static let fieldOfView = 0.6435011087932844
  private static let tileSize = 512.0

  private var heightPoints: Double { max(1, Double(mapView.bounds.height)) }

  fileprivate func distance(zoom: Double, latitude: Double) -> Double {
    let metersPerPoint = cos(latitude * .pi / 180) * 2 * .pi * 6_378_137 / (Self.tileSize * pow(2, zoom))
    return heightPoints / 2 / tan(Self.fieldOfView / 2) * metersPerPoint
  }

  private func zoom(distance: Double, latitude: Double) -> Double {
    let points = heightPoints / 2 / tan(Self.fieldOfView / 2)
    let world = cos(latitude * .pi / 180) * 2 * .pi * 6_378_137
    return log2(points * world / (Self.tileSize * max(1, distance)))
  }

  private func mapCamera(_ camera: MunimCamera) -> (MLNMapCamera, Double) {
    let c = MLNMapCamera()
    c.centerCoordinate = CLLocationCoordinate2D(latitude: camera.latitude, longitude: camera.longitude)
    c.pitch = CGFloat(camera.pitch)
    c.heading = camera.heading
    if let roll = (options["camera"] as? [String: Any])?["roll"] as? NSNumber { c.roll = roll.doubleValue }
    return (c, zoom(distance: camera.distance, latitude: camera.latitude))
  }

  /// MLNMapCamera's altitude for a zoom level: MapLibre iOS converts with a
  /// 30° angular field of view (MLNAltitudeForZoomLevel), 512-point tiles.
  private func altitude(zoom: Double, pitch: Double, latitude: Double) -> Double {
    let metersPerPoint = cos(latitude * .pi / 180) * 2 * .pi * 6_378_137 / pow(2, zoom) / Self.tileSize
    return metersPerPoint * heightPoints / 2 / tan(15 * Double.pi / 180) * cos(pitch * .pi / 180)
  }

  private func setMapCamera(_ camera: MunimCamera, duration: TimeInterval, timing: CAMediaTimingFunction? = nil) {
    let (target, zoom) = mapCamera(camera)
    target.altitude = altitude(zoom: zoom, pitch: camera.pitch, latitude: camera.latitude)
    if duration <= 0 {
      mapView.setCamera(target, animated: false)
    } else {
      mapView.setCamera(target, withDuration: duration, animationTimingFunction: timing)
    }
    modelLayer.setNeedsRender()
  }

  var camera: MunimCamera {
    let c = mapView.centerCoordinate
    return MunimCamera(latitude: c.latitude, longitude: c.longitude,
                       distance: distance(zoom: mapView.zoomLevel, latitude: c.latitude),
                       pitch: Double(mapView.camera.pitch), heading: mapView.camera.heading)
  }

  func setCamera(_ camera: MunimCamera, animated: Bool) {
    stopFlight()
    setMapCamera(camera, duration: animated ? 0.35 : 0)
  }

  func animateCamera(_ camera: MunimCamera, duration: TimeInterval, linear: Bool) {
    stopFlight()
    setMapCamera(camera, duration: duration, timing: CAMediaTimingFunction(name: linear ? .linear : .easeInEaseOut))
  }

  private var flight: (keyframes: [MunimCameraKeyframe], start: Double, loop: Bool)?
  private var flightLink: CADisplayLink?

  func flyCamera(_ keyframes: [MunimCameraKeyframe], start: Double, loop: Bool) {
    stopFlight()
    guard keyframes.count > 1 else {
      if let only = keyframes.first { setMapCamera(only.camera, duration: 0) }
      return
    }
    flight = (keyframes.sorted { $0.t < $1.t }, start, loop)
    let link = CADisplayLink(target: MapLibreFlightTarget(self), selector: #selector(MapLibreFlightTarget.tick))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
    link.add(to: .main, forMode: .common)
    flightLink = link
    stepFlight()
  }

  func stopFlight() {
    flight = nil
    flightLink?.invalidate()
    flightLink = nil
  }

  fileprivate func stepFlight() {
    guard let flight, let first = flight.keyframes.first, let last = flight.keyframes.last else { return }
    var t = Date().timeIntervalSince1970 - flight.start
    let span = last.t - first.t
    if flight.loop, span > 0 {
      t = first.t + (t - first.t).truncatingRemainder(dividingBy: span)
      if t < first.t { t += span }
    }
    let camera: MunimCamera
    if t <= first.t {
      camera = first.camera
    } else if t >= last.t {
      camera = last.camera
      if !flight.loop { stopFlight() }
    } else {
      var i = 1
      while i < flight.keyframes.count - 1, flight.keyframes[i].t < t { i += 1 }
      let a = flight.keyframes[i - 1], b = flight.keyframes[i]
      camera = Self.interpolate(a.camera, b.camera, (t - a.t) / max(1e-9, b.t - a.t))
    }
    setMapCamera(camera, duration: 0)
  }

  private static func interpolate(_ a: MunimCamera, _ b: MunimCamera, _ f: Double) -> MunimCamera {
    let turn = ((b.heading - a.heading).truncatingRemainder(dividingBy: 360) + 540).truncatingRemainder(dividingBy: 360) - 180
    return MunimCamera(
      latitude: a.latitude + (b.latitude - a.latitude) * f,
      longitude: a.longitude + (b.longitude - a.longitude) * f,
      distance: exp(log(max(1, a.distance)) + (log(max(1, b.distance)) - log(max(1, a.distance))) * f),
      pitch: a.pitch + (b.pitch - a.pitch) * f,
      heading: (a.heading + turn * f + 360).truncatingRemainder(dividingBy: 360))
  }

  var visibleRegion: MKCoordinateRegion {
    let b = mapView.visibleCoordinateBounds
    return MKCoordinateRegion(
      center: CLLocationCoordinate2D(latitude: (b.sw.latitude + b.ne.latitude) / 2, longitude: (b.sw.longitude + b.ne.longitude) / 2),
      span: MKCoordinateSpan(latitudeDelta: b.ne.latitude - b.sw.latitude, longitudeDelta: b.ne.longitude - b.sw.longitude))
  }

  func setRegion(_ region: MKCoordinateRegion, duration: TimeInterval) {
    stopFlight()
    let bounds = MLNCoordinateBounds(
      sw: CLLocationCoordinate2D(latitude: region.center.latitude - region.span.latitudeDelta / 2,
                                 longitude: region.center.longitude - region.span.longitudeDelta / 2),
      ne: CLLocationCoordinate2D(latitude: region.center.latitude + region.span.latitudeDelta / 2,
                                 longitude: region.center.longitude + region.span.longitudeDelta / 2))
    let camera = mapView.cameraThatFitsCoordinateBounds(bounds)
    mapView.setCamera(camera, withDuration: max(0, duration), animationTimingFunction: nil)
  }

  func fit(coordinates: [CLLocationCoordinate2D], padding: UIEdgeInsets, animated: Bool) {
    stopFlight()
    guard !coordinates.isEmpty else { return }
    if coordinates.count == 1 {
      mapView.setCenter(coordinates[0], animated: animated)
      return
    }
    var coords = coordinates
    mapView.setVisibleCoordinates(&coords, count: UInt(coords.count), edgePadding: padding, animated: animated)
  }

  func fitMarkers(_ ids: Set<String>, padding: UIEdgeInsets, animated: Bool) {
    fit(coordinates: features.coordinates(of: ids), padding: padding, animated: animated)
  }

  func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
    mapView.convert(coordinate, toPointTo: mapView)
  }

  func coordinate(for point: CGPoint) -> CLLocationCoordinate2D {
    mapView.convert(point, toCoordinateFrom: mapView)
  }

  // MARK: Delegate: camera and rendering

  func mapView(_ mapView: MLNMapView, regionWillChangeWith reason: MLNCameraChangeReason, animated: Bool) {
    let gesture: MLNCameraChangeReason = [.gesturePan, .gesturePinch, .gestureRotate, .gestureZoomIn, .gestureZoomOut,
                                          .gestureOneFingerZoom, .gestureTilt]
    event("cameraMoveStarted", ["reason": reason.isDisjoint(with: gesture) ? (reason.contains(.programmatic) ? "api" : "other") : "gesture"])
  }

  func mapViewRegionIsChanging(_ mapView: MLNMapView) {
    modelLayer.setNeedsRender()
    features.positionCallout()
    onCameraMove?(camera)
  }

  func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
    modelLayer.setNeedsRender()
    features.positionCallout()
    onCameraChange?(camera)
  }

  func mapViewDidBecomeIdle(_ mapView: MLNMapView) {
    event("idle")
  }

  func mapViewDidFinishRenderingMap(_ mapView: MLNMapView, fullyRendered: Bool) {
    event("renderedMap", ["fullyRendered": fullyRendered])
  }

  func mapView(_ mapView: MLNMapView, didFailToLoadImage imageName: String) -> UIImage? {
    if let image = features.image(missing: imageName) { return image }
    event("styleImageMissing", ["id": imageName])
    return nil
  }

  func mapView(_ mapView: MLNMapView, sourceDidChange source: MLNSource) {
    if !source.identifier.hasPrefix("munim-") { event("sourceChanged", ["id": source.identifier]) }
  }

  func mapViewRendererDidError(_ mapView: MLNMapView) {
    event("renderError")
  }

  // MARK: Snapshots and services

  private func writePNG(_ image: UIImage, completion: @escaping (Result<URL, Error>) -> Void) {
    guard let data = image.pngData() else {
      return completion(.failure(MunimMapEngineError("MapLibre: could not encode the snapshot")))
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("munim-maps-snapshot-\(UUID().uuidString).png")
    do {
      try data.write(to: url)
      completion(.success(url))
    } catch {
      completion(.failure(error))
    }
  }

  private var snapshotters: [MLNMapSnapshotter] = []

  private func snapshotter(size: CGSize, styleURL: URL?, camera: MLNMapCamera, zoom: Double, showsLogo: Bool,
                           completion: @escaping (Result<URL, Error>) -> Void) {
    let resolved = resolveStyle()
    let options = MLNMapSnapshotOptions(styleURL: styleURL ?? resolved.url, camera: camera, size: size)
    options.zoomLevel = zoom
    options.showsLogo = showsLogo
    let snapshotter = MLNMapSnapshotter(options: options)
    snapshotters.append(snapshotter)
    snapshotter.start { [weak self] snapshot, error in
      self?.snapshotters.removeAll { $0 === snapshotter }
      if let snapshot { self?.writePNG(snapshot.image, completion: completion) } else {
        completion(.failure(error ?? MunimMapEngineError("MapLibre: the snapshot failed")))
      }
    }
  }

  /// The map as it is drawn now (MLNMapSnapshotter with the same style and camera).
  func snapshot(size: CGSize?, completion: @escaping (Result<URL, Error>) -> Void) {
    let camera = mapView.camera
    snapshotter(size: size ?? bounds.size, styleURL: nil, camera: camera, zoom: mapView.zoomLevel, showsLogo: false, completion: completion)
  }

  /// Reverse geocoding with Nominatim (`maplibre.nominatimUrl`), light use only.
  func address(for coordinate: CLLocationCoordinate2D, completion: @escaping (Result<MunimAddress, Error>) -> Void) {
    let base = string("nominatimUrl").isEmpty ? "https://nominatim.openstreetmap.org" : string("nominatimUrl")
    guard let url = URL(string: "\(base)/reverse?format=jsonv2&addressdetails=1&lat=\(coordinate.latitude)&lon=\(coordinate.longitude)") else { return }
    var request = URLRequest(url: url)
    request.setValue("munim-maps/\(Bundle.main.bundleIdentifier ?? "app")", forHTTPHeaderField: "User-Agent")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    URLSession.shared.dataTask(with: request) { data, _, error in
      let result: Result<MunimAddress, Error>
      if let data, let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], json["error"] == nil {
        let a = json["address"] as? [String: Any] ?? [:]
        func s(_ k: String) -> String { a[k] as? String ?? "" }
        let street = [s("house_number"), s("road")].filter { !$0.isEmpty }.joined(separator: " ")
        let city = [s("city"), s("town"), s("village")].first { !$0.isEmpty } ?? ""
        result = .success(MunimAddress(
          name: json["name"] as? String ?? "", street: street, city: city, region: s("state"), postalCode: s("postcode"),
          country: s("country"), countryCode: s("country_code").uppercased(), formatted: json["display_name"] as? String ?? ""))
      } else {
        result = .failure(error ?? MunimMapEngineError("MapLibre: no address here"))
      }
      DispatchQueue.main.async { completion(result) }
    }.resume()
  }

  func measureAlignment() -> MunimAlignmentReport { modelLayer.measureAlignment() }

  // MARK: Commands

  private func json(_ value: Any?) -> String {
    guard let value, !(value is NSNull) else { return "null" }
    return (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
  }

  private func features(_ list: [MLNFeature]) -> [Any] { list.map { $0.geoJSONDictionary() } }

  func providerCommand(
    _ command: String, arguments: [String: Any], completion: @escaping (Result<Any, Error>) -> Void
  ) {
    runCommand(command, args: arguments) { result in
      completion(result.map { json in
        (try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])) ?? NSNull()
      })
    }
  }

  /// MapLibre's commands, completing with JSON text.
  private func runCommand(_ command: String, args: [String: Any], completion: @escaping (Result<String, Error>) -> Void) {
    let offlineStyle = resolveStyle().url ?? URL(string: MunimMapsConfiguration.shared.maplibreStyleURL)
    if MapLibreOffline.shared.run(command, args: args, styleURL: offlineStyle, completion: completion) { return }
    func ok(_ value: Any? = nil) { completion(.success(json(value))) }
    func fail(_ message: String) { completion(.failure(MapLibreStyleSpec.SpecError(message: "MapLibre \(command): \(message)"))) }
    if command == "snapshot" {
      let w = (args["width"] as? NSNumber)?.doubleValue ?? Double(bounds.width)
      let h = (args["height"] as? NSNumber)?.doubleValue ?? Double(bounds.height)
      var camera = mapView.camera
      var zoom = mapView.zoomLevel
      if let c = args["camera"] as? [String: Any] {
        func n(_ k: String, _ d: Double) -> Double { (c[k] as? NSNumber)?.doubleValue ?? d }
        let target = MLNMapCamera()
        target.centerCoordinate = CLLocationCoordinate2D(latitude: n("latitude", 0), longitude: n("longitude", 0))
        target.pitch = CGFloat(n("pitch", 0))
        target.heading = n("heading", 0)
        camera = target
        if let z = c["zoom"] as? NSNumber {
          zoom = z.doubleValue
        } else {
          let points = h / 2 / tan(Self.fieldOfView / 2)
          zoom = log2(points * cos(n("latitude", 0) * .pi / 180) * 2 * .pi * 6_378_137 / (Self.tileSize * max(1, n("distance", 1000))))
        }
      }
      snapshotter(size: CGSize(width: w, height: h), styleURL: (args["styleUrl"] as? String).flatMap(URL.init(string:)),
                  camera: camera, zoom: zoom, showsLogo: args["showsLogo"] as? Bool ?? false) { result in
        switch result {
        case .success(let url): ok(url.path)
        case .failure(let error): completion(.failure(error))
        }
      }
      return
    }
    if command == "setConnected" { return fail("MapLibre iOS detects connectivity itself; this is Android only") }
    guard let style = mapView.style, styleLoaded else { return fail("the map is not ready yet") }
    do {
      switch command {
      case "queryRenderedFeatures":
        let layers = (args["layers"] as? [String]).map(Set.init)
        let predicate = try args["filter"].map { f -> NSPredicate in
          guard MapLibreStyleSpec.isExpression(f) else { throw MapLibreStyleSpec.SpecError(message: "filter must be an expression") }
          return NSPredicate(mglJSONObject: f)
        }
        let found: [MLNFeature]
        if let b = args["box"] as? [String: Any] {
          func n(_ k: String) -> CGFloat { CGFloat((b[k] as? NSNumber)?.doubleValue ?? 0) }
          found = mapView.visibleFeatures(in: CGRect(x: n("x"), y: n("y"), width: n("width"), height: n("height")),
                                          styleLayerIdentifiers: layers, predicate: predicate)
        } else if let p = args["point"] as? [String: Any] {
          let point = CGPoint(x: (p["x"] as? NSNumber)?.doubleValue ?? 0, y: (p["y"] as? NSNumber)?.doubleValue ?? 0)
          found = mapView.visibleFeatures(at: point, styleLayerIdentifiers: layers, predicate: predicate)
        } else {
          found = mapView.visibleFeatures(in: mapView.bounds, styleLayerIdentifiers: layers, predicate: predicate)
        }
        ok(features(found))
      case "querySourceFeatures":
        let id = args["source"] as? String ?? ""
        let predicate = args["filter"].flatMap { MapLibreStyleSpec.isExpression($0) ? NSPredicate(mglJSONObject: $0) : nil }
        switch style.source(withIdentifier: id) {
        case let source as MLNShapeSource: ok(features(source.features(matching: predicate)))
        case let source as MLNVectorTileSource:
          ok(features(source.features(sourceLayerIdentifiers: Set(args["sourceLayers"] as? [String] ?? []), predicate: predicate)))
        default: fail("'\(id)' is not a GeoJSON or vector source")
        }
      case "getClusterLeaves", "getClusterChildren", "getClusterExpansionZoom":
        guard let source = style.source(withIdentifier: args["source"] as? String ?? "") as? MLNShapeSource else {
          return fail("no GeoJSON source '\(args["source"] ?? "")'")
        }
        let clusterId = (args["clusterId"] as? NSNumber)?.uintValue ?? 0
        let clusters = source.features(matching: NSPredicate(mglJSONObject: ["==", ["get", "cluster_id"], clusterId]))
        guard let cluster = clusters.compactMap({ $0 as? MLNPointFeatureCluster }).first else { return fail("no cluster \(clusterId) loaded") }
        switch command {
        case "getClusterLeaves":
          ok(features(source.leaves(of: cluster, offset: (args["offset"] as? NSNumber)?.uintValue ?? 0,
                                    limit: (args["limit"] as? NSNumber)?.uintValue ?? 10)))
        case "getClusterChildren": ok(features(source.children(of: cluster)))
        default: ok(source.zoomLevel(forExpanding: cluster))
        }
      case "metersPerPoint":
        ok(mapView.metersPerPoint(atLatitude: (args["latitude"] as? NSNumber)?.doubleValue ?? mapView.centerCoordinate.latitude))
      case "getStyle":
        ok(["layers": style.layers.map(\.identifier).filter { !$0.hasPrefix("munim-slot") },
            "sources": style.sources.map(\.identifier), "json": style.styleJSON])
      case "reloadStyle":
        loadStyle(force: true)
        ok()
      case "addSource":
        guard let id = args["id"] as? String, let json = args["source"] as? [String: Any] else { return fail("needs id and source") }
        style.addSource(try MapLibreStyleSpec.source(id: id, json))
        ok()
      case "removeSource":
        guard let source = style.source(withIdentifier: args["id"] as? String ?? "") else { return ok(false) }
        style.removeSource(source)
        ok(true)
      case "setGeoJson":
        guard let source = style.source(withIdentifier: args["source"] as? String ?? "") as? MLNShapeSource else {
          return fail("no GeoJSON source '\(args["source"] ?? "")'")
        }
        if let url = args["data"] as? String, !url.trimmingCharacters(in: .whitespaces).hasPrefix("{") {
          source.url = URL(string: url)
        } else {
          source.shape = try MapLibreStyleSpec.shape(args["data"])
        }
        ok()
      case "addLayer":
        let layer = try MapLibreStyleSpec.layer(args, in: style)
        MapLibreStyleSpec.add(layer, to: style, below: args["beforeId"] as? String, fallback: MapLibreFeatures.slotUser)
        ok()
      case "removeLayer":
        guard let layer = style.layer(withIdentifier: args["id"] as? String ?? "") else { return ok(false) }
        style.removeLayer(layer)
        ok(true)
      case "moveLayer":
        guard let layer = style.layer(withIdentifier: args["id"] as? String ?? "") else { return fail("no layer '\(args["id"] ?? "")'") }
        style.removeLayer(layer)
        MapLibreStyleSpec.add(layer, to: style, below: args["beforeId"] as? String, fallback: MapLibreFeatures.slotUser)
        ok()
      case "setPaintProperty", "setLayoutProperty":
        guard let layer = style.layer(withIdentifier: args["layer"] as? String ?? "") else { return fail("no layer '\(args["layer"] ?? "")'") }
        try MapLibreStyleSpec.setProperty(layer, name: args["name"] as? String ?? "", value: args["value"])
        ok()
      case "setFilter":
        guard let layer = style.layer(withIdentifier: args["layer"] as? String ?? "") else { return fail("no layer '\(args["layer"] ?? "")'") }
        try MapLibreStyleSpec.setFilter(layer, args["filter"])
        ok()
      case "setLayerZoomRange":
        guard let layer = style.layer(withIdentifier: args["layer"] as? String ?? "") else { return fail("no layer '\(args["layer"] ?? "")'") }
        layer.minimumZoomLevel = Float((args["minzoom"] as? NSNumber)?.doubleValue ?? 0)
        layer.maximumZoomLevel = Float((args["maxzoom"] as? NSNumber)?.doubleValue ?? 24)
        ok()
      case "addImage":
        loadStyleImage(args["name"] as? String ?? "", uri: args["uri"] as? String ?? "", sdf: args["sdf"] as? Bool ?? false)
        ok()
      case "removeImage":
        style.removeImage(forName: args["name"] as? String ?? "")
        ok()
      case "setLight":
        applyLight(style, args["light"] as? [String: Any] ?? [:])
        ok()
      case "setFeatureState", "getFeatureState", "removeFeatureState":
        let sourceId = args["source"] as? String ?? ""
        let id = args["id"].map { "\($0)" }
        let state = args["state"] as? [String: Any] ?? [:]
        switch style.source(withIdentifier: sourceId) {
        case let source as MLNShapeSource:
          switch command {
          case "setFeatureState":
            guard let id else { return fail("needs an id") }
            ok(source.setFeatureState(featureID: id, state: state))
          case "getFeatureState":
            guard let id else { return fail("needs an id") }
            ok(source.featureState(featureID: id))
          default:
            if let id { ok(source.removeFeatureState(featureID: id, stateKey: args["key"] as? String)) } else { ok(source.resetFeatureStates()) }
          }
        case let source as MLNVectorTileSource:
          guard let layer = args["sourceLayer"] as? String else { return fail("vector sources need a sourceLayer") }
          switch command {
          case "setFeatureState":
            guard let id else { return fail("needs an id") }
            ok(source.setFeatureState(sourceLayerID: layer, featureID: id, state: state))
          case "getFeatureState":
            guard let id else { return fail("needs an id") }
            ok(source.featureState(sourceLayerID: layer, featureID: id))
          default:
            if let id {
              if let key = args["key"] as? String { ok(source.removeFeatureState(sourceLayerID: layer, featureID: id, stateKey: key)) } else {
                ok(source.removeFeatureState(sourceLayerID: layer, featureID: id))
              }
            } else {
              ok(source.resetFeatureStates(sourceLayerID: layer))
            }
          }
        default:
          fail("'\(sourceId)' is not a GeoJSON or vector source")
        }
      case "flyTo":
        stopFlight()
        guard let c = args["camera"] as? [String: Any] else { return fail("needs a camera") }
        func n(_ k: String, _ d: Double) -> Double { (c[k] as? NSNumber)?.doubleValue ?? d }
        let munim = MunimCamera(latitude: n("latitude", 0), longitude: n("longitude", 0), distance: n("distance", 1000),
                                pitch: n("pitch", 0), heading: n("heading", 0))
        let (target, zoom) = mapCamera(munim)
        target.altitude = altitude(zoom: zoom, pitch: munim.pitch, latitude: munim.latitude)
        let duration = ((args["durationMs"] as? NSNumber)?.doubleValue ?? -1000) / 1000
        mapView.fly(to: target, withDuration: duration, completionHandler: nil)
        ok()
      case "resetNorth":
        mapView.resetNorth()
        ok()
      case "resetPosition":
        mapView.resetPosition()
        ok()
      default:
        fail("unknown command")
      }
    } catch {
      completion(.failure(error))
    }
  }
}

// MARK: - The 3D layer's camera

/// MapLibre's camera for the 3D layer: MLNMapView's zoom, pitch, heading
/// and centre each frame, with MapLibre's fixed 36.87° field of view.
final class MapLibreCameraSource: MapCameraSource {
  weak var engine: MapLibreMapEngine?
  init(_ engine: MapLibreMapEngine) { self.engine = engine }

  var cameraView: UIView? { engine?.mapLibreView }

  func cameraState(previous: MapCameraState?) -> MapCameraState? { engine?.cameraState() }

  func screenPoint(for coordinate: CLLocationCoordinate2D) -> CGPoint? {
    guard let view = engine?.mapLibreView else { return nil }
    return view.convert(coordinate, toPointTo: view)
  }

  func visibleRegion() -> MKCoordinateRegion? { engine?.visibleRegion }
}

extension MapLibreMapEngine {
  var mapLibreView: MLNMapView { mapView }

  func cameraState() -> MapCameraState? {
    guard styleLoaded else { return nil }
    let size = mapView.bounds.size
    guard size.width > 1, size.height > 1 else { return nil }
    let center = mapView.centerCoordinate
    let distance = distance(zoom: mapView.zoomLevel, latitude: center.latitude)
    let pitch = Double(mapView.camera.pitch)
    // MapLibre draws the centre coordinate in the middle of the content inset.
    let centerPoint = mapView.convert(center, toPointTo: mapView)
    var state = MapCameraState(
      latitude: center.latitude, longitude: center.longitude, distance: distance,
      altitude: distance * cos(pitch * .pi / 180), pitch: pitch, heading: mapView.camera.heading,
      mapSize: size, focalLength: MapCameraState.focalLength(height: Double(size.height), verticalFieldOfView: Self.fieldOfView),
      centerPoint: centerPoint)
    state.darkAppearance = isDark
    return state
  }
}

private final class MapLibreFlightTarget: NSObject {
  weak var engine: MapLibreMapEngine?
  init(_ engine: MapLibreMapEngine) { self.engine = engine }
  @objc func tick() { engine?.stepFlight() }
}
#endif
