import { forwardRef, useMemo, useRef, type ReactNode } from 'react'
import { Platform, StyleSheet, View } from 'react-native'
import {
  callback,
  getHostComponent,
  type HybridRef,
} from 'react-native-nitro-modules'
import MarkerViewConfig from '../nitrogen/generated/shared/json/MarkerViewConfig.json'
import type {
  MarkerViewMethods,
  MarkerViewProps,
} from './specs/MarkerView.nitro'
import type { NativeMarker } from './specs/MapFeatures.nitro'
import { toNativeMarker, type MapMarker } from './features'
import { markerContentKey, sameValue } from './markerContent'

const NativeMarkerView = getHostComponent<MarkerViewProps, MarkerViewMethods>(
  'MarkerView',
  () => MarkerViewConfig
)

/** A `MarkerView`'s ref: `redraw()` draws the children again now. */
export type MarkerViewRef = HybridRef<MarkerViewProps, MarkerViewMethods>

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
   * `true`: keep re-drawing the children (15 times a second) so animations
   * and anything else that changes on its own show; the marker's picture is
   * only replaced when it looks different. Default `false`: the children
   * are drawn once, then again only when something changed: the marker's
   * props, the children's elements and props, their size, or a picture in
   * them finishing loading. A re-render that changes nothing draws nothing.
   * State inside a child component that changes without the `MarkerView`'s
   * props changing needs `tracksViewChanges` or the ref's `redraw()`.
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
 * buttons inside them do nothing, and the picture is re-drawn when the
 * content changes (see `tracksViewChanges`), not on every render.
 *
 * `anchor` defaults to the centre.
 *
 * On Android the children are drawn into a bitmap the same way; engines
 * that support it (Mapbox: a view annotation, or a draggable point
 * annotation) show it.
 */
export const MarkerView = forwardRef<MarkerViewRef, MarkerViewProperties>(
  function MarkerViewComponent(props, ref) {
    const { children, tracksViewChanges, ...marker } = props
    const next = toNativeMarker({
      ...marker,
      style: 'image',
      anchor: marker.anchor ?? { x: 0.5, y: 0.5 },
    })
    // The same object while nothing changed: Nitro passes a prop on only
    // when it is a different value, and a new marker re-draws.
    const lastMarker = useRef<NativeMarker | undefined>(undefined)
    if (!lastMarker.current || !sameValue(lastMarker.current, next)) {
      lastMarker.current = next
    }
    const nativeMarker = lastMarker.current
    // Changes when the children (elements, props) change; when they cannot
    // be compared, on every render, as before.
    const renders = useRef(0)
    const contentKey = markerContentKey(children)
    if (contentKey == null) renders.current += 1
    const renderKey = contentKey ?? -renders.current
    const hybridRef = useMemo(
      () =>
        callback((instance: MarkerViewRef) => {
          if (typeof ref === 'function') ref(instance)
          else if (ref) ref.current = instance
        }),
      [ref]
    )
    if (Platform.OS !== 'ios' && Platform.OS !== 'android') return null
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
            renderKey={renderKey}
            hybridRef={hybridRef}
          />
        </View>
      )
    }
    return (
      <NativeMarkerView
        style={styles.offscreen}
        marker={nativeMarker}
        tracksViewChanges={tracksViewChanges ?? false}
        renderKey={renderKey}
        hybridRef={hybridRef}
      >
        {children}
      </NativeMarkerView>
    )
  }
)

const styles = StyleSheet.create({
  // Laid out at its content's size, far outside the map: only its picture shows.
  offscreen: { position: 'absolute', left: -100_000, top: 0 },
  probe: { width: 1, height: 1 },
})
