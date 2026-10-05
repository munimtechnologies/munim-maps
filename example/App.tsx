import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { File, Paths } from 'expo-file-system'
import { StatusBar } from 'expo-status-bar'
import { Linking, Pressable, StyleSheet, Text, View } from 'react-native'
import { useSafeAreaInsets, SafeAreaProvider } from 'react-native-safe-area-context'
import MapView, { Circle } from 'react-native-maps'
import {
  MapModelLayer,
  MunimMapView,
  type MapCamera,
  type MapModel,
  type MapModelLayerRef,
  type MapZone,
  type MapModelLighting,
  type MunimMapViewRef,
} from 'munim-maps'
import { VEHICLES } from 'munim-maps/vehicles'
import { runSelfTest, type SelfTestReport, type TestMode } from './selftest'

const starship = require('./assets/starship.usdz')
const tower = require('./assets/tower.usdz')
const avatars = [
  require('./assets/avatar-a.png'),
  require('./assets/avatar-b.png'),
  require('./assets/avatar-c.png'),
  require('./assets/avatar-d.png'),
]

// The vehicle catalogue (scripts/vehicles/make-vehicles.swift). Paint is
// recoloured with `tint`, so each variant can come in any colour.
const vehicles = {
  sedan: VEHICLES['car-sedan'],
  hatchback: VEHICLES['car-hatchback'],
  suv: VEHICLES['car-suv'],
  sports: VEHICLES['car-sports'],
  pickup: VEHICLES['car-pickup'],
  taxi: VEHICLES['car-taxi'],
  police: VEHICLES['car-police'],
  roadBike: VEHICLES['bike-road'],
  mountainBike: VEHICLES['bike-mountain'],
  cityBike: VEHICLES['bike-city'],
  kickScooter: VEHICLES['scooter-kick'],
  moped: VEHICLES['scooter-moped'],
  speedboat: VEHICLES['boat-speed'],
  sailboat: VEHICLES['boat-sail'],
  airliner: VEHICLES['plane-airliner'],
  jet: VEHICLES['plane-jet'],
  propPlane: VEHICLES['plane-prop'],
}

type Mode = TestMode | 'elevation' | 'lag'

// Lag check: MapKit draws a blue ring (an MKCircle overlay, part of the map
// itself) and munim-maps draws a red puck at the same spot. While MapKit
// animates the camera, any frame of lag shows up as the puck sliding off the
// ring's centre in a screenshot. Opened with munimmapsexample://lagtest.
const LAG_CENTER = { latitude: 41.8838, longitude: -87.6305 }
const LAG_POINTS = [
  { latitude: 41.8843, longitude: -87.6311 },
  { latitude: 41.8832, longitude: -87.6300 },
  { latitude: 41.8838, longitude: -87.6305 },
]
const LAG_MODELS: MapModel[] = LAG_POINTS.map((coordinate, index) => ({
  id: `puck-${index}`,
  coordinate,
  shape: 'cylinder',
  size: { width: 6, height: 0.5, length: 6 },
  color: '#FF0000',
  emissive: true,
  groundShadow: false,
}))

// Friends at real heights in Chicago: floating avatars with a stem down to
// the spot under them. Heights are metres above the ground.
const CHICAGO_CAMERA: MapCamera = {
  latitude: 41.8838,
  longitude: -87.6305,
  distance: 2600,
  pitch: 62,
  heading: 20,
}
const ELEVATION_MODELS: MapModel[] = [
  { name: 'Skydeck, floor 103', at: [41.87888, -87.63591], height: 412, border: '#FF3B30', badge: '103F' },
  { name: 'Hancock, floor 94', at: [41.89886, -87.62294], height: 314, border: '#0A84FF', badge: '94F' },
  { name: 'Office, floor 4', at: [41.88535, -87.63178], height: 14, border: '#30D158', badge: '4F' },
  { name: 'Street level', at: [41.88261, -87.62332], height: 0, border: '#FFD60A', badge: '' },
].map((friend, index) => ({
  id: friend.name,
  coordinate: { latitude: friend.at[0]!, longitude: friend.at[1]! },
  altitude: friend.height,
  image: avatars[index],
  imageBorder: { color: friend.border, width: 3 },
  badge: friend.badge || undefined,
  screenSize: 46,
  stem: friend.height > 0 ? friend.border : false,
}))

// Friends on the move: a vehicle on the ground with the avatar riding above
// it (lift), power-ups as spinning gems with labels, and zone walls.
type Rider = {
  id: string
  at: [number, number]
  vehicle: number
  size: number
  heading: number
  tint?: string
  avatar?: number
  lift?: number
}
const RIDERS: Rider[] = [
  { id: 'sedan', at: [41.8841, -87.6244], vehicle: vehicles.sedan, size: 15, heading: 0, tint: '#2E6FD8', avatar: avatars[1], lift: 15 },
  { id: 'sports', at: [41.8853, -87.6244], vehicle: vehicles.sports, size: 13, heading: 180, tint: '#FF2D55' },
  { id: 'suv', at: [41.8865, -87.6244], vehicle: vehicles.suv, size: 16, heading: 0, tint: '#2F3437' },
  { id: 'pickup', at: [41.8877, -87.6244], vehicle: vehicles.pickup, size: 16, heading: 180, tint: '#8E5A2E' },
  { id: 'hatchback', at: [41.8853, -87.6262], vehicle: vehicles.hatchback, size: 15, heading: 90, tint: '#34C759' },
  { id: 'taxi', at: [41.8866, -87.6262], vehicle: vehicles.taxi, size: 15, heading: 270 },
  { id: 'police', at: [41.8879, -87.6262], vehicle: vehicles.police, size: 15, heading: 90 },
  { id: 'road-bike', at: [41.8812, -87.6175], vehicle: vehicles.roadBike, size: 22, heading: 10, tint: '#D7263D', avatar: avatars[2], lift: 22 },
  { id: 'mountain-bike', at: [41.8823, -87.6172], vehicle: vehicles.mountainBike, size: 22, heading: 190, tint: '#1F9D55' },
  { id: 'city-bike', at: [41.8834, -87.617], vehicle: vehicles.cityBike, size: 22, heading: 10, tint: '#AF52DE' },
  { id: 'kick-scooter', at: [41.8862, -87.6283], vehicle: vehicles.kickScooter, size: 22, heading: 90, tint: '#30D158', avatar: avatars[3], lift: 20 },
  { id: 'moped', at: [41.885, -87.6283], vehicle: vehicles.moped, size: 18, heading: 270, tint: '#7FC8C0' },
  { id: 'speedboat', at: [41.8885, -87.612], vehicle: vehicles.speedboat, size: 14, heading: 30, tint: '#1E3A5F' },
  { id: 'sailboat', at: [41.886, -87.6105], vehicle: vehicles.sailboat, size: 30, heading: 120 },
]
const MOVING: MapModel[] = RIDERS.flatMap((rider) => {
  const coordinate = { latitude: rider.at[0], longitude: rider.at[1] }
  const vehicle: MapModel = {
    id: `${rider.id}-vehicle`,
    coordinate,
    source: rider.vehicle,
    heading: rider.heading,
    screenSize: rider.size,
    tint: rider.tint,
  }
  if (!rider.avatar) return [vehicle]
  return [
    vehicle,
    {
      id: `${rider.id}-rider`,
      coordinate,
      image: rider.avatar,
      imageBorder: { color: '#FFFFFF', width: 3 },
      screenSize: 40,
      lift: rider.lift,
    },
  ]
})
const FLYING: MapModel[] = [
  { id: 'airliner', at: [41.8905, -87.6105], source: vehicles.airliner, altitude: 160, heading: 200, size: 14, tint: '#0A4DA2', label: '✈️ In the air' },
  { id: 'jet', at: [41.893, -87.618], source: vehicles.jet, altitude: 120, heading: 250, size: 13, tint: '#8E1B1B' },
  { id: 'prop', at: [41.879, -87.614], source: vehicles.propPlane, altitude: 90, heading: 330, size: 16, tint: '#FF9F0A' },
].map((plane) => ({
  id: plane.id,
  coordinate: { latitude: plane.at[0]!, longitude: plane.at[1]! },
  source: plane.source,
  altitude: plane.altitude,
  heading: plane.heading,
  screenSize: plane.size,
  tint: plane.tint,
  stem: '#FFFFFF',
  label: plane.label,
}))
const POWER_UPS: MapModel[] = [
  { id: 'revive', at: [41.8826, -87.6275], color: '#FF2D55', label: '❤️ Revive' },
  { id: 'vanish', at: [41.8796, -87.6291], color: '#5E5CE6', label: '👻 Vanish' },
  { id: 'shield', at: [41.8812, -87.6305], color: '#0A84FF', label: '🛡️ Immunity shield' },
  { id: 'trace', at: [41.884, -87.631], color: '#FF9F0A', label: '🧭 Trace' },
  { id: 'steal', at: [41.88, -87.6255], color: '#30D158', label: '💸 Steal credits' },
].map((drop) => ({
  id: drop.id,
  coordinate: { latitude: drop.at[0]!, longitude: drop.at[1]! },
  shape: 'gem' as const,
  color: drop.color,
  emissive: true,
  screenSize: 28,
  spinDegreesPerSecond: 90,
  label: drop.label,
}))
const CITY_MODELS: MapModel[] = [...ELEVATION_MODELS, ...MOVING, ...FLYING, ...POWER_UPS]
const CITY_ZONES: MapZone[] = [
  {
    id: 'park',
    circle: { center: { latitude: 41.8826, longitude: -87.6226 }, radius: 260 },
    height: 60,
    color: '#FF3B3040',
  },
  {
    id: 'block',
    polygon: [
      { latitude: 41.8870, longitude: -87.6330 },
      { latitude: 41.8870, longitude: -87.6290 },
      { latitude: 41.8845, longitude: -87.6290 },
      { latitude: 41.8845, longitude: -87.6330 },
    ],
    height: 45,
    color: '#30D15840',
  },
]

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
  const [mode, setMode] = useState<Mode>('munim')
  const [orbiting, setOrbiting] = useState(false)
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
    void Linking.getInitialURL().then((url) => {
      if (url?.includes('lagtest')) {
        setLaunching(false)
        setStatus('Lag test')
        setMode('lag')
        setOrbiting(true)
      } else {
        startSelfTest()
      }
    })
  }, [])

  function startSelfTest() {
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
        setMode('elevation')
        setOrbiting(true)
      })
      .catch((error) => {
        console.warn('MUNIM_MAPS self-test crashed', error)
        setStatus(`Self-test crashed: ${String(error)}`)
      })
  }

  // Turns the camera a quarter at a time with MapKit's own animation, which
  // is the motion to watch (or screen-record) for lag.
  // Lag test: pan 300 m back and forth with MapKit's own animation.
  useEffect(() => {
    if (!orbiting || mode !== 'lag') return
    let east = false
    const timer = setInterval(() => {
      east = !east
      rnMapRef.current?.animateCamera(
        {
          center: {
            latitude: LAG_CENTER.latitude,
            longitude: LAG_CENTER.longitude + (east ? 0.0012 : -0.0012),
          },
        },
        { duration: 1500 }
      )
    }, 1200)
    return () => clearInterval(timer)
  }, [orbiting, mode])

  useEffect(() => {
    if (!orbiting || mode === 'rnmaps' || mode === 'lag') return
    const timer = setInterval(async () => {
      const map = munimRef.current
      if (!map) return
      const camera = await map.getCamera()
      map.setCamera({ ...camera, heading: (camera.heading + 90) % 360 }, true)
    }, 2500)
    return () => clearInterval(timer)
  }, [orbiting, mode])

  return (
    <View style={styles.root}>
      {mode === 'elevation' ? (
        <MunimMapView
          key="elevation"
          ref={munimRef}
          style={StyleSheet.absoluteFill}
          initialCamera={CHICAGO_CAMERA}
          models={CITY_MODELS}
          zones={CITY_ZONES}
          lighting={lighting}
          onModelPress={setPressed}
          onError={(message) => console.warn('MUNIM_MAPS', message)}
        />
      ) : mode === 'lag' ? (
        <View style={StyleSheet.absoluteFill}>
          <MapView
            ref={rnMapRef}
            style={StyleSheet.absoluteFill}
            testID="lag-map"
            mapType="mutedStandard"
            showsPointsOfInterests={false}
            showsBuildings={false}
            initialCamera={{ center: LAG_CENTER, pitch: 0, heading: 0, altitude: 1500, zoom: 15 }}
          >
            {LAG_POINTS.map((point, index) => (
              <Circle
                key={index}
                center={point}
                radius={9}
                strokeWidth={3}
                strokeColor="#0000FF"
                fillColor="rgba(0,0,0,0)"
              />
            ))}
          </MapView>
          <MapModelLayer mapTestID="lag-map" models={LAG_MODELS} lighting="day" />
        </View>
      ) : mode === 'munim' ? (
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
          <Toggle label="Elevation" on={mode === 'elevation'} onPress={() => setMode('elevation')} />
        </View>
        <View style={styles.row}>
          <Toggle label={launching ? 'Launching' : 'Launch'} on={launching} onPress={() => setLaunching((v) => !v)} />
          <Toggle label="Orbit" on={orbiting} onPress={() => setOrbiting((v) => !v)} />
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
