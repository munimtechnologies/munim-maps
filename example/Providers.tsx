import { useEffect, useMemo, useRef, useState } from 'react'
import { Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native'
import {
  MAP_PROVIDERS,
  MunimMapView,
  availableProviders,
  defaultProvider,
  installedProviders,
  type MapAlignmentReport,
  type MapCamera,
  type MapModel,
  type MapProvider,
  type MunimMapViewRef,
} from 'munim-maps'
import { VEHICLES } from 'munim-maps-vehicles'
import bundledBalloon from 'munim-maps-vehicles/bundled/balloon'

/**
 * The same map, models and camera on every engine: pick MapKit, Google
 * Maps, Mapbox, MapLibre or Cesium. Engines that are not built into this
 * app (or not implemented yet) show munim-maps' placeholder. The status line
 * shows how far the 3D layer is from where the engine draws the same points
 * (`measureAlignment`). munimmapsexample://providers/<provider>
 */

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

/** The example's screens, each reachable from the engine picker. */
export type ExampleScreen =
  | 'google'
  | 'mapbox'
  | 'maplibre'
  | 'cesium'
  | 'layer3d'
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
  { screen: 'cesium', provider: 'cesium', label: 'Cesium' },
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
}) {
  const [provider, setProvider] = useState<MapProvider>(props.initial ?? defaultProvider())
  const [errors, setErrors] = useState<string[]>([])
  const [alignment, setAlignment] = useState<MapAlignmentReport | null>(null)
  const [pressed, setPressed] = useState('')
  const ref = useRef<MunimMapViewRef | null>(null)
  const available = useMemo(() => availableProviders(), [])
  const installed = useMemo(() => installedProviders(), [])

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
        models={MODELS}
        lighting="day"
        onModelPress={setPressed}
        onMapReady={() => console.log(`MUNIM_MAPS_PROVIDERS ${provider} map ready`)}
        onError={(message) => {
          console.log(`MUNIM_MAPS_PROVIDERS ${provider} error ${message}`)
          setErrors((list) => (list.includes(message) ? list : [...list, message].slice(-4)))
        }}
      />
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
              : null}
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
