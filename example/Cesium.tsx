import { useMemo, useRef, useState } from 'react'
import { File, Paths } from 'expo-file-system'
import { Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native'
import {
  MunimMapView,
  cesiumCommands,
  parseCesiumEvent,
  type CesiumMapOptions,
  type CzmlPacket,
  type MapCamera,
  type MapCircle,
  type MapMarker,
  type MapModel,
  type MapPath,
  type MapPolygon,
  type MapPolyline,
  type MapTileOverlay,
  type MapZone,
  type MunimMapViewRef,
} from 'munim-maps'
import { VEHICLES_GLB } from 'munim-maps/vehicles-glb'
import { VEHICLES } from 'munim-maps/vehicles'

/**
 * The Cesium engine with every group of features: the shared munim-maps
 * API (markers, shapes, camera, models, zones, paths) and the `cesium`
 * options (imagery, terrain, 3D Tiles, CZML, data sources, clock, scene
 * modes, lighting, post-processing, widgets) plus `cesiumCommands`.
 * munimmapsexample://cesium — and munimmapsexample://cesium/checks runs the
 * checks (also behind the Checks button); results go to the panel, the log
 * (`MUNIM_MAPS_CESIUM`) and Documents/munim-maps-cesium-checks.json.
 */

const CAMERA: MapCamera = { latitude: 41.8826, longitude: -87.6278, distance: 1100, pitch: 55, heading: 30 }
const NOW = Date.now() / 1000

const JET_ROUTE = [
  { t: 0, coordinate: { latitude: 41.8760, longitude: -87.6400 }, altitude: 260 },
  { t: 20, coordinate: { latitude: 41.8900, longitude: -87.6150 }, altitude: 320 },
  { t: 40, coordinate: { latitude: 41.8760, longitude: -87.6400 }, altitude: 260 },
]

function models(native: boolean): MapModel[] {
  return [
    { id: 'bus', coordinate: { latitude: 41.8829, longitude: -87.6279 }, source: VEHICLES_GLB['bus-city'], heading: 0, tint: '#0A84FF', screenSize: 40, label: 'Bus' },
    { id: 'taxi', coordinate: { latitude: 41.8822, longitude: -87.6271 }, source: VEHICLES_GLB['car-taxi'], heading: 90, screenSize: 28 },
    { id: 'police', coordinate: { latitude: 41.8833, longitude: -87.6268 }, source: VEHICLES_GLB['car-police'], heading: 180, screenSize: 28, spinDegreesPerSecond: 30 },
    { id: 'jet', coordinate: JET_ROUTE[0]!.coordinate, source: VEHICLES_GLB['plane-jet'], screenSize: 60, effect: 'contrail', motion: { keyframes: JET_ROUTE, start: NOW, loop: true } },
    { id: 'fox', coordinate: { latitude: 41.8818, longitude: -87.6290 }, source: require('./assets/models/Fox.glb'), scale: 0.2, heading: 45 },
    { id: 'tower', coordinate: { latitude: 41.8838, longitude: -87.6295 }, shape: 'cylinder', size: { width: 20, height: 60 }, color: '#FF9500', label: 'Shape' },
    { id: 'friend', coordinate: { latitude: 41.8812, longitude: -87.6258 }, altitude: 30, image: require('./assets/avatar-a.png'), badge: '8F', stem: true, label: 'Friend', imageBorder: { color: '#34C759' } },
    { id: 'smoke', coordinate: { latitude: 41.8846, longitude: -87.6245 }, effect: 'smoke', size: { width: 30, height: 60 } },
    // USDZ on iOS: drawn by the native 3D layer on Cesium's camera (modelRenderer 'auto').
    ...(Platform.OS === 'ios' || native ? [{ id: 'native-sedan', coordinate: { latitude: 41.8826, longitude: -87.6278 }, source: VEHICLES['car-sedan'], heading: 30, screenSize: 30 } satisfies MapModel] : []),
  ]
}

const MARKERS: MapMarker[] = [
  { id: 'pin', coordinate: { latitude: 41.8848, longitude: -87.6262 }, title: 'Pin', subtitle: 'Callout with accessories', calloutRight: 'detail', calloutLeft: { text: 'Go' } },
  { id: 'balloon', coordinate: { latitude: 41.8808, longitude: -87.6292 }, title: 'Balloon', style: 'marker', color: '#34C759', glyph: 'B', badges: [{ text: '3', position: 'top-right' }] },
  { id: 'label', coordinate: { latitude: 41.8840, longitude: -87.6235 }, title: 'Label', style: 'label', color: '#0A84FF' },
  { id: 'dot', coordinate: { latitude: 41.8805, longitude: -87.6255 }, title: 'Dot', style: 'dot', color: '#FF9500' },
  { id: 'drag', coordinate: { latitude: 41.8795, longitude: -87.6280 }, title: 'Drag me', draggable: true, color: '#AF52DE' },
  { id: 'avatar', coordinate: { latitude: 41.8800, longitude: -87.6310 }, title: 'Avatar', style: 'avatar', image: require('./assets/avatar-b.png') },
  ...Array.from({ length: 12 }, (_, i): MapMarker => ({ id: `c${i}`, coordinate: { latitude: 41.889 + (i % 4) * 0.0006, longitude: -87.633 + Math.floor(i / 4) * 0.0007 }, style: 'dot', color: '#FF2D55', clusteringId: 'shops' })),
]

const POLYLINES: MapPolyline[] = [
  { id: 'route', coordinates: [{ latitude: 41.8789, longitude: -87.6359 }, { latitude: 41.8826, longitude: -87.6290 }, { latitude: 41.8921, longitude: -87.6264 }], strokeColors: ['#FF3B30', '#FFCC00', '#34C759'], strokeWidth: 6 },
  { id: 'dashed', coordinates: [{ latitude: 41.8770, longitude: -87.6240 }, { latitude: 41.8860, longitude: -87.6200 }], strokeColor: '#5856D6', strokeWidth: 4, dashPattern: [10, 6] },
]
const POLYGONS: MapPolygon[] = [
  {
    id: 'park',
    coordinates: [{ latitude: 41.8850, longitude: -87.6330 }, { latitude: 41.8865, longitude: -87.6300 }, { latitude: 41.8842, longitude: -87.6290 }, { latitude: 41.8835, longitude: -87.6320 }],
    holes: [[{ latitude: 41.8848, longitude: -87.6315 }, { latitude: 41.8852, longitude: -87.6305 }, { latitude: 41.8845, longitude: -87.6303 }]],
    fillColor: '#34C75955',
    strokeColor: '#34C759',
    strokeWidth: 3,
  },
]
const CIRCLES: MapCircle[] = [{ id: 'radius', center: { latitude: 41.8812, longitude: -87.6232 }, radius: 120, fillColor: '#FF950033', strokeColor: '#FF9500', strokeWidth: 2 }]
const ZONES: MapZone[] = [{ id: 'zone', polygon: [{ latitude: 41.8810, longitude: -87.6300 }, { latitude: 41.8810, longitude: -87.6282 }, { latitude: 41.8800, longitude: -87.6282 }, { latitude: 41.8800, longitude: -87.6300 }], height: 50 }]
const PATHS: MapPath[] = [{ id: 'flight', coordinates: JET_ROUTE.map((k) => ({ ...k.coordinate, altitude: k.altitude })), color: '#FFCC00', width: 3 }]
const TILES: MapTileOverlay[] = [{ id: 'hillshade', urlTemplate: 'https://services.arcgisonline.com/ArcGIS/rest/services/Elevation/World_Hillshade/MapServer/tile/{z}/{y}/{x}', opacity: 0.4 }]

/** CZML: a satellite orbit with a trail, glowing / arrow / dashed lines, a wall, a corridor, an extruded ellipse. */
const CZML: CzmlPacket[] = [
  {
    id: 'sat',
    name: 'Satellite',
    availability: '2026-10-07T00:00:00Z/2026-10-08T00:00:00Z',
    position: { epoch: '2026-10-07T00:00:00Z', cartographicDegrees: [0, -87.63, 41.88, 400000, 1800, -60, 50, 400000, 3600, -30, 30, 400000, 5400, -87.63, 41.88, 400000], interpolationAlgorithm: 'LAGRANGE', interpolationDegree: 3 },
    point: { pixelSize: 10, color: { rgba: [255, 255, 0, 255] } },
    path: { width: 2, leadTime: 0, trailTime: 3600, material: { solidColor: { color: { rgba: [255, 255, 0, 160] } } } },
    label: { text: 'Satellite', font: '12px sans-serif', pixelOffset: { cartesian2: [0, -16] } },
  },
  { id: 'glow', polyline: { positions: { cartographicDegrees: [-87.64, 41.875, 150, -87.62, 41.875, 150] }, width: 12, material: { polylineGlow: { color: { rgba: [0, 255, 255, 255] }, glowPower: 0.25 } } } },
  { id: 'arrow', polyline: { positions: { cartographicDegrees: [-87.64, 41.873, 100, -87.62, 41.873, 100] }, width: 14, material: { polylineArrow: { color: { rgba: [255, 0, 255, 255] } } } } },
  { id: 'wall', wall: { positions: { cartographicDegrees: [-87.618, 41.886, 120, -87.616, 41.884, 120, -87.618, 41.882, 120] }, material: { solidColor: { color: { rgba: [255, 59, 48, 120] } } } } },
  { id: 'corridor', corridor: { positions: { cartographicDegrees: [-87.635, 41.878, 0, -87.632, 41.880, 0, -87.629, 41.879, 0] }, width: 30, material: { solidColor: { color: { rgba: [0, 122, 255, 140] } } } } },
  { id: 'extruded', position: { cartographicDegrees: [-87.6215, 41.8790, 0] }, ellipse: { semiMajorAxis: 60, semiMinorAxis: 40, extrudedHeight: 80, material: { solidColor: { color: { rgba: [175, 82, 222, 180] } } } } },
]

const GEOJSON = {
  type: 'FeatureCollection',
  features: [
    { type: 'Feature', properties: { name: 'GeoJSON point' }, geometry: { type: 'Point', coordinates: [-87.6235, 41.8865] } },
    { type: 'Feature', properties: { name: 'GeoJSON line' }, geometry: { type: 'LineString', coordinates: [[-87.6370, 41.8870], [-87.6340, 41.8890]] } },
  ],
}
const KML = `<?xml version="1.0" encoding="UTF-8"?><kml xmlns="http://www.opengis.net/kml/2.2"><Placemark><name>KML placemark</name><Point><coordinates>-87.6205,41.8830,0</coordinates></Point></Placemark></kml>`

type Check = { name: string; ok: boolean; detail: string }

export function CesiumScreen(props: { topInset: number; autoChecks?: boolean; onExit?: () => void }) {
  const ref = useRef<MunimMapViewRef | null>(null)
  const [log, setLog] = useState<string[]>([])
  const [checks, setChecks] = useState<Check[]>([])
  const [sceneMode, setSceneMode] = useState<'3d' | '2d' | 'columbus'>('3d')
  const [imagery, setImagery] = useState<NonNullable<CesiumMapOptions['imagery']>>('openStreetMap')
  const [look, setLook] = useState(false)
  const [widgets, setWidgets] = useState(false)
  const [data, setData] = useState(true)
  const [renderer, setRenderer] = useState<'auto' | 'native'>('auto')
  const [overlay, setOverlay] = useState(false)
  const [dark, setDark] = useState(false)
  const [panel, setPanel] = useState(true)
  const ready = useRef(false)
  const events = useRef<string[]>([])
  const errors = useRef<string[]>([])
  const ranAuto = useRef(false)

  const note = (line: string) => {
    console.log(`MUNIM_MAPS_CESIUM ${line}`)
    setLog((l) => [line, ...l].slice(0, 6))
  }

  const cesium: CesiumMapOptions = useMemo(
    () => ({
      sceneMode,
      imagery,
      modelRenderer: renderer,
      allowEvaluate: true,
      widgets: widgets ? { timeline: true, animation: true } : undefined,
      clock: { startTime: '2026-10-07T00:00:00Z', stopTime: '2026-10-08T00:00:00Z', currentTime: '2026-10-07T00:00:00Z', multiplier: 60, shouldAnimate: true },
      entities: data ? CZML : [],
      dataSources: data ? [{ id: 'geojson', type: 'geojson', data: GEOJSON, options: { markerColor: '#0A84FF', stroke: '#0A84FF', strokeWidth: 4 } }, { id: 'kml', type: 'kml', data: KML }] : [],
      tilesets: data ? [{ id: 'samples', url: 'https://raw.githubusercontent.com/CesiumGS/3d-tiles-samples/main/1.0/TilesetWithDiscreteLOD/tileset.json' }] : [],
      shadows: look,
      fog: look ? { enabled: true, density: 0.0006 } : undefined,
      globe: look ? { enableLighting: true, showGroundAtmosphere: true } : undefined,
      postProcess: look ? { fxaa: true, stages: [{ type: 'silhouette' }] } : undefined,
      clouds: look ? [{ latitude: 41.886, longitude: -87.63, height: 600, scale: { x: 900, y: 200 } }] : undefined,
    }),
    [sceneMode, imagery, renderer, widgets, data, look]
  )

  const runChecks = async () => {
    const map = ref.current
    if (!map) return
    const c = cesiumCommands(map)
    const out: Check[] = []
    const add = (name: string, ok: boolean, detail = '') => {
      out.push({ name, ok, detail })
      note(`check ${ok ? 'PASS' : 'FAIL'} ${name} ${detail}`)
      setChecks([...out])
    }
    const attempt = async (name: string, fn: () => Promise<[boolean, string]>) => {
      try {
        const [ok, detail] = await Promise.race([fn(), new Promise<[boolean, string]>((r) => setTimeout(() => r([false, 'timed out']), 15000))])
        add(name, ok, detail)
      } catch (e) {
        add(name, false, String(e))
      }
    }
    const wait = (ms: number) => new Promise((r) => setTimeout(r, ms))
    const near = (a: number, b: number, tol: number) => Math.abs(a - b) <= tol
    await attempt('mapReady', async () => [ready.current, ''])
    await attempt('version', async () => {
      const v = await c.version()
      return [v.cesium === '1.146.0', v.cesium]
    })
    await attempt('setCamera/getCamera', async () => {
      map.setCamera(CAMERA, false)
      await wait(600)
      const cam = await map.getCamera()
      return [near(cam.latitude, CAMERA.latitude, 1e-4) && near(cam.distance, CAMERA.distance, CAMERA.distance * 0.02) && near(cam.pitch, CAMERA.pitch, 1) && near(cam.heading, CAMERA.heading, 1), JSON.stringify(cam)]
    })
    await attempt('pointForCoordinate', async () => {
      const p = await map.pointForCoordinate(CAMERA)
      const view = await c.evaluate({ script: 'return { w: viewer.scene.canvas.clientWidth, h: viewer.scene.canvas.clientHeight }' }) as { w: number; h: number }
      return [near(p.x, view.w / 2, 3) && near(p.y, view.h / 2, 3), `${p.x.toFixed(1)},${p.y.toFixed(1)} of ${view.w}x${view.h}`]
    })
    await attempt('coordinateForPoint', async () => {
      const p = await map.pointForCoordinate(CAMERA)
      const coord = await map.coordinateForPoint(p)
      return [near(coord.latitude, CAMERA.latitude, 1e-4) && near(coord.longitude, CAMERA.longitude, 1e-4), JSON.stringify(coord)]
    })
    await attempt('getVisibleRegion', async () => {
      const r = await map.getVisibleRegion()
      return [Math.abs(r.latitude - CAMERA.latitude) < r.latitudeDelta && r.latitudeDelta > 0, JSON.stringify(r)]
    })
    await attempt('basemap tiles', async () => {
      const r = (await c.evaluate({ script: "const url = munim.tileUrl('https://tile.openstreetmap.org/2/1/1.png'); const res = await fetch(url); return { url, status: res.status, type: res.headers.get('content-type'), bytes: (await res.arrayBuffer()).byteLength, layers: viewer.imageryLayers.length, ready: viewer.imageryLayers.get(0) && viewer.imageryLayers.get(0).ready, tilesLoaded: viewer.scene.globe.tilesLoaded }" })) as { status: number; bytes: number }
      return [r.status === 200 && r.bytes > 100, JSON.stringify(r)]
    })
    await attempt('animateCamera', async () => {
      const target = { ...CAMERA, heading: 120, distance: 1500 }
      map.animateCamera(target, 500, 'easeInOut')
      const samples: string[] = []
      for (let i = 0; i < 6; i++) {
        await wait(250)
        const s = await map.getCamera()
        samples.push(`${s.latitude.toFixed(4)},${s.longitude.toFixed(4)} ${s.distance.toFixed(0)}m ${s.heading.toFixed(1)}`)
      }
      const cam = await map.getCamera()
      return [near(cam.heading, 120, 1.5) && near(cam.distance, 1500, 40), samples.join(' | ')]
    })
    await attempt('fitToCoordinates', async () => {
      const coords = [{ latitude: 41.87, longitude: -87.65 }, { latitude: 41.90, longitude: -87.61 }]
      map.fitToCoordinates(coords, { top: 40, left: 40, bottom: 40, right: 40 }, false)
      await wait(800)
      const r = await map.getVisibleRegion()
      const inside = coords.every((p) => Math.abs(p.latitude - r.latitude) <= r.latitudeDelta / 2 + 1e-3 && Math.abs(p.longitude - r.longitude) <= r.longitudeDelta / 2 + 1e-3)
      return [inside, JSON.stringify(r)]
    })
    map.setCamera(CAMERA, false)
    await wait(1500)
    await attempt('pick marker', async () => {
      const p = await map.pointForCoordinate(MARKERS[3]!.coordinate)
      const hit = await c.pick({ x: p.x, y: p.y })
      return [hit.kind === 'marker' && hit.id === 'dot', JSON.stringify({ kind: hit.kind, id: hit.id })]
    })
    await attempt('pick model', async () => {
      const p = await map.pointForCoordinate({ latitude: 41.8829, longitude: -87.6279 })
      const hits = await c.drillPick({ x: p.x, y: p.y - 6, limit: 5, width: 12, height: 12 })
      return [hits.some((h) => h.kind === 'model' && h.id === 'bus'), JSON.stringify(hits.map((h) => `${h.kind}:${h.id}`))]
    })
    await attempt('measureDistance', async () => {
      const r = await c.measureDistance({ points: [{ latitude: 0, longitude: 0 }, { latitude: 0, longitude: 1 }] })
      return [near(r.meters, 111319.5, 50), r.meters.toFixed(1)]
    })
    await attempt('measureArea', async () => {
      const r = await c.measureArea({ points: [{ latitude: 0, longitude: 0 }, { latitude: 0, longitude: 0.01 }, { latitude: 0.01, longitude: 0.01 }, { latitude: 0.01, longitude: 0 }] })
      return [near(r.squareMeters, 1113195 * 1.106, 1113195 * 0.02), r.squareMeters.toFixed(0)]
    })
    await attempt('sampleHeights', async () => {
      const h = await c.sampleHeights({ points: [{ latitude: 41.88, longitude: -87.63 }] })
      return [typeof h[0] === 'number', JSON.stringify(h)]
    })
    await attempt('addEntities/getEntity', async () => {
      await c.addEntities({ czml: { id: 'check-point', position: { cartographicDegrees: [-87.6, 41.9, 10] }, point: { pixelSize: 8 } } })
      const e = await c.getEntity({ id: 'check-point' })
      return [!!e && near(e.position!.latitude, 41.9, 1e-6), JSON.stringify(e?.position)]
    })
    await attempt('loadDataSource GeoJSON', async () => {
      const r = await c.loadDataSource({ id: 'check-geojson', type: 'geojson', data: GEOJSON })
      await c.removeDataSource({ id: 'check-geojson' })
      return [r.entities === 2, `${r.entities} entities`]
    })
    await attempt('clock', async () => {
      const clock = await c.setClock({ multiplier: 120 })
      return [clock.multiplier === 120, JSON.stringify(clock)]
    })
    await attempt('scene mode 2D and back', async () => {
      events.current = []
      await c.setSceneMode({ mode: '2d', duration: 0.5 })
      await wait(1500)
      const v = await c.getCameraView()
      await c.setSceneMode({ mode: '3d', duration: 0 })
      await wait(800)
      map.setCamera(CAMERA, false)
      return [v.sceneMode === '2d' && events.current.includes('morphComplete'), `${v.sceneMode} ${events.current.join(',')}`]
    })
    await attempt('imagery layer', async () => {
      const added = await c.addImageryLayer({ id: 'check-grid', type: 'grid' })
      const layers = await c.imageryLayers()
      const removed = await c.removeImageryLayer({ id: 'check-grid' })
      return [layers.some((l) => l.id === 'check-grid') && removed.removed, `index ${added.index}`]
    })
    await attempt('3D Tiles from a URL', async () => {
      for (let i = 0; i < 20; i++) {
        try {
          const info = await c.tilesetInfo({ id: 'samples' })
          return [info.radius > 0, `radius ${info.radius.toFixed(0)} m`]
        } catch {
          await wait(500)
        }
      }
      return [false, 'not loaded']
    })
    await attempt('takeSnapshot', async () => {
      const path = await map.takeSnapshot(320, 240)
      return [path.length > 0, path]
    })
    await attempt('screenshot', async () => {
      const s = await c.screenshot({ format: 'jpeg', quality: 0.6 })
      return [s.dataUrl.length > 1000, `${s.width}x${s.height}`]
    })
    await attempt('evaluate', async () => {
      const v = await c.evaluate({ script: 'return Cesium.VERSION' })
      return [v === '1.146.0', String(v)]
    })
    await attempt('modelInfo (animated Fox)', async () => {
      const info = await c.modelInfo({ id: 'fox' })
      return [info.animations.length > 0, JSON.stringify(info.animations.map((a) => a.name))]
    })
    await attempt('addressForCoordinate', async () => {
      const a = await map.addressForCoordinate(CAMERA)
      return [a.formatted.length > 0, a.formatted]
    })
    await attempt('measureAlignment (native 3D layer)', async () => {
      setRenderer('native')
      await wait(3000)
      const reports = []
      for (const cam of [CAMERA, { ...CAMERA, pitch: 0, heading: 0, distance: 600 }, { ...CAMERA, pitch: 65, heading: 200, distance: 2500 }]) {
        map.setCamera(cam, false)
        await wait(1200)
        reports.push(await map.measureAlignment())
      }
      setRenderer('auto')
      map.setCamera(CAMERA, false)
      const worst = Math.max(...reports.map((r) => r.maxErrorPoints))
      return [reports.every((r) => r.modelsMeasured > 0) && worst < 2, reports.map((r) => `${r.modelsMeasured}m max ${r.maxErrorPoints.toFixed(2)} pt`).join('; ')]
    })
    const passed = out.filter((x) => x.ok).length
    note(`checks ${passed}/${out.length}`)
    try {
      const file = new File(Paths.document, 'munim-maps-cesium-checks.json')
      if (file.exists) file.delete()
      file.create()
      file.write(JSON.stringify({ platform: Platform.OS, finishedAt: new Date().toISOString(), passed, total: out.length, checks: out, errors: errors.current.slice(-40) }, null, 2))
    } catch (e) {
      note(`could not write the report: ${String(e)}`)
    }
  }

  const button = (label: string, onPress: () => void, on = false) => (
    <Pressable key={label} onPress={onPress} style={[styles.chip, on && styles.chipOn]}>
      <Text style={[styles.chipText, on && styles.chipTextOn]}>{label}</Text>
    </Pressable>
  )

  const c = () => cesiumCommands(ref.current)
  const imageryList: NonNullable<CesiumMapOptions['imagery']>[] = ['openStreetMap', 'aerial', 'aerialWithLabels', 'muted', 'naturalEarth']

  return (
    <View style={StyleSheet.absoluteFill}>
      <MunimMapView
        ref={ref}
        provider="cesium"
        style={StyleSheet.absoluteFill}
        initialCamera={CAMERA}
        cesium={cesium}
        models={useMemo(() => models(renderer === 'native'), [renderer])}
        zones={ZONES}
        paths={PATHS}
        markers={MARKERS}
        clusterStyles={[{ clusteringId: 'shops', color: '#FF2D55' }]}
        polylines={POLYLINES}
        polygons={POLYGONS}
        circles={CIRCLES}
        tileOverlays={overlay ? TILES : []}
        colorScheme={dark ? 'dark' : 'light'}
        lighting="day"
        compassVisibility="visible"
        scaleVisibility="visible"
        pitchButtonVisibility="visible"
        showsUserTrackingButton
        mapPadding={{ top: panel ? 0 : 0 }}
        onMapReady={() => {
          ready.current = true
          note('map ready')
          if (props.autoChecks && !ranAuto.current) {
            ranAuto.current = true
            setTimeout(() => void runChecks(), 4000)
          }
        }}
        onPress={(e) => note(`press ${e.latitude.toFixed(5)}, ${e.longitude.toFixed(5)}`)}
        onLongPress={(e) => note(`long press ${e.latitude.toFixed(5)}, ${e.longitude.toFixed(5)}`)}
        onMarkerPress={(id) => note(`marker ${id}`)}
        onMarkerDeselect={(id) => note(`deselect ${id}`)}
        onCalloutPress={(id) => note(`callout ${id}`)}
        onCalloutAccessoryPress={(e) => note(`accessory ${e.id} ${e.side}`)}
        onClusterPress={(e) => {
          note(`cluster ${e.clusteringId} (${e.markerIds.split(',').length})`)
          ref.current?.fitToMarkers(e.markerIds, { top: 80, left: 80, bottom: 80, right: 80 }, true)
        }}
        onOverlayPress={(e) => note(`overlay ${e.kind} ${e.id}`)}
        onMarkerDragEnd={(e) => note(`dragged ${e.id} to ${e.latitude.toFixed(5)}`)}
        onModelPress={(id) => note(`model ${id}`)}
        onProviderEvent={(e) => {
          const event = parseCesiumEvent(e)
          events.current.push(event.name)
          if (event.name === 'pick' && event.data.kind !== 'none') note(`pick ${event.data.kind} ${event.data.id ?? event.data.name ?? ''}`)
          if (event.name === 'tilesetLoaded' || event.name === 'dataSourceLoaded') note(`${event.name} ${event.data.id}`)
        }}
        onError={(m) => {
          errors.current.push(m)
          note(`error ${m}`)
        }}
      />
      <View style={[styles.panel, { top: props.topInset + 8 }, !panel && styles.hidden]}>
        <ScrollView horizontal contentContainerStyle={styles.row} showsHorizontalScrollIndicator={false}>
          {props.onExit ? button('‹ Back', props.onExit) : null}
          {button('Checks', () => void runChecks())}
          {button(sceneMode.toUpperCase(), () => setSceneMode((m) => (m === '3d' ? '2d' : m === '2d' ? 'columbus' : '3d')))}
          {button(String(imagery), () => setImagery((i) => imageryList[(imageryList.indexOf(i as never) + 1) % imageryList.length]!))}
          {button('Look', () => setLook((v) => !v), look)}
          {button('Dark', () => setDark((v) => !v), dark)}
          {button('Data', () => setData((v) => !v), data)}
          {button('Timeline', () => setWidgets((v) => !v), widgets)}
          {button('Hillshade', () => setOverlay((v) => !v), overlay)}
          {button(`3D: ${renderer}`, () => setRenderer((r) => (r === 'auto' ? 'native' : 'auto')), renderer === 'native')}
          {button('Fly', () => void c().flyTo({ destination: { latitude: 48.8584, longitude: 2.2945, height: 1500 }, orientation: { heading: 0, pitch: -35 }, duration: 6 }))}
          {button('Home', () => ref.current?.setCamera(CAMERA, true))}
          {button('Orbit', () => void c().orbit({ degreesPerSecond: 12 }))}
          {button('Stop', () => void c().stopOrbit())}
          {button('Hide', () => setPanel(false))}
        </ScrollView>
        {checks.length ? (
          <Text style={styles.status}>
            Checks {checks.filter((x) => x.ok).length}/{checks.length}
            {checks.filter((x) => !x.ok).map((x) => `  ✗ ${x.name}: ${x.detail}`).join('')}
          </Text>
        ) : null}
        {log.map((line, i) => (
          <Text key={`${i}${line}`} style={styles.status} numberOfLines={1}>
            {line}
          </Text>
        ))}
      </View>
      {!panel ? <Pressable style={[styles.show, { top: props.topInset + 8 }]} onPress={() => setPanel(true)} /> : null}
    </View>
  )
}

const styles = StyleSheet.create({
  panel: { position: 'absolute', left: 12, right: 12, padding: 10, borderRadius: 14, backgroundColor: 'rgba(20,20,24,0.72)', gap: 4 },
  row: { flexDirection: 'row', gap: 8 },
  chip: { paddingHorizontal: 12, paddingVertical: 7, borderRadius: 999, backgroundColor: 'rgba(255,255,255,0.12)' },
  chipOn: { backgroundColor: '#FFFFFF' },
  chipText: { color: '#FFFFFF', fontSize: 13, fontWeight: '600' },
  chipTextOn: { color: '#111111' },
  status: { color: '#FFFFFF', fontSize: 11 },
  hidden: { display: 'none' },
  show: { position: 'absolute', left: 12, width: 44, height: 44 },
})
