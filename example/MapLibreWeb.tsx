import { useCallback, useEffect, useRef, useState } from 'react'
import { Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native'
import { File, Paths } from 'expo-file-system'
import {
  MarkerView,
  MunimMapView,
  maplibreCommands,
  type MapCamera,
  type MapCircle,
  type MapClusterStyle,
  type MapLibreMapOptions,
  type MapMarker,
  type MapModel,
  type MapPath,
  type MapPolygon,
  type MapPolyline,
  type MapProviderEvent,
  type MapZone,
  type MunimMapViewRef,
} from 'munim-maps'
import { VEHICLES } from 'munim-maps-vehicles'

/**
 * The MapLibre engine's GL JS renderer (`maplibre={{ renderer: 'auto' }}`
 * picks it here because of `globe`, `terrain` and `sky`): the globe with its
 * atmosphere, 3D terrain from keyless AWS Terrain Tiles with hillshade,
 * markers, shapes, runtime style layers, and munim-maps' 3D layer drawn
 * inside GL JS (vehicles on the street, on the globe and on the mountains,
 * an avatar, labels, stems, a zone, a path, effects). "Run checks" exercises
 * the shared API, the MapLibre commands and what only GL JS has, and writes
 * the results (iOS: Documents/munim-maps-maplibre-web-checks.json; both:
 * `MUNIM_MAPLIBRE_WEB_CHECK` log lines). munimmapsexample://maplibre/web
 * opens it (`/city` and `/alps` start there), munimmapsexample://maplibre/web/checks
 * also runs the checks.
 */

const LOOP = { latitude: 41.8826, longitude: -87.6278 }
const ALPS = { latitude: 46.5775, longitude: 7.9605 } // Kleine Scheidegg, under the Eiger
const GLOBE_CAMERA: MapCamera = { latitude: 30, longitude: -40, distance: 18_000_000, pitch: 0, heading: 0 }
const CITY_CAMERA: MapCamera = { ...LOOP, distance: 1400, pitch: 50, heading: 20 }
const ALPS_CAMERA: MapCamera = { ...ALPS, distance: 5000, pitch: 62, heading: 40 }

const MODELS: MapModel[] = [
  { id: 'bus', coordinate: { latitude: 41.8829, longitude: -87.6279 }, source: VEHICLES['bus-city'], heading: 0, tint: '#0A84FF', screenSize: 26, label: 'Bus' },
  { id: 'taxi', coordinate: { latitude: 41.8822, longitude: -87.6271 }, source: VEHICLES['car-taxi'], heading: 90, screenSize: 22 },
  { id: 'balloon', coordinate: LOOP, altitude: 120, source: VEHICLES.balloon, screenSize: 56, stem: true, label: '120 m' },
  { id: 'ada', coordinate: { latitude: 41.8834, longitude: -87.6305 }, image: require('./assets/avatar-a.png'), imageBorder: { color: '#FF9F0A' }, badge: '5F', screenSize: 44 },
  { id: 'heli', coordinate: ALPS, altitude: 0, source: VEHICLES['heli-light'], heading: 200, screenSize: 30, label: 'On the ground' },
  { id: 'jet', coordinate: { latitude: 46.583, longitude: 7.95 }, altitude: 4600, altitudeReference: 'sea', source: VEHICLES['plane-jet'], heading: 60, screenSize: 30, stem: true },
  { id: 'smoke', coordinate: { latitude: 46.572, longitude: 7.966 }, shape: 'cylinder', size: { width: 30, height: 20, length: 30 }, color: '#8E8E93', effect: 'smoke' },
  // Over the Atlantic, high up, to see on the globe.
  { id: 'airliner', coordinate: { latitude: 30, longitude: -40 }, altitude: 11000, altitudeReference: 'sea', source: VEHICLES['plane-airliner'], heading: 70, screenSize: 40, label: 'Over the Atlantic' },
]

const MARKERS: MapMarker[] = [
  { id: 'pin', coordinate: { latitude: 41.8846, longitude: -87.6301 }, style: 'pin', color: '#FF3B30', title: 'Pin', callout: true },
  { id: 'balloon-marker', coordinate: { latitude: 41.8841, longitude: -87.6248 }, style: 'marker', glyph: '☕', color: '#AF52DE', title: 'Café', subtitle: 'Drag me', callout: true, draggable: true },
  { id: 'label', coordinate: { latitude: 41.8808, longitude: -87.6302 }, style: 'label', title: 'The Loop', color: '#1C1C1E', badges: [{ text: '3', position: 'top-right' }] },
  { id: 'dot', coordinate: { latitude: 41.8812, longitude: -87.6252 }, style: 'dot', color: '#34C759', size: 14 },
  { id: 'photo', coordinate: { latitude: 41.8852, longitude: -87.6285 }, style: 'avatar', image: require('./assets/avatar-b.png'), size: 40, title: 'Avatar' },
  { id: 'eiger', coordinate: { latitude: 46.5776, longitude: 8.0053 }, style: 'pin', color: '#FF9500', title: 'Eiger' },
  ...Array.from({ length: 6 }, (_, i): MapMarker => ({
    id: `c${i}`,
    coordinate: { latitude: 41.8786 + (i % 3) * 0.0002, longitude: -87.6236 + Math.floor(i / 3) * 0.0002 },
    style: 'dot',
    color: '#0A84FF',
    clusteringId: 'bikes',
  })),
]

const CLUSTERS: MapClusterStyle[] = [{ clusteringId: 'bikes', color: '#0A84FF', glyph: '{count}' }]

const POLYLINES: MapPolyline[] = [
  {
    id: 'route',
    coordinates: [
      { latitude: 41.879, longitude: -87.632 },
      { latitude: 41.88, longitude: -87.628 },
      { latitude: 41.885, longitude: -87.627 },
      { latitude: 41.886, longitude: -87.623 },
    ],
    strokeColors: ['#34C759', '#FFCC00', '#FF3B30'],
    strokeWidth: 6,
    tappable: true,
  },
  {
    id: 'dashed',
    coordinates: [
      { latitude: 41.877, longitude: -87.633 },
      { latitude: 41.877, longitude: -87.622 },
    ],
    strokeColor: '#5856D6',
    strokeWidth: 3,
    dashPattern: [6, 4],
    tappable: true,
  },
  // A great circle Chicago -> Zurich, on the globe.
  { id: 'flight', coordinates: [LOOP, { latitude: 47.45, longitude: 8.56 }], geodesic: true, strokeColor: '#FF2D55', strokeWidth: 2 },
]

const POLYGONS: MapPolygon[] = [
  {
    id: 'park',
    coordinates: [
      { latitude: 41.884, longitude: -87.623 },
      { latitude: 41.884, longitude: -87.62 },
      { latitude: 41.881, longitude: -87.62 },
      { latitude: 41.881, longitude: -87.623 },
    ],
    holes: [[
      { latitude: 41.883, longitude: -87.622 },
      { latitude: 41.883, longitude: -87.621 },
      { latitude: 41.882, longitude: -87.621 },
      { latitude: 41.882, longitude: -87.622 },
    ]],
    fillColor: '#34C75944',
    strokeColor: '#34C759',
    strokeWidth: 2,
    tappable: true,
  },
]

const CIRCLES: MapCircle[] = [{ id: 'zone', center: { latitude: 41.88, longitude: -87.635 }, radius: 120, fillColor: '#FF950033', strokeColor: '#FF9500', strokeWidth: 2 }]

const ZONES: MapZone[] = [
  { id: 'block', polygon: [{ latitude: 41.8835, longitude: -87.6262 }, { latitude: 41.8835, longitude: -87.6248 }, { latitude: 41.8825, longitude: -87.6248 }, { latitude: 41.8825, longitude: -87.6262 }], height: 40, color: '#FF2D5560' },
  { id: 'summit', circle: { center: { latitude: 46.5776, longitude: 8.0053 }, radius: 300 }, height: 80, color: '#FFCC0080' },
]

const PATHS: MapPath[] = [
  {
    id: 'trail',
    coordinates: [
      { latitude: 46.5775, longitude: 7.9605, altitude: 30 },
      { latitude: 46.5735, longitude: 7.975, altitude: 30 },
      { latitude: 46.5755, longitude: 7.99, altitude: 30 },
      { latitude: 46.5776, longitude: 8.0053, altitude: 30 },
    ],
    color: '#FFCC00',
    width: 4,
  },
]

const POINTS = {
  type: 'FeatureCollection',
  features: Array.from({ length: 24 }, (_, i) => ({
    type: 'Feature',
    id: i + 1,
    properties: { mag: (i % 5) + 1, name: `p${i + 1}` },
    geometry: { type: 'Point', coordinates: [-87.636 + (i % 6) * 0.0035, 41.876 + Math.floor(i / 6) * 0.003] },
  })),
}

const OPTIONS: MapLibreMapOptions = {
  style: 'liberty',
  terrain: { exaggeration: 1 },
  sky: true,
  hillshade: { exaggeration: 0.35 },
  allowEvaluate: true,
  sources: {
    points: { type: 'geojson', data: POINTS },
    clustered: { type: 'geojson', data: POINTS, cluster: true, clusterRadius: 60 },
  },
  layers: [
    {
      id: 'points-circle',
      type: 'circle',
      source: 'points',
      paint: {
        'circle-radius': ['interpolate', ['linear'], ['get', 'mag'], 1, 4, 5, 10],
        'circle-color': ['case', ['boolean', ['feature-state', 'picked'], false], '#FF2D55', '#5AC8FA'],
        'circle-stroke-color': '#FFFFFF',
        'circle-stroke-width': 1.5,
      },
    },
    { id: 'clustered-count', type: 'circle', source: 'clustered', filter: ['has', 'point_count'], paint: { 'circle-radius': 0 } },
  ],
}

interface Check {
  name: string
  ok: boolean
  detail: string
}

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms))
const fail = (detail: string): never => {
  throw new Error(detail)
}

/** Drags a marker in the page with mouse events (GL JS markers drag on the page). */
const DRAG_SCRIPT = (id: string) => `
const el = [...document.querySelectorAll('.munim-marker')].find((e) => e.dataset.markerId === ${JSON.stringify(id)});
if (!el) throw new Error('no marker element');
const r = el.getBoundingClientRect();
const x0 = r.left + r.width / 2, y0 = r.top + r.height * 0.4;
const opts = (x, y) => ({ bubbles: true, cancelable: true, clientX: x, clientY: y, button: 0, buttons: 1, view: window });
el.dispatchEvent(new MouseEvent('mousedown', opts(x0, y0)));
const container = map.getCanvasContainer();
for (let i = 1; i <= 12; i++) { await new Promise((r) => setTimeout(r, 25)); container.dispatchEvent(new MouseEvent('mousemove', opts(x0 + i * 6, y0 + i * 3))); }
container.dispatchEvent(new MouseEvent('mouseup', opts(x0 + 72, y0 + 36)));
window.dispatchEvent(new MouseEvent('mouseup', opts(x0 + 72, y0 + 36)));
return true;`

export function MapLibreWebScreen(props: { topInset: number; autoChecks: boolean; start?: 'globe' | 'city' | 'alps'; onExit?: () => void }) {
  const ref = useRef<MunimMapViewRef | null>(null)
  const [checks, setChecks] = useState<Check[]>([])
  const [running, setRunning] = useState(false)
  const [lastEvent, setLastEvent] = useState('')
  const [errors, setErrors] = useState<string[]>([])
  const [style, setStyle] = useState<'liberty' | 'positron'>('liberty')
  const events = useRef<MapProviderEvent[]>([])
  const pressed = useRef<string[]>([])
  const drags = useRef<string[]>([])
  const ready = useRef(false)

  const onProviderEvent = useCallback((event: MapProviderEvent) => {
    events.current.push(event)
    if (!['idle', 'renderedMap', 'sourceChanged', 'cameraMoveStarted', 'styleImageMissing'].includes(event.name)) {
      setLastEvent(`${event.name} ${JSON.stringify(event.data).slice(0, 80)}`)
    }
  }, [])

  const runChecks = useCallback(async () => {
    const map = ref.current
    if (!map || running) return
    setRunning(true)
    const results: Check[] = []
    const ml = maplibreCommands(map)
    const check = async (name: string, body: () => Promise<string | boolean>) => {
      try {
        const out = await body()
        results.push({ name, ok: out !== false, detail: typeof out === 'string' ? out : '' })
      } catch (error) {
        results.push({ name, ok: false, detail: String(error) })
      }
      console.log(`MUNIM_MAPLIBRE_WEB_CHECK ${JSON.stringify(results[results.length - 1])}`)
      setChecks([...results])
    }
    const go = async (camera: MapCamera, ms = 2500) => {
      map.setCamera(camera, false)
      await wait(ms)
    }
    for (let i = 0; i < 80 && !ready.current; i++) await wait(250)

    // The renderer
    await check('auto picks the GL JS renderer (globe, terrain, sky)', async () => {
      const r = await ml.getRenderer()
      return r.renderer === 'web' && r.maplibre.startsWith('5.') ? `GL JS ${r.maplibre}` : fail(JSON.stringify(r))
    })
    await check('renderer event and style loaded', async () => {
      const renderer = events.current.some((e) => e.name === 'renderer')
      const loaded = events.current.some((e) => e.name === 'styleLoaded')
      return renderer && loaded ? 'renderer + styleLoaded events' : fail(`renderer ${renderer}, styleLoaded ${loaded}`)
    })

    // Globe
    await go(GLOBE_CAMERA, 3500)
    await check('globe projection when zoomed out', async () => {
      const globe = await ml.isGlobe()
      const p = await ml.getProjection()
      return globe ? `projection ${JSON.stringify(p.type).slice(0, 60)}` : fail('not a globe')
    })
    await check('getCamera matches setCamera on the globe', async () => {
      const c = await map.getCamera()
      const ok = Math.abs(c.latitude - GLOBE_CAMERA.latitude) < 1e-3 && Math.abs(c.longitude - GLOBE_CAMERA.longitude) < 1e-3 && Math.abs(c.distance / GLOBE_CAMERA.distance - 1) < 0.03
      return ok ? `distance ${(c.distance / 1000).toFixed(0)} km` : fail(JSON.stringify(c))
    })
    await check('sky and atmosphere', async () => {
      const sky = await ml.getSky()
      return sky && sky['sky-color'] && sky['atmosphere-blend'] != null ? `sky ${String(sky['sky-color'])}` : fail(JSON.stringify(sky))
    })
    await check('3D layer on the globe (measureAlignment)', async () => {
      const a = await map.measureAlignment()
      return a.attached && a.modelsMeasured > 0 && a.maxErrorPoints < 1 ? `max ${a.maxErrorPoints.toFixed(3)} pt over ${a.modelsMeasured}` : fail(JSON.stringify(a))
    })
    await check('pointForCoordinate / coordinateForPoint on the globe', async () => {
      // At 18 000 km a point is about 50 km: compare on screen.
      const at = { latitude: 35, longitude: -30 }
      const p = await map.pointForCoordinate(at)
      const c = await map.coordinateForPoint(p)
      const q = await map.pointForCoordinate(c)
      const error = Math.hypot(q.x - p.x, q.y - p.y)
      return error < 1.5 ? `(${p.x.toFixed(1)}, ${p.y.toFixed(1)}), back within ${error.toFixed(2)} pt` : fail(`${JSON.stringify(c)}, ${error.toFixed(2)} pt`)
    })

    // City (Mercator past zoom 12)
    await go(CITY_CAMERA)
    await check('the globe becomes Mercator when zoomed in', async () => ((await ml.isGlobe()) ? fail('still a globe') : 'Mercator at the city'))
    await check('getCamera matches setCamera', async () => {
      const c = await map.getCamera()
      const ok = Math.abs(c.latitude - CITY_CAMERA.latitude) < 1e-4 && Math.abs(c.distance / CITY_CAMERA.distance - 1) < 0.03 && Math.abs(c.pitch - CITY_CAMERA.pitch) < 0.5 && Math.abs(c.heading - CITY_CAMERA.heading) < 0.5
      return ok ? `distance ${c.distance.toFixed(0)} m` : fail(JSON.stringify(c))
    })
    await check('pointForCoordinate / coordinateForPoint round trip', async () => {
      const p = await map.pointForCoordinate(LOOP)
      const c = await map.coordinateForPoint(p)
      return Math.abs(c.latitude - LOOP.latitude) < 1e-5 && Math.abs(c.longitude - LOOP.longitude) < 1e-5 ? `(${p.x.toFixed(1)}, ${p.y.toFixed(1)})` : fail(JSON.stringify(c))
    })
    await check('getVisibleRegion contains the centre', async () => {
      const r = await map.getVisibleRegion()
      return Math.abs(r.latitude - LOOP.latitude) < r.latitudeDelta && r.latitudeDelta > 0 ? `${r.latitudeDelta.toFixed(4)}°` : fail(JSON.stringify(r))
    })
    await check('3D layer aligned with GL JS (measureAlignment, city)', async () => {
      const a = await map.measureAlignment()
      return a.modelsMeasured >= 3 && a.maxErrorPoints < 1 ? `max ${a.maxErrorPoints.toFixed(3)} pt over ${a.modelsMeasured}, ${a.modelsVisibleInRender} on screen` : fail(JSON.stringify(a))
    })
    await check('models loaded and drawn (vehicles, avatar, balloon)', async () => {
      const points = await ml.evaluate<Record<string, { loaded: boolean; x?: number; scale?: number }>>(`return munim.methods.modelScreenPoints()`)
      const drawn = ['bus', 'taxi', 'balloon', 'ada'].filter((id) => points[id]?.loaded && points[id]?.x != null)
      return drawn.length === 4 ? `${drawn.join(', ')}` : fail(JSON.stringify(points).slice(0, 200))
    })
    await check('onModelPress hit test', async () => {
      const points = await ml.evaluate<Record<string, { x: number; y: number }>>(`return munim.methods.modelScreenPoints()`)
      const taxi = points.taxi!
      const hit = await ml.evaluate<string>(`return munim.modelHit({ x: ${taxi.x}, y: ${taxi.y - 4} }) || ''`)
      return hit === 'taxi' ? 'taxi' : fail(`hit '${hit}'`)
    })
    await check('markers are drawn on the page', async () => {
      const points = await ml.evaluate<Record<string, { x: number; y: number; clustered: boolean }>>(`return munim.methods.markerScreenPoints()`)
      const p = await map.pointForCoordinate(MARKERS[0]!.coordinate)
      const pin = points.pin
      return pin && Math.hypot(pin.x - p.x, pin.y - p.y) < 1 ? `${Object.keys(points).length} markers` : fail(JSON.stringify(points).slice(0, 200))
    })
    await check('MarkerView drawn as an image marker', async () => {
      await wait(500)
      const points = await ml.evaluate<Record<string, unknown>>(`return munim.methods.markerScreenPoints()`)
      return points.chip ? 'chip' : fail(Object.keys(points).join(','))
    })
    await check('clustering merges close markers', async () => {
      await go({ ...LOOP, distance: 6000, pitch: 0, heading: 0 }, 2000)
      const points = await ml.evaluate<Record<string, { clustered: boolean }>>(`munim.updateClusters(); return munim.methods.markerScreenPoints()`)
      const clustered = Object.entries(points).filter(([id, p]) => id.startsWith('c') && p.clustered).length
      await go(CITY_CAMERA, 1500)
      return clustered >= 2 ? `${clustered} of 6 in a cluster` : fail(`${clustered} clustered`)
    })
    await check('selectMarker / deselectMarker events', async () => {
      pressed.current = []
      map.selectMarker('pin')
      for (let i = 0; i < 20 && !pressed.current.length; i++) await wait(100)
      map.deselectMarker('pin')
      for (let i = 0; i < 20 && pressed.current.length < 2; i++) await wait(100)
      return pressed.current.join(',') === 'press:pin,deselect:pin' ? pressed.current.join(',') : fail(pressed.current.join(','))
    })
    await check('dragging: onMarkerDragStart, continuous onMarkerDrag, onMarkerDragEnd', async () => {
      drags.current = []
      await ml.evaluate(DRAG_SCRIPT('balloon-marker'))
      await wait(500)
      const moves = drags.current.filter((d) => d === 'drag').length
      return drags.current[0] === 'start' && drags.current[drags.current.length - 1] === 'end' && moves >= 5 ? `${moves} drag events` : fail(drags.current.join(','))
    })
    await check('runtime layer from maplibre.layers renders', async () => {
      const hits = await ml.queryRenderedFeatures({ layers: ['points-circle'] })
      return hits.length > 0 ? `${hits.length} circles` : fail('none')
    })
    await check('querySourceFeatures', async () => {
      const found = await ml.querySourceFeatures({ source: 'points', filter: ['>=', ['get', 'mag'], 3] })
      return found.length > 0 ? `${found.length} with mag ≥ 3` : fail('none')
    })
    await check('getStyle lists layers and sources (hillshade, terrain DEM, shapes, 3D layer)', async () => {
      const s = await ml.getStyle()
      const want = ['points-circle', 'munim-hillshade', 'munim-shape-polyline-route-line']
      const missing = want.filter((id) => !s.layers.includes(id))
      // Custom layers (the 3D layer) are not in GL JS's serialized style.
      const custom = await ml.evaluate<boolean>(`return !!map.getLayer('munim-3d')`)
      return missing.length === 0 && custom && s.sources.includes('munim-terrain-dem') ? `${s.layers.length} layers + the 3D layer, ${s.sources.length} sources` : fail(`missing ${missing.join(',')} 3D layer ${custom}`)
    })
    await check('setPaintProperty / setLayoutProperty / setFilter', async () => {
      await ml.setPaintProperty('points-circle', 'circle-opacity', 0.8)
      await ml.setLayoutProperty('points-circle', 'visibility', 'visible')
      await ml.setFilter('points-circle', ['>=', ['get', 'mag'], 2])
      await wait(500)
      const hits = await ml.queryRenderedFeatures({ layers: ['points-circle'] })
      await ml.setFilter('points-circle', null)
      return hits.length > 0 && hits.every((f) => Number(f.properties.mag) >= 2) ? `${hits.length} after filter` : fail(`${hits.length}`)
    })
    await check('addSource / addLayer / removeLayer / removeSource', async () => {
      await ml.addSource('extra', { type: 'geojson', data: { type: 'Feature', properties: {}, geometry: { type: 'Point', coordinates: [LOOP.longitude, LOOP.latitude] } } })
      await ml.addLayer({ id: 'extra-dot', type: 'circle', source: 'extra', paint: { 'circle-radius': 12, 'circle-color': '#FF2D55' } })
      await wait(500)
      const hits = await ml.queryRenderedFeatures({ layers: ['extra-dot'] })
      await ml.removeLayer('extra-dot')
      await ml.removeSource('extra')
      return hits.length === 1 ? 'added, drawn, removed' : fail(`${hits.length} hits`)
    })
    await check('feature state', async () => {
      await ml.setFeatureState({ source: 'points', id: 3, state: { picked: true } })
      const state = await ml.getFeatureState({ source: 'points', id: 3 })
      await ml.removeFeatureState({ source: 'points', id: 3 })
      return state?.picked === true ? JSON.stringify(state) : fail(JSON.stringify(state))
    })
    await check('GeoJSON clustering commands', async () => {
      await go({ ...LOOP, distance: 12000, pitch: 0, heading: 0 }, 2000)
      const clusters = await ml.querySourceFeatures({ source: 'clustered', filter: ['has', 'point_count'] })
      const id = Number(clusters[0]?.properties.cluster_id)
      const zoom = await ml.getClusterExpansionZoom({ source: 'clustered', clusterId: id })
      const leaves = await ml.getClusterLeaves({ source: 'clustered', clusterId: id, limit: 50 })
      await go(CITY_CAMERA, 1500)
      return leaves.length > 0 ? `cluster ${id}: zoom ${zoom}, ${leaves.length} leaves` : fail('no leaves')
    })
    await check('overlayAtPoint finds the tappable dashed polyline', async () => {
      const at = { latitude: 41.877, longitude: -87.6275 }
      await go({ ...CITY_CAMERA, ...at }, 1500)
      const p = await map.pointForCoordinate(at)
      const id = await map.overlayAtPoint(p)
      await go(CITY_CAMERA, 800)
      return id === 'dashed' ? id : fail(`got '${id}' at ${p.x.toFixed(0)},${p.y.toFixed(0)}`)
    })
    await check('fitToMarkers', async () => {
      map.fitToMarkers('pin,dot', { top: 60, left: 60, bottom: 60, right: 60 }, false)
      await wait(1000)
      const r = await map.getVisibleRegion()
      const inside = (c: { latitude: number; longitude: number }) => Math.abs(c.latitude - r.latitude) <= r.latitudeDelta / 2 && Math.abs(c.longitude - r.longitude) <= r.longitudeDelta / 2
      const ok = inside(MARKERS[0]!.coordinate) && inside(MARKERS[3]!.coordinate)
      await go(CITY_CAMERA, 800)
      return ok ? 'both in view' : fail(JSON.stringify(r))
    })
    await check('setRegion / getVisibleRegion', async () => {
      const region = { latitude: LOOP.latitude, longitude: LOOP.longitude, latitudeDelta: 0.01, longitudeDelta: 0.01 }
      map.setRegion(region, 0)
      await wait(1200)
      const r = await map.getVisibleRegion()
      const ok = Math.abs(r.latitude - region.latitude) < r.latitudeDelta / 2 && r.latitudeDelta >= region.latitudeDelta * 0.9
      await go(CITY_CAMERA, 800)
      return ok ? `${r.latitudeDelta.toFixed(4)}° × ${r.longitudeDelta.toFixed(4)}°` : fail(JSON.stringify(r))
    })
    await check('flyCamera keyframes', async () => {
      const start = Date.now() / 1000
      map.flyCamera([{ t: 0, camera: CITY_CAMERA }, { t: 1, camera: { ...CITY_CAMERA, heading: 110 } }], start, false)
      await wait(1700)
      const c = await map.getCamera()
      return Math.abs(c.heading - 110) < 1 ? `heading ${c.heading.toFixed(1)}` : fail(`heading ${c.heading}`)
    })
    await check('MapLibre flyTo', async () => {
      await wait(500)
      await ml.flyTo({ camera: { ...CITY_CAMERA, distance: 3000, heading: 0 }, durationMs: 800 })
      let c = await map.getCamera()
      for (let i = 0; i < 20 && Math.abs(c.distance / 3000 - 1) >= 0.05; i++) {
        await wait(250)
        c = await map.getCamera()
      }
      await go(CITY_CAMERA, 800)
      return Math.abs(c.distance / 3000 - 1) < 0.05 ? `distance ${c.distance.toFixed(0)}` : fail(`distance ${c.distance}, heading ${c.heading}`)
    })
    await check('metersPerPoint', async () => {
      const m = await ml.metersPerPoint(LOOP.latitude)
      return m > 0 ? `${m.toFixed(3)} m/pt` : fail(String(m))
    })
    await check('takeSnapshot (view, with the 3D layer)', async () => {
      const path = await map.takeSnapshot(320, 240)
      return path.endsWith('.png') ? path.split('/').pop()! : fail(path)
    })
    await check('snapshot command (offscreen map)', async () => {
      const path = await ml.snapshot({ width: 300, height: 200, camera: { ...LOOP, distance: 5000 }, styleUrl: 'https://tiles.openfreemap.org/styles/positron' })
      return path.endsWith('.png') ? path.split('/').pop()! : fail(path)
    })
    await check('offline packs say they are MapLibre Native only', async () => {
      try {
        await ml.offlineListPacks()
        return fail('resolved')
      } catch (error) {
        return /Native only/.test(String(error)) ? 'rejected with the reason' : fail(String(error))
      }
    })
    await check('addressForCoordinate (Nominatim)', async () => {
      const a = await map.addressForCoordinate(LOOP)
      return a.city === 'Chicago' ? a.formatted.slice(0, 60) : fail(a.formatted)
    })

    // Terrain
    await go(ALPS_CAMERA, 6000)
    await check('3D terrain from AWS Terrain Tiles', async () => {
      const terrain = await ml.getTerrain()
      const h = await ml.queryTerrainElevation(ALPS)
      return terrain && h != null && h > 1500 ? `ground ${h.toFixed(0)} m at Kleine Scheidegg` : fail(`terrain ${JSON.stringify(terrain)}, height ${h}`)
    })
    await check('models sit on the terrain (measureAlignment, Alps)', async () => {
      const a = await map.measureAlignment()
      const points = await ml.evaluate<Record<string, { ground: number; z: number }>>(`return munim.methods.modelScreenPoints()`)
      const heli = points.heli
      const onGround = heli && heli.ground > 1500 && Math.abs(heli.z - heli.ground) < 1
      if (a.modelsMeasured > 0 && a.maxErrorPoints < 1.5 && onGround) return `max ${a.maxErrorPoints.toFixed(3)} pt, heli at ${heli!.z.toFixed(0)} m`
      const debug = await ml.evaluate(`const c = map.getContainer(); const p = map.project([${ALPS.longitude}, ${ALPS.latitude}]); return { w: c.clientWidth, h: c.clientHeight, p: [p.x, p.y], cam: munim.munimCamera(), layer: !!map.getLayer('munim-3d'), zoom: map.getZoom() }`)
      return fail(`${a.modelsMeasured} measured, max ${a.maxErrorPoints}; heli ${JSON.stringify(heli)}; ${JSON.stringify(debug)}`)
    })
    await check('sea-level altitude stays above sea level on terrain', async () => {
      const points = await ml.evaluate<Record<string, { z: number }>>(`return munim.methods.modelScreenPoints()`)
      return points.jet && Math.abs(points.jet.z - 4600) < 1 ? `jet at ${points.jet.z.toFixed(0)} m` : fail(JSON.stringify(points.jet))
    })
    await check('pointForCoordinate puts a point on the terrain', async () => {
      const p = await map.pointForCoordinate(ALPS)
      const c = await map.coordinateForPoint(p)
      return Math.abs(c.latitude - ALPS.latitude) < 1e-4 && Math.abs(c.longitude - ALPS.longitude) < 1e-4 ? `(${p.x.toFixed(1)}, ${p.y.toFixed(1)})` : fail(JSON.stringify(c))
    })

    // Style switching keeps everything
    await go(CITY_CAMERA, 1500)
    await check('style switching keeps markers, shapes, runtime layers, terrain and the 3D layer', async () => {
      const before = events.current.filter((e) => e.name === 'styleLoaded').length
      setStyle('positron')
      for (let i = 0; i < 40 && events.current.filter((e) => e.name === 'styleLoaded').length === before; i++) await wait(250)
      await wait(2500)
      const s = await ml.getStyle()
      const terrain = await ml.getTerrain()
      const a = await map.measureAlignment()
      setStyle('liberty')
      await wait(2500)
      const ok = s.layers.includes('points-circle') && a.attached && s.layers.includes('munim-shape-polyline-route-line') && terrain && a.modelsMeasured > 0
      return ok ? 'positron: everything back' : fail(`${s.layers.filter((l) => l.startsWith('munim') || l.startsWith('points')).join(',')} terrain ${!!terrain}`)
    })

    const report = {
      platform: Platform.OS,
      finishedAt: new Date().toISOString(),
      passed: results.filter((r) => r.ok).length,
      total: results.length,
      checks: results,
      events: [...new Set(events.current.map((e) => e.name))],
    }
    console.log(`MUNIM_MAPLIBRE_WEB_CHECK summary ${report.passed}/${report.total}`)
    try {
      const file = new File(Paths.document, 'munim-maps-maplibre-web-checks.json')
      if (file.exists) file.delete()
      file.create()
      file.write(JSON.stringify(report, null, 2))
    } catch (error) {
      console.warn('MUNIM_MAPLIBRE_WEB_CHECK could not write the report', error)
    }
    await go(GLOBE_CAMERA, 0)
    setRunning(false)
  }, [running])

  useEffect(() => {
    if (!props.autoChecks) return
    const timer = setTimeout(() => void runChecks(), 4000)
    return () => clearTimeout(timer)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [props.autoChecks])

  const passed = checks.filter((c) => c.ok).length
  return (
    <View style={StyleSheet.absoluteFill}>
      <MunimMapView
        ref={ref}
        provider="maplibre"
        style={StyleSheet.absoluteFill}
        initialCamera={props.start === 'alps' ? ALPS_CAMERA : props.start === 'city' ? CITY_CAMERA : GLOBE_CAMERA}
        globe
        maplibre={{ ...OPTIONS, style }}
        models={MODELS}
        zones={ZONES}
        paths={PATHS}
        maxCameraDistance={50_000_000}
        markers={MARKERS}
        clusterStyles={CLUSTERS}
        polylines={POLYLINES}
        polygons={POLYGONS}
        circles={CIRCLES}
        showsScale
        selectableMapFeatures={['pointsOfInterest']}
        onMapReady={() => {
          ready.current = true
        }}
        onProviderEvent={onProviderEvent}
        onMarkerPress={(id) => {
          pressed.current.push(`press:${id}`)
          setLastEvent(`marker ${id}`)
        }}
        onMarkerDeselect={(id) => pressed.current.push(`deselect:${id}`)}
        onMarkerDragStart={() => drags.current.push('start')}
        onMarkerDrag={() => drags.current.push('drag')}
        onMarkerDragEnd={(e) => {
          drags.current.push('end')
          setLastEvent(`dragged ${e.id} to ${e.latitude.toFixed(4)}, ${e.longitude.toFixed(4)}`)
        }}
        onCalloutPress={(id) => setLastEvent(`callout ${id}`)}
        onClusterPress={(e) => setLastEvent(`cluster ${e.clusteringId}: ${e.markerIds}`)}
        onOverlayPress={(e) => setLastEvent(`overlay ${e.kind} ${e.id}`)}
        onMapFeaturePress={(f) => setLastEvent(`place ${f.title} (${f.category})`)}
        onModelPress={(id) => setLastEvent(`model ${id}`)}
        onLongPress={(e) => setLastEvent(`long press ${e.latitude.toFixed(4)}, ${e.longitude.toFixed(4)}`)}
        onError={(message) => setErrors((list) => (list.includes(message) ? list : [...list, message].slice(-3)))}
      >
        <MarkerView id="chip" coordinate={{ latitude: 41.8818, longitude: -87.6315 }} anchor={{ x: 0.5, y: 1 }}>
          <View style={styles.chipMarker}>
            <Text style={styles.chipMarkerText}>MarkerView</Text>
          </View>
        </MarkerView>
      </MunimMapView>
      <View style={[styles.panel, { top: props.topInset + 8 }]}>
        <ScrollView horizontal contentContainerStyle={styles.row} showsHorizontalScrollIndicator={false}>
          {props.onExit ? (
            <Pressable onPress={props.onExit} style={styles.chip}>
              <Text style={styles.chipText}>‹ Back</Text>
            </Pressable>
          ) : null}
          <Pressable onPress={() => void runChecks()} style={[styles.chip, styles.chipOn]}>
            <Text style={[styles.chipText, styles.chipTextOn]}>{running ? 'Checking…' : 'Run checks'}</Text>
          </Pressable>
          {([['Globe', GLOBE_CAMERA], ['City', CITY_CAMERA], ['Alps', ALPS_CAMERA]] as const).map(([label, camera]) => (
            <Pressable key={label} onPress={() => ref.current?.animateCamera(camera, 2500, 'easeInOut')} style={styles.chip}>
              <Text style={styles.chipText}>{label}</Text>
            </Pressable>
          ))}
        </ScrollView>
        {checks.length ? (
          <Text style={styles.status}>
            Checks {passed}/{checks.length}
            {checks.filter((c) => !c.ok).map((c) => ` · ✗ ${c.name}`).join('')}
          </Text>
        ) : null}
        {lastEvent ? <Text style={styles.status}>{lastEvent}</Text> : null}
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
  panel: { position: 'absolute', left: 12, right: 12, padding: 10, borderRadius: 14, backgroundColor: 'rgba(20,20,24,0.72)', gap: 6 },
  row: { flexDirection: 'row', gap: 8 },
  chip: { paddingHorizontal: 12, paddingVertical: 7, borderRadius: 999, backgroundColor: 'rgba(255,255,255,0.12)' },
  chipOn: { backgroundColor: '#FFFFFF' },
  chipText: { color: '#FFFFFF', fontSize: 13, fontWeight: '600' },
  chipTextOn: { color: '#111111' },
  status: { color: '#FFFFFF', fontSize: 12 },
  error: { color: '#FFB4A9', fontSize: 11 },
  chipMarker: { paddingHorizontal: 10, paddingVertical: 6, borderRadius: 10, backgroundColor: '#5856D6' },
  chipMarkerText: { color: '#FFFFFF', fontSize: 12, fontWeight: '700' },
})
