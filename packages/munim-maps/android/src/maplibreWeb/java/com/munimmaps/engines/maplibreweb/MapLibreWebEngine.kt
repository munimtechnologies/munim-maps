package com.munimmaps.engines.maplibreweb

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.PointF
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
import com.margelo.nitro.munimmaps.MapAlignmentReport
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
import com.margelo.nitro.munimmaps.MarkerStyle
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

object MapLibreWebEngineFactory : MunimMapEngineFactory {
  override val isImplemented = true
  override fun create(context: Context): MunimMapEngine = MapLibreWebEngine(context)
}

/**
 * MapLibre GL JS as the `maplibre` provider's second renderer ([variant]
 * "web"), for what MapLibre Native does not have: the globe, 3D terrain,
 * sky and atmosphere. GL JS (from jsDelivr, cached on disk, or bundled from
 * the app's `maplibre-gl` package as assets under `munim-maplibre/`) runs in
 * an `android.webkit.WebView` this engine owns. The web half
 * (maplibre/page/munim-maplibre/js) draws the map, markers, shapes and
 * munim-maps' 3D layer (three.js inside GL JS); this half hosts it, serves
 * its files at `https://appassets.androidplatform.net/`, turns props into
 * messages and messages into events, and keeps the Filament layer on GL JS's
 * camera for `modelRendering: 'overlay'`.
 */
@SuppressLint("SetJavaScriptEnabled")
class MapLibreWebEngine(context: Context) : MunimMapEngine, MapCameraSource {
  override val provider = MapProvider.MAPLIBRE
  override val variant = "web"
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
  private var camera: MapLibreWebCamera? = null
  private var destroyed = false
  private var readyReported = false
  private val background = Executors.newFixedThreadPool(4)

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
    settings.userAgentString = "${settings.userAgentString} munim-maps-maplibre/1.0 (${app.packageName})"
    webView.setBackgroundColor(android.graphics.Color.rgb(242, 239, 233))
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
    background.shutdown()
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
    evaluate("window.munimMapLibre&&window.munimMapLibre.receive($json)")
  }

  private fun set(key: String, value: Any?) {
    val v = MapLibreWebJson.value(value)
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
      .put("resourceBase", "$ORIGIN/resource?uri=")
      .put("tileProxy", "")
      .put("density", density)
      .put("appId", app.packageName)
      .put("defaultStyleUrl", MunimMapsConfiguration.maplibreStyleUrl)
    val messages = JSONArray()
    sent["options"]?.let { messages.put(JSONObject().put("t", "set").put("k", "options").put("v", it)) }
    for ((k, v) in sent) if (k != "options") messages.put(JSONObject().put("t", "set").put("k", k).put("v", v ?: JSONObject.NULL))
    messages.put(JSONObject().put("t", "init").put("env", env))
    evaluate("window.munimMapLibre.receive(${JSONObject().put("t", "batch").put("m", messages)})")
  }

  private fun receive(json: String) {
    val m = try { JSONObject(json) } catch (_: Exception) { return }
    when (m.optString("t")) {
      "ready" -> {
        pageReady = true
        sendInit()
        val pending = queue.filter { !it.contains("\"t\":\"set\"") }
        queue.clear()
        for (p in pending) evaluate("window.munimMapLibre.receive($p)")
      }
      "cam" -> m.optJSONObject("s")?.let {
        camera = MapLibreWebCamera(it, camera)
        modelLayer.setNeedsRender()
      }
      "result" -> {
        val completion = calls.remove(m.optString("id")) ?: return
        if (m.optBoolean("ok")) completion(Result.success(if (m.isNull("v")) null else m.opt("v")))
        else completion(Result.failure(IllegalStateException(m.optString("e", "MapLibre GL JS: failed"))))
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
        l?.onProviderEvent("renderer", JSONObject().put("renderer", "web").put("maplibre", d.optString("maplibre")).toString())
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
      "markerDrag" -> l?.onMarkerDrag(MarkerDragEvent(d.optString("id"), lat(), lon()))
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
      "error" -> l?.onError(d.optString("message", "MapLibre GL JS: error"))
    }
  }

  private inner class Client : WebViewClient() {
    override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
      val url = request.url
      if (url.host != HOST) return null
      val path = url.path ?: "/"
      return try {
        when {
          path == "/resource" -> {
            val uri = url.getQueryParameter("uri") ?: return notFound()
            response(readResource(uri), mime(uri.substringBefore('?').substringAfterLast('.', "")))
          }
          path.startsWith("/maplibre-gl/") -> library(MAPLIBRE, path.removePrefix("/maplibre-gl/"))
          path.startsWith("/three/") -> library(THREE, path.removePrefix("/three/"))
          else -> {
            val asset = "munim-maplibre" + (if (path == "/") "/index.html" else path)
            response(app.assets.open(asset).use { it.readBytes() }, mime(asset.substringAfterLast('.', "")))
          }
        }
      } catch (_: Exception) {
        notFound()
      }
    }

    override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
      if (request.url.host == HOST) return false
      // Attribution links open in the browser.
      try {
        app.startActivity(Intent(Intent.ACTION_VIEW, request.url).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
      } catch (_: Exception) {
      }
      return true
    }

    override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
      // The WebView's renderer died (memory): the view cannot be used again.
      listener?.onError("MapLibre GL JS: the WebView's renderer ended (memory); remount the map")
      destroyed = true
      return true
    }
  }

  private fun response(bytes: ByteArray, mime: String): WebResourceResponse {
    val encoding = if (mime.startsWith("text/") || mime == "application/json") "utf-8" else null
    return WebResourceResponse(mime.substringBefore(';'), encoding, 200, "OK",
      mapOf("Access-Control-Allow-Origin" to "*", "Cache-Control" to "no-cache"), ByteArrayInputStream(bytes))
  }

  /**
   * GL JS and three.js: from the APK when bundled (`munimMaps.maplibreBundled=true`,
   * the packages as published, so `.min.js` names fall back to the plain
   * files), otherwise from jsDelivr at the pinned versions (or the manifest's
   * `munimmaps.maplibre_gl_base_url` / `munimmaps.three_base_url`), kept in the
   * cache directory after the first load. The page stays same-origin
   * (workers, ES modules) and works offline afterwards.
   */
  private fun library(lib: Library, relative: String): WebResourceResponse {
    if (relative.isEmpty() || relative.split('/').contains("..")) return notFound()
    val mime = mime(relative.substringAfterLast('.', ""))
    if (bundled(app, lib)) {
      val asset = "munim-maplibre/${lib.folder}/$relative"
      val bytes = runCatching { app.assets.open(asset).use { it.readBytes() } }.getOrNull()
        ?: if (relative.endsWith(".min.js")) app.assets.open("munim-maplibre/${lib.folder}/${relative.removeSuffix(".min.js")}.js").use { it.readBytes() } else return notFound()
      return response(bytes, mime)
    }
    val cached = File(app.cacheDir, "munim-maps-maplibre/${lib.name}@${lib.version}/$relative")
    if (cached.isFile) return response(cached.readBytes(), mime)
    val connection = URL(baseUrl(app, lib) + relative).openConnection() as HttpURLConnection
    connection.connectTimeout = 15_000
    connection.readTimeout = 60_000
    val bytes = try {
      if (connection.responseCode !in 200..299) return notFound()
      connection.inputStream.use { it.readBytes() }
    } finally {
      connection.disconnect()
    }
    runCatching {
      cached.parentFile?.mkdirs()
      val part = File(cached.path + ".part")
      part.writeBytes(bytes)
      part.renameTo(cached)
    }
    return response(bytes, mime)
  }

  private fun notFound() = WebResourceResponse("text/plain", "utf-8", 404, "Not Found",
    mapOf("Access-Control-Allow-Origin" to "*"), ByteArrayInputStream(ByteArray(0)))

  /** The app's files: Metro's http, file paths, assets, raw and drawable resources (release builds). */
  private fun readResource(uri: String): ByteArray {
    val parsed = Uri.parse(uri)
    return when (parsed.scheme?.lowercase(Locale.ROOT)) {
      // Through munim-maps' disk cache: remote models load once.
      "http", "https" -> com.munimmaps.models.ModelAssets.readBlocking(app, uri)
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
    "json", "geojson" -> "application/json"
    "wasm" -> "application/wasm"
    "png" -> "image/png"
    "jpg", "jpeg" -> "image/jpeg"
    "gif" -> "image/gif"
    "svg" -> "image/svg+xml"
    "webp" -> "image/webp"
    "glb" -> "model/gltf-binary"
    "gltf" -> "model/gltf+json"
    else -> "application/octet-stream"
  }

  // Props

  private var options = JSONObject()
  /** `modelRendering`: `auto` / `native` (three.js in the page) or `overlay` (the Filament layer). */
  private val renderer: String get() = options.optString("modelRendering", "auto")

  override fun setStyleUrl(url: String) = set("styleUrl", url)

  override fun setProviderOptions(options: JSONObject) {
    this.options = options
    set("options", options)
    setModels(allModels)
    setZones(allZones)
    setPaths(allPaths)
  }

  // MarkerView: the React Native views drawn to a PNG, sent as an image marker.
  private var appMarkers: Array<NativeMarker> = emptyArray()
  private val viewMarkers = LinkedHashMap<String, NativeMarker>()

  override fun setMarkers(markers: Array<NativeMarker>) {
    appMarkers = markers
    sendMarkers()
  }

  private fun sendMarkers() = set("markers", appMarkers + viewMarkers.values)

  private fun viewMarker(marker: NativeMarker, image: Bitmap?, previous: NativeMarker?): NativeMarker {
    if (image == null) return marker.copy(style = previous?.style ?: MarkerStyle.IMAGE, imageUri = previous?.imageUri ?: "", imageSize = previous?.imageSize ?: marker.imageSize)
    val png = java.io.ByteArrayOutputStream()
    image.compress(Bitmap.CompressFormat.PNG, 100, png)
    val scale = if (image.density > 0) 160.0 / image.density else 1.0
    return marker.copy(
      style = MarkerStyle.IMAGE,
      imageUri = "data:image/png;base64," + Base64.encodeToString(png.toByteArray(), Base64.NO_WRAP),
      imageSize = maxOf(image.width, image.height) * scale,
      borderWidth = 0.0,
    )
  }

  override fun setViewMarker(marker: NativeMarker, image: Bitmap?) {
    viewMarkers[marker.id] = viewMarker(marker, image, viewMarkers[marker.id])
    sendMarkers()
  }

  override fun setViewMarkerImage(image: Bitmap?, id: String) {
    val marker = viewMarkers[id] ?: return
    viewMarkers[id] = viewMarker(marker, image, marker)
    sendMarkers()
  }

  override fun removeViewMarker(id: String) {
    if (viewMarkers.remove(id) != null) sendMarkers()
  }

  override fun setPolylines(polylines: Array<NativePolyline>) = set("polylines", polylines)
  override fun setPolygons(polygons: Array<NativePolygon>) = set("polygons", polygons)
  override fun setCircles(circles: Array<NativeCircle>) = set("circles", circles)
  override fun setTileOverlays(overlays: Array<NativeTileOverlay>) = set("tileOverlays", overlays)
  override fun setClusterStyles(styles: Array<NativeClusterStyle>) = set("clusterStyles", styles)

  private var allModels: Array<NativeMapModel> = emptyArray()
  private var allZones: Array<NativeMapZone> = emptyArray()
  private var allPaths: Array<NativeMapPath> = emptyArray()

  override fun setModels(models: Array<NativeMapModel>) {
    allModels = models
    val overlay = renderer == "overlay"
    set("models", if (overlay) emptyArray<NativeMapModel>() else models)
    modelLayer.models = if (overlay) models else emptyArray()
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
  override fun setShowsTraffic(shows: Boolean) {
    if (shows) listener?.onError("MapLibre: there is no traffic data in OpenStreetMap; showsTraffic needs a traffic tile source (maplibre.sources)")
  }
  override fun setPointsOfInterest(filter: String) = set("pointsOfInterest", filter)
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

  override fun setCamera(camera: MapCamera, animated: Boolean) =
    call("setCamera", JSONObject().put("camera", MapLibreWebJson.value(camera)).put("animated", animated))

  override fun animateCamera(camera: MapCamera, durationMs: Double, easing: MapCameraEasing) =
    call("animateCamera", JSONObject().put("camera", MapLibreWebJson.value(camera)).put("durationMs", durationMs)
      .put("easing", if (easing == MapCameraEasing.LINEAR) "linear" else "easeInOut"))

  override fun flyCamera(keyframes: Array<CameraKeyframe>, start: Double, loop: Boolean) =
    call("flyCamera", JSONObject().put("keyframes", MapLibreWebJson.value(keyframes)).put("start", start).put("loop", loop))

  override fun stopFlight() = call("stopFlight")

  override fun getVisibleRegion(): MapRegion? = camera?.region ?: camera?.let { MapRegion(it.latitude, it.longitude, 0.0, 0.0) }

  override fun setRegion(region: MapRegion, durationMs: Double) =
    call("setRegion", JSONObject().put("region", MapLibreWebJson.value(region)).put("durationMs", durationMs))

  override fun fitToCoordinates(coordinates: Array<MapCoordinate>, padding: EdgeInsets, animated: Boolean) =
    call("fitToCoordinates", JSONObject().put("coordinates", MapLibreWebJson.value(coordinates)).put("padding", MapLibreWebJson.value(padding)).put("animated", animated))

  override fun fitToMarkers(ids: Set<String>, padding: EdgeInsets, animated: Boolean) =
    call("fitToMarkers", JSONObject().put("ids", JSONArray(ids.toList())).put("padding", MapLibreWebJson.value(padding)).put("animated", animated))

  /** From GL JS's last matrices, at the centre's ground height (the promises ask GL JS itself). */
  override fun pointForCoordinate(coordinate: MapCoordinate): MapPoint? {
    val p = camera?.screenPoint(coordinate.latitude, coordinate.longitude) ?: return null
    return MapPoint(p[0], p[1])
  }

  override fun coordinateForPoint(point: MapPoint): MapCoordinate? {
    val c = camera?.coordinate(point.x, point.y) ?: return null
    return MapCoordinate(c[0], c[1])
  }

  // Asynchronous answers (exact, from GL JS)

  override fun fetchCamera(completion: (MapCamera?) -> Unit) = call("getCamera") { result ->
    val d = result.getOrNull() as? JSONObject
    completion(d?.let { MapCamera(it.optDouble("latitude"), it.optDouble("longitude"), it.optDouble("distance"), it.optDouble("pitch"), it.optDouble("heading")) } ?: getCamera())
  }

  override fun fetchVisibleRegion(completion: (MapRegion?) -> Unit) = call("getVisibleRegion") { result ->
    val d = result.getOrNull() as? JSONObject
    completion(d?.let { MapRegion(it.optDouble("latitude"), it.optDouble("longitude"), it.optDouble("latitudeDelta"), it.optDouble("longitudeDelta")) } ?: getVisibleRegion())
  }

  override fun fetchPoint(coordinate: MapCoordinate, completion: (MapPoint?) -> Unit) =
    call("pointForCoordinate", JSONObject().put("coordinate", MapLibreWebJson.value(coordinate))) { result ->
      val d = result.getOrNull() as? JSONObject
      completion(d?.let { MapPoint(it.optDouble("x"), it.optDouble("y")) } ?: pointForCoordinate(coordinate))
    }

  override fun fetchCoordinate(point: MapPoint, completion: (MapCoordinate?) -> Unit) =
    call("coordinateForPoint", JSONObject().put("point", MapLibreWebJson.value(point))) { result ->
      val d = result.getOrNull() as? JSONObject
      completion(d?.let { MapCoordinate(it.optDouble("latitude"), it.optDouble("longitude")) } ?: coordinateForPoint(point))
    }

  override fun fetchAlignment(completion: (MapAlignmentReport) -> Unit) {
    if (renderer == "overlay") return completion(modelLayer.measureAlignment())
    call("measureAlignment") { result ->
      val d = result.getOrNull() as? JSONObject ?: return@call completion(modelLayer.measureAlignment())
      completion(MapAlignmentReport(
        d.optBoolean("attached"), d.optDouble("modelsMeasured"), d.optDouble("maxErrorPoints"), d.optDouble("meanErrorPoints"),
        d.optDouble("modelsVisibleInRender"), d.optDouble("cameraDistance"), d.optDouble("cameraPitch"), d.optDouble("cameraHeading"),
        d.optDouble("fieldOfViewDegrees")))
    }
  }

  override fun fetchOverlayHit(point: MapPoint, completion: (String) -> Unit) =
    call("overlayAtPoint", JSONObject().put("point", MapLibreWebJson.value(point))) { result ->
      completion(result.getOrNull() as? String ?: "")
    }

  // Methods

  override fun selectMarker(id: String) = call("selectMarker", JSONObject().put("id", id))
  override fun deselectMarker(id: String) = call("deselectMarker", JSONObject().put("id", id))

  private fun writePng(value: Any?, prefix: String): Result<String> = runCatching {
    val bytes = Base64.decode(value as String, Base64.DEFAULT)
    val file = File(app.cacheDir, "$prefix-${System.currentTimeMillis()}.png")
    file.writeBytes(bytes)
    file.absolutePath
  }

  override fun takeSnapshot(width: Double, height: Double, completion: (Result<String>) -> Unit) {
    call("snapshot", JSONObject().put("width", width).put("height", height)) { result ->
      completion(result.fold({ writePng(it, "munim-maplibre") }, { Result.failure(it) }))
    }
  }

  /** Reverse geocoding with Nominatim (`maplibre.nominatimUrl`), light use only, as MapLibre Native. */
  override fun addressForCoordinate(coordinate: MapCoordinate, completion: (Result<MapAddress>) -> Unit) {
    val base = options.optString("nominatimUrl").ifEmpty { "https://nominatim.openstreetmap.org" }
    background.execute {
      val result = runCatching {
        val url = URL("$base/reverse?format=jsonv2&addressdetails=1&lat=${coordinate.latitude}&lon=${coordinate.longitude}")
        val connection = url.openConnection() as HttpURLConnection
        connection.setRequestProperty("User-Agent", "munim-maps/${app.packageName}")
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
    }
  }

  override fun providerCommand(command: String, args: JSONObject, completion: (Result<String>) -> Unit) {
    if (command == "snapshot") {
      // MapLibre Native's offscreen snapshotter: an offscreen GL JS map, written to a PNG file.
      call("snapshotOffscreen", args) { result ->
        completion(result.fold({ v -> writePng(v, "munim-maplibre-snapshot").map { JSONObject.quote(it) } }, { Result.failure(it) }))
      }
      return
    }
    call(command, args) { result ->
      completion(result.map { v ->
        when (v) {
          null, JSONObject.NULL -> "null"
          is String -> JSONObject.quote(v)
          else -> v.toString()
        }
      })
    }
  }

  // MapCameraSource: GL JS's camera for the Filament layer, in pixels.

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

  private var locationListener: LocationListener? = null

  private fun updateLocation() {
    val wanted = showsUserLocation || trackingMode != UserTrackingMode.NONE
    if (!wanted) return stopLocation()
    if (locationListener != null) return
    val fine = app.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
    val coarse = app.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
    if (!fine && !coarse) {
      listener?.onError("MapLibre GL JS: showsUserLocation needs the location permission (ask for it first)")
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
      listener?.onError("MapLibre GL JS: location: ${e.message}")
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

  /** A library the page loads from its own origin. */
  private class Library(val name: String, val version: String, val folder: String, val cdn: String, val metaKey: String)

  companion object {
    private const val HOST = "appassets.androidplatform.net"
    private const val ORIGIN = "https://$HOST"

    /** The MapLibre GL JS version the page is written for (and the bundled copy must be). */
    const val MAPLIBRE_GL_VERSION = "5.24.0"
    /** The three.js version the 3D layer is written for. */
    const val THREE_VERSION = "0.186.1"

    private val MAPLIBRE = Library("maplibre-gl", MAPLIBRE_GL_VERSION, "maplibre-gl",
      "https://cdn.jsdelivr.net/npm/maplibre-gl@$MAPLIBRE_GL_VERSION/dist/", "munimmaps.maplibre_gl_base_url")
    private val THREE = Library("three", THREE_VERSION, "three",
      "https://cdn.jsdelivr.net/npm/three@$THREE_VERSION/", "munimmaps.three_base_url")

    private val bundledCache = HashMap<String, Boolean>()
    private val baseUrls = HashMap<String, String>()

    /** Whether the APK has the library (`munimMaps.maplibreBundled=true`). */
    @Synchronized
    private fun bundled(context: Context, lib: Library): Boolean = bundledCache.getOrPut(lib.name) {
      runCatching { context.assets.list("munim-maplibre/${lib.folder}")?.isNotEmpty() == true }.getOrDefault(false)
    }

    /** jsDelivr at the pinned version, or the manifest's meta-data. */
    @Synchronized
    private fun baseUrl(context: Context, lib: Library): String = baseUrls.getOrPut(lib.name) {
      val custom = runCatching {
        @Suppress("DEPRECATION")
        context.packageManager.getApplicationInfo(context.packageName, PackageManager.GET_META_DATA).metaData?.getString(lib.metaKey)
      }.getOrNull()
      if (!custom.isNullOrEmpty()) (if (custom.endsWith("/")) custom else "$custom/") else lib.cdn
    }
  }
}
