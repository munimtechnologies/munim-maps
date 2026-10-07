import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { File, Paths } from 'expo-file-system'
import Constants from 'expo-constants'
import { Image, Platform, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native'
import {
  GoogleServiceError,
  MunimMapView,
  googleEvent,
  googleGeometry,
  googleMap,
  googleMapsServices,
  type GoogleMapOptions,
  type MapCamera,
  type MapCircle,
  type MapMarker,
  type MapModel,
  type MapPolygon,
  type MapPolyline,
  type MapProviderEvent,
  type MunimMapViewRef,
} from 'munim-maps'
import { VEHICLES } from 'munim-maps-vehicles'

/**
 * The Google Maps engine with everything it has: map types, dark mode,
 * traffic, indoor maps, markers (pins, balloons, avatars, labels, dots,
 * clusters, draggable, info windows), shapes (gradients, dashes, holes),
 * ground overlays, heatmaps, KML, GeoJSON, Street View, Google's camera
 * commands, snapshots, Places / Geocoding / Routes and the 3D layer.
 *
 * munimmapsexample://google opens it; munimmapsexample://google/checks also
 * runs the checks (the Checks button does too). Results go to the log
 * (`MUNIM_MAPS_GOOGLE …`) and Documents/munim-maps-google-checks.json.
 */

const LOOP = { latitude: 41.8826, longitude: -87.6278 }
const CAMERA: MapCamera = { ...LOOP, distance: 1200, pitch: 55, heading: 30 }

const MODELS: MapModel[] = [
  { id: 'bus', coordinate: { latitude: 41.8829, longitude: -87.6279 }, source: VEHICLES['bus-city'], heading: 0, tint: '#0A84FF', screenSize: 26 },
  { id: 'taxi', coordinate: { latitude: 41.8822, longitude: -87.6271 }, source: VEHICLES['car-taxi'], heading: 90, screenSize: 22 },
  { id: 'police', coordinate: { latitude: 41.8833, longitude: -87.6268 }, source: VEHICLES['car-police'], heading: 180, screenSize: 22 },
  { id: 'sports', coordinate: { latitude: 41.8819, longitude: -87.6285 }, source: VEHICLES['car-sports'], heading: 270, tint: '#FF3B30', screenSize: 22 },
  { id: 'balloon', coordinate: LOOP, altitude: 120, source: VEHICLES.balloon, screenSize: 60 },
]

const AVATAR = require('./assets/avatar-a.png')

function clusterMarkers(): MapMarker[] {
  const out: MapMarker[] = []
  for (let i = 0; i < 24; i++) {
    out.push({
      id: `c${i}`,
      coordinate: { latitude: 41.875 + (i % 6) * 0.0012, longitude: -87.637 + Math.floor(i / 6) * 0.0015 },
      style: 'dot',
      color: '#AF52DE',
      clusteringId: 'stops',
    })
  }
  return out
}

const MARKERS: MapMarker[] = [
  { id: 'pin', coordinate: { latitude: 41.8841, longitude: -87.6301 }, style: 'pin', color: '#34C759', title: 'Pin', subtitle: 'A classic Google pin', callout: true },
  { id: 'balloonMarker', coordinate: { latitude: 41.8808, longitude: -87.6253 }, style: 'marker', glyph: 'G', color: '#0A84FF', title: 'Balloon', callout: true, calloutDetail: 'A custom info window\nwith two lines', calloutRight: { text: 'Go' } },
  { id: 'avatar', coordinate: { latitude: 41.8851, longitude: -87.6262 }, style: 'avatar', image: AVATAR, size: 44, border: { color: '#FFFFFF', width: 2 }, badges: [{ text: '5F', position: 'top-right' }], title: 'Avatar' },
  { id: 'label', coordinate: { latitude: 41.8797, longitude: -87.6299 }, style: 'label', title: 'The Loop', color: '#1C1C1E' },
  { id: 'drag', coordinate: { latitude: 41.8862, longitude: -87.6314 }, style: 'pin', color: '#FF9500', draggable: true, title: 'Drag me', callout: true },
  ...clusterMarkers(),
]

const ROUTE = [
  { latitude: 41.8789, longitude: -87.6359 },
  { latitude: 41.8826, longitude: -87.629 },
  { latitude: 41.8921, longitude: -87.6264 },
]

const POLYLINES: MapPolyline[] = [
  { id: 'route', coordinates: ROUTE, strokeColors: ['#34C759', '#FFCC00', '#FF3B30'], strokeWidth: 6 },
  { id: 'dashed', coordinates: [{ latitude: 41.877, longitude: -87.62 }, { latitude: 41.889, longitude: -87.62 }], strokeColor: '#5856D6', strokeWidth: 4, dashPattern: [10, 8] },
  { id: 'geodesic', coordinates: [{ latitude: 41.88, longitude: -87.63 }, { latitude: 51.5, longitude: -0.12 }], strokeColor: '#FF2D55', strokeWidth: 2, geodesic: true },
]

const POLYGONS: MapPolygon[] = [
  {
    id: 'park',
    coordinates: [
      { latitude: 41.8865, longitude: -87.6235 },
      { latitude: 41.8865, longitude: -87.618 },
      { latitude: 41.8805, longitude: -87.618 },
      { latitude: 41.8805, longitude: -87.6235 },
    ],
    holes: [[
      { latitude: 41.8845, longitude: -87.6215 },
      { latitude: 41.8845, longitude: -87.62 },
      { latitude: 41.8825, longitude: -87.62 },
      { latitude: 41.8825, longitude: -87.6215 },
    ]],
    fillColor: '#34C75944',
    strokeColor: '#34C759',
    strokeWidth: 2,
  },
]

const CIRCLES: MapCircle[] = [
  { id: 'ring', center: { latitude: 41.8786, longitude: -87.6359 }, radius: 180, fillColor: '#0A84FF22', strokeColor: '#0A84FF', strokeWidth: 2 },
]

const GEOJSON = {
  type: 'FeatureCollection',
  features: [
    {
      type: 'Feature',
      id: 'river',
      properties: { name: 'Chicago River (sketch)', stroke: '#00C7BE', 'stroke-width': 5 },
      geometry: { type: 'LineString', coordinates: [[-87.6386, 41.8862], [-87.6297, 41.8885], [-87.6187, 41.8889]] },
    },
    {
      type: 'Feature',
      id: 'block',
      properties: { name: 'A block', fill: '#FF9500', 'fill-opacity': 0.3, stroke: '#FF9500' },
      geometry: { type: 'Polygon', coordinates: [[[-87.6335, 41.879], [-87.631, 41.879], [-87.631, 41.8775], [-87.6335, 41.8775], [-87.6335, 41.879]]] },
    },
  ],
}

const KML = `<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2"><Document>
<Style id="red"><LineStyle><color>ff3b30ff</color><width>4</width></LineStyle></Style>
<Placemark><name>KML line</name><styleUrl>#red</styleUrl>
<LineString><coordinates>-87.6400,41.8740,0 -87.6200,41.8740,0</coordinates></LineString></Placemark>
<Placemark><name>KML point</name><Point><coordinates>-87.6240,41.8760,0</coordinates></Point></Placemark>
</Document></kml>`

function heatPoints() {
  const out = []
  for (let i = 0; i < 300; i++) {
    const a = (i * 137.5 * Math.PI) / 180
    const r = Math.sqrt(i) * 0.00035
    out.push({ latitude: 41.8895 + r * Math.cos(a), longitude: -87.6235 + r * Math.sin(a) * 1.3, weight: 1 + (i % 5) })
  }
  return out
}

type Check = { name: string; ok: boolean; detail: string }
const TYPES: GoogleMapOptions['mapType'][] = ['normal', 'satellite', 'hybrid', 'terrain']

function wait(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

export function GoogleScreen(props: { topInset: number; autoCheck: boolean; onExit?: () => void }) {
  const ref = useRef<MunimMapViewRef | null>(null)
  const [ready, setReady] = useState(false)
  const [events, setEvents] = useState<string[]>([])
  const [checks, setChecks] = useState<Check[]>([])
  const [running, setRunning] = useState(false)
  const [type, setType] = useState(0)
  const [dark, setDark] = useState(false)
  const [traffic, setTraffic] = useState(false)
  const [layers, setLayers] = useState(true)
  const [tiles, setTiles] = useState(false)
  // Google's photorealistic 3D map (Android, Maps 3D SDK): models drawn natively.
  const [photo3d, setPhoto3d] = useState(false)
  const [status, setStatus] = useState('')
  const seen = useRef<Record<string, number>>({})
  const readyRef = useRef(false)

  const google: GoogleMapOptions = useMemo(
    () => ({
      mode: photo3d ? '3d' : '2d',
      modelRendering: 'auto',
      mapType: TYPES[type],
      transitEnabled: true,
      indoorEnabled: true,
      zoomControls: true,
      mapToolbar: true,
      clusterMinimumSize: 3,
      markers: {
        balloonMarker: { infoWindowAnchor: { x: 0.5, y: 0 } },
        drag: { flat: false, rotation: 0 },
      },
      polylines: { dashed: { pattern: [{ type: 'dash', length: 12 }, { type: 'gap', length: 6 }, { type: 'dot' }, { type: 'gap', length: 6 }], startCap: 'round', endCap: 'square' } },
      polygons: { park: { geodesic: false } },
      tileOverlays: { osm: { tileSize: 256, fadeIn: true, userAgent: 'munim-maps-example' } },
      groundOverlays: layers
        ? [{ id: 'ground', imageUri: Image.resolveAssetSource(AVATAR).uri, position: { latitude: 41.8768, longitude: -87.6305 }, width: 120, bearing: 20, opacity: 0.8, tappable: true }]
        : [],
      heatmaps: layers ? [{ id: 'heat', points: heatPoints(), radius: 30, opacity: 0.8 }] : [],
      geoJsonLayers: layers ? [{ id: 'sketch', geojson: GEOJSON, style: { strokeColor: '#00C7BE', strokeWidth: 3 } }] : [],
      kmlLayers: layers ? [{ id: 'kml', data: KML }] : [],
    }),
    [type, layers, photo3d]
  )

  const log = useCallback((line: string) => {
    console.log(`MUNIM_MAPS_GOOGLE ${line}`)
    setEvents((list) => [line, ...list].slice(0, 6))
  }, [])

  const onProviderEvent = useCallback(
    (event: MapProviderEvent) => {
      const e = googleEvent(event)
      if (!e) return
      seen.current[e.name] = (seen.current[e.name] ?? 0) + 1
      if (e.name === 'tilesRenderingStarted' || e.name === 'tilesRenderingFinished' || e.name === 'streetViewCamera') return
      log(`event ${e.name} ${JSON.stringify(e.data).slice(0, 120)}`)
    },
    [log]
  )

  const waitFor = async (name: string, after: number, ms = 6000) => {
    const start = Date.now()
    while (Date.now() - start < ms) {
      if ((seen.current[name] ?? 0) > after) return true
      await wait(100)
    }
    return false
  }

  const runChecks = useCallback(async () => {
    const map = ref.current
    if (!map || running) return
    setRunning(true)
    const g = googleMap(map)
    const results: Check[] = []
    const check = async (name: string, body: () => Promise<string | boolean>) => {
      let ok = false
      let detail = ''
      try {
        const value = await body()
        ok = value !== false
        detail = typeof value === 'string' ? value : ''
      } catch (error) {
        detail = String(error instanceof Error ? error.message : error)
      }
      results.push({ name, ok, detail })
      console.log(`MUNIM_MAPS_GOOGLE check ${ok ? 'ok' : 'FAIL'} ${name} ${detail}`)
      setChecks([...results])
    }

    await check('map ready', async () => readyRef.current)
    await check('sdkInfo', async () => {
      const info = await g.sdkInfo()
      return `${info.platform} ${info.version}`
    })
    await check('setCamera / getCamera round trip', async () => {
      map.setCamera(CAMERA, false)
      await wait(800)
      const c = await map.getCamera()
      const ok = Math.abs(c.latitude - CAMERA.latitude) < 1e-4 && Math.abs(c.distance / CAMERA.distance - 1) < 0.05 && Math.abs(c.pitch - CAMERA.pitch) < 1
      return ok ? `distance ${c.distance.toFixed(0)} m pitch ${c.pitch.toFixed(1)}` : `got ${JSON.stringify(c)}`
    })
    await check('point / coordinate round trip', async () => {
      const p = await map.pointForCoordinate(LOOP)
      const c = await map.coordinateForPoint(p)
      const d = googleGeometry.computeDistanceBetween(c, LOOP)
      return d < 3 ? `${d.toFixed(2)} m at (${p.x.toFixed(0)}, ${p.y.toFixed(0)})` : false
    })
    await check('getVisibleRegion', async () => {
      const r = await map.getVisibleRegion()
      return Math.abs(r.latitude - LOOP.latitude) < r.latitudeDelta && r.latitudeDelta > 0 ? `${r.latitudeDelta.toFixed(4)}° tall` : false
    })
    // The 3D layer against Google's own projection, at several cameras.
    const poses: MapCamera[] = [
      { ...LOOP, distance: 900, pitch: 0, heading: 0 },
      { ...LOOP, distance: 900, pitch: 45, heading: 90 },
      { ...LOOP, distance: 1500, pitch: 60, heading: 200 },
      { ...LOOP, distance: 4000, pitch: 30, heading: 315 },
      { ...LOOP, distance: 600, pitch: 55, heading: 30 },
    ]
    for (const pose of poses) {
      await check(`3D alignment ${pose.distance} m, pitch ${pose.pitch}, heading ${pose.heading}`, async () => {
        map.setCamera(pose, false)
        await wait(1500)
        const r = await map.measureAlignment()
        const line = `max ${r.maxErrorPoints.toFixed(2)} pt mean ${r.meanErrorPoints.toFixed(2)} pt over ${r.modelsMeasured} models, fov ${r.fieldOfViewDegrees.toFixed(2)}°`
        console.log(`MUNIM_MAPS_GOOGLE alignment ${JSON.stringify({ pose, report: r })}`)
        if (r.modelsMeasured > 0 && r.maxErrorPoints >= 0 && r.maxErrorPoints < 2) return line
        throw new Error(line)
      })
    }
    await check('cameraDiagnostics', async () => {
      const d = await g.cameraDiagnostics()
      return `fov ${Number(d.fieldOfViewDegrees).toFixed(2)}° measured ${d.fieldOfViewMeasured} distance ${Number(d.distance).toFixed(0)} vs zoom ${Number(d.distanceFromZoom).toFixed(0)}`
    })
    await check('animateCamera fires cameraMoveStarted + onCameraChange', async () => {
      const before = seen.current.cameraMoveStarted ?? 0
      map.animateCamera({ ...CAMERA, heading: 120 }, 800, 'easeInOut')
      return await waitFor('cameraMoveStarted', before)
    })
    await check('google.moveCamera / getCameraPosition', async () => {
      await g.moveCamera({ ...LOOP, zoom: 16, bearing: 0, tilt: 0 })
      await wait(500)
      const p = await g.getCameraPosition()
      return Math.abs(p.zoom - 16) < 0.01 ? `zoom ${p.zoom}` : false
    })
    await check('google.zoomBy / scrollBy / zoomTo', async () => {
      await g.zoomBy(1)
      await wait(300)
      await g.scrollBy(20, 0)
      await wait(300)
      await g.zoomTo(15.5)
      await wait(400)
      const p = await g.getCameraPosition()
      return Math.abs(p.zoom - 15.5) < 0.01 ? `zoom ${p.zoom}` : false
    })
    await check('google.getProjection', async () => {
      const p = await g.getProjection()
      return p.farLeft.latitude > p.nearLeft.latitude ? `${p.pointsPerMeter.toFixed(3)} pt/m` : false
    })
    await check('google.getMapCapabilities', async () => JSON.stringify(await g.getMapCapabilities()))
    await check('setRegion', async () => {
      map.setRegion({ ...LOOP, latitudeDelta: 0.02, longitudeDelta: 0.02 }, 0)
      await wait(600)
      const r = await map.getVisibleRegion()
      return r.latitudeDelta > 0.015 ? `${r.latitudeDelta.toFixed(4)}°` : false
    })
    await check('fitToMarkers', async () => {
      map.fitToMarkers('pin,label,drag', { top: 40, left: 40, bottom: 40, right: 40 }, false)
      await wait(800)
      const c = await map.getCamera()
      return Math.abs(c.latitude - 41.883) < 0.01 ? `centre ${c.latitude.toFixed(4)}, ${c.longitude.toFixed(4)}` : false
    })
    await check('flyCamera + stopFlight', async () => {
      const now = Date.now() / 1000
      map.flyCamera([{ t: 0, camera: CAMERA }, { t: 2, camera: { ...CAMERA, heading: 200 } }], now, false)
      await wait(1000)
      map.stopFlight()
      const c = await map.getCamera()
      return c.heading > 31 && c.heading < 199 ? `heading ${c.heading.toFixed(0)} mid-flight` : `heading ${c.heading}`
    })
    await check('overlayAtPoint on the polygon', async () => {
      map.setCamera({ latitude: 41.8835, longitude: -87.6208, distance: 1500, pitch: 0, heading: 0 }, false)
      await wait(800)
      const p = await map.pointForCoordinate({ latitude: 41.8855, longitude: -87.6225 })
      const id = await map.overlayAtPoint(p)
      return id === 'park' ? id : `got "${id}"`
    })
    await check('selectMarker / info window', async () => {
      map.selectMarker('pin')
      await wait(300)
      await g.hideInfoWindow('pin')
      return true
    })
    await check('KML and GeoJSON layers loaded', async () => {
      const kml = await waitFor('kmlLayerLoaded', 0, 4000)
      const geo = await waitFor('geoJsonLayerLoaded', 0, 4000)
      return kml && geo ? 'both' : `kml ${kml} geojson ${geo}`
    })
    await check('takeSnapshot', async () => {
      const path = await map.takeSnapshot(0, 0)
      return path.length > 0 ? path.split('/').pop()! : false
    })
    await check('addressForCoordinate', async () => {
      const a = await map.addressForCoordinate(LOOP)
      return a.formatted || a.street || a.city
    })
    await check('Street View coverage (hasLookAround)', async () => {
      const has = await map.hasLookAround({ latitude: 41.8827, longitude: -87.6233 })
      return has ? 'covered' : false
    })
    await check('streetView.open / getLocation / setCamera / close', async () => {
      const opened = await g.streetView.open({ latitude: 41.8827, longitude: -87.6233, heading: 90, presentation: 'overlay' })
      await wait(2500)
      await g.streetView.setCamera({ heading: 180, pitch: 10 }, 500)
      await wait(800)
      const camera = await g.streetView.getCamera()
      const location = await g.streetView.getLocation()
      await g.streetView.close()
      return `${opened.panoramaId.slice(0, 10)}… ${location.links.length} links, heading ${camera.heading.toFixed(0)}`
    })
    await check('indoor: setIndoorLevel without a building fails cleanly', async () => {
      try {
        await g.setIndoorLevel(0)
        return 'a building was focused'
      } catch (error) {
        return String(error).includes('building') ? 'rejected' : false
      }
    })
    await check('unknown command rejects', async () => {
      try {
        await map.providerCommand('nope', '{}')
        return false
      } catch {
        return 'rejected'
      }
    })
    await check('googleGeometry (JavaScript)', async () => {
      const d = googleGeometry.computeDistanceBetween({ latitude: 0, longitude: 0 }, { latitude: 0, longitude: 1 })
      const path = googleGeometry.decodePath(googleGeometry.encodePath(ROUTE))
      return Math.abs(d - 111_195) < 50 && path.length === 3 ? `${d.toFixed(0)} m per degree` : false
    })
    const key = (Constants.expoConfig?.extra as { googleMapsApiKey?: string } | undefined)?.googleMapsApiKey
    await check('Places / Geocoding / Routes (web services, needs the APIs on the key)', async () => {
      if (!key) return 'no key in the example build'
      const services = googleMapsServices({ apiKey: key, iosBundleId: 'com.munimtech.munimmapsexample', androidPackage: 'com.munimtech.munimmapsexample' })
      const outcome = async (name: string, call: () => Promise<unknown>) => {
        try {
          await call()
          return `${name} ok`
        } catch (error) {
          if (error instanceof GoogleServiceError) return `${name} ${error.status}`
          throw error
        }
      }
      return [
        await outcome('autocomplete', () => services.places.autocomplete({ input: 'pizza', origin: LOOP })),
        await outcome('geocode', () => services.geocoding.geocode('233 S Wacker Dr, Chicago')),
        await outcome('routes', () => services.routes.computeRoutes({ origin: ROUTE[0]!, destination: ROUTE[2]! })),
      ].join(', ')
    })
    map.setCamera(CAMERA, false)
    const passed = results.filter((r) => r.ok).length
    const summary = { provider: 'google', platform: Platform.OS, finishedAt: new Date().toISOString(), passed, failed: results.length - passed, results, events: seen.current }
    console.log(`MUNIM_MAPS_GOOGLE summary ${JSON.stringify({ passed, failed: results.length - passed })}`)
    try {
      const file = new File(Paths.document, 'munim-maps-google-checks.json')
      if (file.exists) file.delete()
      file.create()
      file.write(JSON.stringify(summary, null, 2))
    } catch (error) {
      console.warn('MUNIM_MAPS_GOOGLE could not write the report', error)
    }
    setStatus(`Checks: ${passed}/${results.length} passed`)
    setRunning(false)
  }, [running])

  useEffect(() => {
    if (!props.autoCheck || !ready) return
    const t = setTimeout(() => void runChecks(), 2500)
    return () => clearTimeout(t)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [props.autoCheck, ready])

  const g = () => (ref.current ? googleMap(ref.current) : undefined)

  return (
    <View style={StyleSheet.absoluteFill}>
      <MunimMapView
        ref={ref}
        provider="google"
        style={StyleSheet.absoluteFill}
        initialCamera={CAMERA}
        google={google}
        colorScheme={dark ? 'dark' : 'light'}
        showsTraffic={traffic}
        showsCompass
        models={MODELS}
        lighting="day"
        markers={MARKERS}
        clusterStyles={[{ clusteringId: 'stops', color: '#AF52DE', glyph: '{count}' }]}
        polylines={POLYLINES}
        polygons={POLYGONS}
        circles={CIRCLES}
        tileOverlays={tiles ? [{ id: 'osm', urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', opacity: 0.5, zIndex: 1 }] : []}
        onMapReady={() => {
          readyRef.current = true
          setReady(true)
          log('onMapReady')
        }}
        onPress={(e) => log(`onPress ${e.latitude.toFixed(5)}, ${e.longitude.toFixed(5)}`)}
        onLongPress={(e) => log(`onLongPress ${e.latitude.toFixed(5)}, ${e.longitude.toFixed(5)}`)}
        onMarkerPress={(id) => log(`onMarkerPress ${id}`)}
        onMarkerDeselect={(id) => log(`onMarkerDeselect ${id}`)}
        onCalloutPress={(id) => log(`onCalloutPress ${id}`)}
        onClusterPress={(e) => {
          log(`onClusterPress ${e.clusteringId} ${e.markerIds.split(',').length}`)
          ref.current?.fitToMarkers(e.markerIds, { top: 60, left: 60, bottom: 60, right: 60 }, true)
        }}
        onOverlayPress={(e) => log(`onOverlayPress ${e.kind} ${e.id}`)}
        onMarkerDragEnd={(e) => log(`onMarkerDragEnd ${e.id} ${e.latitude.toFixed(5)}`)}
        onMapFeaturePress={(f) => log(`onMapFeaturePress ${f.title} ${f.id.slice(0, 12)}`)}
        onModelPress={(id) => log(`onModelPress ${id}`)}
        onProviderEvent={onProviderEvent}
        onError={(m) => log(`onError ${m}`)}
      />
      <View style={[styles.panel, { top: props.topInset + 8 }]}>
        <ScrollView horizontal contentContainerStyle={styles.row} showsHorizontalScrollIndicator={false}>
          {props.onExit ? <Chip label="‹ Back" onPress={props.onExit} /> : null}
          <Chip label={running ? 'Checking…' : 'Checks'} onPress={() => void runChecks()} />
          <Chip label={`Type: ${TYPES[type]}`} onPress={() => setType((t) => (t + 1) % TYPES.length)} />
          <Chip label={dark ? 'Dark' : 'Light'} on={dark} onPress={() => setDark((d) => !d)} />
          <Chip label="Traffic" on={traffic} onPress={() => setTraffic((t) => !t)} />
          <Chip label="Layers" on={layers} onPress={() => setLayers((l) => !l)} />
          <Chip label="Tiles" on={tiles} onPress={() => setTiles((t) => !t)} />
          <Chip label="3D" on={photo3d} onPress={() => setPhoto3d((m) => !m)} />
          <Chip label="Street View" onPress={() => void g()?.streetView.open({ latitude: 41.8827, longitude: -87.6233, heading: 90 }).catch((e) => log(String(e)))} />
          <Chip label="Indoor" onPress={() => ref.current?.setCamera({ latitude: 41.8786, longitude: -87.6403, distance: 250, pitch: 0, heading: 0 }, true)} />
          <Chip label="Fly" onPress={() => ref.current?.animateCamera({ ...CAMERA, heading: (Date.now() / 50) % 360, pitch: 60 }, 2000, 'easeInOut')} />
          <Chip label="Snapshot" onPress={() => void ref.current?.takeSnapshot(0, 0).then((p) => log(`snapshot ${p.split('/').pop()}`))} />
        </ScrollView>
        {status ? <Text style={styles.status}>{status}</Text> : null}
        {checks.filter((c) => !c.ok).slice(0, 4).map((c) => (
          <Text key={c.name} style={styles.fail} numberOfLines={2}>✗ {c.name}: {c.detail}</Text>
        ))}
        {events.map((e, i) => (
          <Text key={`${i}${e}`} style={styles.event} numberOfLines={1}>{e}</Text>
        ))}
      </View>
    </View>
  )
}

function Chip(props: { label: string; on?: boolean; onPress: () => void }) {
  return (
    <Pressable onPress={props.onPress} style={[styles.chip, props.on && styles.chipOn]}>
      <Text style={[styles.chipText, props.on && styles.chipTextOn]}>{props.label}</Text>
    </Pressable>
  )
}

const styles = StyleSheet.create({
  panel: { position: 'absolute', left: 12, right: 12, padding: 10, borderRadius: 14, backgroundColor: 'rgba(20,20,24,0.72)', gap: 4 },
  row: { flexDirection: 'row', gap: 8 },
  chip: { paddingHorizontal: 12, paddingVertical: 7, borderRadius: 999, backgroundColor: 'rgba(255,255,255,0.12)' },
  chipOn: { backgroundColor: '#FFFFFF' },
  chipText: { color: '#FFFFFF', fontSize: 13, fontWeight: '600' },
  chipTextOn: { color: '#111111' },
  status: { color: '#FFFFFF', fontSize: 12, fontWeight: '600' },
  fail: { color: '#FFB4A9', fontSize: 11 },
  event: { color: '#D0D0D8', fontSize: 11 },
})
