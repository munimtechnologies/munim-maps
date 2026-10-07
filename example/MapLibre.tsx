import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native'
import { File, Paths } from 'expo-file-system'
import {
  MunimMapView,
  maplibreCommands,
  openMapsServices,
  type MapCamera,
  type MapCircle,
  type MapClusterStyle,
  type MapLibreMapOptions,
  type MapLibreStylePreset,
  type MapMarker,
  type MapModel,
  type MapPolygon,
  type MapPolyline,
  type MapTileOverlay,
  type MunimMapViewRef,
} from 'munim-maps'
import { VEHICLES } from 'munim-maps/vehicles'

/**
 * The MapLibre engine with every feature group on one map: OpenStreetMap
 * data from OpenFreeMap (no key), markers of every style, a cluster, shapes,
 * a tile overlay, runtime style-spec sources and layers (circle, heatmap,
 * fill-extrusion), hillshade, the 3D layer with GLB / USDZ vehicles, style
 * switching. "Run checks" exercises the API and the MapLibre commands and
 * writes the results (iOS: Documents/munim-maps-maplibre-check.json; both:
 * `MUNIM_MAPLIBRE_CHECK` log lines). munimmapsexample://maplibre opens it,
 * munimmapsexample://maplibre/check also runs the checks.
 */

const LOOP = { latitude: 41.8826, longitude: -87.6278 }
const CAMERA: MapCamera = { ...LOOP, distance: 1400, pitch: 50, heading: 20 }
const STYLES: MapLibreStylePreset[] = ['liberty', 'bright', 'positron', 'dark', 'fiord', 'demotiles']

const MODELS: MapModel[] = [
  { id: 'bus', coordinate: { latitude: 41.8829, longitude: -87.6279 }, source: VEHICLES['bus-city'], heading: 0, tint: '#0A84FF', screenSize: 26 },
  { id: 'taxi', coordinate: { latitude: 41.8822, longitude: -87.6271 }, source: VEHICLES['car-taxi'], heading: 90, screenSize: 22 },
  { id: 'balloon', coordinate: LOOP, altitude: 120, source: VEHICLES.balloon, screenSize: 56 },
]

const MARKERS: MapMarker[] = [
  { id: 'pin', coordinate: { latitude: 41.8846, longitude: -87.6301 }, style: 'pin', color: '#FF3B30', title: 'Pin', callout: true },
  { id: 'balloon', coordinate: { latitude: 41.8841, longitude: -87.6248 }, style: 'marker', glyph: '☕', color: '#AF52DE', title: 'Café', subtitle: 'A balloon with a glyph', callout: true, draggable: true },
  { id: 'label', coordinate: { latitude: 41.8808, longitude: -87.6302 }, style: 'label', title: 'The Loop', color: '#1C1C1E' },
  { id: 'dot', coordinate: { latitude: 41.8812, longitude: -87.6252 }, style: 'dot', color: '#34C759', size: 14 },
  {
    id: 'avatar',
    coordinate: { latitude: 41.8834, longitude: -87.6322 },
    style: 'avatar',
    title: 'Ada Lovelace',
    color: '#FF9F0A',
    size: 40,
    badges: [{ text: '5F', position: 'bottom' }],
  },
  // A cluster of six, merged when they overlap.
  ...Array.from({ length: 6 }, (_, i): MapMarker => ({
    id: `c${i}`,
    coordinate: { latitude: 41.8786 + (i % 3) * 0.0004, longitude: -87.6236 + Math.floor(i / 3) * 0.0004 },
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
      { latitude: 41.8790, longitude: -87.6320 },
      { latitude: 41.8800, longitude: -87.6280 },
      { latitude: 41.8850, longitude: -87.6270 },
      { latitude: 41.8860, longitude: -87.6230 },
    ],
    strokeColors: ['#34C759', '#FFCC00', '#FF3B30'],
    strokeWidth: 6,
    tappable: true,
  },
  {
    id: 'dashed',
    coordinates: [
      { latitude: 41.8770, longitude: -87.6330 },
      { latitude: 41.8770, longitude: -87.6220 },
    ],
    strokeColor: '#5856D6',
    strokeWidth: 3,
    dashPattern: [6, 4],
    tappable: true,
  },
]

const POLYGONS: MapPolygon[] = [
  {
    id: 'park',
    coordinates: [
      { latitude: 41.8840, longitude: -87.6230 },
      { latitude: 41.8840, longitude: -87.6200 },
      { latitude: 41.8810, longitude: -87.6200 },
      { latitude: 41.8810, longitude: -87.6230 },
    ],
    holes: [[
      { latitude: 41.8830, longitude: -87.6220 },
      { latitude: 41.8830, longitude: -87.6210 },
      { latitude: 41.8820, longitude: -87.6210 },
      { latitude: 41.8820, longitude: -87.6220 },
    ]],
    fillColor: '#34C75944',
    strokeColor: '#34C759',
    strokeWidth: 2,
    tappable: true,
  },
]

const CIRCLES: MapCircle[] = [
  { id: 'zone', center: { latitude: 41.8800, longitude: -87.6350 }, radius: 120, fillColor: '#FF950033', strokeColor: '#FF9500', strokeWidth: 2 },
]

const TILES: MapTileOverlay[] = [
  { id: 'relief', urlTemplate: 'https://s3.amazonaws.com/elevation-tiles-prod/normal/{z}/{x}/{y}.png', opacity: 0.15, maximumZoom: 15 },
]

// Runtime style-spec content: a GeoJSON source with a circle layer, a
// heatmap and a clustered source, written exactly as in a style JSON.
const POINTS = {
  type: 'FeatureCollection',
  features: Array.from({ length: 24 }, (_, i) => ({
    type: 'Feature',
    id: i + 1,
    properties: { mag: (i % 5) + 1, name: `p${i + 1}` },
    geometry: { type: 'Point', coordinates: [-87.636 + (i % 6) * 0.0035, 41.876 + Math.floor(i / 6) * 0.003] },
  })),
}

function maplibreOptions(style: MapLibreStylePreset): MapLibreMapOptions {
  return {
    style,
    hillshade: { exaggeration: 0.4 },
    sources: {
      points: { type: 'geojson', data: POINTS },
      clustered: { type: 'geojson', data: POINTS, cluster: true, clusterRadius: 60 },
    },
    layers: [
      {
        id: 'points-heat',
        type: 'heatmap',
        source: 'points',
        maxzoom: 14,
        paint: { 'heatmap-radius': 30, 'heatmap-opacity': 0.6 },
      },
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
      {
        id: 'clustered-count',
        type: 'circle',
        source: 'clustered',
        filter: ['has', 'point_count'],
        paint: { 'circle-radius': 0 },
      },
    ],
    light: { anchor: 'viewport', intensity: 0.4 },
    transition: { duration: 300 },
    ornaments: { compass: { position: 'topRight', margin: { x: 12, y: 160 } }, scaleBar: { visible: true, position: 'bottomLeft', margin: { x: 12, y: 40 } } },
    rendering: { prefetchTiles: true },
  }
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

export function MapLibreScreen(props: { topInset: number; panel: boolean; autoCheck: boolean; onExit?: () => void }) {
  const ref = useRef<MunimMapViewRef | null>(null)
  const [style, setStyle] = useState<MapLibreStylePreset>('liberty')
  const [checks, setChecks] = useState<Check[]>([])
  const [running, setRunning] = useState(false)
  const [lastEvent, setLastEvent] = useState('')
  const [errors, setErrors] = useState<string[]>([])
  const events = useRef<{ name: string; payload: unknown }[]>([])
  const pressed = useRef<string[]>([])
  const ready = useRef(false)
  const options = useMemo(() => maplibreOptions(style), [style])

  const onProviderEvent = useCallback((event: { name: string; payload: unknown }) => {
    events.current.push(event)
    if (event.name !== 'idle' && event.name !== 'renderedMap') setLastEvent(`${event.name} ${JSON.stringify(event.payload).slice(0, 80)}`)
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
        const ok = out !== false
        results.push({ name, ok, detail: typeof out === 'string' ? out : '' })
      } catch (error) {
        results.push({ name, ok: false, detail: String(error) })
      }
      console.log(`MUNIM_MAPLIBRE_CHECK ${JSON.stringify(results[results.length - 1])}`)
      setChecks([...results])
    }
    for (let i = 0; i < 40 && !ready.current; i++) await wait(250)
    map.setCamera(CAMERA, false)
    await wait(1500)

    await check('map ready and style loaded', async () => {
      const loaded = events.current.some((e) => e.name === 'styleLoaded')
      return loaded ? 'styleLoaded event received' : false
    })
    await check('getCamera matches setCamera', async () => {
      const c = await map.getCamera()
      const ok = Math.abs(c.latitude - CAMERA.latitude) < 1e-4 && Math.abs(c.distance / CAMERA.distance - 1) < 0.03 &&
        Math.abs(c.pitch - CAMERA.pitch) < 0.5 && Math.abs(c.heading - CAMERA.heading) < 0.5
      return ok ? `distance ${c.distance.toFixed(0)} m` : false
    })
    await check('pointForCoordinate / coordinateForPoint round trip', async () => {
      const p = await map.pointForCoordinate(LOOP)
      const c = await map.coordinateForPoint(p)
      return Math.abs(c.latitude - LOOP.latitude) < 1e-5 && Math.abs(c.longitude - LOOP.longitude) < 1e-5 ? `(${p.x.toFixed(1)}, ${p.y.toFixed(1)})` : false
    })
    await check('getVisibleRegion contains the centre', async () => {
      const r = await map.getVisibleRegion()
      return Math.abs(r.latitude - LOOP.latitude) < r.latitudeDelta && r.latitudeDelta > 0 ? `${r.latitudeDelta.toFixed(4)}°` : false
    })
    await check('3D layer aligned with MapLibre (measureAlignment)', async () => {
      const a = await map.measureAlignment()
      return a.modelsMeasured > 0 && a.maxErrorPoints < 2 ? `max ${a.maxErrorPoints.toFixed(2)} pt over ${a.modelsMeasured}` : fail(`max ${a.maxErrorPoints} pt (${a.modelsMeasured} models)`)
    })
    await check('markers are style layers (queryRenderedFeatures)', async () => {
      const p = await map.pointForCoordinate(MARKERS[1]!.coordinate)
      const hits = await ml.queryRenderedFeatures({ box: { x: p.x - 20, y: p.y - 50, width: 40, height: 60 } })
      return hits.some((f) => f.properties.id === 'balloon') ? `${hits.length} features` : false
    })
    await check('runtime layer from maplibre.layers renders', async () => {
      const hits = await ml.queryRenderedFeatures({ layers: ['points-circle'] })
      return hits.length > 0 ? `${hits.length} circles` : false
    })
    await check('querySourceFeatures', async () => {
      const found = await ml.querySourceFeatures({ source: 'points', filter: ['>=', ['get', 'mag'], 3] })
      return found.length > 0 ? `${found.length} with mag ≥ 3` : false
    })
    await check('getStyle lists layers and sources', async () => {
      const s = await ml.getStyle()
      return s.layers.includes('points-circle') && s.sources.includes('points') ? `${s.layers.length} layers, ${s.sources.length} sources` : false
    })
    await check('setPaintProperty / setLayoutProperty / setFilter', async () => {
      await ml.setPaintProperty('points-circle', 'circle-opacity', 0.8)
      await ml.setLayoutProperty('points-heat', 'visibility', 'none')
      await ml.setFilter('points-circle', ['>=', ['get', 'mag'], 2])
      await wait(400)
      const hits = await ml.queryRenderedFeatures({ layers: ['points-circle'] })
      await ml.setFilter('points-circle', null)
      await ml.setLayoutProperty('points-heat', 'visibility', 'visible')
      return hits.every((f) => Number(f.properties.mag) >= 2) ? `${hits.length} after filter` : false
    })
    await check('addSource / addLayer / removeLayer / removeSource', async () => {
      await ml.addSource('extra', { type: 'geojson', data: { type: 'Feature', properties: {}, geometry: { type: 'Point', coordinates: [LOOP.longitude, LOOP.latitude] } } })
      await ml.addLayer({ id: 'extra-dot', type: 'circle', source: 'extra', paint: { 'circle-radius': 12, 'circle-color': '#FF2D55' } })
      await wait(300)
      const hits = await ml.queryRenderedFeatures({ layers: ['extra-dot'] })
      await ml.removeLayer('extra-dot')
      await ml.removeSource('extra')
      return hits.length === 1 ? 'added, drawn, removed' : false
    })
    await check('feature state', async () => {
      await ml.setFeatureState({ source: 'points', id: 3, state: { picked: true } })
      const state = await ml.getFeatureState({ source: 'points', id: 3 })
      await ml.removeFeatureState({ source: 'points', id: 3 })
      return state?.picked === true ? JSON.stringify(state) : false
    })
    await check('GeoJSON clustering commands', async () => {
      map.setCamera({ ...LOOP, distance: 12000, pitch: 0, heading: 0 }, false)
      await wait(1500)
      const clusters = await ml.querySourceFeatures({ source: 'clustered', filter: ['has', 'point_count'] })
      const id = Number(clusters[0]?.properties.cluster_id)
      const zoom = await ml.getClusterExpansionZoom({ source: 'clustered', clusterId: id })
      const leaves = await ml.getClusterLeaves({ source: 'clustered', clusterId: id, limit: 50 })
      map.setCamera(CAMERA, false)
      await wait(800)
      return leaves.length > 0 ? `cluster ${id}: zoom ${zoom}, ${leaves.length} leaves` : false
    })
    await check('overlayAtPoint finds the tappable polyline', async () => {
      const p = await map.pointForCoordinate({ latitude: 41.8770, longitude: -87.6275 })
      const id = await map.overlayAtPoint(p)
      return id === 'dashed' ? id : fail(`got '${id}'`)
    })
    await check('selectMarker / deselectMarker events', async () => {
      pressed.current = []
      map.selectMarker('pin')
      await wait(200)
      map.deselectMarker('pin')
      await wait(200)
      return pressed.current.join(',') === 'press:pin,deselect:pin' ? pressed.current.join(',') : fail(pressed.current.join(','))
    })
    await check('fitToMarkers', async () => {
      map.fitToMarkers('pin,dot', { top: 60, left: 60, bottom: 60, right: 60 }, false)
      await wait(800)
      const r = await map.getVisibleRegion()
      const inside = (c: { latitude: number; longitude: number }) =>
        Math.abs(c.latitude - r.latitude) <= r.latitudeDelta / 2 && Math.abs(c.longitude - r.longitude) <= r.longitudeDelta / 2
      const ok = inside(MARKERS[0]!.coordinate) && inside(MARKERS[3]!.coordinate)
      map.setCamera(CAMERA, false)
      await wait(800)
      return ok ? 'both in view' : false
    })
    await check('flyCamera keyframes (native frame clock)', async () => {
      const start = Date.now() / 1000
      map.flyCamera([
        { t: 0, camera: CAMERA },
        { t: 1, camera: { ...CAMERA, heading: 110 } },
      ], start, false)
      await wait(1500)
      const c = await map.getCamera()
      return Math.abs(c.heading - 110) < 1 ? `heading ${c.heading.toFixed(1)}` : false
    })
    await check('MapLibre flyTo', async () => {
      await ml.flyTo({ camera: { ...CAMERA, distance: 3000, heading: 0 }, durationMs: 800 })
      await wait(1500)
      const c = await map.getCamera()
      map.setCamera(CAMERA, false)
      await wait(800)
      return Math.abs(c.distance / 3000 - 1) < 0.05 ? `distance ${c.distance.toFixed(0)}` : false
    })
    await check('metersPerPoint', async () => {
      const m = await ml.metersPerPoint(LOOP.latitude)
      return m > 0 ? `${m.toFixed(3)} m/pt` : false
    })
    await check('takeSnapshot (view)', async () => {
      const path = await map.takeSnapshot(320, 240)
      return path.endsWith('.png') ? path.split('/').pop()! : false
    })
    await check('snapshot command (offscreen MapSnapshotter)', async () => {
      const path = await ml.snapshot({ width: 300, height: 200, camera: { ...LOOP, distance: 5000 }, styleUrl: 'https://tiles.openfreemap.org/styles/positron' })
      return path.endsWith('.png') ? path.split('/').pop()! : false
    })
    await check('offline pack: create, progress, list, delete', async () => {
      events.current = events.current.filter((e) => e.name !== 'offlineProgress')
      const pack = await ml.offlineCreatePack({
        name: 'loop-test',
        bounds: { south: 41.880, west: -87.630, north: 41.884, east: -87.625 },
        minZoom: 13,
        maxZoom: 14,
        metadata: { test: true },
      })
      for (let i = 0; i < 40 && !events.current.some((e) => e.name === 'offlineProgress'); i++) await wait(250)
      const progress = events.current.filter((e) => e.name === 'offlineProgress').length
      const list = await ml.offlineListPacks()
      const found = list.find((p) => p.id === pack.id)
      await ml.offlineDeletePack(pack.id)
      const after = await ml.offlineListPacks()
      return found && found.name === 'loop-test' && progress > 0 && !after.some((p) => p.id === pack.id)
        ? `${progress} progress events, ${found.completedResources}/${found.expectedResources} resources`
        : false
    })
    await check('ambient cache size', async () => {
      await ml.offlineSetAmbientCacheSize(64 * 1024 * 1024)
      return '64 MB'
    })
    await check('addressForCoordinate (Nominatim)', async () => {
      const a = await map.addressForCoordinate(LOOP)
      return a.city === 'Chicago' ? a.formatted.slice(0, 60) : fail(a.formatted)
    })
    await check('openMapsServices.search (Photon)', async () => {
      const places = await openMapsServices.search('Willis Tower', { near: LOOP, limit: 3 })
      return places.length > 0 ? places[0]!.formatted.slice(0, 60) : false
    })
    await check('openMapsServices.route (OSRM)', async () => {
      const routes = await openMapsServices.route([LOOP, { latitude: 41.8789, longitude: -87.6359 }], { profile: 'walking' })
      return routes[0] && routes[0].coordinates.length > 1 ? `${routes[0].distance.toFixed(0)} m, ${routes[0].steps.length} steps` : false
    })
    await check('style switching keeps markers and runtime layers', async () => {
      const before = events.current.filter((e) => e.name === 'styleLoaded').length
      setStyle('positron')
      for (let i = 0; i < 40 && events.current.filter((e) => e.name === 'styleLoaded').length === before; i++) await wait(250)
      await wait(1200)
      const s = await ml.getStyle()
      const p = await map.pointForCoordinate(MARKERS[1]!.coordinate)
      const hits = await ml.queryRenderedFeatures({ box: { x: p.x - 20, y: p.y - 50, width: 40, height: 60 } })
      setStyle('liberty')
      await wait(1500)
      return s.layers.includes('points-circle') && hits.some((f) => f.properties.id === 'balloon') ? 'positron: markers and layers back' : false
    })
    
    const report = {
      platform: Platform.OS,
      passed: results.filter((r) => r.ok).length,
      total: results.length,
      checks: results,
      events: [...new Set(events.current.map((e) => e.name))],
    }
    console.log(`MUNIM_MAPLIBRE_CHECK summary ${report.passed}/${report.total}`)
    try {
      const file = new File(Paths.document, 'munim-maps-maplibre-check.json')
      if (file.exists) file.delete()
      file.create()
      file.write(JSON.stringify(report, null, 2))
    } catch (error) {
      console.warn('MUNIM_MAPLIBRE_CHECK could not write the report', error)
    }
    setRunning(false)
  }, [running])

  useEffect(() => {
    if (!props.autoCheck) return
    const timer = setTimeout(() => void runChecks(), 4000)
    return () => clearTimeout(timer)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [props.autoCheck])

  const passed = checks.filter((c) => c.ok).length
  return (
    <View style={StyleSheet.absoluteFill}>
      <MunimMapView
        ref={ref}
        provider="maplibre"
        style={StyleSheet.absoluteFill}
        initialCamera={CAMERA}
        maplibre={options}
        models={MODELS}
        markers={MARKERS}
        clusterStyles={CLUSTERS}
        polylines={POLYLINES}
        polygons={POLYGONS}
        circles={CIRCLES}
        tileOverlays={TILES}
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
        onCalloutPress={(id) => setLastEvent(`callout ${id}`)}
        onClusterPress={(e) => setLastEvent(`cluster ${e.clusteringId}: ${e.markerIds}`)}
        onOverlayPress={(e) => setLastEvent(`overlay ${e.kind} ${e.id}`)}
        onMapFeaturePress={(f) => setLastEvent(`place ${f.title} (${f.category})`)}
        onMarkerDragEnd={(e) => setLastEvent(`dragged ${e.id} to ${e.latitude.toFixed(4)}, ${e.longitude.toFixed(4)}`)}
        onModelPress={(id) => setLastEvent(`model ${id}`)}
        onLongPress={(e) => setLastEvent(`long press ${e.latitude.toFixed(4)}, ${e.longitude.toFixed(4)}`)}
        onError={(message) => setErrors((list) => (list.includes(message) ? list : [...list, message].slice(-3)))}
      />
      <View style={[styles.panel, { top: props.topInset + 8 }, !props.panel && styles.hidden]}>
        <ScrollView horizontal contentContainerStyle={styles.row} showsHorizontalScrollIndicator={false}>
          {props.onExit ? (
            <Pressable onPress={props.onExit} style={styles.chip}>
              <Text style={styles.chipText}>‹ Back</Text>
            </Pressable>
          ) : null}
          <Pressable onPress={() => void runChecks()} style={[styles.chip, styles.chipOn]}>
            <Text style={[styles.chipText, styles.chipTextOn]}>{running ? 'Checking…' : 'Run checks'}</Text>
          </Pressable>
          {STYLES.map((s) => (
            <Pressable key={s} onPress={() => setStyle(s)} style={[styles.chip, s === style && styles.chipOn]}>
              <Text style={[styles.chipText, s === style && styles.chipTextOn]}>{s}</Text>
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
  hidden: { display: 'none' },
})
