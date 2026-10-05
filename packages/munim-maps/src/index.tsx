import { forwardRef, useMemo } from 'react'
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
  type HybridRef,
} from 'react-native-nitro-modules'
import MapModelLayerConfig from '../nitrogen/generated/shared/json/MapModelLayerConfig.json'
import MunimMapViewConfig from '../nitrogen/generated/shared/json/MunimMapViewConfig.json'
import type {
  MapAlignmentReport,
  MapCoordinate,
  MapModelLayerMethods,
  MapModelLayerProps,
  MapModelLighting,
  MapModelShape,
  NativeMapModel,
  NativeMapZone,
} from './specs/MapModelLayer.nitro'
import type {
  MapCamera,
  MapColorScheme,
  MapElevation,
  MapStyle,
  MunimMapViewMethods,
  MunimMapViewProps,
} from './specs/MunimMapView.nitro'

/** A 3D model placed on the map. Only `id` and `coordinate` are required. */
export interface MapModel {
  id: string
  coordinate: { latitude: number; longitude: number }
  /** Metres above the ground. Default 0. */
  altitude?: number
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

/** True where munim-maps can draw models (iOS). */
export const isSupported = Platform.OS === 'ios'

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
    heading: model.heading ?? 0,
    scale: model.scale ?? 1,
    uri,
    shape: uri ? 'none' : (model.shape ?? 'box'),
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
  /** `testID` of the map to draw over. Default: the nearest map on screen. */
  mapTestID?: string
  lighting?: MapModelLighting
  /** Hide models while the camera is farther than this, in metres. Default 50 km. */
  maxCameraDistance?: number
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
        mapTestID={props.mapTestID ?? ''}
        lighting={props.lighting ?? 'auto'}
        maxCameraDistance={props.maxCameraDistance ?? 50_000}
        onModelPress={onModelPress}
        onAttachChange={onAttachChange}
        onError={onError}
        hybridRef={hybridRef}
      />
    </View>
  )
})

export interface MunimMapViewProperties {
  models?: MapModel[]
  zones?: MapZone[]
  initialCamera: MapCamera
  mapStyle?: MapStyle
  elevation?: MapElevation
  colorScheme?: MapColorScheme
  showsBuildings?: boolean
  showsUserLocation?: boolean
  lighting?: MapModelLighting
  maxCameraDistance?: number
  onModelPress?: (id: string) => void
  onCameraChange?: (camera: MapCamera) => void
  onError?: (message: string) => void
  style?: StyleProp<ViewStyle>
}

/** A MapKit map with models built in. iOS only; renders nothing elsewhere. */
export const MunimMapView = forwardRef<MunimMapViewRef, MunimMapViewProperties>(
  function MunimMapViewComponent(props, ref) {
    const models = useNativeModels(props.models)
    const zones = useNativeZones(props.zones)
    const onModelPress = useCallbackProp(props.onModelPress)
    const onCameraChange = useCallbackProp(props.onCameraChange)
    const onError = useCallbackProp(props.onError)
    const hybridRef = useMemo(
      () =>
        callback((instance: MunimMapViewRef) => {
          if (typeof ref === 'function') ref(instance)
          else if (ref) ref.current = instance
        }),
      [ref]
    )
    if (!isSupported) return null
    return (
      <NativeMunimMapView
        style={props.style}
        models={models}
        zones={zones}
        initialCamera={props.initialCamera}
        mapStyle={props.mapStyle ?? 'standard'}
        elevation={props.elevation ?? 'realistic'}
        colorScheme={props.colorScheme ?? 'system'}
        showsBuildings={props.showsBuildings ?? true}
        showsUserLocation={props.showsUserLocation ?? false}
        lighting={props.lighting ?? 'auto'}
        maxCameraDistance={props.maxCameraDistance ?? 50_000}
        onModelPress={onModelPress}
        onCameraChange={onCameraChange}
        onError={onError}
        hybridRef={hybridRef}
      />
    )
  }
)

export type {
  MapAlignmentReport,
  MapCoordinate,
  MapCamera,
  MapColorScheme,
  MapElevation,
  MapModelLighting,
  MapModelShape,
  MapStyle,
  NativeMapModel,
  NativeMapZone,
}
