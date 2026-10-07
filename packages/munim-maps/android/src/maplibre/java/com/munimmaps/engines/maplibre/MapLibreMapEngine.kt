package com.munimmaps.engines.maplibre

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.PointF
import android.graphics.RectF
import android.location.Location
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Choreographer
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.widget.FrameLayout
import com.margelo.nitro.munimmaps.CameraKeyframe
import com.margelo.nitro.munimmaps.EdgeInsets
import com.margelo.nitro.munimmaps.FeatureVisibility
import com.margelo.nitro.munimmaps.MapAddress
import com.margelo.nitro.munimmaps.MapCamera
import com.margelo.nitro.munimmaps.MapCameraEasing
import com.margelo.nitro.munimmaps.MapColorScheme
import com.margelo.nitro.munimmaps.MapCoordinate
import com.margelo.nitro.munimmaps.MapElevation
import com.margelo.nitro.munimmaps.MapFeatureEvent
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
import com.margelo.nitro.munimmaps.UserLocationEvent
import com.margelo.nitro.munimmaps.UserTrackingMode
import com.munimmaps.engine.MapCameraSource
import com.munimmaps.engine.MapCameraState
import com.munimmaps.engine.MunimMapEngine
import com.munimmaps.engine.MunimMapEngineFactory
import com.munimmaps.engine.MunimMapEngineListener
import com.munimmaps.engine.MunimMapsConfiguration
import com.munimmaps.models.MunimModelLayer
import org.json.JSONArray
import org.json.JSONObject
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.geometry.LatLngBounds
import org.maplibre.android.location.LocationComponentActivationOptions
import org.maplibre.android.location.LocationComponentOptions
import org.maplibre.android.location.OnCameraTrackingChangedListener
import org.maplibre.android.location.engine.LocationEngine
import org.maplibre.android.location.engine.LocationEngineCallback
import org.maplibre.android.location.engine.LocationEngineDefault
import org.maplibre.android.location.engine.LocationEngineRequest
import org.maplibre.android.location.engine.LocationEngineResult
import org.maplibre.android.location.modes.CameraMode
import org.maplibre.android.location.modes.RenderMode
import org.maplibre.android.log.Logger
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapLibreMapOptions
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.module.http.HttpRequestUtil
import org.maplibre.android.snapshotter.MapSnapshotter
import org.maplibre.android.style.layers.ColorReliefLayer
import org.maplibre.android.style.layers.FillExtrusionLayer
import org.maplibre.android.style.layers.FillLayer
import org.maplibre.android.style.layers.HillshadeLayer
import org.maplibre.android.style.layers.Layer
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.layers.RasterLayer
import org.maplibre.android.style.layers.SymbolLayer
import org.maplibre.android.style.layers.TransitionOptions
import org.maplibre.android.style.light.Position
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.android.style.sources.RasterDemSource
import org.maplibre.android.style.sources.RasterSource
import org.maplibre.android.style.sources.TileSet
import org.maplibre.android.style.sources.VectorSource
import org.maplibre.android.style.expressions.Expression
import org.maplibre.geojson.Feature
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.tan

object MapLibreMapEngineFactory : MunimMapEngineFactory {
  override val isImplemented = true
  override fun create(context: Context): MunimMapEngine = MapLibreMapEngine(context)
}

/**
 * The MapLibre engine on Android: MapLibre Native's `MapView` with an
 * OpenFreeMap style by default (OpenStreetMap data, no key), munim-maps'
 * markers and shapes as style layers ([MapLibreFeatures]), the whole style
 * spec at runtime ([StyleSpec]), offline packs ([MapLibreOffline]) and
 * the Filament 3D layer over it, driven by MapLibre's camera.
 *
 * MapLibre-only options arrive as `providerOptions` (`maplibre={{…}}` in
 * JavaScript, `MapLibreMapOptions` in src/providers/maplibre.ts) and
 * commands through [providerCommand]; the full list is in docs/providers.md.
 */
class MapLibreMapEngine(private val context: Context) : MunimMapEngine, MapCameraSource {
  override val provider = MapProvider.MAPLIBRE
  override var listener: MunimMapEngineListener? = null

  private val density = context.resources.displayMetrics.density.toDouble()
  private val main = Handler(Looper.getMainLooper())
  private var mapView: MapView? = null
  private val root: FrameLayout
  override val modelLayer = MunimModelLayer(context)
  override val view: View get() = root
  private val features: MapLibreFeatures
  private val scaleBar = ScaleBarView(context)
  private val trackingButton = TrackingButton(context)

  private var map: MapLibreMap? = null
  private var style: Style? = null
  private var styleUrl = ""
  private var options = JSONObject()
  private var initialCamera: MapCamera? = null
  private var appliedInitialCamera = false
  private var destroyed = false
  private var started = false
  private var readySent = false

  // Props kept so they can be applied when the map or a new style arrives.
  private var mapStyle = MapStyle.STANDARD
  private var colorScheme = MapColorScheme.SYSTEM
  private var showsBuildings = true
  private var pointsOfInterest = "all"
  private var showsUserLocation = false
  private var trackingMode = UserTrackingMode.NONE
  private var compass = FeatureVisibility.ADAPTIVE
  private var scale = FeatureVisibility.HIDDEN
  private var showsTrackingButton = false
  private var gestures = booleanArrayOf(true, true, true, true)
  private var distanceRange = 0.0 to 0.0
  private var boundary: MapRegion? = null
  private var padding = EdgeInsets(0.0, 0.0, 0.0, 0.0)
  private var selectableFeatures = emptySet<String>()
  private var loadedStyleKey = ""
  private val eventSink: (String, String) -> Unit = { name, payload -> main.post { listener?.onProviderEvent(name, payload) } }

  init {
    MapLibre.getInstance(context.applicationContext)
    root = object : FrameLayout(context) {
      override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        start()
      }

      override fun onDetachedFromWindow() {
        stop()
        super.onDetachedFromWindow()
      }

      override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        if (features.onTouch(event)) return true
        return super.dispatchTouchEvent(event)
      }
    }
    features = MapLibreFeatures(context, root) { listener }
    root.addView(modelLayer.view, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    root.addView(scaleBar, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.TOP or Gravity.START).apply {
      leftMargin = (12 * density).toInt()
      topMargin = (12 * density).toInt()
    })
    scaleBar.visibility = View.GONE
    root.addView(trackingButton, FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM or Gravity.END).apply {
      rightMargin = (12 * density).toInt()
      bottomMargin = (40 * density).toInt()
    })
    trackingButton.visibility = View.GONE
    trackingButton.setOnClickListener {
      val next = when (trackingMode) {
        UserTrackingMode.NONE -> UserTrackingMode.FOLLOW
        UserTrackingMode.FOLLOW -> UserTrackingMode.FOLLOWWITHHEADING
        UserTrackingMode.FOLLOWWITHHEADING -> UserTrackingMode.NONE
      }
      if (!showsUserLocation) setShowsUserLocation(true)
      setUserTrackingMode(next)
      listener?.onUserTrackingModeChange(next)
    }
    modelLayer.attach(this)
    MapLibreOffline.sinks.add(eventSink)
  }

  /**
   * The MapView is made on the first props (or when shown), so options that
   * MapLibre only reads at creation (pixel ratio, local CJK font, load
   * colour) can come from `maplibre={{…}}`.
   */
  private fun ensureMapView(): MapView {
    mapView?.let { return it }
    val o = MapLibreMapOptions.createFromAttributes(context).textureMode(false)
    if (options.has("pixelRatio")) o.pixelRatio(options.optDouble("pixelRatio").toFloat())
    options.optString("localIdeographFontFamily").takeIf { it.isNotEmpty() }?.let { o.localIdeographFontFamily(it) }
    options.optString("foregroundLoadColor").takeIf { it.isNotEmpty() }?.let { o.foregroundLoadColor(MarkerBitmaps.color(it, Color.WHITE)) }
    val view = MapView(context, o)
    mapView = view
    root.addView(view, 0, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    view.onCreate(null)
    view.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
      applyInitialCameraIfReady()
      modelLayer.setNeedsRender()
    }
    view.addOnDidFailLoadingMapListener { message ->
      listener?.onError("MapLibre: the map failed to load: $message")
      event("mapLoadFailed", JSONObject().put("message", message))
    }
    view.addOnDidBecomeIdleListener { event("idle", JSONObject()) }
    view.addOnDidFinishRenderingMapListener { fully -> event("renderedMap", JSONObject().put("fullyRendered", fully)) }
    view.addOnSourceChangedListener { id -> if (!id.startsWith("munim-")) event("sourceChanged", JSONObject().put("id", id)) }
    view.addOnStyleImageMissingListener { id ->
      if (!features.imageMissing(id)) event("styleImageMissing", JSONObject().put("id", id))
    }
    view.addOnRenderErrorListener { event("renderError", JSONObject()) }
    view.getMapAsync { map -> mapReady(map) }
    if (started) {
      view.onStart()
      view.onResume()
    }
    return view
  }

  private fun event(name: String, payload: JSONObject) {
    listener?.onProviderEvent(name, payload.toString())
  }

  private fun start() {
    if (started || destroyed) return
    started = true
    val view = ensureMapView()
    view.onStart()
    view.onResume()
  }

  private fun stop() {
    if (!started || destroyed) return
    started = false
    mapView?.onPause()
    mapView?.onStop()
  }

  override fun destroy() {
    if (destroyed) return
    stopFlight()
    stopLocationUpdates()
    stop()
    destroyed = true
    MapLibreOffline.sinks.remove(eventSink)
    modelLayer.destroy()
    mapView?.onDestroy()
  }

  @SuppressLint("ClickableViewAccessibility")
  private fun mapReady(map: MapLibreMap) {
    if (destroyed) return
    this.map = map
    features.map = map
    map.setMaxPitchPreference(85.0)
    map.uiSettings.isAttributionEnabled = true
    map.uiSettings.isLogoEnabled = false
    map.addOnCameraMoveStartedListener { reason ->
      val name = when (reason) {
        MapLibreMap.OnCameraMoveStartedListener.REASON_API_GESTURE -> "gesture"
        MapLibreMap.OnCameraMoveStartedListener.REASON_DEVELOPER_ANIMATION -> "animation"
        else -> "api"
      }
      event("cameraMoveStarted", JSONObject().put("reason", name))
    }
    map.addOnCameraMoveListener {
      modelLayer.setNeedsRender()
      features.positionCallout()
      updateScaleBar()
      getCamera()?.let { listener?.onCameraMove(it) }
    }
    map.addOnCameraIdleListener {
      modelLayer.setNeedsRender()
      features.positionCallout()
      updateScaleBar()
      getCamera()?.let { listener?.onCameraChange(it) }
    }
    map.addOnMapClickListener { latLng ->
      val point = map.projection.toScreenLocation(latLng)
      if (modelLayer.handleTap(point.x, point.y)) return@addOnMapClickListener true
      if (features.handleTap(point)) return@addOnMapClickListener true
      if (features.handleOverlayTap(point, latLng)) return@addOnMapClickListener true
      if (mapFeatureTap(point)) return@addOnMapClickListener true
      listener?.onPress(MapPressEvent(latLng.latitude, latLng.longitude, point.x / density, point.y / density))
      false
    }
    map.addOnMapLongClickListener { latLng ->
      val point = map.projection.toScreenLocation(latLng)
      if (features.handleLongPress(point)) return@addOnMapLongClickListener true
      listener?.onLongPress(MapPressEvent(latLng.latitude, latLng.longitude, point.x / density, point.y / density))
      false
    }
    applyMapOptions()
    applyGestures()
    applyLimits()
    applyPadding()
    applyControls()
    loadStyle()
    applyInitialCameraIfReady()
  }

  // MARK: Style

  private val presets = mapOf(
    "liberty" to "https://tiles.openfreemap.org/styles/liberty",
    "bright" to "https://tiles.openfreemap.org/styles/bright",
    "positron" to "https://tiles.openfreemap.org/styles/positron",
    "dark" to "https://tiles.openfreemap.org/styles/dark",
    "fiord" to "https://tiles.openfreemap.org/styles/fiord",
    "demotiles" to "https://demotiles.maplibre.org/style.json",
    "maptiler-streets" to "https://api.maptiler.com/maps/streets-v2/style.json?key={key}",
    "maptiler-outdoor" to "https://api.maptiler.com/maps/outdoor-v2/style.json?key={key}",
    "maptiler-satellite" to "https://api.maptiler.com/maps/satellite/style.json?key={key}",
    "maptiler-hybrid" to "https://api.maptiler.com/maps/hybrid/style.json?key={key}",
    "maptiler-dataviz" to "https://api.maptiler.com/maps/dataviz/style.json?key={key}",
    "stadia-alidade-smooth" to "https://tiles.stadiamaps.com/styles/alidade_smooth.json?api_key={key}",
    "stadia-alidade-smooth-dark" to "https://tiles.stadiamaps.com/styles/alidade_smooth_dark.json?api_key={key}",
    "stadia-outdoors" to "https://tiles.stadiamaps.com/styles/outdoors.json?api_key={key}",
    "stadia-osm-bright" to "https://tiles.stadiamaps.com/styles/osm_bright.json?api_key={key}",
  )

  private fun preset(name: String): String? {
    if (name.isEmpty()) return null
    val url = presets[name] ?: return name.takeIf { it.contains("://") }
    if (url.contains("{key}")) {
      val key = options.optString("apiKey")
      if (key.isEmpty()) {
        listener?.onError("MapLibre: the '$name' style needs maplibre.apiKey")
        return null
      }
      return url.replace("{key}", URLEncoder.encode(key, "UTF-8"))
    }
    return url
  }

  private val isDark: Boolean
    get() = when (colorScheme) {
      MapColorScheme.DARK -> true
      MapColorScheme.LIGHT -> false
      MapColorScheme.SYSTEM -> (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
    }

  /** The style to show: JSON, URL, preset, dark, muted. Returns (key, builder). */
  private fun resolveStyle(): Pair<String, Style.Builder> {
    val json = options.opt("styleJson")
    if (json != null && json != JSONObject.NULL) {
      val text = if (json is JSONObject) json.toString() else json.toString()
      return "json:${text.hashCode()}" to Style.Builder().fromJson(text)
    }
    val explicit = styleUrl.ifEmpty { preset(options.optString("style")) ?: "" }
    // Dark follows the system unless the app picked a style without a dark one.
    val wantsDark = isDark && styleUrl.isEmpty() && (options.optString("style").isEmpty() || options.optString("darkStyle").isNotEmpty())
    val url = when {
      wantsDark -> preset(options.optString("darkStyle").ifEmpty { "dark" }) ?: explicit
      explicit.isNotEmpty() -> explicit
      mapStyle == MapStyle.MUTED -> presets["positron"]!!
      else -> MunimMapsConfiguration.maplibreStyleUrl
    }
    return url to Style.Builder().fromUri(url)
  }

  private fun loadStyle(force: Boolean = false) {
    val map = map ?: return
    val (key, builder) = resolveStyle()
    if (!force && key == loadedStyleKey && style != null) return
    loadedStyleKey = key
    style = null
    features.detachStyle()
    map.setStyle(builder) { loaded ->
      if (destroyed) return@setStyle
      style = loaded
      styleLoaded(loaded)
    }
  }

  private fun styleLoaded(style: Style) {
    originalPoiFilters.clear()
    userSources.clear()
    userLayers.clear()
    applyImagery(style)
    applyRuntimeStyle(style)
    applyBuildings()
    applyPointsOfInterest()
    applyLabelLanguage(style)
    features.restore(style)
    if (showsUserLocation) activateLocation()
    modelLayer.setNeedsRender()
    updateScaleBar()
    event("styleLoaded", JSONObject().put("style", loadedStyleKey))
    if (!readySent) {
      readySent = true
      listener?.onMapReady()
    }
  }

  /** `mapStyle` imagery / hybrid: satellite tiles from `maplibre.satelliteTilesUrl`. */
  private fun applyImagery(style: Style) {
    if (mapStyle != MapStyle.IMAGERY && mapStyle != MapStyle.HYBRID) return
    val tiles = options.optString("satelliteTilesUrl")
    if (tiles.isEmpty()) {
      listener?.onError("MapLibre: mapStyle '${mapStyle.name.lowercase()}' needs maplibre.satelliteTilesUrl (there is no keyless satellite imagery)")
      return
    }
    style.addSource(RasterSource("munim-imagery", TileSet("2.2.0", tiles), 256))
    val layer = RasterLayer("munim-imagery", "munim-imagery")
    if (mapStyle == MapStyle.IMAGERY) {
      style.layers.forEach { it.setProperties(PropertyFactory.visibility("none")) }
      style.addLayer(layer)
    } else {
      // Over the land and water fills, under roads and labels.
      val firstLine = style.layers.firstOrNull { it is LineLayer || it is SymbolLayer }?.id
      if (firstLine != null) style.addLayerBelow(layer, firstLine) else style.addLayer(layer)
      style.layers.filter { it is FillLayer || it is FillExtrusionLayer }.forEach { it.setProperties(PropertyFactory.visibility("none")) }
    }
  }

  private val userSources = ArrayList<String>()
  private val userLayers = ArrayList<String>()
  private var appliedRuntimeKey = ""

  /** `maplibre.sources`, `layers`, `images`, `light`, `transition`, `hillshade`, `colorRelief`. */
  private fun applyRuntimeStyle(style: Style) {
    appliedRuntimeKey = runtimeKey()
    userLayers.forEach { if (style.getLayer(it) != null) style.removeLayer(it) }
    userSources.forEach { if (style.getSource(it) != null) style.removeSource(it) }
    userLayers.clear()
    userSources.clear()
    options.optJSONObject("transition")?.let {
      style.transition = TransitionOptions(it.optLong("duration", 300), it.optLong("delay", 0))
    }
    options.optJSONObject("light")?.let { light -> applyLight(style, light) }
    options.optJSONObject("images")?.let { images ->
      images.keys().forEach { name ->
        val value = images.opt(name)
        val uri = if (value is JSONObject) value.optString("uri") else value.toString()
        val sdf = (value as? JSONObject)?.optBoolean("sdf") ?: false
        loadStyleImage(name, uri, sdf)
      }
    }
    val sources = options.optJSONObject("sources")
    sources?.keys()?.forEach { id ->
      try {
        if (style.getSource(id) != null) style.removeSource(id)
        style.addSource(StyleSpec.source(id, sources.getJSONObject(id)))
        userSources.add(id)
      } catch (e: Exception) {
        listener?.onError("MapLibre: source '$id': ${e.message}")
      }
    }
    val roadsBelow = firstRoadLayer(style)
    hillshade(style, roadsBelow)
    val layers = options.optJSONArray("layers")
    for (i in 0 until (layers?.length() ?: 0)) {
      val json = layers!!.optJSONObject(i) ?: continue
      try {
        val layer = StyleSpec.layer(json)
        if (style.getLayer(layer.id) != null) style.removeLayer(layer.id)
        StyleSpec.add(style, layer, json.optString("beforeId"), MapLibreFeatures.SLOT_USER)
        userLayers.add(layer.id)
      } catch (e: Exception) {
        listener?.onError("MapLibre: layer '${json.optString("id")}': ${e.message}")
      }
    }
  }

  private fun runtimeKey(): String = listOf("sources", "layers", "images", "light", "transition", "hillshade", "colorRelief")
    .joinToString("|") { options.opt(it)?.toString() ?: "" }

  private fun applyLight(style: Style, light: JSONObject) {
    val l = style.light ?: return
    light.optString("anchor").takeIf { it.isNotEmpty() }?.let { l.anchor = it }
    light.optJSONArray("position")?.let { p ->
      if (p.length() == 3) l.position = Position(p.optDouble(0).toFloat(), p.optDouble(1).toFloat(), p.optDouble(2).toFloat())
    }
    light.optString("color").takeIf { it.isNotEmpty() }?.let { l.setColor(MarkerBitmaps.css(it, Color.WHITE)) }
    if (light.has("intensity")) l.intensity = light.optDouble("intensity").toFloat()
  }

  private fun firstRoadLayer(style: Style): String? {
    val roads = Regex("road|highway|street|transport|tunnel|bridge|aeroway|rail", RegexOption.IGNORE_CASE)
    return style.layers.firstOrNull { (it is LineLayer || it is SymbolLayer) && (roads.containsMatchIn(it.id) || it is SymbolLayer) }?.id
  }

  /** Public elevation tiles: AWS Terrain Tiles (Terrarium encoding), keyless. */
  private val terrariumTiles = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"

  private fun demSource(style: Style, id: String, json: JSONObject?) {
    if (style.getSource(id) != null) return
    val tiles = json?.optJSONArray("tiles")?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: listOf(terrariumTiles)
    val set = TileSet("2.2.0", *tiles.toTypedArray())
    set.encoding = json?.optString("encoding")?.takeIf { it.isNotEmpty() } ?: "terrarium"
    set.maxZoom = 15f
    style.addSource(RasterDemSource(id, set, 256))
    userSources.add(id)
  }

  private fun hillshade(style: Style, below: String?) {
    val shade = options.opt("hillshade")
    if (shade == true || shade is JSONObject) {
      val json = shade as? JSONObject
      demSource(style, "munim-dem", json)
      val layer = HillshadeLayer("munim-hillshade", "munim-dem")
      val props = JSONObject()
      json?.let { j ->
        if (j.has("exaggeration")) props.put("hillshade-exaggeration", j.optDouble("exaggeration"))
        j.optString("shadowColor").takeIf { it.isNotEmpty() }?.let { props.put("hillshade-shadow-color", it) }
        j.optString("highlightColor").takeIf { it.isNotEmpty() }?.let { props.put("hillshade-highlight-color", it) }
        j.optString("accentColor").takeIf { it.isNotEmpty() }?.let { props.put("hillshade-accent-color", it) }
        if (j.has("illuminationDirection")) props.put("hillshade-illumination-direction", j.optDouble("illuminationDirection"))
      }
      if (props.length() > 0) StyleSpec.setProperties(layer, props, paint = true)
      StyleSpec.add(style, layer, json?.optString("beforeId"), below ?: MapLibreFeatures.SLOT_USER)
      userLayers.add(layer.id)
    }
    val relief = options.opt("colorRelief")
    if (relief == true || relief is JSONObject) {
      val json = relief as? JSONObject
      demSource(style, "munim-dem-relief", json)
      val layer = ColorReliefLayer("munim-color-relief", "munim-dem-relief")
      val stops = json?.optJSONArray("stops") ?: JSONArray(listOf(0, "#2f6b3a", 500, "#9cba6a", 1500, "#e2c98f", 2500, "#a87c56", 4000, "#ffffff"))
      val expression = JSONArray().put("interpolate").put(JSONArray().put("linear")).put(JSONArray().put("elevation"))
      for (i in 0 until stops.length()) expression.put(stops.get(i))
      StyleSpec.setProperties(layer, JSONObject()
        .put("color-relief-color", expression)
        .put("color-relief-opacity", json?.optDouble("opacity", 0.6) ?: 0.6), paint = true)
      StyleSpec.add(style, layer, json?.optString("beforeId"), below ?: MapLibreFeatures.SLOT_USER)
      userLayers.add(layer.id)
    }
  }

  private fun loadStyleImage(name: String, uri: String, sdf: Boolean) {
    com.munimmaps.models.ModelAssets.load(context, uri) { result ->
      result.onSuccess { bytes ->
        val bitmap = android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        main.post { if (bitmap != null) style?.addImage(name, bitmap, sdf) }
      }.onFailure { e -> main.post { listener?.onError("MapLibre: image '$name': ${e.message}") } }
    }
  }

  private fun layersOfSourceLayer(style: Style, name: String): List<Layer> = style.layers.filter { layer ->
    when (layer) {
      is FillExtrusionLayer -> layer.sourceLayer == name
      is FillLayer -> layer.sourceLayer == name
      is SymbolLayer -> layer.sourceLayer == name
      is LineLayer -> layer.sourceLayer == name
      else -> false
    }
  }

  private fun applyBuildings() {
    val style = style ?: return
    for (layer in layersOfSourceLayer(style, "building")) {
      layer.setProperties(PropertyFactory.visibility(if (showsBuildings) "visible" else "none"))
    }
  }

  private val originalPoiFilters = HashMap<String, Expression?>()

  private fun applyPointsOfInterest() {
    val style = style ?: return
    val filter = pointsOfInterest.trim()
    for (layer in layersOfSourceLayer(style, "poi")) {
      val symbol = layer as? SymbolLayer ?: continue
      if (!originalPoiFilters.containsKey(symbol.id)) originalPoiFilters[symbol.id] = symbol.filter
      val original = originalPoiFilters[symbol.id]
      when (filter) {
        "", "all" -> {
          symbol.setProperties(PropertyFactory.visibility("visible"))
          original?.let { symbol.setFilter(it) }
        }
        "none" -> symbol.setProperties(PropertyFactory.visibility("none"))
        else -> {
          val classes = filter.split(",").map { it.trim().removePrefix("MKPOICategory").replaceFirstChar { c -> c.lowercase() } }
            .filter { it.isNotEmpty() }
          val wanted = StyleSpec.expression(JSONArray().put("match").put(JSONArray().put("get").put("class"))
            .put(JSONArray(classes)).put(true).put(false))!!
          symbol.setProperties(PropertyFactory.visibility("visible"))
          symbol.setFilter(if (original != null) Expression.all(original, wanted) else wanted)
        }
      }
    }
  }

  private fun applyLabelLanguage(style: Style) {
    val language = options.optString("labelLanguage").trim()
    if (language.isEmpty()) return
    val localized = Expression.coalesce(Expression.get("name:$language"), Expression.get("name_int"), Expression.get("name"))
    for (layer in style.layers) {
      val symbol = layer as? SymbolLayer ?: continue
      if (symbol.id.startsWith("munim-")) continue
      val field = symbol.textField
      val text = (field.expression ?: field.value)?.toString() ?: continue
      if (!text.contains("name")) continue
      symbol.setProperties(PropertyFactory.textField(localized))
    }
  }

  // MARK: Props

  override fun setStyleUrl(url: String) {
    if (url == styleUrl) return
    styleUrl = url
    loadStyle()
  }

  override fun setProviderOptions(options: JSONObject) {
    val previous = this.options
    this.options = options
    ensureMapView()
    if (options.optString("projection") == "globe") {
      listener?.onError("MapLibre: globe projection is not in MapLibre Native (only MapLibre GL JS); the map stays flat")
    }
    applyGlobalOptions(previous)
    applyMapOptions()
    applyGestures()
    applyLimits()
    applyControls()
    val styleKeys = listOf("styleJson", "style", "darkStyle", "apiKey", "satelliteTilesUrl")
    val styleChanged = styleKeys.any { previous.opt(it)?.toString() != options.opt(it)?.toString() }
    if (styleChanged) {
      loadStyle(force = previous.opt("satelliteTilesUrl")?.toString() != options.opt("satelliteTilesUrl")?.toString())
    } else {
      style?.let { s ->
        if (runtimeKey() != appliedRuntimeKey) applyRuntimeStyle(s)
        if (previous.optString("labelLanguage") != options.optString("labelLanguage")) loadStyle(force = true)
      }
    }
    if (showsUserLocation && previous.optJSONObject("location")?.toString() != options.optJSONObject("location")?.toString()) activateLocation()
  }

  /** Process-wide settings: HTTP headers, log level. */
  private fun applyGlobalOptions(previous: JSONObject) {
    val headers = options.optJSONObject("httpHeaders")
    if (headers?.toString() != previous.optJSONObject("httpHeaders")?.toString()) {
      val builder = okhttp3.OkHttpClient.Builder()
      if (headers != null && headers.length() > 0) {
        builder.addInterceptor { chain ->
          val request = chain.request().newBuilder()
          headers.keys().forEach { request.header(it, headers.optString(it)) }
          chain.proceed(request.build())
        }
      }
      HttpRequestUtil.setOkHttpClient(builder.build())
    }
    when (options.optString("logLevel")) {
      "none" -> Logger.setVerbosity(Logger.NONE)
      "error" -> Logger.setVerbosity(Logger.ERROR)
      "warning" -> Logger.setVerbosity(Logger.WARN)
      "info" -> Logger.setVerbosity(Logger.INFO)
      "debug" -> Logger.setVerbosity(Logger.DEBUG)
      "verbose" -> Logger.setVerbosity(Logger.VERBOSE)
    }
  }

  /** `maplibre.rendering`, `camera`: everything set on the map object. */
  private fun applyMapOptions() {
    val map = map ?: return
    val rendering = options.optJSONObject("rendering") ?: JSONObject()
    if (rendering.has("maxFps")) mapView?.setMaximumFps(rendering.optInt("maxFps"))
    if (rendering.has("prefetchTiles")) map.prefetchesTiles = rendering.optBoolean("prefetchTiles")
    if (rendering.has("prefetchZoomDelta")) map.prefetchZoomDelta = rendering.optInt("prefetchZoomDelta")
    if (rendering.has("tileCache")) map.tileCacheEnabled = rendering.optBoolean("tileCache")
    if (rendering.has("tileLodScale")) map.tileLodScale = rendering.optDouble("tileLodScale")
    rendering.optJSONObject("frustumOffset")?.let { f ->
      map.setFrustumOffset(RectF((f.optDouble("left") * density).toFloat(), (f.optDouble("top") * density).toFloat(),
        (f.optDouble("right") * density).toFloat(), (f.optDouble("bottom") * density).toFloat()))
    }
    map.isDebugActive = (rendering.optJSONArray("debug")?.length() ?: 0) > 0
  }

  override fun setInitialCamera(camera: MapCamera) {
    initialCamera = camera
    applyInitialCameraIfReady()
  }

  private fun applyInitialCameraIfReady() {
    if (appliedInitialCamera) return
    val camera = initialCamera ?: return
    val map = map ?: return
    if ((mapView?.height ?: 0) <= 0) return
    appliedInitialCamera = true
    map.moveCamera(CameraUpdateFactory.newCameraPosition(position(camera)))
  }

  override fun setMapStyle(style: MapStyle) {
    if (style == mapStyle) return
    mapStyle = style
    loadStyle(force = true)
  }

  override fun setElevation(elevation: MapElevation) {
    // MapLibre Native has no 3D terrain; `maplibre.hillshade` shades relief.
  }

  override fun setGlobe(globe: Boolean) {
    if (globe) listener?.onError("MapLibre: globe projection is not in MapLibre Native (only MapLibre GL JS); the map stays flat")
  }

  override fun setColorScheme(scheme: MapColorScheme) {
    if (scheme == colorScheme) return
    colorScheme = scheme
    loadStyle()
  }

  override fun setShowsBuildings(shows: Boolean) {
    showsBuildings = shows
    applyBuildings()
  }

  override fun setShowsTraffic(shows: Boolean) {
    if (shows) listener?.onError("MapLibre: there is no traffic data in OpenStreetMap; showsTraffic needs a traffic tile source (maplibre.sources)")
  }

  override fun setPointsOfInterest(filter: String) {
    pointsOfInterest = filter
    applyPointsOfInterest()
  }

  override fun setSelectableMapFeatures(features: String) {
    selectableFeatures = features.split(",").map { it.trim() }.filter { it.isNotEmpty() }.toSet()
  }

  /** A tap on a place of the base map (OpenMapTiles layers). */
  private fun mapFeatureTap(point: PointF): Boolean {
    if (selectableFeatures.isEmpty()) return false
    val map = map ?: return false
    val style = style ?: return false
    val kinds = mapOf(
      "poi" to "pointOfInterest", "place" to "territory", "water_name" to "physicalFeature",
      "mountain_peak" to "physicalFeature", "park" to "physicalFeature",
    )
    val wanted = kinds.filterValues {
      (it == "pointOfInterest" && "pointsOfInterest" in selectableFeatures) ||
        (it == "territory" && "territories" in selectableFeatures) ||
        (it == "physicalFeature" && "physicalFeatures" in selectableFeatures)
    }
    val layerIds = style.layers.filter { l -> (l as? SymbolLayer)?.sourceLayer in wanted.keys }.map { it.id }
    if (layerIds.isEmpty()) return false
    val box = RectF(point.x - 10 * density.toFloat(), point.y - 10 * density.toFloat(), point.x + 10 * density.toFloat(), point.y + 10 * density.toFloat())
    val hit = map.queryRenderedFeatures(box, *layerIds.toTypedArray()).firstOrNull() ?: return false
    val layerSource = (style.getLayer(layerIds.firstOrNull { id ->
      map.queryRenderedFeatures(box, id).any { it.id() == hit.id() }
    } ?: layerIds.first()) as? SymbolLayer)?.sourceLayer ?: "poi"
    val geometry = hit.geometry() as? org.maplibre.geojson.Point
    val latLng = geometry?.let { LatLng(it.latitude(), it.longitude()) } ?: map.projection.fromScreenLocation(point)
    val title = hit.getStringProperty("name") ?: hit.getStringProperty("name_en") ?: ""
    listener?.onMapFeaturePress(MapFeatureEvent(title, latLng.latitude, latLng.longitude, kinds[layerSource] ?: "pointOfInterest",
      hit.getStringProperty("class") ?: "", hit.id() ?: hit.toJson()))
    return true
  }

  // MARK: 2D content

  override fun setMarkers(markers: Array<NativeMarker>) = features.setMarkers(markers)
  override fun setViewMarker(marker: NativeMarker, image: android.graphics.Bitmap?) = features.setViewMarker(marker, image)
  override fun setViewMarkerImage(image: android.graphics.Bitmap?, id: String) = features.setViewMarkerImage(image, id)
  override fun removeViewMarker(id: String) = features.removeViewMarker(id)
  override fun setPolylines(polylines: Array<NativePolyline>) = features.setShapes(polylines = polylines)
  override fun setPolygons(polygons: Array<NativePolygon>) = features.setShapes(polygons = polygons)
  override fun setCircles(circles: Array<NativeCircle>) = features.setShapes(circles = circles)
  override fun setTileOverlays(overlays: Array<NativeTileOverlay>) = features.setTileOverlays(overlays)
  override fun setClusterStyles(styles: Array<NativeClusterStyle>) = features.setClusterStyles(styles)
  override fun setOverlayPressEnabled(enabled: Boolean) {
    features.overlayPressEnabled = enabled
  }

  override fun selectMarker(id: String) = features.select(id)
  override fun deselectMarker(id: String) = features.deselect(id)

  override fun overlayAtPoint(point: MapPoint): String =
    features.overlayAt(PointF((point.x * density).toFloat(), (point.y * density).toFloat()))?.first ?: ""

  // MARK: Controls

  override fun setCompassVisibility(visibility: FeatureVisibility) {
    compass = visibility
    applyControls()
  }

  override fun setScaleVisibility(visibility: FeatureVisibility) {
    scale = visibility
    applyControls()
  }

  override fun setShowsUserTrackingButton(shows: Boolean) {
    showsTrackingButton = shows
    applyControls()
  }

  private fun gravity(position: String, fallback: Int): Int = when (position) {
    "topLeft" -> Gravity.TOP or Gravity.START
    "topRight" -> Gravity.TOP or Gravity.END
    "bottomLeft" -> Gravity.BOTTOM or Gravity.START
    "bottomRight" -> Gravity.BOTTOM or Gravity.END
    else -> fallback
  }

  private fun margins(o: JSONObject?, gravity: Int): IntArray {
    val m = o?.optJSONObject("margin")
    val x = ((m?.optDouble("x", 8.0) ?: 8.0) * density).toInt()
    val y = ((m?.optDouble("y", 8.0) ?: 8.0) * density).toInt()
    val left = if (gravity and Gravity.END == Gravity.END) 0 else x
    val right = if (gravity and Gravity.END == Gravity.END) x else 0
    val top = if (gravity and Gravity.BOTTOM == Gravity.BOTTOM) 0 else y
    val bottom = if (gravity and Gravity.BOTTOM == Gravity.BOTTOM) y else 0
    return intArrayOf(left, top, right, bottom)
  }

  private fun applyControls() {
    val ornaments = options.optJSONObject("ornaments")
    map?.uiSettings?.let { ui ->
      val c = ornaments?.optJSONObject("compass")
      ui.isCompassEnabled = (c?.optBoolean("visible", compass != FeatureVisibility.HIDDEN) ?: (compass != FeatureVisibility.HIDDEN))
      ui.setCompassFadeFacingNorth(compass == FeatureVisibility.ADAPTIVE)
      if (c != null) {
        val g = gravity(c.optString("position"), Gravity.TOP or Gravity.END)
        ui.compassGravity = g
        val m = margins(c, g)
        ui.setCompassMargins(m[0], m[1], m[2], m[3])
      }
      val logo = ornaments?.optJSONObject("logo")
      ui.isLogoEnabled = logo?.optBoolean("visible", false) ?: false
      if (logo != null) {
        val g = gravity(logo.optString("position"), Gravity.BOTTOM or Gravity.START)
        ui.logoGravity = g
        val m = margins(logo, g)
        ui.setLogoMargins(m[0], m[1], m[2], m[3])
      }
      val attribution = ornaments?.optJSONObject("attribution")
      ui.isAttributionEnabled = attribution?.optBoolean("visible", true) ?: true
      if (attribution != null) {
        val g = gravity(attribution.optString("position"), Gravity.BOTTOM or Gravity.START)
        ui.attributionGravity = g
        val m = margins(attribution, g)
        ui.setAttributionMargins(m[0], m[1], m[2], m[3])
      }
    }
    val bar = ornaments?.optJSONObject("scaleBar")
    scaleBar.metric = bar?.optBoolean("metric", true) ?: true
    val showsScale = bar?.optBoolean("visible", scale != FeatureVisibility.HIDDEN) ?: (scale != FeatureVisibility.HIDDEN)
    scaleBar.visibility = if (showsScale) View.VISIBLE else View.GONE
    (scaleBar.layoutParams as? FrameLayout.LayoutParams)?.let { lp ->
      val g = gravity(bar?.optString("position") ?: "", Gravity.TOP or Gravity.START)
      val m = margins(bar, g)
      lp.gravity = g
      lp.setMargins(max(m[0], (12 * density).toInt()), max(m[1], (12 * density).toInt()), m[2], m[3])
      scaleBar.layoutParams = lp
    }
    trackingButton.visibility = if (showsTrackingButton) View.VISIBLE else View.GONE
    updateScaleBar()
  }

  private fun updateScaleBar() {
    if (scaleBar.visibility != View.VISIBLE) return
    val map = map ?: return
    val target = map.cameraPosition.target ?: return
    scaleBar.metersPerPixel = map.projection.getMetersPerPixelAtLatitude(target.latitude)
  }

  // MARK: Gestures and limits

  override fun setGestures(zoom: Boolean, scroll: Boolean, rotate: Boolean, pitch: Boolean) {
    gestures = booleanArrayOf(zoom, scroll, rotate, pitch)
    applyGestures()
  }

  private fun applyGestures() {
    val ui = map?.uiSettings ?: return
    ui.isZoomGesturesEnabled = gestures[0]
    ui.isScrollGesturesEnabled = gestures[1]
    ui.isRotateGesturesEnabled = gestures[2]
    ui.isTiltGesturesEnabled = gestures[3]
    val g = options.optJSONObject("gestures") ?: return
    if (g.has("doubleTapZoom")) ui.isDoubleTapGesturesEnabled = g.optBoolean("doubleTapZoom")
    if (g.has("quickZoom")) ui.isQuickZoomGesturesEnabled = g.optBoolean("quickZoom")
    if (g.has("flingVelocityAnimation")) ui.isFlingVelocityAnimationEnabled = g.optBoolean("flingVelocityAnimation")
    if (g.has("scaleVelocityAnimation")) ui.isScaleVelocityAnimationEnabled = g.optBoolean("scaleVelocityAnimation")
    if (g.has("rotateVelocityAnimation")) ui.isRotateVelocityAnimationEnabled = g.optBoolean("rotateVelocityAnimation")
    if (g.has("horizontalScroll")) ui.isHorizontalScrollGesturesEnabled = g.optBoolean("horizontalScroll")
    if (g.has("disableRotateWhenScaling")) ui.isDisableRotateWhenScaling = g.optBoolean("disableRotateWhenScaling")
    if (g.optBoolean("anchorToCenter", false)) ui.focalPoint = PointF(root.width / 2f, root.height / 2f) else if (g.has("anchorToCenter")) ui.focalPoint = null
  }

  override fun setCameraDistanceRange(min: Double, max: Double) {
    distanceRange = min to max
    applyLimits()
  }

  override fun setCameraBoundary(region: MapRegion?) {
    boundary = region
    applyLimits()
  }

  private fun applyLimits() {
    val map = map ?: return
    val c = options.optJSONObject("camera") ?: JSONObject()
    val latitude = map.cameraPosition.target?.latitude ?: 0.0
    val fov = fieldOfView(map.cameraPosition)
    var minZoom = if (c.has("minZoom")) c.optDouble("minZoom") else 0.0
    var maxZoom = if (c.has("maxZoom")) c.optDouble("maxZoom") else 25.5
    // Farther away is a lower zoom.
    if (distanceRange.second > 0) minZoom = max(minZoom, zoom(distanceRange.second, latitude, fov))
    if (distanceRange.first > 0) maxZoom = min(maxZoom, zoom(distanceRange.first, latitude, fov))
    map.setMinZoomPreference(minZoom)
    map.setMaxZoomPreference(maxZoom)
    map.setMinPitchPreference(if (c.has("minPitch")) c.optDouble("minPitch") else 0.0)
    map.setMaxPitchPreference(if (c.has("maxPitch")) c.optDouble("maxPitch") else 85.0)
    val region = boundary
    map.setLatLngBoundsForCameraTarget(region?.let {
      LatLngBounds.Builder()
        .include(LatLng(it.latitude - it.latitudeDelta / 2, it.longitude - it.longitudeDelta / 2))
        .include(LatLng(it.latitude + it.latitudeDelta / 2, it.longitude + it.longitudeDelta / 2))
        .build()
    })
  }

  override fun setMapPadding(padding: EdgeInsets) {
    this.padding = padding
    applyPadding()
  }

  private fun applyPadding() {
    val map = map ?: return
    map.setPadding((padding.left * density).toInt(), (padding.top * density).toInt(), (padding.right * density).toInt(), (padding.bottom * density).toInt())
    modelLayer.setNeedsRender()
  }

  // MARK: User location

  private var locationEngine: LocationEngine? = null
  private val locationCallback = object : LocationEngineCallback<LocationEngineResult> {
    override fun onSuccess(result: LocationEngineResult?) {
      val location = result?.lastLocation ?: return
      main.post { reportLocation(location) }
    }

    override fun onFailure(exception: Exception) {
      main.post { listener?.onError("MapLibre: location: ${exception.message}") }
    }
  }

  private fun reportLocation(l: Location) {
    listener?.onUserLocationChange(UserLocationEvent(
      l.latitude, l.longitude, if (l.hasAltitude()) l.altitude else 0.0, if (l.hasAccuracy()) l.accuracy.toDouble() else -1.0,
      if (Build.VERSION.SDK_INT >= 26 && l.hasVerticalAccuracy()) l.verticalAccuracyMeters.toDouble() else -1.0,
      if (l.hasBearing()) l.bearing.toDouble() else -1.0, if (l.hasSpeed()) l.speed.toDouble() else -1.0))
  }

  private fun hasLocationPermission(): Boolean =
    context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
      context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

  override fun setShowsUserLocation(shows: Boolean) {
    showsUserLocation = shows
    if (shows) activateLocation() else {
      stopLocationUpdates()
      try {
        map?.locationComponent?.takeIf { it.isLocationComponentActivated }?.isLocationComponentEnabled = false
      } catch (_: Exception) {}
    }
  }

  @SuppressLint("MissingPermission")
  private fun activateLocation() {
    val map = map ?: return
    val style = style ?: return
    if (!hasLocationPermission()) {
      listener?.onError("MapLibre: showsUserLocation needs the location permission (ACCESS_FINE_LOCATION); ask for it first")
      return
    }
    val o = options.optJSONObject("location") ?: JSONObject()
    val builder = LocationComponentOptions.builder(context)
      .pulseEnabled(o.optBoolean("pulse", false))
      .layerBelow(MapLibreFeatures.SLOT_MARKERS)
    o.optString("puckColor").takeIf { it.isNotEmpty() }?.let { builder.foregroundTintColor(MarkerBitmaps.color(it, MarkerBitmaps.SYSTEM_BLUE)) }
    o.optString("accuracyColor").takeIf { it.isNotEmpty() }?.let { builder.accuracyColor(MarkerBitmaps.color(it, MarkerBitmaps.SYSTEM_BLUE)) }
    o.optString("pulseColor").takeIf { it.isNotEmpty() }?.let { builder.pulseColor(MarkerBitmaps.color(it, MarkerBitmaps.SYSTEM_BLUE)) }
    val engine = locationEngine ?: LocationEngineDefault.getDefaultLocationEngine(context.applicationContext).also { locationEngine = it }
    val component = map.locationComponent
    try {
      component.activateLocationComponent(
        LocationComponentActivationOptions.Builder(context, style)
          .locationComponentOptions(builder.build())
          .locationEngine(engine)
          .useDefaultLocationEngine(false)
          .build())
      component.isLocationComponentEnabled = true
      component.renderMode = when (o.optString("renderMode")) {
        "compass" -> RenderMode.COMPASS
        "gps" -> RenderMode.GPS
        else -> if (trackingMode == UserTrackingMode.FOLLOWWITHHEADING) RenderMode.COMPASS else RenderMode.NORMAL
      }
      component.addOnCameraTrackingChangedListener(object : OnCameraTrackingChangedListener {
        override fun onCameraTrackingDismissed() {
          if (trackingMode != UserTrackingMode.NONE) {
            trackingMode = UserTrackingMode.NONE
            trackingButton.mode = 0
            listener?.onUserTrackingModeChange(UserTrackingMode.NONE)
          }
        }

        override fun onCameraTrackingChanged(currentMode: Int) {}
      })
      engine.requestLocationUpdates(LocationEngineRequest.Builder(1000).setPriority(LocationEngineRequest.PRIORITY_HIGH_ACCURACY).build(),
        locationCallback, Looper.getMainLooper())
      applyTracking()
    } catch (e: Exception) {
      listener?.onError("MapLibre: location: ${e.message}")
    }
  }

  private fun stopLocationUpdates() {
    locationEngine?.removeLocationUpdates(locationCallback)
  }

  override fun setUserTrackingMode(mode: UserTrackingMode) {
    trackingMode = mode
    trackingButton.mode = mode.ordinal
    if (mode != UserTrackingMode.NONE && !showsUserLocation) setShowsUserLocation(true)
    applyTracking()
  }

  private fun applyTracking() {
    val component = map?.locationComponent ?: return
    if (!component.isLocationComponentActivated) return
    val course = options.optJSONObject("location")?.optBoolean("course") ?: false
    component.cameraMode = when (trackingMode) {
      UserTrackingMode.NONE -> CameraMode.NONE
      UserTrackingMode.FOLLOW -> CameraMode.TRACKING
      UserTrackingMode.FOLLOWWITHHEADING -> if (course) CameraMode.TRACKING_GPS else CameraMode.TRACKING_COMPASS
    }
    if (trackingMode == UserTrackingMode.FOLLOWWITHHEADING) component.renderMode = if (course) RenderMode.GPS else RenderMode.COMPASS
  }

  // MARK: Camera: MapLibre zooms; munim-maps speaks metres from the camera.

  /** Vertical field of view in radians (MapLibre's default is 36.87°). */
  private fun fieldOfView(position: CameraPosition?): Double {
    val fov = position?.fov ?: 0.0
    return if (fov > 1 && fov < 180) fov * PI / 180 else DEFAULT_FOV
  }

  private fun heightPoints(): Double = max(1.0, (mapView?.height ?: 0) / density)

  /** Metres from the camera to the centre at this zoom (512-point tiles). */
  private fun distance(zoom: Double, latitude: Double, fov: Double): Double {
    val metersPerPoint = cos(latitude * PI / 180) * 2 * PI * MapCameraState.MERCATOR_RADIUS / (TILE_SIZE * 2.0.pow(zoom))
    return heightPoints() / 2 / tan(fov / 2) * metersPerPoint
  }

  private fun zoom(distance: Double, latitude: Double, fov: Double): Double {
    val points = heightPoints() / 2 / tan(fov / 2)
    val worldMeters = cos(latitude * PI / 180) * 2 * PI * MapCameraState.MERCATOR_RADIUS
    return ln(points * worldMeters / (TILE_SIZE * max(1.0, distance))) / ln(2.0)
  }

  private fun position(camera: MapCamera): CameraPosition {
    val fov = fieldOfView(map?.cameraPosition)
    val builder = CameraPosition.Builder()
      .target(LatLng(camera.latitude, camera.longitude))
      .zoom(zoom(camera.distance, camera.latitude, fov))
      .tilt(camera.pitch)
      .bearing(camera.heading)
    options.optJSONObject("camera")?.takeIf { it.has("roll") }?.let { builder.roll(it.optDouble("roll")) }
    return builder.build()
  }

  override fun getCamera(): MapCamera? {
    val position = map?.cameraPosition ?: return null
    val target = position.target ?: return null
    return MapCamera(target.latitude, target.longitude,
      distance(position.zoom, target.latitude, fieldOfView(position)), position.tilt, position.bearing)
  }

  override fun setCamera(camera: MapCamera, animated: Boolean) {
    stopFlight()
    val map = map ?: return
    val update = CameraUpdateFactory.newCameraPosition(position(camera))
    if (animated) map.animateCamera(update) else map.moveCamera(update)
  }

  override fun animateCamera(camera: MapCamera, durationMs: Double, easing: MapCameraEasing) {
    stopFlight()
    val map = map ?: return
    val update = CameraUpdateFactory.newCameraPosition(position(camera))
    if (durationMs <= 0) map.moveCamera(update) else map.easeCamera(update, durationMs.toInt(), easing == MapCameraEasing.EASEINOUT)
  }

  private var flight: Triple<List<CameraKeyframe>, Double, Boolean>? = null
  private val frameCallback = object : Choreographer.FrameCallback {
    override fun doFrame(frameTimeNanos: Long) {
      if (flight == null || destroyed) return
      stepFlight()
      if (flight != null) Choreographer.getInstance().postFrameCallback(this)
    }
  }

  override fun flyCamera(keyframes: Array<CameraKeyframe>, start: Double, loop: Boolean) {
    stopFlight()
    if (keyframes.size < 2) {
      keyframes.firstOrNull()?.let { setCamera(it.camera, false) }
      return
    }
    flight = Triple(keyframes.sortedBy { it.t }, start, loop)
    stepFlight()
    Choreographer.getInstance().postFrameCallback(frameCallback)
  }

  override fun stopFlight() {
    if (flight == null) return
    flight = null
    Choreographer.getInstance().removeFrameCallback(frameCallback)
  }

  private fun stepFlight() {
    val (frames, start, loop) = flight ?: return
    val map = map ?: return
    val first = frames.first()
    val last = frames.last()
    var t = System.currentTimeMillis() / 1000.0 - start
    val span = last.t - first.t
    if (loop && span > 0) {
      t = first.t + ((t - first.t) % span).let { if (it < 0) it + span else it }
    }
    val camera = when {
      t <= first.t -> first.camera
      t >= last.t -> {
        if (!loop) flight = null
        last.camera
      }
      else -> {
        var i = 1
        while (i < frames.size - 1 && frames[i].t < t) i++
        val a = frames[i - 1]
        val b = frames[i]
        interpolate(a.camera, b.camera, (t - a.t) / max(1e-9, b.t - a.t))
      }
    }
    map.moveCamera(CameraUpdateFactory.newCameraPosition(position(camera)))
    modelLayer.setNeedsRender()
  }

  private fun interpolate(a: MapCamera, b: MapCamera, f: Double): MapCamera {
    val turn = (((b.heading - a.heading) % 360) + 540) % 360 - 180
    return MapCamera(
      a.latitude + (b.latitude - a.latitude) * f,
      a.longitude + (b.longitude - a.longitude) * f,
      exp(ln(max(1.0, a.distance)) + (ln(max(1.0, b.distance)) - ln(max(1.0, a.distance))) * f),
      a.pitch + (b.pitch - a.pitch) * f,
      ((a.heading + turn * f) % 360 + 360) % 360)
  }

  override fun getVisibleRegion(): MapRegion? {
    val bounds = map?.projection?.visibleRegion?.latLngBounds ?: return null
    val center = bounds.center
    return MapRegion(center.latitude, center.longitude, bounds.latitudeSpan, bounds.longitudeSpan)
  }

  override fun setRegion(region: MapRegion, durationMs: Double) {
    stopFlight()
    val map = map ?: return
    val bounds = LatLngBounds.Builder()
      .include(LatLng(region.latitude - region.latitudeDelta / 2, region.longitude - region.longitudeDelta / 2))
      .include(LatLng(region.latitude + region.latitudeDelta / 2, region.longitude + region.longitudeDelta / 2))
      .build()
    val update = CameraUpdateFactory.newLatLngBounds(bounds, 0)
    if (durationMs > 0) map.animateCamera(update, durationMs.toInt()) else map.moveCamera(update)
  }

  override fun fitToCoordinates(coordinates: Array<MapCoordinate>, padding: EdgeInsets, animated: Boolean) {
    stopFlight()
    val map = map ?: return
    if (coordinates.isEmpty()) return
    if (coordinates.size == 1) {
      val c = coordinates[0]
      val update = CameraUpdateFactory.newLatLng(LatLng(c.latitude, c.longitude))
      if (animated) map.animateCamera(update) else map.moveCamera(update)
      return
    }
    val builder = LatLngBounds.Builder()
    coordinates.forEach { builder.include(LatLng(it.latitude, it.longitude)) }
    val update = CameraUpdateFactory.newLatLngBounds(builder.build(),
      (padding.left * density).toInt(), (padding.top * density).toInt(),
      (padding.right * density).toInt(), (padding.bottom * density).toInt())
    if (animated) map.animateCamera(update) else map.moveCamera(update)
  }

  override fun fitToMarkers(ids: Set<String>, padding: EdgeInsets, animated: Boolean) {
    fitToCoordinates(features.markerCoordinates(ids).toTypedArray(), padding, animated)
  }

  override fun pointForCoordinate(coordinate: MapCoordinate): MapPoint? {
    val point = map?.projection?.toScreenLocation(LatLng(coordinate.latitude, coordinate.longitude)) ?: return null
    return MapPoint(point.x / density, point.y / density)
  }

  override fun coordinateForPoint(point: MapPoint): MapCoordinate? {
    val latLng = map?.projection?.fromScreenLocation(PointF((point.x * density).toFloat(), (point.y * density).toFloat()))
      ?: return null
    return MapCoordinate(latLng.latitude, latLng.longitude)
  }

  // MARK: Snapshots and services

  private fun writePng(bitmap: Bitmap, completion: (Result<String>) -> Unit) {
    Thread {
      try {
        val file = File(context.cacheDir, "munim-maps-snapshot-${System.currentTimeMillis()}.png")
        FileOutputStream(file).use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        main.post { completion(Result.success(file.absolutePath)) }
      } catch (e: Exception) {
        main.post { completion(Result.failure(e)) }
      }
    }.start()
  }

  override fun takeSnapshot(width: Double, height: Double, completion: (Result<String>) -> Unit) {
    val map = map ?: return completion(Result.failure(IllegalStateException("The map is not ready yet")))
    map.snapshot { bitmap ->
      val out = if (width > 0 && height > 0) Bitmap.createScaledBitmap(bitmap, (width * density).toInt(), (height * density).toInt(), true) else bitmap
      writePng(out, completion)
    }
  }

  private fun snapshotter(args: JSONObject, completion: (Result<String>) -> Unit) {
    val w = args.optDouble("width", root.width / density)
    val h = args.optDouble("height", root.height / density)
    val snapshotOptions = MapSnapshotter.Options((w * density).toInt(), (h * density).toInt())
      .withPixelRatio(density.toFloat())
      .withLogo(args.optBoolean("showsLogo", false))
    val url = args.optString("styleUrl").ifEmpty { resolveStyle().second.uri ?: "" }
    val json = resolveStyle().second.json
    if (args.optString("styleUrl").isEmpty() && !json.isNullOrEmpty()) snapshotOptions.withStyleJson(json) else snapshotOptions.withStyle(url)
    val c = args.optJSONObject("camera")
    if (c != null) {
      val fov = DEFAULT_FOV
      val builder = CameraPosition.Builder().target(LatLng(c.optDouble("latitude"), c.optDouble("longitude")))
        .tilt(c.optDouble("pitch", 0.0)).bearing(c.optDouble("heading", 0.0))
      builder.zoom(if (c.has("zoom")) c.optDouble("zoom") else {
        val points = h / 2 / tan(fov / 2)
        val world = cos(c.optDouble("latitude") * PI / 180) * 2 * PI * MapCameraState.MERCATOR_RADIUS
        ln(points * world / (TILE_SIZE * max(1.0, c.optDouble("distance", 1000.0)))) / ln(2.0)
      })
      snapshotOptions.withCameraPosition(builder.build())
    } else map?.cameraPosition?.let { snapshotOptions.withCameraPosition(it) }
    val snapshotter = MapSnapshotter(context, snapshotOptions)
    activeSnapshotters.add(snapshotter)
    snapshotter.start({ snapshot ->
      activeSnapshotters.remove(snapshotter)
      writePng(snapshot.bitmap, completion)
    }, { error ->
      activeSnapshotters.remove(snapshotter)
      completion(Result.failure(RuntimeException(error)))
    })
  }

  private val activeSnapshotters = HashSet<MapSnapshotter>()

  /** Reverse geocoding with Nominatim (`maplibre.nominatimUrl`), light use only. */
  override fun addressForCoordinate(coordinate: MapCoordinate, completion: (Result<MapAddress>) -> Unit) {
    val base = options.optString("nominatimUrl").ifEmpty { "https://nominatim.openstreetmap.org" }
    Thread {
      val result = runCatching {
        val url = URL("$base/reverse?format=jsonv2&addressdetails=1&lat=${coordinate.latitude}&lon=${coordinate.longitude}")
        val connection = url.openConnection() as HttpURLConnection
        connection.setRequestProperty("User-Agent", "munim-maps/${context.packageName}")
        connection.setRequestProperty("Accept", "application/json")
        connection.connectTimeout = 10_000
        connection.readTimeout = 10_000
        val body = connection.inputStream.bufferedReader().use { it.readText() }
        val json = JSONObject(body)
        if (json.has("error")) throw RuntimeException(json.optString("error"))
        val a = json.optJSONObject("address") ?: JSONObject()
        val street = listOf(a.optString("house_number"), a.optString("road")).filter { it.isNotEmpty() }.joinToString(" ")
        val city = a.optString("city").ifEmpty { a.optString("town").ifEmpty { a.optString("village") } }
        MapAddress(json.optString("name"), street, city, a.optString("state"), a.optString("postcode"), a.optString("country"),
          a.optString("country_code").uppercase(), json.optString("display_name"), listOf(street, city).filter { it.isNotEmpty() }.joinToString(", "))
      }
      main.post { completion(result) }
    }.start()
  }

  // MARK: Commands

  override fun providerCommand(command: String, args: JSONObject, completion: (Result<String>) -> Unit) {
    val styleUrlForOffline = resolveStyle().first.takeIf { !it.startsWith("json:") } ?: MunimMapsConfiguration.maplibreStyleUrl
    if (MapLibreOffline.run(context, command, args, styleUrlForOffline, completion)) return
    val map = map
    val style = style
    fun ok(value: Any? = null) = completion(Result.success(when (value) {
      null -> "null"
      is String -> JSONObject.quote(value)
      else -> value.toString()
    }))
    fun fail(message: String) = completion(Result.failure(IllegalArgumentException("MapLibre $command: $message")))
    if (command == "setConnected") {
      MapLibre.setConnected(if (args.isNull("connected")) null else args.optBoolean("connected"))
      return ok()
    }
    if (command == "snapshot") return snapshotter(args, completion)
    if (map == null || style == null) return fail("the map is not ready yet")
    try {
      when (command) {
        "queryRenderedFeatures" -> {
          val layers = args.optJSONArray("layers")?.let { a -> Array(a.length()) { a.getString(it) } } ?: emptyArray()
          val filter = StyleSpec.expression(args.opt("filter"))
          val found: List<Feature> = when {
            args.has("box") -> {
              val b = args.getJSONObject("box")
              val rect = RectF((b.optDouble("x") * density).toFloat(), (b.optDouble("y") * density).toFloat(),
                ((b.optDouble("x") + b.optDouble("width")) * density).toFloat(), ((b.optDouble("y") + b.optDouble("height")) * density).toFloat())
              map.queryRenderedFeatures(rect, filter, *layers)
            }
            args.has("point") -> {
              val p = args.getJSONObject("point")
              map.queryRenderedFeatures(PointF((p.optDouble("x") * density).toFloat(), (p.optDouble("y") * density).toFloat()), filter, *layers)
            }
            else -> map.queryRenderedFeatures(RectF(0f, 0f, root.width.toFloat(), root.height.toFloat()), filter, *layers)
          }
          ok(featuresJson(found))
        }
        "querySourceFeatures" -> {
          val id = args.getString("source")
          val filter = StyleSpec.expression(args.opt("filter"))
          val found = when (val source = style.getSource(id)) {
            is GeoJsonSource -> source.querySourceFeatures(filter)
            is VectorSource -> source.querySourceFeatures(args.optJSONArray("sourceLayers")?.let { a -> Array(a.length()) { a.getString(it) } } ?: emptyArray(), filter)
            else -> return fail("'$id' is not a GeoJSON or vector source")
          }
          ok(featuresJson(found))
        }
        "getClusterLeaves", "getClusterChildren", "getClusterExpansionZoom" -> {
          val source = style.getSourceAs<GeoJsonSource>(args.getString("source")) ?: return fail("no GeoJSON source '${args.optString("source")}'")
          val clusterId = args.optLong("clusterId")
          val cluster = source.querySourceFeatures(Expression.eq(Expression.get("cluster_id"), clusterId)).firstOrNull()
            ?: return fail("no cluster $clusterId on screen")
          when (command) {
            "getClusterLeaves" -> ok(featuresJson(source.getClusterLeaves(cluster, args.optLong("limit", 10), args.optLong("offset", 0)).features().orEmpty()))
            "getClusterChildren" -> ok(featuresJson(source.getClusterChildren(cluster).features().orEmpty()))
            else -> ok(source.getClusterExpansionZoom(cluster))
          }
        }
        "metersPerPoint" -> ok(map.projection.getMetersPerPixelAtLatitude(args.optDouble("latitude")) * density)
        "getStyle" -> ok(JSONObject()
          .put("layers", JSONArray(style.layers.map { it.id }.filter { !it.startsWith("munim-slot") }))
          .put("sources", JSONArray(style.sources.map { it.id }))
          .put("json", style.json))
        "reloadStyle" -> {
          loadStyle(force = true)
          ok()
        }
        "addSource" -> {
          val id = args.getString("id")
          style.addSource(StyleSpec.source(id, args.getJSONObject("source")))
          ok()
        }
        "removeSource" -> ok(style.removeSource(args.getString("id")))
        "setGeoJson" -> {
          val source = style.getSourceAs<GeoJsonSource>(args.getString("source")) ?: return fail("no GeoJSON source '${args.optString("source")}'")
          StyleSpec.setGeoJson(source, args.opt("data"))
          ok()
        }
        "addLayer" -> {
          val layer = StyleSpec.layer(args)
          StyleSpec.add(style, layer, args.optString("beforeId"), MapLibreFeatures.SLOT_USER)
          ok()
        }
        "removeLayer" -> ok(style.removeLayer(args.getString("id")))
        "moveLayer" -> {
          val layer = style.getLayer(args.getString("id")) ?: return fail("no layer '${args.optString("id")}'")
          style.removeLayer(layer)
          StyleSpec.add(style, layer, args.optString("beforeId"), MapLibreFeatures.SLOT_USER)
          ok()
        }
        "setPaintProperty", "setLayoutProperty" -> {
          val layer = style.getLayer(args.getString("layer")) ?: return fail("no layer '${args.optString("layer")}'")
          StyleSpec.setProperty(layer, args.getString("name"), args.opt("value"), paint = command == "setPaintProperty")
          ok()
        }
        "setFilter" -> {
          val layer = style.getLayer(args.getString("layer")) ?: return fail("no layer '${args.optString("layer")}'")
          StyleSpec.setFilter(layer, args.opt("filter"))
          ok()
        }
        "setLayerZoomRange" -> {
          val layer = style.getLayer(args.getString("layer")) ?: return fail("no layer '${args.optString("layer")}'")
          layer.minZoom = args.optDouble("minzoom", 0.0).toFloat()
          layer.maxZoom = args.optDouble("maxzoom", 24.0).toFloat()
          ok()
        }
        "addImage" -> {
          loadStyleImage(args.getString("name"), args.getString("uri"), args.optBoolean("sdf"))
          ok()
        }
        "removeImage" -> {
          style.removeImage(args.getString("name"))
          ok()
        }
        "setLight" -> {
          applyLight(style, args.optJSONObject("light") ?: JSONObject())
          ok()
        }
        "setFeatureState", "getFeatureState", "removeFeatureState" -> {
          val sourceId = args.getString("source")
          val sourceLayer = args.optString("sourceLayer").takeIf { it.isNotEmpty() }
          val id = if (args.has("id")) args.get("id").toString() else null
          when (val source = style.getSource(sourceId)) {
            is GeoJsonSource -> when (command) {
              "setFeatureState" -> ok(source.setFeatureState(id ?: return fail("needs an id"), StyleSpec.gsonObject(args.optJSONObject("state"))))
              "getFeatureState" -> ok(source.getFeatureState(id ?: return fail("needs an id"))?.toString())
              else -> ok(if (id == null) source.resetFeatureStates() else if (args.has("key")) source.removeFeatureState(id, args.getString("key")) else source.removeFeatureState(id))
            }
            is VectorSource -> {
              val layer = sourceLayer ?: return fail("vector sources need a sourceLayer")
              when (command) {
                "setFeatureState" -> ok(source.setFeatureState(layer, id ?: return fail("needs an id"), StyleSpec.gsonObject(args.optJSONObject("state"))))
                "getFeatureState" -> ok(source.getFeatureState(layer, id ?: return fail("needs an id"))?.toString())
                else -> ok(if (id == null) source.resetFeatureStates(layer) else if (args.has("key")) source.removeFeatureState(layer, id, args.getString("key")) else source.removeFeatureState(layer, id))
              }
            }
            else -> fail("'$sourceId' is not a GeoJSON or vector source")
          }
        }
        "flyTo" -> {
          stopFlight()
          val c = args.getJSONObject("camera")
          val camera = MapCamera(c.getDouble("latitude"), c.getDouble("longitude"), c.optDouble("distance", 1000.0), c.optDouble("pitch", 0.0), c.optDouble("heading", 0.0))
          map.animateCamera(CameraUpdateFactory.newCameraPosition(position(camera)), args.optInt("durationMs", 2000))
          ok()
        }
        "resetNorth" -> {
          map.resetNorth()
          ok()
        }
        "resetPosition" -> {
          initialCamera?.let { setCamera(it, true) }
          ok()
        }
        else -> fail("unknown command")
      }
    } catch (e: Exception) {
      completion(Result.failure(e))
    }
  }

  private fun featuresJson(features: List<Feature>): JSONArray = JSONArray(features.map { JSONObject(it.toJson()) })

  // MARK: MapCameraSource

  override val cameraView: View? get() = if (destroyed) null else mapView

  override fun cameraState(previous: MapCameraState?): MapCameraState? {
    val map = map ?: return null
    val mapView = mapView ?: return null
    if (style == null) return null
    val width = mapView.width.toDouble()
    val height = mapView.height.toDouble()
    if (width < 1 || height < 1) return null
    val position = map.cameraPosition
    val target = position.target ?: return null
    val fov = fieldOfView(position)
    val distance = distance(position.zoom, target.latitude, fov)
    // MapLibre puts the centre coordinate in the middle of the padded area.
    val pad = position.padding ?: doubleArrayOf(0.0, 0.0, 0.0, 0.0)
    val centerX = pad.getOrElse(0) { 0.0 } + (width - pad.getOrElse(0) { 0.0 } - pad.getOrElse(2) { 0.0 }) / 2
    val centerY = pad.getOrElse(1) { 0.0 } + (height - pad.getOrElse(1) { 0.0 } - pad.getOrElse(3) { 0.0 }) / 2
    return MapCameraState(
      latitude = target.latitude,
      longitude = target.longitude,
      distance = distance,
      altitude = distance * cos(position.tilt * PI / 180),
      pitch = position.tilt,
      heading = position.bearing,
      width = width,
      height = height,
      focalLength = MapCameraState.focalLength(height, fov),
      centerX = centerX,
      centerY = centerY,
      pixelRatio = density,
      darkAppearance = isDark,
    )
  }

  override fun screenPoint(latitude: Double, longitude: Double): PointF? =
    map?.projection?.toScreenLocation(LatLng(latitude, longitude))

  companion object {
    /** MapLibre's vertical field of view: 2 atan(1/3), about 36.87°. */
    private const val DEFAULT_FOV = 0.6435011087932844
    private const val TILE_SIZE = 512.0
  }
}
