import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native'
import {
  MAP_PROVIDERS,
  MarkerView,
  MunimMapView,
  availableProviders,
  defaultProvider,
  installedProviders,
  type MapAlignmentReport,
  type MapCamera,
  type MapMarker,
  type MapModel,
  type MapProvider,
  type MapRegion,
  type MunimMapViewRef,
} from 'munim-maps'
import { File, Paths } from 'expo-file-system'
import { VEHICLES } from 'munim-maps-vehicles'
import bundledBalloon from 'munim-maps-vehicles/bundled/balloon'

/**
 * The same map, models and camera on every engine: pick MapKit, Google
 * Maps, Mapbox, MapLibre or Cesium. Engines that are not built into this
 * app (or not implemented yet) show munim-maps' placeholder. The status line
 * shows how far the 3D layer is from where the engine draws the same points
 * (`measureAlignment`). munimmapsexample://providers/<provider>
 *
 * munimmapsexample://providers/<provider>/check runs the shared-API checks
 * on that engine (react-native-maps' region API: `animateToRegion`,
 * `onRegionChangeStart`, `onRegionChangeComplete`, the controlled `region`)
 * and writes Documents/munim-maps-shared-checks-<provider>.json and
 * `MUNIM_MAPS_SHARED` log lines.
 */

const REGION_A: MapRegion = { latitude: 41.8790, longitude: -87.6350, latitudeDelta: 0.02, longitudeDelta: 0.02 }
const REGION_B: MapRegion = { latitude: 41.8900, longitude: -87.6200, latitudeDelta: 0.03, longitudeDelta: 0.03 }

interface SharedCheck {
  name: string
  ok: boolean
  detail: string
}

const wait = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms))

/**
 * The map shows `want`: its corners are inside the visible region (a pitched
 * camera, as here, sees more than the region, so the visible region is
 * larger), and the visible region is not wildly larger. On a tall phone at
 * 55° pitch the visible region reaches far toward the horizon: about 26 x
 * the region on MapLibre (Android), so the bound is 40 x.
 */
function near(region: MapRegion, want: MapRegion) {
  const slack = 0.1
  const inside = (lat: number, lon: number) =>
    Math.abs(lat - region.latitude) <= (region.latitudeDelta / 2) * (1 + slack) &&
    Math.abs(lon - region.longitude) <= (region.longitudeDelta / 2) * (1 + slack)
  const corners = [-1, 1].flatMap((a) =>
    [-1, 1].map((b) => inside(want.latitude + (a * want.latitudeDelta) / 2, want.longitude + (b * want.longitudeDelta) / 2))
  )
  return corners.every(Boolean) && region.latitudeDelta < want.latitudeDelta * 40
}

const NAMES: Record<MapProvider, string> = {
  mapkit: 'MapKit',
  google: 'Google',
  mapbox: 'Mapbox',
  maplibre: 'MapLibre',
  cesium: 'Cesium',
}

// Chicago's Loop, pitched, with vehicles (USDZ on iOS, GLB on Android).
const CAMERA: MapCamera = { latitude: 41.8826, longitude: -87.6278, distance: 900, pitch: 55, heading: 30 }
const MODELS: MapModel[] = [
  { id: 'bus', coordinate: { latitude: 41.8829, longitude: -87.6279 }, source: VEHICLES['bus-city'], heading: 0, tint: '#0A84FF', screenSize: 26 },
  { id: 'taxi', coordinate: { latitude: 41.8822, longitude: -87.6271 }, source: VEHICLES['car-taxi'], heading: 90, screenSize: 22 },
  { id: 'police', coordinate: { latitude: 41.8833, longitude: -87.6268 }, source: VEHICLES['car-police'], heading: 180, screenSize: 22 },
  { id: 'sports', coordinate: { latitude: 41.8819, longitude: -87.6285 }, source: VEHICLES['car-sports'], heading: 270, tint: '#FF3B30', screenSize: 22 },
  {
    id: 'balloon',
    coordinate: { latitude: 41.8826, longitude: -87.6278 },
    altitude: 120,
    // Inside the app (munim-maps-vehicles/bundled), not from the CDN.
    source: bundledBalloon,
    screenSize: 60,
  },
]

// A draggable marker on every engine: onMarkerDragStart / onMarkerDrag
// (continuous) / onMarkerDragEnd are logged as MUNIM_MAPS_PROVIDERS lines.
const MARKERS: MapMarker[] = [
  { id: 'drag', coordinate: { latitude: 41.8812, longitude: -87.6290 }, title: 'Drag me', draggable: true, color: '#AF52DE' },
]

/** The example's screens, each reachable from the engine picker. */
export type ExampleScreen =
  | 'google'
  | 'mapbox'
  | 'maplibre'
  | 'maplibreweb'
  | 'cesium'
  | 'layer3d'
  | 'layer-rnmapbox'
  | 'layer-rnmaps-google'
  | 'parity'
  | 'munim'
  | 'rnmaps'
  | 'expomaps'
  | 'terrain'
  | 'elevation'
  | 'features'
  | 'space'

/** Each engine's own screen (every feature group and its checks). */
const ENGINE_SCREENS: { screen: ExampleScreen; provider: MapProvider; label: string }[] = [
  { screen: 'parity', provider: 'mapkit', label: 'MapKit' },
  { screen: 'google', provider: 'google', label: 'Google' },
  { screen: 'mapbox', provider: 'mapbox', label: 'Mapbox' },
  { screen: 'maplibre', provider: 'maplibre', label: 'MapLibre' },
  { screen: 'maplibreweb', provider: 'maplibre', label: 'MapLibre GL JS (globe, terrain)' },
  { screen: 'cesium', provider: 'cesium', label: 'Cesium' },
]

/** MapModelLayer over other libraries' maps (Android). */
const ANDROID_SCREENS: { screen: ExampleScreen; label: string }[] = [
  { screen: 'layer-rnmapbox', label: 'Layer over @rnmapbox/maps' },
  { screen: 'layer-rnmaps-google', label: 'Layer over react-native-maps' },
]

/** The other examples (iOS: MapKit, react-native-maps and expo-maps). */
const IOS_SCREENS: { screen: ExampleScreen; label: string }[] = [
  { screen: 'munim', label: 'Demo' },
  { screen: 'features', label: 'Features' },
  { screen: 'terrain', label: 'Terrain' },
  { screen: 'elevation', label: 'Elevation' },
  { screen: 'space', label: 'Satellites' },
  { screen: 'rnmaps', label: 'react-native-maps' },
  { screen: 'expomaps', label: 'expo-maps' },
]

export function ProvidersScreen(props: {
  initial?: MapProvider
  topInset: number
  panel: boolean
  /** Back to the other examples (iOS). */
  onExit?: () => void
  /** Opens another screen; `layer3d` gets the engine picked here. */
  onOpen?: (screen: ExampleScreen, provider: MapProvider) => void
  /** Run the shared-API checks once the map is ready. */
  autoCheck?: boolean
}) {
  const [provider, setProvider] = useState<MapProvider>(props.initial ?? defaultProvider())
  const [errors, setErrors] = useState<string[]>([])
  const [alignment, setAlignment] = useState<MapAlignmentReport | null>(null)
  const [pressed, setPressed] = useState('')
  const ref = useRef<MunimMapViewRef | null>(null)
  const available = useMemo(() => availableProviders(), [])
  const installed = useMemo(() => installedProviders(), [])

  // Shared-API checks: react-native-maps' region API on this engine.
  const [region, setRegion] = useState<MapRegion | undefined>(undefined)
  const [checkStatus, setCheckStatus] = useState('')
  const ready = useRef(false)
  const starts = useRef(0)
  const completes = useRef<MapRegion[]>([])
  const drags = useRef(0)
  const runToken = useRef(0)
  const runChecks = useCallback(async () => {
    // One run at a time: switching engines (the map remounts) ends the last.
    const token = ++runToken.current
    const checks: SharedCheck[] = []
    const check = (name: string, ok: boolean, detail: unknown) => {
      if (token !== runToken.current) return
      checks.push({ name, ok, detail: JSON.stringify(detail) })
      console.log(`MUNIM_MAPS_SHARED ${provider} ${ok ? 'pass' : 'FAIL'} ${name} ${JSON.stringify(detail)}`)
    }
    setCheckStatus('Checking…')
    // Wait for this engine's map: until it is ready, the ref may still be
    // the previous engine's view.
    for (let i = 0; i < 60 && !ready.current; i++) await wait(250)
    for (let i = 0; i < 60 && !ref.current; i++) await wait(250)
    const map = ref.current
    if (!map || token !== runToken.current) return
    check('onMapReady', ready.current, {})
    await wait(1500)
    starts.current = 0
    completes.current = []
    map.animateToRegion(REGION_A, 600)
    await wait(3500)
    check('onRegionChangeStart fires', starts.current > 0, { starts: starts.current })
    const last = completes.current[completes.current.length - 1]
    check('onRegionChangeComplete reports the region', !!last && near(last, REGION_A), last ?? null)
    const visibleA = await map.getVisibleRegion()
    check('animateToRegion moves the map', near(visibleA, REGION_A), visibleA)
    setRegion(REGION_B)
    await wait(3500)
    const visibleB = await map.getVisibleRegion()
    check('controlled region moves the map', near(visibleB, REGION_B), visibleB)
    if (token !== runToken.current) return
    const passed = checks.filter((c) => c.ok).length
    const report = { provider, platform: Platform.OS, finishedAt: new Date().toISOString(), passed, total: checks.length, checks }
    console.log(`MUNIM_MAPS_SHARED ${provider} done ${passed}/${checks.length}`)
    setCheckStatus(`Shared API: ${passed}/${checks.length}`)
    try {
      const file = new File(Paths.document, `munim-maps-shared-checks-${provider}.json`)
      if (file.exists) file.delete()
      file.create()
      file.write(JSON.stringify(report, null, 2))
    } catch (error) {
      console.warn('MUNIM_MAPS_SHARED could not write the report', error)
    }
  }, [provider])

  useEffect(() => {
    ready.current = false
    setRegion(undefined)
    setCheckStatus('')
  }, [provider])

  useEffect(() => {
    // With a deep-linked engine, only once that engine is showing.
    if (props.autoCheck && (!props.initial || props.initial === provider)) void runChecks()
    // Once per engine opened by the deep link.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [props.autoCheck, provider])

  // A deep link can arrive after the screen is up (Android starts here).
  useEffect(() => {
    if (props.initial) setProvider(props.initial)
  }, [props.initial])

  useEffect(() => {
    setErrors([])
    setAlignment(null)
    const timer = setInterval(() => {
      ref.current
        ?.measureAlignment()
        .then((report) => {
          setAlignment(report)
          console.log(
            `MUNIM_MAPS_PROVIDERS ${provider} alignment ${JSON.stringify(report)}`
          )
        })
        .catch(() => {})
    }, 3000)
    return () => clearInterval(timer)
  }, [provider])

  const isAvailable = available.includes(provider)
  return (
    <View style={StyleSheet.absoluteFill}>
      <MunimMapView
        key={provider}
        ref={ref}
        provider={provider}
        style={StyleSheet.absoluteFill}
        initialCamera={CAMERA}
        region={region}
        models={MODELS}
        lighting="day"
        onModelPress={setPressed}
        markers={MARKERS}
        onMarkerPress={(id) => console.log(`MUNIM_MAPS_PROVIDERS ${provider} marker press ${id}`)}
        onMarkerDragStart={(e) => {
          drags.current = 0
          console.log(`MUNIM_MAPS_PROVIDERS ${provider} drag start ${e.id}`)
        }}
        onMarkerDrag={(e) => {
          drags.current += 1
          if (drags.current % 5 === 1) {
            console.log(`MUNIM_MAPS_PROVIDERS ${provider} drag move ${e.id} ${e.latitude.toFixed(5)},${e.longitude.toFixed(5)}`)
          }
        }}
        onMarkerDragEnd={(e) =>
          console.log(
            `MUNIM_MAPS_PROVIDERS ${provider} drag end ${e.id} ${e.latitude.toFixed(5)},${e.longitude.toFixed(5)} after ${drags.current} onMarkerDrag`
          )
        }
        onRegionChangeStart={() => {
          starts.current += 1
        }}
        onRegionChangeComplete={(r) => {
          completes.current.push(r)
        }}
        onMapReady={() => {
          ready.current = true
          console.log(`MUNIM_MAPS_PROVIDERS ${provider} map ready`)
        }}
        onError={(message) => {
          console.log(`MUNIM_MAPS_PROVIDERS ${provider} error ${message}`)
          setErrors((list) => (list.includes(message) ? list : [...list, message].slice(-4)))
        }}
      >
        {/* React Native views as a marker (Android: an image marker; Mapbox: a view annotation). */}
        <MarkerView id="pill" coordinate={{ latitude: 41.8840, longitude: -87.6262 }} anchor={{ x: 0.5, y: 1 }}>
          <View style={styles.pill}>
            <Text style={styles.pillText}>MarkerView</Text>
          </View>
        </MarkerView>
      </MunimMapView>
      <View style={[styles.panel, { top: props.topInset + 8 }, !props.panel && styles.hidden]}>
        <ScrollView horizontal contentContainerStyle={styles.row} showsHorizontalScrollIndicator={false}>
          {props.onExit ? (
            <Pressable onPress={props.onExit} style={styles.chip}>
              <Text style={styles.chipText}>‹ Examples</Text>
            </Pressable>
          ) : null}
          {MAP_PROVIDERS.map((p) => (
            <Pressable
              key={p}
              onPress={() => setProvider(p)}
              style={[styles.chip, p === provider && styles.chipOn, !available.includes(p) && styles.chipOff]}
            >
              <Text style={[styles.chipText, p === provider && styles.chipTextOn]}>{NAMES[p]}</Text>
            </Pressable>
          ))}
          <Pressable onPress={() => void runChecks()} style={styles.chip}>
            <Text style={styles.chipText}>Check regions</Text>
          </Pressable>
        </ScrollView>
        {props.onOpen ? (
          <ScrollView horizontal contentContainerStyle={styles.row} showsHorizontalScrollIndicator={false}>
            <Text style={styles.label}>Screens</Text>
            {ENGINE_SCREENS.filter((e) => available.includes(e.provider)).map((e) => (
              <Pressable key={e.screen} onPress={() => props.onOpen?.(e.screen, e.provider)} style={styles.chip}>
                <Text style={styles.chipText}>{e.label} ›</Text>
              </Pressable>
            ))}
            {isAvailable ? (
              <Pressable onPress={() => props.onOpen?.('layer3d', provider)} style={styles.chip}>
                <Text style={styles.chipText}>3D layer on {NAMES[provider]} ›</Text>
              </Pressable>
            ) : null}
            {Platform.OS === 'ios'
              ? IOS_SCREENS.map((e) => (
                  <Pressable key={e.screen} onPress={() => props.onOpen?.(e.screen, provider)} style={styles.chip}>
                    <Text style={styles.chipText}>{e.label} ›</Text>
                  </Pressable>
                ))
              : ANDROID_SCREENS.map((e) => (
                  <Pressable key={e.screen} onPress={() => props.onOpen?.(e.screen, provider)} style={styles.chip}>
                    <Text style={styles.chipText}>{e.label} ›</Text>
                  </Pressable>
                ))}
          </ScrollView>
        ) : null}
        <Text style={styles.status}>
          {Platform.OS} · built in: {installed.join(', ') || 'none'} · working: {available.join(', ') || 'none'}
        </Text>
        {!isAvailable ? (
          <Text style={styles.status}>
            {NAMES[provider]} is {installed.includes(provider) ? 'built in but not implemented yet' : 'not built into this app'}: the map shows munim-maps' placeholder.
          </Text>
        ) : null}
        {alignment && alignment.modelsMeasured > 0 ? (
          <Text style={styles.status}>
            3D layer vs map: max {alignment.maxErrorPoints.toFixed(2)} pt, mean {alignment.meanErrorPoints.toFixed(2)} pt over {alignment.modelsMeasured} models · fov {alignment.fieldOfViewDegrees.toFixed(1)}°
          </Text>
        ) : null}
        {pressed ? <Text style={styles.status}>Tapped: {pressed}</Text> : null}
        {checkStatus ? <Text style={styles.status}>{checkStatus}</Text> : null}
        {errors.map((e) => (
          <Text key={e} style={styles.error} numberOfLines={2}>
            {e}
          </Text>
        ))}
      </View>
    </View>
  )
}

const styles = StyleSheet.create({
  pill: {
    backgroundColor: '#0A84FF',
    borderRadius: 14,
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderWidth: 2,
    borderColor: 'white',
  },
  pillText: { color: 'white', fontWeight: '700', fontSize: 14 },
  panel: {
    position: 'absolute',
    left: 12,
    right: 12,
    padding: 10,
    borderRadius: 14,
    backgroundColor: 'rgba(20,20,24,0.72)',
    gap: 6,
  },
  row: { flexDirection: 'row', gap: 8 },
  chip: { paddingHorizontal: 12, paddingVertical: 7, borderRadius: 999, backgroundColor: 'rgba(255,255,255,0.12)' },
  chipOn: { backgroundColor: '#FFFFFF' },
  chipOff: { opacity: 0.55 },
  chipText: { color: '#FFFFFF', fontSize: 13, fontWeight: '600' },
  chipTextOn: { color: '#111111' },
  status: { color: '#FFFFFF', fontSize: 12 },
  label: { color: '#FFFFFF', fontSize: 12, fontWeight: '700', alignSelf: 'center' },
  error: { color: '#FFB4A9', fontSize: 11 },
  hidden: { display: 'none' },
})
