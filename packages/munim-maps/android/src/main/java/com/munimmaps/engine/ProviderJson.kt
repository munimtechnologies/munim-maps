package com.munimmaps.engine

import org.json.JSONArray
import org.json.JSONObject

/** JSON for engine-only methods and events (`providerCommand`, `onProviderEvent`). */
object ProviderJson {
  /** The JSON object in [json], or an empty one. */
  fun objectOf(json: String): JSONObject = try {
    if (json.isBlank()) JSONObject() else JSONObject(json)
  } catch (_: Exception) {
    JSONObject()
  }

  /** [value] as JSON text (JSONObject, JSONArray, Map, List, String, Number, Boolean or null). */
  fun stringOf(value: Any?): String = when (val wrapped = wrap(value)) {
    null, JSONObject.NULL -> "null"
    is String -> JSONObject.quote(wrapped)
    else -> wrapped.toString()
  }

  /** A value org.json writes: maps and lists become JSONObject and JSONArray. */
  fun wrap(value: Any?): Any? = when (value) {
    null -> JSONObject.NULL
    is JSONObject, is JSONArray, is String, is Boolean -> value
    is Number -> if (value.toDouble().isFinite()) value else JSONObject.NULL
    is Map<*, *> -> JSONObject().also { o -> value.forEach { (k, v) -> o.put(k.toString(), wrap(v)) } }
    is Iterable<*> -> JSONArray().also { a -> value.forEach { a.put(wrap(it)) } }
    is Array<*> -> JSONArray().also { a -> value.forEach { a.put(wrap(it)) } }
    is DoubleArray -> JSONArray().also { a -> value.forEach { a.put(wrap(it)) } }
    else -> JSONObject.wrap(value) ?: value.toString()
  }
}
