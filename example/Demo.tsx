import { useEffect, useMemo, useRef, useState } from 'react'
import { StyleSheet, Text, View } from 'react-native'
import { MunimMapView, type MapCamera, type MapModel, type MapPath, type MunimMapViewRef } from 'munim-maps'
import { VEHICLES, type VehicleName } from 'munim-maps/vehicles'
import { ORBIT_PATHS, satelliteModels } from './orbits'

/**
 * Scripted shots for the demo video, opened with
 * munimmapsexample://demo/<shot>. No buttons or text on screen; each shot
 * runs a camera move and its own animation from the moment it mounts.
 */
export type Shot = 'launch' | 'ascent' | 'traffic' | 'friends' | 'orbit' | 'jets'
export const SHOTS: Shot[] = ['launch', 'ascent', 'traffic', 'friends', 'orbit', 'jets']

const tower = require('./assets/tower.usdz')
const avatars = [
  require('./assets/avatar-a.png'),
  require('./assets/avatar-b.png'),
  require('./assets/avatar-c.png'),
  require('./assets/avatar-d.png'),
]

/** Seconds since the shot started, every display frame. */
function useShotClock(): number {
  const [seconds, setSeconds] = useState(0)
  useEffect(() => {
    const start = Date.now()
    let frame = requestAnimationFrame(function tick() {
      setSeconds((Date.now() - start) / 1000)
      frame = requestAnimationFrame(tick)
    })
    return () => cancelAnimationFrame(frame)
  }, [])
  return seconds
}

type Move = { at: number; camera: MapCamera; duration: number; easing?: 'linear' | 'easeInOut' }

const METERS_PER_DEGREE = 111_320
const metersToLat = (m: number) => m / METERS_PER_DEGREE
const metersToLon = (m: number, latitude: number) =>
  m / (METERS_PER_DEGREE * Math.cos((latitude * Math.PI) / 180))
const clamp01 = (x: number) => Math.min(1, Math.max(0, x))

// MARK: Starship

const PAD_A = {
  tower: { latitude: 25.99695, longitude: -97.15726 },
  mount: { latitude: 25.99717, longitude: -97.15696 },
}
const PAD_B = {
  tower: { latitude: 25.99585, longitude: -97.15468 },
  mount: { latitude: 25.9961, longitude: -97.1544 },
}
const MOUNT_HEIGHT = 20

/** Metres climbed `t` seconds after ignition: liftoff 2 s in. */
function climb(t: number): number {
  const flying = t - 2
  return flying <= 0 ? 0 : 6 * flying * flying + 4 * flying
}

/** Ignition at `ignition` seconds, liftoff 2 s later, then a steady climb. */
function launchModels(seconds: number, ignition: number): MapModel[] {
  const t = seconds - ignition
  const altitude = climb(t)
  const throttle = clamp01((t + 0.2) / 0.8)
  // Smoke builds through ignition, rolls out at liftoff, then clears.
  const smoke = t < 0 ? 0 : t < 3 ? clamp01(t / 1.5) : clamp01(1 - (t - 3) / 9)
  return [
    { id: 'tower-a', coordinate: PAD_A.tower, source: tower, heading: 40 },
    { id: 'tower-b', coordinate: PAD_B.tower, source: tower, heading: 40 },
    { id: 'mount-a', coordinate: PAD_A.mount, shape: 'cylinder', size: { width: 22, height: MOUNT_HEIGHT, length: 22 }, color: '#3A3D42' },
    { id: 'mount-b', coordinate: PAD_B.mount, shape: 'cylinder', size: { width: 22, height: MOUNT_HEIGHT, length: 22 }, color: '#3A3D42' },
    { id: 'ship-b', coordinate: PAD_B.mount, source: VEHICLES['rocket-starship'], altitude: MOUNT_HEIGHT },
    {
      id: 'ship-a',
      coordinate: PAD_A.mount,
      source: VEHICLES['rocket-starship'],
      altitude: MOUNT_HEIGHT + altitude,
      groundShadow: altitude < 60,
      effect: t > -0.2 ? 'exhaust' : undefined,
      effectIntensity: throttle,
    },
    {
      id: 'smoke-a',
      coordinate: PAD_A.mount,
      effect: 'smoke',
      size: { width: 240, height: 90 },
      effectIntensity: smoke,
      groundShadow: false,
    },
  ]
}

/**
 * Looks at a point `altitude` metres above `ground` from `slant` metres
 * away. MapKit's camera looks at the ground, so it aims at the spot beyond
 * the point on its line of sight.
 */
function lookAt(ground: { latitude: number; longitude: number }, altitude: number, slant: number, pitch: number, heading: number): MapCamera {
  const p = (pitch * Math.PI) / 180
  const h = (heading * Math.PI) / 180
  const beyond = altitude * Math.tan(p)
  return {
    latitude: ground.latitude + metersToLat(Math.cos(h) * beyond),
    longitude: ground.longitude + metersToLon(Math.sin(h) * beyond, ground.latitude),
    distance: slant + altitude / Math.cos(p),
    pitch,
    heading,
  }
}

/** Follows the Starship up, letting it drift a little higher in the frame. */
function launchCamera(seconds: number): MapCamera {
  const t = seconds - 1.2
  const altitude = climb(t)
  return lookAt(PAD_A.mount, MOUNT_HEIGHT + 55 + altitude * 0.8, 600 + altitude * 0.5, 76, 18 + seconds * 3)
}

const LAUNCH_MOVES: Move[] = [{ at: 0, camera: launchCamera(0), duration: 0 }]

const ASCENT_MOVES: Move[] = [
  { at: 0, camera: { ...PAD_A.mount, distance: 1500, pitch: 70, heading: 300 }, duration: 0 },
  { at: 0.1, camera: { ...PAD_A.mount, distance: 3200, pitch: 80, heading: 340 }, duration: 8, easing: 'linear' },
]

// MARK: Chicago traffic

const LOOP = { latitude: 41.8828, longitude: -87.6245 }
type Lane = { kind: 'ns'; longitude: number } | { kind: 'ew'; latitude: number }
const STREETS: { lane: Lane; direction: 1 | -1; count: number; speed: number }[] = [
  // Michigan Avenue, both directions.
  { lane: { kind: 'ns', longitude: -87.62445 }, direction: 1, count: 7, speed: 13 },
  { lane: { kind: 'ns', longitude: -87.62455 }, direction: -1, count: 7, speed: 12 },
  // State Street.
  { lane: { kind: 'ns', longitude: -87.62775 }, direction: 1, count: 5, speed: 11 },
  { lane: { kind: 'ns', longitude: -87.62785 }, direction: -1, count: 5, speed: 11 },
  // Columbus Drive.
  { lane: { kind: 'ns', longitude: -87.62035 }, direction: -1, count: 5, speed: 14 },
  // Randolph, Madison and Jackson.
  { lane: { kind: 'ew', latitude: 41.88455 }, direction: 1, count: 5, speed: 12 },
  { lane: { kind: 'ew', latitude: 41.88205 }, direction: -1, count: 5, speed: 12 },
  { lane: { kind: 'ew', latitude: 41.87815 }, direction: 1, count: 4, speed: 12 },
]
const CARS: { name: VehicleName; tint?: string; size: number }[] = [
  { name: 'car-sedan', tint: '#2E6FD8', size: 15 },
  { name: 'car-taxi', size: 15 },
  { name: 'car-suv', tint: '#2F3437', size: 16 },
  { name: 'car-ev', tint: '#E8E8EA', size: 15 },
  { name: 'bus-city', size: 20 },
  { name: 'car-sports', tint: '#FF2D55', size: 13 },
  { name: 'car-pickup', tint: '#8E5A2E', size: 16 },
  { name: 'car-hatchback', tint: '#34C759', size: 15 },
  { name: 'car-taxi', size: 15 },
  { name: 'van-delivery', tint: '#FFFFFF', size: 18 },
  { name: 'car-police', size: 15 },
  { name: 'car-minivan', tint: '#9AA4AE', size: 16 },
  { name: 'car-supercar', tint: '#FFD60A', size: 13 },
  { name: 'truck-box', size: 19 },
]
/** Length of street the cars loop along, metres either side of the Loop. */
const STREET_SPAN = 900

function trafficModels(seconds: number): MapModel[] {
  const models: MapModel[] = []
  let carIndex = 0
  STREETS.forEach((street, s) => {
    for (let i = 0; i < street.count; i += 1) {
      const car = CARS[carIndex++ % CARS.length]!
      const spacing = (2 * STREET_SPAN) / street.count
      const along = ((i * spacing + street.direction * street.speed * seconds + s * 37) % (2 * STREET_SPAN) + 2 * STREET_SPAN) % (2 * STREET_SPAN) - STREET_SPAN
      const coordinate =
        street.lane.kind === 'ns'
          ? { latitude: LOOP.latitude + metersToLat(along), longitude: street.lane.longitude }
          : { latitude: street.lane.latitude, longitude: LOOP.longitude + metersToLon(along, LOOP.latitude) }
      const heading = street.lane.kind === 'ns' ? (street.direction > 0 ? 0 : 180) : street.direction > 0 ? 90 : 270
      models.push({
        id: `car-${s}-${i}`,
        coordinate,
        source: VEHICLES[car.name],
        tint: car.tint,
        heading,
        screenSize: car.size,
      })
    }
  })

  // Bikes and scooters on the lakefront trail, two with friends riding.
  const riders: { name: VehicleName; tint: string; avatar?: number; speed: number; offset: number; dir: 1 | -1 }[] = [
    { name: 'bike-road', tint: '#D7263D', avatar: avatars[2], speed: 7, offset: 0, dir: 1 },
    { name: 'bike-city', tint: '#AF52DE', speed: 5, offset: 260, dir: -1 },
    { name: 'scooter-kick', tint: '#30D158', avatar: avatars[3], speed: 6, offset: 520, dir: 1 },
    { name: 'bike-mountain', tint: '#1F9D55', speed: 6.5, offset: 780, dir: -1 },
    { name: 'scooter-moped', tint: '#7FC8C0', speed: 8, offset: 1040, dir: 1 },
  ]
  riders.forEach((rider, i) => {
    const along = ((rider.offset + rider.dir * rider.speed * seconds) % 1400 + 1400) % 1400 - 700
    const coordinate = { latitude: LOOP.latitude + metersToLat(along), longitude: -87.6153 + (rider.dir > 0 ? 0 : 0.00006) }
    models.push({
      id: `rider-${i}`,
      coordinate,
      source: VEHICLES[rider.name],
      tint: rider.tint,
      heading: rider.dir > 0 ? 0 : 180,
      screenSize: 22,
    })
    if (rider.avatar) {
      models.push({
        id: `rider-${i}-friend`,
        coordinate,
        image: rider.avatar,
        imageBorder: { color: '#FFFFFF', width: 3 },
        screenSize: 38,
        lift: 22,
      })
    }
  })

  // Boats on the lake.
  const boats: { name: VehicleName; tint?: string; size: number; at: [number, number]; heading: number; speed: number }[] = [
    { name: 'boat-speed', tint: '#1E3A5F', size: 14, at: [41.8845, -87.6075], heading: 20, speed: 14 },
    { name: 'boat-sail', size: 30, at: [41.8795, -87.6065], heading: 340, speed: 3 },
    { name: 'boat-yacht', size: 16, at: [41.8880, -87.6090], heading: 160, speed: 5 },
  ]
  boats.forEach((boat, i) => {
    const d = boat.speed * seconds
    const h = (boat.heading * Math.PI) / 180
    models.push({
      id: `boat-${i}`,
      coordinate: {
        latitude: boat.at[0] + metersToLat(Math.cos(h) * d),
        longitude: boat.at[1] + metersToLon(Math.sin(h) * d, boat.at[0]),
      },
      source: VEHICLES[boat.name],
      tint: boat.tint,
      heading: boat.heading,
      screenSize: boat.size,
    })
  })

  // An airliner on approach and a helicopter over the river.
  const planeAlong = -1800 + 70 * seconds
  models.push({
    id: 'airliner',
    coordinate: { latitude: LOOP.latitude + metersToLat(150), longitude: LOOP.longitude + metersToLon(-planeAlong, LOOP.latitude) },
    source: VEHICLES['plane-airliner'],
    tint: '#0A4DA2',
    altitude: 420 - seconds * 6,
    heading: 270,
    screenSize: 20,
  })
  const turn = seconds * 0.35
  models.push({
    id: 'heli',
    coordinate: {
      latitude: 41.8875 + metersToLat(Math.cos(turn) * 180),
      longitude: -87.6300 + metersToLon(Math.sin(turn) * 180, 41.8875),
    },
    source: VEHICLES['heli-light'],
    tint: '#D62828',
    altitude: 160,
    heading: ((turn * 180) / Math.PI + 90) % 360,
    screenSize: 16,
  })
  return models
}

const TRAFFIC_MOVES: Move[] = [
  { at: 0, camera: { latitude: 41.8822, longitude: -87.6235, distance: 1500, pitch: 58, heading: 200 }, duration: 0 },
  { at: 0.1, camera: { latitude: 41.8812, longitude: -87.6230, distance: 1250, pitch: 60, heading: 235 }, duration: 9, easing: 'linear' },
]

// MARK: Friends in buildings

const FRIENDS: MapModel[] = [
  { name: 'Skydeck', at: [41.87888, -87.63591], height: 412, border: '#FF3B30', badge: '103F', avatar: 0 },
  { name: 'Trump', at: [41.88894, -87.62637], height: 300, border: '#AF52DE', badge: '82F', avatar: 1 },
  { name: 'Aon', at: [41.88524, -87.62164], height: 240, border: '#30D158', badge: '66F', avatar: 2 },
  { name: 'Chase', at: [41.8817, -87.6303], height: 200, border: '#0A84FF', badge: '55F', avatar: 3 },
  { name: 'Office', at: [41.88535, -87.63178], height: 14, border: '#FFD60A', badge: '4F', avatar: 0 },
  { name: 'Park', at: [41.8826, -87.6226], height: 0, border: '#FF9F0A', badge: '', avatar: 1 },
].map((friend) => ({
  id: friend.name,
  coordinate: { latitude: friend.at[0]!, longitude: friend.at[1]! },
  altitude: friend.height,
  image: avatars[friend.avatar],
  imageBorder: { color: friend.border, width: 3 },
  badge: friend.badge || undefined,
  screenSize: 60,
  stem: friend.height > 0 ? friend.border : false,
}))

const FRIENDS_MOVES: Move[] = [
  { at: 0, camera: { latitude: 41.8890, longitude: -87.6290, distance: 4200, pitch: 55, heading: 192 }, duration: 0 },
  { at: 0.1, camera: { latitude: 41.8880, longitude: -87.6290, distance: 3700, pitch: 57, heading: 212 }, duration: 8, easing: 'linear' },
]

// MARK: Satellites

const ORBIT_MOVES: Move[] = [
  { at: 0, camera: { latitude: 24, longitude: -70, distance: 21_000_000, pitch: 0, heading: 0 }, duration: 0 },
  { at: 0.1, camera: { latitude: 26, longitude: -35, distance: 25_000_000, pitch: 0, heading: 0 }, duration: 9, easing: 'linear' },
]

// MARK: Jets over Manhattan

const MANHATTAN = { latitude: 40.7484, longitude: -73.9857 }
const JETS: { name: VehicleName; dx: number; dz: number }[] = [
  { name: 'jet-f22', dx: 0, dz: 0 },
  { name: 'jet-f35', dx: -32, dz: -30 },
  { name: 'jet-yf23', dx: 32, dz: -30 },
  { name: 'jet-f16', dx: 0, dz: -60 },
]
const JET_SPEED = 120
const JET_HEADING = 29 // Up the avenues.
const JET_ALTITUDE = 600

function jetCenter(seconds: number) {
  const along = -900 + JET_SPEED * seconds
  const h = (JET_HEADING * Math.PI) / 180
  return {
    latitude: MANHATTAN.latitude + metersToLat(Math.cos(h) * along),
    longitude: MANHATTAN.longitude + metersToLon(Math.sin(h) * along, MANHATTAN.latitude),
  }
}

function jetModels(seconds: number): MapModel[] {
  const center = jetCenter(seconds)
  const h = (JET_HEADING * Math.PI) / 180
  return JETS.map((jet) => {
    // Offsets in the formation's frame: dx to the right, dz behind (negative).
    const north = Math.cos(h) * jet.dz - Math.sin(h) * jet.dx
    const east = Math.sin(h) * jet.dz + Math.cos(h) * jet.dx
    return {
      id: jet.name,
      coordinate: {
        latitude: center.latitude + metersToLat(north),
        longitude: center.longitude + metersToLon(east, center.latitude),
      },
      source: VEHICLES[jet.name],
      altitude: JET_ALTITUDE,
      heading: JET_HEADING,
      screenSize: 20,
    }
  })
}

/**
 * MapKit's camera looks at a point on the ground, so to frame jets 600 m up
 * it looks at the spot beyond them on its line of sight.
 */
function jetCamera(seconds: number, heading: number, pitch: number, distance: number): MapCamera {
  const jets = jetCenter(seconds)
  const beyond = JET_ALTITUDE * Math.tan((pitch * Math.PI) / 180)
  const h = (heading * Math.PI) / 180
  return {
    latitude: jets.latitude + metersToLat(Math.cos(h) * beyond),
    longitude: jets.longitude + metersToLon(Math.sin(h) * beyond, jets.latitude),
    distance: distance + beyond / Math.sin((pitch * Math.PI) / 180),
    pitch,
    heading,
  }
}

function jetMoves(): Move[] {
  return [
    { at: 0, camera: jetCamera(0, JET_HEADING + 205, 52, 200), duration: 0 },
    { at: 0.1, camera: jetCamera(9.1, JET_HEADING + 165, 56, 200), duration: 9, easing: 'linear' },
  ]
}

// MARK: Screen

const SHOT_SETUP: Record<Shot, {
  moves: Move[]
  mapStyle: 'standard' | 'hybrid'
  globe?: boolean
  /** A camera worked out every frame instead of moves. */
  track?: (seconds: number) => MapCamera
}> = {
  launch: { moves: LAUNCH_MOVES, mapStyle: 'hybrid', track: launchCamera },
  ascent: { moves: ASCENT_MOVES, mapStyle: 'hybrid' },
  traffic: { moves: TRAFFIC_MOVES, mapStyle: 'standard' },
  friends: {
    moves: FRIENDS_MOVES,
    mapStyle: 'standard',
    track: (t) => ({ latitude: 41.8848, longitude: -87.6290, distance: 3000 - t * 40, pitch: 56, heading: 8 + t * 3.5 }),
  },
  orbit: { moves: ORBIT_MOVES, mapStyle: 'standard', globe: true },
  jets: {
    moves: jetMoves(),
    mapStyle: 'standard',
    track: (t) => jetCamera(t, JET_HEADING + 205 - t * 4.5, 52 + t * 0.4, 200),
  },
}

export function Demo({ shot }: { shot: Shot }) {
  const seconds = useShotClock()
  const map = useRef<MunimMapViewRef | null>(null)
  const [error, setError] = useState('')
  const setup = SHOT_SETUP[shot]

  useEffect(() => {
    const timers = setup.moves.map((move) =>
      setTimeout(() => {
        if (move.duration > 0) map.current?.animateCamera(move.camera, move.duration * 1000, move.easing ?? 'easeInOut')
        else map.current?.setCamera(move.camera, false)
      }, 1500 + move.at * 1000)
    )
    return () => timers.forEach(clearTimeout)
  }, [setup])

  // Everything starts 1.5 s in, once the map has loaded and the first camera
  // jump has landed.
  const t = Math.max(0, seconds - 1.5)

  useEffect(() => {
    if (setup.track && seconds > 1.5) map.current?.setCamera(setup.track(t), false)
  }, [setup, seconds, t])
  const models = useMemo<MapModel[]>(() => {
    switch (shot) {
      case 'launch':
        return launchModels(t, 1.2)
      case 'ascent':
        return launchModels(t + 6, 1.2)
      case 'traffic':
        return trafficModels(t)
      case 'friends':
        return FRIENDS
      case 'orbit':
        return satelliteModels(t, 60).map((m) => ({ ...m, screenSize: (m.screenSize ?? 0) * 1.6 }))
      case 'jets':
        return jetModels(t)
    }
  }, [shot, t])
  const paths: MapPath[] = shot === 'orbit' ? ORBIT_PATHS : []

  return (
    <View style={styles.root}>
      <MunimMapView
        ref={map}
        style={StyleSheet.absoluteFill}
        initialCamera={setup.moves[0]!.camera}
        mapStyle={setup.mapStyle}
        globe={setup.globe ?? false}
        showsCompass={false}
        pointsOfInterest="none"
        models={models}
        paths={paths}
        lighting="day"
        maxCameraDistance={shot === 'orbit' ? 100_000_000 : 50_000}
        onError={setError}
      />
      {error ? <Text style={styles.error}>{error}</Text> : null}
    </View>
  )
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#000' },
  error: { position: 'absolute', top: 60, left: 12, right: 12, color: '#F00', fontSize: 13, backgroundColor: '#FFFE' },
})
