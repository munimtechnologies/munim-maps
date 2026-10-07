import type { HybridObject } from 'react-native-nitro-modules'

/**
 * Keys and defaults shared by every map, as the native side receives them.
 * Every field is required so no optional crosses the bridge
 * (margelo/nitro#1319); empty strings keep what the app's native config
 * (Info.plist / AndroidManifest, written by the Expo config plugin) set.
 */
export interface NativeMapsConfiguration {
  /** Google Maps SDK key. iOS only at runtime; Android reads the manifest. */
  googleMapsApiKey: string
  /** Mapbox public access token (`pk.…`). */
  mapboxAccessToken: string
  /** Cesium ion access token, for Cesium World Terrain, imagery and 3D Tiles. */
  cesiumIonToken: string
  /** Default MapLibre style URL. Empty for OpenFreeMap's Liberty style. */
  maplibreStyleUrl: string
  /** Default Mapbox style URL. Empty for Mapbox Standard. */
  mapboxStyleUrl: string
}

/** munim-maps' global configuration and which engines this build has. */
export interface MunimMapsConfig extends HybridObject<{
  ios: 'swift'
  android: 'kotlin'
}> {
  configure(configuration: NativeMapsConfiguration): void
  /**
   * The engines compiled into this app and implemented, comma-separated
   * (`mapkit,maplibre`). A string, not an array, to avoid a Swift bridging
   * issue with string arrays in Nitro 0.36.
   */
  availableProviders(): string
  /** The engines compiled into this app, implemented or not, comma-separated. */
  installedProviders(): string
  /**
   * An engine-level method that needs no map (Mapbox's offline downloads):
   * the provider, the method's name and JSON arguments in, JSON out. Rejects
   * when the engine is not built in or has no such method.
   */
  providerCall(
    provider: string,
    method: string,
    argsJson: string
  ): Promise<string>
  /**
   * Receives engine-level events (download progress): provider, event name
   * and JSON payload. One listener; the JavaScript side fans it out.
   */
  setProviderEventListener(
    listener: (provider: string, name: string, json: string) => void
  ): void
}
