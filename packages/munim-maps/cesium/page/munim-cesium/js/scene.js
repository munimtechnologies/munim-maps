// The viewer, the base map (imagery and terrain), 3D Tiles, the look of the
// scene (atmosphere, lighting, shadows, fog, post-processing), the clock,
// data sources and CZML entities: everything in the `cesium={{…}}` options
// that is not a camera or a munim feature.
/* global Cesium */
;(function () {
  'use strict'
  const M = window.munimCesium
  const C = Cesium

  // MARK: Viewer

  /** Options that only take effect when the viewer is made; changing them makes a new viewer. */
  const CREATION_KEYS = ['widgets', 'mapProjection', 'scene3DOnly', 'msaaSamples', 'orderIndependentTranslucency', 'contextOptions', 'useBrowserRecommendedResolution', 'mapMode2D', 'automaticallyTrackDataSourceClocks', 'creditContainer']

  function creationKey(options) {
    const picked = {}
    for (const k of CREATION_KEYS) if (options && options[k] !== undefined) picked[k] = options[k]
    return JSON.stringify(picked)
  }

  M.options = () => M.state.options || {}

  let viewerKey = ''

  M.createViewer = function () {
    const options = M.options()
    const widgets = options.widgets || {}
    if (M.viewer) M.destroyViewer()
    C.Ion.defaultAccessToken = M.env.ionToken || ''
    if (options.ionServer) C.Ion.defaultServer = options.ionServer
    if (options.arcGisAccessToken) C.ArcGisMapService.defaultAccessToken = options.arcGisAccessToken
    if (options.googleMapsApiKey || M.env.googleKey) C.GoogleMaps.defaultApiKey = options.googleMapsApiKey || M.env.googleKey
    if (options.googleStreetViewApiKey) C.GoogleMaps.defaultStreetViewStaticApiKey = options.googleStreetViewApiKey
    if (options.bingMapsKey) C.BingMapsGeocoderService && (C.BingMapsImageryProvider.defaultKey = options.bingMapsKey)
    if (options.iTwinAccessToken && C.ITwinPlatform) C.ITwinPlatform.defaultAccessToken = options.iTwinAccessToken
    if (options.iTwinShareKey && C.ITwinPlatform) C.ITwinPlatform.defaultShareKey = options.iTwinShareKey

    const geocoder = widgets.geocoder
    const viewer = new C.Viewer('map', {
      baseLayer: false,
      terrainProvider: new C.EllipsoidTerrainProvider(),
      animation: !!widgets.animation,
      timeline: !!widgets.timeline,
      baseLayerPicker: !!widgets.baseLayerPicker && !!M.env.ionToken,
      geocoder: geocoder ? (typeof geocoder === 'string' ? M.enumValue(C.IonGeocodeProviderType, geocoder, true) : true) : false,
      homeButton: !!widgets.homeButton,
      sceneModePicker: !!widgets.sceneModePicker,
      projectionPicker: !!widgets.projectionPicker,
      navigationHelpButton: !!widgets.navigationHelpButton,
      navigationInstructionsInitiallyVisible: false,
      fullscreenButton: !!widgets.fullscreenButton,
      vrButton: !!widgets.vrButton,
      infoBox: !!widgets.infoBox,
      selectionIndicator: !!widgets.selectionIndicator,
      scene3DOnly: !!options.scene3DOnly,
      mapProjection: M.norm(options.mapProjection) === 'webmercator' ? new C.WebMercatorProjection() : new C.GeographicProjection(),
      mapMode2D: M.norm(options.mapMode2D) === 'rotate' ? C.MapMode2D.ROTATE : C.MapMode2D.INFINITE_SCROLL,
      msaaSamples: M.num(options.msaaSamples, 4),
      orderIndependentTranslucency: options.orderIndependentTranslucency !== false,
      useBrowserRecommendedResolution: options.useBrowserRecommendedResolution === true,
      automaticallyTrackDataSourceClocks: options.automaticallyTrackDataSourceClocks !== false,
      requestRenderMode: true,
      maximumRenderTimeChange: Infinity,
      contextOptions: Object.assign({ webgl: { alpha: false, preserveDrawingBuffer: false } }, options.contextOptions || {}),
      shouldAnimate: false,
      showRenderLoopErrors: false,
    })
    M.viewer = viewer
    viewerKey = creationKey(options)
    viewer.scene.globe.baseColor = C.Color.fromCssColorString('#a9c5d8')
    // Double-tap would zoom to (and track) entities: munim-maps leaves that to the app.
    viewer.screenSpaceEventHandler.removeInputAction(C.ScreenSpaceEventType.LEFT_DOUBLE_CLICK)
    if (widgets.inspector) viewer.extend(C.viewerCesiumInspectorMixin)
    if (widgets.tilesInspector) viewer.extend(C.viewerCesium3DTilesInspectorMixin)
    if (widgets.voxelInspector) viewer.extend(C.viewerVoxelInspectorMixin)
    if (widgets.performanceWatchdog) viewer.extend(C.viewerPerformanceWatchdogMixin, typeof widgets.performanceWatchdog === 'object' ? widgets.performanceWatchdog : undefined)
    if (widgets.dragDrop) viewer.extend(C.viewerDragDropMixin)
    viewer.scene.renderError.addEventListener((_, error) => {
      M.lastRenderError = error
      M.error('rendering stopped', error)
      // Keep drawing: one bad tile or model should not freeze the map.
      setTimeout(() => {
        if (M.viewer === viewer && !viewer.isDestroyed()) viewer.useDefaultRenderLoop = true
      }, 1000)
    })
    viewer.scene.morphComplete.addEventListener(() => M.emit('provider', { name: 'morphComplete', data: { sceneMode: sceneModeName() } }))
    viewer.selectedEntityChanged.addEventListener((entity) => M.emit('provider', { name: 'selectedEntityChanged', data: { id: entity ? entity.id : null } }))
    viewer.trackedEntityChanged.addEventListener((entity) => M.emit('provider', { name: 'trackedEntityChanged', data: { id: entity ? entity.id : null } }))
    viewer.scene.globe.tileLoadProgressEvent.addEventListener((queued) => {
      if (queued === 0) M.emit('provider', { name: 'globeTilesLoaded', data: {} })
    })
    M.layers = new Map()
    M.tilesets = new Map()
    M.dataSources = new Map()
    for (const hook of M.viewerHooks) hook(viewer)
    // Apply every prop again, in registration order.
    for (const key of M.order) {
      if (M.state[key] !== undefined) {
        try {
          M.handlers[key](M.state[key])
        } catch (e) {
          M.error(`could not apply ${key}`, e)
        }
      }
    }
    viewer.scene.requestRender()
    return viewer
  }

  M.viewerHooks = []

  M.destroyViewer = function () {
    if (!M.viewer) return
    for (const hook of M.destroyHooks) hook(M.viewer)
    M.viewer.destroy()
    M.viewer = undefined
  }
  M.destroyHooks = []

  function sceneModeName() {
    const mode = M.viewer.scene.mode
    if (mode === C.SceneMode.SCENE2D) return '2d'
    if (mode === C.SceneMode.COLUMBUS_VIEW) return 'columbus'
    if (mode === C.SceneMode.MORPHING) return 'morphing'
    return '3d'
  }
  M.sceneModeName = sceneModeName

  // MARK: Imagery

  const OSM = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
  const ESRI_IMAGERY = 'https://services.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
  const ESRI_LABELS = 'https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}'
  const OSM_CREDIT = '© OpenStreetMap contributors'
  const ESRI_CREDIT = 'Esri, Maxar, Earthstar Geographics, and the GIS User Community'

  /** A layer spec for the base map from `mapStyle` (or `cesium.imagery`). */
  function baseLayerSpecs() {
    const options = M.options()
    const hasIon = !!M.env.ionToken
    const style = M.norm(M.state.mapStyle || 'standard')
    let base = options.imagery
    if (base == null || base === '') {
      if (style === 'imagery') base = 'aerial'
      else if (style === 'hybrid') base = 'aerialWithLabels'
      else if (style === 'muted') base = 'muted'
      else base = 'openStreetMap'
    }
    if (typeof base === 'object') return [base]
    const dark = M.isDark()
    const tone = dark ? { brightness: 0.55, contrast: 1.15, saturation: 0.35, gamma: 1.1 } : {}
    switch (M.norm(base)) {
      case 'none':
        return []
      case 'naturalearth':
        return [{ type: 'tms', url: C.buildModuleUrl('Assets/Textures/NaturalEarthII'), ...tone }]
      case 'muted':
        return [{ type: 'openStreetMap', saturation: 0.15, brightness: dark ? 0.5 : 1.08, contrast: dark ? 1.15 : 0.85 }]
      case 'aerial':
        return [hasIon ? { type: 'ion', assetId: 2 } : { type: 'urlTemplate', url: ESRI_IMAGERY, maximumLevel: 19, credit: ESRI_CREDIT }]
      case 'aerialwithlabels':
        return hasIon ? [{ type: 'ion', assetId: 3 }] : [{ type: 'urlTemplate', url: ESRI_IMAGERY, maximumLevel: 19, credit: ESRI_CREDIT }, { type: 'urlTemplate', url: ESRI_LABELS, maximumLevel: 19, credit: 'Esri' }]
      case 'road':
        return [hasIon ? { type: 'ion', assetId: 4, ...tone } : { type: 'openStreetMap', ...tone }]
      case 'openstreetmap':
      case 'standard':
      default:
        return [{ type: 'openStreetMap', ...tone }]
    }
  }

  const LAYER_KEYS = ['alpha', 'nightAlpha', 'dayAlpha', 'brightness', 'contrast', 'hue', 'saturation', 'gamma', 'show', 'splitDirection', 'minificationFilter', 'magnificationFilter', 'cutoutRectangle', 'colorToAlpha', 'colorToAlphaThreshold', 'rectangle', 'minimumTerrainLevel', 'maximumTerrainLevel']

  /** Makes an imagery provider (or a promise of one) from a layer spec. */
  M.imageryProvider = function (spec) {
    const type = M.norm(spec.type || (spec.url ? 'urlTemplate' : 'openStreetMap'))
    const opts = M.convertOptions(Object.assign({}, spec.options || {}, pickProviderKeys(spec)))
    switch (type) {
      case 'openstreetmap':
      case 'osm': {
        const url = spec.url || OSM
        return new C.UrlTemplateImageryProvider(Object.assign({ url: M.tileUrl(url), maximumLevel: 19, credit: OSM_CREDIT }, opts, { url: M.tileUrl(url) }))
      }
      case 'urltemplate':
      case 'url':
      case 'xyz':
        return new C.UrlTemplateImageryProvider(Object.assign({}, opts, { url: M.tileUrl(spec.url) }))
      case 'wms':
        return new C.WebMapServiceImageryProvider(Object.assign({}, opts, { url: spec.url, layers: spec.layers || opts.layers }))
      case 'wmts':
        return new C.WebMapTileServiceImageryProvider(Object.assign({ style: 'default', tileMatrixSetID: 'default028mm', format: 'image/jpeg' }, opts, { url: spec.url, layer: spec.layer || opts.layer }))
      case 'tms':
      case 'tilemapservice':
        return C.TileMapServiceImageryProvider.fromUrl(spec.url, opts)
      case 'singletile':
      case 'image':
        return C.SingleTileImageryProvider.fromUrl(M.resource(spec.url), opts)
      case 'bing':
        return C.BingMapsImageryProvider.fromUrl(spec.url || 'https://dev.virtualearth.net', Object.assign({ key: spec.key }, opts, { mapStyle: M.enumValue(C.BingMapsStyle, spec.mapStyle, C.BingMapsStyle.AERIAL) }))
      case 'ion':
        return C.IonImageryProvider.fromAssetId(spec.assetId, opts)
      case 'arcgis':
        if (spec.basemapType) return C.ArcGisMapServerImageryProvider.fromBasemapType(M.enumValue(C.ArcGisBaseMapType, spec.basemapType, C.ArcGisBaseMapType.SATELLITE), opts)
        return C.ArcGisMapServerImageryProvider.fromUrl(spec.url, opts)
      case 'mapbox':
        return new C.MapboxImageryProvider(Object.assign({}, opts, { mapId: spec.mapId, accessToken: spec.accessToken }))
      case 'mapboxstyle':
        return new C.MapboxStyleImageryProvider(Object.assign({}, opts, { styleId: spec.styleId, username: spec.username, accessToken: spec.accessToken }))
      case 'google2d':
        if (spec.assetId) return C.Google2DImageryProvider.fromIonAssetId(Object.assign({}, opts, { assetId: spec.assetId }))
        return C.Google2DImageryProvider.fromUrl(Object.assign({ key: spec.key || C.GoogleMaps.defaultApiKey }, opts))
      case 'azure2d':
        return new C.Azure2DImageryProvider(Object.assign({}, opts, { subscriptionKey: spec.subscriptionKey }))
      case 'googleearthenterprise':
        return C.GoogleEarthEnterpriseMetadata.fromUrl(spec.url).then((metadata) => new C.GoogleEarthEnterpriseImageryProvider(Object.assign({}, opts, { metadata })))
      case 'grid':
        return new C.GridImageryProvider(opts)
      case 'tilecoordinates':
        return new C.TileCoordinatesImageryProvider(opts)
      default:
        throw new Error(`unknown imagery type "${spec.type}"`)
    }
  }

  function pickProviderKeys(spec) {
    const out = {}
    for (const k of Object.keys(spec)) {
      if (k === 'type' || k === 'id' || k === 'options' || k === 'layer' || k === 'zIndex' || LAYER_KEYS.includes(k)) continue
      out[k] = spec[k]
    }
    return out
  }

  function layerOptions(spec) {
    const out = {}
    for (const k of LAYER_KEYS) if (spec[k] !== undefined) out[k] = spec[k]
    Object.assign(out, spec.layer || {})
    return M.convertOptions(out)
  }

  function makeLayer(spec) {
    const provider = M.imageryProvider(spec)
    const options = layerOptions(spec)
    let layer
    if (provider && typeof provider.then === 'function') {
      layer = C.ImageryLayer.fromProviderAsync(provider, options)
      layer.errorEvent.addEventListener((e) => M.error(`imagery ${spec.id || spec.type}`, e))
    } else {
      layer = new C.ImageryLayer(provider, options)
    }
    return layer
  }

  /** Base map + `cesium.imageryLayers` + `tileOverlays`, bottom to top, re-using unchanged layers. */
  M.updateImagery = function () {
    const viewer = M.viewer
    if (!viewer) return
    const options = M.options()
    const overlays = (M.state.tileOverlays || []).slice().sort((a, b) => (a.zIndex || 0) - (b.zIndex || 0))
    const replaces = overlays.some((o) => o.replacesMap)
    const specs = []
    if (!replaces) baseLayerSpecs().forEach((s, i) => specs.push({ key: `base${i}`, spec: s }))
    ;(options.imageryLayers || []).forEach((s, i) => specs.push({ key: `layer:${s.id || i}`, spec: s }))
    for (const o of overlays) {
      if (!o.urlTemplate) continue
      specs.push({
        key: `overlay:${o.id}`,
        spec: {
          type: 'urlTemplate',
          url: o.urlTemplate,
          minimumLevel: Math.max(0, Math.floor(M.num(o.minimumZoom, 0))),
          maximumLevel: M.num(o.maximumZoom, 0) > 0 ? Math.floor(o.maximumZoom) : undefined,
          alpha: M.num(o.opacity, 1),
        },
      })
    }
    const collection = viewer.imageryLayers
    const wanted = new Map()
    for (const { key, spec } of specs) wanted.set(key + '|' + JSON.stringify(spec), spec)
    for (const [key, layer] of M.layers) {
      if (!wanted.has(key)) {
        collection.remove(layer, true)
        M.layers.delete(key)
      }
    }
    for (const [key, spec] of wanted) {
      if (M.layers.has(key)) continue
      try {
        const layer = makeLayer(spec)
        collection.add(layer)
        M.layers.set(key, layer)
      } catch (e) {
        M.error(`imagery ${spec.id || spec.type}`, e)
      }
    }
    for (const key of wanted.keys()) {
      const layer = M.layers.get(key)
      if (layer) collection.raiseToTop(layer)
    }
  }

  // MARK: Terrain

  let terrainKey = ''

  M.terrainSpec = function () {
    const options = M.options()
    let spec = options.terrain
    if (spec == null || spec === '') {
      const flat = M.norm(M.state.elevation) === 'flat'
      spec = !flat && M.env.ionToken ? 'world' : 'ellipsoid'
    }
    if (typeof spec === 'string') spec = { type: spec }
    return spec
  }

  M.updateTerrain = function () {
    const viewer = M.viewer
    if (!viewer) return
    const spec = M.terrainSpec()
    const key = JSON.stringify(spec)
    if (key === terrainKey) return
    terrainKey = key
    const type = M.norm(spec.type || 'ellipsoid')
    const providerOptions = { requestVertexNormals: spec.requestVertexNormals !== false, requestWaterMask: !!spec.requestWaterMask, requestMetadata: spec.requestMetadata !== false }
    let terrain
    try {
      switch (type) {
        case 'ellipsoid':
        case 'none':
          viewer.scene.terrainProvider = new C.EllipsoidTerrainProvider()
          M.emit('provider', { name: 'terrainChanged', data: { type: 'ellipsoid' } })
          return
        case 'world':
          terrain = C.Terrain.fromWorldTerrain(providerOptions)
          break
        case 'bathymetry':
          terrain = C.Terrain.fromWorldBathymetry(providerOptions)
          break
        case 'ion':
          terrain = new C.Terrain(C.CesiumTerrainProvider.fromIonAssetId(spec.assetId, providerOptions))
          break
        case 'url':
        case 'quantizedmesh':
          terrain = new C.Terrain(C.CesiumTerrainProvider.fromUrl(spec.url, providerOptions))
          break
        case 'arcgis':
          terrain = new C.Terrain(C.ArcGISTiledElevationTerrainProvider.fromUrl(spec.url || 'https://elevation3d.arcgis.com/arcgis/rest/services/WorldElevation3D/Terrain3D/ImageServer', { token: spec.token }))
          break
        case 'vrtheworld':
          terrain = new C.Terrain(C.VRTheWorldTerrainProvider.fromUrl(spec.url))
          break
        case '3dtiles':
          terrain = new C.Terrain(spec.assetId ? C.Cesium3DTilesTerrainProvider.fromIonAssetId(spec.assetId, providerOptions) : C.Cesium3DTilesTerrainProvider.fromUrl(spec.url, providerOptions))
          break
        case 'googleearthenterprise':
          terrain = new C.Terrain(C.GoogleEarthEnterpriseMetadata.fromUrl(spec.url).then((metadata) => new C.GoogleEarthEnterpriseTerrainProvider({ metadata })))
          break
        default:
          throw new Error(`unknown terrain type "${spec.type}"`)
      }
    } catch (e) {
      M.error('terrain', e)
      return
    }
    terrain.errorEvent.addEventListener((e) => M.error('terrain', e))
    terrain.readyEvent.addEventListener(() => {
      M.emit('provider', { name: 'terrainChanged', data: { type } })
      M.requestRender()
    })
    viewer.scene.setTerrain(terrain)
  }

  /** True once the ground is raised to real heights. */
  M.drawsTerrain = () => !!(M.viewer && !(M.viewer.scene.terrainProvider instanceof C.EllipsoidTerrainProvider))

  // MARK: 3D Tiles

  /** A tileset (or another 3D source) from a spec; resolves to what was added to the scene. */
  async function loadTileset(spec) {
    const viewer = M.viewer
    const type = M.norm(spec.type || (spec.ionAssetId ? 'ion' : spec.url ? 'url' : ''))
    const options = M.convertOptions(Object.assign({}, spec.options || {}, tilesetConstructorKeys(spec)))
    if (spec.clippingPolygons) options.clippingPolygons = clippingPolygons(spec.clippingPolygons)
    if (spec.clippingPlanes) options.clippingPlanes = clippingPlanes(spec.clippingPlanes)
    if (spec.customShader) options.customShader = customShader(spec.customShader)
    let primitive
    switch (type) {
      case 'osmbuildings':
        primitive = await C.createOsmBuildingsAsync(options)
        break
      case 'photorealistic':
      case 'google': {
        const key = spec.key || M.options().googleMapsApiKey || M.env.googleKey
        if (spec.source === 'ion' || (!spec.source && M.env.ionToken && !spec.key)) {
          primitive = await C.Cesium3DTileset.fromIonAssetId(2275207, options)
        } else {
          primitive = await C.createGooglePhotorealistic3DTileset({ key, onlyUsingWithGoogleGeocoder: true }, options)
        }
        break
      }
      case 'ion':
        primitive = await C.Cesium3DTileset.fromIonAssetId(spec.ionAssetId || spec.assetId, options)
        break
      case 'i3s':
        primitive = await C.I3SDataProvider.fromUrl(spec.url, Object.assign({ geoidTiledTerrainProvider: undefined }, options))
        break
      case 'voxel': {
        const provider = await C.Cesium3DTilesVoxelProvider.fromUrl(spec.url)
        primitive = new C.VoxelPrimitive(Object.assign({ provider }, options))
        if (spec.customShader) primitive.customShader = customShader(spec.customShader)
        break
      }
      case 'mvt': {
        const provider = await C.MVTDataProvider.fromUrl(M.tileUrl(spec.url), Object.assign({ scene: viewer.scene }, options))
        primitive = provider.tileset
        break
      }
      case 'itwin':
        if (spec.iModelId) primitive = await C.ITwinData.createTilesetFromIModelId(Object.assign({ iModelId: spec.iModelId, changesetId: spec.changesetId, tilesetOptions: options }))
        else primitive = await C.ITwinData.createTilesetForRealityDataId(Object.assign({ iTwinId: spec.iTwinId, realityDataId: spec.realityDataId, type: spec.realityDataType, rootDocument: spec.rootDocument, tilesetOptions: options }))
        break
      case 'url':
      case '3dtiles':
      default:
        primitive = await C.Cesium3DTileset.fromUrl(M.resource(spec.url), options)
    }
    return primitive
  }

  M.loadTileset = loadTileset

  const TILESET_SKIP = ['id', 'type', 'url', 'ionAssetId', 'assetId', 'key', 'source', 'style', 'flyTo', 'options', 'clippingPolygons', 'clippingPlanes', 'customShader', 'iModelId', 'changesetId', 'iTwinId', 'realityDataId', 'realityDataType', 'rootDocument', 'zoomTo']

  function tilesetConstructorKeys(spec) {
    const out = {}
    for (const k of Object.keys(spec)) if (!TILESET_SKIP.includes(k)) out[k] = spec[k]
    if (out.pointCloudShading && !(out.pointCloudShading instanceof C.PointCloudShading)) out.pointCloudShading = new C.PointCloudShading(out.pointCloudShading)
    if (out.imageBasedLighting && !(out.imageBasedLighting instanceof C.ImageBasedLighting)) out.imageBasedLighting = new C.ImageBasedLighting(out.imageBasedLighting)
    return out
  }

  function clippingPolygons(spec) {
    const list = Array.isArray(spec) ? spec : spec.polygons || []
    return new C.ClippingPolygonCollection({
      polygons: list.map((poly) => new C.ClippingPolygon({ positions: (poly.positions || poly).map((p) => M.cartesian(p)) })),
      inverse: !!spec.inverse,
      enabled: spec.enabled !== false,
    })
  }

  function clippingPlanes(spec) {
    return new C.ClippingPlaneCollection({
      planes: (spec.planes || []).map((p) => new C.ClippingPlane(new C.Cartesian3(p.normal.x, p.normal.y, p.normal.z), p.distance)),
      edgeWidth: spec.edgeWidth || 0,
      edgeColor: M.color(spec.edgeColor, '#ffffff'),
      unionClippingRegions: !!spec.unionClippingRegions,
      enabled: spec.enabled !== false,
      modelMatrix: spec.center ? C.Transforms.eastNorthUpToFixedFrame(M.cartesian(spec.center)) : undefined,
    })
  }

  function customShader(spec) {
    if (spec instanceof C.CustomShader) return spec
    const uniforms = {}
    for (const [name, u] of Object.entries(spec.uniforms || {})) {
      uniforms[name] = { type: M.enumValue(C.UniformType, u.type, C.UniformType.FLOAT), value: u.value }
    }
    return new C.CustomShader({
      mode: M.enumValue(C.CustomShaderMode, spec.mode, C.CustomShaderMode.MODIFY_MATERIAL),
      lightingModel: spec.lightingModel ? M.enumValue(C.LightingModel, spec.lightingModel) : undefined,
      translucencyMode: M.enumValue(C.CustomShaderTranslucencyMode, spec.translucencyMode, C.CustomShaderTranslucencyMode.INHERIT),
      uniforms,
      vertexShaderText: spec.vertexShaderText,
      fragmentShaderText: spec.fragmentShaderText,
    })
  }
  M.customShader = customShader

  function applyTilesetStyle(primitive, spec) {
    if (spec.style !== undefined && 'style' in primitive) {
      try {
        primitive.style = spec.style ? new C.Cesium3DTileStyle(spec.style) : undefined
      } catch (e) {
        M.error(`style of ${spec.id}`, e)
      }
    }
    if (spec.show !== undefined) primitive.show = spec.show !== false
  }

  /** The tilesets the options ask for: buildings, photorealistic, `tilesets`. */
  function wantedTilesets() {
    const options = M.options()
    const list = []
    const hasIon = !!M.env.ionToken
    const buildings = options.osmBuildings
    const occlusion = M.norm(M.state.occlusion) === 'buildings'
    if (buildings || (buildings === undefined && hasIon && (M.state.showsBuildings === true || occlusion) && !options.photorealistic)) {
      list.push(Object.assign({ id: 'osmBuildings', type: 'osmBuildings' }, typeof buildings === 'object' ? buildings : {}))
    }
    if (options.photorealistic) list.push(Object.assign({ id: 'photorealistic', type: 'photorealistic' }, typeof options.photorealistic === 'object' ? options.photorealistic : {}))
    ;(options.tilesets || []).forEach((t, i) => list.push(Object.assign({ id: `tileset${i}` }, t)))
    return list
  }

  M.updateTilesets = function () {
    const viewer = M.viewer
    if (!viewer) return
    const wanted = new Map()
    for (const spec of wantedTilesets()) {
      const { style, show, flyTo, zoomTo, ...rest } = spec
      wanted.set(spec.id, { spec, key: JSON.stringify(rest) })
    }
    for (const [id, entry] of M.tilesets) {
      const next = wanted.get(id)
      if (!next || next.key !== entry.key) {
        entry.cancelled = true
        if (entry.primitive) {
          if (entry.primitive instanceof C.I3SDataProvider || entry.primitive instanceof C.VoxelPrimitive || entry.primitive instanceof C.Cesium3DTileset) viewer.scene.primitives.remove(entry.primitive)
        }
        M.tilesets.delete(id)
      } else if (entry.primitive) {
        applyTilesetStyle(entry.primitive, next.spec)
        entry.spec = next.spec
      }
    }
    for (const [id, { spec, key }] of wanted) {
      if (M.tilesets.has(id)) continue
      const entry = { key, spec, primitive: undefined, cancelled: false }
      M.tilesets.set(id, entry)
      loadTileset(spec).then(
        (primitive) => {
          if (entry.cancelled || !M.viewer || M.viewer !== viewer) {
            if (primitive && primitive.destroy) primitive.destroy()
            return
          }
          entry.primitive = primitive
          viewer.scene.primitives.add(primitive)
          applyTilesetStyle(primitive, entry.spec)
          if (primitive.tileFailed) primitive.tileFailed.addEventListener((e) => M.error(`tile of ${id}`, e && e.message))
          if (primitive.allTilesLoaded) primitive.allTilesLoaded.addEventListener(() => M.emit('provider', { name: 'tilesetAllTilesLoaded', data: { id } }))
          if (primitive.loadProgress) primitive.loadProgress.addEventListener(() => M.requestRender())
          M.emit('provider', { name: 'tilesetLoaded', data: { id } })
          if (spec.flyTo || spec.zoomTo) viewer.zoomTo(primitive)
          M.requestRender()
        },
        (error) => {
          if (!entry.cancelled) M.error(`could not load 3D tiles "${id}"`, error)
        }
      )
    }
  }

  M.tileset = (id) => {
    const entry = M.tilesets.get(id)
    return entry ? entry.primitive : undefined
  }

  // MARK: Scene look

  function setFlag(target, key, value) {
    if (value === undefined || !target) return
    if (typeof value === 'boolean') {
      if ('show' in target) target.show = value
      else if ('enabled' in target) target.enabled = value
    } else if (typeof value === 'object') {
      M.assign(target, value)
    }
  }

  let defaults
  /** The scene as Cesium makes it, to go back to when an option is removed. */
  function captureDefaults(viewer) {
    const s = viewer.scene
    defaults = {
      globe: { enableLighting: s.globe.enableLighting, showGroundAtmosphere: s.globe.showGroundAtmosphere, depthTestAgainstTerrain: s.globe.depthTestAgainstTerrain, showWaterEffect: s.globe.showWaterEffect, dynamicAtmosphereLighting: s.globe.dynamicAtmosphereLighting },
      fog: { enabled: s.fog.enabled, density: s.fog.density },
      shadows: false,
      hdr: s.highDynamicRange,
      background: s.backgroundColor.clone(),
    }
  }
  M.viewerHooks.push(captureDefaults)

  const stages = []

  M.updateLook = function () {
    const viewer = M.viewer
    if (!viewer) return
    const s = viewer.scene
    const o = M.options()
    const globe = s.globe
    // Back to Cesium's defaults, then the options on top.
    M.assign(globe, defaults.globe)
    globe.material = undefined
    if (o.globe) {
      const { material, translucency, clippingPolygons: polys, clippingPlanes: planes, cartographicLimitRectangle, ...rest } = o.globe
      M.assign(globe, rest)
      if (translucency) M.assign(globe.translucency, M.convertOptions(translucency))
      if (polys) globe.clippingPolygons = clippingPolygons(polys)
      if (planes) globe.clippingPlanes = clippingPlanes(planes)
      if (cartographicLimitRectangle) globe.cartographicLimitRectangle = M.rectangle(cartographicLimitRectangle)
      if (material) globe.material = globeMaterial(material)
    }
    if (o.atmosphere && s.atmosphere) {
      const { dynamicLighting, ...rest } = o.atmosphere
      M.assign(s.atmosphere, rest)
      if (dynamicLighting !== undefined) s.atmosphere.dynamicLighting = M.enumValue(C.DynamicAtmosphereLightingType, dynamicLighting, C.DynamicAtmosphereLightingType.NONE)
    }
    if (s.skyAtmosphere) s.skyAtmosphere.show = o.skyAtmosphere !== false
    setFlag(s.skyAtmosphere, 'skyAtmosphere', typeof o.skyAtmosphere === 'object' ? o.skyAtmosphere : undefined)
    if (s.skyBox) {
      s.skyBox.show = o.skyBox !== false
      if (o.skyBox && o.skyBox.sources) s.skyBox = new C.SkyBox({ sources: o.skyBox.sources })
    }
    if (s.sun) setFlag(s.sun, 'sun', o.sun === undefined ? true : o.sun)
    if (s.moon) setFlag(s.moon, 'moon', o.moon === undefined ? true : o.moon)
    M.assign(s.fog, defaults.fog)
    setFlag(s.fog, 'fog', o.fog)
    // Shadows.
    const shadows = o.shadows
    viewer.shadows = !!shadows
    if (shadows && typeof shadows === 'object') M.assign(s.shadowMap, shadows, ['enabled'])
    if (o.terrainShadows !== undefined) viewer.terrainShadows = M.enumValue(C.ShadowMode, o.terrainShadows, C.ShadowMode.RECEIVE_ONLY)
    // Light (the munim model lighting decides unless the app sets one).
    M.updateLight()
    s.highDynamicRange = o.highDynamicRange === undefined ? defaults.hdr : !!o.highDynamicRange
    if (o.tonemapper && s.postProcessStages) s.postProcessStages.tonemapper = M.enumValue(C.Tonemapper, o.tonemapper, C.Tonemapper.PBR_NEUTRAL)
    if (o.exposure !== undefined && s.postProcessStages) s.postProcessStages.exposure = o.exposure
    s.backgroundColor = o.backgroundColor ? M.color(o.backgroundColor) : defaults.background
    if (o.verticalExaggeration !== undefined) s.verticalExaggeration = o.verticalExaggeration
    else if (o.terrainExaggeration !== undefined) s.verticalExaggeration = o.terrainExaggeration
    else s.verticalExaggeration = 1
    if (o.verticalExaggerationRelativeHeight !== undefined) s.verticalExaggerationRelativeHeight = o.verticalExaggerationRelativeHeight
    s.debugShowFramesPerSecond = !!o.debugShowFramesPerSecond
    if (o.pickTranslucentDepth !== undefined) s.pickTranslucentDepth = !!o.pickTranslucentDepth
    if (o.resolutionScale !== undefined) viewer.resolutionScale = o.resolutionScale
    else viewer.resolutionScale = M.defaultResolutionScale()
    if (o.targetFrameRate !== undefined) viewer.targetFrameRate = o.targetFrameRate
    if (o.showCredits === false) viewer.cesiumWidget.creditContainer.style.display = 'none'
    else viewer.cesiumWidget.creditContainer.style.display = ''
    if (o.sceneOptions) M.assign(s, o.sceneOptions)
    // Post-processing.
    const pp = s.postProcessStages
    const post = o.postProcess || {}
    pp.fxaa.enabled = !!post.fxaa
    const bloom = pp.bloom
    bloom.enabled = !!post.bloom
    if (post.bloom && typeof post.bloom === 'object') M.assign(bloom.uniforms, post.bloom)
    const ao = pp.ambientOcclusion
    if (ao) {
      ao.enabled = !!post.ambientOcclusion && C.PostProcessStageLibrary.isAmbientOcclusionSupported(s)
      if (post.ambientOcclusion && typeof post.ambientOcclusion === 'object') M.assign(ao.uniforms, post.ambientOcclusion)
    }
    while (stages.length) pp.remove(stages.pop())
    for (const st of post.stages || []) {
      try {
        const stage = postProcessStage(st)
        if (stage) {
          pp.add(stage)
          stages.push(stage)
        }
      } catch (e) {
        M.error(`post-process stage ${st.type}`, e)
      }
    }
    M.updateClouds()
    M.updateDarkUI()
  }

  M.defaultResolutionScale = function () {
    // Cesium draws at CSS pixels by default; device pixels look sharp but
    // cost a lot of fill rate on phones, so cap at 2.
    return Math.min(2, window.devicePixelRatio || 1)
  }

  function globeMaterial(spec) {
    if (spec.elevationBands) {
      return C.createElevationBandMaterial({
        scene: M.viewer.scene,
        layers: spec.elevationBands.map((layer) => ({
          entries: layer.entries.map((e) => ({ height: e.height, color: M.color(e.color) })),
          extendDownwards: layer.extendDownwards,
          extendUpwards: layer.extendUpwards,
        })),
      })
    }
    const uniforms = {}
    for (const [k, v] of Object.entries(spec.uniforms || {})) uniforms[k] = /color/i.test(k) ? M.color(v) : v
    if (spec.type === 'ElevationRamp' || spec.type === 'SlopeRamp' || spec.type === 'AspectRamp') {
      if (spec.ramp) uniforms.image = rampImage(spec.ramp)
    }
    return C.Material.fromType(spec.type, uniforms)
  }

  function rampImage(colors) {
    const canvas = document.createElement('canvas')
    canvas.width = 256
    canvas.height = 1
    const ctx = canvas.getContext('2d')
    const gradient = ctx.createLinearGradient(0, 0, 256, 0)
    colors.forEach((c, i) => gradient.addColorStop(i / Math.max(1, colors.length - 1), M.css(c)))
    ctx.fillStyle = gradient
    ctx.fillRect(0, 0, 256, 1)
    return canvas
  }

  function postProcessStage(spec) {
    const lib = C.PostProcessStageLibrary
    let stage
    switch (M.norm(spec.type)) {
      case 'blackandwhite':
        stage = lib.createBlackAndWhiteStage()
        break
      case 'brightness':
        stage = lib.createBrightnessStage()
        break
      case 'nightvision':
        stage = lib.createNightVisionStage()
        break
      case 'depthoffield':
        stage = lib.isDepthOfFieldSupported(M.viewer.scene) ? lib.createDepthOfFieldStage() : undefined
        break
      case 'edgedetection':
        stage = lib.createEdgeDetectionStage()
        break
      case 'silhouette':
        stage = lib.createSilhouetteStage()
        break
      case 'lensflare':
        stage = lib.createLensFlareStage()
        break
      case 'blur':
        stage = lib.createBlurStage()
        break
      case 'custom':
        stage = new C.PostProcessStage({ fragmentShader: spec.fragmentShader, uniforms: spec.uniforms || {} })
        return stage
      default:
        throw new Error('unknown stage')
    }
    if (stage && spec.uniforms) M.assign(stage.uniforms, spec.uniforms)
    if (stage && spec.enabled === false) stage.enabled = false
    return stage
  }

  /** The scene light: the app's `cesium.light`, else from the munim `lighting` prop. */
  let headlight = false
  M.updateLight = function () {
    const viewer = M.viewer
    if (!viewer) return
    const s = viewer.scene
    const o = M.options()
    headlight = false
    if (o.light) {
      const spec = typeof o.light === 'string' ? { type: o.light } : o.light
      const options = { color: M.color(spec.color, '#ffffff'), intensity: M.num(spec.intensity, 2) }
      if (M.norm(spec.type) === 'directional') {
        const d = spec.direction || { x: 0, y: 0, z: -1 }
        if (spec.direction) s.light = new C.DirectionalLight(Object.assign(options, { direction: C.Cartesian3.normalize(new C.Cartesian3(d.x, d.y, d.z), new C.Cartesian3()) }))
        else {
          s.light = new C.DirectionalLight(Object.assign(options, { direction: new C.Cartesian3(0, 0, -1) }))
          headlight = true
        }
      } else {
        s.light = new C.SunLight(options)
      }
      return
    }
    switch (M.norm(M.state.lighting || 'auto')) {
      case 'day':
        s.light = new C.DirectionalLight({ direction: new C.Cartesian3(0, 0, -1), intensity: 2.2 })
        headlight = true
        break
      case 'night':
        s.light = new C.DirectionalLight({ direction: new C.Cartesian3(0, 0, -1), intensity: 0.6, color: M.color('#9fb4ff') })
        headlight = true
        break
      default:
        s.light = new C.SunLight()
    }
  }

  // A light that comes from over the viewer's shoulder, so models are lit whatever the time.
  M.viewerHooks.push((viewer) => {
    viewer.scene.preRender.addEventListener((scene) => {
      if (!headlight || !(scene.light instanceof C.DirectionalLight)) return
      const camera = scene.camera
      const dir = C.Cartesian3.clone(camera.directionWC, new C.Cartesian3())
      const up = scene.globe.ellipsoid.geodeticSurfaceNormal(camera.positionWC, new C.Cartesian3())
      if (!up) return
      C.Cartesian3.add(dir, C.Cartesian3.multiplyByScalar(up, -0.6, new C.Cartesian3()), dir)
      scene.light.direction = C.Cartesian3.normalize(dir, dir)
    })
  })

  // MARK: Clouds

  let clouds
  M.updateClouds = function () {
    const viewer = M.viewer
    const list = M.options().clouds
    if (clouds) {
      viewer.scene.primitives.remove(clouds)
      clouds = undefined
    }
    if (!list || !list.length) return
    clouds = new C.CloudCollection(M.options().cloudOptions || {})
    for (const c of list) {
      clouds.add({
        position: M.cartesian(c.position || c),
        scale: c.scale ? new C.Cartesian2(c.scale.x, c.scale.y) : new C.Cartesian2(1500, 250),
        maximumSize: c.maximumSize ? new C.Cartesian3(c.maximumSize.x, c.maximumSize.y, c.maximumSize.z) : undefined,
        slice: M.num(c.slice, -1),
        brightness: M.num(c.brightness, 1),
        color: c.color ? M.color(c.color) : undefined,
        show: c.show !== false,
      })
    }
    viewer.scene.primitives.add(clouds)
  }

  M.updateDarkUI = function () {
    document.body.classList.toggle('munim-dark', M.isDark())
  }

  // MARK: Clock

  let clockKey = ''
  /** Applies `cesium.clock` when it changed (so other option changes do not reset the time). */
  M.updateClock = function (force) {
    const viewer = M.viewer
    const clock = viewer.clock
    const c = M.options().clock
    if (!c) return
    const key = JSON.stringify(c)
    if (key === clockKey && !force) return
    clockKey = key
    M.applyClock(c)
  }

  M.applyClock = function (c) {
    const viewer = M.viewer
    const clock = viewer.clock
    if (c.startTime) clock.startTime = M.julian(c.startTime)
    if (c.stopTime) clock.stopTime = M.julian(c.stopTime)
    if (c.currentTime) clock.currentTime = M.julian(c.currentTime)
    if (c.multiplier !== undefined) clock.multiplier = c.multiplier
    if (c.shouldAnimate !== undefined) clock.shouldAnimate = !!c.shouldAnimate
    if (c.canAnimate !== undefined) clock.canAnimate = !!c.canAnimate
    if (c.clockRange) clock.clockRange = M.enumValue(C.ClockRange, c.clockRange, C.ClockRange.UNBOUNDED)
    if (c.clockStep) clock.clockStep = M.enumValue(C.ClockStep, c.clockStep, C.ClockStep.SYSTEM_CLOCK_MULTIPLIER)
    if (viewer.timeline && c.startTime && c.stopTime) viewer.timeline.zoomTo(clock.startTime, clock.stopTime)
  }
  M.destroyHooks.push(() => {
    clockKey = ''
  })

  M.clockState = function () {
    const clock = M.viewer.clock
    return {
      startTime: M.iso(clock.startTime),
      stopTime: M.iso(clock.stopTime),
      currentTime: M.iso(clock.currentTime),
      multiplier: clock.multiplier,
      shouldAnimate: clock.shouldAnimate,
      clockRange: Object.keys(C.ClockRange).find((k) => C.ClockRange[k] === clock.clockRange),
      clockStep: Object.keys(C.ClockStep).find((k) => C.ClockStep[k] === clock.clockStep),
    }
  }

  // MARK: Data sources and entities

  /** Loads a data source from a spec: CZML, GeoJSON / TopoJSON, KML / KMZ or GPX. */
  M.loadDataSource = async function (spec) {
    const type = M.norm(spec.type || guessType(spec.url))
    const source = spec.data !== undefined ? spec.data : M.resource(spec.url)
    const options = M.convertOptions(Object.assign({}, spec.options || {}))
    for (const k of ['stroke', 'fill', 'markerColor']) if (spec.options && spec.options[k]) options[k] = M.color(spec.options[k])
    let dataSource
    switch (type) {
      case 'czml':
        dataSource = await C.CzmlDataSource.load(source, options)
        break
      case 'geojson':
      case 'topojson':
      case 'json':
        dataSource = await C.GeoJsonDataSource.load(source, options)
        break
      case 'kml':
      case 'kmz': {
        const kmlSource = typeof source === 'string' && spec.data !== undefined ? new DOMParser().parseFromString(source, 'text/xml') : source
        dataSource = await C.KmlDataSource.load(kmlSource, Object.assign({ camera: M.viewer.scene.camera, canvas: M.viewer.scene.canvas }, options))
        break
      }
      case 'gpx':
        dataSource = await C.GpxDataSource.load(typeof source === 'string' && spec.data !== undefined ? new DOMParser().parseFromString(source, 'text/xml') : source, options)
        break
      default:
        throw new Error(`unknown data source type "${spec.type}"`)
    }
    if (spec.name) dataSource.name = spec.name
    return dataSource
  }

  function guessType(url) {
    const s = String(url || '').toLowerCase()
    if (s.endsWith('.czml')) return 'czml'
    if (s.endsWith('.kml')) return 'kml'
    if (s.endsWith('.kmz')) return 'kmz'
    if (s.endsWith('.gpx')) return 'gpx'
    return 'geojson'
  }

  function applyClustering(dataSource, clustering) {
    if (!clustering) return
    const c = dataSource.clustering
    c.enabled = clustering.enabled !== false
    if (clustering.pixelRange !== undefined) c.pixelRange = clustering.pixelRange
    if (clustering.minimumClusterSize !== undefined) c.minimumClusterSize = clustering.minimumClusterSize
    if (clustering.clusterBillboards !== undefined) c.clusterBillboards = clustering.clusterBillboards
    if (clustering.clusterLabels !== undefined) c.clusterLabels = clustering.clusterLabels
    if (clustering.clusterPoints !== undefined) c.clusterPoints = clustering.clusterPoints
    if (clustering.color) {
      const pin = new C.PinBuilder()
      c.clusterEvent.addEventListener((entities, cluster) => {
        cluster.label.show = false
        cluster.billboard.show = true
        cluster.billboard.id = cluster.label.id
        cluster.billboard.verticalOrigin = C.VerticalOrigin.BOTTOM
        cluster.billboard.image = pin.fromText(String(entities.length), M.color(clustering.color), 48).toDataURL()
      })
    }
  }

  M.updateDataSources = function () {
    const viewer = M.viewer
    if (!viewer) return
    const specs = (M.options().dataSources || []).map((s, i) => Object.assign({ id: `dataSource${i}` }, s))
    const wanted = new Map(specs.map((s) => [s.id, s]))
    for (const [id, entry] of M.dataSources) {
      const next = wanted.get(id)
      const key = next ? JSON.stringify({ ...next, show: undefined }) : ''
      if (!next || key !== entry.key) {
        entry.cancelled = true
        if (entry.dataSource) viewer.dataSources.remove(entry.dataSource, true)
        M.dataSources.delete(id)
      } else if (entry.dataSource) {
        entry.dataSource.show = next.show !== false
      }
    }
    for (const spec of specs) {
      if (M.dataSources.has(spec.id)) continue
      const entry = { key: JSON.stringify({ ...spec, show: undefined }), dataSource: undefined, cancelled: false }
      M.dataSources.set(spec.id, entry)
      M.loadDataSource(spec).then(
        (dataSource) => {
          if (entry.cancelled || M.viewer !== viewer) return
          entry.dataSource = dataSource
          dataSource.show = spec.show !== false
          applyClustering(dataSource, spec.clustering)
          viewer.dataSources.add(dataSource)
          M.emit('provider', { name: 'dataSourceLoaded', data: { id: spec.id, entities: dataSource.entities.values.length } })
          if (spec.flyTo || spec.zoomTo) viewer.flyTo(dataSource)
          M.requestRender()
        },
        (error) => {
          if (!entry.cancelled) M.error(`could not load data source "${spec.id}"`, error)
        }
      )
    }
  }

  M.dataSource = (id) => {
    const entry = M.dataSources.get(id)
    return entry ? entry.dataSource : undefined
  }

  // `cesium.entities`: CZML packets in their own data source, updated in place.
  let entitySource
  let entityIds = new Set()

  M.updateEntities = function () {
    const viewer = M.viewer
    if (!viewer) return
    const packets = M.options().entities || []
    if (!entitySource) {
      entitySource = new C.CzmlDataSource('munim-entities')
      viewer.dataSources.add(entitySource)
    }
    const ids = new Set(packets.map((p) => p.id).filter(Boolean))
    const removed = [...entityIds].filter((id) => !ids.has(id))
    const document = { id: 'document', version: '1.0' }
    const list = [document, ...removed.map((id) => ({ id, delete: true })), ...packets.filter((p) => p.id !== 'document')]
    entityIds = ids
    entitySource.process(list).catch((e) => M.error('entities', e))
  }
  M.destroyHooks.push(() => {
    entitySource = undefined
    entityIds = new Set()
    clouds = undefined
    stages.length = 0
    terrainKey = ''
  })

  M.entitySource = () => entitySource

  /** Finds an entity by id in every data source (munim features, CZML, loaded files). */
  M.findEntity = function (id) {
    const viewer = M.viewer
    let found = viewer.entities.getById(id)
    if (found) return found
    for (let i = 0; i < viewer.dataSources.length; i++) {
      found = viewer.dataSources.get(i).entities.getById(id)
      if (found) return found
    }
    return undefined
  }

  M.updateTracking = function () {
    const viewer = M.viewer
    const o = M.options()
    if (o.trackedEntityId !== undefined) viewer.trackedEntity = o.trackedEntityId ? M.findEntity(o.trackedEntityId) : undefined
    if (o.selectedEntityId !== undefined) viewer.selectedEntity = o.selectedEntityId ? M.findEntity(o.selectedEntityId) : undefined
  }

  // MARK: Options

  let appliedMode
  M.on('options', (options) => {
    if (creationKey(options) !== viewerKey) {
      M.createViewer()
      return
    }
    M.updateImagery()
    M.updateTerrain()
    M.updateTilesets()
    M.updateLook()
    M.updateClock()
    M.updateDataSources()
    M.updateEntities()
    M.updateTracking()
    const mode = options.sceneMode ? M.norm(options.sceneMode) : '3d'
    if (mode !== appliedMode) {
      const duration = M.num(options.morphDuration, appliedMode === undefined ? 0 : 2)
      appliedMode = mode
      M.morph(mode, duration)
    }
    M.applyController && M.applyController()
    M.applyFrustum && M.applyFrustum()
  })
  M.destroyHooks.push(() => {
    appliedMode = undefined
  })

  M.on('mapStyle', () => M.updateImagery())
  M.on('colorScheme', () => {
    M.updateImagery()
    M.updateDarkUI()
  })
  M.on('elevation', () => M.updateTerrain())
  M.on('tileOverlays', () => M.updateImagery())
  M.on('showsBuildings', () => M.updateTilesets())
  M.on('occlusion', () => M.updateTilesets())
  M.on('lighting', () => M.updateLight())
  M.on('globe', () => {})
  M.on('styleUrl', (url) => {
    // Cesium has no style JSON: a `styleUrl` is taken as an XYZ imagery template.
    if (url) M.error('styleUrl is a MapLibre / Mapbox style; use tileOverlays or cesium.imagery for Cesium')
  })
})()
