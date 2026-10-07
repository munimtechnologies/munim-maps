import { Platform } from 'react-native'
import { NitroModules } from 'react-native-nitro-modules'
import type { MunimMapsConfig } from '../specs/MunimMapsConfig.nitro'
import type { MapProvider } from '../specs/MunimMapView.nitro'
import type { CesiumMapOptions } from './cesium'
import type { GoogleMapOptions } from './google'
import type { MapboxMapOptions } from './mapbox'
import type { MapKitMapOptions } from './mapkit'
import type { MapLibreMapOptions } from './maplibre'

export type {
  CesiumMapOptions,
  GoogleMapOptions,
  MapboxMapOptions,
  MapKitMapOptions,
  MapLibreMapOptions,
  MapProvider,
}

/** Every engine munim-maps knows, in the order the example lists them. */
export const MAP_PROVIDERS: readonly MapProvider[] = [
  'mapkit',
  'google',
  'mapbox',
  'maplibre',
  'cesium',
]

/** Keys and defaults for every map. Set once, before the first map mounts. */
export interface MunimMapsConfiguration {
  /**
   * The engine for maps without a `provider`. Default `mapkit` on iOS; on
   * Android `google` when the Google engine is built in, else `maplibre`.
   */
  defaultProvider?: MapProvider
  /**
   * Google Maps SDK key. On iOS it is handed to `GMSServices` before the
   * first Google map. Android only reads the key from the app's manifest
   * (`com.google.android.geo.API_KEY`), which the Expo config plugin writes.
   */
  googleMapsApiKey?: string
  /** Mapbox public access token (`pk.…`). Or the config plugin's `mapbox.accessToken`. */
  mapboxAccessToken?: string
  /** Cesium ion access token (Cesium World Terrain, imagery, 3D Tiles). */
  cesiumIonToken?: string
  /** Style for MapLibre maps without `styleUrl`. Default OpenFreeMap Liberty. */
  maplibreStyleUrl?: string
  /** Style for Mapbox maps without `styleUrl`. Default Mapbox Standard. */
  mapboxStyleUrl?: string
}

let config: MunimMapsConfig | undefined
let mapboxToken = ''

/** The Mapbox token given to `configureMunimMaps`, for `MapboxServices`. */
export function configuredMapboxToken(): string {
  return mapboxToken
}
let installed: MapProvider[] | undefined
let available: MapProvider[] | undefined
let defaultOverride: MapProvider | undefined

function native(): MunimMapsConfig | undefined {
  if (Platform.OS !== 'ios' && Platform.OS !== 'android') return undefined
  try {
    config ??=
      NitroModules.createHybridObject<MunimMapsConfig>('MunimMapsConfig')
  } catch {
    return undefined
  }
  return config
}

function parse(list: string): MapProvider[] {
  return list
    .split(',')
    .map((p) => p.trim())
    .filter((p): p is MapProvider =>
      (MAP_PROVIDERS as readonly string[]).includes(p)
    )
}

/**
 * Sets API keys and defaults for every map. Call it once at startup, before
 * the first `MunimMapView` mounts. Values left out keep what the app's
 * native configuration set (Info.plist / AndroidManifest, written by the
 * Expo config plugin).
 */
export function configureMunimMaps(configuration: MunimMapsConfiguration) {
  if (configuration.defaultProvider) {
    defaultOverride = configuration.defaultProvider
  }
  if (configuration.mapboxAccessToken) {
    mapboxToken = configuration.mapboxAccessToken
  }
  native()?.configure({
    googleMapsApiKey: configuration.googleMapsApiKey ?? '',
    mapboxAccessToken: configuration.mapboxAccessToken ?? '',
    cesiumIonToken: configuration.cesiumIonToken ?? '',
    maplibreStyleUrl: configuration.maplibreStyleUrl ?? '',
    mapboxStyleUrl: configuration.mapboxStyleUrl ?? '',
  })
}

/**
 * Engines that are built into this app and implemented on this platform.
 * Engines other than MapKit (iOS) and MapLibre (Android) are opt-in at build
 * time: see docs/providers.md.
 */
export function availableProviders(): MapProvider[] {
  available ??= parse(native()?.availableProviders() ?? '')
  return available
}

/** Engines whose SDK is built into this app, implemented yet or not. */
export function installedProviders(): MapProvider[] {
  installed ??= parse(native()?.installedProviders() ?? '')
  return installed
}

export function isProviderAvailable(provider: MapProvider): boolean {
  return availableProviders().includes(provider)
}

/** The engine a `MunimMapView` without `provider` uses. */
export function defaultProvider(): MapProvider {
  if (defaultOverride) return defaultOverride
  if (Platform.OS === 'android') {
    return isProviderAvailable('google') ? 'google' : 'maplibre'
  }
  return 'mapkit'
}

/** Per-provider options on `MunimMapView`, namespaced by engine. */
export interface ProviderOptionProps {
  /** MapKit-only options (`provider="mapkit"`). */
  mapkit?: MapKitMapOptions
  /** Google Maps-only options (`provider="google"`). */
  google?: GoogleMapOptions
  /** Mapbox-only options (`provider="mapbox"`). */
  mapbox?: MapboxMapOptions
  /** MapLibre-only options (`provider="maplibre"`). */
  maplibre?: MapLibreMapOptions
  /** Cesium-only options (`provider="cesium"`). */
  cesium?: CesiumMapOptions
}

/** JSON of the active provider's namespaced options, for the native side. */
export function providerOptionsJson(
  provider: MapProvider,
  props: ProviderOptionProps
): string {
  const options = props[provider]
  return options ? JSON.stringify(options) : '{}'
}

/** An engine-only event (`onProviderEvent`) with its payload decoded. */
export interface MapProviderEvent {
  name: string

  data: any
}

/** Decodes engine JSON; `undefined` for empty or broken text. */
export function parseProviderJson(json: string): unknown {
  if (!json) return undefined
  try {
    return JSON.parse(json)
  } catch {
    return undefined
  }
}

/** What `callMapProvider` needs: a mounted `MunimMapView`'s ref. */
export interface ProviderCallTarget {
  providerCall(method: string, argsJson: string): Promise<string>
}

/**
 * Calls an engine-only method on a mounted map (`ref.current`), such as
 * Mapbox's `queryRenderedFeatures`. Rejects when the map's engine has no
 * such method. Each engine's typed wrappers (`mapboxMap(ref)`) use this.
 */
export async function callMapProvider<T = unknown>(
  map: ProviderCallTarget | null | undefined,
  method: string,
  args: object = {}
): Promise<T> {
  if (!map) throw new Error(`munim-maps: ${method}: the map is not mounted`)
  return parseProviderJson(
    await map.providerCall(method, JSON.stringify(args))
  ) as T
}

/**
 * Calls an engine-level method that needs no map, such as Mapbox's offline
 * downloads (`MapboxOffline`). Rejects when the engine is not built in.
 */
export async function callProvider<T = unknown>(
  provider: MapProvider,
  method: string,
  args: object = {}
): Promise<T> {
  const target = native()
  if (!target) throw new Error('munim-maps: not available on this platform')
  return parseProviderJson(
    await target.providerCall(provider, method, JSON.stringify(args))
  ) as T
}

type ProviderListener = (name: string, data: unknown) => void
const providerListeners = new Map<MapProvider, Set<ProviderListener>>()
let providerListenerInstalled = false

/**
 * Listens to engine-level events (Mapbox's download progress). Returns a
 * function that stops listening.
 */
export function addProviderEventListener(
  provider: MapProvider,
  listener: ProviderListener
): () => void {
  const target = native()
  if (target && !providerListenerInstalled) {
    providerListenerInstalled = true
    target.setProviderEventListener((from, name, json) => {
      const set = providerListeners.get(from as MapProvider)
      if (!set || set.size === 0) return
      const data = parseProviderJson(json)
      for (const l of [...set]) l(name, data)
    })
  }
  let set = providerListeners.get(provider)
  if (!set) {
    set = new Set()
    providerListeners.set(provider, set)
  }
  const listeners = set
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}
