import CoreLocation
import UIKit

// Map types shared by every engine (MapKit, Google, Mapbox, MapLibre, Cesium).

/// When the map shows a control: only when useful, always, or never.
@_expose(!Cxx)
public enum MunimFeatureVisibility: String, Sendable {
  case adaptive, visible, hidden
}

@_expose(!Cxx)
public enum MunimMapStyle: String, Sendable { case standard, muted, hybrid, imagery }
@_expose(!Cxx)
public enum MunimElevation: String, Sendable { case flat, realistic }
@_expose(!Cxx)
public enum MunimMapFeatureKind: String, Sendable { case pointsOfInterest, territories, physicalFeatures }

/// A MapKit camera: where it looks, how far away, tilt and heading.
@_expose(!Cxx)
public struct MunimCamera: Sendable {
  public var latitude: Double
  public var longitude: Double
  /// Metres from the camera to the point at the centre of the map.
  public var distance: Double
  /// Degrees from straight down.
  public var pitch: Double
  /// Degrees clockwise from north.
  public var heading: Double

  public init(latitude: Double, longitude: Double, distance: Double, pitch: Double = 0, heading: Double = 0) {
    self.latitude = latitude
    self.longitude = longitude
    self.distance = distance
    self.pitch = pitch
    self.heading = heading
  }

  public init(center: CLLocationCoordinate2D, distance: Double, pitch: Double = 0, heading: Double = 0) {
    self.init(latitude: center.latitude, longitude: center.longitude, distance: distance, pitch: pitch, heading: heading)
  }
}

/// Where the camera is `t` seconds into a flight.
@_expose(!Cxx)
public struct MunimCameraKeyframe: Sendable {
  public var t: Double
  public var camera: MunimCamera

  public init(t: Double, camera: MunimCamera) {
    self.t = t
    self.camera = camera
  }
}

/// A place on Apple's map that the user tapped.
@_expose(!Cxx)
public struct MunimMapFeature: Sendable {
  public var title: String
  public var coordinate: CLLocationCoordinate2D
  /// `pointOfInterest`, `territory` or `physicalFeature`.
  public var kind: String
  /// The point-of-interest category raw value, such as `MKPOICategoryCafe`.
  public var category: String
  /// For `mapItem(forFeature:)`.
  public var id: String = ""
}

/// What tapping a place on Apple's map shows (iOS 18+).
@_expose(!Cxx)
public enum MunimSelectionAccessory: String, Sendable {
  case none, automatic, callout, calloutCompact, calloutFull, sheet, openInMaps
}

@_expose(!Cxx)
public struct MunimAddress: Sendable {
  public var name: String
  public var street: String
  public var city: String
  public var region: String
  public var postalCode: String
  public var country: String
  public var countryCode: String
  public var formatted: String
}

