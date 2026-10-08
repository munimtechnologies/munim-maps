import { Platform } from 'react-native'
import { NitroModules } from 'react-native-nitro-modules'
import type { MunimMapsConfig } from '../specs/MunimMapsConfig.nitro'
import type { MapProvider, ProviderEvent } from '../specs/MunimMapView.nitro'
import type { CesiumMapOptions } from './cesium'
import type { GoogleMapOptions } from './google'
import type { MapboxMapOptions } from './mapbox'
import type { MapKitMapOptions } from './mapkit'
import { resolveMapLibreRenderer, type MapLibreMapOptions } from './maplibre'

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
/**
 * Who draws `models`: `native` = the engine itself (Mapbox's model layer,
 * Cesium's glTF entities, Google's photorealistic 3D map on Android), so
 * they are lit, shadowed and hidden by the map's own buildings and terrain;
 * `overlay` = munim-maps' 3D layer (SceneKit on iOS, Filament on Android)
 * over the map; `auto` (default) = native where the engine can draw models
 * (Mapbox, Cesium, Google 3D) and the overlay elsewhere (MapKit, MapLibre,
 * the Google 2D map). Whatever an engine cannot draw natively (avatars,
 * labels, stems, effects, occluders, USDZ files) stays on the overlay,
 * except on Cesium, which draws avatars, labels, zones and paths as
 * entities too.
 */
export type ModelRendering = 'auto' | 'native' | 'overlay'

export interface ProviderOptionProps {
  /**
   * Who draws `models` (`auto` by default): the engine itself or munim-maps'
   * 3D layer. See `ModelRendering`. The per-engine `google.modelRendering`,
   * `mapbox.modelRendering` and `cesium.modelRendering` are aliases; this
   * prop wins when both are set.
   */
  modelRendering?: ModelRendering
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

/**
 * JSON of the active provider's namespaced options, for the native side.
 * MapLibre's `renderer` arrives resolved (`native` or `web`, see
 * `resolveMapLibreRenderer`), so the native side picks MapLibre Native or
 * GL JS without knowing every prop.
 */
export function providerOptionsJson(
  provider: MapProvider,
  props: ProviderOptionProps & { globe?: boolean }
): string {
  let options = props[provider] as Record<string, unknown> | undefined
  if (provider === 'maplibre') {
    const resolved = resolveMapLibreRenderer(props.maplibre, props)
    options = { ...options, renderer: resolved.renderer }
  }
  // The shared `modelRendering` reaches the engine with its own options.
  if (props.modelRendering) {
    return JSON.stringify({ ...options, modelRendering: props.modelRendering })
  }
  return options ? JSON.stringify(options) : '{}'
}

/**
 * An event only one engine has (`onProviderEvent`): which engine, the
 * event's name and its data (parsed from JSON). Engines document their
 * events; Google's are typed as `GoogleMapEvent`.
 */
export interface MapProviderEvent<Data = any> {
  provider: MapProvider
  name: string
  data: Data
}

/** Parses a native `ProviderEvent`. */
export function parseProviderEvent(event: ProviderEvent): MapProviderEvent {
  let data: unknown = null
  try {
    data = JSON.parse(event.json)
  } catch {
    data = event.json
  }
  return { provider: event.provider as MapProvider, name: event.name, data }
}

/** Anything with `MunimMapView`'s `providerCommand` method (its ref). */
export interface ProviderCommandTarget {
  providerCommand(command: string, argsJson: string): Promise<string>
}

/**
 * Calls a method only the active engine has (`ref.providerCommand` with
 * JSON in and out). Rejects when the engine does not know the command.
 */
export async function providerCommand<Result = unknown>(
  map: ProviderCommandTarget,
  command: string,
  args: object = {}
): Promise<Result> {
  const json = await map.providerCommand(command, JSON.stringify(args))
  return JSON.parse(json || 'null') as Result
}

/** Decodes engine JSON; `undefined` for empty or broken text. */
function parseJson(json: string): unknown {
  if (!json) return undefined
  try {
    return JSON.parse(json)
  } catch {
    return undefined
  }
}

/**
 * Runs an engine-level command that needs no map, such as Mapbox's offline
 * downloads (`MapboxOffline`). Rejects when the engine is not built in.
 */
export async function callProvider<T = unknown>(
  provider: MapProvider,
  command: string,
  args: object = {}
): Promise<T> {
  const target = native()
  if (!target) throw new Error('munim-maps: not available on this platform')
  return parseJson(
    await target.providerCommand(provider, command, JSON.stringify(args))
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
      const data = parseJson(json)
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
