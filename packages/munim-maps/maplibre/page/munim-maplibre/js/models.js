// munim-maps' 3D layer drawn inside GL JS: a custom style layer
// (`munim-3d`) that renders with three.js into the map's own WebGL context,
// with GL JS's camera, so models stay exactly on the map on the flat map,
// on the globe (and through the globe-to-Mercator transition) and on 3D
// terrain, and are hidden by terrain and the style's 3D buildings.
//
// - GLB / glTF models (the vehicle catalogue resolves to GLB here), turned
//   half a turn as on the other engines (glTF faces +Z, munim models face
//   north at heading 0), with heading, altitude (`ground` or `sea`), scale,
//   `screenSize`, `tint` (`paint…` materials), spin, embedded animations,
//   `motion` keyframes, `lift`, ground shadows, occluders (depth only);
// - built-in shapes (box, sphere, cylinder, cone, capsule, pyramid, gem);
// - pictures (avatars with border and badge), labels and stems, drawn on a
//   2D canvas over the map in the same frame (they face the camera and
//   stay readable, as on the other engines);
// - zones (fading walls with a ground outline) and paths (3D ribbons a
//   fixed number of points wide);
// - effects: exhaust, smoke, contrail.
//
// Each model is drawn in its own local frame (metres: x east, y up, z south)
// with the matrix GL JS gives custom layers for a model at that point
// (`getMatrixForModel`) times the frame's projection, blended between the
// globe and Mercator as GL JS blends its tiles, so precision holds at any
// zoom. three.js is loaded only when there is something to draw.
/* global maplibregl */
;(function () {
  'use strict'
  const M = window.munimMapLibre

  const FONT = '-apple-system, system-ui, "Segoe UI", Roboto, sans-serif'
  const EARTH_RADIUS = 6371008.8 // GL JS's

  let THREE // the module, once loaded
  let addons // { GLTFLoader, SkeletonUtils, RoomEnvironment }
  let threeLoading

  /** Loads three.js (same origin: CDN through the app, or bundled). */
  M.loadThree = function () {
    if (!threeLoading) {
      threeLoading = Promise.all([
        import('three'),
        import('three/addons/loaders/GLTFLoader.js'),
        import('three/addons/utils/SkeletonUtils.js'),
        import('three/addons/environments/RoomEnvironment.js'),
      ]).then(([three, gltf, skeleton, room]) => {
        THREE = three
        addons = { GLTFLoader: gltf.GLTFLoader, SkeletonUtils: skeleton, RoomEnvironment: room.RoomEnvironment }
        return THREE
      })
      threeLoading.catch((e) => {
        threeLoading = undefined
        M.error('could not load three.js for the 3D layer', e)
      })
    }
    return threeLoading
  }
  M.threeVersion = () => (THREE ? THREE.REVISION : '')

  // MARK: 4x4 matrices (column-major, float64)

  const mat = {
    create: () => {
      const m = new Float64Array(16)
      m[0] = m[5] = m[10] = m[15] = 1
      return m
    },
    from: (a) => Float64Array.from(a),
    multiply(a, b) {
      const out = new Float64Array(16)
      for (let c = 0; c < 4; c++) {
        for (let r = 0; r < 4; r++) {
          out[c * 4 + r] = a[r] * b[c * 4] + a[4 + r] * b[c * 4 + 1] + a[8 + r] * b[c * 4 + 2] + a[12 + r] * b[c * 4 + 3]
        }
      }
      return out
    },
    translate(m, x, y, z) {
      const t = mat.create()
      t[12] = x
      t[13] = y
      t[14] = z
      return mat.multiply(m, t)
    },
    scale(m, x, y, z) {
      const s = mat.create()
      s[0] = x
      s[5] = y
      s[10] = z
      return mat.multiply(m, s)
    },
    rotateX(m, a) {
      const r = mat.create()
      const c = Math.cos(a)
      const s = Math.sin(a)
      r[5] = c
      r[6] = s
      r[9] = -s
      r[10] = c
      return mat.multiply(m, r)
    },
    rotateY(m, a) {
      const r = mat.create()
      const c = Math.cos(a)
      const s = Math.sin(a)
      r[0] = c
      r[2] = -s
      r[8] = s
      r[10] = c
      return mat.multiply(m, r)
    },
    rotateZ(m, a) {
      const r = mat.create()
      const c = Math.cos(a)
      const s = Math.sin(a)
      r[0] = c
      r[1] = s
      r[4] = -s
      r[5] = c
      return mat.multiply(m, r)
    },
    mix(a, b, t) {
      const out = new Float64Array(16)
      for (let i = 0; i < 16; i++) out[i] = a[i] + (b[i] - a[i]) * t
      return out
    },
    apply(m, x, y, z, w = 1) {
      return [m[0] * x + m[4] * y + m[8] * z + m[12] * w, m[1] * x + m[5] * y + m[9] * z + m[13] * w, m[2] * x + m[6] * y + m[10] * z + m[14] * w, m[3] * x + m[7] * y + m[11] * z + m[15] * w]
    },
    invert(m) {
      const inv = new Float64Array(16)
      inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] + m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10]
      inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] - m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10]
      inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] + m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9]
      inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] - m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9]
      inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] - m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10]
      inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] + m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10]
      inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] - m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9]
      inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] + m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9]
      inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] + m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6]
      inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] - m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6]
      inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] + m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5]
      inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] - m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5]
      inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] - m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6]
      inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] + m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6]
      inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] - m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5]
      inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] + m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5]
      const det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12]
      if (!det) return undefined
      for (let i = 0; i < 16; i++) inv[i] /= det
      return inv
    },
  }
  M.mat = mat

  // MARK: Frames: a local frame (metres: x east, y up, z south) at a point

  /** GL JS's mercator matrix for a model at a point (`MercatorTransform.getMatrixForModel`). */
  function mercatorModel(lng, lat, altitude) {
    const c = maplibregl.MercatorCoordinate.fromLngLat([lng, lat], altitude)
    const s = c.meterInMercatorCoordinateUnits()
    let m = mat.translate(mat.create(), c.x, c.y, c.z)
    m = mat.rotateZ(m, Math.PI)
    m = mat.rotateX(m, Math.PI / 2)
    return mat.scale(m, -s, s, s)
  }

  /** GL JS's globe matrix for a model at a point (`VerticalPerspectiveTransform.getMatrixForModel`). */
  function globeModel(lng, lat, altitude) {
    const scale = 1 / EARTH_RADIUS
    let m = mat.rotateY(mat.create(), M.toRad(lng))
    m = mat.rotateX(m, -M.toRad(lat))
    m = mat.translate(m, 0, 0, 1 + altitude / EARTH_RADIUS)
    m = mat.rotateX(m, Math.PI / 2)
    return mat.scale(m, scale, scale, scale)
  }

  /** A point on the unit sphere GL JS draws the globe on, raised by `altitude` metres. */
  function spherePoint(lng, lat, altitude) {
    const l = M.toRad(lng)
    const f = M.toRad(lat)
    const r = 1 + altitude / EARTH_RADIUS
    return [Math.sin(l) * Math.cos(f) * r, Math.sin(f) * r, Math.cos(l) * Math.cos(f) * r]
  }

  /**
   * The frame's state this frame: what GL JS gave the custom layer
   * (`defaultProjectionData`), the viewport, and helpers for a point.
   */
  let frame

  function makeFrame(args, gl) {
    const data = args.defaultProjectionData
    const t = data.projectionTransition || 0
    const container = M.map.getContainer()
    return {
      t,
      main: mat.from(data.mainMatrix),
      fallback: mat.from(data.fallbackMatrix),
      plane: data.clippingPlane ? Array.from(data.clippingPlane) : [0, 0, 0, 0],
      width: container.clientWidth,
      height: container.clientHeight,
      bufferWidth: gl.drawingBufferWidth,
      bufferHeight: gl.drawingBufferHeight,
      fovy: args.fov == null ? M.fovy() : args.fov > Math.PI ? M.toRad(args.fov) : args.fov,
      zoom: M.map.getZoom(),
    }
  }

  /** The full matrix (local metres -> clip) for a frame at a point. */
  function frameMatrix(lng, lat, altitude) {
    const f = frame
    if (f.t <= 0) return mat.multiply(f.main, mercatorModel(lng, lat, altitude))
    const globe = mat.multiply(f.main, globeModel(lng, lat, altitude))
    if (f.t >= 0.999) return globe
    const flat = mat.multiply(f.fallback, mercatorModel(lng, lat, altitude))
    return mat.mix(flat, globe, f.t)
  }

  /** Whether a point is on the side of the globe that faces the camera. */
  function facesCamera(lng, lat, altitude) {
    if (!frame || frame.t <= 0) return true
    const p = spherePoint(lng, lat, altitude)
    const [a, b, c, d] = frame.plane
    return p[0] * a + p[1] * b + p[2] * c + d >= -1e-6
  }

  /** Clip -> CSS pixels; undefined behind the camera. */
  function toScreen(clip) {
    if (!(clip[3] > 1e-9)) return undefined
    return { x: ((clip[0] / clip[3] + 1) / 2) * frame.width, y: ((1 - clip[1] / clip[3]) / 2) * frame.height, w: clip[3] }
  }

  /** Where the camera's eye is in a frame's local metres (the projection's centre). */
  function eyeIn(matrix) {
    const inv = mat.invert(matrix)
    if (!inv) return [0, 1000, 0]
    const e = mat.apply(inv, 0, 0, 1, 0)
    if (Math.abs(e[3]) < 1e-12) return [0, 1000, 0]
    return [e[0] / e[3], e[1] / e[3], e[2] / e[3]]
  }

  /** Metres per CSS pixel at a distance from the eye. */
  function metersPerPixel(distance) {
    return (2 * distance * Math.tan(frame.fovy / 2)) / Math.max(1, frame.height)
  }

  // MARK: Ground

  function terrainOn() {
    return M.drawsTerrain()
  }

  /** The drawn ground height (terrain × exaggeration) at a point, 0 without terrain. */
  function groundAt(lng, lat) {
    if (!terrainOn()) return 0
    const h = M.map.queryTerrainElevation([lng, lat])
    return h == null || !isFinite(h) ? 0 : h
  }
  M.groundAt = groundAt

  function seaLevel(spec) {
    return M.norm(spec.altitudeReference) === 'sea'
  }

  // MARK: Motion

  function bearing(a, b) {
    const f1 = M.toRad(a.latitude)
    const f2 = M.toRad(b.latitude)
    const dl = M.toRad(b.longitude - a.longitude)
    const y = Math.sin(dl) * Math.cos(f2)
    const x = Math.cos(f1) * Math.sin(f2) - Math.sin(f1) * Math.cos(f2) * Math.cos(dl)
    return (M.toDeg(Math.atan2(y, x)) + 360) % 360
  }

  /** Where a model is now: its coordinate, or along its motion keyframes on the wall clock. */
  function pose(spec, now) {
    const motion = spec.motion || []
    let latitude = spec.latitude
    let longitude = spec.longitude
    let altitude = M.num(spec.altitude, 0)
    let heading = M.num(spec.heading, 0)
    if (motion.length) {
      const frames = motion
      const last = frames[frames.length - 1]
      let t = now - M.num(spec.motionStart, 0)
      if (spec.motionLoop && last.t > 0) t = ((t % last.t) + last.t) % last.t
      t = Math.max(frames[0].t, Math.min(last.t, t))
      let i = 0
      while (i < frames.length - 1 && frames[i + 1].t <= t) i++
      const a = frames[i]
      const b = frames[Math.min(i + 1, frames.length - 1)]
      const f = b.t > a.t ? (t - a.t) / (b.t - a.t) : 0
      latitude = a.latitude + (b.latitude - a.latitude) * f
      longitude = a.longitude + (b.longitude - a.longitude) * f
      altitude = M.num(a.altitude, 0) + (M.num(b.altitude, 0) - M.num(a.altitude, 0)) * f
      const explicitA = M.num(a.heading, -1) >= 0
      const explicitB = M.num(b.heading, -1) >= 0
      if (explicitA && explicitB) {
        const d = ((b.heading - a.heading + 540) % 360) - 180
        heading = a.heading + d * f
      } else if (explicitA) heading = a.heading
      else if (a !== b && (a.latitude !== b.latitude || a.longitude !== b.longitude)) heading = bearing(a, b)
      else if (i > 0) heading = bearing(frames[i - 1], a)
    }
    if (spec.spinDegreesPerSecond) heading += now * spec.spinDegreesPerSecond
    return { latitude, longitude, altitude, heading: ((heading % 360) + 360) % 360 }
  }

  function isAnimated(spec) {
    return (spec.motion && spec.motion.length > 0) || !!spec.spinDegreesPerSecond || M.norm(spec.effect || 'none') !== 'none'
  }

  // MARK: Assets

  const gltfs = new Map() // uri -> Promise<gltf>

  function loadGltf(uri) {
    if (!gltfs.has(uri)) {
      const loader = new addons.GLTFLoader()
      loader.setCrossOrigin('anonymous')
      const p = loader.loadAsync(M.resource(uri))
      p.catch(() => gltfs.delete(uri))
      gltfs.set(uri, p)
    }
    return gltfs.get(uri)
  }

  let shadowTexture
  function shadowMap() {
    if (shadowTexture) return shadowTexture
    const c = document.createElement('canvas')
    c.width = c.height = 64
    const ctx = c.getContext('2d')
    const g = ctx.createRadialGradient(32, 32, 0, 32, 32, 32)
    g.addColorStop(0, 'rgba(0,0,0,0.42)')
    g.addColorStop(0.6, 'rgba(0,0,0,0.18)')
    g.addColorStop(1, 'rgba(0,0,0,0)')
    ctx.fillStyle = g
    ctx.fillRect(0, 0, 64, 64)
    shadowTexture = new THREE.CanvasTexture(c)
    shadowTexture.colorSpace = THREE.SRGBColorSpace
    return shadowTexture
  }

  let puffTexture
  function puffMap() {
    if (puffTexture) return puffTexture
    const c = document.createElement('canvas')
    c.width = c.height = 64
    const ctx = c.getContext('2d')
    const g = ctx.createRadialGradient(32, 32, 0, 32, 32, 32)
    g.addColorStop(0, 'rgba(255,255,255,1)')
    g.addColorStop(0.4, 'rgba(255,255,255,0.55)')
    g.addColorStop(1, 'rgba(255,255,255,0)')
    ctx.fillStyle = g
    ctx.fillRect(0, 0, 64, 64)
    puffTexture = new THREE.CanvasTexture(c)
    return puffTexture
  }

  // MARK: Lights

  function makeLights(scene) {
    const ambient = new THREE.HemisphereLight(0xffffff, 0x8a8a80, 1.1)
    const sun = new THREE.DirectionalLight(0xffffff, 2.4)
    // Afternoon sun from the south-west, as on the other engines.
    sun.position.set(-0.354, 0.866, 0.354)
    sun.target.position.set(0, 0, 0)
    scene.add(ambient, sun, sun.target)
    return { ambient, sun }
  }

  function applyLighting(lights, night) {
    lights.ambient.intensity = night ? 0.45 : 1.1
    lights.ambient.color.set(night ? 0x99adff : 0xffffff)
    lights.sun.intensity = night ? 0.55 : 2.4
    lights.sun.color.set(night ? 0xb3c7ff : 0xffffff)
  }

  function night() {
    const l = M.norm(M.state.lighting || 'auto')
    return l === 'night' || (l === 'auto' && M.isDark())
  }

  // MARK: Model items

  let items = new Map() // id -> item
  let zones = []
  let paths = []
  let layerAdded = false
  let renderer
  let camera
  let environment

  function buildKey(spec) {
    return JSON.stringify([spec.uri, spec.tintColor, spec.shape, spec.width, spec.height, spec.length, spec.color, spec.emissive, spec.imageUri, spec.imageBorderColor, spec.imageBorderWidth, spec.imageBadge, spec.label, spec.effect, spec.effectOrigins, spec.groundShadow, spec.occluder, spec.playAnimations])
  }

  function isPicture(spec) {
    return !!spec.imageUri
  }

  function shapeMesh(spec, item) {
    const shape = M.norm(spec.shape || 'box')
    const w = Math.max(0.01, M.num(spec.width, 10))
    const h = Math.max(0.01, M.num(spec.height, 10))
    const l = Math.max(0.01, M.num(spec.length, 10))
    const c = M.rgba(spec.color, '#0A84FF')
    const material = new THREE.MeshStandardMaterial({ color: new THREE.Color(c.r, c.g, c.b).convertSRGBToLinear(), roughness: 0.55, metalness: 0.05, transparent: c.a < 1, opacity: c.a })
    if (spec.emissive) {
      material.emissive = material.color.clone()
      material.emissiveIntensity = 0.85
    }
    let geometry
    switch (shape) {
      case 'sphere':
        geometry = new THREE.SphereGeometry(0.5, 32, 16)
        geometry.scale(w, h, l)
        break
      case 'capsule':
        geometry = new THREE.SphereGeometry(0.5, 32, 16)
        geometry.scale(w, h, l)
        break
      case 'cylinder':
        geometry = new THREE.CylinderGeometry(w / 2, w / 2, h, 32)
        geometry.scale(1, 1, l / w)
        break
      case 'cone':
        geometry = new THREE.ConeGeometry(w / 2, h, 32)
        geometry.scale(1, 1, l / w)
        break
      case 'pyramid':
        geometry = new THREE.ConeGeometry(Math.SQRT1_2, h, 4)
        geometry.rotateY(Math.PI / 4)
        geometry.scale(w, 1, l)
        break
      case 'gem':
        geometry = new THREE.OctahedronGeometry(0.5)
        geometry.scale(w, h, l)
        break
      case 'box':
      default:
        geometry = new THREE.BoxGeometry(w, h, l)
    }
    geometry.translate(0, h / 2, 0)
    item.height = h
    item.radius = Math.max(w, l, h) / 2
    item.center = h / 2
    return new THREE.Mesh(geometry, material)
  }

  function tint(object, color) {
    if (!color) return
    const c = M.rgba(color)
    if (!c) return
    object.traverse((o) => {
      if (!o.isMesh) return
      const list = Array.isArray(o.material) ? o.material : [o.material]
      const next = list.map((m) => {
        if (!m || !/^paint/i.test(m.name || '')) return m
        const copy = m.clone()
        copy.color = new THREE.Color(c.r, c.g, c.b).convertSRGBToLinear()
        if (c.a < 1) {
          copy.transparent = true
          copy.opacity = c.a
        }
        return copy
      })
      o.material = Array.isArray(o.material) ? next : next[0]
    })
  }

  function makeItem(spec) {
    const scene = new THREE.Scene()
    const lights = makeLights(scene)
    const item = { spec, key: buildKey(spec), scene, lights, root: new THREE.Group(), body: new THREE.Group(), height: Math.max(0.01, M.num(spec.height, 10)), radius: 5, center: 5, loaded: false, cancelled: false }
    // root: heading and the frame; body: the model (scaled for screenSize).
    item.root.add(item.body)
    scene.add(item.root)
    if (spec.occluder) item.depthOnly = true
    if (isPicture(spec)) {
      item.loaded = true
      buildPicture(item)
    } else if (spec.uri) {
      loadGltf(spec.uri)
        .then((gltf) => {
          if (item.cancelled) return
          const object = addons.SkeletonUtils.clone(gltf.scene)
          // glTF faces +Z; munim models face north (-Z) at heading 0.
          object.rotation.y = Math.PI
          tint(object, spec.tintColor)
          if (item.depthOnly) {
            object.traverse((o) => {
              if (o.isMesh) {
                o.material = new THREE.MeshBasicMaterial({ colorWrite: false })
              }
            })
          }
          const box = new THREE.Box3().setFromObject(object)
          const size = box.getSize(new THREE.Vector3())
          item.height = Math.max(0.01, size.y)
          item.radius = Math.max(size.x, size.y, size.z) / 2
          item.center = (box.min.y + box.max.y) / 2
          item.body.add(object)
          if (spec.playAnimations !== false && gltf.animations && gltf.animations.length) {
            item.mixer = new THREE.AnimationMixer(object)
            for (const clip of gltf.animations) item.mixer.clipAction(clip).play()
          }
          item.loaded = true
          M.repaint()
        })
        .catch((e) => M.error(`could not load model ${spec.id}`, e))
    } else if (M.norm(spec.shape || 'box') !== 'none') {
      const mesh = shapeMesh(spec, item)
      if (item.depthOnly) mesh.material = new THREE.MeshBasicMaterial({ colorWrite: false })
      item.body.add(mesh)
      item.loaded = true
    } else {
      item.loaded = true
      item.height = Math.max(0.01, M.num(spec.height, 10))
      item.radius = Math.max(M.num(spec.width, 10), M.num(spec.length, 10)) / 2
    }
    if (spec.groundShadow && !isPicture(spec) && !spec.occluder && M.norm(spec.effect) !== 'smoke') {
      const shadow = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), new THREE.MeshBasicMaterial({ map: shadowMap(), transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2, polygonOffsetUnits: -2 }))
      shadow.rotation.x = -Math.PI / 2
      shadow.renderOrder = -1
      item.shadow = shadow
      item.scene.add(shadow)
    }
    if (spec.label) buildLabel(item)
    buildEffects(item)
    return item
  }

  function disposeItem(item) {
    item.cancelled = true
    item.scene.traverse((o) => {
      if (o.geometry) o.geometry.dispose()
      const list = o.material ? (Array.isArray(o.material) ? o.material : [o.material]) : []
      for (const m of list) if (m !== shadowTexture) m.dispose()
    })
  }

  // MARK: Pictures, labels, stems (2D, in the same frame)

  let overlay // { canvas, ctx }

  function ensureOverlay() {
    if (overlay) return overlay
    const container = M.map.getCanvasContainer()
    const canvas = document.createElement('canvas')
    canvas.className = 'munim-3d-overlay'
    const mapCanvas = M.map.getCanvas()
    container.insertBefore(canvas, mapCanvas.nextSibling)
    overlay = { canvas, ctx: canvas.getContext('2d'), width: 0, height: 0, scale: 1, drawn: false }
    return overlay
  }

  function sizeOverlay() {
    const o = ensureOverlay()
    const w = frame.width
    const h = frame.height
    const scale = Math.min(3, window.devicePixelRatio || 1)
    if (o.width !== w || o.height !== h || o.scale !== scale) {
      o.canvas.width = Math.round(w * scale)
      o.canvas.height = Math.round(h * scale)
      o.canvas.style.width = `${w}px`
      o.canvas.style.height = `${h}px`
      o.width = w
      o.height = h
      o.scale = scale
    }
    o.ctx.setTransform(o.scale, 0, 0, o.scale, 0, 0)
    o.ctx.clearRect(0, 0, w, h)
    return o
  }

  function buildPicture(item) {
    const spec = item.spec
    const size = M.num(spec.screenSize, 0) > 0 ? spec.screenSize : 44
    const border = M.num(spec.imageBorderWidth, 3)
    const pad = 4
    const badgeHeight = spec.imageBadge ? 18 : 0
    const w = size + pad * 2
    const h = size + pad * 2 + badgeHeight / 2
    const { canvas, ctx } = M.canvas(w, h)
    item.picture = { canvas, width: w, height: h, centerY: pad + size / 2, size }
    const draw = (img) => {
      const cx = w / 2
      const cy = pad + size / 2
      ctx.clearRect(0, 0, w, h)
      ctx.shadowColor = 'rgba(0,0,0,0.35)'
      ctx.shadowBlur = 4
      ctx.beginPath()
      ctx.arc(cx, cy, size / 2, 0, Math.PI * 2)
      ctx.fillStyle = spec.imageBorderColor ? M.css(spec.imageBorderColor) : '#ffffff'
      ctx.fill()
      ctx.shadowBlur = 0
      ctx.save()
      ctx.beginPath()
      ctx.arc(cx, cy, size / 2 - border, 0, Math.PI * 2)
      ctx.clip()
      if (img) {
        const inner = size - border * 2
        const ratio = Math.max(inner / img.width, inner / img.height)
        const sw = inner / ratio
        const sh = inner / ratio
        ctx.drawImage(img, (img.width - sw) / 2, (img.height - sh) / 2, sw, sh, cx - inner / 2, cy - inner / 2, inner, inner)
      } else {
        ctx.fillStyle = M.css(spec.color, '#0A84FF')
        ctx.fill()
      }
      ctx.restore()
      if (spec.imageBadge) {
        ctx.font = `700 11px ${FONT}`
        const bw = Math.max(22, ctx.measureText(spec.imageBadge).width + 10)
        const by = pad + size - 6
        ctx.fillStyle = '#1c1c1e'
        M.roundRect(ctx, cx - bw / 2, by, bw, badgeHeight, badgeHeight / 2)
        ctx.fill()
        ctx.fillStyle = '#ffffff'
        ctx.textAlign = 'center'
        ctx.textBaseline = 'middle'
        ctx.fillText(spec.imageBadge, cx, by + badgeHeight / 2 + 0.5)
      }
      M.repaint()
    }
    draw(undefined)
    M.loadImage(spec.imageUri)
      .then((img) => !item.cancelled && draw(img))
      .catch((e) => M.error(`model ${spec.id} picture`, e))
  }

  function buildLabel(item) {
    const text = item.spec.label
    const probe = M.canvas(1, 1).ctx
    probe.font = `600 13px ${FONT}`
    const w = Math.ceil(probe.measureText(text).width) + 16
    const h = 22
    const { canvas, ctx } = M.canvas(w + 4, h + 4)
    ctx.shadowColor = 'rgba(0,0,0,0.25)'
    ctx.shadowBlur = 3
    ctx.fillStyle = 'rgba(28,28,30,0.82)'
    M.roundRect(ctx, 2, 2, w, h, h / 2)
    ctx.fill()
    ctx.shadowBlur = 0
    ctx.fillStyle = '#ffffff'
    ctx.font = `600 13px ${FONT}`
    ctx.textAlign = 'center'
    ctx.textBaseline = 'middle'
    ctx.fillText(text, 2 + w / 2, 2 + h / 2 + 0.5)
    item.labelImage = { canvas, width: w + 4, height: h + 4 }
  }

  // MARK: Effects (exhaust, smoke, contrail)

  function parseOrigins(value) {
    if (!value) return []
    if (Array.isArray(value)) return value.map((p) => (Array.isArray(p) ? p.map(Number) : [M.num(p.x, 0), M.num(p.y, 0), M.num(p.z, 0)]))
    return String(value)
      .split(';')
      .map((p) => p.split(',').map(Number))
      .filter((p) => p.length === 3 && p.every((n) => isFinite(n)))
  }

  const PUFF_VERTEX = `
    attribute float size;
    attribute vec4 tint;
    uniform float pxPerMeter;
    varying vec4 vTint;
    void main() {
      vTint = tint;
      vec4 clip = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
      gl_Position = clip;
      gl_PointSize = clamp(size * pxPerMeter, 1.0, 256.0);
    }`
  const PUFF_FRAGMENT = `
    uniform sampler2D map;
    varying vec4 vTint;
    void main() {
      vec4 t = texture2D(map, gl_PointCoord);
      gl_FragColor = vec4(vTint.rgb, vTint.a * t.a);
    }`

  function buildEffects(item) {
    const spec = item.spec
    const effect = M.norm(spec.effect || 'none')
    if (effect === 'none' || isPicture(spec)) return
    const origins = parseOrigins(spec.effectOrigins)
    const list = origins.length ? origins : [[0, 0, 0]]
    if (effect === 'contrail') {
      item.trails = list.map((origin) => ({ origin, samples: [] }))
      return
    }
    const smoke = effect === 'smoke'
    const count = smoke ? 90 : 140
    const geometry = new THREE.BufferGeometry()
    geometry.setAttribute('position', new THREE.BufferAttribute(new Float32Array(count * 3), 3))
    geometry.setAttribute('size', new THREE.BufferAttribute(new Float32Array(count), 1))
    geometry.setAttribute('tint', new THREE.BufferAttribute(new Float32Array(count * 4), 4))
    const material = new THREE.ShaderMaterial({
      uniforms: { map: { value: puffMap() }, pxPerMeter: { value: 1 } },
      vertexShader: PUFF_VERTEX,
      fragmentShader: PUFF_FRAGMENT,
      transparent: true,
      depthWrite: false,
      blending: smoke ? THREE.NormalBlending : THREE.AdditiveBlending,
    })
    const points = new THREE.Points(geometry, material)
    points.frustumCulled = false
    item.particles = { points, smoke, origins: smoke ? [[0, 0, 0]] : list, list: [], count, last: 0 }
    item.root.add(points)
  }

  /** Steps the particles (in the model's frame, before scaling) and writes them. */
  function stepParticles(item, now, scale, pxPerMeter) {
    const p = item.particles
    if (!p) return
    const spec = item.spec
    const intensity = Math.max(0, Math.min(1, M.num(spec.effectIntensity, 1)))
    const dt = Math.min(0.1, p.last ? now - p.last : 0)
    p.last = now
    const width = Math.max(1, M.num(spec.width, 10))
    const height = Math.max(1, M.num(spec.height, 10))
    const rate = (p.smoke ? 14 : 70) * intensity * p.origins.length
    p.carry = (p.carry || 0) + rate * dt
    while (p.carry >= 1 && p.list.length < p.count) {
      p.carry -= 1
      const o = p.origins[Math.floor(Math.random() * p.origins.length)]
      if (p.smoke) {
        const a = Math.random() * Math.PI * 2
        const r = (Math.random() * width) / 2
        p.list.push({ x: Math.cos(a) * r, y: 0, z: Math.sin(a) * r, vx: (Math.random() - 0.5) * 0.6, vy: height / 6 + Math.random() * (height / 6), vz: (Math.random() - 0.5) * 0.6, age: 0, life: 3 + Math.random() * 3, size: width / 5 })
      } else {
        const spread = 0.22
        p.list.push({ x: o[0] * scale, y: o[1] * scale, z: o[2] * scale, vx: (Math.random() - 0.5) * spread * 30 * scale, vy: -(20 + Math.random() * 25) * scale, vz: (Math.random() - 0.5) * spread * 30 * scale, age: 0, life: 0.35 + Math.random() * 0.5, size: 2.2 * scale })
      }
    }
    if (p.carry > 1) p.carry = 1
    const pos = p.points.geometry.attributes.position.array
    const size = p.points.geometry.attributes.size.array
    const color = p.points.geometry.attributes.tint.array
    let n = 0
    p.list = p.list.filter((q) => (q.age += dt) < q.life)
    for (const q of p.list) {
      q.x += q.vx * dt
      q.y += q.vy * dt
      q.z += q.vz * dt
      if (p.smoke) q.vy *= 0.995
      const f = q.age / q.life
      pos[n * 3] = q.x
      pos[n * 3 + 1] = q.y
      pos[n * 3 + 2] = q.z
      size[n] = q.size * (p.smoke ? 1 + f * 3 : 1 + f * 2)
      if (p.smoke) {
        const g = 0.78 - f * 0.18
        color.set([g, g, g, 0.5 * (1 - f) * intensity], n * 4)
      } else {
        color.set([1, 0.82 - f * 0.4, 0.45 - f * 0.3, 0.9 * (1 - f) * intensity], n * 4)
      }
      n++
    }
    for (let i = n; i < p.count; i++) size[i] = 0
    p.points.geometry.attributes.position.needsUpdate = true
    p.points.geometry.attributes.size.needsUpdate = true
    p.points.geometry.attributes.tint.needsUpdate = true
    p.points.geometry.setDrawRange(0, n)
    p.points.material.uniforms.pxPerMeter.value = pxPerMeter
  }

  // MARK: Ribbons (paths, zone outlines, contrails): screen-space width, globe/Mercator blended

  const RIBBON_VERTEX = `
    attribute vec3 merc;
    attribute vec3 otherMerc;
    attribute vec3 otherGlobe;
    attribute float side;
    attribute float ends;
    uniform mat4 uMerc;
    uniform mat4 uGlobe;
    uniform float uT;
    uniform vec2 uViewport;
    uniform float uWidth;
    vec4 project(vec3 m, vec3 g) {
      vec4 a = uMerc * vec4(m, 1.0);
      if (uT <= 0.0) return a;
      vec4 b = uGlobe * vec4(g, 1.0);
      return mix(a, b, uT);
    }
    void main() {
      vec4 self = project(merc, position);
      vec4 other = project(otherMerc, otherGlobe);
      vec2 a = self.xy / max(self.w, 1e-6) * uViewport;
      vec2 b = other.xy / max(other.w, 1e-6) * uViewport;
      vec2 dir = normalize((b - a) * ends + vec2(1e-6, 0.0));
      vec2 normal = vec2(-dir.y, dir.x);
      vec2 offset = normal * side * uWidth * 0.5 / uViewport;
      gl_Position = self + vec4(offset * self.w, 0.0, 0.0);
    }`
  const RIBBON_FRAGMENT = `
    uniform vec4 uColor;
    void main() { gl_FragColor = uColor; }`

  /**
   * A ribbon through points (each `{ g: [x,y,z] globe-local, m: [x,y,z] mercator-local }`).
   * Every segment is a quad of four vertices that know the other end.
   */
  function ribbonGeometry(points, closed) {
    const list = closed && points.length > 2 ? [...points, points[0]] : points
    const segments = Math.max(0, list.length - 1)
    const n = segments * 4
    const globe = new Float32Array(n * 3)
    const merc = new Float32Array(n * 3)
    const otherGlobe = new Float32Array(n * 3)
    const otherMerc = new Float32Array(n * 3)
    const side = new Float32Array(n)
    const ends = new Float32Array(n)
    const index = []
    for (let i = 0; i < segments; i++) {
      const a = list[i]
      const b = list[i + 1]
      const verts = [
        [a, b, 1, 1],
        [a, b, -1, 1],
        [b, a, 1, -1],
        [b, a, -1, -1],
      ]
      verts.forEach(([self, other, s, e], k) => {
        const v = i * 4 + k
        globe.set(self.g, v * 3)
        merc.set(self.m, v * 3)
        otherGlobe.set(other.g, v * 3)
        otherMerc.set(other.m, v * 3)
        side[v] = s
        ends[v] = e
      })
      const v = i * 4
      index.push(v, v + 1, v + 2, v + 1, v + 3, v + 2)
    }
    const geometry = new THREE.BufferGeometry()
    geometry.setAttribute('position', new THREE.BufferAttribute(globe, 3))
    geometry.setAttribute('merc', new THREE.BufferAttribute(merc, 3))
    geometry.setAttribute('otherGlobe', new THREE.BufferAttribute(otherGlobe, 3))
    geometry.setAttribute('otherMerc', new THREE.BufferAttribute(otherMerc, 3))
    geometry.setAttribute('side', new THREE.BufferAttribute(side, 1))
    geometry.setAttribute('ends', new THREE.BufferAttribute(ends, 1))
    geometry.setIndex(index)
    return geometry
  }

  function ribbonMaterial(color, width) {
    const c = M.rgba(color, '#FFFFFF')
    return new THREE.ShaderMaterial({
      uniforms: {
        uMerc: { value: new THREE.Matrix4() },
        uGlobe: { value: new THREE.Matrix4() },
        uT: { value: 0 },
        uViewport: { value: new THREE.Vector2(1, 1) },
        uWidth: { value: width },
        uColor: { value: new THREE.Vector4(c.r, c.g, c.b, c.a) },
      },
      vertexShader: RIBBON_VERTEX,
      fragmentShader: RIBBON_FRAGMENT,
      transparent: c.a < 1,
      depthWrite: false,
      side: THREE.DoubleSide,
    })
  }

  // Walls (zones): world-space quads, both projections.
  const WALL_VERTEX = `
    attribute vec3 merc;
    attribute float fade;
    uniform mat4 uMerc;
    uniform mat4 uGlobe;
    uniform float uT;
    varying float vFade;
    void main() {
      vFade = fade;
      vec4 a = uMerc * vec4(merc, 1.0);
      gl_Position = uT <= 0.0 ? a : mix(a, uGlobe * vec4(position, 1.0), uT);
    }`
  const WALL_FRAGMENT = `
    uniform vec4 uColor;
    varying float vFade;
    void main() {
      float band = vFade < 0.04 ? 1.0 : 0.0;
      float alpha = mix(min(1.0, uColor.a * 2.0), 0.0, vFade);
      gl_FragColor = vec4(uColor.rgb, max(alpha, band * 0.9));
    }`

  /** A point of a path or zone in a frame: globe-local and mercator-local metres. */
  function localPoint(frameAt, lng, lat, altitude) {
    // Globe: exact (the globe is a sphere in GL JS's own units).
    const s = spherePoint(lng, lat, altitude)
    const g = mat.apply(frameAt.globeInverse, s[0], s[1], s[2])
    // Mercator: the frame's mercator matrix, inverted.
    const c = maplibregl.MercatorCoordinate.fromLngLat([lng, lat], altitude)
    const m = mat.apply(frameAt.mercInverse, c.x, c.y, c.z)
    return { g: [g[0], g[1], g[2]], m: [m[0], m[1], m[2]] }
  }

  function frameAt(lng, lat, altitude) {
    const merc = mercatorModel(lng, lat, altitude)
    const globe = globeModel(lng, lat, altitude)
    return { lng, lat, altitude, merc, globe, mercInverse: mat.invert(merc), globeInverse: mat.invert(globe) }
  }

  /** Sets a ribbon / wall material's matrices for its frame this frame. */
  function setFrameUniforms(material, f) {
    const u = material.uniforms
    const mercMatrix = frame.t > 0 ? mat.multiply(frame.fallback, f.merc) : mat.multiply(frame.main, f.merc)
    u.uMerc.value.fromArray(mercMatrix)
    u.uT.value = frame.t >= 0.999 ? 1 : frame.t
    if (frame.t > 0) u.uGlobe.value.fromArray(mat.multiply(frame.main, f.globe))
    if (u.uViewport) u.uViewport.value.set(frame.width / 2, frame.height / 2)
  }

  // MARK: Zones and paths

  function buildZone(zone) {
    const points = zone.points || zone.coordinates || []
    if (points.length < 3) return undefined
    const ground = (p) => groundAt(p.longitude, p.latitude)
    const origin = frameAt(points[0].longitude, points[0].latitude, ground(points[0]))
    const height = M.num(zone.height, 40)
    const ring = [...points, points[0]]
    const globe = []
    const merc = []
    const fade = []
    const index = []
    ring.forEach((p, i) => {
      const g0 = ground(p)
      const lo = localPoint(origin, p.longitude, p.latitude, g0)
      const hi = localPoint(origin, p.longitude, p.latitude, g0 + height)
      globe.push(...lo.g, ...hi.g)
      merc.push(...lo.m, ...hi.m)
      fade.push(0, 1)
      if (i > 0) {
        const v = i * 2
        index.push(v - 2, v - 1, v, v - 1, v + 1, v)
      }
    })
    const geometry = new THREE.BufferGeometry()
    geometry.setAttribute('position', new THREE.BufferAttribute(new Float32Array(globe), 3))
    geometry.setAttribute('merc', new THREE.BufferAttribute(new Float32Array(merc), 3))
    geometry.setAttribute('fade', new THREE.BufferAttribute(new Float32Array(fade), 1))
    geometry.setIndex(index)
    const c = M.rgba(zone.color, '#0A84FF40')
    const material = new THREE.ShaderMaterial({
      uniforms: { uMerc: { value: new THREE.Matrix4() }, uGlobe: { value: new THREE.Matrix4() }, uT: { value: 0 }, uColor: { value: new THREE.Vector4(c.r, c.g, c.b, c.a) } },
      vertexShader: WALL_VERTEX,
      fragmentShader: WALL_FRAGMENT,
      transparent: true,
      depthWrite: false,
      side: THREE.DoubleSide,
    })
    const wall = new THREE.Mesh(geometry, material)
    wall.frustumCulled = false
    const outline = new THREE.Mesh(
      ribbonGeometry(
        points.map((p) => localPoint(origin, p.longitude, p.latitude, ground(p) + 0.3)),
        true
      ),
      ribbonMaterial(M.opaque(zone.color, '#0A84FF'), 2)
    )
    outline.frustumCulled = false
    const scene = new THREE.Scene()
    scene.add(wall, outline)
    return { id: zone.id, kind: 'zone', spec: zone, origin, scene, materials: [material, outline.material], visible: zone.visible !== false, groundKey: groundKey(points) }
  }

  function buildPath(path) {
    const points = path.points || (path.coordinates || []).map((c, i) => ({ latitude: c.latitude, longitude: c.longitude, altitude: (path.altitudes || [])[i] || 0 }))
    if (points.length < 2) return undefined
    const sea = seaLevel(path)
    const height = (p) => (sea ? M.num(p.altitude, 0) : groundAt(p.longitude, p.latitude) + M.num(p.altitude, 0) + 0.3)
    const origin = frameAt(points[0].longitude, points[0].latitude, height(points[0]))
    const local = points.map((p) => localPoint(origin, p.longitude, p.latitude, height(p)))
    const mesh = new THREE.Mesh(ribbonGeometry(local, !!path.closed), ribbonMaterial(path.color || '#FFFFFF', M.num(path.width, 2)))
    mesh.frustumCulled = false
    const scene = new THREE.Scene()
    scene.add(mesh)
    return { id: path.id, kind: 'path', spec: path, origin, scene, materials: [mesh.material], visible: path.visible !== false, groundKey: sea ? '' : groundKey(points) }
  }

  function groundKey(points) {
    if (!terrainOn()) return 'flat'
    let sum = 0
    for (const p of points) sum += groundAt(p.longitude, p.latitude)
    return `t:${Math.round(sum)}`
  }

  function disposeScene(scene) {
    scene.traverse((o) => {
      if (o.geometry) o.geometry.dispose()
      if (o.material) o.material.dispose()
    })
  }

  function rebuildZonesAndPaths() {
    if (!THREE) return
    for (const z of zones) disposeScene(z.scene)
    for (const p of paths) disposeScene(p.scene)
    zones = (M.state.zones || []).map(buildZone).filter(Boolean)
    paths = (M.state.paths || []).map(buildPath).filter(Boolean)
    M.repaint()
  }

  // MARK: The custom layer

  const customLayer = {
    id: 'munim-3d',
    type: 'custom',
    renderingMode: '3d',
    onAdd(map, gl) {
      if (!renderer || renderer.getContext() !== gl) {
        renderer = new THREE.WebGLRenderer({ canvas: map.getCanvas(), context: gl, antialias: true })
        renderer.autoClear = false
        renderer.outputColorSpace = THREE.SRGBColorSpace
        const pmrem = new THREE.PMREMGenerator(renderer)
        environment = pmrem.fromScene(new addons.RoomEnvironment(), 0.04).texture
        pmrem.dispose()
        renderer.resetState()
      }
      camera = camera || new THREE.Camera()
    },
    render(gl, args) {
      try {
        draw(gl, args)
      } catch (e) {
        if (!draw.failed) {
          draw.failed = true
          M.error('the 3D layer could not draw', e)
        }
      }
    },
    onRemove() {},
  }

  /**
   * Where the 3D layer goes: under the style's 3D buildings, so buildings in
   * front of a model hide it (they test against its depth) but translucent
   * ones still show it through them; with `occlusion="buildings"`, over
   * everything (buildings in front hide models completely).
   */
  function slot(map) {
    if (M.norm(M.state.occlusion) === 'buildings') return undefined
    const layer = (map.getStyle().layers || []).find((l) => l.type === 'fill-extrusion')
    return layer ? layer.id : undefined
  }

  function hasContent() {
    return items.size > 0 || zones.length > 0 || paths.length > 0 || (M.state.models || []).length > 0 || (M.state.zones || []).length > 0 || (M.state.paths || []).length > 0
  }

  function ensureLayer() {
    const map = M.map
    if (!map || !THREE || !M.styleLoaded(map)) return
    if (map.getLayer('munim-3d')) return
    map.addLayer(customLayer, slot(map))
    layerAdded = true
  }

  /** Draws one frame of every item (inside GL JS's render pass). */
  function draw(gl, args) {
    frame = makeFrame(args, gl)
    const now = Date.now() / 1000
    const o = sizeOverlay()
    const ctx = o.ctx
    const camDistance = M.distanceForZoom(frame.zoom, M.map.getCenter().lat, frame.height)
    const hideAll = camDistance > M.num(M.state.maxCameraDistance, 50000)
    renderer.resetState()
    renderer.setViewport(0, 0, frame.bufferWidth, frame.bufferHeight)
    // GL JS draws the globe with its own depth values (they clip the far
    // side), not the camera's: on the globe models draw over the map.
    if (frame.t > 0) {
      gl.clear(gl.DEPTH_BUFFER_BIT)
    }
    const lit = night()
    let animating = false
    const pictures = []
    const ordered = [...items.values()].sort((a, b) => (b.depthOnly ? 1 : 0) - (a.depthOnly ? 1 : 0))
    for (const item of ordered) {
      const spec = item.spec
      item.screen = undefined
      if (isAnimated(spec) || item.mixer || item.particles || item.trails) animating = true
      if (!item.loaded || spec.visible === false || hideAll) continue
      const p = pose(spec, now)
      const ground = groundAt(p.longitude, p.latitude)
      const base = seaLevel(spec) ? p.altitude : ground + p.altitude
      // First the frame at the model's point, to find the eye and the scale.
      let matrix = frameMatrix(p.longitude, p.latitude, base)
      let eye = eyeIn(matrix)
      const distance = Math.hypot(eye[0], eye[1], eye[2])
      const mpp = metersPerPixel(distance)
      const lift = M.num(spec.liftPoints, 0) * mpp
      const z = base + lift
      if (lift) {
        matrix = frameMatrix(p.longitude, p.latitude, z)
        eye = eyeIn(matrix)
      }
      if (!facesCamera(p.longitude, p.latitude, z)) continue
      let scale = M.num(spec.scale, 1)
      const screenSize = M.num(spec.screenSize, 0)
      if (screenSize > 0 && !isPicture(spec)) scale = (screenSize * mpp) / Math.max(0.01, item.height) * M.num(spec.scale, 1)
      item.scale = scale
      const anchor = toScreen(mat.apply(matrix, 0, 0, 0))
      const top = toScreen(mat.apply(matrix, 0, isPicture(spec) ? 0 : item.height * scale, 0))
      item.screen = { anchor, top, mpp, radiusPx: (item.radius * scale) / mpp, centerPx: toScreen(mat.apply(matrix, 0, item.center * scale, 0)) }
      item.frame = { lng: p.longitude, lat: p.latitude, z, ground }
      // Stems from the ground up to floating models.
      if (spec.stem && z - ground > 0.5 && anchor) {
        const g = toScreen(mat.apply(matrix, 0, ground - z, 0))
        if (g) pictures.push({ order: anchor.w, draw: () => drawStem(ctx, g, anchor, spec.stemColor) })
      }
      if (isPicture(spec)) {
        if (anchor && item.picture) pictures.push({ order: anchor.w, draw: () => drawPicture(ctx, item, anchor) })
        if (anchor && item.labelImage) pictures.push({ order: anchor.w - 1e-3, draw: () => drawLabel(ctx, item.labelImage, anchor.x, anchor.y - (item.picture ? item.picture.size / 2 : 22) - 6) })
        continue
      }
      if (item.labelImage && top) pictures.push({ order: top.w - 1e-3, draw: () => drawLabel(ctx, item.labelImage, top.x, top.y - 4) })
      // three.js: projection = the frame's matrix moved to the eye, so the
      // eye is where lighting and reflections expect it.
      item.root.rotation.set(0, M.toRad(-p.heading), 0)
      item.body.scale.setScalar(scale)
      if (item.mixer) item.mixer.update(Math.min(0.1, item.lastTime ? now - item.lastTime : 0))
      item.lastTime = now
      if (item.shadow) {
        item.shadow.position.set(0, ground - z + 0.05, 0)
        const r = Math.max(0.5, item.radius * scale * 0.9)
        item.shadow.scale.set(r * 2, r * 2, 1)
        item.shadow.visible = !seaLevel(spec) || z - ground < 200
      }
      stepParticles(item, now, scale, 1 / mpp)
      applyLighting(item.lights, lit)
      item.scene.environment = environment
      item.scene.environmentIntensity = lit ? 0.15 : 0.55
      camera.position.set(eye[0], eye[1], eye[2])
      camera.updateMatrixWorld(true)
      camera.projectionMatrix.fromArray(mat.multiply(matrix, mat.translate(mat.create(), eye[0], eye[1], eye[2])))
      camera.projectionMatrixInverse.copy(camera.projectionMatrix).invert()
      renderer.render(item.scene, camera)
      // Contrails: a ribbon through the last seconds of positions.
      if (item.trails) drawTrails(item, now, p, z, scale)
    }
    // Zones and paths.
    camera.position.set(0, 0, 0)
    camera.updateMatrixWorld(true)
    camera.projectionMatrix.identity()
    camera.projectionMatrixInverse.identity()
    for (const list of [zones, paths]) {
      for (const z of list) {
        if (!z.visible || hideAll) continue
        if (!facesCamera(z.origin.lng, z.origin.lat, z.origin.altitude) && frame.t >= 0.999) continue
        for (const m of z.materials) setFrameUniforms(m, z.origin)
        renderer.render(z.scene, camera)
      }
    }
    renderer.resetState()
    // Pictures, labels and stems: far ones first.
    pictures.sort((a, b) => b.order - a.order)
    for (const p of pictures) p.draw()
    if (animating) M.map.triggerRepaint()
    checkGround()
  }

  function drawStem(ctx, ground, top, color) {
    ctx.strokeStyle = M.css(color, '#FFFFFF')
    ctx.lineWidth = 2
    ctx.beginPath()
    ctx.moveTo(ground.x, ground.y)
    ctx.lineTo(top.x, top.y)
    ctx.stroke()
    ctx.fillStyle = M.css(color, '#FFFFFF')
    ctx.beginPath()
    ctx.arc(ground.x, ground.y, 4, 0, Math.PI * 2)
    ctx.fill()
  }

  function drawPicture(ctx, item, at) {
    const p = item.picture
    const x = at.x - p.width / 2
    const y = at.y - p.centerY
    ctx.drawImage(p.canvas, x, y, p.width, p.height)
    item.screen.rect = { x, y, w: p.width, h: p.height }
  }

  function drawLabel(ctx, label, x, y) {
    ctx.drawImage(label.canvas, x - label.width / 2, y - label.height, label.width, label.height)
  }

  function drawTrails(item, now, p, z, scale) {
    for (const trail of item.trails) {
      const o = trail.origin
      // The origin in the model's metres (x right, y up, z back), turned to the heading.
      const h = M.toRad(p.heading)
      const east = (o[0] * Math.cos(h) + o[2] * Math.sin(h)) * scale
      const north = (o[0] * -Math.sin(h) + o[2] * Math.cos(h)) * -scale
      const lat = p.latitude + north / 111320
      const lng = p.longitude + east / (111320 * Math.cos(M.toRad(p.latitude)))
      const last = trail.samples[trail.samples.length - 1]
      if (!last || now - last.t > 0.1) trail.samples.push({ t: now, lng, lat, z: z + o[1] * scale })
      while (trail.samples.length && now - trail.samples[0].t > 12) trail.samples.shift()
      if (trail.samples.length < 2) continue
      const origin = frameAt(lng, lat, z)
      const local = [...trail.samples.map((s) => localPoint(origin, s.lng, s.lat, s.z)), localPoint(origin, lng, lat, z + o[1] * scale)]
      const intensity = Math.max(0, Math.min(1, M.num(item.spec.effectIntensity, 1)))
      if (trail.mesh) disposeScene(trail.mesh)
      const mesh = new THREE.Mesh(ribbonGeometry(local, false), ribbonMaterial(`rgba(255,255,255,${0.75 * intensity})`, 5))
      mesh.frustumCulled = false
      const scene = new THREE.Scene()
      scene.add(mesh)
      trail.mesh = scene
      setFrameUniforms(mesh.material, origin)
      camera.position.set(0, 0, 0)
      camera.updateMatrixWorld(true)
      camera.projectionMatrix.identity()
      renderer.render(scene, camera)
    }
  }

  // Terrain heights arrive as tiles load: rebuild walls and paths when they change.
  let groundTimer = 0
  function checkGround() {
    if (!terrainOn() || (!zones.length && !paths.length)) return
    const now = Date.now()
    if (now - groundTimer < 600) return
    groundTimer = now
    const stale = [...zones, ...paths].some((z) => {
      const points = z.spec.points || z.spec.coordinates || []
      return z.groundKey && z.groundKey !== groundKey(points)
    })
    if (stale) M.later(rebuildZonesAndPaths)
  }

  // MARK: Props

  function setModels(list) {
    const specs = list || []
    if (!specs.length && !items.size) return
    M.loadThree().then(() => {
      ensureLayer()
      const next = new Map()
      for (const spec of specs) next.set(spec.id, spec)
      for (const [id, item] of items) {
        const spec = next.get(id)
        if (!spec || buildKey(spec) !== item.key) {
          disposeItem(item)
          items.delete(id)
        }
      }
      for (const [id, spec] of next) {
        const item = items.get(id)
        if (item) item.spec = spec
        else items.set(id, makeItem(spec))
      }
      M.repaint()
    })
  }

  function setZonesAndPaths() {
    if (!(M.state.zones || []).length && !(M.state.paths || []).length && !zones.length && !paths.length) return
    M.loadThree().then(() => {
      ensureLayer()
      rebuildZonesAndPaths()
    })
  }

  M.on('models', setModels)
  M.on('zones', setZonesAndPaths)
  M.on('paths', setZonesAndPaths)
  M.on('lighting', () => M.repaint())
  M.on('maxCameraDistance', () => M.repaint())
  M.on('occlusion', () => {
    const map = M.map
    if (!map || !map.getLayer('munim-3d')) return
    const before = slot(map)
    map.moveLayer('munim-3d', before)
  })
  M.on('followTerrain', () => M.repaint())

  M.styleHooks.push(() => {
    layerAdded = false
    if (THREE && hasContent()) ensureLayer()
    // Terrain may have changed: walls and paths follow it.
    if (THREE && (zones.length || paths.length)) M.later(rebuildZonesAndPaths)
  })
  M.mapHooks.push((map) => {
    map.on('terrain', () => THREE && (zones.length || paths.length) && M.later(rebuildZonesAndPaths))
  })

  // MARK: Taps and measuring

  /** The id of the nearest model under a point (CSS pixels), as the other engines' hit test. */
  M.modelHit = function (point) {
    let best
    let bestDistance = Infinity
    for (const item of items.values()) {
      const s = item.screen
      if (!s || !s.anchor || item.spec.visible === false || item.depthOnly) continue
      if (s.rect) {
        const r = s.rect
        if (point.x >= r.x - 6 && point.x <= r.x + r.w + 6 && point.y >= r.y - 6 && point.y <= r.y + r.h + 6) {
          const d = Math.hypot(point.x - (r.x + r.w / 2), point.y - (r.y + r.h / 2))
          if (d < bestDistance) {
            best = item.spec.id
            bestDistance = d
          }
        }
        continue
      }
      const c = s.centerPx || s.anchor
      const d = Math.hypot(point.x - c.x, point.y - c.y)
      if (d <= Math.max(8, s.radiusPx) + 22 && d < bestDistance) {
        best = item.spec.id
        bestDistance = d
      }
    }
    return best
  }

  /**
   * How far the 3D layer is from where GL JS draws the same points: each
   * model's ground point through the layer's matrices against `map.project`
   * (which puts it on the terrain).
   */
  M.measureAlignment = function () {
    const map = M.map
    const cam = M.munimCamera()
    const report = { attached: !!(map && map.getLayer('munim-3d')), modelsMeasured: 0, maxErrorPoints: 0, meanErrorPoints: 0, modelsVisibleInRender: 0, cameraDistance: cam.distance, cameraPitch: cam.pitch, cameraHeading: cam.heading, fieldOfViewDegrees: M.toDeg(M.fovy()) }
    if (!frame || !report.attached) return report
    let total = 0
    for (const item of items.values()) {
      const spec = item.spec
      // The models drawn in the last frame, where they were drawn.
      if (spec.visible === false || !item.screen || !item.frame) continue
      const f = item.frame
      const ours = toScreen(mat.apply(frameMatrix(f.lng, f.lat, f.ground), 0, 0, 0))
      const theirs = map.project([f.lng, f.lat])
      if (!ours || !theirs) continue
      if (theirs.x < 0 || theirs.y < 0 || theirs.x > frame.width || theirs.y > frame.height) continue
      const error = Math.hypot(ours.x - theirs.x, ours.y - theirs.y)
      report.modelsMeasured += 1
      total += error
      report.maxErrorPoints = Math.max(report.maxErrorPoints, error)
      const s = item.screen
      if (s && s.anchor && s.anchor.x >= 0 && s.anchor.y >= 0 && s.anchor.x <= frame.width && s.anchor.y <= frame.height) report.modelsVisibleInRender += 1
    }
    report.meanErrorPoints = report.modelsMeasured ? total / report.modelsMeasured : 0
    return report
  }

  M.method('measureAlignment', () => M.measureAlignment())
  M.method('modelScreenPoints', () => {
    const out = {}
    for (const [id, item] of items) {
      const s = item.screen
      out[id] = s && s.anchor ? { x: s.anchor.x, y: s.anchor.y, top: s.top ? { x: s.top.x, y: s.top.y } : null, radius: s.radiusPx, scale: item.scale, height: item.height, loaded: item.loaded, ground: item.frame ? item.frame.ground : 0, z: item.frame ? item.frame.z : 0 } : { loaded: item.loaded, hidden: true }
    }
    return out
  })
  M.method('modelHit', (a) => M.modelHit(a.point || a) || '')
  M.method('threeVersion', () => M.loadThree().then(() => THREE.REVISION))

  M.destroyHooks.push(() => {
    for (const item of items.values()) disposeItem(item)
    items = new Map()
    zones = []
    paths = []
    layerAdded = false
  })
})()
