// MapLibre commands (`maplibreCommands(ref)` / `providerCommand`) on GL JS:
// the same names and arguments as the MapLibre Native engine, plus what
// only GL JS has (projection, terrain, sky, terrain heights) and
// `evaluate` (with `maplibre.allowEvaluate`) for anything else.
/* global maplibregl */
;(function () {
  'use strict'
  const M = window.munimMapLibre

  function feature(f) {
    const json = typeof f.toJSON === 'function' ? f.toJSON() : f
    return { type: 'Feature', id: json.id, geometry: json.geometry, properties: json.properties || {}, layer: f.layer ? f.layer.id : undefined, source: f.source, sourceLayer: f.sourceLayer, state: f.state }
  }

  function geojsonSource(id) {
    const source = M.map.getSource(id)
    if (!source) throw new Error(`no source '${id}'`)
    return source
  }

  function layer(id) {
    if (!M.map.getLayer(id)) throw new Error(`no layer '${id}'`)
    return id
  }

  // Queries
  M.method('queryRenderedFeatures', (a) => {
    const options = {}
    if (a.layers) options.layers = a.layers.filter((id) => M.map.getLayer(id))
    if (a.filter) options.filter = a.filter
    let geometry
    if (a.point) geometry = [a.point.x, a.point.y]
    else if (a.box) {
      geometry = [
        [a.box.x, a.box.y],
        [a.box.x + a.box.width, a.box.y + a.box.height],
      ]
    }
    if (a.layers && options.layers.length === 0) return []
    return (geometry ? M.map.queryRenderedFeatures(geometry, options) : M.map.queryRenderedFeatures(options)).map(feature)
  })
  M.method('querySourceFeatures', (a) => {
    geojsonSource(a.source)
    const layers = a.sourceLayers && a.sourceLayers.length ? a.sourceLayers : [undefined]
    const out = []
    for (const sourceLayer of layers) out.push(...M.map.querySourceFeatures(a.source, { sourceLayer, filter: a.filter }).map(feature))
    return out
  })
  M.method('getClusterLeaves', async (a) => (await geojsonSource(a.source).getClusterLeaves(a.clusterId, M.num(a.limit, 10), M.num(a.offset, 0))).map(feature))
  M.method('getClusterChildren', async (a) => (await geojsonSource(a.source).getClusterChildren(a.clusterId)).map(feature))
  M.method('getClusterExpansionZoom', (a) => geojsonSource(a.source).getClusterExpansionZoom(a.clusterId))
  M.method('metersPerPoint', (a) => M.metersPerPoint(M.num(a.latitude, M.map.getCenter().lat), M.map.getZoom()))

  // Runtime styling
  M.method('getStyle', () => {
    const style = M.map.getStyle()
    return { layers: (style.layers || []).map((l) => l.id), sources: Object.keys(style.sources || {}), json: JSON.stringify(style) }
  })
  M.method('reloadStyle', () => M.loadStyle(true))
  M.method('addSource', (a) => {
    if (M.map.getSource(a.id)) throw new Error(`source '${a.id}' exists`)
    M.map.addSource(a.id, a.source)
  })
  M.method('removeSource', (a) => {
    if (!M.map.getSource(a.id)) return false
    for (const l of M.map.getStyle().layers || []) if (l.source === a.id) M.map.removeLayer(l.id)
    M.map.removeSource(a.id)
    return true
  })
  M.method('setGeoJson', (a) => {
    const source = geojsonSource(a.source)
    if (typeof source.setData !== 'function') throw new Error(`'${a.source}' is not a GeoJSON source`)
    source.setData(a.data)
  })
  M.method('addLayer', (a) => {
    const spec = Object.assign({}, a)
    const before = spec.beforeId
    delete spec.beforeId
    M.map.addLayer(spec, before && M.map.getLayer(before) ? before : M.userSlot(M.map))
  })
  M.method('removeLayer', (a) => {
    if (!M.map.getLayer(a.id)) return false
    M.map.removeLayer(a.id)
    return true
  })
  M.method('moveLayer', (a) => M.map.moveLayer(layer(a.id), a.beforeId && M.map.getLayer(a.beforeId) ? a.beforeId : undefined))
  M.method('setPaintProperty', (a) => M.map.setPaintProperty(layer(a.layer), a.name, a.value))
  M.method('setLayoutProperty', (a) => M.map.setLayoutProperty(layer(a.layer), a.name, a.value))
  M.method('setFilter', (a) => M.map.setFilter(layer(a.layer), a.filter == null ? null : a.filter))
  M.method('setLayerZoomRange', (a) => M.map.setLayerZoomRange(layer(a.layer), M.num(a.minzoom, 0), M.num(a.maxzoom, 24)))
  M.method('addImage', (a) => M.addStyleImage(M.map, a.name, { uri: a.uri, sdf: !!a.sdf }))
  M.method('removeImage', (a) => {
    if (M.map.hasImage(a.name)) M.map.removeImage(a.name)
  })
  M.method('setLight', (a) => M.map.setLight(a.light || {}))
  function featureTarget(a) {
    const target = { source: a.source, id: a.id }
    if (a.sourceLayer) target.sourceLayer = a.sourceLayer
    return target
  }
  M.method('setFeatureState', (a) => M.map.setFeatureState(featureTarget(a), a.state || {}))
  M.method('getFeatureState', (a) => M.map.getFeatureState(featureTarget(a)))
  M.method('removeFeatureState', (a) => {
    const target = { source: a.source }
    if (a.sourceLayer) target.sourceLayer = a.sourceLayer
    if (a.id != null) target.id = a.id
    M.map.removeFeatureState(target, a.key)
  })

  // Camera
  M.method('flyTo', (a) => {
    M.stopFlight()
    const view = M.viewForCamera(a.camera || M.munimCamera())
    M.map.flyTo(Object.assign(view, { duration: M.num(a.durationMs, 1500), essential: true }))
  })
  M.method('resetNorth', () => M.map.resetNorth({ duration: 300 }))
  M.method('resetPosition', () => M.map.resetNorthPitch({ duration: 300 }))
  M.method('easeTo', (a) => {
    const o = Object.assign({}, a)
    if (o.easing) delete o.easing
    M.map.easeTo(Object.assign({ essential: true }, o))
  })
  M.method('jumpTo', (a) => M.map.jumpTo(a))

  // GL JS only: projection, terrain, sky
  M.method('setProjection', (a) => {
    const p = a.projection
    M.map.setProjection(typeof p === 'string' ? { type: p } : p || { type: 'mercator' })
  })
  M.method('getProjection', () => M.map.getProjection() || { type: 'mercator' })
  M.method('isGlobe', () => M.isGlobe())
  M.method('setTerrain', (a) => {
    if (!a.terrain) {
      M.map.setTerrain(null)
      return
    }
    const t = a.terrain === true ? {} : a.terrain
    const source = t.source && M.map.getSource(t.source) ? t.source : M.demSource(M.map, 'munim-terrain-dem', t)
    M.map.setTerrain({ source, exaggeration: M.num(t.exaggeration, 1) })
  })
  M.method('getTerrain', () => M.map.getTerrain() || null)
  M.method('queryTerrainElevation', (a) => {
    const c = a.coordinate || a
    return M.map.queryTerrainElevation([c.longitude, c.latitude])
  })
  M.method('setSky', (a) => M.map.setSky(a.sky || undefined))
  M.method('getSky', () => M.map.getSky() || null)
  M.method('getRenderer', () => ({ renderer: 'web', maplibre: M.version(), three: M.threeVersion ? M.threeVersion() : '' }))
  M.method('version', () => M.version())

  // Snapshots: the view (the map and the 3D layer; markers are DOM), or an
  // offscreen map with any style, camera and size.
  function canvasPng(map) {
    return new Promise((resolve, reject) => {
      map.once('render', () => {
        try {
          resolve(map.getCanvas().toDataURL('image/png').replace(/^data:image\/png;base64,/, ''))
        } catch (e) {
          reject(e)
        }
      })
      map.triggerRepaint()
    })
  }

  function resized(base64, width, height) {
    if (!(width > 0 && height > 0)) return Promise.resolve(base64)
    return new Promise((resolve, reject) => {
      const img = new Image()
      img.onload = () => {
        const c = document.createElement('canvas')
        c.width = Math.round(width)
        c.height = Math.round(height)
        const ctx = c.getContext('2d')
        const ratio = Math.max(c.width / img.width, c.height / img.height)
        const sw = c.width / ratio
        const sh = c.height / ratio
        ctx.drawImage(img, (img.width - sw) / 2, (img.height - sh) / 2, sw, sh, 0, 0, c.width, c.height)
        resolve(c.toDataURL('image/png').replace(/^data:image\/png;base64,/, ''))
      }
      img.onerror = reject
      img.src = `data:image/png;base64,${base64}`
    })
  }

  M.method('snapshot', async (a) => resized(await canvasPng(M.map), M.num(a.width, 0), M.num(a.height, 0)))

  M.method('snapshotOffscreen', (a) => {
    const width = Math.max(16, M.num(a.width, 512))
    const height = Math.max(16, M.num(a.height, 512))
    const div = document.createElement('div')
    div.style.cssText = `position:absolute;left:-${width + 100}px;top:0;width:${width}px;height:${height}px;`
    document.body.appendChild(div)
    const cam = a.camera || M.munimCamera()
    const view = cam.zoom != null ? { center: [cam.longitude, cam.latitude], zoom: cam.zoom, pitch: M.num(cam.pitch, 0), bearing: M.num(cam.heading, 0) } : M.viewForCamera(cam, height)
    const style = a.styleUrl || M.map.getStyle()
    const map = new maplibregl.Map(Object.assign({ container: div, style, interactive: false, attributionControl: false, maplibreLogo: !!a.showsLogo, canvasContextAttributes: { preserveDrawingBuffer: true }, fadeDuration: 0 }, view))
    const done = () => {
      map.remove()
      div.remove()
    }
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        done()
        reject(new Error('the snapshot timed out'))
      }, 30000)
      map.once('idle', () => {
        clearTimeout(timer)
        try {
          const data = map.getCanvas().toDataURL('image/png').replace(/^data:image\/png;base64,/, '')
          done()
          resolve(data)
        } catch (e) {
          done()
          reject(e)
        }
      })
      map.on('error', (e) => {
        if (e && e.error && /style/i.test(String(e.error.message))) {
          clearTimeout(timer)
          done()
          reject(e.error)
        }
      })
    })
  })

  // MapLibre Native's offline packs and connectivity switch: GL JS has neither.
  const nativeOnly = 'is MapLibre Native only (renderer "native"); GL JS keeps tiles in the WebView HTTP cache'
  for (const name of ['offlineCreatePack', 'offlineListPacks', 'offlineResumePack', 'offlineSuspendPack', 'offlineDeletePack', 'offlineInvalidatePack', 'offlineSetAmbientCacheSize', 'offlineClearAmbientCache', 'offlineInvalidateAmbientCache', 'offlineResetDatabase', 'offlineMergeDatabase', 'setConnected']) {
    M.method(name, () => {
      throw new Error(`${name} ${nativeOnly}`)
    })
  }

  // Anything else in GL JS (opt-in).
  M.method('evaluate', (a) => {
    if (!M.options().allowEvaluate) throw new Error('evaluate needs maplibre={{ allowEvaluate: true }}')
    // eslint-disable-next-line no-new-func
    const fn = new Function('map', 'maplibregl', 'munim', `return (async () => { ${a.script || ''} })()`)
    return fn(M.map, maplibregl, M)
  })
})()
