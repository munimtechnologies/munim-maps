/**
 * The Cesium engine (`provider="cesium"`): CesiumJS 1.146 bundled with
 * munim-maps (offline, Apache-2.0), running in a WebView the engine owns
 * (WKWebView on iOS, android.webkit.WebView on Android).
 *
 * - Every shared munim-maps prop, event and method works (markers, shapes,
 *   camera, models, zones, paths…).
 * - `cesium={{ … }}` (`CesiumMapOptions`) reaches the rest of CesiumJS
 *   declaratively: imagery and terrain providers, 3D Tiles (Cesium OSM
 *   Buildings, Google Photorealistic 3D Tiles, your own), CZML / GeoJSON /
 *   KML / GPX data sources, CZML entities, the clock, scene modes, lighting,
 *   atmosphere, shadows, fog, post-processing, Viewer widgets.
 * - `cesiumCommands(ref)` reaches it imperatively: flights, picking,
 *   measuring, terrain heights, screenshots, data sources, tilesets…
 * - `onProviderEvent` + `parseCesiumEvent` deliver Cesium-only events.
 *
 * Without a token it uses OpenStreetMap imagery and a smooth ellipsoid (no
 * terrain). `configureMunimMaps({ cesiumIonToken })` turns on Cesium World
 * Terrain, Bing imagery and ion assets.
 */
import type { MunimMapViewMethods, ProviderEvent } from '../specs/MunimMapView.nitro'

// MARK: Shared value shapes

/** A position: degrees and metres above the WGS84 ellipsoid. */
export interface CesiumPosition {
  latitude: number
  longitude: number
  /** Metres above the ellipsoid. Default 0. */
  height?: number
}

/** A rectangle in degrees. */
export interface CesiumRectangle {
  west: number
  south: number
  east: number
  north: number
}

/** `#RRGGBB`, `#RRGGBBAA` or any CSS colour. */
export type CesiumColor = string

/** Degrees, as Cesium's camera uses them (pitch -90 looks straight down). */
export interface CesiumOrientation {
  heading?: number
  pitch?: number
  roll?: number
}

// MARK: Imagery

export type CesiumImageryPreset =
  /** OpenStreetMap's standard tiles (no key). The default. */
  | 'openStreetMap'
  /** Satellite: Bing through ion with a token, else Esri World Imagery. */
  | 'aerial'
  /** Satellite with labels. */
  | 'aerialWithLabels'
  /** Roads: Bing through ion with a token, else OpenStreetMap. */
  | 'road'
  /** OpenStreetMap, washed out. */
  | 'muted'
  /** Natural Earth II, bundled with Cesium: works offline. */
  | 'naturalEarth'
  /** No imagery: the globe's `baseColor`. */
  | 'none'

/**
 * An imagery layer: a provider (`type`) with its options, and how the layer
 * draws (alpha, brightness…). Unknown keys go to the provider's constructor
 * options, so every option of every Cesium imagery provider is reachable.
 */
export interface CesiumImageryLayer {
  id?: string
  type:
    | 'openStreetMap'
    | 'urlTemplate'
    | 'wms'
    | 'wmts'
    | 'tms'
    | 'singleTile'
    | 'bing'
    | 'ion'
    | 'arcgis'
    | 'mapbox'
    | 'mapboxStyle'
    | 'google2d'
    | 'azure2d'
    | 'googleEarthEnterprise'
    | 'grid'
    | 'tileCoordinates'
  /** Template (`{z}/{x}/{y}`, `{s}`, `{reverseY}`…) or service URL. */
  url?: string
  /** ion asset id (`ion`, `google2d`). */
  assetId?: number
  /** WMS layers. */
  layers?: string
  /** WMTS layer, style, tile matrix set, format. */
  layer?: string
  style?: string
  tileMatrixSetID?: string
  format?: string
  /** WMS / WMTS query parameters. */
  parameters?: Record<string, string | number | boolean>
  /** Bing / Google / Azure / Mapbox keys. */
  key?: string
  accessToken?: string
  subscriptionKey?: string
  /** Bing map style (`aerial`, `road`, `canvasDark`…). */
  mapStyle?: string
  /** ArcGIS basemap (`satellite`, `oceans`, `hillshade`). */
  basemapType?: 'satellite' | 'oceans' | 'hillshade'
  /** Mapbox. */
  mapId?: string
  styleId?: string
  username?: string
  minimumLevel?: number
  maximumLevel?: number
  rectangle?: CesiumRectangle
  tilingScheme?: 'webMercator' | 'geographic'
  subdomains?: string | string[]
  credit?: string
  tileWidth?: number
  tileHeight?: number
  enablePickFeatures?: boolean
  // Layer appearance
  alpha?: number
  nightAlpha?: number
  dayAlpha?: number
  brightness?: number
  contrast?: number
  hue?: number
  saturation?: number
  gamma?: number
  show?: boolean
  splitDirection?: 'left' | 'none' | 'right'
  colorToAlpha?: CesiumColor
  colorToAlphaThreshold?: number
  cutoutRectangle?: CesiumRectangle
  /** Anything else the provider takes. */
  options?: Record<string, unknown>
  [key: string]: unknown
}

// MARK: Terrain

export type CesiumTerrain =
  /** A smooth WGS84 ellipsoid: no heights, no key. */
  | 'ellipsoid'
  /** Cesium World Terrain (ion token). */
  | 'world'
  /** Cesium World Bathymetry: terrain with the sea floor (ion token). */
  | 'bathymetry'
  /** Esri World Elevation 3D. */
  | 'arcgis'
  | {
      type: 'ellipsoid' | 'world' | 'bathymetry' | 'ion' | 'url' | 'arcgis' | 'vrTheWorld' | '3dTiles' | 'googleEarthEnterprise'
      /** ion asset id (`ion`, `3dTiles`). */
      assetId?: number
      /** quantized-mesh (`url`), ArcGIS, VR-TheWorld, 3D Tiles or GEE URL. */
      url?: string
      /** ArcGIS token. */
      token?: string
      /** Lighting normals. Default true. */
      requestVertexNormals?: boolean
      /** Water mask (animated water with `globe.showWaterEffect`). */
      requestWaterMask?: boolean
      requestMetadata?: boolean
    }

// MARK: 3D Tiles

/** A Cesium 3D Tiles style (`color`, `show`, `pointSize`… expressions). */
export interface Cesium3DTileStyle {
  show?: string | boolean | { conditions: [string, string][] }
  color?: string | { conditions: [string, string][] }
  pointSize?: string | number
  defines?: Record<string, string>
  meta?: Record<string, string>
  [key: string]: unknown
}

export interface CesiumClippingPolygons {
  polygons: (CesiumPosition[] | { positions: CesiumPosition[] })[]
  /** Clip outside the polygons instead of inside. */
  inverse?: boolean
  enabled?: boolean
}

export interface CesiumClippingPlanes {
  planes: { normal: { x: number; y: number; z: number }; distance: number }[]
  /** Planes are relative to an east-north-up frame here. */
  center?: CesiumPosition
  edgeWidth?: number
  edgeColor?: CesiumColor
  unionClippingRegions?: boolean
  enabled?: boolean
}

export interface CesiumCustomShader {
  mode?: 'modifyMaterial' | 'replaceMaterial'
  lightingModel?: 'unlit' | 'pbr'
  translucencyMode?: 'inherit' | 'opaque' | 'translucent'
  uniforms?: Record<string, { type: string; value: unknown }>
  vertexShaderText?: string
  fragmentShaderText?: string
}

/**
 * A 3D source: 3D Tiles from a URL or ion, Cesium OSM Buildings, Google
 * Photorealistic 3D Tiles, I3S scene layers, voxels, Mapbox Vector Tiles
 * (as 3D Tiles), or iTwin models / reality data. Other keys are
 * `Cesium3DTileset` constructor options (`maximumScreenSpaceError`,
 * `dynamicScreenSpaceError`, `shadows`, `pointCloudShading`,
 * `imageBasedLighting`, `classificationType`, `enableCollision`…).
 */
export interface CesiumTileset {
  id?: string
  type?: 'url' | 'ion' | 'osmBuildings' | 'photorealistic' | 'i3s' | 'voxel' | 'mvt' | 'itwin'
  url?: string
  ionAssetId?: number
  /** Photorealistic: through ion (asset 2275207, ion token) or Google's Map Tiles API (`key`, else the Google Maps key). */
  source?: 'ion' | 'google'
  key?: string
  style?: Cesium3DTileStyle
  show?: boolean
  /** Frame it once loaded. */
  flyTo?: boolean
  clippingPolygons?: CesiumClippingPolygons
  clippingPlanes?: CesiumClippingPlanes
  customShader?: CesiumCustomShader
  maximumScreenSpaceError?: number
  /** iTwin. */
  iModelId?: string
  changesetId?: string
  iTwinId?: string
  realityDataId?: string
  options?: Record<string, unknown>
  [key: string]: unknown
}

// MARK: Data

/** A CZML packet (https://github.com/AnalyticalGraphicsInc/czml-writer/wiki/Packet). */
export interface CzmlPacket {
  id: string
  name?: string
  parent?: string
  description?: string
  availability?: string
  delete?: boolean
  position?: unknown
  orientation?: unknown
  viewFrom?: unknown
  properties?: Record<string, unknown>
  billboard?: Record<string, unknown>
  box?: Record<string, unknown>
  corridor?: Record<string, unknown>
  cylinder?: Record<string, unknown>
  ellipse?: Record<string, unknown>
  ellipsoid?: Record<string, unknown>
  label?: Record<string, unknown>
  model?: Record<string, unknown>
  path?: Record<string, unknown>
  point?: Record<string, unknown>
  polygon?: Record<string, unknown>
  polyline?: Record<string, unknown>
  polylineVolume?: Record<string, unknown>
  rectangle?: Record<string, unknown>
  tileset?: Record<string, unknown>
  wall?: Record<string, unknown>
  clock?: Record<string, unknown>
  [key: string]: unknown
}

export interface CesiumDataSource {
  id?: string
  type?: 'czml' | 'geojson' | 'topojson' | 'kml' | 'kmz' | 'gpx'
  /** A file URL (`https://`, `file://`, a bundled asset's URI). */
  url?: string
  /** Or the data itself: CZML packets, a GeoJSON object, KML / GPX text. */
  data?: unknown
  /**
   * The loader's options: GeoJSON `clampToGround`, `stroke`, `fill`,
   * `strokeWidth`, `markerSize`, `markerSymbol`, `markerColor`; KML
   * `clampToGround`, `screenOverlayContainer`; GPX `clampToGround`,
   * `waypointImage`, `trackColor`, `routeColor`…
   */
  options?: Record<string, unknown>
  show?: boolean
  flyTo?: boolean
  /** Cluster its billboards, labels and points. */
  clustering?: { enabled?: boolean; pixelRange?: number; minimumClusterSize?: number; clusterBillboards?: boolean; clusterLabels?: boolean; clusterPoints?: boolean; color?: CesiumColor }
}

// MARK: Time

export interface CesiumClock {
  /** ISO 8601 or seconds since 1970. */
  startTime?: string | number
  stopTime?: string | number
  currentTime?: string | number
  /** Seconds of simulation per second. */
  multiplier?: number
  shouldAnimate?: boolean
  canAnimate?: boolean
  clockRange?: 'unbounded' | 'clamped' | 'loopStop'
  clockStep?: 'tickDependent' | 'systemClockMultiplier' | 'systemClock'
}

// MARK: Look

export interface CesiumGlobeOptions {
  show?: boolean
  baseColor?: CesiumColor
  enableLighting?: boolean
  dynamicAtmosphereLighting?: boolean
  dynamicAtmosphereLightingFromSun?: boolean
  showGroundAtmosphere?: boolean
  atmosphereLightIntensity?: number
  lightingFadeOutDistance?: number
  lightingFadeInDistance?: number
  nightFadeOutDistance?: number
  nightFadeInDistance?: number
  depthTestAgainstTerrain?: boolean
  showWaterEffect?: boolean
  showSkirts?: boolean
  backFaceCulling?: boolean
  maximumScreenSpaceError?: number
  tileCacheSize?: number
  preloadAncestors?: boolean
  preloadSiblings?: boolean
  undergroundColor?: CesiumColor
  translucency?: { enabled?: boolean; frontFaceAlpha?: number; backFaceAlpha?: number; rectangle?: CesiumRectangle }
  cartographicLimitRectangle?: CesiumRectangle
  clippingPolygons?: CesiumClippingPolygons
  clippingPlanes?: CesiumClippingPlanes
  /**
   * A material on the globe: `{ type: 'ElevationContour' | 'ElevationRamp'
   * | 'SlopeRamp' | 'AspectRamp' | …, uniforms, ramp: colours }`, or
   * `{ elevationBands: [...] }`.
   */
  material?: { type?: string; uniforms?: Record<string, unknown>; ramp?: CesiumColor[]; elevationBands?: { entries: { height: number; color: CesiumColor }[]; extendDownwards?: boolean; extendUpwards?: boolean }[] }
  [key: string]: unknown
}

export interface CesiumPostProcess {
  fxaa?: boolean
  bloom?: boolean | { glowOnly?: boolean; contrast?: number; brightness?: number; delta?: number; sigma?: number; stepSize?: number }
  ambientOcclusion?: boolean | { intensity?: number; bias?: number; lengthCap?: number; stepSize?: number; frustumLength?: number; ambientOcclusionOnly?: boolean; delta?: number; sigma?: number; blurStepSize?: number }
  /** Stages from Cesium's PostProcessStageLibrary, or your own shader. */
  stages?: {
    type: 'blackAndWhite' | 'brightness' | 'nightVision' | 'depthOfField' | 'edgeDetection' | 'silhouette' | 'lensFlare' | 'blur' | 'custom'
    uniforms?: Record<string, unknown>
    enabled?: boolean
    fragmentShader?: string
  }[]
}

export interface CesiumWidgets {
  /** The clock dial (bottom left). */
  animation?: boolean
  /** The timeline (bottom). */
  timeline?: boolean
  /** Imagery / terrain picker (needs an ion token). */
  baseLayerPicker?: boolean
  /** Search box: true (ion geocoder), or `google`, `bing`. */
  geocoder?: boolean | 'default' | 'google' | 'bing'
  homeButton?: boolean
  sceneModePicker?: boolean
  projectionPicker?: boolean
  navigationHelpButton?: boolean
  fullscreenButton?: boolean
  vrButton?: boolean
  /** Entity descriptions when one is selected. */
  infoBox?: boolean
  selectionIndicator?: boolean
  /** Debug panels (viewer mixins). */
  inspector?: boolean
  tilesInspector?: boolean
  voxelInspector?: boolean
  performanceWatchdog?: boolean | { lowFrameRateMessage?: string }
  dragDrop?: boolean
}

/**
 * Options only the Cesium engine reads (`provider="cesium"`), passed as
 * `cesium={{ … }}` on `MunimMapView`. Keys marked "made once" rebuild the
 * Cesium viewer when they change (everything is re-applied).
 */
export interface CesiumMapOptions {
  // Scene
  /** `3d` (globe, default), `2d` or `columbus` (2.5D); morphs when it changes. */
  sceneMode?: '3d' | '2d' | 'columbus'
  /** Seconds the morph takes. Default 2. */
  morphDuration?: number
  /** Made once. Only 3D: saves memory. */
  scene3DOnly?: boolean
  /** Made once. 2D / Columbus projection. Default geographic. */
  mapProjection?: 'geographic' | 'webMercator'
  /** Made once. 2D: rotate or scroll forever. */
  mapMode2D?: 'rotate' | 'infiniteScroll'
  /** Made once. Viewer widgets (all off by default). */
  widgets?: CesiumWidgets
  /** Made once. MSAA samples (default 4). */
  msaaSamples?: number
  /** Made once. */
  orderIndependentTranslucency?: boolean
  /** Made once. Draw at CSS pixels (faster, softer). Default false: device pixels up to 2x. */
  useBrowserRecommendedResolution?: boolean
  /** Made once. WebGL context options. */
  contextOptions?: Record<string, unknown>
  /** Made once. Follow loaded data sources' clocks. Default true. */
  automaticallyTrackDataSourceClocks?: boolean
  /** Scale of the drawing buffer. Default the device pixel ratio, up to 2. */
  resolutionScale?: number
  targetFrameRate?: number

  // Base map
  /** Imagery under everything. Default from `mapStyle` (`standard`: OpenStreetMap). */
  imagery?: CesiumImageryPreset | CesiumImageryLayer
  /** More imagery layers, bottom to top, over the base. */
  imageryLayers?: CesiumImageryLayer[]
  /** Default `world` with an ion token (unless `elevation="flat"`), else `ellipsoid`. */
  terrain?: CesiumTerrain
  /** Exaggerates terrain and 3D Tiles heights. Default 1. */
  verticalExaggeration?: number
  /** @deprecated the same as `verticalExaggeration`. */
  terrainExaggeration?: number
  verticalExaggerationRelativeHeight?: number

  // 3D Tiles
  /**
   * Cesium OSM Buildings (ion token). Default: on with a token while
   * `showsBuildings` (or `occlusion="buildings"`) and no photorealistic tiles.
   * An object is a style and tileset options.
   */
  osmBuildings?: boolean | Omit<CesiumTileset, 'type'>
  /** Google Photorealistic 3D Tiles. Default false. */
  photorealistic?: boolean | Omit<CesiumTileset, 'type'>
  tilesets?: CesiumTileset[]

  // Data
  /** CZML packets, updated in place by `id` (removed ids are deleted). */
  entities?: CzmlPacket[]
  dataSources?: CesiumDataSource[]

  // Time
  clock?: CesiumClock

  // Look
  globe?: CesiumGlobeOptions
  /** Scene atmosphere (ground and fog colour): `lightIntensity`, `rayleighCoefficient`, `hueShift`, `dynamicLighting`… */
  atmosphere?: { dynamicLighting?: 'none' | 'sceneLight' | 'sunlight'; [key: string]: unknown }
  skyAtmosphere?: boolean | Record<string, unknown>
  /** The star box; `sources` are six image URLs (positiveX…negativeZ). */
  skyBox?: boolean | { sources: Record<string, string> }
  sun?: boolean | { glowFactor?: number }
  moon?: boolean | Record<string, unknown>
  fog?: boolean | { enabled?: boolean; density?: number; minimumBrightness?: number; screenSpaceErrorFactor?: number; [key: string]: unknown }
  /** Shadows from the light; an object sets the shadow map (`softShadows`, `size`, `darkness`, `maximumDistance`). */
  shadows?: boolean | { softShadows?: boolean; size?: number; darkness?: number; maximumDistance?: number; fadingEnabled?: boolean; normalOffset?: boolean }
  terrainShadows?: 'enabled' | 'disabled' | 'castOnly' | 'receiveOnly'
  /**
   * The light. Default from the munim `lighting` prop: `auto` is the sun at
   * the clock's time; `day` / `night` light from over the viewer's shoulder.
   */
  light?: 'sun' | 'directional' | { type: 'sun' | 'directional'; direction?: { x: number; y: number; z: number }; color?: CesiumColor; intensity?: number }
  highDynamicRange?: boolean
  tonemapper?: 'reinhard' | 'modifiedReinhard' | 'filmic' | 'aces' | 'pbrNeutral'
  exposure?: number
  backgroundColor?: CesiumColor
  postProcess?: CesiumPostProcess
  /** Volumetric-looking cumulus clouds. */
  clouds?: { position?: CesiumPosition; latitude?: number; longitude?: number; height?: number; scale?: { x: number; y: number }; maximumSize?: { x: number; y: number; z: number }; slice?: number; brightness?: number; color?: CesiumColor; show?: boolean }[]
  cloudOptions?: { noiseDetail?: number; noiseOffset?: { x: number; y: number; z: number } }
  debugShowFramesPerSecond?: boolean
  pickTranslucentDepth?: boolean
  /** Hide the data attributions. Only where the data's terms allow it. */
  showCredits?: boolean
  /** Any other `Scene` property (`light`, `fog`… are above). */
  sceneOptions?: Record<string, unknown>

  // Camera and input
  camera?: {
    frustum?: 'perspective' | 'orthographic'
    /** Field of view in degrees (the larger of width and height). Default 60. */
    fov?: number
    near?: number
    far?: number
    percentageChanged?: number
    defaultMoveAmount?: number
    defaultLookAmount?: number
    defaultRotateAmount?: number
    defaultZoomAmount?: number
    maximumZoomFactor?: number
  }
  /**
   * Cesium's ScreenSpaceCameraController (`enableTilt`, `inertiaSpin`,
   * `minimumZoomDistance`, `enableCollisionDetection`, `maximumTiltAngle`…);
   * set after the munim gesture props, so it wins.
   */
  controller?: Record<string, unknown>
  /** Follow this entity (CZML / data source id) with the camera. */
  trackedEntityId?: string
  /** Select this entity (info box, selection indicator). */
  selectedEntityId?: string
  /** Select entities (info box) when tapped. Default true. */
  selectEntitiesOnTap?: boolean
  /** Send a `pick` event for every tap. Default true. */
  pickEvents?: boolean

  // munim models
  /**
   * Who draws `models`, `zones` and `paths`: `auto` (default) lets Cesium
   * draw glTF / GLB, shapes and pictures (hidden by terrain and buildings)
   * and munim-maps' native 3D layer draw other files (USDZ, SCN, OBJ on
   * iOS); `cesium` draws everything in Cesium (other files are skipped);
   * `native` draws everything on the native layer over the WebView, exactly
   * as on MapKit.
   */
  modelRenderer?: 'auto' | 'cesium' | 'native'
  /** Degrees added to models' heading. Default -90 (Cesium faces glTF models east). */
  modelHeadingOffset?: number

  // Keys and services
  /** ion server for self-hosted ion. */
  ionServer?: string
  arcGisAccessToken?: string
  /** Google Map Tiles API key (photorealistic tiles, 2D tiles); default the Google Maps key. */
  googleMapsApiKey?: string
  googleStreetViewApiKey?: string
  bingMapsKey?: string
  iTwinAccessToken?: string
  iTwinShareKey?: string

  /** Allow `cesiumCommands(ref).evaluate(script)`: JavaScript in the map's WebView. Default false. */
  allowEvaluate?: boolean
}

// MARK: Events

/** Cesium-only events (`onProviderEvent`), parsed. */
export type CesiumEvent =
  | { name: 'pick'; data: CesiumPick }
  | { name: 'tilesetLoaded' | 'tilesetAllTilesLoaded' | 'dataSourceLoaded'; data: { id: string; entities?: number } }
  | { name: 'selectedEntityChanged' | 'trackedEntityChanged'; data: { id: string | null } }
  | { name: 'morphComplete'; data: { sceneMode: '3d' | '2d' | 'columbus' } }
  | { name: 'terrainChanged'; data: { type: string } }
  | { name: 'cameraMoveStart' | 'cameraMoveEnd' | 'globeTilesLoaded'; data: Record<string, never> }

/** What a tap or `pick` hit. */
export interface CesiumPick {
  kind: 'marker' | 'model' | 'overlay' | 'zone' | 'path' | 'cluster' | 'entity' | 'feature' | 'primitive' | 'user' | 'none'
  id?: string
  ids?: string[]
  entityId?: string
  name?: string
  /** Entity properties or 3D Tiles feature properties. */
  properties?: Record<string, unknown>
  /** The ground, terrain or tile surface under the point. */
  position?: CesiumPosition | null
  latitude?: number
  longitude?: number
  height?: number
  x?: number
  y?: number
}

/** Reads a Cesium event from `onProviderEvent`. */
export function parseCesiumEvent(event: ProviderEvent): CesiumEvent {
  let data: unknown = {}
  try {
    data = JSON.parse(event.data || '{}')
  } catch {
    data = {}
  }
  return { name: event.name, data } as CesiumEvent
}

// MARK: Commands

export interface CesiumCameraView {
  position: CesiumPosition
  heading: number
  pitch: number
  roll: number
  frustum: { type: 'perspective' | 'orthographic'; fov?: number; fovy?: number; aspectRatio?: number; near: number; far: number; width?: number }
  viewMatrix: number[]
  projectionMatrix: number[]
  sceneMode: '3d' | '2d' | 'columbus' | 'morphing'
  munim: { latitude: number; longitude: number; distance: number; pitch: number; heading: number }
}

/** Something to frame or follow: by id. */
export interface CesiumTarget {
  entityId?: string
  dataSourceId?: string
  tilesetId?: string
  modelId?: string
  markerId?: string
}

export interface CesiumCommands {
  /** Cesium's camera flight (arcs up for long distances). */
  flyTo(options: { destination: CesiumPosition | CesiumRectangle; orientation?: CesiumOrientation; duration?: number; maximumHeight?: number; pitchAdjustHeight?: number; flyOverLongitude?: number; flyOverLongitudeWeight?: number; easing?: string }): Promise<{ completed: boolean }>
  setView(options: { destination: CesiumPosition | CesiumRectangle; orientation?: CesiumOrientation }): Promise<null>
  /** Looks at a point from heading / pitch / range; `lock` keeps the camera locked to it. */
  lookAt(options: { target: CesiumPosition; heading?: number; pitch?: number; range?: number; lock?: boolean }): Promise<null>
  flyHome(options?: { duration?: number }): Promise<null>
  zoomTo(target: CesiumTarget & { offset?: { heading?: number; pitch?: number; range?: number } }): Promise<{ completed: boolean }>
  flyToTarget(target: CesiumTarget & { duration?: number; maximumHeight?: number; offset?: { heading?: number; pitch?: number; range?: number } }): Promise<{ completed: boolean }>
  trackEntity(options: { id?: string }): Promise<{ tracking: boolean }>
  selectEntity(options: { id?: string }): Promise<null>
  /** Circles a point (default the centre) until `stopOrbit`. */
  orbit(options?: { center?: CesiumPosition; degreesPerSecond?: number; pitch?: number; range?: number; heading?: number }): Promise<null>
  stopOrbit(): Promise<null>
  cameraMove(options: { direction: 'forward' | 'backward' | 'left' | 'right' | 'up' | 'down' | 'in' | 'out'; amount?: number }): Promise<null>
  cameraLook(options: { direction: 'left' | 'right' | 'up' | 'down' | 'twistLeft' | 'twistRight'; degrees?: number }): Promise<null>
  cameraRotate(options: { direction: 'left' | 'right' | 'up' | 'down'; degrees?: number }): Promise<null>
  getCameraView(): Promise<CesiumCameraView>
  setSceneMode(options: { mode: '3d' | '2d' | 'columbus'; duration?: number }): Promise<null>
  /** A data URL of the scene. */
  screenshot(options?: { width?: number; height?: number; format?: 'png' | 'jpeg'; quality?: number }): Promise<{ dataUrl: string; width: number; height: number }>
  requestRender(): Promise<null>
  pick(point: { x: number; y: number; width?: number; height?: number }): Promise<CesiumPick>
  drillPick(point: { x: number; y: number; limit?: number; width?: number; height?: number }): Promise<CesiumPick[]>
  /** The surface (terrain, 3D Tiles, models) under a point. */
  pickPosition(point: { x: number; y: number }): Promise<CesiumPosition | null>
  /** Features of imagery layers there (WMS GetFeatureInfo, ArcGIS identify…). */
  pickImageryFeatures(point: { x: number; y: number }): Promise<{ name?: string; description?: string; data: unknown; position: CesiumPosition | null; layer: number }[]>
  toScreen(position: CesiumPosition): Promise<{ x: number; y: number } | null>
  measureDistance(options: { points: CesiumPosition[]; mode?: 'geodesic' | 'rhumb' | 'straight' }): Promise<{ meters: number; segments: number[] }>
  measureArea(options: { points: CesiumPosition[] }): Promise<{ squareMeters: number }>
  measureHeading(options: { from: CesiumPosition; to: CesiumPosition }): Promise<{ degrees: number; meters: number }>
  /** Ground heights (terrain; with `includeTiles`, 3D Tiles and models too). */
  sampleHeights(options: { points: CesiumPosition[]; includeTiles?: boolean; mostDetailed?: boolean; level?: number }): Promise<(number | null)[]>
  clampToHeight(options: { points: CesiumPosition[] }): Promise<(CesiumPosition | null)[]>
  addEntities(options: { czml: CzmlPacket | CzmlPacket[] }): Promise<{ count: number }>
  removeEntities(options: { ids: string[] }): Promise<{ removed: number }>
  getEntity(options: { id: string; time?: string }): Promise<{ id: string; name?: string; show: boolean; position: CesiumPosition | null; properties?: Record<string, unknown>; description?: string; availability: { start: string; stop: string } | null } | null>
  listEntities(options?: { dataSourceId?: string }): Promise<{ id: string; name?: string; dataSource: string }[]>
  exportKml(options?: { ids?: string[] }): Promise<{ kml: string }>
  loadDataSource(source: CesiumDataSource): Promise<{ id: string; entities: number }>
  removeDataSource(options: { id: string }): Promise<{ removed: boolean }>
  addTileset(tileset: CesiumTileset): Promise<{ id: string }>
  removeTileset(options: { id: string }): Promise<{ removed: boolean }>
  setTilesetStyle(options: { id: string; style?: Cesium3DTileStyle }): Promise<null>
  /** Any Cesium3DTileset property (`maximumScreenSpaceError`, `show`, `customShader`…). */
  setTilesetProperties(options: { id: string; [key: string]: unknown }): Promise<null>
  tilesetInfo(options: { id: string }): Promise<{ center: CesiumPosition | null; radius: number; properties: unknown; asset: unknown; extras: unknown; tilesLoaded: boolean; memoryBytes: number }>
  addImageryLayer(layer: CesiumImageryLayer & { index?: number }): Promise<{ id: string; index: number }>
  removeImageryLayer(options: { id: string }): Promise<{ removed: boolean }>
  setImageryLayer(options: { id: string; raise?: boolean | 'top'; lower?: boolean | 'bottom'; [key: string]: unknown }): Promise<null>
  imageryLayers(): Promise<{ index: number; id: string | null; show: boolean; alpha: number; ready: boolean }[]>
  setTerrain(options: { terrain: CesiumTerrain }): Promise<null>
  setClock(clock: CesiumClock): Promise<CesiumClock>
  play(): Promise<null>
  pause(): Promise<null>
  setTime(options: { time: string | number }): Promise<CesiumClock>
  getClock(): Promise<CesiumClock>
  addParticleSystem(options: { id?: string; position: CesiumPosition; image?: string; emitter?: 'cone' | 'box' | 'circle' | 'sphere'; emitterAngle?: number; emitterRadius?: number; emitterSize?: number; startColor?: CesiumColor; endColor?: CesiumColor; startScale?: number; endScale?: number; minimumParticleLife?: number; maximumParticleLife?: number; minimumSpeed?: number; maximumSpeed?: number; imageSize?: number; sizeInMeters?: boolean; emissionRate?: number; lifetime?: number; loop?: boolean; bursts?: { time: number; minimum: number; maximum: number }[] }): Promise<{ id: string }>
  removeParticleSystem(options: { id: string }): Promise<{ removed: boolean }>
  /** A 360° panorama in the scene: an equirectangular image, a cube map, or Google Street View (Street View Static API key). */
  loadPanorama(options: { id?: string; type?: 'equirectangular' | 'cubemap' | 'googleStreetView'; image?: string; sources?: Record<string, string>; latitude: number; longitude: number; height?: number; heading?: number; pitch?: number; roll?: number; radius?: number; key?: string; panoId?: string }): Promise<{ id: string }>
  removePanorama(options?: { id?: string }): Promise<{ removed: boolean }>
  /** A munim model drawn by Cesium: its animations and size. */
  modelInfo(options: { id: string }): Promise<{ animations: { index: number; name?: string }[]; radius: number; scale: number }>
  playModelAnimation(options: { id: string; name?: string; index?: number; loop?: 'none' | 'repeat' | 'mirroredRepeat'; multiplier?: number; reverse?: boolean }): Promise<null>
  stopModelAnimations(options: { id: string }): Promise<null>
  /** Shows / hides or moves a node of a munim model (glTF node name). */
  setModelNode(options: { id: string; node: string; show?: boolean; matrix?: number[] }): Promise<null>
  /** Cesium model looks: colour blend, silhouette, minimum pixel size, shadows, custom shader, wireframe. */
  setModelStyle(options: { id: string; color?: CesiumColor | null; colorBlendMode?: 'highlight' | 'replace' | 'mix'; colorBlendAmount?: number; silhouetteColor?: CesiumColor; silhouetteSize?: number; minimumPixelSize?: number; maximumScale?: number; shadows?: 'enabled' | 'disabled' | 'castOnly' | 'receiveOnly'; customShader?: CesiumCustomShader | null; debugWireframe?: boolean; showOutline?: boolean }): Promise<null>
  /**
   * Runs JavaScript in the map's WebView with `Cesium`, `viewer` and
   * `munim` in scope, resolving with its (JSON) result. Needs
   * `cesium={{ allowEvaluate: true }}`: everything CesiumJS has, unwrapped.
   */
  evaluate(options: { script: string }): Promise<unknown>
  version(): Promise<{ cesium: string; bridge: number }>
  stats(): Promise<Record<string, unknown>>
}

type CommandHost = Pick<MunimMapViewMethods, 'providerCommand'>

/**
 * Cesium's own methods on a `MunimMapView` ref with `provider="cesium"`:
 * `cesiumCommands(ref.current).flyTo({ destination: … })`. Each rejects on
 * other engines.
 */
export function cesiumCommands(map: CommandHost | null | undefined): CesiumCommands {
  return new Proxy({} as CesiumCommands, {
    get(_, name) {
      if (typeof name !== 'string' || name === 'then') return undefined
      return async (args?: unknown) => {
        if (!map) throw new Error('munim-maps: the map is not mounted')
        const json = await map.providerCommand(name, JSON.stringify(args ?? {}))
        return json ? JSON.parse(json) : null
      }
    },
  })
}
