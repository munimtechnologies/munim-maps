@file:OptIn(MapboxExperimental::class, MapboxDelicateApi::class)

package com.munimmaps.engines.mapbox

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.TimeInterpolator
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.PointF
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Choreographer
import android.view.MotionEvent
import android.view.TextureView
import android.view.View
import android.view.ViewConfiguration
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.LinearInterpolator
import android.widget.FrameLayout
import com.mapbox.common.Cancelable
import com.mapbox.common.MapboxOptions
import com.mapbox.geojson.Point
import com.mapbox.maps.CameraOptions
import com.mapbox.maps.CoordinateBounds
import com.mapbox.maps.EdgeInsets
import com.mapbox.maps.MapInitOptions
import com.mapbox.maps.MapView
import com.mapbox.maps.MapboxDelicateApi
import com.mapbox.maps.MapboxExperimental
import com.mapbox.maps.MapboxMap
import com.mapbox.maps.ScreenCoordinate
import com.mapbox.maps.plugin.animation.MapAnimationOptions
import com.mapbox.maps.plugin.animation.camera
import com.mapbox.maps.plugin.animation.easeTo
import com.mapbox.maps.plugin.gestures.OnMapClickListener
import com.mapbox.maps.plugin.gestures.OnMapLongClickListener
import com.mapbox.maps.plugin.gestures.gestures
import com.mapbox.maps.toCameraOptions
import com.margelo.nitro.munimmaps.CameraKeyframe
import com.margelo.nitro.munimmaps.EdgeInsets as MunimInsets
import com.margelo.nitro.munimmaps.FeatureVisibility
import com.margelo.nitro.munimmaps.MapAddress
import com.margelo.nitro.munimmaps.MapCamera
import com.margelo.nitro.munimmaps.MapCameraEasing
import com.margelo.nitro.munimmaps.MapColorScheme
import com.margelo.nitro.munimmaps.MapCoordinate
import com.margelo.nitro.munimmaps.MapElevation
import com.margelo.nitro.munimmaps.MapPoint
import com.margelo.nitro.munimmaps.MapPressEvent
import com.margelo.nitro.munimmaps.MapProvider
import com.margelo.nitro.munimmaps.MapRegion
import com.margelo.nitro.munimmaps.MapStyle
import com.margelo.nitro.munimmaps.NativeCircle
import com.margelo.nitro.munimmaps.NativeClusterStyle
import com.margelo.nitro.munimmaps.NativeMarker
import com.margelo.nitro.munimmaps.NativePolygon
import com.margelo.nitro.munimmaps.NativePolyline
import com.margelo.nitro.munimmaps.NativeTileOverlay
import com.margelo.nitro.munimmaps.UserTrackingMode
import com.munimmaps.engine.MapCameraSource
import com.munimmaps.engine.MapCameraState
import com.munimmaps.engine.MunimMapEngine
import com.munimmaps.engine.MunimMapEngineFactory
import com.munimmaps.engine.MunimMapEngineListener
import com.munimmaps.engine.MunimMapsConfiguration
import com.munimmaps.engine.ProviderJson
import com.munimmaps.engine.UnavailableMapEngine
import com.munimmaps.models.MunimModelLayer
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.Executors
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.tan

/**
 * The Mapbox engine's factory, found by name by `MunimMapEngines`. Offline
 * downloads (`MapboxOffline` in JavaScript) need no map and run here.
 */
object MapboxMapEngineFactory : MunimMapEngineFactory {
  override val isImplemented = true

  override fun create(context: Context): MunimMapEngine {
    MunimMapsConfiguration.load(context)
    val token = MunimMapsConfiguration.mapboxAccessToken.trim()
    if (token.isEmpty()) {
      return UnavailableMapEngine(context, MapProvider.MAPBOX,
        "Mapbox needs a public access token (pk.…): configureMunimMaps({ mapboxAccessToken }), the Expo config " +
          "plugin's mapboxAccessToken option, or a mapbox_access_token string resource.")
    }
    MapboxOptions.accessToken = token
    return MapboxMapEngine(context)
  }

  override fun providerCommand(
    context: Context,
    command: String,
    args: JSONObject,
    emit: (String, Any?) -> Unit,
    completion: (Result<String>) -> Unit,
  ) {
    MunimMapsConfiguration.load(context)
    if (MunimMapsConfiguration.mapboxAccessToken.isNotBlank()) MapboxOptions.accessToken = MunimMapsConfiguration.mapboxAccessToken.trim()
    MapboxOffline.call(context, command, args, emit) { result -> completion(result.map { ProviderJson.stringOf(it) }) }
  }
}

/**
 * The Mapbox engine on Android: Mapbox Maps SDK v11's `MapView` (Mapbox
 * Standard by default), munim-maps' Filament 3D layer over it, and every
 * Mapbox feature through `mapbox={{…}}` ([MapboxStyleController],
 * [MapboxControls]), `ref.providerCommand` ([MapboxCalls]) and offline
 * downloads ([MapboxOffline]).
 *
 * - Markers are point annotations ([MapboxAnnotations]); `MarkerView`s are
 *   Mapbox view annotations (point annotations while draggable).
 * - Polylines, polygons, circles and tile overlays are GeoJSON / raster
 *   sources with their own layers ([MapboxShapes]), in Standard's `middle`
 *   (above roads) or `top` (above labels) slot.
 * - The 3D layer reads Mapbox's camera (zoom with 512-point tiles, the
 *   camera's vertical field of view, padding) every frame.
 * - Taps go to the 3D layer first, then annotations and featureset
 *   interactions, then tappable overlays, then `onPress`.
 */
class MapboxMapEngine(context: Context) : MunimMapEngine, MapCameraSource {
  override val provider = MapProvider.MAPBOX
  override var listener: MunimMapEngineListener? = null

  internal val context: Context = context
  internal val density = context.resources.displayMetrics.density.toDouble()
  internal val main = Handler(Looper.getMainLooper())
  internal val mapView: MapView
  internal val map: MapboxMap get() = mapView.mapboxMap
  private val root: FrameLayout
  override val modelLayer = MunimModelLayer(context)
  override val view: View get() = root

  internal val style = MapboxStyleController(this)
  internal val shapes = MapboxShapes(this)
  internal val annotations = MapboxAnnotations(this)
  internal val controls = MapboxControls(this)
  private val calls = MapboxCalls(this)

  internal var destroyed = false
    private set
  private var started = false
  internal var styleLoaded = false
    private set
  private var mapReadyReported = false
  private var initialCamera: MapCamera? = null
  private var appliedInitialCamera = false
  private var cameraMovedSinceIdle = false
  private val subscriptions = mutableListOf<Cancelable>()

  // Shared props the style controller reads.
  internal var mapStyle = MapStyle.STANDARD
  internal var elevation = MapElevation.FLAT
  internal var globe = false
  internal var colorScheme = MapColorScheme.SYSTEM
  internal var showsBuildings = true
  internal var showsTraffic = false
  internal var pointsOfInterest = "all"
  internal var styleUrl = ""
  internal var mapPadding = EdgeInsets(0.0, 0.0, 0.0, 0.0)
  internal var overlayPressEnabled = false

  init {
    mapView = MapView(context, MapInitOptions(context, styleUri = null, textureView = false))
    root = object : FrameLayout(context) {
      override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        start()
      }

      override fun onDetachedFromWindow() {
        stop()
        super.onDetachedFromWindow()
      }

      override fun dispatchTouchEvent(event: MotionEvent): Boolean = dispatchTouch(event) { super.dispatchTouchEvent(it) }
    }
    root.addView(mapView, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    root.addView(modelLayer.view, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    controls.attachButton(root)
    mapView.addOnLayoutChangeListener { _, l, t, r, b, ol, ot, or, ob ->
      if (r - l != or - ol || b - t != ob - ot) {
        applyInitialCameraIfReady()
        controls.applyCameraLimits()
      }
      modelLayer.setNeedsRender()
    }
    setUpMap()
    modelLayer.attach(this)
    style.scheduleRefresh()
  }

  private fun setUpMap() {
    val map = map
    subscriptions += map.subscribeCameraChanged { event ->
      modelLayer.setNeedsRender()
      cameraMovedSinceIdle = true
      getCamera()?.let { listener?.onCameraMove(it) }
      controls.cameraMoved()
      style.emit("cameraChanged") {
        val cs = event.cameraState
        JSONObject()
          .put("center", MapboxJson.coordinate(cs.center))
          .put("zoom", cs.zoom).put("bearing", cs.bearing).put("pitch", cs.pitch)
          .put("padding", MapboxJson.insetsJson(cs.padding, density))
      }
    }
    subscriptions += map.subscribeMapIdle {
      modelLayer.setNeedsRender()
      if (cameraMovedSinceIdle) {
        cameraMovedSinceIdle = false
        getCamera()?.let { listener?.onCameraChange(it) }
        controls.cameraIdle()
      }
      style.emit("mapIdle") { JSONObject() }
    }
    subscriptions += map.subscribeMapLoadingError { error ->
      val message = "Mapbox: ${error.message}"
      Log.w(TAG, message)
      if (error.type == com.mapbox.maps.MapLoadingErrorType.STYLE) listener?.onError(message)
      style.emit("mapLoadingError") {
        JSONObject().put("type", error.type.name.lowercase()).put("message", error.message)
          .put("sourceId", error.sourceId ?: JSONObject.NULL)
          .put("tileId", error.tileId?.let { JSONObject().put("z", it.z.toInt()).put("x", it.x).put("y", it.y) } ?: JSONObject.NULL)
      }
    }
    style.subscribeEvents()

    // Taps on the map surface: after annotations and featureset interactions.
    mapView.gestures.addOnMapClickListener(OnMapClickListener { point -> mapClick(point) })
    mapView.gestures.addOnMapLongClickListener(OnMapLongClickListener { point -> mapLongClick(point) })
  }

  private fun start() {
    if (started || destroyed) return
    started = true
    mapView.onStart()
    controls.start()
  }

  private fun stop() {
    if (!started || destroyed) return
    started = false
    controls.stop()
    mapView.onStop()
  }

  override fun destroy() {
    if (destroyed) return
    stopFlight()
    stop()
    destroyed = true
    subscriptions.forEach { it.cancel() }
    subscriptions.clear()
    style.destroy()
    annotations.destroy()
    controls.destroy()
    calls.destroy()
    modelLayer.destroy()
    mapView.onDestroy()
  }

  // Style

  /** Loads a style (URI or JSON); [onLoaded] runs once it is loaded. */
  internal fun loadStyle(uri: String?, json: String?, onLoaded: () -> Unit) {
    styleLoaded = false
    val callback = com.mapbox.maps.Style.OnStyleLoaded {
      if (destroyed) return@OnStyleLoaded
      styleLoaded = true
      onLoaded()
      shapes.styleLoaded()
      annotations.styleLoaded()
      controls.styleLoaded()
      modelLayer.setNeedsRender()
      applyInitialCameraIfReady()
      if (!mapReadyReported) {
        mapReadyReported = true
        listener?.onMapReady()
      }
    }
    if (json != null) map.loadStyle(json, callback) else map.loadStyle(uri ?: com.mapbox.maps.Style.STANDARD, callback)
  }

  // Taps

  private var downX = 0f
  private var downY = 0f
  private var downTime = 0L
  private var tapCandidate = false
  private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop

  /**
   * Taps on a 3D model win over everything under them: a short tap whose
   * point hits a model goes to the model layer and the map sees a cancel.
   */
  private fun dispatchTouch(event: MotionEvent, superDispatch: (MotionEvent) -> Boolean): Boolean {
    when (event.actionMasked) {
      MotionEvent.ACTION_DOWN -> {
        downX = event.x
        downY = event.y
        downTime = event.eventTime
        tapCandidate = true
      }
      MotionEvent.ACTION_POINTER_DOWN -> tapCandidate = false
      MotionEvent.ACTION_MOVE -> if (abs(event.x - downX) > touchSlop || abs(event.y - downY) > touchSlop) tapCandidate = false
      MotionEvent.ACTION_UP -> {
        if (tapCandidate && event.eventTime - downTime < ViewConfiguration.getLongPressTimeout() &&
          modelLayer.handleTap(event.x, event.y)
        ) {
          val cancel = MotionEvent.obtain(event).apply { action = MotionEvent.ACTION_CANCEL }
          superDispatch(cancel)
          cancel.recycle()
          tapCandidate = false
          return true
        }
        tapCandidate = false
      }
    }
    return superDispatch(event)
  }

  private fun mapClick(point: Point): Boolean {
    val pixel = map.pixelForCoordinate(point)
    if (annotations.handleMapClick()) return true
    if (overlayPressEnabled) {
      val hit = shapes.hit(pixel.x, pixel.y)
      if (hit != null) {
        listener?.onOverlayPress(com.margelo.nitro.munimmaps.OverlayPressEvent(hit.first, hit.second, point.latitude(), point.longitude()))
        return true
      }
    }
    listener?.onPress(MapPressEvent(point.latitude(), point.longitude(), pixel.x / density, pixel.y / density))
    return true
  }

  private fun mapLongClick(point: Point): Boolean {
    val pixel = map.pixelForCoordinate(point)
    listener?.onLongPress(MapPressEvent(point.latitude(), point.longitude(), pixel.x / density, pixel.y / density))
    return true
  }

  // Props

  override fun setStyleUrl(url: String) {
    if (url == styleUrl) return
    styleUrl = url
    style.scheduleRefresh()
  }

  override fun setProviderOptions(options: JSONObject) {
    style.setOptions(options)
    controls.setOptions(options)
  }

  override fun setMarkers(markers: Array<NativeMarker>) = annotations.setMarkers(markers)
  override fun setClusterStyles(styles: Array<NativeClusterStyle>) = annotations.setClusterStyles(styles)
  override fun setViewMarker(marker: NativeMarker, image: Bitmap?) = annotations.setViewMarker(marker, image)
  override fun setViewMarkerImage(image: Bitmap?, id: String) = annotations.setViewMarkerImage(image, id)
  override fun removeViewMarker(id: String) = annotations.removeViewMarker(id)
  override fun selectMarker(id: String) = annotations.select(id, true)
  override fun deselectMarker(id: String) = annotations.deselect(id)

  override fun setPolylines(polylines: Array<NativePolyline>) = shapes.setPolylines(polylines)
  override fun setPolygons(polygons: Array<NativePolygon>) = shapes.setPolygons(polygons)
  override fun setCircles(circles: Array<NativeCircle>) = shapes.setCircles(circles)
  override fun setTileOverlays(overlays: Array<NativeTileOverlay>) = shapes.setTileOverlays(overlays)

  override fun setInitialCamera(camera: MapCamera) {
    initialCamera = camera
    applyInitialCameraIfReady()
  }

  private fun applyInitialCameraIfReady() {
    if (appliedInitialCamera || destroyed) return
    val camera = initialCamera ?: return
    if (mapView.height <= 0 || mapView.width <= 0) return
    appliedInitialCamera = true
    map.setCamera(cameraOptions(camera))
    modelLayer.setNeedsRender()
  }

  override fun setMapStyle(style: MapStyle) {
    if (style == mapStyle) return
    mapStyle = style
    this.style.scheduleRefresh()
  }

  override fun setElevation(elevation: MapElevation) {
    if (elevation == this.elevation) return
    this.elevation = elevation
    style.scheduleRefresh()
  }

  override fun setGlobe(globe: Boolean) {
    if (globe == this.globe) return
    this.globe = globe
    style.scheduleRefresh()
  }

  override fun setColorScheme(scheme: MapColorScheme) {
    if (scheme == colorScheme) return
    colorScheme = scheme
    style.scheduleRefresh()
  }

  override fun setShowsBuildings(shows: Boolean) {
    if (shows == showsBuildings) return
    showsBuildings = shows
    style.scheduleRefresh()
  }

  override fun setShowsTraffic(shows: Boolean) {
    if (shows == showsTraffic) return
    showsTraffic = shows
    style.scheduleRefresh()
  }

  override fun setPointsOfInterest(filter: String) {
    if (filter == pointsOfInterest) return
    pointsOfInterest = filter
    style.scheduleRefresh()
  }

  override fun setShowsUserLocation(shows: Boolean) = controls.setShowsUserLocation(shows)
  override fun setUserTrackingMode(mode: UserTrackingMode) = controls.setUserTrackingMode(mode)
  override fun setShowsUserTrackingButton(shows: Boolean) = controls.setShowsTrackingButton(shows)
  override fun setCompassVisibility(visibility: FeatureVisibility) = controls.setCompassVisibility(visibility)
  override fun setScaleVisibility(visibility: FeatureVisibility) = controls.setScaleVisibility(visibility)
  override fun setGestures(zoom: Boolean, scroll: Boolean, rotate: Boolean, pitch: Boolean) =
    controls.setGestures(zoom, scroll, rotate, pitch)
  override fun setCameraDistanceRange(min: Double, max: Double) = controls.setCameraDistanceRange(min, max)
  override fun setCameraBoundary(region: MapRegion?) = controls.setCameraBoundary(region)

  override fun setMapPadding(padding: MunimInsets) {
    mapPadding = EdgeInsets(padding.top * density, padding.left * density, padding.bottom * density, padding.right * density)
    map.setCamera(CameraOptions.Builder().padding(mapPadding).build())
    modelLayer.setNeedsRender()
  }

  override fun setOverlayPressEnabled(enabled: Boolean) {
    overlayPressEnabled = enabled
  }

  // Camera: Mapbox zooms (512-point tiles); munim-maps speaks metres from the camera.

  /** Vertical field of view in radians (Mapbox's default is 36.87°). */
  private fun fieldOfView(degrees: Double?): Double =
    if (degrees != null && degrees > 1 && degrees < 179) degrees * PI / 180 else DEFAULT_FOV

  private fun heightPoints(): Double = maxOf(1.0, mapView.height / density)

  private fun metersPerPoint(zoom: Double, latitude: Double): Double =
    cos(latitude * PI / 180) * 2 * PI * MapCameraState.MERCATOR_RADIUS / (TILE_SIZE * 2.0.pow(zoom))

  /** Metres from the camera to the centre at this zoom. */
  internal fun distance(zoom: Double, latitude: Double, fov: Double = currentFov()): Double =
    heightPoints() / 2 / tan(fov / 2) * metersPerPoint(zoom, latitude)

  internal fun zoom(distance: Double, latitude: Double, fov: Double = currentFov()): Double {
    val points = heightPoints() / 2 / tan(fov / 2)
    val worldMeters = cos(latitude * PI / 180) * 2 * PI * MapCameraState.MERCATOR_RADIUS
    return ln(points * worldMeters / (TILE_SIZE * maxOf(0.01, distance))) / ln(2.0)
  }

  private fun currentFov(): Double = fieldOfView(map.cameraState.verticalFov)

  internal fun cameraOptions(camera: MapCamera): CameraOptions = CameraOptions.Builder()
    .center(Point.fromLngLat(camera.longitude, camera.latitude))
    .zoom(zoom(camera.distance, camera.latitude))
    .pitch(camera.pitch)
    .bearing(camera.heading)
    .build()

  override fun getCamera(): MapCamera? {
    if (destroyed) return null
    val cs = map.cameraState
    val center = cs.center
    return MapCamera(center.latitude(), center.longitude(),
      distance(cs.zoom, center.latitude(), fieldOfView(cs.verticalFov)), cs.pitch, cs.bearing)
  }

  /** Every camera call except flights stops a flight and ends user tracking. */
  private fun takeCamera() {
    stopFlight()
    controls.endTrackingForCameraMove()
    mapView.camera.cancelAllAnimators()
  }

  override fun setCamera(camera: MapCamera, animated: Boolean) {
    takeCamera()
    if (animated) {
      map.easeTo(cameraOptions(camera), MapAnimationOptions.Builder().duration(600).build())
    } else {
      map.setCamera(cameraOptions(camera))
    }
    modelLayer.setNeedsRender()
  }

  override fun animateCamera(camera: MapCamera, durationMs: Double, easing: MapCameraEasing) {
    takeCamera()
    if (durationMs <= 0) {
      map.setCamera(cameraOptions(camera))
      return
    }
    val interpolator: TimeInterpolator = if (easing == MapCameraEasing.LINEAR) LinearInterpolator() else AccelerateDecelerateInterpolator()
    map.easeTo(cameraOptions(camera), MapAnimationOptions.Builder().duration(durationMs.toLong()).interpolator(interpolator).build())
  }

  // Flights: keyframes on the wall clock (seconds since 1970), like iOS.

  private var flight: Triple<List<CameraKeyframe>, Double, Boolean>? = null
  private val flightFrame = object : Choreographer.FrameCallback {
    override fun doFrame(frameTimeNanos: Long) {
      if (flight == null || destroyed) return
      stepFlight()
      if (flight != null) Choreographer.getInstance().postFrameCallback(this)
    }
  }

  override fun flyCamera(keyframes: Array<CameraKeyframe>, start: Double, loop: Boolean) {
    if (keyframes.size < 2) {
      stopFlight()
      keyframes.firstOrNull()?.let { setCamera(it.camera, false) }
      return
    }
    controls.endTrackingForCameraMove()
    mapView.camera.cancelAllAnimators()
    val wasFlying = flight != null
    flight = Triple(keyframes.sortedBy { it.t }, start, loop)
    if (!wasFlying) Choreographer.getInstance().postFrameCallback(flightFrame)
    stepFlight()
  }

  override fun stopFlight() {
    flight = null
    Choreographer.getInstance().removeFrameCallback(flightFrame)
  }

  private fun stepFlight() {
    val (keyframes, start, loop) = flight ?: return
    val first = keyframes.first()
    val last = keyframes.last()
    var t = System.currentTimeMillis() / 1000.0 - start
    val span = last.t - first.t
    if (loop && span > 0) {
      t = first.t + ((t - first.t) % span)
      if (t < first.t) t += span
    }
    val camera = when {
      t <= first.t -> first.camera
      t >= last.t -> {
        if (!loop) flight = null
        last.camera
      }
      else -> {
        var i = 1
        while (i < keyframes.size - 1 && keyframes[i].t < t) i++
        val a = keyframes[i - 1]
        val b = keyframes[i]
        interpolate(a.camera, b.camera, (t - a.t) / maxOf(1e-9, b.t - a.t))
      }
    }
    map.setCamera(cameraOptions(camera))
    modelLayer.setNeedsRender()
  }

  private fun interpolate(a: MapCamera, b: MapCamera, f: Double): MapCamera {
    val turn = (((b.heading - a.heading) % 360) + 540) % 360 - 180
    return MapCamera(
      a.latitude + (b.latitude - a.latitude) * f,
      a.longitude + (b.longitude - a.longitude) * f,
      exp(ln(maxOf(1.0, a.distance)) + (ln(maxOf(1.0, b.distance)) - ln(maxOf(1.0, a.distance))) * f),
      a.pitch + (b.pitch - a.pitch) * f,
      ((a.heading + turn * f) % 360 + 360) % 360,
    )
  }

  override fun getVisibleRegion(): MapRegion? {
    if (destroyed || mapView.width <= 0) return null
    val bounds = map.coordinateBoundsForCamera(map.cameraState.toCameraOptions())
    val center = bounds.center()
    return MapRegion(center.latitude(), center.longitude(), bounds.latitudeSpan(), bounds.longitudeSpan())
  }

  override fun setRegion(region: MapRegion, durationMs: Double) {
    takeCamera()
    val bounds = CoordinateBounds(
      Point.fromLngLat(region.longitude - region.longitudeDelta / 2, region.latitude - region.latitudeDelta / 2),
      Point.fromLngLat(region.longitude + region.longitudeDelta / 2, region.latitude + region.latitudeDelta / 2),
    )
    val camera = map.cameraForCoordinateBounds(bounds, EdgeInsets(0.0, 0.0, 0.0, 0.0), map.cameraState.bearing, 0.0, null, null)
    if (durationMs > 0) {
      map.easeTo(camera, MapAnimationOptions.Builder().duration(durationMs.toLong()).build())
    } else {
      map.setCamera(camera)
    }
  }

  override fun fitToCoordinates(coordinates: Array<MapCoordinate>, padding: MunimInsets, animated: Boolean) {
    if (coordinates.isEmpty()) return
    takeCamera()
    val points = coordinates.map { Point.fromLngLat(it.longitude, it.latitude) }
    val camera = if (points.size == 1) {
      CameraOptions.Builder().center(points[0]).build()
    } else {
      val current = map.cameraState
      map.cameraForCoordinates(points,
        CameraOptions.Builder().bearing(current.bearing).pitch(current.pitch).padding(mapPadding).build(),
        EdgeInsets(padding.top * density, padding.left * density, padding.bottom * density, padding.right * density),
        null, null)
    }
    if (animated) map.easeTo(camera, MapAnimationOptions.Builder().duration(600).build()) else map.setCamera(camera)
  }

  override fun fitToMarkers(ids: Set<String>, padding: MunimInsets, animated: Boolean) {
    val coordinates = annotations.coordinates(ids)
    if (coordinates.isEmpty()) return
    fitToCoordinates(coordinates.toTypedArray(), padding, animated)
  }

  override fun pointForCoordinate(coordinate: MapCoordinate): MapPoint? {
    if (destroyed) return null
    val p = map.pixelForCoordinate(Point.fromLngLat(coordinate.longitude, coordinate.latitude))
    return MapPoint(p.x / density, p.y / density)
  }

  override fun coordinateForPoint(point: MapPoint): MapCoordinate? {
    if (destroyed) return null
    val c = map.coordinateForPixel(ScreenCoordinate(point.x * density, point.y * density))
    return MapCoordinate(c.latitude(), c.longitude())
  }

  override fun overlayAtPoint(point: MapPoint): String = shapes.hit(point.x * density, point.y * density)?.first ?: ""

  // Methods

  override fun takeSnapshot(width: Double, height: Double, completion: (Result<String>) -> Unit) {
    mapView.snapshot { bitmap ->
      if (bitmap == null) {
        completion(Result.failure(IllegalStateException("Mapbox: the snapshot failed")))
        return@snapshot
      }
      // The 3D layer draws in its own view: put it over the map.
      var image: Bitmap = bitmap.copy(Bitmap.Config.ARGB_8888, true)
      (modelLayer.view as? TextureView)?.bitmap?.let { overlay ->
        Canvas(image).drawBitmap(overlay, null, android.graphics.Rect(0, 0, image.width, image.height), null)
      }
      if (width > 0 && height > 0) {
        image = Bitmap.createScaledBitmap(image, maxOf(1, (width * density).toInt()), maxOf(1, (height * density).toInt()), true)
      }
      executor.execute {
        val result = runCatching { writePng(context, image, "munim-maps-mapbox") }
        main.post { completion(result) }
      }
    }
  }

  override fun addressForCoordinate(coordinate: MapCoordinate, completion: (Result<MapAddress>) -> Unit) {
    val token = MunimMapsConfiguration.mapboxAccessToken.trim()
    executor.execute {
      val result = runCatching { reverseGeocode(coordinate, token) }
      main.post { completion(result) }
    }
  }

  /** Mapbox Geocoding v6 reverse lookup (counts against the token's Geocoding quota). */
  private fun reverseGeocode(coordinate: MapCoordinate, token: String): MapAddress {
    val url = URL("https://api.mapbox.com/search/geocode/v6/reverse?longitude=${coordinate.longitude}&latitude=${coordinate.latitude}" +
      "&access_token=${URLEncoder.encode(token, "UTF-8")}")
    val connection = url.openConnection() as HttpURLConnection
    connection.connectTimeout = 15_000
    connection.readTimeout = 20_000
    val text = try {
      if (connection.responseCode !in 200..299) error("Mapbox geocoding: HTTP ${connection.responseCode}")
      connection.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
    } finally {
      connection.disconnect()
    }
    val features = JSONObject(text).optJSONArray("features") ?: JSONArray()
    if (features.length() == 0) error("Mapbox geocoding: no address here")
    // The first feature is the most specific (address, street, place…); its context has the rest.
    val props = features.getJSONObject(0).optJSONObject("properties") ?: JSONObject()
    val context = props.optJSONObject("context") ?: JSONObject()
    fun ctx(key: String, field: String = "name") = context.optJSONObject(key)?.optString(field, "") ?: ""
    val street = ctx("address").ifEmpty {
      listOf(ctx("address", "address_number"), ctx("street")).filter { it.isNotEmpty() }.joinToString(" ")
    }.ifEmpty { ctx("street") }
    return MapAddress(
      name = props.optString("name", ""),
      street = street,
      city = ctx("place").ifEmpty { ctx("locality") },
      region = ctx("region"),
      postalCode = ctx("postcode"),
      country = ctx("country"),
      countryCode = ctx("country", "country_code").uppercase(),
      formatted = props.optString("full_address", props.optString("place_formatted", "")),
      shortAddress = props.optString("name", ""),
    )
  }

  override fun providerCommand(command: String, args: JSONObject, completion: (Result<String>) -> Unit) =
    calls.call(command, args) { result -> completion(result.map { ProviderJson.stringOf(it) }) }

  // MapCameraSource

  override val cameraView: View? get() = if (destroyed) null else mapView

  override fun cameraState(previous: MapCameraState?): MapCameraState? {
    if (destroyed || !styleLoaded) return null
    val width = mapView.width.toDouble()
    val height = mapView.height.toDouble()
    if (width < 1 || height < 1) return null
    val cs = map.cameraState
    val center = cs.center
    val fov = fieldOfView(cs.verticalFov)
    val distance = distance(cs.zoom, center.latitude(), fov)
    val padding = cs.padding
    return MapCameraState(
      latitude = center.latitude(),
      longitude = center.longitude(),
      distance = distance,
      altitude = distance * cos(cs.pitch * PI / 180),
      pitch = cs.pitch,
      heading = cs.bearing,
      width = width,
      height = height,
      focalLength = MapCameraState.focalLength(height, fov),
      centerX = padding.left + (width - padding.left - padding.right) / 2,
      centerY = padding.top + (height - padding.top - padding.bottom) / 2,
      globe = style.isGlobe && cs.zoom < GLOBE_ZOOM,
      drawsTerrain = style.terrainOn,
      darkAppearance = style.isDark,
      pixelRatio = density,
    )
  }

  override fun screenPoint(latitude: Double, longitude: Double): PointF? {
    if (destroyed) return null
    val p = map.pixelForCoordinate(Point.fromLngLat(longitude, latitude))
    return PointF(p.x.toFloat(), p.y.toFloat())
  }

  internal fun report(message: String) {
    Log.w(TAG, message)
    listener?.onError("Mapbox: $message")
  }

  internal companion object {
    const val TAG = "MunimMapsMapbox"

    /** Mapbox's vertical field of view: 2 atan(1/3), about 36.87°. */
    const val DEFAULT_FOV = 0.6435011087932844
    const val TILE_SIZE = 512.0

    /** Below this zoom Mapbox's globe projection draws a sphere. */
    const val GLOBE_ZOOM = 5.5
    val executor = Executors.newFixedThreadPool(2)

    fun writePng(context: Context, bitmap: Bitmap, prefix: String): String {
      val file = File(context.cacheDir, "$prefix-${System.currentTimeMillis()}.png")
      FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
      return file.absolutePath
    }
  }
}

/** Animation listener that reports whether it ran to the end. */
internal class FinishListener(private val done: (Boolean) -> Unit) : AnimatorListenerAdapter() {
  private var cancelled = false
  private var reported = false
  override fun onAnimationCancel(animation: Animator) {
    cancelled = true
  }

  override fun onAnimationEnd(animation: Animator) {
    if (reported) return
    reported = true
    done(!cancelled)
  }
}
