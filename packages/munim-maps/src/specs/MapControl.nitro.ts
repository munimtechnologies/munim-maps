import type {
  HybridView,
  HybridViewMethods,
  HybridViewProps,
} from 'react-native-nitro-modules'
import type { FeatureVisibility } from './MunimMapView.nitro'

/**
 * - `compass`: `MKCompassButton`, turns the map back to north when tapped.
 * - `scale`: `MKScaleView`, the distance legend.
 * - `userTrackingButton`: `MKUserTrackingButton`, cycles `userTrackingMode`.
 */
export type MapControlKind = 'compass' | 'scale' | 'userTrackingButton'

/** Where the scale's legend sits in its view. `center` needs iOS 26. */
export type MapScaleAlignment = 'leading' | 'trailing' | 'center'

/**
 * A MapKit control placed anywhere in your layout, like SwiftUI's
 * `MapCompass(scope:)`: it drives the `MunimMapView` whose `mapScope` is the
 * same string.
 */
export interface MapControlProps extends HybridViewProps {
  kind: MapControlKind
  mapScope: string
  /** Compass and scale. */
  visibility: FeatureVisibility
  scaleAlignment: MapScaleAlignment
}

export interface MapControlMethods extends HybridViewMethods {}

export type MapControl = HybridView<
  MapControlProps,
  MapControlMethods,
  { ios: 'swift' }
>
