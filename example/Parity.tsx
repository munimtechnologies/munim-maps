import { useEffect, useMemo, useRef, useState, type RefObject } from 'react'
import { Pressable, StyleSheet, Text, TextInput, View } from 'react-native'
import {
  LookAroundView,
  MapCompass,
  MapScale,
  MapUserTrackingButton,
  MarkerView,
  MunimMapView,
  createSearchCompleter,
  directions,
  formatDistance,
  routePolyline,
  searchPlaces,
  type MapCamera,
  type MapItem,
  type MapMarker,
  type MapPolyline,
  type MunimMapViewRef,
  type Route,
  type SearchCompletion,
  type UserTrackingMode,
} from 'munim-maps'

/**
 * Everything from MapKit in one screen: user tracking with heading and its
 * button, standalone controls, search with autocomplete, a route drawn with
 * a gradient, Apple's place cards for tapped places, Look Around, a React
 * Native view as a marker, styled clusters and callout buttons.
 * munimmapsexample://parity (add /follow to start following).
 */

export const PARITY_CAMERA: MapCamera = {
  latitude: 41.8858,
  longitude: -87.6249,
  distance: 5200,
  pitch: 0,
  heading: 0,
}
export const WILLIS_TOWER = { latitude: 41.8789, longitude: -87.6359 }
export const NAVY_PIER = { latitude: 41.8917, longitude: -87.6086 }
export const LOOP_REGION = {
  latitude: 41.8826,
  longitude: -87.6233,
  latitudeDelta: 0.03,
  longitudeDelta: 0.03,
}
export const PARITY_POLYGON_ID = 'parity-block'
export const PARITY_VIEW_MARKER_ID = 'parity-view-marker'

const CAFES: MapMarker[] = Array.from({ length: 8 }, (_, i) => ({
  id: `parity-cafe-${i}`,
  coordinate: {
    latitude: 41.8835 + (i % 4) * 0.0005,
    longitude: -87.6305 + Math.floor(i / 4) * 0.0007,
  },
  glyphSymbol: 'cup.and.saucer.fill',
  color: '#8D6E63',
  clusteringId: 'cafes',
  displayPriority: 'high' as const,
}))

const MARKERS: MapMarker[] = [
  {
    id: 'parity-willis',
    coordinate: WILLIS_TOWER,
    title: 'Willis Tower',
    subtitle: 'Skydeck, floor 103',
    glyphSymbol: 'building.2.fill',
    selectedGlyphSymbol: 'binoculars.fill',
    color: '#FF3B30',
    titleVisibility: 'visible',
    animatesWhenAdded: true,
  },
  {
    // Classic pin with a full callout: buttons at both ends and detail text.
    id: 'parity-skydeck',
    coordinate: { latitude: 41.8786, longitude: -87.6352 },
    style: 'pin',
    color: '#FF9F0A',
    title: 'Skydeck Chicago',
    subtitle: 'Floor 103',
    callout: true,
    calloutLeft: { symbol: 'phone.fill', color: '#30D158' },
    calloutRight: { text: 'Tickets' },
    calloutDetail: 'Open daily, 9 am to 10 pm.\nThe Ledge: glass boxes 412 m up.',
  },
  {
    id: 'parity-pier',
    coordinate: NAVY_PIER,
    title: 'Navy Pier',
    glyphSymbol: 'ferry.fill',
    color: '#0A84FF',
    collisionMode: 'circle',
    displayPriority: 'required',
  },
  ...CAFES,
]

export interface ParityHandle {
  route: Route | null
  completions: SearchCompletion[]
  trackingEvents: UserTrackingMode[]
}

export function ParityScreen(props: {
  mapRef: RefObject<MunimMapViewRef | null>
  startFollowing: boolean
  /** munimmapsexample://parity/callout: show a callout without a tap. */
  demo: string
  handle: RefObject<ParityHandle>
  trackingMode: UserTrackingMode
  setTrackingMode: (mode: UserTrackingMode) => void
  onEvent: (text: string) => void
  topInset: number
}) {
  const { handle, onEvent, setTrackingMode } = props
  const [query, setQuery] = useState('Willis T')
  const [completions, setCompletions] = useState<SearchCompletion[]>([])
  const [found, setFound] = useState<MapItem[]>([])
  const [route, setRoute] = useState<Route | null>(null)
  const [drawn, setDrawn] = useState(1)
  const [lookAround, setLookAround] = useState('Look Around: loading…')
  const [clock, setClock] = useState(0)

  // Autocomplete while typing.
  const completer = useMemo(
    () =>
      createSearchCompleter({
        region: LOOP_REGION,
        onResults: (results) => {
          handle.current.completions = results
          setCompletions(results.slice(0, 4))
        },
        onError: (message) => onEvent(`completer: ${message}`),
      }),
    [handle, onEvent]
  )
  useEffect(() => {
    completer.setQuery(query)
  }, [completer, query])
  useEffect(() => () => completer.cancel(), [completer])

  // Coffee nearby, and the route from Willis Tower to Navy Pier.
  useEffect(() => {
    searchPlaces({ query: 'coffee', region: LOOP_REGION, resultTypes: ['pointOfInterest'] })
      .then((items) => setFound(items.slice(0, 5)))
      .catch((error) => onEvent(`search: ${String(error)}`))
    directions({ from: WILLIS_TOWER, to: NAVY_PIER, transportType: 'automobile' })
      .then(([best]) => {
        if (!best) return
        handle.current.route = best
        setRoute(best)
        setDrawn(0)
      })
      .catch((error) => onEvent(`directions: ${String(error)}`))
  }, [handle, onEvent])

  // Draw the route in over a second and a half (strokeEnd).
  useEffect(() => {
    if (!route || drawn >= 1) return
    const timer = setTimeout(() => setDrawn((d) => Math.min(1, d + 0.05)), 60)
    return () => clearTimeout(timer)
  }, [route, drawn])

  // A ticking clock in the React Native marker (tracksViewChanges).
  useEffect(() => {
    const timer = setInterval(() => setClock((c) => c + 1), 1000)
    return () => clearInterval(timer)
  }, [])

  useEffect(() => {
    if (props.startFollowing) setTrackingMode('followWithHeading')
  }, [props.startFollowing, setTrackingMode])

  // Deep-link demos, for screenshots without touch.
  const { demo, mapRef } = props
  useEffect(() => {
    if (demo === 'callout') {
      const timer = setTimeout(() => {
        mapRef.current?.setCamera({ ...WILLIS_TOWER, distance: 2500, pitch: 0, heading: 0 }, false)
        setTimeout(() => mapRef.current?.selectMarker('parity-skydeck'), 800)
      }, 2500)
      return () => clearTimeout(timer)
    }
    return undefined
  }, [demo, mapRef, found, onEvent])

  const polylines = useMemo<MapPolyline[]>(() => {
    const lines: MapPolyline[] = []
    if (route) {
      lines.push({
        ...routePolyline(route, {
          id: 'parity-route',
          strokeColors: ['#30D158', '#0A84FF', '#BF5AF2'],
          strokeWidth: 7,
        }),
        strokeEnd: drawn,
      })
    }
    return lines
  }, [route, drawn])

  const markers = useMemo<MapMarker[]>(
    () => [
      ...MARKERS,
      ...found.map((item, i) => ({
        id: `parity-found-${i}`,
        coordinate: item,
        title: item.name,
        subtitle: item.address.shortAddress,
        glyphSymbol: 'magnifyingglass',
        color: '#FF9F0A',
        callout: true,
        displayPriority: 'low' as const,
      })),
    ],
    [found]
  )

  async function pick(completion: SearchCompletion) {
    const [item] = await completer.resolve(completion)
    if (!item) return
    setFound([item])
    props.mapRef.current?.setCamera(
      { latitude: item.latitude, longitude: item.longitude, distance: 1500, pitch: 45, heading: 0 },
      true
    )
  }

  return (
    <View style={StyleSheet.absoluteFill}>
      <MunimMapView
        ref={props.mapRef}
        style={StyleSheet.absoluteFill}
        mapScope="parity"
        initialCamera={PARITY_CAMERA}
        markers={markers}
        polylines={polylines}
        polygons={[
          {
            id: PARITY_POLYGON_ID,
            coordinates: [
              { latitude: 41.8775, longitude: -87.6245 },
              { latitude: 41.8775, longitude: -87.6195 },
              { latitude: 41.8745, longitude: -87.6195 },
              { latitude: 41.8745, longitude: -87.6245 },
            ],
            strokeColor: '#FF2D55',
            fillColor: '#FF2D5533',
            level: 'aboveRoads',
          },
        ]}
        clusterStyles={[
          { clusteringId: 'cafes', color: '#6D4C41', glyph: '☕{count}', glyphColor: '#FFD60A', title: '{count} cafés' },
        ]}
        showsUserLocation
        userTrackingMode={props.trackingMode}
        onUserTrackingModeChange={(mode) => {
          handle.current.trackingEvents.push(mode)
          setTrackingMode(mode)
          onEvent(`tracking ${mode}`)
        }}
        showsUserTrackingButton
        pitchButtonVisibility="visible"
        compassVisibility="hidden"
        scaleVisibility="hidden"
        selectableMapFeatures={['pointsOfInterest']}
        selectionAccessory={props.demo === 'callout' ? 'none' : 'automatic'}
        onMapFeaturePress={(f) => onEvent(`place ${f.title}`)}
        onOverlayPress={(e) => onEvent(`overlay ${e.id}`)}
        onClusterPress={(e) => {
          onEvent(`cluster ${e.clusteringId}`)
          props.mapRef.current?.fitToMarkers(e.markerIds, { top: 80, left: 80, bottom: 80, right: 80 }, true)
        }}
        onCalloutAccessoryPress={(e) => onEvent(`callout ${e.id} ${e.side}`)}
        onMarkerPress={(id) => onEvent(`marker ${id}`)}
        onError={(message) => onEvent(`error ${message}`)}
      >
        <MarkerView
          id={PARITY_VIEW_MARKER_ID}
          coordinate={{ latitude: 41.8826, longitude: -87.6226 }}
          anchor={{ x: 0.5, y: 1 }}
          title="Cloud Gate"
          callout
          tracksViewChanges
        >
          <View style={styles.bubble}>
            <Text style={styles.bubbleEmoji}>🫘</Text>
            <View>
              <Text style={styles.bubbleTitle}>React Native marker</Text>
              <Text style={styles.bubbleText}>{`open ${clock}s`}</Text>
            </View>
          </View>
          <View style={styles.bubbleTail} />
        </MarkerView>
      </MunimMapView>

      <View style={[styles.search, { top: props.topInset + 150 }]}>
        <TextInput
          value={query}
          onChangeText={setQuery}
          placeholder="Search Apple Maps"
          placeholderTextColor="#8E8E93"
          style={styles.input}
        />
        {completions.map((c) => (
          <Pressable key={`${c.index}-${c.title}`} onPress={() => void pick(c)} style={styles.row}>
            <Text style={styles.rowTitle}>{c.title}</Text>
            {c.subtitle ? <Text style={styles.rowText}>{c.subtitle}</Text> : null}
          </Pressable>
        ))}
        {route ? (
          <Text style={styles.route}>
            {`Route: ${formatDistance(route.distance)}, ${Math.round(route.expectedTravelTime / 60)} min by car, ${route.steps.length} steps`}
          </Text>
        ) : null}
      </View>

      <View style={styles.controls}>
        <MapCompass mapScope="parity" visibility="visible" />
        <MapUserTrackingButton mapScope="parity" style={styles.trackingButton} />
        <MapScale mapScope="parity" visibility="visible" style={styles.scale} />
      </View>

      <View style={styles.lookAround}>
        <LookAroundView
          style={StyleSheet.absoluteFill}
          coordinate={{ latitude: 41.8827, longitude: -87.6233 }}
          badgePosition="bottomTrailing"
          onSceneChange={(available) => setLookAround(available ? '' : 'No Look Around here')}
          onError={(message) => setLookAround(`Look Around: ${message}`)}
        />
        {lookAround ? <Text style={styles.lookAroundText}>{lookAround}</Text> : null}
      </View>
    </View>
  )
}

const styles = StyleSheet.create({
  bubble: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 16,
    backgroundColor: '#1C1C1E',
    borderWidth: 2,
    borderColor: '#FFD60A',
  },
  bubbleEmoji: { fontSize: 22 },
  bubbleTitle: { color: '#FFFFFF', fontWeight: '700', fontSize: 13 },
  bubbleText: { color: '#FFD60A', fontSize: 12 },
  bubbleTail: {
    alignSelf: 'center',
    width: 0,
    height: 0,
    borderLeftWidth: 8,
    borderRightWidth: 8,
    borderTopWidth: 10,
    borderLeftColor: 'transparent',
    borderRightColor: 'transparent',
    borderTopColor: '#FFD60A',
  },
  search: {
    position: 'absolute',
    left: 12,
    width: 320,
    padding: 10,
    borderRadius: 14,
    backgroundColor: 'rgba(28,28,30,0.88)',
    gap: 6,
  },
  input: {
    color: '#FFFFFF',
    fontSize: 15,
    paddingHorizontal: 10,
    paddingVertical: 8,
    borderRadius: 10,
    backgroundColor: 'rgba(255,255,255,0.12)',
  },
  row: { paddingVertical: 4, paddingHorizontal: 4 },
  rowTitle: { color: '#FFFFFF', fontSize: 14, fontWeight: '600' },
  rowText: { color: '#AEAEB2', fontSize: 12 },
  route: { color: '#30D158', fontSize: 12, marginTop: 4 },
  controls: {
    position: 'absolute',
    left: 12,
    bottom: 230,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  trackingButton: {
    backgroundColor: 'rgba(255,255,255,0.9)',
    borderRadius: 8,
  },
  scale: { width: 160 },
  lookAround: {
    position: 'absolute',
    left: 12,
    bottom: 24,
    width: 320,
    height: 190,
    borderRadius: 14,
    overflow: 'hidden',
    backgroundColor: '#1C1C1E',
  },
  lookAroundText: { color: '#FFFFFF', fontSize: 12, margin: 10 },
})
