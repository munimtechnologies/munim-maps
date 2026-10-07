package com.munimmaps.engines.google

import android.graphics.Color
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.LatLngBounds
import org.json.JSONArray
import org.json.JSONObject

/**
 * Read-only access to the `google={…}` options and command arguments, with
 * the conversions the Google engine needs. The Android twin of iOS's
 * `GoogleJSON`.
 */
class GJson(val raw: Any?) {
  operator fun get(key: String): GJson = GJson((raw as? JSONObject)?.opt(key)?.takeIf { it != JSONObject.NULL })

  val exists: Boolean get() = raw != null
  val obj: JSONObject? get() = raw as? JSONObject
  val keys: List<String> get() = obj?.keys()?.asSequence()?.toList() ?: emptyList()
  val array: List<GJson>
    get() {
      val a = raw as? JSONArray ?: return emptyList()
      return (0 until a.length()).map { GJson(a.opt(it)?.takeIf { v -> v != JSONObject.NULL }) }
    }

  val string: String? get() = when (raw) {
    is String -> raw
    is Number, is Boolean -> raw.toString()
    else -> null
  }

  val double: Double? get() = when (raw) {
    is Number -> raw.toDouble()
    is String -> raw.toDoubleOrNull()
    else -> null
  }

  val bool: Boolean? get() = when (raw) {
    is Boolean -> raw
    is String -> raw.toBooleanStrictOrNull()
    is Number -> raw.toInt() != 0
    else -> null
  }

  fun string(fallback: String) = string ?: fallback
  fun double(fallback: Double) = double ?: fallback
  fun bool(fallback: Boolean) = bool ?: fallback

  /** `#RRGGBB(AA)` / `#RGB` as an Android colour, or null. */
  val color: Int? get() = string?.let { parseColor(it) }

  val latLng: LatLng?
    get() {
      val lat = this["latitude"].double ?: this["lat"].double ?: return null
      val lng = this["longitude"].double ?: this["lng"].double ?: return null
      return LatLng(lat, lng)
    }

  /** `{ southwest, northeast }`, or a region `{ latitude, longitude, latitudeDelta, longitudeDelta }`. */
  val bounds: LatLngBounds?
    get() {
      val sw = this["southwest"].latLng
      val ne = this["northeast"].latLng
      if (sw != null && ne != null) return LatLngBounds(sw, ne)
      val c = latLng ?: return null
      val dLat = this["latitudeDelta"].double ?: return null
      val dLng = this["longitudeDelta"].double ?: return null
      return LatLngBounds(LatLng(c.latitude - dLat / 2, c.longitude - dLng / 2), LatLng(c.latitude + dLat / 2, c.longitude + dLng / 2))
    }

  override fun toString(): String = raw?.toString() ?: ""

  companion object {
    /** Parses `#RGB`, `#RRGGBB` or `#RRGGBBAA` (CSS order, alpha last); also Android's names. */
    fun parseColor(text: String): Int? {
      var s = text.trim()
      if (s.isEmpty()) return null
      if (!s.startsWith("#")) return try { Color.parseColor(s) } catch (_: IllegalArgumentException) { null }
      s = s.substring(1)
      if (s.length == 3 || s.length == 4) s = s.map { "$it$it" }.joinToString("")
      val value = s.toLongOrNull(16) ?: return null
      return when (s.length) {
        6 -> (0xFF000000 or value).toInt()
        8 -> {
          val rgb = (value shr 8) and 0xFFFFFF
          val alpha = value and 0xFF
          ((alpha shl 24) or rgb).toInt()
        }
        else -> null
      }
    }
  }
}

/** JSON values for events and command results. */
object GOut {
  fun latLng(c: LatLng) = JSONObject().put("latitude", c.latitude).put("longitude", c.longitude)
  fun bounds(b: LatLngBounds) = JSONObject().put("southwest", latLng(b.southwest)).put("northeast", latLng(b.northeast))
  fun obj(vararg pairs: Pair<String, Any?>): JSONObject {
    val o = JSONObject()
    for ((k, v) in pairs) o.put(k, v ?: JSONObject.NULL)
    return o
  }
}
