package com.munimmaps.models

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.google.android.filament.Engine
import com.google.android.filament.Scene
import com.munimmaps.engine.MapCameraState
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.zip.GZIPInputStream
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.asinh
import kotlin.math.atan
import kotlin.math.floor
import kotlin.math.sinh
import kotlin.math.tan

/**
 * Hides models behind buildings (`occlusion="buildings"`): the Android twin
 * of iOS's `BuildingOccluder`.
 *
 * Map engines do not share their depth buffer with the 3D layer, so a car
 * behind a building would be drawn in front of it. This loads building
 * footprints and heights from vector tiles (the OpenMapTiles `building`
 * layer, by default from OpenFreeMap) around the camera and draws their walls
 * into the depth buffer only: nothing shows, but models behind them are
 * hidden. Avatars, labels and stems are drawn on top, so people inside
 * buildings still show.
 */
internal class BuildingOccluder(
  context: Context,
  private val engine: Engine,
  private val scene: Scene,
  private val materials: ModelMaterials,
) {
  var enabled = false
    set(value) {
      field = value
      if (!value) {
        cancelAll()
        for (tile in tiles.values) tile.part?.show(scene, false)
      }
    }

  /** `{z}/{x}/{y}` template; empty uses OpenFreeMap. */
  var tileUrlTemplate = ""
    set(value) {
      if (field == value) return
      field = value
      resolvedTemplate = null
      clear()
    }

  var onError: ((String) -> Unit)? = null
  /** A tile finished loading. */
  var onChange: (() -> Unit)? = null

  private class Tile(val latitude: Double, val longitude: Double) {
    var part: MeshPart? = null
    var task: Future<*>? = null
    var loaded = false
  }

  private val tiles = HashMap<String, Tile>()
  private var resolvedTemplate: String? = null
  private var resolving = false
  private var reportedError = false
  private val main = Handler(Looper.getMainLooper())
  private val cacheDirectory = File(context.applicationContext.cacheDir, "munim-maps-buildings")
  private var destroyed = false

  /** Loads tiles around the camera and moves the loaded ones into place. */
  fun update(state: MapCameraState) {
    if (!enabled) return
    val active = !state.globe && state.distance < MAX_DISTANCE
    if (active) visibleRegion(state)?.let { requestTiles(it) }
    for (tile in tiles.values) {
      val part = tile.part ?: continue
      part.show(scene, active && tile.loaded)
      if (!active || !tile.loaded) continue
      val p = state.scenePosition(tile.latitude, tile.longitude, 0.0)
      part.setTransform(floatArrayOf(1f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 1f, 0f, p[0].toFloat(), p[1].toFloat(), p[2].toFloat(), 1f))
    }
  }

  /** The ground under the screen's corners (or the horizon), as south, west, north, east. */
  private fun visibleRegion(state: MapCameraState): DoubleArray? {
    var south = 90.0
    var north = -90.0
    var west = 180.0
    var east = -180.0
    var any = false
    val points = listOf(0.0 to 0.0, state.width to 0.0, 0.0 to state.height, state.width to state.height,
      state.width / 2 to state.height / 2, state.width / 2 to 0.0)
    val eye = state.position
    for ((x, y) in points) {
      val ray = state.ray(x, y)
      // Where the ray meets the ground, but never more than 3 km out
      // (towards the horizon buildings are too small to matter).
      val farthest = 3_000.0 / MapCameraState.norm(ray)
      val t = if (ray[1] < -1e-6) minOf(-eye[1] / ray[1], farthest) else farthest
      val (latitude, longitude) = groundCoordinate(state, eye[0] + ray[0] * t, eye[2] + ray[2] * t)
      south = minOf(south, latitude); north = maxOf(north, latitude)
      west = minOf(west, longitude); east = maxOf(east, longitude)
      any = true
    }
    return if (any) doubleArrayOf(south, west, north, east) else null
  }

  private fun requestTiles(region: DoubleArray) {
    val template = resolvedTemplateOrResolve() ?: return
    val latPad = (region[2] - region[0]) * 0.1
    val lonPad = (region[3] - region[1]) * 0.1
    val (x0, y0) = tileIndex(minOf(85.0, region[2] + latPad), region[1] - lonPad)
    val (x1, y1) = tileIndex(maxOf(-85.0, region[0] - latPad), region[3] + lonPad)
    val centerLat = (region[0] + region[2]) / 2
    val centerLon = (region[1] + region[3]) / 2
    val (cx, cy) = tileIndex(centerLat, centerLon)
    val wanted = mutableListOf<Pair<Int, Int>>()
    for (x in minOf(x0, x1)..maxOf(x0, x1)) for (y in minOf(y0, y1)..maxOf(y0, y1)) wanted.add(x to y)
    // Nearest first, and never too many.
    wanted.sortBy { abs(it.first - cx) + abs(it.second - cy) }
    val keep = wanted.take(MAX_TILES)
    val keys = keep.map { "${it.first}/${it.second}" }.toSet()
    for (key in tiles.keys.toList()) {
      if (key !in keys) tiles.remove(key)?.let { drop(it) }
    }
    for ((x, y) in keep) if (tiles["$x/$y"] == null) load(x, y, template)
  }

  private fun load(x: Int, y: Int, template: String) {
    val key = "$x/$y"
    val (latitude, longitude) = coordinate(x.toDouble(), y.toDouble())
    val tile = Tile(latitude, longitude)
    tiles[key] = tile
    val url = template.replace("{z}", "$ZOOM").replace("{x}", "$x").replace("{y}", "$y")
    val cache = File(cacheDirectory, "${template.hashCode().toLong() and 0xffffffffL}-$ZOOM-$x-$y.pbf")
    tile.task = executor.submit {
      val result = runCatching {
        val bytes = if (cache.exists()) cache.readBytes() else download(url).also {
          cacheDirectory.mkdirs()
          runCatching { cache.writeBytes(it) }
        }
        wallMesh(bytes, x, y)
      }
      main.post {
        if (destroyed || tiles[key] !== tile) return@post
        result.onFailure {
          if (it is InterruptedException) return@post
          tiles.remove(key)
          reportOnce("Could not load building tile $key: ${it.message}")
        }
        result.onSuccess { mesh ->
          tile.loaded = true
          if (mesh != null) {
            tile.part = MeshPart(engine, mesh, materials.unlit(blend = false, occluder = true, label = "munim-buildings"),
              channel = 1, priority = 0)
          }
          onChange?.invoke()
        }
      }
    }
  }

  private fun download(url: String): ByteArray {
    val connection = URL(url).openConnection() as HttpURLConnection
    connection.connectTimeout = 15_000
    connection.readTimeout = 30_000
    connection.setRequestProperty("User-Agent", "munim-maps (https://github.com/munimtechnologies/munim-maps)")
    try {
      val status = connection.responseCode
      if (status !in 200..299) error("HTTP $status")
      return connection.inputStream.use { it.readBytes() }
    } finally {
      connection.disconnect()
    }
  }

  /** OpenFreeMap's tile URLs are versioned, so read the current one from its TileJSON once. */
  private fun resolvedTemplateOrResolve(): String? {
    if (tileUrlTemplate.isNotEmpty()) return tileUrlTemplate
    resolvedTemplate?.let { return it }
    if (resolving) return null
    resolving = true
    executor.execute {
      val result = runCatching {
        val json = JSONObject(String(download(OPENFREEMAP_TILEJSON)))
        json.getJSONArray("tiles").getString(0)
      }
      main.post {
        resolving = false
        result.onSuccess {
          resolvedTemplate = it
          onChange?.invoke()
        }
        result.onFailure { reportOnce("Could not read the building tile index: ${it.message}") }
      }
    }
    return null
  }

  private fun reportOnce(message: String) {
    if (reportedError) return
    reportedError = true
    onError?.invoke(message)
  }

  private fun drop(tile: Tile) {
    tile.task?.cancel(true)
    tile.part?.destroy(scene)
    tile.part = null
  }

  private fun cancelAll() {
    for (tile in tiles.values) tile.task?.cancel(true)
  }

  private fun clear() {
    for (tile in tiles.values) drop(tile)
    tiles.clear()
  }

  fun destroy() {
    destroyed = true
    clear()
  }

  companion object {
    private const val ZOOM = 14
    /** Beyond this camera distance buildings are too small to matter. */
    private const val MAX_DISTANCE = 9_000.0
    private const val MAX_TILES = 9
    private const val OPENFREEMAP_TILEJSON = "https://tiles.openfreemap.org/planet"
    private val executor = Executors.newFixedThreadPool(2)

    fun tileIndex(latitude: Double, longitude: Double): Pair<Int, Int> {
      val n = (1 shl ZOOM).toDouble()
      val x = (longitude + 180) / 360 * n
      val lat = latitude * PI / 180
      val y = (1 - asinh(tan(lat)) / PI) / 2 * n
      return floor(x).toInt() to floor(y).toInt()
    }

    fun coordinate(x: Double, y: Double): Pair<Double, Double> {
      val n = (1 shl ZOOM).toDouble()
      val longitude = x / n * 360 - 180
      val latitude = atan(sinh(PI * (1 - 2 * y / n))) * 180 / PI
      return latitude to longitude
    }

    /** Coordinate of a point on the flat map's ground, in scene metres. */
    fun groundCoordinate(state: MapCameraState, x: Double, z: Double): Pair<Double, Double> {
      val scale = MapCameraState.metersPerMapPoint(state.latitude)
      val (cx, cy) = MapCameraState.mapPoint(state.latitude, state.longitude)
      return MapCameraState.coordinate(cx + x / scale, cy + z / scale)
    }

    /** Walls for every building ring in the tile, in metres east and south of its north-west corner. */
    fun wallMesh(tileData: ByteArray, x: Int, y: Int): MeshData? {
      val buildings = VectorTile.buildings(tileData)
      if (buildings.isEmpty()) return null
      val (lat0, lon0) = coordinate(x.toDouble(), y.toDouble())
      val (lat1, lon1) = coordinate(x + 1.0, y + 1.0)
      val (centerLat, _) = coordinate(x + 0.5, y + 0.5)
      val origin = MapCameraState.mapPoint(lat0, lon0)
      val far = MapCameraState.mapPoint(lat1, lon1)
      val metersPerPoint = MapCameraState.metersPerMapPoint(centerLat)
      val mesh = MeshData()
      for (building in buildings) {
        if (building.hide3D || building.height <= building.minHeight) continue
        val extent = building.extent.toDouble()
        val top = building.height.toFloat()
        val bottom = building.minHeight.toFloat()
        for (ring in building.rings) {
          if (ring.size < 6) continue
          val count = ring.size / 2
          val points = FloatArray(count * 2) { i ->
            val k = i / 2
            if (i % 2 == 0) ((far.first - origin.first) * ring[k * 2] / extent * metersPerPoint).toFloat()
            else ((far.second - origin.second) * ring[k * 2 + 1] / extent * metersPerPoint).toFloat()
          }
          for (i in 0 until count) {
            val j = (i + 1) % count
            val ax = points[i * 2]
            val az = points[i * 2 + 1]
            val bx = points[j * 2]
            val bz = points[j * 2 + 1]
            if (ax == bx && az == bz) continue
            val v = mesh.vertex(ax, bottom, az)
            mesh.vertex(bx, bottom, bz)
            mesh.vertex(bx, top, bz)
            mesh.vertex(ax, top, az)
            mesh.quad(v, v + 1, v + 2, v + 3)
          }
        }
      }
      return mesh.takeIf { it.vertexCount > 0 }
    }
  }
}

/** The parts of a Mapbox Vector Tile that building occlusion needs. */
internal object VectorTile {
  class Building(
    val height: Double,
    val minHeight: Double,
    /** Outlines whose parts are drawn separately. */
    val hide3D: Boolean,
    val extent: Int,
    /** Each ring as x, y pairs in tile units. */
    val rings: List<IntArray>,
  )

  private class Reader(val bytes: ByteArray, var position: Int, val end: Int) {
    val atEnd get() = position >= end

    fun varint(): Long {
      var result = 0L
      var shift = 0
      while (true) {
        if (position >= end) error("truncated")
        val byte = bytes[position++].toInt() and 0xff
        result = result or ((byte and 0x7f).toLong() shl shift)
        if (byte < 0x80) return result
        shift += 7
        if (shift > 63) error("truncated")
      }
    }

    fun key(): Pair<Int, Int> {
      val key = varint()
      return (key ushr 3).toInt() to (key and 7).toInt()
    }

    fun lengthDelimited(): Reader {
      val length = varint().toInt()
      if (length < 0 || position + length > end) error("truncated")
      val reader = Reader(bytes, position, position + length)
      position += length
      return reader
    }

    fun fixed32(): Int {
      if (position + 4 > end) error("truncated")
      var v = 0
      for (i in 0..3) v = v or ((bytes[position + i].toInt() and 0xff) shl (8 * i))
      position += 4
      return v
    }

    fun fixed64(): Long {
      if (position + 8 > end) error("truncated")
      var v = 0L
      for (i in 0..7) v = v or ((bytes[position + i].toLong() and 0xff) shl (8 * i))
      position += 8
      return v
    }

    fun string() = String(bytes, position, end - position, Charsets.UTF_8)

    fun skip(wire: Int) {
      when (wire) {
        0 -> varint()
        1 -> fixed64()
        2 -> lengthDelimited()
        5 -> fixed32()
        else -> error("bad wire type")
      }
    }
  }

  /** Polygons of the `building` layer with their heights in metres. */
  fun buildings(data: ByteArray): List<Building> {
    var bytes = data
    if (bytes.size > 2 && bytes[0] == 0x1f.toByte() && bytes[1] == 0x8b.toByte()) {
      bytes = GZIPInputStream(ByteArrayInputStream(bytes)).use { it.readBytes() }
    }
    val result = mutableListOf<Building>()
    val reader = Reader(bytes, 0, bytes.size)
    while (!reader.atEnd) {
      val (field, wire) = reader.key()
      if (field != 3 || wire != 2) {
        reader.skip(wire)
        continue
      }
      decodeLayer(reader.lengthDelimited())?.let { result.addAll(it) }
    }
    return result
  }

  private fun decodeLayer(reader: Reader): List<Building>? {
    var name = ""
    val keys = mutableListOf<String>()
    val values = mutableListOf<Double?>()
    val features = mutableListOf<Reader>()
    var extent = 4096
    while (!reader.atEnd) {
      val (field, wire) = reader.key()
      when {
        field == 1 && wire == 2 -> name = reader.lengthDelimited().string()
        field == 2 && wire == 2 -> features.add(reader.lengthDelimited())
        field == 3 && wire == 2 -> keys.add(reader.lengthDelimited().string())
        field == 4 && wire == 2 -> values.add(decodeValue(reader.lengthDelimited()))
        field == 5 && wire == 0 -> extent = reader.varint().toInt()
        else -> reader.skip(wire)
      }
      // Skip other layers without decoding their features.
      if (field == 1 && name != "building") return null
    }
    if (name != "building") return null
    val heightKey = keys.indexOf("render_height")
    val minKey = keys.indexOf("render_min_height")
    val hideKey = keys.indexOf("hide_3d")
    return features.mapNotNull { feature ->
      var tags = LongArray(0)
      var type = 0
      var geometry = LongArray(0)
      while (!feature.atEnd) {
        val (field, wire) = feature.key()
        when {
          field == 2 && wire == 2 -> tags = packed(feature.lengthDelimited())
          field == 3 && wire == 0 -> type = feature.varint().toInt()
          field == 4 && wire == 2 -> geometry = packed(feature.lengthDelimited())
          else -> feature.skip(wire)
        }
      }
      if (type != 3) return@mapNotNull null // polygons only
      var height = 10.0
      var minHeight = 0.0
      var hide3D = false
      var i = 0
      while (i + 1 < tags.size) {
        val key = tags[i].toInt()
        val value = values.getOrNull(tags[i + 1].toInt())
        if (value != null) {
          if (key == heightKey) height = value
          if (key == minKey) minHeight = value
          if (key == hideKey) hide3D = value != 0.0
        }
        i += 2
      }
      Building(height, minHeight, hide3D, extent, rings(geometry))
    }
  }

  /** Numbers only; strings become null. Booleans are 0 or 1. */
  private fun decodeValue(reader: Reader): Double? {
    var value: Double? = null
    while (!reader.atEnd) {
      val (field, wire) = reader.key()
      value = when {
        field == 2 && wire == 5 -> java.lang.Float.intBitsToFloat(reader.fixed32()).toDouble()
        field == 3 && wire == 1 -> java.lang.Double.longBitsToDouble(reader.fixed64())
        field == 4 && wire == 0 -> reader.varint().toDouble()
        field == 5 && wire == 0 -> reader.varint().toDouble()
        field == 6 && wire == 0 -> {
          val raw = reader.varint()
          ((raw ushr 1) xor -(raw and 1)).toDouble()
        }
        field == 7 && wire == 0 -> if (reader.varint() != 0L) 1.0 else 0.0
        else -> {
          reader.skip(wire)
          value
        }
      }
    }
    return value
  }

  /** MoveTo / LineTo / ClosePath commands to closed rings. */
  private fun rings(commands: LongArray): List<IntArray> {
    val rings = mutableListOf<IntArray>()
    var ring = mutableListOf<Int>()
    var x = 0
    var y = 0
    var i = 0
    fun zigzag(v: Long): Int = ((v ushr 1) xor -(v and 1)).toInt()
    while (i < commands.size) {
      val command = (commands[i] and 0x7).toInt()
      val count = (commands[i] ushr 3).toInt()
      i += 1
      when (command) {
        1, 2 -> {
          if (command == 1 && ring.isNotEmpty()) {
            rings.add(ring.toIntArray())
            ring = mutableListOf()
          }
          repeat(count) {
            if (i + 1 < commands.size) {
              x += zigzag(commands[i])
              y += zigzag(commands[i + 1])
              ring.add(x)
              ring.add(y)
              i += 2
            }
          }
        }
        7 -> if (ring.isNotEmpty()) {
          rings.add(ring.toIntArray())
          ring = mutableListOf()
        }
        else -> return rings
      }
    }
    if (ring.isNotEmpty()) rings.add(ring.toIntArray())
    return rings
  }

  private fun packed(reader: Reader): LongArray {
    val result = ArrayList<Long>()
    while (!reader.atEnd) result.add(reader.varint())
    return result.toLongArray()
  }
}
