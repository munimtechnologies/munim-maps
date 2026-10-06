import CoreLocation
import Foundation

// Plain Swift types for munim-maps. The React Native views convert their
// props into these; native apps (Swift Package Manager) use them directly.

// MARK: - 3D models

/// A particle effect drawn with a model.
@_expose(!Cxx)
public enum MunimEffect: String, Sendable {
  case none
  /// An engine plume pointing down from the model's base, sized to the model
  /// (a rocket on launch, a jet's afterburner pointing down).
  case exhaust
  /// A billowing smoke cloud on the ground, `width` metres across and
  /// `height` metres tall (a launch pad, a fire). Use without a `uri`.
  case smoke

  var stringValue: String { rawValue }
}

@_expose(!Cxx)
public enum MunimShape: String, Sendable {
  case none, box, sphere, cylinder, cone, capsule, pyramid, gem

  var stringValue: String { rawValue }
}

@_expose(!Cxx)
public enum MunimLighting: String, Sendable {
  /// Follows the map's light or dark appearance.
  case auto
  case day
  case night
}

/// A 3D model on the map.
@_expose(!Cxx)
public struct MunimModel: Sendable {
  public var id: String
  public var latitude: Double
  public var longitude: Double
  /// Metres above the ground.
  public var altitude: Double
  /// Degrees clockwise from north.
  public var heading: Double
  public var scale: Double
  /// `file://`, absolute path or `http(s)://` URL of a USDZ, USD, SCN or OBJ file.
  public var uri: String
  /// Used when `uri` and `imageUri` are empty.
  public var shape: MunimShape
  /// Shape size in metres.
  public var width: Double
  public var height: Double
  public var length: Double
  /// Shape colour, `#RRGGBB` or `#RRGGBBAA`.
  public var color: String
  /// Recolours an asset's paint (materials named `paint…`). Empty keeps its colours.
  public var tintColor: String
  public var emissive: Bool
  public var spinDegreesPerSecond: Double
  public var playAnimations: Bool
  /// When above 0, the model is kept this many points tall at any zoom.
  public var screenSize: Double
  public var groundShadow: Bool
  /// A PNG or JPEG drawn as a round picture that always faces the camera.
  public var imageUri: String
  public var imageBorderColor: String
  public var imageBorderWidth: Double
  /// Short text in a pill under the picture, such as `5F`.
  public var imageBadge: String
  /// Raises the model this many points above `altitude`, at any zoom.
  public var liftPoints: Double
  /// Text in a pill floating above the model.
  public var label: String
  /// A line from the ground up to the model.
  public var stem: Bool
  public var stemColor: String
  public var effect: MunimEffect
  /// 0...1: how strong the effect is, to throttle up or let smoke clear.
  public var effectIntensity: Double
  public var visible: Bool

  public init(
    id: String,
    coordinate: CLLocationCoordinate2D,
    altitude: Double = 0,
    heading: Double = 0,
    scale: Double = 1,
    uri: String = "",
    shape: MunimShape = .box,
    width: Double = 10,
    height: Double = 10,
    length: Double = 10,
    color: String = "#0A84FF",
    tintColor: String = "",
    emissive: Bool = false,
    spinDegreesPerSecond: Double = 0,
    playAnimations: Bool = true,
    screenSize: Double = 0,
    groundShadow: Bool = true,
    imageUri: String = "",
    imageBorderColor: String = "",
    imageBorderWidth: Double = 3,
    imageBadge: String = "",
    liftPoints: Double = 0,
    label: String = "",
    stem: Bool = false,
    stemColor: String = "#FFFFFF",
    effect: MunimEffect = .none,
    effectIntensity: Double = 1,
    visible: Bool = true
  ) {
    self.id = id
    latitude = coordinate.latitude
    longitude = coordinate.longitude
    self.altitude = altitude
    self.heading = heading
    self.scale = scale
    self.uri = uri
    self.shape = uri.isEmpty ? shape : .none
    self.width = width
    self.height = height
    self.length = length
    self.color = color
    self.tintColor = tintColor
    self.emissive = emissive
    self.spinDegreesPerSecond = spinDegreesPerSecond
    self.playAnimations = playAnimations
    self.screenSize = screenSize > 0 ? screenSize : (imageUri.isEmpty ? 0 : 44)
    self.groundShadow = groundShadow && imageUri.isEmpty
    self.imageUri = imageUri
    self.imageBorderColor = imageBorderColor
    self.imageBorderWidth = imageBorderWidth
    self.imageBadge = imageBadge
    self.liftPoints = liftPoints
    self.label = label
    self.stem = stem
    self.stemColor = stemColor
    self.effect = effect
    self.effectIntensity = effectIntensity
    self.visible = visible
  }

  public var coordinate: CLLocationCoordinate2D {
    get { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    set { latitude = newValue.latitude; longitude = newValue.longitude }
  }
}

/// A see-through wall on a zone outline.
@_expose(!Cxx)
public struct MunimZone: Sendable {
  public var id: String
  public var points: [CLLocationCoordinate2D]
  /// Metres.
  public var height: Double
  /// `#RRGGBBAA`; the alpha sets how see-through the wall is.
  public var color: String
  public var visible: Bool

  public init(id: String, points: [CLLocationCoordinate2D], height: Double = 40,
              color: String = "#0A84FF40", visible: Bool = true) {
    self.id = id
    self.points = points
    self.height = height
    self.color = color
    self.visible = visible
  }

  /// A circular zone as a 72-point outline.
  public init(id: String, center: CLLocationCoordinate2D, radius: Double, height: Double = 40,
              color: String = "#0A84FF40", visible: Bool = true) {
    let lat = center.latitude * .pi / 180
    let lon = center.longitude * .pi / 180
    let angular = radius / 6_371_008.8
    let points = (0..<72).map { i -> CLLocationCoordinate2D in
      let bearing = Double(i) / 72 * 2 * .pi
      let pLat = asin(sin(lat) * cos(angular) + cos(lat) * sin(angular) * cos(bearing))
      let pLon = lon + atan2(sin(bearing) * sin(angular) * cos(lat), cos(angular) - sin(lat) * sin(pLat))
      return CLLocationCoordinate2D(latitude: pLat * 180 / .pi, longitude: pLon * 180 / .pi)
    }
    self.init(id: id, points: points, height: height, color: color, visible: visible)
  }
}

/// A line drawn in 3D by the model layer: it can sit above the ground (a
/// flight path or an orbit) and follows the globe when MapKit draws one,
/// where MapKit's own overlays stay flat.
@_expose(!Cxx)
public struct MunimPath: Sendable {
  public var id: String
  public var coordinates: [CLLocationCoordinate2D]
  /// Metres above the ground for each coordinate. Missing values repeat the
  /// last one (empty means on the ground).
  public var altitudes: [Double]
  /// `#RRGGBB` or `#RRGGBBAA`.
  public var color: String
  /// Points on screen.
  public var width: Double
  /// Joins the last point back to the first.
  public var closed: Bool
  public var visible: Bool

  public init(id: String, coordinates: [CLLocationCoordinate2D], altitudes: [Double] = [],
              color: String = "#FFFFFF", width: Double = 2, closed: Bool = false, visible: Bool = true) {
    self.id = id
    self.coordinates = coordinates
    self.altitudes = altitudes
    self.color = color
    self.width = width
    self.closed = closed
    self.visible = visible
  }

  func altitude(at index: Int) -> Double {
    guard !altitudes.isEmpty else { return 0 }
    return altitudes[min(index, altitudes.count - 1)]
  }
}

/// How far the drawn models are from where MapKit draws the same points.
@_expose(!Cxx)
public struct MunimAlignmentReport: Sendable {
  public var attached: Bool
  public var modelsMeasured: Double
  public var maxErrorPoints: Double
  public var meanErrorPoints: Double
  public var modelsVisibleInRender: Double
  public var cameraDistance: Double
  public var cameraPitch: Double
  public var cameraHeading: Double
  public var fieldOfViewDegrees: Double
}

// MARK: - Map features

@_expose(!Cxx)
public enum MunimMarkerStyle: String, Sendable {
  case pin, marker, image, avatar, label, dot

  var stringValue: String { rawValue }
}

@_expose(!Cxx)
public enum MunimBadgePosition: String, Sendable {
  case topLeft = "top-left"
  case topRight = "top-right"
  case bottomLeft = "bottom-left"
  case bottomRight = "bottom-right"
  case bottom

  var stringValue: String { rawValue }
}

@_expose(!Cxx)
public struct MunimMarkerBadge: Sendable {
  public var text: String
  public var position: MunimBadgePosition
  public var color: String
  public var textColor: String

  public init(text: String, position: MunimBadgePosition = .bottom, color: String = "", textColor: String = "") {
    self.text = text
    self.position = position
    self.color = color
    self.textColor = textColor
  }
}

@_expose(!Cxx)
public struct MunimMarker: Sendable {
  public var id: String
  public var latitude: Double
  public var longitude: Double
  public var title: String
  public var subtitle: String
  public var style: MunimMarkerStyle
  public var color: String
  public var glyph: String
  public var imageUri: String
  public var imageSize: Double
  public var borderColor: String
  public var borderWidth: Double
  public var badges: [MunimMarkerBadge]
  public var anchorX: Double
  public var anchorY: Double
  public var zIndex: Double
  public var draggable: Bool
  public var clusteringId: String
  public var calloutEnabled: Bool
  public var opacity: Double
  public var visible: Bool

  public init(
    id: String,
    coordinate: CLLocationCoordinate2D,
    title: String = "",
    subtitle: String = "",
    style: MunimMarkerStyle = .marker,
    color: String = "",
    glyph: String = "",
    imageUri: String = "",
    imageSize: Double = 0,
    borderColor: String = "",
    borderWidth: Double? = nil,
    badges: [MunimMarkerBadge] = [],
    anchorX: Double = 0.5,
    anchorY: Double? = nil,
    zIndex: Double = 0,
    draggable: Bool = false,
    clusteringId: String = "",
    calloutEnabled: Bool = false,
    opacity: Double = 1,
    visible: Bool = true
  ) {
    self.id = id
    latitude = coordinate.latitude
    longitude = coordinate.longitude
    self.title = title
    self.subtitle = subtitle
    self.style = style
    self.color = color
    self.glyph = glyph
    self.imageUri = imageUri
    self.imageSize = imageSize
    self.borderColor = borderColor
    self.borderWidth = borderWidth ?? (style == .avatar ? 2 : 0)
    self.badges = badges
    self.anchorX = anchorX
    self.anchorY = anchorY ?? (style == .image ? 1 : 0.5)
    self.zIndex = zIndex
    self.draggable = draggable
    self.clusteringId = clusteringId
    self.calloutEnabled = calloutEnabled
    self.opacity = opacity
    self.visible = visible
  }
}

@_expose(!Cxx)
public enum MunimLineCap: String, Sendable {
  case round, butt, square

  var stringValue: String { rawValue }
}

@_expose(!Cxx)
public struct MunimPolyline: Sendable {
  public var id: String
  public var coordinates: [CLLocationCoordinate2D]
  public var strokeColor: String
  public var strokeWidth: Double
  /// Dash and gap lengths in points, comma-separated, such as `"4,10"`.
  public var dashPattern: String
  public var geodesic: Bool
  public var lineCap: MunimLineCap
  public var zIndex: Double

  public init(id: String, coordinates: [CLLocationCoordinate2D], strokeColor: String = "#0A84FF",
              strokeWidth: Double = 3, dashPattern: String = "", geodesic: Bool = false,
              lineCap: MunimLineCap = .round, zIndex: Double = 0) {
    self.id = id
    self.coordinates = coordinates
    self.strokeColor = strokeColor
    self.strokeWidth = strokeWidth
    self.dashPattern = dashPattern
    self.geodesic = geodesic
    self.lineCap = lineCap
    self.zIndex = zIndex
  }
}

@_expose(!Cxx)
public struct MunimPolygon: Sendable {
  public var id: String
  public var coordinates: [CLLocationCoordinate2D]
  public var holes: [[CLLocationCoordinate2D]]
  public var strokeColor: String
  public var fillColor: String
  public var strokeWidth: Double
  public var dashPattern: String
  public var zIndex: Double

  public init(id: String, coordinates: [CLLocationCoordinate2D], holes: [[CLLocationCoordinate2D]] = [],
              strokeColor: String = "#0A84FF", fillColor: String = "#0A84FF33", strokeWidth: Double = 2,
              dashPattern: String = "", zIndex: Double = 0) {
    self.id = id
    self.coordinates = coordinates
    self.holes = holes
    self.strokeColor = strokeColor
    self.fillColor = fillColor
    self.strokeWidth = strokeWidth
    self.dashPattern = dashPattern
    self.zIndex = zIndex
  }
}

@_expose(!Cxx)
public struct MunimCircle: Sendable {
  public var id: String
  public var latitude: Double
  public var longitude: Double
  /// Metres.
  public var radius: Double
  public var strokeColor: String
  public var fillColor: String
  public var strokeWidth: Double
  public var dashPattern: String
  public var zIndex: Double

  public init(id: String, center: CLLocationCoordinate2D, radius: Double, strokeColor: String = "#0A84FF",
              fillColor: String = "#0A84FF33", strokeWidth: Double = 2, dashPattern: String = "",
              zIndex: Double = 0) {
    self.id = id
    latitude = center.latitude
    longitude = center.longitude
    self.radius = radius
    self.strokeColor = strokeColor
    self.fillColor = fillColor
    self.strokeWidth = strokeWidth
    self.dashPattern = dashPattern
    self.zIndex = zIndex
  }
}

@_expose(!Cxx)
public struct MunimTileOverlay: Sendable {
  public var id: String
  /// `https://tile.example.com/{z}/{x}/{y}.png`.
  public var urlTemplate: String
  public var replacesMap: Bool
  public var minimumZoom: Double
  public var maximumZoom: Double
  public var opacity: Double
  public var zIndex: Double

  public init(id: String, urlTemplate: String, replacesMap: Bool = false, minimumZoom: Double = 0,
              maximumZoom: Double = 0, opacity: Double = 1, zIndex: Double = 0) {
    self.id = id
    self.urlTemplate = urlTemplate
    self.replacesMap = replacesMap
    self.minimumZoom = minimumZoom
    self.maximumZoom = maximumZoom
    self.opacity = opacity
    self.zIndex = zIndex
  }
}
