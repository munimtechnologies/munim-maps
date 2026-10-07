import { useCallback, useMemo, useRef, useState } from 'react'
import { File, Paths } from 'expo-file-system'
import {
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native'
import {
  MAPBOX_STYLES,
  MapboxOffline,
  MapboxServices,
  MarkerView,
  MunimMapView,
  mapboxMap,
  type MapboxLayer,
  type MapboxMapOptions,
  type MapCamera,
  type MapCircle,
  type MapMarker,
  type MapModel,
  type MapPolygon,
  type MapPolyline,
  type MapProviderEvent,
  type MunimMapViewRef,
  type UserTrackingMode,
} from 'munim-maps'
import { VEHICLES as CATALOGUE, type VehicleName } from 'munim-maps-vehicles'

// These checks compare glTF models (drawn by the engine) with USDZ ones
// (munim-maps' 3D layer on iOS), so they pick formats explicitly: VEHICLES as
// the platform's own format (USDZ on iOS, GLB on Android), VEHICLES_GLB as GLB.
const VEHICLES = new Proxy({} as Record<VehicleName, string>, {
  get: (_, name) => (Platform.OS === 'ios' ? CATALOGUE[name as VehicleName].usdz : CATALOGUE[name as VehicleName].glb),
})
const VEHICLES_GLB = new Proxy({} as Record<VehicleName, string>, {
  get: (_, name) => CATALOGUE[name as VehicleName].glb,
})

/**
 * Every group of the Mapbox engine on one map: Standard / Standard
 * Satellite with light presets, globe, terrain, runtime sources and layers
 * of every kind (clustered GeoJSON, heatmap, fill-extrusion, line gradient,
 * raster, hillshade, Mapbox's own glTF model layer), images, featureset
 * taps, markers, dashed lines, MarkerViews (view annotations), the location
 * puck with heading and pulse, follow-with-heading, munim-maps' 3D models,
 * and the checks (button, or munimmapsexample://mapbox/checks).
 */

const CHICAGO: MapCamera = { latitude: 41.8826, longitude: -87.6278, distance: 1400, pitch: 55, heading: 30 }
const PRESETS = ['day', 'dusk', 'night', 'dawn'] as const

const MODELS: MapModel[] = [
  { id: 'bus', coordinate: { latitude: 41.8829, longitude: -87.6279 }, source: VEHICLES['bus-city'], heading: 0, tint: '#0A84FF', screenSize: 26 },
  { id: 'taxi', coordinate: { latitude: 41.8822, longitude: -87.6271 }, source: VEHICLES['car-taxi'], heading: 90, screenSize: 22 },
  { id: 'police', coordinate: { latitude: 41.8833, longitude: -87.6268 }, source: VEHICLES['car-police'], heading: 180, screenSize: 22 },
  { id: 'balloon', coordinate: { latitude: 41.8826, longitude: -87.6278 }, altitude: 120, source: VEHICLES.balloon, screenSize: 60 },
]

// glTF models: drawn by Mapbox's own model layer with modelRendering 'auto'
// (the labelled one stays on munim-maps' 3D layer in 'auto').
const START = Date.now() / 1000
const NATIVE_MODELS: MapModel[] = [
  {
    id: 'glb-bus',
    coordinate: { latitude: 41.8795, longitude: -87.62775 },
    source: VEHICLES_GLB['bus-city'],
    tint: '#FF9500',
    motion: {
      keyframes: [
        { t: 0, coordinate: { latitude: 41.8795, longitude: -87.62775 } },
        { t: 20, coordinate: { latitude: 41.8860, longitude: -87.62775 } },
        { t: 40, coordinate: { latitude: 41.8795, longitude: -87.62775 } },
      ],
      start: START,
      loop: true,
    },
  },
  // On Millennium Park's lawn, out in the open.
  { id: 'glb-taxi', coordinate: { latitude: 41.8828, longitude: -87.6216 }, source: VEHICLES_GLB['car-taxi'], heading: 45, screenSize: 30 },
  { id: 'glb-truck', coordinate: { latitude: 41.8823, longitude: -87.6216 }, source: VEHICLES_GLB['truck-fire'], heading: 90, tint: '#34C759' },
  { id: 'glb-bus-still', coordinate: { latitude: 41.8826, longitude: -87.6222 }, source: VEHICLES_GLB['bus-city'], heading: 0, tint: '#FF9500' },
  { id: 'glb-taxi-spin', coordinate: { latitude: 41.8831, longitude: -87.6221 }, source: VEHICLES_GLB['car-taxi'], spinDegreesPerSecond: 30 },
  { id: 'glb-jet', coordinate: { latitude: 41.8834, longitude: -87.6212 }, source: VEHICLES_GLB['plane-airliner'], altitude: 120, heading: 270, scale: 1 },
  { id: 'glb-police', coordinate: { latitude: 41.8808, longitude: -87.6292 }, source: VEHICLES_GLB['car-police'], heading: 0, label: 'Unit 7', stem: true },
]
const RENDERING = ['auto', 'native', 'overlay'] as const

const MARKERS: MapMarker[] = [
  { id: 'pin', coordinate: { latitude: 41.8816, longitude: -87.6301 }, style: 'pin', color: '#FF3B30', title: 'Pin', callout: true },
  { id: 'balloon-marker', coordinate: { latitude: 41.8841, longitude: -87.6301 }, style: 'marker', color: '#34C759', glyph: '☕', title: 'Café', subtitle: 'Balloon marker' },
  { id: 'label', coordinate: { latitude: 41.8806, longitude: -87.6262 }, style: 'label', title: 'Label pill', color: '#5856D6' },
  { id: 'dot', coordinate: { latitude: 41.8848, longitude: -87.6255 }, style: 'dot', color: '#FF9500', size: 18 },
  { id: 'drag', coordinate: { latitude: 41.8812, longitude: -87.6240 }, style: 'marker', color: '#AF52DE', glyph: '↔', title: 'Drag me', draggable: true },
  ...Array.from({ length: 12 }, (_, i): MapMarker => ({
    id: `c${i}`,
    coordinate: { latitude: 41.8775 + (i % 4) * 0.0004, longitude: -87.6335 + Math.floor(i / 4) * 0.0004 },
    style: 'dot',
    color: '#0A84FF',
    clusteringId: 'stops',
  })),
]

const POLYLINES: MapPolyline[] = [
  { id: 'dash-4-10', coordinates: [{ latitude: 41.8790, longitude: -87.6359 }, { latitude: 41.8826, longitude: -87.6290 }, { latitude: 41.8921, longitude: -87.6264 }], strokeColor: '#0A84FF', strokeWidth: 4, dashPattern: [4, 10], tappable: true },
  { id: 'dash-6-4', coordinates: [{ latitude: 41.8785, longitude: -87.6240 }, { latitude: 41.8860, longitude: -87.6235 }], strokeColor: '#FF2D55', strokeWidth: 3, dashPattern: [6, 4] },
  { id: 'gradient', coordinates: [{ latitude: 41.8770, longitude: -87.6320 }, { latitude: 41.8770, longitude: -87.6220 }], strokeWidth: 6, strokeColors: ['#34C759', '#FFCC00', '#FF3B30'], tappable: true },
]

const POLYGONS: MapPolygon[] = [
  {
    id: 'park',
    coordinates: [
      { latitude: 41.8855, longitude: -87.6215 },
      { latitude: 41.8855, longitude: -87.6180 },
      { latitude: 41.8820, longitude: -87.6180 },
      { latitude: 41.8820, longitude: -87.6215 },
    ],
    holes: [[
      { latitude: 41.8843, longitude: -87.6203 },
      { latitude: 41.8843, longitude: -87.6192 },
      { latitude: 41.8832, longitude: -87.6192 },
      { latitude: 41.8832, longitude: -87.6203 },
    ]],
    fillColor: '#34C75955',
    strokeColor: '#248A3D',
    strokeWidth: 2,
    tappable: true,
  },
]

const CIRCLES: MapCircle[] = [
  { id: 'zone', center: { latitude: 41.8790, longitude: -87.6300 }, radius: 120, fillColor: '#FF950040', strokeColor: '#FF9500', strokeWidth: 2, dashPattern: [3, 3], tappable: true },
]

/** Points for the clustered GeoJSON source and the heatmap. */
function points(): object {
  const features = Array.from({ length: 160 }, (_, i) => ({
    type: 'Feature',
    id: i,
    properties: { weight: (i % 7) + 1 },
    geometry: {
      type: 'Point',
      coordinates: [-87.645 + ((i * 37) % 100) / 2500, 41.872 + ((i * 53) % 100) / 2500],
    },
  }))
  return { type: 'FeatureCollection', features }
}

const BLOCK = {
  type: 'Feature',
  properties: { height: 220 },
  geometry: {
    type: 'Polygon',
    coordinates: [[[-87.6352, 41.8862], [-87.6338, 41.8862], [-87.6338, 41.8872], [-87.6352, 41.8872], [-87.6352, 41.8862]]],
  },
}

// A white circle as an SDF icon (recoloured with icon-color). A valid PNG:
// the previous one had bad CRC / zlib checksums, which iOS tolerates and
// Android's BitmapFactory does not.
const SDF_DOT =
  'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAL0lEQVR42mP4//8/AyUYmyAhgNcAYgFWA0gFKAaQC0YNGF4GUJyQqJKUqZKZSMYA26Sogj5K8sEAAAAASUVORK5CYII='

type Check = { name: string; ok: boolean; detail: string }

/** Copies a snapshot into Documents, so it can be pulled off the device. */
function keep(path: string, name: string) {
  try {
    const target = new File(Paths.document, name)
    if (target.exists) target.delete()
    new File(path.startsWith('file://') ? path : `file://${path}`).copy(target)
  } catch (error) {
    console.warn('MUNIM_MAPS_MAPBOX could not keep the snapshot', error)
  }
}

/** Documents/munim-maps-mapbox-checks.json, rewritten as checks finish, for pulling off a device. */
function writeReport(report: object) {
  try {
    const file = new File(Paths.document, 'munim-maps-mapbox-checks.json')
    if (file.exists) file.delete()
    file.create()
    file.write(JSON.stringify({ platform: Platform.OS, time: new Date().toISOString(), ...report }, null, 2))
  } catch (error) {
    console.warn('MUNIM_MAPS_MAPBOX could not write the report', error)
  }
}

export function MapboxScreen(props: {
  topInset: number
  /** Run the checks when the map is ready: all of them, or only the native-model check. */
  autoChecks?: boolean | 'native'
  onExit?: () => void
}) {
  const ref = useRef<MunimMapViewRef | null>(null)
  const [satellite, setSatellite] = useState(false)
  const [preset, setPreset] = useState(0)
  const [terrain, setTerrain] = useState(false)
  const [globe, setGlobe] = useState(true)
  const [layersOn, setLayersOn] = useState(true)
  const [tracking, setTracking] = useState<UserTrackingMode>('none')
  const [status, setStatus] = useState('')
  const [checks, setChecks] = useState<Check[]>([])
  const [running, setRunning] = useState(false)
  const [drag, setDrag] = useState('')
  const [dragCount, setDragCount] = useState(0)
  const [ready, setReady] = useState(false)
  const [rendering, setRendering] = useState(0)
  const events = useRef<Record<string, number>>({})
  const errors = useRef<string[]>([])
  const ranAuto = useRef(false)

  const glbUri = VEHICLES_GLB['bus-school']

  const layers: MapboxLayer[] = useMemo(
    () =>
      layersOn
        ? [
            { id: 'heat', type: 'heatmap', source: 'points', slot: 'middle', maxzoom: 17, paint: { 'heatmap-weight': ['/', ['get', 'weight'], 7], 'heatmap-radius': 24, 'heatmap-opacity': 0.6 } },
            { id: 'clusters', type: 'circle', source: 'points', slot: 'top', filter: ['has', 'point_count'], paint: { 'circle-color': ['case', ['boolean', ['feature-state', 'picked'], false], '#FF3B30', '#5E5CE6'], 'circle-radius': ['step', ['get', 'point_count'], 14, 10, 18, 30, 24], 'circle-stroke-width': 2, 'circle-stroke-color': '#FFFFFF', 'circle-emissive-strength': 1 } },
            { id: 'cluster-count', type: 'symbol', source: 'points', slot: 'top', filter: ['has', 'point_count'], layout: { 'text-field': ['get', 'point_count_abbreviated'], 'text-size': 12 }, paint: { 'text-color': '#FFFFFF' } },
            { id: 'point-icons', type: 'symbol', source: 'points', slot: 'top', filter: ['!', ['has', 'point_count']], layout: { 'icon-image': 'sdf-dot', 'icon-allow-overlap': true }, paint: { 'icon-color': '#FF9F0A' } },
            { id: 'block', type: 'fill-extrusion', source: 'block', paint: { 'fill-extrusion-color': '#64D2FF', 'fill-extrusion-height': ['get', 'height'], 'fill-extrusion-opacity': 0.8 } },
            { id: 'model', type: 'model', source: 'model-point', slot: 'middle', layout: { 'model-id': 'school-bus' }, paint: { 'model-scale': [8, 8, 8], 'model-rotation': [0, 0, 90], 'model-type': 'common-3d' } },
            { id: 'hillshade', type: 'hillshade', source: 'dem', slot: 'bottom', paint: { 'hillshade-exaggeration': 0.4 } },
          ]
        : [],
    [layersOn]
  )

  const mapbox: MapboxMapOptions = useMemo(
    () => ({
      modelRendering: RENDERING[rendering],
      standard: { lightPreset: PRESETS[preset], show3dObjects: true, showPointOfInterestLabels: true },
      projection: globe ? 'globe' : 'mercator',
      atmosphere: { 'range': [0.8, 8], 'star-intensity': 0.2, 'horizon-blend': 0.1 },
      terrain: terrain ? { exaggeration: 1.5 } : false,
      sources: layersOn
        ? {
            'points': { type: 'geojson', data: points(), cluster: true, clusterRadius: 40, clusterMaxZoom: 15 },
            'block': { type: 'geojson', data: BLOCK },
            'model-point': { type: 'geojson', data: { type: 'Feature', properties: {}, geometry: { type: 'Point', coordinates: [-87.6262, 41.8838] } } },
            'dem': { type: 'raster-dem', url: 'mapbox://mapbox.mapbox-terrain-dem-v1', tileSize: 512 },
          }
        : undefined,
      layers,
      images: { 'sdf-dot': { uri: SDF_DOT, sdf: true, scale: 1 } },
      models: glbUri ? { 'school-bus': glbUri } : undefined,
      puck: { type: '2d', bearing: 'heading', pulsing: { enabled: true, color: '#0A84FF', radius: 'accuracy' }, showsAccuracyRing: true },
      ornaments: { scaleBar: { visibility: 'visible', position: 'bottom-left', units: 'metric' }, compass: { position: 'top-right', margins: [12, 120] } },
      gestures: { simultaneousRotateAndPinchZoomEnabled: true },
      cameraBounds: { maxPitch: 85 },
      events: ['mapLoaded', 'mapIdle', 'styleLoaded', 'sourceDataLoaded', 'styleImageMissing', 'mapLoadingError'],
      interactions: [
        { id: 'poi', type: 'tap', featureset: { featuresetId: 'poi', importId: 'basemap' } },
        { id: 'building', type: 'tap', featureset: { featuresetId: 'buildings', importId: 'basemap' }, setState: { select: true } },
        { id: 'cluster', type: 'tap', layerId: 'clusters' },
      ],
    }),
    [preset, globe, terrain, layersOn, layers, glbUri, rendering]
  )

  const onProviderEvent = useCallback((event: MapProviderEvent) => {
    events.current[event.name] = (events.current[event.name] ?? 0) + 1
    if (event.name === 'interaction') {
      const name = event.data?.feature?.properties?.name ?? event.data?.featureId ?? ''
      setStatus(`Tapped ${event.data?.id}: ${name}`)
    } else if (event.name === 'mapLoadingError') {
      setStatus(`Mapbox error: ${event.data?.message}`)
      if (errors.current.length < 40) errors.current.push(`mapLoadingError ${event.data?.type}: ${event.data?.message}`)
    }
  }, [])

  const runChecks = useCallback(async (only?: 'native') => {
    const map = ref.current
    if (!map || running) return
    setRunning(true)
    const results: Check[] = []
    writeReport({ finished: false, started: true, results })
    const mb = mapboxMap(map)
    const wait = (ms: number) => new Promise((r) => setTimeout(r, ms))
    async function check(name: string, body: () => Promise<string | boolean>) {
      try {
        const value = await Promise.race([
          body(),
          new Promise<string>((_, reject) => setTimeout(() => reject(new Error('timed out')), 20_000)),
        ])
        const ok = value !== false && !(typeof value === 'string' && value.startsWith('FAIL '))
        results.push({ name, ok, detail: typeof value === 'string' ? value : '' })
      } catch (error) {
        results.push({ name, ok: false, detail: String((error as Error)?.message ?? error) })
      }
      setChecks([...results])
      writeReport({ finished: false, passed: results.filter((r) => r.ok).length, total: results.length, results, errors: errors.current })
      console.log(`MUNIM_MAPS_MAPBOX check ${results[results.length - 1]!.ok ? 'PASS' : 'FAIL'} ${name} ${results[results.length - 1]!.detail}`)
    }

    await map.setCamera(CHICAGO, false)
    await wait(1500)
    await check('getCamera matches the initial camera', async () => {
      const c = await map.getCamera()
      const d = Math.abs(c.distance - CHICAGO.distance) / CHICAGO.distance
      return d < 0.02 && Math.abs(c.pitch - CHICAGO.pitch) < 0.5 ? `distance ${c.distance.toFixed(0)} m` : false
    })
    await check('point ↔ coordinate round trip', async () => {
      const p = await map.pointForCoordinate({ latitude: 41.883, longitude: -87.628 })
      const c = await map.coordinateForPoint(p)
      const back = await map.pointForCoordinate(c)
      const e = Math.hypot(back.x - p.x, back.y - p.y)
      return e < 1 ? `${e.toFixed(3)} pt` : false
    })
    await check('getVisibleRegion contains the centre', async () => {
      const r = await map.getVisibleRegion()
      return Math.abs(r.latitude - CHICAGO.latitude) < r.latitudeDelta && r.longitudeDelta > 0 ? `${r.latitudeDelta.toFixed(4)}°` : false
    })
    if (!only) setRendering(2)
    await wait(1200)
    for (const [pitch, heading] of only ? [] : ([[0, 0], [55, 30], [70, 200]] as const)) {
      await map.setCamera({ ...CHICAGO, pitch, heading }, false)
      await wait(900)
      await check(`3D layer alignment (pitch ${pitch}, heading ${heading})`, async () => {
        const a = await map.measureAlignment()
        return a.modelsMeasured > 0 && a.maxErrorPoints < 2 ? `max ${a.maxErrorPoints.toFixed(2)} pt over ${a.modelsMeasured}` : false
      })
    }
    setRendering(0)
    await map.setCamera(CHICAGO, false)
    await wait(2500)
    await check('native glTF models in Mapbox\'s model layer', async () => {
      const f = await mb.queryRenderedFeatures({ layerIds: ['munim-native-models', 'munim-native-models-sea', 'munim-native-moving', 'munim-native-moving-sea', 'munim-native-animated', 'munim-native-animated-sea'] })
      const ids = [...new Set(f.map((x) => String(x.feature.properties?.id ?? x.feature.id ?? '')))]
      keep(await map.takeSnapshot(0, 0), 'mapbox-native.png')
      const state = await mb.getNativeModels()
      return ids.length > 0
        ? `drawn natively: ${ids.join(', ')} (overlay: ${state.overlay.join(', ')})`
        : `FAIL none drawn: ${JSON.stringify(state).slice(0, 1500)}`
    })
    if (only) {
      // Close-ups to check heading, size and tint by eye.
      // Where the moving bus is now, as the engine places it.
      const positions = ((await mb.getNativeModels()) as { positions?: Record<string, number[]> }).positions ?? {}
      const bus = positions['glb-bus'] ?? [41.8826, -87.6283]
      await map.setCamera({ latitude: bus[0]!, longitude: bus[1]!, distance: 250, pitch: 0, heading: 0 }, false)
      await wait(500)
      keep(await map.takeSnapshot(0, 0), 'mapbox-native-bus.png')
      await map.setCamera({ latitude: 41.8828, longitude: -87.6214, distance: 300, pitch: 55, heading: 0 }, false)
      await wait(3000)
      keep(await map.takeSnapshot(0, 0), 'mapbox-native-taxi.png')
      // The fire truck faces east (heading 90): its cab should point right.
      await map.setCamera({ latitude: 41.8827, longitude: -87.6218, distance: 180, pitch: 0, heading: 0 }, false)
      await wait(3000)
      keep(await map.takeSnapshot(0, 0), 'mapbox-native-truck.png')
      await map.setCamera(CHICAGO, false)
      const passedNative = results.filter((r) => r.ok).length
      writeReport({ finished: true, passed: passedNative, total: results.length, errors: errors.current, results })
      setRunning(false)
      return
    }
    await check('getCameraState (zoom levels)', async () => {
      const s = await mb.getCameraState()
      return s.zoom > 10 && s.zoom < 20 ? `zoom ${s.zoom.toFixed(2)}` : false
    })
    await check('style imports: basemap with config', async () => {
      const imports = await mb.getStyleImports()
      const config = await mb.getStyleImportConfig({ importId: 'basemap' })
      return imports.some((i) => i.id === 'basemap') && 'lightPreset' in config ? `${imports.length} import(s)` : false
    })
    await check('slots and featuresets (Standard)', async () => {
      const slots = await mb.getSlots()
      const sets = await mb.getFeaturesets()
      return slots.includes('middle') && sets.length > 0 ? `${slots.join('/')} · ${sets.map((s) => s.featuresetId).join(',')}` : false
    })
    await check('runtime layers and sources', async () => {
      const layerIds = (await mb.getLayers()).map((l) => l.id)
      const sourceIds = (await mb.getSources()).map((s) => s.id)
      const wanted = ['heat', 'clusters', 'block', 'model', 'hillshade']
      const missing = wanted.filter((id) => !layerIds.includes(id))
      return missing.length === 0 && sourceIds.includes('points') ? `${layerIds.length} layers` : `FAIL missing ${missing.join(',')}`
    })
    await check('getStyleJson', async () => ((await mb.getStyleJson()).length > 100 ? 'ok' : false))
    await check('querySourceFeatures (clustered GeoJSON)', async () => {
      const f = await mb.querySourceFeatures({ sourceId: 'points' })
      return f.length > 0 ? `${f.length} features` : false
    })
    let cluster: unknown
    // The points cluster below zoom 15: step back to see clusters.
    await map.setCamera({ latitude: 41.892, longitude: -87.625, distance: 12_000, pitch: 0, heading: 0 }, false)
    await wait(2500)
    await check('queryRenderedFeatures on the clusters layer', async () => {
      const f = await mb.queryRenderedFeatures({ layerIds: ['clusters'] })
      cluster = f[0]?.feature
      return f.length > 0 ? `${f.length} clusters` : false
    })
    await check('cluster expansion zoom and leaves', async () => {
      if (!cluster) return false
      const zoom = await mb.getClusterExpansionZoom({ sourceId: 'points', cluster: cluster as never })
      const leaves = await mb.getClusterLeaves({ sourceId: 'points', cluster: cluster as never, limit: 5 })
      const children = await mb.getClusterChildren({ sourceId: 'points', cluster: cluster as never })
      return typeof zoom === 'number' && leaves.length > 0 && children.length > 0 ? `zoom ${zoom}, ${leaves.length} leaves` : false
    })
    await map.setCamera(CHICAGO, false)
    await wait(2000)
    await check('queryRenderedFeatures (featureset: buildings)', async () => {
      const f = await mb.queryRenderedFeatures({ featureset: { featuresetId: 'buildings', importId: 'basemap' } })
      return f.length > 0 ? `${f.length} buildings` : false
    })
    await check('feature state set / get / remove', async () => {
      await mb.setFeatureState({ sourceId: 'points', featureId: '3', state: { picked: true } })
      const s = await mb.getFeatureState({ sourceId: 'points', featureId: '3' })
      await mb.removeFeatureState({ sourceId: 'points', featureId: '3' })
      return s?.picked === true ? 'picked = true' : false
    })
    await check('setLayerProperties / getLayerProperties', async () => {
      await mb.setLayerProperties({ layerId: 'block', properties: { paint: { 'fill-extrusion-color': '#FF375F' } } })
      const p = await mb.getLayerProperties({ layerId: 'block' })
      return JSON.stringify(p).includes('fill-extrusion') ? 'ok' : false
    })
    await check('updateGeoJSONSource', async () => {
      await mb.updateGeoJSONSource({ sourceId: 'block', data: { ...BLOCK, properties: { height: 320 } } })
      return 'ok'
    })
    await check('setStyleImportConfig (lightPreset dusk → back)', async () => {
      await mb.setStyleImportConfig({ importId: 'basemap', config: { lightPreset: 'dusk' } })
      const c = await mb.getStyleImportConfig({ importId: 'basemap' })
      await mb.setStyleImportConfig({ importId: 'basemap', config: { lightPreset: PRESETS[preset] } })
      return c.lightPreset === 'dusk' ? 'dusk' : `FAIL got ${String(c.lightPreset)}`
    })
    await check('overlayAtPoint (the polygon, its hole, a dashed line)', async () => {
      await map.setCamera({ latitude: 41.8838, longitude: -87.6198, distance: 1500, pitch: 0, heading: 0 }, false)
      await wait(800)
      const inside = await map.overlayAtPoint(await map.pointForCoordinate({ latitude: 41.8850, longitude: -87.6210 }))
      const hole = await map.overlayAtPoint(await map.pointForCoordinate({ latitude: 41.88375, longitude: -87.61975 }))
      // Centred on the line's point: at CHICAGO it is below the bottom edge of a phone.
      await map.setCamera({ ...CHICAGO, latitude: 41.8808, longitude: -87.63245 }, false)
      await wait(800)
      const line = await map.overlayAtPoint(await map.pointForCoordinate({ latitude: 41.8808, longitude: -87.63245 }))
      await map.setCamera(CHICAGO, false)
      await wait(300)
      return inside === 'park' && hole === '' && line === 'dash-4-10'
        ? 'park, hole empty, dash-4-10'
        : `FAIL inside "${inside}", hole "${hole}", line "${line}"`
    })
    await check('cameraForCoordinates', async () => {
      const c = await mb.cameraForCoordinates({ coordinates: [{ latitude: 41.87, longitude: -87.64 }, { latitude: 41.89, longitude: -87.61 }], padding: { top: 40, left: 40, bottom: 40, right: 40 } })
      return typeof c.zoom === 'number' ? `zoom ${c.zoom.toFixed(2)}` : false
    })
    await check('getBounds', async () => {
      const b = await mb.getBounds()
      return b && b.northeast.latitude > b.southwest.latitude ? 'ok' : false
    })
    await check('easeTo resolves when finished', async () => String(await mb.easeTo({ camera: { zoom: 15, bearing: 60, pitch: 45 }, duration: 600 })))
    await check('flyTo resolves when finished', async () => String(await mb.flyTo({ camera: { center: { latitude: 41.8826, longitude: -87.6278 }, zoom: 16, pitch: 50 }, duration: 1200 })))
    await check('fitToCoordinates frames them', async () => {
      map.fitToCoordinates([{ latitude: 41.875, longitude: -87.64 }, { latitude: 41.89, longitude: -87.615 }], { top: 30, left: 30, bottom: 30, right: 30 }, false)
      await wait(600)
      const r = await map.getVisibleRegion()
      return r.latitude - r.latitudeDelta / 2 <= 41.8751 && r.latitude + r.latitudeDelta / 2 >= 41.8899 ? 'ok' : false
    })
    await check('flyCamera keyframes move the camera', async () => {
      const start = Date.now() / 1000
      map.flyCamera([{ t: 0, camera: CHICAGO }, { t: 1, camera: { ...CHICAGO, heading: 120, distance: 2500 } }], start, false)
      await wait(1400)
      const c = await map.getCamera()
      return Math.abs(c.heading - 120) < 1 ? `heading ${c.heading.toFixed(1)}` : false
    })
    await check('setViewport overview, then idle', async () => {
      const done = await mb.setViewport({ state: 'overview', coordinates: [{ latitude: 41.87, longitude: -87.64 }, { latitude: 41.89, longitude: -87.61 }], duration: 500 })
      await mb.setViewport({ state: 'idle' })
      return String(done)
    })
    await check('free camera, tile cover, camera bounds, style camera', async () => {
      await mb.setFreeCamera({ position: { latitude: 41.875, longitude: -87.635, altitude: 900 }, lookAt: { latitude: 41.8826, longitude: -87.6278 } })
      const free = await mb.getFreeCamera()
      const tiles = await mb.tileCover({ minZoom: 0, maxZoom: 16 })
      const bounds = await mb.getCameraBounds()
      await mb.getStyleDefaultCamera()
      return Math.abs(free.position.altitude - 900) < 50 && tiles.length > 0 && bounds.maxPitch === 85
        ? `alt ${free.position.altitude.toFixed(0)} m, ${tiles.length} tiles`
        : false
    })
    await check('performance statistics', async () => {
      const stats = await mb.collectPerformanceStatistics({ durationMs: 500 })
      return stats.collectionDurationMillis > 0 ? `median ${stats.mapRenderDuration.medianMillis.toFixed(2)} ms` : false
    })
    await check('location override + follow with heading', async () => {
      await mb.setLocationOverride({ latitude: 41.8789, longitude: -87.6359, heading: 75, accuracy: 20 })
      setTracking('followWithHeading')
      await wait(3500)
      const c = await map.getCamera()
      await mb.setLocationOverride({ latitude: 41.8800, longitude: -87.6340, heading: 120 })
      await wait(2500)
      const c2 = await map.getCamera()
      setTracking('none')
      await mb.clearLocationOverride()
      const near = Math.abs(c.latitude - 41.8789) < 0.001 && Math.abs(c.longitude + 87.6359) < 0.001
      const turned = Math.abs(((c2.heading - 120 + 540) % 360) - 180) < 3
      return near && turned ? `followed, heading ${c2.heading.toFixed(0)}°` : `FAIL first ${c.latitude.toFixed(4)}, ${c.longitude.toFixed(4)}; then ${c2.latitude.toFixed(4)}, ${c2.longitude.toFixed(4)} heading ${c2.heading.toFixed(0)}`
    })
    await map.setCamera({ ...CHICAGO, distance: 6000 }, false)
    setTerrain(true)
    await wait(3500)
    await check('terrain: getElevation', async () => {
      const e = await mb.getElevation({ latitude: 41.8826, longitude: -87.6278 })
      return typeof e === 'number' ? `${e.toFixed(1)} m` : false
    })
    setTerrain(false)
    await check('takeSnapshot (the map view)', async () => {
      const path = await map.takeSnapshot(0, 0)
      keep(path, 'mapbox-view.png')
      return path.length > 0 ? path.split('/').pop()! : false
    })
    await check('snapshot (Mapbox Snapshotter)', async () => {
      const path = await mb.snapshot({ width: 300, height: 200, camera: { center: { latitude: 41.8826, longitude: -87.6278 }, zoom: 14 } })
      keep(path, 'mapbox-snapshotter.png')
      return path.length > 0 ? path.split('/').pop()! : false
    })
    await check('addressForCoordinate (Mapbox geocoding)', async () => {
      const a = await map.addressForCoordinate({ latitude: 41.8789, longitude: -87.6359 })
      return a.city ? `${a.formatted || a.city}` : false
    })
    await check('MapboxServices.geocode', async () => {
      const r = (await MapboxServices.geocode('Willis Tower, Chicago', { limit: 1 })) as { features?: unknown[] }
      return (r.features?.length ?? 0) > 0 ? 'found' : false
    })
    let progress = 0
    const remove = MapboxOffline.addListener(() => {
      progress += 1
    })
    await check('offline: estimate, download, list, remove a tile region', async () => {
      const bounds = { southwest: { latitude: 41.878, longitude: -87.632 }, northeast: { latitude: 41.886, longitude: -87.622 } }
      const estimate = await MapboxOffline.estimateTileRegion({ bounds, minZoom: 12, maxZoom: 13 })
      const region = await MapboxOffline.loadTileRegion({ id: 'munim-check', bounds, minZoom: 12, maxZoom: 13 })
      const all = await MapboxOffline.tileRegions()
      await MapboxOffline.removeTileRegion({ id: 'munim-check' })
      return all.some((r) => r.id === 'munim-check') && region.completedResourceCount > 0
        ? `${region.completedResourceCount} tiles, est. ${Math.round(estimate.transferSize / 1024)} KB, ${progress} progress events`
        : false
    })
    remove()
    await check('Mapbox events reach onProviderEvent', async () => {
      const e = events.current
      // Moving native models keep the map drawing, so it may never be idle.
      return (e.mapLoaded ?? 0) > 0 && (e.styleLoaded ?? 0) > 0 && (e.sourceDataLoaded ?? 0) > 0 ? JSON.stringify(e) : false
    })
    await map.setCamera(CHICAGO, false)
    const passed = results.filter((r) => r.ok).length
    console.log(`MUNIM_MAPS_MAPBOX checks ${passed}/${results.length}`)
    writeReport({ finished: true, passed, total: results.length, events: events.current, errors: errors.current, results })
    setStatus(`Checks: ${passed}/${results.length} passed`)
    setRunning(false)
  }, [running, preset])

  const onMapReady = useCallback(() => {
    setReady(true)
    console.log('MUNIM_MAPS_MAPBOX map ready')
    writeReport({ finished: false, mapReady: true, results: [] })
    if (props.autoChecks && !ranAuto.current) {
      ranAuto.current = true
      setTimeout(() => void runChecks(props.autoChecks === 'native' ? 'native' : undefined), 4000)
    }
  }, [props.autoChecks, runChecks])

  return (
    <View style={StyleSheet.absoluteFill}>
      <MunimMapView
        ref={ref}
        provider="mapbox"
        style={StyleSheet.absoluteFill}
        initialCamera={CHICAGO}
        mapStyle={satellite ? 'hybrid' : 'standard'}
        styleUrl={satellite ? MAPBOX_STYLES.standardSatellite : ''}
        globe={globe}
        models={[...MODELS, ...NATIVE_MODELS]}
        lighting="auto"
        markers={MARKERS}
        clusterStyles={[{ clusteringId: 'stops', color: '#0A84FF', glyph: '{count}' }]}
        polylines={POLYLINES}
        polygons={POLYGONS}
        circles={CIRCLES}
        showsUserLocation
        userTrackingMode={tracking}
        onUserTrackingModeChange={setTracking}
        showsUserTrackingButton
        showsScale
        mapbox={mapbox}
        onMapReady={onMapReady}
        onProviderEvent={onProviderEvent}
        onPress={(e) => setStatus(`Map tap ${e.latitude.toFixed(5)}, ${e.longitude.toFixed(5)}`)}
        onMarkerPress={(id) => setStatus(`Marker ${id}`)}
        onClusterPress={(e) => setStatus(`Cluster of ${e.markerIds.split(',').length}`)}
        onOverlayPress={(e) => setStatus(`${e.kind} ${e.id}`)}
        onModelPress={(id) => setStatus(`Model ${id}`)}
        onMarkerDragStart={(e) => setDrag(`start ${e.id}`)}
        onMarkerDrag={(e) => {
          setDragCount((n) => n + 1)
          setDrag(`${e.id} ${e.latitude.toFixed(5)}, ${e.longitude.toFixed(5)}`)
        }}
        onMarkerDragEnd={(e) => setDrag(`end ${e.id} ${e.latitude.toFixed(5)}`)}
        onError={(message) => {
          console.log(`MUNIM_MAPS_MAPBOX error ${message}`)
          if (errors.current.length < 40) errors.current.push(message)
        }}
      >
        <MarkerView id="avatar" coordinate={{ latitude: 41.8838, longitude: -87.6290 }} anchor={{ x: 0.5, y: 1 }}>
          <View style={styles.avatarWrap}>
            <View style={styles.avatar}>
              <Text style={styles.emoji}>🧑‍🚀</Text>
            </View>
            <View style={styles.floor}>
              <Text style={styles.floorText}>5F</Text>
            </View>
          </View>
        </MarkerView>
        <MarkerView id="pill" coordinate={{ latitude: 41.8800, longitude: -87.6285 }} draggable>
          <View style={styles.pill}>
            <Text style={styles.pillText}>Drag this view</Text>
          </View>
        </MarkerView>
      </MunimMapView>
      <View style={[styles.panel, { top: props.topInset + 8 }]}>
        <ScrollView horizontal contentContainerStyle={styles.row} showsHorizontalScrollIndicator={false}>
          {props.onExit ? <Chip label="‹ Back" onPress={props.onExit} /> : null}
          <Chip label={satellite ? 'Satellite' : 'Standard'} onPress={() => setSatellite((s) => !s)} />
          <Chip label={`Light: ${PRESETS[preset]}`} onPress={() => setPreset((p) => (p + 1) % PRESETS.length)} />
          <Chip label={globe ? 'Globe' : 'Mercator'} onPress={() => setGlobe((g) => !g)} />
          <Chip label={terrain ? 'Terrain on' : 'Terrain off'} onPress={() => setTerrain((t) => !t)} />
          <Chip label={`Models: ${RENDERING[rendering]}`} onPress={() => setRendering((r) => (r + 1) % RENDERING.length)} />
          <Chip label={layersOn ? 'Layers on' : 'Layers off'} onPress={() => setLayersOn((l) => !l)} />
          <Chip label={`Track: ${tracking}`} onPress={() => setTracking((t) => (t === 'none' ? 'follow' : t === 'follow' ? 'followWithHeading' : 'none'))} />
          <Chip label="Zoom out" onPress={() => ref.current?.animateCamera({ latitude: 30, longitude: -60, distance: 18_000_000, pitch: 0, heading: 0 }, 2500, 'easeInOut')} />
          <Chip label="Chicago" onPress={() => ref.current?.animateCamera(CHICAGO, 2000, 'easeInOut')} />
          <Chip label={running ? 'Checking…' : 'Run checks'} onPress={() => void runChecks()} />
        </ScrollView>
        <Text style={styles.status}>
          {Platform.OS} · Mapbox {ready ? 'ready' : 'loading'} {status ? `· ${status}` : ''}
        </Text>
        {drag ? <Text style={styles.status}>Drag: {drag} ({dragCount} moves)</Text> : null}
        {checks.length ? (
          <ScrollView style={styles.checks}>
            {checks.map((c) => (
              <Text key={c.name} style={[styles.check, !c.ok && styles.fail]}>
                {c.ok ? '✓' : '✗'} {c.name} {c.detail ? `— ${c.detail}` : ''}
              </Text>
            ))}
          </ScrollView>
        ) : null}
      </View>
    </View>
  )
}

function Chip(props: { label: string; onPress: () => void }) {
  return (
    <Pressable onPress={props.onPress} style={styles.chip}>
      <Text style={styles.chipText}>{props.label}</Text>
    </Pressable>
  )
}

const styles = StyleSheet.create({
  panel: { position: 'absolute', left: 12, right: 12, padding: 10, borderRadius: 14, backgroundColor: 'rgba(20,20,24,0.72)', gap: 6 },
  row: { flexDirection: 'row', gap: 8 },
  chip: { paddingHorizontal: 12, paddingVertical: 7, borderRadius: 999, backgroundColor: 'rgba(255,255,255,0.14)' },
  chipText: { color: '#FFFFFF', fontSize: 13, fontWeight: '600' },
  status: { color: '#FFFFFF', fontSize: 12 },
  checks: { maxHeight: 260 },
  check: { color: '#D1FFD6', fontSize: 11 },
  fail: { color: '#FFB4A9' },
  avatarWrap: { alignItems: 'center' },
  avatar: { width: 44, height: 44, borderRadius: 22, backgroundColor: '#FFFFFF', borderWidth: 3, borderColor: '#0A84FF', alignItems: 'center', justifyContent: 'center' },
  emoji: { fontSize: 24 },
  floor: { marginTop: -6, paddingHorizontal: 6, paddingVertical: 1, borderRadius: 8, backgroundColor: '#111111' },
  floorText: { color: '#FFFFFF', fontSize: 10, fontWeight: '800' },
  pill: { paddingHorizontal: 10, paddingVertical: 6, borderRadius: 14, backgroundColor: '#FF2D55' },
  pillText: { color: '#FFFFFF', fontSize: 12, fontWeight: '700' },
})
