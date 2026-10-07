import MapKit
import UIKit
import simd

/// MapKit's camera for the 3D layer: reads an `MKMapView` every frame.
///
/// MapKit does not publish its projection, so the camera is fitted to it
/// (see `MapCameraState.read(from:previousFocalLength:globe:)`), measured
/// on device to well under a point.
@_expose(!Cxx)
public final class MapKitCameraSource: MapCameraSource {
  public private(set) weak var mapView: MKMapView?

  public init(mapView: MKMapView) {
    self.mapView = mapView
  }

  public var cameraView: UIView? { mapView }

  public func cameraState(previous: MapCameraState?) -> MapCameraState? {
    guard let mapView else { return nil }
    guard var state = MapCameraState.read(
      from: mapView, previousFocalLength: previous?.focalLength ?? 0,
      globe: MapGlobe.isShowingGlobe(mapView))
    else { return nil }
    state.drawsTerrain = Self.drawsTerrain(mapView)
    state.darkAppearance = mapView.traitCollection.userInterfaceStyle == .dark
    return state
  }

  public func screenPoint(for coordinate: CLLocationCoordinate2D) -> CGPoint? {
    guard let mapView else { return nil }
    return mapView.convert(coordinate, toPointTo: mapView)
  }

  public func visibleRegion() -> MKCoordinateRegion? {
    mapView?.region
  }

  /// Whether MapKit is drawing real 3D terrain. Satellite imagery (`hybrid`,
  /// `imagery`) with realistic elevation raises the ground to its height;
  /// the standard style stays flat with shading, even when realistic.
  static func drawsTerrain(_ mapView: MKMapView) -> Bool {
    if #available(iOS 16.0, *) {
      switch mapView.preferredConfiguration {
      case let hybrid as MKHybridMapConfiguration: return hybrid.elevationStyle == .realistic
      case let imagery as MKImageryMapConfiguration: return imagery.elevationStyle == .realistic
      default: break
      }
    }
    return mapView.mapType == .hybridFlyover || mapView.mapType == .satelliteFlyover
  }
}

extension MapCameraState {
  /// Reads the camera of `mapView`, measuring its focal length.
  ///
  /// MapKit does not publish its field of view, so it is measured from the
  /// map: two points on the screen row through the centre coordinate land on
  /// a ground line square to the view, all at the same depth, so their
  /// ground distance gives the focal length. The depth itself depends a
  /// little on the focal length (the row is off the centre line), so this
  /// settles it in a few rounds. Falls back to `previousFocalLength` when
  /// the map cannot answer, for example before it has a size.
  static func read(
    from mapView: MKMapView,
    previousFocalLength: Double,
    globe: Bool = false
  ) -> MapCameraState? {
    let bounds = mapView.bounds
    guard bounds.width > 1, bounds.height > 1 else { return nil }
    let camera = mapView.camera
    let distance = camera.centerCoordinateDistance
    let altitude = camera.altitude
    guard distance.isFinite, distance > 0, altitude.isFinite, altitude > 0 else { return nil }
    let pitch = Double(camera.pitch)
    let heading = camera.heading

    let local = CGRect(origin: .zero, size: bounds.size)
    var center = mapView.convert(camera.centerCoordinate, toPointTo: mapView)
    center.x -= bounds.minX
    center.y -= bounds.minY
    if !center.x.isFinite || !center.y.isFinite || !local.contains(center) {
      center = CGPoint(x: local.midX, y: local.midY)
    }

    // 30° vertical is what MapKit uses on iPhone; only a starting guess.
    var focal = previousFocalLength > 0
      ? previousFocalLength : Double(bounds.height) / 2 / tan(.pi / 12)
    let half = min(60, bounds.width / 4)
    let left = mapView.convert(
      CGPoint(x: bounds.minX + center.x - half, y: bounds.minY + center.y),
      toCoordinateFrom: mapView)
    let right = mapView.convert(
      CGPoint(x: bounds.minX + center.x + half, y: bounds.minY + center.y),
      toCoordinateFrom: mapView)
    if CLLocationCoordinate2DIsValid(left), CLLocationCoordinate2DIsValid(right) {
      let meters = MKMapPoint(left).distance(to: MKMapPoint(right))
      if meters.isFinite, meters > 0 {
        let rotation = orientation(heading: heading, pitch: pitch)
        let forward = rotation.act(SIMD3<Float>(0, 0, -1))
        for _ in 0..<4 {
          let direction = ray(
            through: center, mapSize: bounds.size, focalLength: focal, orientation: rotation)
          guard direction.y < -1e-5 else { break }
          let toGround = direction * (Float(altitude) / -direction.y)
          let depth = Double(simd_dot(toGround, forward))
          guard depth > 0 else { break }
          focal = Double(2 * half) * depth / meters
        }
      }
    }
    guard focal > 0 else { return nil }

    var snapshot = MapCameraState(
      latitude: camera.centerCoordinate.latitude,
      longitude: camera.centerCoordinate.longitude,
      distance: distance,
      altitude: altitude,
      pitch: pitch,
      heading: heading,
      mapSize: bounds.size,
      focalLength: focal,
      centerPoint: center
    )
    if globe {
      snapshot.globe = true
      // MapKit's conversions stay flat on the globe, so far out the
      // measurement above is off; keep the focal length measured closer in.
      if distance > flatMeasurementLimit, previousFocalLength > 0 {
        snapshot.focalLength = previousFocalLength
      }
    }
    return snapshot
  }

  /// Beyond this distance the flat focal-length measurement is not trusted.
  private static let flatMeasurementLimit: Double = 1_000_000
}
