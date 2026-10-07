import { useMemo } from 'react'
import {
  Platform,
  StyleSheet,
  type StyleProp,
  type ViewStyle,
} from 'react-native'
import { getHostComponent } from 'react-native-nitro-modules'
import MapControlConfig from '../nitrogen/generated/shared/json/MapControlConfig.json'
import type {
  MapControlKind,
  MapControlMethods,
  MapControlProps,
  MapScaleAlignment,
} from './specs/MapControl.nitro'
import type { FeatureVisibility } from './specs/MunimMapView.nitro'

const NativeMapControl = getHostComponent<MapControlProps, MapControlMethods>(
  'MapControl',
  () => MapControlConfig
)

export type { MapScaleAlignment }

export interface MapControlProperties {
  /** The `mapScope` of the `MunimMapView` this control drives. */
  mapScope: string
  style?: StyleProp<ViewStyle>
}

const SIZES: Record<MapControlKind, ViewStyle> = {
  compass: { width: 44, height: 44 },
  scale: { width: 150, height: 24 },
  userTrackingButton: { width: 44, height: 44 },
}

function Control(
  props: MapControlProperties & {
    kind: MapControlKind
    visibility?: FeatureVisibility
    scaleAlignment?: MapScaleAlignment
  }
) {
  const style = useMemo(
    () => StyleSheet.compose(SIZES[props.kind], props.style),
    [props.kind, props.style]
  )
  if (Platform.OS !== 'ios') return null
  return (
    <NativeMapControl
      style={style}
      kind={props.kind}
      mapScope={props.mapScope}
      visibility={props.visibility ?? 'adaptive'}
      scaleAlignment={props.scaleAlignment ?? 'leading'}
    />
  )
}

/**
 * MapKit's compass (`MKCompassButton`) anywhere in your layout, like
 * SwiftUI's `MapCompass(scope:)`. Tapping it turns the map back to north.
 * Hide the map's own with `compassVisibility="hidden"`.
 */
export function MapCompass(
  props: MapControlProperties & {
    /** `'adaptive'` (default) shows it only while the map is rotated. */
    visibility?: FeatureVisibility
  }
) {
  return <Control {...props} kind="compass" />
}

/** MapKit's scale legend (`MKScaleView`) anywhere in your layout. */
export function MapScale(
  props: MapControlProperties & {
    /** `'adaptive'` (default) shows it only while zooming. */
    visibility?: FeatureVisibility
    /** Default `'leading'`. `'center'` needs iOS 26. */
    alignment?: MapScaleAlignment
  }
) {
  return <Control {...props} kind="scale" scaleAlignment={props.alignment} />
}

/**
 * MapKit's user tracking button (`MKUserTrackingButton`) anywhere in your
 * layout. It cycles the map's `userTrackingMode`; the map reports each
 * change through `onUserTrackingModeChange`.
 */
export function MapUserTrackingButton(props: MapControlProperties) {
  return <Control {...props} kind="userTrackingButton" />
}
