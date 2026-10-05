import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { File, Paths } from 'expo-file-system'
import { StatusBar } from 'expo-status-bar'
import { Pressable, StyleSheet, Text, View } from 'react-native'
import { useSafeAreaInsets, SafeAreaProvider } from 'react-native-safe-area-context'
import MapView from 'react-native-maps'
import {
  MapModelLayer,
  MunimMapView,
  type MapCamera,
  type MapModel,
  type MapModelLayerRef,
  type MapModelLighting,
  type MunimMapViewRef,
} from 'munim-maps'
import { runSelfTest, type SelfTestReport, type TestMode } from './selftest'

const starship = require('./assets/starship.usdz')
const tower = require('./assets/tower.usdz')

// Starbase, Texas: two launch towers, each with a Starship on its mount.
const STARBASE = { latitude: 25.9965, longitude: -97.1559 }
const PADS = [
  {
    id: 'a',
    tower: { latitude: 25.99695, longitude: -97.15726 },
    mount: { latitude: 25.99717, longitude: -97.15696 },
  },
  {
    id: 'b',
    tower: { latitude: 25.99585, longitude: -97.15468 },
    mount: { latitude: 25.9961, longitude: -97.1544 },
  },
]

const INITIAL_CAMERA: MapCamera = {
  ...STARBASE,
  distance: 1100,
  pitch: 55,
  heading: 35,
}

/** Seconds per launch: 4 on the pad, then a climb to about 4 km. */
const CYCLE = 22

function launchAltitude(seconds: number): number {
  const t = (seconds % CYCLE) - 4
  return t <= 0 ? 0 : 12 * t * t
}

function useLaunchClock(running: boolean): number {
  const [seconds, setSeconds] = useState(0)
  useEffect(() => {
    if (!running) return
    const start = Date.now() - seconds * 1000
    const timer = setInterval(() => setSeconds((Date.now() - start) / 1000), 33)
    return () => clearInterval(timer)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [running])
  return seconds
}

function buildModels(seconds: number, launching: boolean): MapModel[] {
  const models: MapModel[] = []
  PADS.forEach((pad, index) => {
    // Stagger the two pads so one is always flying.
    const altitude = launching ? launchAltitude(seconds + index * (CYCLE / 2)) : 0
    models.push({ id: `tower-${pad.id}`, coordinate: pad.tower, source: tower, heading: 40 })
    models.push({
      id: `ship-${pad.id}`,
      coordinate: pad.mount,
      source: starship,
      altitude: altitude + 20,
      groundShadow: altitude < 50,
    })
    models.push({
      id: `mount-${pad.id}`,
      coordinate: pad.mount,
      shape: 'cylinder',
      size: { width: 22, height: 20, length: 22 },
      color: '#3A3D42',
    })
    models.push({
      id: `flame-${pad.id}`,
      coordinate: pad.mount,
      shape: 'capsule',
      size: { width: 7, height: 40, length: 7 },
      color: '#FF8A2A',
      emissive: true,
      groundShadow: false,
      altitude: altitude - 20,
      heading: 0,
      visible: altitude > 0,
    })
  })
  // A marker-style model that keeps its size on screen.
  models.push({
    id: 'marker',
    coordinate: { latitude: 25.9952, longitude: -97.1575 },
    shape: 'pyramid',
    size: { width: 1, height: 1.4, length: 1 },
    color: '#30D158',
    emissive: true,
    screenSize: 36,
    spinDegreesPerSecond: 90,
    groundShadow: false,
  })
  return models
}

function writeReport(report: SelfTestReport) {
  try {
    const file = new File(Paths.document, 'munim-maps-selftest.json')
    if (file.exists) file.delete()
    file.create()
    file.write(JSON.stringify(report, null, 2))
  } catch (error) {
    console.warn('MUNIM_MAPS could not write the self-test report', error)
  }
}

function Example() {
  const insets = useSafeAreaInsets()
  const [mode, setMode] = useState<TestMode>('munim')
  const [lighting, setLighting] = useState<MapModelLighting>('auto')
  const [launching, setLaunching] = useState(true)
  const [status, setStatus] = useState('Running self-test…')
  const [pressed, setPressed] = useState<string | null>(null)
  const [attached, setAttached] = useState(false)
  const seconds = useLaunchClock(launching)
  const models = useMemo(() => buildModels(seconds, launching), [seconds, launching])

  const munimRef = useRef<MunimMapViewRef | null>(null)
  const layerRef = useRef<MapModelLayerRef | null>(null)
  const rnMapRef = useRef<MapView | null>(null)
  const attachedRef = useRef(false)
  const modeWaiters = useRef<(() => void)[]>([])

  useEffect(() => {
    const waiters = modeWaiters.current
    modeWaiters.current = []
    // Let the new screen mount before resolving.
    setTimeout(() => waiters.forEach((resolve) => resolve()), 300)
  }, [mode])

  const onAttachChange = useCallback((value: boolean) => {
    attachedRef.current = value
    setAttached(value)
  }, [])

  const ran = useRef(false)
  useEffect(() => {
    if (ran.current) return
    ran.current = true
    runSelfTest(
      {
        showMode: (next) =>
          new Promise<void>((resolve) => {
            modeWaiters.current.push(resolve)
            setMode((current) => {
              if (current === next) setTimeout(resolve, 0)
              return next
            })
          }),
        munimMap: () => munimRef.current,
        layer: () => layerRef.current,
        setRnMapsCamera: (camera) =>
          rnMapRef.current?.setCamera({
            center: { latitude: camera.latitude, longitude: camera.longitude },
            pitch: camera.pitch,
            heading: camera.heading,
            altitude: camera.distance * Math.cos((camera.pitch * Math.PI) / 180),
          }),
        waitForLayerAttached: async (timeoutMs) => {
          const end = Date.now() + timeoutMs
          while (Date.now() < end) {
            if (attachedRef.current) return true
            await new Promise((resolve) => setTimeout(resolve, 100))
          }
          return attachedRef.current
        },
      },
      STARBASE
    )
      .then((report) => {
        writeReport(report)
        setStatus(`Self-test: ${report.passed} passed, ${report.failed} failed`)
      })
      .catch((error) => {
        console.warn('MUNIM_MAPS self-test crashed', error)
        setStatus(`Self-test crashed: ${String(error)}`)
      })
  }, [])

  return (
    <View style={styles.root}>
      {mode === 'munim' ? (
        <MunimMapView
          ref={munimRef}
          style={StyleSheet.absoluteFill}
          initialCamera={INITIAL_CAMERA}
          mapStyle="muted"
          models={models}
          lighting={lighting}
          onModelPress={setPressed}
          onError={(message) => console.warn('MUNIM_MAPS', message)}
        />
      ) : (
        <View style={StyleSheet.absoluteFill}>
          <MapView
            ref={rnMapRef}
            style={StyleSheet.absoluteFill}
            testID="rn-map"
            pitchEnabled
            rotateEnabled
            initialCamera={{
              center: STARBASE,
              pitch: INITIAL_CAMERA.pitch,
              heading: INITIAL_CAMERA.heading,
              altitude: 700,
              zoom: 16,
            }}
          />
          <MapModelLayer
            ref={layerRef}
            mapTestID="rn-map"
            models={models}
            lighting={lighting}
            onAttachChange={onAttachChange}
            onModelPress={setPressed}
            onError={(message) => console.warn('MUNIM_MAPS', message)}
          />
        </View>
      )}

      <View style={[styles.panel, { top: insets.top + 8 }]}>
        <View style={styles.row}>
          <Toggle label="MunimMapView" on={mode === 'munim'} onPress={() => setMode('munim')} />
          <Toggle label="react-native-maps" on={mode === 'rnmaps'} onPress={() => setMode('rnmaps')} />
        </View>
        <View style={styles.row}>
          <Toggle label={launching ? 'Launching' : 'Launch'} on={launching} onPress={() => setLaunching((v) => !v)} />
          <Toggle
            label={`Light: ${lighting}`}
            on={lighting !== 'auto'}
            onPress={() =>
              setLighting((v) => (v === 'auto' ? 'day' : v === 'day' ? 'night' : 'auto'))
            }
          />
        </View>
        <Text style={styles.status}>{status}</Text>
        {mode === 'rnmaps' ? (
          <Text style={styles.status}>{attached ? 'Layer attached to the map' : 'Looking for the map…'}</Text>
        ) : null}
        {pressed ? <Text style={styles.status}>Tapped: {pressed}</Text> : null}
      </View>
      <StatusBar style="auto" />
    </View>
  )
}

function Toggle(props: { label: string; on: boolean; onPress: () => void }) {
  return (
    <Pressable onPress={props.onPress} style={[styles.toggle, props.on && styles.toggleOn]}>
      <Text style={[styles.toggleText, props.on && styles.toggleTextOn]}>{props.label}</Text>
    </Pressable>
  )
}

export default function App() {
  return (
    <SafeAreaProvider>
      <Example />
    </SafeAreaProvider>
  )
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  panel: {
    position: 'absolute',
    left: 12,
    right: 12,
    padding: 10,
    borderRadius: 14,
    backgroundColor: 'rgba(20,20,24,0.72)',
    gap: 8,
  },
  row: { flexDirection: 'row', gap: 8 },
  toggle: {
    paddingHorizontal: 12,
    paddingVertical: 7,
    borderRadius: 999,
    backgroundColor: 'rgba(255,255,255,0.12)',
  },
  toggleOn: { backgroundColor: '#FFFFFF' },
  toggleText: { color: '#FFFFFF', fontSize: 13, fontWeight: '600' },
  toggleTextOn: { color: '#111111' },
  status: { color: '#FFFFFF', fontSize: 12 },
})
