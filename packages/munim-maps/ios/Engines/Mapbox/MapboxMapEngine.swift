#if canImport(MapboxMaps)
@_spi(Experimental) import MapboxMaps
import MapKit
import UIKit
import simd

// The Mapbox engine: Mapbox Maps SDK v11 (`MapView`), compiled only with the
// `NitroMunimMaps/Mapbox` subspec. Everything Mapbox-only is driven by the
// `mapbox={{…}}` options (`MapboxStyleOptions.swift`), the `providerCommand`
// methods (`MapboxCalls.swift`) and the engine-level offline calls
// (`MapboxOffline.swift`); markers, shapes and MarkerViews are in
// `MapboxContent.swift`. The JavaScript side is src/providers/mapbox.ts.

enum MapboxMapEngineFactory: MunimMapEngineFactory {
  static let isImplemented = true
  static func make() -> MunimMapEngine { MapboxMapEngine() }

  static func providerCommand(
    _ command: String, arguments: [String: Any], emit: @escaping (String, Any) -> Void,
    completion: @escaping (Result<Any, Error>) -> Void
  ) {
    MapboxOffline.call(command, args: arguments, emit: emit, completion: completion)
  }
}

/// Mapbox Maps SDK v11 behind `MunimMapView`, with munim-maps' SceneKit 3D
/// layer over it.
final class MapboxMapEngine: UIView, MunimMapEngine, MunimMapEngineDefaults {
  let provider = MunimMapProvider.mapbox
  var view: UIView { self }
  let modelLayer = MunimModelLayer()

  let mapView: MapView
  var mapboxMap: MapboxMap { mapView.mapboxMap }
  /// Signal subscriptions for the map's lifetime.
  var cancelables = Set<AnyCancelable>()
  /// Subscriptions for `mapbox.events`, replaced when the list changes.
  var eventCancelables: [String: AnyCancelable] = [:]
  lazy var cameraSource = MapboxCameraSource(engine: self)
  let content = MapboxContentState()
  var style = MapboxStyleState()

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
  var onMarkerDrag: ((String, CLLocationCoordinate2D) -> Void)?
  var onUserLocationChange: ((CLLocation) -> Void)?
  var onMapFeaturePress: ((MunimMapFeature) -> Void)?
  var onUserTrackingModeChange: ((MKUserTrackingMode) -> Void)?
  var onError: ((String) -> Void)?
  var onProviderEvent: ((String, Any) -> Void)?

  // MARK: Life

  private var reportedReady = false
  private var appliedInitialCamera = false
  private var lastIdleCamera: MunimCamera?
  private var configObserver: NSObjectProtocol?

  init() {
    let token = MunimMapsConfiguration.shared.mapboxAccessToken
    if !token.isEmpty { MapboxOptions.accessToken = token }
    mapView = MapView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), mapInitOptions: MapInitOptions())
    super.init(frame: .zero)
    mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    mapView.frame = bounds
    addSubview(mapView)
    modelLayer.view.frame = bounds
    modelLayer.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(modelLayer.view)
    modelLayer.onError = { [weak self] message in self?.onError?(message) }
    modelLayer.attach(to: cameraSource)
    // Map frames go out in Core Animation transactions, so the 3D layer and
    // the map land in the same frame.
    mapView.presentationTransactionMode = .sync
    mapView.ornaments.options.scaleBar.visibility = .hidden
    mapView.ornaments.options.compass.visibility = .adaptive
    subscribe()
    if token.isEmpty {
      DispatchQueue.main.async { [weak self] in
        self?.onError?("Mapbox: no access token. Set mapboxAccessToken with configureMunimMaps or the config plugin (MBXAccessToken in Info.plist).")
      }
    }
    configObserver = NotificationCenter.default.addObserver(
      forName: MunimMapsConfiguration.didChange, object: nil, queue: .main
    ) { [weak self] _ in self?.configurationChanged() }
    loadStyleIfNeeded()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  deinit {
    if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    flightLink?.invalidate()
  }

  private func configurationChanged() {
    let token = MunimMapsConfiguration.shared.mapboxAccessToken
    if !token.isEmpty, MapboxOptions.accessToken != token {
      MapboxOptions.accessToken = token
      style.loadedStyleKey = nil
    }
    loadStyleIfNeeded()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    applyInitialCameraIfReady()
    content.trackingButton?.frame = trackingButtonFrame()
    modelLayer.setNeedsRender()
  }

  private func subscribe() {
    mapboxMap.onStyleLoaded.observe { [weak self] _ in self?.styleLoaded() }.store(in: &cancelables)
    mapboxMap.onMapLoadingError.observe { [weak self] error in
      self?.onError?("Mapbox: \(error.message)")
    }.store(in: &cancelables)
    mapboxMap.onCameraChanged.observe { [weak self] _ in self?.cameraChanged() }.store(in: &cancelables)
    mapboxMap.onMapIdle.observe { [weak self] _ in self?.mapIdle() }.store(in: &cancelables)
    // Map-wide interactions run after annotations and featuresets had their turn.
    AnyCancelable(mapboxMap.addInteraction(TapInteraction { [weak self] context in
      self?.tapped(context)
      return false
    })).store(in: &cancelables)
    AnyCancelable(mapboxMap.addInteraction(LongPressInteraction { [weak self] context in
      self?.onLongPress?(context.coordinate, context.point)
      return false
    })).store(in: &cancelables)
    mapView.location.onLocationChange.observe { [weak self] locations in
      guard let self, let location = locations.last else { return }
      self.onUserLocationChange?(CLLocation(
        coordinate: location.coordinate,
        altitude: location.altitude ?? 0,
        horizontalAccuracy: location.horizontalAccuracy ?? -1,
        verticalAccuracy: location.verticalAccuracy ?? -1,
        course: location.bearing ?? -1,
        speed: location.speed ?? -1,
        timestamp: location.timestamp))
    }.store(in: &cancelables)
    mapView.viewport.addStatusObserver(self)
  }

  private func styleLoaded() {
    applyStyleOptions(reloaded: true)
    reapplyContent()
    modelLayer.setNeedsRender()
    if !reportedReady {
      reportedReady = true
      onMapReady?()
    }
  }

  private func cameraChanged() {
    modelLayer.setNeedsRender()
    content.trackingButton.map { _ in updateTrackingButton() }
    onCameraMove?(camera)
  }

  private func mapIdle() {
    modelLayer.setNeedsRender()
    let now = camera
    if let last = lastIdleCamera, last.isClose(to: now) { return }
    lastIdleCamera = now
    onCameraChange?(now)
  }

  private func tapped(_ context: InteractionContext) {
    let point = context.point
    if modelLayer.modelHit(at: point) != nil { return } // models report their own taps
    // View annotations (MarkerViews, callouts) take their own taps.
    let annotationViews = content.viewMarkers.values.map { $0.imageView as UIView } + [content.callout?.view].compactMap { $0 }
    if annotationViews.contains(where: { !$0.isHidden && $0.superview != nil && $0.convert($0.bounds, to: mapView).contains(point) }) {
      return
    }
    if content.selectedMarker != nil { deselectMarker(content.selectedMarker ?? "") }
    if onOverlayPress != nil {
      overlayHit(at: point) { [weak self] hit in
        guard let self else { return }
        if let hit {
          self.onOverlayPress?(hit.id, hit.kind, context.coordinate)
        } else {
          self.onPress?(context.coordinate, point)
        }
      }
      return
    }
    onPress?(context.coordinate, point)
  }

  // MARK: Style

  var styleURL = "" { didSet { if oldValue != styleURL { loadStyleIfNeeded() } } }

  var providerOptions: [String: Any] = [:] {
    didSet {
      style.options = providerOptions
      loadStyleIfNeeded()
      if mapboxMap.isStyleLoaded { applyStyleOptions(reloaded: false) }
      applyMapOptions()
    }
  }

  var mapStyle: MunimMapStyle = .standard { didSet { if oldValue != mapStyle { styleInputsChanged() } } }
  var elevation: MunimElevation = .realistic { didSet { if oldValue != elevation { styleInputsChanged() } } }
  var globe = false { didSet { if oldValue != globe { styleInputsChanged() } } }
  var colorScheme: UIUserInterfaceStyle = .unspecified { didSet { styleInputsChanged() } }
  var showsBuildings = true { didSet { if oldValue != showsBuildings { styleInputsChanged() } } }
  var showsTraffic = false { didSet { if oldValue != showsTraffic { styleInputsChanged() } } }
  var pointOfInterestFilter: MKPointOfInterestFilter = .includingAll {
    didSet { styleInputsChanged() }
  }

  override func traitCollectionDidChange(_ previous: UITraitCollection?) {
    super.traitCollectionDidChange(previous)
    if colorScheme == .unspecified, previous?.userInterfaceStyle != traitCollection.userInterfaceStyle {
      styleInputsChanged()
    }
  }

  /// Whether the map should look dark (`colorScheme`, else the system).
  var isDark: Bool {
    switch colorScheme {
    case .dark: return true
    case .light: return false
    default: return traitCollection.userInterfaceStyle == .dark
    }
  }

  private func styleInputsChanged() {
    loadStyleIfNeeded()
    if mapboxMap.isStyleLoaded { applyStyleOptions(reloaded: false) }
  }

  // MARK: Look

  var showsUserLocation = false { didSet { applyLocation() } }

  var compassVisibility: MunimFeatureVisibility = .adaptive { didSet { applyOrnaments() } }
  var scaleVisibility: MunimFeatureVisibility = .hidden { didSet { applyOrnaments() } }
  var showsUserTrackingButton = false { didSet { updateTrackingButton() } }
  var selectableFeatures: Set<MunimMapFeatureKind> = [] { didSet { applyInteractions() } }

  // MARK: Gestures and limits

  var userTrackingMode: MKUserTrackingMode = .none {
    didSet { if oldValue != userTrackingMode { applyTrackingMode() } }
  }

  var isZoomEnabled = true { didSet { applyGestures() } }
  var isScrollEnabled = true { didSet { applyGestures() } }
  var isRotateEnabled = true { didSet { applyGestures() } }
  var isPitchEnabled = true { didSet { applyGestures() } }

  var cameraDistanceRange: ClosedRange<Double>? { didSet { applyCameraBounds() } }
  var cameraBoundary: MKCoordinateRegion? { didSet { applyCameraBounds() } }

  var mapPadding: UIEdgeInsets = .zero {
    didSet {
      guard oldValue != mapPadding else { return }
      mapboxMap.setCamera(to: CameraOptions(padding: mapPadding))
      modelLayer.setNeedsRender()
    }
  }

  // MARK: Camera: munim-maps speaks metres from the camera, Mapbox zoom levels.

  /// Mapbox's vertical field of view: 2 atan(1/3), about 36.87°.
  static let fieldOfView = 0.6435011087932844
  static let tileSize = 512.0
  static let earthCircumference = 2 * Double.pi * 6_378_137

  private var viewHeight: Double { bounds.height > 1 ? Double(bounds.height) : 800 }

  static func metersPerPoint(zoom: Double, latitude: Double) -> Double {
    cos(latitude * .pi / 180) * earthCircumference / (tileSize * pow(2, zoom))
  }

  func distance(zoom: Double, latitude: Double) -> Double {
    viewHeight / 2 / tan(Self.fieldOfView / 2) * Self.metersPerPoint(zoom: zoom, latitude: latitude)
  }

  func zoom(distance: Double, latitude: Double) -> Double {
    let points = viewHeight / 2 / tan(Self.fieldOfView / 2)
    return log2(points * cos(latitude * .pi / 180) * Self.earthCircumference / (Self.tileSize * max(0.01, distance)))
  }

  func cameraOptions(_ camera: MunimCamera) -> CameraOptions {
    CameraOptions(
      center: CLLocationCoordinate2D(latitude: camera.latitude, longitude: camera.longitude),
      zoom: zoom(distance: camera.distance, latitude: camera.latitude),
      bearing: camera.heading,
      pitch: camera.pitch)
  }

  var camera: MunimCamera {
    let state = mapboxMap.cameraState
    return MunimCamera(
      latitude: state.center.latitude, longitude: state.center.longitude,
      distance: distance(zoom: state.zoom, latitude: state.center.latitude),
      pitch: Double(state.pitch), heading: state.bearing)
  }

  var initialCamera: MunimCamera? { didSet { applyInitialCameraIfReady() } }

  private func applyInitialCameraIfReady() {
    guard !appliedInitialCamera, let initialCamera, bounds.height > 1 else { return }
    appliedInitialCamera = true
    mapboxMap.setCamera(to: cameraOptions(initialCamera))
  }

  /// A camera move from JavaScript ends user tracking, like MapKit.
  func endTrackingForCameraMove() {
    guard userTrackingMode != .none else { return }
    userTrackingMode = .none
    onUserTrackingModeChange?(.none)
  }

  func setCamera(_ camera: MunimCamera, animated: Bool) {
    stopFlight()
    endTrackingForCameraMove()
    if animated {
      mapView.camera.ease(to: cameraOptions(camera), duration: 0.35, curve: .easeInOut)
    } else {
      mapboxMap.setCamera(to: cameraOptions(camera))
    }
    modelLayer.setNeedsRender()
  }

  func animateCamera(_ camera: MunimCamera, duration: TimeInterval, linear: Bool) {
    stopFlight()
    endTrackingForCameraMove()
    guard duration > 0 else { return setCamera(camera, animated: false) }
    mapView.camera.ease(to: cameraOptions(camera), duration: duration, curve: linear ? .linear : .easeInOut)
  }

  private var flight: (keyframes: [MunimCameraKeyframe], start: Double, loop: Bool)?
  private var flightLink: CADisplayLink?

  func flyCamera(_ keyframes: [MunimCameraKeyframe], start: Double, loop: Bool) {
    guard keyframes.count > 1 else {
      stopFlight()
      if let only = keyframes.first { setCamera(only.camera, animated: false) }
      return
    }
    endTrackingForCameraMove()
    mapView.camera.cancelAnimations()
    flight = (keyframes.sorted { $0.t < $1.t }, start, loop)
    if flightLink == nil {
      let link = CADisplayLink(target: MapboxFlightTarget(self), selector: #selector(MapboxFlightTarget.tick))
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
      link.add(to: .main, forMode: .common)
      flightLink = link
    }
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
      let a = flight.keyframes[i - 1]
      let b = flight.keyframes[i]
      camera = Self.interpolate(a.camera, b.camera, (t - a.t) / max(1e-9, b.t - a.t))
    }
    mapboxMap.setCamera(to: cameraOptions(camera))
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

  var visibleRegion: MKCoordinateRegion {
    let b = mapboxMap.coordinateBounds(for: CameraOptions(cameraState: mapboxMap.cameraState))
    return MKCoordinateRegion(
      center: CLLocationCoordinate2D(
        latitude: (b.southwest.latitude + b.northeast.latitude) / 2,
        longitude: (b.southwest.longitude + b.northeast.longitude) / 2),
      span: MKCoordinateSpan(
        latitudeDelta: abs(b.northeast.latitude - b.southwest.latitude),
        longitudeDelta: abs(b.northeast.longitude - b.southwest.longitude)))
  }

  func setRegion(_ region: MKCoordinateRegion, duration: TimeInterval) {
    let sw = CLLocationCoordinate2D(
      latitude: region.center.latitude - region.span.latitudeDelta / 2,
      longitude: region.center.longitude - region.span.longitudeDelta / 2)
    let ne = CLLocationCoordinate2D(
      latitude: region.center.latitude + region.span.latitudeDelta / 2,
      longitude: region.center.longitude + region.span.longitudeDelta / 2)
    frame(coordinates: [sw, ne], padding: .zero, duration: duration)
  }

  func fit(coordinates: [CLLocationCoordinate2D], padding: UIEdgeInsets, animated: Bool) {
    frame(coordinates: coordinates, padding: padding, duration: animated ? 0.5 : 0)
  }

  func fitMarkers(_ ids: Set<String>, padding: UIEdgeInsets, animated: Bool) {
    let all = markers + content.viewMarkers.values.map(\.marker)
    let coordinates = all.filter { ids.isEmpty || ids.contains($0.id) }
      .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    fit(coordinates: coordinates, padding: padding, animated: animated)
  }

  private func frame(coordinates: [CLLocationCoordinate2D], padding: UIEdgeInsets, duration: TimeInterval) {
    guard !coordinates.isEmpty else { return }
    stopFlight()
    endTrackingForCameraMove()
    let state = mapboxMap.cameraState
    let target: CameraOptions
    if coordinates.count == 1 {
      target = CameraOptions(center: coordinates[0])
    } else {
      guard let fitted = try? mapboxMap.camera(
        for: coordinates,
        camera: CameraOptions(padding: mapPadding, bearing: state.bearing, pitch: state.pitch),
        coordinatesPadding: padding, maxZoom: nil, offset: nil)
      else { return }
      target = fitted
    }
    if duration > 0 {
      mapView.camera.ease(to: target, duration: duration, curve: .easeInOut)
    } else {
      mapboxMap.setCamera(to: target)
    }
  }

  func point(for coordinate: CLLocationCoordinate2D) -> CGPoint { mapboxMap.point(for: coordinate) }
  func coordinate(for point: CGPoint) -> CLLocationCoordinate2D { mapboxMap.coordinate(for: point) }

  // MARK: Methods

  func snapshot(size: CGSize?, completion: @escaping (Result<URL, Error>) -> Void) {
    do {
      var image = try mapView.snapshot(includeOverlays: false)
      if let size, size.width > 0, size.height > 0, size != image.size {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
          image.draw(in: CGRect(origin: .zero, size: size))
        }
      }
      completion(Result { try MapboxFiles.writePNG(image, prefix: "mapbox-snapshot") })
    } catch {
      completion(.failure(error))
    }
  }

  func address(for coordinate: CLLocationCoordinate2D, completion: @escaping (Result<MunimAddress, Error>) -> Void) {
    MapboxGeocoder.reverse(coordinate, completion: completion)
  }

  func providerCommand(
    _ command: String, arguments: [String: Any], completion: @escaping (Result<Any, Error>) -> Void
  ) {
    MapboxCalls.call(command, args: arguments, engine: self, completion: completion)
  }

  func setProviderEventHandler(_ handler: ((String, Any) -> Void)?) {
    onProviderEvent = handler
  }

  /// Sends a Mapbox event when it is in `mapbox.events`, or always for `interaction`.
  func emit(_ name: String, _ payload: Any) {
    onProviderEvent?(name, MunimProviderJSON.sanitize(payload))
  }
}

/// Breaks the retain cycle between the flight's `CADisplayLink` and the engine.
private final class MapboxFlightTarget: NSObject {
  weak var engine: MapboxMapEngine?
  init(_ engine: MapboxMapEngine) { self.engine = engine }
  @objc func tick() { engine?.stepFlight() }
}

extension MapboxMapEngine: ViewportStatusObserver {
  func viewportStatusDidChange(from fromStatus: ViewportStatus, to toStatus: ViewportStatus, reason: ViewportStatusChangeReason) {
    // The user panned away while following: tracking drops back to none.
    if toStatus == .idle, reason == .userInteraction, userTrackingMode != .none {
      userTrackingMode = .none
      onUserTrackingModeChange?(.none)
    }
    emit("viewportStatus", ["status": Self.describe(toStatus), "reason": Self.describe(reason)])
  }

  static func describe(_ reason: ViewportStatusChangeReason) -> String {
    switch reason {
    case .idleRequested: return "idleRequested"
    case .transitionStarted: return "transitionStarted"
    case .transitionSucceeded: return "transitionSucceeded"
    case .transitionFailed: return "transitionFailed"
    case .userInteraction: return "userInteraction"
    default: return "other"
    }
  }

  static func describe(_ status: ViewportStatus) -> String {
    switch status {
    case .idle: return "idle"
    case .state: return "state"
    case .transition: return "transition"
    }
  }
}

extension MunimCamera {
  func isClose(to other: MunimCamera) -> Bool {
    abs(latitude - other.latitude) < 1e-9 && abs(longitude - other.longitude) < 1e-9
      && abs(distance - other.distance) < 1e-3 * max(1, distance)
      && abs(pitch - other.pitch) < 1e-6 && abs(heading - other.heading) < 1e-6
  }
}

/// Mapbox's camera for the 3D layer.
///
/// Mapbox draws with a pinhole camera of 36.87° vertical field of view and
/// 512-point tiles; zoom gives the distance to the centre. With camera
/// padding Mapbox moves the centre of perspective to the middle of the
/// padded area, so the camera's axis goes through the centre coordinate and
/// the projection is off-centre: that case passes an exact camera transform
/// and projection.
final class MapboxCameraSource: MapCameraSource {
  weak var engine: MapboxMapEngine?
  init(engine: MapboxMapEngine) { self.engine = engine }

  var cameraView: UIView? { engine?.mapView }

  func cameraState(previous: MapCameraState?) -> MapCameraState? {
    guard let engine, engine.mapboxMap.isStyleLoaded else { return nil }
    let size = engine.mapView.bounds.size
    guard size.width > 1, size.height > 1 else { return nil }
    let state = engine.mapboxMap.cameraState
    let latitude = state.center.latitude
    let fov = MapboxMapEngine.fieldOfView
    let focal = MapCameraState.focalLength(height: Double(size.height), verticalFieldOfView: fov)
    let distance = Double(size.height) / 2 / tan(fov / 2)
      * MapboxMapEngine.metersPerPoint(zoom: state.zoom, latitude: latitude)
    let pitch = Double(state.pitch)
    let padding = state.padding
    let center = CGPoint(
      x: padding.left + (size.width - padding.left - padding.right) / 2,
      y: padding.top + (size.height - padding.top - padding.bottom) / 2)
    var result = MapCameraState(
      latitude: latitude, longitude: state.center.longitude,
      distance: distance, altitude: distance * cos(pitch * .pi / 180),
      pitch: pitch, heading: state.bearing,
      mapSize: size, focalLength: focal, centerPoint: center,
      globe: engine.style.isGlobe && state.zoom < MapboxMapEngine.globeZoomLimit,
      drawsTerrain: engine.style.hasTerrain,
      darkAppearance: engine.style.isDarkPreset)
    if !result.globe, padding != .zero {
      // Off-centre projection: the axis through the centre coordinate.
      let rotation = MapCameraState.orientation(heading: result.heading, pitch: pitch)
      var transform = simd_float4x4(rotation)
      let back = rotation.act(SIMD3<Float>(0, 0, 1))
      transform.columns.3 = SIMD4(back * Float(distance), 1)
      result.cameraTransformOverride = transform
      let aspect = Float(size.width / size.height)
      let f = Float(1 / tan(fov / 2))
      let near = result.nearPlane
      let far = result.farPlane
      let ox = Float((center.x - size.width / 2) / (size.width / 2))
      let oy = Float(-(center.y - size.height / 2) / (size.height / 2))
      result.projectionOverride = simd_float4x4(columns: (
        SIMD4(f / aspect, 0, 0, 0),
        SIMD4(0, f, 0, 0),
        SIMD4(-ox, -oy, (far + near) / (near - far), -1),
        SIMD4(0, 0, 2 * far * near / (near - far), 0)))
    }
    return result
  }

  func screenPoint(for coordinate: CLLocationCoordinate2D) -> CGPoint? {
    engine?.mapboxMap.point(for: coordinate)
  }

  func visibleRegion() -> MKCoordinateRegion? { engine?.visibleRegion }
}

extension MapboxMapEngine {
  /// Below this zoom Mapbox draws its globe (it blends to flat by zoom 6).
  static let globeZoomLimit = 5.5
}

/// Writing PNGs for snapshots.
enum MapboxFiles {
  static func writePNG(_ image: UIImage, prefix: String) throws -> URL {
    guard let data = image.pngData() else { throw MunimMapEngineError("Mapbox: could not encode the snapshot") }
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(prefix)-\(UUID().uuidString).png")
    try data.write(to: url)
    return url
  }
}
#endif
