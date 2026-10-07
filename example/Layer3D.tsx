import { useEffect, useMemo, useRef, useState } from 'react'
import { Pressable, StyleSheet, Text, View } from 'react-native'
import {
  MunimMapView,
  defaultProvider,
  groundElevation,
  type MapAlignmentReport,
  type MapCamera,
  type MapModel,
  type MapPath,
  type MapProvider,
  type MapZone,
  type MunimMapViewRef,
} from 'munim-maps'
import { VEHICLES } from 'munim-maps-vehicles'

/**
 * Every group of the 3D layer on one engine: GLB vehicles (tint, screen
 * size, motion), built-in shapes, pictures (avatars with rings, badges,
 * stems, lift), labels, zones, 3D paths, effects (exhaust, smoke,
 * contrail), an occluder, building occlusion, a model above sea level, and
 * `flyCamera`. "Run checks" (or munimmapsexample://layer3d/<provider>/check)
 * measures the layer against the engine's own projection at several cameras
 * and mid-flight, and logs `MUNIM_MAPS_LAYER3D {…}`.
 */

export const CENTER = { latitude: 41.8826, longitude: -87.6278 }
const CAMERA: MapCamera = { ...CENTER, distance: 900, pitch: 55, heading: 30 }

const avatars = [
  require('./assets/avatar-a.png'),
  require('./assets/avatar-b.png'),
  require('./assets/avatar-c.png'),
]

const SHAPES = ['box', 'sphere', 'cylinder', 'cone', 'capsule', 'pyramid', 'gem'] as const
const SHAPE_COLORS = ['#0A84FF', '#FF9F0A', '#30D158', '#FF375F', '#BF5AF2', '#FFD60A', '#64D2FF']

export function buildModels(start: number): MapModel[] {
  const shapes: MapModel[] = SHAPES.map((shape, i) => ({
    id: `shape-${shape}`,
    coordinate: { latitude: 41.8838, longitude: -87.6302 + i * 0.00032 },
    shape,
    size: { width: 14, height: shape === 'cylinder' || shape === 'cone' ? 22 : 14, length: 14 },
    color: SHAPE_COLORS[i],
    emissive: shape === 'gem',
    spinDegreesPerSecond: shape === 'gem' ? 45 : 0,
  }))
  return [
    ...shapes,
    { id: 'glass', coordinate: { latitude: 41.8842, longitude: -87.6302 }, shape: 'box', size: { width: 20, height: 30, length: 8 }, color: '#FF3B3080' },
    {
      id: 'bus',
      coordinate: { latitude: 41.8790, longitude: -87.62766 },
      source: VEHICLES['bus-city'],
      tint: '#0A84FF',
      label: 'Route 29',
      motion: {
        start,
        loop: true,
        keyframes: [
          { t: 0, coordinate: { latitude: 41.8790, longitude: -87.62766 } },
          { t: 60, coordinate: { latitude: 41.8889, longitude: -87.62797 } },
          { t: 120, coordinate: { latitude: 41.8790, longitude: -87.62766 } },
        ],
      },
    },
    { id: 'taxi', coordinate: { latitude: 41.8822, longitude: -87.6271 }, source: VEHICLES['car-taxi'], heading: 90, screenSize: 22, label: 'Taxi' },
    { id: 'police', coordinate: { latitude: 41.8833, longitude: -87.6268 }, source: VEHICLES['car-police'], heading: 180, screenSize: 22 },
    // Hides the police car's front half, like a wall would.
    { id: 'wall', coordinate: { latitude: 41.8831, longitude: -87.6268 }, shape: 'box', size: { width: 30, height: 12, length: 2 }, occluder: true },
    {
      id: 'friend-a',
      coordinate: { latitude: 41.8829, longitude: -87.6262 },
      altitude: 30,
      image: avatars[0],
      imageBorder: { color: '#34C759', width: 3 },
      badge: '8F',
      stem: '#34C759',
    },
    { id: 'friend-b', coordinate: { latitude: 41.8822, longitude: -87.6271 }, image: avatars[1], lift: 36, imageBorder: { color: '#FFFFFF' } },
    { id: 'friend-c', coordinate: { latitude: 41.8817, longitude: -87.6290 }, image: avatars[2], label: 'Sam', screenSize: 40 },
    {
      id: 'starship',
      coordinate: { latitude: 41.8806, longitude: -87.6315 },
      altitude: 140,
      source: VEHICLES['rocket-starship'],
      effect: 'exhaust',
      stem: true,
    },
    { id: 'pad-smoke', coordinate: { latitude: 41.8806, longitude: -87.6315 }, effect: 'smoke', size: { width: 80, height: 40 } },
    {
      id: 'jet',
      coordinate: { latitude: 41.8850, longitude: -87.6330 },
      source: VEHICLES['plane-jet'],
      screenSize: 30,
      effect: 'contrail',
      motion: {
        start,
        loop: true,
        keyframes: [
          { t: 0, coordinate: { latitude: 41.8850, longitude: -87.6340 }, altitude: 300 },
          { t: 40, coordinate: { latitude: 41.8800, longitude: -87.6220 }, altitude: 300 },
        ],
      },
    },
    // 250 m above sea level: Chicago's ground is about 180 m, so this floats about 70 m up.
    { id: 'sea-sphere', coordinate: { latitude: 41.8812, longitude: -87.6255 }, altitude: 250, altitudeReference: 'sea', shape: 'sphere', size: { width: 12, height: 12, length: 12 }, color: '#FF9F0A', stem: '#FF9F0A' },
  ]
}

export const ZONES: MapZone[] = [
  { id: 'loop', circle: { center: CENTER, radius: 120 }, height: 40, color: '#0A84FF40' },
  {
    id: 'block',
    polygon: [
      { latitude: 41.8841, longitude: -87.6262 },
      { latitude: 41.8841, longitude: -87.6248 },
      { latitude: 41.8832, longitude: -87.6248 },
      { latitude: 41.8832, longitude: -87.6262 },
    ],
    height: 25,
    color: '#FF375F55',
  },
]

export const PATHS: MapPath[] = [
  {
    id: 'flight',
    coordinates: [
      { latitude: 41.8850, longitude: -87.6340, altitude: 300 },
      { latitude: 41.8800, longitude: -87.6220, altitude: 300 },
    ],
    color: '#FFFFFFCC',
    width: 3,
  },
  {
    id: 'ring',
    coordinates: [
      { latitude: 41.8815, longitude: -87.6300, altitude: 60 },
      { latitude: 41.8815, longitude: -87.6250, altitude: 120 },
      { latitude: 41.8840, longitude: -87.6250, altitude: 60 },
      { latitude: 41.8840, longitude: -87.6300, altitude: 120 },
    ],
    color: '#FFD60A',
    width: 4,
    closed: true,
  },
  {
    id: 'sea-path',
    coordinates: [
      { latitude: 41.8805, longitude: -87.6265, altitude: 230 },
      { latitude: 41.8812, longitude: -87.6255, altitude: 250 },
    ],
    altitudeReference: 'sea',
    color: '#FF9F0A',
    width: 3,
  },
]

const POSES: Partial<MapCamera>[] = [
  { distance: 900, pitch: 55, heading: 30 },
  { distance: 400, pitch: 70, heading: 120 },
  { distance: 2500, pitch: 0, heading: 0 },
  { distance: 1500, pitch: 45, heading: 250 },
  { distance: 250, pitch: 60, heading: 300 },
  { distance: 6000, pitch: 30, heading: 75 },
]

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms))

export function Layer3DScreen(props: {
  provider?: MapProvider
  autoCheck?: boolean
  /** munimmapsexample://layer3d/cam/lat,lon,distance,pitch,heading */
  camera?: MapCamera
  /** munimmapsexample://layer3d/noocclusion */
  occlusion?: boolean
  topInset: number
  /** Back to the engine picker. */
  onExit?: () => void
}) {
  const provider = props.provider ?? defaultProvider()
  const ref = useRef<MunimMapViewRef | null>(null)
  const [start] = useState(() => Date.now() / 1000)
  const models = useMemo(() => buildModels(start), [start])
  const [buildings, setBuildings] = useState(props.occlusion ?? true)
  const [status, setStatus] = useState('')
  const [errors, setErrors] = useState<string[]>([])
  const [pressed, setPressed] = useState('')
  const [ready, setReady] = useState(false)
  const ran = useRef(false)

  async function runChecks() {
    const map = ref.current
    if (!map) return
    setStatus('Checking…')
    const results: { camera: Partial<MapCamera>; report: MapAlignmentReport }[] = []
    for (const pose of POSES) {
      map.setCamera({ ...CENTER, distance: 900, pitch: 0, heading: 0, ...pose }, false)
      await wait(2500)
      const report = await map.measureAlignment()
      results.push({ camera: pose, report })
      console.log(`MUNIM_MAPS_LAYER3D pose ${JSON.stringify({ pose, report })}`)
    }
    // A flight: the layer steps it on its own frame clock.
    const flightStart = Date.now() / 1000
    map.flyCamera(
      [
        { t: 0, camera: { ...CENTER, distance: 1200, pitch: 50, heading: 0 } },
        { t: 4, camera: { latitude: 41.8806, longitude: -87.6315, distance: 500, pitch: 65, heading: 90 } },
        { t: 8, camera: { ...CENTER, distance: 2000, pitch: 40, heading: 200 } },
      ],
      flightStart,
      false
    )
    const flight: MapAlignmentReport[] = []
    for (const at of [1.5, 3, 5, 6.5]) {
      await wait(Math.max(0, (flightStart + at) * 1000 - Date.now()))
      const report = await map.measureAlignment()
      flight.push(report)
      console.log(`MUNIM_MAPS_LAYER3D flight ${JSON.stringify({ at, report })}`)
    }
    await wait(2500)
    const camera = await map.getCamera()
    let ground: number[] | string = []
    try {
      ground = await groundElevation([CENTER, { latitude: 37.7459, longitude: -119.5332 }])
    } catch (error) {
      ground = String(error)
    }
    const all = [...results.map((r) => r.report), ...flight].filter((r) => r.modelsMeasured > 0)
    const summary = {
      provider,
      poses: results.length,
      flightSamples: flight.length,
      maxErrorPoints: Math.max(0, ...all.map((r) => r.maxErrorPoints)),
      meanErrorPoints: all.reduce((sum, r) => sum + r.meanErrorPoints, 0) / Math.max(1, all.length),
      flightMaxErrorPoints: Math.max(0, ...flight.map((r) => r.maxErrorPoints)),
      flightEndCamera: camera,
      groundElevation: ground,
      errors,
    }
    console.log(`MUNIM_MAPS_LAYER3D summary ${JSON.stringify(summary)}`)
    setStatus(
      `max ${summary.maxErrorPoints.toFixed(2)} pt, mean ${summary.meanErrorPoints.toFixed(2)} pt over ${all.length} cameras · flight max ${summary.flightMaxErrorPoints.toFixed(2)} pt`
    )
    map.setCamera(props.camera ?? CAMERA, false)
  }

  useEffect(() => {
    if (!ready || !props.autoCheck || ran.current) return
    ran.current = true
    // Let tiles and models load first.
    setTimeout(() => void runChecks(), 4000)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ready, props.autoCheck])

  return (
    <View style={StyleSheet.absoluteFill}>
      <MunimMapView
        ref={ref}
        provider={provider}
        style={StyleSheet.absoluteFill}
        initialCamera={props.camera ?? CAMERA}
        models={models}
        zones={ZONES}
        paths={PATHS}
        occlusion={buildings ? 'buildings' : 'none'}
        lighting="day"
        onModelPress={(id) => {
          setPressed(id)
          console.log(`MUNIM_MAPS_LAYER3D pressed ${id}`)
        }}
        onPress={(event) => console.log(`MUNIM_MAPS_LAYER3D map press ${event.x.toFixed(0)},${event.y.toFixed(0)}`)}
        onMapReady={() => setReady(true)}
        onError={(message) => {
          console.log(`MUNIM_MAPS_LAYER3D error ${message}`)
          setErrors((list) => (list.includes(message) ? list : [...list, message].slice(-4)))
        }}
      />
      <View style={[styles.panel, { top: props.topInset + 8 }]}>
        <View style={styles.row}>
          {props.onExit ? (
            <Pressable style={styles.chip} onPress={props.onExit}>
              <Text style={styles.chipText}>‹ Engines</Text>
            </Pressable>
          ) : null}
          <Pressable style={styles.chip} onPress={() => void runChecks()}>
            <Text style={styles.chipText}>Run checks</Text>
          </Pressable>
          <Pressable style={[styles.chip, buildings && styles.chipOn]} onPress={() => setBuildings((b) => !b)}>
            <Text style={[styles.chipText, buildings && styles.chipTextOn]}>Buildings hide models</Text>
          </Pressable>
        </View>
        <Text style={styles.status}>3D layer on {provider}{status ? ` · ${status}` : ''}</Text>
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
  chipText: { color: '#FFFFFF', fontSize: 13, fontWeight: '600' },
  chipTextOn: { color: '#111111' },
  status: { color: '#FFFFFF', fontSize: 12 },
  error: { color: '#FFB4A9', fontSize: 11 },
})
