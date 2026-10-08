// The munim camera (centre, distance in metres from the camera, pitch from
// straight down, heading) on GL JS's camera (centre, zoom, pitch, bearing),
// with the same conversion as the MapLibre Native engine (512-point tiles,
// GL JS's vertical field of view), flights, regions, fitting, and the
// camera state the native side reads (synchronous getters, the native 3D
// layer with `modelRendering: 'overlay'`).
/* global maplibregl */
;(function () {
  'use strict'
  const M = window.munimMapLibre

  const EARTH_CIRCUMFERENCE = 2 * Math.PI * 6378137 // as the native engines
  const TILE_SIZE = 512

  /** GL JS's vertical field of view, radians (36.87° unless changed). */
  M.fovy = function () {
    const map = M.map
    const deg = map && map.transform && typeof map.transform.fov === 'number' ? map.transform.fov : 36.86989764584402
    return M.toRad(deg)
  }

  function heightPoints(height) {
    const h = height || (M.map ? M.map.getContainer().clientHeight : window.innerHeight) || 1
    return Math.max(1, h)
  }

  /** Points from the camera to the centre, at GL JS's field of view. */
  function cameraPoints(height) {
    return heightPoints(height) / 2 / Math.tan(M.fovy() / 2)
  }

  M.metersPerPoint = function (latitude, zoom) {
    return (Math.cos(M.toRad(latitude)) * EARTH_CIRCUMFERENCE) / (TILE_SIZE * Math.pow(2, zoom))
  }

  M.distanceForZoom = function (zoom, latitude, height) {
    return cameraPoints(height) * M.metersPerPoint(latitude, zoom)
  }

  M.zoomForDistance = function (distance, latitude, height) {
    const world = Math.cos(M.toRad(latitude)) * EARTH_CIRCUMFERENCE
    return Math.log2((cameraPoints(height) * world) / (TILE_SIZE * Math.max(1, distance)))
  }

  function wrapHeading(h) {
    return ((h % 360) + 360) % 360
  }

  /** GL JS camera options for a munim camera. */
  M.viewForCamera = function (cam, height) {
    const latitude = Math.max(-85, Math.min(85, M.num(cam.latitude, 0)))
    return {
      center: [M.num(cam.longitude, 0), latitude],
      zoom: Math.max(0, Math.min(24, M.zoomForDistance(Math.max(1, M.num(cam.distance, 1000)), latitude, height))),
      pitch: Math.max(0, Math.min(85, M.num(cam.pitch, 0))),
      bearing: M.num(cam.heading, 0),
    }
  }

  /** The munim camera now. */
  M.munimCamera = function () {
    const map = M.map
    const c = map.getCenter()
    return {
      latitude: c.lat,
      longitude: c.lng,
      distance: M.distanceForZoom(map.getZoom(), c.lat),
      pitch: map.getPitch(),
      heading: wrapHeading(map.getBearing()),
    }
  }

  /**
   * GL JS 5 freezes the centre's ground height for every animation and only
   * thaws it with `freezeElevation`, so after an ease the centre stays at the
   * old height (a jump to the Alps would keep Chicago's): thaw it once the
   * camera rests, so the centre follows the terrain under it again.
   */
  M.thawElevation = function () {
    const map = M.map
    if (map && map._elevationFreeze && !map.isMoving()) {
      map._elevationFreeze = false
      map.triggerRepaint()
    }
  }

  M.applyCamera = function (cam) {
    M.map.jumpTo(M.viewForCamera(cam))
    M.thawElevation()
  }

  const EASE_IN_OUT = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2)

  /** Moves to a munim camera over `seconds` (0 jumps). */
  M.animateTo = function (cam, seconds, easing) {
    const map = M.map
    if (!(seconds > 0)) {
      M.applyCamera(cam)
      return
    }
    const view = M.viewForCamera(cam)
    // The shortest turn, as the other engines.
    const current = map.getBearing()
    let bearing = view.bearing
    while (bearing - current > 180) bearing -= 360
    while (bearing - current < -180) bearing += 360
    map.easeTo(Object.assign(view, { bearing, duration: seconds * 1000, easing: easing === 'linear' ? (t) => t : EASE_IN_OUT, essential: true }))
  }

  // MARK: Flights (keyframes on the page's frame clock)

  let flight
  M.isFlying = () => !!flight

  function interpolate(a, b, f) {
    const turn = ((((b.heading - a.heading) % 360) + 540) % 360) - 180
    return {
      latitude: a.latitude + (b.latitude - a.latitude) * f,
      longitude: a.longitude + (b.longitude - a.longitude) * f,
      distance: Math.exp(Math.log(Math.max(1, a.distance)) + (Math.log(Math.max(1, b.distance)) - Math.log(Math.max(1, a.distance))) * f),
      pitch: a.pitch + (b.pitch - a.pitch) * f,
      heading: wrapHeading(a.heading + turn * f),
    }
  }

  function stepFlight() {
    if (!flight) return
    const frames = flight.keyframes
    const first = frames[0]
    const last = frames[frames.length - 1]
    let t = Date.now() / 1000 - flight.start
    const span = last.t - first.t
    if (flight.loop && span > 0) {
      t = first.t + ((((t - first.t) % span) + span) % span)
    }
    let cam
    if (t <= first.t) cam = first.camera
    else if (t >= last.t) {
      cam = last.camera
      if (!flight.loop) flight = undefined
    } else {
      let i = 1
      while (i < frames.length - 1 && frames[i].t < t) i++
      const a = frames[i - 1]
      const b = frames[i]
      cam = interpolate(a.camera, b.camera, (t - a.t) / Math.max(1e-9, b.t - a.t))
    }
    M.applyCamera(cam)
    if (flight) requestAnimationFrame(stepFlight)
  }

  M.startFlight = function (keyframes, start, loop) {
    M.stopFlight()
    const frames = (keyframes || []).slice().sort((a, b) => a.t - b.t)
    if (frames.length === 0) return
    if (frames.length === 1) {
      M.applyCamera(frames[0].camera)
      return
    }
    flight = { keyframes: frames, start: M.num(start, Date.now() / 1000), loop: !!loop }
    stepFlight()
  }

  M.stopFlight = function () {
    flight = undefined
    if (M.map && M.map.isEasing && M.map.isEasing()) M.map.stop()
  }

  // MARK: Regions

  M.visibleRegion = function () {
    const b = M.map.getBounds()
    const west = b.getWest()
    const east = b.getEast()
    const south = Math.max(-90, b.getSouth())
    const north = Math.min(90, b.getNorth())
    return {
      latitude: (south + north) / 2,
      longitude: (west + east) / 2,
      latitudeDelta: Math.max(0, north - south),
      longitudeDelta: Math.max(0, Math.min(360, east - west)),
    }
  }

  function padding(p) {
    const q = p || {}
    return { top: M.num(q.top, 0), left: M.num(q.left, 0), bottom: M.num(q.bottom, 0), right: M.num(q.right, 0) }
  }

  /** Frames bounds keeping the camera's pitch and heading (as MapLibre Native does). */
  function frameBounds(bounds, pad, seconds) {
    const map = M.map
    const camera = map.cameraForBounds(bounds, { padding: padding(pad), bearing: map.getBearing(), pitch: map.getPitch() })
    if (!camera) return
    if (seconds > 0) map.easeTo(Object.assign(camera, { duration: seconds * 1000, essential: true }))
    else map.jumpTo(camera)
  }

  M.fitCoordinates = function (coordinates, pad, animated) {
    if (!coordinates || !coordinates.length) return
    M.stopFlight()
    if (coordinates.length === 1) {
      M.map.easeTo({ center: M.lngLat(coordinates[0]), duration: animated ? 600 : 0 })
      return
    }
    const bounds = new maplibregl.LngLatBounds()
    for (const c of coordinates) bounds.extend(M.lngLat(c))
    frameBounds(bounds, pad, animated ? 0.8 : 0)
  }

  // MARK: Camera state for the native side

  /** The projection the custom-layer API exposes: matrices for mercator and globe. */
  M.projectionData = function () {
    const t = M.map.transform
    try {
      return t.getProjectionDataForCustomLayer(true)
    } catch (e) {
      return undefined
    }
  }

  function list(m) {
    return m ? Array.from(m, (v) => +v) : undefined
  }

  M.cameraState = function () {
    const map = M.map
    const cam = M.munimCamera()
    const container = map.getContainer()
    const p = map.getPadding()
    const data = M.projectionData()
    const transform = map.transform
    return Object.assign(cam, {
      zoom: map.getZoom(),
      fovy: M.fovy(),
      width: container.clientWidth,
      height: container.clientHeight,
      centerX: p.left + (container.clientWidth - p.left - p.right) / 2,
      centerY: p.top + (container.clientHeight - p.top - p.bottom) / 2,
      globe: !!data && data.projectionTransition > 0,
      transition: data ? data.projectionTransition : 0,
      mainMatrix: data ? list(data.mainMatrix) : undefined,
      fallbackMatrix: data ? list(data.fallbackMatrix) : undefined,
      clippingPlane: data ? list(data.clippingPlane) : undefined,
      terrain: M.drawsTerrain(),
      centerElevation: transform && typeof transform.elevation === 'number' ? transform.elevation : 0,
      dark: M.isDark(),
    })
  }

  let lastPosted = ''
  function postCamera(withRegion) {
    if (!M.map || !M.styleLoaded()) return
    const state = M.cameraState()
    if (withRegion) state.region = M.visibleRegion()
    const key = JSON.stringify([state.latitude, state.longitude, state.distance, state.pitch, state.heading, state.width, state.height, state.transition, state.centerElevation, withRegion])
    if (key === lastPosted && !withRegion) return
    lastPosted = key
    M.post({ t: 'cam', s: state })
  }
  M.postCamera = postCamera

  M.mapHooks.push((map) => {
    map.on('movestart', (e) => {
      M.providerEvent('cameraMoveStarted', { reason: e && e.originalEvent ? 'gesture' : flight ? 'flight' : 'api' })
    })
    map.on('move', () => {
      postCamera(false)
      M.emit('cameraMove', M.munimCamera())
    })
    map.on('moveend', () => {
      M.thawElevation()
      postCamera(true)
      M.emit('cameraChange', M.munimCamera())
      const range = M.state.distanceRange
      if (range && (range.min > 0 || range.max > 0)) M.applyLimits()
    })
    map.on('resize', () => postCamera(true))
    map.on('load', () => postCamera(true))
    map.on('terrain', () => postCamera(true))
  })

  // MARK: Props

  let initialApplied = false
  M.mapHooks.push(() => {
    const cam = M.state.initialCamera
    if (cam && cam.distance > 0) initialApplied = true
  })
  M.on('initialCamera', (cam) => {
    if (initialApplied || !cam || !(cam.distance > 0)) return
    initialApplied = true
    M.applyCamera(cam)
  })
  // GL JS cannot move the camera before its style (and projection) exist.
  function applyPadding(p) {
    const map = M.map
    if (!M.styleLoaded(map)) {
      map.once('style.load', () => applyPadding(M.state.mapPadding))
      return
    }
    const next = padding(p)
    const now = map.getPadding()
    if (now.top === next.top && now.left === next.left && now.bottom === next.bottom && now.right === next.right) return
    map.setPadding(next)
    postCamera(true)
  }
  M.on('mapPadding', applyPadding)
  M.mapHooks.push(() => {
    if (M.state.mapPadding) applyPadding(M.state.mapPadding)
  })

  // MARK: Methods

  M.method('setCamera', (a) => {
    M.stopFlight()
    if (a.animated) M.animateTo(a.camera, 0.8, 'easeinout')
    else M.applyCamera(a.camera)
  })
  M.method('animateCamera', (a) => {
    M.stopFlight()
    M.animateTo(a.camera, (a.durationMs || 0) / 1000, M.norm(a.easing) === 'linear' ? 'linear' : 'easeinout')
  })
  M.method('flyCamera', (a) => M.startFlight(a.keyframes || [], a.start || Date.now() / 1000, a.loop))
  M.method('stopFlight', () => M.stopFlight())
  M.method('getCamera', () => M.munimCamera())
  M.method('getVisibleRegion', () => M.visibleRegion())
  M.method('cameraState', () => M.cameraState())
  M.method('setRegion', (a) => {
    M.stopFlight()
    const r = a.region
    const bounds = new maplibregl.LngLatBounds(
      [r.longitude - r.longitudeDelta / 2, r.latitude - r.latitudeDelta / 2],
      [r.longitude + r.longitudeDelta / 2, r.latitude + r.latitudeDelta / 2]
    )
    frameBounds(bounds, null, (a.durationMs || 0) / 1000)
  })
  M.method('fitToCoordinates', (a) => M.fitCoordinates(a.coordinates || [], a.padding, a.animated))
  M.method('pointForCoordinate', (a) => {
    const c = a.coordinate || a
    const p = M.map.project([c.longitude, c.latitude])
    return { x: p.x, y: p.y }
  })
  M.method('coordinateForPoint', (a) => {
    const p = a.point || a
    const c = M.map.unproject([p.x, p.y])
    return { latitude: c.lat, longitude: c.lng }
  })
})()
