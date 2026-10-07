package com.munimmaps.engines.mapbox

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import com.mapbox.common.location.LocationObserver
import com.mapbox.common.location.LocationProvider
import com.mapbox.common.location.LocationServiceFactory
import com.mapbox.geojson.LineString
import com.mapbox.geojson.Point
import com.mapbox.maps.CameraBoundsOptions
import com.mapbox.maps.CoordinateBounds
import com.mapbox.maps.ImageHolder
import com.mapbox.maps.ScreenCoordinate
import com.mapbox.maps.plugin.DistanceUnits
import com.mapbox.maps.plugin.LocationPuck
import com.mapbox.maps.plugin.LocationPuck2D
import com.mapbox.maps.plugin.LocationPuck3D
import com.mapbox.maps.plugin.ModelElevationReference
import com.mapbox.maps.plugin.ModelScaleMode
import com.mapbox.maps.plugin.PuckBearing
import com.mapbox.maps.plugin.ScrollMode
import com.mapbox.maps.plugin.attribution.attribution
import com.mapbox.maps.plugin.compass.compass
import com.mapbox.maps.plugin.gestures.gestures
import com.mapbox.maps.plugin.locationcomponent.LocationComponentConstants
import com.mapbox.maps.plugin.locationcomponent.createDefault2DPuck
import com.mapbox.maps.plugin.locationcomponent.location
import com.mapbox.maps.plugin.logo.logo
import com.mapbox.maps.plugin.scalebar.scalebar
import com.mapbox.maps.plugin.viewport.ViewportStatus
import com.mapbox.maps.plugin.viewport.ViewportStatusObserver
import com.mapbox.maps.plugin.viewport.data.DefaultViewportTransitionOptions
import com.mapbox.maps.plugin.viewport.data.FollowPuckViewportStateBearing
import com.mapbox.maps.plugin.viewport.data.FollowPuckViewportStateOptions
import com.mapbox.maps.plugin.viewport.data.OverviewViewportStateOptions
import com.mapbox.maps.plugin.viewport.data.ViewportStatusChangeReason
import com.mapbox.maps.plugin.viewport.viewport
import com.margelo.nitro.munimmaps.FeatureVisibility
import com.margelo.nitro.munimmaps.MapRegion
import com.margelo.nitro.munimmaps.UserLocationEvent
import com.margelo.nitro.munimmaps.UserTrackingMode
import org.json.JSONArray
import org.json.JSONObject

/**
 * Gestures, ornaments (compass, scale bar, logo, attribution), camera
 * limits, the user location puck, user tracking (Mapbox's viewport plugin)
 * and munim-maps' tracking button, from the shared props and `mapbox={{…}}`
 * (`gestures`, `ornaments`, `puck`, `cameraBounds`).
 */
internal class MapboxControls(private val engine: MapboxMapEngine) {
  private var options = JSONObject()
  private val density get() = engine.density
  private val mapView get() = engine.mapView

  // Shared props
  private var zoomEnabled = true
  private var scrollEnabled = true
  private var rotateEnabled = true
  private var pitchEnabled = true
  private var compassVisibility = FeatureVisibility.ADAPTIVE
  private var scaleVisibility = FeatureVisibility.HIDDEN
  private var minDistance = 0.0
  private var maxDistance = 0.0
  private var boundary: MapRegion? = null
  private var showsUserLocation = false
  private var trackingMode = UserTrackingMode.NONE
  private var started = false

  fun setOptions(next: JSONObject) {
    val before = options
    options = next
    if (!MapboxJson.same(before.opt("gestures"), next.opt("gestures"))) applyGestures()
    if (!MapboxJson.same(before.opt("ornaments"), next.opt("ornaments"))) applyOrnaments()
    if (!MapboxJson.same(before.opt("cameraBounds"), next.opt("cameraBounds"))) applyCameraLimits()
    if (!MapboxJson.same(before.opt("puck"), next.opt("puck"))) applyLocation()
  }

  fun styleLoaded() {
    applyOrnaments()
    applyCameraLimits()
  }

  // Gestures

  fun setGestures(zoom: Boolean, scroll: Boolean, rotate: Boolean, pitch: Boolean) {
    zoomEnabled = zoom
    scrollEnabled = scroll
    rotateEnabled = rotate
    pitchEnabled = pitch
    applyGestures()
  }

  private fun applyGestures() {
    val g = options.optJSONObject("gestures") ?: JSONObject()
    fun flag(key: String, default: Boolean = true) = if (g.has(key)) g.optBoolean(key, default) else default
    mapView.gestures.updateSettings {
      scrollEnabled = this@MapboxControls.scrollEnabled && flag("panEnabled")
      pinchToZoomEnabled = zoomEnabled && flag("pinchEnabled") && flag("pinchZoomEnabled")
      doubleTapToZoomInEnabled = zoomEnabled && flag("doubleTapToZoomInEnabled")
      doubleTouchToZoomOutEnabled = zoomEnabled && flag("doubleTouchToZoomOutEnabled")
      quickZoomEnabled = zoomEnabled && flag("quickZoomEnabled")
      rotateEnabled = this@MapboxControls.rotateEnabled && flag("rotateEnabled")
      pitchEnabled = this@MapboxControls.pitchEnabled && flag("pitchEnabled")
      pinchScrollEnabled = flag("pinchPanEnabled")
      simultaneousRotateAndPinchToZoomEnabled = flag("simultaneousRotateAndPinchZoomEnabled")
      scrollDecelerationEnabled = flag("scrollDecelerationEnabled")
      rotateDecelerationEnabled = flag("rotateDecelerationEnabled")
      pinchToZoomDecelerationEnabled = flag("pinchToZoomDecelerationEnabled")
      increaseRotateThresholdWhenPinchingToZoom = flag("increaseRotateThresholdWhenPinchingToZoom")
      scrollMode = when (g.optString("panMode")) {
        "horizontal" -> ScrollMode.HORIZONTAL
        "vertical" -> ScrollMode.VERTICAL
        else -> ScrollMode.HORIZONTAL_AND_VERTICAL
      }
      focalPoint = g.optJSONObject("focalPoint")?.let { ScreenCoordinate(it.optDouble("x") * density, it.optDouble("y") * density) }
    }
  }

  // Ornaments

  fun setCompassVisibility(visibility: FeatureVisibility) {
    compassVisibility = visibility
    applyOrnaments()
  }

  fun setScaleVisibility(visibility: FeatureVisibility) {
    scaleVisibility = visibility
    applyOrnaments()
  }

  private fun gravity(position: String, default: Int): Int = when (position) {
    "top-left" -> Gravity.TOP or Gravity.START
    "top-right" -> Gravity.TOP or Gravity.END
    "bottom-left" -> Gravity.BOTTOM or Gravity.START
    "bottom-right" -> Gravity.BOTTOM or Gravity.END
    else -> default
  }

  private fun visibilityOf(json: JSONObject?, shared: FeatureVisibility): FeatureVisibility = when (json?.optString("visibility")) {
    "adaptive" -> FeatureVisibility.ADAPTIVE
    "visible" -> FeatureVisibility.VISIBLE
    "hidden" -> FeatureVisibility.HIDDEN
    else -> shared
  }

  /** `[x, y]` points from the corner, as left/top/right/bottom pixel margins. */
  private fun margins(json: JSONObject?): Pair<Float, Float>? {
    val m = json?.optJSONArray("margins") ?: return null
    return (m.optDouble(0, 0.0) * density).toFloat() to (m.optDouble(1, 0.0) * density).toFloat()
  }

  private var scaleAdaptive = false

  private fun applyOrnaments() {
    val o = options.optJSONObject("ornaments") ?: JSONObject()
    val compass = o.optJSONObject("compass")
    val compassVis = visibilityOf(compass, compassVisibility)
    mapView.compass.updateSettings {
      enabled = compassVis != FeatureVisibility.HIDDEN
      fadeWhenFacingNorth = compassVis == FeatureVisibility.ADAPTIVE
      compass?.optString("position")?.let { position = gravity(it, position) }
      margins(compass)?.let { (x, y) ->
        marginLeft = x; marginRight = x; marginTop = y; marginBottom = y
      }
    }
    val scale = o.optJSONObject("scaleBar")
    val scaleVis = visibilityOf(scale, scaleVisibility)
    scaleAdaptive = scaleVis == FeatureVisibility.ADAPTIVE
    mapView.scalebar.updateSettings {
      enabled = scaleVis == FeatureVisibility.VISIBLE
      scale?.optString("position")?.let { position = gravity(it, position) }
      margins(scale)?.let { (x, y) ->
        marginLeft = x; marginRight = x; marginTop = y; marginBottom = y
      }
      when (scale?.optString("units")) {
        "metric" -> distanceUnits = DistanceUnits.METRIC
        "imperial" -> distanceUnits = DistanceUnits.IMPERIAL
        "nautical" -> distanceUnits = DistanceUnits.NAUTICAL
      }
    }
    val logo = o.optJSONObject("logo")
    mapView.logo.updateSettings {
      logo?.optString("position")?.let { position = gravity(it, position) }
      margins(logo)?.let { (x, y) ->
        marginLeft = x; marginRight = x; marginTop = y; marginBottom = y
      }
    }
    val attribution = o.optJSONObject("attributionButton")
    mapView.attribution.updateSettings {
      attribution?.optString("position")?.let { position = gravity(it, position) }
      margins(attribution)?.let { (x, y) ->
        marginLeft = x; marginRight = x; marginTop = y; marginBottom = y
      }
      MapboxColors.parse(attribution?.optString("tintColor"))?.let { iconColor = it }
    }
  }

  private val hideScale = Runnable { if (scaleAdaptive) mapView.scalebar.enabled = false }

  /** Adaptive scale bar: shown while the camera moves. */
  fun cameraMoved() {
    if (!scaleAdaptive) return
    engine.main.removeCallbacks(hideScale)
    if (!mapView.scalebar.enabled) mapView.scalebar.enabled = true
  }

  fun cameraIdle() {
    if (!scaleAdaptive) return
    engine.main.removeCallbacks(hideScale)
    engine.main.postDelayed(hideScale, 1500)
  }

  // Camera limits

  fun setCameraDistanceRange(min: Double, max: Double) {
    minDistance = min
    maxDistance = max
    applyCameraLimits()
  }

  fun setCameraBoundary(region: MapRegion?) {
    boundary = region
    applyCameraLimits()
  }

  fun applyCameraLimits() {
    if (engine.destroyed || mapView.height <= 0) return
    val latitude = engine.map.cameraState.center.latitude()
    val bounds = options.optJSONObject("cameraBounds")
    val builder = CameraBoundsOptions.Builder()
    // Closest distance is the largest zoom; farthest distance the smallest.
    builder.maxZoom(if (bounds?.has("maxZoom") == true) bounds.optDouble("maxZoom") else if (minDistance > 0) engine.zoom(minDistance, latitude) else 25.5)
    builder.minZoom(if (bounds?.has("minZoom") == true) bounds.optDouble("minZoom") else if (maxDistance > 0) engine.zoom(maxDistance, latitude).coerceAtLeast(0.0) else 0.0)
    builder.minPitch(bounds?.optDouble("minPitch", 0.0) ?: 0.0)
    builder.maxPitch(bounds?.optDouble("maxPitch", 85.0) ?: 85.0)
    val box = bounds?.optJSONObject("bounds")
    val coordinateBounds = when {
      box != null -> {
        val sw = MapboxJson.point(box.optJSONObject("southwest"))
        val ne = MapboxJson.point(box.optJSONObject("northeast"))
        if (sw != null && ne != null) CoordinateBounds(sw, ne) else null
      }
      boundary != null -> boundary!!.let { r ->
        CoordinateBounds(
          Point.fromLngLat(r.longitude - r.longitudeDelta / 2, r.latitude - r.latitudeDelta / 2),
          Point.fromLngLat(r.longitude + r.longitudeDelta / 2, r.latitude + r.latitudeDelta / 2),
        )
      }
      else -> null
    }
    builder.bounds(coordinateBounds ?: CoordinateBounds(Point.fromLngLat(-180.0, -90.0), Point.fromLngLat(180.0, 90.0), true))
    engine.map.setBounds(builder.build()).error?.let { engine.report("cameraBounds: $it") }
  }

  // User location and the puck

  fun setShowsUserLocation(shows: Boolean) {
    showsUserLocation = shows
    applyLocation()
  }

  private fun hasPermission(): Boolean {
    val c = engine.context
    return c.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
      c.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
  }

  private var reportedPermission = false
  private val puckImages = mutableMapOf<String, android.graphics.Bitmap>()
  private var puckModelUri: String? = null

  private val locationOn get() = showsUserLocation || trackingMode != UserTrackingMode.NONE

  private fun applyLocation() {
    if (engine.destroyed) return
    val puck = options.optJSONObject("puck") ?: JSONObject()
    val on = locationOn && puck.optString("type") != "none"
    if (locationOn && !hasPermission() && !reportedPermission) {
      reportedPermission = true
      engine.report("showsUserLocation needs the location permission (ACCESS_FINE_LOCATION or ACCESS_COARSE_LOCATION); ask for it in the app")
    }
    if (hasPermission()) reportedPermission = false
    val bearing = when {
      trackingMode == UserTrackingMode.FOLLOWWITHHEADING -> "heading"
      else -> puck.optString("bearing", "heading")
    }
    val built = buildPuck(puck, bearing != "none")
    mapView.location.updateSettings {
      enabled = on
      if (built != null) locationPuck = built
      puckBearingEnabled = bearing != "none"
      puckBearing = if (bearing == "course") PuckBearing.COURSE else PuckBearing.HEADING
      showAccuracyRing = puck.optBoolean("showsAccuracyRing", false)
      MapboxColors.parse(puck.optString("accuracyRingColor"))?.let { accuracyRingColor = it }
      MapboxColors.parse(puck.optString("accuracyRingBorderColor"))?.let { accuracyRingBorderColor = it }
      val pulsing = puck.optJSONObject("pulsing")
      pulsingEnabled = pulsing?.optBoolean("enabled", true) ?: false
      MapboxColors.parse(pulsing?.optString("color"))?.let { pulsingColor = it }
      when (val radius = pulsing?.opt("radius")) {
        "accuracy" -> pulsingMaxRadius = LocationComponentConstants.PULSING_MAX_RADIUS_FOLLOW_ACCURACY
        is Number -> pulsingMaxRadius = (radius.toDouble() * density).toFloat()
        else -> {}
      }
    }
    updateLocationObserver()
  }

  /** The puck from `puck`: Mapbox's default 2D puck, custom 2D images, or a 3D model. */
  private fun buildPuck(puck: JSONObject, withBearing: Boolean): LocationPuck? {
    if (puck.optString("type") == "3d") {
      val uri = puck.optString("modelUri")
      if (uri.isEmpty()) {
        engine.report("puck: type '3d' needs modelUri")
        return null
      }
      val resolved = puckModelUri?.takeIf { it.startsWith("resolved:$uri|") }?.substringAfter('|')
      if (resolved == null) {
        engine.style.modelUri(uri) { file ->
          if (file == null) engine.report("puck: could not load $uri") else {
            puckModelUri = "resolved:$uri|$file"
            applyLocation()
          }
        }
        return null
      }
      fun floats(key: String, default: List<Float>): List<Float> =
        (puck.opt(key) as? JSONArray)?.takeIf { it.length() == 3 && it.opt(0) is Number }?.let { a -> List(3) { a.optDouble(it).toFloat() } } ?: default
      val scale = puck.opt("modelScale")
      val rotation = puck.opt("modelRotation")
      return LocationPuck3D(
        modelUri = resolved,
        modelScale = floats("modelScale", listOf(1f, 1f, 1f)),
        modelScaleExpression = (scale as? JSONArray)?.takeIf { it.opt(0) is String }?.toString(),
        modelRotation = floats("modelRotation", listOf(0f, 0f, 90f)),
        modelRotationExpression = (rotation as? JSONArray)?.takeIf { it.opt(0) is String }?.toString(),
        modelTranslation = floats("modelTranslation", listOf(0f, 0f, 0f)),
        modelOpacity = puck.optDouble("modelOpacity", 1.0).toFloat(),
        modelCastShadows = puck.optBoolean("modelCastShadows", true),
        modelReceiveShadows = puck.optBoolean("modelReceiveShadows", true),
        modelScaleMode = if (puck.optString("modelScaleMode") == "map") ModelScaleMode.MAP else ModelScaleMode.VIEWPORT,
        modelEmissiveStrength = puck.optDouble("modelEmissiveStrength", 1.0).toFloat(),
        modelElevationReference = if (puck.optString("modelElevationReference") == "sea") ModelElevationReference.SEA else ModelElevationReference.GROUND,
      )
    }
    val keys = listOf("topImage", "bearingImage", "shadowImage")
    val custom = keys.any { puck.optString(it).isNotEmpty() }
    val scale = puck.opt("scale")
    val scaleExpression = when (scale) {
      is Number -> JSONArray().put("literal").put(scale).toString()
      is JSONArray -> scale.toString()
      else -> null
    }
    val opacity = puck.optDouble("opacity", 1.0).toFloat()
    if (!custom) {
      return createDefault2DPuck(withBearing).also { p ->
        p.opacity = opacity
        if (scaleExpression != null) p.scaleExpression = scaleExpression
      }
    }
    val missing = keys.map { puck.optString(it) }.filter { it.isNotEmpty() && puckImages[it] == null }
    if (missing.isNotEmpty()) {
      missing.forEach { uri ->
        MarkerPhotos.load(engine.context, uri) { bitmap ->
          if (bitmap == null) engine.report("puck: could not load $uri") else {
            puckImages[uri] = bitmap
            applyLocation()
          }
        }
      }
      return null
    }
    fun holder(key: String) = puck.optString(key).takeIf { it.isNotEmpty() }?.let { puckImages[it] }?.let { ImageHolder.from(it) }
    return LocationPuck2D(
      topImage = holder("topImage"),
      bearingImage = holder("bearingImage"),
      shadowImage = holder("shadowImage"),
      scaleExpression = scaleExpression,
      opacity = opacity,
    )
  }

  // Location override (`setLocationOverride`): a provider we push values into.

  private class OverrideProvider : com.mapbox.maps.plugin.locationcomponent.LocationProvider {
    val consumers = mutableSetOf<com.mapbox.maps.plugin.locationcomponent.LocationConsumer>()
    var point: Point? = null
    var bearing: Double? = null
    var accuracy: Double? = null

    override fun registerLocationConsumer(locationConsumer: com.mapbox.maps.plugin.locationcomponent.LocationConsumer) {
      consumers.add(locationConsumer)
      push(locationConsumer)
    }

    override fun unRegisterLocationConsumer(locationConsumer: com.mapbox.maps.plugin.locationcomponent.LocationConsumer) {
      consumers.remove(locationConsumer)
    }

    fun push(consumer: com.mapbox.maps.plugin.locationcomponent.LocationConsumer) {
      point?.let { consumer.onLocationUpdated(it) }
      bearing?.let { consumer.onBearingUpdated(it) }
      accuracy?.let { consumer.onHorizontalAccuracyRadiusUpdated(it) }
    }

    fun pushAll() = consumers.toList().forEach { push(it) }
  }

  private var overrideProvider: OverrideProvider? = null
  private var deviceProvider: com.mapbox.maps.plugin.locationcomponent.LocationProvider? = null

  fun setLocationOverride(args: JSONObject) {
    val location = mapView.location
    val provider = overrideProvider ?: OverrideProvider().also {
      deviceProvider = location.getLocationProvider()
      overrideProvider = it
      location.setLocationProvider(it)
    }
    val point = Point.fromLngLat(args.optDouble("longitude"), args.optDouble("latitude"))
    val heading = if (args.has("heading")) args.optDouble("heading") else null
    val course = if (args.has("course")) args.optDouble("course") else null
    val useCourse = trackingMode != UserTrackingMode.FOLLOWWITHHEADING && options.optJSONObject("puck")?.optString("bearing") == "course"
    provider.point = point
    provider.bearing = (if (useCourse) course ?: heading else heading ?: course) ?: provider.bearing
    if (args.has("accuracy")) provider.accuracy = args.optDouble("accuracy")
    provider.pushAll()
    engine.listener?.onUserLocationChange(UserLocationEvent(point.latitude(), point.longitude(),
      args.optDouble("altitude", 0.0), args.optDouble("accuracy", -1.0), -1.0, heading ?: course ?: -1.0, args.optDouble("speed", -1.0)))
  }

  fun clearLocationOverride() {
    if (overrideProvider == null) return
    overrideProvider = null
    deviceProvider?.let { mapView.location.setLocationProvider(it) }
    deviceProvider = null
  }

  // Location updates for onUserLocationChange (the device provider Mapbox's puck uses).

  private var locationProvider: LocationProvider? = null
  private val locationObserver = LocationObserver { locations ->
    val l = locations.lastOrNull() ?: return@LocationObserver
    if (overrideProvider != null) return@LocationObserver
    engine.main.post {
      engine.listener?.onUserLocationChange(UserLocationEvent(
        l.latitude, l.longitude, l.altitude ?: 0.0, l.horizontalAccuracy ?: -1.0, l.verticalAccuracy ?: -1.0,
        l.bearing ?: -1.0, l.speed ?: -1.0))
    }
  }

  @SuppressLint("MissingPermission")
  private fun updateLocationObserver() {
    val want = locationOn && started && hasPermission()
    if (want && locationProvider == null) {
      val result = LocationServiceFactory.getOrCreate().getDeviceLocationProvider(null)
      val provider = result.value
      if (provider == null) {
        engine.report("location: ${result.error?.message ?: "no location provider"}")
        return
      }
      provider.addLocationObserver(locationObserver, Looper.getMainLooper())
      locationProvider = provider
    } else if (!want && locationProvider != null) {
      locationProvider?.removeLocationObserver(locationObserver)
      locationProvider = null
    }
  }

  fun start() {
    started = true
    updateLocationObserver()
  }

  fun stop() {
    started = false
    updateLocationObserver()
  }

  // User tracking (viewport plugin)

  private var statusObserver: ViewportStatusObserver? = null

  fun setUserTrackingMode(mode: UserTrackingMode) {
    if (mode == trackingMode) return
    trackingMode = mode
    applyLocation()
    updateButton()
    val viewport = mapView.viewport
    ensureStatusObserver()
    if (mode == UserTrackingMode.NONE) {
      if (viewport.status != ViewportStatus.Idle) viewport.idle()
      return
    }
    val cs = engine.map.cameraState
    val bearing = if (mode == UserTrackingMode.FOLLOWWITHHEADING) FollowPuckViewportStateBearing.SyncWithLocationPuck
    else FollowPuckViewportStateBearing.Constant(cs.bearing)
    val state = viewport.makeFollowPuckViewportState(FollowPuckViewportStateOptions.Builder()
      .bearing(bearing)
      .zoom(maxOf(cs.zoom, 15.0))
      .pitch(cs.pitch)
      .padding(engine.mapPadding)
      .build())
    viewport.transitionTo(state, viewport.makeDefaultViewportTransition(DefaultViewportTransitionOptions.Builder().maxDurationMs(1500).build())) {}
  }

  private fun ensureStatusObserver() {
    if (statusObserver != null) return
    val observer = ViewportStatusObserver { _, to, reason ->
      // A gesture ends following, like MapKit.
      if (to == ViewportStatus.Idle && reason == ViewportStatusChangeReason.USER_INTERACTION && trackingMode != UserTrackingMode.NONE) {
        trackingMode = UserTrackingMode.NONE
        applyLocation()
        updateButton()
        engine.listener?.onUserTrackingModeChange(UserTrackingMode.NONE)
      }
    }
    mapView.viewport.addStatusObserver(observer)
    statusObserver = observer
  }

  /** A camera call from the app ends user tracking. */
  fun endTrackingForCameraMove() {
    if (trackingMode == UserTrackingMode.NONE) return
    trackingMode = UserTrackingMode.NONE
    mapView.viewport.idle()
    applyLocation()
    updateButton()
    engine.listener?.onUserTrackingModeChange(UserTrackingMode.NONE)
  }

  /**
   * `setViewport` (providerCommand): follow the puck, frame coordinates, or
   * stop. Completes with true when the transition finished.
   */
  fun setViewport(args: JSONObject, completion: (Boolean) -> Unit) {
    val viewport = mapView.viewport
    ensureStatusObserver()
    val padding = MapboxJson.insets(args.optJSONObject("padding"), density)
    val duration = if (args.has("duration")) args.optLong("duration") else null
    val transition = when {
      duration == null -> viewport.defaultTransition
      duration <= 0 -> viewport.makeImmediateViewportTransition()
      else -> viewport.makeDefaultViewportTransition(DefaultViewportTransitionOptions.Builder().maxDurationMs(duration).build())
    }
    when (args.optString("state")) {
      "idle" -> {
        viewport.idle()
        completion(true)
      }
      "followPuck" -> {
        if (!locationOn) {
          showsUserLocation = true
          applyLocation()
        }
        val bearing = when (val b = args.opt("bearing")) {
          "heading" -> FollowPuckViewportStateBearing.SyncWithLocationPuck
          "course" -> {
            mapView.location.puckBearing = PuckBearing.COURSE
            FollowPuckViewportStateBearing.SyncWithLocationPuck
          }
          is Number -> FollowPuckViewportStateBearing.Constant(b.toDouble())
          else -> FollowPuckViewportStateBearing.Constant(engine.map.cameraState.bearing)
        }
        val builder = FollowPuckViewportStateOptions.Builder().bearing(bearing)
        if (args.has("zoom")) builder.zoom(args.optDouble("zoom"))
        if (args.has("pitch")) builder.pitch(args.optDouble("pitch"))
        padding?.let { builder.padding(it) }
        viewport.transitionTo(viewport.makeFollowPuckViewportState(builder.build()), transition) { completion(it) }
      }
      "overview" -> {
        val coordinates = args.optJSONArray("coordinates") ?: JSONArray()
        val points = (0 until coordinates.length()).mapNotNull { MapboxJson.point(coordinates.optJSONObject(it)) }
        if (points.isEmpty()) {
          completion(false)
          return
        }
        val geometry = if (points.size == 1) points[0] else LineString.fromLngLats(points)
        val builder = OverviewViewportStateOptions.Builder().geometry(geometry)
        padding?.let { builder.geometryPadding(it) }
        if (args.has("pitch")) builder.pitch(args.optDouble("pitch"))
        (args.opt("bearing") as? Number)?.let { builder.bearing(it.toDouble()) }
        if (args.has("zoom")) builder.maxZoom(args.optDouble("zoom"))
        viewport.transitionTo(viewport.makeOverviewViewportState(builder.build()), transition) { completion(it) }
      }
      else -> completion(false)
    }
  }

  // The tracking button (`showsUserTrackingButton`): none → follow → follow with heading.

  private var button: TrackingButton? = null

  fun attachButton(root: FrameLayout) {
    val size = (40 * density).toInt()
    val b = TrackingButton(engine.context)
    b.visibility = View.GONE
    b.setOnClickListener {
      val next = when (trackingMode) {
        UserTrackingMode.NONE -> UserTrackingMode.FOLLOW
        UserTrackingMode.FOLLOW -> UserTrackingMode.FOLLOWWITHHEADING
        UserTrackingMode.FOLLOWWITHHEADING -> UserTrackingMode.NONE
      }
      setUserTrackingMode(next)
      engine.listener?.onUserTrackingModeChange(next)
    }
    val params = FrameLayout.LayoutParams(size, size, Gravity.BOTTOM or Gravity.END)
    params.rightMargin = (12 * density).toInt()
    params.bottomMargin = (40 * density).toInt()
    root.addView(b, params)
    button = b
  }

  fun setShowsTrackingButton(shows: Boolean) {
    button?.visibility = if (shows) View.VISIBLE else View.GONE
  }

  private fun updateButton() {
    button?.mode = trackingMode
  }

  fun destroy() {
    statusObserver?.let { mapView.viewport.removeStatusObserver(it) }
    statusObserver = null
    locationProvider?.removeLocationObserver(locationObserver)
    locationProvider = null
    engine.main.removeCallbacks(hideScale)
  }

  /** A round button with a location arrow, filled while tracking. */
  private class TrackingButton(context: Context) : View(context) {
    var mode = UserTrackingMode.NONE
      set(value) {
        field = value
        invalidate()
      }
    private val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; setShadowLayer(4f, 0f, 1f, Color.argb(70, 0, 0, 0)) }
    private val arrow = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(10, 132, 255); strokeWidth = 3f; strokeJoin = Paint.Join.ROUND }

    init {
      setLayerType(LAYER_TYPE_SOFTWARE, null)
      contentDescription = "User tracking"
    }

    override fun onDraw(canvas: Canvas) {
      val w = width.toFloat()
      val h = height.toFloat()
      canvas.drawCircle(w / 2, h / 2, minOf(w, h) / 2 - 3, bg)
      val s = minOf(w, h) * 0.22f
      val path = Path().apply {
        moveTo(w / 2 + s, h / 2 - s)
        lineTo(w / 2 - s * 1.1f, h / 2 - s * 0.05f)
        lineTo(w / 2 - s * 0.05f, h / 2 + s * 0.05f)
        lineTo(w / 2 + s * 0.05f, h / 2 + s * 1.1f)
        close()
      }
      arrow.style = if (mode == UserTrackingMode.NONE) Paint.Style.STROKE else Paint.Style.FILL_AND_STROKE
      canvas.drawPath(path, arrow)
      if (mode == UserTrackingMode.FOLLOWWITHHEADING) canvas.drawCircle(w / 2, h / 2 - s * 1.5f, 2.5f, arrow)
    }
  }
}
