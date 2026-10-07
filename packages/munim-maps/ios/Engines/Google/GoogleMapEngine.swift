#if canImport(GoogleMaps)
import GoogleMaps
import GoogleMapsUtils
import MapKit
import UIKit

// The Google engine: Google Maps SDK for iOS (`GMSMapView`) with Google Maps
// Utils (clustering, heatmaps, KML, GeoJSON), and munim-maps' SceneKit 3D
// layer over it on Google's camera (`GoogleCameraSource`).
//
// Compiled only with the `NitroMunimMaps/Google` subspec. Shared props and
// methods follow `MunimMapEngine`; options only Google has come in
// `providerOptions` (JavaScript `google={{ … }}`, `GoogleMapOptions` in
// src/providers/google.ts), events only Google has go out through
// `setProviderEventHandler` (`onProviderEvent`), and methods only Google has
// through `providerCommand` (GoogleCommands.swift).

enum GoogleMapEngineFactory: MunimMapEngineFactory {
  static let isImplemented = true

  static func make() -> MunimMapEngine {
    guard GoogleMapEngine.provideAPIKey() else {
      return UnavailableMapEngine(
        provider: .google,
        reason: "No Google Maps API key. Pass googleMapsApiKey to configureMunimMaps (or the Expo config "
          + "plugin, Info.plist MunimMapsGoogleMapsApiKey) before the first Google map.")
    }
    return GoogleMapEngine()
  }
}

/// munim-maps' Google Maps engine on iOS. Native apps can reach it through
/// `MunimMapContainerView.engine as? GoogleMapEngine` (for example for
/// `mapView`, or `addTileLayer` with a custom `GMSTileLayer`).
@_expose(!Cxx)
public final class GoogleMapEngine: UIView, MunimMapEngine, MunimMapEngineDefaults {
  public let provider = MunimMapProvider.google
  public var view: UIView { self }
  public let modelLayer = MunimModelLayer()
  /// Google's map view; made at the first layout (and again when `mapId`
  /// changes, since Google only takes a Map ID when the view is made).
  public private(set) var mapView: GMSMapView?
  var cameraSource: GoogleCameraSource?

  // MARK: Key

  private static var providedKey: String?

  /// Hands the key to `GMSServices` once. False when there is none.
  static func provideAPIKey() -> Bool {
    if providedKey != nil { return true }
    let key = MunimMapsConfiguration.shared.googleMapsApiKey
    guard !key.isEmpty else { return false }
    GMSServices.provideAPIKey(key)
    providedKey = key
    return true
  }

  // MARK: Init

  init() {
    super.init(frame: .zero)
    clipsToBounds = true
    modelLayer.view.frame = bounds
    modelLayer.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(modelLayer.view)
    modelLayer.onError = { [weak self] message in self?.onError?(message) }
  }

  public required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  deinit {
    flightLink?.invalidate()
    readyTimer?.invalidate()
    myLocationObservation?.invalidate()
  }

  public override func layoutSubviews() {
    super.layoutSubviews()
    guard bounds.width > 0, bounds.height > 0 else { return }
    if mapView == nil { makeMapView() }
    mapView?.frame = bounds
    modelLayer.view.frame = bounds
    streetView?.frame = bounds
    applyInitialCameraIfReady()
    applyZoomLimits()
    modelLayer.setNeedsRender()
  }

  /// Makes (or remakes) Google's map view with the current options.
  func makeMapView() {
    let options = GMSMapViewOptions()
    options.frame = bounds
    let mapId = self.options["mapId"].string ?? ""
    if !mapId.isEmpty { options.mapID = GMSMapID(identifier: mapId) }
    if let background = self.options["backgroundColor"].color { options.backgroundColor = background }
    if let old = mapView {
      options.camera = old.camera
      teardownMapView(old)
    }
    let map = GMSMapView(options: options)
    map.frame = bounds
    map.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    map.delegate = self
    map.indoorDisplay.delegate = self
    insertSubview(map, at: 0)
    mapView = map
    builtMapId = mapId

    let source = GoogleCameraSource(mapView: map)
    cameraSource = source
    modelLayer.detach()
    modelLayer.attach(to: source)

    myLocationObservation = map.observe(\.myLocation, options: [.new]) { [weak self] map, _ in
      DispatchQueue.main.async { self?.myLocationChanged(map.myLocation) }
    }

    applySettings()
    rebuildContent()
    readyTimer?.invalidate()
    readyTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
      self?.reportReady()
    }
  }

  private func teardownMapView(_ map: GMSMapView) {
    map.delegate = nil
    clusterManagers.values.forEach { $0.clearItems() }
    clusterManagers.removeAll()
    gmsMarkers.removeAll()
    gmsPolylines.removeAll()
    gmsPolygons.removeAll()
    gmsCircles.removeAll()
    tileLayers.removeAll()
    groundOverlays.removeAll()
    heatmapLayers.removeAll()
    overlayKeys.removeAll()
    kmlRenderers.values.forEach { $0.clear() }
    kmlRenderers.removeAll()
    geoJsonOverlays.removeAll()
    featureLayerIds.removeAll()
    map.clear()
    map.removeFromSuperview()
    myLocationObservation?.invalidate()
    myLocationObservation = nil
  }

  /// Puts every piece of content on a new map view.
  private func rebuildContent() {
    applyMarkers()
    applyPolylines()
    applyPolygons()
    applyCircles()
    applyTileOverlays()
    applyGoogleOverlays()
  }

  // MARK: State

  var options = GoogleJSON([String: Any]())
  private var builtMapId = ""
  private var appliedInitialCamera = false
  private var readyReported = false
  private var readyTimer: Timer?
  private var tilesLoaded = false
  private var myLocationObservation: NSKeyValueObservation?
  var providerEventHandler: ((String, Any) -> Void)?
  lazy var locationManager = CLLocationManager()
  var lastHeading: CLLocationDirection = -1
  var headingDelegate: GoogleHeadingDelegate?

  // Markers (GoogleMarkers.swift)
  var markerData: [String: MunimMarker] = [:]
  var gmsMarkers: [String: GMSMarker] = [:]
  var viewMarkers: [String: MunimMarker] = [:]
  var markerExtras: [String: String] = [:]
  var viewMarkerImages: [String: UIImage] = [:]
  var clusterManagers: [String: GMUClusterManager] = [:]
  var clusterIds: [String: String] = [:]
  var photos: [String: UIImage] = [:]
  var loadingPhotos: Set<String> = []
  var selectedMarkerId: String?

  // Shapes and overlays (GoogleShapes.swift)
  var gmsPolylines: [String: GMSPolyline] = [:]
  var gmsPolygons: [String: GMSPolygon] = [:]
  var gmsCircles: [String: GMSCircle] = [:]
  var tileLayers: [String: GMSTileLayer] = [:]
  var customTileLayers: [String: GMSTileLayer] = [:]
  var groundOverlays: [String: GMSGroundOverlay] = [:]
  var heatmapLayers: [String: GMUHeatmapTileLayer] = [:]
  var overlayKeys: [String: String] = [:]
  var dashZoom: Float = -1

  // Layers (GoogleLayers.swift)
  var kmlRenderers: [String: GMUGeometryRenderer] = [:]
  var kmlSources: [String: String] = [:]
  var geoJsonOverlays: [String: [GMSOverlay]] = [:]
  var geoJsonSources: [String: String] = [:]
  var featureLayerIds: [String: String] = [:]

  // Street View (GoogleStreetView.swift). The service is kept: Google drops
  // the callback when it is released mid-request.
  var streetView: GoogleStreetView?
  lazy var panoramaService = GMSPanoramaService()

  // Flights
  private var flight: (keyframes: [MunimCameraKeyframe], start: Double, loop: Bool)?
  private var flightLink: CADisplayLink?

  // MARK: Events

  public var onMapReady: (() -> Void)?
  public var onPress: ((CLLocationCoordinate2D, CGPoint) -> Void)?
  public var onLongPress: ((CLLocationCoordinate2D, CGPoint) -> Void)?
  public var onCameraMove: ((MunimCamera) -> Void)?
  public var onCameraChange: ((MunimCamera) -> Void)?
  public var onMarkerPress: ((String) -> Void)?
  public var onMarkerDeselect: ((String) -> Void)?
  public var onCalloutPress: ((String) -> Void)?
  public var onCalloutAccessoryPress: ((String, String) -> Void)?
  public var onClusterPress: ((String, [String], CLLocationCoordinate2D) -> Void)?
  public var onOverlayPress: ((String, String, CLLocationCoordinate2D) -> Void)?
  public var onMarkerDragStart: ((String, CLLocationCoordinate2D) -> Void)?
  public var onMarkerDragEnd: ((String, CLLocationCoordinate2D) -> Void)?
  public var onMarkerDrag: ((String, CLLocationCoordinate2D) -> Void)?
  public var onUserLocationChange: ((CLLocation) -> Void)?
  public var onMapFeaturePress: ((MunimMapFeature) -> Void)?
  public var onUserTrackingModeChange: ((MKUserTrackingMode) -> Void)?
  public var onError: ((String) -> Void)?

  public func setProviderEventHandler(_ handler: ((String, Any) -> Void)?) {
    providerEventHandler = handler
  }

  /// Sends an event only Google has to `onProviderEvent`.
  func emit(_ name: String, _ data: [String: Any] = [:]) {
    providerEventHandler?(name, data)
  }

  private func reportReady() {
    guard !readyReported, mapView != nil else { return }
    readyReported = true
    readyTimer?.invalidate()
    onMapReady?()
  }

  // MARK: Provider settings

  /// A JSON map style to load (`file://`, a path or `https://`), applied
  /// with the `google.styleJson` rules. Google has no style URLs of its own.
  public var styleURL: String = "" {
    didSet {
      guard styleURL != oldValue else { return }
      loadStyleURL()
    }
  }
  var styleURLJSON: String?

  public var providerOptions: [String: Any] = [:] {
    didSet {
      options = GoogleJSON(providerOptions)
      reportModeLimits()
      guard mapView != nil else { return }
      if (options["mapId"].string ?? "") != builtMapId {
        makeMapView()
        return
      }
      applySettings()
      applyMarkers()
      applyPolylines()
      applyPolygons()
      applyCircles()
      applyTileOverlays()
      applyGoogleOverlays()
    }
  }

  private var reportedModeLimits: Set<String> = []

  /// Google's photorealistic 3D map (`google.mode: '3d'`) is the Maps 3D SDK
  /// for iOS, `GoogleMaps3D`: a SwiftUI-only Swift package that CocoaPods
  /// cannot install, so the iOS engine stays on the 2D map, where models are
  /// always drawn by munim-maps' overlay.
  private func reportModeLimits() {
    if options["mode"].string == "3d", reportedModeLimits.insert("3d").inserted {
      onError?("Google Maps: mode '3d' (photorealistic 3D) is Android only for now; iOS's Maps 3D SDK (GoogleMaps3D) is a SwiftUI-only Swift package. Showing the 2D map")
    }
    if options["modelRendering"].string == "native", reportedModeLimits.insert("native").inserted {
      onError?("Google Maps: the 2D map has no native 3D models; models are drawn by the munim overlay")
    }
  }

  private func loadStyleURL() {
    let text = styleURL.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else {
      styleURLJSON = nil
      applySettings()
      return
    }
    let url = text.hasPrefix("/") ? URL(fileURLWithPath: text) : URL(string: text)
    guard let url else {
      onError?("Google Maps: styleUrl is not a URL: \(text)")
      return
    }
    URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
      DispatchQueue.main.async {
        guard let self else { return }
        guard let data, let json = String(data: data, encoding: .utf8) else {
          self.onError?("Google Maps: could not load the style at \(text): \(error?.localizedDescription ?? "no data")")
          return
        }
        self.styleURLJSON = json
        self.applySettings()
      }
    }.resume()
  }

  // MARK: 2D content

  public var markers: [MunimMarker] = [] { didSet { applyMarkers() } }
  public var polylines: [MunimPolyline] = [] { didSet { applyPolylines() } }
  public var polygons: [MunimPolygon] = [] { didSet { applyPolygons() } }
  public var circles: [MunimCircle] = [] { didSet { applyCircles() } }
  public var tileOverlays: [MunimTileOverlay] = [] {
    didSet {
      applyTileOverlays()
      applySettings()
    }
  }
  public var clusterStyles: [MunimClusterStyle] = [] { didSet { reclusterAll() } }

  // MARK: Look

  public var initialCamera: MunimCamera? {
    didSet { applyInitialCameraIfReady() }
  }

  public var mapStyle: MunimMapStyle = .standard { didSet { applySettings() } }
  public var colorScheme: UIUserInterfaceStyle = .unspecified { didSet { applySettings() } }
  public var showsBuildings = true { didSet { applySettings() } }
  public var showsTraffic = false { didSet { applySettings() } }
  public var pointOfInterestFilter: MKPointOfInterestFilter = .includingAll { didSet { applySettings() } }
  public var showsUserLocation = false {
    didSet {
      if showsUserLocation { requestLocationPermission() }
      applySettings()
    }
  }

  public var compassVisibility: MunimFeatureVisibility = .adaptive { didSet { applySettings() } }
  public var showsUserTrackingButton = false { didSet { applySettings() } }
  public var selectableFeatures: Set<MunimMapFeatureKind> = []

  public var isZoomEnabled = true { didSet { applySettings() } }
  public var isScrollEnabled = true { didSet { applySettings() } }
  public var isRotateEnabled = true { didSet { applySettings() } }
  public var isPitchEnabled = true { didSet { applySettings() } }
  public var cameraDistanceRange: ClosedRange<Double>? { didSet { applyZoomLimits() } }
  public var cameraBoundary: MKCoordinateRegion? { didSet { applySettings() } }
  public var mapPadding: UIEdgeInsets = .zero { didSet { applySettings() } }

  public var userTrackingMode: MKUserTrackingMode = .none {
    didSet {
      guard userTrackingMode != oldValue else { return }
      if userTrackingMode != .none {
        requestLocationPermission()
        stopFlight()
        followUser(animated: true)
      }
      updateHeadingUpdates()
      applySettings()
    }
  }

  /// Applies every map-level setting: type, styles, layers, controls,
  /// gestures, limits and padding.
  func applySettings() {
    guard let mapView else { return }
    let o = options

    // Map type: `google.mapType` wins; tile overlays that replace the map hide it.
    var type: GMSMapViewType
    switch mapStyle {
    case .standard, .muted: type = .normal
    case .hybrid: type = .hybrid
    case .imagery: type = .satellite
    }
    switch o["mapType"].string {
    case "normal": type = .normal
    case "satellite": type = .satellite
    case "hybrid": type = .hybrid
    case "terrain": type = .terrain
    case "none": type = .none
    default: break
    }
    if tileOverlays.contains(where: \.replacesMap) { type = .none }
    if mapView.mapType != type { mapView.mapType = type }

    mapView.mapStyle = combinedStyle()
    mapView.overrideUserInterfaceStyle = colorScheme
    mapView.isBuildingsEnabled = showsBuildings
    mapView.isTrafficEnabled = showsTraffic
    // Transit lines are GoogleMaps 10+ (react-native-maps pins 9.4).
    if mapView.responds(to: NSSelectorFromString("setTransitEnabled:")) {
      mapView.setValue(o["transitEnabled"].bool(false), forKey: "transitEnabled")
    }
    mapView.isIndoorEnabled = o["indoorEnabled"].bool(false)
    mapView.isMyLocationEnabled = showsUserLocation || userTrackingMode != .none
    if let background = o["backgroundColor"].color { mapView.backgroundColor = background }
    switch o["preferredFrameRate"].string {
    case "powerSave": mapView.preferredFrameRate = .powerSave
    case "conservative": mapView.preferredFrameRate = .conservative
    case "maximum": mapView.preferredFrameRate = .maximum
    default: break
    }
    mapView.accessibilityElementsHidden = o["accessibilityElementsHidden"].bool(false)

    let settings = mapView.settings
    settings.compassButton = o["compass"].bool(compassVisibility != .hidden)
    settings.myLocationButton = o["myLocationButton"].bool(showsUserTrackingButton)
    settings.indoorPicker = o["indoorLevelPicker"].bool(o["indoorEnabled"].bool(false))
    settings.zoomGestures = isZoomEnabled
    settings.scrollGestures = isScrollEnabled
    settings.rotateGestures = isRotateEnabled
    settings.tiltGestures = isPitchEnabled
    settings.allowScrollGesturesDuringRotateOrZoom = o["scrollGesturesDuringRotateOrZoom"].bool(true)
    settings.consumesGesturesInView = o["consumesGesturesInView"].bool(true)

    if let bounds = o["cameraTargetBounds"].bounds {
      mapView.cameraTargetBounds = bounds
    } else if let region = cameraBoundary {
      mapView.cameraTargetBounds = GMSCoordinateBounds(
        coordinate: CLLocationCoordinate2D(
          latitude: region.center.latitude - region.span.latitudeDelta / 2,
          longitude: region.center.longitude - region.span.longitudeDelta / 2),
        coordinate: CLLocationCoordinate2D(
          latitude: region.center.latitude + region.span.latitudeDelta / 2,
          longitude: region.center.longitude + region.span.longitudeDelta / 2))
    } else {
      mapView.cameraTargetBounds = nil
    }

    if mapView.padding != mapPadding { mapView.padding = mapPadding }
    switch o["paddingAdjustmentBehavior"].string {
    case "always": mapView.paddingAdjustmentBehavior = .always
    case "automatic": mapView.paddingAdjustmentBehavior = .automatic
    case "never": mapView.paddingAdjustmentBehavior = .never
    default: break
    }
    applyZoomLimits()
    modelLayer.setNeedsRender()
  }

  /// `cameraDistanceRange` (metres) or `google.minZoom` / `maxZoom`.
  func applyZoomLimits() {
    guard let mapView, mapView.bounds.height > 0 else { return }
    let latitude = mapView.camera.target.latitude
    var minZoom = Float(options["minZoom"].double ?? Double(kGMSMinZoomLevel))
    var maxZoom = Float(options["maxZoom"].double ?? Double(kGMSMaxZoomLevel))
    if let range = cameraDistanceRange {
      if options["maxZoom"].double == nil, range.lowerBound > 0 {
        maxZoom = Float(GoogleCameraSource.zoom(distance: range.lowerBound, latitude: latitude, height: mapView.bounds.height))
      }
      if options["minZoom"].double == nil, range.upperBound.isFinite, range.upperBound < .greatestFiniteMagnitude {
        minZoom = Float(GoogleCameraSource.zoom(distance: range.upperBound, latitude: latitude, height: mapView.bounds.height))
      }
    }
    minZoom = max(kGMSMinZoomLevel, min(minZoom, kGMSMaxZoomLevel))
    maxZoom = max(minZoom, min(maxZoom, kGMSMaxZoomLevel))
    if mapView.minZoom != minZoom || mapView.maxZoom != maxZoom {
      mapView.setMinZoom(minZoom, maxZoom: maxZoom)
    }
  }

  /// The JSON style: the muted look, hidden points of interest,
  /// `styleUrl` and `google.styleJson`. Cloud styling (`mapId`) replaces
  /// JSON styles, so none is set then.
  private func combinedStyle() -> GMSMapStyle? {
    var rules: [Any] = []
    if mapStyle == .muted {
      rules.append(["stylers": [["saturation": -60], ["lightness": 15]]])
    }
    rules.append(contentsOf: GooglePointsOfInterest.rules(for: pointOfInterestFilter))
    if let text = styleURLJSON, let parsed = Self.styleRules(text) { rules.append(contentsOf: parsed) }
    switch options["styleJson"].raw {
    case let text as String: if let parsed = Self.styleRules(text) { rules.append(contentsOf: parsed) }
    case let list as [Any]: rules.append(contentsOf: list)
    default: break
    }
    guard !rules.isEmpty else { return nil }
    if !(options["mapId"].string ?? "").isEmpty {
      onError?("Google Maps: JSON styles (styleJson, styleUrl, muted, pointsOfInterest) are ignored on a map with a mapId; style it in the Cloud console")
      return nil
    }
    guard let data = try? JSONSerialization.data(withJSONObject: rules),
          let json = String(data: data, encoding: .utf8)
    else { return nil }
    do {
      return try GMSMapStyle(jsonString: json)
    } catch {
      onError?("Google Maps: invalid styleJson: \(error.localizedDescription)")
      return nil
    }
  }

  private static func styleRules(_ text: String) -> [Any]? {
    (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [Any]
  }

  // MARK: Camera

  private func applyInitialCameraIfReady() {
    guard !appliedInitialCamera, let camera = initialCamera, let mapView, mapView.bounds.height > 0 else { return }
    appliedInitialCamera = true
    mapView.camera = position(for: camera)
    modelLayer.setNeedsRender()
  }

  /// A Google camera for a munim-maps camera (metres → zoom).
  func position(for camera: MunimCamera) -> GMSCameraPosition {
    let height = mapView?.bounds.height ?? bounds.height
    let zoom = GoogleCameraSource.zoom(distance: camera.distance, latitude: camera.latitude, height: height)
    return GMSCameraPosition(
      latitude: camera.latitude, longitude: camera.longitude, zoom: Float(zoom),
      bearing: camera.heading, viewingAngle: camera.pitch)
  }

  /// The munim-maps camera for a Google one (zoom → metres).
  func munimCamera(_ position: GMSCameraPosition) -> MunimCamera {
    if let mapView, mapView.camera.isEqual(position), let state = cameraSource?.cameraState(previous: nil) {
      return MunimCamera(
        latitude: state.latitude, longitude: state.longitude, distance: state.distance,
        pitch: state.pitch, heading: state.heading)
    }
    let height = mapView?.bounds.height ?? bounds.height
    return MunimCamera(
      latitude: position.target.latitude, longitude: position.target.longitude,
      distance: GoogleCameraSource.distance(zoom: Double(position.zoom), latitude: position.target.latitude, height: height),
      pitch: position.viewingAngle, heading: position.bearing)
  }

  public var camera: MunimCamera {
    guard let mapView else { return initialCamera ?? MunimCamera(latitude: 0, longitude: 0, distance: 10_000_000) }
    return munimCamera(mapView.camera)
  }

  public func setCamera(_ camera: MunimCamera, animated: Bool) {
    stopFlight()
    endTrackingForCameraMove()
    guard let mapView else {
      initialCamera = camera
      appliedInitialCamera = false
      return
    }
    let target = position(for: camera)
    if animated { mapView.animate(to: target) } else { mapView.camera = target }
    modelLayer.setNeedsRender()
  }

  /// Moves the camera over `duration` seconds, stepped once a frame so the
  /// 3D layer reads the camera Google is drawing.
  public func animateCamera(_ camera: MunimCamera, duration: TimeInterval, linear: Bool) {
    guard duration > 0 else { return setCamera(camera, animated: false) }
    let from = self.camera
    let steps = linear ? 1 : 24
    let keyframes = (0...steps).map { i -> MunimCameraKeyframe in
      let x = Double(i) / Double(steps)
      let eased = linear ? x : x * x * (3 - 2 * x)
      return MunimCameraKeyframe(t: x * duration, camera: Self.interpolate(from, camera, eased))
    }
    flyCamera(keyframes, start: Date().timeIntervalSince1970, loop: false)
  }

  public func flyCamera(_ keyframes: [MunimCameraKeyframe], start: Double, loop: Bool) {
    guard keyframes.count > 1 else {
      stopFlight()
      if let only = keyframes.first { setCamera(only.camera, animated: false) }
      return
    }
    endTrackingForCameraMove()
    if flight == nil { emit("cameraMoveStarted", ["reason": "developerAnimation"]) }
    flight = (keyframes.sorted { $0.t < $1.t }, start, loop)
    if flightLink == nil {
      let link = CADisplayLink(target: GoogleFlightTarget(self), selector: #selector(GoogleFlightTarget.tick))
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
      link.add(to: .main, forMode: .common)
      flightLink = link
    }
    stepFlight()
  }

  public func stopFlight() {
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
      let a = flight.keyframes[i - 1]
      let b = flight.keyframes[i]
      camera = Self.interpolate(a.camera, b.camera, (t - a.t) / max(1e-9, b.t - a.t))
    }
    mapView?.camera = position(for: camera)
    modelLayer.setNeedsRender()
  }

  static func interpolate(_ a: MunimCamera, _ b: MunimCamera, _ f: Double) -> MunimCamera {
    let turn = ((b.heading - a.heading).truncatingRemainder(dividingBy: 360) + 540)
      .truncatingRemainder(dividingBy: 360) - 180
    return MunimCamera(
      latitude: a.latitude + (b.latitude - a.latitude) * f,
      longitude: a.longitude + (b.longitude - a.longitude) * f,
      distance: exp(log(max(1, a.distance)) + (log(max(1, b.distance)) - log(max(1, a.distance))) * f),
      pitch: a.pitch + (b.pitch - a.pitch) * f,
      heading: (a.heading + turn * f + 360).truncatingRemainder(dividingBy: 360))
  }

  public var visibleRegion: MKCoordinateRegion {
    guard let mapView else {
      return MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: camera.latitude, longitude: camera.longitude),
        span: MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0))
    }
    return GoogleCameraSource.region(GMSCoordinateBounds(region: mapView.projection.visibleRegion()))
  }

  public func setRegion(_ region: MKCoordinateRegion, duration: TimeInterval) {
    stopFlight()
    endTrackingForCameraMove()
    let bounds = GMSCoordinateBounds(
      coordinate: CLLocationCoordinate2D(
        latitude: region.center.latitude - region.span.latitudeDelta / 2,
        longitude: region.center.longitude - region.span.longitudeDelta / 2),
      coordinate: CLLocationCoordinate2D(
        latitude: region.center.latitude + region.span.latitudeDelta / 2,
        longitude: region.center.longitude + region.span.longitudeDelta / 2))
    move(GMSCameraUpdate.fit(bounds, withPadding: 0), duration: duration)
  }

  /// Applies a camera update, animated over `duration` seconds (0 jumps).
  func move(_ update: GMSCameraUpdate, duration: TimeInterval) {
    guard let mapView else { return }
    if duration <= 0 {
      mapView.moveCamera(update)
    } else {
      CATransaction.begin()
      CATransaction.setAnimationDuration(duration)
      mapView.animate(with: update)
      CATransaction.commit()
    }
    modelLayer.setNeedsRender()
  }

  public func fit(coordinates: [CLLocationCoordinate2D], padding: UIEdgeInsets, animated: Bool) {
    guard !coordinates.isEmpty else { return }
    stopFlight()
    endTrackingForCameraMove()
    if coordinates.count == 1 {
      move(GMSCameraUpdate.setTarget(coordinates[0]), duration: animated ? 0.35 : 0)
      return
    }
    var bounds = GMSCoordinateBounds()
    for c in coordinates { bounds = bounds.includingCoordinate(c) }
    move(GMSCameraUpdate.fit(bounds, with: padding), duration: animated ? 0.35 : 0)
  }

  public func fitMarkers(_ ids: Set<String>, padding: UIEdgeInsets, animated: Bool) {
    let coordinates = markerData.values
      .filter { ids.isEmpty || ids.contains($0.id) }
      .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    fit(coordinates: coordinates, padding: padding, animated: animated)
  }

  public func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
    mapView?.projection.point(for: coordinate) ?? .zero
  }

  public func coordinate(for point: CGPoint) -> CLLocationCoordinate2D {
    mapView?.projection.coordinate(for: point) ?? kCLLocationCoordinate2DInvalid
  }

  // MARK: User location and tracking

  func requestLocationPermission() {
    if locationManager.authorizationStatus == .notDetermined {
      locationManager.requestWhenInUseAuthorization()
    }
  }

  private func myLocationChanged(_ location: CLLocation?) {
    guard let location else { return }
    onUserLocationChange?(location)
    if userTrackingMode != .none { followUser(animated: true) }
  }

  private func followUser(animated: Bool) {
    guard let mapView, let location = mapView.myLocation else { return }
    let current = mapView.camera
    var bearing = current.bearing
    if userTrackingMode == .followWithHeading {
      if lastHeading >= 0 { bearing = lastHeading } else if location.course >= 0 { bearing = location.course }
    }
    let target = GMSCameraPosition(
      target: location.coordinate, zoom: max(current.zoom, 15), bearing: bearing,
      viewingAngle: current.viewingAngle)
    if animated { mapView.animate(to: target) } else { mapView.camera = target }
  }

  private func updateHeadingUpdates() {
    if userTrackingMode == .followWithHeading, CLLocationManager.headingAvailable() {
      let delegate = GoogleHeadingDelegate { [weak self] heading in
        guard let self else { return }
        self.lastHeading = heading
        if self.userTrackingMode == .followWithHeading { self.followUser(animated: false) }
      }
      headingDelegate = delegate
      locationManager.delegate = delegate
      locationManager.startUpdatingHeading()
    } else {
      locationManager.stopUpdatingHeading()
      lastHeading = -1
    }
  }

  /// A camera move by the app or the user ends following, like MapKit.
  func endTrackingForCameraMove() {
    guard userTrackingMode != .none else { return }
    userTrackingMode = .none
    onUserTrackingModeChange?(.none)
  }

  // MARK: Methods

  public func snapshot(size: CGSize?, completion: @escaping (Result<URL, Error>) -> Void) {
    guard let mapView, mapView.bounds.width > 0 else {
      return completion(.failure(MunimMapEngineError("Google Maps: the map has no size yet")))
    }
    let target = size ?? mapView.bounds.size
    let format = UIGraphicsImageRendererFormat()
    format.scale = window?.screen.scale ?? UIScreen.main.scale
    let image = UIGraphicsImageRenderer(size: target, format: format).image { _ in
      mapView.drawHierarchy(in: CGRect(origin: .zero, size: target), afterScreenUpdates: true)
    }
    guard let data = image.pngData() else {
      return completion(.failure(MunimMapEngineError("Google Maps: could not encode the snapshot")))
    }
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("munim-maps-google-\(UUID().uuidString).png")
    do {
      try data.write(to: url)
      completion(.success(url))
    } catch {
      completion(.failure(error))
    }
  }

  public func address(
    for coordinate: CLLocationCoordinate2D, completion: @escaping (Result<MunimAddress, Error>) -> Void
  ) {
    GMSGeocoder().reverseGeocodeCoordinate(coordinate) { response, error in
      if let address = response?.firstResult() {
        let lines = address.lines ?? []
        completion(.success(MunimAddress(
          name: lines.first ?? address.thoroughfare ?? "",
          street: address.thoroughfare ?? "",
          city: address.locality ?? "",
          region: address.administrativeArea ?? "",
          postalCode: address.postalCode ?? "",
          country: address.country ?? "",
          countryCode: "",
          formatted: lines.joined(separator: ", "))))
        return
      }
      // Google's geocoder needs the Geocoding API on the key; fall back to Apple's.
      CLGeocoder().reverseGeocodeLocation(
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
      ) { placemarks, appleError in
        guard let p = placemarks?.first else {
          completion(.failure(error ?? appleError ?? MunimMapEngineError("No address here")))
          return
        }
        let street = [p.subThoroughfare, p.thoroughfare].compactMap { $0 }.joined(separator: " ")
        completion(.success(MunimAddress(
          name: p.name ?? "", street: street, city: p.locality ?? "", region: p.administrativeArea ?? "",
          postalCode: p.postalCode ?? "", country: p.country ?? "", countryCode: p.isoCountryCode ?? "",
          formatted: [street, p.locality, p.administrativeArea, p.postalCode, p.country]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "))))
      }
    }
  }

  /// Street View is Google's Look Around.
  public func hasLookAround(at coordinate: CLLocationCoordinate2D, completion: @escaping (Bool) -> Void) {
    panoramaService.requestPanoramaNearCoordinate(coordinate) { panorama, _ in
      completion(panorama != nil)
    }
  }

  public func openLookAround(at coordinate: CLLocationCoordinate2D, completion: @escaping (Bool) -> Void) {
    openStreetView(GoogleJSON(["latitude": coordinate.latitude, "longitude": coordinate.longitude,
                               "presentation": "fullScreen"])) { result in
      if case .success = result { completion(true) } else { completion(false) }
    }
  }
}

// MARK: - GMSMapViewDelegate

extension GoogleMapEngine: GMSMapViewDelegate {
  public func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
    if gesture {
      stopFlight()
      endTrackingForCameraMove()
    }
    emit("cameraMoveStarted", ["reason": gesture ? "gesture" : "apiAnimation"])
  }

  public func mapView(_ mapView: GMSMapView, didChange position: GMSCameraPosition) {
    modelLayer.setNeedsRender()
    onCameraMove?(munimCamera(position))
  }

  public func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
    modelLayer.setNeedsRender()
    updateDashesIfZoomChanged()
    onCameraChange?(munimCamera(position))
  }

  public func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
    let point = mapView.projection.point(for: coordinate)
    if modelLayer.modelHit(at: point) != nil { return }  // models have their own event
    if let id = selectedMarkerId {
      selectedMarkerId = nil
      mapView.selectedMarker = nil
      onMarkerDeselect?(id)
    }
    if onOverlayPress != nil, let hit = overlayHit(at: point) {
      onOverlayPress?(hit.id, hit.kind, coordinate)
      return
    }
    onPress?(coordinate, point)
  }

  public func mapView(_ mapView: GMSMapView, didLongPressAt coordinate: CLLocationCoordinate2D) {
    onLongPress?(coordinate, mapView.projection.point(for: coordinate))
  }

  public func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
    markerTapped(marker)
  }

  public func mapView(_ mapView: GMSMapView, didTapInfoWindowOf marker: GMSMarker) {
    guard let id = marker.userData as? String else { return }
    onCalloutPress?(id)
    emit("infoWindowPress", ["id": id])
  }

  public func mapView(_ mapView: GMSMapView, didLongPressInfoWindowOf marker: GMSMarker) {
    guard let id = marker.userData as? String else { return }
    emit("infoWindowLongPress", ["id": id])
  }

  public func mapView(_ mapView: GMSMapView, didCloseInfoWindowOf marker: GMSMarker) {
    guard let id = marker.userData as? String else { return }
    emit("infoWindowClose", ["id": id])
  }

  public func mapView(_ mapView: GMSMapView, markerInfoWindow marker: GMSMarker) -> UIView? {
    infoWindow(for: marker)
  }

  public func mapView(_ mapView: GMSMapView, didTap overlay: GMSOverlay) {
    overlayTapped(overlay)
  }

  public func mapView(
    _ mapView: GMSMapView, didTapPOIWithPlaceID placeID: String, name: String, location: CLLocationCoordinate2D
  ) {
    onMapFeaturePress?(MunimMapFeature(
      title: name, coordinate: location, kind: "pointOfInterest", category: "", id: placeID))
    emit("poiClick", ["placeId": placeID, "name": name, "latitude": location.latitude, "longitude": location.longitude])
  }

  public func mapView(_ mapView: GMSMapView, didBeginDragging marker: GMSMarker) {
    guard let id = marker.userData as? String else { return }
    onMarkerDragStart?(id, marker.position)
  }

  public func mapView(_ mapView: GMSMapView, didDrag marker: GMSMarker) {
    guard let id = marker.userData as? String else { return }
    onMarkerDrag?(id, marker.position)
    emit("markerDrag", ["id": id, "latitude": marker.position.latitude, "longitude": marker.position.longitude])
  }

  public func mapView(_ mapView: GMSMapView, didEndDragging marker: GMSMarker) {
    guard let id = marker.userData as? String else { return }
    markerData[id]?.latitude = marker.position.latitude
    markerData[id]?.longitude = marker.position.longitude
    onMarkerDragEnd?(id, marker.position)
  }

  public func didTapMyLocationButton(for mapView: GMSMapView) -> Bool {
    emit("myLocationButtonPress")
    return false
  }

  public func mapView(_ mapView: GMSMapView, didTapMyLocation location: CLLocationCoordinate2D) {
    emit("myLocationPress", GoogleOut.coordinate(location))
  }

  public func mapViewDidStartTileRendering(_ mapView: GMSMapView) {
    emit("tilesRenderingStarted")
  }

  public func mapViewDidFinishTileRendering(_ mapView: GMSMapView) {
    emit("tilesRenderingFinished")
    if !tilesLoaded {
      tilesLoaded = true
      emit("mapLoaded")
    }
    reportReady()
  }

  public func mapViewSnapshotReady(_ mapView: GMSMapView) {
    emit("snapshotReady")
  }

  public func mapView(_ mapView: GMSMapView, didChange mapCapabilities: GMSMapCapabilityFlags) {
    emit("mapCapabilitiesChanged", Self.capabilities(mapCapabilities))
  }

  public func mapView(
    _ mapView: GMSMapView, didTap features: [Feature], in featureLayer: FeatureLayer<Feature>,
    atLocation location: CLLocationCoordinate2D
  ) {
    featuresTapped(features, layer: featureLayer, at: location)
  }

  static func capabilities(_ flags: GMSMapCapabilityFlags) -> [String: Any] {
    ["advancedMarkers": flags.contains(.advancedMarkers),
     "dataDrivenStyling": flags.contains(.dataDrivenStyling),
     "spritePolylines": flags.contains(.spritePolylines)]
  }
}

// MARK: - Indoor

extension GoogleMapEngine: GMSIndoorDisplayDelegate {
  public func didChangeActiveBuilding(_ building: GMSIndoorBuilding?) {
    emit("indoorBuildingFocused", Self.building(building, active: mapView?.indoorDisplay.activeLevel))
  }

  public func didChangeActiveLevel(_ level: GMSIndoorLevel?) {
    let building = mapView?.indoorDisplay.activeBuilding
    let index = building?.levels.firstIndex { $0 === level } ?? -1
    emit("indoorLevelActivated", [
      "name": level?.name ?? "", "shortName": level?.shortName ?? "", "index": index,
      "building": Self.building(building, active: level),
    ])
  }

  static func building(_ building: GMSIndoorBuilding?, active: GMSIndoorLevel?) -> [String: Any] {
    guard let building else { return [:] }
    return [
      "levels": building.levels.map { ["name": $0.name ?? "", "shortName": $0.shortName ?? ""] },
      "defaultLevelIndex": building.defaultLevelIndex,
      "activeLevelIndex": building.levels.firstIndex { $0 === active } ?? -1,
      "underground": building.isUnderground,
    ]
  }
}

/// Breaks the retain cycle between the flight's `CADisplayLink` and the engine.
private final class GoogleFlightTarget: NSObject {
  weak var owner: GoogleMapEngine?

  init(_ owner: GoogleMapEngine) {
    self.owner = owner
  }

  @objc func tick() {
    owner?.stepFlight()
  }
}

/// Compass headings for `followWithHeading`.
final class GoogleHeadingDelegate: NSObject, CLLocationManagerDelegate {
  private let onHeading: (CLLocationDirection) -> Void

  init(_ onHeading: @escaping (CLLocationDirection) -> Void) {
    self.onHeading = onHeading
  }

  func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
    let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    onHeading(heading)
  }
}

/// MapKit's point-of-interest categories as Google JSON style rules.
enum GooglePointsOfInterest {
  /// Google's POI feature types, each shown when any of these MapKit
  /// categories is included.
  private static let groups: [(String, [MKPointOfInterestCategory])] = [
    ("poi.attraction", [.amusementPark, .aquarium, .museum, .theater, .zoo, .movieTheater, .stadium]),
    ("poi.business", [.bakery, .bank, .brewery, .cafe, .carRental, .evCharger, .foodMarket, .gasStation,
                      .hotel, .laundry, .nightlife, .parking, .restaurant, .store, .winery, .atm]),
    ("poi.government", [.fireStation, .police, .postOffice, .library]),
    ("poi.medical", [.hospital, .pharmacy]),
    ("poi.park", [.park, .nationalPark, .beach, .campground, .marina]),
    ("poi.school", [.school, .university]),
    ("poi.sports_complex", [.fitnessCenter, .stadium]),
    ("transit.station", [.publicTransport, .airport]),
  ]

  static func rules(for filter: MKPointOfInterestFilter) -> [Any] {
    var hidden: [String] = []
    for (type, categories) in groups where !categories.contains(where: { filter.includes($0) }) {
      hidden.append(type)
    }
    if hidden.count == groups.count {
      return [["featureType": "poi", "stylers": [["visibility": "off"]]],
              ["featureType": "transit.station", "stylers": [["visibility": "off"]]]]
    }
    return hidden.map { ["featureType": $0, "stylers": [["visibility": "off"]]] }
  }
}
#endif
