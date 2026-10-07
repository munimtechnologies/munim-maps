// Cesium-only engine methods, called from JavaScript through
// `cesiumCommands(mapRef)` (src/providers/cesium.ts) as
// `providerCommand(name, argsJson)`. Each resolves with a JSON value.
/* global Cesium */
;(function () {
  'use strict'
  const M = window.munimCesium
  const C = Cesium

  const hpr = (o) => new C.HeadingPitchRoll(M.toRad(M.num(o && o.heading, 0)), M.toRad(M.num(o && o.pitch, -90)), M.toRad(M.num(o && o.roll, 0)))

  function destination(d) {
    if (!d) throw new Error('destination is required')
    if (d.west != null || d.latitudeDelta != null) return M.rectangle(d)
    return M.cartesian(d)
  }

  function easing(name) {
    if (!name) return undefined
    const key = Object.keys(C.EasingFunction).find((k) => M.norm(k) === M.norm(name))
    return key ? C.EasingFunction[key] : undefined
  }

  /** A target to frame: an entity, data source, tileset, munim model or marker by id. */
  function target(a) {
    if (a.entityId) return M.findEntity(a.entityId) || M.findEntity(`munim-marker:${a.entityId}`) || M.findEntity(`munim-model:${a.entityId}`)
    if (a.dataSourceId) return M.dataSource(a.dataSourceId)
    if (a.tilesetId) return M.tileset(a.tilesetId)
    if (a.modelId) {
      const rt = M.modelRuntime(a.modelId)
      if (rt && rt.model) return rt.model
      return M.findEntity(`munim-model:${a.modelId}`)
    }
    if (a.markerId) return M.findEntity(`munim-marker:${a.markerId}`)
    return undefined
  }

  function offset(o) {
    if (!o) return undefined
    return new C.HeadingPitchRange(M.toRad(M.num(o.heading, 0)), M.toRad(M.num(o.pitch, -45)), M.num(o.range, 0))
  }

  // MARK: Camera

  M.method('flyTo', (a) => {
    M.stopFlight()
    return new Promise((resolve) => {
      M.viewer.camera.flyTo({
        destination: destination(a.destination),
        orientation: a.orientation ? hpr(a.orientation) : undefined,
        duration: a.duration,
        maximumHeight: a.maximumHeight,
        pitchAdjustHeight: a.pitchAdjustHeight,
        flyOverLongitude: a.flyOverLongitude,
        flyOverLongitudeWeight: a.flyOverLongitudeWeight,
        convert: a.convert,
        easingFunction: easing(a.easing),
        complete: () => resolve({ completed: true }),
        cancel: () => resolve({ completed: false }),
      })
      M.requestRender()
    })
  })

  M.method('setView', (a) => {
    M.stopFlight()
    M.viewer.camera.setView({ destination: destination(a.destination), orientation: a.orientation ? hpr(a.orientation) : undefined })
  })

  M.method('lookAt', (a) => {
    M.stopFlight()
    const camera = M.viewer.camera
    camera.lookAt(M.cartesian(a.target), new C.HeadingPitchRange(M.toRad(M.num(a.heading, 0)), M.toRad(M.num(a.pitch, -45)), M.num(a.range, 1000)))
    if (!a.lock) camera.lookAtTransform(C.Matrix4.IDENTITY)
  })

  M.method('flyHome', (a) => M.viewer.camera.flyHome(a.duration))

  M.method('zoomTo', (a) => {
    const t = target(a)
    if (!t) throw new Error('nothing to zoom to')
    return M.viewer.zoomTo(t, offset(a.offset)).then((ok) => ({ completed: !!ok }))
  })

  M.method('flyToTarget', (a) => {
    const t = target(a)
    if (!t) throw new Error('nothing to fly to')
    return M.viewer.flyTo(t, { duration: a.duration, maximumHeight: a.maximumHeight, offset: offset(a.offset) }).then((ok) => ({ completed: !!ok }))
  })

  M.method('trackEntity', (a) => {
    M.viewer.trackedEntity = a.id ? target({ entityId: a.id }) : undefined
    return { tracking: !!M.viewer.trackedEntity }
  })

  M.method('selectEntity', (a) => {
    M.viewer.selectedEntity = a.id ? target({ entityId: a.id }) : undefined
  })

  let orbit
  M.method('orbit', (a) => {
    M.stopFlight()
    const camera = M.viewer.camera
    const now = M.cameraNow()
    const center = a.center ? M.cartesian(a.center, M.groundHeight(a.center.latitude, a.center.longitude)) : C.Cartesian3.fromDegrees(now.longitude, now.latitude, now.height)
    const pitch = M.toRad(M.num(a.pitch, now.pitch) - 90)
    const range = M.num(a.range, now.distance)
    let heading = M.toRad(M.num(a.heading, now.heading))
    const speed = M.toRad(M.num(a.degreesPerSecond, 10))
    let last = Date.now()
    if (orbit) orbit()
    const remove = M.viewer.scene.preRender.addEventListener(() => {
      const t = Date.now()
      heading += (speed * (t - last)) / 1000
      last = t
      camera.lookAt(center, new C.HeadingPitchRange(heading, pitch, range))
    })
    orbit = () => {
      remove()
      camera.lookAtTransform(C.Matrix4.IDENTITY)
      orbit = undefined
    }
    M.continuous.orbit = true
  })

  M.method('stopOrbit', () => {
    if (orbit) orbit()
    delete M.continuous.orbit
  })

  M.method('cameraMove', (a) => {
    const camera = M.viewer.camera
    const amount = a.amount
    switch (M.norm(a.direction)) {
      case 'forward':
        return camera.moveForward(amount)
      case 'backward':
        return camera.moveBackward(amount)
      case 'left':
        return camera.moveLeft(amount)
      case 'right':
        return camera.moveRight(amount)
      case 'up':
        return camera.moveUp(amount)
      case 'down':
        return camera.moveDown(amount)
      case 'in':
        return camera.zoomIn(amount)
      case 'out':
        return camera.zoomOut(amount)
    }
    throw new Error('direction is forward, backward, left, right, up, down, in or out')
  })

  M.method('cameraLook', (a) => {
    const camera = M.viewer.camera
    const angle = M.toRad(M.num(a.degrees, 5))
    switch (M.norm(a.direction)) {
      case 'left':
        return camera.lookLeft(angle)
      case 'right':
        return camera.lookRight(angle)
      case 'up':
        return camera.lookUp(angle)
      case 'down':
        return camera.lookDown(angle)
      case 'twistleft':
        return camera.twistLeft(angle)
      case 'twistright':
        return camera.twistRight(angle)
    }
    throw new Error('direction is left, right, up, down, twistLeft or twistRight')
  })

  M.method('cameraRotate', (a) => {
    const camera = M.viewer.camera
    const angle = M.toRad(M.num(a.degrees, 5))
    switch (M.norm(a.direction)) {
      case 'left':
        return camera.rotateLeft(angle)
      case 'right':
        return camera.rotateRight(angle)
      case 'up':
        return camera.rotateUp(angle)
      case 'down':
        return camera.rotateDown(angle)
    }
    throw new Error('direction is left, right, up or down')
  })

  M.method('getCameraView', () => {
    const camera = M.viewer.camera
    const f = camera.frustum
    const carto = camera.positionCartographic
    const vec = (v) => ({ x: v.x, y: v.y, z: v.z })
    return {
      position: { latitude: M.toDeg(carto.latitude), longitude: M.toDeg(carto.longitude), height: carto.height },
      heading: M.toDeg(camera.heading),
      pitch: M.toDeg(camera.pitch),
      roll: M.toDeg(camera.roll),
      positionWC: vec(camera.positionWC),
      directionWC: vec(camera.directionWC),
      upWC: vec(camera.upWC),
      rightWC: vec(camera.rightWC),
      frustum: {
        type: f instanceof C.OrthographicFrustum || f instanceof C.OrthographicOffCenterFrustum ? 'orthographic' : 'perspective',
        fov: f.fov != null ? M.toDeg(f.fov) : undefined,
        fovy: f.fovy != null ? M.toDeg(f.fovy) : undefined,
        aspectRatio: f.aspectRatio,
        near: f.near,
        far: f.far,
        width: f.width,
      },
      viewMatrix: Array.from(C.Matrix4.toArray(camera.viewMatrix)),
      projectionMatrix: Array.from(C.Matrix4.toArray(f.projectionMatrix)),
      sceneMode: M.sceneModeName(),
      munim: M.munimCamera(),
    }
  })

  // MARK: Scene

  M.method('setSceneMode', (a) => {
    M.morph(M.norm(a.mode), M.num(a.duration, 2))
  })

  M.method('screenshot', (a) => {
    const viewer = M.viewer
    viewer.render()
    const canvas = viewer.scene.canvas
    const type = M.norm(a.format) === 'jpeg' || M.norm(a.format) === 'jpg' ? 'image/jpeg' : 'image/png'
    let source = canvas
    if (a.width > 0 && a.height > 0) {
      const out = document.createElement('canvas')
      out.width = a.width
      out.height = a.height
      out.getContext('2d').drawImage(canvas, 0, 0, a.width, a.height)
      source = out
    }
    const dataUrl = source.toDataURL(type, M.num(a.quality, 0.92))
    return { dataUrl, width: source.width, height: source.height }
  })

  // The shared `takeSnapshot`: a PNG of the map, base64.
  M.method('snapshot', (a) => {
    const viewer = M.viewer
    viewer.render()
    const canvas = viewer.scene.canvas
    let source = canvas
    if (a.width > 0 && a.height > 0) {
      const scale = Math.min(3, window.devicePixelRatio || 1)
      const out = document.createElement('canvas')
      out.width = Math.round(a.width * scale)
      out.height = Math.round(a.height * scale)
      out.getContext('2d').drawImage(canvas, 0, 0, out.width, out.height)
      source = out
    }
    return source.toDataURL('image/png').replace(/^data:image\/png;base64,/, '')
  })

  M.method('requestRender', () => M.requestRender())

  M.method('pick', (a) => {
    const position = M.windowPosition(a)
    const what = M.describePick(M.viewer.scene.pick(position, a.width, a.height))
    const ground = M.pickGround(position, true)
    return describe(what, ground)
  })

  function describe(what, ground) {
    const out = { position: ground ? M.fromCartesian(ground) : null }
    if (!what) return Object.assign(out, { kind: 'none' })
    out.kind = what.kind
    if (what.id !== undefined) out.id = typeof what.id === 'string' ? what.id : String(what.id)
    if (what.ids) out.ids = what.ids
    if (what.properties) out.properties = what.properties
    if (what.entity) {
      out.entityId = what.entity.id
      out.name = what.entity.name
      try {
        if (what.entity.properties) out.properties = what.entity.properties.getValue(M.viewer.clock.currentTime)
      } catch (e) {
        // not plain values
      }
    }
    return out
  }

  M.method('drillPick', (a) => {
    const position = M.windowPosition(a)
    const ground = M.pickGround(position, true)
    return M.viewer.scene.drillPick(position, a.limit, a.width, a.height).map((p) => describe(M.describePick(p), ground))
  })

  M.method('pickPosition', (a) => {
    const p = M.pickGround(M.windowPosition(a), true)
    return p ? M.fromCartesian(p) : null
  })

  M.method('pickImageryFeatures', (a) => {
    const viewer = M.viewer
    const ray = viewer.camera.getPickRay(M.windowPosition(a))
    const promise = viewer.imageryLayers.pickImageryLayerFeatures(ray, viewer.scene)
    if (!promise) return []
    return promise.then((features) => features.map((f) => ({ name: f.name, description: f.description, data: typeof f.data === 'object' ? f.data : String(f.data), position: f.position ? { latitude: M.toDeg(f.position.latitude), longitude: M.toDeg(f.position.longitude) } : null, layer: viewer.imageryLayers.indexOf(f.imageryLayer) })))
  })

  M.method('toScreen', (a) => {
    const p = C.SceneTransforms.worldToWindowCoordinates(M.viewer.scene, M.cartesian(a, M.groundHeight(a.latitude, a.longitude)))
    return p ? { x: p.x, y: p.y } : null
  })

  // MARK: Measurement and heights

  function cartos(points) {
    return points.map((p) => C.Cartographic.fromDegrees(p.longitude, p.latitude, p.height || p.altitude || 0))
  }

  M.method('measureDistance', (a) => {
    const points = a.points || []
    const mode = M.norm(a.mode || 'geodesic')
    const segments = []
    for (let i = 1; i < points.length; i++) {
      const [p, q] = cartos([points[i - 1], points[i]])
      let d
      if (mode === 'straight') d = C.Cartesian3.distance(C.Cartographic.toCartesian(p), C.Cartographic.toCartesian(q))
      else if (mode === 'rhumb') d = new C.EllipsoidRhumbLine(p, q).surfaceDistance
      else d = new C.EllipsoidGeodesic(p, q).surfaceDistance
      segments.push(d)
    }
    return { meters: segments.reduce((x, y) => x + y, 0), segments }
  })

  M.method('measureArea', (a) => {
    const positions = (a.points || []).map((p) => M.cartesian(p))
    if (positions.length < 3) return { squareMeters: 0 }
    const plane = C.EllipsoidTangentPlane.fromPoints(positions, C.Ellipsoid.WGS84)
    const projected = plane.projectPointsOntoPlane(positions)
    const area = Math.abs(C.PolygonPipeline.computeArea2D(projected))
    return { squareMeters: area }
  })

  M.method('measureHeading', (a) => {
    const [p, q] = cartos([a.from, a.to])
    const g = new C.EllipsoidGeodesic(p, q)
    return { degrees: (M.toDeg(g.startHeading) + 360) % 360, meters: g.surfaceDistance }
  })

  M.method('sampleHeights', async (a) => {
    const viewer = M.viewer
    const points = cartos(a.points || [])
    if (a.includeTiles) {
      const sampled = await viewer.scene.sampleHeightMostDetailed(points, a.objectsToExclude, a.width)
      return sampled.map((c) => (c && c.height != null ? c.height : null))
    }
    if (!M.drawsTerrain()) return points.map(() => 0)
    const sampled = a.mostDetailed === false ? await C.sampleTerrain(viewer.terrainProvider, a.level || 11, points) : await C.sampleTerrainMostDetailed(viewer.terrainProvider, points)
    return sampled.map((c) => (c.height == null ? null : c.height))
  })

  M.method('clampToHeight', async (a) => {
    const clamped = await M.viewer.scene.clampToHeightMostDetailed((a.points || []).map((p) => M.cartesian(p)))
    return clamped.map((c) => (c ? M.fromCartesian(c) : null))
  })

  // MARK: Entities, data sources, tilesets, imagery, terrain

  let commandEntities
  function commandSource() {
    if (!commandEntities || !M.viewer.dataSources.contains(commandEntities)) {
      commandEntities = new C.CzmlDataSource('munim-command-entities')
      M.viewer.dataSources.add(commandEntities)
    }
    return commandEntities
  }
  M.destroyHooks.push(() => {
    commandEntities = undefined
    orbit = undefined
    panoramas.clear()
    particles.clear()
    extraTilesets.clear()
    extraLayers.clear()
  })

  M.method('addEntities', async (a) => {
    const packets = Array.isArray(a.czml) ? a.czml : [a.czml]
    await commandSource().process([{ id: 'document', version: '1.0' }, ...packets.filter((p) => p.id !== 'document')])
    return { count: packets.length }
  })

  M.method('removeEntities', (a) => {
    let removed = 0
    for (const id of a.ids || []) {
      for (let i = 0; i < M.viewer.dataSources.length; i++) {
        if (M.viewer.dataSources.get(i).entities.removeById(id)) removed++
      }
      if (M.viewer.entities.removeById(id)) removed++
    }
    return { removed }
  })

  M.method('getEntity', (a) => {
    const e = M.findEntity(a.id)
    if (!e) return null
    const time = a.time ? M.julian(a.time) : M.viewer.clock.currentTime
    const position = e.position ? e.position.getValue(time) : undefined
    let properties
    try {
      properties = e.properties ? e.properties.getValue(time) : undefined
    } catch (err) {
      properties = undefined
    }
    return { id: e.id, name: e.name, show: e.show, position: position ? M.fromCartesian(position) : null, properties, description: e.description ? e.description.getValue(time) : undefined, availability: e.availability ? { start: M.iso(e.availability.start), stop: M.iso(e.availability.stop) } : null }
  })

  M.method('listEntities', (a) => {
    const out = []
    const viewer = M.viewer
    for (let i = 0; i < viewer.dataSources.length; i++) {
      const ds = viewer.dataSources.get(i)
      if (a.dataSourceId && ds !== M.dataSource(a.dataSourceId)) continue
      for (const e of ds.entities.values) out.push({ id: e.id, name: e.name, dataSource: ds.name })
    }
    return out
  })

  M.method('exportKml', async (a) => {
    const entities = new C.EntityCollection()
    const viewer = M.viewer
    const ids = a.ids ? new Set(a.ids) : undefined
    for (let i = 0; i < viewer.dataSources.length; i++) {
      for (const e of viewer.dataSources.get(i).entities.values) if (!ids || ids.has(e.id)) entities.add(e)
    }
    const result = await C.exportKml({ entities, kmz: false })
    return { kml: result.kml }
  })

  const extraDataSources = new Map()
  M.method('loadDataSource', async (a) => {
    const id = a.id || `ds${Date.now()}`
    if (extraDataSources.has(id)) M.viewer.dataSources.remove(extraDataSources.get(id), true)
    const ds = await M.loadDataSource(a)
    await M.viewer.dataSources.add(ds)
    extraDataSources.set(id, ds)
    if (a.flyTo) await M.viewer.flyTo(ds)
    return { id, entities: ds.entities.values.length }
  })

  M.method('removeDataSource', (a) => {
    const ds = extraDataSources.get(a.id) || M.dataSource(a.id)
    if (!ds) return { removed: false }
    extraDataSources.delete(a.id)
    return { removed: M.viewer.dataSources.remove(ds, true) }
  })

  const extraTilesets = new Map()
  M.method('addTileset', async (a) => {
    const id = a.id || `tileset${Date.now()}`
    const prev = extraTilesets.get(id)
    if (prev) M.viewer.scene.primitives.remove(prev)
    const primitive = await M.loadTileset(Object.assign({}, a))
    M.viewer.scene.primitives.add(primitive)
    extraTilesets.set(id, primitive)
    if (a.style && 'style' in primitive) primitive.style = new C.Cesium3DTileStyle(a.style)
    if (a.flyTo) await M.viewer.zoomTo(primitive)
    return { id }
  })

  M.method('removeTileset', (a) => {
    const t = extraTilesets.get(a.id)
    if (!t) return { removed: false }
    extraTilesets.delete(a.id)
    return { removed: M.viewer.scene.primitives.remove(t) }
  })

  function anyTileset(id) {
    return extraTilesets.get(id) || M.tileset(id)
  }

  M.method('setTilesetStyle', (a) => {
    const t = anyTileset(a.id)
    if (!t) throw new Error(`no tileset "${a.id}"`)
    t.style = a.style ? new C.Cesium3DTileStyle(a.style) : undefined
  })

  M.method('setTilesetProperties', (a) => {
    const t = anyTileset(a.id)
    if (!t) throw new Error(`no tileset "${a.id}"`)
    const { id, customShader, ...rest } = a
    M.assign(t, M.convertOptions(rest))
    if (customShader) t.customShader = M.customShader(customShader)
  })

  M.method('tilesetInfo', (a) => {
    const t = anyTileset(a.id)
    if (!t) throw new Error(`no tileset "${a.id}"`)
    const sphere = t.boundingSphere
    return {
      center: sphere ? M.fromCartesian(sphere.center) : null,
      radius: sphere ? sphere.radius : 0,
      properties: t.properties || null,
      asset: t.asset || null,
      extras: t.extras || null,
      tilesLoaded: !!t.tilesLoaded,
      memoryBytes: t.totalMemoryUsageInBytes,
    }
  })

  const extraLayers = new Map()
  M.method('addImageryLayer', async (a) => {
    const id = a.id || `layer${Date.now()}`
    if (extraLayers.has(id)) M.viewer.imageryLayers.remove(extraLayers.get(id), true)
    const provider = await Promise.resolve(M.imageryProvider(a))
    const layerOptions = {}
    for (const k of ['alpha', 'nightAlpha', 'dayAlpha', 'brightness', 'contrast', 'hue', 'saturation', 'gamma', 'show', 'splitDirection', 'colorToAlpha', 'colorToAlphaThreshold']) if (a[k] !== undefined) layerOptions[k] = a[k]
    const layer = new C.ImageryLayer(provider, M.convertOptions(layerOptions))
    M.viewer.imageryLayers.add(layer, a.index)
    extraLayers.set(id, layer)
    return { id, index: M.viewer.imageryLayers.indexOf(layer) }
  })

  M.method('removeImageryLayer', (a) => {
    const layer = extraLayers.get(a.id)
    if (!layer) return { removed: false }
    extraLayers.delete(a.id)
    return { removed: M.viewer.imageryLayers.remove(layer, true) }
  })

  M.method('setImageryLayer', (a) => {
    const layer = extraLayers.get(a.id)
    if (!layer) throw new Error(`no imagery layer "${a.id}"`)
    const { id, index, raise, lower, ...rest } = a
    M.assign(layer, M.convertOptions(rest))
    const layers = M.viewer.imageryLayers
    if (raise === 'top') layers.raiseToTop(layer)
    else if (raise) layers.raise(layer)
    if (lower === 'bottom') layers.lowerToBottom(layer)
    else if (lower) layers.lower(layer)
  })

  M.method('imageryLayers', () => {
    const layers = M.viewer.imageryLayers
    const out = []
    for (let i = 0; i < layers.length; i++) {
      const l = layers.get(i)
      const extra = [...extraLayers.entries()].find(([, v]) => v === l)
      out.push({ index: i, id: extra ? extra[0] : null, show: l.show, alpha: l.alpha, ready: l.ready })
    }
    return out
  })

  M.method('setTerrain', (a) => {
    M.state.options = Object.assign({}, M.state.options || {}, { terrain: a.terrain })
    M.updateTerrain()
  })

  // MARK: Time

  M.method('setClock', (a) => {
    M.applyClock(a)
    return M.clockState()
  })
  M.method('play', () => {
    M.viewer.clock.shouldAnimate = true
  })
  M.method('pause', () => {
    M.viewer.clock.shouldAnimate = false
  })
  M.method('setTime', (a) => {
    M.viewer.clock.currentTime = M.julian(a.time)
    return M.clockState()
  })
  M.method('getClock', () => M.clockState())

  // MARK: Particles, panoramas

  const particles = new Map()
  M.method('addParticleSystem', (a) => {
    const id = a.id || `particles${Date.now()}`
    if (particles.has(id)) M.viewer.scene.primitives.remove(particles.get(id))
    const emitterType = M.norm(a.emitter || 'cone')
    const emitter =
      emitterType === 'box' ? new C.BoxEmitter(new C.Cartesian3(a.emitterSize || 10, a.emitterSize || 10, a.emitterSize || 10)) : emitterType === 'circle' ? new C.CircleEmitter(a.emitterRadius || 5) : emitterType === 'sphere' ? new C.SphereEmitter(a.emitterRadius || 5) : new C.ConeEmitter(M.toRad(a.emitterAngle || 30))
    const system = new C.ParticleSystem({
      image: a.image ? M.resource(a.image) : C.buildModuleUrl('Assets/Textures/moonSmall.jpg'),
      startColor: M.color(a.startColor, '#ffffff'),
      endColor: M.color(a.endColor, '#ffffff00'),
      startScale: M.num(a.startScale, 1),
      endScale: M.num(a.endScale, 4),
      minimumParticleLife: M.num(a.minimumParticleLife, 1),
      maximumParticleLife: M.num(a.maximumParticleLife, 3),
      minimumSpeed: M.num(a.minimumSpeed, 1),
      maximumSpeed: M.num(a.maximumSpeed, 4),
      imageSize: new C.Cartesian2(M.num(a.imageSize, 10), M.num(a.imageSize, 10)),
      sizeInMeters: a.sizeInMeters !== false,
      emissionRate: M.num(a.emissionRate, 10),
      lifetime: M.num(a.lifetime, 16),
      loop: a.loop !== false,
      emitter,
      modelMatrix: C.Transforms.eastNorthUpToFixedFrame(M.cartesian(a.position, 0)),
      bursts: (a.bursts || []).map((b) => new C.ParticleBurst(b)),
    })
    M.viewer.scene.primitives.add(system)
    particles.set(id, system)
    M.continuous[`particles:${id}`] = true
    return { id }
  })

  M.method('removeParticleSystem', (a) => {
    const s = particles.get(a.id)
    if (!s) return { removed: false }
    particles.delete(a.id)
    delete M.continuous[`particles:${a.id}`]
    return { removed: M.viewer.scene.primitives.remove(s) }
  })

  const panoramas = new Map()
  M.method('loadPanorama', async (a) => {
    const id = a.id || 'panorama'
    if (panoramas.has(id)) M.viewer.scene.primitives.remove(panoramas.get(id))
    const type = M.norm(a.type || 'equirectangular')
    let primitive
    if (type === 'googlestreetview') {
      const provider = await C.GoogleStreetViewCubeMapPanoramaProvider.fromUrl({ key: a.key })
      const carto = C.Cartographic.fromDegrees(a.longitude, a.latitude, a.height || 0)
      let panoId = a.panoId
      if (!panoId) {
        const found = await provider.getNearestPanoId(carto, a.radius)
        panoId = found && found.panoId
      }
      primitive = await provider.loadPanorama({ cartographic: carto, panoId })
    } else {
      const position = M.cartesian(a, a.height || 0)
      const transform = C.Transforms.headingPitchRollToFixedFrame(position, hpr({ heading: a.heading || 0, pitch: a.pitch || 0, roll: a.roll || 0 }))
      const options = { transform, image: M.resource(a.image), radius: a.radius }
      primitive = type === 'cubemap' ? new C.CubeMapPanorama(Object.assign(options, { sources: a.sources })) : new C.EquirectangularPanorama(options)
    }
    M.viewer.scene.primitives.add(primitive)
    panoramas.set(id, primitive)
    return { id }
  })

  M.method('removePanorama', (a) => {
    const p = panoramas.get(a.id || 'panorama')
    if (!p) return { removed: false }
    panoramas.delete(a.id || 'panorama')
    return { removed: M.viewer.scene.primitives.remove(p) }
  })

  // MARK: munim models on Cesium

  function modelOf(id) {
    const rt = M.modelRuntime(id)
    if (!rt || !rt.model) throw new Error(`model "${id}" is not a loaded glTF model`)
    return rt.model
  }

  M.method('modelInfo', (a) => {
    const model = modelOf(a.id)
    const animations = []
    const gltfAnimations = model.sceneGraph && model.sceneGraph.components ? model.sceneGraph.components.animations || [] : []
    gltfAnimations.forEach((anim, index) => animations.push({ index, name: anim.name }))
    const sphere = model.boundingSphere
    return { animations, radius: sphere ? sphere.radius : 0, scale: model.scale }
  })

  M.method('playModelAnimation', (a) => {
    const model = modelOf(a.id)
    const options = { loop: M.enumValue(C.ModelAnimationLoop, a.loop || 'repeat', C.ModelAnimationLoop.REPEAT), multiplier: M.num(a.multiplier, 1), reverse: !!a.reverse }
    if (a.name !== undefined) options.name = a.name
    else if (a.index !== undefined) options.index = a.index
    else return model.activeAnimations.addAll(options) && null
    model.activeAnimations.add(options)
  })

  M.method('stopModelAnimations', (a) => {
    modelOf(a.id).activeAnimations.removeAll()
  })

  M.method('setModelNode', (a) => {
    const model = modelOf(a.id)
    const node = model.getNode(a.node)
    if (!node) throw new Error(`no node "${a.node}"`)
    if (a.show !== undefined) node.show = !!a.show
    if (a.matrix) node.matrix = C.Matrix4.fromArray(a.matrix)
  })

  M.method('setModelStyle', (a) => {
    const model = modelOf(a.id)
    if (a.color !== undefined) model.color = a.color ? M.color(a.color) : undefined
    if (a.colorBlendMode !== undefined) model.colorBlendMode = M.enumValue(C.ColorBlendMode, a.colorBlendMode, C.ColorBlendMode.HIGHLIGHT)
    if (a.colorBlendAmount !== undefined) model.colorBlendAmount = a.colorBlendAmount
    if (a.silhouetteColor !== undefined) model.silhouetteColor = M.color(a.silhouetteColor)
    if (a.silhouetteSize !== undefined) model.silhouetteSize = a.silhouetteSize
    if (a.minimumPixelSize !== undefined) model.minimumPixelSize = a.minimumPixelSize
    if (a.maximumScale !== undefined) model.maximumScale = a.maximumScale
    if (a.shadows !== undefined) model.shadows = M.enumValue(C.ShadowMode, a.shadows, C.ShadowMode.ENABLED)
    if (a.customShader !== undefined) model.customShader = a.customShader ? M.customShader(a.customShader) : undefined
    if (a.debugWireframe !== undefined) model.debugWireframe = !!a.debugWireframe
    if (a.showOutline !== undefined) model.showOutline = !!a.showOutline
  })

  // MARK: Escape hatch and info

  M.method('evaluate', (a) => {
    if (M.options().allowEvaluate !== true) throw new Error('evaluate needs cesium={{ allowEvaluate: true }}')
    // eslint-disable-next-line no-new-func
    const fn = new Function('Cesium', 'viewer', 'munim', a.script)
    return Promise.resolve(fn(C, M.viewer, M)).then((value) => {
      try {
        return JSON.parse(JSON.stringify(value === undefined ? null : value))
      } catch (e) {
        return String(value)
      }
    })
  })

  M.method('version', () => ({ cesium: C.VERSION, bridge: 1 }))

  M.method('stats', () => {
    const scene = M.viewer.scene
    return {
      sceneMode: M.sceneModeName(),
      imageryLayers: M.viewer.imageryLayers.length,
      dataSources: M.viewer.dataSources.length,
      primitives: scene.primitives.length,
      terrain: M.drawsTerrain(),
      tilesLoaded: scene.globe.tilesLoaded,
      resolutionScale: M.viewer.resolutionScale,
      pixelRatio: scene.pixelRatio,
      drawingBuffer: { width: scene.drawingBufferWidth, height: scene.drawingBufferHeight },
      webgl2: !!scene.context.webgl2,
    }
  })
})()
