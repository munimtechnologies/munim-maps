import { useRef, type ReactNode } from 'react'
import { Platform, StyleSheet, View } from 'react-native'
import { getHostComponent } from 'react-native-nitro-modules'
import MarkerViewConfig from '../nitrogen/generated/shared/json/MarkerViewConfig.json'
import type {
  MarkerViewMethods,
  MarkerViewProps,
} from './specs/MarkerView.nitro'
import { toNativeMarker, type MapMarker } from './features'

const NativeMarkerView = getHostComponent<MarkerViewProps, MarkerViewMethods>(
  'MarkerView',
  () => MarkerViewConfig
)

export interface MarkerViewProperties extends Omit<
  MapMarker,
  | 'style'
  | 'image'
  | 'size'
  | 'glyph'
  | 'glyphSymbol'
  | 'selectedGlyphSymbol'
  | 'glyphColor'
  | 'color'
  | 'border'
  | 'badges'
  | 'titleVisibility'
  | 'subtitleVisibility'
  | 'animatesWhenAdded'
> {
  /** What to draw. Laid out at its own size, like any React Native view. */
  children: ReactNode
  /**
   * Keep re-drawing the children (15 times a second) so animations, timers
   * and images that load later show. Turn it off once the content is
   * stable: drawing costs CPU. Default false, which re-draws only when the
   * `MarkerView` re-renders (and briefly after, for pictures loading).
   */
  tracksViewChanges?: boolean
}

/**
 * React Native views as a marker, like SwiftUI's `Annotation { … }`. Put it
 * inside a `MunimMapView`.
 *
 * The children are laid out off screen and drawn into the marker's
 * picture, so the marker is a real MapKit annotation: it moves with the map
 * in the same frame, clusters, collides, selects, drags and shows callouts
 * (`onMarkerPress` and the other marker events fire on the map with this
 * `id`). The trade-off: the children are a picture, not live views. Taps on
 * buttons inside them do nothing, and changes show when the `MarkerView`
 * re-renders, or continuously with `tracksViewChanges`.
 *
 * `anchor` defaults to the centre.
 *
 * On Android the children are drawn into a bitmap the same way; engines
 * that support it (Mapbox: a view annotation, or a draggable point
 * annotation) show it.
 */
export function MarkerView(props: MarkerViewProperties) {
  const renders = useRef(0)
  renders.current += 1
  if (Platform.OS !== 'ios' && Platform.OS !== 'android') return null
  const { children, tracksViewChanges, ...marker } = props
  const nativeMarker = toNativeMarker({
    ...marker,
    style: 'image',
    anchor: marker.anchor ?? { x: 0.5, y: 0.5 },
  })
  if (Platform.OS === 'android') {
    // Android's native views cannot hold React children: the children's
    // view comes first in a container, the native marker (which draws it)
    // second. `MunimMapView` keeps its children off screen.
    return (
      <View style={styles.offscreen} collapsable={false} pointerEvents="none">
        <View collapsable={false}>{children}</View>
        <NativeMarkerView
          style={styles.probe}
          marker={nativeMarker}
          tracksViewChanges={tracksViewChanges ?? false}
          renderKey={renders.current}
        />
      </View>
    )
  }
  return (
    <NativeMarkerView
      style={styles.offscreen}
      marker={nativeMarker}
      tracksViewChanges={tracksViewChanges ?? false}
      renderKey={renders.current}
    >
      {children}
    </NativeMarkerView>
  )
}

const styles = StyleSheet.create({
  // Laid out at its content's size, far outside the map: only its picture shows.
  offscreen: { position: 'absolute', left: -100_000, top: 0 },
  probe: { width: 1, height: 1 },
})
