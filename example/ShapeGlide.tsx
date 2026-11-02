import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Platform, Pressable, StyleSheet, Text, View } from 'react-native'
import { File, Paths } from 'expo-file-system'
import {
  MunimMapView,
  installedProviders,
  type MapCircle,
  type MapCoordinate,
  type MapPolygon,
  type MapProvider,
  type MunimMapViewRef,
} from 'munim-maps'

/**
 * Circles and polygons that glide (`animationDuration`), the way Manhunt
 * moves and shrinks its game zones: the props change once a second and the
 * shapes move smoothly in between. The magenta circle jumps (no
 * animationDuration), for comparison. Every fourth second the zone only
 * changes colour, which restyles it in place.
 *
 * munimmapsexample://glide/<provider or maplibreweb>[/jump] (/jump: start with animationDuration 0)
 * munimmapsexample://glide/<provider>/check: holds the shapes still, checks
 * that taps find the circle, the polygon and not its hole, moves the zone
 * and checks it is found where it glided to; writes
 * Documents/munim-maps-glide-check-<provider>.json and a MUNIM_MAPS_GLIDE line.
 *
 * The zone and the magenta circle move east together, so in a screenshot a
 * gliding zone is up to one step behind the magenta circle and a jumping
 * one is level with it (~/.config/munim-maps/plan/glide-measure.py).
 */

const CENTER = { latitude: 41.8827, longitude: -87.6233 }
const STEP_MS = 1000

type Engine = MapProvider | 'maplibreweb'

const wait = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms))

export function ShapeGlideScreen({ initial, jump, check, topInset }: { initial?: Engine; jump?: boolean; check?: boolean; topInset: number }) {
  const engines = useMemo<Engine[]>(() => {
    const list: Engine[] = installedProviders()
    return list.includes('maplibre') ? [...list, 'maplibreweb'] : list
  }, [])
  const [engine, setEngine] = useState<Engine>(initial && engines.includes(initial) ? initial : engines[0] ?? 'mapkit')
  const provider: MapProvider = engine === 'maplibreweb' ? 'maplibre' : engine
  const [animate, setAnimate] = useState(!jump)
  const [tick, setTick] = useState(0)
  const [checkStatus, setCheckStatus] = useState('')
  const map = useRef<MunimMapViewRef>(null)

  useEffect(() => {
    if (check) return
    const id = setInterval(() => setTick((t) => t + 1), STEP_MS)
    return () => clearInterval(id)
  }, [check])

  const runCheck = useCallback(async () => {
    const results: { name: string; ok: boolean; detail: string }[] = []
    const hit = async (c: MapCoordinate) => map.current!.overlayAtPoint(await map.current!.pointForCoordinate(c))
    const expect = async (name: string, c: MapCoordinate, want: string) => {
      const got = await hit(c)
      results.push({ name, ok: got === want, detail: `got '${got}', want '${want}'` })
    }
    await wait(4000)
    // Tick 0: the zone at its start, the pentagon unturned.
    await expect('circle centre hits the circle', { latitude: CENTER.latitude, longitude: CENTER.longitude - 0.02 }, 'zone')
    await expect('polygon ring hits the polygon', { latitude: CENTER.latitude + 0.012 + 0.004, longitude: CENTER.longitude + 0.016 }, 'pentagon')
    await expect('polygon hole hits nothing', { latitude: CENTER.latitude + 0.012, longitude: CENTER.longitude + 0.016 }, '')
    await expect('empty map hits nothing', { latitude: CENTER.latitude - 0.03, longitude: CENTER.longitude + 0.03 }, '')
    // Five steps on at once: the zone glides 0.01° east over a second.
    setTick(5)
    await wait(STEP_MS + 800)
    const moved = { latitude: CENTER.latitude + 0.002, longitude: CENTER.longitude }
    await expect('the glided circle is hit where it arrived', moved, 'zone')
    await expect('its old centre is outside it now', { latitude: CENTER.latitude, longitude: CENTER.longitude - 0.02 }, '')
    const passed = results.filter((r) => r.ok).length
    console.log(`MUNIM_MAPS_GLIDE ${engine} ${passed}/${results.length} ${JSON.stringify(results.filter((r) => !r.ok))}`)
    setCheckStatus(`check ${passed}/${results.length}`)
    try {
      const file = new File(Paths.document, `munim-maps-glide-check-${engine}.json`)
      if (file.exists) file.delete()
      file.create()
      file.writeSync(JSON.stringify({ engine, platform: Platform.OS, finishedAt: new Date().toISOString(), passed, total: results.length, results }, null, 2))
    } catch (error) {
      console.warn('MUNIM_MAPS_GLIDE could not write the report', error)
    }
  }, [engine])

  const duration = animate ? STEP_MS : 0
  // 0...1 and back over 20 s.
  const phase = (tick % 20) / 10
  const wave = phase <= 1 ? phase : 2 - phase

  const circles: MapCircle[] = [
    {
      id: 'zone',
      center: { latitude: CENTER.latitude + 0.004 * wave, longitude: CENTER.longitude - 0.02 + 0.04 * wave },
      radius: 1400 - 1000 * wave,
      fillColor: Math.floor(tick / 4) % 2 ? '#00E5FF22' : '#7F00FF22',
      strokeColor: Math.floor(tick / 4) % 2 ? '#00E5FF' : '#7F00FF',
      strokeWidth: 3,
      animationDuration: duration,
    },
    {
      id: 'jumps',
      center: { latitude: CENTER.latitude - 0.016, longitude: CENTER.longitude - 0.02 + 0.04 * wave },
      radius: 300,
      fillColor: '#FF00FF22',
      strokeColor: '#FF00FF',
      strokeWidth: 2,
    },
  ]

  // A pentagon turning 18° a second, with a hole: same vertex counts, so it glides.
  const ring = (radius: number, turn: number) =>
    Array.from({ length: 5 }, (_, i) => {
      const a = ((i * 72 + turn) * Math.PI) / 180
      return {
        latitude: CENTER.latitude + 0.012 + radius * Math.cos(a),
        longitude: CENTER.longitude + 0.016 + (radius * Math.sin(a)) / Math.cos((CENTER.latitude * Math.PI) / 180),
      }
    })
  const polygons: MapPolygon[] = [
    {
      id: 'pentagon',
      coordinates: ring(0.006, tick * 18),
      holes: [ring(0.002, -tick * 18)],
      fillColor: '#FF9F0A44',
      strokeColor: '#FF9F0A',
      strokeWidth: 3,
      animationDuration: duration,
    },
  ]

  return (
    <View style={styles.fill}>
      <MunimMapView
        ref={map}
        style={styles.fill}
        onMapReady={check ? () => void runCheck() : undefined}
        provider={provider}
        maplibre={{ renderer: engine === 'maplibreweb' ? 'web' : 'native' }}
        initialRegion={{ latitude: CENTER.latitude, longitude: CENTER.longitude, latitudeDelta: 0.05, longitudeDelta: 0.05 }}
        circles={circles}
        polygons={polygons}
      />
      <View style={[styles.panel, { top: topInset + 8 }]}>
        <View style={styles.row}>
          {engines.map((p) => (
            <Pressable key={p} onPress={() => setEngine(p)} style={[styles.chip, p === engine && styles.on]}>
              <Text style={[styles.label, p === engine && styles.onLabel]}>{p}</Text>
            </Pressable>
          ))}
        </View>
        <View style={styles.row}>
          <Pressable onPress={() => setAnimate((a) => !a)} style={[styles.chip, animate && styles.on]}>
            <Text style={[styles.label, animate && styles.onLabel]}>{animate ? `animationDuration ${STEP_MS}` : 'animationDuration 0'}</Text>
          </Pressable>
          <Text style={styles.status}>update {tick}{checkStatus ? ` · ${checkStatus}` : ''}</Text>
        </View>
      </View>
    </View>
  )
}

const styles = StyleSheet.create({
  fill: { flex: 1 },
  panel: { position: 'absolute', left: 8, right: 8, gap: 6 },
  row: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, alignItems: 'center' },
  chip: { paddingHorizontal: 10, paddingVertical: 6, borderRadius: 14, backgroundColor: 'rgba(255,255,255,0.92)' },
  on: { backgroundColor: '#0A84FF' },
  label: { fontSize: 13, fontWeight: '600', color: '#111' },
  onLabel: { color: '#fff' },
  status: { fontSize: 13, fontWeight: '600', color: '#111', backgroundColor: 'rgba(255,255,255,0.92)', paddingHorizontal: 8, paddingVertical: 4, borderRadius: 8 },
})
