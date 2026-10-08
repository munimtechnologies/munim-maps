#if MUNIM_MAPS_MAPLIBRE_WEB
import CoreLocation
import MapKit
import UIKit
import WebKit

// MapLibre GL JS as the `maplibre` provider's second renderer (`variant`
// "web"): GL JS (from jsDelivr, cached on disk, or bundled from the app's
// `maplibre-gl` package) in a WKWebView this engine owns. It has what
// MapLibre Native does not: the globe, 3D terrain, sky and atmosphere. The
// web half (maplibre/page/munim-maplibre/js) draws the map, markers, shapes
// and munim-maps' 3D layer (three.js inside GL JS); this half hosts it,
// turns props into messages and messages into events, and keeps the native
// 3D layer on GL JS's camera for what only SceneKit draws (USDZ, SCN, OBJ)
// and for `modelRendering: 'overlay'`.

enum MapLibreWebEngineFactory: MunimMapEngineFactory {
  static let isImplemented = true
  static func make() -> MunimMapEngine { MapLibreWebEngine() }
}

final class MapLibreWebEngine: UIView, MunimMapEngine, MunimMapEngineDefaults,
  WKScriptMessageHandler, WKNavigationDelegate, CLLocationManagerDelegate
{
  let provider = MunimMapProvider.maplibre
  var variant: String { "web" }
  let modelLayer = MunimModelLayer()
  var view: UIView { self }

  private let webView: WKWebView
  private let schemeHandler = MapLibreWebSchemeHandler()
  private var pageReady = false
  private var queue: [String] = []
  /// Every prop sent, to send again when the page (re)loads.
  private var sent: [String: Any] = [:]
  private var calls: [String: (Result<Any?, Error>) -> Void] = [:]
  private var nextCall = 0
  private var snapshotState: MapLibreWebCamera?
  private var readyReported = false
  private var configObserver: NSObjectProtocol?
  private let cameraSource = MapLibreWebCameraSource()

  override init(frame: CGRect) {
    let configuration = WKWebViewConfiguration()
    configuration.setURLSchemeHandler(schemeHandler, forURLScheme: MapLibreWebSchemeHandler.scheme)
    configuration.allowsInlineMediaPlayback = true
    configuration.suppressesIncrementalRendering = false
    webView = WKWebView(frame: .zero, configuration: configuration)
    super.init(frame: frame)
    backgroundColor = UIColor(red: 0.95, green: 0.94, blue: 0.91, alpha: 1)
    configuration.userContentController.add(MapLibreWebScriptHandler(self), name: "munim")
    webView.navigationDelegate = self
    webView.isOpaque = true
    webView.backgroundColor = backgroundColor
    webView.scrollView.backgroundColor = backgroundColor
    webView.scrollView.isScrollEnabled = false
    webView.scrollView.bounces = false
    webView.scrollView.contentInsetAdjustmentBehavior = .never
    if #available(iOS 16.4, *) {
      #if DEBUG
      webView.isInspectable = true
      #endif
    }
    webView.frame = bounds
    webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(webView)
    let layerView = modelLayer.view
    layerView.frame = bounds
    layerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    layerView.isUserInteractionEnabled = false
    addSubview(layerView)
    cameraSource.engine = self
    modelLayer.attach(to: cameraSource)
    modelLayer.onError = { [weak self] message in self?.onError?(message) }
    configObserver = NotificationCenter.default.addObserver(
      forName: MunimMapsConfiguration.didChange, object: nil, queue: .main
    ) { [weak self] _ in self?.sendInit() }
    load()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  deinit {
    if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    webView.configuration.userContentController.removeScriptMessageHandler(forName: "munim")
    locationManager?.stopUpdatingLocation()
  }

  private func load() {
    guard MapLibreWebSchemeHandler.root != nil else {
      onError?("MapLibre GL JS: the MunimMapsMapLibre resource bundle is missing; reinstall pods with the NitroMunimMaps/MapLibre subspec")
      return
    }
    pageReady = false
    webView.load(URLRequest(url: URL(string: MapLibreWebSchemeHandler.base + "index.html")!))
  }

  // MARK: Messages

  private func post(_ message: [String: Any]) {
    let json = MapLibreWebJSON.string(message)
    guard pageReady else {
      queue.append(json)
      return
    }
    webView.evaluateJavaScript("window.munimMapLibre&&window.munimMapLibre.receive(\(json))", completionHandler: nil)
  }

  /// Sends a prop (and remembers it for a page reload).
  private func set(_ key: String, _ value: Any) {
    let v = MapLibreWebJSON.value(value)
    sent[key] = v
    post(["t": "set", "k": key, "v": v])
  }

  private func call(_ method: String, _ args: [String: Any] = [:], completion: ((Result<Any?, Error>) -> Void)? = nil) {
    nextCall += 1
    let id = "c\(nextCall)"
    if let completion { calls[id] = completion }
    post(["t": "call", "id": id, "m": method, "a": MapLibreWebJSON.value(args)])
  }

  private func sendInit() {
    guard pageReady else { return }
    let env: [String: Any] = [
      "platform": "ios",
      "resourceBase": MapLibreWebSchemeHandler.base + "resource?uri=",
      "tileProxy": MapLibreWebSchemeHandler.base + "tile/",
      "density": Double(UIScreen.main.scale),
      "appId": Bundle.main.bundleIdentifier ?? "",
      "defaultStyleUrl": MunimMapsConfiguration.shared.maplibreStyleURL,
    ]
    // Options first: they decide the map the rest is applied to; then init.
    let props = sent.map { ["t": "set", "k": $0.key, "v": $0.value] as [String: Any] }
    let ordered = props.sorted { ($0["k"] as? String == "options" ? 0 : 1) < ($1["k"] as? String == "options" ? 0 : 1) }
    let batch: [String: Any] = ["t": "batch", "m": ordered + [["t": "init", "env": env]]]
    webView.evaluateJavaScript("window.munimMapLibre.receive(\(MapLibreWebJSON.string(batch)))", completionHandler: nil)
  }

  func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let text = message.body as? String, let m = MapLibreWebJSON.parse(text) as? [String: Any], let t = m["t"] as? String else { return }
    switch t {
    case "ready":
      pageReady = true
      sendInit()
      let pending = queue.filter { !$0.contains("\"t\":\"set\"") }
      queue.removeAll()
      for json in pending { webView.evaluateJavaScript("window.munimMapLibre.receive(\(json))", completionHandler: nil) }
    case "cam":
      if let s = m["s"] as? [String: Any] {
        snapshotState = MapLibreWebCamera(s, previous: snapshotState)
        modelLayer.setNeedsRender()
      }
    case "result":
      guard let id = m["id"] as? String, let completion = calls.removeValue(forKey: id) else { return }
      if m["ok"] as? Bool == true {
        completion(.success(m["v"] is NSNull ? nil : m["v"]))
      } else {
        completion(.failure(MunimMapEngineError(m["e"] as? String ?? "MapLibre GL JS: failed")))
      }
    case "event":
      handleEvent(m["n"] as? String ?? "", m["d"] as? [String: Any] ?? [:])
    default:
      break
    }
  }

  private func double(_ d: [String: Any], _ key: String) -> Double { (d[key] as? NSNumber)?.doubleValue ?? 0 }

  private func coordinate(_ d: [String: Any]) -> CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: double(d, "latitude"), longitude: double(d, "longitude"))
  }

  private func camera(_ d: [String: Any]) -> MunimCamera {
    MunimCamera(latitude: double(d, "latitude"), longitude: double(d, "longitude"), distance: double(d, "distance"),
                pitch: double(d, "pitch"), heading: double(d, "heading"))
  }

  private func handleEvent(_ name: String, _ d: [String: Any]) {
    switch name {
    case "mapReady":
      guard !readyReported else { return }
      readyReported = true
      providerEventHandler?("renderer", ["renderer": "web", "maplibre": d["maplibre"] ?? ""])
      onMapReady?()
    case "press":
      let point = CGPoint(x: double(d, "x"), y: double(d, "y"))
      if let id = modelLayer.modelHit(at: point) {
        modelLayer.onModelPress?(id)
      } else {
        onPress?(coordinate(d), point)
      }
    case "longPress":
      onLongPress?(coordinate(d), CGPoint(x: double(d, "x"), y: double(d, "y")))
    case "cameraMove": onCameraMove?(camera(d))
    case "cameraChange": onCameraChange?(camera(d))
    case "markerPress": onMarkerPress?(d["id"] as? String ?? "")
    case "markerDeselect": onMarkerDeselect?(d["id"] as? String ?? "")
    case "calloutPress": onCalloutPress?(d["id"] as? String ?? "")
    case "calloutAccessoryPress": onCalloutAccessoryPress?(d["id"] as? String ?? "", d["side"] as? String ?? "right")
    case "clusterPress":
      let ids = (d["markerIds"] as? String ?? "").split(separator: ",").map(String.init)
      onClusterPress?(d["clusteringId"] as? String ?? "", ids, coordinate(d))
    case "overlayPress": onOverlayPress?(d["id"] as? String ?? "", d["kind"] as? String ?? "", coordinate(d))
    case "markerDragStart": onMarkerDragStart?(d["id"] as? String ?? "", coordinate(d))
    case "markerDragEnd": onMarkerDragEnd?(d["id"] as? String ?? "", coordinate(d))
    case "markerDrag": onMarkerDrag?(d["id"] as? String ?? "", coordinate(d))
    case "modelPress": modelLayer.onModelPress?(d["id"] as? String ?? "")
    case "userTrackingModeChange":
      let mode = d["mode"] as? String ?? "none"
      trackingMode = mode == "follow" ? .follow : mode == "followWithHeading" ? .followWithHeading : .none
      onUserTrackingModeChange?(trackingMode)
    case "mapFeaturePress":
      onMapFeaturePress?(MunimMapFeature(
        title: d["title"] as? String ?? "", coordinate: coordinate(d), kind: d["kind"] as? String ?? "pointOfInterest",
        category: d["category"] as? String ?? "", id: d["id"] as? String ?? ""))
    case "provider":
      providerEventHandler?(d["name"] as? String ?? "", d["data"] ?? [String: Any]())
    case "error":
      onError?(d["message"] as? String ?? "MapLibre GL JS: error")
    default:
      break
    }
  }

  // MARK: WKNavigationDelegate

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    // The WebView's process can be killed under memory pressure: start again.
    onError?("MapLibre GL JS: the WebView's content process ended (memory); reloading")
    readyReported = true
    load()
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    onError?("MapLibre GL JS: \(error.localizedDescription)")
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    onError?("MapLibre GL JS: \(error.localizedDescription)")
  }

  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    // Attribution links open in Safari, not over the map.
    if let url = action.request.url, action.navigationType == .linkActivated, url.scheme != MapLibreWebSchemeHandler.scheme {
      UIApplication.shared.open(url)
      return decisionHandler(.cancel)
    }
    decisionHandler(.allow)
  }

  // MARK: Provider settings

  var styleURL = "" { didSet { set("styleUrl", styleURL) } }

  var providerOptions: [String: Any] = [:] {
    didSet {
      set("options", providerOptions)
      // The model split depends on `modelRendering`.
      setModels(allModels)
      setZones(allZones)
      setPaths(allPaths)
    }
  }

  /// `modelRendering`: `auto` / `native` (drawn in the page with three.js)
  /// or `overlay` (munim-maps' SceneKit layer over the WebView).
  private var renderer: String { providerOptions["modelRendering"] as? String ?? "auto" }

  // MARK: 2D content

  var markers: [MunimMarker] = [] { didSet { sendMarkers() } }

  /// `MarkerView`s: the React Native view rendered to a PNG, drawn as an image marker.
  private var viewMarkers: [String: MunimMarker] = [:]
  private var viewMarkerOrder: [String] = []

  private func sendMarkers() {
    set("markers", markers + viewMarkerOrder.compactMap { viewMarkers[$0] })
  }

  private func viewMarker(_ marker: MunimMarker, image: UIImage?) -> MunimMarker {
    var m = marker
    m.style = .image
    if let image, let data = image.pngData() {
      m.imageUri = "data:image/png;base64," + data.base64EncodedString()
      m.imageSize = Double(max(image.size.width, image.size.height))
      m.borderWidth = 0
    }
    return m
  }

  func setViewMarker(_ marker: MunimMarker, image: UIImage?) {
    if viewMarkers[marker.id] == nil { viewMarkerOrder.append(marker.id) }
    viewMarkers[marker.id] = viewMarker(marker, image: image)
    sendMarkers()
  }

  func setViewMarkerImage(_ image: UIImage?, id: String) {
    guard let marker = viewMarkers[id] else { return }
    viewMarkers[id] = viewMarker(marker, image: image)
    sendMarkers()
  }

  func removeViewMarker(_ id: String) {
    viewMarkers[id] = nil
    viewMarkerOrder.removeAll { $0 == id }
    sendMarkers()
  }

  var polylines: [MunimPolyline] = [] { didSet { set("polylines", polylines) } }
  var polygons: [MunimPolygon] = [] { didSet { set("polygons", polygons) } }
  var circles: [MunimCircle] = [] { didSet { set("circles", circles) } }
  var tileOverlays: [MunimTileOverlay] = [] { didSet { set("tileOverlays", tileOverlays) } }
  var clusterStyles: [MunimClusterStyle] = [] { didSet { set("clusterStyles", clusterStyles) } }

  // MARK: 3D content

  private var allModels: [MunimModel] = []
  private var allZones: [MunimZone] = []
  private var allPaths: [MunimPath] = []

  /// Whether the page draws this model (glTF, shapes, pictures) or SceneKit does (USDZ, SCN, OBJ…).
  private func pageDraws(_ model: MunimModel) -> Bool {
    if renderer == "overlay" { return false }
    if !model.imageUri.isEmpty || model.uri.isEmpty { return true }
    let path = model.uri.split(separator: "?").first.map(String.init) ?? model.uri
    let ext = (path as NSString).pathExtension.lowercased()
    return !["usdz", "usd", "usda", "usdc", "scn", "scnz", "obj", "dae", "abc", "ply", "stl", "reality"].contains(ext)
  }

  func setModels(_ models: [MunimModel]) {
    allModels = models
    set("models", models.filter(pageDraws))
    modelLayer.models = models.filter { !pageDraws($0) }
  }

  func setZones(_ zones: [MunimZone]) {
    allZones = zones
    set("zones", renderer == "overlay" ? [] : zones)
    modelLayer.zones = renderer == "overlay" ? zones : []
  }

  func setPaths(_ paths: [MunimPath]) {
    allPaths = paths
    set("paths", renderer == "overlay" ? [] : paths)
    modelLayer.paths = renderer == "overlay" ? paths : []
  }

  func modelLayerDidChange() {
    set("lighting", modelLayer.lighting.rawValue)
    set("maxCameraDistance", modelLayer.maxCameraDistance)
    set("occlusion", modelLayer.buildingOcclusion ? "buildings" : "none")
    set("followTerrain", modelLayer.followsTerrain)
  }

  // MARK: Look

  var initialCamera: MunimCamera? { didSet { if let initialCamera { set("initialCamera", initialCamera) } } }
  var mapStyle: MunimMapStyle = .standard { didSet { set("mapStyle", mapStyle.rawValue) } }
  var elevation: MunimElevation = .realistic { didSet { set("elevation", elevation.rawValue) } }
  var globe = false { didSet { set("globe", globe) } }
  var colorScheme: UIUserInterfaceStyle = .unspecified {
    didSet { set("colorScheme", colorScheme == .dark ? "dark" : colorScheme == .light ? "light" : "system") }
  }
  var showsBuildings = true { didSet { set("showsBuildings", showsBuildings) } }
  var showsTraffic = false {
    didSet {
      if showsTraffic { onError?("MapLibre: there is no traffic data in OpenStreetMap; showsTraffic needs a traffic tile source (maplibre.sources)") }
    }
  }
  var pointOfInterestFilter: MKPointOfInterestFilter = .includingAll {
    didSet {
      if pointOfInterestFilter == .includingAll {
        set("pointsOfInterest", "all")
      } else if pointOfInterestFilter == .excludingAll {
        set("pointsOfInterest", "none")
      } else {
        set("pointsOfInterest", Self.categories.filter { pointOfInterestFilter.includes($0) }.map(\.rawValue).joined(separator: ","))
      }
    }
  }

  private static let categories: [MKPointOfInterestCategory] = [
    .airport, .amusementPark, .aquarium, .atm, .bakery, .bank, .beach, .brewery, .cafe, .campground, .carRental,
    .evCharger, .fireStation, .fitnessCenter, .foodMarket, .gasStation, .hospital, .hotel, .laundry, .library,
    .marina, .movieTheater, .museum, .nationalPark, .nightlife, .park, .parking, .pharmacy, .police, .postOffice,
    .publicTransport, .restaurant, .restroom, .school, .stadium, .store, .theater, .university, .winery, .zoo,
  ]

  var showsUserLocation = false {
    didSet {
      set("showsUserLocation", showsUserLocation)
      updateLocationUpdates()
    }
  }

  // MARK: Controls

  var compassVisibility: MunimFeatureVisibility = .adaptive { didSet { set("compassVisibility", compassVisibility.rawValue) } }
  var scaleVisibility: MunimFeatureVisibility = .hidden { didSet { set("scaleVisibility", scaleVisibility.rawValue) } }
  var showsUserTrackingButton = false { didSet { set("showsUserTrackingButton", showsUserTrackingButton) } }
  var pitchButtonVisibility: MunimFeatureVisibility = .hidden { didSet { set("pitchButtonVisibility", pitchButtonVisibility.rawValue) } }
  var selectableFeatures: Set<MunimMapFeatureKind> = [] { didSet { set("selectableFeatures", selectableFeatures.map(\.rawValue)) } }

  // MARK: Gestures and limits

  private var trackingMode: MKUserTrackingMode = .none
  var userTrackingMode: MKUserTrackingMode {
    get { trackingMode }
    set {
      trackingMode = newValue
      set("userTrackingMode", newValue == .follow ? "follow" : newValue == .followWithHeading ? "followWithHeading" : "none")
      updateLocationUpdates()
    }
  }

  var isZoomEnabled = true { didSet { sendGestures() } }
  var isScrollEnabled = true { didSet { sendGestures() } }
  var isRotateEnabled = true { didSet { sendGestures() } }
  var isPitchEnabled = true { didSet { sendGestures() } }

  private func sendGestures() {
    set("gestures", ["zoom": isZoomEnabled, "scroll": isScrollEnabled, "rotate": isRotateEnabled, "pitch": isPitchEnabled])
  }

  var cameraDistanceRange: ClosedRange<Double>? {
    didSet {
      let r = cameraDistanceRange
      set("distanceRange", ["min": r?.lowerBound ?? 0, "max": r.map { $0.upperBound.isFinite && $0.upperBound < 1e15 ? $0.upperBound : 0 } ?? 0])
    }
  }

  var cameraBoundary: MKCoordinateRegion? {
    didSet {
      if let b = cameraBoundary {
        set("boundary", ["latitude": b.center.latitude, "longitude": b.center.longitude,
                         "latitudeDelta": b.span.latitudeDelta, "longitudeDelta": b.span.longitudeDelta])
      } else {
        set("boundary", NSNull())
      }
    }
  }

  var mapPadding: UIEdgeInsets = .zero {
    didSet { set("mapPadding", ["top": mapPadding.top, "left": mapPadding.left, "bottom": mapPadding.bottom, "right": mapPadding.right]) }
  }

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
  var onOverlayPress: ((String, String, CLLocationCoordinate2D) -> Void)? {
    didSet { set("overlayPress", onOverlayPress != nil) }
  }
  var onMarkerDragStart: ((String, CLLocationCoordinate2D) -> Void)?
  var onMarkerDragEnd: ((String, CLLocationCoordinate2D) -> Void)?
  var onMarkerDrag: ((String, CLLocationCoordinate2D) -> Void)?
  var onUserLocationChange: ((CLLocation) -> Void)?
  var onMapFeaturePress: ((MunimMapFeature) -> Void)?
  var onUserTrackingModeChange: ((MKUserTrackingMode) -> Void)?
  var onError: ((String) -> Void)?
  private var providerEventHandler: ((String, Any) -> Void)?
  func setProviderEventHandler(_ handler: ((String, Any) -> Void)?) { providerEventHandler = handler }

  // MARK: Camera

  var camera: MunimCamera {
    snapshotState?.munim ?? initialCamera ?? MunimCamera(latitude: 0, longitude: 0, distance: 10_000_000)
  }

  func setCamera(_ camera: MunimCamera, animated: Bool) {
    call("setCamera", ["camera": camera, "animated": animated])
  }

  func animateCamera(_ camera: MunimCamera, duration: TimeInterval, linear: Bool) {
    call("animateCamera", ["camera": camera, "durationMs": duration * 1000, "easing": linear ? "linear" : "easeInOut"])
  }

  func flyCamera(_ keyframes: [MunimCameraKeyframe], start: Double, loop: Bool) {
    call("flyCamera", ["keyframes": keyframes, "start": start, "loop": loop])
  }

  func stopFlight() { call("stopFlight") }

  var visibleRegion: MKCoordinateRegion {
    if let r = snapshotState?.region {
      return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: r.latitude, longitude: r.longitude),
                                span: MKCoordinateSpan(latitudeDelta: r.latitudeDelta, longitudeDelta: r.longitudeDelta))
    }
    let c = camera
    return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude),
                              span: MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0))
  }

  func setRegion(_ region: MKCoordinateRegion, duration: TimeInterval) {
    call("setRegion", ["region": ["latitude": region.center.latitude, "longitude": region.center.longitude,
                                  "latitudeDelta": region.span.latitudeDelta, "longitudeDelta": region.span.longitudeDelta],
                       "durationMs": duration * 1000])
  }

  private func insets(_ p: UIEdgeInsets) -> [String: Any] {
    ["top": p.top, "left": p.left, "bottom": p.bottom, "right": p.right]
  }

  func fit(coordinates: [CLLocationCoordinate2D], padding: UIEdgeInsets, animated: Bool) {
    call("fitToCoordinates", ["coordinates": coordinates, "animated": animated, "padding": insets(padding)])
  }

  func fitMarkers(_ ids: Set<String>, padding: UIEdgeInsets, animated: Bool) {
    call("fitToMarkers", ["ids": Array(ids), "animated": animated, "padding": insets(padding)])
  }

  /// From GL JS's last matrices, at the ground height of the centre (the
  /// promise-based `fetchPoint` asks GL JS itself, on terrain).
  func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
    snapshotState?.screenPoint(latitude: coordinate.latitude, longitude: coordinate.longitude) ?? .zero
  }

  func coordinate(for point: CGPoint) -> CLLocationCoordinate2D {
    snapshotState?.coordinate(at: point) ?? kCLLocationCoordinate2DInvalid
  }

  // MARK: Asynchronous answers (exact, from GL JS)

  func fetchCamera(_ completion: @escaping (MunimCamera) -> Void) {
    call("getCamera") { [weak self] result in
      guard let self else { return }
      if case .success(let v) = result, let d = v as? [String: Any] { completion(self.camera(d)) } else { completion(self.camera) }
    }
  }

  func fetchVisibleRegion(_ completion: @escaping (MKCoordinateRegion) -> Void) {
    call("getVisibleRegion") { [weak self] result in
      guard let self else { return }
      if case .success(let v) = result, let d = v as? [String: Any] {
        completion(MKCoordinateRegion(center: self.coordinate(d), span: MKCoordinateSpan(latitudeDelta: self.double(d, "latitudeDelta"), longitudeDelta: self.double(d, "longitudeDelta"))))
      } else {
        completion(self.visibleRegion)
      }
    }
  }

  func fetchPoint(for coordinate: CLLocationCoordinate2D, _ completion: @escaping (CGPoint) -> Void) {
    call("pointForCoordinate", ["coordinate": coordinate]) { [weak self] result in
      guard let self else { return }
      if case .success(let v) = result, let d = v as? [String: Any] {
        completion(CGPoint(x: self.double(d, "x"), y: self.double(d, "y")))
      } else {
        completion(self.point(for: coordinate))
      }
    }
  }

  func fetchCoordinate(for point: CGPoint, _ completion: @escaping (CLLocationCoordinate2D) -> Void) {
    call("coordinateForPoint", ["point": ["x": point.x, "y": point.y]]) { [weak self] result in
      guard let self else { return }
      if case .success(let v) = result, let d = v as? [String: Any] { completion(self.coordinate(d)) } else { completion(self.coordinate(for: point)) }
    }
  }

  func fetchAlignment(_ completion: @escaping (MunimAlignmentReport) -> Void) {
    // Models on the SceneKit layer (overlay, USDZ) are measured there.
    if renderer == "overlay" || allModels.allSatisfy({ !pageDraws($0) }) && !allModels.isEmpty {
      completion(modelLayer.measureAlignment())
      return
    }
    call("measureAlignment") { [weak self] result in
      guard let self else { return }
      guard case .success(let v) = result, let d = v as? [String: Any] else { return completion(self.modelLayer.measureAlignment()) }
      completion(MunimAlignmentReport(
        attached: d["attached"] as? Bool ?? false, modelsMeasured: self.double(d, "modelsMeasured"),
        maxErrorPoints: self.double(d, "maxErrorPoints"), meanErrorPoints: self.double(d, "meanErrorPoints"),
        modelsVisibleInRender: self.double(d, "modelsVisibleInRender"), cameraDistance: self.double(d, "cameraDistance"),
        cameraPitch: self.double(d, "cameraPitch"), cameraHeading: self.double(d, "cameraHeading"),
        fieldOfViewDegrees: self.double(d, "fieldOfViewDegrees")))
    }
  }

  func fetchOverlayHit(at point: CGPoint, _ completion: @escaping (String) -> Void) {
    call("overlayAtPoint", ["point": ["x": point.x, "y": point.y]]) { result in
      if case .success(let v) = result, let id = v as? String { completion(id) } else { completion("") }
    }
  }

  func measureAlignment() -> MunimAlignmentReport { modelLayer.measureAlignment() }

  // MARK: Methods

  func selectMarker(_ id: String) { call("selectMarker", ["id": id]) }
  func deselectMarker(_ id: String) { call("deselectMarker", ["id": id]) }

  private func writePNG(_ value: Any?, prefix: String, completion: @escaping (Result<URL, Error>) -> Void) {
    guard let base64 = value as? String, let data = Data(base64Encoded: base64) else {
      return completion(.failure(MunimMapEngineError("MapLibre GL JS: no snapshot")))
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString).png")
    do {
      try data.write(to: url)
      completion(.success(url))
    } catch {
      completion(.failure(error))
    }
  }

  func snapshot(size: CGSize?, completion: @escaping (Result<URL, Error>) -> Void) {
    call("snapshot", ["width": size?.width ?? 0, "height": size?.height ?? 0]) { [weak self] result in
      switch result {
      case .success(let value): self?.writePNG(value, prefix: "munim-maplibre", completion: completion)
      case .failure(let error): completion(.failure(error))
      }
    }
  }

  func address(for coordinate: CLLocationCoordinate2D, completion: @escaping (Result<MunimAddress, Error>) -> Void) {
    let custom = providerOptions["nominatimUrl"] as? String ?? ""
    let base = custom.isEmpty ? "https://nominatim.openstreetmap.org" : custom
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

  func providerCommand(
    _ command: String, arguments: [String: Any], completion: @escaping (Result<Any, Error>) -> Void
  ) {
    if command == "snapshot" {
      // MapLibre Native's offscreen snapshotter: an offscreen GL JS map, written to a PNG file.
      call("snapshotOffscreen", arguments) { [weak self] result in
        switch result {
        case .success(let value):
          self?.writePNG(value, prefix: "munim-maplibre-snapshot") { written in completion(written.map { $0.path as Any }) }
        case .failure(let error): completion(.failure(error))
        }
      }
      return
    }
    call(command, arguments) { result in completion(result.map { $0 ?? NSNull() }) }
  }

  // MARK: The native 3D layer on GL JS's camera

  fileprivate var webCameraView: UIView? { window == nil ? nil : webView }
  fileprivate var cameraSnapshot: MapLibreWebCamera? { snapshotState }

  // MARK: User location

  private var locationManager: CLLocationManager?

  private func updateLocationUpdates() {
    let wanted = showsUserLocation || trackingMode != .none
    if wanted {
      let manager = locationManager ?? CLLocationManager()
      locationManager = manager
      manager.delegate = self
      if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
      manager.startUpdatingLocation()
      if trackingMode == .followWithHeading { manager.startUpdatingHeading() } else { manager.stopUpdatingHeading() }
    } else {
      locationManager?.stopUpdatingLocation()
      locationManager?.stopUpdatingHeading()
    }
  }

  private var lastHeading: CLLocationDirection = -1

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let l = locations.last else { return }
    set("userLocation", ["latitude": l.coordinate.latitude, "longitude": l.coordinate.longitude, "altitude": l.altitude,
                         "horizontalAccuracy": l.horizontalAccuracy, "heading": lastHeading >= 0 ? lastHeading : l.course])
    onUserLocationChange?(l)
  }

  func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
    lastHeading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
      updateLocationUpdates()
    }
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    onError?("MapLibre GL JS: location: \(error.localizedDescription)")
  }
}

/// GL JS's camera as munim-maps' native 3D layer reads it.
final class MapLibreWebCameraSource: MapCameraSource {
  weak var engine: MapLibreWebEngine?

  var cameraView: UIView? { engine?.webCameraView }

  func cameraState(previous: MapCameraState?) -> MapCameraState? {
    guard let s = engine?.cameraSnapshot, s.width > 0, s.height > 0 else { return nil }
    return MapCameraState(
      latitude: s.latitude,
      longitude: s.longitude,
      distance: s.distance,
      altitude: s.distance * cos(s.pitch * .pi / 180),
      pitch: s.pitch,
      heading: s.heading,
      mapSize: CGSize(width: s.width, height: s.height),
      focalLength: MapCameraState.focalLength(height: s.height, verticalFieldOfView: s.fovy),
      centerPoint: CGPoint(x: s.centerX, y: s.centerY),
      globe: s.globe,
      drawsTerrain: s.terrain,
      darkAppearance: s.dark)
  }

  func screenPoint(for coordinate: CLLocationCoordinate2D) -> CGPoint? {
    engine?.cameraSnapshot?.screenPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
  }

  func visibleRegion() -> MKCoordinateRegion? { engine?.visibleRegion }
}
#endif
