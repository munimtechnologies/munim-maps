@file:OptIn(MapboxExperimental::class)

package com.munimmaps.engines.mapbox

import android.os.Looper
import android.view.animation.AccelerateDecelerateInterpolator
import android.view.animation.AccelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.view.animation.LinearInterpolator
import com.mapbox.bindgen.Value
import com.mapbox.geojson.Feature
import com.mapbox.geojson.Point
import com.mapbox.maps.CameraOptions
import com.mapbox.maps.EdgeInsets
import com.mapbox.maps.FeaturesetFeatureId
import com.mapbox.maps.GeoJSONSourceData
import com.mapbox.maps.LayerPosition
import com.mapbox.maps.MapSnapshotOptions
import com.mapbox.maps.MapboxExperimental
import com.mapbox.maps.QueriedFeature
import com.mapbox.maps.RenderedQueryGeometry
import com.mapbox.maps.RenderedQueryOptions
import com.mapbox.maps.ScreenBox
import com.mapbox.maps.ScreenCoordinate
import com.mapbox.maps.Size
import com.mapbox.maps.SnapshotOverlayOptions
import com.mapbox.maps.Snapshotter
import com.mapbox.maps.SourceQueryOptions
import com.mapbox.maps.interactions.FeatureStateKey
import com.mapbox.maps.interactions.TypedFeaturesetDescriptor
import com.mapbox.maps.plugin.animation.MapAnimationOptions
import com.mapbox.maps.plugin.animation.camera
import com.mapbox.maps.plugin.animation.easeTo
import com.mapbox.maps.plugin.animation.flyTo
import com.mapbox.maps.toCameraOptions
import org.json.JSONArray
import org.json.JSONObject

/**
 * The Mapbox engine's own methods (`mapboxMap(ref)` in JavaScript, through
 * `ref.providerCommand`): queries, feature state, GeoJSON updates, style
 * inspection and changes, Mapbox's camera in zoom levels, the viewport,
 * standalone snapshots. Method names and arguments are `MapboxMapMethods`'.
 */
internal class MapboxCalls(private val engine: MapboxMapEngine) {
  private val density get() = engine.density
  private val map get() = engine.map
  private val snapshotters = mutableSetOf<Snapshotter>()

  fun call(method: String, args: JSONObject, completion: (Result<Any?>) -> Unit) {
    // Callbacks from the SDK may come on another thread; JavaScript gets them on the main thread.
    val done: (Result<Any?>) -> Unit = { result ->
      if (Looper.myLooper() == Looper.getMainLooper()) completion(result) else engine.main.post { completion(result) }
    }
    if (engine.destroyed) {
      done(Result.failure(IllegalStateException("Mapbox: the map is gone")))
      return
    }
    try {
      run(method, args, done)
    } catch (error: Throwable) {
      done(Result.failure(error))
    }
  }

  private fun ok(done: (Result<Any?>) -> Unit, value: Any? = null) = done(Result.success(value))
  private fun fail(done: (Result<Any?>) -> Unit, message: String) = done(Result.failure(IllegalArgumentException("Mapbox: $message")))

  /** null result or an error message from the SDK. */
  private fun <V> finish(done: (Result<Any?>) -> Unit, result: com.mapbox.bindgen.Expected<String, V>, value: (V) -> Any? = { null }) {
    val error = result.error
    if (error != null) fail(done, error) else ok(done, result.value?.let(value))
  }

  private fun requireString(args: JSONObject, key: String): String =
    args.optString(key, "").ifEmpty { throw IllegalArgumentException("Mapbox: \"$key\" is required") }

  private fun run(method: String, args: JSONObject, done: (Result<Any?>) -> Unit) {
    when (method) {
      // Queries
      "queryRenderedFeatures" -> queryRendered(args, done)
      "querySourceFeatures" -> {
        val filter = args.opt("filter")?.let { MapboxJson.value(it) } ?: MapboxJson.value(true)
        map.querySourceFeatures(requireString(args, "sourceId"),
          SourceQueryOptions(MapboxJson.strings(args.optJSONArray("sourceLayerIds")), filter)) { result ->
          finish(done, result) { list -> JSONArray().also { a -> list.forEach { a.put(queried(it.queriedFeature, null)) } } }
        }
      }
      "getClusterExpansionZoom" -> map.getGeoJsonClusterExpansionZoom(requireString(args, "sourceId"), cluster(args)) { result ->
        finish(done, result) { MapboxJson.json(it.value) }
      }
      "getClusterLeaves" -> map.getGeoJsonClusterLeaves(requireString(args, "sourceId"), cluster(args),
        args.optLong("limit", 10), args.optLong("offset", 0)) { result ->
        finish(done, result) { features(it.featureCollection) }
      }
      "getClusterChildren" -> map.getGeoJsonClusterChildren(requireString(args, "sourceId"), cluster(args)) { result ->
        finish(done, result) { features(it.featureCollection) }
      }

      // Feature state
      "setFeatureState" -> {
        val state = args.optJSONObject("state") ?: JSONObject()
        val featureset = descriptor(args.optJSONObject("featureset"))
        if (featureset != null) {
          map.setFeatureState(featureset, featureId(args), JsonFeatureState.build(state)) { finish(done, it) }
        } else {
          val sourceLayer = args.optString("sourceLayerId", "")
          if (sourceLayer.isEmpty()) {
            map.setFeatureState(requireString(args, "sourceId"), requireString(args, "featureId"), MapboxJson.value(state)) { finish(done, it) }
          } else {
            map.setFeatureState(requireString(args, "sourceId"), sourceLayer, requireString(args, "featureId"), MapboxJson.value(state)) { finish(done, it) }
          }
        }
      }
      "getFeatureState" -> {
        val featureset = descriptor(args.optJSONObject("featureset"))
        if (featureset != null) {
          map.getFeatureState(featureset, featureId(args)) { state -> ok(done, MapboxJson.parse(state.asJsonString())) }
        } else {
          val sourceLayer = args.optString("sourceLayerId", "").ifEmpty { null }
          map.getFeatureState(requireString(args, "sourceId"), sourceLayer, requireString(args, "featureId")) { result ->
            finish(done, result) { MapboxJson.json(it) }
          }
        }
      }
      "removeFeatureState" -> {
        val key = args.optString("stateKey", "").ifEmpty { null }
        val featureset = descriptor(args.optJSONObject("featureset"))
        if (featureset != null) {
          map.removeFeatureState(featureset, featureId(args), key?.let { FeatureStateKey.create(it) }) { finish(done, it) }
        } else {
          val sourceLayer = args.optString("sourceLayerId", "").ifEmpty { null }
          map.removeFeatureState(requireString(args, "sourceId"), sourceLayer, requireString(args, "featureId"), key) { finish(done, it) }
        }
      }
      "resetFeatureStates" -> {
        val featureset = descriptor(args.optJSONObject("featureset"))
        if (featureset != null) {
          map.resetFeatureStates(featureset) { finish(done, it) }
        } else {
          val sourceLayer = args.optString("sourceLayerId", "").ifEmpty { null }
          map.resetFeatureStates(requireString(args, "sourceId"), sourceLayer) { finish(done, it) }
        }
      }

      // GeoJSON
      "updateGeoJSONSource" -> {
        val data = args.opt("data") ?: throw IllegalArgumentException("Mapbox: \"data\" is required")
        val text = if (data is String) data else data.toString()
        finish(done, map.setStyleGeoJSONSourceData(requireString(args, "sourceId"), args.optString("dataId", ""), GeoJSONSourceData.valueOf(text)))
      }
      "addGeoJSONSourceFeatures" -> finish(done, map.addGeoJSONSourceFeatures(requireString(args, "sourceId"), args.optString("dataId", ""), featureList(args)))
      "updateGeoJSONSourceFeatures" -> finish(done, map.updateGeoJSONSourceFeatures(requireString(args, "sourceId"), args.optString("dataId", ""), featureList(args)))
      "removeGeoJSONSourceFeatures" -> finish(done, map.removeGeoJSONSourceFeatures(requireString(args, "sourceId"), args.optString("dataId", ""),
        MapboxJson.strings(args.optJSONArray("featureIds"))))

      // Style
      "setLayerProperties" -> finish(done, map.setStyleLayerProperties(requireString(args, "layerId"), MapboxJson.value(args.optJSONObject("properties") ?: JSONObject())))
      "getLayerProperties" -> finish(done, map.getStyleLayerProperties(requireString(args, "layerId"))) { MapboxJson.json(it) }
      "setSourceProperties" -> finish(done, map.setStyleSourceProperties(requireString(args, "sourceId"), MapboxJson.value(args.optJSONObject("properties") ?: JSONObject())))
      "getSourceProperties" -> finish(done, map.getStyleSourceProperties(requireString(args, "sourceId"))) { MapboxJson.json(it) }
      "moveLayer" -> {
        val id = requireString(args, "layerId")
        args.optString("slot", "").takeIf { it.isNotEmpty() }?.let { slot ->
          map.setStyleLayerProperty(id, "slot", Value.valueOf(slot)).error?.let { return fail(done, it) }
        }
        val above = args.optString("aboveId", "").ifEmpty { null }
        val below = args.optString("beforeId", "").ifEmpty { null }
        val at = if (args.has("index")) args.optInt("index") else null
        if (above == null && below == null && at == null) {
          if (args.has("slot")) ok(done) else finish(done, map.moveStyleLayer(id, null))
        } else {
          finish(done, map.moveStyleLayer(id, LayerPosition(above, below, at)))
        }
      }
      "getStyleJson" -> ok(done, map.styleJSON)
      "getLayers" -> ok(done, JSONArray().also { a -> map.styleLayers.forEach { a.put(JSONObject().put("id", it.id).put("type", it.type)) } })
      "getSources" -> ok(done, JSONArray().also { a -> map.styleSources.forEach { a.put(JSONObject().put("id", it.id).put("type", it.type)) } })
      "getSlots" -> ok(done, JSONArray(map.styleSlots))
      "getStyleImports" -> ok(done, JSONArray().also { a -> map.getStyleImports().forEach { a.put(JSONObject().put("id", it.id).put("type", it.type)) } })
      "getStyleImportSchema" -> finish(done, map.getStyleImportSchema(requireString(args, "importId"))) { MapboxJson.json(it) }
      "getStyleImportConfig" -> finish(done, map.getStyleImportConfigProperties(requireString(args, "importId"))) { config ->
        JSONObject().also { o -> config.forEach { (k, v) -> o.put(k, MapboxJson.json(v.value)) } }
      }
      "setStyleImportConfig" -> {
        val config = args.optJSONObject("config") ?: JSONObject()
        val values = HashMap<String, Value>()
        config.keys().forEach { values[it] = MapboxJson.value(config.opt(it)) }
        finish(done, map.setStyleImportConfigProperties(requireString(args, "importId"), values))
      }
      "getFeaturesets" -> ok(done, JSONArray().also { a ->
        map.getFeaturesets().forEach { f ->
          a.put(JSONObject().apply {
            f.featuresetId?.let { put("featuresetId", it) }
            f.importId?.let { put("importId", it) }
            f.layerId?.let { put("layerId", it) }
          })
        }
      })

      // Camera in zoom levels
      "getCameraState" -> {
        val cs = map.cameraState
        ok(done, JSONObject()
          .put("center", MapboxJson.coordinate(cs.center))
          .put("zoom", cs.zoom).put("bearing", cs.bearing).put("pitch", cs.pitch)
          .put("padding", MapboxJson.insetsJson(cs.padding, density)))
      }
      "setCamera" -> {
        engine.stopFlight()
        map.setCamera(cameraOptions(args.optJSONObject("camera")))
        ok(done)
      }
      "easeTo", "flyTo" -> {
        engine.stopFlight()
        val camera = cameraOptions(args.optJSONObject("camera"))
        val builder = MapAnimationOptions.Builder()
        if (args.has("duration")) builder.duration(args.optLong("duration"))
        if (method == "easeTo") {
          builder.interpolator(when (args.optString("curve")) {
            "linear" -> LinearInterpolator()
            "easeIn" -> AccelerateInterpolator()
            "easeOut" -> DecelerateInterpolator()
            else -> AccelerateDecelerateInterpolator()
          })
          map.easeTo(camera, builder.build(), FinishListener { ok(done, it) })
        } else {
          map.flyTo(camera, builder.build(), FinishListener { ok(done, it) })
        }
      }
      "cancelCameraAnimations" -> {
        engine.stopFlight()
        engine.mapView.camera.cancelAllAnimators()
        ok(done)
      }
      "cameraForCoordinates" -> {
        val list = args.optJSONArray("coordinates") ?: JSONArray()
        val points = (0 until list.length()).mapNotNull { MapboxJson.point(list.optJSONObject(it)) }
        if (points.isEmpty()) return fail(done, "\"coordinates\" is required")
        val base = CameraOptions.Builder()
        if (args.has("bearing")) base.bearing(args.optDouble("bearing"))
        if (args.has("pitch")) base.pitch(args.optDouble("pitch"))
        val padding = MapboxJson.insets(args.optJSONObject("padding"), density) ?: EdgeInsets(0.0, 0.0, 0.0, 0.0)
        val maxZoom = if (args.has("maxZoom")) args.optDouble("maxZoom") else null
        ok(done, cameraJson(map.cameraForCoordinates(points, base.build(), padding, maxZoom, null)))
      }
      "getBounds" -> {
        val bounds = map.coordinateBoundsForCamera(map.cameraState.toCameraOptions())
        ok(done, JSONObject().put("southwest", MapboxJson.coordinate(bounds.southwest)).put("northeast", MapboxJson.coordinate(bounds.northeast)))
      }
      "getElevation" -> {
        val elevation = map.getElevation(Point.fromLngLat(args.optDouble("longitude"), args.optDouble("latitude")))
        ok(done, elevation ?: JSONObject.NULL)
      }
      "setViewport" -> engine.controls.setViewport(args) { ok(done, it) }

      // Free camera, limits, tiles, statistics, location override
      "getFreeCamera" -> {
        val free = map.getFreeCameraOptions()
        val location = free.location
        ok(done, JSONObject().put("position", JSONObject()
          .put("latitude", location?.latitude() ?: JSONObject.NULL)
          .put("longitude", location?.longitude() ?: JSONObject.NULL)
          .put("altitude", free.altitude ?: JSONObject.NULL)))
      }
      "setFreeCamera" -> {
        engine.stopFlight()
        val free = map.getFreeCameraOptions()
        args.optJSONObject("position")?.let { p ->
          val point = Point.fromLngLat(p.optDouble("longitude"), p.optDouble("latitude"))
          if (p.has("altitude")) free.setLocation(point, p.optDouble("altitude")) else free.setLocation(point)
        }
        val look = args.optJSONObject("lookAt")
        if (look != null) {
          val point = Point.fromLngLat(look.optDouble("longitude"), look.optDouble("latitude"))
          if (look.has("altitude")) free.lookAtPoint(point, look.optDouble("altitude")) else free.lookAtPoint(point)
        } else if (args.has("pitch") || args.has("bearing")) {
          val cs = map.cameraState
          free.setPitchBearing(args.optDouble("pitch", cs.pitch), args.optDouble("bearing", cs.bearing))
        }
        map.setCamera(free)
        engine.modelLayer.setNeedsRender()
        ok(done)
      }
      "getCameraBounds" -> {
        val b = map.getBounds()
        ok(done, JSONObject()
          .put("bounds", JSONObject().put("southwest", MapboxJson.coordinate(b.bounds.southwest)).put("northeast", MapboxJson.coordinate(b.bounds.northeast)))
          .put("minZoom", b.minZoom).put("maxZoom", b.maxZoom).put("minPitch", b.minPitch).put("maxPitch", b.maxPitch))
      }
      "getStyleDefaultCamera" -> ok(done, cameraJson(map.styleDefaultCamera))
      "tileCover" -> {
        val builder = com.mapbox.maps.TileCoverOptions.Builder()
        if (args.has("tileSize")) builder.tileSize(args.optInt("tileSize").toShort())
        if (args.has("minZoom")) builder.minZoom(args.optInt("minZoom").toByte())
        if (args.has("maxZoom")) builder.maxZoom(args.optInt("maxZoom").toByte())
        if (args.has("roundZoom")) builder.roundZoom(args.optBoolean("roundZoom"))
        ok(done, JSONArray().also { a ->
          map.tileCover(builder.build(), null).forEach { t ->
            a.put(JSONObject().put("z", t.canonical.z.toInt()).put("x", t.canonical.x).put("y", t.canonical.y)
              .put("overscaledZ", t.overscaledZ.toInt()).put("wrap", t.wrap.toInt()))
          }
        })
      }
      "collectPerformanceStatistics" -> {
        val options = com.mapbox.maps.PerformanceStatisticsOptions.Builder()
          .samplerOptions(listOf(com.mapbox.maps.PerformanceSamplerOptions.CUMULATIVE_RENDERING_STATS,
            com.mapbox.maps.PerformanceSamplerOptions.PER_FRAME_RENDERING_STATS))
          .samplingDurationMillis(args.optDouble("durationMs", 1000.0))
          .build()
        map.triggerRepaint()
        map.startPerformanceStatisticsCollection(options) { stats ->
          val c = stats.cumulativeStatistics
          ok(done, JSONObject()
            .put("collectionDurationMillis", stats.collectionDurationMillis)
            .put("mapRenderDuration", JSONObject()
              .put("maxMillis", stats.mapRenderDurationStatistics.maxMillis)
              .put("medianMillis", stats.mapRenderDurationStatistics.medianMillis))
            .put("cumulative", JSONObject()
              .put("drawCalls", c?.drawCalls ?: JSONObject.NULL)
              .put("textureBytes", c?.textureBytes ?: JSONObject.NULL)
              .put("vertexBytes", c?.vertexBytes ?: JSONObject.NULL)))
        }
      }
      "getNativeModels" -> ok(done, engine.nativeModels.describe())
      "setLocationOverride" -> {
        engine.controls.setLocationOverride(args)
        ok(done)
      }
      "clearLocationOverride" -> {
        engine.controls.clearLocationOverride()
        ok(done)
      }

      // Rendering
      "snapshot" -> snapshot(args, done)
      "triggerRepaint" -> {
        map.triggerRepaint()
        ok(done)
      }
      "reduceMemoryUse" -> {
        map.reduceMemoryUse()
        ok(done)
      }
      else -> done(Result.failure(UnsupportedOperationException("Mapbox has no method \"$method\"")))
    }
  }

  // Helpers

  private fun cluster(args: JSONObject): Feature {
    val json = args.optJSONObject("cluster") ?: throw IllegalArgumentException("Mapbox: \"cluster\" (a feature) is required")
    return MapboxJson.featureFrom(json)
  }

  private fun features(list: List<Feature>?): JSONArray = JSONArray().also { a -> list?.forEach { a.put(MapboxJson.feature(it)) } }

  private fun featureList(args: JSONObject): List<Feature> {
    val list = args.optJSONArray("features") ?: return emptyList()
    return (0 until list.length()).mapNotNull { list.optJSONObject(it)?.let(MapboxJson::featureFrom) }
  }

  /** `{ featuresetId, importId }` or `{ layerId }`. */
  private fun descriptor(json: JSONObject?): TypedFeaturesetDescriptor<com.mapbox.maps.interactions.FeatureState, com.mapbox.maps.interactions.FeaturesetFeature<com.mapbox.maps.interactions.FeatureState>>? {
    json ?: return null
    json.optString("layerId", "").takeIf { it.isNotEmpty() }?.let { return TypedFeaturesetDescriptor.Layer(it) }
    val id = json.optString("featuresetId", "").ifEmpty { return null }
    return TypedFeaturesetDescriptor.Featureset(id, json.optString("importId", "").ifEmpty { null })
  }

  private fun featureId(args: JSONObject) =
    FeaturesetFeatureId(requireString(args, "featureId"), args.optString("featureNamespace", "").ifEmpty { null })

  private fun queried(q: QueriedFeature, layers: List<String>?): JSONObject {
    val out = JSONObject()
      .put("feature", MapboxJson.feature(q.feature))
      .put("source", q.source)
      .put("state", MapboxJson.json(q.state))
    q.sourceLayer?.let { out.put("sourceLayer", it) }
    layers?.let { out.put("layers", JSONArray(it)) }
    q.featuresetFeatureId?.let { id ->
      out.put("featureId", id.featureId)
      id.featureNamespace?.let { out.put("featureNamespace", it) }
    }
    return out
  }

  private fun queryRendered(args: JSONObject, done: (Result<Any?>) -> Unit) {
    val geometry = when {
      args.optJSONObject("point") != null -> RenderedQueryGeometry(MapboxJson.screen(args.optJSONObject("point"), density)!!)
      args.optJSONObject("box") != null -> {
        val b = args.getJSONObject("box")
        RenderedQueryGeometry(ScreenBox(
          ScreenCoordinate(minOf(b.optDouble("x1"), b.optDouble("x2")) * density, minOf(b.optDouble("y1"), b.optDouble("y2")) * density),
          ScreenCoordinate(maxOf(b.optDouble("x1"), b.optDouble("x2")) * density, maxOf(b.optDouble("y1"), b.optDouble("y2")) * density)))
      }
      else -> RenderedQueryGeometry(ScreenBox(ScreenCoordinate(0.0, 0.0),
        ScreenCoordinate(engine.mapView.width.toDouble(), engine.mapView.height.toDouble())))
    }
    val filter = args.opt("filter")?.let { MapboxJson.value(it) }
    val featureset = descriptor(args.optJSONObject("featureset"))
    if (featureset != null) {
      map.queryRenderedFeatures(featureset, geometry, filter) { list ->
        ok(done, JSONArray().also { a ->
          list.forEach { f ->
            val target = JSONObject()
            when (val d = f.descriptor) {
              is TypedFeaturesetDescriptor.Featureset -> {
                target.put("featuresetId", d.featuresetId)
                d.importId?.let { target.put("importId", it) }
              }
              is TypedFeaturesetDescriptor.Layer -> target.put("layerId", d.layerId)
              else -> {}
            }
            a.put(JSONObject()
              .put("feature", MapboxJson.feature(f.originalFeature))
              .put("source", "")
              .put("state", MapboxJson.parse(f.state.asJsonString()))
              .put("featureset", target)
              .apply {
                f.id?.let { id ->
                  put("featureId", id.featureId)
                  id.featureNamespace?.let { put("featureNamespace", it) }
                }
              })
          }
        })
      }
      return
    }
    val layerIds = args.optJSONArray("layerIds")?.let { MapboxJson.strings(it) }
    map.queryRenderedFeatures(geometry, RenderedQueryOptions(layerIds, filter)) { result ->
      finish(done, result) { list ->
        JSONArray().also { a ->
          list.forEach { r ->
            val item = queried(r.queriedFeature, r.layers)
            r.targets?.firstOrNull()?.featureset?.let { d ->
              item.put("featureset", JSONObject().apply {
                d.featuresetId?.let { put("featuresetId", it) }
                d.importId?.let { put("importId", it) }
                d.layerId?.let { put("layerId", it) }
              })
            }
            a.put(item)
          }
        }
      }
    }
  }

  private fun cameraOptions(json: JSONObject?): CameraOptions {
    val b = CameraOptions.Builder()
    json ?: return b.build()
    MapboxJson.point(json.optJSONObject("center"))?.let { b.center(it) }
    if (json.has("zoom")) b.zoom(json.optDouble("zoom"))
    if (json.has("bearing")) b.bearing(json.optDouble("bearing"))
    if (json.has("pitch")) b.pitch(json.optDouble("pitch"))
    MapboxJson.insets(json.optJSONObject("padding"), density)?.let { b.padding(it) }
    MapboxJson.screen(json.optJSONObject("anchor"), density)?.let { b.anchor(it) }
    return b.build()
  }

  private fun cameraJson(c: CameraOptions): JSONObject = JSONObject().apply {
    c.center?.let { put("center", MapboxJson.coordinate(it)) }
    c.zoom?.let { put("zoom", it) }
    c.bearing?.let { put("bearing", it) }
    c.pitch?.let { put("pitch", it) }
    c.padding?.let { put("padding", MapboxJson.insetsJson(it, density)) }
  }

  /** A PNG from Mapbox's standalone `Snapshotter`. */
  private fun snapshot(args: JSONObject, done: (Result<Any?>) -> Unit) {
    val width = if (args.has("width")) args.optDouble("width") else engine.mapView.width / density
    val height = if (args.has("height")) args.optDouble("height") else engine.mapView.height / density
    if (width < 1 || height < 1) return fail(done, "snapshot needs a size")
    val pixelRatio = if (args.has("pixelRatio")) args.optDouble("pixelRatio").toFloat() else density.toFloat()
    val options = MapSnapshotOptions.Builder().size(Size(width.toFloat(), height.toFloat())).pixelRatio(pixelRatio).build()
    val overlay = SnapshotOverlayOptions(args.optBoolean("showsLogo", true), args.optBoolean("showsAttribution", true))
    val snapshotter = Snapshotter(engine.context, options, overlay)
    snapshotters.add(snapshotter)
    val styleJson = args.opt("styleJson")?.let { if (it is JSONObject) it.toString() else it as? String }
    val styleUrl = args.optString("styleUrl", "")
    when {
      styleJson != null -> snapshotter.setStyleJson(styleJson)
      styleUrl.isNotEmpty() -> snapshotter.setStyleUri(styleUrl)
      else -> {
        val uri = map.styleURI
        if (uri.isNotEmpty()) snapshotter.setStyleUri(uri) else snapshotter.setStyleJson(map.styleJSON)
      }
    }
    snapshotter.setCamera(args.optJSONObject("camera")?.let { cameraOptions(it) } ?: map.cameraState.toCameraOptions())
    snapshotter.start(null) { bitmap, error ->
      snapshotters.remove(snapshotter)
      if (bitmap == null) {
        snapshotter.destroy()
        fail(done, error ?: "snapshot failed")
        return@start
      }
      MapboxMapEngine.executor.execute {
        val result = runCatching { MapboxMapEngine.writePng(engine.context, bitmap, "munim-maps-mapbox-snapshot") }
        engine.main.post {
          snapshotter.destroy()
          done(result.map { it })
        }
      }
    }
  }

  fun destroy() {
    snapshotters.forEach { runCatching { it.destroy() } }
    snapshotters.clear()
  }
}
