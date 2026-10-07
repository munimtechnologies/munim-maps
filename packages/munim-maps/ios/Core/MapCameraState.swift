import CoreGraphics
import MapKit
import simd

/// The camera of a map engine, as munim-maps' 3D layer draws with it.
///
/// Every engine (MapKit, Google Maps, Mapbox, MapLibre, Cesium) describes
/// its camera with this, once a frame (`MapCameraSource.cameraState`), and
/// the SceneKit renderer (`MapModelRenderer`) only ever reads this: it never
/// looks at the engine's map view.
///
/// The scene is laid out in metres around the centre coordinate of the map:
/// x points east, y points up and z points south, so SceneKit's default
/// forward direction (-z) is north. Positions come from Web Mercator map
/// points, the flat projection every engine draws in at street and city zoom.
///
/// The camera is a pinhole centred on the view, with a vertical field of
/// view of `fieldOfView` (from `focalLength`, in points), turned to `heading`
/// and `pitch`, `altitude` metres above the ground. The centre coordinate
/// need not be on the camera's centre line: MapKit draws it at the centre of
/// the map's safe area (`centerPoint`), so the camera is moved until the ray
/// through that point lands on it. Engines that centre the map on the view
/// pass the view's centre.
///
/// An engine can draw the Earth as a globe instead (MapKit's satellite
/// imagery with realistic elevation, or the standard style with `MapGlobe`;
/// Mapbox's globe projection; Cesium always). Then `globe` is true: positions
/// are placed on a sphere, still in metres around the centre coordinate with
/// y up there, and the camera sits `distance` metres back along the ray
/// through the centre point.
///
/// Engines whose SDK hands out an exact view-projection (Mapbox and MapLibre
/// custom layers, Cesium) may set `viewMatrixOverride` and
/// `projectionOverride` to use it instead of the pinhole model, in the same
/// scene space.
@_expose(!Cxx)
public struct MapCameraState: Equatable {
  /// The globe is a sphere this size (MapKit's; WGS84's mean radius).
  public static let earthRadius: Double = 6_371_008.8

  /// The centre coordinate of the map.
  public var latitude: Double
  public var longitude: Double
  /// Metres from the camera to the centre coordinate.
  public var distance: Double
  /// Height of the camera above the ground, in metres.
  public var altitude: Double
  /// Degrees from straight down.
  public var pitch: Double
  /// Degrees clockwise from north.
  public var heading: Double
  /// The map's size in points: the viewport.
  public var mapSize: CGSize
  /// Focal length in points (half the map's height over the tangent of half
  /// the vertical field of view).
  public var focalLength: Double
  /// Where the centre coordinate is drawn, in the map's coordinates.
  public var centerPoint: CGPoint
  /// Whether the engine is drawing the Earth as a globe.
  public var globe = false
  /// Whether the engine raises the ground to real terrain heights (MapKit's
  /// satellite imagery with realistic elevation, Mapbox terrain, Cesium).
  /// Models above sea level and `followsTerrain` then lift onto it.
  public var drawsTerrain = false
  /// Whether the map is drawn dark, for `lighting = .auto`.
  public var darkAppearance = false
  /// An exact camera transform (camera to scene, column-major), when the
  /// engine has one. Nil uses the pinhole model above.
  public var cameraTransformOverride: simd_float4x4?
  /// An exact OpenGL-style projection, when the engine has one.
  public var projectionOverride: simd_float4x4?

  public init(
    latitude: Double,
    longitude: Double,
    distance: Double,
    altitude: Double,
    pitch: Double,
    heading: Double,
    mapSize: CGSize,
    focalLength: Double,
    centerPoint: CGPoint,
    globe: Bool = false,
    drawsTerrain: Bool = false,
    darkAppearance: Bool = false
  ) {
    self.latitude = latitude
    self.longitude = longitude
    self.distance = distance
    self.altitude = altitude
    self.pitch = pitch
    self.heading = heading
    self.mapSize = mapSize
    self.focalLength = focalLength
    self.centerPoint = centerPoint
    self.globe = globe
    self.drawsTerrain = drawsTerrain
    self.darkAppearance = darkAppearance
  }

  /// Focal length in points for a vertical field of view, in radians.
  public static func focalLength(height: Double, verticalFieldOfView: Double) -> Double {
    height / 2 / tan(verticalFieldOfView / 2)
  }

  var centerMapPoint: MKMapPoint {
    MKMapPoint(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
  }

  var metersPerMapPoint: Double { MKMetersPerMapPointAtLatitude(latitude) }

  /// Vertical field of view in radians.
  public var fieldOfView: Double {
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
    if let cameraTransformOverride { return cameraTransformOverride }
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
    if let projectionOverride { return projectionOverride }
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
  public func scenePosition(
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
  public func project(_ position: SIMD3<Float>) -> (point: CGPoint, depth: Float)? {
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
}
