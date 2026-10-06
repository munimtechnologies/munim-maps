import type { MapModel, MapPath } from 'munim-maps'
import { VEHICLES } from 'munim-maps/vehicles'

/**
 * Satellites on circular orbits for the globe screen. Time runs fast (one
 * ISS orbit in about 40 seconds) and the Earth does not turn under them, so
 * each orbit's ground track is a fixed great circle.
 */
interface Orbit {
  id: string
  model: keyof typeof VEHICLES
  /** Degrees. */
  inclination: number
  /** Longitude where the orbit crosses the equator going north, degrees. */
  node: number
  /** Degrees along the orbit at time 0. */
  phase: number
  /** Metres above the ground. */
  altitude: number
  /**
   * munim-maps sizes models by height on screen; these craft are flat, so
   * this is chosen from each model's proportions for a sensible width.
   */
  screenSize: number
  track?: string
}

const EARTH_RADIUS = 6_371_000
const MU = 3.986004418e14
const TIME_SCALE = 140

const STARLINK_TRAIN: Orbit[] = Array.from({ length: 10 }, (_, i) => ({
  id: `starlink-${i}`,
  model: 'satellite-starlink',
  // Retrograde, so the train heads north-west across the ISS's track
  // instead of following it.
  inclination: 127,
  node: -25,
  phase: 34 + i * 4,
  altitude: 550_000,
  screenSize: 0.8,
  track: i === 0 ? '#FFFFFF' : undefined,
}))

export const ORBITS: Orbit[] = [
  { id: 'iss', model: 'satellite-iss', inclination: 51.6, node: -40, phase: 20, altitude: 420_000, screenSize: 26, track: '#FFD60A' },
  { id: 'dragon', model: 'satellite-dragon', inclination: 51.6, node: -40, phase: 8, altitude: 418_000, screenSize: 15 },
  { id: 'hubble', model: 'satellite-hubble', inclination: 28.5, node: -60, phase: 7, altitude: 540_000, screenSize: 24, track: '#64D2FF' },
  { id: 'cubesat', model: 'satellite-cubesat', inclination: 97.4, node: -10, phase: 55, altitude: 500_000, screenSize: 20, track: '#30D158' },
  ...STARLINK_TRAIN,
  { id: 'gps-1', model: 'satellite-gps', inclination: 55, node: -60, phase: 60, altitude: 20_180_000, screenSize: 12, track: '#FF9F0A' },
  { id: 'gps-2', model: 'satellite-gps', inclination: 55, node: 0, phase: -20, altitude: 20_180_000, screenSize: 12 },
]

const rad = (d: number) => (d * Math.PI) / 180
const deg = (r: number) => (r * 180) / Math.PI

function groundPoint(orbit: Orbit, u: number) {
  const i = rad(orbit.inclination)
  const latitude = deg(Math.asin(Math.sin(i) * Math.sin(u)))
  let longitude = orbit.node + deg(Math.atan2(Math.cos(i) * Math.sin(u), Math.cos(u)))
  longitude = ((((longitude + 180) % 360) + 360) % 360) - 180
  return { latitude, longitude }
}

function bearing(a: { latitude: number; longitude: number }, b: { latitude: number; longitude: number }) {
  const p1 = rad(a.latitude)
  const p2 = rad(b.latitude)
  const dl = rad(b.longitude - a.longitude)
  const y = Math.sin(dl) * Math.cos(p2)
  const x = Math.cos(p1) * Math.sin(p2) - Math.sin(p1) * Math.cos(p2) * Math.cos(dl)
  return (deg(Math.atan2(y, x)) + 360) % 360
}

/** Radians along the orbit after `seconds` of (sped-up) time. */
function argument(orbit: Orbit, seconds: number, timeScale: number) {
  const radius = EARTH_RADIUS + orbit.altitude
  const meanMotion = Math.sqrt(MU / radius ** 3)
  return rad(orbit.phase) + meanMotion * seconds * timeScale
}

export function satelliteModels(seconds: number, timeScale = TIME_SCALE): MapModel[] {
  return ORBITS.map((orbit) => {
    const u = argument(orbit, seconds, timeScale)
    const here = groundPoint(orbit, u)
    const ahead = groundPoint(orbit, u + 0.002)
    return {
      id: orbit.id,
      coordinate: here,
      altitude: orbit.altitude,
      heading: bearing(here, ahead),
      source: VEHICLES[orbit.model],
      screenSize: orbit.screenSize,
      groundShadow: false,
    }
  })
}

/** Each tracked orbit as a ring at its own height. */
export const ORBIT_PATHS: MapPath[] = ORBITS.filter((o) => o.track).map((orbit) => ({
  id: `orbit-${orbit.id}`,
  coordinates: Array.from({ length: 180 }, (_, k) => ({
    ...groundPoint(orbit, rad(k * 2)),
    altitude: orbit.altitude,
  })),
  color: `${orbit.track}AA`,
  width: 1.5,
  closed: true,
}))
