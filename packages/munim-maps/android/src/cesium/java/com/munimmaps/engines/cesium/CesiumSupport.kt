package com.munimmaps.engines.cesium

import com.margelo.nitro.munimmaps.MapRegion
import org.json.JSONArray
import org.json.JSONObject
import java.lang.reflect.Modifier
import java.util.Locale
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * JSON for the web side from Nitro's generated Kotlin types (data classes
 * kept with @Keep, so their field names survive R8), arrays and maps. Enums
 * become their lower-cased names (`FOLLOWWITHHEADING` -> `followwithheading`;
 * the web side compares names case- and separator-insensitively).
 */
object CesiumJson {
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
 * The camera Cesium last reported (`{ t: 'cam' }`) in CSS pixels (dp), with
 * Cesium's view and projection matrices for exact point <-> coordinate
 * conversion without a round trip to JavaScript.
 */
class CesiumCamera(s: JSONObject, previous: CesiumCamera?) {
  val latitude = s.optDouble("latitude", 0.0)
  val longitude = s.optDouble("longitude", 0.0)
  val centerHeight = s.optDouble("centerHeight", 0.0)
  val distance = s.optDouble("distance", 1000.0)
  val pitch = s.optDouble("pitch", 0.0)
  val heading = s.optDouble("heading", 0.0)
  val fovy = s.optDouble("fovy", Math.PI / 3)
  val width = s.optDouble("width", 0.0)
  val height = s.optDouble("height", 0.0)
  val centerX = s.optDouble("centerX", width / 2)
  val centerY = s.optDouble("centerY", height / 2)
  val globe = s.optBoolean("globe", true)
  val terrain = s.optBoolean("terrain", false)
  val dark = s.optBoolean("dark", false)
  private val view = matrix(s.optJSONArray("view"))
  private val projection = matrix(s.optJSONArray("projection"))
  val region: MapRegion? = s.optJSONObject("region")?.let {
    MapRegion(it.optDouble("latitude"), it.optDouble("longitude"), it.optDouble("latitudeDelta"), it.optDouble("longitudeDelta"))
  } ?: previous?.region

  /** Where Cesium draws a coordinate (at the centre's ground height), in CSS pixels; null when behind the camera. */
  fun screenPoint(latitude: Double, longitude: Double): DoubleArray? {
    if (width <= 0) return null
    val p = ecef(latitude, longitude, centerHeight)
    val clip = mul(projection, mul(view, doubleArrayOf(p[0], p[1], p[2], 1.0)))
    if (clip[3] <= 1e-9) return null
    val x = clip[0] / clip[3]
    val y = clip[1] / clip[3]
    return doubleArrayOf((x + 1) / 2 * width, (1 - y) / 2 * height)
  }

  /** The coordinate under a point (CSS pixels), on the ellipsoid raised to the centre's height. */
  fun coordinate(px: Double, py: Double): DoubleArray? {
    if (width <= 0 || height <= 0) return null
    val inverse = invert(mulMat(projection, view)) ?: return null
    val x = px / width * 2 - 1
    val y = 1 - py / height * 2
    fun unproject(z: Double): DoubleArray {
      val v = mul(inverse, doubleArrayOf(x, y, z, 1.0))
      return doubleArrayOf(v[0] / v[3], v[1] / v[3], v[2] / v[3])
    }
    val near = unproject(-1.0)
    val far = unproject(1.0)
    val d = doubleArrayOf(far[0] - near[0], far[1] - near[1], far[2] - near[2])
    val len = sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2])
    for (i in 0..2) d[i] /= len
    val sa = 1 / (A + centerHeight)
    val sb = 1 / (B + centerHeight)
    val o = doubleArrayOf(near[0] * sa, near[1] * sa, near[2] * sb)
    val dv = doubleArrayOf(d[0] * sa, d[1] * sa, d[2] * sb)
    val qa = dv[0] * dv[0] + dv[1] * dv[1] + dv[2] * dv[2]
    val qb = 2 * (o[0] * dv[0] + o[1] * dv[1] + o[2] * dv[2])
    val qc = o[0] * o[0] + o[1] * o[1] + o[2] * o[2] - 1
    val disc = qb * qb - 4 * qa * qc
    if (disc < 0) return null
    val t = (-qb - sqrt(disc)) / (2 * qa)
    if (t <= 0) return null
    return geodetic(doubleArrayOf(near[0] + d[0] * t, near[1] + d[1] * t, near[2] + d[2] * t))
  }

  companion object {
    private const val A = 6_378_137.0
    private const val B = 6_356_752.314245179
    private const val E2 = 1 - (B * B) / (A * A)

    /** Column-major 4x4 from Cesium. */
    private fun matrix(a: JSONArray?): DoubleArray =
      if (a != null && a.length() == 16) DoubleArray(16) { a.optDouble(it) } else doubleArrayOf(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0)

    private fun mul(m: DoubleArray, v: DoubleArray) = DoubleArray(4) { r -> m[r] * v[0] + m[4 + r] * v[1] + m[8 + r] * v[2] + m[12 + r] * v[3] }

    private fun mulMat(a: DoubleArray, b: DoubleArray) = DoubleArray(16) { i ->
      val c = i / 4
      val r = i % 4
      a[r] * b[c * 4] + a[4 + r] * b[c * 4 + 1] + a[8 + r] * b[c * 4 + 2] + a[12 + r] * b[c * 4 + 3]
    }

    /** General 4x4 inverse (column-major; the layout does not matter for inversion). */
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

    fun ecef(latitude: Double, longitude: Double, height: Double): DoubleArray {
      val phi = Math.toRadians(latitude)
      val lambda = Math.toRadians(longitude)
      val n = A / sqrt(1 - E2 * sin(phi) * sin(phi))
      return doubleArrayOf((n + height) * cos(phi) * cos(lambda), (n + height) * cos(phi) * sin(lambda), (n * (1 - E2) + height) * sin(phi))
    }

    fun geodetic(p: DoubleArray): DoubleArray {
      val lon = atan2(p[1], p[0])
      val r = sqrt(p[0] * p[0] + p[1] * p[1])
      var lat = atan2(p[2], r * (1 - E2))
      for (i in 0 until 6) {
        val n = A / sqrt(1 - E2 * sin(lat) * sin(lat))
        val h = r / maxOf(1e-9, cos(lat)) - n
        lat = atan2(p[2], r * (1 - E2 * n / (n + h)))
      }
      return doubleArrayOf(Math.toDegrees(lat), Math.toDegrees(lon))
    }
  }
}
