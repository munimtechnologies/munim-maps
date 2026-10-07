import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { File, Paths } from 'expo-file-system'
import { StatusBar } from 'expo-status-bar'
import { Linking, Pressable, StyleSheet, Text, View } from 'react-native'
import { useSafeAreaInsets, SafeAreaProvider } from 'react-native-safe-area-context'
import MapView, { Circle } from 'react-native-maps'
import { AppleMaps } from 'expo-maps'
import {
  MapModelLayer,
  MunimMapView,
  groundElevation,
  type MapPath,
  type MapCamera,
  type MapModel,
  type MapModelLayerRef,
  type MapZone,
  type MapMarker,
  type MapPolyline,
  type MapPolygon,
  type MapCircle,
  type MapTileOverlay,
  type MapModelLighting,
  type MunimMapViewRef,
} from 'munim-maps'
import { VEHICLES } from 'munim-maps/vehicles'
import { Demo, SHOTS, type Shot } from './Demo'
import { ORBIT_PATHS, satelliteModels } from './orbits'
import { runSelfTest, type SelfTestReport, type TestMode } from './selftest'
import { ParityScreen, type ParityHandle } from './Parity'
import type { UserTrackingMode } from 'munim-maps'

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

type Mode = TestMode | 'elevation' | 'lag' | 'features' | 'space'

// Terrain: Half Dome and Yosemite Valley, with heights above sea level
// (`altitudeReference: 'sea'`), the way a phone reports them. munim-maps
// looks up the ground under each model and takes it off.
const HALF_DOME = { latitude: 37.74602, longitude: -119.53313 }
const GLACIER_POINT = { latitude: 37.73065, longitude: -119.57357 }
const VALLEY = { latitude: 37.7395, longitude: -119.5735 }
const TERRAIN_CAMERA: MapCamera = { latitude: 37.738, longitude: -119.565, distance: 8000, pitch: 40, heading: 60 }
const TERRAIN_MODELS: MapModel[] = [
  {
    id: 'summit',
    coordinate: HALF_DOME,
    altitude: 2694 + 2, // a hiker on the summit, 2,694 m above sea level
    altitudeReference: 'sea',
    image: avatars[0],
    imageBorder: { color: '#FF9F0A', width: 3 },
    badge: '2694 m',
    screenSize: 44,
    stem: '#FF9F0A',
  },
  {
    // Above the ground (the default), kept on the 3D terrain by followTerrain.
    id: 'glacier-point',
    coordinate: GLACIER_POINT,
    shape: 'gem',
    color: '#30D158',
    emissive: true,
    screenSize: 26,
    spinDegreesPerSecond: 90,
    label: 'Glacier Point',
  },
  {
    id: 'balloon',
    coordinate: VALLEY,
    altitude: 1800, // about 600 m above the valley floor
    altitudeReference: 'sea',
    source: VEHICLES.balloon,
    screenSize: 40,
    stem: '#FFFFFF',
    label: '1800 m above sea level',
  },
]
const TERRAIN_PATHS: MapPath[] = [
  {
    id: 'zipline',
    coordinates: [
      { ...GLACIER_POINT, altitude: 2199 + 40 },
      { ...HALF_DOME, altitude: 2694 + 40 },
    ],
    altitudeReference: 'sea',
    color: '#FF9F0AFF',
    width: 3,
  },
]

// expo-maps (SwiftUI's Map) with munim-maps drawn over it.
const EXPO_MAPS_ZOOM = 16

// Map features on MunimMapView: every marker style, shapes, a tile overlay.
const LOOP = { latitude: 41.8826, longitude: -87.6233 }
const FEATURE_CAMERA: MapCamera = { latitude: 41.8835, longitude: -87.6290, distance: 7000, pitch: 0, heading: 0 }
const CAFES = Array.from({ length: 6 }, (_, i) => ({
  latitude: 41.8865 + (i % 3) * 0.0006,
  longitude: -87.6335 + Math.floor(i / 3) * 0.0008,
}))
const FEATURE_MARKERS: MapMarker[] = [
  { id: 'pin', coordinate: { latitude: 41.8789, longitude: -87.6359 }, style: 'pin', color: '#FF3B30', title: 'Willis Tower', subtitle: '233 S Wacker Dr', callout: true },
  { id: 'pizza', coordinate: { latitude: 41.8921, longitude: -87.6264 }, style: 'marker', glyph: '🍕', color: '#FF9F0A', title: 'Pizza', callout: true },
  {
    id: 'friend',
    coordinate: { latitude: 41.8853, longitude: -87.6318 },
    style: 'avatar',
    image: avatars[1],
    size: 46,
    border: { color: '#0A84FF', width: 3 },
    badges: [
      { text: '5F', position: 'top-left' },
      { text: '🚗', position: 'bottom-right', color: '#FFFFFF' },
    ],
  },
  { id: 'park-label', coordinate: LOOP, style: 'label', title: 'Millennium Park', color: '#30D158' },
  { id: 'dot', coordinate: { latitude: 41.8807, longitude: -87.6278 }, style: 'dot', color: '#AF52DE', size: 16 },
  { id: 'photo', coordinate: { latitude: 41.8758, longitude: -87.6244 }, style: 'image', image: avatars[2], size: 40 },
  { id: 'drag-me', coordinate: { latitude: 41.8735, longitude: -87.6305 }, style: 'marker', glyph: '✋', color: '#5856D6', title: 'Drag me', draggable: true },
  ...CAFES.map((coordinate, i) => ({
    id: `cafe-${i}`,
    coordinate,
    style: 'marker' as const,
    glyph: '☕️',
    color: '#8D6E63',
    clusteringId: 'cafes',
  })),
]
const FEATURE_POLYLINES: MapPolyline[] = [
  { id: 'route', coordinates: [{ latitude: 41.8789, longitude: -87.6359 }, { latitude: 41.8826, longitude: -87.6290 }, { latitude: 41.8921, longitude: -87.6264 }], strokeColor: '#0A84FF', strokeWidth: 5 },
  { id: 'dashed', coordinates: [{ latitude: 41.8735, longitude: -87.6305 }, { latitude: 41.8758, longitude: -87.6244 }], strokeColor: '#FF2D55', strokeWidth: 3, dashPattern: [6, 8] },
]
const FEATURE_POLYGONS: MapPolygon[] = [
  {
    id: 'block',
    coordinates: [
      { latitude: 41.8870, longitude: -87.6240 },
      { latitude: 41.8870, longitude: -87.6190 },
      { latitude: 41.8840, longitude: -87.6190 },
      { latitude: 41.8840, longitude: -87.6240 },
    ],
    holes: [[
      { latitude: 41.8860, longitude: -87.6225 },
      { latitude: 41.8860, longitude: -87.6205 },
      { latitude: 41.8850, longitude: -87.6205 },
      { latitude: 41.8850, longitude: -87.6225 },
    ]],
    strokeColor: '#FF9F0A',
    fillColor: '#FF9F0A33',
  },
]
const FEATURE_CIRCLES: MapCircle[] = [
  { id: 'radius', center: { latitude: 41.8807, longitude: -87.6278 }, radius: 250, strokeColor: '#AF52DE', fillColor: '#AF52DE22', dashPattern: [4, 6] },
]
const TERRAIN_TILES: MapTileOverlay[] = [
  { id: 'terrain', urlTemplate: 'https://s3.amazonaws.com/elevation-tiles-prod/normal/{z}/{x}/{y}.png', opacity: 0.35 },
]

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
// Cities around the world for the globe screen.
const GLOBE_CITIES: [string, number, number, string][] = [
  ['nyc', 40.7128, -74.006, '#FF453A'],
  ['london', 51.5072, -0.1276, '#FF9F0A'],
  ['paris', 48.8566, 2.3522, '#FFD60A'],
  ['cairo', 30.0444, 31.2357, '#30D158'],
  ['rio', -22.9068, -43.1729, '#64D2FF'],
  ['lagos', 6.5244, 3.3792, '#0A84FF'],
  ['tokyo', 35.6762, 139.6503, '#BF5AF2'],
  ['sydney', -33.8688, 151.2093, '#FF375F'],
  ['honolulu', 21.3069, -157.8583, '#FF9F0A'],
  ['anchorage', 61.2181, -149.9003, '#64D2FF'],
  ['lima', -12.0464, -77.0428, '#30D158'],
  ['chicago', 41.8781, -87.6298, '#FFD60A'],
  ['berlin', 52.52, 13.405, '#FF453A'],
  ['reykjavik', 64.1466, -21.9426, '#0A84FF'],
  ['capetown', -33.9249, 18.4241, '#BF5AF2'],
  ['mumbai', 19.076, 72.8777, '#FF375F'],
]
const GLOBE_MODELS: MapModel[] = GLOBE_CITIES.map(([id, latitude, longitude, color]) => ({
  id: `globe-${id}`,
  coordinate: { latitude, longitude },
  shape: 'gem',
  color,
  emissive: true,
  screenSize: 22,
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
    tower: { latitude: 25.997045, longitude: -97.15713 },
    mount: { latitude: 25.99717, longitude: -97.15696 },
    heading: 51,
  },
  {
    id: 'b',
    tower: { latitude: 25.99629, longitude: -97.154675 },
    mount: { latitude: 25.99643, longitude: -97.15452 },
    heading: 45,
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
    models.push({ id: `tower-${pad.id}`, coordinate: pad.tower, source: VEHICLES['starbase-tower'], heading: pad.heading })
    models.push({ id: `mount-${pad.id}`, coordinate: pad.mount, source: VEHICLES['starbase-mount'], heading: pad.heading })
    models.push({
      id: `ship-${pad.id}`,
      coordinate: pad.mount,
      source: VEHICLES['rocket-starship'],
      altitude: altitude + 20,
      heading: pad.heading,
      groundShadow: altitude < 50,
      effect: altitude > 0 ? 'exhaust' : undefined,
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
  const [tiles, setTiles] = useState(false)
  const [globe, setGlobe] = useState(false)
  const [demoShot, setDemoShot] = useState<Shot | null>(null)
  const [globeSwitch, setGlobeSwitch] = useState(true)
  const [globeStyle, setGlobeStyle] = useState<'standard' | 'hybrid'>('standard')
  const [lastEvent, setLastEvent] = useState('')
  const featuresReady = useRef(false)
  const [lighting, setLighting] = useState<MapModelLighting>('auto')
  const [launching, setLaunching] = useState(true)
  const [status, setStatus] = useState('Running self-test…')
  const [pressed, setPressed] = useState<string | null>(null)
  const [attached, setAttached] = useState(false)
  const [terrainFlat, setTerrainFlat] = useState(false)
  const [terrainHybrid, setTerrainHybrid] = useState(true)
  const [panel, setPanel] = useState(true)
  const [terrainHeights, setTerrainHeights] = useState('')
  const [expoAttached, setExpoAttached] = useState(false)
  // munimmapsexample://expomaps/nearest: no testID, so the layer finds the map itself.
  const [expoNearest, setExpoNearest] = useState(false)
  const expoAttachedRef = useRef(false)
  const expoLayerRef = useRef<MapModelLayerRef | null>(null)
  const expoMapRef = useRef<AppleMaps.MapView | null>(null)
  // The MapKit parity screen.
  const [trackingMode, setTrackingMode] = useState<UserTrackingMode>('none')
  const [parityFollow, setParityFollow] = useState(false)
  const [parityDemo, setParityDemo] = useState('')
  const parityHandle = useRef<ParityHandle>({ route: null, completions: [], trackingEvents: [] })
  const seconds = useLaunchClock(launching)
  const models = useMemo(() => buildModels(seconds, launching), [seconds, launching])
  const satellites = useMemo(() => (mode === 'space' ? satelliteModels(seconds) : []), [mode, seconds])

  // Drift slowly round the Earth on the satellite screen.
  useEffect(() => {
    if (mode !== 'space' || !orbiting) return
    munimRef.current?.setCamera(
      { latitude: 22, longitude: -55 + seconds * 2, distance: 24_000_000, pitch: 0, heading: 0 },
      false
    )
  }, [mode, orbiting, seconds])

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
  const onExpoAttachChange = useCallback((value: boolean) => {
    expoAttachedRef.current = value
    setExpoAttached(value)
  }, [])

  // The same ground heights munim-maps uses for the terrain screen.
  useEffect(() => {
    if (mode !== 'terrain') return
    groundElevation([HALF_DOME, VALLEY])
      .then(([dome, valley]) =>
        setTerrainHeights(`Ground: Half Dome ${dome!.toFixed(0)} m, valley ${valley!.toFixed(0)} m`)
      )
      .catch((error) => setTerrainHeights(`groundElevation failed: ${String(error)}`))
  }, [mode])

  const ran = useRef(false)
  useEffect(() => {
    if (ran.current) return
    ran.current = true
    void Linking.getInitialURL().then((url) => {
      if (url?.includes('nopanel')) setPanel(false)
      const shot = /demo\/(\w+)/.exec(url ?? '')?.[1] as Shot | undefined
      if (shot && SHOTS.includes(shot)) {
        setLaunching(false)
        setDemoShot(shot)
      } else if (url?.includes('orbit')) {
        setStatus('Satellites')
        if (url.includes('still')) setLaunching(false)
        setMode('space')
      } else if (url?.includes('cities')) {
        setLaunching(false)
        setStatus('Globe: cities')
        if (url.includes('hybrid')) setGlobeStyle('hybrid')
        if (url.includes('noglobe')) setGlobeSwitch(false)
        setMode('globe')
        const far = /far(\d+)/.exec(url)
        if (far) {
          setTimeout(() => {
            munimRef.current?.setCamera(
              url.includes('eu') ? { latitude: 50, longitude: 5, distance: Number(far[1]) * 1000, pitch: 0, heading: 0 } : { latitude: 25, longitude: -30, distance: Number(far[1]) * 1000, pitch: 0, heading: 0 },
              false
            )
          }, 3000)
        }
      } else if (url?.includes('munimglobe')) {
        setLaunching(false)
        setStatus('Globe: MunimMapView standard + globe')
        setGlobe(true)
        setMode('elevation')
        setTimeout(() => {
          munimRef.current?.setCamera({ latitude: 30, longitude: -60, distance: 25_000_000, pitch: 0, heading: 0 }, true)
        }, 3000)
      } else if (url?.includes('globe')) {
        setLaunching(false)
        setStatus('Globe: react-native-maps flat standard + globe')
        setGlobe(true)
        setMode('rnmaps')
        setTimeout(() => {
          rnMapRef.current?.animateCamera(
            { center: { latitude: 30, longitude: -60 }, altitude: 25_000_000, pitch: 0, heading: 0 },
            { duration: 1 }
          )
        }, 3000)
      } else if (url?.includes('terrain')) {
        setLaunching(false)
        setStatus('Terrain: heights above sea level')
        if (url.includes('flat')) setTerrainFlat(true)
        if (url.includes('standard')) setTerrainHybrid(false)
        setMode('terrain')
        // munimmapsexample://terrain/cam/lat,lon,distance,pitch,heading
        const cam = /cam\/([-\d.,]+)/.exec(url)?.[1]?.split(',').map(Number)
        if (cam?.length === 5) {
          const [latitude, longitude, distance, pitch, heading] = cam as [number, number, number, number, number]
          setTimeout(() => munimRef.current?.setCamera({ latitude, longitude, distance, pitch, heading }, false), 2500)
        }
      } else if (url?.includes('expomaps')) {
        setStatus('expo-maps')
        if (url.includes('nearest')) setExpoNearest(true)
        setMode('expomaps')
      } else if (url?.includes('parity')) {
        setLaunching(false)
        setStatus('MapKit parity')
        if (url.includes('follow')) setParityFollow(true)
        setParityDemo(/parity\/(placecard|callout)/.exec(url)?.[1] ?? '')
        setMode('parity')
      } else if (url?.includes('features')) {
        setLaunching(false)
        setStatus('Features')
        setMode('features')
        // munimmapsexample://features/select/<marker id>: select a marker without a tap.
        const selected = /select\/([\w-]+)/.exec(url)?.[1]
        if (selected) setTimeout(() => munimRef.current?.selectMarker(selected), 3000)
      } else if (url?.includes('lagtest')) {
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
        featuresReady: () => featuresReady.current,
        markerIds: () => FEATURE_MARKERS.map((m) => m.id),
        setGlobeStyle,
        waitForLayerAttached: async (timeoutMs) => {
          const end = Date.now() + timeoutMs
          while (Date.now() < end) {
            if (attachedRef.current) return true
            await new Promise((resolve) => setTimeout(resolve, 100))
          }
          return attachedRef.current
        },
        expoLayer: () => expoLayerRef.current,
        setExpoMapsZoom: (center, zoom) =>
          expoMapRef.current?.setCameraPosition({ coordinates: center, zoom }),
        setTerrainView: (flat, satellite) => {
          setTerrainFlat(flat)
          setTerrainHybrid(satellite)
        },
        parity: () => parityHandle.current,
        setTrackingMode,
        waitForExpoLayerAttached: async (timeoutMs) => {
          const end = Date.now() + timeoutMs
          while (Date.now() < end) {
            if (expoAttachedRef.current) return true
            await new Promise((resolve) => setTimeout(resolve, 100))
          }
          return expoAttachedRef.current
        },
      },
      STARBASE
    )
      .then((report) => {
        writeReport(report)
        setStatus(`Self-test: ${report.passed} passed, ${report.failed} failed`)
        setMode(report.failed > 0 ? 'features' : 'elevation')
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
    if (!orbiting || mode === 'rnmaps' || mode === 'lag' || mode === 'expomaps' || mode === 'terrain' || mode === 'parity') return
    const timer = setInterval(async () => {
      const map = munimRef.current
      if (!map) return
      const camera = await map.getCamera()
      map.setCamera({ ...camera, heading: (camera.heading + 90) % 360 }, true)
    }, 2500)
    return () => clearInterval(timer)
  }, [orbiting, mode])

  if (demoShot) {
    return (
      <>
        <StatusBar hidden />
        <Demo shot={demoShot} />
      </>
    )
  }

  return (
    <View style={styles.root}>
      {mode === 'parity' ? (
        <ParityScreen
          mapRef={munimRef}
          startFollowing={parityFollow}
          demo={parityDemo}
          handle={parityHandle}
          trackingMode={trackingMode}
          setTrackingMode={setTrackingMode}
          onEvent={setLastEvent}
          topInset={insets.top}
        />
      ) : mode === 'features' ? (
        <MunimMapView
          key="features"
          ref={munimRef}
          style={StyleSheet.absoluteFill}
          initialCamera={FEATURE_CAMERA}
          markers={FEATURE_MARKERS}
          polylines={FEATURE_POLYLINES}
          polygons={FEATURE_POLYGONS}
          circles={FEATURE_CIRCLES}
          tileOverlays={tiles ? TERRAIN_TILES : []}
          showsScale
          selectableMapFeatures={['pointsOfInterest']}
          onMapReady={() => {
            featuresReady.current = true
            setLastEvent('map ready')
          }}
          onPress={(e) => setLastEvent(`press ${e.latitude.toFixed(4)}, ${e.longitude.toFixed(4)}`)}
          onLongPress={(e) => setLastEvent(`long press ${e.latitude.toFixed(4)}, ${e.longitude.toFixed(4)}`)}
          onMarkerPress={(id) => setLastEvent(`marker ${id}`)}
          onCalloutPress={(id) => setLastEvent(`callout ${id}`)}
          onMarkerDragEnd={(e) => setLastEvent(`dragged ${e.id} to ${e.latitude.toFixed(4)}, ${e.longitude.toFixed(4)}`)}
          onMapFeaturePress={(f) => setLastEvent(`place ${f.title} (${f.category || f.kind})`)}
          onCameraChange={(c) => setLastEvent(`camera ${c.distance.toFixed(0)} m`)}
          onError={(message) => console.warn('MUNIM_MAPS', message)}
        />
      ) : mode === 'space' ? (
        <MunimMapView
          key="space"
          ref={munimRef}
          style={StyleSheet.absoluteFill}
          initialCamera={{ latitude: 22, longitude: -55, distance: 24_000_000, pitch: 0, heading: 0 }}
          globe
          models={satellites}
          paths={ORBIT_PATHS}
          maxCameraDistance={100_000_000}
          lighting="day"
          onModelPress={setPressed}
          onError={(message) => setStatus(`Error: ${message}`)}
        />
      ) : mode === 'globe' ? (
        <MunimMapView
          key="globe"
          ref={munimRef}
          style={StyleSheet.absoluteFill}
          initialCamera={{ latitude: 30, longitude: -40, distance: 20_000_000, pitch: 0, heading: 0 }}
          mapStyle={globeStyle}
          globe={globeSwitch}
          models={GLOBE_MODELS}
          maxCameraDistance={100_000_000}
          onModelPress={setPressed}
          onError={(message) => console.warn('MUNIM_MAPS', message)}
        />
      ) : mode === 'elevation' ? (
        <MunimMapView
          key="elevation"
          ref={munimRef}
          style={StyleSheet.absoluteFill}
          initialCamera={CHICAGO_CAMERA}
          models={CITY_MODELS}
          zones={CITY_ZONES}
          globe={globe}
          lighting={lighting}
          onModelPress={setPressed}
          onError={(message) => console.warn('MUNIM_MAPS', message)}
        />
      ) : mode === 'terrain' ? (
        <MunimMapView
          key={`terrain-${terrainFlat}-${terrainHybrid}`}
          ref={munimRef}
          style={StyleSheet.absoluteFill}
          initialCamera={TERRAIN_CAMERA}
          elevation={terrainFlat ? 'flat' : 'realistic'}
          mapStyle={terrainHybrid ? 'hybrid' : 'standard'}
          followTerrain
          models={TERRAIN_MODELS}
          paths={TERRAIN_PATHS}
          lighting={lighting}
          onModelPress={setPressed}
          onError={(message) => setStatus(`Error: ${message}`)}
        />
      ) : mode === 'expomaps' ? (
        <View style={StyleSheet.absoluteFill}>
          <View testID="expo-map" collapsable={false} style={StyleSheet.absoluteFill}>
            <AppleMaps.View
              ref={expoMapRef}
              style={StyleSheet.absoluteFill}
              cameraPosition={{ coordinates: STARBASE, zoom: EXPO_MAPS_ZOOM }}
            />
          </View>
          <MapModelLayer
            ref={expoLayerRef}
            mapTestID={expoNearest ? undefined : 'expo-map'}
            models={models}
            lighting={lighting}
            onAttachChange={onExpoAttachChange}
            onModelPress={setPressed}
            onError={(message) => console.warn('MUNIM_MAPS', message)}
          />
        </View>
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
            globe={globe}
            models={models}
            lighting={lighting}
            onAttachChange={onAttachChange}
            onModelPress={setPressed}
            onError={(message) => console.warn('MUNIM_MAPS', message)}
          />
        </View>
      )}

      <View style={[styles.panel, { top: insets.top + 8 }, !panel && styles.hidden]}>
        <View style={styles.row}>
          <Toggle label="MunimMapView" on={mode === 'munim'} onPress={() => setMode('munim')} />
          <Toggle label="react-native-maps" on={mode === 'rnmaps'} onPress={() => setMode('rnmaps')} />
          <Toggle label="Elevation" on={mode === 'elevation'} onPress={() => setMode('elevation')} />
        </View>
        <View style={styles.row}>
          <Toggle label="Features" on={mode === 'features'} onPress={() => setMode('features')} />
          {mode === 'features' ? <Toggle label="Tiles" on={tiles} onPress={() => setTiles((v) => !v)} /> : null}
          <Toggle label="Terrain" on={mode === 'terrain'} onPress={() => setMode('terrain')} />
          {mode === 'terrain' ? (
            <>
              <Toggle label={terrainHybrid ? 'Satellite' : 'Standard'} on={terrainHybrid} onPress={() => setTerrainHybrid((v) => !v)} />
              <Toggle label={terrainFlat ? 'Flat' : '3D'} on={!terrainFlat} onPress={() => setTerrainFlat((v) => !v)} />
            </>
          ) : null}
          <Toggle label="expo-maps" on={mode === 'expomaps'} onPress={() => setMode('expomaps')} />
          <Toggle label="MapKit" on={mode === 'parity'} onPress={() => setMode('parity')} />
          {mode === 'parity' ? (
            <Toggle
              label={`Track: ${trackingMode}`}
              on={trackingMode !== 'none'}
              onPress={() =>
                setTrackingMode((m) => (m === 'none' ? 'follow' : m === 'follow' ? 'followWithHeading' : 'none'))
              }
            />
          ) : null}
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
        {mode === 'expomaps' ? (
          <Text style={styles.status}>{expoAttached ? 'Layer attached to the expo-maps map' : 'Looking for the map…'}</Text>
        ) : null}
        {mode === 'terrain' && terrainHeights ? <Text style={styles.status}>{terrainHeights}</Text> : null}
        {pressed ? <Text style={styles.status}>Tapped: {pressed}</Text> : null}
        {(mode === 'features' || mode === 'parity') && lastEvent ? <Text style={styles.status}>Last event: {lastEvent}</Text> : null}
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
  hidden: { display: 'none' },
})
