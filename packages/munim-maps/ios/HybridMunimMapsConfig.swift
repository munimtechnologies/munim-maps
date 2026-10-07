import Foundation
import NitroModules

/// React Native `configureMunimMaps()` and the engines this build has.
final class HybridMunimMapsConfig: HybridMunimMapsConfigSpec {
  func configure(configuration: NativeMapsConfiguration) throws {
    // Set right away (not on the main queue), so a map created right after
    // sees it; the change notification is posted on the main thread.
    let shared = MunimMapsConfiguration.shared
    // Empty keeps what Info.plist set.
    if !configuration.googleMapsApiKey.isEmpty { shared.googleMapsApiKey = configuration.googleMapsApiKey }
    if !configuration.mapboxAccessToken.isEmpty { shared.mapboxAccessToken = configuration.mapboxAccessToken }
    if !configuration.cesiumIonToken.isEmpty { shared.cesiumIonToken = configuration.cesiumIonToken }
    if !configuration.maplibreStyleUrl.isEmpty { shared.maplibreStyleURL = configuration.maplibreStyleUrl }
    if !configuration.mapboxStyleUrl.isEmpty { shared.mapboxStyleURL = configuration.mapboxStyleUrl }
  }

  func availableProviders() throws -> String {
    MunimMapEngines.available.map(\.rawValue).joined(separator: ",")
  }

  func installedProviders() throws -> String {
    MunimMapEngines.installed.map(\.rawValue).joined(separator: ",")
  }

  /// Shared by every config object: engine-level events go to the last listener set.
  private static var eventListener: ((String, String, String) -> Void)?

  func providerCommand(provider: String, command: String, argsJson: String) throws -> Promise<String> {
    let promise = Promise<String>()
    guard let engine = MunimMapProvider(rawValue: provider) else {
      promise.reject(withError: MunimMapEngineError("Unknown map provider \"\(provider)\""))
      return promise
    }
    let args = MunimProviderJSON.object(argsJson)
    DispatchQueue.main.async {
      MunimMapEngines.providerCommand(
        engine, command: command, arguments: args,
        emit: { name, payload in
          Self.eventListener?(provider, name, MunimProviderJSON.string(payload))
        },
        completion: { result in
          switch result {
          case .success(let value): promise.resolve(withResult: MunimProviderJSON.string(value))
          case .failure(let error): promise.reject(withError: error)
          }
        })
    }
    return promise
  }

  func setProviderEventListener(listener: @escaping (String, String, String) -> Void) throws {
    Self.eventListener = listener
  }
}
