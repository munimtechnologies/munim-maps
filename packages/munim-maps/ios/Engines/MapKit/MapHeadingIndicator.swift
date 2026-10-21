import MapKit

/// Shows the heading cone on the user location dot without following the
/// user, like Apple Maps.
///
/// MapKit's public API only shows the cone in `.followWithHeading`, which also
/// turns and moves the map. Apple Maps keeps it on through switches on
/// `MKMapView` that are not public API: they may be removed in any iOS
/// release, and App Review may reject apps that use them. Every step is
/// checked, so when the switches are missing nothing happens and the dot
/// shows no cone, as before.
enum MapHeadingIndicator {
  /// Apple Maps' switch. MapKit ignores it on devices it decides have no
  /// always-on compass.
  private static let alwaysSetter = "_setAlwaysShowHeadingIndicatorIfSupported:"
  private static let alwaysGetter = "_alwaysShowHeadingIndicator"
  /// The switch `.followWithHeading` uses. No device check: it starts heading
  /// updates and passes the heading to the dot.
  private static let showSetter = "_setShowHeadingIndicator:"

  private typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
  private typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void

  /// Turns the cone on or off on `map`. Returns false when neither switch is
  /// available.
  @discardableResult
  static func set(_ enabled: Bool, on map: MKMapView) -> Bool {
    if enabled, call(alwaysSetter, true, on: map), read(alwaysGetter, on: map) == true { return true }
    if !enabled { call(alwaysSetter, false, on: map) }
    return call(showSetter, enabled, on: map)
  }

  @discardableResult
  private static func call(_ name: String, _ value: Bool, on map: MKMapView) -> Bool {
    let selector = NSSelectorFromString(name)
    guard map.responds(to: selector), let imp = map.method(for: selector) else { return false }
    unsafeBitCast(imp, to: Setter.self)(map, selector, value)
    return true
  }

  private static func read(_ name: String, on map: MKMapView) -> Bool? {
    let selector = NSSelectorFromString(name)
    guard map.responds(to: selector), let imp = map.method(for: selector) else { return nil }
    return unsafeBitCast(imp, to: Getter.self)(map, selector)
  }
}
