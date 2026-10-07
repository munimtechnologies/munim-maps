import MapKit
import UIKit

/// The map engines munim-maps can draw with.
@_expose(!Cxx)
public enum MunimMapProvider: String, CaseIterable, Sendable {
  /// Apple's MapKit. Always built in on iOS.
  case mapkit
  /// Google Maps SDK for iOS (`NitroMunimMaps/Google` subspec).
  case google
  /// Mapbox Maps SDK v11 (`NitroMunimMaps/Mapbox` subspec).
  case mapbox
  /// MapLibre Native (`NitroMunimMaps/MapLibre` subspec): open maps,
  /// OpenStreetMap data from OpenFreeMap by default, no key.
  case maplibre
  /// Cesium, a 3D globe with terrain and 3D Tiles (`NitroMunimMaps/Cesium`).
  case cesium

  /// The name people know it by, for messages.
  public var displayName: String {
    switch self {
    case .mapkit: return "MapKit"
    case .google: return "Google Maps"
    case .mapbox: return "Mapbox"
    case .maplibre: return "MapLibre"
    case .cesium: return "Cesium"
    }
  }

  /// The CocoaPods subspec that builds this engine in.
  public var subspec: String {
    switch self {
    case .mapkit: return "NitroMunimMaps"
    case .google: return "NitroMunimMaps/Google"
    case .mapbox: return "NitroMunimMaps/Mapbox"
    case .maplibre: return "NitroMunimMaps/MapLibre"
    case .cesium: return "NitroMunimMaps/Cesium"
    }
  }
}

/// An error from an engine, such as a method it does not support.
@_expose(!Cxx)
public struct MunimMapEngineError: LocalizedError, Sendable {
  public var message: String
  public init(_ message: String) { self.message = message }
  public var errorDescription: String? { message }
}

/// One map engine behind `MunimMapView`: MapKit, Google Maps, Mapbox,
/// MapLibre or Cesium.
///
/// `MunimMapContainerView` (what React Native's `MunimMapView` and Swift's
/// `MunimMapHost` show) owns one engine at a time, puts `view` in itself and
/// sets the properties below as props change. The engine draws the map and
/// its 2D features (markers, shapes, tile overlays) with its own SDK, and
/// reports events through the `on…` closures.
///
/// 3D models, zones and paths are not the engine's job: every engine owns a
/// `MunimModelLayer` (`modelLayer`), puts its view over the map view, and
/// attaches it to a `MapCameraSource` that describes the engine's camera
/// each frame (`MapCameraState`: centre, distance, pitch, heading, field of
/// view, viewport, globe). The container sets models, zones, paths,
/// lighting, occlusion and terrain on that layer directly, so the SceneKit
/// renderer draws the same models over any engine.
///
/// Properties and methods have default implementations (a no-op, or an
/// `onError` / failed completion saying the engine does not support it), so
/// an engine can be built up feature by feature. The `on…` events have none:
/// declare each as a stored property and call it when it happens. The
/// MapKit engine (`MunimMapKitView`) is the reference implementation.
///
/// MapKit value types (`MKCoordinateRegion`, `MKUserTrackingMode`,
/// `MKPointOfInterestFilter`, `MKMapItem`) appear in the interface because
/// munim-maps started on MapKit; MapKit is part of iOS, so every engine can
/// use them.
public protocol MunimMapEngine: AnyObject {
  // MARK: Identity

  var provider: MunimMapProvider { get }
  /// The engine's map view, sized to the container.
  var view: UIView { get }
  /// munim-maps' 3D layer, over the map and attached to the engine's camera.
  var modelLayer: MunimModelLayer { get }

  // MARK: Provider settings

  /// MapLibre / Mapbox style URL. Empty for the engine's default.
  var styleURL: String { get set }
  /// The active provider's own options (the `google`, `mapbox`, `maplibre`,
  /// `cesium` or `mapkit` prop in React Native), decoded from JSON.
  var providerOptions: [String: Any] { get set }

  // MARK: 2D content

  var markers: [MunimMarker] { get set }
  var polylines: [MunimPolyline] { get set }
  var polygons: [MunimPolygon] { get set }
  var circles: [MunimCircle] { get set }
  var tileOverlays: [MunimTileOverlay] { get set }
  var clusterStyles: [MunimClusterStyle] { get set }
  /// A marker drawn from a React Native view (`MarkerView`): `image` is the
  /// view rendered, updated with `setViewMarkerImage`.
  func setViewMarker(_ marker: MunimMarker, image: UIImage?)
  func setViewMarkerImage(_ image: UIImage?, id: String)
  func removeViewMarker(_ id: String)

  // MARK: Look

  /// Applied once, when the map first has a size.
  var initialCamera: MunimCamera? { get set }
  var mapStyle: MunimMapStyle { get set }
  var elevation: MunimElevation { get set }
  /// Draw the Earth as a globe when zoomed far out.
  var globe: Bool { get set }
  var colorScheme: UIUserInterfaceStyle { get set }
  var showsBuildings: Bool { get set }
  var showsUserLocation: Bool { get set }
  var showsTraffic: Bool { get set }
  var pointOfInterestFilter: MKPointOfInterestFilter { get set }

  // MARK: Controls

  var compassVisibility: MunimFeatureVisibility { get set }
  var scaleVisibility: MunimFeatureVisibility { get set }
  var showsUserTrackingButton: Bool { get set }
  var pitchButtonVisibility: MunimFeatureVisibility { get set }
  /// Name standalone controls use to find this map.
  var mapScope: String { get set }
  /// What tapping a place on the base map shows (MapKit's place cards).
  var selectionAccessory: MunimSelectionAccessory { get set }
  /// Places on the base map that can be tapped (`onMapFeaturePress`).
  var selectableFeatures: Set<MunimMapFeatureKind> { get set }

  // MARK: Gestures and limits

  var userTrackingMode: MKUserTrackingMode { get set }
  var isZoomEnabled: Bool { get set }
  var isScrollEnabled: Bool { get set }
  var isRotateEnabled: Bool { get set }
  var isPitchEnabled: Bool { get set }
  /// Closest and farthest camera distance in metres; nil for the engine's.
  var cameraDistanceRange: ClosedRange<Double>? { get set }
  /// Keep the camera's centre inside this region; nil for none.
  var cameraBoundary: MKCoordinateRegion? { get set }
  /// Space covered by the app's own UI; the map centres in what is left.
  var mapPadding: UIEdgeInsets { get set }

  // MARK: Events (no defaults: declare them as stored properties)

  var onMapReady: (() -> Void)? { get set }
  /// A tap on the map (not on a marker, model or tappable overlay).
  var onPress: ((CLLocationCoordinate2D, CGPoint) -> Void)? { get set }
  var onLongPress: ((CLLocationCoordinate2D, CGPoint) -> Void)? { get set }
  /// While the camera moves, about once a frame.
  var onCameraMove: ((MunimCamera) -> Void)? { get set }
  /// When the camera stops.
  var onCameraChange: ((MunimCamera) -> Void)? { get set }
  var onMarkerPress: ((String) -> Void)? { get set }
  var onMarkerDeselect: ((String) -> Void)? { get set }
  var onCalloutPress: ((String) -> Void)? { get set }
  /// Marker id and `"left"` or `"right"`.
  var onCalloutAccessoryPress: ((String, String) -> Void)? { get set }
  /// Clustering id, member marker ids, where the cluster is.
  var onClusterPress: ((String, [String], CLLocationCoordinate2D) -> Void)? { get set }
  /// Id, kind (`polyline`, `polygon`, `circle`) and where. Overlays are only
  /// hit-tested while this is set; taken instead of `onPress`.
  var onOverlayPress: ((String, String, CLLocationCoordinate2D) -> Void)? { get set }
  var onMarkerDragStart: ((String, CLLocationCoordinate2D) -> Void)? { get set }
  var onMarkerDragEnd: ((String, CLLocationCoordinate2D) -> Void)? { get set }
  var onUserLocationChange: ((CLLocation) -> Void)? { get set }
  var onMapFeaturePress: ((MunimMapFeature) -> Void)? { get set }
  /// The engine changed the tracking mode (the user panned away).
  var onUserTrackingModeChange: ((MKUserTrackingMode) -> Void)? { get set }
  /// Errors from the engine. Also forward them from `modelLayer.onError`.
  var onError: ((String) -> Void)? { get set }

  // MARK: Camera

  var camera: MunimCamera { get }
  func setCamera(_ camera: MunimCamera, animated: Bool)
  func animateCamera(_ camera: MunimCamera, duration: TimeInterval, linear: Bool)
  /// Flies through keyframes on the native frame clock; `start` is seconds
  /// since 1970, the clock models' `motion` uses.
  func flyCamera(_ keyframes: [MunimCameraKeyframe], start: Double, loop: Bool)
  func stopFlight()
  var visibleRegion: MKCoordinateRegion { get }
  func setRegion(_ region: MKCoordinateRegion, duration: TimeInterval)
  func fit(coordinates: [CLLocationCoordinate2D], padding: UIEdgeInsets, animated: Bool)
  /// Frames these markers (all when empty).
  func fitMarkers(_ ids: Set<String>, padding: UIEdgeInsets, animated: Bool)
  func point(for coordinate: CLLocationCoordinate2D) -> CGPoint
  func coordinate(for point: CGPoint) -> CLLocationCoordinate2D

  // MARK: Methods

  func selectMarker(_ id: String)
  func deselectMarker(_ id: String)
  /// A PNG of the map (no models or markers needed).
  func snapshot(size: CGSize?, completion: @escaping (Result<URL, Error>) -> Void)
  func address(for coordinate: CLLocationCoordinate2D, completion: @escaping (Result<MunimAddress, Error>) -> Void)
  func hasLookAround(at coordinate: CLLocationCoordinate2D, completion: @escaping (Bool) -> Void)
  func openLookAround(at coordinate: CLLocationCoordinate2D, completion: @escaping (Bool) -> Void)
  /// How far the 3D layer is from where the engine draws the same points.
  func measureAlignment() -> MunimAlignmentReport
  /// The tappable overlay a tap at `point` would hit.
  func overlayHit(at point: CGPoint) -> (id: String, kind: String)?
  func mapItem(forFeature id: String, completion: @escaping (Result<MKMapItem, Error>) -> Void)

  // MARK: Engine-only methods and events

  /// An engine-only method (React Native `ref.providerCall`): `args` is the
  /// decoded JSON object; complete with any JSON-compatible value
  /// (`[String: Any]`, `[Any]`, `String`, `NSNumber`, `Bool`, `NSNull`).
  /// The default rejects every method.
  func providerCall(_ method: String, args: [String: Any], completion: @escaping (Result<Any, Error>) -> Void)
  /// Engine-only events (`onProviderEvent`): a name and a JSON-compatible
  /// payload. Declare it as a stored property to send events; the default
  /// drops them.
  var onProviderEvent: ((String, Any) -> Void)? { get set }
}

public extension MunimMapEngine {
  func providerCall(_ method: String, args: [String: Any], completion: @escaping (Result<Any, Error>) -> Void) {
    completion(.failure(MunimMapEngineError("\(provider.displayName) has no method \"\(method)\"")))
  }

  var onProviderEvent: ((String, Any) -> Void)? { get { nil } set {} }

  /// Reports that this engine cannot do `what` yet.
  func reportUnsupported(_ what: String) {
    onError?("\(provider.displayName): \(what) is not supported yet")
  }

  func unsupportedError(_ what: String) -> MunimMapEngineError {
    MunimMapEngineError("\(provider.displayName): \(what) is not supported yet")
  }
}

// MARK: - Defaults

/// Adopt this next to `MunimMapEngine` to get the default implementations
/// below for everything the engine does not implement yet. An engine that
/// implements everything (MapKit) leaves it out, so the compiler reports any
/// requirement it misses instead of silently using a default.
public protocol MunimMapEngineDefaults {}

public extension MunimMapEngine where Self: MunimMapEngineDefaults {
  var styleURL: String { get { "" } set {} }
  var providerOptions: [String: Any] { get { [:] } set {} }

  var markers: [MunimMarker] { get { [] } set { if !newValue.isEmpty { reportUnsupported("markers") } } }
  var polylines: [MunimPolyline] { get { [] } set { if !newValue.isEmpty { reportUnsupported("polylines") } } }
  var polygons: [MunimPolygon] { get { [] } set { if !newValue.isEmpty { reportUnsupported("polygons") } } }
  var circles: [MunimCircle] { get { [] } set { if !newValue.isEmpty { reportUnsupported("circles") } } }
  var tileOverlays: [MunimTileOverlay] { get { [] } set { if !newValue.isEmpty { reportUnsupported("tileOverlays") } } }
  var clusterStyles: [MunimClusterStyle] { get { [] } set {} }
  func setViewMarker(_ marker: MunimMarker, image: UIImage?) { reportUnsupported("MarkerView") }
  func setViewMarkerImage(_ image: UIImage?, id: String) {}
  func removeViewMarker(_ id: String) {}

  var mapStyle: MunimMapStyle { get { .standard } set {} }
  var elevation: MunimElevation { get { .realistic } set {} }
  var globe: Bool { get { false } set {} }
  var colorScheme: UIUserInterfaceStyle { get { .unspecified } set {} }
  var showsBuildings: Bool { get { true } set {} }
  var showsUserLocation: Bool { get { false } set { if newValue { reportUnsupported("showsUserLocation") } } }
  var showsTraffic: Bool { get { false } set {} }
  var pointOfInterestFilter: MKPointOfInterestFilter { get { .includingAll } set {} }

  var compassVisibility: MunimFeatureVisibility { get { .hidden } set {} }
  var scaleVisibility: MunimFeatureVisibility { get { .hidden } set {} }
  var showsUserTrackingButton: Bool { get { false } set {} }
  var pitchButtonVisibility: MunimFeatureVisibility { get { .hidden } set {} }
  var mapScope: String { get { "" } set {} }
  var selectionAccessory: MunimSelectionAccessory { get { .none } set {} }
  var selectableFeatures: Set<MunimMapFeatureKind> { get { [] } set {} }

  var userTrackingMode: MKUserTrackingMode {
    get { .none }
    set { if newValue != .none { reportUnsupported("userTrackingMode") } }
  }
  var isZoomEnabled: Bool { get { true } set {} }
  var isScrollEnabled: Bool { get { true } set {} }
  var isRotateEnabled: Bool { get { true } set {} }
  var isPitchEnabled: Bool { get { true } set {} }
  var cameraDistanceRange: ClosedRange<Double>? { get { nil } set {} }
  var cameraBoundary: MKCoordinateRegion? { get { nil } set {} }
  var mapPadding: UIEdgeInsets { get { .zero } set {} }

  var camera: MunimCamera { initialCamera ?? MunimCamera(latitude: 0, longitude: 0, distance: 10_000_000) }
  func setCamera(_ camera: MunimCamera, animated: Bool) { reportUnsupported("setCamera") }
  func animateCamera(_ camera: MunimCamera, duration: TimeInterval, linear: Bool) {
    setCamera(camera, animated: duration > 0)
  }
  func flyCamera(_ keyframes: [MunimCameraKeyframe], start: Double, loop: Bool) { reportUnsupported("flyCamera") }
  func stopFlight() {}
  var visibleRegion: MKCoordinateRegion {
    MKCoordinateRegion(
      center: CLLocationCoordinate2D(latitude: camera.latitude, longitude: camera.longitude),
      span: MKCoordinateSpan(latitudeDelta: 0, longitudeDelta: 0))
  }
  func setRegion(_ region: MKCoordinateRegion, duration: TimeInterval) { reportUnsupported("setRegion") }
  func fit(coordinates: [CLLocationCoordinate2D], padding: UIEdgeInsets, animated: Bool) {
    reportUnsupported("fitToCoordinates")
  }
  func fitMarkers(_ ids: Set<String>, padding: UIEdgeInsets, animated: Bool) { reportUnsupported("fitToMarkers") }
  func point(for coordinate: CLLocationCoordinate2D) -> CGPoint {
    reportUnsupported("pointForCoordinate")
    return .zero
  }
  func coordinate(for point: CGPoint) -> CLLocationCoordinate2D {
    reportUnsupported("coordinateForPoint")
    return kCLLocationCoordinate2DInvalid
  }

  func selectMarker(_ id: String) {}
  func deselectMarker(_ id: String) {}
  func snapshot(size: CGSize?, completion: @escaping (Result<URL, Error>) -> Void) {
    completion(.failure(unsupportedError("takeSnapshot")))
  }
  func address(for coordinate: CLLocationCoordinate2D, completion: @escaping (Result<MunimAddress, Error>) -> Void) {
    completion(.failure(unsupportedError("addressForCoordinate")))
  }
  func hasLookAround(at coordinate: CLLocationCoordinate2D, completion: @escaping (Bool) -> Void) { completion(false) }
  func openLookAround(at coordinate: CLLocationCoordinate2D, completion: @escaping (Bool) -> Void) { completion(false) }
  func measureAlignment() -> MunimAlignmentReport { modelLayer.measureAlignment() }
  func overlayHit(at point: CGPoint) -> (id: String, kind: String)? { nil }
  func mapItem(forFeature id: String, completion: @escaping (Result<MKMapItem, Error>) -> Void) {
    completion(.failure(unsupportedError("mapItemForFeature")))
  }
}
