import Foundation

/// Keys and defaults every engine reads: set from JavaScript with
/// `configureMunimMaps`, or from the app's Info.plist (the Expo config
/// plugin writes these keys), or in Swift before the first map.
///
/// Info.plist keys: `MunimMapsGoogleMapsApiKey`, `MBXAccessToken` (Mapbox's
/// own key), `MunimMapsCesiumIonToken`, `MunimMapsMapLibreStyleURL`,
/// `MunimMapsMapboxStyleURL`.
@_expose(!Cxx)
public final class MunimMapsConfiguration {
  public static let shared = MunimMapsConfiguration()
  /// Posted on the main thread after any value changes.
  public static let didChange = Notification.Name("MunimMapsConfigurationDidChange")

  /// OpenFreeMap's Liberty style: OpenStreetMap data, free, no key.
  public static let openFreeMapStyleURL = "https://tiles.openfreemap.org/styles/liberty"

  public var googleMapsApiKey: String { didSet { changed() } }
  public var mapboxAccessToken: String { didSet { changed() } }
  public var cesiumIonToken: String { didSet { changed() } }
  /// Style for MapLibre maps without their own `styleURL`.
  public var maplibreStyleURL: String { didSet { changed() } }
  /// Style for Mapbox maps without their own `styleURL`. Empty is Mapbox Standard.
  public var mapboxStyleURL: String { didSet { changed() } }

  init(bundle: Bundle = .main) {
    func string(_ key: String) -> String {
      (bundle.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
    }
    googleMapsApiKey = string("MunimMapsGoogleMapsApiKey")
    mapboxAccessToken = string("MBXAccessToken")
    cesiumIonToken = string("MunimMapsCesiumIonToken")
    let maplibre = string("MunimMapsMapLibreStyleURL")
    maplibreStyleURL = maplibre.isEmpty ? Self.openFreeMapStyleURL : maplibre
    mapboxStyleURL = string("MunimMapsMapboxStyleURL")
  }

  private func changed() {
    if Thread.isMainThread {
      NotificationCenter.default.post(name: Self.didChange, object: self)
    } else {
      DispatchQueue.main.async { NotificationCenter.default.post(name: Self.didChange, object: self) }
    }
  }
}
