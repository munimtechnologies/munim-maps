// The munim camera (centre, distance, pitch from straight down, heading) on
// Cesium's camera, flights, limits, gestures, and the camera state the
// native side reads every frame (its 3D layer and synchronous getters).
/* global Cesium */
;(function () {
  'use strict'
  const M = window.munimCesium
  const C = Cesium

  const scratchRay = new C.Ray()

  function padding() {
    const p = M.state.mapPadding || {}
    return { top: p.top || 0, left: p.left || 0, bottom: p.bottom || 0, right: p.right || 0 }
  }

  /** Where the centre coordinate is drawn: the middle of what the padding leaves, in CSS pixels. */
  M.centerPoint = function () {
    const canvas = M.viewer.scene.canvas
    const p = padding()
    return new C.Cartesian2(p.left + (canvas.clientWidth - p.left - p.right) / 2, p.top + (canvas.clientHeight - p.top - p.bottom) / 2)
  }

  /** The ground (terrain or 3D Tiles if loaded, else the ellipsoid) under a window position. */
  M.pickGround = function (position, useDepth) {
    const scene = M.viewer.scene
    if (useDepth && scene.pickPositionSupported) {
      const picked = scene.pickPosition(position)
      if (picked) return picked
    }
    const ray = scene.camera.getPickRay(position, scratchRay)
    if (!ray) return undefined
    if (scene.mode === C.SceneMode.SCENE3D) {
      const onGlobe = scene.globe.pick(ray, scene)
      if (onGlobe) return onGlobe
    }
    return scene.camera.pickEllipsoid(position, scene.globe.ellipsoid)
  }

  /** Ground height at a coordinate from the loaded terrain tiles (0 when unknown). */
  M.groundHeight = function (latitude, longitude) {
    if (!M.drawsTerrain()) return 0
    const h = M.viewer.scene.globe.getHeight(C.Cartographic.fromDegrees(longitude, latitude))
    return h == null ? 0 : h
  }

  /** The camera as munim describes it, in the frame of the centre point. */
  M.cameraNow = function () {
    const viewer = M.viewer
    const scene = viewer.scene
    const camera = scene.camera
    const centerPoint = M.centerPoint()
    let center = M.pickGround(centerPoint)
    if (scene.mode !== C.SceneMode.SCENE3D) {
      const carto = camera.positionCartographic
      const c = center ? C.Cartographic.fromCartesian(center) : carto
      const pitch = 90 + M.toDeg(camera.pitch)
      let height = carto.height
      if (scene.mode === C.SceneMode.SCENE2D) {
        const f = camera.frustum
        const widthMeters = (f.right - f.left) || 1
        const fovy = C.Math.toRadians(60)
        height = (widthMeters * (scene.canvas.clientHeight / Math.max(1, scene.canvas.clientWidth))) / 2 / Math.tan(fovy / 2)
      }
      return {
        latitude: M.toDeg(c.latitude),
        longitude: M.toDeg(c.longitude),
        height: c.height || 0,
        distance: height / Math.max(0.1, Math.cos(M.toRad(pitch))),
        pitch: Math.max(0, Math.min(90, pitch)),
        heading: (M.toDeg(camera.heading) + 360) % 360,
        center: undefined,
      }
    }
    const position = camera.positionWC
    if (!center) {
      const ray = camera.getPickRay(centerPoint, scratchRay)
      center = ray ? C.IntersectionTests.grazingAltitudeLocation(ray, scene.globe.ellipsoid) : undefined
    }
    if (!center) center = scene.globe.ellipsoid.scaleToGeodeticSurface(position, new C.Cartesian3())
    const frame = C.Transforms.eastNorthUpToFixedFrame(center)
    const east = C.Matrix4.getColumn(frame, 0, new C.Cartesian4())
    const north = C.Matrix4.getColumn(frame, 1, new C.Cartesian4())
    const up = C.Matrix4.getColumn(frame, 2, new C.Cartesian4())
    const toCenter = C.Cartesian3.subtract(center, position, new C.Cartesian3())
    const distance = C.Cartesian3.magnitude(toCenter)
    const dir = C.Cartesian3.normalize(toCenter, toCenter)
    const dot = (a, b) => a.x * b.x + a.y * b.y + a.z * b.z
    const pitch = M.toDeg(Math.acos(Math.max(-1, Math.min(1, -dot(dir, up)))))
    let heading
    if (pitch < 0.5) {
      const u = camera.upWC
      heading = M.toDeg(Math.atan2(dot(u, east), dot(u, north)))
    } else {
      heading = M.toDeg(Math.atan2(dot(dir, east), dot(dir, north)))
    }
    const carto = C.Cartographic.fromCartesian(center)
    return {
      latitude: M.toDeg(carto.latitude),
      longitude: M.toDeg(carto.longitude),
      height: carto.height,
      distance,
      pitch,
      heading: (heading + 360) % 360,
      center,
    }
  }

  M.munimCamera = function () {
    const c = M.cameraNow()
    return { latitude: c.latitude, longitude: c.longitude, distance: c.distance, pitch: c.pitch, heading: c.heading }
  }

  /** Puts the camera at a munim camera, now. */
  M.applyCamera = function (cam, centerHeight) {
    const viewer = M.viewer
    const scene = viewer.scene
    const camera = scene.camera
    const height = centerHeight != null ? centerHeight : M.groundHeight(cam.latitude, cam.longitude)
    const pitch = Math.max(0, Math.min(90, M.num(cam.pitch, 0)))
    const heading = M.toRad(M.num(cam.heading, 0))
    const distance = Math.max(1, M.num(cam.distance, 1000))
    if (scene.mode === C.SceneMode.SCENE2D) {
      camera.setView({ destination: C.Cartesian3.fromDegrees(cam.longitude, cam.latitude, distance), orientation: { heading, pitch: -C.Math.PI_OVER_TWO, roll: 0 } })
      return
    }
    const center = C.Cartesian3.fromDegrees(cam.longitude, cam.latitude, height)
    // Straight down has no heading in Cesium's lookAt: keep a hair of pitch.
    const offset = new C.HeadingPitchRange(heading, M.toRad(Math.max(0.01, pitch) - 90), distance)
    camera.lookAt(center, offset)
    camera.lookAtTransform(C.Matrix4.IDENTITY)
    const p = padding()
    if (p.top || p.bottom || p.left || p.right) {
      // Move the camera so the centre lands in the middle of the padded area.
      const want = M.centerPoint()
      const canvas = scene.canvas
      const dx = want.x - canvas.clientWidth / 2
      const dy = want.y - canvas.clientHeight / 2
      const fovy = camera.frustum.fovy || C.Math.toRadians(60)
      const metersPerPixel = (2 * distance * Math.tan(fovy / 2)) / Math.max(1, canvas.clientHeight)
      camera.moveLeft(dx * metersPerPixel)
      camera.moveUp(-dy * metersPerPixel)
    }
  }

  // MARK: Flights (the munim camera, interpolated on the frame clock)

  let flight // { keyframes, start (s since 1970), loop, onDone }

  function lerpAngle(a, b, t) {
    let d = ((b - a + 540) % 360) - 180
    return a + d * t
  }

  function interpolate(a, b, t) {
    // Distances interpolate in log space, so zooming feels even.
    const logDistance = Math.log(Math.max(1, a.distance)) * (1 - t) + Math.log(Math.max(1, b.distance)) * t
    return {
      latitude: a.latitude + (b.latitude - a.latitude) * t,
      longitude: lerpAngle(a.longitude, b.longitude, t),
      distance: Math.exp(logDistance),
      pitch: a.pitch + (b.pitch - a.pitch) * t,
      heading: lerpAngle(a.heading, b.heading, t),
    }
  }

  const ease = {
    linear: (t) => t,
    easeinout: (t) => (t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2),
  }

  M.startFlight = function (keyframes, start, loop, easing) {
    if (!keyframes.length) return
    flight = { keyframes: keyframes.slice().sort((a, b) => a.t - b.t), start, loop: !!loop, easing: easing || 'linear' }
    M.viewer.trackedEntity = undefined
    M.requestRender()
  }

  M.stopFlight = function () {
    flight = undefined
  }

  M.isFlying = () => !!flight

  function stepFlight() {
    if (!flight) return
    const frames = flight.keyframes
    const last = frames[frames.length - 1]
    let t = Date.now() / 1000 - flight.start
    if (t < 0) t = 0
    if (flight.loop && last.t > 0) t = t % last.t
    let cam
    if (t >= last.t) {
      cam = last.camera
    } else {
      let i = 0
      while (i < frames.length - 1 && frames[i + 1].t <= t) i++
      const a = frames[i]
      const b = frames[Math.min(i + 1, frames.length - 1)]
      const span = Math.max(1e-6, b.t - a.t)
      const f = Math.max(0, Math.min(1, (t - a.t) / span))
      cam = interpolate(a.camera, b.camera, (ease[flight.easing] || ease.linear)(f))
    }
    M.applyCamera(cam)
    if (!flight.loop && t >= last.t) flight = undefined
  }

  M.animateTo = function (cam, seconds, easing) {
    if (seconds <= 0) {
      M.stopFlight()
      M.applyCamera(cam)
      return
    }
    const from = M.munimCamera()
    M.startFlight([{ t: 0, camera: from }, { t: seconds, camera: cam }], Date.now() / 1000, false, easing)
  }

  // MARK: Limits and gestures

  M.applyController = function () {
    const viewer = M.viewer
    if (!viewer) return
    const c = viewer.scene.screenSpaceCameraController
    const g = M.state.gestures || {}
    const zoom = g.zoom !== false
    const scroll = g.scroll !== false
    const rotate = g.rotate !== false
    const pitch = g.pitch !== false
    c.enableZoom = zoom
    // Dragging the globe (3D) or the map (2D, Columbus view).
    c.enableRotate = scroll
    c.enableTranslate = scroll
    // Turning (twist) and tilting.
    c.enableLook = rotate
    c.enableTilt = pitch || rotate
    const range = M.state.distanceRange || {}
    c.minimumZoomDistance = range.min > 0 ? range.min : 1
    c.maximumZoomDistance = range.max > 0 ? range.max : Number.POSITIVE_INFINITY
    const controller = M.options().controller
    if (controller) M.assign(c, controller)
  }

  M.applyFrustum = function () {
    const viewer = M.viewer
    if (!viewer) return
    const camera = viewer.scene.camera
    const o = M.options().camera || {}
    if (M.norm(o.frustum) === 'orthographic') {
      if (!(camera.frustum instanceof C.OrthographicFrustum)) camera.switchToOrthographicFrustum()
    } else if (camera.frustum instanceof C.OrthographicFrustum && viewer.scene.mode !== C.SceneMode.SCENE2D) {
      camera.switchToPerspectiveFrustum()
    }
    if (camera.frustum instanceof C.PerspectiveFrustum) {
      if (o.fov !== undefined) camera.frustum.fov = M.toRad(o.fov)
      if (o.near !== undefined) camera.frustum.near = o.near
      if (o.far !== undefined) camera.frustum.far = o.far
    }
    if (o.percentageChanged !== undefined) camera.percentageChanged = o.percentageChanged
    if (o.defaultMoveAmount !== undefined) camera.defaultMoveAmount = o.defaultMoveAmount
    if (o.defaultLookAmount !== undefined) camera.defaultLookAmount = o.defaultLookAmount
    if (o.defaultRotateAmount !== undefined) camera.defaultRotateAmount = o.defaultRotateAmount
    if (o.defaultZoomAmount !== undefined) camera.defaultZoomAmount = o.defaultZoomAmount
    if (o.maximumZoomFactor !== undefined) camera.maximumZoomFactor = o.maximumZoomFactor
  }

  function keepInBoundary() {
    const b = M.state.boundary
    if (!b || !(b.latitudeDelta > 0) || flight) return
    const cam = M.cameraNow()
    const minLat = b.latitude - b.latitudeDelta / 2
    const maxLat = b.latitude + b.latitudeDelta / 2
    const minLon = b.longitude - b.longitudeDelta / 2
    const maxLon = b.longitude + b.longitudeDelta / 2
    const lat = Math.max(minLat, Math.min(maxLat, cam.latitude))
    const lon = Math.max(minLon, Math.min(maxLon, cam.longitude))
    if (Math.abs(lat - cam.latitude) > 1e-9 || Math.abs(lon - cam.longitude) > 1e-9) {
      M.applyCamera({ latitude: lat, longitude: lon, distance: cam.distance, pitch: cam.pitch, heading: cam.heading })
    }
  }

  // MARK: Camera state for the native side and camera events

  const lastView = new C.Matrix4()
  let lastWidth = 0
  let lastHeight = 0
  let moving = false
  let idleTimer
  let readySent = false

  M.cameraState = function () {
    const scene = M.viewer.scene
    const camera = scene.camera
    const canvas = scene.canvas
    const cam = M.cameraNow()
    const width = canvas.clientWidth
    const height = canvas.clientHeight
    const frustum = camera.frustum
    let fovy = frustum.fovy
    if (!(fovy > 0)) fovy = C.Math.toRadians(60)
    const centerPoint = cam.center ? C.SceneTransforms.worldToWindowCoordinates(scene, cam.center) : undefined
    const view = camera.viewMatrix
    const proj = frustum.projectionMatrix
    const state = {
      latitude: cam.latitude,
      longitude: cam.longitude,
      centerHeight: cam.height,
      distance: cam.distance,
      pitch: cam.pitch,
      heading: cam.heading,
      fovy,
      width,
      height,
      centerX: centerPoint ? centerPoint.x : width / 2,
      centerY: centerPoint ? centerPoint.y : height / 2,
      globe: scene.mode === C.SceneMode.SCENE3D,
      terrain: M.drawsTerrain(),
      dark: M.isDark(),
      sceneMode: M.sceneModeName(),
      view: Array.from(C.Matrix4.toArray(view)),
      projection: proj ? Array.from(C.Matrix4.toArray(proj)) : null,
    }
    // Where Cesium itself draws the native models' ground points (measureAlignment).
    const points = M.nativeModelPoints && M.nativeModelPoints()
    if (points && points.length) {
      state.points = []
      for (const p of points) {
        const w = C.SceneTransforms.worldToWindowCoordinates(scene, C.Cartesian3.fromDegrees(p.longitude, p.latitude, cam.height + (p.altitude || 0)))
        if (w) state.points.push([p.id, w.x, w.y])
      }
    }
    return state
  }

  M.visibleRegion = function () {
    const scene = M.viewer.scene
    const rect = scene.camera.computeViewRectangle(scene.globe.ellipsoid)
    if (!rect) {
      const cam = M.cameraNow()
      return { latitude: cam.latitude, longitude: cam.longitude, latitudeDelta: 180, longitudeDelta: 360 }
    }
    let west = M.toDeg(rect.west)
    let east = M.toDeg(rect.east)
    if (east < west) east += 360
    const south = M.toDeg(rect.south)
    const north = M.toDeg(rect.north)
    let lon = (west + east) / 2
    if (lon > 180) lon -= 360
    return { latitude: (south + north) / 2, longitude: lon, latitudeDelta: north - south, longitudeDelta: east - west }
  }

  function postCamera(force) {
    const scene = M.viewer.scene
    const canvas = scene.canvas
    const view = scene.camera.viewMatrix
    const sized = canvas.clientWidth !== lastWidth || canvas.clientHeight !== lastHeight
    const changed = force || sized || !C.Matrix4.equalsEpsilon(view, lastView, 1e-9)
    if (!changed) return false
    C.Matrix4.clone(view, lastView)
    lastWidth = canvas.clientWidth
    lastHeight = canvas.clientHeight
    const state = M.cameraState()
    M.post({ t: 'cam', s: state })
    return true
  }
  M.postCamera = postCamera

  function cameraEvent(state) {
    return { latitude: state.latitude, longitude: state.longitude, distance: state.distance, pitch: state.pitch, heading: state.heading }
  }

  M.viewerHooks.push((viewer) => {
    readySent = false
    const scene = viewer.scene
    scene.preRender.addEventListener(() => {
      stepFlight()
      keepInBoundary()
    })
    scene.postRender.addEventListener(() => {
      if (!postCamera(false)) return
      const cam = M.munimCamera()
      M.emit('cameraMove', cam)
      moving = true
      clearTimeout(idleTimer)
      idleTimer = setTimeout(() => {
        moving = false
        const state = M.cameraState()
        M.post({ t: 'cam', s: Object.assign(state, { region: M.visibleRegion() }) })
        M.emit('cameraChange', cameraEvent(state))
      }, 150)
      if (!readySent) {
        readySent = true
        M.post({ t: 'cam', s: Object.assign(M.cameraState(), { region: M.visibleRegion() }) })
      }
    })
    scene.camera.moveStart.addEventListener(() => M.emit('provider', { name: 'cameraMoveStart', data: {} }))
    scene.camera.moveEnd.addEventListener(() => M.emit('provider', { name: 'cameraMoveEnd', data: {} }))
  })

  M.isMoving = () => moving

  // MARK: Props

  let initialApplied = false
  M.on('initialCamera', (cam) => {
    if (initialApplied || !cam || !(cam.distance > 0)) return
    initialApplied = true
    M.applyCamera(cam)
  })
  M.destroyHooks.push(() => {
    // A new viewer starts where the old one was.
    try {
      const cam = M.munimCamera()
      M.state.initialCamera = cam
    } catch (e) {
      // no camera yet
    }
    initialApplied = false
    flight = undefined
  })
  M.on('gestures', () => M.applyController())
  M.on('distanceRange', () => M.applyController())
  M.on('boundary', () => keepInBoundary())
  M.on('mapPadding', () => M.postCamera(true))

  // MARK: Methods

  M.method('setCamera', (a) => {
    if (a.animated) M.animateTo(a.camera, 0.8, 'easeinout')
    else {
      M.stopFlight()
      M.applyCamera(a.camera)
    }
  })
  M.method('animateCamera', (a) => M.animateTo(a.camera, (a.durationMs || 0) / 1000, M.norm(a.easing) === 'linear' ? 'linear' : 'easeinout'))
  M.method('flyCamera', (a) => M.startFlight(a.keyframes || [], a.start || Date.now() / 1000, a.loop))
  M.method('stopFlight', () => M.stopFlight())
  M.method('getCamera', () => M.munimCamera())
  M.method('getVisibleRegion', () => M.visibleRegion())

  function frameRectangle(rect, pad, seconds) {
    const viewer = M.viewer
    const camera = viewer.scene.camera
    const sphere = C.BoundingSphere.fromRectangle3D(rect, viewer.scene.globe.ellipsoid)
    const canvas = viewer.scene.canvas
    const p = pad || {}
    const usable = Math.max(0.2, Math.min((canvas.clientWidth - (p.left || 0) - (p.right || 0)) / Math.max(1, canvas.clientWidth), (canvas.clientHeight - (p.top || 0) - (p.bottom || 0)) / Math.max(1, canvas.clientHeight)))
    const fovy = camera.frustum.fovy || C.Math.toRadians(60)
    const fov = Math.min(fovy, camera.frustum.fov || fovy)
    const range = (sphere.radius / Math.sin(fov / 2)) / usable
    const center = C.Cartographic.fromCartesian(sphere.center)
    const cam = { latitude: M.toDeg(center.latitude), longitude: M.toDeg(center.longitude), distance: Math.max(50, range), pitch: 0, heading: M.munimCamera().heading }
    M.animateTo(cam, seconds, 'easeinout')
  }

  M.method('setRegion', (a) => {
    const r = a.region
    frameRectangle(M.rectangle(r), null, (a.durationMs || 0) / 1000)
  })

  M.fitCoordinates = function (coordinates, pad, animated) {
    if (!coordinates.length) return
    if (coordinates.length === 1) {
      const cam = M.munimCamera()
      M.animateTo(Object.assign(cam, { latitude: coordinates[0].latitude, longitude: coordinates[0].longitude }), animated ? 0.6 : 0, 'easeinout')
      return
    }
    const rect = C.Rectangle.fromCartographicArray(coordinates.map((c) => C.Cartographic.fromDegrees(c.longitude, c.latitude)))
    frameRectangle(rect, pad, animated ? 0.8 : 0)
  }

  M.method('fitToCoordinates', (a) => M.fitCoordinates(a.coordinates || [], a.padding, a.animated))

  M.method('pointForCoordinate', (a) => {
    const scene = M.viewer.scene
    const c = a.coordinate
    const p = C.SceneTransforms.worldToWindowCoordinates(scene, C.Cartesian3.fromDegrees(c.longitude, c.latitude, c.height != null ? c.height : M.groundHeight(c.latitude, c.longitude)))
    return p ? { x: p.x, y: p.y } : null
  })

  M.method('coordinateForPoint', (a) => {
    const position = M.pickGround(M.windowPosition(a.point), a.useDepth !== false)
    return position ? M.fromCartesian(position) : null
  })
})()
