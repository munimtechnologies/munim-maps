import MapKit
import NitroModules
import UIKit

/// React Native `MunimMapView`: a `MunimMapContainerView` showing the engine
/// in `provider`, with props, events and methods forwarded to it
/// (`MunimMapEngine`). 3D props go straight to the engine's model layer.
/// When `provider` changes, the engine is replaced and every prop applied
/// to the new one.
final class HybridMunimMapView: HybridMunimMapViewSpec {
  private let container = MunimMapContainerView(provider: .mapkit)
  private var map: MunimMapEngine { container.engine }
  var view: UIView { container }

  override init() {
    super.init()
    wire(container.engine)
  }

  /// Sends the engine's events to JavaScript.
  private func wire(_ engine: MunimMapEngine) {
    engine.onError = { [weak self] message in self?.onError?(message) }
    engine.modelLayer.onModelPress = { [weak self] id in self?.onModelPress?(id) }
    engine.onMapReady = { [weak self] in self?.onMapReady?() }
    engine.onCameraChange = { [weak self] camera in self?.onCameraChange?(camera.nitro) }
    engine.onCameraMove = { [weak self] camera in self?.onCameraMove?(camera.nitro) }
    engine.onPress = { [weak self] c, p in
      self?.onPress?(MapPressEvent(latitude: c.latitude, longitude: c.longitude, x: Double(p.x), y: Double(p.y)))
    }
    engine.onLongPress = { [weak self] c, p in
      self?.onLongPress?(MapPressEvent(latitude: c.latitude, longitude: c.longitude, x: Double(p.x), y: Double(p.y)))
    }
    engine.onMarkerPress = { [weak self] id in self?.onMarkerPress?(id) }
    engine.onMarkerDeselect = { [weak self] id in self?.onMarkerDeselect?(id) }
    engine.onCalloutPress = { [weak self] id in self?.onCalloutPress?(id) }
    engine.onCalloutAccessoryPress = { [weak self] id, side in
      self?.onCalloutAccessoryPress?(CalloutAccessoryEvent(id: id, side: side == "left" ? .left : .right))
    }
    engine.onClusterPress = { [weak self] clusteringId, ids, c in
      self?.onClusterPress?(ClusterPressEvent(
        clusteringId: clusteringId, markerIds: ids.joined(separator: ","), latitude: c.latitude, longitude: c.longitude))
    }
    engine.onMarkerDragStart = { [weak self] id, c in
      self?.onMarkerDragStart?(MarkerDragEvent(id: id, latitude: c.latitude, longitude: c.longitude))
    }
    engine.onMarkerDragEnd = { [weak self] id, c in
      self?.onMarkerDragEnd?(MarkerDragEvent(id: id, latitude: c.latitude, longitude: c.longitude))
    }
    engine.onUserLocationChange = { [weak self] l in
      self?.onUserLocationChange?(UserLocationEvent(
        latitude: l.coordinate.latitude, longitude: l.coordinate.longitude, altitude: l.altitude,
        horizontalAccuracy: l.horizontalAccuracy, verticalAccuracy: l.verticalAccuracy,
        heading: l.course >= 0 ? l.course : -1, speed: l.speed >= 0 ? l.speed : -1))
    }
    engine.onUserTrackingModeChange = { [weak self] mode in self?.onUserTrackingModeChange?(UserTrackingMode(mode)) }
    engine.onMapFeaturePress = { [weak self] f in
      self?.onMapFeaturePress?(MapFeatureEvent(
        title: f.title, latitude: f.coordinate.latitude, longitude: f.coordinate.longitude,
        kind: f.kind, category: f.category, id: f.id))
    }
    let provider = engine.provider.rawValue
    engine.setProviderEventHandler { [weak self] name, data in
      self?.onProviderEvent?(ProviderEvent(provider: provider, name: name, json: Self.json(data)))
    }
  }

  /// JSON text for a JSON-compatible value (`null` when it is not).
  static func json(_ value: Any) -> String {
    if value is NSNull { return "null" }
    guard JSONSerialization.isValidJSONObject([value]),
          let data = try? JSONSerialization.data(withJSONObject: [value], options: [.fragmentsAllowed]),
          let text = String(data: data, encoding: .utf8)
    else { return "null" }
    // Unwrap the array that made fragments valid.
    return String(text.dropFirst().dropLast())
  }

  /// Sets every prop again, on a new engine (`again` runs the observers).
  private func applyAll() {
    styleUrl = again(styleUrl)
    providerOptions = again(providerOptions)
    initialCamera = again(initialCamera)
    models = again(models)
    zones = again(zones)
    paths = again(paths)
    occlusion = again(occlusion)
    buildingTilesUrl = again(buildingTilesUrl)
    followTerrain = again(followTerrain)
    lighting = again(lighting)
    maxCameraDistance = again(maxCameraDistance)
    markers = again(markers)
    polylines = again(polylines)
    polygons = again(polygons)
    circles = again(circles)
    tileOverlays = again(tileOverlays)
    clusterStyles = again(clusterStyles)
    selectionAccessory = again(selectionAccessory)
    mapStyle = again(mapStyle)
    elevation = again(elevation)
    globe = again(globe)
    colorScheme = again(colorScheme)
    showsBuildings = again(showsBuildings)
    showsUserLocation = again(showsUserLocation)
    compassVisibility = again(compassVisibility)
    scaleVisibility = again(scaleVisibility)
    showsUserTrackingButton = again(showsUserTrackingButton)
    pitchButtonVisibility = again(pitchButtonVisibility)
    mapScope = again(mapScope)
    showsTraffic = again(showsTraffic)
    pointsOfInterest = again(pointsOfInterest)
    userTrackingMode = again(userTrackingMode)
    zoomEnabled = again(zoomEnabled)
    scrollEnabled = again(scrollEnabled)
    rotateEnabled = again(rotateEnabled)
    pitchEnabled = again(pitchEnabled)
    applyDistanceRange()
    cameraBoundary = again(cameraBoundary)
    mapPadding = again(mapPadding)
    selectableMapFeatures = again(selectableMapFeatures)
    onOverlayPress = again(onOverlayPress)
  }

  // MARK: Props

  /// The value as is: assigning it to its property runs `didSet` again.
  private func again<T>(_ value: T) -> T { value }

  var provider: MapProvider = .mapkit {
    didSet {
      let wanted = MunimMapProvider(rawValue: provider.stringValue) ?? .mapkit
      guard let engine = container.setProvider(wanted) else { return }
      wire(engine)
      applyAll()
    }
  }

  var styleUrl = "" { didSet { map.styleURL = styleUrl } }

  var providerOptions = "{}" {
    didSet {
      let data = Data(providerOptions.utf8)
      map.providerOptions = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
  }

  var models: [NativeMapModel] = [] { didSet { map.modelLayer.models = models.map(\.core) } }
  var zones: [NativeMapZone] = [] { didSet { map.modelLayer.zones = zones.map(\.core) } }
  var paths: [NativeMapPath] = [] { didSet { map.modelLayer.paths = paths.map(\.core) } }
  var occlusion: MapOcclusion = .none { didSet { map.modelLayer.buildingOcclusion = occlusion == .buildings } }
  var buildingTilesUrl = "" { didSet { map.modelLayer.buildingTilesURL = buildingTilesUrl } }
  var followTerrain = false { didSet { map.modelLayer.followsTerrain = followTerrain } }
  var lighting: MapModelLighting = .auto { didSet { map.modelLayer.lighting = lighting.core } }
  var maxCameraDistance: Double = 50_000 { didSet { map.modelLayer.maxCameraDistance = maxCameraDistance } }

  var markers: [NativeMarker] = [] { didSet { map.markers = markers.map(\.core) } }
  var polylines: [NativePolyline] = [] { didSet { map.polylines = polylines.map(\.core) } }
  var polygons: [NativePolygon] = [] { didSet { map.polygons = polygons.map(\.core) } }
  var circles: [NativeCircle] = [] { didSet { map.circles = circles.map(\.core) } }
  var tileOverlays: [NativeTileOverlay] = [] { didSet { map.tileOverlays = tileOverlays.map(\.core) } }
  var clusterStyles: [NativeClusterStyle] = [] { didSet { map.clusterStyles = clusterStyles.map(\.core) } }
  var selectionAccessory: SelectionAccessory = .none {
    didSet { map.selectionAccessory = MunimSelectionAccessory(rawValue: selectionAccessory.stringValue) ?? .none }
  }

  var initialCamera = MapCamera(latitude: 0, longitude: 0, distance: 0, pitch: 0, heading: 0) {
    didSet { map.initialCamera = initialCamera.distance > 0 ? initialCamera.core : nil }
  }

  var mapStyle: MapStyle = .standard {
    didSet { map.mapStyle = MunimMapStyle(rawValue: mapStyle.stringValue) ?? .standard }
  }

  var elevation: MapElevation = .realistic {
    didSet { map.elevation = MunimElevation(rawValue: elevation.stringValue) ?? .realistic }
  }

  var globe = false { didSet { map.globe = globe } }

  var colorScheme: MapColorScheme = .system {
    didSet {
      switch colorScheme {
      case .system: map.colorScheme = .unspecified
      case .light: map.colorScheme = .light
      case .dark: map.colorScheme = .dark
      }
    }
  }

  var showsBuildings = true { didSet { map.showsBuildings = showsBuildings } }
  var showsUserLocation = false { didSet { map.showsUserLocation = showsUserLocation } }
  var compassVisibility: FeatureVisibility = .adaptive { didSet { map.compassVisibility = compassVisibility.core } }
  var scaleVisibility: FeatureVisibility = .hidden { didSet { map.scaleVisibility = scaleVisibility.core } }
  var showsUserTrackingButton = false { didSet { map.showsUserTrackingButton = showsUserTrackingButton } }
  var pitchButtonVisibility: FeatureVisibility = .hidden { didSet { map.pitchButtonVisibility = pitchButtonVisibility.core } }
  var mapScope = "" { didSet { map.mapScope = mapScope } }
  var showsTraffic = false { didSet { map.showsTraffic = showsTraffic } }

  var pointsOfInterest = "all" {
    didSet {
      switch pointsOfInterest.trimmingCharacters(in: .whitespaces) {
      case "", "all": map.pointOfInterestFilter = .includingAll
      case "none": map.pointOfInterestFilter = .excludingAll
      default:
        let categories = pointsOfInterest.split(separator: ",")
          .map { MKPointOfInterestCategory(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
        map.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
      }
    }
  }

  var userTrackingMode: UserTrackingMode = .none {
    didSet { map.userTrackingMode = userTrackingMode.mapKit }
  }

  var zoomEnabled = true { didSet { map.isZoomEnabled = zoomEnabled } }
  var scrollEnabled = true { didSet { map.isScrollEnabled = scrollEnabled } }
  var rotateEnabled = true { didSet { map.isRotateEnabled = rotateEnabled } }
  var pitchEnabled = true { didSet { map.isPitchEnabled = pitchEnabled } }

  var minCameraDistance: Double = 0 { didSet { applyDistanceRange() } }
  var maxCameraDistanceLimit: Double = 0 { didSet { applyDistanceRange() } }

  var cameraBoundary = MapRegion(latitude: 0, longitude: 0, latitudeDelta: 0, longitudeDelta: 0) {
    didSet {
      map.cameraBoundary = cameraBoundary.latitudeDelta > 0 && cameraBoundary.longitudeDelta > 0
        ? cameraBoundary.mapKit : nil
    }
  }

  var mapPadding = EdgeInsets(top: 0, left: 0, bottom: 0, right: 0) {
    didSet { map.mapPadding = mapPadding.uiKit }
  }

  var selectableMapFeatures = "" {
    didSet {
      map.selectableFeatures = Set(selectableMapFeatures.split(separator: ",")
        .compactMap { MunimMapFeatureKind(rawValue: $0.trimmingCharacters(in: .whitespaces)) })
    }
  }

  private func applyDistanceRange() {
    if minCameraDistance <= 0 && maxCameraDistanceLimit <= 0 {
      map.cameraDistanceRange = nil
    } else {
      map.cameraDistanceRange = max(0, minCameraDistance)...(maxCameraDistanceLimit > 0 ? maxCameraDistanceLimit : .greatestFiniteMagnitude)
    }
  }

  // MARK: Events

  var onModelPress: ((_ id: String) -> Void)?
  var onCameraChange: ((_ camera: MapCamera) -> Void)?
  var onCameraMove: ((_ camera: MapCamera) -> Void)?
  var onMapReady: (() -> Void)?
  var onPress: ((_ event: MapPressEvent) -> Void)?
  var onLongPress: ((_ event: MapPressEvent) -> Void)?
  var onMarkerPress: ((_ id: String) -> Void)?
  var onMarkerDeselect: ((_ id: String) -> Void)?
  var onCalloutPress: ((_ id: String) -> Void)?
  var onCalloutAccessoryPress: ((_ event: CalloutAccessoryEvent) -> Void)?
  var onClusterPress: ((_ event: ClusterPressEvent) -> Void)?
  var onOverlayPress: ((_ event: OverlayPressEvent) -> Void)? {
    didSet {
      // Overlays are hit-tested on taps only while someone listens.
      map.onOverlayPress = onOverlayPress == nil ? nil : { [weak self] id, kind, c in
        self?.onOverlayPress?(OverlayPressEvent(id: id, kind: kind, latitude: c.latitude, longitude: c.longitude))
      }
    }
  }
  var onMarkerDragStart: ((_ event: MarkerDragEvent) -> Void)?
  var onMarkerDragEnd: ((_ event: MarkerDragEvent) -> Void)?
  var onUserLocationChange: ((_ location: UserLocationEvent) -> Void)?
  var onUserTrackingModeChange: ((_ mode: UserTrackingMode) -> Void)?
  var onMapFeaturePress: ((_ feature: MapFeatureEvent) -> Void)?
  var onProviderEvent: ((_ event: ProviderEvent) -> Void)?
  var onError: ((_ message: String) -> Void)?

  // MARK: Methods

  func setCamera(camera: MapCamera, animated: Bool) throws {
    DispatchQueue.main.async { self.map.setCamera(camera.core, animated: animated) }
  }

  func animateCamera(camera: MapCamera, durationMs: Double, easing: MapCameraEasing) throws {
    DispatchQueue.main.async {
      self.map.animateCamera(camera.core, duration: durationMs / 1000, linear: easing == .linear)
    }
  }

  func flyCamera(keyframes: [CameraKeyframe], start: Double, loop: Bool) throws {
    let frames = keyframes.map { MunimCameraKeyframe(t: $0.t, camera: $0.camera.core) }
    DispatchQueue.main.async { self.map.flyCamera(frames, start: start, loop: loop) }
  }

  func stopFlight() throws {
    DispatchQueue.main.async { self.map.stopFlight() }
  }

  func getCamera() throws -> Promise<MapCamera> {
    mainPromise { self.map.camera.nitro }
  }

  func setRegion(region: MapRegion, durationMs: Double) throws {
    DispatchQueue.main.async { self.map.setRegion(region.mapKit, duration: durationMs / 1000) }
  }

  func getVisibleRegion() throws -> Promise<MapRegion> {
    mainPromise {
      let r = self.map.visibleRegion
      return MapRegion(latitude: r.center.latitude, longitude: r.center.longitude,
                       latitudeDelta: r.span.latitudeDelta, longitudeDelta: r.span.longitudeDelta)
    }
  }

  func fitToCoordinates(coordinates: [MapCoordinate], padding: EdgeInsets, animated: Bool) throws {
    DispatchQueue.main.async {
      self.map.fit(coordinates: coordinates.map(CLLocationCoordinate2D.init), padding: padding.uiKit, animated: animated)
    }
  }

  func fitToMarkers(ids: String, padding: EdgeInsets, animated: Bool) throws {
    let wanted = Set(ids.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    DispatchQueue.main.async { self.map.fitMarkers(wanted, padding: padding.uiKit, animated: animated) }
  }

  func pointForCoordinate(coordinate: MapCoordinate) throws -> Promise<MapPoint> {
    mainPromise {
      let p = self.map.point(for: CLLocationCoordinate2D(coordinate))
      return MapPoint(x: Double(p.x), y: Double(p.y))
    }
  }

  func coordinateForPoint(point: MapPoint) throws -> Promise<MapCoordinate> {
    mainPromise {
      let c = self.map.coordinate(for: CGPoint(x: point.x, y: point.y))
      return MapCoordinate(latitude: c.latitude, longitude: c.longitude)
    }
  }

  func selectMarker(id: String) throws {
    DispatchQueue.main.async { self.map.selectMarker(id) }
  }

  func deselectMarker(id: String) throws {
    DispatchQueue.main.async { self.map.deselectMarker(id) }
  }

  func takeSnapshot(width: Double, height: Double) throws -> Promise<String> {
    let promise = Promise<String>()
    DispatchQueue.main.async {
      let size = width > 0 && height > 0 ? CGSize(width: width, height: height) : nil
      self.map.snapshot(size: size) { result in
        switch result {
        case .success(let url): promise.resolve(withResult: url.path)
        case .failure(let error): promise.reject(withError: error)
        }
      }
    }
    return promise
  }

  func addressForCoordinate(coordinate: MapCoordinate) throws -> Promise<MapAddress> {
    let promise = Promise<MapAddress>()
    DispatchQueue.main.async {
      self.map.address(for: CLLocationCoordinate2D(coordinate)) { result in
        switch result {
        case .success(let a):
          promise.resolve(withResult: MapAddress(
            name: a.name, street: a.street, city: a.city, region: a.region, postalCode: a.postalCode,
            country: a.country, countryCode: a.countryCode, formatted: a.formatted,
            shortAddress: [a.street, a.city].filter { !$0.isEmpty }.joined(separator: ", ")))
        case .failure(let error):
          promise.reject(withError: error)
        }
      }
    }
    return promise
  }

  func hasLookAround(coordinate: MapCoordinate) throws -> Promise<Bool> {
    let promise = Promise<Bool>()
    DispatchQueue.main.async {
      self.map.hasLookAround(at: CLLocationCoordinate2D(coordinate)) { promise.resolve(withResult: $0) }
    }
    return promise
  }

  func openLookAround(coordinate: MapCoordinate) throws -> Promise<Bool> {
    let promise = Promise<Bool>()
    DispatchQueue.main.async {
      self.map.openLookAround(at: CLLocationCoordinate2D(coordinate)) { promise.resolve(withResult: $0) }
    }
    return promise
  }

  func measureAlignment() throws -> Promise<MapAlignmentReport> {
    mainPromise { self.map.measureAlignment().nitro }
  }

  func overlayAtPoint(point: MapPoint) throws -> Promise<String> {
    mainPromise { self.map.overlayHit(at: CGPoint(x: point.x, y: point.y))?.id ?? "" }
  }

  func mapItemForFeature(id: String) throws -> Promise<MapItem> {
    let promise = Promise<MapItem>()
    DispatchQueue.main.async {
      self.map.mapItem(forFeature: id) { result in
        switch result {
        case .success(let item): promise.resolve(withResult: MapItem(item))
        case .failure(let error): promise.reject(withError: error)
        }
      }
    }
    return promise
  }

  func providerCommand(command: String, argsJson: String) throws -> Promise<String> {
    let promise = Promise<String>()
    let arguments = (try? JSONSerialization.jsonObject(with: Data(argsJson.utf8))) as? [String: Any] ?? [:]
    DispatchQueue.main.async {
      self.map.providerCommand(command, arguments: arguments) { result in
        switch result {
        case .success(let value): promise.resolve(withResult: Self.json(value))
        case .failure(let error): promise.reject(withError: error)
        }
      }
    }
    return promise
  }
}
