package com.munimmaps.engines.mapbox

import android.graphics.Color
import com.mapbox.bindgen.Expected
import com.mapbox.bindgen.Value
import com.mapbox.geojson.Feature
import com.mapbox.geojson.Point
import com.mapbox.maps.EdgeInsets
import com.mapbox.maps.ScreenCoordinate
import com.margelo.nitro.munimmaps.MapCoordinate
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import kotlin.math.PI
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * JSON, style values, colours and geometry helpers for the Mapbox engine.
 *
 * Style objects arrive from JavaScript as JSON (style-spec shaped) and go to
 * the SDK as `com.mapbox.bindgen.Value` through `Value.fromJson`, so every
 * layer type, property and expression passes through unchanged.
 */
internal object MapboxJson {
  /** A JSON-compatible value (JSONObject, JSONArray, String, Number, Boolean, null) as a style Value. */
  fun value(json: Any?): Value {
    val text = when (json) {
      null, JSONObject.NULL -> return Value.nullValue()
      is JSONObject, is JSONArray -> json.toString()
      is String -> JSONObject.quote(json)
      is Boolean -> return Value.valueOf(json)
      is Int, is Long -> return Value.valueOf((json as Number).toLong())
      is Number -> return Value.valueOf(json.toDouble())
      else -> com.munimmaps.engine.ProviderJson.stringOf(json)
    }
    val parsed = Value.fromJson(text)
    return parsed.value ?: throw IllegalArgumentException(parsed.error ?: "Bad style value $text")
  }

  /** A style Value back as JSON (JSONObject, JSONArray, String, Number, Boolean or JSONObject.NULL). */
  fun json(value: Value?): Any? {
    if (value == null) return JSONObject.NULL
    return parse(value.toJson())
  }

  fun parse(text: String?): Any? {
    if (text.isNullOrBlank()) return JSONObject.NULL
    return try {
      JSONTokener(text).nextValue()
    } catch (_: Exception) {
      text
    }
  }

  /** The error of an SDK call, or null when it succeeded. */
  fun <V> error(result: Expected<String, V>?): String? = result?.error

  /** JSON object or JSON text as a JSON object (null when it is neither). */
  fun objectOf(value: Any?): JSONObject? = when (value) {
    is JSONObject -> value
    is String -> try { JSONObject(value) } catch (_: Exception) { null }
    else -> null
  }

  /** Same JSON (key order ignored for objects). */
  fun same(a: Any?, b: Any?): Boolean {
    if (a === b) return true
    if (a == null || a == JSONObject.NULL) return b == null || b == JSONObject.NULL
    if (b == null || b == JSONObject.NULL) return false
    if (a is JSONObject && b is JSONObject) {
      if (a.length() != b.length()) return false
      val keys = a.keys()
      while (keys.hasNext()) {
        val k = keys.next()
        if (!b.has(k) || !same(a.opt(k), b.opt(k))) return false
      }
      return true
    }
    if (a is JSONArray && b is JSONArray) {
      if (a.length() != b.length()) return false
      for (i in 0 until a.length()) if (!same(a.opt(i), b.opt(i))) return false
      return true
    }
    if (a is Number && b is Number) return a.toDouble() == b.toDouble()
    return a == b
  }

  fun list(array: JSONArray?): List<Any?> = if (array == null) emptyList() else List(array.length()) { array.opt(it) }

  fun strings(array: JSONArray?): List<String> =
    if (array == null) emptyList() else List(array.length()) { array.optString(it) }.filter { it.isNotEmpty() }

  fun doubles(array: JSONArray?): List<Double> =
    if (array == null) emptyList() else List(array.length()) { array.optDouble(it, 0.0) }

  fun point(json: JSONObject?): Point? {
    json ?: return null
    if (!json.has("latitude") || !json.has("longitude")) return null
    return Point.fromLngLat(json.optDouble("longitude"), json.optDouble("latitude"))
  }

  fun coordinate(point: Point): JSONObject =
    JSONObject().put("latitude", point.latitude()).put("longitude", point.longitude())

  /** `{ top, left, bottom, right }` in points to pixels. */
  fun insets(json: JSONObject?, density: Double): EdgeInsets? {
    json ?: return null
    return EdgeInsets(
      json.optDouble("top", 0.0) * density,
      json.optDouble("left", 0.0) * density,
      json.optDouble("bottom", 0.0) * density,
      json.optDouble("right", 0.0) * density,
    )
  }

  fun insetsJson(insets: EdgeInsets, density: Double): JSONObject = JSONObject()
    .put("top", insets.top / density)
    .put("left", insets.left / density)
    .put("bottom", insets.bottom / density)
    .put("right", insets.right / density)

  fun screen(json: JSONObject?, density: Double): ScreenCoordinate? {
    json ?: return null
    return ScreenCoordinate(json.optDouble("x") * density, json.optDouble("y") * density)
  }

  /** A GeoJSON feature as JSON. */
  fun feature(feature: Feature): JSONObject = (parse(feature.toJson()) as? JSONObject) ?: JSONObject()

  fun featureFrom(json: JSONObject): Feature = Feature.fromJson(json.toString())
}

/** Colours as JavaScript passes them: `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`, `rgb()`, `rgba()` or a name. */
internal object MapboxColors {
  fun parse(value: String?): Int? {
    val text = value?.trim() ?: return null
    if (text.isEmpty()) return null
    if (text.startsWith("#")) {
      val hex = text.substring(1)
      val n = hex.toLongOrNull(16) ?: return null
      return when (hex.length) {
        3 -> Color.rgb(expand((n shr 8) and 0xF), expand((n shr 4) and 0xF), expand(n and 0xF))
        4 -> Color.argb(expand(n and 0xF), expand((n shr 12) and 0xF), expand((n shr 8) and 0xF), expand((n shr 4) and 0xF))
        6 -> Color.rgb(((n shr 16) and 0xFF).toInt(), ((n shr 8) and 0xFF).toInt(), (n and 0xFF).toInt())
        8 -> Color.argb((n and 0xFF).toInt(), ((n shr 24) and 0xFF).toInt(), ((n shr 16) and 0xFF).toInt(), ((n shr 8) and 0xFF).toInt())
        else -> null
      }
    }
    val lower = text.lowercase()
    if (lower.startsWith("rgb")) {
      val inside = lower.substringAfter('(').substringBefore(')')
      val parts = inside.split(',', ' ', '/').map { it.trim() }.filter { it.isNotEmpty() }
      if (parts.size < 3) return null
      fun channel(s: String) = if (s.endsWith("%")) (s.dropLast(1).toFloatOrNull() ?: 0f) * 2.55f else s.toFloatOrNull() ?: 0f
      val a = parts.getOrNull(3)?.let { if (it.endsWith("%")) (it.dropLast(1).toFloatOrNull() ?: 100f) / 100f else it.toFloatOrNull() ?: 1f } ?: 1f
      return Color.argb((a.coerceIn(0f, 1f) * 255).toInt(), channel(parts[0]).toInt().coerceIn(0, 255),
        channel(parts[1]).toInt().coerceIn(0, 255), channel(parts[2]).toInt().coerceIn(0, 255))
    }
    if (lower == "transparent" || lower == "clear") return Color.TRANSPARENT
    return try {
      Color.parseColor(lower)
    } catch (_: Exception) {
      null
    }
  }

  private fun expand(n: Long): Int = (n * 17).toInt()

  /** The colour as a style-spec string (`rgba(r, g, b, a)`), or [fallback]. */
  fun css(value: String?, fallback: String): String {
    val c = parse(value) ?: return fallback
    return css(c)
  }

  fun css(c: Int): String =
    "rgba(${Color.red(c)}, ${Color.green(c)}, ${Color.blue(c)}, ${"%.4f".format(java.util.Locale.US, Color.alpha(c) / 255.0)})"

  /** Splits a comma-separated colour list, keeping `rgba(…)` whole. */
  fun split(list: String): List<String> {
    val out = mutableListOf<String>()
    var depth = 0
    val current = StringBuilder()
    for (ch in list) {
      when {
        ch == '(' -> { depth++; current.append(ch) }
        ch == ')' -> { depth--; current.append(ch) }
        ch == ',' && depth == 0 -> { out.add(current.toString().trim()); current.clear() }
        else -> current.append(ch)
      }
    }
    if (current.isNotBlank()) out.add(current.toString().trim())
    return out.filter { it.isNotEmpty() }
  }
}

/** Earth geometry for shapes. */
internal object MapboxGeo {
  private const val R = 6_371_008.8

  /** A ring of [segments] points [radius] metres around a centre (closed). */
  fun circle(latitude: Double, longitude: Double, radius: Double, segments: Int = 96): List<Point> {
    val ring = ArrayList<Point>(segments + 1)
    for (i in 0..segments) {
      val bearing = 2 * PI * (i % segments) / segments
      ring.add(destination(latitude, longitude, radius, bearing))
    }
    return ring
  }

  fun destination(latitude: Double, longitude: Double, distance: Double, bearing: Double): Point {
    val d = distance / R
    val p1 = latitude * PI / 180
    val l1 = longitude * PI / 180
    val p2 = asin(sin(p1) * cos(d) + cos(p1) * sin(d) * cos(bearing))
    val l2 = l1 + atan2(sin(bearing) * sin(d) * cos(p1), cos(d) - sin(p1) * sin(p2))
    var lon = l2 * 180 / PI
    lon = ((lon + 540) % 360) - 180
    return Point.fromLngLat(lon, p2 * 180 / PI)
  }

  /** Points along great circles between the coordinates (about every 100 km, at least 8 per leg). */
  fun geodesic(coordinates: List<MapCoordinate>): List<Point> {
    if (coordinates.size < 2) return coordinates.map { Point.fromLngLat(it.longitude, it.latitude) }
    val out = ArrayList<Point>()
    for (i in 0 until coordinates.size - 1) {
      val a = coordinates[i]
      val b = coordinates[i + 1]
      val p1 = a.latitude * PI / 180
      val l1 = a.longitude * PI / 180
      val p2 = b.latitude * PI / 180
      val l2 = b.longitude * PI / 180
      val d = 2 * asin(sqrt(sin((p2 - p1) / 2).let { it * it } + cos(p1) * cos(p2) * sin((l2 - l1) / 2).let { it * it }))
      val steps = maxOf(8, (d * R / 100_000).toInt()).coerceAtMost(512)
      var lastLon = a.longitude
      for (s in 0 until steps) {
        val f = s.toDouble() / steps
        if (d < 1e-12) {
          out.add(Point.fromLngLat(a.longitude, a.latitude))
          break
        }
        val A = sin((1 - f) * d) / sin(d)
        val B = sin(f * d) / sin(d)
        val x = A * cos(p1) * cos(l1) + B * cos(p2) * cos(l2)
        val y = A * cos(p1) * sin(l1) + B * cos(p2) * sin(l2)
        val z = A * sin(p1) + B * sin(p2)
        val lat = atan2(z, sqrt(x * x + y * y)) * 180 / PI
        var lon = atan2(y, x) * 180 / PI
        // Keep longitudes continuous across the antimeridian (Mapbox draws the short way).
        while (lon - lastLon > 180) lon -= 360
        while (lon - lastLon < -180) lon += 360
        lastLon = lon
        out.add(Point.fromLngLat(lon, lat))
      }
    }
    val last = coordinates.last()
    var lon = last.longitude
    val prev = out.lastOrNull()?.longitude() ?: lon
    while (lon - prev > 180) lon -= 360
    while (lon - prev < -180) lon += 360
    out.add(Point.fromLngLat(lon, last.latitude))
    return out
  }

  fun points(coordinates: Array<MapCoordinate>): List<Point> = coordinates.map { Point.fromLngLat(it.longitude, it.latitude) }

  /** Closes a ring (first point repeated last). */
  fun closed(ring: List<Point>): List<Point> {
    if (ring.size < 3) return ring
    val first = ring.first()
    val last = ring.last()
    return if (first.latitude() == last.latitude() && first.longitude() == last.longitude()) ring else ring + first
  }

  // Screen-space hit tests, in pixels.

  fun distanceToSegment(px: Double, py: Double, ax: Double, ay: Double, bx: Double, by: Double): Double {
    val dx = bx - ax
    val dy = by - ay
    val len = dx * dx + dy * dy
    val t = if (len <= 0) 0.0 else (((px - ax) * dx + (py - ay) * dy) / len).coerceIn(0.0, 1.0)
    val cx = ax + t * dx
    val cy = ay + t * dy
    return sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy))
  }

  fun distanceToPolyline(px: Double, py: Double, xy: List<ScreenCoordinate>): Double {
    if (xy.isEmpty()) return Double.MAX_VALUE
    if (xy.size == 1) return sqrt((px - xy[0].x).let { it * it } + (py - xy[0].y).let { it * it })
    var best = Double.MAX_VALUE
    for (i in 0 until xy.size - 1) {
      best = minOf(best, distanceToSegment(px, py, xy[i].x, xy[i].y, xy[i + 1].x, xy[i + 1].y))
    }
    return best
  }

  fun inside(px: Double, py: Double, ring: List<ScreenCoordinate>): Boolean {
    var inside = false
    var j = ring.size - 1
    for (i in ring.indices) {
      val a = ring[i]
      val b = ring[j]
      if ((a.y > py) != (b.y > py) && px < (b.x - a.x) * (py - a.y) / (b.y - a.y) + a.x) inside = !inside
      j = i
    }
    return inside
  }
}
