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
}
