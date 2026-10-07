package com.munimmaps.engines.cesium

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.PointF
import android.location.Geocoder
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.view.View
import android.webkit.JavascriptInterface
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import com.margelo.nitro.munimmaps.CalloutAccessoryEvent
import com.margelo.nitro.munimmaps.CalloutAccessorySide
import com.margelo.nitro.munimmaps.CameraKeyframe
import com.margelo.nitro.munimmaps.ClusterPressEvent
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
import com.margelo.nitro.munimmaps.MarkerDragEvent
import com.margelo.nitro.munimmaps.NativeCircle
import com.margelo.nitro.munimmaps.NativeClusterStyle
import com.margelo.nitro.munimmaps.NativeMapModel
import com.margelo.nitro.munimmaps.NativeMapPath
import com.margelo.nitro.munimmaps.NativeMapZone
import com.margelo.nitro.munimmaps.NativeMarker
import com.margelo.nitro.munimmaps.NativePolygon
import com.margelo.nitro.munimmaps.NativePolyline
import com.margelo.nitro.munimmaps.NativeTileOverlay
import com.margelo.nitro.munimmaps.OverlayPressEvent
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
import java.io.ByteArrayInputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import java.util.concurrent.Executors
import kotlin.math.PI
import kotlin.math.cos

object CesiumMapEngineFactory : MunimMapEngineFactory {
  override val isImplemented = true
  override fun create(context: Context): MunimMapEngine = CesiumMapEngine(context)
}

/**
 * The Cesium engine on Android: CesiumJS (bundled with munim-maps as
 * assets under `munim-cesium/`, added by `munimMaps.cesium=true`) running in
 * an `android.webkit.WebView` this engine owns. The web half
 * (cesium/munim-cesium/js) draws the map, markers, shapes and the glTF
 * models; this half hosts it, serves its files at
 * `https://appassets.androidplatform.net/` (so it is a secure https origin
 * and tile servers see a referrer), turns props into messages and messages
 * into events, and keeps munim-maps' Filament 3D layer on Cesium's camera
 * (`cesium.modelRenderer = 'native'`).
 */
@SuppressLint("SetJavaScriptEnabled")
class CesiumMapEngine(context: Context) : MunimMapEngine, MapCameraSource {
  override val provider = MapProvider.CESIUM
  override var listener: MunimMapEngineListener? = null

  private val app = context.applicationContext
  private val density = context.resources.displayMetrics.density.toDouble()
  private val main = Handler(Looper.getMainLooper())
  private val webView = WebView(context)
  private val root = FrameLayout(context)
  override val modelLayer = MunimModelLayer(context)
  override val view: View get() = root

  private var pageReady = false
  private val queue = mutableListOf<String>()
  private val sent = LinkedHashMap<String, Any?>()
  private val calls = HashMap<String, (Result<Any?>) -> Unit>()
  private var nextCall = 0
  private var camera: CesiumCamera? = null
  private var destroyed = false
  private var readyReported = false

  init {
    MunimMapsConfiguration.load(context)
    if (app.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) WebView.setWebContentsDebuggingEnabled(true)
    val settings = webView.settings
    settings.javaScriptEnabled = true
    settings.domStorageEnabled = true
    settings.allowFileAccess = false
    settings.allowContentAccess = false
    settings.mediaPlaybackRequiresUserGesture = false
    settings.setSupportZoom(false)
    settings.builtInZoomControls = false
    settings.useWideViewPort = true
    settings.loadWithOverviewMode = false
    // OpenStreetMap's tile policy asks apps to identify themselves.
    settings.userAgentString = "${settings.userAgentString} munim-maps-cesium/1.0 (${app.packageName})"
    webView.setBackgroundColor(android.graphics.Color.BLACK)
    webView.isVerticalScrollBarEnabled = false
    webView.isHorizontalScrollBarEnabled = false
    webView.overScrollMode = View.OVER_SCROLL_NEVER
    webView.addJavascriptInterface(Bridge(), "MunimAndroid")
    webView.webViewClient = Client()
    root.addView(webView, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    val layerView = modelLayer.view
    layerView.isClickable = false
    layerView.isFocusable = false
    root.addView(layerView, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    modelLayer.attach(this)
    load()
  }

  private fun load() {
    pageReady = false
    webView.loadUrl("$ORIGIN/index.html")
  }

  override fun destroy() {
    if (destroyed) return
    destroyed = true
    stopLocation()
    modelLayer.destroy()
    webView.removeJavascriptInterface("MunimAndroid")
    webView.destroy()
  }

  // Messages

  private inner class Bridge {
    @JavascriptInterface
    fun postMessage(json: String) {
      main.post { if (!destroyed) receive(json) }
    }
  }

  private fun evaluate(js: String) {
    if (destroyed) return
    if (Looper.myLooper() == Looper.getMainLooper()) webView.evaluateJavascript(js, null)
    else main.post { if (!destroyed) webView.evaluateJavascript(js, null) }
  }

  private fun post(message: JSONObject) {
    val json = message.toString()
    if (!pageReady) {
      queue.add(json)
      return
    }
    evaluate("window.munimCesium&&window.munimCesium.receive($json)")
  }

  private fun set(key: String, value: Any?) {
    val v = CesiumJson.value(value)
    sent[key] = v
    post(JSONObject().put("t", "set").put("k", key).put("v", v ?: JSONObject.NULL))
  }

  private fun call(method: String, args: JSONObject = JSONObject(), completion: ((Result<Any?>) -> Unit)? = null) {
    nextCall += 1
    val id = "c$nextCall"
    if (completion != null) calls[id] = completion
    post(JSONObject().put("t", "call").put("id", id).put("m", method).put("a", args))
  }

  private fun sendInit() {
    if (!pageReady) return
    val env = JSONObject()
      .put("platform", "android")
      .put("ionToken", MunimMapsConfiguration.cesiumIonToken)
      .put("googleKey", MunimMapsConfiguration.googleMapsApiKey)
      .put("resourceBase", "$ORIGIN/resource?uri=")
      .put("tileProxy", "")
      .put("density", density)
      .put("appId", app.packageName)
    val messages = JSONArray()
    sent["options"]?.let { messages.put(JSONObject().put("t", "set").put("k", "options").put("v", it)) }
    for ((k, v) in sent) if (k != "options") messages.put(JSONObject().put("t", "set").put("k", k).put("v", v ?: JSONObject.NULL))
    messages.put(JSONObject().put("t", "init").put("env", env))
    evaluate("window.munimCesium.receive(${JSONObject().put("t", "batch").put("m", messages)})")
  }

  private fun receive(json: String) {
    val m = try { JSONObject(json) } catch (_: Exception) { return }
    when (m.optString("t")) {
      "ready" -> {
        pageReady = true
        sendInit()
        val pending = queue.filter { !it.contains("\"t\":\"set\"") }
        queue.clear()
        for (p in pending) evaluate("window.munimCesium.receive($p)")
      }
      "cam" -> m.optJSONObject("s")?.let {
        camera = CesiumCamera(it, camera)
        modelLayer.setNeedsRender()
      }
      "result" -> {
        val completion = calls.remove(m.optString("id")) ?: return
        if (m.optBoolean("ok")) completion(Result.success(if (m.isNull("v")) null else m.opt("v")))
        else completion(Result.failure(IllegalStateException(m.optString("e", "Cesium: failed"))))
      }
      "event" -> handleEvent(m.optString("n"), m.optJSONObject("d") ?: JSONObject())
    }
  }

  private fun handleEvent(name: String, d: JSONObject) {
    val l = listener
    fun lat() = d.optDouble("latitude", 0.0)
    fun lon() = d.optDouble("longitude", 0.0)
    fun cam() = MapCamera(lat(), lon(), d.optDouble("distance", 0.0), d.optDouble("pitch", 0.0), d.optDouble("heading", 0.0))
    when (name) {
      "mapReady" -> if (!readyReported) {
        readyReported = true
        l?.onMapReady()
      }
      "press" -> {
        val x = d.optDouble("x")
        val y = d.optDouble("y")
        if (!modelLayer.handleTap((x * density).toFloat(), (y * density).toFloat())) l?.onPress(MapPressEvent(lat(), lon(), x, y))
      }
      "longPress" -> l?.onLongPress(MapPressEvent(lat(), lon(), d.optDouble("x"), d.optDouble("y")))
      "cameraMove" -> l?.onCameraMove(cam())
      "cameraChange" -> l?.onCameraChange(cam())
      "markerPress" -> l?.onMarkerPress(d.optString("id"))
      "markerDeselect" -> l?.onMarkerDeselect(d.optString("id"))
      "calloutPress" -> l?.onCalloutPress(d.optString("id"))
      "calloutAccessoryPress" -> l?.onCalloutAccessoryPress(
        CalloutAccessoryEvent(d.optString("id"), if (d.optString("side") == "left") CalloutAccessorySide.LEFT else CalloutAccessorySide.RIGHT))
      "clusterPress" -> l?.onClusterPress(ClusterPressEvent(d.optString("clusteringId"), d.optString("markerIds"), lat(), lon()))
      "overlayPress" -> l?.onOverlayPress(OverlayPressEvent(d.optString("id"), d.optString("kind"), lat(), lon()))
      "markerDragStart" -> l?.onMarkerDragStart(MarkerDragEvent(d.optString("id"), lat(), lon()))
      "markerDragEnd" -> l?.onMarkerDragEnd(MarkerDragEvent(d.optString("id"), lat(), lon()))
      "modelPress" -> modelLayer.onModelPress?.invoke(d.optString("id"))
      "userTrackingModeChange" -> {
        trackingMode = when (d.optString("mode")) {
          "follow" -> UserTrackingMode.FOLLOW
          "followWithHeading" -> UserTrackingMode.FOLLOWWITHHEADING
          else -> UserTrackingMode.NONE
        }
        l?.onUserTrackingModeChange(trackingMode)
      }
      "mapFeaturePress" -> l?.onMapFeaturePress(
        MapFeatureEvent(d.optString("title"), lat(), lon(), d.optString("kind"), d.optString("category"), d.optString("id")))
      "provider" -> l?.onProviderEvent(d.optString("name"), (d.opt("data") ?: JSONObject()).toString())
      "error" -> l?.onError(d.optString("message", "Cesium: error"))
    }
  }

  private inner class Client : WebViewClient() {
    override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
      val url = request.url
      if (url.host != HOST) return null
      val path = url.path ?: "/"
      return try {
        if (path == "/resource") {
          val uri = url.getQueryParameter("uri") ?: return notFound()
          response(readResource(uri), mime(uri.substringBefore('?').substringAfterLast('.', "")))
        } else {
          val asset = "munim-cesium" + (if (path == "/") "/index.html" else path)
          response(app.assets.open(asset).use { it.readBytes() }, mime(asset.substringAfterLast('.', "")))
        }
      } catch (_: Exception) {
        notFound()
      }
    }

    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
      if (request.url.host == HOST) return false
      // Links in credits and info boxes open in the browser.
      try {
        app.startActivity(Intent(Intent.ACTION_VIEW, request.url).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
      } catch (_: Exception) {
      }
      return true
    }

    override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
      // The WebView's renderer died (memory): the view cannot be used again.
      listener?.onError("Cesium: the WebView's renderer ended (memory); remount the map")
      destroyed = true
      return true
    }
  }

  private fun response(bytes: ByteArray, mime: String): WebResourceResponse {
    val encoding = if (mime.startsWith("text/") || mime == "application/json") "utf-8" else null
    return WebResourceResponse(mime.substringBefore(';'), encoding, 200, "OK",
      mapOf("Access-Control-Allow-Origin" to "*", "Cache-Control" to "no-cache"), ByteArrayInputStream(bytes))
  }

  private fun notFound() = WebResourceResponse("text/plain", "utf-8", 404, "Not Found",
    mapOf("Access-Control-Allow-Origin" to "*"), ByteArrayInputStream(ByteArray(0)))

  /** The app's files: Metro's http, file paths, assets, raw and drawable resources (release builds). */
  private fun readResource(uri: String): ByteArray {
    val parsed = Uri.parse(uri)
    return when (parsed.scheme?.lowercase(Locale.ROOT)) {
      "http", "https" -> {
        val connection = URL(uri).openConnection() as HttpURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        try {
          if (connection.responseCode !in 200..299) error("HTTP ${connection.responseCode}")
          connection.inputStream.use { it.readBytes() }
        } finally {
          connection.disconnect()
        }
      }
      "file" -> File(parsed.path ?: error("bad path")).readBytes()
      "asset" -> app.assets.open(uri.removePrefix("asset:/").trimStart('/')).use { it.readBytes() }
      "android.resource", "res" -> readNamed(parsed.lastPathSegment ?: error("bad resource"))
      else -> if (uri.startsWith("/")) File(uri).readBytes() else readNamed(uri)
    }
  }

  private fun readNamed(name: String): ByteArray {
    val base = name.substringBeforeLast('.')
    for (type in listOf("raw", "drawable")) {
      val id = app.resources.getIdentifier(base, type, app.packageName)
      if (id != 0) return app.resources.openRawResource(id).use { it.readBytes() }
    }
    error("No resource named $name")
  }

  private fun mime(ext: String): String = when (ext.lowercase(Locale.ROOT)) {
    "html" -> "text/html"
    "js", "mjs", "cjs" -> "text/javascript"
    "css" -> "text/css"
    "json", "czml", "geojson", "topojson" -> "application/json"
    "wasm" -> "application/wasm"
    "png" -> "image/png"
    "jpg", "jpeg" -> "image/jpeg"
    "gif" -> "image/gif"
    "svg" -> "image/svg+xml"
    "webp" -> "image/webp"
    "glb" -> "model/gltf-binary"
    "gltf" -> "model/gltf+json"
    "kml" -> "application/vnd.google-earth.kml+xml"
    "xml", "gpx" -> "application/xml"
    else -> "application/octet-stream"
  }

  // Props

  private var options = JSONObject()
  /** `modelRendering`: `auto` / `native` (Cesium) or `overlay` (the Filament layer); `modelRenderer` is the older name. */
  private val renderer: String
    get() = options.optString("modelRendering", "").ifEmpty {
      when (options.optString("modelRenderer", "auto")) {
        "cesium" -> "native"
        "native" -> "overlay"
        else -> "auto"
      }
    }

  override fun setStyleUrl(url: String) = set("styleUrl", url)

  override fun setProviderOptions(options: JSONObject) {
    this.options = options
    set("options", options)
    setModels(allModels)
    setZones(allZones)
    setPaths(allPaths)
  }

  override fun setMarkers(markers: Array<NativeMarker>) = set("markers", markers)
  override fun setPolylines(polylines: Array<NativePolyline>) = set("polylines", polylines)
  override fun setPolygons(polygons: Array<NativePolygon>) = set("polygons", polygons)
  override fun setCircles(circles: Array<NativeCircle>) = set("circles", circles)
  override fun setTileOverlays(overlays: Array<NativeTileOverlay>) = set("tileOverlays", overlays)
  override fun setClusterStyles(styles: Array<NativeClusterStyle>) = set("clusterStyles", styles)

  private var allModels: Array<NativeMapModel> = emptyArray()
  private var allZones: Array<NativeMapZone> = emptyArray()
  private var allPaths: Array<NativeMapPath> = emptyArray()

  /** Whether Cesium draws the model (glTF, shapes, pictures) or the Filament layer does. */
  private fun cesiumDraws(model: NativeMapModel): Boolean = when (renderer) {
    "overlay" -> false
    "native" -> true
    else -> !model.occluder
  }

  override fun setModels(models: Array<NativeMapModel>) {
    allModels = models
    set("models", models.filter { cesiumDraws(it) })
    modelLayer.models = models.filter { !cesiumDraws(it) }.toTypedArray()
  }

  override fun setZones(zones: Array<NativeMapZone>) {
    allZones = zones
    set("zones", if (renderer == "overlay") emptyArray<NativeMapZone>() else zones)
    modelLayer.zones = if (renderer == "overlay") zones else emptyArray()
  }

  override fun setPaths(paths: Array<NativeMapPath>) {
    allPaths = paths
    set("paths", if (renderer == "overlay") emptyArray<NativeMapPath>() else paths)
    modelLayer.paths = if (renderer == "overlay") paths else emptyArray()
  }

  override fun modelLayerDidChange() {
    set("lighting", modelLayer.lighting.name.lowercase(Locale.ROOT))
    set("maxCameraDistance", modelLayer.maxCameraDistance)
    set("occlusion", if (modelLayer.buildingOcclusion) "buildings" else "none")
    set("followTerrain", modelLayer.followsTerrain)
  }

  private var initialCamera: MapCamera? = null
  override fun setInitialCamera(camera: MapCamera) {
    initialCamera = camera
    set("initialCamera", camera)
  }
  override fun setMapStyle(style: MapStyle) = set("mapStyle", style.name.lowercase(Locale.ROOT))
  override fun setElevation(elevation: MapElevation) = set("elevation", elevation.name.lowercase(Locale.ROOT))
  override fun setGlobe(globe: Boolean) = set("globe", globe)
  override fun setColorScheme(scheme: MapColorScheme) = set("colorScheme", scheme.name.lowercase(Locale.ROOT))
  override fun setShowsBuildings(shows: Boolean) = set("showsBuildings", shows)
  private var showsUserLocation = false
  override fun setShowsUserLocation(shows: Boolean) {
    showsUserLocation = shows
    set("showsUserLocation", shows)
    updateLocation()
  }
  override fun setShowsTraffic(shows: Boolean) {}
  override fun setPointsOfInterest(filter: String) {}
  override fun setCompassVisibility(visibility: FeatureVisibility) = set("compassVisibility", visibility.name.lowercase(Locale.ROOT))
  override fun setScaleVisibility(visibility: FeatureVisibility) = set("scaleVisibility", visibility.name.lowercase(Locale.ROOT))
  override fun setShowsUserTrackingButton(shows: Boolean) = set("showsUserTrackingButton", shows)
  override fun setPitchButtonVisibility(visibility: FeatureVisibility) = set("pitchButtonVisibility", visibility.name.lowercase(Locale.ROOT))
  override fun setSelectableMapFeatures(features: String) =
    set("selectableFeatures", features.split(",").map { it.trim() }.filter { it.isNotEmpty() })

  private var trackingMode = UserTrackingMode.NONE
  override fun setUserTrackingMode(mode: UserTrackingMode) {
    trackingMode = mode
    set("userTrackingMode", when (mode) {
      UserTrackingMode.FOLLOW -> "follow"
      UserTrackingMode.FOLLOWWITHHEADING -> "followWithHeading"
      else -> "none"
    })
    updateLocation()
  }

  override fun setGestures(zoom: Boolean, scroll: Boolean, rotate: Boolean, pitch: Boolean) =
    set("gestures", JSONObject().put("zoom", zoom).put("scroll", scroll).put("rotate", rotate).put("pitch", pitch))

  override fun setCameraDistanceRange(min: Double, max: Double) =
    set("distanceRange", JSONObject().put("min", min).put("max", max))

  override fun setCameraBoundary(region: MapRegion?) = set("boundary", region)
  override fun setMapPadding(padding: EdgeInsets) = set("mapPadding", padding)
  override fun setOverlayPressEnabled(enabled: Boolean) = set("overlayPress", enabled)

  // Camera

  override fun getCamera(): MapCamera? = camera?.let { MapCamera(it.latitude, it.longitude, it.distance, it.pitch, it.heading) } ?: initialCamera

  private fun cameraJson(c: MapCamera) = CesiumJson.value(c)

  override fun setCamera(camera: MapCamera, animated: Boolean) =
    call("setCamera", JSONObject().put("camera", cameraJson(camera)).put("animated", animated))

  override fun animateCamera(camera: MapCamera, durationMs: Double, easing: MapCameraEasing) =
    call("animateCamera", JSONObject().put("camera", cameraJson(camera)).put("durationMs", durationMs)
      .put("easing", if (easing == MapCameraEasing.LINEAR) "linear" else "easeInOut"))

  override fun flyCamera(keyframes: Array<CameraKeyframe>, start: Double, loop: Boolean) =
    call("flyCamera", JSONObject().put("keyframes", CesiumJson.value(keyframes)).put("start", start).put("loop", loop))

  override fun stopFlight() = call("stopFlight")

  override fun getVisibleRegion(): MapRegion? = camera?.region ?: camera?.let { MapRegion(it.latitude, it.longitude, 0.0, 0.0) }

  override fun setRegion(region: MapRegion, durationMs: Double) =
    call("setRegion", JSONObject().put("region", CesiumJson.value(region)).put("durationMs", durationMs))

  override fun fitToCoordinates(coordinates: Array<MapCoordinate>, padding: EdgeInsets, animated: Boolean) =
    call("fitToCoordinates", JSONObject().put("coordinates", CesiumJson.value(coordinates)).put("padding", CesiumJson.value(padding)).put("animated", animated))

  override fun fitToMarkers(ids: Set<String>, padding: EdgeInsets, animated: Boolean) =
    call("fitToMarkers", JSONObject().put("ids", JSONArray(ids.toList())).put("padding", CesiumJson.value(padding)).put("animated", animated))

  override fun pointForCoordinate(coordinate: MapCoordinate): MapPoint? {
    val p = camera?.screenPoint(coordinate.latitude, coordinate.longitude) ?: return null
    return MapPoint(p[0], p[1])
  }

  override fun coordinateForPoint(point: MapPoint): MapCoordinate? {
    val c = camera?.coordinate(point.x, point.y) ?: return null
    return MapCoordinate(c[0], c[1])
  }

  // Methods

  override fun selectMarker(id: String) = call("selectMarker", JSONObject().put("id", id))
  override fun deselectMarker(id: String) = call("deselectMarker", JSONObject().put("id", id))

  override fun takeSnapshot(width: Double, height: Double, completion: (Result<String>) -> Unit) {
    call("snapshot", JSONObject().put("width", width).put("height", height)) { result ->
      result.fold({ value ->
        try {
          val bytes = Base64.decode(value as String, Base64.DEFAULT)
          val file = File(app.cacheDir, "munim-cesium-${System.currentTimeMillis()}.png")
          file.writeBytes(bytes)
          completion(Result.success(file.absolutePath))
        } catch (e: Exception) {
          completion(Result.failure(e))
        }
      }, { completion(Result.failure(it)) })
    }
  }

  override fun addressForCoordinate(coordinate: MapCoordinate, completion: (Result<MapAddress>) -> Unit) {
    background.execute {
      val result = runCatching {
        @Suppress("DEPRECATION")
        val a = Geocoder(app).getFromLocation(coordinate.latitude, coordinate.longitude, 1)?.firstOrNull()
          ?: error("No address here")
        val street = listOfNotNull(a.subThoroughfare, a.thoroughfare).joinToString(" ")
        val formatted = (0..a.maxAddressLineIndex).mapNotNull { a.getAddressLine(it) }.joinToString(", ")
        MapAddress(a.featureName ?: "", street, a.locality ?: "", a.adminArea ?: "", a.postalCode ?: "",
          a.countryName ?: "", a.countryCode ?: "", formatted, listOfNotNull(street.ifEmpty { null }, a.locality).joinToString(", "))
      }
      main.post { completion(result) }
    }
  }

  override fun providerCommand(command: String, args: String, completion: (Result<String>) -> Unit) {
    val json = try { JSONObject(args.ifBlank { "{}" }) } catch (_: Exception) { JSONObject() }
    call(command, json) { result ->
      completion(result.map { v ->
        when (v) {
          null, JSONObject.NULL -> "null"
          is String -> JSONObject.quote(v)
          else -> v.toString()
        }
      })
    }
  }

  // MapCameraSource: Cesium's camera for the Filament layer, in pixels.

  override val cameraView: View? get() = if (destroyed) null else webView

  override fun cameraState(previous: MapCameraState?): MapCameraState? {
    val c = camera ?: return null
    if (c.width <= 0 || c.height <= 0) return null
    val width = c.width * density
    val height = c.height * density
    return MapCameraState(
      latitude = c.latitude,
      longitude = c.longitude,
      distance = c.distance,
      altitude = c.distance * cos(c.pitch * PI / 180),
      pitch = c.pitch,
      heading = c.heading,
      width = width,
      height = height,
      focalLength = MapCameraState.focalLength(height, c.fovy),
      centerX = c.centerX * density,
      centerY = c.centerY * density,
      globe = c.globe,
      drawsTerrain = c.terrain,
      darkAppearance = c.dark,
      pixelRatio = density,
    )
  }

  override fun screenPoint(latitude: Double, longitude: Double): PointF? {
    val p = camera?.screenPoint(latitude, longitude) ?: return null
    return PointF((p[0] * density).toFloat(), (p[1] * density).toFloat())
  }

  // User location (needs the app to hold location permission)

  private val background = Executors.newSingleThreadExecutor()
  private var locationListener: LocationListener? = null

  private fun updateLocation() {
    val wanted = showsUserLocation || trackingMode != UserTrackingMode.NONE
    if (!wanted) return stopLocation()
    if (locationListener != null) return
    val fine = app.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
    val coarse = app.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
    if (!fine && !coarse) {
      listener?.onError("Cesium: showsUserLocation needs the location permission (ask for it first)")
      return
    }
    val manager = app.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    val l = LocationListener { location -> onLocation(location) }
    locationListener = l
    try {
      for (p in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
        if (manager.isProviderEnabled(p)) manager.requestLocationUpdates(p, 1000L, 1f, l, Looper.getMainLooper())
      }
      (manager.getLastKnownLocation(LocationManager.GPS_PROVIDER) ?: manager.getLastKnownLocation(LocationManager.NETWORK_PROVIDER))?.let { onLocation(it) }
    } catch (e: SecurityException) {
      listener?.onError("Cesium: location: ${e.message}")
    }
  }

  private fun stopLocation() {
    val l = locationListener ?: return
    (app.getSystemService(Context.LOCATION_SERVICE) as LocationManager).removeUpdates(l)
    locationListener = null
  }

  private fun onLocation(location: Location) {
    val heading = if (location.hasBearing()) location.bearing.toDouble() else -1.0
    set("userLocation", JSONObject().put("latitude", location.latitude).put("longitude", location.longitude)
      .put("altitude", location.altitude).put("horizontalAccuracy", location.accuracy.toDouble()).put("heading", heading))
    listener?.onUserLocationChange(UserLocationEvent(location.latitude, location.longitude, location.altitude,
      location.accuracy.toDouble(), if (location.hasVerticalAccuracy()) location.verticalAccuracyMeters.toDouble() else -1.0,
      heading, if (location.hasSpeed()) location.speed.toDouble() else -1.0))
  }

  companion object {
    private const val HOST = "appassets.androidplatform.net"
    private const val ORIGIN = "https://$HOST"
  }
}
