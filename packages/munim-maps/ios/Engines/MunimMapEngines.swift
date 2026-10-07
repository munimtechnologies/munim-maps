import UIKit

/// How the registry makes one engine. Each engine folder
/// (`ios/Engines/<Name>/`) defines one, compiled only when its SDK is.
protocol MunimMapEngineFactory {
  /// False while the engine is a stub: it is built in, but draws a
  /// placeholder. Flip it once the engine draws a map.
  static var isImplemented: Bool { get }
  static func make() -> MunimMapEngine
}

/// The engines built into this app, and making them.
///
/// MapKit is always built in. The others compile only when their SDK is in
/// the app: the `NitroMunimMaps/Google`, `/Mapbox`, `/MapLibre` and `/Cesium`
/// subspecs add the SDK, and each engine's folder is wrapped in
/// `#if canImport(<SDK>)` (Cesium: `#if MUNIM_MAPS_CESIUM`), so the default
/// install pulls in no extra SDKs.
@_expose(!Cxx)
public enum MunimMapEngines {
  private static func factory(for provider: MunimMapProvider) -> MunimMapEngineFactory.Type? {
    switch provider {
    case .mapkit:
      return MapKitMapEngineFactory.self
    case .google:
      #if canImport(GoogleMaps)
      return GoogleMapEngineFactory.self
      #else
      return nil
      #endif
    case .mapbox:
      #if canImport(MapboxMaps)
      return MapboxMapEngineFactory.self
      #else
      return nil
      #endif
    case .maplibre:
      #if canImport(MapLibre)
      return MapLibreMapEngineFactory.self
      #else
      return nil
      #endif
    case .cesium:
      #if MUNIM_MAPS_CESIUM
      return CesiumMapEngineFactory.self
      #else
      return nil
      #endif
    }
  }

  /// Engines whose SDK is built in, implemented yet or not.
  public static var installed: [MunimMapProvider] {
    MunimMapProvider.allCases.filter { factory(for: $0) != nil }
  }

  /// Engines that are built in and draw a map.
  public static var available: [MunimMapProvider] {
    MunimMapProvider.allCases.filter { factory(for: $0)?.isImplemented == true }
  }

  /// A new engine for `provider`, or a placeholder saying why there is none.
  public static func make(_ provider: MunimMapProvider) -> MunimMapEngine {
    guard let factory = factory(for: provider) else {
      return UnavailableMapEngine(
        provider: provider,
        reason: "\(provider.displayName) is not built into this app. Add the \(provider.subspec) subspec "
          + "(or the Expo config plugin's providers option) and rebuild.")
    }
    return factory.make()
  }
}
