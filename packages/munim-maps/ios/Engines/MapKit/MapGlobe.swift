import MapKit

/// Turns on the globe for MapKit's standard style.
///
/// MapKit's public API shows the globe only for satellite imagery with
/// realistic elevation. Apple Maps shows it for the standard style too,
/// through a switch on VectorKit's map, the object that draws `MKMapView`.
/// That switch is not public API: it may be removed in any iOS release, and
/// App Review may reject apps that use it. Every step is checked, so when the
/// switch is missing nothing happens and the map stays flat.
enum MapGlobe {
  private static let mapLayerKey = "_mapLayer"
  private static let globeKey = "enableGlobe"

  /// Sets the globe switch on `map`. Returns false when it isn't available.
  @discardableResult
  static func set(_ enabled: Bool, on map: MKMapView) -> Bool {
    guard let vectorMap = vectorMap(of: map) else { return false }
    if isEnabled(vectorMap) == enabled { return true }
    vectorMap.setValue(enabled, forKey: globeKey)
    return true
  }

  /// Whether MapKit is drawing `map` as a globe: VectorKit's switch when it
  /// can be read (it is also on for realistic satellite imagery), otherwise
  /// the public styles that show one.
  static func isShowingGlobe(_ map: MKMapView) -> Bool {
    if let vectorMap = vectorMap(of: map), let enabled = isEnabled(vectorMap) { return enabled }
    if #available(iOS 16.0, *) {
      switch map.preferredConfiguration {
      case let hybrid as MKHybridMapConfiguration: return hybrid.elevationStyle == .realistic
      case let imagery as MKImageryMapConfiguration: return imagery.elevationStyle == .realistic
      default: return false
      }
    }
    return map.mapType == .hybridFlyover || map.mapType == .satelliteFlyover
  }

  static func isAvailable(on map: MKMapView) -> Bool {
    vectorMap(of: map) != nil
  }

  private static func vectorMap(of map: MKMapView) -> NSObject? {
    let getter = NSSelectorFromString(mapLayerKey)
    guard map.responds(to: getter),
          let layer = map.perform(getter)?.takeUnretainedValue() as? NSObject,
          layer.responds(to: NSSelectorFromString("setEnableGlobe:"))
    else { return nil }
    return layer
  }

  private static func isEnabled(_ vectorMap: NSObject) -> Bool? {
    guard vectorMap.responds(to: NSSelectorFromString(globeKey)) else { return nil }
    return (vectorMap.value(forKey: globeKey) as? Bool)
  }
}
