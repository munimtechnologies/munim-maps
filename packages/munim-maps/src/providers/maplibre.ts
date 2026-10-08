/**
 * Options only the MapLibre engine reads (`provider="maplibre"`), passed as
 * `maplibre={{ … }}` on `MunimMapView`, and typed wrappers for its commands
 * (`maplibreCommands(ref)`) and events (`onProviderEvent`).
 *
 * MapLibre Native draws any MapLibre style: the default is OpenFreeMap's
 * Liberty style (OpenStreetMap data, free, no key). Everything in the
 * MapLibre style spec is reachable: whole styles (`styleUrl`, `styleJson`),
 * or sources and layers added on top (`sources`, `layers`), with
 * expressions, filters, feature state, images and light, written exactly as
 * in a style JSON. See docs/providers.md for the full checklist.
 *
 * Two renderers draw the `maplibre` provider: MapLibre Native (the SDK) and
 * MapLibre GL JS 5 in a WebView, which adds what Native does not have: the
 * globe, 3D terrain, sky and atmosphere. `renderer: 'auto'` (default) uses
 * Native unless the map asks for one of those (`resolveMapLibreRenderer`).
 */

/** A value or an expression from the MapLibre style spec. */
export type StyleValue = unknown

/** OpenFreeMap styles (no key), MapLibre's demo tiles, or keyed hosts. */
export type MapLibreStylePreset =
  | 'liberty'
  | 'bright'
  | 'positron'
  | 'dark'
  | 'fiord'
  | 'demotiles'
  /** MapTiler (needs `apiKey`). */
  | 'maptiler-streets'
  | 'maptiler-outdoor'
  | 'maptiler-satellite'
  | 'maptiler-hybrid'
  | 'maptiler-dataviz'
  /** Stadia Maps (needs `apiKey`). */
  | 'stadia-alidade-smooth'
  | 'stadia-alidade-smooth-dark'
  | 'stadia-outdoors'
  | 'stadia-osm-bright'

/** A style-spec source: `{ type: 'vector', url: 'pmtiles://…' }`, … */
export interface MapLibreSource {
  type: 'vector' | 'raster' | 'raster-dem' | 'geojson' | 'image'
  /** TileJSON URL, `pmtiles://…`, or a GeoJSON / image URL. */
  url?: string
  tiles?: string[]
  tileSize?: number
  minzoom?: number
  maxzoom?: number
  bounds?: [number, number, number, number]
  scheme?: 'xyz' | 'tms'
  attribution?: string
  /** `raster-dem`: `terrarium` or `mapbox`; `vector`: `mvt` or `mlt`. */
  encoding?: 'terrarium' | 'mapbox' | 'mvt' | 'mlt'
  /** `geojson`: a FeatureCollection, Feature, geometry or URL. */
  data?: unknown
  cluster?: boolean
  clusterRadius?: number
  clusterMaxZoom?: number
  lineMetrics?: boolean
  tolerance?: number
  buffer?: number
  /** `image`: corners, top left first, as [longitude, latitude]. */
  coordinates?: [number, number][]
}

/** A style-spec layer, plus where to put it. */
export interface MapLibreLayer {
  'id': string
  'type':
    | 'fill'
    | 'line'
    | 'symbol'
    | 'circle'
    | 'heatmap'
    | 'fill-extrusion'
    | 'raster'
    | 'hillshade'
    | 'color-relief'
    | 'background'
  'source'?: string
  'source-layer'?: string
  'minzoom'?: number
  'maxzoom'?: number
  'filter'?: StyleValue
  'layout'?: Record<string, StyleValue>
  'paint'?: Record<string, StyleValue>
  /** Insert below this layer (default: on top, under munim-maps' markers). */
  'beforeId'?: string
}

export type MapLibreOrnamentPosition =
  'topLeft' | 'topRight' | 'bottomLeft' | 'bottomRight'

export interface MapLibreOrnament {
  visible?: boolean
  position?: MapLibreOrnamentPosition
  /** Points from the corner. */
  margin?: { x: number; y: number }
}

export type MapLibreDebugOption =
  'tileBoundaries' | 'tileInfo' | 'timestamps' | 'collisionBoxes' | 'overdraw'

export interface MapLibreMapOptions {
  /**
   * A preset style. Ignored when `styleUrl` or `styleJson` is set. Default
   * `liberty` (OpenFreeMap, no key).
   */
  style?: MapLibreStylePreset
  /** A whole style as JSON (object or string), instead of a URL. */
  styleJson?: string | Record<string, unknown>
  /** Key for MapTiler or Stadia presets; added to their style URLs. */
  apiKey?: string
  /** Style for `colorScheme="dark"` (and dark system appearance). Default OpenFreeMap Dark. */
  darkStyle?: MapLibreStylePreset | string
  /**
   * `{z}/{x}/{y}` satellite imagery for `mapStyle` `imagery` and `hybrid`
   * (there is no keyless global imagery: use your provider's URL).
   */
  satelliteTilesUrl?: string
  /** Sources to add to the style, by id. */
  sources?: Record<string, MapLibreSource>
  /** Layers to add to the style, in order. */
  layers?: MapLibreLayer[]
  /** Images for `icon-image`, `fill-pattern`…: a URL or `{ uri, sdf }`. */
  images?: Record<string, string | { uri: string; sdf?: boolean }>
  /** The style's light (style-spec `light`). */
  light?: {
    anchor?: 'map' | 'viewport'
    position?: [number, number, number]
    color?: string
    intensity?: number
  }
  /** Style transitions, milliseconds. */
  transition?: { duration?: number; delay?: number }
  /** iOS: fade labels in and out as they collide. Default true. */
  placementTransitions?: boolean
  /** Show labels in this language (`name:<lang>`), falling back to the local name. */
  labelLanguage?: string
  /**
   * Shaded relief from public elevation tiles (AWS Terrain Tiles, Terrarium
   * encoding, keyless), or your own `raster-dem` tiles.
   */
  hillshade?:
    | boolean
    | {
        tiles?: string[]
        encoding?: 'terrarium' | 'mapbox'
        exaggeration?: number
        shadowColor?: string
        highlightColor?: string
        accentColor?: string
        illuminationDirection?: number
        /** Insert below this layer. Default under the first road layer. */
        beforeId?: string
      }
  /** Elevation coloured by height (`color-relief` layer). */
  colorRelief?:
    | boolean
    | {
        tiles?: string[]
        encoding?: 'terrarium' | 'mapbox'
        /** `[elevation, color, elevation, color, …]`. */
        stops?: (number | string)[]
        opacity?: number
        beforeId?: string
      }
  /**
   * Which renderer draws the map. `auto` (default): MapLibre Native, unless
   * the map asks for something only MapLibre GL JS has (the `globe` prop,
   * `projection` other than `mercator`, `terrain`, `sky`); then GL JS.
   * `web` always uses GL JS, `native` always uses MapLibre Native (which
   * reports what it cannot draw through `onError`). See
   * `resolveMapLibreRenderer`.
   */
  renderer?: MapLibreRenderer
  /**
   * The projection: `globe` (GL JS: a globe when zoomed out that turns into
   * Mercator from zoom 10 to 12; the same as the `globe` prop),
   * `vertical-perspective` (always a globe), `mercator`, or a style-spec
   * `projection` (`{ type: … }`, expressions allowed). Anything but
   * `mercator` needs the GL JS renderer (MapLibre Native has no globe).
   */
  projection?:
    'mercator' | 'globe' | 'vertical-perspective' | { type: StyleValue }
  /**
   * 3D terrain (GL JS renderer): `true` for keyless public elevation tiles
   * (AWS Terrain Tiles, Terrarium encoding, zoom 15), or your `raster-dem`
   * tiles, a TileJSON `url`, or a `source` already in the style;
   * `exaggeration` scales heights. `elevation="flat"` turns it off. munim
   * models, paths and zones sit on it.
   */
  terrain?:
    | boolean
    | {
        tiles?: string[]
        url?: string
        /** A `raster-dem` source in the style or `sources`. */
        source?: string
        encoding?: 'terrarium' | 'mapbox'
        tileSize?: number
        maxzoom?: number
        exaggeration?: number
        attribution?: string
      }
  /**
   * Sky and atmosphere (GL JS renderer): `true` for munim-maps' default sky
   * (with the globe's atmosphere when zoomed out), `false` for none, or a
   * style-spec `sky` (`sky-color`, `horizon-color`, `fog-color`,
   * `fog-ground-blend`, `horizon-fog-blend`, `sky-horizon-blend`,
   * `atmosphere-blend`; expressions allowed). The globe and terrain get the
   * default sky unless this is `false`.
   */
  sky?: boolean | Record<string, StyleValue>
  /** GL JS renderer: vertical field of view in degrees (default 36.87). */
  fov?: number
  /** GL JS renderer: label fade duration in milliseconds (default 300). */
  fadeDuration?: number
  /**
   * GL JS renderer: let `maplibreCommands(ref).evaluate({ script })` run
   * JavaScript in the page (with `map`, `maplibregl` and `munim`), so every
   * GL JS API is reachable. Off by default.
   */
  allowEvaluate?: boolean
  ornaments?: {
    compass?: MapLibreOrnament
    scaleBar?: MapLibreOrnament & { metric?: boolean }
    logo?: MapLibreOrnament
    attribution?: MapLibreOrnament
  }
  gestures?: {
    doubleTapZoom?: boolean
    quickZoom?: boolean
    /** iOS. */
    quickZoomReversed?: boolean
    /** iOS: `horizontal`, `vertical` or `default`. */
    panScrollingMode?: 'default' | 'horizontal' | 'vertical'
    /** iOS: degrees within which a rotation snaps to north. */
    snapToNorthTolerance?: number
    /** iOS: `UIScrollView.DecelerationRate` (0.998 normal, 0.99 fast, 0 none). */
    decelerationRate?: number
    /** Rotate and zoom about the centre, not the fingers. */
    anchorToCenter?: boolean
    /** iOS. */
    hapticFeedback?: boolean
    /** Android. */
    flingVelocityAnimation?: boolean
    /** Android. */
    scaleVelocityAnimation?: boolean
    /** Android. */
    rotateVelocityAnimation?: boolean
    /** Android. */
    horizontalScroll?: boolean
    /** Android. */
    disableRotateWhenScaling?: boolean
  }
  camera?: {
    minZoom?: number
    maxZoom?: number
    minPitch?: number
    maxPitch?: number
    /** Degrees of roll about the line of sight. */
    roll?: number
  }
  rendering?: {
    maxFps?: number
    prefetchTiles?: boolean
    /** Android. */
    prefetchZoomDelta?: number
    tileCache?: boolean
    tileLodScale?: number
    /** iOS. */
    tileLodMinRadius?: number
    /** iOS. */
    tileLodPitchThreshold?: number
    /** iOS. */
    tileLodZoomShift?: number
    /** Don't draw tiles under these screen edges (points). */
    frustumOffset?: {
      top?: number
      left?: number
      bottom?: number
      right?: number
    }
    debug?: MapLibreDebugOption[]
    /** On-screen frame timings. */
    renderingStats?: boolean
  }
  location?: {
    /** Follow the course (direction of travel) when tracking with heading. */
    course?: boolean
    /** Android render mode. */
    renderMode?: 'normal' | 'compass' | 'gps'
    puckColor?: string
    accuracyColor?: string
    /** Android. */
    pulse?: boolean
    /** Android. */
    pulseColor?: string
    /** iOS. */
    showsHeading?: boolean
    /** iOS: where the user sits on screen while tracking. */
    verticalAlignment?: 'center' | 'top' | 'bottom'
  }
  /** Android: draw CJK glyphs with this local font instead of downloading them. */
  localIdeographFontFamily?: string
  /** Android: map pixel ratio (sharper or cheaper raster tiles). */
  pixelRatio?: number
  /** Android: colour shown before the style loads. */
  foregroundLoadColor?: string
  /**
   * Nominatim server for `addressForCoordinate`. Default the public
   * `https://nominatim.openstreetmap.org` (light use only: one request a
   * second); use your own or a hosted one in production.
   */
  nominatimUrl?: string
  /** Headers added to every MapLibre request (tiles, styles, glyphs). */
  httpHeaders?: Record<string, string>
  /** `error`, `warning`, `info`, `debug`, `verbose` or `none`. */
  logLevel?: 'none' | 'error' | 'warning' | 'info' | 'debug' | 'verbose'
}

export type MapLibreRenderer = 'auto' | 'native' | 'web'

/** What GL JS has and MapLibre Native does not, as the options and props ask for it. */
export type MapLibreWebFeature = 'globe' | 'projection' | 'terrain' | 'sky'

/**
 * The renderer `maplibre={{ renderer }}` resolves to, and why. `auto` uses
 * MapLibre GL JS when the map asks for the globe (`globe` prop or
 * `projection` other than `mercator`), 3D terrain (`terrain`) or a sky
 * (`sky`), and MapLibre Native otherwise. A style URL's own `projection`,
 * `terrain` or `sky` cannot be seen from here: use `renderer: 'web'` for
 * such styles (a `styleJson` with them is detected).
 */
export function resolveMapLibreRenderer(
  options: MapLibreMapOptions | undefined,
  props: { globe?: boolean } = {}
): { renderer: 'native' | 'web'; reasons: MapLibreWebFeature[] } {
  const reasons: MapLibreWebFeature[] = []
  const o = options ?? {}
  if (props.globe) reasons.push('globe')
  if (o.projection && o.projection !== 'mercator') reasons.push('projection')
  if (o.terrain) reasons.push('terrain')
  if (o.sky) reasons.push('sky')
  const style =
    typeof o.styleJson === 'string'
      ? safeParse(o.styleJson)
      : (o.styleJson as Record<string, unknown> | undefined)
  if (style) {
    const projection = style.projection as { type?: unknown } | undefined
    if (projection && projection.type !== 'mercator') reasons.push('projection')
    if (style.terrain) reasons.push('terrain')
    if (style.sky) reasons.push('sky')
  }
  const wanted = o.renderer ?? 'auto'
  if (wanted === 'web') return { renderer: 'web', reasons }
  if (wanted === 'native') return { renderer: 'native', reasons }
  return { renderer: reasons.length ? 'web' : 'native', reasons }
}

function safeParse(text: string): Record<string, unknown> | undefined {
  try {
    return JSON.parse(text)
  } catch {
    return undefined
  }
}

// MARK: Commands

/** A GeoJSON Feature as MapLibre returns it. */
export interface MapLibreFeature {
  type: 'Feature'
  id?: string | number
  geometry: { type: string; coordinates: unknown }
  properties: Record<string, unknown>
}

export interface MapLibreOfflinePack {
  id: string
  name: string
  metadata: Record<string, unknown>
  state: 'inactive' | 'active' | 'complete' | 'invalid' | 'unknown'
  completedResources: number
  expectedResources: number
  completedTiles: number
  completedBytes: number
  /** Whether `expectedResources` is exact (the download knows its size). */
  isComplete: boolean
}

export interface MapLibreSnapshotOptions {
  width: number
  height: number
  styleUrl?: string
  camera?: {
    latitude: number
    longitude: number
    zoom?: number
    distance?: number
    pitch?: number
    heading?: number
  }
  showsLogo?: boolean
}

interface CommandTarget {
  providerCommand(command: string, argsJson: string): Promise<string>
}

async function run<T>(
  target: CommandTarget | null | undefined,
  command: string,
  args: object = {}
): Promise<T> {
  if (!target) throw new Error('The map is not mounted')
  const json = await target.providerCommand(command, JSON.stringify(args))
  return (json ? JSON.parse(json) : null) as T
}

/**
 * Typed MapLibre commands for a `MunimMapView` ref with
 * `provider="maplibre"`:
 *
 * ```ts
 * const maplibre = maplibreCommands(ref.current)
 * const features = await maplibre.queryRenderedFeatures({ point: { x, y }, layers: ['poi'] })
 * ```
 */
export function maplibreCommands(target: CommandTarget | null | undefined) {
  return {
    // Queries
    queryRenderedFeatures: (args: {
      point?: { x: number; y: number }
      box?: { x: number; y: number; width: number; height: number }
      layers?: string[]
      filter?: StyleValue
    }) => run<MapLibreFeature[]>(target, 'queryRenderedFeatures', args),
    querySourceFeatures: (args: {
      source: string
      sourceLayers?: string[]
      filter?: StyleValue
    }) => run<MapLibreFeature[]>(target, 'querySourceFeatures', args),
    getClusterLeaves: (args: {
      source: string
      clusterId: number
      limit?: number
      offset?: number
    }) => run<MapLibreFeature[]>(target, 'getClusterLeaves', args),
    getClusterChildren: (args: { source: string; clusterId: number }) =>
      run<MapLibreFeature[]>(target, 'getClusterChildren', args),
    getClusterExpansionZoom: (args: { source: string; clusterId: number }) =>
      run<number>(target, 'getClusterExpansionZoom', args),
    metersPerPoint: (latitude: number) =>
      run<number>(target, 'metersPerPoint', { latitude }),

    // Runtime styling
    getStyle: () =>
      run<{ layers: string[]; sources: string[]; json?: string }>(
        target,
        'getStyle'
      ),
    reloadStyle: () => run<null>(target, 'reloadStyle'),
    addSource: (id: string, source: MapLibreSource) =>
      run<null>(target, 'addSource', { id, source }),
    removeSource: (id: string) => run<boolean>(target, 'removeSource', { id }),
    setGeoJson: (source: string, data: unknown) =>
      run<null>(target, 'setGeoJson', { source, data }),
    addLayer: (layer: MapLibreLayer) => run<null>(target, 'addLayer', layer),
    removeLayer: (id: string) => run<boolean>(target, 'removeLayer', { id }),
    moveLayer: (id: string, beforeId?: string) =>
      run<null>(target, 'moveLayer', { id, beforeId }),
    setPaintProperty: (layer: string, name: string, value: StyleValue) =>
      run<null>(target, 'setPaintProperty', { layer, name, value }),
    setLayoutProperty: (layer: string, name: string, value: StyleValue) =>
      run<null>(target, 'setLayoutProperty', { layer, name, value }),
    setFilter: (layer: string, filter: StyleValue | null) =>
      run<null>(target, 'setFilter', { layer, filter }),
    setLayerZoomRange: (layer: string, minzoom: number, maxzoom: number) =>
      run<null>(target, 'setLayerZoomRange', { layer, minzoom, maxzoom }),
    addImage: (name: string, uri: string, sdf = false) =>
      run<null>(target, 'addImage', { name, uri, sdf }),
    removeImage: (name: string) => run<null>(target, 'removeImage', { name }),
    setLight: (light: MapLibreMapOptions['light']) =>
      run<null>(target, 'setLight', { light }),
    setFeatureState: (args: {
      source: string
      sourceLayer?: string
      id: string | number
      state: Record<string, unknown>
    }) => run<null>(target, 'setFeatureState', args),
    getFeatureState: (args: {
      source: string
      sourceLayer?: string
      id: string | number
    }) => run<Record<string, unknown>>(target, 'getFeatureState', args),
    removeFeatureState: (args: {
      source: string
      sourceLayer?: string
      id?: string | number
      key?: string
    }) => run<null>(target, 'removeFeatureState', args),

    // Camera
    flyTo: (args: {
      camera: {
        latitude: number
        longitude: number
        distance: number
        pitch?: number
        heading?: number
      }
      durationMs?: number
    }) => run<null>(target, 'flyTo', args),
    resetNorth: () => run<null>(target, 'resetNorth'),
    resetPosition: () => run<null>(target, 'resetPosition'),

    // Snapshots
    /** An offscreen snapshot (any style, camera, size); resolves with a PNG path. */
    snapshot: (options: MapLibreSnapshotOptions) =>
      run<string>(target, 'snapshot', options),

    // Offline
    /**
     * Downloads a region for offline use: tiles from `minZoom` to `maxZoom`
     * in `bounds` (or around `geometry`), with the map's style unless
     * `styleUrl` is set. Progress arrives as `offlineProgress` events.
     */
    offlineCreatePack: (args: {
      name: string
      bounds?: { south: number; west: number; north: number; east: number }
      geometry?: unknown
      minZoom: number
      maxZoom: number
      styleUrl?: string
      includeIdeographs?: boolean
      metadata?: Record<string, unknown>
    }) => run<MapLibreOfflinePack>(target, 'offlineCreatePack', args),
    offlineListPacks: () =>
      run<MapLibreOfflinePack[]>(target, 'offlineListPacks'),
    offlineResumePack: (id: string) =>
      run<null>(target, 'offlineResumePack', { id }),
    offlineSuspendPack: (id: string) =>
      run<null>(target, 'offlineSuspendPack', { id }),
    offlineDeletePack: (id: string) =>
      run<null>(target, 'offlineDeletePack', { id }),
    offlineInvalidatePack: (id: string) =>
      run<null>(target, 'offlineInvalidatePack', { id }),
    offlineSetAmbientCacheSize: (bytes: number) =>
      run<null>(target, 'offlineSetAmbientCacheSize', { bytes }),
    offlineClearAmbientCache: () =>
      run<null>(target, 'offlineClearAmbientCache'),
    offlineInvalidateAmbientCache: () =>
      run<null>(target, 'offlineInvalidateAmbientCache'),
    offlineResetDatabase: () => run<null>(target, 'offlineResetDatabase'),
    /** Merges another MapLibre offline database file into this app's. */
    offlineMergeDatabase: (path: string) =>
      run<MapLibreOfflinePack[]>(target, 'offlineMergeDatabase', { path }),

    // Network
    /** Android: tell MapLibre whether it is online (null: let it detect). */
    setConnected: (connected: boolean | null) =>
      run<null>(target, 'setConnected', { connected }),

    // GL JS renderer only
    /** Which renderer draws the map, and the GL JS and three.js versions. */
    getRenderer: () =>
      run<{ renderer: 'web'; maplibre: string; three: string }>(
        target,
        'getRenderer'
      ),
    setProjection: (projection: MapLibreMapOptions['projection']) =>
      run<null>(target, 'setProjection', { projection }),
    getProjection: () => run<{ type: unknown }>(target, 'getProjection'),
    /** Whether the map is drawn as a globe now (false past zoom 12). */
    isGlobe: () => run<boolean>(target, 'isGlobe'),
    setTerrain: (terrain: MapLibreMapOptions['terrain'] | null) =>
      run<null>(target, 'setTerrain', { terrain }),
    getTerrain: () =>
      run<{ source: string; exaggeration?: number } | null>(
        target,
        'getTerrain'
      ),
    /** Drawn ground height (metres × exaggeration) where terrain tiles are loaded; null without terrain. */
    queryTerrainElevation: (coordinate: {
      latitude: number
      longitude: number
    }) => run<number | null>(target, 'queryTerrainElevation', { coordinate }),
    setSky: (sky: Record<string, StyleValue> | null) =>
      run<null>(target, 'setSky', { sky }),
    getSky: () => run<Record<string, StyleValue> | null>(target, 'getSky'),
    /** GL JS `easeTo` / `jumpTo` options (center, zoom, bearing, pitch, roll, padding, duration). */
    easeTo: (options: Record<string, unknown>) =>
      run<null>(target, 'easeTo', options),
    jumpTo: (options: Record<string, unknown>) =>
      run<null>(target, 'jumpTo', options),
    /** Runs JavaScript in the page (needs `maplibre={{ allowEvaluate: true }}`); resolves with its JSON result. */
    evaluate: <T = unknown>(script: string) =>
      run<T>(target, 'evaluate', { script }),
  }
}

export type MapLibreCommands = ReturnType<typeof maplibreCommands>

/** Names of `onProviderEvent` events the MapLibre engine sends. */
export type MapLibreEventName =
  | 'styleLoaded'
  | 'mapLoadFailed'
  | 'cameraMoveStarted'
  | 'idle'
  | 'renderedMap'
  | 'sourceChanged'
  | 'styleImageMissing'
  | 'renderError'
  | 'offlineProgress'
  | 'offlineError'
  /** GL JS renderer: once, with `{ renderer: 'web', maplibre }`. */
  | 'renderer'
  /** GL JS renderer: the projection changed (globe <-> Mercator). */
  | 'projectionTransition'
