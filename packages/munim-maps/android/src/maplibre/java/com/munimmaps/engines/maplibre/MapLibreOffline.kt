package com.munimmaps.engines.maplibre

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.geometry.LatLngBounds
import org.maplibre.android.offline.OfflineGeometryRegionDefinition
import org.maplibre.android.offline.OfflineManager
import org.maplibre.android.offline.OfflineRegion
import org.maplibre.android.offline.OfflineRegionError
import org.maplibre.android.offline.OfflineRegionStatus
import org.maplibre.android.offline.OfflineTilePyramidRegionDefinition
import org.maplibre.geojson.Geometry
import org.maplibre.geojson.GeometryCollection
import java.util.concurrent.CopyOnWriteArraySet

/**
 * MapLibre offline packs on Android (`OfflineManager`): tile pyramids or
 * shapes, downloaded into MapLibre's database and used automatically when
 * the network is not there. Packs are named with JSON metadata
 * (`{ name, metadata }`); progress goes to every MapLibre map as
 * `offlineProgress` / `offlineError` events.
 */
internal object MapLibreOffline {
  /** (event name, JSON payload) sinks: the maps on screen. */
  val sinks = CopyOnWriteArraySet<(String, String) -> Unit>()
  private val regions = HashMap<Long, OfflineRegion>()

  private fun emit(name: String, payload: JSONObject) {
    val json = payload.toString()
    sinks.forEach { it(name, json) }
  }

  private fun manager(context: Context) = OfflineManager.getInstance(context.applicationContext)

  private fun info(region: OfflineRegion): JSONObject = try {
    JSONObject(String(region.metadata))
  } catch (_: Exception) {
    JSONObject()
  }

  private fun state(status: OfflineRegionStatus?): String = when {
    status == null -> "unknown"
    status.isComplete -> "complete"
    status.downloadState == OfflineRegion.STATE_ACTIVE -> "active"
    else -> "inactive"
  }

  fun pack(region: OfflineRegion, status: OfflineRegionStatus?): JSONObject {
    val meta = info(region)
    return JSONObject()
      .put("id", region.id.toString())
      .put("name", meta.optString("name"))
      .put("metadata", meta.optJSONObject("metadata") ?: JSONObject())
      .put("state", state(status))
      .put("completedResources", status?.completedResourceCount ?: 0)
      .put("expectedResources", status?.requiredResourceCount ?: 0)
      .put("completedTiles", status?.completedTileCount ?: 0)
      .put("completedBytes", status?.completedResourceSize ?: 0)
      .put("isComplete", status?.isComplete ?: false)
  }

  private fun observe(region: OfflineRegion) {
    regions[region.id] = region
    region.setObserver(object : OfflineRegion.OfflineRegionObserver {
      override fun onStatusChanged(status: OfflineRegionStatus) {
        emit("offlineProgress", pack(region, status))
        if (status.isComplete) region.setDownloadState(OfflineRegion.STATE_INACTIVE)
      }

      override fun onError(error: OfflineRegionError) {
        emit("offlineError", JSONObject().put("id", region.id.toString()).put("reason", error.reason).put("message", error.message))
      }

      override fun mapboxTileCountLimitExceeded(limit: Long) {
        emit("offlineError", JSONObject().put("id", region.id.toString()).put("reason", "tileCountLimit").put("message", "Tile count limit $limit exceeded"))
      }
    })
  }

  private fun withRegion(context: Context, id: String, completion: (Result<String>) -> Unit, block: (OfflineRegion) -> Unit) {
    val key = id.toLongOrNull() ?: return completion(Result.failure(IllegalArgumentException("Unknown pack '$id'")))
    regions[key]?.let { return block(it) }
    manager(context).getOfflineRegion(key, object : OfflineManager.GetOfflineRegionCallback {
      override fun onRegion(region: OfflineRegion) {
        observe(region)
        block(region)
      }

      override fun onRegionNotFound() = completion(Result.failure(IllegalArgumentException("Unknown pack '$id'")))
      override fun onError(error: String) = completion(Result.failure(RuntimeException(error)))
    })
  }

  private fun fileSource(completion: (Result<String>) -> Unit) = object : OfflineManager.FileSourceCallback {
    override fun onSuccess() = completion(Result.success("null"))
    override fun onError(message: String) = completion(Result.failure(RuntimeException(message)))
  }

  fun run(context: Context, command: String, args: JSONObject, styleUrl: String, completion: (Result<String>) -> Unit): Boolean {
    val pixelRatio = context.resources.displayMetrics.density
    when (command) {
      "offlineCreatePack" -> {
        val name = args.optString("name")
        val minZoom = args.optDouble("minZoom", 0.0)
        val maxZoom = args.optDouble("maxZoom", 16.0)
        val style = args.optString("styleUrl").ifEmpty { styleUrl }
        val ideographs = args.optBoolean("includeIdeographs", false)
        val definition = when {
          args.has("geometry") -> {
            val geometry: Geometry = GeometryCollection.fromJson(
              JSONObject().put("type", "GeometryCollection").put("geometries", JSONArray().put(args.getJSONObject("geometry"))).toString())
            OfflineGeometryRegionDefinition(style, geometry, minZoom, maxZoom, pixelRatio, ideographs)
          }
          args.has("bounds") -> {
            val b = args.getJSONObject("bounds")
            val bounds = LatLngBounds.Builder()
              .include(LatLng(b.getDouble("north"), b.getDouble("east")))
              .include(LatLng(b.getDouble("south"), b.getDouble("west")))
              .build()
            OfflineTilePyramidRegionDefinition(style, bounds, minZoom, maxZoom, pixelRatio, ideographs)
          }
          else -> return completion(Result.failure(IllegalArgumentException("offlineCreatePack needs bounds or geometry"))).let { true }
        }
        val metadata = JSONObject().put("name", name).put("metadata", args.optJSONObject("metadata") ?: JSONObject())
        manager(context).createOfflineRegion(definition, metadata.toString().toByteArray(), object : OfflineManager.CreateOfflineRegionCallback {
          override fun onCreate(offlineRegion: OfflineRegion) {
            observe(offlineRegion)
            offlineRegion.setDownloadState(OfflineRegion.STATE_ACTIVE)
            completion(Result.success(pack(offlineRegion, null).put("state", "active").toString()))
          }

          override fun onError(error: String) = completion(Result.failure(RuntimeException(error)))
        })
      }
      "offlineListPacks" -> manager(context).listOfflineRegions(object : OfflineManager.ListOfflineRegionsCallback {
        override fun onList(offlineRegions: Array<OfflineRegion>?) {
          val list = offlineRegions.orEmpty().toList()
          if (list.isEmpty()) return completion(Result.success("[]"))
          val out = arrayOfNulls<JSONObject>(list.size)
          var left = list.size
          list.forEachIndexed { i, region ->
            regions.getOrPut(region.id) { region.also(::observe) }
            region.getStatus(object : OfflineRegion.OfflineRegionStatusCallback {
              override fun onStatus(status: OfflineRegionStatus?) {
                out[i] = pack(region, status)
                if (--left == 0) completion(Result.success(JSONArray(out.toList()).toString()))
              }

              override fun onError(error: String?) {
                out[i] = pack(region, null)
                if (--left == 0) completion(Result.success(JSONArray(out.toList()).toString()))
              }
            })
          }
        }

        override fun onError(error: String) = completion(Result.failure(RuntimeException(error)))
      })
      "offlineResumePack" -> withRegion(context, args.optString("id"), completion) {
        it.setDownloadState(OfflineRegion.STATE_ACTIVE)
        completion(Result.success("null"))
      }
      "offlineSuspendPack" -> withRegion(context, args.optString("id"), completion) {
        it.setDownloadState(OfflineRegion.STATE_INACTIVE)
        completion(Result.success("null"))
      }
      "offlineDeletePack" -> withRegion(context, args.optString("id"), completion) { region ->
        region.setDownloadState(OfflineRegion.STATE_INACTIVE)
        region.delete(object : OfflineRegion.OfflineRegionDeleteCallback {
          override fun onDelete() {
            regions.remove(region.id)
            completion(Result.success("null"))
          }

          override fun onError(error: String) = completion(Result.failure(RuntimeException(error)))
        })
      }
      "offlineInvalidatePack" -> withRegion(context, args.optString("id"), completion) { region ->
        region.invalidate(object : OfflineRegion.OfflineRegionInvalidateCallback {
          override fun onInvalidate() = completion(Result.success("null"))
          override fun onError(error: String) = completion(Result.failure(RuntimeException(error)))
        })
      }
      "offlineSetAmbientCacheSize" -> manager(context).setMaximumAmbientCacheSize(args.optLong("bytes", 50L * 1024 * 1024), fileSource(completion))
      "offlineClearAmbientCache" -> manager(context).clearAmbientCache(fileSource(completion))
      "offlineInvalidateAmbientCache" -> manager(context).invalidateAmbientCache(fileSource(completion))
      "offlineResetDatabase" -> {
        regions.clear()
        manager(context).resetDatabase(fileSource(completion))
      }
      "offlineMergeDatabase" -> manager(context).mergeOfflineRegions(args.optString("path"), object : OfflineManager.MergeOfflineRegionsCallback {
        override fun onMerge(offlineRegions: Array<OfflineRegion>?) {
          val list = offlineRegions.orEmpty().onEach(::observe).map { pack(it, null) }
          completion(Result.success(JSONArray(list).toString()))
        }

        override fun onError(error: String) = completion(Result.failure(RuntimeException(error)))
      })
      else -> return false
    }
    return true
  }
}
