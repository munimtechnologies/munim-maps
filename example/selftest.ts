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

export type TestMode = 'munim' | 'rnmaps'

export interface SelfTestHost {
  showMode(mode: TestMode): Promise<void>
  munimMap(): MunimMapViewRef | null
  layer(): MapModelLayerRef | null
  /** Moves react-native-maps' camera. */
  setRnMapsCamera(camera: MapCamera): void
  waitForLayerAttached(timeoutMs: number): Promise<boolean>
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
