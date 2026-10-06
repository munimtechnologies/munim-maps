import CoreGraphics
import MapKit
import simd

/// A MapKit camera turned into a SceneKit camera.
///
/// The scene is laid out in metres around the centre coordinate of the map:
/// x points east, y points up and z points south, so SceneKit's default
/// forward direction (-z) is north. Positions come from Web Mercator map
/// points, the same flat projection MapKit draws in at street and city zoom.
///
/// MapKit's camera, fitted against `MKMapView.convert` on device: a pinhole
/// camera centred on the view (30° vertical field of view on iPhone), turned
/// to the camera's `heading` and `pitch`, at the camera's `altitude`. The
/// centre coordinate is not on the camera's centre line: MapKit draws it at
/// the centre of the map's safe area, so the camera is moved until the ray
/// through that point lands on it.
///
/// MapKit can draw the Earth as a globe instead (satellite imagery with
/// realistic elevation, or the standard style with `MapGlobe`). Then
/// `globe` is true: positions are placed on a sphere, still in metres around
/// the centre coordinate with y up there, and the camera sits `distance`
/// metres back along the ray through the centre point. Close in the two
/// agree; far out only the sphere matches what MapKit draws. MapKit's own
/// `convert` methods stay flat on the globe, so they can't be used to check.
struct MapCameraSnapshot: Equatable {
  /// MapKit's globe is a sphere this size.
  static let earthRadius: Double = 6_371_008.8

  var latitude: Double
  var longitude: Double
  /// Metres from the camera to the centre coordinate, as MapKit reports it.
  var distance: Double
  /// Height of the camera above the ground, in metres.
  var altitude: Double
  var pitch: Double
  var heading: Double
  var mapSize: CGSize
  /// Focal length in points, measured against MapKit (see `read`).
  var focalLength: Double
  /// Where MapKit draws the centre coordinate, in the map's coordinates.
  var centerPoint: CGPoint
  /// Whether MapKit is drawing the Earth as a globe.
  var globe = false

  var centerMapPoint: MKMapPoint {
    MKMapPoint(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
  }

  var metersPerMapPoint: Double { MKMetersPerMapPointAtLatitude(latitude) }

  /// Vertical field of view in radians.
  var fieldOfView: Double {
    guard focalLength > 0, mapSize.height > 0 else { return .pi / 6 }
    return 2 * atan(Double(mapSize.height) / 2 / focalLength)
  }

  var orientation: simd_quatf {
    Self.orientation(heading: heading, pitch: pitch)
  }

  static func orientation(heading: Double, pitch: Double) -> simd_quatf {
    let heading = Float(heading * .pi / 180)
    let pitch = Float(pitch * .pi / 180)
    let yaw = simd_quatf(angle: -heading, axis: SIMD3(0, 1, 0))
    // Start looking straight down, then tilt up towards the horizon.
    let tilt = simd_quatf(angle: -(Float.pi / 2 - pitch), axis: SIMD3(1, 0, 0))
    return yaw * tilt
  }

  /// World direction of the ray through `point` on screen (not normalised).
  static func ray(
    through point: CGPoint,
    mapSize: CGSize,
    focalLength: Double,
    orientation: simd_quatf
  ) -> SIMD3<Float> {
    let local = SIMD3<Float>(
      Float((Double(point.x) - Double(mapSize.width) / 2) / focalLength),
      Float(-(Double(point.y) - Double(mapSize.height) / 2) / focalLength),
      -1)
    return orientation.act(local)
  }

  /// The camera, placed so the ray through `centerPoint` meets the ground at
  /// the centre coordinate (the origin).
  var position: SIMD3<Float> {
    let direction = Self.ray(
      through: centerPoint, mapSize: mapSize, focalLength: focalLength,
      orientation: orientation)
    if globe { return -simd_normalize(direction) * Float(distance) }
    guard direction.y < -1e-5 else {
      return -orientation.act(SIMD3(0, 0, -1)) * Float(distance)
    }
    return -direction * (Float(altitude) / -direction.y)
  }

  var cameraTransform: simd_float4x4 {
    var transform = simd_float4x4(orientation)
    transform.columns.3 = SIMD4(position, 1)
    return transform
  }

  var nearPlane: Float { Float(max(0.5, distance * 0.01)) }
  var farPlane: Float {
    Float(globe ? distance + 2 * Self.earthRadius : max(10_000, distance * 60))
  }

  /// OpenGL-style perspective matrix, the convention SceneKit's
  /// `projectionTransform` uses.
  var projection: simd_float4x4 {
    let aspect = Float(mapSize.width / max(1, mapSize.height))
    let f = 1 / tan(Float(fieldOfView) / 2)
    let near = nearPlane
    let far = farPlane
    return simd_float4x4(columns: (
      SIMD4(f / aspect, 0, 0, 0),
      SIMD4(0, f, 0, 0),
      SIMD4(0, 0, (far + near) / (near - far), -1),
      SIMD4(0, 0, 2 * far * near / (near - far), 0)
    ))
  }

  /// Scene position of a coordinate, `altitude` metres above the ground.
  func scenePosition(
    latitude: Double,
    longitude: Double,
    altitude: Double
  ) -> SIMD3<Float> {
    if globe { return globePosition(latitude: latitude, longitude: longitude, altitude: altitude) }
    let point = MKMapPoint(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
    let center = centerMapPoint
    let scale = metersPerMapPoint
    return SIMD3(
      Float((point.x - center.x) * scale),
      Float(altitude),
      Float((point.y - center.y) * scale)
    )
  }

  /// Turns a model standing at a coordinate upright there: identity on the
  /// flat map, tilted with the Earth's curve on the globe.
  func localOrientation(latitude: Double, longitude: Double) -> simd_quatf {
    guard globe else { return simd_quatf(ix: 0, iy: 0, iz: 0, r: 1) }
    let frame = Self.enuFrame(latitude: latitude, longitude: longitude)
    let center = Self.enuFrame(latitude: self.latitude, longitude: self.longitude)
    func toScene(_ v: SIMD3<Double>) -> SIMD3<Float> {
      SIMD3(Float(simd_dot(v, center.east)), Float(simd_dot(v, center.up)), Float(-simd_dot(v, center.north)))
    }
    // The local axes (x east, y up, z south) seen from the centre's frame.
    let matrix = simd_float3x3(columns: (toScene(frame.east), toScene(frame.up), toScene(-frame.north)))
    return simd_quatf(matrix)
  }

  /// Unit vector pointing up (away from the ground) at a coordinate.
  func localUp(latitude: Double, longitude: Double) -> SIMD3<Float> {
    localOrientation(latitude: latitude, longitude: longitude).act(SIMD3(0, 1, 0))
  }

  private static func enuFrame(latitude: Double, longitude: Double)
    -> (east: SIMD3<Double>, north: SIMD3<Double>, up: SIMD3<Double>)
  {
    let phi = latitude * .pi / 180
    let lambda = longitude * .pi / 180
    return (
      SIMD3(-sin(lambda), cos(lambda), 0),
      SIMD3(-sin(phi) * cos(lambda), -sin(phi) * sin(lambda), cos(phi)),
      SIMD3(cos(phi) * cos(lambda), cos(phi) * sin(lambda), sin(phi))
    )
  }

  private func globePosition(latitude: Double, longitude: Double, altitude: Double) -> SIMD3<Float> {
    let r = Self.earthRadius
    let center = Self.enuFrame(latitude: self.latitude, longitude: self.longitude)
    let up = Self.enuFrame(latitude: latitude, longitude: longitude).up
    let d = up * (r + altitude) - center.up * r
    return SIMD3(Float(simd_dot(d, center.east)), Float(simd_dot(d, center.up)), Float(-simd_dot(d, center.north)))
  }

  /// Screen point (in the map's own coordinates) of a scene position, and
  /// its depth along the view direction. Nil when behind the camera.
  func project(_ position: SIMD3<Float>) -> (point: CGPoint, depth: Float)? {
    let view = cameraTransform.inverse
    let eye = view * SIMD4(position, 1)
    let clip = projection * eye
    guard clip.w > 1e-4 else { return nil }
    let ndc = SIMD2(clip.x, clip.y) / clip.w
    let point = CGPoint(
      x: CGFloat((ndc.x + 1) / 2) * mapSize.width,
      y: CGFloat((1 - ndc.y) / 2) * mapSize.height
    )
    return (point, -eye.z)
  }

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
  ) -> MapCameraSnapshot? {
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

    var snapshot = MapCameraSnapshot(
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
