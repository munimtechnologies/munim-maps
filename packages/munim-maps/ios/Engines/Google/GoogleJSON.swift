#if canImport(GoogleMaps)
import CoreLocation
import GoogleMaps
import UIKit

/// Read-only access to decoded JSON (the `google={…}` options and command
/// arguments), with the conversions the Google engine needs.
struct GoogleJSON {
  let raw: Any?

  init(_ raw: Any?) {
    self.raw = raw is NSNull ? nil : raw
  }

  subscript(key: String) -> GoogleJSON {
    GoogleJSON((raw as? [String: Any])?[key])
  }

  var exists: Bool { raw != nil }
  var dictionary: [String: Any]? { raw as? [String: Any] }
  var keys: [String] { dictionary.map { Array($0.keys) } ?? [] }
  var array: [GoogleJSON] { (raw as? [Any])?.map(GoogleJSON.init) ?? [] }

  var string: String? {
    switch raw {
    case let s as String: return s
    case let n as NSNumber: return n.stringValue
    default: return nil
    }
  }

  var double: Double? {
    switch raw {
    case let n as NSNumber: return n.doubleValue
    case let s as String: return Double(s)
    default: return nil
    }
  }

  var bool: Bool? {
    switch raw {
    case let n as NSNumber: return n.boolValue
    case let s as String: return s == "true" ? true : s == "false" ? false : nil
    default: return nil
    }
  }

  func string(_ fallback: String) -> String { string ?? fallback }
  func double(_ fallback: Double) -> Double { double ?? fallback }
  func bool(_ fallback: Bool) -> Bool { bool ?? fallback }

  /// `#RRGGBB(AA)`, `#RGB` or a CSS colour name the core understands.
  var color: UIColor? {
    guard let s = string, !s.isEmpty else { return nil }
    return UIColor(mapModelHex: s) ?? GoogleJSON.namedColor(s)
  }

  /// `{ latitude, longitude }` (or `lat` / `lng`).
  var coordinate: CLLocationCoordinate2D? {
    let lat = self["latitude"].double ?? self["lat"].double
    let lng = self["longitude"].double ?? self["lng"].double
    guard let lat, let lng else { return nil }
    return CLLocationCoordinate2D(latitude: lat, longitude: lng)
  }

  var coordinates: [CLLocationCoordinate2D] { array.compactMap(\.coordinate) }

  /// `{ southwest, northeast }`, or a region `{ latitude, longitude, latitudeDelta, longitudeDelta }`.
  var bounds: GMSCoordinateBounds? {
    if let sw = self["southwest"].coordinate, let ne = self["northeast"].coordinate {
      return GMSCoordinateBounds(coordinate: sw, coordinate: ne)
    }
    if let center = coordinate, let dLat = self["latitudeDelta"].double, let dLng = self["longitudeDelta"].double {
      return GMSCoordinateBounds(
        coordinate: CLLocationCoordinate2D(latitude: center.latitude - dLat / 2, longitude: center.longitude - dLng / 2),
        coordinate: CLLocationCoordinate2D(latitude: center.latitude + dLat / 2, longitude: center.longitude + dLng / 2))
    }
    return nil
  }

  private static func namedColor(_ name: String) -> UIColor? {
    switch name.lowercased() {
    case "black": return .black
    case "white": return .white
    case "red": return .systemRed
    case "green": return .systemGreen
    case "blue": return .systemBlue
    case "yellow": return .systemYellow
    case "orange": return .systemOrange
    case "purple": return .systemPurple
    case "gray", "grey": return .systemGray
    case "clear", "transparent": return .clear
    default: return nil
    }
  }
}

/// JSON-compatible values for events and command results.
enum GoogleOut {
  static func coordinate(_ c: CLLocationCoordinate2D) -> [String: Any] {
    ["latitude": c.latitude, "longitude": c.longitude]
  }

  static func bounds(_ b: GMSCoordinateBounds) -> [String: Any] {
    ["southwest": coordinate(b.southWest), "northeast": coordinate(b.northEast)]
  }

  static func camera(_ p: GMSCameraPosition) -> [String: Any] {
    ["latitude": p.target.latitude, "longitude": p.target.longitude, "zoom": Double(p.zoom),
     "bearing": p.bearing, "tilt": p.viewingAngle]
  }

  static func hex(_ color: UIColor?) -> String {
    guard let color else { return "" }
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    return String(format: "#%02X%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255), Int(a * 255))
  }
}
#endif
