import MapKit
import SwiftUI

/// munim-maps in SwiftUI: a MapKit map with markers, shapes, tile overlays,
/// 3D models and zones.
///
/// ```swift
/// MunimMap(
///   initialCamera: MunimCamera(latitude: 41.88, longitude: -87.63, distance: 2500, pitch: 60),
///   models: [MunimModel(id: "car", coordinate: c, uri: MunimVehicles.url("car-ev")!.absoluteString, screenSize: 18)],
///   markers: [MunimMarker(id: "pizza", coordinate: p, glyph: "🍕")],
///   onMarkerPress: { print($0) }
/// )
/// ```
///
/// For everything else (events, camera methods, Look Around), use
/// `MunimMapKitView` from UIKit, or reach it with `onMapCreated`.
@_expose(!Cxx)
public struct MunimMap: UIViewRepresentable {
  public var initialCamera: MunimCamera
  public var models: [MunimModel]
  public var zones: [MunimZone]
  public var paths: [MunimPath]
  public var markers: [MunimMarker]
  public var polylines: [MunimPolyline]
  public var polygons: [MunimPolygon]
  public var circles: [MunimCircle]
  public var tileOverlays: [MunimTileOverlay]
  public var mapStyle: MunimMapStyle
  public var elevation: MunimElevation
  /// The standard style as a globe when zoomed out; see `MunimModelLayer.globe`.
  public var globe: Bool
  /// Hide models behind buildings; see `MunimModelLayer.buildingOcclusion`.
  public var buildingOcclusion: Bool
  public var showsUserLocation: Bool
  public var onModelPress: ((String) -> Void)?
  public var onMarkerPress: ((String) -> Void)?
  public var onPress: ((CLLocationCoordinate2D) -> Void)?
  public var onCameraChange: ((MunimCamera) -> Void)?
  /// Called once with the underlying view, for methods and other events.
  public var onMapCreated: ((MunimMapKitView) -> Void)?

  public init(
    initialCamera: MunimCamera,
    models: [MunimModel] = [],
    zones: [MunimZone] = [],
    paths: [MunimPath] = [],
    markers: [MunimMarker] = [],
    polylines: [MunimPolyline] = [],
    polygons: [MunimPolygon] = [],
    circles: [MunimCircle] = [],
    tileOverlays: [MunimTileOverlay] = [],
    mapStyle: MunimMapStyle = .standard,
    elevation: MunimElevation = .realistic,
    globe: Bool = false,
    buildingOcclusion: Bool = false,
    showsUserLocation: Bool = false,
    onModelPress: ((String) -> Void)? = nil,
    onMarkerPress: ((String) -> Void)? = nil,
    onPress: ((CLLocationCoordinate2D) -> Void)? = nil,
    onCameraChange: ((MunimCamera) -> Void)? = nil,
    onMapCreated: ((MunimMapKitView) -> Void)? = nil
  ) {
    self.initialCamera = initialCamera
    self.models = models
    self.zones = zones
    self.paths = paths
    self.markers = markers
    self.polylines = polylines
    self.polygons = polygons
    self.circles = circles
    self.tileOverlays = tileOverlays
    self.mapStyle = mapStyle
    self.elevation = elevation
    self.globe = globe
    self.buildingOcclusion = buildingOcclusion
    self.showsUserLocation = showsUserLocation
    self.onModelPress = onModelPress
    self.onMarkerPress = onMarkerPress
    self.onPress = onPress
    self.onCameraChange = onCameraChange
    self.onMapCreated = onMapCreated
  }

  public func makeUIView(context: Context) -> MunimMapKitView {
    let view = MunimMapKitView(frame: .zero)
    view.initialCamera = initialCamera
    onMapCreated?(view)
    return view
  }

  public func updateUIView(_ view: MunimMapKitView, context: Context) {
    view.models = models
    view.zones = zones
    view.paths = paths
    view.markers = markers
    view.polylines = polylines
    view.polygons = polygons
    view.circles = circles
    view.tileOverlays = tileOverlays
    view.mapStyle = mapStyle
    view.elevation = elevation
    view.globe = globe
    view.buildingOcclusion = buildingOcclusion
    view.showsUserLocation = showsUserLocation
    view.onModelPress = onModelPress
    view.onMarkerPress = onMarkerPress
    view.onPress = onPress.map { handler in { coordinate, _ in handler(coordinate) } }
    view.onCameraChange = onCameraChange
  }
}
