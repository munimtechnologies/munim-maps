#if canImport(GoogleMaps)
import GoogleMaps
import MapKit
import UIKit

/// Google's camera for munim-maps' 3D layer: reads a `GMSMapView` every
/// frame and describes it as a `MapCameraState`.
///
/// Google publishes a zoom level, not a camera distance or field of view,
/// so both are measured from Google's own projection: the ground scale on
/// the screen row through the camera target gives points per metre at the
/// target's depth, and, while the map is tilted, how much a point further up
/// the screen is foreshortened gives the distance to the target. Their
/// product is the focal length, kept (as a field of view) for flat views.
final class GoogleCameraSource: MapCameraSource {
  weak var mapView: GMSMapView?

  /// Google's vertical field of view in radians, measured from its
  /// projection the first time a map is tilted (the same for every map).
  static var fieldOfView: Double = defaultFieldOfView
  static var fieldOfViewMeasured = false
  /// A starting guess until a tilted map has been measured.
  static let defaultFieldOfView: Double = 2 * atan(1.0 / 2.0)

  /// Web Mercator's sphere: 256 points span 2πR at zoom 0.
  static let earthRadius = 6_378_137.0

  init(mapView: GMSMapView) {
    self.mapView = mapView
  }

  var cameraView: UIView? { mapView }

  func cameraState(previous: MapCameraState?) -> MapCameraState? {
    guard let mapView else { return nil }
    let size = mapView.bounds.size
    guard size.width > 1, size.height > 1 else { return nil }
    let position = mapView.camera
    let target = position.target
    guard CLLocationCoordinate2DIsValid(target) else { return nil }
    let projection = mapView.projection
    let pitch = position.viewingAngle
    let heading = position.bearing

    var center = projection.point(for: target)
    if !center.x.isFinite || !center.y.isFinite {
      let inset = mapView.bounds.inset(by: mapView.padding)
      center = CGPoint(x: inset.midX, y: inset.midY)
    }

    let measured = Self.measure(
      projection: projection, target: target, center: center, size: size, pitch: pitch, heading: heading)
    let pointsPerMeter = measured?.pointsPerMeter
      ?? Self.pointsPerMeter(zoom: Double(position.zoom), latitude: target.latitude)
    if let focal = measured?.focalLength {
      let fov = 2 * atan(Double(size.height) / 2 / focal)
      if fov.isFinite, fov > 0.05, fov < 2.5 {
        Self.fieldOfView = Self.fieldOfViewMeasured ? Self.fieldOfView * 0.8 + fov * 0.2 : fov
        Self.fieldOfViewMeasured = true
      }
    }
    let focal = measured?.focalLength ?? MapCameraState.focalLength(
      height: Double(size.height), verticalFieldOfView: Self.fieldOfView)
    let distance = focal / pointsPerMeter
    guard distance.isFinite, distance > 0 else { return nil }

    var state = MapCameraState(
      latitude: target.latitude,
      longitude: target.longitude,
      distance: distance,
      altitude: distance * cos(pitch * .pi / 180),
      pitch: pitch,
      heading: heading,
      mapSize: size,
      focalLength: focal,
      centerPoint: center)
    state.darkAppearance = Self.isDark(mapView)
    return state
  }

  func screenPoint(for coordinate: CLLocationCoordinate2D) -> CGPoint? {
    mapView?.projection.point(for: coordinate)
  }

  func visibleRegion() -> MKCoordinateRegion? {
    guard let mapView else { return nil }
    return Self.region(GMSCoordinateBounds(region: mapView.projection.visibleRegion()))
  }

  // MARK: Measuring

  /// Points per metre at the target's depth, and the focal length when the
  /// map is tilted enough to tell.
  static func measure(
    projection: GMSProjection, target: CLLocationCoordinate2D, center: CGPoint, size: CGSize,
    pitch: Double, heading: Double
  ) -> (pointsPerMeter: Double, focalLength: Double?)? {
    let metersPerMapPoint = MKMetersPerMapPointAtLatitude(target.latitude)
    let half = min(60, Double(size.width) / 4)
    let left = projection.coordinate(for: CGPoint(x: Double(center.x) - half, y: Double(center.y)))
    let right = projection.coordinate(for: CGPoint(x: Double(center.x) + half, y: Double(center.y)))
    guard CLLocationCoordinate2DIsValid(left), CLLocationCoordinate2DIsValid(right) else { return nil }
    let a = MKMapPoint(left), b = MKMapPoint(right)
    let meters = hypot(b.x - a.x, b.y - a.y) * metersPerMapPoint
    guard meters.isFinite, meters > 0 else { return nil }
    let k = 2 * half / meters

    guard pitch >= 10 else { return (k, nil) }
    // A point up the screen from the target, on the ground further away.
    let h = min(Double(center.y) * 0.6, Double(size.height) / 4)
    guard h > 10 else { return (k, nil) }
    let far = projection.coordinate(for: CGPoint(x: Double(center.x), y: Double(center.y) - h))
    guard CLLocationCoordinate2DIsValid(far) else { return (k, nil) }
    let c = MKMapPoint(target), f = MKMapPoint(far)
    let east = (f.x - c.x) * metersPerMapPoint
    let north = -(f.y - c.y) * metersPerMapPoint
    let theta = heading * .pi / 180
    let s = east * sin(theta) + north * cos(theta)
    let tilt = pitch * .pi / 180
    let denominator = k * s * cos(tilt) - h
    guard s > 0, denominator > 1e-9 else { return (k, nil) }
    let distance = h * s * sin(tilt) / denominator
    guard distance.isFinite, distance > 0 else { return (k, nil) }
    return (k, k * distance)
  }

  // MARK: Zoom and distance

  /// Ground points per metre at a zoom level (256-point tiles).
  static func pointsPerMeter(zoom: Double, latitude: Double) -> Double {
    256 * pow(2, zoom) / (2 * .pi * earthRadius * max(0.01, cos(latitude * .pi / 180)))
  }

  static func focalLength(height: CGFloat) -> Double {
    MapCameraState.focalLength(height: Double(max(1, height)), verticalFieldOfView: fieldOfView)
  }

  /// Metres from the camera to the target at a zoom level, for a map this tall.
  static func distance(zoom: Double, latitude: Double, height: CGFloat) -> Double {
    focalLength(height: height) / pointsPerMeter(zoom: zoom, latitude: latitude)
  }

  /// The zoom level that puts the camera `distance` metres from the target.
  static func zoom(distance: Double, latitude: Double, height: CGFloat) -> Double {
    let perMeter = focalLength(height: height) / max(1, distance)
    return log2(perMeter * 2 * .pi * earthRadius * max(0.01, cos(latitude * .pi / 180)) / 256)
  }

  static func region(_ bounds: GMSCoordinateBounds) -> MKCoordinateRegion {
    let sw = bounds.southWest, ne = bounds.northEast
    var lngDelta = ne.longitude - sw.longitude
    if lngDelta < 0 { lngDelta += 360 }
    var lng = sw.longitude + lngDelta / 2
    if lng > 180 { lng -= 360 }
    return MKCoordinateRegion(
      center: CLLocationCoordinate2D(latitude: (sw.latitude + ne.latitude) / 2, longitude: lng),
      span: MKCoordinateSpan(latitudeDelta: ne.latitude - sw.latitude, longitudeDelta: lngDelta))
  }

  static func isDark(_ mapView: GMSMapView) -> Bool {
    switch mapView.overrideUserInterfaceStyle {
    case .dark: return true
    case .light: return false
    default: return mapView.traitCollection.userInterfaceStyle == .dark
    }
  }
}
#endif
