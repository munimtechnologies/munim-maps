import MapKit
import UIKit

/// A full MapKit map with munim-maps' markers, shapes, tile overlays and 3D
/// models built in. Use it from UIKit, or through `MunimMap` in SwiftUI.
@_expose(!Cxx)
public final class MunimMapKitView: UIView {
  public let mapView = MKMapView()
  public let modelLayer = MunimModelLayer()

  private let features: MapFeatureController
  private lazy var delegate = MunimMapDelegate(owner: self)
  private var appliedInitialCamera = false
  private var reportedReady = false

  // MARK: Content

  public var models: [MunimModel] {
    get { modelLayer.models }
    set { modelLayer.models = newValue }
  }

  public var zones: [MunimZone] {
    get { modelLayer.zones }
    set { modelLayer.zones = newValue }
  }

  /// Keeps models on 3D terrain; see `MunimModelLayer.followsTerrain`.
  public var followsTerrain: Bool {
    get { modelLayer.followsTerrain }
    set { modelLayer.followsTerrain = newValue }
  }

  /// Hides models behind buildings; see `MunimModelLayer.buildingOcclusion`.
  public var buildingOcclusion: Bool {
    get { modelLayer.buildingOcclusion }
    set { modelLayer.buildingOcclusion = newValue }
  }

  public var buildingTilesURL: String {
    get { modelLayer.buildingTilesURL }
    set { modelLayer.buildingTilesURL = newValue }
  }

  public var paths: [MunimPath] {
    get { modelLayer.paths }
    set { modelLayer.paths = newValue }
  }

  public var lighting: MunimLighting {
    get { modelLayer.lighting }
    set { modelLayer.lighting = newValue }
  }

  public var maxCameraDistance: Double {
    get { modelLayer.maxCameraDistance }
    set { modelLayer.maxCameraDistance = newValue }
  }

  public var markers: [MunimMarker] = [] { didSet { syncMarkers() } }

  /// Markers drawn from views (React Native `MarkerView`), by id.
  private var viewMarkers: [String: MunimMarker] = [:]

  /// Adds or updates a marker whose picture is `image` (a snapshot of a
  /// view). Its `style` is treated as `.image`.
  public func setViewMarker(_ marker: MunimMarker, image: UIImage?) {
    var marker = marker
    marker.style = .image
    marker.imageUri = ""
    viewMarkers[marker.id] = marker
    features.setViewImage(image, for: marker.id)
    syncMarkers()
  }

  /// Updates only the picture of a view marker.
  public func setViewMarkerImage(_ image: UIImage?, id: String) {
    guard viewMarkers[id] != nil else { return }
    features.setViewImage(image, for: id)
  }

  public func removeViewMarker(_ id: String) {
    guard viewMarkers.removeValue(forKey: id) != nil else { return }
    features.setViewImage(nil, for: id)
    syncMarkers()
  }

  private func syncMarkers() {
    features.setMarkers(viewMarkers.isEmpty ? markers : markers + viewMarkers.values)
  }
  public var polylines: [MunimPolyline] = [] { didSet { features.setPolylines(polylines) } }
  public var polygons: [MunimPolygon] = [] { didSet { features.setPolygons(polygons) } }
  public var circles: [MunimCircle] = [] { didSet { features.setCircles(circles) } }
  public var tileOverlays: [MunimTileOverlay] = [] { didSet { features.setTileOverlays(tileOverlays) } }
  /// How clusters of markers look, by clustering id.
  public var clusterStyles: [MunimClusterStyle] = [] {
    didSet { features.clusterStyles = Dictionary(clusterStyles.map { ($0.clusteringId, $0) }, uniquingKeysWith: { $1 }) }
  }

  /// What tapping a place on Apple's map (`selectableFeatures`) shows: Apple's
  /// place card in a callout or sheet, or an Open in Maps button. iOS 18+.
  public var selectionAccessory: MunimSelectionAccessory = .none {
    didSet {
      // MapKit asks whether the delegate answers `selectionAccessoryFor`
      // when it is set; set it again so it asks anew.
      guard (oldValue == .none) != (selectionAccessory == .none) else { return }
      mapView.delegate = nil
      mapView.delegate = delegate
    }
  }

  fileprivate var wantsSelectionAccessory: Bool { selectionAccessory != .none }

  // MARK: Look

  /// Applied once, when the map first has a size.
  public var initialCamera: MunimCamera? {
    didSet { applyInitialCameraIfReady() }
  }

  public var mapStyle: MunimMapStyle = .standard { didSet { if oldValue != mapStyle { applyConfiguration() } } }
  public var elevation: MunimElevation = .realistic { didSet { if oldValue != elevation { applyConfiguration() } } }
  public var showsTraffic = false { didSet { if oldValue != showsTraffic { applyConfiguration() } } }
  /// Which points of interest to show.
  @nonobjc public var pointOfInterestFilter: MKPointOfInterestFilter = .includingAll { didSet { applyConfiguration() } }

  /// The standard style as a globe when zoomed far out, like Apple Maps.
  /// Uses a MapKit switch that is not public API; see `MunimModelLayer.globe`.
  public var globe: Bool {
    get { modelLayer.globe }
    set { modelLayer.globe = newValue }
  }

  public var colorScheme: UIUserInterfaceStyle = .unspecified {
    didSet {
      mapView.overrideUserInterfaceStyle = colorScheme
      modelLayer.setNeedsRender()
    }
  }

  public var showsBuildings: Bool {
    get { mapView.showsBuildings }
    set { mapView.showsBuildings = newValue }
  }

  public var showsUserLocation: Bool {
    get { mapView.showsUserLocation }
    set {
      if newValue { locationAuthorization.requestIfNeeded() }
      mapView.showsUserLocation = newValue
    }
  }

  /// The compass: `adaptive` (MapKit's, shown while the map is rotated),
  /// `visible` (always) or `hidden`.
  public var compassVisibility: MunimFeatureVisibility = .adaptive { didSet { applyControls() } }

  /// The scale legend: `adaptive` (MapKit's, shown while zooming), `visible`
  /// (always) or `hidden`.
  public var scaleVisibility: MunimFeatureVisibility = .hidden { didSet { applyControls() } }

  public var showsCompass: Bool {
    get { compassVisibility != .hidden }
    set { compassVisibility = newValue ? .adaptive : .hidden }
  }

  public var showsScale: Bool {
    get { scaleVisibility != .hidden }
    set { scaleVisibility = newValue ? .adaptive : .hidden }
  }

  /// MapKit's button that cycles the user tracking mode, top right. Built in
  /// on iOS 17+, an `MKUserTrackingButton` before.
  public var showsUserTrackingButton = false { didSet { applyControls() } }

  /// MapKit's 2D/3D button. iOS 17+.
  public var pitchButtonVisibility: MunimFeatureVisibility = .hidden { didSet { applyControls() } }

  /// Name that standalone controls (`MunimMapControlView`) use to find this map.
  public var mapScope = "" {
    didSet { if oldValue != mapScope { MunimMapScopes.register(self, scope: mapScope, previous: oldValue) } }
  }

  /// MapKit's user tracking. MapKit owns the following: it keeps the map on
  /// the user (and turned with the device for `.followWithHeading`, with
  /// the heading beam) and drops back to `.none` when the user pans or
  /// zooms away, which `onUserTrackingModeChange` reports. Setting a mode
  /// asks for when-in-use location access if the app has not yet (the app
  /// needs `NSLocationWhenInUseUsageDescription`).
  @nonobjc public var userTrackingMode: MKUserTrackingMode {
    get { mapView.userTrackingMode }
    set {
      requestedTrackingMode = newValue
      trackingDroppedByMapKit = false
      applyTrackingMode()
    }
  }

  /// The mode last asked for, re-applied once location access is granted if
  /// MapKit dropped it while waiting.
  private var requestedTrackingMode: MKUserTrackingMode = .none
  private var trackingDroppedByMapKit = false
  private let locationAuthorization = MapLocationAuthorization()
  private var builtInCompass: MKCompassButton?
  private var builtInScale: MKScaleView?
  private var builtInTrackingButton: MKUserTrackingButton?

  public var isZoomEnabled: Bool {
    get { mapView.isZoomEnabled }
    set { mapView.isZoomEnabled = newValue }
  }

  public var isScrollEnabled: Bool {
    get { mapView.isScrollEnabled }
    set { mapView.isScrollEnabled = newValue }
  }

  public var isRotateEnabled: Bool {
    get { mapView.isRotateEnabled }
    set { mapView.isRotateEnabled = newValue }
  }

  public var isPitchEnabled: Bool {
    get { mapView.isPitchEnabled }
    set { mapView.isPitchEnabled = newValue }
  }

  /// Closest and farthest camera distance in metres; nil for MapKit's limits.
  public var cameraDistanceRange: ClosedRange<Double>? {
    didSet {
      if let range = cameraDistanceRange {
        mapView.cameraZoomRange = MKMapView.CameraZoomRange(
          minCenterCoordinateDistance: range.lowerBound, maxCenterCoordinateDistance: range.upperBound)
      } else {
        mapView.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 0)
      }
    }
  }

  /// Keep the camera's centre inside this region.
  @nonobjc public var cameraBoundary: MKCoordinateRegion? {
    didSet { mapView.cameraBoundary = cameraBoundary.flatMap { MKMapView.CameraBoundary(coordinateRegion: $0) } }
  }

  /// Space covered by your own UI.
  public var mapPadding: UIEdgeInsets = .zero {
    didSet {
      mapView.layoutMargins = mapPadding
      setNeedsLayout()
      modelLayer.setNeedsRender()
    }
  }

  /// Places on Apple's map that can be tapped (`onMapFeaturePress`). iOS 16+.
  public var selectableFeatures: Set<MunimMapFeatureKind> = [] {
    didSet {
      guard #available(iOS 16.0, *) else { return }
      var options: MKMapFeatureOptions = []
      if selectableFeatures.contains(.pointsOfInterest) { options.insert(.pointsOfInterest) }
      if selectableFeatures.contains(.territories) { options.insert(.territories) }
      if selectableFeatures.contains(.physicalFeatures) { options.insert(.physicalFeatures) }
      mapView.selectableMapFeatures = options
    }
  }

  // MARK: Events

  public var onMapReady: (() -> Void)?
  public var onPress: ((CLLocationCoordinate2D, CGPoint) -> Void)?
  public var onLongPress: ((CLLocationCoordinate2D, CGPoint) -> Void)?
  /// While the camera moves, about once a frame.
  public var onCameraMove: ((MunimCamera) -> Void)?
  /// When the camera stops.
  public var onCameraChange: ((MunimCamera) -> Void)?
  public var onMarkerPress: ((String) -> Void)?
  public var onMarkerDeselect: ((String) -> Void)?
  public var onCalloutPress: ((String) -> Void)?
  /// A callout accessory was tapped: marker id and `"left"` or `"right"`.
  public var onCalloutAccessoryPress: ((String, String) -> Void)?
  /// A cluster was tapped: its clustering id, the member marker ids and where it is.
  public var onClusterPress: ((String, [String], CLLocationCoordinate2D) -> Void)?
  /// A tappable polyline, polygon or circle was tapped: id, kind
  /// (`polyline`, `polygon`, `circle`) and where. Taken instead of `onPress`.
  public var onOverlayPress: ((String, String, CLLocationCoordinate2D) -> Void)?
  public var onMarkerDragStart: ((String, CLLocationCoordinate2D) -> Void)?
  public var onMarkerDragEnd: ((String, CLLocationCoordinate2D) -> Void)?
  public var onUserLocationChange: ((CLLocation) -> Void)?
  public var onMapFeaturePress: ((MunimMapFeature) -> Void)?
  /// MapKit changed the user tracking mode: the user panned or zoomed away,
  /// used the tracking button, or a camera move ended the following.
  @nonobjc public var onUserTrackingModeChange: ((MKUserTrackingMode) -> Void)?

  public var onModelPress: ((String) -> Void)? {
    get { modelLayer.onModelPress }
    set { modelLayer.onModelPress = newValue }
  }

  public var onError: ((String) -> Void)? {
    didSet {
      modelLayer.onError = onError
      features.onError = onError
    }
  }

  // MARK: Life cycle

  public override init(frame: CGRect) {
    features = MapFeatureController(mapView: mapView)
    super.init(frame: frame)
    mapView.frame = bounds
    mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    mapView.delegate = delegate
    addSubview(mapView)

    modelLayer.view.frame = bounds
    modelLayer.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(modelLayer.view)
    modelLayer.attach(to: mapView)

    let tap = UITapGestureRecognizer(target: delegate, action: #selector(MunimMapDelegate.handleTap(_:)))
    tap.cancelsTouchesInView = false
    tap.delegate = delegate
    mapView.addGestureRecognizer(tap)
    let longPress = UILongPressGestureRecognizer(target: delegate, action: #selector(MunimMapDelegate.handleLongPress(_:)))
    longPress.delegate = delegate
    mapView.addGestureRecognizer(longPress)
    locationAuthorization.onAuthorized = { [weak self] in self?.locationAuthorized() }
    applyConfiguration()
    applyControls()
  }

  public required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  public override func layoutSubviews() {
    super.layoutSubviews()
    applyInitialCameraIfReady()
    layoutControls()
    modelLayer.setNeedsRender()
  }

  public override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil { applyTrackingMode() }
  }

  public override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    setNeedsLayout()
  }

  // MARK: Camera and conversions

  public var camera: MunimCamera {
    let c = mapView.camera
    return MunimCamera(latitude: c.centerCoordinate.latitude, longitude: c.centerCoordinate.longitude,
                       distance: c.centerCoordinateDistance, pitch: Double(c.pitch), heading: c.heading)
  }

  public func setCamera(_ camera: MunimCamera, animated: Bool) {
    stopFlight()
    endTrackingForCameraMove()
    mapView.setCamera(Self.mapKitCamera(camera), animated: animated)
    modelLayer.setNeedsRender()
  }

  /// Moves the camera over `duration` seconds, eased or at a steady speed.
  ///
  /// The camera is stepped once a frame rather than handed to a UIKit
  /// animation: during one of those MapKit reports where the camera is
  /// going, not where it is, so models drawn over it would slide.
  public func animateCamera(_ camera: MunimCamera, duration: TimeInterval, linear: Bool = false) {
    guard duration > 0 else { return setCamera(camera, animated: false) }
    let from = self.camera
    let steps = linear ? 1 : 24
    let keyframes = (0...steps).map { i -> MunimCameraKeyframe in
      let x = Double(i) / Double(steps)
      let eased = linear ? x : x * x * (3 - 2 * x)
      return MunimCameraKeyframe(t: x * duration, camera: Self.interpolate(from, camera, eased))
    }
    flyCamera(keyframes, start: Date().timeIntervalSince1970)
  }

  private var flight: (keyframes: [MunimCameraKeyframe], start: Double, loop: Bool)?
  private var flightLink: CADisplayLink?

  /// Flies the camera through keyframes, `t` seconds after `start` (seconds
  /// since 1970), interpolating every frame. Pass the same clock as models'
  /// `motionStart` to follow a moving model exactly. Any other camera call
  /// stops it.
  public func flyCamera(_ keyframes: [MunimCameraKeyframe], start: Double, loop: Bool = false) {
    guard keyframes.count > 1 else {
      stopFlight()
      if let only = keyframes.first { setCamera(only.camera, animated: false) }
      return
    }
    endTrackingForCameraMove()
    flight = (keyframes.sorted { $0.t < $1.t }, start, loop)
    if flightLink == nil {
      let link = CADisplayLink(target: FlightTarget(self), selector: #selector(FlightTarget.tick))
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
    mapView.camera = Self.mapKitCamera(camera)
    modelLayer.setNeedsRender()
  }

  private static func interpolate(_ a: MunimCamera, _ b: MunimCamera, _ f: Double) -> MunimCamera {
    let turn = ((b.heading - a.heading).truncatingRemainder(dividingBy: 360) + 540)
      .truncatingRemainder(dividingBy: 360) - 180
    return MunimCamera(
      latitude: a.latitude + (b.latitude - a.latitude) * f,
      longitude: a.longitude + (b.longitude - a.longitude) * f,
      // Zoom at a steady rate in scale, not in metres.
      distance: exp(log(max(1, a.distance)) + (log(max(1, b.distance)) - log(max(1, a.distance))) * f),
      pitch: a.pitch + (b.pitch - a.pitch) * f,
      heading: (a.heading + turn * f + 360).truncatingRemainder(dividingBy: 360))
  }

  @nonobjc public var visibleRegion: MKCoordinateRegion { mapView.region }

  /// Moves to a region over `duration` seconds (0 jumps).
  @nonobjc public func setRegion(_ region: MKCoordinateRegion, duration: TimeInterval) {
    endTrackingForCameraMove()
    if duration <= 0 {
      mapView.setRegion(region, animated: false)
    } else {
      UIView.animate(withDuration: duration) { self.mapView.setRegion(region, animated: true) }
    }
  }

  @nonobjc public func fit(coordinates: [CLLocationCoordinate2D], padding: UIEdgeInsets = .zero, animated: Bool = true) {
    guard let rect = MapFeatureController.boundingRect(coordinates.map { MKMapPoint($0) }) else { return }
    endTrackingForCameraMove()
    mapView.setVisibleMapRect(rect, edgePadding: padding, animated: animated)
  }

  /// Frames the markers with these ids (all markers when empty).
  public func fitMarkers(_ ids: Set<String> = [], padding: UIEdgeInsets = .zero, animated: Bool = true) {
    guard let rect = features.mapRect(forMarkers: ids) else { return }
    endTrackingForCameraMove()
    mapView.setVisibleMapRect(rect, edgePadding: padding, animated: animated)
  }

  @nonobjc public func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
    mapView.convert(coordinate, toPointTo: mapView)
  }

  @nonobjc public func coordinate(for point: CGPoint) -> CLLocationCoordinate2D {
    mapView.convert(point, toCoordinateFrom: mapView)
  }

  public func selectMarker(_ id: String) {
    if let a = features.annotations[id] { mapView.selectAnnotation(a, animated: true) }
  }

  public func deselectMarker(_ id: String) {
    if let a = features.annotations[id] { mapView.deselectAnnotation(a, animated: true) }
  }

  /// A PNG of the map (no models or markers), written to a temporary file.
  public func snapshot(size: CGSize? = nil, completion: @escaping (Result<URL, Error>) -> Void) {
    let options = MKMapSnapshotter.Options()
    options.camera = mapView.camera
    options.size = size ?? mapView.bounds.size
    options.traitCollection = mapView.traitCollection
    if #available(iOS 17.0, *), let configuration = mapView.preferredConfiguration.copy() as? MKMapConfiguration {
      options.preferredConfiguration = configuration
    }
    MKMapSnapshotter(options: options).start { snapshot, error in
      guard let snapshot, let data = snapshot.image.pngData() else {
        completion(.failure(error ?? MapModelError.message("Snapshot failed")))
        return
      }
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("munim-maps-snapshot-\(UUID().uuidString).png")
      completion(Result { try data.write(to: url); return url })
    }
  }

  /// Reverse-geocodes a coordinate.
  @nonobjc public func address(for coordinate: CLLocationCoordinate2D, completion: @escaping (Result<MunimAddress, Error>) -> Void) {
    let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
      guard let p = placemarks?.first else {
        completion(.failure(error ?? MapModelError.message("No address here")))
        return
      }
      let street = [p.subThoroughfare, p.thoroughfare].compactMap { $0 }.joined(separator: " ")
      let formatted = [p.name, street.isEmpty ? nil : street, p.locality, p.administrativeArea, p.postalCode, p.country]
        .compactMap { $0 }
        .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        .joined(separator: ", ")
      completion(.success(MunimAddress(
        name: p.name ?? "", street: street, city: p.locality ?? "", region: p.administrativeArea ?? "",
        postalCode: p.postalCode ?? "", country: p.country ?? "", countryCode: p.isoCountryCode ?? "",
        formatted: formatted)))
    }
  }

  /// Whether Apple has Look Around imagery at the coordinate.
  @nonobjc public func hasLookAround(at coordinate: CLLocationCoordinate2D, completion: @escaping (Bool) -> Void) {
    guard #available(iOS 16.0, *) else { return completion(false) }
    MKLookAroundSceneRequest(coordinate: coordinate).getSceneWithCompletionHandler { scene, _ in
      completion(scene != nil)
    }
  }

  /// Presents Apple's full-screen Look Around at the coordinate.
  @nonobjc public func openLookAround(at coordinate: CLLocationCoordinate2D, completion: @escaping (Bool) -> Void) {
    guard #available(iOS 16.0, *) else { return completion(false) }
    MKLookAroundSceneRequest(coordinate: coordinate).getSceneWithCompletionHandler { scene, _ in
      DispatchQueue.main.async {
        guard let scene, let presenter = self.topViewController() else { return completion(false) }
        let controller = MKLookAroundViewController(scene: scene)
        controller.modalPresentationStyle = .fullScreen
        presenter.present(controller, animated: true)
        completion(true)
      }
    }
  }

  public func measureAlignment() -> MunimAlignmentReport {
    modelLayer.measureAlignment()
  }

  /// Tapped map features by `MunimMapFeature.id`, the most recent few.
  private var featureAnnotations: [(id: String, annotation: MKAnnotation)] = []
  private var featureCounter = 0

  /// The full place (phone, website, address…) behind a tapped map feature.
  @nonobjc public func mapItem(forFeature id: String, completion: @escaping (Result<MKMapItem, Error>) -> Void) {
    guard #available(iOS 16.0, *),
          let feature = featureAnnotations.last(where: { $0.id == id })?.annotation as? MKMapFeatureAnnotation
    else { return completion(.failure(MapModelError.message("No map feature with id \(id)"))) }
    MKMapItemRequest(mapFeatureAnnotation: feature).getMapItem { item, error in
      if let item { completion(.success(item)) } else {
        completion(.failure(error ?? MapModelError.message("No place found for the feature")))
      }
    }
  }

  // MARK: Controls and tracking

  /// MapKit's own controls where it has them; a standalone control where
  /// MapKit cannot do what was asked (an always-visible compass or scale,
  /// the tracking button before iOS 17).
  private func applyControls() {
    mapView.showsCompass = compassVisibility == .adaptive
    mapView.showsScale = scaleVisibility == .adaptive
    if compassVisibility == .visible {
      let compass = builtInCompass ?? MKCompassButton(mapView: mapView)
      compass.compassVisibility = .visible
      if compass.superview == nil { addSubview(compass) }
      builtInCompass = compass
    } else {
      builtInCompass?.removeFromSuperview()
      builtInCompass = nil
    }
    if scaleVisibility == .visible {
      let scale = builtInScale ?? MKScaleView(mapView: mapView)
      scale.scaleVisibility = .visible
      if scale.superview == nil { addSubview(scale) }
      builtInScale = scale
    } else {
      builtInScale?.removeFromSuperview()
      builtInScale = nil
    }
    if #available(iOS 17.0, *) {
      mapView.showsUserTrackingButton = showsUserTrackingButton
      mapView.pitchButtonVisibility = pitchButtonVisibility.mapKit
    } else if showsUserTrackingButton {
      let button = builtInTrackingButton ?? MKUserTrackingButton(mapView: mapView)
      if button.superview == nil { addSubview(button) }
      builtInTrackingButton = button
    } else {
      builtInTrackingButton?.removeFromSuperview()
      builtInTrackingButton = nil
    }
    setNeedsLayout()
  }

  /// Places the standalone controls where MapKit puts its own: the scale top
  /// left, the buttons top right, inside the safe area and `mapPadding`.
  private func layoutControls() {
    let safe = mapView.safeAreaInsets
    let top = safe.top + mapPadding.top + 8
    let right = bounds.width - safe.right - mapPadding.right - 8
    var y = top
    if let button = builtInTrackingButton {
      let size = button.intrinsicContentSize
      button.frame = CGRect(x: right - size.width, y: y, width: size.width, height: size.height)
      y += size.height + 8
    } else if #available(iOS 17.0, *) {
      // MapKit's own button group sits above the compass.
      let buttons = (showsUserTrackingButton ? 1 : 0) + (pitchButtonVisibility == .visible ? 1 : 0)
      if buttons > 0 { y += CGFloat(buttons) * 44 + 8 }
    }
    if let compass = builtInCompass {
      let size = compass.intrinsicContentSize
      compass.frame = CGRect(x: right - size.width, y: y, width: size.width, height: size.height)
    }
    if let scale = builtInScale {
      let left = safe.left + mapPadding.left + 8
      let size = scale.intrinsicContentSize
      scale.frame = CGRect(x: left, y: top, width: max(size.width, min(200, bounds.width / 2)), height: size.height)
    }
  }

  /// Moving the camera from code ends user tracking, as a pan does (MapKit
  /// would otherwise keep following and pull the camera back), and reports
  /// it through `onUserTrackingModeChange`.
  private func endTrackingForCameraMove() {
    guard mapView.userTrackingMode != .none else { return }
    mapView.setUserTrackingMode(.none, animated: false)
  }

  private func applyTrackingMode() {
    let mode = requestedTrackingMode
    if mode != .none { locationAuthorization.requestIfNeeded() }
    guard mapView.userTrackingMode != mode else { return }
    mapView.setUserTrackingMode(mode, animated: window != nil)
  }

  private func locationAuthorized() {
    // MapKit drops tracking it cannot start while access is undecided; pick
    // it back up once the user allows it, unless they have moved on since.
    if trackingDroppedByMapKit, requestedTrackingMode != .none, mapView.userTrackingMode == .none {
      trackingDroppedByMapKit = false
      applyTrackingMode()
    }
  }

  fileprivate func trackingModeChanged(_ mode: MKUserTrackingMode) {
    if mode == .none, requestedTrackingMode != .none {
      let status = CLLocationManager().authorizationStatus
      trackingDroppedByMapKit = status == .notDetermined
    }
    onUserTrackingModeChange?(mode)
  }

  // MARK: Internals

  private func topViewController() -> UIViewController? {
    var controller = window?.rootViewController
    while let presented = controller?.presentedViewController { controller = presented }
    return controller
  }

  private func applyInitialCameraIfReady() {
    guard !appliedInitialCamera, let initialCamera, initialCamera.distance > 0,
          bounds.width > 0, bounds.height > 0
    else { return }
    appliedInitialCamera = true
    mapView.setCamera(Self.mapKitCamera(initialCamera), animated: false)
  }

  static func mapKitCamera(_ camera: MunimCamera) -> MKMapCamera {
    MKMapCamera(
      lookingAtCenter: CLLocationCoordinate2D(latitude: camera.latitude, longitude: camera.longitude),
      fromDistance: camera.distance, pitch: CGFloat(camera.pitch), heading: camera.heading)
  }

  private func applyConfiguration() {
    if #available(iOS 16.0, *) {
      let elevationStyle: MKMapConfiguration.ElevationStyle = elevation == .realistic ? .realistic : .flat
      let configuration: MKMapConfiguration
      switch mapStyle {
      case .standard, .muted:
        let standard = MKStandardMapConfiguration(
          elevationStyle: elevationStyle, emphasisStyle: mapStyle == .muted ? .muted : .default)
        standard.pointOfInterestFilter = pointOfInterestFilter
        standard.showsTraffic = showsTraffic
        configuration = standard
      case .hybrid:
        let hybrid = MKHybridMapConfiguration(elevationStyle: elevationStyle)
        hybrid.pointOfInterestFilter = pointOfInterestFilter
        hybrid.showsTraffic = showsTraffic
        configuration = hybrid
      case .imagery:
        configuration = MKImageryMapConfiguration(elevationStyle: elevationStyle)
      }
      mapView.preferredConfiguration = configuration
    } else {
      switch mapStyle {
      case .standard, .muted: mapView.mapType = .standard
      case .hybrid: mapView.mapType = elevation == .realistic ? .hybridFlyover : .hybrid
      case .imagery: mapView.mapType = elevation == .realistic ? .satelliteFlyover : .satellite
      }
      mapView.pointOfInterestFilter = pointOfInterestFilter
      mapView.showsTraffic = showsTraffic
    }
    modelLayer.setNeedsRender()
  }

  // MARK: Delegate hooks

  fileprivate func handleTap(at point: CGPoint) {
    if modelLayer.modelHit(at: point) != nil { return } // models have their own event
    if let onOverlayPress, let hit = features.overlayHit(at: point) {
      onOverlayPress(hit.id, hit.kind, coordinate(for: point))
      return
    }
    onPress?(coordinate(for: point), point)
  }

  /// Ids of the tappable overlays under a point, topmost first (what a tap
  /// there would hit), for tests and custom gestures.
  @nonobjc public func overlayHit(at point: CGPoint) -> (id: String, kind: String)? {
    features.overlayHit(at: point)
  }

  fileprivate func handleLongPress(at point: CGPoint) {
    onLongPress?(coordinate(for: point), point)
  }

  fileprivate func viewFor(_ annotation: MKAnnotation) -> MKAnnotationView? {
    if let cluster = annotation as? MKClusterAnnotation { return features.clusterView(for: cluster, in: mapView) }
    guard let annotation = annotation as? MunimAnnotation else { return nil }
    return features.view(for: annotation, in: mapView)
  }

  @available(iOS 18.0, *)
  fileprivate func selectionAccessory(for annotation: MKAnnotation) -> MKSelectionAccessory? {
    guard annotation is MKMapFeatureAnnotation else { return nil }
    switch selectionAccessory {
    case .none: return nil
    case .automatic: return .mapItemDetail(.automatic(presentationViewController: hostViewController()))
    case .callout: return .mapItemDetail(.callout())
    case .calloutCompact: return .mapItemDetail(.callout(.compact))
    case .calloutFull: return .mapItemDetail(.callout(.full))
    case .sheet:
      guard let controller = hostViewController() else { return .mapItemDetail(.callout()) }
      return .mapItemDetail(.sheet(presentedFrom: controller))
    case .openInMaps: return .mapItemDetail(.openInMaps)
    }
  }

  /// The view controller showing this map, for sheets.
  private func hostViewController() -> UIViewController? {
    var responder: UIResponder? = self
    while let current = responder {
      if let controller = current as? UIViewController { return controller }
      responder = current.next
    }
    return topViewController()
  }

  fileprivate func rendererFor(_ overlay: MKOverlay) -> MKOverlayRenderer {
    features.renderer(for: overlay) ?? MKOverlayRenderer(overlay: overlay)
  }

  fileprivate func didSelect(_ annotation: MKAnnotation) {
    if let a = annotation as? MunimAnnotation {
      onMarkerPress?(a.id)
      return
    }
    if let cluster = annotation as? MKClusterAnnotation {
      let ids = cluster.memberAnnotations.compactMap { ($0 as? MunimAnnotation)?.id }
      onClusterPress?(features.clusteringId(of: cluster), ids, cluster.coordinate)
      // Leave MapKit's enlarged cluster up only when it has a title to show.
      if cluster.title == nil || features.clusterStyles[features.clusteringId(of: cluster)] == nil {
        mapView.deselectAnnotation(cluster, animated: false)
      }
      return
    }
    if #available(iOS 16.0, *), let feature = annotation as? MKMapFeatureAnnotation {
      let kind: String
      switch feature.featureType {
      case .pointOfInterest: kind = "pointOfInterest"
      case .territory: kind = "territory"
      case .physicalFeature: kind = "physicalFeature"
      @unknown default: kind = "unknown"
      }
      featureCounter += 1
      let id = "feature-\(featureCounter)"
      featureAnnotations.append((id, feature))
      if featureAnnotations.count > 32 { featureAnnotations.removeFirst() }
      onMapFeaturePress?(MunimMapFeature(
        title: feature.title ?? "", coordinate: feature.coordinate, kind: kind,
        category: feature.pointOfInterestCategory?.rawValue ?? "", id: id))
    }
  }

  fileprivate func didDeselect(_ annotation: MKAnnotation) {
    if let a = annotation as? MunimAnnotation { onMarkerDeselect?(a.id) }
  }

  fileprivate func calloutTapped(_ annotation: MKAnnotation, control: UIControl) {
    guard let a = annotation as? MunimAnnotation else { return }
    onCalloutPress?(a.id)
    let side = control.tag == MapFeatureController.leftAccessoryTag ? "left" : "right"
    onCalloutAccessoryPress?(a.id, side)
  }

  fileprivate func dragChanged(_ annotation: MKAnnotation, to state: MKAnnotationView.DragState) {
    guard let a = annotation as? MunimAnnotation else { return }
    switch state {
    case .starting: onMarkerDragStart?(a.id, a.coordinate)
    case .ending, .canceling: onMarkerDragEnd?(a.id, a.coordinate)
    default: break
    }
  }

  fileprivate func regionDidChange() { onCameraChange?(camera) }
  fileprivate func regionIsChanging() { onCameraMove?(camera) }

  fileprivate func didFinishLoading() {
    guard !reportedReady else { return }
    reportedReady = true
    onMapReady?()
  }

  fileprivate func userLocationChanged(_ location: CLLocation?) {
    if let location { onUserLocationChange?(location) }
  }
}

private final class MunimMapDelegate: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
  weak var owner: MunimMapKitView?

  init(owner: MunimMapKitView) {
    self.owner = owner
  }

  /// Only answer `selectionAccessoryFor` when a selection accessory is
  /// wanted: while the method exists MapKit shows no classic callouts.
  override func responds(to selector: Selector!) -> Bool {
    if selector == NSSelectorFromString("mapView:selectionAccessoryForAnnotation:") {
      return owner?.wantsSelectionAccessory == true && super.responds(to: selector)
    }
    return super.responds(to: selector)
  }

  @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
    guard recognizer.state == .ended, let map = recognizer.view as? MKMapView else { return }
    let point = recognizer.location(in: map)
    if let hit = map.hitTest(point, with: nil), hit.isInsideAnnotationView { return }
    owner?.handleTap(at: point)
  }

  @objc func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
    guard recognizer.state == .began, let map = recognizer.view else { return }
    owner?.handleLongPress(at: recognizer.location(in: map))
  }

  func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
    true
  }

  func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
    owner?.viewFor(annotation)
  }

  func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
    owner?.rendererFor(overlay) ?? MKOverlayRenderer(overlay: overlay)
  }

  func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) { owner?.didSelect(annotation) }
  func mapView(_ mapView: MKMapView, didDeselect annotation: MKAnnotation) { owner?.didDeselect(annotation) }

  func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
               calloutAccessoryControlTapped control: UIControl) {
    if let annotation = view.annotation { owner?.calloutTapped(annotation, control: control) }
  }

  @available(iOS 18.0, *)
  func mapView(_ mapView: MKMapView, selectionAccessoryFor annotation: MKAnnotation) -> MKSelectionAccessory? {
    owner?.selectionAccessory(for: annotation)
  }

  func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
               didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
    if let annotation = view.annotation { owner?.dragChanged(annotation, to: newState) }
    if newState == .ending || newState == .canceling { view.dragState = .none }
  }

  func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) { owner?.regionDidChange() }
  func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) { owner?.regionIsChanging() }
  func mapViewDidFinishLoadingMap(_ mapView: MKMapView) { owner?.didFinishLoading() }
  func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) { owner?.didFinishLoading() }
  func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) { owner?.userLocationChanged(userLocation.location) }
  func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) { owner?.trackingModeChanged(mode) }
}

private extension UIView {
  /// Whether this view is, or sits inside, a marker view or callout.
  var isInsideAnnotationView: Bool {
    var view: UIView? = self
    while let current = view {
      if current is MKAnnotationView { return true }
      if current is MKMapView { return false }
      view = current.superview
    }
    return false
  }
}

/// Breaks the retain cycle between the flight's `CADisplayLink` and the view.
private final class FlightTarget: NSObject {
  weak var owner: MunimMapKitView?

  init(_ owner: MunimMapKitView) {
    self.owner = owner
  }

  @objc func tick() {
    owner?.stepFlight()
  }
}
