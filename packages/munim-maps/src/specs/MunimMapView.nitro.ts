import type {
  HybridView,
  HybridViewMethods,
  HybridViewProps,
} from 'react-native-nitro-modules'
import type {
  MapAlignmentReport,
  MapModelLighting,
  NativeMapModel,
  MapOcclusion,
  NativeMapPath,
  NativeMapZone,
} from './MapModelLayer.nitro'
import type {
  CalloutAccessoryEvent,
  ClusterPressEvent,
  FeatureVisibility,
  MapAddress,
  MapFeatureEvent,
  MapItem,
  NativeClusterStyle,
  MapPoint,
  MapPressEvent,
  MapRegion,
  MarkerDragEvent,
  OverlayPressEvent,
  NativeCircle,
  NativeMarker,
  NativePolygon,
  NativePolyline,
  NativeTileOverlay,
  UserLocationEvent,
} from './MapFeatures.nitro'
import type { MapCoordinate } from './MapModelLayer.nitro'

/**
 * The map engine drawing a `MunimMapView`: Apple's MapKit, Google Maps,
 * Mapbox, MapLibre (open maps: OpenStreetMap data, no key) or Cesium (a 3D
 * globe). Each engine other than MapKit is opt-in at build time (CocoaPods
 * subspec on iOS, Gradle property on Android; see docs/providers.md).
 */
export type MapProvider = 'mapkit' | 'google' | 'mapbox' | 'maplibre' | 'cesium'

export type MapStyle = 'standard' | 'muted' | 'hybrid' | 'imagery'
export type MapElevation = 'flat' | 'realistic'
export type MapColorScheme = 'system' | 'light' | 'dark'
export type MapCameraEasing = 'linear' | 'easeInOut'

/** Where the camera is `t` seconds into a flight. */
export interface CameraKeyframe {
  t: number
  camera: MapCamera
}
/**
 * MapKit's user tracking: `follow` keeps the map centred on the user,
 * `followWithHeading` also turns it with the device (and shows the heading
 * beam). MapKit drops back to `none` when the user pans or zooms away.
 */
export type UserTrackingMode = 'none' | 'follow' | 'followWithHeading'
export type { FeatureVisibility }

/**
 * What tapping a place on Apple's map (`selectableMapFeatures`) shows, iOS
 * 18+: Apple's place card in a `callout` (`calloutCompact`, `calloutFull`),
 * a `sheet`, chosen by MapKit (`automatic`), or a button that opens Apple
 * Maps (`openInMaps`). `none` leaves it to you (`onMapFeaturePress`).
 */
export type SelectionAccessory =
  | 'none'
  | 'automatic'
  | 'callout'
  | 'calloutCompact'
  | 'calloutFull'
  | 'sheet'
  | 'openInMaps'

export interface EdgeInsets {
  top: number
  left: number
  bottom: number
  right: number
}

/**
 * An event only one engine has (Google's indoor level change, a Street View
 * panorama change…): the engine's `provider` id, the event `name` and its
 * data as JSON. `onProviderEvent` on `MunimMapView` parses `json`.
 */
export interface ProviderEvent {
  provider: string
  name: string
  json: string
}

export interface MapCamera {
  latitude: number
  longitude: number
  /** Metres from the camera to the point at the centre of the map. */
  distance: number
  /** Degrees from straight down. */
  pitch: number
  /** Degrees clockwise from north. */
  heading: number
}

export interface MunimMapViewProps extends HybridViewProps {
  /**
   * The engine drawing this map, resolved in JavaScript (the platform
   * default when not set). An engine that is not built into the app shows a
   * placeholder and reports `onError`.
   */
  provider: MapProvider
  /**
   * A style URL for the engines that take one: MapLibre and Mapbox style
   * JSON (`https://…/style.json`, `mapbox://styles/…`). Empty for the
   * engine's default (OpenFreeMap for MapLibre, Mapbox Standard).
   */
  styleUrl: string
  /**
   * JSON of the active provider's own options (`google`, `mapbox`,
   * `maplibre`, `cesium` or `mapkit` on the JavaScript component), so each
   * engine can add options without changing this spec. `{}` for none.
   */
  providerOptions: string
  models: NativeMapModel[]
  zones: NativeMapZone[]
  paths: NativeMapPath[]
  /**
   * `buildings` hides models behind buildings (MapKit does not share its
   * depth buffer). Footprints and heights come from vector tiles around the
   * camera, OpenStreetMap data from OpenFreeMap unless `buildingTilesUrl`
   * is set. Avatars, labels and stems stay visible.
   */
  occlusion: MapOcclusion
  /** `{z}/{x}/{y}` vector tiles with an OpenMapTiles `building` layer. Empty uses OpenFreeMap. */
  buildingTilesUrl: string
  /**
   * Keep models, paths and zones whose altitude is above the ground on
   * MapKit's 3D terrain (satellite imagery, `hybrid` / `imagery`, with
   * realistic elevation), using terrain heights from public elevation tiles.
   * Models above sea level always follow the terrain.
   */
  followTerrain: boolean
  /** Applied once, when the map first appears. */
  initialCamera: MapCamera
  mapStyle: MapStyle
  elevation: MapElevation
  /**
   * Show the standard style as a globe when zoomed far out, like Apple
   * Maps (MapKit only does this for satellite imagery). Uses a MapKit switch
   * that is not public API: it may stop working in an iOS update (the map
   * stays flat) and App Review may reject an app for it. Default false.
   */
  globe: boolean
  colorScheme: MapColorScheme
  showsBuildings: boolean
  showsUserLocation: boolean
  lighting: MapModelLighting
  maxCameraDistance: number

  // Map features (everything react-native-maps draws on iOS).
  markers: NativeMarker[]
  polylines: NativePolyline[]
  polygons: NativePolygon[]
  circles: NativeCircle[]
  tileOverlays: NativeTileOverlay[]
  /** How clusters of markers (`clusteringId`) look. */
  clusterStyles: NativeClusterStyle[]

  // Controls and behaviour.
  compassVisibility: FeatureVisibility
  scaleVisibility: FeatureVisibility
  /** MapKit's button that cycles user tracking (top right). iOS 17+ built in, earlier a `MKUserTrackingButton`. */
  showsUserTrackingButton: boolean
  /** MapKit's 2D/3D button. iOS 17+. */
  pitchButtonVisibility: FeatureVisibility
  /** Name standalone controls (`MapCompass`, `MapScale`, `MapUserTrackingButton`) use to find this map. */
  mapScope: string
  showsTraffic: boolean
  /** `all`, `none`, or comma-separated `MKPOICategory…` values to include. */
  pointsOfInterest: string
  userTrackingMode: UserTrackingMode
  zoomEnabled: boolean
  scrollEnabled: boolean
  rotateEnabled: boolean
  pitchEnabled: boolean
  /** Closest and farthest camera distance in metres; 0 for MapKit's limits. */
  minCameraDistance: number
  maxCameraDistanceLimit: number
  /** Keep the camera's centre inside this region; zero deltas for none. */
  cameraBoundary: MapRegion
  /** Space covered by your own UI; the map centres in what is left. */
  mapPadding: EdgeInsets
  /** `pointsOfInterest`, `territories`, `physicalFeatures`, comma-separated, or empty. */
  selectableMapFeatures: string
  /** Apple's place card for a tapped place (iOS 18+). */
  selectionAccessory: SelectionAccessory

  onModelPress?: (id: string) => void
  /** Fires when the camera stops moving. */
  onCameraChange?: (camera: MapCamera) => void
  /** Fires while the camera moves (about once a frame). */
  onCameraMove?: (camera: MapCamera) => void
  onMapReady?: () => void
  onPress?: (event: MapPressEvent) => void
  onLongPress?: (event: MapPressEvent) => void
  onMarkerPress?: (id: string) => void
  onMarkerDeselect?: (id: string) => void
  onCalloutPress?: (id: string) => void
  onCalloutAccessoryPress?: (event: CalloutAccessoryEvent) => void
  onClusterPress?: (event: ClusterPressEvent) => void
  /** A tappable polyline, polygon or circle was tapped (the topmost one). */
  onOverlayPress?: (event: OverlayPressEvent) => void
  onMarkerDragStart?: (event: MarkerDragEvent) => void
  onMarkerDragEnd?: (event: MarkerDragEvent) => void
  onUserLocationChange?: (location: UserLocationEvent) => void
  /** MapKit changed the tracking mode: the user panned away, or used the tracking button. */
  onUserTrackingModeChange?: (mode: UserTrackingMode) => void
  onMapFeaturePress?: (feature: MapFeatureEvent) => void
  /** Events only the active engine has (see each engine's docs). */
  onProviderEvent?: (event: ProviderEvent) => void
  onError?: (message: string) => void
}

export interface MunimMapViewMethods extends HybridViewMethods {
  setCamera(camera: MapCamera, animated: boolean): void
  /** Moves the camera over `durationMs`, for scripted fly-throughs. */
  animateCamera(
    camera: MapCamera,
    durationMs: number,
    easing: MapCameraEasing
  ): void
  /**
   * Flies the camera through keyframes, interpolated natively every frame.
   * `start` is when `t = 0` is, in seconds since 1970 (`Date.now() / 1000`),
   * the same clock as models' `motion`, so the camera can follow them.
   */
  flyCamera(keyframes: CameraKeyframe[], start: number, loop: boolean): void
  stopFlight(): void
  getCamera(): Promise<MapCamera>
  /** Animates to a region over `durationMs` (0 jumps). */
  setRegion(region: MapRegion, durationMs: number): void
  getVisibleRegion(): Promise<MapRegion>
  /** Frames the coordinates with `padding` points around them. */
  fitToCoordinates(
    coordinates: MapCoordinate[],
    padding: EdgeInsets,
    animated: boolean
  ): void
  /**
   * Frames the markers with these comma-separated ids (all markers when
   * empty). A string, not an array, to avoid a Swift bridging issue with
   * string arrays in Nitro 0.36.
   */
  fitToMarkers(ids: string, padding: EdgeInsets, animated: boolean): void
  pointForCoordinate(coordinate: MapCoordinate): Promise<MapPoint>
  coordinateForPoint(point: MapPoint): Promise<MapCoordinate>
  selectMarker(id: string): void
  deselectMarker(id: string): void
  /** Writes a PNG of the map (no models or markers) and returns its path. */
  takeSnapshot(width: number, height: number): Promise<string>
  /** Reverse-geocodes a coordinate. */
  addressForCoordinate(coordinate: MapCoordinate): Promise<MapAddress>
  /** Whether Apple has Look Around imagery here. */
  hasLookAround(coordinate: MapCoordinate): Promise<boolean>
  /** Opens Apple's full-screen Look Around at the coordinate. */
  openLookAround(coordinate: MapCoordinate): Promise<boolean>
  measureAlignment(): Promise<MapAlignmentReport>
  /** Id of the tappable overlay a tap at `point` would hit, or empty. */
  overlayAtPoint(point: MapPoint): Promise<string>
  /** The full place behind a tapped map feature (`MapFeatureEvent.id`). */
  mapItemForFeature(id: string): Promise<MapItem>
  /**
   * A method only the active engine has, such as Google's
   * `streetView.open`: `command` names it, `argsJson` is its arguments as
   * JSON, and the promise resolves with the result as JSON (`null` for
   * none). Rejects when the engine does not know the command.
   */
  providerCommand(command: string, argsJson: string): Promise<string>
}

export type MunimMapView = HybridView<
  MunimMapViewProps,
  MunimMapViewMethods,
  { ios: 'swift'; android: 'kotlin' }
>
