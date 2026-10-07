import { Platform } from 'react-native'
import {
  createSearchCompleter,
  directions,
  eta,
  formatDistance,
  geocode,
  groundElevation,
  hasLookAround,
  lookAroundSnapshot,
  mapItem,
  mapSnapshot,
  pointsOfInterest,
  reverseGeocode,
  searchPlaces,
  type MapItem,
  type SearchCompletion,
  type UserTrackingMode,
  type MapAlignmentReport,
  type MapCamera,
  type MapModelLayerRef,
  type MunimMapViewRef,
} from 'munim-maps'
import {
  LOOP_REGION,
  NAVY_PIER,
  PARITY_POLYGON_ID,
  PARITY_VIEW_MARKER_ID,
  WILLIS_TOWER,
  type ParityHandle,
} from './Parity'

/**
 * Unattended device check for the example app. It runs once on launch and
 * logs `MUNIM_MAPS_CHECK` / `MUNIM_MAPS_SELFTEST` lines; the caller writes
 * the report to Documents/munim-maps-selftest.json.
 *
 * Each check moves the camera, waits for MapKit to settle, then asks the
 * native side how far the drawn models are from where MapKit draws the same
 * coordinates, and whether their pixels are really on screen.
 */
export type CheckStatus = 'pass' | 'fail'

export interface Check {
  name: string
  status: CheckStatus
  detail?: unknown
}

export interface SelfTestReport {
  platform: string
  os: string
  startedAt: string
  finishedAt: string
  passed: number
  failed: number
  checks: Check[]
}

export type TestMode = 'munim' | 'rnmaps' | 'features' | 'globe' | 'expomaps' | 'terrain' | 'parity'

export interface SelfTestHost {
  showMode(mode: TestMode): Promise<void>
  munimMap(): MunimMapViewRef | null
  layer(): MapModelLayerRef | null
  /** Moves react-native-maps' camera. */
  setRnMapsCamera(camera: MapCamera): void
  waitForLayerAttached(timeoutMs: number): Promise<boolean>
  featuresReady(): boolean
  markerIds(): string[]
  /** The globe screen's map style. */
  setGlobeStyle(style: 'standard' | 'hybrid'): void
  /** The layer drawn over expo-maps. */
  expoLayer(): MapModelLayerRef | null
  /** Moves expo-maps' camera (it takes a centre and a zoom level only). */
  setExpoMapsZoom(center: { latitude: number; longitude: number }, zoom: number): void
  waitForExpoLayerAttached(timeoutMs: number): Promise<boolean>
  /** The terrain screen's map: flat or 3D, standard or satellite. */
  setTerrainView(flat: boolean, satellite: boolean): void
  /** The MapKit parity screen's state. */
  parity(): ParityHandle
  setTrackingMode(mode: UserTrackingMode): void
}

/** Metres between two coordinates (good enough for a few km). */
function meters(a: { latitude: number; longitude: number }, b: { latitude: number; longitude: number }) {
  const dy = (a.latitude - b.latitude) * 111_320
  const dx = (a.longitude - b.longitude) * 111_320 * Math.cos((a.latitude * Math.PI) / 180)
  return Math.hypot(dx, dy)
}

async function waitFor<T>(read: () => T | undefined | null | false, timeoutMs: number): Promise<T | undefined> {
  const end = Date.now() + timeoutMs
  while (Date.now() < end) {
    const value = read()
    if (value) return value
    await sleep(200)
  }
  return undefined
}

/** Yosemite Valley from the west, with Half Dome and Glacier Point in view. */
const TERRAIN_CHECK_CAMERA: MapCamera = { latitude: 37.738, longitude: -119.565, distance: 8000, pitch: 40, heading: 60 }

/** Known ground heights above sea level, and how far off the tiles may be. */
const KNOWN_HEIGHTS = [
  { name: 'Denver, Colorado State Capitol', latitude: 39.73924, longitude: -104.98486, meters: 1609, tolerance: 15 },
  { name: 'Half Dome summit', latitude: 37.74602, longitude: -119.53313, meters: 2694, tolerance: 25 },
  { name: 'Chicago Loop', latitude: 41.8838, longitude: -87.6305, meters: 181, tolerance: 10 },
]

/** Largest allowed gap between our drawing and MapKit's, in points. */
const MAX_ERROR_POINTS = 3

export const CAMERAS: { name: string; camera: Omit<MapCamera, 'latitude' | 'longitude'> }[] = [
  { name: 'top-down', camera: { distance: 1500, pitch: 0, heading: 0 } },
  { name: 'pitched 45, heading 30', camera: { distance: 1500, pitch: 45, heading: 30 } },
  { name: 'pitched 60, heading 200', camera: { distance: 900, pitch: 60, heading: 200 } },
  { name: 'far, pitched 30, heading 90', camera: { distance: 4000, pitch: 30, heading: 90 } },
  { name: 'close, pitched 70, heading 315', camera: { distance: 500, pitch: 70, heading: 315 } },
]

/**
 * Close in with the globe switched on. (MapKit's conversions stay flat on
 * the globe, so far-out views can only be checked by eye.)
 */
export const GLOBE_CAMERAS: { name: string; camera: MapCamera }[] = [
  { name: 'Chicago top-down', camera: { latitude: 41.8781, longitude: -87.6298, distance: 1500, pitch: 0, heading: 0 } },
  { name: 'Chicago pitched 55, heading 120', camera: { latitude: 41.8781, longitude: -87.6298, distance: 1200, pitch: 55, heading: 120 } },
  { name: 'Tokyo far, pitched 30', camera: { latitude: 35.6762, longitude: 139.6503, distance: 6000, pitch: 30, heading: 0 } },
]

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms))

function log(check: Check) {
  console.log(`MUNIM_MAPS_CHECK ${JSON.stringify(check)}`)
}

function judge(name: string, report: MapAlignmentReport): Check {
  const ok =
    report.attached &&
    report.modelsMeasured > 0 &&
    report.maxErrorPoints >= 0 &&
    report.maxErrorPoints <= MAX_ERROR_POINTS &&
    report.modelsVisibleInRender > 0
  return { name, status: ok ? 'pass' : 'fail', detail: report }
}

export async function runSelfTest(
  host: SelfTestHost,
  center: { latitude: number; longitude: number }
): Promise<SelfTestReport> {
  const startedAt = new Date().toISOString()
  const checks: Check[] = []
  const record = (check: Check) => {
    checks.push(check)
    log(check)
  }

  // Standalone MunimMapView.
  await host.showMode('munim')
  await sleep(2500)
  for (const { name, camera } of CAMERAS) {
    const map = host.munimMap()
    if (!map) {
      record({ name: `MunimMapView ${name}`, status: 'fail', detail: 'no ref' })
      continue
    }
    map.setCamera({ ...center, ...camera }, false)
    await sleep(1200)
    record(judge(`MunimMapView ${name}`, await map.measureAlignment()))
  }

  // MapModelLayer over react-native-maps.
  await host.showMode('rnmaps')
  const attached = await host.waitForLayerAttached(8000)
  record({
    name: 'MapModelLayer finds the react-native-maps map',
    status: attached ? 'pass' : 'fail',
  })
  if (attached) {
    await sleep(2000)
    for (const { name, camera } of CAMERAS) {
      host.setRnMapsCamera({ ...center, ...camera })
      await sleep(1200)
      const layer = host.layer()
      if (!layer) {
        record({ name: `MapModelLayer ${name}`, status: 'fail', detail: 'no ref' })
        continue
      }
      record(judge(`MapModelLayer ${name}`, await layer.measureAlignment()))
    }
  }

  // MapModelLayer over expo-maps, whose AppleMaps.View is SwiftUI's Map.
  // Its camera only takes a centre and a zoom level, so top-down only.
  await host.showMode('expomaps')
  const expoAttached = await host.waitForExpoLayerAttached(8000)
  record({
    name: 'MapModelLayer finds the expo-maps map',
    status: expoAttached ? 'pass' : 'fail',
  })
  if (expoAttached) {
    await sleep(2000)
    for (const zoom of [15, 16, 17]) {
      host.setExpoMapsZoom(center, zoom)
      await sleep(1500)
      const layer = host.expoLayer()
      if (!layer) {
        record({ name: `expo-maps zoom ${zoom}`, status: 'fail', detail: 'no ref' })
        continue
      }
      record(judge(`expo-maps zoom ${zoom}`, await layer.measureAlignment()))
    }
  }

  // Terrain: ground heights from the elevation tiles, and models placed
  // above sea level showing once their tiles have loaded.
  try {
    const heights = await groundElevation(KNOWN_HEIGHTS)
    KNOWN_HEIGHTS.forEach((known, index) => {
      const height = heights[index] ?? NaN
      record({
        name: `groundElevation ${known.name}`,
        status: Math.abs(height - known.meters) <= known.tolerance ? 'pass' : 'fail',
        detail: { height, expected: known.meters },
      })
    })
  } catch (error) {
    record({ name: 'groundElevation', status: 'fail', detail: String(error) })
  }
  await host.showMode('terrain')
  for (const [flat, satellite] of [
    [true, false],
    [false, true],
  ] as const) {
    host.setTerrainView(flat, satellite)
    await sleep(3000)
    const name = flat ? 'Terrain flat map' : 'Terrain satellite 3D'
    const terrainMap = host.munimMap()
    if (!terrainMap) {
      record({ name, status: 'fail', detail: 'no ref' })
      continue
    }
    terrainMap.setCamera(TERRAIN_CHECK_CAMERA, false)
    await sleep(4000)
    const report = await terrainMap.measureAlignment()
    // On the flat map every model on screen is drawn once its terrain tile
    // has arrived. On 3D terrain the models are lifted onto the ground and
    // MapKit's conversions stay flat, so only check that they are drawn.
    const check = judge(`${name}: models placed on the terrain`, report)
    if (flat && report.modelsVisibleInRender < report.modelsMeasured) check.status = 'fail'
    record(check)
  }

  // With the globe on (the standard style through `globe`, and satellite
  // imagery with realistic elevation, which is a globe on its own), models
  // are placed on the sphere; close in that must still match MapKit.
  await host.showMode('globe')
  for (const style of ['standard', 'hybrid'] as const) {
    host.setGlobeStyle(style)
    await sleep(2500)
    for (const { name, camera } of GLOBE_CAMERAS) {
      const map = host.munimMap()
      if (!map) {
        record({ name: `Globe ${style} ${name}`, status: 'fail', detail: 'no ref' })
        continue
      }
      map.setCamera(camera, false)
      await sleep(2500)
      record(judge(`Globe ${style} ${name}`, await map.measureAlignment()))
    }
  }

  // MunimMapView's MapKit features: conversions, regions, fitting, snapshots,
  // geocoding and Look Around.
  await host.showMode('features')
  await sleep(3000)
  const map = host.munimMap()
  const check = async (name: string, run: () => Promise<unknown>) => {
    try {
      const detail = await run()
      record({ name: `Features: ${name}`, status: detail === false ? 'fail' : 'pass', detail })
    } catch (error) {
      record({ name: `Features: ${name}`, status: 'fail', detail: String(error) })
    }
  }
  if (!map) {
    record({ name: 'Features: map', status: 'fail', detail: 'no ref' })
  } else {
    await check('onMapReady fired', async () => host.featuresReady())
    await check('pointForCoordinate and back', async () => {
      const loop = { latitude: 41.8826, longitude: -87.6233 }
      const point = await map.pointForCoordinate(loop)
      const back = await map.coordinateForPoint(point)
      const error = Math.hypot(back.latitude - loop.latitude, back.longitude - loop.longitude)
      return error < 1e-4 ? { point, error } : false
    })
    await check('setRegion moves the map', async () => {
      map.setRegion({ latitude: 41.89, longitude: -87.62, latitudeDelta: 0.02, longitudeDelta: 0.02 }, 0)
      await sleep(800)
      const region = await map.getVisibleRegion()
      const ok = Math.abs(region.latitude - 41.89) < 0.002 && Math.abs(region.longitude + 87.62) < 0.002
      return ok ? region : false
    })
    await check('fitToMarkers frames every marker', async () => {
      map.fitToMarkers('', { top: 40, left: 40, bottom: 40, right: 40 }, false)
      await sleep(1000)
      const region = await map.getVisibleRegion()
      const inside = (lat: number, lon: number) =>
        Math.abs(lat - region.latitude) <= region.latitudeDelta / 2 &&
        Math.abs(lon - region.longitude) <= region.longitudeDelta / 2
      const ok = [41.8789, 41.8921, 41.8735].every((lat, i) =>
        inside(lat, [-87.6359, -87.6264, -87.6305][i]!)
      )
      return ok ? { markers: host.markerIds().length, region } : false
    })
    await check('takeSnapshot writes a PNG', async () => {
      const path = await map.takeSnapshot(300, 300)
      return path.endsWith('.png') ? path : false
    })
    await check('addressForCoordinate finds Chicago', async () => {
      const address = await map.addressForCoordinate({ latitude: 41.8826, longitude: -87.6233 })
      return address.city === 'Chicago' ? address.formatted : false
    })
    await check('hasLookAround in the Loop', async () =>
      map.hasLookAround({ latitude: 41.8838, longitude: -87.6305 })
    )
  }

  // MapKit parity: services, overlays hit-testing, React Native markers and
  // user tracking, on the parity screen.
  await host.showMode('parity')
  await sleep(3000)
  const parityMap = host.munimMap()
  const parity = async (name: string, run: () => Promise<unknown>) => {
    try {
      const detail = await run()
      record({ name: `MapKit: ${name}`, status: detail === false ? 'fail' : 'pass', detail })
    } catch (error) {
      record({ name: `MapKit: ${name}`, status: 'fail', detail: String(error) })
    }
  }
  let firstPlace: MapItem | undefined
  await parity('searchPlaces finds coffee in the Loop', async () => {
    const items = await searchPlaces({ query: 'coffee', region: LOOP_REGION })
    firstPlace = items.find((item) => item.identifier) ?? items[0]
    return items.length > 0 ? { count: items.length, first: items[0]?.name, identifier: items[0]?.identifier } : false
  })
  await parity('search completer suggests and resolves', async () => {
    let latest: SearchCompletion[] = []
    const completer = createSearchCompleter({ region: LOOP_REGION, onResults: (r) => (latest = r) })
    completer.setQuery('Willis Tower')
    const results = await waitFor(() => (latest.length > 0 ? latest : undefined), 8000)
    if (!results) return false
    const [item] = await completer.resolve(results[0]!)
    completer.cancel()
    return item ? { suggestion: results[0]!.title, resolved: item.name } : false
  })
  await parity('pointsOfInterest finds cafés', async () => {
    const items = await pointsOfInterest({ center: WILLIS_TOWER, radius: 600, categories: ['cafe'] })
    return items.length > 0 && items.every((i) => i.category === 'MKPOICategoryCafe')
      ? { count: items.length, first: items[0]?.name }
      : false
  })
  await parity('directions Willis Tower to Navy Pier', async () => {
    const routes = await directions({ from: WILLIS_TOWER, to: NAVY_PIER, transportType: 'automobile', alternates: true })
    const best = routes[0]
    return best && best.coordinates.length > 10 && best.steps.length > 0 && best.distance > 2000
      ? { routes: routes.length, distance: best.distance, minutes: best.expectedTravelTime / 60, steps: best.steps.length, name: best.name }
      : false
  })
  await parity('walking eta', async () => {
    const result = await eta({ from: WILLIS_TOWER, to: NAVY_PIER, transportType: 'walking' })
    return result.expectedTravelTime > 600 ? result : false
  })
  await parity('geocode an address', async () => {
    const items = await geocode('233 S Wacker Dr, Chicago, IL')
    const item = items[0]
    return item && meters(item, WILLIS_TOWER) < 400 ? { name: item.name, formatted: item.address.formatted } : false
  })
  await parity('reverseGeocode finds Chicago', async () => {
    const items = await reverseGeocode(WILLIS_TOWER)
    return items[0]?.address.city === 'Chicago' ? items[0].address.formatted : false
  })
  await parity('mapItem by identifier', async () => {
    if (!firstPlace?.identifier) return { skipped: 'search returned no identifier (iOS < 18)' }
    const item = await mapItem(firstPlace.identifier)
    return item.name === firstPlace.name ? { identifier: item.identifier, name: item.name } : false
  })
  await parity('mapSnapshot writes a PNG', async () => {
    const path = await mapSnapshot({ region: LOOP_REGION, width: 300, height: 200, mapStyle: 'muted' })
    return path.endsWith('.png') ? path : false
  })
  await parity('hasLookAround and lookAroundSnapshot', async () => {
    const loop = { latitude: 41.8838, longitude: -87.6305 }
    if (!(await hasLookAround(loop))) return false
    const path = await lookAroundSnapshot({ coordinate: loop, width: 320, height: 200 })
    return path.endsWith('.png') ? path : false
  })
  await parity('formatDistance', async () => {
    const text = formatDistance(1609.34, { units: 'imperial' })
    return text.length > 0 ? text : false
  })
  if (!parityMap) {
    record({ name: 'MapKit: map', status: 'fail', detail: 'no ref' })
  } else {
    await parity('tap hit-testing finds the route and the polygon', async () => {
      const route = await waitFor(() => host.parity().route, 10_000)
      if (!route) return false
      // The route draws itself in over about 1.5 s (strokeEnd).
      await sleep(2000)
      const middle = route.coordinates[Math.floor(route.coordinates.length / 2)]!
      const onRoute = await parityMap.overlayAtPoint(await parityMap.pointForCoordinate(middle))
      const inBlock = await parityMap.overlayAtPoint(
        await parityMap.pointForCoordinate({ latitude: 41.876, longitude: -87.622 })
      )
      const outside = await parityMap.overlayAtPoint(
        await parityMap.pointForCoordinate({ latitude: 41.8955, longitude: -87.6400 })
      )
      return onRoute === 'parity-route' && inBlock === PARITY_POLYGON_ID && outside === ''
        ? { onRoute, inBlock, outside }
        : false
    })
    await parity('MarkerView is a map marker', async () => {
      parityMap.fitToMarkers(PARITY_VIEW_MARKER_ID, { top: 40, left: 40, bottom: 40, right: 40 }, false)
      await sleep(1500)
      const region = await parityMap.getVisibleRegion()
      const ok =
        Math.abs(region.latitude - 41.8826) < 0.01 &&
        Math.abs(region.longitude + 87.6226) < 0.01 &&
        region.latitudeDelta < 0.1
      return ok ? region : false
    })
    await parity('user tracking follows and MapKit reports dropping it', async () => {
      const events = host.parity().trackingEvents
      events.length = 0
      host.setTrackingMode('followWithHeading')
      await sleep(4000)
      const followed = events.length === 0 || events[events.length - 1] === 'followWithHeading'
      // A camera move ends following, as a pan does; MapKit reports 'none'.
      parityMap.setCamera({ ...WILLIS_TOWER, distance: 3000, pitch: 0, heading: 0 }, false)
      const dropped = await waitFor(() => events.includes('none'), 4000)
      host.setTrackingMode('none')
      if (!dropped) throw new Error(`no 'none' event; events: ${JSON.stringify(events)}`)
      return { events: [...events], followedUntilMoved: followed }
    })
  }

  const report: SelfTestReport = {
    platform: Platform.OS,
    os: String(Platform.Version),
    startedAt,
    finishedAt: new Date().toISOString(),
    passed: checks.filter((c) => c.status === 'pass').length,
    failed: checks.filter((c) => c.status === 'fail').length,
    checks,
  }
  console.log(`MUNIM_MAPS_SELFTEST ${JSON.stringify(report)}`)
  return report
}
