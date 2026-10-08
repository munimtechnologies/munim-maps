import { useCallback, useEffect, useMemo, useRef, useState, type ComponentType } from 'react'
import { Pressable, StyleSheet, Text, View } from 'react-native'
import {
  MapModelLayer,
  type MapAlignmentReport,
  type MapModel,
  type MapModelLayerRef,
} from 'munim-maps'
import { CENTER, PATHS, ZONES, buildModels } from './Layer3D'

/**
 * `MapModelLayer` over another library's map on Android: `@rnmapbox/maps`
 * (`LayerOverRnMapbox.tsx`) or react-native-maps' Google map
 * (`LayerOverRnMaps.tsx`). The same vehicles, avatars, zones and paths as
 * the 3D layer screen, drawn by munim-maps over a map munim-maps does not
 * own, found by `mapTestID`.
 *
 * munimmapsexample://layer/<library>/check moves the host map's camera with
 * its own API to several poses (one with map padding) and through an
 * animation, and measures the layer against the host's own projection
 * (`measureAlignment`), logging `MUNIM_MAPS_LAYER_OVER {…}`.
 * munimmapsexample://layer/<library>/pan[45] shows only a probe: a magenta
 * circle drawn by the host map and a green box drawn by munim-maps at the
 * same coordinate, looking straight down (or pitched 45°), to compare them
 * on screenshots while the map is dragged.
 */

export type HostLibrary = 'rnmapbox' | 'rnmaps-google'

/** A camera in the host's own terms (its zoom level). */
export interface HostPose {
  latitude: number
  longitude: number
  zoom: number
  pitch: number
  heading: number
  /** Top map padding in points (the camera's centre moves down). */
  paddingTop?: number
}

export interface HostHandle {
  setCamera(pose: HostPose): void
  animateCamera(pose: HostPose, ms: number): void
}

export interface HostMapProps {
  testID: string
  initial: HostPose
  /** The coordinate of the host's magenta probe circle. */
  probe: { latitude: number; longitude: number }
  probeRadius: number
  /** Draw the host map in a TextureView where the library can (`@rnmapbox/maps`' `surfaceView={false}`). */
  textureView?: boolean
  onReady: () => void
  handle: (handle: HostHandle | null) => void
}

export const PROBE = { latitude: 41.8795, longitude: -87.624 }
const PROBE_RADIUS = 30

const PROBE_MODEL: MapModel = {
  id: 'probe',
  coordinate: PROBE,
  shape: 'box',
  size: { width: 16, height: 0.3, length: 16 },
  color: '#00B000',
  emissive: false,
  groundShadow: false,
}

const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms))

/** Mapbox zooms count 512-point tiles, Google's 256-point tiles: one level apart. */
function hostZoom(library: HostLibrary, mapboxZoom: number) {
  return library === 'rnmapbox' ? mapboxZoom : mapboxZoom + 1
}

/** Mapbox zoom levels; the last pose adds 160 points of top padding. */
const POSES: (Omit<HostPose, 'latitude' | 'longitude'> & { paddingTop?: number })[] = [
  { zoom: 16, pitch: 0, heading: 0 },
  { zoom: 16.5, pitch: 55, heading: 30 },
  { zoom: 17.5, pitch: 65, heading: 120 },
  { zoom: 15, pitch: 45, heading: 250 },
  { zoom: 18, pitch: 60, heading: 300 },
  { zoom: 13.5, pitch: 30, heading: 75 },
  { zoom: 16.5, pitch: 50, heading: 200, paddingTop: 160 },
]

export function LayerOverScreen(props: {
  library: HostLibrary
  Host: ComponentType<HostMapProps>
  autoCheck?: boolean
  /** Probe only, for screenshots while panning: 0 or 45 (pitch). */
  pan?: number
  /** With 160 points of top map padding (munimmapsexample://layer/<library>/pan45pad). */
  panPadding?: boolean
  /** The host map in a TextureView (munimmapsexample://layer/rnmapbox/…/tex). */
  hostTextureView?: boolean
  topInset: number
  onExit?: () => void
}) {
  const { library, Host } = props
  const layerRef = useRef<MapModelLayerRef | null>(null)
  const host = useRef<HostHandle | null>(null)
  const [start] = useState(() => Date.now() / 1000)
  const panning = props.pan != null
  const models = useMemo(
    () => (panning ? [PROBE_MODEL] : [...buildModels(start), PROBE_MODEL]),
    [start, panning]
  )
  const initial: HostPose = panning
    ? { ...PROBE, zoom: hostZoom(library, 17), pitch: props.pan ?? 0, heading: 0, paddingTop: props.panPadding ? 160 : 0 }
    : { ...CENTER, zoom: hostZoom(library, 16.5), pitch: 55, heading: 30 }
  const [attached, setAttached] = useState(false)
  const [ready, setReady] = useState(false)
  const [status, setStatus] = useState('')
  const [pressed, setPressed] = useState('')
  const [errors, setErrors] = useState<string[]>([])
  const ran = useRef(false)
  const setHost = useCallback((h: HostHandle | null) => {
    host.current = h
  }, [])

  const log = (kind: string, value: unknown) =>
    console.log(`MUNIM_MAPS_LAYER_OVER ${kind} ${JSON.stringify({ library, ...(value as object) })}`)

  async function measure(): Promise<MapAlignmentReport | null> {
    const layer = layerRef.current
    return layer ? layer.measureAlignment() : null
  }

  async function runChecks() {
    if (!host.current) return
    setStatus('Checking…')
    const poses: MapAlignmentReport[] = []
    for (const pose of POSES) {
      host.current?.setCamera({ ...CENTER, paddingTop: 0, ...pose, zoom: hostZoom(library, pose.zoom) })
      await wait(2500)
      const report = await measure()
      if (report) poses.push(report)
      log('pose', { pose, report })
    }
    // An animation the host runs itself: the layer follows its camera every frame.
    host.current?.setCamera({ ...CENTER, zoom: hostZoom(library, 15.5), pitch: 30, heading: 0, paddingTop: 0 })
    await wait(1500)
    host.current?.animateCamera(
      { latitude: 41.8806, longitude: -87.6315, zoom: hostZoom(library, 17.5), pitch: 60, heading: 140, paddingTop: 0 },
      4000
    )
    const moving: MapAlignmentReport[] = []
    for (let i = 0; i < 14; i += 1) {
      await wait(250)
      const report = await measure()
      if (report) moving.push(report)
    }
    log('animation', { samples: moving.map((r) => ({ max: r.maxErrorPoints, n: r.modelsMeasured, d: r.cameraDistance })) })
    await wait(1500)
    const measured = [...poses, ...moving].filter((r) => r.modelsMeasured > 0)
    const summary = {
      attached: layerRef.current?.isAttached() ?? false,
      poses: poses.length,
      posesMeasured: poses.filter((r) => r.modelsMeasured > 0).length,
      animationSamples: moving.filter((r) => r.modelsMeasured > 0).length,
      maxErrorPoints: Math.max(0, ...measured.map((r) => r.maxErrorPoints)),
      meanErrorPoints: measured.reduce((sum, r) => sum + r.meanErrorPoints, 0) / Math.max(1, measured.length),
      animationMaxErrorPoints: Math.max(0, ...moving.filter((r) => r.modelsMeasured > 0).map((r) => r.maxErrorPoints)),
      paddedPoseMaxErrorPoints: poses[poses.length - 1]?.maxErrorPoints ?? -1,
      fieldOfViewDegrees: poses.map((r) => Number(r.fieldOfViewDegrees.toFixed(2))),
      errors,
    }
    log('summary', summary)
    setStatus(
      `max ${summary.maxErrorPoints.toFixed(2)} pt, mean ${summary.meanErrorPoints.toFixed(2)} pt over ${measured.length} cameras · animating max ${summary.animationMaxErrorPoints.toFixed(2)} pt`
    )
    host.current?.setCamera(initial)
  }

  useEffect(() => {
    if (!ready || !attached || !props.autoCheck || ran.current) return
    ran.current = true
    // Let tiles and models load first.
    setTimeout(() => void runChecks(), 4000)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ready, attached, props.autoCheck])

  // While panning by hand (or adb), report how far apart the layer and the host draw the probe.
  useEffect(() => {
    if (!panning || !attached) return
    const timer = setInterval(() => {
      void measure().then((report) => report && log('probe', { report }))
    }, 1000)
    return () => clearInterval(timer)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [panning, attached])

  const name = library === 'rnmapbox' ? '@rnmapbox/maps' : 'react-native-maps (Google)'
  return (
    <View style={StyleSheet.absoluteFill}>
      <Host
        testID="host-map"
        initial={initial}
        probe={PROBE}
        probeRadius={PROBE_RADIUS}
        textureView={props.hostTextureView}
        onReady={() => {
          setReady(true)
          log('ready', {})
        }}
        handle={setHost}
      />
      <MapModelLayer
        ref={layerRef}
        mapTestID="host-map"
        models={models}
        zones={panning ? [] : ZONES}
        paths={panning ? [] : PATHS}
        lighting="day"
        onAttachChange={(value) => {
          setAttached(value)
          log('attached', { attached: value })
        }}
        onModelPress={(id) => {
          setPressed(id)
          log('pressed', { id })
        }}
        onError={(message) => {
          log('error', { message })
          setErrors((list) => (list.includes(message) ? list : [...list, message].slice(-4)))
        }}
      />
      {panning ? null : (
        <View style={[styles.panel, { top: props.topInset + 8 }]}>
          <View style={styles.row}>
            {props.onExit ? (
              <Pressable style={styles.chip} onPress={props.onExit}>
                <Text style={styles.chipText}>‹ Engines</Text>
              </Pressable>
            ) : null}
            <Pressable style={styles.chip} onPress={() => void runChecks()}>
              <Text style={styles.chipText}>Run checks</Text>
            </Pressable>
          </View>
          <Text style={styles.status}>
            MapModelLayer over {name} · {attached ? 'attached' : 'looking for the map…'}
            {status ? ` · ${status}` : ''}
          </Text>
          {pressed ? <Text style={styles.status}>Tapped: {pressed}</Text> : null}
          {errors.map((e) => (
            <Text key={e} style={styles.error} numberOfLines={2}>
              {e}
            </Text>
          ))}
        </View>
      )}
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
  chipText: { color: '#FFFFFF', fontSize: 13, fontWeight: '600' },
  status: { color: '#FFFFFF', fontSize: 12 },
  error: { color: '#FFB4A9', fontSize: 11 },
})
