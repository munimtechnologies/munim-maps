package com.munimmaps.engines.google

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Point
import android.graphics.PointF
import android.location.Geocoder
import android.location.Location
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import com.facebook.react.bridge.ReactContext
import com.google.android.gms.maps.CameraUpdate
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.GoogleMap
import com.google.android.gms.maps.GoogleMapOptions
import com.google.android.gms.maps.MapView
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.Circle
import com.google.android.gms.maps.model.GroundOverlay
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.LatLngBounds
import com.google.android.gms.maps.model.MapColorScheme
import com.google.android.gms.maps.model.MapStyleOptions
import com.google.android.gms.maps.model.Marker
import com.google.android.gms.maps.model.Polygon
import com.google.android.gms.maps.model.Polyline
import com.google.android.gms.maps.model.TileOverlay
import com.google.maps.android.clustering.ClusterManager
import com.google.maps.android.collections.GroundOverlayManager
import com.google.maps.android.collections.MarkerManager
import com.google.maps.android.collections.PolygonManager
import com.google.maps.android.collections.PolylineManager
import com.google.maps.android.data.Layer
import com.margelo.nitro.munimmaps.CameraKeyframe
import com.margelo.nitro.munimmaps.EdgeInsets
import com.margelo.nitro.munimmaps.FeatureVisibility
import com.margelo.nitro.munimmaps.MapAddress
import com.margelo.nitro.munimmaps.MapCamera
import com.margelo.nitro.munimmaps.MapCameraEasing
import com.margelo.nitro.munimmaps.MapColorScheme as MunimColorScheme
import com.margelo.nitro.munimmaps.MapCoordinate
import com.margelo.nitro.munimmaps.MapFeatureEvent
import com.margelo.nitro.munimmaps.MapPoint
import com.margelo.nitro.munimmaps.MapPressEvent
import com.margelo.nitro.munimmaps.MapProvider
import com.margelo.nitro.munimmaps.MapRegion
import com.margelo.nitro.munimmaps.MapStyle
import com.margelo.nitro.munimmaps.NativeCircle
import com.margelo.nitro.munimmaps.NativeClusterStyle
import com.margelo.nitro.munimmaps.MarkerStyle
import com.margelo.nitro.munimmaps.NativeMarker
import com.margelo.nitro.munimmaps.NativePolygon
import com.margelo.nitro.munimmaps.NativePolyline
import com.margelo.nitro.munimmaps.NativeTileOverlay
import com.margelo.nitro.munimmaps.UserLocationEvent
import com.margelo.nitro.munimmaps.UserTrackingMode
import com.munimmaps.engine.MapCameraSource
import com.munimmaps.engine.MapCameraState
import com.munimmaps.engine.MunimMapEngine
import com.munimmaps.engine.MunimMapEngineFactory
import com.munimmaps.engine.MunimMapEngineListener
import com.munimmaps.engine.MunimMapsConfiguration
import com.munimmaps.engine.UnavailableMapEngine
import com.munimmaps.models.MunimModelLayer
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Locale
import java.util.concurrent.Executors
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.ln

object GoogleMapEngineFactory : MunimMapEngineFactory {
  override val isImplemented = true

  override fun create(context: Context): MunimMapEngine {
    MunimMapsConfiguration.load(context)
    if (MunimMapsConfiguration.googleMapsApiKey.isEmpty()) {
      return UnavailableMapEngine(
        context, MapProvider.GOOGLE,
        "No Google Maps API key. Add com.google.android.geo.API_KEY meta-data to the app's manifest " +
          "(the Expo config plugin's googleMapsApiKey writes it).",
      )
    }
    return GoogleMapEngine(context)
  }
}

/**
 * munim-maps' Google Maps engine on Android: the Maps SDK's `MapView`,
 * android-maps-utils (clustering, heatmaps, KML, GeoJSON) and the Filament
 * 3D layer on Google's camera ([GoogleCamera]).
 *
 * Shared props and methods follow [MunimMapEngine]; options only Google has
 * come in `providerOptions` (`google={{ … }}` in JavaScript), events only
 * Google has go to [MunimMapEngineListener.onProviderEvent], methods only
 * Google has to [providerCommand] (GoogleCommands.kt). The map view is made
 * when the first options arrive (Google takes a Map ID and lite mode only
 * then) and made again when they change.
 */
class GoogleMapEngine(internal val context: Context) : MunimMapEngine, MapCameraSource {
  override val provider = MapProvider.GOOGLE
  override var listener: MunimMapEngineListener? = null
  override val modelLayer = MunimModelLayer(context)

  internal val density = context.resources.displayMetrics.density.toDouble()
  internal val main = Handler(Looper.getMainLooper())
  private val root: FrameLayout
  override val view: View get() = root

  internal var mapView: MapView? = null
  internal var map: GoogleMap? = null
  internal var options = GJson(JSONObject())
  private var builtMapId: String? = null
  private var builtLite = false
  private var destroyed = false
  private var started = false
  private var readyReported = false
  private var loaded = false

  // Managers that let several owners share Google's click listeners.
  internal var markerManager: MarkerManager? = null
  internal var markerCollection: MarkerManager.Collection? = null
  internal var polygonManager: PolygonManager? = null
  internal var polylineManager: PolylineManager? = null
  internal var groundOverlayManager: GroundOverlayManager? = null
  internal var groundOverlayCollection: GroundOverlayManager.Collection? = null

  // Props
  internal var styleUrl = ""
  internal var styleUrlJson: String? = null
  internal var initialCamera: MapCamera? = null
  private var appliedInitialCamera = false
  internal var mapStyle = MapStyle.STANDARD
  internal var colorScheme = MunimColorScheme.SYSTEM
  internal var showsBuildings = true
  internal var showsUserLocation = false
  internal var showsTraffic = false
  internal var pointsOfInterest = "all"
  internal var compassVisibility = FeatureVisibility.ADAPTIVE
  internal var showsUserTrackingButton = false
  internal var userTrackingMode = UserTrackingMode.NONE
  internal var gestures = booleanArrayOf(true, true, true, true)
  internal var distanceRange = doubleArrayOf(0.0, 0.0)
  internal var cameraBoundary: MapRegion? = null
  internal var padding = EdgeInsets(0.0, 0.0, 0.0, 0.0)
  internal var overlayPressEnabled = false

  // Content (GoogleMarkers.kt, GoogleShapes.kt, GoogleLayers.kt)
  internal var markers: Array<NativeMarker> = emptyArray()
  internal var polylines: Array<NativePolyline> = emptyArray()
  internal var polygons: Array<NativePolygon> = emptyArray()
  internal var circles: Array<NativeCircle> = emptyArray()
  internal var tileOverlays: Array<NativeTileOverlay> = emptyArray()
  internal var clusterStyles: Array<NativeClusterStyle> = emptyArray()
  internal val markerData = mutableMapOf<String, NativeMarker>()
  internal val markerExtras = mutableMapOf<String, String>()
  internal val gmsMarkers = mutableMapOf<String, Marker>()
  internal val clusterItems = mutableMapOf<String, GoogleClusterItem>()
  internal val clusterManagers = mutableMapOf<String, ClusterManager<GoogleClusterItem>>()
  internal val photos = mutableMapOf<String, Bitmap>()
  internal val loadingPhotos = mutableSetOf<String>()
  internal var selectedMarkerId: String? = null
  internal val gmsPolylines = mutableMapOf<String, Polyline>()
  internal val gmsPolygons = mutableMapOf<String, Polygon>()
  internal val gmsCircles = mutableMapOf<String, Circle>()
  internal val tileLayers = mutableMapOf<String, Pair<String, TileOverlay>>()
  internal val customTileLayers = mutableMapOf<String, TileOverlay>()
  internal val groundOverlays = mutableMapOf<String, GroundOverlay>()
  internal val heatmaps = mutableMapOf<String, Pair<com.google.maps.android.heatmaps.HeatmapTileProvider, TileOverlay>>()
  internal val dataLayers = mutableMapOf<String, Pair<String, Layer>>()
  internal val overlayKeys = mutableMapOf<String, String>()
  internal val featureLayerKeys = mutableMapOf<String, String>()
  internal var streetView: GoogleStreetView? = null

  // Photorealistic 3D mode (Google3DMode.kt, src/google3d)
  internal var mode3d: Google3DMode? = null
  /** The 3D map started before `initialCamera` arrived (props come in any order). */
  private var mode3dNeedsCamera = false
  private var reportedNativeIn2d = false

  /** The 2D map's models go to the munim overlay; the 3D map draws them itself. */
  override fun setModels(models: Array<com.margelo.nitro.munimmaps.NativeMapModel>) {
    modelLayer.models = models
    mode3d?.setModels(models)
  }

  // Flights
  private var flight: Triple<List<CameraKeyframe>, Double, Boolean>? = null
  private val flightTick = object : Runnable {
    override fun run() {
      if (flight == null) return
      stepFlight()
      if (flight != null) main.postDelayed(this, 16)
    }
  }

  init {
    root = object : FrameLayout(context) {
      override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        if (mapView == null) createMapView()
        start()
      }

      override fun onDetachedFromWindow() {
        stop()
        super.onDetachedFromWindow()
      }
    }
    root.addView(modelLayer.view, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    modelLayer.attach(this)
  }

  // MARK: Lifecycle

  private fun start() {
    if (started || destroyed) return
    started = true
    mode3d?.resume()
    mapView?.onStart()
    mapView?.onResume()
    streetView?.resume()
  }

  private fun stop() {
    if (!started || destroyed) return
    started = false
    mode3d?.pause()
    streetView?.pause()
    mapView?.onPause()
    mapView?.onStop()
  }

  override fun destroy() {
    if (destroyed) return
    stop()
    destroyed = true
    stopFlight()
    closeStreetView()
    leave3d()
    modelLayer.destroy()
    mapView?.onDestroy()
  }

  /** Makes (or remakes) Google's map view with the current options. */
  internal fun createMapView() {
    if (destroyed) return
    val mapId = options["mapId"].string?.takeIf { it.isNotEmpty() }
    val lite = options["liteMode"].bool(false)
    val googleOptions = GoogleMapOptions()
    mapId?.let { googleOptions.mapId(it) }
    if (lite) googleOptions.liteMode(true)
    options["backgroundColor"].color?.let { googleOptions.backgroundColor(it) }
    googleOptions.mapColorScheme(colorSchemeValue())
    map?.cameraPosition?.let { googleOptions.camera(it) }
    mapView?.let { old ->
      clearContent()
      old.onPause()
      old.onStop()
      old.onDestroy()
      root.removeView(old)
    }
    map = null
    val next = MapView(context, googleOptions)
    next.onCreate(null)
    if (started) {
      next.onStart()
      next.onResume()
    }
    root.addView(next, 0, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    next.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
      applyInitialCameraIfReady()
      applyZoomLimits()
      modelLayer.setNeedsRender()
    }
    mapView = next
    builtMapId = mapId
    builtLite = lite
    next.getMapAsync { mapReady(it, next) }
  }

  private fun clearContent() {
    clusterManagers.values.forEach { it.clearItems() }
    clusterManagers.clear()
    clusterItems.clear()
    gmsMarkers.clear()
    markerData.clear()
    markerExtras.clear()
    gmsPolylines.clear()
    gmsPolygons.clear()
    gmsCircles.clear()
    tileLayers.clear()
    groundOverlays.clear()
    heatmaps.clear()
    overlayKeys.clear()
    dataLayers.values.forEach { it.second.removeLayerFromMap() }
    dataLayers.clear()
    featureLayerKeys.clear()
    map?.clear()
  }

  @SuppressLint("PotentialBehaviorOverride")
  private fun mapReady(map: GoogleMap, from: MapView) {
    if (destroyed || from !== mapView) return
    this.map = map
    val markers = MarkerManager(map)
    markerManager = markers
    polygonManager = PolygonManager(map)
    polylineManager = PolylineManager(map)
    val grounds = GroundOverlayManager(map)
    groundOverlayManager = grounds
    groundOverlayCollection = grounds.newCollection().also { collection ->
      collection.setOnGroundOverlayClickListener { overlay ->
        (overlay.tag as? String)?.let { emit("groundOverlayPress", GOut.obj("id" to it)) }
      }
    }
    markerCollection = markers.newCollection().also { setUpMarkerCollection(it) }

    map.setOnCameraMoveStartedListener { reason ->
      if (reason == GoogleMap.OnCameraMoveStartedListener.REASON_GESTURE) {
        stopFlight()
        endTrackingForCameraMove()
      }
      emit("cameraMoveStarted", GOut.obj("reason" to when (reason) {
        GoogleMap.OnCameraMoveStartedListener.REASON_GESTURE -> "gesture"
        GoogleMap.OnCameraMoveStartedListener.REASON_API_ANIMATION -> "apiAnimation"
        else -> "developerAnimation"
      }))
    }
    map.setOnCameraMoveListener {
      modelLayer.setNeedsRender()
      getCamera()?.let { listener?.onCameraMove(it) }
    }
    map.setOnCameraIdleListener {
      modelLayer.setNeedsRender()
      clusterManagers.values.forEach { it.onCameraIdle() }
      getCamera()?.let { listener?.onCameraChange(it) }
    }
    map.setOnCameraMoveCanceledListener { emit("cameraMoveCanceled") }
    map.setOnMapClickListener { latLng -> mapTapped(latLng) }
    map.setOnMapLongClickListener { latLng ->
      val p = map.projection.toScreenLocation(latLng)
      listener?.onLongPress(MapPressEvent(latLng.latitude, latLng.longitude, p.x / density, p.y / density))
    }
    map.setOnPoiClickListener { poi ->
      listener?.onMapFeaturePress(MapFeatureEvent(poi.name, poi.latLng.latitude, poi.latLng.longitude, "pointOfInterest", "", poi.placeId))
      emit("poiClick", GOut.obj("placeId" to poi.placeId, "name" to poi.name, "latitude" to poi.latLng.latitude, "longitude" to poi.latLng.longitude))
    }
    map.setOnMyLocationButtonClickListener {
      emit("myLocationButtonPress")
      false
    }
    map.setOnMyLocationClickListener { location -> emit("myLocationPress", GOut.obj("latitude" to location.latitude, "longitude" to location.longitude)) }
    @Suppress("DEPRECATION")
    map.setOnMyLocationChangeListener { location -> myLocationChanged(location) }
    map.setOnInfoWindowCloseListener { marker -> markerId(marker)?.let { emit("infoWindowClose", GOut.obj("id" to it)) } }
    map.setOnIndoorStateChangeListener(object : GoogleMap.OnIndoorStateChangeListener {
      override fun onIndoorBuildingFocused() {
        emit("indoorBuildingFocused", indoorBuilding())
      }

      override fun onIndoorLevelActivated(building: com.google.android.gms.maps.model.IndoorBuilding) {
        val level = building.levels.getOrNull(building.activeLevelIndex)
        emit("indoorLevelActivated", GOut.obj(
          "name" to (level?.name ?: ""), "shortName" to (level?.shortName ?: ""),
          "index" to building.activeLevelIndex, "building" to indoorBuilding(),
        ))
      }
    })
    map.addOnMapCapabilitiesChangedListener { capabilities ->
      emit("mapCapabilitiesChanged", GOut.obj(
        "advancedMarkers" to capabilities.isAdvancedMarkersAvailable,
        "dataDrivenStyling" to capabilities.isDataDrivenStylingAvailable,
      ))
    }
    map.setOnMapLoadedCallback {
      if (!loaded) {
        loaded = true
        emit("mapLoaded")
      }
      reportReady()
    }
    main.postDelayed({ reportReady() }, 3000)

    applySettings()
    applyInitialCameraIfReady()
    applyMarkers()
    applyPolylines()
    applyPolygons()
    applyCircles()
    applyTileOverlays()
    applyGoogleOverlays()
    customTileLayers.clear()
    modelLayer.setNeedsRender()
  }

  private fun reportReady() {
    if (readyReported || map == null || destroyed) return
    readyReported = true
    listener?.onMapReady()
  }

  /** Sends an event only Google has to `onProviderEvent`. */
  internal fun emit(name: String, data: JSONObject = JSONObject()) {
    listener?.onProviderEvent(name, data.toString())
  }

  internal fun reportError(message: String) {
    listener?.onError("Google Maps: $message")
  }

  // MARK: Taps

  private fun mapTapped(latLng: LatLng) {
    val map = map ?: return
    val p = map.projection.toScreenLocation(latLng)
    if (modelLayer.handleTap(p.x.toFloat(), p.y.toFloat())) return
    selectedMarkerId?.let { id ->
      selectedMarkerId = null
      gmsMarkers[id]?.hideInfoWindow()
      listener?.onMarkerDeselect(id)
    }
    if (overlayPressEnabled) {
      overlayHit(p.x.toDouble(), p.y.toDouble())?.let { (id, kind) ->
        listener?.onOverlayPress(com.margelo.nitro.munimmaps.OverlayPressEvent(id, kind, latLng.latitude, latLng.longitude))
        return
      }
    }
    listener?.onPress(MapPressEvent(latLng.latitude, latLng.longitude, p.x / density, p.y / density))
  }

  // MARK: Props

  override fun setStyleUrl(url: String) {
    if (url == styleUrl) return
    styleUrl = url
    val text = url.trim()
    if (text.isEmpty()) {
      styleUrlJson = null
      applySettings()
      return
    }
    Executors.newSingleThreadExecutor().execute {
      val json = runCatching {
        if (text.startsWith("/") || text.startsWith("file://")) File(text.removePrefix("file://")).readText()
        else java.net.URL(text).readText()
      }
      main.post {
        json.onSuccess { styleUrlJson = it; applySettings() }
          .onFailure { reportError("could not load the style at $text: ${it.message}") }
      }
    }
  }

  override fun setProviderOptions(options: JSONObject) {
    this.options = GJson(options)
    updateMode()
    val mapId = this.options["mapId"].string?.takeIf { it.isNotEmpty() }
    val lite = this.options["liteMode"].bool(false)
    if (mapView == null || mapId != builtMapId || lite != builtLite) {
      createMapView()
      return
    }
    applySettings()
    applyMarkers()
    applyPolylines()
    applyPolygons()
    applyCircles()
    applyTileOverlays()
    applyGoogleOverlays()
  }

  override fun setMarkers(markers: Array<NativeMarker>) {
    appMarkers = markers
    showMarkers()
  }

  // MarkerView: React Native views drawn into bitmaps, shown as image markers.
  private var appMarkers: Array<NativeMarker> = emptyArray()
  private val viewMarkers = LinkedHashMap<String, NativeMarker>()
  /** The bitmaps of `MarkerView`s, by the `imageUri` their markers carry. */
  internal val viewBitmaps = HashMap<String, Bitmap>()
  private var viewGeneration = 0

  override fun setViewMarker(marker: NativeMarker, image: Bitmap?) = putViewMarker(marker, image)

  override fun setViewMarkerImage(image: Bitmap?, id: String) {
    val marker = viewMarkers[id] ?: return
    putViewMarker(marker, image)
  }

  override fun removeViewMarker(id: String) {
    val marker = viewMarkers.remove(id) ?: return
    viewBitmaps.remove(marker.imageUri)
    showMarkers()
  }

  private fun putViewMarker(marker: NativeMarker, image: Bitmap?) {
    var uri = viewMarkers[marker.id]?.imageUri ?: ""
    if (image != null) {
      viewBitmaps.remove(uri)
      uri = "munim-view:${marker.id}:${++viewGeneration}"
      viewBitmaps[uri] = image
    }
    viewMarkers[marker.id] = marker.copy(style = MarkerStyle.IMAGE, imageUri = uri)
    showMarkers()
  }

  private fun showMarkers() {
    markers = appMarkers + viewMarkers.values
    applyMarkers()
    mode3d?.setMarkers(markers)
  }
  override fun setPolylines(polylines: Array<NativePolyline>) { this.polylines = polylines; applyPolylines(); mode3d?.setPolylines(polylines) }
  override fun setPolygons(polygons: Array<NativePolygon>) { this.polygons = polygons; applyPolygons(); mode3d?.setPolygons(polygons) }

  // MARK: 3D mode

  /**
   * `google.mode: '3d'` switches to Google's photorealistic 3D map (Maps 3D
   * SDK), where models are drawn natively (`modelRendering` `auto` or
   * `native`); the 2D map keeps the munim overlay (it has no 3D models).
   */
  private fun updateMode() {
    val wants3d = options["mode"].string == "3d"
    val rendering = options["modelRendering"].string ?: "auto"
    if (!wants3d && rendering == "native" && !reportedNativeIn2d) {
      reportedNativeIn2d = true
      reportError("the 2D Google map has no native 3D models; models are drawn by the munim overlay (use google.mode '3d' for native models)")
    }
    if (wants3d && mode3d == null) enter3d()
    if (!wants3d && mode3d != null) leave3d()
    mode3d?.setOptions(options)
    if (wants3d && rendering == "overlay") {
      reportError("Google's 3D map has no projection the munim overlay can follow; its models are drawn natively")
    }
  }

  private val host3d = object : Google3DHost {
    override fun emit(name: String, data: JSONObject) = this@GoogleMapEngine.emit(name, data)
    override fun error(message: String) = reportError(message)
    override fun ready() {
      emit("map3dReady")
      reportReady()
    }
    override fun press(latitude: Double, longitude: Double, placeId: String?) {
      if (placeId != null) {
        listener?.onMapFeaturePress(MapFeatureEvent("", latitude, longitude, "pointOfInterest", "", placeId))
        emit("poiClick", GOut.obj("placeId" to placeId, "name" to "", "latitude" to latitude, "longitude" to longitude))
      } else {
        listener?.onPress(MapPressEvent(latitude, longitude, -1.0, -1.0))
      }
    }
    override fun cameraChanged(camera: MapCamera, idle: Boolean) {
      if (idle) listener?.onCameraChange(camera) else listener?.onCameraMove(camera)
    }
    override fun modelPressed(id: String) { modelLayer.onModelPress?.invoke(id) }
    override fun markerPressed(id: String) { listener?.onMarkerPress(id) }
  }

  private fun enter3d() {
    val start = getCamera() ?: initialCamera
    val mode = Google3DModes.create(context, host3d, start)
    if (mode == null) {
      reportError("google.mode '3d' needs the Maps 3D SDK: set munimMaps.googleMaps3d=true (Expo plugin googleMaps3d: true) and rebuild")
      return
    }
    mode3d = mode
    mode3dNeedsCamera = start == null
    root.addView(mode.view, 0, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    mapView?.visibility = View.GONE
    modelLayer.view.visibility = View.GONE
    modelLayer.detach()
    if (started) mode.resume()
    mode.setMarkers(markers)
    mode.setPolylines(polylines)
    mode.setPolygons(polygons)
    mode.setModels(modelLayer.models)
    emit("modeChange", GOut.obj("mode" to "3d"))
  }

  private fun leave3d() {
    val mode = mode3d ?: return
    mode3d = null
    mode3dNeedsCamera = false
    mode.destroy()
    root.removeView(mode.view)
    mapView?.visibility = View.VISIBLE
    if (!destroyed) {
      modelLayer.view.visibility = View.VISIBLE
      modelLayer.attach(this)
    }
    emit("modeChange", GOut.obj("mode" to "2d"))
  }
  override fun setCircles(circles: Array<NativeCircle>) { this.circles = circles; applyCircles() }
  override fun setTileOverlays(overlays: Array<NativeTileOverlay>) {
    tileOverlays = overlays
    applyTileOverlays()
    applySettings()
  }
  override fun setClusterStyles(styles: Array<NativeClusterStyle>) {
    clusterStyles = styles
    clusterManagers.values.forEach { it.cluster() }
  }

  override fun setInitialCamera(camera: MapCamera) {
    initialCamera = camera
    applyInitialCameraIfReady()
    if (mode3dNeedsCamera) {
      mode3dNeedsCamera = false
      mode3d?.setCamera(camera, 0.0)
    }
  }

  override fun setMapStyle(style: MapStyle) { mapStyle = style; applySettings() }
  override fun setColorScheme(scheme: MunimColorScheme) { colorScheme = scheme; applySettings() }
  override fun setShowsBuildings(shows: Boolean) { showsBuildings = shows; applySettings() }
  override fun setShowsUserLocation(shows: Boolean) {
    showsUserLocation = shows
    if (shows) requestLocationPermission()
    applySettings()
  }
  override fun setShowsTraffic(shows: Boolean) { showsTraffic = shows; applySettings() }
  override fun setPointsOfInterest(filter: String) { pointsOfInterest = filter; applySettings() }
  override fun setCompassVisibility(visibility: FeatureVisibility) { compassVisibility = visibility; applySettings() }
  override fun setShowsUserTrackingButton(shows: Boolean) { showsUserTrackingButton = shows; applySettings() }
  override fun setUserTrackingMode(mode: UserTrackingMode) {
    if (mode == userTrackingMode) return
    userTrackingMode = mode
    if (mode != UserTrackingMode.NONE) {
      requestLocationPermission()
      stopFlight()
    }
    applySettings()
    lastLocation?.let { follow(it) }
  }
  override fun setGestures(zoom: Boolean, scroll: Boolean, rotate: Boolean, pitch: Boolean) {
    gestures = booleanArrayOf(zoom, scroll, rotate, pitch)
    applySettings()
  }
  override fun setCameraDistanceRange(min: Double, max: Double) {
    distanceRange = doubleArrayOf(min, max)
    applyZoomLimits()
  }
  override fun setCameraBoundary(region: MapRegion?) { cameraBoundary = region; applySettings() }
  override fun setMapPadding(padding: EdgeInsets) { this.padding = padding; applySettings() }
  override fun setOverlayPressEnabled(enabled: Boolean) { overlayPressEnabled = enabled }

  private fun colorSchemeValue(): Int = when (colorScheme) {
    MunimColorScheme.LIGHT -> MapColorScheme.LIGHT
    MunimColorScheme.DARK -> MapColorScheme.DARK
    else -> MapColorScheme.FOLLOW_SYSTEM
  }

  internal fun paddingPx(): IntArray = intArrayOf(
    (padding.left * density).toInt(), (padding.top * density).toInt(),
    (padding.right * density).toInt(), (padding.bottom * density).toInt(),
  )

  /** Every map-level setting: type, style, layers, controls, gestures, limits, padding. */
  @SuppressLint("MissingPermission")
  internal fun applySettings() {
    val map = map ?: return
    val o = options
    var type = when (mapStyle) {
      MapStyle.HYBRID -> GoogleMap.MAP_TYPE_HYBRID
      MapStyle.IMAGERY -> GoogleMap.MAP_TYPE_SATELLITE
      else -> GoogleMap.MAP_TYPE_NORMAL
    }
    when (o["mapType"].string) {
      "normal" -> type = GoogleMap.MAP_TYPE_NORMAL
      "satellite" -> type = GoogleMap.MAP_TYPE_SATELLITE
      "hybrid" -> type = GoogleMap.MAP_TYPE_HYBRID
      "terrain" -> type = GoogleMap.MAP_TYPE_TERRAIN
      "none" -> type = GoogleMap.MAP_TYPE_NONE
    }
    if (tileOverlays.any { it.replacesMap }) type = GoogleMap.MAP_TYPE_NONE
    if (map.mapType != type) map.mapType = type

    map.setMapStyle(combinedStyle())
    map.mapColorScheme = colorSchemeValue()
    map.isBuildingsEnabled = showsBuildings
    map.isTrafficEnabled = showsTraffic
    map.isTransitEnabled = o["transitEnabled"].bool(false)
    map.isIndoorEnabled = o["indoorEnabled"].bool(false)
    val wantsLocation = showsUserLocation || userTrackingMode != UserTrackingMode.NONE
    if (wantsLocation && !hasLocationPermission()) {
      requestLocationPermission()
    } else if (map.isMyLocationEnabled != wantsLocation) {
      try {
        map.isMyLocationEnabled = wantsLocation
      } catch (error: SecurityException) {
        reportError("showing the user's location needs the location permission")
      }
    }
    o["contentDescription"].string?.let { map.setContentDescription(it) }

    val ui = map.uiSettings
    ui.isCompassEnabled = o["compass"].bool(compassVisibility != FeatureVisibility.HIDDEN)
    ui.isMyLocationButtonEnabled = o["myLocationButton"].bool(showsUserTrackingButton)
    ui.isIndoorLevelPickerEnabled = o["indoorLevelPicker"].bool(o["indoorEnabled"].bool(false))
    ui.isZoomControlsEnabled = o["zoomControls"].bool(false)
    ui.isMapToolbarEnabled = o["mapToolbar"].bool(false)
    ui.isZoomGesturesEnabled = gestures[0]
    ui.isScrollGesturesEnabled = gestures[1]
    ui.isRotateGesturesEnabled = gestures[2]
    ui.isTiltGesturesEnabled = gestures[3]
    ui.isScrollGesturesEnabledDuringRotateOrZoom = o["scrollGesturesDuringRotateOrZoom"].bool(true)

    val bounds = o["cameraTargetBounds"].bounds ?: cameraBoundary?.let { r ->
      LatLngBounds(
        LatLng(r.latitude - r.latitudeDelta / 2, r.longitude - r.longitudeDelta / 2),
        LatLng(r.latitude + r.latitudeDelta / 2, r.longitude + r.longitudeDelta / 2),
      )
    }
    map.setLatLngBoundsForCameraTarget(bounds)
    val p = paddingPx()
    map.setPadding(p[0], p[1], p[2], p[3])
    applyZoomLimits()
    modelLayer.setNeedsRender()
  }

  internal fun applyZoomLimits() {
    val map = map ?: return
    val height = mapView?.height?.toDouble() ?: 0.0
    var minZoom = options["minZoom"].double
    var maxZoom = options["maxZoom"].double
    if (height > 0) {
      val latitude = map.cameraPosition.target.latitude
      if (maxZoom == null && distanceRange[0] > 0) maxZoom = GoogleCamera.zoom(distanceRange[0], latitude, height, density)
      if (minZoom == null && distanceRange[1] > 0) minZoom = GoogleCamera.zoom(distanceRange[1], latitude, height, density)
    }
    map.resetMinMaxZoomPreference()
    minZoom?.let { map.setMinZoomPreference(it.toFloat()) }
    maxZoom?.let { map.setMaxZoomPreference(it.toFloat()) }
  }

  /** The muted look, hidden points of interest, `styleUrl` and `google.styleJson`; none with a Map ID. */
  private fun combinedStyle(): MapStyleOptions? {
    val rules = JSONArray()
    if (mapStyle == MapStyle.MUTED) {
      rules.put(JSONObject().put("stylers", JSONArray().put(JSONObject().put("saturation", -60)).put(JSONObject().put("lightness", 15))))
    }
    for (rule in GooglePointsOfInterest.rules(pointsOfInterest)) rules.put(rule)
    fun addAll(text: String?) {
      val list = text?.let { runCatching { JSONArray(it) }.getOrNull() } ?: return
      for (i in 0 until list.length()) rules.put(list.get(i))
    }
    addAll(styleUrlJson)
    when (val raw = options["styleJson"].raw) {
      is String -> addAll(raw)
      is JSONArray -> addAll(raw.toString())
    }
    if (rules.length() == 0) return null
    if (builtMapId != null) {
      reportError("JSON styles (styleJson, styleUrl, muted, pointsOfInterest) are ignored on a map with a mapId; style it in the Cloud console")
      return null
    }
    return MapStyleOptions(rules.toString())
  }

  // MARK: Camera

  private fun heightPx(): Double = maxOf(1.0, mapView?.height?.toDouble() ?: 1.0)

  private fun applyInitialCameraIfReady() {
    if (appliedInitialCamera) return
    val camera = initialCamera ?: return
    val map = map ?: return
    if ((mapView?.height ?: 0) <= 0) return
    appliedInitialCamera = true
    map.moveCamera(CameraUpdateFactory.newCameraPosition(position(camera)))
    modelLayer.setNeedsRender()
  }

  internal fun position(camera: MapCamera): CameraPosition = CameraPosition.Builder()
    .target(LatLng(camera.latitude, camera.longitude))
    .zoom(GoogleCamera.zoom(camera.distance, camera.latitude, heightPx(), density).toFloat())
    .tilt(camera.pitch.toFloat().coerceIn(0f, 90f))
    .bearing(camera.heading.toFloat())
    .build()

  override fun getCamera(): MapCamera? {
    mode3d?.let { return it.getCamera() }
    val map = map ?: return null
    val view = mapView ?: return null
    GoogleCamera.state(map, view, paddingPx(), density, false)?.let {
      return MapCamera(it.latitude, it.longitude, it.distance, it.pitch, it.heading)
    }
    val p = map.cameraPosition
    return MapCamera(p.target.latitude, p.target.longitude,
      GoogleCamera.distance(p.zoom.toDouble(), p.target.latitude, heightPx(), density), p.tilt.toDouble(), p.bearing.toDouble())
  }

  override fun setCamera(camera: MapCamera, animated: Boolean) {
    stopFlight()
    endTrackingForCameraMove()
    mode3d?.let { return it.setCamera(camera, if (animated) 1000.0 else 0.0) }
    val map = map
    if (map == null) {
      initialCamera = camera
      appliedInitialCamera = false
      return
    }
    val update = CameraUpdateFactory.newCameraPosition(position(camera))
    if (animated) map.animateCamera(update) else map.moveCamera(update)
    modelLayer.setNeedsRender()
  }

  /** Stepped once a frame (like iOS), so the 3D layer reads the camera Google draws. */
  override fun animateCamera(camera: MapCamera, durationMs: Double, easing: MapCameraEasing) {
    mode3d?.let { return it.setCamera(camera, durationMs) }
    if (durationMs <= 0) return setCamera(camera, false)
    val from = getCamera() ?: return setCamera(camera, false)
    val linear = easing == MapCameraEasing.LINEAR
    val steps = if (linear) 1 else 24
    val seconds = durationMs / 1000
    val frames = (0..steps).map { i ->
      val x = i.toDouble() / steps
      val eased = if (linear) x else x * x * (3 - 2 * x)
      CameraKeyframe(x * seconds, interpolate(from, camera, eased))
    }
    flyCamera(frames.toTypedArray(), System.currentTimeMillis() / 1000.0, false)
  }

  override fun flyCamera(keyframes: Array<CameraKeyframe>, start: Double, loop: Boolean) {
    mode3d?.let { mode ->
      // Google 3D flies to one camera: the last keyframe, over the flight's length.
      val last = keyframes.maxByOrNull { it.t } ?: return
      return mode.setCamera(last.camera, maxOf(0.0, (last.t - keyframes.minOf { it.t }) * 1000))
    }
    if (keyframes.size < 2) {
      stopFlight()
      keyframes.firstOrNull()?.let { setCamera(it.camera, false) }
      return
    }
    endTrackingForCameraMove()
    val wasFlying = flight != null
    flight = Triple(keyframes.sortedBy { it.t }, start, loop)
    stepFlight()
    if (!wasFlying) main.postDelayed(flightTick, 16)
  }

  override fun stopFlight() {
    flight = null
    main.removeCallbacks(flightTick)
  }

  private fun stepFlight() {
    val (frames, start, loop) = flight ?: return
    val map = map ?: return
    val first = frames.first()
    val last = frames.last()
    var t = System.currentTimeMillis() / 1000.0 - start
    val span = last.t - first.t
    if (loop && span > 0) {
      t = first.t + (t - first.t).mod(span)
    }
    val camera = when {
      t <= first.t -> first.camera
      t >= last.t -> {
        if (!loop) stopFlight()
        last.camera
      }
      else -> {
        var i = 1
        while (i < frames.size - 1 && frames[i].t < t) i++
        val a = frames[i - 1]
        val b = frames[i]
        interpolate(a.camera, b.camera, (t - a.t) / maxOf(1e-9, b.t - a.t))
      }
    }
    map.moveCamera(CameraUpdateFactory.newCameraPosition(position(camera)))
    modelLayer.setNeedsRender()
  }

  private fun interpolate(a: MapCamera, b: MapCamera, f: Double): MapCamera {
    val turn = ((b.heading - a.heading) % 360 + 540) % 360 - 180
    return MapCamera(
      a.latitude + (b.latitude - a.latitude) * f,
      a.longitude + (b.longitude - a.longitude) * f,
      exp(ln(maxOf(1.0, a.distance)) + (ln(maxOf(1.0, b.distance)) - ln(maxOf(1.0, a.distance))) * f),
      a.pitch + (b.pitch - a.pitch) * f,
      ((a.heading + turn * f) % 360 + 360) % 360,
    )
  }

  override fun getVisibleRegion(): MapRegion? {
    val bounds = map?.projection?.visibleRegion?.latLngBounds ?: return null
    return region(bounds)
  }

  internal fun region(bounds: LatLngBounds): MapRegion {
    var lngDelta = bounds.northeast.longitude - bounds.southwest.longitude
    if (lngDelta < 0) lngDelta += 360
    var lng = bounds.southwest.longitude + lngDelta / 2
    if (lng > 180) lng -= 360
    return MapRegion((bounds.southwest.latitude + bounds.northeast.latitude) / 2, lng,
      bounds.northeast.latitude - bounds.southwest.latitude, lngDelta)
  }

  override fun setRegion(region: MapRegion, durationMs: Double) {
    stopFlight()
    endTrackingForCameraMove()
    val bounds = LatLngBounds(
      LatLng(region.latitude - region.latitudeDelta / 2, region.longitude - region.longitudeDelta / 2),
      LatLng(region.latitude + region.latitudeDelta / 2, region.longitude + region.longitudeDelta / 2),
    )
    move(CameraUpdateFactory.newLatLngBounds(bounds, 0), durationMs)
  }

  /** Applies a camera update, animated over `durationMs` (0 jumps). */
  internal fun move(update: CameraUpdate, durationMs: Double) {
    val map = map ?: return
    if (durationMs <= 0) map.moveCamera(update) else map.animateCamera(update, durationMs.toInt(), null)
    modelLayer.setNeedsRender()
  }

  override fun fitToCoordinates(coordinates: Array<MapCoordinate>, padding: EdgeInsets, animated: Boolean) {
    if (coordinates.isEmpty()) return
    stopFlight()
    endTrackingForCameraMove()
    if (coordinates.size == 1) {
      move(CameraUpdateFactory.newLatLng(LatLng(coordinates[0].latitude, coordinates[0].longitude)), if (animated) 350.0 else 0.0)
      return
    }
    val builder = LatLngBounds.Builder()
    coordinates.forEach { builder.include(LatLng(it.latitude, it.longitude)) }
    val view = mapView ?: return
    // Google pads equally; fit inside the padded area with the largest side.
    val pad = (maxOf(padding.top, padding.left, padding.bottom, padding.right) * density).toInt()
    val update = if (view.width > 0 && view.height > 0) {
      CameraUpdateFactory.newLatLngBounds(builder.build(), view.width, view.height, pad)
    } else {
      CameraUpdateFactory.newLatLngBounds(builder.build(), pad)
    }
    move(update, if (animated) 350.0 else 0.0)
  }

  override fun fitToMarkers(ids: Set<String>, padding: EdgeInsets, animated: Boolean) {
    val coordinates = markerData.values.filter { ids.isEmpty() || it.id in ids }
      .map { MapCoordinate(it.latitude, it.longitude) }.toTypedArray()
    fitToCoordinates(coordinates, padding, animated)
  }

  override fun pointForCoordinate(coordinate: MapCoordinate): MapPoint? {
    val p = map?.projection?.toScreenLocation(LatLng(coordinate.latitude, coordinate.longitude)) ?: return null
    return MapPoint(p.x / density, p.y / density)
  }

  override fun coordinateForPoint(point: MapPoint): MapCoordinate? {
    val c = map?.projection?.fromScreenLocation(Point((point.x * density).toInt(), (point.y * density).toInt())) ?: return null
    return MapCoordinate(c.latitude, c.longitude)
  }

  // MARK: User location

  private var lastLocation: Location? = null

  private fun hasLocationPermission(): Boolean =
    context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
      context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

  private var askedForPermission = false

  /** Asks for location access once; the location layer turns on when the map is next set up after it is granted. */
  private fun requestLocationPermission() {
    if (hasLocationPermission() || askedForPermission) return
    askedForPermission = true
    val activity = activity() ?: return reportError("showing the user's location needs the location permission")
    activity.requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), 0x6d6d)
    // Re-check after the dialog.
    main.postDelayed(object : Runnable {
      var tries = 0
      override fun run() {
        if (hasLocationPermission()) applySettings() else if (++tries < 60) main.postDelayed(this, 1000)
      }
    }, 1000)
  }

  private fun myLocationChanged(location: Location) {
    lastLocation = location
    listener?.onUserLocationChange(UserLocationEvent(
      location.latitude, location.longitude, location.altitude, location.accuracy.toDouble(),
      if (location.hasVerticalAccuracy()) location.verticalAccuracyMeters.toDouble() else -1.0,
      if (location.hasBearing()) location.bearing.toDouble() else -1.0,
      if (location.hasSpeed()) location.speed.toDouble() else -1.0,
    ))
    if (userTrackingMode != UserTrackingMode.NONE) follow(location)
  }

  /** Google has no tracking mode: follow the location (and its bearing) ourselves. */
  private fun follow(location: Location) {
    val map = map ?: return
    val current = map.cameraPosition
    val bearing = if (userTrackingMode == UserTrackingMode.FOLLOWWITHHEADING && location.hasBearing()) location.bearing else current.bearing
    map.animateCamera(CameraUpdateFactory.newCameraPosition(CameraPosition.Builder(current)
      .target(LatLng(location.latitude, location.longitude)).zoom(maxOf(current.zoom, 15f)).bearing(bearing).build()))
  }

  internal fun endTrackingForCameraMove() {
    if (userTrackingMode == UserTrackingMode.NONE) return
    userTrackingMode = UserTrackingMode.NONE
    listener?.onUserTrackingModeChange(UserTrackingMode.NONE)
  }

  // MARK: Methods

  override fun takeSnapshot(width: Double, height: Double, completion: (Result<String>) -> Unit) {
    val map = map ?: return completion(Result.failure(IllegalStateException("Google Maps: the map is not ready yet")))
    map.snapshot { bitmap ->
      if (bitmap == null) return@snapshot completion(Result.failure(IllegalStateException("Google Maps: no snapshot")))
      val out = if (width > 0 && height > 0) {
        Bitmap.createScaledBitmap(bitmap, (width * density).toInt(), (height * density).toInt(), true)
      } else bitmap
      try {
        val file = File(context.cacheDir, "munim-maps-google-${System.nanoTime()}.png")
        file.outputStream().use { out.compress(Bitmap.CompressFormat.PNG, 100, it) }
        completion(Result.success(file.absolutePath))
      } catch (error: Exception) {
        completion(Result.failure(error))
      }
    }
  }

  /** Android's Maps SDK has no geocoder; Android's own (`android.location.Geocoder`) answers. */
  override fun addressForCoordinate(coordinate: MapCoordinate, completion: (Result<MapAddress>) -> Unit) {
    Executors.newSingleThreadExecutor().execute {
      val result = runCatching {
        @Suppress("DEPRECATION")
        val a = Geocoder(context, Locale.getDefault()).getFromLocation(coordinate.latitude, coordinate.longitude, 1)
          ?.firstOrNull() ?: error("No address here")
        val street = listOfNotNull(a.subThoroughfare, a.thoroughfare).joinToString(" ")
        val lines = (0..a.maxAddressLineIndex).mapNotNull { a.getAddressLine(it) }
        MapAddress(
          a.featureName ?: "", street, a.locality ?: "", a.adminArea ?: "", a.postalCode ?: "",
          a.countryName ?: "", a.countryCode ?: "", lines.joinToString(", "),
          listOf(street, a.locality ?: "").filter { it.isNotEmpty() }.joinToString(", "),
        )
      }
      main.post { completion(result) }
    }
  }

  // MARK: MapCameraSource

  override val cameraView: View? get() = if (destroyed) null else mapView

  override fun cameraState(previous: MapCameraState?): MapCameraState? {
    val map = map ?: return null
    val view = mapView ?: return null
    return GoogleCamera.state(map, view, paddingPx(), density, isDark())
  }

  override fun screenPoint(latitude: Double, longitude: Double): PointF? {
    val p = map?.projection?.toScreenLocation(LatLng(latitude, longitude)) ?: return null
    return PointF(p.x.toFloat(), p.y.toFloat())
  }

  private fun isDark(): Boolean = when (colorScheme) {
    MunimColorScheme.DARK -> true
    MunimColorScheme.LIGHT -> false
    else -> (context.resources.configuration.uiMode and android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
      android.content.res.Configuration.UI_MODE_NIGHT_YES
  }

  internal fun indoorBuilding(): JSONObject {
    val building = map?.focusedBuilding ?: return JSONObject()
    val levels = JSONArray()
    building.levels.forEach { levels.put(GOut.obj("name" to it.name, "shortName" to it.shortName)) }
    return GOut.obj(
      "levels" to levels, "defaultLevelIndex" to building.defaultLevelIndex,
      "activeLevelIndex" to building.activeLevelIndex, "underground" to building.isUnderground,
    )
  }

  // MARK: Overrides implemented in the other files

  override fun selectMarker(id: String) = selectMarkerById(id)
  override fun deselectMarker(id: String) = deselectMarkerById(id)
  override fun overlayAtPoint(point: MapPoint): String =
    overlayHit(point.x * density, point.y * density)?.first ?: ""
  override fun providerCommand(command: String, args: JSONObject, completion: (Result<String>) -> Unit) {
    if (mode3d?.command(command, GJson(args), completion) == true) return
    runCommand(command, GJson(args), completion)
  }

  /** Street View is Google's Look Around. */
  override fun hasLookAround(coordinate: MapCoordinate, completion: (Boolean) -> Unit) =
    streetViewCoverage(GJson(JSONObject().put("latitude", coordinate.latitude).put("longitude", coordinate.longitude))) {
      completion(it != null)
    }

  override fun openLookAround(coordinate: MapCoordinate, completion: (Boolean) -> Unit) =
    openStreetView(GJson(JSONObject().put("latitude", coordinate.latitude).put("longitude", coordinate.longitude)
      .put("presentation", "fullScreen"))) { completion(it.isSuccess) }

  @Suppress("unused")
  private val radians = PI / 180
}

/** MapKit-style point-of-interest categories (`pointsOfInterest`) as Google JSON style rules. */
object GooglePointsOfInterest {
  private val groups = listOf(
    "poi.attraction" to listOf("amusementPark", "aquarium", "museum", "theater", "zoo", "movieTheater", "stadium"),
    "poi.business" to listOf("bakery", "bank", "brewery", "cafe", "carRental", "evCharger", "foodMarket", "gasStation",
      "hotel", "laundry", "nightlife", "parking", "restaurant", "store", "winery", "atm"),
    "poi.government" to listOf("fireStation", "police", "postOffice", "library"),
    "poi.medical" to listOf("hospital", "pharmacy"),
    "poi.park" to listOf("park", "nationalPark", "beach", "campground", "marina"),
    "poi.school" to listOf("school", "university"),
    "poi.sports_complex" to listOf("fitnessCenter", "stadium"),
    "transit.station" to listOf("publicTransport", "airport"),
  )

  private fun off(type: String) = JSONObject().put("featureType", type)
    .put("stylers", JSONArray().put(JSONObject().put("visibility", "off")))

  /** `all`, `none`, or comma-separated `MKPOICategory…` values or short names. */
  fun rules(filter: String): List<JSONObject> {
    val text = filter.trim()
    if (text.isEmpty() || text == "all") return emptyList()
    if (text == "none") return listOf(off("poi"), off("transit.station"))
    val included = text.split(",").map {
      it.trim().removePrefix("MKPOICategory").replaceFirstChar { c -> c.lowercase() }
    }.toSet()
    return groups.filter { (_, categories) -> categories.none { it in included } }.map { off(it.first) }
  }
}
