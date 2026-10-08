// The map itself: MapLibre GL JS's Map with the style munim-maps asks for
// (styleUrl, presets, JSON, dark, imagery), and everything GL JS has that
// MapLibre Native does not: the globe projection, 3D terrain from a
// raster-dem source, sky and atmosphere. Runtime style content
// (`maplibre.sources`, `layers`, `images`, `light`, hillshade, colour
// relief) comes back after every style load, before munim's own markers,
// shapes and 3D layer (features.js, models.js hook into `styleHooks`).
/* global maplibregl */
;(function () {
  'use strict'
  const M = window.munimMapLibre

  // MARK: Style

  const PRESETS = {
    liberty: 'https://tiles.openfreemap.org/styles/liberty',
    bright: 'https://tiles.openfreemap.org/styles/bright',
    positron: 'https://tiles.openfreemap.org/styles/positron',
    dark: 'https://tiles.openfreemap.org/styles/dark',
    fiord: 'https://tiles.openfreemap.org/styles/fiord',
    demotiles: 'https://demotiles.maplibre.org/style.json',
    'maptiler-streets': 'https://api.maptiler.com/maps/streets-v2/style.json?key={key}',
    'maptiler-outdoor': 'https://api.maptiler.com/maps/outdoor-v2/style.json?key={key}',
    'maptiler-satellite': 'https://api.maptiler.com/maps/satellite/style.json?key={key}',
    'maptiler-hybrid': 'https://api.maptiler.com/maps/hybrid/style.json?key={key}',
    'maptiler-dataviz': 'https://api.maptiler.com/maps/dataviz/style.json?key={key}',
    'stadia-alidade-smooth': 'https://tiles.stadiamaps.com/styles/alidade_smooth.json?api_key={key}',
    'stadia-alidade-smooth-dark': 'https://tiles.stadiamaps.com/styles/alidade_smooth_dark.json?api_key={key}',
    'stadia-outdoors': 'https://tiles.stadiamaps.com/styles/outdoors.json?api_key={key}',
    'stadia-osm-bright': 'https://tiles.stadiamaps.com/styles/osm_bright.json?api_key={key}',
  }
  M.PRESETS = PRESETS
  const DEFAULT_STYLE = PRESETS.liberty
  /** AWS Terrain Tiles (Terrarium encoding, keyless, public dataset). */
  M.TERRARIUM = 'https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png'

  function preset(name) {
    if (!name) return undefined
    const url = PRESETS[name]
    if (!url) return /:\/\//.test(name) ? name : undefined
    if (url.includes('{key}')) {
      const key = M.options().apiKey
      if (!key) {
        M.error(`the '${name}' style needs maplibre.apiKey`)
        return undefined
      }
      return url.replace('{key}', encodeURIComponent(key))
    }
    return url
  }

  /** The style to show: JSON, URL, preset, dark, muted. Returns `{ key, style }`. */
  M.resolveStyle = function () {
    const o = M.options()
    if (o.styleJson != null) {
      const style = typeof o.styleJson === 'string' ? JSON.parse(o.styleJson) : o.styleJson
      return { key: `json:${JSON.stringify(style).length}:${JSON.stringify(style).slice(0, 200)}`, style }
    }
    const styleUrl = M.state.styleUrl || ''
    const explicit = styleUrl || preset(o.style) || ''
    const wantsDark = M.isDark() && !styleUrl && (!o.style || !!o.darkStyle)
    let url
    if (wantsDark) url = preset(o.darkStyle || 'dark') || explicit
    else if (explicit) url = explicit
    else if (M.norm(M.state.mapStyle) === 'muted') url = PRESETS.positron
    else url = M.env.defaultStyleUrl || DEFAULT_STYLE
    return { key: url, style: url }
  }

  let loadedStyleKey = ''

  /** Loads the style when what it resolves to changed (or always with `force`). */
  M.loadStyle = function (force) {
    const map = M.map
    if (!map) return
    let resolved
    try {
      resolved = M.resolveStyle()
    } catch (e) {
      M.error('styleJson is not valid JSON', e)
      return
    }
    if (!force && resolved.key === loadedStyleKey) return
    loadedStyleKey = resolved.key
    map.setStyle(resolved.style, { diff: false })
  }

  // MARK: The map

  function transformRequest(url) {
    const headers = M.options().httpHeaders
    let target = url
    // OpenStreetMap's raster tiles ask apps to identify themselves; WebKit
    // sends no Referer from the engine's URL scheme, so they go through it.
    if (M.env.tileProxy && /^https:\/\/([a-c]\.)?tile\.openstreetmap\.org\//i.test(url)) target = M.tileUrl(url)
    return headers && Object.keys(headers).length ? { url: target, headers } : { url: target }
  }

  /** Makes the map (once): the first `init` from the app. */
  M.createMap = function () {
    const o = M.options()
    const cam = M.state.initialCamera
    const container = document.getElementById('map')
    const options = {
      container,
      style: { version: 8, sources: {}, layers: [{ id: 'munim-background', type: 'background', paint: { 'background-color': M.isDark() ? '#1c1c1e' : '#f2efe9' } }] },
      attributionControl: false,
      maplibreLogo: false,
      maxPitch: 85,
      fadeDuration: o.fadeDuration != null ? o.fadeDuration : 300,
      canvasContextAttributes: { antialias: true, powerPreference: 'high-performance' },
      transformRequest,
      validateStyle: false,
      dragRotate: true,
      pitchWithRotate: true,
      touchPitch: true,
      renderWorldCopies: o.renderWorldCopies !== false,
      cancelPendingTileRequestsWhileZooming: true,
    }
    if (o.localIdeographFontFamily) options.localIdeographFontFamily = o.localIdeographFontFamily
    if (M.num(o.pixelRatio, 0) > 0) options.pixelRatio = o.pixelRatio
    if (cam && cam.distance > 0) {
      const view = M.viewForCamera(cam, container.clientHeight || window.innerHeight)
      options.center = view.center
      options.zoom = view.zoom
      options.pitch = view.pitch
      options.bearing = view.bearing
    }
    const map = new maplibregl.Map(options)
    M.map = map
    lastOptions = JSON.stringify(o)
    window.munimMap = map
    map.touchZoomRotate.enable()
    map.on('style.load', () => onStyleLoad(map))
    map.on('error', (e) => {
      const err = e && e.error
      const message = err && err.message ? err.message : String(err || 'error')
      // Tiles that fail (offline, 404 at the edge of a source) are not worth an onError each.
      if (e.tile || /tile/i.test(message) || (err && err.status === 404)) return
      M.providerEvent('mapLoadFailed', { message })
      M.error('map error', err || message)
    })
    map.on('styleimagemissing', (e) => M.providerEvent('styleImageMissing', { name: e.id }))
    map.on('idle', () => {
      M.providerEvent('idle', {})
      M.providerEvent('renderedMap', { fullyRendered: true })
    })
    map.on('sourcedata', (e) => {
      if (e.sourceId && e.isSourceLoaded && e.sourceDataType !== 'metadata' && !String(e.sourceId).startsWith('munim-')) {
        M.providerEvent('sourceChanged', { source: e.sourceId })
      }
    })
    map.on('webglcontextlost', () => M.providerEvent('renderError', { message: 'WebGL context lost' }))
    map.on('projectiontransition', (e) => M.providerEvent('projectionTransition', { projection: e && e.newProjection }))
    for (const hook of M.mapHooks) {
      try {
        hook(map)
      } catch (e) {
        M.error('map hook', e)
      }
    }
    M.applyGestures()
    M.applyLimits()
    M.applyMapOptions()
    M.loadStyle(true)
    return map
  }

  let readySent = false
  function onStyleLoad(map) {
    const steps = [
      ['imagery', applyImagery],
      ['runtime style', applyRuntimeStyle],
      ['buildings', M.applyBuildings],
      ['points of interest', M.applyPointsOfInterest],
      ['label language', applyLabelLanguage],
      ['projection', M.applyProjection],
      ['terrain', M.applyTerrain],
      ['sky', M.applySky],
    ]
    for (const [name, fn] of steps) {
      try {
        fn(map)
      } catch (e) {
        M.error(`could not apply ${name}`, e)
      }
    }
    for (const hook of M.styleHooks) {
      try {
        hook(map)
      } catch (e) {
        M.error('style hook', e)
      }
    }
    M.providerEvent('styleLoaded', { style: loadedStyleKey })
    if (!readySent) {
      readySent = true
      const ready = () => M.emit('mapReady', { maplibre: M.version() })
      // Ready once the first frame of the style is drawn.
      map.once('render', ready)
      map.triggerRepaint()
    }
  }

  // MARK: Imagery (`mapStyle` imagery / hybrid)

  function applyImagery(map) {
    const mode = M.norm(M.state.mapStyle)
    if (mode !== 'imagery' && mode !== 'hybrid') return
    const tiles = M.options().satelliteTilesUrl
    if (!tiles) {
      M.error(`mapStyle '${M.state.mapStyle}' needs maplibre.satelliteTilesUrl (there is no keyless satellite imagery)`)
      return
    }
    map.addSource('munim-imagery', { type: 'raster', tiles: [tiles], tileSize: 256 })
    const layers = map.getStyle().layers || []
    if (mode === 'imagery') {
      for (const l of layers) map.setLayoutProperty(l.id, 'visibility', 'none')
      map.addLayer({ id: 'munim-imagery', type: 'raster', source: 'munim-imagery' })
    } else {
      const first = layers.find((l) => l.type === 'line' || l.type === 'symbol')
      map.addLayer({ id: 'munim-imagery', type: 'raster', source: 'munim-imagery' }, first && first.id)
      for (const l of layers) if (l.type === 'fill' || l.type === 'fill-extrusion') map.setLayoutProperty(l.id, 'visibility', 'none')
    }
  }

  // MARK: Runtime style (the style spec, from `maplibre={{…}}`)

  let userSources = []
  let userLayers = []
  let lastOptions = '{}'
  let lastRuntime = ''

  /** The first road or label layer: hillshade and relief go under it. */
  M.firstRoadLayer = function (map) {
    const words = ['road', 'highway', 'street', 'transport', 'tunnel', 'bridge', 'aeroway', 'rail']
    const layer = (map.getStyle().layers || []).find((l) => l.type === 'symbol' || (l.type === 'line' && words.some((w) => l.id.toLowerCase().includes(w))))
    return layer && layer.id
  }

  /** Where user layers go by default: under munim-maps' own markers and shapes. */
  M.userSlot = function (map) {
    const layer = (map.getStyle().layers || []).find((l) => l.id.startsWith('munim-shape') || l.id.startsWith('munim-3d') || l.id.startsWith('munim-user'))
    return layer && layer.id
  }

  function demSource(map, id, json) {
    if (map.getSource(id)) return id
    const j = json && typeof json === 'object' ? json : {}
    const source = { type: 'raster-dem', tileSize: M.num(j.tileSize, 256), maxzoom: M.num(j.maxzoom, 15), encoding: j.encoding || 'terrarium' }
    if (j.url) source.url = j.url
    else source.tiles = j.tiles || [M.TERRARIUM]
    if (j.attribution) source.attribution = j.attribution
    map.addSource(id, source)
    return id
  }
  M.demSource = demSource

  function addImage(map, name, value) {
    const uri = typeof value === 'string' ? value : value && value.uri
    const sdf = !!(value && value.sdf)
    if (!uri) return Promise.resolve()
    return map
      .loadImage(M.resource(uri))
      .then((res) => {
        if (!M.map || M.map !== map) return
        if (map.hasImage(name)) map.removeImage(name)
        map.addImage(name, res.data, { sdf, pixelRatio: value && value.pixelRatio ? value.pixelRatio : 1 })
      })
      .catch((e) => M.error(`image '${name}'`, e))
  }
  M.addStyleImage = addImage

  function applyRuntimeStyle(map) {
    const o = M.options()
    for (const id of userLayers) if (map.getLayer(id)) map.removeLayer(id)
    for (const id of userSources) if (map.getSource(id)) map.removeSource(id)
    userLayers = []
    userSources = []
    lastRuntime = runtimeKey()
    if (o.transition && map.style && map.style.stylesheet) {
      map.style.stylesheet.transition = { duration: M.num(o.transition.duration, 300), delay: M.num(o.transition.delay, 0) }
    }
    if (o.light) map.setLight(o.light)
    for (const [name, value] of Object.entries(o.images || {})) addImage(map, name, value)
    for (const [id, source] of Object.entries(o.sources || {})) {
      try {
        if (map.getSource(id)) {
          for (const l of map.getStyle().layers || []) if (l.source === id) map.removeLayer(l.id)
          map.removeSource(id)
        }
        map.addSource(id, source)
        userSources.push(id)
      } catch (e) {
        M.error(`source '${id}'`, e)
      }
    }
    const below = M.firstRoadLayer(map)
    const shade = o.hillshade
    if (shade === true || (shade && typeof shade === 'object')) {
      const j = typeof shade === 'object' ? shade : {}
      userSources.push(demSource(map, 'munim-dem', j))
      const paint = {}
      if (j.exaggeration != null) paint['hillshade-exaggeration'] = j.exaggeration
      if (j.shadowColor) paint['hillshade-shadow-color'] = j.shadowColor
      if (j.highlightColor) paint['hillshade-highlight-color'] = j.highlightColor
      if (j.accentColor) paint['hillshade-accent-color'] = j.accentColor
      if (j.illuminationDirection != null) paint['hillshade-illumination-direction'] = j.illuminationDirection
      if (j.method) paint['hillshade-method'] = j.method
      map.addLayer({ id: 'munim-hillshade', type: 'hillshade', source: 'munim-dem', paint }, j.beforeId || below)
      userLayers.push('munim-hillshade')
    }
    const relief = o.colorRelief
    if (relief === true || (relief && typeof relief === 'object')) {
      const j = typeof relief === 'object' ? relief : {}
      userSources.push(demSource(map, 'munim-dem-relief', j))
      const stops = j.stops || [0, '#2f6b3a', 500, '#9cba6a', 1500, '#e2c98f', 2500, '#a87c56', 4000, '#ffffff']
      map.addLayer(
        {
          id: 'munim-color-relief',
          type: 'color-relief',
          source: 'munim-dem-relief',
          paint: { 'color-relief-color': ['interpolate', ['linear'], ['elevation'], ...stops], 'color-relief-opacity': j.opacity != null ? j.opacity : 0.6 },
        },
        j.beforeId || below
      )
      userLayers.push('munim-color-relief')
    }
    for (const layer of o.layers || []) {
      try {
        const spec = Object.assign({}, layer)
        const before = spec.beforeId
        delete spec.beforeId
        if (map.getLayer(spec.id)) map.removeLayer(spec.id)
        map.addLayer(spec, before && map.getLayer(before) ? before : M.userSlot(map))
        userLayers.push(spec.id)
      } catch (e) {
        M.error(`layer '${layer && layer.id}'`, e)
      }
    }
  }

  function runtimeKey() {
    const o = M.options()
    return JSON.stringify(['sources', 'layers', 'images', 'light', 'transition', 'hillshade', 'colorRelief'].map((k) => o[k]))
  }

  // MARK: Base map layers

  function layersOfSourceLayer(map, name) {
    return (map.getStyle().layers || []).filter((l) => l['source-layer'] === name)
  }

  M.applyBuildings = function (map = M.map) {
    if (!map || !map.style) return
    const show = M.state.showsBuildings !== false
    for (const l of layersOfSourceLayer(map, 'building')) map.setLayoutProperty(l.id, 'visibility', show ? 'visible' : 'none')
  }

  /** MapKit categories (`MKPOICategoryCafe`, `cafe`) to OpenMapTiles `class` names. */
  const CLASS_NAMES = {
    atm: 'atm',
    cafe: 'cafe',
    evcharger: 'charging_station',
    fitnesscenter: 'fitness',
    foodmarket: 'grocery',
    gasstation: 'fuel',
    movietheater: 'cinema',
    nationalpark: 'park',
    nightlife: 'bar',
    postoffice: 'post',
    publictransport: 'bus',
    restroom: 'toilets',
    store: 'shop',
    university: 'college',
  }
  function className(category) {
    const raw = String(category).replace(/^MKPOICategory/, '')
    const key = raw.toLowerCase()
    return CLASS_NAMES[key] || raw.charAt(0).toLowerCase() + raw.slice(1)
  }

  const originalPoiFilters = new Map()
  M.applyPointsOfInterest = function (map = M.map) {
    if (!map || !map.style) return
    const filter = String(M.state.pointsOfInterest || 'all').trim()
    for (const l of layersOfSourceLayer(map, 'poi')) {
      if (l.type !== 'symbol') continue
      if (!originalPoiFilters.has(l.id)) originalPoiFilters.set(l.id, l.filter)
      const original = originalPoiFilters.get(l.id)
      if (filter === '' || filter === 'all') {
        map.setLayoutProperty(l.id, 'visibility', 'visible')
        map.setFilter(l.id, original || null)
      } else if (filter === 'none') {
        map.setLayoutProperty(l.id, 'visibility', 'none')
      } else {
        const classes = filter
          .split(',')
          .map((c) => c.trim())
          .filter(Boolean)
          .map(className)
        const wanted = ['match', ['get', 'class'], classes.length ? classes : ['none'], true, false]
        map.setLayoutProperty(l.id, 'visibility', 'visible')
        map.setFilter(l.id, original ? ['all', original, wanted] : wanted)
      }
    }
  }

  function applyLabelLanguage(map) {
    const language = String(M.options().labelLanguage || '').trim()
    if (!language) return
    const localized = ['coalesce', ['get', `name:${language}`], ['get', 'name_int'], ['get', 'name']]
    for (const l of map.getStyle().layers || []) {
      if (l.type !== 'symbol' || l.id.startsWith('munim-')) continue
      const field = l.layout && l.layout['text-field']
      if (field && JSON.stringify(field).includes('name')) map.setLayoutProperty(l.id, 'text-field', localized)
    }
  }

  // MARK: Globe, terrain, sky (GL JS only)

  /** The projection asked for: `globe` prop, `maplibre.projection`, else Mercator. */
  M.wantedProjection = function () {
    const p = M.options().projection
    if (p && typeof p === 'object') return p
    if (M.state.globe || p === 'globe') return { type: 'globe' }
    if (p === 'vertical-perspective') return { type: 'vertical-perspective' }
    return { type: 'mercator' }
  }

  M.applyProjection = function (map = M.map) {
    if (!map || !map.style) return
    const projection = M.wantedProjection()
    map.setProjection(projection)
    // Space around the globe (GL JS leaves it transparent).
    document.body.classList.toggle('munim-globe', projection.type !== 'mercator')
  }

  M.isGlobe = function () {
    const map = M.map
    if (!map || !map.style) return false
    try {
      return !!(map.transform && map.transform.getProjectionDataForCustomLayer && map.transform.getProjectionDataForCustomLayer(true).projectionTransition > 0)
    } catch (e) {
      return false
    }
  }

  /** `maplibre.terrain`: true or `{ tiles | url | source, encoding, exaggeration, … }`; off with `elevation="flat"`. */
  M.terrainOptions = function () {
    const t = M.options().terrain
    if (!t || M.norm(M.state.elevation) === 'flat') return undefined
    return t === true ? {} : t
  }

  M.applyTerrain = function (map = M.map) {
    if (!map || !map.style) return
    const t = M.terrainOptions()
    if (!t) {
      if (map.getTerrain()) map.setTerrain(null)
      return
    }
    const source = t.source && map.getSource(t.source) ? t.source : demSource(map, 'munim-terrain-dem', t)
    map.setTerrain({ source, exaggeration: M.num(t.exaggeration, 1) })
  }

  M.drawsTerrain = () => !!(M.map && M.map.getTerrain && M.map.getTerrain())

  /** The default sky: blue above a pale horizon, with the globe's atmosphere when zoomed out. */
  function defaultSky(dark) {
    return dark
      ? {
          'sky-color': '#0b1026',
          'horizon-color': '#2a3550',
          'fog-color': '#1c2333',
          'sky-horizon-blend': 0.6,
          'horizon-fog-blend': 0.6,
          'fog-ground-blend': 0.6,
          'atmosphere-blend': ['interpolate', ['linear'], ['zoom'], 0, 1, 6, 0.6, 10, 0],
        }
      : {
          'sky-color': '#5fa3e6',
          'horizon-color': '#e8f1fb',
          'fog-color': '#ffffff',
          'sky-horizon-blend': 0.6,
          'horizon-fog-blend': 0.5,
          'fog-ground-blend': 0.6,
          'atmosphere-blend': ['interpolate', ['linear'], ['zoom'], 0, 1, 6, 0.7, 10, 0],
        }
  }

  /**
   * `maplibre.sky`: true (the default sky), false (none) or a style-spec
   * `sky`. The globe gets the default sky (its atmosphere) unless `sky` is false.
   */
  M.applySky = function (map = M.map) {
    if (!map || !map.style) return
    const s = M.options().sky
    if (s === false) {
      map.setSky(undefined)
      return
    }
    const style = map.getStyle()
    if (s && typeof s === 'object') map.setSky(Object.assign(defaultSky(M.isDark()), s))
    else if (s === true || M.wantedProjection().type !== 'mercator' || M.terrainOptions()) {
      if (!style.sky || s === true) map.setSky(defaultSky(M.isDark()))
    }
  }

  // MARK: Gestures and limits

  M.applyGestures = function () {
    const map = M.map
    if (!map) return
    const g = M.state.gestures || {}
    const o = M.options().gestures || {}
    const zoom = g.zoom !== false
    const scroll = g.scroll !== false
    const rotate = g.rotate !== false
    const pitch = g.pitch !== false
    const set = (handler, on, options) => {
      if (!handler) return
      if (on) handler.enable(options)
      else handler.disable()
    }
    const around = o.anchorToCenter ? { around: 'center' } : undefined
    set(map.scrollZoom, zoom, around)
    set(map.boxZoom, zoom)
    set(map.doubleClickZoom, zoom && o.doubleTapZoom !== false)
    set(map.dragPan, scroll)
    set(map.keyboard, scroll || zoom)
    set(map.touchZoomRotate, zoom || rotate, around)
    if (map.touchZoomRotate) {
      if (rotate) map.touchZoomRotate.enableRotation()
      else map.touchZoomRotate.disableRotation()
    }
    set(map.dragRotate, rotate || pitch)
    set(map.touchPitch, pitch, around)
    if (map.dragRotate && map.dragRotate._pitchWithRotate !== undefined) map.dragRotate._pitchWithRotate = pitch
    if (map.cooperativeGestures) {
      if (o.cooperative) map.cooperativeGestures.enable()
      else map.cooperativeGestures.disable()
    }
  }

  /** `cameraDistanceRange`, `cameraBoundary`, `maplibre.camera` limits; distances become zooms at the centre's latitude. */
  M.applyLimits = function () {
    const map = M.map
    if (!map) return
    const c = M.options().camera || {}
    let minZoom = M.num(c.minZoom, 0)
    let maxZoom = M.num(c.maxZoom, 24)
    const range = M.state.distanceRange || {}
    const lat = map.getCenter().lat
    if (range.max > 0) minZoom = Math.max(minZoom, M.zoomForDistance(range.max, lat))
    if (range.min > 0) maxZoom = Math.min(maxZoom, M.zoomForDistance(range.min, lat))
    if (maxZoom < minZoom) maxZoom = minZoom
    map.setMinZoom(minZoom)
    map.setMaxZoom(maxZoom)
    map.setMinPitch(M.num(c.minPitch, 0))
    map.setMaxPitch(M.num(c.maxPitch, 85))
    const b = M.state.boundary
    if (b && b.latitudeDelta > 0 && b.longitudeDelta > 0) {
      map.setMaxBounds([
        [b.longitude - b.longitudeDelta / 2, b.latitude - b.latitudeDelta / 2],
        [b.longitude + b.longitudeDelta / 2, b.latitude + b.latitudeDelta / 2],
      ])
    } else {
      map.setMaxBounds(null)
    }
  }

  /** `maplibre.rendering`, `pixelRatio`, ornaments: things that need no style. */
  M.applyMapOptions = function () {
    const map = M.map
    if (!map) return
    const o = M.options()
    const r = o.rendering || {}
    const debug = new Set(r.debug || [])
    map.showTileBoundaries = debug.has('tileBoundaries')
    map.showCollisionBoxes = debug.has('collisionBoxes')
    map.showOverdrawInspector = debug.has('overdraw')
    if (M.num(o.pixelRatio, 0) > 0 && map.getPixelRatio() !== o.pixelRatio) map.setPixelRatio(o.pixelRatio)
    if (r.tileCache === false) map.setMaxTileCacheSize(0)
    else if (M.num(r.maxTileCacheSize, 0) > 0) map.setMaxTileCacheSize(r.maxTileCacheSize)
    if (o.camera && o.camera.roll != null && map.setRoll) map.setRoll(o.camera.roll)
    if (o.fov != null && map.setVerticalFieldOfView) map.setVerticalFieldOfView(o.fov)
    applyOrnaments(map, o.ornaments || {})
  }

  let attribution, logo
  function corner(position, fallback) {
    switch (position) {
      case 'topLeft':
        return 'top-left'
      case 'topRight':
        return 'top-right'
      case 'bottomLeft':
        return 'bottom-left'
      case 'bottomRight':
        return 'bottom-right'
      default:
        return fallback
    }
  }

  function applyOrnaments(map, ornaments) {
    const a = ornaments.attribution || {}
    if (attribution) map.removeControl(attribution)
    attribution = undefined
    // Attribution stays on unless asked (OpenStreetMap's licence asks for it).
    if (a.visible !== false) {
      attribution = new maplibregl.AttributionControl({ compact: true })
      map.addControl(attribution, corner(a.position, 'bottom-right'))
      if (a.margin) applyMargin(attribution, a.margin)
    }
    const l = ornaments.logo || {}
    if (logo) map.removeControl(logo)
    logo = undefined
    if (l.visible) {
      logo = new maplibregl.LogoControl({ compact: true })
      map.addControl(logo, corner(l.position, 'bottom-left'))
      if (l.margin) applyMargin(logo, l.margin)
    }
  }

  function applyMargin(control, margin) {
    const el = control._container
    if (!el) return
    el.style.margin = `${M.num(margin.y, 10)}px ${M.num(margin.x, 10)}px`
  }

  // MARK: Props

  M.on('styleUrl', () => M.loadStyle(false))
  M.on('mapStyle', () => M.loadStyle(true))
  M.on('colorScheme', () => {
    document.body.classList.toggle('munim-dark', M.isDark())
    M.loadStyle(false)
    M.applySky()
  })
  M.on('options', (o) => {
    const previous = JSON.parse(lastOptions)
    lastOptions = JSON.stringify(o || {})
    const changed = (k) => JSON.stringify(previous[k]) !== JSON.stringify((o || {})[k])
    M.applyMapOptions()
    if (['style', 'styleJson', 'darkStyle', 'apiKey', 'satelliteTilesUrl', 'labelLanguage'].some(changed)) {
      M.loadStyle(true)
      return
    }
    if (!M.styleLoaded(M.map)) return
    const key = runtimeKey()
    if (key !== lastRuntime) {
      lastRuntime = key
      try {
        applyRuntimeStyle(M.map)
      } catch (e) {
        M.error('could not apply the runtime style', e)
      }
    }
    if (changed('projection')) M.applyProjection()
    if (changed('terrain')) M.applyTerrain()
    if (changed('sky') || changed('projection') || changed('terrain')) M.applySky()
    if (changed('gestures')) M.applyGestures()
    if (changed('camera')) M.applyLimits()
  })
  M.on('globe', () => {
    M.applyProjection()
    M.applySky()
  })
  M.on('elevation', () => {
    M.applyTerrain()
    M.applySky()
  })
  M.on('showsBuildings', () => M.applyBuildings())
  M.on('pointsOfInterest', () => M.applyPointsOfInterest())
  M.on('gestures', () => M.applyGestures())
  M.on('distanceRange', () => M.applyLimits())
  M.on('boundary', () => M.applyLimits())
  M.on('initialCamera', () => {})
})()
