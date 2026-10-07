package com.margelo.nitro.munimmaps

import android.os.Handler
import android.os.Looper
import com.facebook.react.uimanager.ThemedReactContext
import com.margelo.nitro.core.Promise
import com.munimmaps.engine.MunimMapContainerView
import com.munimmaps.engine.MunimMapEngine
import com.munimmaps.engine.MunimMapEngineListener
import com.munimmaps.engine.MunimMapsConfiguration
import com.munimmaps.engine.ProviderJson
import org.json.JSONObject

/**
 * React Native `MunimMapView` on Android: a [MunimMapContainerView] showing
 * the engine in `provider`, with props, events and methods forwarded to it
 * ([MunimMapEngine]). 3D props go straight to the engine's model layer. The
 * engine is made after the first batch of props (so the right one is made
 * once) and replaced, with every prop applied again, when `provider` changes.
 */
class HybridMunimMapView(private val context: ThemedReactContext) : HybridMunimMapViewSpec() {
  private val container = MunimMapContainerView(context)
  private val main = Handler(Looper.getMainLooper())
  override val view get() = container

  private val engine: MunimMapEngine? get() = container.engine

  init {
    MunimMapsConfiguration.load(context)
  }

  override fun afterUpdate() {
    val next = container.setProvider(provider) ?: return
    next.listener = listener
    applyAll(next)
  }

  override fun onDropView() {
    container.destroy()
  }

  private fun applyAll(e: MunimMapEngine) {
    e.setStyleUrl(styleUrl)
    e.setProviderOptions(options(providerOptions))
    if (initialCamera.distance > 0) e.setInitialCamera(initialCamera)
    applyModelLayer(e)
    e.setMarkers(markers)
    e.setPolylines(polylines)
    e.setPolygons(polygons)
    e.setCircles(circles)
    e.setTileOverlays(tileOverlays)
    e.setClusterStyles(clusterStyles)
    e.setMapStyle(mapStyle)
    e.setElevation(elevation)
    e.setGlobe(globe)
    e.setColorScheme(colorScheme)
    e.setShowsBuildings(showsBuildings)
    e.setShowsUserLocation(showsUserLocation)
    e.setShowsTraffic(showsTraffic)
    e.setPointsOfInterest(pointsOfInterest)
    e.setCompassVisibility(compassVisibility)
    e.setScaleVisibility(scaleVisibility)
    e.setShowsUserTrackingButton(showsUserTrackingButton)
    e.setUserTrackingMode(userTrackingMode)
    e.setGestures(zoomEnabled, scrollEnabled, rotateEnabled, pitchEnabled)
    e.setCameraDistanceRange(minCameraDistance, maxCameraDistanceLimit)
    e.setCameraBoundary(boundary())
    e.setMapPadding(mapPadding)
    e.setOverlayPressEnabled(onOverlayPress != null)
  }

  private fun applyModelLayer(e: MunimMapEngine) {
    val layer = e.modelLayer
    layer.models = models
    layer.zones = zones
    layer.paths = paths
    layer.buildingOcclusion = occlusion == MapOcclusion.BUILDINGS
    layer.buildingTilesUrl = buildingTilesUrl
    layer.followsTerrain = followTerrain
    layer.lighting = lighting
    layer.maxCameraDistance = maxCameraDistance
    layer.onModelPress = { id -> onModelPress?.invoke(id) }
    layer.onError = { message -> onError?.invoke(message) }
  }

  private fun options(json: String): JSONObject = try {
    JSONObject(json.ifBlank { "{}" })
  } catch (_: Exception) {
    JSONObject()
  }

  private fun boundary(): MapRegion? =
    cameraBoundary.takeIf { it.latitudeDelta > 0 && it.longitudeDelta > 0 }

  // Events

  private val listener = object : MunimMapEngineListener {
    override fun onMapReady() { onMapReady?.invoke() }
    override fun onPress(event: MapPressEvent) { onPress?.invoke(event) }
    override fun onLongPress(event: MapPressEvent) { onLongPress?.invoke(event) }
    override fun onCameraMove(camera: MapCamera) { onCameraMove?.invoke(camera) }
    override fun onCameraChange(camera: MapCamera) { onCameraChange?.invoke(camera) }
    override fun onMarkerPress(id: String) { onMarkerPress?.invoke(id) }
    override fun onMarkerDeselect(id: String) { onMarkerDeselect?.invoke(id) }
    override fun onCalloutPress(id: String) { onCalloutPress?.invoke(id) }
    override fun onCalloutAccessoryPress(event: CalloutAccessoryEvent) { onCalloutAccessoryPress?.invoke(event) }
    override fun onClusterPress(event: ClusterPressEvent) { onClusterPress?.invoke(event) }
    override fun onOverlayPress(event: OverlayPressEvent) { onOverlayPress?.invoke(event) }
    override fun onMarkerDragStart(event: MarkerDragEvent) { onMarkerDragStart?.invoke(event) }
    override fun onMarkerDragEnd(event: MarkerDragEvent) { onMarkerDragEnd?.invoke(event) }
    override fun onUserLocationChange(location: UserLocationEvent) { onUserLocationChange?.invoke(location) }
    override fun onUserTrackingModeChange(mode: UserTrackingMode) { onUserTrackingModeChange?.invoke(mode) }
    override fun onMapFeaturePress(feature: MapFeatureEvent) { onMapFeaturePress?.invoke(feature) }
    override fun onError(message: String) { onError?.invoke(message) }
    override fun onProviderEvent(name: String, json: String) { onProviderEvent?.invoke(ProviderEvent(name, json)) }
  }

  // Props

  override var provider: MapProvider = MapProvider.MAPLIBRE
  override var styleUrl: String = ""
    set(value) { field = value; engine?.setStyleUrl(value) }
  override var providerOptions: String = "{}"
    set(value) { field = value; engine?.setProviderOptions(options(value)) }

  override var models: Array<NativeMapModel> = emptyArray()
    set(value) { field = value; engine?.modelLayer?.models = value }
  override var zones: Array<NativeMapZone> = emptyArray()
    set(value) { field = value; engine?.modelLayer?.zones = value }
  override var paths: Array<NativeMapPath> = emptyArray()
    set(value) { field = value; engine?.modelLayer?.paths = value }
  override var occlusion: MapOcclusion = MapOcclusion.NONE
    set(value) { field = value; engine?.modelLayer?.buildingOcclusion = value == MapOcclusion.BUILDINGS }
  override var buildingTilesUrl: String = ""
    set(value) { field = value; engine?.modelLayer?.buildingTilesUrl = value }
  override var followTerrain: Boolean = false
    set(value) { field = value; engine?.modelLayer?.followsTerrain = value }
  override var lighting: MapModelLighting = MapModelLighting.AUTO
    set(value) { field = value; engine?.modelLayer?.lighting = value }
  override var maxCameraDistance: Double = 50_000.0
    set(value) { field = value; engine?.modelLayer?.maxCameraDistance = value }

  override var initialCamera: MapCamera = MapCamera(0.0, 0.0, 0.0, 0.0, 0.0)
    set(value) { field = value; if (value.distance > 0) engine?.setInitialCamera(value) }
  override var mapStyle: MapStyle = MapStyle.STANDARD
    set(value) { field = value; engine?.setMapStyle(value) }
  override var elevation: MapElevation = MapElevation.REALISTIC
    set(value) { field = value; engine?.setElevation(value) }
  override var globe: Boolean = false
    set(value) { field = value; engine?.setGlobe(value) }
  override var colorScheme: MapColorScheme = MapColorScheme.SYSTEM
    set(value) { field = value; engine?.setColorScheme(value) }
  override var showsBuildings: Boolean = true
    set(value) { field = value; engine?.setShowsBuildings(value) }
  override var showsUserLocation: Boolean = false
    set(value) { field = value; engine?.setShowsUserLocation(value) }

  override var markers: Array<NativeMarker> = emptyArray()
    set(value) { field = value; engine?.setMarkers(value) }
  override var polylines: Array<NativePolyline> = emptyArray()
    set(value) { field = value; engine?.setPolylines(value) }
  override var polygons: Array<NativePolygon> = emptyArray()
    set(value) { field = value; engine?.setPolygons(value) }
  override var circles: Array<NativeCircle> = emptyArray()
    set(value) { field = value; engine?.setCircles(value) }
  override var tileOverlays: Array<NativeTileOverlay> = emptyArray()
    set(value) { field = value; engine?.setTileOverlays(value) }
  override var clusterStyles: Array<NativeClusterStyle> = emptyArray()
    set(value) { field = value; engine?.setClusterStyles(value) }

  override var compassVisibility: FeatureVisibility = FeatureVisibility.ADAPTIVE
    set(value) { field = value; engine?.setCompassVisibility(value) }
  override var scaleVisibility: FeatureVisibility = FeatureVisibility.HIDDEN
    set(value) { field = value; engine?.setScaleVisibility(value) }
  override var showsUserTrackingButton: Boolean = false
    set(value) { field = value; engine?.setShowsUserTrackingButton(value) }
  /** MapKit's 2D/3D button; iOS only. */
  override var pitchButtonVisibility: FeatureVisibility = FeatureVisibility.HIDDEN
  /** Standalone controls are iOS only. */
  override var mapScope: String = ""
  override var showsTraffic: Boolean = false
    set(value) { field = value; engine?.setShowsTraffic(value) }
  override var pointsOfInterest: String = "all"
    set(value) { field = value; engine?.setPointsOfInterest(value) }
  override var userTrackingMode: UserTrackingMode = UserTrackingMode.NONE
    set(value) { field = value; engine?.setUserTrackingMode(value) }
  override var zoomEnabled: Boolean = true
    set(value) { field = value; applyGestures() }
  override var scrollEnabled: Boolean = true
    set(value) { field = value; applyGestures() }
  override var rotateEnabled: Boolean = true
    set(value) { field = value; applyGestures() }
  override var pitchEnabled: Boolean = true
    set(value) { field = value; applyGestures() }
  override var minCameraDistance: Double = 0.0
    set(value) { field = value; engine?.setCameraDistanceRange(value, maxCameraDistanceLimit) }
  override var maxCameraDistanceLimit: Double = 0.0
    set(value) { field = value; engine?.setCameraDistanceRange(minCameraDistance, value) }
  override var cameraBoundary: MapRegion = MapRegion(0.0, 0.0, 0.0, 0.0)
    set(value) { field = value; engine?.setCameraBoundary(boundary()) }
  override var mapPadding: EdgeInsets = EdgeInsets(0.0, 0.0, 0.0, 0.0)
    set(value) { field = value; engine?.setMapPadding(value) }
  /** Tappable places on Apple's map; MapKit only. */
  override var selectableMapFeatures: String = ""
  /** Apple's place cards; MapKit only. */
  override var selectionAccessory: SelectionAccessory = SelectionAccessory.NONE

  private fun applyGestures() {
    engine?.setGestures(zoomEnabled, scrollEnabled, rotateEnabled, pitchEnabled)
  }

  // Event props

  override var onModelPress: ((id: String) -> Unit)? = null
  override var onCameraChange: ((camera: MapCamera) -> Unit)? = null
  override var onCameraMove: ((camera: MapCamera) -> Unit)? = null
  override var onMapReady: (() -> Unit)? = null
  override var onPress: ((event: MapPressEvent) -> Unit)? = null
  override var onLongPress: ((event: MapPressEvent) -> Unit)? = null
  override var onMarkerPress: ((id: String) -> Unit)? = null
  override var onMarkerDeselect: ((id: String) -> Unit)? = null
  override var onCalloutPress: ((id: String) -> Unit)? = null
  override var onCalloutAccessoryPress: ((event: CalloutAccessoryEvent) -> Unit)? = null
  override var onClusterPress: ((event: ClusterPressEvent) -> Unit)? = null
  override var onOverlayPress: ((event: OverlayPressEvent) -> Unit)? = null
    set(value) { field = value; engine?.setOverlayPressEnabled(value != null) }
  override var onMarkerDragStart: ((event: MarkerDragEvent) -> Unit)? = null
  override var onMarkerDragEnd: ((event: MarkerDragEvent) -> Unit)? = null
  override var onUserLocationChange: ((location: UserLocationEvent) -> Unit)? = null
  override var onUserTrackingModeChange: ((mode: UserTrackingMode) -> Unit)? = null
  override var onMapFeaturePress: ((feature: MapFeatureEvent) -> Unit)? = null
  override var onError: ((message: String) -> Unit)? = null
  override var onProviderEvent: ((event: ProviderEvent) -> Unit)? = null

  // Methods (called on the JavaScript thread; the engine runs on the main thread)

  private fun onMain(block: (MunimMapEngine) -> Unit) {
    main.post { engine?.let(block) }
  }

  private fun <T> mainPromise(block: (MunimMapEngine, Promise<T>) -> Unit): Promise<T> {
    val promise = Promise<T>()
    main.post {
      val e = engine
      if (e == null) promise.reject(IllegalStateException("The map is not ready yet"))
      else try {
        block(e, promise)
      } catch (error: Throwable) {
        promise.reject(error)
      }
    }
    return promise
  }

  override fun setCamera(camera: MapCamera, animated: Boolean) = onMain { it.setCamera(camera, animated) }

  override fun animateCamera(camera: MapCamera, durationMs: Double, easing: MapCameraEasing) =
    onMain { it.animateCamera(camera, durationMs, easing) }

  override fun flyCamera(keyframes: Array<CameraKeyframe>, start: Double, loop: Boolean) =
    onMain { it.flyCamera(keyframes, start, loop) }

  override fun stopFlight() = onMain { it.stopFlight() }

  override fun getCamera(): Promise<MapCamera> = mainPromise { e, p ->
    val camera = e.getCamera()
    if (camera != null) p.resolve(camera) else p.reject(IllegalStateException("The camera is not known yet"))
  }

  override fun setRegion(region: MapRegion, durationMs: Double) = onMain { it.setRegion(region, durationMs) }

  override fun getVisibleRegion(): Promise<MapRegion> = mainPromise { e, p ->
    val region = e.getVisibleRegion()
    if (region != null) p.resolve(region) else p.reject(IllegalStateException("The region is not known yet"))
  }

  override fun fitToCoordinates(coordinates: Array<MapCoordinate>, padding: EdgeInsets, animated: Boolean) =
    onMain { it.fitToCoordinates(coordinates, padding, animated) }

  override fun fitToMarkers(ids: String, padding: EdgeInsets, animated: Boolean) {
    val wanted = ids.split(",").map { it.trim() }.filter { it.isNotEmpty() }.toSet()
    onMain { it.fitToMarkers(wanted, padding, animated) }
  }

  override fun pointForCoordinate(coordinate: MapCoordinate): Promise<MapPoint> = mainPromise { e, p ->
    val point = e.pointForCoordinate(coordinate)
    if (point != null) p.resolve(point) else p.reject(UnsupportedOperationException("pointForCoordinate is not available"))
  }

  override fun coordinateForPoint(point: MapPoint): Promise<MapCoordinate> = mainPromise { e, p ->
    val coordinate = e.coordinateForPoint(point)
    if (coordinate != null) p.resolve(coordinate) else p.reject(UnsupportedOperationException("coordinateForPoint is not available"))
  }

  override fun selectMarker(id: String) = onMain { it.selectMarker(id) }

  override fun deselectMarker(id: String) = onMain { it.deselectMarker(id) }

  override fun takeSnapshot(width: Double, height: Double): Promise<String> = mainPromise { e, p ->
    e.takeSnapshot(width, height) { result -> result.fold({ p.resolve(it) }, { p.reject(it) }) }
  }

  override fun addressForCoordinate(coordinate: MapCoordinate): Promise<MapAddress> = mainPromise { e, p ->
    e.addressForCoordinate(coordinate) { result -> result.fold({ p.resolve(it) }, { p.reject(it) }) }
  }

  /** Look Around is Apple's. */
  override fun hasLookAround(coordinate: MapCoordinate): Promise<Boolean> = Promise.resolved(false)

  override fun openLookAround(coordinate: MapCoordinate): Promise<Boolean> = Promise.resolved(false)

  override fun measureAlignment(): Promise<MapAlignmentReport> = mainPromise { e, p -> p.resolve(e.measureAlignment()) }

  override fun overlayAtPoint(point: MapPoint): Promise<String> = mainPromise { e, p -> p.resolve(e.overlayAtPoint(point)) }

  override fun providerCall(method: String, argsJson: String): Promise<String> = mainPromise { e, p ->
    e.providerCall(method, ProviderJson.objectOf(argsJson)) { result ->
      result.fold({ p.resolve(ProviderJson.stringOf(it)) }, { p.reject(it) })
    }
  }

  override fun mapItemForFeature(id: String): Promise<MapItem> =
    Promise.rejected(UnsupportedOperationException("mapItemForFeature is MapKit only"))
}
