package com.munimmaps.engines.mapbox

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.mapbox.bindgen.Value
import com.mapbox.common.Cancelable
import com.mapbox.common.NetworkRestriction
import com.mapbox.common.OfflineSwitch
import com.mapbox.common.TileRegion
import com.mapbox.common.TileRegionLoadOptions
import com.mapbox.common.TileStore
import com.mapbox.common.TileStoreOptions
import com.mapbox.geojson.Feature
import com.mapbox.geojson.Geometry
import com.mapbox.geojson.Point
import com.mapbox.geojson.Polygon
import com.mapbox.maps.GlyphsRasterizationMode
import com.mapbox.maps.MapboxMap
import com.mapbox.maps.OfflineManager
import com.mapbox.maps.StylePack
import com.mapbox.maps.StylePackLoadOptions
import com.mapbox.maps.TilesetDescriptorOptions
import org.json.JSONArray
import org.json.JSONObject

/**
 * Mapbox offline maps for `MapboxOffline` in JavaScript, no map needed:
 * style packs from the `OfflineManager`, tile regions from the default
 * `TileStore`, with progress as `offline.progress` events and cancellation
 * by id.
 */
internal object MapboxOffline {
  private val main = Handler(Looper.getMainLooper())
  private val downloads = mutableMapOf<String, Cancelable>()
  private val tileStore: TileStore by lazy { TileStore.create() }
  private val offlineManager: OfflineManager by lazy { OfflineManager() }

  fun call(context: Context, method: String, args: JSONObject, emit: (String, Any?) -> Unit, completion: (Result<Any?>) -> Unit) {
    val done: (Result<Any?>) -> Unit = { r -> if (Looper.myLooper() == Looper.getMainLooper()) completion(r) else main.post { completion(r) } }
    try {
      run(method, args, emit, done)
    } catch (error: Throwable) {
      done(Result.failure(error))
    }
  }

  private fun fail(done: (Result<Any?>) -> Unit, message: String) = done(Result.failure(IllegalStateException("Mapbox offline: $message")))

  private fun run(method: String, args: JSONObject, emit: (String, Any?) -> Unit, done: (Result<Any?>) -> Unit) {
    when (method) {
      "offline.loadStylePack" -> {
        val uri = args.optString("styleUri", "").ifEmpty { MapboxStyleController.STANDARD }
        val cancelable = offlineManager.loadStylePack(uri, stylePackOptions(args), { progress ->
          main.post {
            emit("offline.progress", JSONObject()
              .put("id", uri).put("kind", "stylePack")
              .put("requiredResourceCount", progress.requiredResourceCount)
              .put("completedResourceCount", progress.completedResourceCount)
              .put("completedResourceSize", progress.completedResourceSize)
              .put("erroredResourceCount", progress.erroredResourceCount)
              .put("loadedResourceCount", progress.loadedResourceCount)
              .put("loadedResourceSize", progress.loadedResourceSize))
          }
        }) { result ->
          main.post { downloads.remove(uri) }
          val pack = result.value
          if (pack != null) done(Result.success(stylePack(pack))) else fail(done, result.error?.message ?: "style pack failed")
        }
        downloads[uri]?.cancel()
        downloads[uri] = cancelable
      }
      "offline.loadTileRegion" -> {
        val id = args.optString("id", "").ifEmpty { return fail(done, "\"id\" is required") }
        val options = regionOptions(args, forLoad = true) ?: return fail(done, "\"geometry\" or \"bounds\" is required")
        val cancelable = tileStore.loadTileRegion(id, options, { progress ->
          main.post {
            emit("offline.progress", JSONObject()
              .put("id", id).put("kind", "tileRegion")
              .put("requiredResourceCount", progress.requiredResourceCount)
              .put("completedResourceCount", progress.completedResourceCount)
              .put("completedResourceSize", progress.completedResourceSize)
              .put("erroredResourceCount", progress.erroredResourceCount)
              .put("loadedResourceCount", progress.loadedResourceCount)
              .put("loadedResourceSize", progress.loadedResourceSize))
          }
        }) { result ->
          main.post { downloads.remove(id) }
          val region = result.value
          if (region != null) done(Result.success(tileRegion(region))) else fail(done, result.error?.message ?: "tile region failed")
        }
        downloads[id]?.cancel()
        downloads[id] = cancelable
      }
      "offline.cancel" -> {
        val id = args.optString("id", "")
        val cancelable = downloads.remove(id)
        cancelable?.cancel()
        done(Result.success(cancelable != null))
      }
      "offline.estimateTileRegion" -> {
        val options = regionOptions(args, forLoad = false) ?: return fail(done, "\"geometry\" or \"bounds\" is required")
        tileStore.estimateTileRegion("munim-estimate-${System.nanoTime()}", options, { }) { result ->
          val estimate = result.value
          if (estimate != null) {
            done(Result.success(JSONObject().put("storageSize", estimate.storageSize).put("transferSize", estimate.transferSize)
              .put("errorMargin", estimate.errorMargin)))
          } else {
            fail(done, result.error?.message ?: "estimate failed")
          }
        }
      }
      "offline.tileRegions" -> tileStore.getAllTileRegions { result ->
        val list = result.value
        if (list != null) done(Result.success(JSONArray().also { a -> list.forEach { a.put(tileRegion(it)) } }))
        else fail(done, result.error?.message ?: "could not list tile regions")
      }
      "offline.tileRegion" -> tileStore.getTileRegion(args.optString("id")) { result ->
        val region = result.value
        if (region != null) done(Result.success(tileRegion(region))) else fail(done, result.error?.message ?: "no such tile region")
      }
      "offline.tileRegionMetadata" -> tileStore.getTileRegionMetadata(args.optString("id")) { result ->
        val value = result.value
        if (value != null) done(Result.success(MapboxJson.json(value))) else fail(done, result.error?.message ?: "no such tile region")
      }
      "offline.removeTileRegion" -> tileStore.removeTileRegion(args.optString("id")) { result ->
        if (result.error != null) fail(done, result.error!!.message) else done(Result.success(null))
      }
      "offline.stylePacks" -> offlineManager.getAllStylePacks { result ->
        val list = result.value
        if (list != null) done(Result.success(JSONArray().also { a -> list.forEach { a.put(stylePack(it)) } }))
        else fail(done, result.error?.message ?: "could not list style packs")
      }
      "offline.stylePackMetadata" -> offlineManager.getStylePackMetadata(args.optString("styleUri")) { result ->
        val value = result.value
        if (value != null) done(Result.success(MapboxJson.json(value))) else fail(done, result.error?.message ?: "no such style pack")
      }
      "offline.removeStylePack" -> offlineManager.removeStylePack(args.optString("styleUri")) { result ->
        if (result.error != null) fail(done, result.error!!.message) else done(Result.success(null))
      }
      "offline.setTileStoreQuota" -> {
        tileStore.setOption(TileStoreOptions.DISK_QUOTA, Value.valueOf(args.optLong("bytes")))
        done(Result.success(null))
      }
      "offline.setConnected" -> {
        OfflineSwitch.getInstance().setMapboxStackConnected(args.optBoolean("connected", true))
        done(Result.success(null))
      }
      "offline.clearData" -> clearData(done)
      // The token maps use, for MapboxServices in JavaScript.
      "accessToken" -> done(Result.success(com.mapbox.common.MapboxOptions.accessToken))
      else -> done(Result.failure(UnsupportedOperationException("Mapbox has no method \"$method\"")))
    }
  }

  /** Ambient cache, tile regions and style packs. */
  private fun clearData(done: (Result<Any?>) -> Unit) {
    MapboxMap.clearData { result ->
      val error = result.error
      tileStore.getAllTileRegions { regions -> regions.value?.forEach { tileStore.removeTileRegion(it.id) } }
      offlineManager.getAllStylePacks { packs -> packs.value?.forEach { offlineManager.removeStylePack(it.styleURI) } }
      if (error != null) fail(done, error) else done(Result.success(null))
    }
  }

  private fun stylePackOptions(args: JSONObject): StylePackLoadOptions {
    val builder = StylePackLoadOptions.Builder()
      .glyphsRasterizationMode(when (args.optString("glyphsRasterizationMode")) {
        "allGlyphsRasterizedLocally" -> GlyphsRasterizationMode.ALL_GLYPHS_RASTERIZED_LOCALLY
        "noGlyphsRasterizedLocally" -> GlyphsRasterizationMode.NO_GLYPHS_RASTERIZED_LOCALLY
        else -> GlyphsRasterizationMode.IDEOGRAPHS_RASTERIZED_LOCALLY
      })
      .acceptExpired(args.optBoolean("acceptExpired", false))
    args.optJSONObject("metadata")?.let { builder.metadata(MapboxJson.value(it)) }
    return builder.build()
  }

  private fun geometry(args: JSONObject): Geometry? {
    args.optJSONObject("geometry")?.let { geometry ->
      val feature = JSONObject().put("type", "Feature").put("geometry", geometry).put("properties", JSONObject())
      return Feature.fromJson(feature.toString()).geometry()
    }
    val bounds = args.optJSONObject("bounds") ?: return null
    val sw = MapboxJson.point(bounds.optJSONObject("southwest")) ?: return null
    val ne = MapboxJson.point(bounds.optJSONObject("northeast")) ?: return null
    return Polygon.fromLngLats(listOf(listOf(
      Point.fromLngLat(sw.longitude(), sw.latitude()),
      Point.fromLngLat(ne.longitude(), sw.latitude()),
      Point.fromLngLat(ne.longitude(), ne.latitude()),
      Point.fromLngLat(sw.longitude(), ne.latitude()),
      Point.fromLngLat(sw.longitude(), sw.latitude()),
    )))
  }

  private fun regionOptions(args: JSONObject, forLoad: Boolean): TileRegionLoadOptions? {
    val geometry = geometry(args) ?: return null
    val descriptorOptions = TilesetDescriptorOptions.Builder()
      .styleURI(args.optString("styleUri", "").ifEmpty { MapboxStyleController.STANDARD })
      .minZoom(args.optInt("minZoom", 0).coerceIn(0, 22).toByte())
      .maxZoom(args.optInt("maxZoom", 16).coerceIn(0, 22).toByte())
    if (args.has("pixelRatio")) descriptorOptions.pixelRatio(args.optDouble("pixelRatio").toFloat())
    MapboxJson.strings(args.optJSONArray("tilesets")).takeIf { it.isNotEmpty() }?.let { descriptorOptions.tilesets(it) }
    val descriptor = offlineManager.createTilesetDescriptor(descriptorOptions.build())
    val builder = TileRegionLoadOptions.Builder().geometry(geometry).descriptors(listOf(descriptor))
    if (forLoad) {
      builder.acceptExpired(args.optBoolean("acceptExpired", false))
      builder.networkRestriction(when (args.optString("networkRestriction")) {
        "disallowExpensive" -> NetworkRestriction.DISALLOW_EXPENSIVE
        "disallowAll" -> NetworkRestriction.DISALLOW_ALL
        else -> NetworkRestriction.NONE
      })
      args.optJSONObject("metadata")?.let { builder.metadata(MapboxJson.value(it)) }
    }
    return builder.build()
  }

  private fun tileRegion(r: TileRegion): JSONObject = JSONObject()
    .put("id", r.id)
    .put("requiredResourceCount", r.requiredResourceCount)
    .put("completedResourceCount", r.completedResourceCount)
    .put("completedResourceSize", r.completedResourceSize)
    .apply { r.expires?.let { put("expires", it.time) } }

  private fun stylePack(p: StylePack): JSONObject = JSONObject()
    .put("styleUri", p.styleURI)
    .put("requiredResourceCount", p.requiredResourceCount)
    .put("completedResourceCount", p.completedResourceCount)
    .put("completedResourceSize", p.completedResourceSize)
    .put("glyphsRasterizationMode", when (p.glyphsRasterizationMode) {
      GlyphsRasterizationMode.ALL_GLYPHS_RASTERIZED_LOCALLY -> "allGlyphsRasterizedLocally"
      GlyphsRasterizationMode.NO_GLYPHS_RASTERIZED_LOCALLY -> "noGlyphsRasterizedLocally"
      else -> "ideographsRasterizedLocally"
    })
    .apply { p.expires?.let { put("expires", it.time) } }
}
