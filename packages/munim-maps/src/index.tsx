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
  MapModelLayerMethods,
  MapModelLayerProps,
  MapModelLighting,
  MapModelShape,
  NativeMapModel,
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
  /** Soft round shadow on the ground. Default true. */
  groundShadow?: boolean
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

function resolveUri(source: MapModel['source']): string {
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
  const uri = resolveUri(model.source)
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
    emissive: model.emissive ?? false,
    spinDegreesPerSecond: model.spinDegreesPerSecond ?? 0,
    playAnimations: model.playAnimations ?? true,
    screenSize: model.screenSize ?? 0,
    groundShadow: model.groundShadow ?? true,
    visible: model.visible ?? true,
  }
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
  MapCamera,
  MapColorScheme,
  MapElevation,
  MapModelLighting,
  MapModelShape,
  MapStyle,
  NativeMapModel,
}
