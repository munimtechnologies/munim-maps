import { useEffect, useMemo, useRef, useState } from 'react'
import { StyleSheet, Text, View } from 'react-native'
import {
  MunimMapView,
  type MapCamera,
  type MapModel,
  type MapPath,
  type MunimMapViewRef,
} from 'munim-maps'
import { VEHICLES, type VehicleName } from 'munim-maps/vehicles'
import { ORBIT_PATHS, satelliteModels } from './orbits'

/**
 * Scripted shots for the demo video, opened with
 * munimmapsexample://demo/<shot>. No buttons or text on screen.
 *
 * Everything that moves is described once, as keyframes on one clock: models
 * through `motion` and the camera through `flyCamera`. munim-maps then moves
 * both natively every frame, so nothing depends on JavaScript keeping up and
 * the models stay locked to the map while the camera moves.
 */
export type Shot = 'launch' | 'ascent' | 'traffic' | 'friends' | 'orbit' | 'jets' | 'models'
export const SHOTS: Shot[] = ['launch', 'ascent', 'traffic', 'friends', 'orbit', 'jets', 'models']

/** Seconds for the map to load before anything moves. */
const LEAD = 1.5

const METERS_PER_DEGREE = 111_320
const metersToLat = (m: number) => m / METERS_PER_DEGREE
const metersToLon = (m: number, latitude: number) =>
  m / (METERS_PER_DEGREE * Math.cos((latitude * Math.PI) / 180))
const clamp01 = (x: number) => Math.min(1, Math.max(0, x))
type LatLng = { latitude: number; longitude: number }
type Keyframes = NonNullable<MapModel['motion']>['keyframes']
type CameraKeyframe = { t: number; camera: MapCamera }

/** `fn` sampled every `step` seconds from `from` to `to`. */
function sample<T>(from: number, to: number, step: number, fn: (t: number) => T): { t: number; value: T }[] {
  const out: { t: number; value: T }[] = []
  for (let t = from; t <= to + 1e-9; t += step) out.push({ t, value: fn(t) })
  return out
}

/** A point `meters` along `heading` from `from`. */
function offset(from: LatLng, heading: number, meters: number): LatLng {
  const h = (heading * Math.PI) / 180
  return {
    latitude: from.latitude + metersToLat(Math.cos(h) * meters),
    longitude: from.longitude + metersToLon(Math.sin(h) * meters, from.latitude),
  }
}

/**
 * A camera looking at a point `altitude` metres above `ground`. MapKit's
 * camera looks at the ground, so it aims at the spot beyond the point on its
 * line of sight.
 */
function lookAt(ground: LatLng, altitude: number, slant: number, pitch: number, heading: number): MapCamera {
  const p = (pitch * Math.PI) / 180
  const beyond = offset(ground, heading, altitude * Math.tan(p))
  return { ...beyond, distance: slant + altitude / Math.cos(p), pitch, heading }
}

// MARK: Lanes

/** Lanes on the real streets, from Apple Maps directions (scripts/build-routes.py). */
type Lane = { name: string; points: [number, number][]; cumulative: number[]; length: number }
const LANES: Lane[] = (
  require('./routes.json') as { lanes: { name: string; points: [number, number][] }[] }
).lanes.map((l) => {
  const cumulative = [0]
  for (let i = 1; i < l.points.length; i += 1) {
    const [lat0, lon0] = l.points[i - 1]!
    const [lat1, lon1] = l.points[i]!
    const dy = (lat1 - lat0) * METERS_PER_DEGREE
    const dx = (lon1 - lon0) * METERS_PER_DEGREE * Math.cos((lat0 * Math.PI) / 180)
    cumulative.push(cumulative[i - 1]! + Math.hypot(dx, dy))
  }
  return { ...l, cumulative, length: cumulative[cumulative.length - 1]! }
})
const lane = (name: string) => LANES.find((l) => l.name === name)!

/** Position `distance` metres along a lane (wrapping), `side` metres to its right. */
function along(l: Lane, distance: number, side = 0): LatLng {
  const d = ((distance % l.length) + l.length) % l.length
  let i = 1
  while (i < l.cumulative.length - 1 && l.cumulative[i]! < d) i += 1
  const [lat0, lon0] = l.points[i - 1]!
  const [lat1, lon1] = l.points[i]!
  const span = l.cumulative[i]! - l.cumulative[i - 1]! || 1
  const f = (d - l.cumulative[i - 1]!) / span
  const dy = (lat1 - lat0) * METERS_PER_DEGREE
  const dx = (lon1 - lon0) * METERS_PER_DEGREE * Math.cos((lat0 * Math.PI) / 180)
  const len = Math.hypot(dx, dy) || 1
  const latitude = lat0 + (lat1 - lat0) * f
  return {
    latitude: latitude + metersToLat((-dx / len) * side),
    longitude: lon0 + (lon1 - lon0) * f + metersToLon((dy / len) * side, latitude),
  }
}

/** Keyframes for driving along a lane at `speed` m/s from `start` metres. */
function drive(l: Lane, start: number, speed: number, side = 0, until = 22): Keyframes {
  const bridge = l.name.startsWith('ggb')
  return sample(-LEAD, until, 0.5, (t) => start + speed * t).map(({ t, value }) => {
    const onLane = along(l, value, side)
    // Both are tuned by eye from each shot's camera so the cars sit in the
    // lanes MapKit draws, whose 3D roads are a little off their coordinates.
    const coordinate = bridge ? offset(onLane, 82, BRIDGE_NUDGE.east) : offset(onLane, 90, CHICAGO_NUDGE_EAST)
    const deck = deckHeight(coordinate)
    return { t, coordinate, altitude: deck > 0 ? deck + BRIDGE_NUDGE.up : 0 }
  })
}

/**
 * Tuned by eye from the bridge shot's camera so the cars sit on Apple's
 * roadway there: metres east across the deck, and metres up.
 */
const BRIDGE_NUDGE = { east: 13, up: 8 }
const CHICAGO_NUDGE_EAST = 3.5

/**
 * The Golden Gate Bridge's roadway is about 67 m above the water at the
 * towers and 75 m at mid-span; cars on it ride at that height.
 */
function deckHeight(at: LatLng): number {
  if (at.longitude > -122.46 || at.longitude < -122.49) return 0
  const lat = at.latitude
  const ramp = (a: number, b: number) => clamp01((lat - a) / (b - a))
  if (lat < 37.806 || lat > 37.835) return 0
  if (lat < 37.8105) return 62 * ramp(37.806, 37.8105)
  if (lat > 37.8285) return 62 * (1 - ramp(37.8285, 37.835))
  const mid = 1 - Math.abs(lat - 37.8195) / 0.009
  return 64 + 11 * mid
}

// MARK: Starship

// Starbase Pad A and Pad B. Tower, mount and ship share the pad's heading
// (the bearing from tower to mount), which puts the chopsticks around the
// booster and the heat shield away from the tower.
const PAD_A_MOUNT = { latitude: 25.99717, longitude: -97.15696 }
const PAD_B_MOUNT = { latitude: 25.99643, longitude: -97.15452 }
const PAD_A = { mount: PAD_A_MOUNT, heading: 51, tower: offset(PAD_A_MOUNT, 51 + 180, 22) }
const PAD_B = { mount: PAD_B_MOUNT, heading: 45, tower: offset(PAD_B_MOUNT, 45 + 180, 22) }
const MOUNT_HEIGHT = 20
const IGNITION = 1.2

/** Metres climbed `t` seconds after ignition: liftoff 2 s in. */
function climb(t: number): number {
  const flying = t - 2
  return flying <= 0 ? 0 : 6 * flying * flying + 4 * flying
}

/** Engine throttle and pad smoke, `t` seconds after ignition. */
function launchEffects(t: number) {
  return {
    burning: t > -0.2,
    throttle: clamp01((t + 0.2) / 0.8),
    smoke: t < 0 ? 0 : t < 3 ? clamp01(t / 1.5) : clamp01(1 - (t - 3) / 9),
  }
}

function launchModels(start: number, shift: number, effects: ReturnType<typeof launchEffects>): MapModel[] {
  return [
    { id: 'tower-a', coordinate: PAD_A.tower, source: VEHICLES['starbase-tower'], heading: PAD_A.heading },
    { id: 'tower-b', coordinate: PAD_B.tower, source: VEHICLES['starbase-tower'], heading: PAD_B.heading },
    { id: 'mount-a', coordinate: PAD_A.mount, source: VEHICLES['starbase-mount'], heading: PAD_A.heading },
    { id: 'mount-b', coordinate: PAD_B.mount, source: VEHICLES['starbase-mount'], heading: PAD_B.heading },
    { id: 'ship-b', coordinate: PAD_B.mount, source: VEHICLES['rocket-starship'], altitude: MOUNT_HEIGHT, heading: PAD_B.heading },
    {
      id: 'ship-a',
      coordinate: PAD_A.mount,
      source: VEHICLES['rocket-starship'],
      heading: PAD_A.heading,
      groundShadow: false,
      effect: effects.burning ? 'exhaust' : undefined,
      effectIntensity: effects.throttle,
      motion: {
        start,
        keyframes: sample(-LEAD, 20, 0.1, (t) => MOUNT_HEIGHT + climb(t + shift - IGNITION)).map(({ t, value }) => ({
          t,
          coordinate: PAD_A.mount,
          altitude: value,
          heading: PAD_A.heading,
        })),
      },
    },
    {
      id: 'smoke-a',
      coordinate: PAD_A.mount,
      effect: 'smoke',
      size: { width: 230, height: 80 },
      effectIntensity: effects.smoke,
      groundShadow: false,
    },
  ]
}

/**
 * The "same frame" shot picks up exactly where the launch clip in the video
 * ends (launch t = 6.1, at ascent t = 1.7), then pulls out and swings round.
 */
// The pull-out starts 5 s into the video, where the music lifts.
const ASCENT_HANDOFF = { ascent: 2.2, launch: 6.6 }
const ASCENT_SHIFT = ASCENT_HANDOFF.launch - ASCENT_HANDOFF.ascent
function ascentCamera(t: number): MapCamera {
  // Blend the launch camera's own settings, so it keeps aiming at the ship
  // the whole way: up close and following, then wide and swinging round.
  // Over 2 s, so the whole of Starbase is in view by the cut at 7 s.
  const x = clamp01((t - ASCENT_HANDOFF.ascent) / 2)
  const p = x * x * (3 - 2 * x)
  const launchT = t + ASCENT_SHIFT
  // Once the pull-out is done the camera holds still: aim at where the
  // ship was then, not where it is now.
  const settled = Math.min(launchT, ASCENT_HANDOFF.launch + 2)
  const ship = MOUNT_HEIGHT + climb(settled - IGNITION)
  const handoff = launchT <= ASCENT_HANDOFF.launch ? launchCamera(launchT) : launchCamera(ASCENT_HANDOFF.launch)
  const nearAim = MOUNT_HEIGHT + 55 + climb(Math.min(launchT, ASCENT_HANDOFF.launch) - IGNITION) * 0.8
  const aim = nearAim + (ship * 0.45 - nearAim) * p
  const slant = 600 + nearAim * 0.5 + (1500 - (600 + nearAim * 0.5)) * p
  const pitch = 76 - 8 * p
  const heading = handoff.heading + 80 * p
  return lookAt(PAD_A.mount, aim, slant, pitch, heading)
}

/** Follows the Starship up, letting it drift a little higher in the frame. */
function launchCamera(t: number): MapCamera {
  const altitude = climb(t - IGNITION)
  return lookAt(PAD_A.mount, MOUNT_HEIGHT + 55 + altitude * 0.8, 600 + altitude * 0.5, 76, 18 + t * 3)
}

// MARK: Traffic

const CARS: { name: VehicleName; tint?: string }[] = [
  { name: 'car-sedan', tint: '#2E6FD8' },
  { name: 'car-taxi' },
  { name: 'car-suv', tint: '#2F3437' },
  { name: 'car-ev', tint: '#E8E8EA' },
  { name: 'bus-city' },
  { name: 'car-sports', tint: '#FF2D55' },
  { name: 'car-pickup', tint: '#8E5A2E' },
  { name: 'car-hatchback', tint: '#34C759' },
  { name: 'car-taxi' },
  { name: 'van-delivery', tint: '#FFFFFF' },
  { name: 'car-police' },
  { name: 'car-minivan', tint: '#9AA4AE' },
  { name: 'car-supercar', tint: '#FFD60A' },
  { name: 'truck-box' },
]
/** Vehicles are drawn at real size times this, so they read on a phone. */
const TRAFFIC_SCALE = 1.6

function traffic(start: number, laneNames: string[], spacing = 75, scale = TRAFFIC_SCALE): MapModel[] {
  type Car = { name: string; road: Lane; from: number; speed: number; car: (typeof CARS)[number]; i: number }
  const cars: Car[] = []
  let index = 0
  laneNames.forEach((name, l) => {
    const road = lane(name)
    const count = Math.max(2, Math.round(road.length / spacing))
    const speed = 10 + (l % 4) * 1.5
    for (let i = 0; i < count; i += 1) {
      const car = CARS[index++ % CARS.length]!
      // Start each car far enough back that it never reaches the end of its
      // lane during the shot.
      cars.push({ name, road, from: (i / count) * (road.length - speed * 24) + l * 3, speed, car, i })
    }
  })
  // Where lanes cross, nudge cars so no two are ever within 9 m of each
  // other: the shot is planned in full, so this is checked ahead of time.
  const times = sample(-LEAD, 22, 0.25, (t) => t).map(({ t }) => t)
  const where = (c: Car, t: number) => along(c.road, c.from + c.speed * t)
  const close = (a: LatLng, b: LatLng) =>
    Math.hypot((a.latitude - b.latitude) * METERS_PER_DEGREE, (a.longitude - b.longitude) * METERS_PER_DEGREE * 0.745) < 9
  for (let pass = 0; pass < 40; pass += 1) {
    let moved = false
    cars.forEach((c, ci) => {
      for (let cj = 0; cj < ci; cj += 1) {
        const d = cars[cj]!
        if (d.name === c.name) continue
        if (times.some((t) => close(where(c, t), where(d, t)))) {
          c.from -= 14
          moved = true
          return
        }
      }
    })
    if (!moved) break
  }
  return cars.map((c) => ({
    id: `car-${c.name}-${c.i}`,
    coordinate: along(c.road, c.from),
    altitude: deckHeight(along(c.road, c.from)),
    source: VEHICLES[c.car.name],
    tint: c.car.tint,
    scale,
    motion: { start, keyframes: drive(c.road, c.from, c.speed) },
  }))
}

// Monroe and Randolph come out from between the towers onto Michigan Avenue.
const CHICAGO_LANES = ['monroe-e', 'randolph-w', 'columbus-n', 'columbus-s', 'michigan-n', 'michigan-s']

// MARK: Friends, the Find My way

const FRIENDS: { name: string; photo: number; at: LatLng; height: number; badge?: string }[] = [
  { name: 'A', photo: require('./assets/avatar-a.png'), at: { latitude: 41.87888, longitude: -87.63591 }, height: 412, badge: 'Floor 103' },
  { name: 'B', photo: require('./assets/avatar-b.png'), at: { latitude: 41.88894, longitude: -87.62637 }, height: 300, badge: 'Floor 82' },
  { name: 'C', photo: require('./assets/avatar-c.png'), at: { latitude: 41.88524, longitude: -87.62164 }, height: 240, badge: 'Floor 66' },
  { name: 'D', photo: require('./assets/avatar-d.png'), at: { latitude: 41.8826, longitude: -87.6235 }, height: 0 },
]

function friends(start: number): MapModel[] {
  return FRIENDS.map((f) => ({
    id: f.name,
    coordinate: f.at,
    altitude: f.height,
    image: f.photo,
    imageBorder: { color: '#FFFFFF', width: 4 },
    badge: f.badge,
    screenSize: 64,
    stem: f.height > 0 ? '#FFFFFF' : false,
    // One friend is out walking up the Michigan Avenue sidewalk.
    motion: f.height === 0 ? { start, keyframes: drive(lane('michigan-n'), 300, 1.5, 9) } : undefined,
  }))
}

// MARK: Satellites

const ORBIT_TIME_SCALE = 22
/** Sizes on top of each orbit's own, so the craft read on the whole globe. */
const ORBIT_SIZE: Record<string, number> = { dragon: 1.5, iss: 1.05 }

function satellites(start: number): MapModel[] {
  const frames = sample(-LEAD, 16, 0.25, (t) => satelliteModels(t, ORBIT_TIME_SCALE))
  return frames[0]!.value.map((first, i) => ({
    ...first,
    groundShadow: false,
    screenSize: (first.screenSize ?? 0) * (ORBIT_SIZE[first.id] ?? 1.3),
    motion: {
      start,
      keyframes: frames.map(({ t, value }) => ({
        t,
        coordinate: value[i]!.coordinate,
        altitude: value[i]!.altitude,
        heading: value[i]!.heading,
      })),
    },
  }))
}

// MARK: San Francisco: jets over the Golden Gate

const SOUTH_TOWER = { latitude: 37.8107, longitude: -122.4775 }
const MID_SPAN = { latitude: 37.8199, longitude: -122.4783 }
const JET_HEADING = 282 // Over the bridge and out to the Pacific.
const JET_ALTITUDE = 240
const JET_SPEED = 115
/**
 * Each aircraft's engine exhausts in its own metres (x right, y up, z back):
 * one contrail per engine. The F-22 and YF-23 are twin-engined with nozzles
 * near the tail (the YF-23's sit in troughs on top); the F-35 and F-16 have
 * one; the airliners trail from the two engines under their wings.
 */
const ENGINES: Partial<Record<VehicleName, [number, number, number][]>> = {
  'jet-f22': [[-0.95, 1.5, 9.1], [0.95, 1.5, 9.1]],
  'jet-yf23': [[-1.7, 1.9, 9.7], [1.7, 1.9, 9.7]],
  'jet-f35': [[0, 1.4, 7.7]],
  'jet-f16': [[0, 1.8, 7.5]],
  'plane-airliner': [[-5.6, 1.2, -2.2], [5.6, 1.2, -2.2]],
  'plane-widebody': [[-8.7, 1.9, -3.6], [8.7, 1.9, -3.6]],
}

const FORMATION: { name: VehicleName; right: number; back: number }[] = [
  { name: 'jet-f22', right: 0, back: 0 },
  { name: 'jet-f35', right: -70, back: 60 },
  { name: 'jet-yf23', right: 70, back: 60 },
  { name: 'jet-f16', right: 0, back: 120 },
]
/** The formation's lead, `t` seconds in: in from the bay, over mid-span at about t = 5. */
function jetLead(t: number): LatLng {
  return offset(offset(MID_SPAN, 180, 600), JET_HEADING, -575 + JET_SPEED * t)
}

function straightLine(start: number, id: string, name: VehicleName, from: LatLng, heading: number, speed: number, altitude: number, scale: number, tint?: string, contrail = false): MapModel {
  return {
    id,
    coordinate: from,
    source: VEHICLES[name],
    tint,
    scale,
    effect: contrail ? 'contrail' : undefined,
    effectOrigins: contrail ? ENGINES[name] : undefined,
    groundShadow: altitude < 1,
    motion: {
      start,
      keyframes: [
        { t: -LEAD, coordinate: offset(from, heading, -speed * LEAD), altitude, heading },
        { t: 22, coordinate: offset(from, heading, speed * 22), altitude, heading },
      ],
    },
  }
}

/** Set to show the bridge occluders in red, for lining them up with Apple's bridge. */
const SHOW_OCCLUDERS = false

/**
 * Invisible stand-ins for the Golden Gate's railing, suspender cables and
 * tower legs on the camera's (west) side, so cars pass behind them the way
 * they pass behind buildings.
 */
function bridgeOccluders(): MapModel[] {
  const road = lane('ggb-s')
  const models: MapModel[] = []
  const box = (id: string, at: LatLng, base: number, width: number, height: number, length: number, heading: number): MapModel => ({
    id,
    coordinate: at,
    altitude: base,
    shape: 'box',
    size: { width, height, length },
    heading,
    color: '#FF0000',
    occluder: !SHOW_OCCLUDERS,
    groundShadow: false,
  })
  const westEdge = (d: number) => offset(along(road, d), 262, BRIDGE_EDGE)
  const headingAt = (d: number) => {
    const a = along(road, d)
    const b = along(road, d + 5)
    return ((Math.atan2((b.longitude - a.longitude) * Math.cos((a.latitude * Math.PI) / 180), b.latitude - a.latitude) * 180) / Math.PI + 360) % 360
  }
  // Distances along the lane of the two towers (southbound: north tower first).
  const nearest = (lat: number) => {
    let best = 0
    for (let d = 0; d < road.length; d += 2) {
      if (Math.abs(along(road, d).latitude - lat) < Math.abs(along(road, best).latitude - lat)) best = d
    }
    return best
  }
  const north = nearest(TOWERS.north)
  const south = nearest(TOWERS.south)
  const mid = (north + south) / 2
  const half = Math.abs(south - north) / 2
  // Railing.
  for (let d = 0; d < road.length; d += 20) {
    const at = westEdge(d + 10)
    models.push(box(`rail-${d}`, at, deckHeight(at) + OCC_UP - 0.5, 0.6, 2.6, 21, headingAt(d + 10)))
  }
  // Suspenders every 50 ft (15.24 m) either side of the south tower, tall
  // enough to cover a car; HANGER_PHASE lines them up with Apple's.
  for (let k = -60; k <= 140; k += 1) {
    const d = south + HANGER_PHASE + k * HANGER_SPACING * Math.sign(north - south)
    if (d < 0 || d > road.length) continue
    const at = westEdge(d)
    models.push(box(`hanger-${k}`, at, deckHeight(at) + OCC_UP, 1.2, 14, 1.2, headingAt(d)))
  }
  // The south tower's west leg.
  const leg = offset(westEdge(south), 262, 3)
  models.push(box('tower-south', leg, 0, 9, 227, 10, headingAt(south)))
  return models
}

/** Where Apple draws the towers, and the west edge of the deck from the cars' line. */
const TOWERS = { south: 37.8106, north: 37.8270 }
const BRIDGE_EDGE = 6
const HANGER_PHASE = 11
const HANGER_SPACING = 25
const OCC_UP = 10

function sanFrancisco(start: number): MapModel[] {
  const jets: MapModel[] = FORMATION.map((jet) => ({
    id: jet.name,
    coordinate: jetLead(0),
    source: VEHICLES[jet.name],
    scale: 2.5,
    effect: 'contrail',
    effectOrigins: ENGINES[jet.name],
    groundShadow: false,
    motion: {
      start,
      keyframes: sample(-LEAD, 18, 0.5, (t) =>
        offset(offset(jetLead(t), JET_HEADING + 180, jet.back), JET_HEADING + 90, jet.right)
      ).map(({ t, value }) => ({ t, coordinate: value, altitude: JET_ALTITUDE, heading: JET_HEADING })),
    },
  }))
  return [
    ...jets,
    // Airliners heading out over the bridge to the Pacific, with contrails.
    straightLine(start, 'airliner', 'plane-airliner', offset(offset(MID_SPAN, 180, 700), 295, -1400), 295, 85, 480, 3, '#0A4DA2', true),
    straightLine(start, 'widebody', 'plane-widebody', offset(offset(MID_SPAN, 180, 1700), 285, -2000), 285, 90, 650, 3, undefined, true),
    // Boats on the water either side of the south tower, in the shot.
    straightLine(start, 'sail-1', 'boat-sail', offset(SOUTH_TOWER, 95, 420), 30, 3, 0, 4),
    straightLine(start, 'sail-2', 'boat-sail', offset(SOUTH_TOWER, 70, 700), 210, 3, 0, 4),
    straightLine(start, 'speedboat', 'boat-speed', offset(SOUTH_TOWER, 300, 260), 20, 12, 0, 5, '#E5484D'),
    straightLine(start, 'ferry', 'boat-yacht', offset(SOUTH_TOWER, 330, 420), 60, 6, 0, 4.5),
    straightLine(start, 'jetski', 'boat-jetski', offset(SOUTH_TOWER, 280, 180), 200, 9, 0, 6),
    // Traffic on the bridge.
    // Close to real size, so each car stays inside its lane.
    ...traffic(start, ['ggb-n', 'ggb-s'], 55, 1.8),
    ...bridgeOccluders(),
  ]
}

/**
 * Over the bay looking south-east, with the south tower in view and the
 * city's shore behind it, drifting slowly west towards the Pacific.
 */
function jetCamera(t: number): MapCamera {
  const x = clamp01((t + LEAD) / 14)
  return {
    ...offset({ latitude: 37.8125, longitude: -122.477 }, 300, x * 220),
    distance: 1600 + x * 350,
    pitch: 72,
    heading: 128 - x * 22,
  }
}

// MARK: Your own models

// Any glTF / GLB, USDZ, USD, SCN, OBJ, PLY or STL file works as a source:
// bundled with require(), downloaded from a URL, or a file:// path.
const fox = require('./assets/models/Fox.glb')
const BALLOON_URL = 'https://raw.githubusercontent.com/munimtechnologies/munim-maps/main/packages/munim-maps/ios/Vehicles/Models/balloon.usdz'
const LAWN = { latitude: 40.7714, longitude: -73.9752 } // Sheep Meadow, Central Park

function yourModels(start: number): MapModel[] {
  const balloonAt = offset(offset(LAWN, 90, 50), 0, 25)
  return [
    {
      id: 'fox',
      coordinate: LAWN,
      source: fox,
      screenSize: 60,
      label: 'Fox.glb',
      motion: {
        start,
        keyframes: sample(-LEAD, 20, 0.5, (t) => offset(LAWN, 90, -18 + t * 1.8)).map(({ t, value }) => ({
          t,
          coordinate: value,
          heading: 90,
        })),
      },
    },
    {
      id: 'helicopter',
      coordinate: offset(LAWN, 270, 45),
      source: VEHICLES['heli-light'],
      tint: '#0A84FF',
      screenSize: 40,
      label: 'heli-light.usdz',
      motion: {
        start,
        keyframes: sample(-LEAD, 20, 0.25, (t) => 22 + Math.sin(t * 0.9) * 2).map(({ t, value }) => ({
          t,
          coordinate: offset(LAWN, 270, 45),
          altitude: value,
          heading: 120 + t * 4,
        })),
      },
    },
    {
      id: 'remote-balloon',
      coordinate: balloonAt,
      source: BALLOON_URL,
      screenSize: 110,
      stem: '#FFFFFF',
      label: 'balloon.usdz from a URL',
      motion: {
        start,
        keyframes: sample(-LEAD, 20, 0.25, (t) => 28 + Math.sin(t * 0.8) * 3).map(({ t, value }) => ({
          t,
          coordinate: balloonAt,
          altitude: value,
          heading: 0,
        })),
      },
    },
  ]
}

// MARK: Shots

type Setup = {
  /** Seconds before t = 0; longer lets iOS's status bar settle after launch. */
  lead?: number
  occlusion?: 'none' | 'buildings'
  globe?: boolean
  maxCameraDistance?: number
  /** The camera at `t`, flown natively from keyframes `cameraStep` seconds apart. */
  camera: (t: number) => MapCamera
  cameraStep: number
  models: (start: number) => MapModel[]
  paths?: MapPath[]
}

const SETUPS: Record<Shot, Setup> = {
  // One continuous take: follows the ship up, then pulls out and swings
  // round (the video uses it for both the launch and "same frame" captions).
  // Starts on the wide final view for a moment so the ocean and the whole
  // site load, well before the part the video uses (from t = 2.85).
  launch: { lead: LEAD + 4, camera: (t) => ascentCamera((t < 0.9 ? ASCENT_HANDOFF.launch + 2.5 : t) - ASCENT_SHIFT), cameraStep: 0.1, models: (start) => launchModels(start, 0, launchEffects(-1)) },
  ascent: {
    // A wide, slow dolly while the ship climbs: the pads must stay put.
    camera: ascentCamera,
    cameraStep: 0.1,
    models: (start) => launchModels(start, ASCENT_SHIFT, launchEffects(ASCENT_SHIFT - IGNITION)),
  },
  traffic: {
    occlusion: 'buildings',
    // Over Grant Park at Monroe and Michigan, pushing in and turning right.
    // Close enough that MapKit loads the trees at full detail up front.
    camera: (t) => ({ latitude: 41.8809, longitude: -87.6224, distance: 620 - Math.max(0, t) * 4, pitch: 64, heading: 252 + Math.max(0, t) * 2.2 }),
    cameraStep: 1,
    models: (start) => traffic(start, CHICAGO_LANES, 85),
  },
  friends: {
    camera: (t) => ({ latitude: 41.8838, longitude: -87.6282, distance: 4400 - t * 40, pitch: 38, heading: 40 + t * 2 }),
    cameraStep: 1,
    models: friends,
  },
  orbit: {
    globe: true,
    maxCameraDistance: 100_000_000,
    camera: (t) => ({ latitude: 22, longitude: -45 + t * 1.2, distance: 38_000_000, pitch: 0, heading: 0 }),
    cameraStep: 1,
    models: satellites,
    paths: ORBIT_PATHS,
  },
  jets: { occlusion: 'buildings', camera: jetCamera, cameraStep: 1, models: sanFrancisco },
  models: {
    camera: () => ({ ...offset(LAWN, 0, 22), distance: 700, pitch: 54, heading: 15 }),
    cameraStep: 1,
    models: yourModels,
  },
}

export function Demo({ shot }: { shot: Shot }) {
  const setup = SETUPS[shot]
  const map = useRef<MunimMapViewRef | null>(null)
  const [error, setError] = useState('')
  // One clock for everything: t = 0 is LEAD seconds after the shot opens.
  const start = useMemo(() => Date.now() / 1000 + (SETUPS[shot].lead ?? LEAD), [shot])
  const isLaunch = shot === 'launch' || shot === 'ascent'
  const shift = shot === 'ascent' ? ASCENT_SHIFT : 0
  const [effects, setEffects] = useState(launchEffects(shift - LEAD - IGNITION))

  // Throttle and smoke change slowly, so a few updates a second is enough;
  // positions never go through here.
  useEffect(() => {
    if (!isLaunch) return
    const timer = setInterval(() => setEffects(launchEffects(Date.now() / 1000 - start + shift - IGNITION)), 100)
    return () => clearInterval(timer)
  }, [isLaunch, shift, start])

  const otherModels = useMemo(() => (isLaunch ? [] : setup.models(start)), [isLaunch, setup, start])
  const models = useMemo(
    () => (isLaunch ? launchModels(start, shift, effects) : otherModels),
    [isLaunch, otherModels, shift, start, effects]
  )

  // Fly once the map is ready (the ref is not there on the first render).
  const flown = useRef(false)
  const fly = () => {
    if (flown.current || !map.current) return
    flown.current = true
    const keyframes: CameraKeyframe[] = sample(-LEAD, 22, setup.cameraStep, setup.camera).map(({ t, value }) => ({
      t,
      camera: value,
    }))
    map.current.flyCamera(keyframes, start, false)
  }
  useEffect(() => {
    const timer = setTimeout(fly, 600)
    return () => clearTimeout(timer)
  })

  return (
    <View style={styles.root}>
      <MunimMapView
        ref={map}
        style={StyleSheet.absoluteFill}
        initialCamera={setup.camera(-LEAD)}
        mapStyle="standard"
        colorScheme="light"
        globe={setup.globe ?? false}
        showsCompass={false}
        pointsOfInterest="none"
        models={models}
        paths={setup.paths ?? []}
        lighting="day"
        maxCameraDistance={setup.maxCameraDistance ?? 50_000}
        occlusion={setup.occlusion ?? 'none'}
        onError={setError}
        onMapReady={fly}
      />
      {error ? <Text style={styles.error}>{error}</Text> : null}
    </View>
  )
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#000' },
  error: { position: 'absolute', top: 60, left: 12, right: 12, color: '#F00', fontSize: 13, backgroundColor: '#FFFE' },
})
