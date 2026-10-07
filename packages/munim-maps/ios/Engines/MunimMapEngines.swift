import UIKit

/// How the registry makes one engine. Each engine folder
/// (`ios/Engines/<Name>/`) defines one, compiled only when its SDK is.
protocol MunimMapEngineFactory {
  /// False while the engine is a stub: it is built in, but draws a
  /// placeholder. Flip it once the engine draws a map.
  static var isImplemented: Bool { get }
  static func make() -> MunimMapEngine
  /// Engine-level methods that need no map (Mapbox's offline downloads).
  /// `emit` sends an event to JavaScript (`setProviderEventListener`).
  static func providerCall(
    _ method: String, args: [String: Any], emit: @escaping (String, Any) -> Void,
    completion: @escaping (Result<Any, Error>) -> Void)
}

extension MunimMapEngineFactory {
  static func providerCall(
    _ method: String, args: [String: Any], emit: @escaping (String, Any) -> Void,
    completion: @escaping (Result<Any, Error>) -> Void
  ) {
    completion(.failure(MunimMapEngineError("This engine has no method \"\(method)\"")))
  }
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

  /// Calls an engine-level method (no map needed) on `provider`'s engine.
  public static func providerCall(
    _ provider: MunimMapProvider, method: String, args: [String: Any],
    emit: @escaping (String, Any) -> Void,
    completion: @escaping (Result<Any, Error>) -> Void
  ) {
    guard let factory = factory(for: provider) else {
      completion(.failure(MunimMapEngineError("\(provider.displayName) is not built into this app")))
      return
    }
    factory.providerCall(method, args: args, emit: emit, completion: completion)
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

/// JSON for engine-only methods and events (`providerCall`, `onProviderEvent`).
@_expose(!Cxx)
public enum MunimProviderJSON {
  /// The JSON object in `json`, or an empty one.
  public static func object(_ json: String) -> [String: Any] {
    guard let data = json.data(using: .utf8), !data.isEmpty else { return [:] }
    return ((try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? [String: Any]) ?? [:]
  }

  /// `value` as JSON text; `null` when it cannot be written.
  public static func string(_ value: Any) -> String {
    let clean = sanitize(value)
    guard let data = try? JSONSerialization.data(withJSONObject: clean, options: [.fragmentsAllowed]) else {
      return "null"
    }
    return String(decoding: data, as: UTF8.self)
  }

  /// Makes a value JSONSerialization accepts (non-finite numbers become null).
  public static func sanitize(_ value: Any) -> Any {
    switch value {
    case let dictionary as [String: Any]: return dictionary.mapValues(sanitize)
    case let array as [Any]: return array.map(sanitize)
    case let number as NSNumber:
      if CFGetTypeID(number) == CFBooleanGetTypeID() { return number }
      return number.doubleValue.isFinite ? number : NSNull()
    case let double as Double: return double.isFinite ? double : NSNull()
    case is String, is NSNull: return value
    default:
      let mirror = Mirror(reflecting: value)
      if mirror.displayStyle == .optional {
        return mirror.children.first.map { sanitize($0.value) } ?? NSNull()
      }
      return String(describing: value)
    }
  }
}
