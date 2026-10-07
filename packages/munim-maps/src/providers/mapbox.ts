/**
 * The Mapbox engine (`provider="mapbox"`): Mapbox Maps SDK v11 on iOS and
 * Android.
 *
 * - Options only Mapbox has go in `mapbox={{ … }}` on `MunimMapView`
 *   (`MapboxMapOptions`). They are declarative: the engine adds, updates and
 *   removes what changed between renders.
 * - Methods only Mapbox has are on `mapboxMap(ref)` (`MapboxMapMethods`),
 *   on top of `ref.providerCommand`.
 * - Offline downloads need no map: `MapboxOffline`.
 * - Mapbox's map events and featureset taps arrive in `onProviderEvent`
 *   (`MapboxEventName`).
 *
 * Style objects (sources, layers, lights, terrain, atmosphere, expressions)
 * are written exactly as in the Mapbox Style Specification
 * (https://docs.mapbox.com/style-spec/), kebab-case keys and all, and handed
 * to the SDK unchanged, so every layer type, source type, property and
 * expression the SDK supports works on both platforms.
 */
import {
  callProvider,
  providerCommand,
  addProviderEventListener,
  configuredMapboxToken,
} from './index'
import type { ProviderCommandTarget } from './index'

/** A Mapbox style expression, such as `['get', 'height']`. */

export type MapboxExpression = any[]
/** A style-spec value: a constant or an expression. */
export type MapboxValue<T> = T | MapboxExpression
type Json = Record<string, unknown>

/** Mapbox's own styles, for `styleUrl`. */
export const MAPBOX_STYLES = {
  standard: 'mapbox://styles/mapbox/standard',
  standardSatellite: 'mapbox://styles/mapbox/standard-satellite',
  streets: 'mapbox://styles/mapbox/streets-v12',
  outdoors: 'mapbox://styles/mapbox/outdoors-v12',
  light: 'mapbox://styles/mapbox/light-v11',
  dark: 'mapbox://styles/mapbox/dark-v11',
  satellite: 'mapbox://styles/mapbox/satellite-v9',
  satelliteStreets: 'mapbox://styles/mapbox/satellite-streets-v12',
  navigationDay: 'mapbox://styles/mapbox/navigation-day-v1',
  navigationNight: 'mapbox://styles/mapbox/navigation-night-v1',
} as const

/**
 * Mapbox Standard's (and Standard Satellite's) configuration: the `basemap`
 * import's config properties. Unknown keys are passed through, so options
 * Mapbox adds later work too.
 */
export interface MapboxStandardConfig {
  /** Time of day. Default follows `colorScheme` (`night` when dark). */
  'lightPreset'?: 'dawn' | 'day' | 'dusk' | 'night'
  /** `default`, `faded`, `monochrome`, or `custom` with `theme-data`. */
  'theme'?: 'default' | 'faded' | 'monochrome' | 'custom'
  /** A colour lookup table (base64 PNG) for `theme: 'custom'`. */
  'theme-data'?: string
  'font'?: string
  'show3dObjects'?: boolean
  'show3dBuildings'?: boolean
  'show3dTrees'?: boolean
  'show3dLandmarks'?: boolean
  'show3dFacades'?: boolean
  'showPointOfInterestLabels'?: boolean
  'showTransitLabels'?: boolean
  'showPlaceLabels'?: boolean
  'showRoadLabels'?: boolean
  'showPedestrianRoads'?: boolean
  'showLandmarkIcons'?: boolean
  'showLandmarkIconLabels'?: boolean
  'showAdminBoundaries'?: boolean
  /** Standard Satellite. */
  'showRoadsAndTransit'?: boolean
  'densityPointOfInterestLabels'?: number
  'colorModePointOfInterestLabels'?: 'default' | 'single'
  'backgroundPointOfInterestLabels'?: 'none' | 'circle'
  [config: string]: unknown
}

/** A style-spec source (`{ type: 'geojson', data, cluster: true }`). */
export interface MapboxSource {
  type:
    | 'vector'
    | 'raster'
    | 'raster-dem'
    | 'raster-array'
    | 'geojson'
    | 'image'
    | 'video'
    | 'model'
    | 'batched-model'
  [property: string]: unknown
}

/**
 * Where a runtime layer goes: `slot` (Standard's `bottom`, `middle`, `top`),
 * or above / below another layer, or at an index. Default: on top.
 */
export interface MapboxLayerPosition {
  /** Put the layer under this one. */
  beforeId?: string
  /** Put the layer over this one. */
  aboveId?: string
  /** Index among all layers. */
  index?: number
}

/**
 * A style-spec layer, every type: `fill`, `line`, `symbol`, `circle`,
 * `heatmap`, `fill-extrusion`, `raster`, `raster-particle`, `hillshade`,
 * `background`, `sky`, `model`, `location-indicator`, `slot`, `clip`,
 * `building`. Mapbox Standard's slots go in `slot`.
 */
export interface MapboxLayer extends MapboxLayerPosition {
  'id': string
  'type':
    | 'fill'
    | 'line'
    | 'symbol'
    | 'circle'
    | 'heatmap'
    | 'fill-extrusion'
    | 'raster'
    | 'raster-particle'
    | 'hillshade'
    | 'background'
    | 'sky'
    | 'model'
    | 'location-indicator'
    | 'slot'
    | 'clip'
    | 'building'
  'source'?: string
  'source-layer'?: string
  'slot'?: 'bottom' | 'middle' | 'top' | string
  'filter'?: MapboxExpression
  'minzoom'?: number
  'maxzoom'?: number
  'layout'?: Json
  'paint'?: Json
  [property: string]: unknown
}

/** An image for symbol layers (`icon-image`) and patterns. */
export interface MapboxImage {
  /** `file://`, `http(s)://`, a bundled asset, or `data:image/png;base64,…`. */
  uri: string
  /** Pixels per point of the image. Default the screen's. */
  scale?: number
  /** A signed distance field image, recoloured with `icon-color`. */
  sdf?: boolean
  /** Stretchable areas, in image pixels: `[[from, to], …]`. */
  stretchX?: [number, number][]
  stretchY?: [number, number][]
  /** The area text fits in, `[left, top, right, bottom]` in image pixels. */
  content?: [number, number, number, number]
}

/** A style import added at runtime (`imports`). */
export interface MapboxStyleImport {
  id: string
  /** A style URL. */
  url?: string
  /** Or a whole style. */
  json?: Json | string
  config?: Json
  /** Put it before this import. Default last. */
  beforeId?: string
}

/** A light, as in the style spec's `lights` array. */
export interface MapboxLight {
  id: string
  type: 'ambient' | 'directional' | 'flat'
  properties?: Json
}

/** Raised terrain. */
export interface MapboxTerrain {
  /** A `raster-dem` source id. Default Mapbox Terrain-DEM, added for you. */
  source?: string
  exaggeration?: MapboxValue<number>
  [property: string]: unknown
}

/** The globe's atmosphere and fog (style spec `fog`). */
export interface MapboxAtmosphere {
  'range'?: MapboxValue<[number, number]>
  'color'?: MapboxValue<string>
  'high-color'?: MapboxValue<string>
  'horizon-blend'?: MapboxValue<number>
  'space-color'?: MapboxValue<string>
  'star-intensity'?: MapboxValue<number>
  'vertical-range'?: MapboxValue<[number, number]>
  [property: string]: unknown
}

export type MapboxOrnamentPosition =
  'top-left' | 'top-right' | 'bottom-left' | 'bottom-right'

export interface MapboxOrnament {
  position?: MapboxOrnamentPosition
  /** Points from the corner, `[x, y]`. */
  margins?: [number, number]
  /** `adaptive` shows the compass only while rotated. */
  visibility?: 'adaptive' | 'visible' | 'hidden'
}

/** Mapbox's on-map controls. */
export interface MapboxOrnaments {
  compass?: MapboxOrnament
  scaleBar?: MapboxOrnament & { units?: 'metric' | 'imperial' | 'nautical' }
  /** Mapbox's terms require the logo to stay visible. */
  logo?: Omit<MapboxOrnament, 'visibility'>
  /** Mapbox's terms require attribution to stay reachable. */
  attributionButton?: Omit<MapboxOrnament, 'visibility'> & {
    tintColor?: string
  }
}

/** Mapbox's gesture settings, on top of `zoomEnabled` and friends. */
export interface MapboxGestures {
  panEnabled?: boolean
  pinchEnabled?: boolean
  rotateEnabled?: boolean
  pitchEnabled?: boolean
  pinchZoomEnabled?: boolean
  pinchPanEnabled?: boolean
  simultaneousRotateAndPinchZoomEnabled?: boolean
  doubleTapToZoomInEnabled?: boolean
  doubleTouchToZoomOutEnabled?: boolean
  quickZoomEnabled?: boolean
  panMode?: 'horizontal' | 'vertical' | 'horizontalAndVertical'
  /** 0...1, how quickly a fling slows down (iOS `panDecelerationFactor`). */
  panDecelerationFactor?: number
  /** Zoom and rotate around this point (points) instead of the fingers. */
  focalPoint?: { x: number; y: number }
  /** Android: keep scrolling after a fling. */
  scrollDecelerationEnabled?: boolean
  rotateDecelerationEnabled?: boolean
  pinchToZoomDecelerationEnabled?: boolean
  /** Android: allow two-finger rotation while scaling. */
  increaseRotateThresholdWhenPinchingToZoom?: boolean
}

/** The user location puck (`showsUserLocation`). */
export interface MapboxPuck {
  /** `2d` (default), `3d` (a glTF model), or `none`. */
  type?: '2d' | '3d' | 'none'
  /** Turn the puck with the device (`heading`) or travel (`course`). */
  bearing?: 'heading' | 'course' | 'none'
  /** 2D: images (URIs) and look. */
  topImage?: string
  bearingImage?: string
  shadowImage?: string
  scale?: MapboxValue<number>
  showsAccuracyRing?: boolean
  accuracyRingColor?: string
  accuracyRingBorderColor?: string
  opacity?: number
  /** A pulsing ring around the 2D puck. */
  pulsing?: { enabled?: boolean; color?: string; radius?: number | 'accuracy' }
  /** 3D: a glTF model. */
  modelUri?: string
  modelScale?: MapboxValue<[number, number, number]>
  modelRotation?: MapboxValue<[number, number, number]>
  modelTranslation?: [number, number, number]
  modelOpacity?: number
  modelCastShadows?: boolean
  modelReceiveShadows?: boolean
  modelScaleMode?: 'viewport' | 'map'
  modelEmissiveStrength?: number
  modelElevationReference?: 'sea' | 'ground'
}

/** Keep the camera inside these limits. */
export interface MapboxCameraBounds {
  /** South-west and north-east corners. */
  bounds?: {
    southwest: { latitude: number; longitude: number }
    northeast: { latitude: number; longitude: number }
  }
  minZoom?: number
  maxZoom?: number
  minPitch?: number
  maxPitch?: number
}

/**
 * Report taps or long presses on a featureset (Standard's `poi`,
 * `buildings`, `place-labels`, `landmark-icons`) or a layer as
 * `onProviderEvent` `interaction` events. Optionally set feature state on
 * the tapped feature (`select: { select: true }`) for Standard's highlight.
 */
export interface MapboxInteraction {
  /** Your name for it, echoed in the event. */
  id: string
  type: 'tap' | 'longPress'
  /** A featureset: `{ featuresetId: 'poi', importId: 'basemap' }`. */
  featureset?: { featuresetId: string; importId?: string }
  /** Or a layer of your own. */
  layerId?: string
  /** Only features matching this expression. */
  filter?: MapboxExpression
  /** Feature state to set on the feature that was hit (and clear on the last one). */
  setState?: Json
  /** Stop the tap here (no `onPress`). Default true. */
  consume?: boolean
}

/** Mapbox's map events you can receive in `onProviderEvent`. */
export type MapboxEventName =
  | 'mapLoaded'
  | 'mapIdle'
  | 'mapLoadingError'
  | 'styleLoaded'
  | 'styleDataLoaded'
  | 'styleImageMissing'
  | 'styleImageRemoveUnused'
  | 'sourceDataLoaded'
  | 'sourceAdded'
  | 'sourceRemoved'
  | 'cameraChanged'
  | 'renderFrameStarted'
  | 'renderFrameFinished'
  | 'resourceRequest'

/** Rendering switches. */
export interface MapboxRendering {
  /** Frames per second; default the screen's. */
  preferredFramesPerSecond?: number
  /** Zoom levels to fetch ahead of the camera. */
  prefetchZoomDelta?: number
  /** Tile cache budget in megabytes. */
  tileCacheBudgetMegabytes?: number
  /** `heightOnly` (default), `widthAndHeight` or `none`. */
  constrainMode?: 'none' | 'heightOnly' | 'widthAndHeight'
  viewportMode?: 'default' | 'flippedY'
  northOrientation?: 'upwards' | 'rightwards' | 'downwards' | 'leftwards'
  /** Keep the camera at the map's centre when it resizes. */
  shouldFlyToCenter?: boolean
  /** Duration of style transitions, in milliseconds. */
  transitionDuration?: number
  transitionDelay?: number
  /** Use the camera's ray for the scale of 3D models and fill extrusions. */
  [option: string]: unknown
}

export type MapboxDebugOption =
  | 'tileBorders'
  | 'parseStatus'
  | 'timestamps'
  | 'collision'
  | 'overdraw'
  | 'stencilClip'
  | 'depthBuffer'
  | 'modelBounds'
  | 'terrainWireframe'
  | 'layers2DWireframe'
  | 'layers3DWireframe'
  | 'light'
  | 'camera'
  | 'padding'

/**
 * Options only the Mapbox engine reads, passed as `mapbox={{ … }}` on
 * `MunimMapView`. The style itself is `styleUrl` (`MAPBOX_STYLES`; default
 * Mapbox Standard) or `styleJson`.
 */
export interface MapboxMapOptions {
  // Style

  /** A whole style (object or JSON text) instead of `styleUrl`. */
  styleJson?: Json | string
  /** Mapbox Standard's configuration (the `basemap` import). */
  standard?: MapboxStandardConfig
  /** Shorthand for `standard.lightPreset`. */
  lightPreset?: 'dawn' | 'day' | 'dusk' | 'night'
  /** Config of any style import: `{ [importId]: { [config]: value } }`. */
  importConfig?: Record<string, Json>
  /** Style imports to add (fragments, other styles). */
  imports?: MapboxStyleImport[]
  /**
   * `globe` (Mapbox's default: a globe when zoomed out, flat close in) or
   * `mercator`. Default follows `globe` on `MunimMapView`.
   */
  projection?: 'globe' | 'mercator'
  /** The globe's atmosphere and fog; `false` removes the style's. */
  atmosphere?: MapboxAtmosphere | false
  /**
   * Raised terrain: `true` for Mapbox Terrain-DEM, or the source and
   * exaggeration; `false` removes the style's. Default: on for
   * `mapStyle` `hybrid` / `imagery` with `elevation` `realistic`.
   */
  terrain?: MapboxTerrain | boolean
  /** Shorthand for `terrain.exaggeration` (0 turns terrain off). */
  terrainExaggeration?: number
  /** Replaces the style's lights: one `flat`, or `ambient` + `directional`. */
  lights?: MapboxLight[]
  /** Falling snow (style spec `snow`), experimental in the SDK. */
  snow?: Json | false
  /** Rain (style spec `rain`), experimental in the SDK. */
  rain?: Json | false
  /** The style's colour theme: a lookup table as a base64 PNG. */
  colorTheme?: { data: string } | false
  /** Sources by id. */
  sources?: Record<string, MapboxSource>
  /** Layers, in order (later ones on top unless positioned). */
  layers?: MapboxLayer[]
  /** Images by id, for `icon-image`, patterns and `location-indicator`. */
  images?: Record<string, MapboxImage>
  /** glTF models by id (`model-id` in `model` layers): `{ id: uri }`. */
  models?: Record<string, string>

  /**
   * Who draws `models`. Mapbox can draw glTF / GLB models itself in a
   * `model` layer, lit and shadowed by Mapbox and hidden by its 3D buildings
   * and terrain.
   * - `auto` (default): models that are only a glTF body (no label, stem,
   *   effect, lift or animation) are drawn by Mapbox; the rest by
   *   munim-maps' 3D layer.
   * - `native`: every glTF model is drawn by Mapbox; labels, stems and
   *   effects stay on munim-maps' 3D layer.
   * - `overlay`: everything on munim-maps' 3D layer.
   * USDZ and built-in shapes, avatars, zones and paths are always drawn by
   * munim-maps' 3D layer. Natively drawn models follow `heading`, `motion`,
   * spin, `altitude` (`altitudeReference`), `scale`, `screenSize` and
   * `tint` (a colour override on the model's `paint*` materials);
   * `measureAlignment` covers only the 3D layer's models.
   */
  modelRendering?: 'auto' | 'native' | 'overlay'

  // Camera, gestures, controls

  /** Limits for the camera. */
  cameraBounds?: MapboxCameraBounds
  gestures?: MapboxGestures
  ornaments?: MapboxOrnaments
  puck?: MapboxPuck
  rendering?: MapboxRendering
  debug?: MapboxDebugOption[]

  // Events

  /** Mapbox map events to send to `onProviderEvent` (none by default). */
  events?: MapboxEventName[]
  /** Featureset and layer taps to send as `interaction` events. */
  interactions?: MapboxInteraction[]
}

// --- Methods on a mounted map ---------------------------------------------

export interface MapboxFeature {
  type: 'Feature'
  id?: string | number
  geometry: Json
  properties: Json
}

/** A feature from `queryRenderedFeatures`. */
export interface MapboxQueriedFeature {
  feature: MapboxFeature
  source: string
  sourceLayer?: string
  /** Feature state. */
  state?: Json
  /** Layers it was drawn in. */
  layers?: string[]
  /** For featureset queries: the featureset and its feature id. */
  featureset?: { featuresetId?: string; importId?: string; layerId?: string }
  featureNamespace?: string
}

/** Mapbox's own camera, in zoom levels. */
export interface MapboxCameraOptions {
  center?: { latitude: number; longitude: number }
  zoom?: number
  bearing?: number
  pitch?: number
  /** Points: `{ top, left, bottom, right }`. */
  padding?: { top?: number; left?: number; bottom?: number; right?: number }
  /** Zoom and rotate around this point. */
  anchor?: { x: number; y: number }
}

export interface MapboxCameraState {
  center: { latitude: number; longitude: number }
  zoom: number
  bearing: number
  pitch: number
  padding: { top: number; left: number; bottom: number; right: number }
}

export type MapboxFeatureTarget =
  | { sourceId: string; sourceLayerId?: string; featureId: string }
  | {
      featureset:
        { featuresetId: string; importId?: string } | { layerId: string }
      featureId: string
      featureNamespace?: string
    }

export interface MapboxSnapshotOptions {
  /** Points. Default the map's size. */
  width?: number
  height?: number
  /** Default the map's style. */
  styleUrl?: string
  styleJson?: Json | string
  /** Default the map's camera. */
  camera?: MapboxCameraOptions
  /** Default the screen's. */
  pixelRatio?: number
  showsLogo?: boolean
  showsAttribution?: boolean
}

/** Typed wrappers for the Mapbox engine's methods, on `ref.providerCommand`. */
export interface MapboxMapMethods {
  /** Features drawn at a point, in a box, or (no geometry) on the whole map. */
  queryRenderedFeatures(options?: {
    point?: { x: number; y: number }
    box?: { x1: number; y1: number; x2: number; y2: number }
    layerIds?: string[]
    filter?: MapboxExpression
    featureset?:
      { featuresetId: string; importId?: string } | { layerId: string }
  }): Promise<MapboxQueriedFeature[]>
  /** Features in a source's loaded tiles, drawn or not. */
  querySourceFeatures(options: {
    sourceId: string
    sourceLayerIds?: string[]
    filter?: MapboxExpression
  }): Promise<MapboxQueriedFeature[]>
  /** The zoom at which a GeoJSON cluster breaks apart. */
  getClusterExpansionZoom(options: {
    sourceId: string
    cluster: MapboxFeature
  }): Promise<number>
  getClusterLeaves(options: {
    sourceId: string
    cluster: MapboxFeature
    limit?: number
    offset?: number
  }): Promise<MapboxFeature[]>
  getClusterChildren(options: {
    sourceId: string
    cluster: MapboxFeature
  }): Promise<MapboxFeature[]>
  setFeatureState(target: MapboxFeatureTarget & { state: Json }): Promise<null>
  getFeatureState(target: MapboxFeatureTarget): Promise<Json>
  removeFeatureState(
    target: MapboxFeatureTarget & { stateKey?: string }
  ): Promise<null>
  resetFeatureStates(options: {
    sourceId?: string
    sourceLayerId?: string
    featureset?:
      { featuresetId: string; importId?: string } | { layerId: string }
  }): Promise<null>
  /** Replaces a GeoJSON source's data without re-rendering React. */
  updateGeoJSONSource(options: {
    sourceId: string
    data: Json | string
    dataId?: string
  }): Promise<null>
  /** Partial GeoJSON updates (features need ids). */
  addGeoJSONSourceFeatures(options: {
    sourceId: string
    features: MapboxFeature[]
    dataId?: string
  }): Promise<null>
  updateGeoJSONSourceFeatures(options: {
    sourceId: string
    features: MapboxFeature[]
    dataId?: string
  }): Promise<null>
  removeGeoJSONSourceFeatures(options: {
    sourceId: string
    featureIds: string[]
    dataId?: string
  }): Promise<null>
  setLayerProperties(options: {
    layerId: string
    properties: Json
  }): Promise<null>
  getLayerProperties(options: { layerId: string }): Promise<Json>
  setSourceProperties(options: {
    sourceId: string
    properties: Json
  }): Promise<null>
  getSourceProperties(options: { sourceId: string }): Promise<Json>
  moveLayer(
    options: { layerId: string } & MapboxLayerPosition & { slot?: string }
  ): Promise<null>
  getStyleJson(): Promise<string>
  /** Every layer: `{ id, type }`. */
  getLayers(): Promise<{ id: string; type: string }[]>
  getSources(): Promise<{ id: string; type: string }[]>
  getSlots(): Promise<string[]>
  getStyleImports(): Promise<{ id: string; type: string }[]>
  getStyleImportSchema(options: { importId: string }): Promise<Json>
  getStyleImportConfig(options: { importId: string }): Promise<Json>
  setStyleImportConfig(options: {
    importId: string
    config: Json
  }): Promise<null>
  /** The featuresets the style has (Standard: `poi`, `buildings`, …). */
  getFeaturesets(): Promise<
    { featuresetId?: string; importId?: string; layerId?: string }[]
  >
  /** Mapbox's camera, in zoom levels. */
  getCameraState(): Promise<MapboxCameraState>
  /** Jumps, eases or flies (Mapbox's `flyTo` curve) in zoom levels. */
  setCamera(options: { camera: MapboxCameraOptions }): Promise<null>
  easeTo(options: {
    camera: MapboxCameraOptions
    duration?: number
    curve?: 'linear' | 'easeIn' | 'easeOut' | 'easeInOut'
  }): Promise<boolean>
  flyTo(options: {
    camera: MapboxCameraOptions
    duration?: number
  }): Promise<boolean>
  cancelCameraAnimations(): Promise<null>
  /** The camera that frames these coordinates. */
  cameraForCoordinates(options: {
    coordinates: { latitude: number; longitude: number }[]
    padding?: MapboxCameraOptions['padding']
    bearing?: number
    pitch?: number
    maxZoom?: number
  }): Promise<MapboxCameraOptions>
  /** The visible bounds (`southwest`, `northeast`). */
  getBounds(): Promise<MapboxCameraBounds['bounds']>
  /** Terrain height in metres, when terrain is on and loaded there. */
  getElevation(options: {
    latitude: number
    longitude: number
  }): Promise<number | null>
  /**
   * Viewport: follow the user's puck (`followPuck`), frame coordinates
   * (`overview`), or stop (`idle`). Resolves when the transition ends
   * (true) or is cancelled (false).
   */
  setViewport(options: {
    state: 'followPuck' | 'overview' | 'idle'
    zoom?: number
    pitch?: number
    bearing?: 'heading' | 'course' | number
    padding?: MapboxCameraOptions['padding']
    /** `overview`: what to frame. */
    coordinates?: { latitude: number; longitude: number }[]
    /** Milliseconds; 0 jumps. Default Mapbox's transition. */
    duration?: number
  }): Promise<boolean>
  /** A PNG of a map drawn off screen by Mapbox's `Snapshotter`; its path. */
  snapshot(options?: MapboxSnapshotOptions): Promise<string>
  /**
   * Which `models` Mapbox draws in its model layer (`modelRendering`) and
   * which munim-maps' 3D layer draws, with the model source as Mapbox has it.
   */
  getNativeModels(): Promise<{
    mode: 'auto' | 'native' | 'overlay'
    native: string[]
    overlay: string[]
    installed: boolean
    /** Where each native model is now: `[latitude, longitude, altitude, heading]`. */
    positions?: Record<string, [number, number, number, number]>
    source?: Json
    layers?: string[]
  }>
  /** The camera as a position in space (Mapbox's free camera). */
  getFreeCamera(): Promise<{
    position: { latitude: number; longitude: number; altitude: number }
  }>
  /**
   * Places the camera at `position` (altitude in metres) and points it at
   * `lookAt`, or turns it to `pitch` and `bearing`.
   */
  setFreeCamera(options: {
    position?: { latitude: number; longitude: number; altitude?: number }
    lookAt?: { latitude: number; longitude: number; altitude?: number }
    pitch?: number
    bearing?: number
  }): Promise<null>
  /** The camera limits in effect. */
  getCameraBounds(): Promise<MapboxCameraBounds>
  /** The camera the style asks for (its `center`, `zoom`, …). */
  getStyleDefaultCamera(): Promise<MapboxCameraOptions>
  /** The tiles covering the view. */
  tileCover(options?: {
    tileSize?: number
    minZoom?: number
    maxZoom?: number
    roundZoom?: boolean
  }): Promise<
    { z: number; x: number; y: number; overscaledZ: number; wrap: number }[]
  >
  /** Rendering statistics sampled over `durationMs` (default 1000). */
  collectPerformanceStatistics(options?: { durationMs?: number }): Promise<{
    collectionDurationMillis: number
    mapRenderDuration: { maxMillis: number; medianMillis: number }
    cumulative?: {
      drawCalls?: number
      textureBytes?: number
      vertexBytes?: number
    }
  }>
  /**
   * Drives the location puck (and the follow modes) from these values
   * instead of the device's location: simulation, tests, or your own
   * positioning. Call again to move it; `clearLocationOverride` goes back to
   * the device.
   */
  setLocationOverride(location: {
    latitude: number
    longitude: number
    altitude?: number
    /** Metres. */
    accuracy?: number
    /** Degrees, for `puck.bearing: 'heading'`. */
    heading?: number
    /** Degrees, for `puck.bearing: 'course'`. */
    course?: number
    speed?: number
  }): Promise<null>
  clearLocationOverride(): Promise<null>
  /** Redraw now. */
  triggerRepaint(): Promise<null>
  /** Free memory the map can rebuild. */
  reduceMemoryUse(): Promise<null>
}

/** The Mapbox engine's methods on a mounted map (`ref.current`). */
export function mapboxMap(
  map: ProviderCommandTarget | null | undefined
): MapboxMapMethods {
  return new Proxy({} as MapboxMapMethods, {
    get: (_target, method: string) => (args?: object) =>
      map
        ? providerCommand(map, method, args ?? {})
        : Promise.reject(
            new Error(`munim-maps: ${method}: the map is not mounted`)
          ),
  })
}

// --- Offline (no map needed) ------------------------------------------------

export interface MapboxTileRegion {
  id: string
  requiredResourceCount: number
  completedResourceCount: number
  completedResourceSize: number
  expires?: number
}

export interface MapboxStylePack {
  styleUri: string
  requiredResourceCount: number
  completedResourceCount: number
  completedResourceSize: number
  expires?: number
  glyphsRasterizationMode?: string
}

/** Progress of a download, in `MapboxOffline.addListener`. */
export interface MapboxDownloadProgress {
  /** Tile region id, or style URL for style packs. */
  id: string
  kind: 'tileRegion' | 'stylePack'
  requiredResourceCount: number
  completedResourceCount: number
  completedResourceSize: number
  erroredResourceCount?: number
  loadedResourceCount?: number
  loadedResourceSize?: number
}

/**
 * Mapbox's offline maps: style packs (style, sprites, fonts) from the
 * `OfflineManager` and tile regions from the `TileStore`. A map shows
 * downloaded areas without a connection once both are there.
 */
export const MapboxOffline = {
  /** Downloads a style's resources. Resolves when done. */
  loadStylePack: (options: {
    styleUri: string
    /** `ideographsRasterizedLocally` (default), `allGlyphsRasterizedLocally`, `noGlyphsRasterizedLocally`. */
    glyphsRasterizationMode?: string
    metadata?: Json
    acceptExpired?: boolean
  }) =>
    callProvider<MapboxStylePack>('mapbox', 'offline.loadStylePack', options),
  /** Downloads the tiles of an area. Resolves when done. */
  loadTileRegion: (options: {
    id: string
    /** A GeoJSON geometry, or `bounds`. */
    geometry?: Json
    bounds?: MapboxCameraBounds['bounds']
    /** Style whose tilesets to load. Default Mapbox Standard. */
    styleUri?: string
    minZoom?: number
    maxZoom?: number
    pixelRatio?: number
    /** Extra tilesets (`mapbox://mapbox.mapbox-terrain-dem-v1`). */
    tilesets?: string[]
    metadata?: Json
    acceptExpired?: boolean
    /** `none`, `disallowExpensive` (no cellular) or `disallowAll`. */
    networkRestriction?: 'none' | 'disallowExpensive' | 'disallowAll'
  }) =>
    callProvider<MapboxTileRegion>('mapbox', 'offline.loadTileRegion', options),
  /** Cancels a download started with `loadTileRegion` / `loadStylePack`. */
  cancel: (options: { id: string }) =>
    callProvider<boolean>('mapbox', 'offline.cancel', options),
  /** Size estimate of a tile region before downloading it. */
  estimateTileRegion: (options: {
    geometry?: Json
    bounds?: MapboxCameraBounds['bounds']
    styleUri?: string
    minZoom?: number
    maxZoom?: number
  }) =>
    callProvider<{ storageSize: number; transferSize: number }>(
      'mapbox',
      'offline.estimateTileRegion',
      options
    ),
  tileRegions: () =>
    callProvider<MapboxTileRegion[]>('mapbox', 'offline.tileRegions'),
  tileRegion: (options: { id: string }) =>
    callProvider<MapboxTileRegion>('mapbox', 'offline.tileRegion', options),
  tileRegionMetadata: (options: { id: string }) =>
    callProvider<Json>('mapbox', 'offline.tileRegionMetadata', options),
  removeTileRegion: (options: { id: string }) =>
    callProvider<null>('mapbox', 'offline.removeTileRegion', options),
  stylePacks: () =>
    callProvider<MapboxStylePack[]>('mapbox', 'offline.stylePacks'),
  stylePackMetadata: (options: { styleUri: string }) =>
    callProvider<Json>('mapbox', 'offline.stylePackMetadata', options),
  removeStylePack: (options: { styleUri: string }) =>
    callProvider<null>('mapbox', 'offline.removeStylePack', options),
  /** Disk quota for the tile store, in bytes. */
  setTileStoreQuota: (options: { bytes: number }) =>
    callProvider<null>('mapbox', 'offline.setTileStoreQuota', options),
  /** Stop (false) or resume (true) all Mapbox network traffic. */
  setConnected: (options: { connected: boolean }) =>
    callProvider<null>('mapbox', 'offline.setConnected', options),
  /** Clears Mapbox's ambient cache and tile store. */
  clearData: () => callProvider<null>('mapbox', 'offline.clearData'),
  /** Download progress for every download. Returns `remove`. */
  addListener: (listener: (progress: MapboxDownloadProgress) => void) =>
    addProviderEventListener('mapbox', (name, data) => {
      if (name === 'offline.progress') listener(data as MapboxDownloadProgress)
    }),
}

// --- Web services (the public token, from JavaScript) -----------------------

let serviceToken = ''
let nativeToken: Promise<string> | undefined

/**
 * The token for `MapboxServices`. Default: the one given to
 * `configureMunimMaps({ mapboxAccessToken })`, else the one the app is
 * built with (Info.plist / strings.xml, from the config plugin).
 */
export function setMapboxServicesToken(token: string) {
  serviceToken = token
}

async function service<T>(url: string, token?: string): Promise<T> {
  // The token the app is built with (Info.plist / strings.xml), when
  // JavaScript was not given one.
  nativeToken ??= callProvider<string>('mapbox', 'accessToken').catch(() => '')
  const key =
    token ?? (serviceToken || configuredMapboxToken() || (await nativeToken))
  if (!key) throw new Error('munim-maps: Mapbox services need an access token')
  const response = await fetch(
    `${url}${url.includes('?') ? '&' : '?'}access_token=${encodeURIComponent(key)}`
  )
  if (!response.ok) {
    throw new Error(`Mapbox ${response.status}: ${await response.text()}`)
  }
  return (await response.json()) as T
}

function query(params: Record<string, unknown>): string {
  return Object.entries(params)
    .filter(([, v]) => v != null && v !== '')
    .map(
      ([k, v]) =>
        `${k}=${encodeURIComponent(Array.isArray(v) ? v.join(',') : String(v))}`
    )
    .join('&')
}

/**
 * Mapbox's web APIs with the public token: Geocoding v6, Search Box,
 * Directions, Matrix and Isochrone. Each request counts against your
 * Mapbox account's free tier and is billed beyond it (see Mapbox pricing);
 * Mapbox's terms limit storing results from temporary geocoding.
 */
export const MapboxServices = {
  /** Forward geocoding (Geocoding API v6). */
  geocode: (
    q: string,
    options: {
      proximity?: [number, number]
      country?: string
      language?: string
      limit?: number
      types?: string[]
      token?: string
    } = {}
  ) =>
    service<Json>(
      `https://api.mapbox.com/search/geocode/v6/forward?${query({ q, proximity: options.proximity, country: options.country, language: options.language, limit: options.limit, types: options.types })}`,
      options.token
    ),
  /** Reverse geocoding (Geocoding API v6). */
  reverseGeocode: (
    coordinate: { latitude: number; longitude: number },
    options: { language?: string; types?: string[]; token?: string } = {}
  ) =>
    service<Json>(
      `https://api.mapbox.com/search/geocode/v6/reverse?${query({ longitude: coordinate.longitude, latitude: coordinate.latitude, language: options.language, types: options.types })}`,
      options.token
    ),
  /** Search Box suggestions (POIs, addresses). One `sessionToken` per search session. */
  suggest: (
    q: string,
    options: {
      sessionToken: string
      proximity?: [number, number]
      language?: string
      limit?: number
      types?: string[]
      token?: string
    }
  ) =>
    service<Json>(
      `https://api.mapbox.com/search/searchbox/v1/suggest?${query({ q, session_token: options.sessionToken, proximity: options.proximity, language: options.language, limit: options.limit, types: options.types })}`,
      options.token
    ),
  /** The place behind a Search Box suggestion. */
  retrieve: (
    mapboxId: string,
    options: { sessionToken: string; token?: string }
  ) =>
    service<Json>(
      `https://api.mapbox.com/search/searchbox/v1/retrieve/${encodeURIComponent(mapboxId)}?${query({ session_token: options.sessionToken })}`,
      options.token
    ),
  /** Directions between 2...25 coordinates. */
  directions: (
    coordinates: { latitude: number; longitude: number }[],
    options: {
      profile?: 'driving' | 'driving-traffic' | 'walking' | 'cycling'
      alternatives?: boolean
      steps?: boolean
      overview?: 'full' | 'simplified' | 'false'
      language?: string
      token?: string
    } = {}
  ) =>
    service<Json>(
      `https://api.mapbox.com/directions/v5/mapbox/${options.profile ?? 'driving'}/${coordinates.map((c) => `${c.longitude},${c.latitude}`).join(';')}?${query({ geometries: 'geojson', alternatives: options.alternatives, steps: options.steps, overview: options.overview ?? 'full', language: options.language })}`,
      options.token
    ),
  /** Travel times between coordinates. */
  matrix: (
    coordinates: { latitude: number; longitude: number }[],
    options: {
      profile?: 'driving' | 'driving-traffic' | 'walking' | 'cycling'
      token?: string
    } = {}
  ) =>
    service<Json>(
      `https://api.mapbox.com/directions-matrix/v1/mapbox/${options.profile ?? 'driving'}/${coordinates.map((c) => `${c.longitude},${c.latitude}`).join(';')}`,
      options.token
    ),
  /** Areas reachable within these minutes. */
  isochrone: (
    coordinate: { latitude: number; longitude: number },
    options: {
      minutes: number[]
      profile?: 'driving' | 'walking' | 'cycling'
      polygons?: boolean
      token?: string
    }
  ) =>
    service<Json>(
      `https://api.mapbox.com/isochrone/v1/mapbox/${options.profile ?? 'driving'}/${coordinate.longitude},${coordinate.latitude}?${query({ contours_minutes: options.minutes, polygons: options.polygons })}`,
      options.token
    ),
}
