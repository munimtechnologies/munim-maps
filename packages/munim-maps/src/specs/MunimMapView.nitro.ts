import type {
  HybridView,
  HybridViewMethods,
  HybridViewProps,
} from 'react-native-nitro-modules'
import type {
  MapAlignmentReport,
  MapModelLighting,
  NativeMapModel,
  NativeMapPath,
  NativeMapZone,
} from './MapModelLayer.nitro'
import type {
  MapAddress,
  MapFeatureEvent,
  MapPoint,
  MapPressEvent,
  MapRegion,
  MarkerDragEvent,
  NativeCircle,
  NativeMarker,
  NativePolygon,
  NativePolyline,
  NativeTileOverlay,
  UserLocationEvent,
} from './MapFeatures.nitro'
import type { MapCoordinate } from './MapModelLayer.nitro'

export type MapStyle = 'standard' | 'muted' | 'hybrid' | 'imagery'
export type MapElevation = 'flat' | 'realistic'
export type MapColorScheme = 'system' | 'light' | 'dark'
export type MapCameraEasing = 'linear' | 'easeInOut'
export type UserTrackingMode = 'none' | 'follow' | 'follow-with-heading'

export interface EdgeInsets {
  top: number
  left: number
  bottom: number
  right: number
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
  models: NativeMapModel[]
  zones: NativeMapZone[]
  paths: NativeMapPath[]
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

  // Controls and behaviour.
  showsCompass: boolean
  showsScale: boolean
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
  onMarkerDragStart?: (event: MarkerDragEvent) => void
  onMarkerDragEnd?: (event: MarkerDragEvent) => void
  onUserLocationChange?: (location: UserLocationEvent) => void
  onMapFeaturePress?: (feature: MapFeatureEvent) => void
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
}

export type MunimMapView = HybridView<
  MunimMapViewProps,
  MunimMapViewMethods,
  { ios: 'swift' }
>
