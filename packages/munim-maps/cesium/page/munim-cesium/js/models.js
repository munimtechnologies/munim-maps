// munim-maps' 3D layer drawn by Cesium itself: GLB / glTF models (the
// vehicle catalogue) as Cesium models with heading, altitude, scale,
// screenSize, tint, spin, animations and motion; built-in shapes; pictures
// (avatars) with badges; labels; stems; lift; ground shadows; effects
// (exhaust, smoke, contrail) as particle systems; zones as fading walls;
// paths as 3D lines. Cesium has a depth buffer, so models hide behind
// terrain and 3D Tiles (buildings) on their own.
//
// The native engine sends only the models Cesium can draw (glTF, shapes,
// pictures); others (USDZ, SCN, OBJ on iOS) stay on the native 3D layer,
// drawn over the WebView with Cesium's camera.
/* global Cesium */
;(function () {
  'use strict'
  const M = window.munimCesium
  const C = Cesium

  const FONT = '-apple-system, system-ui, "Segoe UI", Roboto, sans-serif'
  const ALWAYS = Number.POSITIVE_INFINITY

  let models = new Map() // id -> runtime
  let source // CustomDataSource for billboards, labels, stems, shapes, shadows, zones, paths

  function dataSource() {
    if (!source) {
      source = new C.CustomDataSource('munim-3d')
      M.viewer.dataSources.add(source)
    }
    return source
  }

  // MARK: GLB files (tint recolours `paint…` materials in the file itself)

  const files = new Map() // uri -> Promise<ArrayBuffer>
  const tinted = new Map() // uri|tint -> Promise<url>

  function fetchFile(uri) {
    if (!files.has(uri)) {
      const url = M.resource(uri)
      files.set(
        uri,
        fetch(url).then((r) => {
          if (!r.ok) throw new Error(`HTTP ${r.status} for ${uri}`)
          return r.arrayBuffer()
        })
      )
      files.get(uri).catch(() => files.delete(uri))
    }
    return files.get(uri)
  }

  function isGlb(buffer) {
    return buffer.byteLength > 12 && new DataView(buffer).getUint32(0, true) === 0x46546c67
  }

  /** A copy of a GLB with `paint…` materials' base colour set to `tint`. */
  function tintGlb(buffer, tint) {
    const view = new DataView(buffer)
    const jsonLength = view.getUint32(12, true)
    const jsonText = new TextDecoder().decode(new Uint8Array(buffer, 20, jsonLength))
    const gltf = JSON.parse(jsonText)
    const color = M.color(tint)
    const linear = (c) => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4))
    for (const material of gltf.materials || []) {
      if (!/^paint/i.test(material.name || '')) continue
      material.pbrMetallicRoughness = material.pbrMetallicRoughness || {}
      material.pbrMetallicRoughness.baseColorFactor = [linear(color.red), linear(color.green), linear(color.blue), color.alpha]
    }
    let json = new TextEncoder().encode(JSON.stringify(gltf))
    const padded = Math.ceil(json.length / 4) * 4
    const rest = new Uint8Array(buffer, 20 + jsonLength)
    const out = new Uint8Array(12 + 8 + padded + rest.length)
    const outView = new DataView(out.buffer)
    outView.setUint32(0, 0x46546c67, true)
    outView.setUint32(4, 2, true)
    outView.setUint32(8, out.length, true)
    outView.setUint32(12, padded, true)
    outView.setUint32(16, 0x4e4f534a, true)
    out.set(json, 20)
    for (let i = json.length; i < padded; i++) out[20 + i] = 0x20
    out.set(rest, 20 + padded)
    return out.buffer
  }

  /**
   * The model's height in metres from its glTF POSITION bounds (glTF is
   * Y-up), so `screenSize` means the same on Cesium as on the other engines:
   * the model's height on screen in points. Undefined when it can't be read.
   */
  const heights = new Map() // uri -> Promise<number | undefined>
  function gltfHeight(uri) {
    if (!heights.has(uri)) {
      heights.set(
        uri,
        fetchFile(uri)
          .then((buffer) => {
            let gltf
            if (isGlb(buffer)) {
              const jsonLength = new DataView(buffer).getUint32(12, true)
              gltf = JSON.parse(new TextDecoder().decode(new Uint8Array(buffer, 20, jsonLength)))
            } else {
              gltf = JSON.parse(new TextDecoder().decode(new Uint8Array(buffer)))
            }
            let min = Infinity
            let max = -Infinity
            for (const mesh of gltf.meshes || []) {
              for (const primitive of mesh.primitives || []) {
                const accessor = (gltf.accessors || [])[primitive.attributes && primitive.attributes.POSITION]
                if (accessor && accessor.min && accessor.max) {
                  min = Math.min(min, accessor.min[1])
                  max = Math.max(max, accessor.max[1])
                }
              }
            }
            return max > min ? max - min : undefined
          })
          .catch(() => undefined)
      )
    }
    return heights.get(uri)
  }

  /** A URL for the model's file, tinted if asked. */
  function modelUrl(uri, tint) {
    if (!tint) {
      if (/^data:/i.test(uri)) return Promise.resolve(uri)
      return Promise.resolve(M.resource(uri))
    }
    const key = `${uri}|${tint}`
    if (!tinted.has(key)) {
      tinted.set(
        key,
        fetchFile(uri).then((buffer) => {
          const data = isGlb(buffer) ? tintGlb(buffer, tint) : buffer
          return URL.createObjectURL(new Blob([data], { type: 'model/gltf-binary' }))
        })
      )
    }
    return tinted.get(key)
  }

  // MARK: Pictures (avatars)

  async function pictureCanvas(spec, size) {
    const border = M.num(spec.imageBorderWidth, 3)
    const pad = 4
    const badgeHeight = spec.imageBadge ? 18 : 0
    const w = size + pad * 2
    const h = size + pad * 2 + badgeHeight / 2
    const scale = Math.min(3, window.devicePixelRatio || 1)
    const canvas = document.createElement('canvas')
    canvas.width = Math.ceil(w * scale)
    canvas.height = Math.ceil(h * scale)
    const ctx = canvas.getContext('2d')
    ctx.scale(scale, scale)
    let img
    try {
      img = await M.loadImage(spec.imageUri)
    } catch (e) {
      M.error(`model ${spec.id} picture`, e)
    }
    const cx = w / 2
    const cy = pad + size / 2
    ctx.shadowColor = 'rgba(0,0,0,0.35)'
    ctx.shadowBlur = 4
    ctx.beginPath()
    ctx.arc(cx, cy, size / 2, 0, Math.PI * 2)
    ctx.fillStyle = spec.imageBorderColor ? M.css(spec.imageBorderColor) : '#ffffff'
    ctx.fill()
    ctx.shadowBlur = 0
    ctx.save()
    ctx.beginPath()
    ctx.arc(cx, cy, size / 2 - (spec.imageBorderColor || border ? border : 0), 0, Math.PI * 2)
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
      ctx.beginPath()
      ctx.roundRect ? ctx.roundRect(cx - bw / 2, by, bw, badgeHeight, badgeHeight / 2) : ctx.rect(cx - bw / 2, by, bw, badgeHeight)
      ctx.fill()
      ctx.fillStyle = '#ffffff'
      ctx.textAlign = 'center'
      ctx.textBaseline = 'middle'
      ctx.fillText(spec.imageBadge, cx, by + badgeHeight / 2 + 0.5)
    }
    return { canvas, width: w, height: h, centerY: cy }
  }

  // MARK: Motion

  function haversineHeading(a, b) {
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
      else if (a !== b && (a.latitude !== b.latitude || a.longitude !== b.longitude)) heading = haversineHeading(a, b)
      else if (i > 0) heading = haversineHeading(frames[i - 1], a)
    }
    if (spec.spinDegreesPerSecond) heading += now * spec.spinDegreesPerSecond
    return { latitude, longitude, altitude, heading: ((heading % 360) + 360) % 360 }
  }

  function isAnimated(spec) {
    return (spec.motion && spec.motion.length > 0) || !!spec.spinDegreesPerSecond || M.norm(spec.effect || 'none') !== 'none'
  }

  // MARK: Models

  function seaLevel(spec) {
    return M.norm(spec.altitudeReference) === 'sea'
  }

  /** Metres per CSS pixel at a position (for screenSize and lift). */
  function metersPerPixel(position) {
    const scene = M.viewer.scene
    const camera = scene.camera
    const distance = C.Cartesian3.distance(camera.positionWC, position)
    const fovy = camera.frustum.fovy || C.Math.toRadians(60)
    return (2 * distance * Math.tan(fovy / 2)) / Math.max(1, scene.canvas.clientHeight)
  }

  function shapeGraphics(spec, rt) {
    const shape = M.norm(spec.shape || 'box')
    const w = Math.max(0.01, M.num(spec.width, 10)) * M.num(spec.scale, 1)
    const h = Math.max(0.01, M.num(spec.height, 10)) * M.num(spec.scale, 1)
    const l = Math.max(0.01, M.num(spec.length, 10)) * M.num(spec.scale, 1)
    let color = M.color(spec.color, '#0A84FF')
    if (spec.emissive) color = C.Color.lerp(color, C.Color.WHITE, 0.25, new C.Color())
    const material = new C.ColorMaterialProperty(color)
    rt.height = h
    rt.radius = Math.max(w, l) / 2
    switch (shape) {
      case 'sphere':
        return { ellipsoid: { radii: new C.Cartesian3(w / 2, l / 2, h / 2), material } }
      case 'capsule':
        return { ellipsoid: { radii: new C.Cartesian3(w / 2, l / 2, h / 2), material } }
      case 'cylinder':
        return { cylinder: { length: h, topRadius: w / 2, bottomRadius: w / 2, material } }
      case 'cone':
        return { cylinder: { length: h, topRadius: 0, bottomRadius: w / 2, material } }
      case 'pyramid':
        return { cylinder: { length: h, topRadius: 0, bottomRadius: (w / 2) * Math.SQRT2, slices: 4, material } }
      case 'gem':
        return { cylinder: { length: h, topRadius: w / 4, bottomRadius: w / 2, slices: 6, material } }
      case 'box':
      default:
        return { box: { dimensions: new C.Cartesian3(w, l, h), material } }
    }
  }

  function shadowImage() {
    if (shadowImage.canvas) return shadowImage.canvas
    const c = document.createElement('canvas')
    c.width = c.height = 64
    const ctx = c.getContext('2d')
    const g = ctx.createRadialGradient(32, 32, 0, 32, 32, 32)
    g.addColorStop(0, 'rgba(0,0,0,0.45)')
    g.addColorStop(1, 'rgba(0,0,0,0)')
    ctx.fillStyle = g
    ctx.fillRect(0, 0, 64, 64)
    shadowImage.canvas = c
    return c
  }

  function particleImage(color) {
    const c = document.createElement('canvas')
    c.width = c.height = 32
    const ctx = c.getContext('2d')
    const g = ctx.createRadialGradient(16, 16, 0, 16, 16, 16)
    g.addColorStop(0, color)
    g.addColorStop(1, 'rgba(255,255,255,0)')
    ctx.fillStyle = g
    ctx.fillRect(0, 0, 32, 32)
    return c
  }

  function createRuntime(spec) {
    const rt = { spec, key: '', entities: [], model: undefined, particles: [], trails: [], height: M.num(spec.height, 10), radius: 5, loaded: false }
    return rt
  }

  function destroyRuntime(rt) {
    const viewer = M.viewer
    if (!viewer) return
    for (const e of rt.entities) dataSource().entities.remove(e)
    rt.entities = []
    if (rt.model) viewer.scene.primitives.remove(rt.model)
    rt.model = undefined
    for (const p of rt.particles) viewer.scene.primitives.remove(p.system)
    rt.particles = []
    for (const t of rt.trails) viewer.scene.primitives.remove(t.collection)
    rt.trails = []
    rt.cancelled = true
  }

  /** What makes a model need rebuilding (as opposed to moving). */
  function buildKey(spec) {
    return JSON.stringify([spec.uri, spec.tintColor, spec.shape, spec.width, spec.height, spec.length, spec.color, spec.emissive, spec.imageUri, spec.imageBorderColor, spec.imageBorderWidth, spec.imageBadge, spec.label, spec.stem, spec.stemColor, spec.effect, spec.effectOrigins, spec.groundShadow, spec.screenSize, spec.occluder, spec.playAnimations, spec.altitudeReference])
  }

  function build(rt) {
    const spec = rt.spec
    const viewer = M.viewer
    const ds = dataSource()
    const sea = seaLevel(spec)
    const heightReference = sea ? C.HeightReference.NONE : C.HeightReference.RELATIVE_TO_GROUND
    rt.cancelled = false
    rt.sea = sea
    if (spec.occluder) return // Cesium has real depth; occluders are a MapKit workaround.
    const position = C.Cartesian3.fromDegrees(spec.longitude, spec.latitude, M.num(spec.altitude, 0))
    rt.position = position
    if (spec.imageUri) {
      const size = M.num(spec.screenSize, 0) > 0 ? spec.screenSize : 44
      const entity = ds.entities.add({
        id: `munim-model:${spec.id}`,
        position,
        billboard: { image: shadowImage(), width: 1, height: 1, heightReference, disableDepthTestDistance: ALWAYS, verticalOrigin: C.VerticalOrigin.CENTER },
      })
      entity._munim = { kind: 'model', id: spec.id }
      rt.entities.push(entity)
      rt.picture = entity
      pictureCanvas(spec, size).then((pic) => {
        if (rt.cancelled) return
        entity.billboard.image = pic.canvas
        entity.billboard.width = pic.width
        entity.billboard.height = pic.height
        rt.pictureSize = pic
        M.requestRender()
      })
    } else if (spec.uri) {
      const tint = spec.tintColor || ''
      if (!/^data:/i.test(spec.uri)) {
        gltfHeight(spec.uri).then((h) => {
          if (rt.cancelled || !h) return
          rt.gltfHeight = h
          if (rt.loaded) {
            rt.height = h
            update(rt, Date.now() / 1000, true)
            M.requestRender()
          }
        })
      }
      modelUrl(spec.uri, tint)
        .then((url) =>
          C.Model.fromGltfAsync({
            url,
            id: { munimModel: spec.id },
            modelMatrix: C.Transforms.headingPitchRollToFixedFrame(position, new C.HeadingPitchRoll(M.toRad(M.num(spec.heading, 0)), 0, 0)),
            scale: M.num(spec.scale, 1),
            heightReference,
            scene: viewer.scene,
            shadows: viewer.shadows ? C.ShadowMode.ENABLED : C.ShadowMode.DISABLED,
            backFaceCulling: false,
          })
        )
        .then((model) => {
          if (rt.cancelled || M.viewer !== viewer) {
            model.destroy()
            return
          }
          rt.model = model
          viewer.scene.primitives.add(model)
          model.readyEvent.addEventListener(() => {
            rt.loaded = true
            const sphere = model.boundingSphere
            rt.radius = sphere ? sphere.radius / Math.max(1e-6, model.scale) : rt.radius
            rt.height = rt.gltfHeight || rt.radius * 1.2
            if (spec.playAnimations !== false && model.activeAnimations) model.activeAnimations.addAll({ loop: C.ModelAnimationLoop.REPEAT })
            update(rt, Date.now() / 1000, true)
            M.requestRender()
          })
          model.errorEvent && model.errorEvent.addEventListener((e) => M.error(`model ${spec.id}`, e))
        })
        .catch((e) => M.error(`could not load model ${spec.id}`, e))
    } else if (M.norm(spec.shape || 'box') !== 'none') {
      const graphics = shapeGraphics(spec, rt)
      const entity = ds.entities.add(Object.assign({ id: `munim-model:${spec.id}`, position }, graphics))
      entity._munim = { kind: 'model', id: spec.id }
      rt.entities.push(entity)
      rt.shape = entity
    }
    if (spec.groundShadow && !spec.imageUri && M.norm(spec.effect) !== 'smoke') {
      const entity = ds.entities.add({
        id: `munim-model-shadow:${spec.id}`,
        position,
        ellipse: { semiMajorAxis: 3, semiMinorAxis: 3, material: new C.ImageMaterialProperty({ image: shadowImage(), transparent: true }), classificationType: C.ClassificationType.BOTH },
      })
      entity._munim = { kind: 'model', id: spec.id }
      rt.entities.push(entity)
      rt.shadow = entity
    }
    if (spec.label) {
      const entity = ds.entities.add({
        id: `munim-model-label:${spec.id}`,
        position,
        label: {
          text: spec.label,
          font: `600 13px ${FONT}`,
          fillColor: C.Color.WHITE,
          showBackground: true,
          backgroundColor: new C.Color(0.1, 0.1, 0.12, 0.8),
          backgroundPadding: new C.Cartesian2(8, 5),
          verticalOrigin: C.VerticalOrigin.BOTTOM,
          horizontalOrigin: C.HorizontalOrigin.CENTER,
          heightReference,
          disableDepthTestDistance: ALWAYS,
        },
      })
      entity._munim = { kind: 'model', id: spec.id }
      rt.entities.push(entity)
      rt.label = entity
    }
    if (spec.stem && M.num(spec.altitude, 0) > 0) {
      const entity = ds.entities.add({
        id: `munim-model-stem:${spec.id}`,
        polyline: { positions: [position, position], width: 1.5, material: M.color(spec.stemColor, '#ffffff'), depthFailMaterial: M.color(spec.stemColor, '#ffffff') },
      })
      rt.entities.push(entity)
      rt.stem = entity
    }
    buildEffects(rt)
  }

  function buildEffects(rt) {
    const spec = rt.spec
    const effect = M.norm(spec.effect || 'none')
    if (effect === 'none') return
    const scene = M.viewer.scene
    const intensity = Math.max(0, Math.min(1, M.num(spec.effectIntensity, 1)))
    const origins = parseOrigins(spec.effectOrigins)
    if (effect === 'contrail') {
      for (const origin of origins.length ? origins : [[0, 0, 0]]) {
        const collection = scene.primitives.add(new C.PolylineCollection())
        const line = collection.add({ positions: [], width: 6, material: C.Material.fromType('PolylineGlow', { color: new C.Color(1, 1, 1, 0.8 * intensity), glowPower: 0.3, taperPower: 0.6 }) })
        rt.trails.push({ collection, line, origin, samples: [] })
      }
      return
    }
    const smoke = effect === 'smoke'
    const width = Math.max(1, M.num(spec.width, 10))
    const height = Math.max(1, M.num(spec.height, 10))
    for (const origin of smoke ? [[0, 0, 0]] : origins.length ? origins : [[0, 0, 0]]) {
      const system = scene.primitives.add(
        new C.ParticleSystem({
          image: particleImage(smoke ? 'rgba(200,200,200,0.9)' : 'rgba(255,190,90,1)'),
          startColor: smoke ? new C.Color(0.75, 0.75, 0.75, 0.55 * intensity) : new C.Color(1, 0.85, 0.5, 0.95 * intensity),
          endColor: smoke ? new C.Color(0.6, 0.6, 0.6, 0) : new C.Color(0.7, 0.7, 0.7, 0),
          startScale: 1,
          endScale: smoke ? 4 : 3,
          minimumParticleLife: smoke ? 3 : 0.4,
          maximumParticleLife: smoke ? 6 : 1.2,
          minimumSpeed: smoke ? height / 8 : 20,
          maximumSpeed: smoke ? height / 4 : 45,
          imageSize: new C.Cartesian2(smoke ? width / 6 : 4, smoke ? width / 6 : 4),
          emissionRate: (smoke ? 20 : 60) * Math.max(0.05, intensity),
          emitter: smoke ? new C.CircleEmitter(width / 2) : new C.ConeEmitter(C.Math.toRadians(12)),
          sizeInMeters: true,
          lifetime: 16,
        })
      )
      rt.particles.push({ system, origin, smoke })
    }
  }

  function parseOrigins(value) {
    if (!value) return []
    if (Array.isArray(value)) return value.map((p) => (Array.isArray(p) ? p : [p.x || 0, p.y || 0, p.z || 0]))
    return String(value)
      .split(';')
      .map((p) => p.split(',').map(Number))
      .filter((p) => p.length === 3 && p.every((n) => isFinite(n)))
  }

  const scratchMatrix = new C.Matrix4()
  const scratchHpr = new C.HeadingPitchRoll()

  /** Moves and sizes a model for this frame. */
  function update(rt, now, force) {
    const spec = rt.spec
    const scene = M.viewer.scene
    const animated = isAnimated(spec)
    if (!force && !animated && !(M.num(spec.screenSize, 0) > 0) && !(M.num(spec.liftPoints, 0) > 0) && !rt.dirty) return
    rt.dirty = false
    const p = pose(spec, now)
    const ground = rt.sea ? 0 : 0 // heights clamp through heightReference
    let altitude = p.altitude + ground
    let position = C.Cartesian3.fromDegrees(p.longitude, p.latitude, altitude)
    const mpp = metersPerPixel(position)
    const lift = M.num(spec.liftPoints, 0) * mpp
    if (lift) {
      altitude += lift
      position = C.Cartesian3.fromDegrees(p.longitude, p.latitude, altitude)
    }
    rt.position = position
    const camera = scene.camera
    const visible = spec.visible !== false && C.Cartesian3.distance(camera.positionWC, position) <= M.num(M.state.maxCameraDistance, 50000) * (M.options().modelMaxDistanceScale || 4)
    let scale = M.num(spec.scale, 1)
    const screenSize = M.num(spec.screenSize, 0)
    if (screenSize > 0 && !spec.imageUri) {
      // Height, like the other engines (the bounding sphere's diameter made
      // long models such as cars and buses several times too small).
      const size = Math.max(0.01, (rt.loaded ? rt.gltfHeight || rt.radius * 2 : rt.height) || 1)
      scale = (screenSize * mpp) / size
    }
    rt.currentScale = scale
    const hpr = C.HeadingPitchRoll.fromDegrees(p.heading + M.headingOffset(), 0, 0, scratchHpr)
    if (rt.model) {
      rt.model.show = visible
      rt.model.modelMatrix = C.Transforms.headingPitchRollToFixedFrame(position, hpr, C.Ellipsoid.WGS84, C.Transforms.eastNorthUpToFixedFrame, rt.model.modelMatrix)
      rt.model.scale = scale
    }
    const sizeMeters = (rt.loaded ? rt.radius * 2 : rt.height) * (screenSize > 0 && !spec.imageUri ? scale : M.num(spec.scale, 1))
    if (rt.shape) {
      rt.shape.show = visible
      const half = (rt.height * (screenSize > 0 ? scale / M.num(spec.scale, 1) : 1)) / 2
      const base = rt.sea ? 0 : M.groundHeight(p.latitude, p.longitude)
      rt.shape.position = C.Cartesian3.fromDegrees(p.longitude, p.latitude, base + altitude + half)
      rt.shape.orientation = C.Transforms.headingPitchRollQuaternion(position, hpr)
    }
    if (rt.picture) {
      rt.picture.show = spec.visible !== false
      rt.picture.position = position
    }
    if (rt.shadow) {
      rt.shadow.show = visible
      rt.shadow.position = C.Cartesian3.fromDegrees(p.longitude, p.latitude)
      const r = Math.max(0.5, (rt.loaded ? rt.radius : rt.radius || 5) * (screenSize > 0 ? scale : M.num(spec.scale, 1)) * 0.9)
      rt.shadow.ellipse.semiMajorAxis = r
      rt.shadow.ellipse.semiMinorAxis = r
    }
    if (rt.label) {
      rt.label.show = spec.visible !== false
      const top = spec.imageUri ? altitude : altitude + sizeMeters * 0.9
      rt.label.position = C.Cartesian3.fromDegrees(p.longitude, p.latitude, top)
      rt.label.label.pixelOffset = new C.Cartesian2(0, spec.imageUri ? -((rt.pictureSize ? rt.pictureSize.height / 2 : 22) + 6) : -6)
    }
    if (rt.stem) {
      rt.stem.show = spec.visible !== false
      const groundHeight = rt.sea ? M.groundHeight(p.latitude, p.longitude) : M.groundHeight(p.latitude, p.longitude)
      const top = rt.sea ? altitude : groundHeight + altitude
      rt.stem.polyline.positions = [C.Cartesian3.fromDegrees(p.longitude, p.latitude, groundHeight), C.Cartesian3.fromDegrees(p.longitude, p.latitude, top)]
    }
    if (rt.particles.length || rt.trails.length) {
      const groundHeight = rt.sea ? 0 : M.groundHeight(p.latitude, p.longitude)
      const base = C.Cartesian3.fromDegrees(p.longitude, p.latitude, groundHeight + altitude)
      const frame = C.Transforms.headingPitchRollToFixedFrame(base, hpr, C.Ellipsoid.WGS84, C.Transforms.eastNorthUpToFixedFrame, scratchMatrix)
      for (const part of rt.particles) {
        part.system.show = visible
        part.system.modelMatrix = C.Matrix4.clone(frame, part.system.modelMatrix)
        // Origins are in the model's metres: x right, y up, z back (munim) -> x east, y north, z up here.
        const o = part.origin
        const offset = C.Matrix4.fromTranslation(new C.Cartesian3(o[0] * scale, -o[2] * scale, o[1] * scale))
        // Exhaust points down out of the base; smoke rises.
        const rotate = part.smoke ? C.Matrix4.IDENTITY : C.Matrix4.fromRotationTranslation(C.Matrix3.fromRotationX(Math.PI))
        part.system.emitterModelMatrix = C.Matrix4.multiply(offset, rotate, new C.Matrix4())
      }
      for (const trail of rt.trails) {
        const o = trail.origin
        const point = C.Matrix4.multiplyByPoint(frame, new C.Cartesian3(o[0] * scale, -o[2] * scale, o[1] * scale), new C.Cartesian3())
        const last = trail.samples[trail.samples.length - 1]
        if (!last || now - last.t > 0.1) trail.samples.push({ t: now, p: point })
        while (trail.samples.length && now - trail.samples[0].t > 12) trail.samples.shift()
        trail.line.positions = [...trail.samples.map((s) => s.p), point]
        trail.line.show = visible && trail.samples.length > 1
      }
    }
  }

  // Cesium turns glTF models to face east (+x) at heading 0; munim models face north.
  const offset = -90
  M.headingOffset = () => M.num(M.options().modelHeadingOffset, offset)

  function setModels(list) {
    if (!M.viewer) return
    const next = new Map()
    for (const spec of list || []) next.set(spec.id, spec)
    for (const [id, rt] of models) {
      const spec = next.get(id)
      if (!spec || buildKey(spec) !== rt.key) {
        destroyRuntime(rt)
        models.delete(id)
      }
    }
    for (const [id, spec] of next) {
      let rt = models.get(id)
      if (!rt) {
        rt = createRuntime(spec)
        rt.key = buildKey(spec)
        models.set(id, rt)
        build(rt)
      } else {
        rt.spec = spec
      }
      rt.dirty = true
      update(rt, Date.now() / 1000, true)
    }
  }

  M.modelsAnimating = function () {
    for (const rt of models.values()) if (isAnimated(rt.spec) || (rt.model && rt.spec.playAnimations !== false && rt.model.activeAnimations && rt.model.activeAnimations.length)) return true
    return false
  }

  M.modelRuntime = (id) => models.get(id)

  M.viewerHooks.push((viewer) => {
    viewer.scene.preRender.addEventListener(() => {
      const now = Date.now() / 1000
      for (const rt of models.values()) update(rt, now, false)
    })
  })

  // MARK: Zones (fading walls) and paths (3D lines)

  let zoneEntities = []
  let pathEntities = []

  function wallImage(color) {
    const c = document.createElement('canvas')
    c.width = 4
    c.height = 128
    const ctx = c.getContext('2d')
    const solid = color.withAlpha(1).toCssColorString()
    const g = ctx.createLinearGradient(0, 128, 0, 0)
    g.addColorStop(0, color.withAlpha(Math.min(1, color.alpha * 2)).toCssColorString())
    g.addColorStop(1, color.withAlpha(0).toCssColorString())
    ctx.fillStyle = g
    ctx.fillRect(0, 0, 4, 128)
    ctx.fillStyle = solid
    ctx.fillRect(0, 126, 4, 2)
    return c
  }

  async function groundHeights(points) {
    if (!M.drawsTerrain()) return points.map(() => 0)
    try {
      const sampled = await C.sampleTerrainMostDetailed(M.viewer.terrainProvider, points.map((p) => C.Cartographic.fromDegrees(p.longitude, p.latitude)))
      return sampled.map((c) => c.height || 0)
    } catch (e) {
      return points.map((p) => M.groundHeight(p.latitude, p.longitude))
    }
  }

  async function setZones(list) {
    const ds = dataSource()
    for (const e of zoneEntities) ds.entities.remove(e)
    zoneEntities = []
    const token = (setZones.token = (setZones.token || 0) + 1)
    for (const zone of list || []) {
      const points = zone.points || zone.coordinates || []
      if (points.length < 3) continue
      const color = M.color(zone.color, '#0A84FF40')
      const ring = [...points, points[0]]
      const heights = await groundHeights(ring)
      if (token !== setZones.token) return
      const height = M.num(zone.height, 40)
      const positions = ring.map((p) => C.Cartesian3.fromDegrees(p.longitude, p.latitude))
      const wall = ds.entities.add({
        id: `munim-zone:${zone.id}`,
        show: zone.visible !== false,
        wall: {
          positions,
          minimumHeights: heights,
          maximumHeights: heights.map((h) => h + height),
          material: new C.ImageMaterialProperty({ image: wallImage(color), transparent: true }),
        },
      })
      wall._munim = { kind: 'zone', id: zone.id }
      const bottom = ds.entities.add({ show: zone.visible !== false, polyline: { positions, width: 2, material: color.withAlpha(1), clampToGround: true } })
      zoneEntities.push(wall, bottom)
    }
    M.requestRender()
  }

  async function setPaths(list) {
    const ds = dataSource()
    for (const e of pathEntities) ds.entities.remove(e)
    pathEntities = []
    const token = (setPaths.token = (setPaths.token || 0) + 1)
    for (const path of list || []) {
      const points = path.points || (path.coordinates || []).map((c, i) => ({ latitude: c.latitude, longitude: c.longitude, altitude: (path.altitudes || [])[i] || 0 }))
      if (points.length < 2) continue
      const list2 = path.closed ? [...points, points[0]] : points
      const color = M.color(path.color, '#FFFFFF')
      const width = M.num(path.width, 2)
      const flat = list2.every((p) => !(M.num(p.altitude, 0) > 0)) && !seaLevel(path)
      let entity
      if (flat) {
        entity = ds.entities.add({ show: path.visible !== false, polyline: { positions: list2.map((p) => C.Cartesian3.fromDegrees(p.longitude, p.latitude)), width, material: color, clampToGround: true } })
      } else {
        const heights = seaLevel(path) ? list2.map(() => 0) : await groundHeights(list2)
        if (token !== setPaths.token) return
        entity = ds.entities.add({
          show: path.visible !== false,
          polyline: { positions: list2.map((p, i) => C.Cartesian3.fromDegrees(p.longitude, p.latitude, heights[i] + M.num(p.altitude, 0))), width, material: color, arcType: C.ArcType.GEODESIC, depthFailMaterial: color.withAlpha(color.alpha * 0.35) },
        })
      }
      entity._munim = { kind: 'path', id: path.id }
      pathEntities.push(entity)
    }
    M.requestRender()
  }

  M.on('models', setModels)
  M.on('zones', (list) => setZones(list).catch((e) => M.error('zones', e)))
  M.on('paths', (list) => setPaths(list).catch((e) => M.error('paths', e)))
  M.on('maxCameraDistance', () => {
    for (const rt of models.values()) rt.dirty = true
  })
  M.on('followTerrain', () => {})

  M.destroyHooks.push(() => {
    for (const rt of models.values()) rt.cancelled = true
    models = new Map()
    source = undefined
    zoneEntities = []
    pathEntities = []
  })
})()
