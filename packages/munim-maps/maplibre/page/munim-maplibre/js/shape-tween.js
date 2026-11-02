// Glides circles and polygons to new geometry (`animationDuration`) on the
// page, once an animation frame, so the app only sends the occasional
// update. The same file is in the Cesium and GL JS pages
// (test/shape-tween.test.js keeps the two copies identical).
//
// Style changes apply at once; only the geometry moves. A polygon glides
// only when its new rings have the same vertex counts; otherwise it jumps.
;(function (root) {
  'use strict'

  const num = (v, fallback) => (typeof v === 'number' && isFinite(v) ? v : fallback)
  const lerp = (a, b, t) => a + (b - a) * t

  /** Longitude the short way round the antimeridian. */
  function lerpLongitude(a, b, t) {
    let d = (b - a) % 360
    if (d > 180) d -= 360
    else if (d < -180) d += 360
    let v = a + d * t
    if (v > 180) v -= 360
    else if (v < -180) v += 360
    return v
  }

  const lerpCoordinate = (a, b, t) => ({ latitude: lerp(a.latitude, b.latitude, t), longitude: lerpLongitude(a.longitude, b.longitude, t) })

  function geometry(kind, s) {
    if (kind === 'circle') return { latitude: s.latitude, longitude: s.longitude, radius: s.radius }
    return { coordinates: s.coordinates || [], holes: s.holes || [] }
  }

  function sameRing(a, b) {
    if (a.length !== b.length) return false
    for (let i = 0; i < a.length; i++) if (a[i].latitude !== b[i].latitude || a[i].longitude !== b[i].longitude) return false
    return true
  }

  function sameGeometry(kind, a, b) {
    if (kind === 'circle') return a.latitude === b.latitude && a.longitude === b.longitude && a.radius === b.radius
    return sameRing(a.coordinates, b.coordinates) && a.holes.length === b.holes.length && a.holes.every((h, i) => sameRing(h, b.holes[i]))
  }

  /** Same vertex counts, so a polygon's vertices can move pairwise. */
  function sameShape(a, b) {
    return a.coordinates.length === b.coordinates.length && a.holes.length === b.holes.length && a.holes.every((h, i) => h.length === b.holes[i].length)
  }

  function interpolate(kind, from, to, t) {
    if (t >= 1) return to
    if (kind === 'circle') {
      return { latitude: lerp(from.latitude, to.latitude, t), longitude: lerpLongitude(from.longitude, to.longitude, t), radius: lerp(from.radius, to.radius, t) }
    }
    return {
      coordinates: to.coordinates.map((c, i) => lerpCoordinate(from.coordinates[i], c, t)),
      holes: to.holes.map((ring, h) => ring.map((c, i) => lerpCoordinate(from.holes[h][i], c, t))),
    }
  }

  /**
   * `onFrame(kind, shapes)` gets every shape of a kind as drawn now, once a
   * frame while any of them glides. `set(kind, shapes)` takes new props and
   * returns the shapes to draw now.
   */
  function create(onFrame, options) {
    const now = (options && options.now) || (() => performance.now())
    const schedule = (options && options.schedule) || ((fn) => requestAnimationFrame(fn))
    const targets = { circle: [], polygon: [] }
    let drawn = new Map() // `${kind}:${id}` -> geometry of the props
    let runs = new Map() // `${kind}:${id}` -> { kind, from, to, start, duration }
    let scheduled = false

    const progress = (run, t) => (run.duration > 0 ? Math.min(1, Math.max(0, (t - run.start) / run.duration)) : 1)
    const at = (run, t) => interpolate(run.kind, run.from, run.to, progress(run, t))

    function current(key, t) {
      const run = runs.get(key)
      return run ? at(run, t) : drawn.get(key)
    }

    function frame(kind, t) {
      return targets[kind].map((s) => {
        const run = runs.get(`${kind}:${s.id}`)
        return run ? Object.assign({}, s, at(run, t)) : s
      })
    }

    function tick() {
      scheduled = false
      const t = now()
      const kinds = new Set([...runs.values()].map((r) => r.kind))
      for (const kind of kinds) onFrame(kind, frame(kind, t))
      for (const [key, run] of runs) if (t >= run.start + run.duration) runs.delete(key)
      start()
    }

    function start() {
      if (runs.size && !scheduled) {
        scheduled = true
        schedule(tick)
      }
    }

    function set(kind, list) {
      list = list || []
      const t = now()
      const nextRuns = new Map([...runs].filter(([, run]) => run.kind !== kind))
      const nextDrawn = new Map([...drawn].filter(([key]) => !key.startsWith(`${kind}:`)))
      for (const s of list) {
        const key = `${kind}:${s.id}`
        if (nextDrawn.has(key)) continue
        const to = geometry(kind, s)
        nextDrawn.set(key, to)
        const duration = num(s.animationDuration, 0)
        if (!(duration > 0)) continue
        const from = current(key, t)
        if (!from || (kind === 'polygon' && !sameShape(from, to))) continue
        const run = runs.get(key)
        if (run && sameGeometry(kind, run.to, to)) {
          // Already gliding there (the same props again): carry on.
          nextRuns.set(key, run)
          continue
        }
        if (sameGeometry(kind, from, to)) continue
        nextRuns.set(key, { kind, from, to, start: t, duration })
      }
      targets[kind] = list
      drawn = nextDrawn
      runs = nextRuns
      start()
      return frame(kind, t)
    }

    return {
      set,
      /** True while the shape glides. */
      running: (kind, id) => runs.has(`${kind}:${id}`),
      reset() {
        runs = new Map()
        drawn = new Map()
        targets.circle = []
        targets.polygon = []
      },
    }
  }

  root.munimShapeTween = { create, interpolate, lerpLongitude, sameShape, sameGeometry }
  if (typeof module !== 'undefined' && module.exports) module.exports = root.munimShapeTween
})(typeof window !== 'undefined' ? window : globalThis)
