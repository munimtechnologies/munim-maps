import { forwardRef, useMemo, type ReactNode } from 'react'
import {
  Platform,
  StyleSheet,
  View,
  type StyleProp,
  type ViewStyle,
} from 'react-native'
import {
  callback,
  getHostComponent,
  NitroModules,
  type HybridRef,
} from 'react-native-nitro-modules'
import MapModelLayerConfig from '../nitrogen/generated/shared/json/MapModelLayerConfig.json'
import MunimMapViewConfig from '../nitrogen/generated/shared/json/MunimMapViewConfig.json'
import type {
  MapAlignmentReport,
  MapAltitudeReference,
  MapCoordinate,
  MapPathPoint,
  MapModelLayerMethods,
  MapModelLayerProps,
  MapModelLighting,
  MapModelShape,
  MapModelEffect,
  MapOcclusion,
  MotionKeyframe,
  NativeMapModel,
  NativeMapPath,
  NativeMapZone,
} from './specs/MapModelLayer.nitro'
import type { MunimTerrain } from './specs/MunimTerrain.nitro'
import type {
  EdgeInsets,
  MapCamera,
  MapCameraEasing,
  CameraKeyframe,
  MapColorScheme,
  MapElevation,
  MapStyle,
  MunimMapViewMethods,
  MunimMapViewProps,
  UserTrackingMode,
  FeatureVisibility,
  SelectionAccessory,
} from './specs/MunimMapView.nitro'
import type {
  CalloutAccessoryEvent,
  ClusterPressEvent,
  MapItem,
  MarkerCollisionMode,
  LineCap,
  LineJoin,
  OverlayLevel,
  OverlayPressEvent,
  MapAddress,
  MapFeatureEvent,
  MapPoint,
  MapPressEvent,
  MapRegion,
  MarkerBadgePosition,
  MarkerDragEvent,
  MarkerStyle,
  UserLocationEvent,
} from './specs/MapFeatures.nitro'
import { pointsOfInterestFilter } from './services'
import {
  defaultProvider,
  providerOptionsJson,
  type MapProvider,
  type ProviderOptionProps,
} from './providers'
import {
  toNativeClusterStyle,
  toNativeCircle,
  toNativeMarker,
  toNativePolygon,
  toNativePolyline,
  toNativeTileOverlay,
  type CalloutAccessory,
  type MapClusterStyle,
  type MarkerDisplayPriority,
  type MapCircle,
  type MapMarker,
  type MapPolygon,
  type MapPolyline,
  type MapTileOverlay,
} from './features'

/** A 3D model placed on the map. Only `id` and `coordinate` are required. */
export interface MapModel {
  id: string
  coordinate: { latitude: number; longitude: number }
  /** Metres above the ground, or above sea level with `altitudeReference: 'sea'`. Default 0. */
  altitude?: number
  /**
   * What `altitude` (and `motion` keyframe altitudes) are measured from.
   * `'ground'` (default): metres above the ground under the model. `'sea'`:
   * metres above sea level, such as a phone's GPS altitude; munim-maps looks
   * up the ground height there from terrain tiles (see `groundElevation`),
   * takes it off, and shows the model once the tile has loaded.
   */
  altitudeReference?: MapAltitudeReference
  /** Degrees clockwise from north. Default 0. */
  heading?: number
  /** Default 1. */
  scale?: number
  /**
   * A USDZ, USD, SCN or OBJ file: a `require()`d asset, a `file://` path or
   * an `http(s)://` URL. Leave out to draw `shape` instead.
   */
  source?: number | string | { uri: string }
  /** Built-in shape used when there is no `source`. Default `box`. */
  shape?: Exclude<MapModelShape, 'none'>
  /** Shape size in metres. Default 10 x 10 x 10. */
  size?: { width?: number; height?: number; length?: number }
  /** Shape colour, `#RRGGBB` or `#RRGGBBAA`. Default `#0A84FF`. */
  color?: string
  /**
   * Recolours an asset's paint (materials named `paint…`), so one model
   * file can come in any colour. Default: the file's colours.
   */
  tint?: string
  /** Makes the shape glow. Default false. */
  emissive?: boolean
  /** Turns the model around its vertical axis. Default 0. */
  spinDegreesPerSecond?: number
  /** Loops animations embedded in a USDZ file. Default true. */
  playAnimations?: boolean
  /**
   * Keeps the model this many points tall whatever the zoom, like a marker.
   * Default 0, which keeps its real size in metres.
   */
  screenSize?: number
  /** Soft round shadow on the ground. Default true, false for images. */
  groundShadow?: boolean
  /**
   * A PNG or JPEG drawn as a round picture that always faces the camera,
   * such as an avatar. Replaces `source` and `shape`. `screenSize` sets its
   * size in points (default 44).
   */
  image?: number | string | { uri: string }
  /** Ring around `image`. */
  imageBorder?: { color: string; width?: number }
  /** Short text in a pill under `image`, such as `4F`. */
  badge?: string
  /**
   * A thin line from the ground up to the model, so a floating model (a
   * friend on the 8th floor) shows the spot below it. `true` or a colour.
   */
  stem?: boolean | string
  /**
   * Raises the model this many points above `altitude` at any zoom, for
   * example to float an avatar over a vehicle model. Default 0.
   */
  lift?: number
  /** Text in a pill floating above the model, such as a name. */
  label?: string
  /**
   * A particle effect: `exhaust` is an engine plume pointing down from the
   * model's base, sized to the model (a rocket launching); `smoke` is a
   * billowing cloud on the ground, `size.width` metres across and
   * `size.height` tall (use it without `source`); `contrail` leaves two
   * white trails in the sky behind a model moving with `motion`. Default none.
   */
  effect?: 'exhaust' | 'smoke' | 'contrail'
  /** 0...1: throttle the effect up, or let the smoke clear. Default 1. */
  effectIntensity?: number
  /**
   * Moves the model along keyframes on the native frame clock, so motion
   * stays smooth whatever JavaScript is doing. `t` is seconds after `start`
   * (seconds since 1970, `Date.now() / 1000`); between keyframes the model
   * moves in a straight line and, unless a keyframe sets `heading`, faces
   * where it is going. `coordinate` is ignored while `motion` is set.
   */
  /**
   * Draws nothing but hides other models behind it, like buildings do with
   * `occlusion="buildings"`: stand-ins for things on the map, such as a
   * bridge's railings and towers. Usually a `box` shape. Default false.
   */
  occluder?: boolean
  /**
   * Where the effect starts, in the model's own metres: `[x, y, z]` with x to
   * the right, y up and z towards the back, the model's base centred on the
   * origin. For `contrail`, one trail per point (one per engine).
   */
  effectOrigins?: [number, number, number][]
  motion?: {
    keyframes: {
      t: number
      coordinate: { latitude: number; longitude: number }
      altitude?: number
      heading?: number
    }[]
    start: number
    loop?: boolean
  }
  /** Default true. */
  visible?: boolean
}

/**
 * A see-through wall standing on a zone's outline and fading out towards the
 * top. Give either `polygon` or `circle`.
 */
export interface MapZone {
  id: string
  polygon?: { latitude: number; longitude: number }[]
  circle?: { center: { latitude: number; longitude: number }; radius: number }
  /** Wall height in metres. Default 40. */
  height?: number
  /**
   * `#RRGGBB` or `#RRGGBBAA`. The alpha sets how see-through the wall is;
   * the top and bottom edges are solid. Default `#0A84FF40`.
   */
  color?: string
  /** Default true. */
  visible?: boolean
}

export type MapModelLayerRef = HybridRef<
  MapModelLayerProps,
  MapModelLayerMethods
>
export type MunimMapViewRef = HybridRef<MunimMapViewProps, MunimMapViewMethods>

const NativeMapModelLayer = getHostComponent<
  MapModelLayerProps,
  MapModelLayerMethods
>('MapModelLayer', () => MapModelLayerConfig)

const NativeMunimMapView = getHostComponent<
  MunimMapViewProps,
  MunimMapViewMethods
>('MunimMapView', () => MunimMapViewConfig)

/** True where munim-maps has native code (iOS and Android). */
export const isSupported = Platform.OS === 'ios' || Platform.OS === 'android'

function resolveUri(source: MapModel['source'] | MapModel['image']): string {
  if (source == null) return ''
  if (typeof source === 'string') return source
  if (typeof source === 'number') {
    // Loaded lazily so the package works without Image in tests.
    const { Image } = require('react-native') as typeof import('react-native')
    return Image.resolveAssetSource(source)?.uri ?? ''
  }
  return source.uri
}

export function toNativeModel(model: MapModel): NativeMapModel {
  const imageUri = resolveUri(model.image)
  const uri = imageUri ? '' : resolveUri(model.source)
  return {
    id: model.id,
    latitude: model.coordinate.latitude,
    longitude: model.coordinate.longitude,
    altitude: model.altitude ?? 0,
    altitudeReference: model.altitudeReference ?? 'ground',
    heading: model.heading ?? 0,
    scale: model.scale ?? 1,
    uri,
    shape: uri
      ? 'none'
      : (model.shape ?? (model.effect === 'smoke' ? 'none' : 'box')),
    width: model.size?.width ?? 10,
    height: model.size?.height ?? 10,
    length: model.size?.length ?? 10,
    color: model.color ?? '#0A84FF',
    tintColor: model.tint ?? '',
    emissive: model.emissive ?? false,
    spinDegreesPerSecond: model.spinDegreesPerSecond ?? 0,
    playAnimations: model.playAnimations ?? true,
    screenSize: model.screenSize ?? (imageUri ? 44 : 0),
    groundShadow: model.groundShadow ?? !imageUri,
    imageUri,
    imageBorderColor: model.imageBorder?.color ?? '',
    imageBorderWidth: model.imageBorder?.width ?? 3,
    imageBadge: model.badge ?? '',
    liftPoints: model.lift ?? 0,
    label: model.label ?? '',
    stem: model.stem != null && model.stem !== false,
    stemColor: typeof model.stem === 'string' ? model.stem : '#FFFFFF',
    effect: model.effect ?? 'none',
    effectIntensity: model.effectIntensity ?? 1,
    motion: (model.motion?.keyframes ?? []).map((k) => ({
      t: k.t,
      latitude: k.coordinate.latitude,
      longitude: k.coordinate.longitude,
      altitude: k.altitude ?? 0,
      heading: k.heading ?? -1,
    })),
    motionStart: model.motion?.start ?? 0,
    motionLoop: model.motion?.loop ?? false,
    occluder: model.occluder ?? false,
    effectOrigins: (model.effectOrigins ?? [])
      .map((p) => p.join(','))
      .join(';'),
    visible: model.visible ?? true,
  }
}

const EARTH_RADIUS_METERS = 6_371_008.8

/** Outline of a circle on the ground, as `segments` points. */
export function circleToPolygon(
  center: { latitude: number; longitude: number },
  radiusMeters: number,
  segments = 72
): MapCoordinate[] {
  const lat = (center.latitude * Math.PI) / 180
  const lon = (center.longitude * Math.PI) / 180
  const angular = radiusMeters / EARTH_RADIUS_METERS
  const points: MapCoordinate[] = []
  for (let i = 0; i < segments; i += 1) {
    const bearing = (i / segments) * 2 * Math.PI
    const pointLat = Math.asin(
      Math.sin(lat) * Math.cos(angular) +
        Math.cos(lat) * Math.sin(angular) * Math.cos(bearing)
    )
    const pointLon =
      lon +
      Math.atan2(
        Math.sin(bearing) * Math.sin(angular) * Math.cos(lat),
        Math.cos(angular) - Math.sin(lat) * Math.sin(pointLat)
      )
    points.push({
      latitude: (pointLat * 180) / Math.PI,
      longitude: (pointLon * 180) / Math.PI,
    })
  }
  return points
}

export function toNativeZone(zone: MapZone): NativeMapZone {
  const points = zone.polygon
    ? zone.polygon.map((p) => ({
        latitude: p.latitude,
        longitude: p.longitude,
      }))
    : zone.circle
      ? circleToPolygon(zone.circle.center, zone.circle.radius)
      : []
  return {
    id: zone.id,
    points,
    height: zone.height ?? 40,
    color: zone.color ?? '#0A84FF40',
    visible: zone.visible ?? true,
  }
}

function useNativeZones(zones: MapZone[] | undefined): NativeMapZone[] {
  return useMemo(() => (zones ?? []).map(toNativeZone), [zones])
}

/**
 * A line drawn in 3D by munim-maps: it can sit above the ground (a flight
 * path, an orbit) and follows the globe, where MapKit's polylines stay flat.
 */
export interface MapPath {
  id: string
  coordinates: { latitude: number; longitude: number; altitude?: number }[]
  /** `#RRGGBB` or `#RRGGBBAA`. Default white. */
  color?: string
  /** Width in points. Default 2. */
  width?: number
  /** Join the last point back to the first. Default false. */
  closed?: boolean
  /**
   * What the points' `altitude` is measured from: `'ground'` (default) or
   * `'sea'` level, as on `MapModel`.
   */
  altitudeReference?: MapAltitudeReference
  /** Default true. */
  visible?: boolean
}

export function toNativePath(path: MapPath): NativeMapPath {
  return {
    id: path.id,
    points: path.coordinates.map((c) => ({
      latitude: c.latitude,
      longitude: c.longitude,
      altitude: c.altitude ?? 0,
    })),
    color: path.color ?? '#FFFFFF',
    width: path.width ?? 2,
    closed: path.closed ?? false,
    altitudeReference: path.altitudeReference ?? 'ground',
    visible: path.visible ?? true,
  }
}

let terrain: MunimTerrain | undefined

/**
 * Ground height above sea level, in metres, at each coordinate: the same
 * terrain munim-maps uses for `altitudeReference: 'sea'`. From the free
 * public Terrarium elevation tiles on AWS (about 7-10 m per sample, cached
 * on the device). Negative under the sea (the sea floor) and in places below
 * sea level. Rejects if a tile cannot be downloaded, and on Android.
 */
export function groundElevation(
  coordinates: { latitude: number; longitude: number }[]
): Promise<number[]> {
  if (!isSupported) {
    return Promise.reject(new Error('munim-maps: groundElevation is iOS only'))
  }
  terrain ??= NitroModules.createHybridObject<MunimTerrain>('MunimTerrain')
  return terrain.groundElevation(
    coordinates.map((c) => ({ latitude: c.latitude, longitude: c.longitude }))
  )
}

function useNativePaths(paths: MapPath[] | undefined): NativeMapPath[] {
  return useMemo(() => (paths ?? []).map(toNativePath), [paths])
}

function useNativeModels(models: MapModel[] | undefined): NativeMapModel[] {
  return useMemo(() => (models ?? []).map(toNativeModel), [models])
}

function useCallbackProp<A extends unknown[]>(
  fn: ((...args: A) => void) | undefined
) {
  return useMemo(() => (fn ? callback(fn) : undefined), [fn])
}

export interface MapModelLayerProperties {
  models: MapModel[]
  zones?: MapZone[]
  /** Lines in 3D, above the ground and on the globe. */
  paths?: MapPath[]
  /**
   * `'buildings'` hides models behind buildings, which MapKit cannot do on
   * its own. Footprints and heights come from vector tiles around the camera
   * (OpenStreetMap data from OpenFreeMap by default, so the visible area is
   * requested from that server). Avatars, labels and stems stay visible.
   * Default `'none'`.
   */
  occlusion?: MapOcclusion
  /** `{z}/{x}/{y}` vector tiles with an OpenMapTiles `building` layer. Default OpenFreeMap. */
  buildingTilesUrl?: string
  /**
   * Keep models, paths and zones whose `altitude` is above the ground on
   * MapKit's 3D terrain, which it draws for satellite imagery (`hybrid`,
   * `imagery`) with realistic elevation; otherwise they sit at the height of
   * the ground at the camera's centre. MapKit does not share terrain
   * heights, so they come from public elevation tiles (the area is requested
   * from AWS). Models with `altitudeReference: 'sea'` always follow the
   * terrain. Default false.
   */
  followTerrain?: boolean
  /** `testID` of the map to draw over. Default: the nearest map on screen. */
  mapTestID?: string
  lighting?: MapModelLighting
  /** Hide models while the camera is farther than this, in metres. Default 50 km. */
  maxCameraDistance?: number
  /**
   * Keep the map on realistic elevation: 3D terrain and landmarks up close,
   * like Apple Maps, even over a map library that sets a flat style
   * (react-native-maps' `standard`). Default false.
   */
  realisticElevation?: boolean
  /**
   * Show the standard style as a globe when zoomed far out, like Apple
   * Maps (MapKit only does this for satellite imagery). Uses a MapKit switch
   * that is not public API: it may stop working in an iOS update (the map
   * stays flat) and App Review may reject an app for it. Default false.
   */
  globe?: boolean
  onModelPress?: (id: string) => void
  onAttachChange?: (attached: boolean) => void
  onError?: (message: string) => void
  /** Defaults to filling the parent, the same as the map. */
  style?: StyleProp<ViewStyle>
}

/**
 * Draws models over an existing MapKit map, such as react-native-maps'
 * `MapView` on iOS. Render it right after the map, covering it. Touches pass
 * through to the map. Renders nothing on Android.
 */
export const MapModelLayer = forwardRef<
  MapModelLayerRef,
  MapModelLayerProperties
>(function MapModelLayerComponent(props, ref) {
  const models = useNativeModels(props.models)
  const zones = useNativeZones(props.zones)
  const paths = useNativePaths(props.paths)
  const onModelPress = useCallbackProp(props.onModelPress)
  const onAttachChange = useCallbackProp(props.onAttachChange)
  const onError = useCallbackProp(props.onError)
  const hybridRef = useMemo(
    () =>
      callback((instance: MapModelLayerRef) => {
        if (typeof ref === 'function') ref(instance)
        else if (ref) ref.current = instance
      }),
    [ref]
  )
  if (!isSupported) return null
  return (
    <View pointerEvents="none" style={[StyleSheet.absoluteFill, props.style]}>
      <NativeMapModelLayer
        style={StyleSheet.absoluteFill}
        models={models}
        zones={zones}
        paths={paths}
        occlusion={props.occlusion ?? 'none'}
        buildingTilesUrl={props.buildingTilesUrl ?? ''}
        followTerrain={props.followTerrain ?? false}
        mapTestID={props.mapTestID ?? ''}
        lighting={props.lighting ?? 'auto'}
        maxCameraDistance={props.maxCameraDistance ?? 50_000}
        realisticElevation={props.realisticElevation ?? false}
        globe={props.globe ?? false}
        onModelPress={onModelPress}
        onAttachChange={onAttachChange}
        onError={onError}
        hybridRef={hybridRef}
      />
    </View>
  )
})

export interface MunimMapViewProperties extends ProviderOptionProps {
  /**
   * The map engine: `'mapkit'` (Apple Maps, iOS), `'google'`, `'mapbox'`,
   * `'maplibre'` (open maps: OpenStreetMap data, no key) or `'cesium'`.
   * Default `'mapkit'` on iOS; on Android `'google'` when its engine is
   * built in, else `'maplibre'` (`configureMunimMaps` changes the default).
   * Engines are opt-in at build time; one that is not built in shows a
   * placeholder and reports `onError`. Options only one engine reads go in
   * that engine's prop (`google={{ mapId }}`, `mapbox={{ projection }}`…).
   */
  provider?: MapProvider
  /**
   * Style URL for MapLibre and Mapbox (style JSON, `mapbox://styles/…`).
   * Default OpenFreeMap Liberty for MapLibre, Mapbox Standard for Mapbox.
   */
  styleUrl?: string
  initialCamera: MapCamera
  // 3D
  models?: MapModel[]
  zones?: MapZone[]
  /** Lines in 3D, above the ground and on the globe. */
  paths?: MapPath[]
  /**
   * `'buildings'` hides models behind buildings, which MapKit cannot do on
   * its own. Footprints and heights come from vector tiles around the camera
   * (OpenStreetMap data from OpenFreeMap by default, so the visible area is
   * requested from that server). Avatars, labels and stems stay visible.
   * Default `'none'`.
   */
  occlusion?: MapOcclusion
  /** `{z}/{x}/{y}` vector tiles with an OpenMapTiles `building` layer. Default OpenFreeMap. */
  buildingTilesUrl?: string
  /**
   * Keep models, paths and zones whose `altitude` is above the ground on
   * MapKit's 3D terrain, which it draws for satellite imagery (`hybrid`,
   * `imagery`) with realistic elevation; otherwise they sit at the height of
   * the ground at the camera's centre. MapKit does not share terrain
   * heights, so they come from public elevation tiles (the area is requested
   * from AWS). Models with `altitudeReference: 'sea'` always follow the
   * terrain. Default false.
   */
  followTerrain?: boolean
  lighting?: MapModelLighting
  maxCameraDistance?: number
  // Map features
  markers?: MapMarker[]
  polylines?: MapPolyline[]
  polygons?: MapPolygon[]
  circles?: MapCircle[]
  tileOverlays?: MapTileOverlay[]
  /** How clusters of markers (`clusteringId`) look. Default MapKit's. */
  clusterStyles?: MapClusterStyle[]
  // Look
  mapStyle?: MapStyle
  elevation?: MapElevation
  /**
   * Show the standard style as a globe when zoomed far out, like Apple
   * Maps (MapKit only does this for satellite imagery). Uses a MapKit switch
   * that is not public API: it may stop working in an iOS update (the map
   * stays flat) and App Review may reject an app for it. Default false.
   */
  globe?: boolean
  colorScheme?: MapColorScheme
  showsBuildings?: boolean
  showsUserLocation?: boolean
  /** Shorthand for `compassVisibility` `'adaptive'` (true, default) or `'hidden'`. */
  showsCompass?: boolean
  /** Shorthand for `scaleVisibility` `'adaptive'` (true) or `'hidden'` (default). */
  showsScale?: boolean
  /**
   * The compass, top right: `'adaptive'` shows it while the map is rotated
   * (MapKit's default), `'visible'` always, `'hidden'` never.
   */
  compassVisibility?: FeatureVisibility
  /** The scale legend, top left: `'adaptive'` shows it while zooming. */
  scaleVisibility?: FeatureVisibility
  /**
   * MapKit's button that cycles `userTrackingMode` (none, follow, follow
   * with heading), top right. Use `onUserTrackingModeChange` to keep your
   * state in step. Default false.
   */
  showsUserTrackingButton?: boolean
  /** MapKit's 2D/3D button, top right. iOS 17+. Default `'hidden'`. */
  pitchButtonVisibility?: FeatureVisibility
  /**
   * A name for this map, so `MapCompass`, `MapScale` and
   * `MapUserTrackingButton` placed anywhere else can drive it.
   */
  mapScope?: string
  showsTraffic?: boolean
  /**
   * `'all'`, `'none'`, or the categories to show: `MKPOICategory…` values or
   * their short names (`'cafe'`, `'evCharger'`). Default `'all'`.
   */
  pointsOfInterest?: 'all' | 'none' | string[]
  /**
   * MapKit's user tracking, exactly like `MKMapView.userTrackingMode`:
   * `'follow'` keeps the map on the user, `'followWithHeading'` also turns
   * it with the device and shows the heading beam. MapKit owns the
   * following (nothing recentres from JavaScript, so it never fights the
   * user) and drops back to `'none'` when the user pans or zooms away:
   * handle `onUserTrackingModeChange` and store the mode in state, so
   * setting it again re-enables tracking. Asks for when-in-use location
   * access if needed (add `NSLocationWhenInUseUsageDescription`).
   */
  userTrackingMode?: UserTrackingMode | 'follow-with-heading'
  // Gestures and limits
  zoomEnabled?: boolean
  scrollEnabled?: boolean
  rotateEnabled?: boolean
  pitchEnabled?: boolean
  /** Closest and farthest camera distance, in metres. */
  cameraDistanceRange?: { min?: number; max?: number }
  /** Keep the camera's centre inside this region. */
  cameraBoundary?: MapRegion
  /** Space covered by your own UI. */
  mapPadding?: Partial<EdgeInsets>
  /** Places on Apple's map that can be tapped (`onMapFeaturePress`). */
  selectableMapFeatures?: (
    'pointsOfInterest' | 'territories' | 'physicalFeatures'
  )[]
  /**
   * What tapping a place on Apple's map shows, iOS 18+: Apple's place card
   * as a `'callout'` (`'calloutCompact'`, `'calloutFull'`), a `'sheet'`, or
   * whichever suits (`'automatic'`), or an `'openInMaps'` button. Default
   * `'none'` (handle `onMapFeaturePress` yourself). Needs
   * `selectableMapFeatures`.
   */
  selectionAccessory?: SelectionAccessory
  // Events
  onModelPress?: (id: string) => void
  onCameraChange?: (camera: MapCamera) => void
  onCameraMove?: (camera: MapCamera) => void
  onMapReady?: () => void
  onPress?: (event: MapPressEvent) => void
  onLongPress?: (event: MapPressEvent) => void
  onMarkerPress?: (id: string) => void
  onMarkerDeselect?: (id: string) => void
  onCalloutPress?: (id: string) => void
  /** A callout's left or right accessory was tapped. */
  onCalloutAccessoryPress?: (event: CalloutAccessoryEvent) => void
  /**
   * A cluster was tapped. `markerIds` lists its markers, comma-separated
   * (`fitToMarkers(event.markerIds, …)` zooms in on them).
   */
  onClusterPress?: (event: ClusterPressEvent) => void
  /**
   * A tappable polyline, polygon or circle was tapped (the topmost). Taken
   * instead of `onPress`. Overlays are only hit-tested while this is set.
   */
  onOverlayPress?: (event: OverlayPressEvent) => void
  onMarkerDragStart?: (event: MarkerDragEvent) => void
  onMarkerDragEnd?: (event: MarkerDragEvent) => void
  onUserLocationChange?: (location: UserLocationEvent) => void
  /**
   * MapKit changed the tracking mode: the user panned or zoomed away (to
   * `'none'`), used the tracking button, or a camera move ended following.
   */
  onUserTrackingModeChange?: (mode: UserTrackingMode) => void
  onMapFeaturePress?: (feature: MapFeatureEvent) => void
  onError?: (message: string) => void
  /**
   * Events only the active engine has, such as MapLibre's `styleLoaded`,
   * `idle` or `offlineProgress` (`MapLibreEventName`). `payload` is the
   * event's data, parsed from JSON.
   */
  onProviderEvent?: (event: { name: string; payload: unknown }) => void
  style?: StyleProp<ViewStyle>
  /** `MarkerView`s: React Native views as markers. */
  children?: ReactNode
}

const NO_REGION: MapRegion = {
  latitude: 0,
  longitude: 0,
  latitudeDelta: 0,
  longitudeDelta: 0,
}

function insets(padding?: Partial<EdgeInsets>): EdgeInsets {
  return {
    top: padding?.top ?? 0,
    left: padding?.left ?? 0,
    bottom: padding?.bottom ?? 0,
    right: padding?.right ?? 0,
  }
}

function useMapped<T, N>(items: T[] | undefined, map: (item: T) => N): N[] {
  // eslint-disable-next-line react-hooks/exhaustive-deps
  return useMemo(() => (items ?? []).map(map), [items])
}

/**
 * A map with models built in, drawn by the engine in `provider` (MapKit by
 * default on iOS, MapLibre or Google Maps on Android).
 */
export const MunimMapView = forwardRef<MunimMapViewRef, MunimMapViewProperties>(
  function MunimMapViewComponent(props, ref) {
    const models = useNativeModels(props.models)
    const zones = useNativeZones(props.zones)
    const paths = useNativePaths(props.paths)
    const markers = useMapped(props.markers, toNativeMarker)
    const polylines = useMapped(props.polylines, toNativePolyline)
    const polygons = useMapped(props.polygons, toNativePolygon)
    const circles = useMapped(props.circles, toNativeCircle)
    const tileOverlays = useMapped(props.tileOverlays, toNativeTileOverlay)
    const onModelPress = useCallbackProp(props.onModelPress)
    const onCameraChange = useCallbackProp(props.onCameraChange)
    const onCameraMove = useCallbackProp(props.onCameraMove)
    const onMapReady = useCallbackProp(props.onMapReady)
    const onPress = useCallbackProp(props.onPress)
    const onLongPress = useCallbackProp(props.onLongPress)
    const onMarkerPress = useCallbackProp(props.onMarkerPress)
    const onMarkerDeselect = useCallbackProp(props.onMarkerDeselect)
    const onCalloutPress = useCallbackProp(props.onCalloutPress)
    const onCalloutAccessoryPress = useCallbackProp(
      props.onCalloutAccessoryPress
    )
    const onClusterPress = useCallbackProp(props.onClusterPress)
    const onOverlayPress = useCallbackProp(props.onOverlayPress)
    const clusterStyles = useMapped(props.clusterStyles, toNativeClusterStyle)
    const onMarkerDragStart = useCallbackProp(props.onMarkerDragStart)
    const onMarkerDragEnd = useCallbackProp(props.onMarkerDragEnd)
    const onUserLocationChange = useCallbackProp(props.onUserLocationChange)
    const onUserTrackingModeChange = useCallbackProp(
      props.onUserTrackingModeChange
    )
    const onMapFeaturePress = useCallbackProp(props.onMapFeaturePress)
    const onError = useCallbackProp(props.onError)
    const providerEvent = props.onProviderEvent
    const onProviderEvent = useMemo(
      () =>
        providerEvent
          ? callback((name: string, payload: string) => {
              let data: unknown = null
              try {
                data = payload ? JSON.parse(payload) : null
              } catch {
                data = payload
              }
              providerEvent({ name, payload: data })
            })
          : undefined,
      [providerEvent]
    )
    const pointsOfInterest = pointsOfInterestFilter(props.pointsOfInterest)
    const hybridRef = useMemo(
      () =>
        callback((instance: MunimMapViewRef) => {
          if (typeof ref === 'function') ref(instance)
          else if (ref) ref.current = instance
        }),
      [ref]
    )
    const provider = props.provider ?? defaultProvider()
    if (!isSupported) return null
    return (
      <NativeMunimMapView
        style={props.style}
        provider={provider}
        styleUrl={props.styleUrl ?? ''}
        providerOptions={providerOptionsJson(provider, props)}
        models={models}
        zones={zones}
        paths={paths}
        occlusion={props.occlusion ?? 'none'}
        buildingTilesUrl={props.buildingTilesUrl ?? ''}
        followTerrain={props.followTerrain ?? false}
        initialCamera={props.initialCamera}
        mapStyle={props.mapStyle ?? 'standard'}
        elevation={props.elevation ?? 'realistic'}
        globe={props.globe ?? false}
        colorScheme={props.colorScheme ?? 'system'}
        showsBuildings={props.showsBuildings ?? true}
        showsUserLocation={props.showsUserLocation ?? false}
        lighting={props.lighting ?? 'auto'}
        maxCameraDistance={props.maxCameraDistance ?? 50_000}
        markers={markers}
        polylines={polylines}
        polygons={polygons}
        circles={circles}
        tileOverlays={tileOverlays}
        clusterStyles={clusterStyles}
        selectionAccessory={props.selectionAccessory ?? 'none'}
        compassVisibility={
          props.compassVisibility ??
          (props.showsCompass === false ? 'hidden' : 'adaptive')
        }
        scaleVisibility={
          props.scaleVisibility ?? (props.showsScale ? 'adaptive' : 'hidden')
        }
        showsUserTrackingButton={props.showsUserTrackingButton ?? false}
        pitchButtonVisibility={props.pitchButtonVisibility ?? 'hidden'}
        mapScope={props.mapScope ?? ''}
        showsTraffic={props.showsTraffic ?? false}
        pointsOfInterest={pointsOfInterest}
        userTrackingMode={
          props.userTrackingMode === 'follow-with-heading'
            ? 'followWithHeading'
            : (props.userTrackingMode ?? 'none')
        }
        zoomEnabled={props.zoomEnabled ?? true}
        scrollEnabled={props.scrollEnabled ?? true}
        rotateEnabled={props.rotateEnabled ?? true}
        pitchEnabled={props.pitchEnabled ?? true}
        minCameraDistance={props.cameraDistanceRange?.min ?? 0}
        maxCameraDistanceLimit={props.cameraDistanceRange?.max ?? 0}
        cameraBoundary={props.cameraBoundary ?? NO_REGION}
        mapPadding={insets(props.mapPadding)}
        selectableMapFeatures={(props.selectableMapFeatures ?? []).join(',')}
        onModelPress={onModelPress}
        onCameraChange={onCameraChange}
        onCameraMove={onCameraMove}
        onMapReady={onMapReady}
        onPress={onPress}
        onLongPress={onLongPress}
        onMarkerPress={onMarkerPress}
        onMarkerDeselect={onMarkerDeselect}
        onCalloutPress={onCalloutPress}
        onCalloutAccessoryPress={onCalloutAccessoryPress}
        onClusterPress={onClusterPress}
        onOverlayPress={onOverlayPress}
        onMarkerDragStart={onMarkerDragStart}
        onMarkerDragEnd={onMarkerDragEnd}
        onUserLocationChange={onUserLocationChange}
        onUserTrackingModeChange={onUserTrackingModeChange}
        onMapFeaturePress={onMapFeaturePress}
        onError={onError}
        onProviderEvent={onProviderEvent}
        hybridRef={hybridRef}
      >
        {props.children}
      </NativeMunimMapView>
    )
  }
)

export * from './services'
export * from './openMapsServices'
export {
  maplibreCommands,
  type MapLibreCommands,
  type MapLibreEventName,
  type MapLibreFeature,
  type MapLibreLayer,
  type MapLibreOfflinePack,
  type MapLibreOrnament,
  type MapLibreSnapshotOptions,
  type MapLibreSource,
  type MapLibreStylePreset,
} from './providers/maplibre'
export {
  MAP_PROVIDERS,
  availableProviders,
  configureMunimMaps,
  defaultProvider,
  installedProviders,
  isProviderAvailable,
  type CesiumMapOptions,
  type GoogleMapOptions,
  type MapboxMapOptions,
  type MapKitMapOptions,
  type MapLibreMapOptions,
  type MapProvider,
  type MunimMapsConfiguration,
  type ProviderOptionProps,
} from './providers'
export { MarkerView, type MarkerViewProperties } from './MarkerView'
export {
  LookAroundView,
  type LookAroundViewProperties,
  type LookAroundBadgePosition,
} from './LookAroundView'

export {
  MapCompass,
  MapScale,
  MapUserTrackingButton,
  type MapControlProperties,
  type MapScaleAlignment,
} from './controls'

export {
  toNativeCircle,
  toNativeMarker,
  toNativePolygon,
  toNativePolyline,
  toNativeTileOverlay,
}
export type {
  CalloutAccessory,
  CalloutAccessoryEvent,
  ClusterPressEvent,
  MapClusterStyle,
  MapItem,
  LineJoin,
  OverlayLevel,
  OverlayPressEvent,
  MarkerCollisionMode,
  MarkerDisplayPriority,
  SelectionAccessory,
  EdgeInsets,
  LineCap,
  MapAddress,
  MapCircle,
  MapFeatureEvent,
  MapMarker,
  MapPoint,
  MapPolygon,
  MapPolyline,
  MapPressEvent,
  MapRegion,
  MapTileOverlay,
  MarkerBadgePosition,
  MarkerDragEvent,
  MarkerStyle,
  UserLocationEvent,
  UserTrackingMode,
  FeatureVisibility,
  MapAlignmentReport,
  MapAltitudeReference,
  MapCoordinate,
  MapPathPoint,
  MapCamera,
  MapCameraEasing,
  CameraKeyframe,
  MapColorScheme,
  MapElevation,
  MapModelLighting,
  MapModelShape,
  MapModelEffect,
  MapOcclusion,
  MapStyle,
  MotionKeyframe,
  NativeMapModel,
  NativeMapPath,
  NativeMapZone,
}
