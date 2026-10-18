import type {
  HybridView,
  HybridViewMethods,
  HybridViewProps,
} from 'react-native-nitro-modules'
import type { NativeMarker } from './MapFeatures.nitro'

/**
 * React Native children as a MapKit marker. The children are laid out off
 * screen and drawn into the marker's image (re-drawn when the props, the
 * children's size or a picture in them change, and continuously while
 * `tracksViewChanges`), so the marker is a real `MKAnnotationView`: it
 * moves with the map in the same frame, clusters, collides, selects and
 * shows callouts like any other.
 */
export interface MarkerViewProps extends HybridViewProps {
  marker: NativeMarker
  tracksViewChanges: boolean
  /**
   * A hash of the children as given: changes when they do, so a re-render
   * that changes them re-draws (and one that does not, does not).
   */
  renderKey: number
}

export interface MarkerViewMethods extends HybridViewMethods {
  /** Draws the children again now. */
  redraw(): void
}

export type MarkerView = HybridView<
  MarkerViewProps,
  MarkerViewMethods,
  { ios: 'swift'; android: 'kotlin' }
>
