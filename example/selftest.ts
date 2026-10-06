import { Platform } from 'react-native'
import type {
  MapAlignmentReport,
  MapCamera,
  MapModelLayerRef,
  MunimMapViewRef,
} from 'munim-maps'

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

export type TestMode = 'munim' | 'rnmaps' | 'features' | 'globe'

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
}

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
