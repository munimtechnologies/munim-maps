package com.munimmaps.models

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.zip.Inflater
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.asinh
import kotlin.math.floor
import kotlin.math.tan

/**
 * Ground height above sea level anywhere on Earth, from terrain tiles: the
 * Android twin of iOS's `MunimTerrain` (ios/Core/TerrainElevation.swift).
 *
 * Reads the free, public Terrarium elevation tiles on AWS (PNG tiles where
 * `height = R * 256 + G + B / 256 - 32768` metres) at zoom 14 with bilinear
 * sampling. Tiles are kept in memory and in the app's cache folder, and a
 * tile is only ever fetched once at a time. Heights are above mean sea level;
 * under the sea they are the sea floor.
 */
object MunimTerrain {
  /** `{z}/{x}/{y}` template of Terrarium-encoded PNG tiles. */
  @Volatile
  var tileUrlTemplate = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"

  const val ZOOM = 14
  const val TILE_SIZE = 256
  private const val MEMORY_TILES = 64
  /** A failed tile is not asked for again until this many milliseconds later. */
  private const val RETRY_INTERVAL = 30_000L

  private data class TileKey(val z: Int, val x: Int, val y: Int)

  private val lock = Any()
  private val tiles = HashMap<TileKey, FloatArray>()
  private val lastUsed = HashMap<TileKey, Long>()
  private var useCounter = 0L
  private val waiting = HashMap<TileKey, MutableList<(Result<FloatArray>) -> Unit>>()
  private val failedAt = HashMap<TileKey, Long>()
  private val executor = Executors.newFixedThreadPool(3)
  private val main = Handler(Looper.getMainLooper())
  @Volatile
  private var cacheDirectory: File? = null

  /** Called on the main thread whenever a tile loads (true) or fails (false, with why). */
  private val listeners = mutableListOf<(Boolean, String?) -> Unit>()

  fun init(context: Context) {
    if (cacheDirectory == null) cacheDirectory = File(context.applicationContext.cacheDir, "munim-maps-terrain")
  }

  fun addListener(listener: (Boolean, String?) -> Unit) = synchronized(listeners) { listeners.add(listener) }

  fun removeListener(listener: (Boolean, String?) -> Unit) = synchronized(listeners) { listeners.remove(listener) }

  // Public API

  /** Ground heights above sea level in metres, one per coordinate; fails if a tile cannot load. */
  fun groundElevations(coordinates: List<Pair<Double, Double>>, completion: (Result<DoubleArray>) -> Unit) {
    val keys = coordinates.flatMap { tileKeys(it.first, it.second) }.toSet()
    if (keys.isEmpty()) return completion(Result.success(DoubleArray(coordinates.size) { Double.NaN }))
    val loaded = HashMap<TileKey, FloatArray>()
    var failure: Throwable? = null
    var remaining = keys.size
    for (key in keys) {
      load(key, retryFailed = true) { result ->
        val done = synchronized(loaded) {
          result.onSuccess { loaded[key] = it }.onFailure { failure = failure ?: it }
          remaining -= 1
          remaining == 0
        }
        if (done) {
          failure?.let { return@load completion(Result.failure(it)) }
          completion(Result.success(DoubleArray(coordinates.size) { i ->
            sample(coordinates[i].first, coordinates[i].second) { loaded[it] } ?: Double.NaN
          }))
        }
      }
    }
  }

  /**
   * The ground height at a coordinate if its tiles are in memory; otherwise
   * null, and the tiles are requested (listeners hear when they load). Cheap
   * enough to call every frame.
   */
  fun cachedGroundElevation(latitude: Double, longitude: Double): Double? {
    val value = synchronized(lock) {
      sample(latitude, longitude) { key ->
        tiles[key]?.also {
          useCounter += 1
          lastUsed[key] = useCounter
        }
      }
    }
    if (value == null) prefetch(listOf(latitude to longitude))
    return value
  }

  /** Starts loading the tiles under these coordinates, at most [limit] tiles. */
  fun prefetch(coordinates: List<Pair<Double, Double>>, limit: Int = 32) {
    val keys = LinkedHashSet<TileKey>()
    for ((latitude, longitude) in coordinates) {
      keys.addAll(tileKeys(latitude, longitude))
      if (keys.size >= limit) break
    }
    for (key in keys.take(limit)) load(key, retryFailed = false) {}
  }

  // Tiles

  private fun load(key: TileKey, retryFailed: Boolean, completion: (Result<FloatArray>) -> Unit) {
    val template: String
    synchronized(lock) {
      tiles[key]?.let { return completion(Result.success(it)) }
      val failed = failedAt[key]
      if (!retryFailed && failed != null && System.currentTimeMillis() - failed < RETRY_INTERVAL) {
        return completion(Result.failure(IllegalStateException("Elevation tile ${key.z}/${key.x}/${key.y} failed recently")))
      }
      waiting[key]?.let {
        it.add(completion)
        return
      }
      waiting[key] = mutableListOf(completion)
      template = tileUrlTemplate
    }
    executor.execute {
      val cache = cacheDirectory?.let { File(it, "${stableHash(template)}-${key.z}-${key.x}-${key.y}.png") }
      cache?.takeIf { it.exists() }?.let { file ->
        runCatching { decode(file.readBytes()) }.getOrNull()?.let { return@execute finish(key, Result.success(it)) }
      }
      val url = template.replace("{z}", "${key.z}").replace("{x}", "${key.x}").replace("{y}", "${key.y}")
      val result = runCatching {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        connection.setRequestProperty("User-Agent", "munim-maps (https://github.com/munimtechnologies/munim-maps)")
        val bytes = try {
          val status = connection.responseCode
          if (status !in 200..299) error("Could not load elevation tile ${key.z}/${key.x}/${key.y}: HTTP $status")
          connection.inputStream.use { it.readBytes() }
        } finally {
          connection.disconnect()
        }
        val heights = decode(bytes) ?: error("Could not read elevation tile ${key.z}/${key.x}/${key.y}")
        cache?.let {
          it.parentFile?.mkdirs()
          runCatching { it.writeBytes(bytes) }
        }
        heights
      }
      finish(key, result.recoverCatching {
        throw IllegalStateException(it.message ?: "Could not load elevation tile ${key.z}/${key.x}/${key.y}")
      })
    }
  }

  private fun finish(key: TileKey, result: Result<FloatArray>) {
    val callbacks = synchronized(lock) {
      result.onSuccess { heights ->
        tiles[key] = heights
        useCounter += 1
        lastUsed[key] = useCounter
        failedAt.remove(key)
        if (tiles.size > MEMORY_TILES) {
          lastUsed.minByOrNull { it.value }?.key?.let {
            tiles.remove(it)
            lastUsed.remove(it)
          }
        }
      }.onFailure { failedAt[key] = System.currentTimeMillis() }
      waiting.remove(key) ?: mutableListOf()
    }
    callbacks.forEach { it(result) }
    main.post {
      val all = synchronized(listeners) { listeners.toList() }
      all.forEach { it(result.isSuccess, result.exceptionOrNull()?.message) }
    }
  }

  private fun stableHash(string: String): Long {
    var hash = -3750763034362895579L // 14695981039346656037 as signed
    for (byte in string.toByteArray()) {
      hash = hash xor (byte.toLong() and 0xff)
      hash *= 1099511628211L
    }
    return hash and 0x7fff_ffff_ffffL
  }

  // Sampling

  /** Global pixel position at [ZOOM], whole numbers at pixel centres. */
  private fun pixel(latitude: Double, longitude: Double): DoubleArray {
    val size = (1 shl ZOOM).toDouble() * TILE_SIZE
    val lat = latitude.coerceIn(-85.051128, 85.051128) * PI / 180
    var lon = longitude % 360
    if (lon >= 180) lon -= 360
    if (lon < -180) lon += 360
    val x = (lon + 180) / 360 * size
    val y = (1 - asinh(tan(lat)) / PI) / 2 * size
    return doubleArrayOf(x - 0.5, y - 0.5)
  }

  private fun valid(latitude: Double, longitude: Double) =
    latitude in -90.0..90.0 && longitude in -180.0..180.0 && !latitude.isNaN() && !longitude.isNaN()

  private fun corners(latitude: Double, longitude: Double): Triple<List<IntArray>, Double, Double> {
    val size = (1 shl ZOOM) * TILE_SIZE
    val p = pixel(latitude, longitude)
    val x0 = floor(p[0]).toInt()
    val y0 = floor(p[1]).toInt()
    fun wrap(x: Int) = ((x % size) + size) % size
    fun clamp(y: Int) = y.coerceIn(0, size - 1)
    val pixels = listOf(intArrayOf(x0, y0), intArrayOf(x0 + 1, y0), intArrayOf(x0, y0 + 1), intArrayOf(x0 + 1, y0 + 1))
      .map { intArrayOf(wrap(it[0]), clamp(it[1])) }
    return Triple(pixels, p[0] - x0, p[1] - y0)
  }

  private fun tileKeys(latitude: Double, longitude: Double): List<TileKey> {
    if (!valid(latitude, longitude)) return emptyList()
    return corners(latitude, longitude).first.map { TileKey(ZOOM, it[0] / TILE_SIZE, it[1] / TILE_SIZE) }.distinct()
  }

  private fun sample(latitude: Double, longitude: Double, tile: (TileKey) -> FloatArray?): Double? {
    if (!valid(latitude, longitude)) return null
    val (pixels, fx, fy) = corners(latitude, longitude)
    val values = DoubleArray(4)
    for ((i, p) in pixels.withIndex()) {
      val heights = tile(TileKey(ZOOM, p[0] / TILE_SIZE, p[1] / TILE_SIZE)) ?: return null
      values[i] = heights[(p[1] % TILE_SIZE) * TILE_SIZE + p[0] % TILE_SIZE].toDouble()
    }
    val top = values[0] + (values[1] - values[0]) * fx
    val bottom = values[2] + (values[3] - values[2]) * fx
    return top + (bottom - top) * fy
  }

  // Decoding

  /** Heights from a Terrarium PNG, read from the raw bytes so no colour management changes them. */
  internal fun decode(png: ByteArray): FloatArray? {
    PngReader.rgb(png)?.let { (width, height, rgb) ->
      if (width != TILE_SIZE || height != TILE_SIZE) return null
      return FloatArray(TILE_SIZE * TILE_SIZE) { i ->
        val r = rgb[i * 3].toInt() and 0xff
        val g = rgb[i * 3 + 1].toInt() and 0xff
        val b = rgb[i * 3 + 2].toInt() and 0xff
        r * 256f + g + b / 256f - 32768f
      }
    }
    // Palette or 16-bit PNGs: let Android decode them, unpremultiplied and without colour conversion.
    val options = BitmapFactory.Options().apply {
      inPremultiplied = false
      inPreferredConfig = Bitmap.Config.ARGB_8888
      inScaled = false
    }
    val bitmap = BitmapFactory.decodeByteArray(png, 0, png.size, options) ?: return null
    if (bitmap.width != TILE_SIZE || bitmap.height != TILE_SIZE) return null
    val pixels = IntArray(TILE_SIZE * TILE_SIZE)
    bitmap.getPixels(pixels, 0, TILE_SIZE, 0, 0, TILE_SIZE, TILE_SIZE)
    bitmap.recycle()
    return FloatArray(pixels.size) { i ->
      val p = pixels[i]
      ((p shr 16) and 0xff) * 256f + ((p shr 8) and 0xff) + (p and 0xff) / 256f - 32768f
    }
  }
}

/** Reads 8-bit RGB / RGBA, non-interlaced PNGs to RGB bytes (what Terrarium tiles are). */
internal object PngReader {
  fun rgb(png: ByteArray): Triple<Int, Int, ByteArray>? {
    if (png.size < 33 || png[0] != 0x89.toByte() || png[1] != 'P'.code.toByte()) return null
    var offset = 8
    var width = 0
    var height = 0
    var channels = 0
    val idat = ByteArrayOutputStream()
    while (offset + 8 <= png.size) {
      val length = int(png, offset)
      val type = String(png, offset + 4, 4, Charsets.US_ASCII)
      val data = offset + 8
      if (length < 0 || data + length > png.size) return null
      when (type) {
        "IHDR" -> {
          width = int(png, data)
          height = int(png, data + 4)
          val depth = png[data + 8].toInt()
          val color = png[data + 9].toInt()
          val interlace = png[data + 12].toInt()
          channels = when (color) { 2 -> 3; 6 -> 4; else -> return null }
          if (depth != 8 || interlace != 0) return null
        }
        "IDAT" -> idat.write(png, data, length)
        "IEND" -> break
      }
      offset = data + length + 4
    }
    if (width <= 0 || height <= 0 || channels == 0) return null
    val stride = width * channels
    val raw = ByteArray((stride + 1) * height)
    val inflater = Inflater()
    inflater.setInput(idat.toByteArray())
    var read = 0
    while (read < raw.size && !inflater.finished()) {
      val n = inflater.inflate(raw, read, raw.size - read)
      if (n == 0 && (inflater.needsInput() || inflater.needsDictionary())) break
      read += n
    }
    inflater.end()
    if (read < raw.size) return null
    val out = ByteArray(width * height * 3)
    var previous = ByteArray(stride)
    val line = ByteArray(stride)
    for (y in 0 until height) {
      val start = y * (stride + 1)
      val filter = raw[start].toInt()
      for (x in 0 until stride) {
        val v = raw[start + 1 + x].toInt() and 0xff
        val a = if (x >= channels) line[x - channels].toInt() and 0xff else 0
        val b = previous[x].toInt() and 0xff
        val c = if (x >= channels) previous[x - channels].toInt() and 0xff else 0
        val value = when (filter) {
          0 -> v
          1 -> v + a
          2 -> v + b
          3 -> v + (a + b) / 2
          4 -> {
            val p = a + b - c
            val pa = abs(p - a)
            val pb = abs(p - b)
            val pc = abs(p - c)
            v + if (pa <= pb && pa <= pc) a else if (pb <= pc) b else c
          }
          else -> return null
        }
        line[x] = value.toByte()
      }
      for (x in 0 until width) {
        out[(y * width + x) * 3] = line[x * channels]
        out[(y * width + x) * 3 + 1] = line[x * channels + 1]
        out[(y * width + x) * 3 + 2] = line[x * channels + 2]
      }
      previous = line.copyOf()
    }
    return Triple(width, height, out)
  }

  private fun int(b: ByteArray, i: Int) =
    ((b[i].toInt() and 0xff) shl 24) or ((b[i + 1].toInt() and 0xff) shl 16) or
      ((b[i + 2].toInt() and 0xff) shl 8) or (b[i + 3].toInt() and 0xff)
}
