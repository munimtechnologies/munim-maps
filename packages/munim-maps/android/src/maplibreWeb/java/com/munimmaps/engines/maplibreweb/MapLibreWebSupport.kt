package com.munimmaps.engines.maplibreweb

import com.margelo.nitro.munimmaps.MapRegion
import org.json.JSONArray
import org.json.JSONObject
import java.lang.reflect.Modifier
import java.util.Locale
import kotlin.math.PI
import kotlin.math.asin
import kotlin.math.atan
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan

/**
 * JSON for the page from Nitro's generated Kotlin types (data classes kept
 * with @Keep, so their field names survive R8), arrays and maps. Enums
 * become their lower-cased names (the page compares names case- and
 * separator-insensitively).
 */
object MapLibreWebJson {
  fun value(any: Any?): Any? = when (any) {
    null -> JSONObject.NULL
    is JSONObject, is JSONArray, is String, is Boolean -> any
    is Double -> if (any.isFinite()) any else 0.0
    is Float -> if (any.isFinite()) any.toDouble() else 0.0
    is Number -> any
    is Enum<*> -> any.name.lowercase(Locale.ROOT)
    is Array<*> -> JSONArray().also { a -> any.forEach { a.put(value(it)) } }
    is DoubleArray -> JSONArray().also { a -> any.forEach { a.put(it) } }
    is Iterable<*> -> JSONArray().also { a -> any.forEach { a.put(value(it)) } }
    is Map<*, *> -> JSONObject().also { o -> any.forEach { (k, v) -> o.put(k.toString(), value(v)) } }
    else -> reflect(any)
  }

  private fun reflect(any: Any): JSONObject {
    val o = JSONObject()
    var type: Class<*>? = any.javaClass
    while (type != null && type != Any::class.java) {
      for (field in type.declaredFields) {
        if (Modifier.isStatic(field.modifiers) || field.isSynthetic) continue
        field.isAccessible = true
        o.put(field.name, value(field.get(any)))
      }
      type = type.superclass
    }
    return o
  }
}

/**
 * The camera GL JS last reported (`{ t: 'cam' }`), in CSS pixels (dp), with
 * the matrices GL JS gives custom layers (Mercator and globe, and the
 * transition between them), for point <-> coordinate conversion at the
 * height of the ground at the centre, without a round trip to JavaScript.
 */
class MapLibreWebCamera(s: JSONObject, previous: MapLibreWebCamera?) {
  val latitude = s.optDouble("latitude", 0.0)
  val longitude = s.optDouble("longitude", 0.0)
  val distance = s.optDouble("distance", 1000.0)
  val pitch = s.optDouble("pitch", 0.0)
  val heading = s.optDouble("heading", 0.0)
  val fovy = s.optDouble("fovy", 0.6435011087932844)
  val width = s.optDouble("width", 0.0)
  val height = s.optDouble("height", 0.0)
  val centerX = s.optDouble("centerX", width / 2)
  val centerY = s.optDouble("centerY", height / 2)
  val globe = s.optBoolean("globe", false)
  val transition = s.optDouble("transition", 0.0)
  val terrain = s.optBoolean("terrain", false)
  val dark = s.optBoolean("dark", false)
  val centerElevation = s.optDouble("centerElevation", 0.0)
  private val main = matrix(s.optJSONArray("mainMatrix"))
  private val fallback = matrix(s.optJSONArray("fallbackMatrix"))
  val region: MapRegion? = s.optJSONObject("region")?.let {
    MapRegion(it.optDouble("latitude"), it.optDouble("longitude"), it.optDouble("latitudeDelta"), it.optDouble("longitudeDelta"))
  } ?: previous?.region

  /** Where GL JS draws a coordinate (at the centre's ground height), in CSS pixels. */
  fun screenPoint(latitude: Double, longitude: Double): DoubleArray? {
    if (width <= 0) return null
    val m = mercator(latitude, longitude, centerElevation)
    val clip = if (transition <= 0) {
      mul(main, doubleArrayOf(m[0], m[1], m[2], 1.0))
    } else {
      val p = sphere(latitude, longitude, centerElevation)
      val g = mul(main, doubleArrayOf(p[0], p[1], p[2], 1.0))
      if (transition >= 0.999) g else {
        val f = mul(fallback, doubleArrayOf(m[0], m[1], m[2], 1.0))
        DoubleArray(4) { f[it] + (g[it] - f[it]) * transition }
      }
    }
    if (clip[3] <= 1e-12) return null
    return doubleArrayOf((clip[0] / clip[3] + 1) / 2 * width, (1 - clip[1] / clip[3]) / 2 * height)
  }

  /** The coordinate under a point (CSS pixels), on the ground at the centre's height. */
  fun coordinate(px: Double, py: Double): DoubleArray? {
    if (width <= 0 || height <= 0) return null
    val useGlobe = transition >= 0.5
    val inverse = invert(if (useGlobe || transition <= 0) main else fallback) ?: return null
    val x = px / width * 2 - 1
    val y = 1 - py / height * 2
    fun unproject(z: Double): DoubleArray {
      val v = mul(inverse, doubleArrayOf(x, y, z, 1.0))
      return doubleArrayOf(v[0] / v[3], v[1] / v[3], v[2] / v[3])
    }
    val near = unproject(-1.0)
    val far = unproject(1.0)
    val d = DoubleArray(3) { far[it] - near[it] }
    if (useGlobe) {
      val r = 1 + centerElevation / EARTH_RADIUS
      val len = sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2])
      for (i in 0..2) d[i] /= len
      val b = 2 * (near[0] * d[0] + near[1] * d[1] + near[2] * d[2])
      val c = near[0] * near[0] + near[1] * near[1] + near[2] * near[2] - r * r
      val disc = b * b - 4 * c
      if (disc < 0) return null
      val t = (-b - sqrt(disc)) / 2
      if (t <= 0) return null
      val p = DoubleArray(3) { (near[it] + d[it] * t) / r }
      return doubleArrayOf(Math.toDegrees(asin(p[1].coerceIn(-1.0, 1.0))), Math.toDegrees(atan2(p[0], p[2])))
    }
    val z = mercator(latitude, longitude, centerElevation)[2]
    if (kotlin.math.abs(d[2]) < 1e-15) return null
    val t = (z - near[2]) / d[2]
    val mx = near[0] + d[0] * t
    val my = near[1] + d[1] * t
    val lon = mx * 360 - 180
    val lat = 360 / PI * atan(exp((180 - my * 360) * PI / 180)) - 90
    return doubleArrayOf(lat, lon)
  }

  companion object {
    private const val EARTH_RADIUS = 6_371_008.8 // GL JS's

    /** GL JS's `MercatorCoordinate.fromLngLat`. */
    fun mercator(latitude: Double, longitude: Double, altitude: Double): DoubleArray {
      val x = (180 + longitude) / 360
      val y = (180 - (180 / PI * ln(tan(PI / 4 + latitude * PI / 360)))) / 360
      val meter = 1 / (2 * PI * EARTH_RADIUS * cos(Math.toRadians(latitude)))
      return doubleArrayOf(x, y, altitude * meter)
    }

    fun sphere(latitude: Double, longitude: Double, altitude: Double): DoubleArray {
      val l = Math.toRadians(longitude)
      val f = Math.toRadians(latitude)
      val r = 1 + altitude / EARTH_RADIUS
      return doubleArrayOf(sin(l) * cos(f) * r, sin(f) * r, cos(l) * cos(f) * r)
    }

    /** Column-major 4x4 from GL JS. */
    private fun matrix(a: JSONArray?): DoubleArray =
      if (a != null && a.length() == 16) DoubleArray(16) { a.optDouble(it) } else doubleArrayOf(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0)

    private fun mul(m: DoubleArray, v: DoubleArray) = DoubleArray(4) { r -> m[r] * v[0] + m[4 + r] * v[1] + m[8 + r] * v[2] + m[12 + r] * v[3] }

    private fun invert(m: DoubleArray): DoubleArray? {
      val inv = DoubleArray(16)
      inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] + m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10]
      inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] - m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10]
      inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] + m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9]
      inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] - m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9]
      inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] - m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10]
      inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] + m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10]
      inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] - m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9]
      inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] + m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9]
      inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] + m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6]
      inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] - m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6]
      inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] + m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5]
      inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] - m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5]
      inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] - m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6]
      inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] + m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6]
      inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] - m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5]
      inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] + m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5]
      val det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12]
      if (det == 0.0) return null
      return DoubleArray(16) { inv[it] / det }
    }
  }
}
