package com.munimmaps.engines.maplibre

import com.google.gson.JsonElement
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import org.json.JSONArray
import org.json.JSONObject
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.geometry.LatLngQuad
import org.maplibre.android.maps.Style
import org.maplibre.android.style.expressions.Expression
import org.maplibre.android.style.layers.BackgroundLayer
import org.maplibre.android.style.layers.CircleLayer
import org.maplibre.android.style.layers.ColorReliefLayer
import org.maplibre.android.style.layers.FillExtrusionLayer
import org.maplibre.android.style.layers.FillLayer
import org.maplibre.android.style.layers.HeatmapLayer
import org.maplibre.android.style.layers.HillshadeLayer
import org.maplibre.android.style.layers.Layer
import org.maplibre.android.style.layers.LayoutPropertyValue
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.PaintPropertyValue
import org.maplibre.android.style.layers.RasterLayer
import org.maplibre.android.style.layers.SymbolLayer
import org.maplibre.android.style.sources.GeoJsonOptions
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.android.style.sources.ImageSource
import org.maplibre.android.style.sources.RasterDemSource
import org.maplibre.android.style.sources.RasterSource
import org.maplibre.android.style.sources.Source
import org.maplibre.android.style.sources.TileSet
import org.maplibre.android.style.sources.VectorSource
import java.net.URI

/**
 * MapLibre style-spec JSON (sources, layers, properties, filters) onto
 * MapLibre Android's runtime styling API. Property values go to the native
 * style parser as plain Java values (arrays, maps, strings, numbers), so
 * every expression, zoom function and literal is read exactly as in a style
 * JSON file.
 */
internal object StyleSpec {
  /** org.json value → what MapLibre's native converter reads. */
  fun java(value: Any?): Any? = when (value) {
    null, JSONObject.NULL -> null
    is JSONArray -> Array<Any?>(value.length()) { java(value.opt(it)) }
    is JSONObject -> HashMap<String, Any?>().also { map -> value.keys().forEach { map[it] = java(value.opt(it)) } }
    is Int -> value.toDouble()
    is Long -> value.toDouble()
    is Float -> value.toDouble()
    else -> value
  }

  fun gson(value: Any?): JsonElement = JsonParser.parseString(
    when (value) {
      is JSONObject, is JSONArray -> value.toString()
      is String -> JSONObject.quote(value)
      null, JSONObject.NULL -> "null"
      else -> value.toString()
    })

  fun gsonObject(value: JSONObject?): JsonObject =
    JsonParser.parseString((value ?: JSONObject()).toString()).asJsonObject

  fun expression(value: Any?): Expression? = when (value) {
    null, JSONObject.NULL -> null
    is JSONArray -> Expression.Converter.convert(value.toString())
    is Boolean -> Expression.literal(value)
    else -> Expression.Converter.convert(gson(value))
  }

  private fun strings(array: JSONArray?): List<String> =
    (0 until (array?.length() ?: 0)).mapNotNull { array?.optString(it)?.takeIf { s -> s.isNotEmpty() } }

  private fun tileSet(json: JSONObject): TileSet {
    val tiles = strings(json.optJSONArray("tiles"))
    val set = TileSet("2.2.0", *tiles.toTypedArray())
    if (json.has("minzoom")) set.minZoom = json.optDouble("minzoom").toFloat()
    if (json.has("maxzoom")) set.maxZoom = json.optDouble("maxzoom").toFloat()
    json.optJSONArray("bounds")?.let { b ->
      if (b.length() == 4) set.setBounds(b.optDouble(0).toFloat(), b.optDouble(1).toFloat(), b.optDouble(2).toFloat(), b.optDouble(3).toFloat())
    }
    json.optString("scheme").takeIf { it.isNotEmpty() }?.let { set.scheme = it }
    json.optString("attribution").takeIf { it.isNotEmpty() }?.let { set.attribution = it }
    json.optString("encoding").takeIf { it.isNotEmpty() }?.let { set.encoding = it }
    return set
  }

  /** A style-spec source object as a MapLibre source. */
  fun source(id: String, json: JSONObject): Source {
    val type = json.optString("type")
    val url = json.optString("url")
    val hasTiles = (json.optJSONArray("tiles")?.length() ?: 0) > 0
    val tileSize = if (json.has("tileSize")) json.optInt("tileSize") else 0
    return when (type) {
      "vector" -> if (hasTiles) VectorSource(id, tileSet(json)) else VectorSource(id, url)
      "raster" -> when {
        hasTiles && tileSize > 0 -> RasterSource(id, tileSet(json), tileSize)
        hasTiles -> RasterSource(id, tileSet(json))
        tileSize > 0 -> RasterSource(id, url, tileSize)
        else -> RasterSource(id, url)
      }
      "raster-dem" -> when {
        hasTiles && tileSize > 0 -> RasterDemSource(id, tileSet(json), tileSize)
        hasTiles -> RasterDemSource(id, tileSet(json))
        tileSize > 0 -> RasterDemSource(id, url, tileSize)
        else -> RasterDemSource(id, url)
      }
      "geojson" -> {
        val options = GeoJsonOptions()
        if (json.has("cluster")) options.withCluster(json.optBoolean("cluster"))
        if (json.has("clusterRadius")) options.withClusterRadius(json.optInt("clusterRadius"))
        if (json.has("clusterMaxZoom")) options.withClusterMaxZoom(json.optInt("clusterMaxZoom"))
        if (json.has("lineMetrics")) options.withLineMetrics(json.optBoolean("lineMetrics"))
        if (json.has("tolerance")) options.withTolerance(json.optDouble("tolerance").toFloat())
        if (json.has("buffer")) options.withBuffer(json.optInt("buffer"))
        if (json.has("maxzoom")) options.withMaxZoom(json.optInt("maxzoom"))
        if (json.has("minzoom")) options.withMinZoom(json.optInt("minzoom"))
        when (val data = json.opt("data")) {
          is String -> if (data.trimStart().startsWith("{")) GeoJsonSource(id, data, options) else GeoJsonSource(id, URI(data), options)
          is JSONObject -> GeoJsonSource(id, data.toString(), options)
          else -> GeoJsonSource(id, options)
        }
      }
      "image" -> {
        val c = json.optJSONArray("coordinates") ?: throw IllegalArgumentException("image source '$id' needs coordinates")
        fun corner(i: Int): LatLng {
          val p = c.getJSONArray(i)
          return LatLng(p.getDouble(1), p.getDouble(0))
        }
        ImageSource(id, LatLngQuad(corner(0), corner(1), corner(2), corner(3)), URI(url))
      }
      else -> throw IllegalArgumentException("Unknown source type '$type' for '$id'")
    }
  }

  /** Replaces a GeoJSON source's data with GeoJSON (object, string or URL). */
  fun setGeoJson(source: GeoJsonSource, data: Any?) {
    when (data) {
      is String -> if (data.trimStart().startsWith("{")) source.setGeoJson(data) else source.setUri(data)
      is JSONObject -> source.setGeoJson(data.toString())
      else -> source.setGeoJson("""{"type":"FeatureCollection","features":[]}""")
    }
  }

  /** A style-spec layer object as a MapLibre layer (not added yet). */
  fun layer(json: JSONObject): Layer {
    val id = json.getString("id")
    val source = json.optString("source")
    val layer: Layer = when (val type = json.optString("type")) {
      "fill" -> FillLayer(id, source)
      "line" -> LineLayer(id, source)
      "symbol" -> SymbolLayer(id, source)
      "circle" -> CircleLayer(id, source)
      "heatmap" -> HeatmapLayer(id, source)
      "fill-extrusion" -> FillExtrusionLayer(id, source)
      "raster" -> RasterLayer(id, source)
      "hillshade" -> HillshadeLayer(id, source)
      "color-relief" -> ColorReliefLayer(id, source)
      "background" -> BackgroundLayer(id)
      else -> throw IllegalArgumentException("Unknown layer type '$type' for '$id'")
    }
    json.optString("source-layer").takeIf { it.isNotEmpty() }?.let { setSourceLayer(layer, it) }
    if (json.has("minzoom")) layer.minZoom = json.optDouble("minzoom").toFloat()
    if (json.has("maxzoom")) layer.maxZoom = json.optDouble("maxzoom").toFloat()
    if (json.has("filter")) setFilter(layer, json.opt("filter"))
    json.optJSONObject("layout")?.let { setProperties(layer, it, paint = false) }
    json.optJSONObject("paint")?.let { setProperties(layer, it, paint = true) }
    return layer
  }

  fun setProperties(layer: Layer, properties: JSONObject, paint: Boolean) {
    val values = properties.keys().asSequence().map { name ->
      val value = java(properties.opt(name))
      if (paint) PaintPropertyValue(name, value) else LayoutPropertyValue(name, value)
    }.toList()
    layer.setProperties(*values.toTypedArray())
  }

  fun setProperty(layer: Layer, name: String, value: Any?, paint: Boolean) {
    val v = java(value)
    layer.setProperties(if (paint) PaintPropertyValue(name, v) else LayoutPropertyValue(name, v))
  }

  private fun setSourceLayer(layer: Layer, sourceLayer: String) {
    when (layer) {
      is FillLayer -> layer.sourceLayer = sourceLayer
      is LineLayer -> layer.sourceLayer = sourceLayer
      is SymbolLayer -> layer.sourceLayer = sourceLayer
      is CircleLayer -> layer.sourceLayer = sourceLayer
      is HeatmapLayer -> layer.sourceLayer = sourceLayer
      is FillExtrusionLayer -> layer.sourceLayer = sourceLayer
    }
  }

  fun setFilter(layer: Layer, filter: Any?) {
    val expression = expression(filter) ?: Expression.literal(true)
    when (layer) {
      is FillLayer -> layer.setFilter(expression)
      is LineLayer -> layer.setFilter(expression)
      is SymbolLayer -> layer.setFilter(expression)
      is CircleLayer -> layer.setFilter(expression)
      is HeatmapLayer -> layer.setFilter(expression)
      is FillExtrusionLayer -> layer.setFilter(expression)
      else -> throw IllegalArgumentException("Layer '${layer.id}' has no filter")
    }
  }

  /** Adds a layer below `beforeId` when it exists, else under `fallbackBelow`, else on top. */
  fun add(style: Style, layer: Layer, beforeId: String?, fallbackBelow: String?) {
    when {
      !beforeId.isNullOrEmpty() && style.getLayer(beforeId) != null -> style.addLayerBelow(layer, beforeId)
      !fallbackBelow.isNullOrEmpty() && style.getLayer(fallbackBelow) != null -> style.addLayerBelow(layer, fallbackBelow)
      else -> style.addLayer(layer)
    }
  }
}
