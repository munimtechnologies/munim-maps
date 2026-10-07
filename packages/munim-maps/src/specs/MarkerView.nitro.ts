import type {
  HybridView,
  HybridViewMethods,
  HybridViewProps,
} from 'react-native-nitro-modules'
import type { NativeMarker } from './MapFeatures.nitro'

/**
 * React Native children as a MapKit marker. The children are laid out off
 * screen and drawn into the marker's image (re-drawn when the props change,
 * and continuously while `tracksViewChanges`), so the marker is a real
 * `MKAnnotationView`: it moves with the map in the same frame, clusters,
 * collides, selects and shows callouts like any other.
 */
export interface MarkerViewProps extends HybridViewProps {
  marker: NativeMarker
  tracksViewChanges: boolean
  /** Changes on every React render, so a re-render re-draws. */
  renderKey: number
}

export interface MarkerViewMethods extends HybridViewMethods {
  /** Draws the children again now. */
  redraw(): void
}

export type MarkerView = HybridView<
  MarkerViewProps,
  MarkerViewMethods,
  { ios: 'swift' }
>
