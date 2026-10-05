import type {
  HybridView,
  HybridViewMethods,
  HybridViewProps,
} from 'react-native-nitro-modules'
import type {
  MapAlignmentReport,
  MapModelLighting,
  NativeMapModel,
} from './MapModelLayer.nitro'

export type MapStyle = 'standard' | 'muted' | 'hybrid' | 'imagery'
export type MapElevation = 'flat' | 'realistic'
export type MapColorScheme = 'system' | 'light' | 'dark'

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
  /** Applied once, when the map first appears. */
  initialCamera: MapCamera
  mapStyle: MapStyle
  elevation: MapElevation
  colorScheme: MapColorScheme
  showsBuildings: boolean
  showsUserLocation: boolean
  lighting: MapModelLighting
  maxCameraDistance: number
  onModelPress?: (id: string) => void
  /** Fires when the camera stops moving. */
  onCameraChange?: (camera: MapCamera) => void
  onError?: (message: string) => void
}

export interface MunimMapViewMethods extends HybridViewMethods {
  setCamera(camera: MapCamera, animated: boolean): void
  getCamera(): Promise<MapCamera>
  measureAlignment(): Promise<MapAlignmentReport>
}

export type MunimMapView = HybridView<
  MunimMapViewProps,
  MunimMapViewMethods,
  { ios: 'swift' }
>
