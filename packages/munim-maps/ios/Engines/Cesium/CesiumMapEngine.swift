#if MUNIM_MAPS_CESIUM
import CoreLocation
import MapKit
import UIKit
import WebKit

// The Cesium engine on iOS: CesiumJS (bundled with munim-maps, in the
// `MunimMapsCesium` resource bundle of the `NitroMunimMaps/Cesium` subspec)
// running in a WKWebView this engine owns. The web half
// (cesium/munim-cesium/js) draws the map, markers, shapes and the glTF
// models; this half hosts it, turns props into messages, messages into
// events, and keeps munim-maps' native 3D layer (USDZ, SCN, OBJ models) on
// Cesium's camera.

enum CesiumMapEngineFactory: MunimMapEngineFactory {
  static let isImplemented = true
  static func make() -> MunimMapEngine { CesiumMapEngine() }
}

final class CesiumMapEngine: UIView, MunimMapEngine, MunimMapEngineDefaults,
  WKScriptMessageHandler, WKNavigationDelegate, CLLocationManagerDelegate
{
  let provider = MunimMapProvider.cesium
  let modelLayer = MunimModelLayer()
  var view: UIView { self }

  private let webView: WKWebView
  private let schemeHandler = CesiumSchemeHandler()
  private var pageReady = false
  private var queue: [String] = []
  /// Every prop sent, to send again when the page (re)loads.
  private var sent: [String: Any] = [:]
  private var calls: [String: (Result<Any?, Error>) -> Void] = [:]
  private var nextCall = 0
  private var snapshotState: CesiumCameraSnapshot?
  private var readyReported = false
  private var configObserver: NSObjectProtocol?
  private let cameraSource = CesiumCameraSource()

  override init(frame: CGRect) {
    let configuration = WKWebViewConfiguration()
    configuration.setURLSchemeHandler(schemeHandler, forURLScheme: CesiumSchemeHandler.scheme)
    configuration.allowsInlineMediaPlayback = true
    configuration.mediaTypesRequiringUserActionForPlayback = []
    configuration.suppressesIncrementalRendering = false
    webView = WKWebView(frame: .zero, configuration: configuration)
    super.init(frame: frame)
    backgroundColor = .black
    configuration.userContentController.add(CesiumScriptHandler(self), name: "munim")
    webView.navigationDelegate = self
    webView.isOpaque = true
    webView.backgroundColor = .black
    webView.scrollView.isScrollEnabled = false
    webView.scrollView.bounces = false
    webView.scrollView.contentInsetAdjustmentBehavior = .never
    webView.customUserAgent = nil
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
    guard CesiumSchemeHandler.root != nil else {
      onError?("Cesium: the MunimMapsCesium resource bundle is missing; reinstall pods with the NitroMunimMaps/Cesium subspec")
      return
    }
    pageReady = false
    webView.load(URLRequest(url: URL(string: CesiumSchemeHandler.base + "index.html")!))
  }

  // MARK: Messages

  private func post(_ message: [String: Any]) {
    let json = CesiumJSON.string(message)
    guard pageReady else {
      queue.append(json)
      return
    }
    webView.evaluateJavaScript("window.munimCesium&&window.munimCesium.receive(\(json))", completionHandler: nil)
  }

  /// Sends a prop (and remembers it for a page reload).
  private func set(_ key: String, _ value: Any) {
    let v = CesiumJSON.value(value)
    sent[key] = v
    post(["t": "set", "k": key, "v": v])
  }

  private func call(_ method: String, _ args: [String: Any] = [:], completion: ((Result<Any?, Error>) -> Void)? = nil) {
    nextCall += 1
    let id = "c\(nextCall)"
    if let completion { calls[id] = completion }
    post(["t": "call", "id": id, "m": method, "a": CesiumJSON.value(args)])
  }

  private func sendInit() {
    let config = MunimMapsConfiguration.shared
    let env: [String: Any] = [
      "platform": "ios",
      "ionToken": config.cesiumIonToken,
      "googleKey": config.googleMapsApiKey,
      "resourceBase": CesiumSchemeHandler.base + "resource?uri=",
      "tileProxy": CesiumSchemeHandler.base + "tile/",
      "density": Double(UIScreen.main.scale),
      "appId": Bundle.main.bundleIdentifier ?? "",
    ]
    guard pageReady else { return }
    let props = sent.map { ["t": "set", "k": $0.key, "v": $0.value] as [String: Any] }
    // Options first: they decide the viewer the rest is applied to.
    let ordered = props.sorted { ($0["k"] as? String == "options" ? 0 : 1) < ($1["k"] as? String == "options" ? 0 : 1) }
    let batch: [String: Any] = ["t": "batch", "m": ordered + [["t": "init", "env": env]]]
    // Props before init, so the first viewer is made with them.
    webView.evaluateJavaScript("window.munimCesium.receive(\(CesiumJSON.string(batch)))", completionHandler: nil)
  }

  func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let text = message.body as? String, let m = CesiumJSON.parse(text) as? [String: Any], let t = m["t"] as? String else { return }
    switch t {
    case "ready":
      pageReady = true
      sendInit()
      let pending = queue.filter { !$0.contains("\"t\":\"set\"") }
      queue.removeAll()
      for json in pending { webView.evaluateJavaScript("window.munimCesium.receive(\(json))", completionHandler: nil) }
    case "cam":
      if let s = m["s"] as? [String: Any] {
        snapshotState = CesiumCameraSnapshot(s, previous: snapshotState)
        modelLayer.setNeedsRender()
      }
    case "result":
      guard let id = m["id"] as? String, let completion = calls.removeValue(forKey: id) else { return }
      if m["ok"] as? Bool == true {
        completion(.success(m["v"] is NSNull ? nil : m["v"]))
      } else {
        completion(.failure(MunimMapEngineError(m["e"] as? String ?? "Cesium: failed")))
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
      let event = d["name"] as? String ?? ""
      providerEventHandler?(event, d["data"] ?? [String: Any]())
    case "error":
      onError?(d["message"] as? String ?? "Cesium: error")
    default:
      break
    }
  }

  // MARK: WKNavigationDelegate

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    // The WebView's process can be killed under memory pressure: start again.
    onError?("Cesium: the WebView's content process ended (memory); reloading")
    load()
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    onError?("Cesium: \(error.localizedDescription)")
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    onError?("Cesium: \(error.localizedDescription)")
  }

  func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    // Links in credits and info boxes open in Safari, not over the map.
    if let url = action.request.url, action.navigationType == .linkActivated, url.scheme != CesiumSchemeHandler.scheme {
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
      // The model split depends on `modelRenderer`.
      setModels(allModels)
      setZones(allZones)
      setPaths(allPaths)
    }
  }

  /// `modelRendering`: `auto` / `native` (Cesium entities and primitives) or
  /// `overlay` (munim-maps' native 3D layer over the WebView). The older
  /// `modelRenderer` (`cesium`, `native`) still works.
  private var renderer: String {
    if let mode = providerOptions["modelRendering"] as? String { return mode }
    switch providerOptions["modelRenderer"] as? String {
    case "cesium": return "native"
    case "native": return "overlay"
    default: return "auto"
    }
  }

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
    if let data = image?.pngData() {
      m.imageUri = "data:image/png;base64," + data.base64EncodedString()
      m.imageSize = Double(max(image!.size.width, image!.size.height))
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

  /// Whether Cesium draws this model (glTF, shapes, pictures) or the native layer does (USDZ, SCN, OBJ…).
  private func cesiumDraws(_ model: MunimModel) -> Bool {
    switch renderer {
    case "overlay": return false
    case "native": return true
    default:
      if model.occluder { return false }
      if !model.imageUri.isEmpty || model.uri.isEmpty { return true }
      let path = model.uri.split(separator: "?").first.map(String.init) ?? model.uri
      let ext = (path as NSString).pathExtension.lowercased()
      return !["usdz", "usd", "usda", "usdc", "scn", "scnz", "obj", "dae", "abc", "ply", "stl", "reality"].contains(ext)
    }
  }

  func setModels(_ models: [MunimModel]) {
    allModels = models
    set("models", models.filter(cesiumDraws))
    modelLayer.models = models.filter { !cesiumDraws($0) }
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

  func fit(coordinates: [CLLocationCoordinate2D], padding: UIEdgeInsets, animated: Bool) {
    call("fitToCoordinates", ["coordinates": coordinates, "animated": animated,
                              "padding": ["top": padding.top, "left": padding.left, "bottom": padding.bottom, "right": padding.right]])
  }

  func fitMarkers(_ ids: Set<String>, padding: UIEdgeInsets, animated: Bool) {
    call("fitToMarkers", ["ids": Array(ids), "animated": animated,
                          "padding": ["top": padding.top, "left": padding.left, "bottom": padding.bottom, "right": padding.right]])
  }

  /// From Cesium's last view and projection matrices, at the ground height of the centre.
  func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
    snapshotState?.screenPoint(latitude: coordinate.latitude, longitude: coordinate.longitude) ?? .zero
  }

  func coordinate(for point: CGPoint) -> CLLocationCoordinate2D {
    snapshotState?.coordinate(at: point) ?? kCLLocationCoordinate2DInvalid
  }

  // MARK: Methods

  func selectMarker(_ id: String) { call("selectMarker", ["id": id]) }
  func deselectMarker(_ id: String) { call("deselectMarker", ["id": id]) }

  func snapshot(size: CGSize?, completion: @escaping (Result<URL, Error>) -> Void) {
    call("snapshot", ["width": size?.width ?? 0, "height": size?.height ?? 0]) { result in
      switch result {
      case .success(let value):
        guard let base64 = value as? String, let data = Data(base64Encoded: base64) else {
          return completion(.failure(MunimMapEngineError("Cesium: no snapshot")))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("munim-cesium-\(UUID().uuidString).png")
        do {
          try data.write(to: url)
          completion(.success(url))
        } catch {
          completion(.failure(error))
        }
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  func address(for coordinate: CLLocationCoordinate2D, completion: @escaping (Result<MunimAddress, Error>) -> Void) {
    CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) { placemarks, error in
      guard let p = placemarks?.first else {
        return completion(.failure(error ?? MunimMapEngineError("No address here")))
      }
      let street = [p.subThoroughfare, p.thoroughfare].compactMap { $0 }.joined(separator: " ")
      let formatted = [p.name, street.isEmpty ? nil : street, p.locality, p.administrativeArea, p.postalCode, p.country]
        .compactMap { $0 }
        .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        .joined(separator: ", ")
      completion(.success(MunimAddress(
        name: p.name ?? "", street: street, city: p.locality ?? "", region: p.administrativeArea ?? "",
        postalCode: p.postalCode ?? "", country: p.country ?? "", countryCode: p.isoCountryCode ?? "", formatted: formatted)))
    }
  }

  func providerCommand(
    _ command: String, arguments: [String: Any], completion: @escaping (Result<Any, Error>) -> Void
  ) {
    call(command, arguments) { result in
      completion(result.map { $0 ?? NSNull() })
    }
  }

  // MARK: The native 3D layer on Cesium's camera

  fileprivate var webCameraView: UIView? { window == nil ? nil : webView }
  fileprivate var cameraSnapshot: CesiumCameraSnapshot? { snapshotState }

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
    onError?("Cesium: location: \(error.localizedDescription)")
  }
}
/// Cesium's camera as munim-maps' native 3D layer reads it.
final class CesiumCameraSource: MapCameraSource {
  weak var engine: CesiumMapEngine?

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
