package com.munimmaps.engines.google

import android.graphics.Color
import com.google.android.gms.maps.model.BitmapDescriptorFactory
import com.google.android.gms.maps.model.DatasetFeature
import com.google.android.gms.maps.model.FeatureClickEvent
import com.google.android.gms.maps.model.FeatureLayer
import com.google.android.gms.maps.model.FeatureLayerOptions
import com.google.android.gms.maps.model.FeatureStyle
import com.google.android.gms.maps.model.FeatureType
import com.google.android.gms.maps.model.PlaceFeature
import com.google.maps.android.data.Feature
import com.google.maps.android.data.Layer
import com.google.maps.android.data.geojson.GeoJsonFeature
import com.google.maps.android.data.geojson.GeoJsonLayer
import com.google.maps.android.data.geojson.GeoJsonLineStringStyle
import com.google.maps.android.data.geojson.GeoJsonPointStyle
import com.google.maps.android.data.geojson.GeoJsonPolygonStyle
import com.google.maps.android.data.kml.KmlLayer
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.File
import java.net.URL
import java.util.concurrent.Executors

// KML and GeoJSON layers (android-maps-utils) and data-driven styling of
// Google's boundaries and datasets (feature layers, needs a Map ID).

private val loader = Executors.newFixedThreadPool(2)

/** The text of a layer: inline `data` / `geojson`, or `url` / `uri`. */
private fun GoogleMapEngine.loadLayer(item: GJson, inline: String, completion: (String?) -> Unit) {
  when (val raw = item[inline].raw) {
    is String -> return completion(raw)
    is JSONObject -> return completion(raw.toString())
  }
  val source = item["url"].string ?: item["uri"].string ?: return completion(null)
  loader.execute {
    val text = runCatching {
      if (source.startsWith("/")) File(source).readText()
      else if (source.startsWith("file://")) File(source.removePrefix("file://")).readText()
      else URL(source).readText()
    }.getOrNull()
    main.post { completion(text) }
  }
}

/** `google.kmlLayers` and `google.geoJsonLayers`. */
internal fun GoogleMapEngine.applyDataLayers() {
  val map = map ?: return
  val markers = markerManager ?: return
  val wanted = mutableSetOf<String>()
  for ((kind, list) in listOf("kml" to options["kmlLayers"].array, "geojson" to options["geoJsonLayers"].array)) {
    for (item in list) {
      val id = item["id"].string ?: continue
      val key = "$kind:$id"
      wanted.add(key)
      val source = item.toString()
      if (dataLayers[key]?.first == source || pendingLayers[this]?.get(key) == source) continue
      dataLayers.remove(key)?.second?.removeLayerFromMap()
      pendingLayers.getOrPut(this) { mutableMapOf() }[key] = source
      loadLayer(item, if (kind == "kml") "data" else "geojson") { text ->
        if (pendingLayers[this]?.get(key) != source || this.map !== map) return@loadLayer
        pendingLayers[this]?.remove(key)
        if (text == null) return@loadLayer reportError("could not load the ${if (kind == "kml") "KML" else "GeoJSON"} layer $id")
        try {
          val layer: Layer = if (kind == "kml") {
            KmlLayer(map, ByteArrayInputStream(text.toByteArray()), context, markers, polygonManager, polylineManager, groundOverlayManager, null)
          } else {
            GeoJsonLayer(map, JSONObject(text), markers, polygonManager, polylineManager, groundOverlayManager).also { style(it, item["style"]) }
          }
          layer.addLayerToMap()
          layer.setOnFeatureClickListener { feature -> layerFeatureTapped(kind, id, feature) }
          dataLayers[key] = source to layer
          val count = if (layer is KmlLayer) layer.placemarks.count() else (layer as GeoJsonLayer).features.count()
          emit(if (kind == "kml") "kmlLayerLoaded" else "geoJsonLayerLoaded",
            GOut.obj("id" to id, if (kind == "kml") "placemarks" to count else "features" to count))
        } catch (error: Exception) {
          reportError("could not read the ${if (kind == "kml") "KML" else "GeoJSON"} layer $id: ${error.message}")
        }
      }
    }
  }
  for (key in dataLayers.keys.toList()) if (key !in wanted) dataLayers.remove(key)?.second?.removeLayerFromMap()
  pendingLayers[this]?.keys?.retainAll(wanted)
}

private val pendingLayers = java.util.WeakHashMap<GoogleMapEngine, MutableMap<String, String>>()

private fun GoogleMapEngine.layerFeatureTapped(kind: String, layerId: String, feature: Feature) {
  val properties = JSONObject()
  for (key in feature.propertyKeys) properties.put(key, feature.getProperty(key) ?: JSONObject.NULL)
  if (kind == "kml") {
    emit("kmlFeaturePress", GOut.obj("layerId" to layerId, "title" to (feature.getProperty("name") ?: ""),
      "snippet" to (feature.getProperty("description") ?: ""), "properties" to properties))
  } else {
    emit("geoJsonFeaturePress", GOut.obj("layerId" to layerId, "featureId" to (feature.id ?: ""), "properties" to properties))
  }
}

/** The layer's default style, and each feature's simplestyle properties. */
private fun GoogleMapEngine.style(layer: GeoJsonLayer, style: GJson) {
  val stroke = style["strokeColor"].color ?: Color.rgb(10, 132, 255)
  val fill = style["fillColor"].color ?: Color.argb(64, 10, 132, 255)
  val width = (style["strokeWidth"].double(2.0) * density).toFloat()
  val z = style["zIndex"].double(0.0).toFloat()
  val geodesic = style["geodesic"].bool(false)
  val tappable = style["tappable"].bool(true)
  layer.defaultPolygonStyle.apply {
    strokeColor = stroke
    fillColor = fill
    strokeWidth = width
    zIndex = z
    isGeodesic = geodesic
    isClickable = tappable
  }
  layer.defaultLineStringStyle.apply {
    color = stroke
    this.width = width
    zIndex = z
    isGeodesic = geodesic
    isClickable = tappable
  }
  style["pointColor"].color?.let { color ->
    val hsv = FloatArray(3)
    Color.colorToHSV(color, hsv)
    layer.defaultPointStyle.icon = BitmapDescriptorFactory.defaultMarker(hsv[0])
  }
  for (feature: GeoJsonFeature in layer.features) {
    fun color(key: String, opacity: String): Int? {
      val base = feature.getProperty(key)?.let { GJson.parseColor(it) } ?: return null
      val alpha = feature.getProperty(opacity)?.toDoubleOrNull() ?: return base
      return Color.argb((alpha * 255).toInt(), Color.red(base), Color.green(base), Color.blue(base))
    }
    val s = color("stroke", "stroke-opacity")
    val f = color("fill", "fill-opacity")
    val w = feature.getProperty("stroke-width")?.toDoubleOrNull()
    if (s != null || f != null || w != null) {
      feature.polygonStyle = GeoJsonPolygonStyle().apply {
        strokeColor = s ?: stroke
        fillColor = f ?: fill
        strokeWidth = ((w ?: style["strokeWidth"].double(2.0)) * density).toFloat()
        zIndex = z
        isGeodesic = geodesic
        isClickable = tappable
      }
      feature.lineStringStyle = GeoJsonLineStringStyle().apply {
        color = s ?: stroke
        this.width = ((w ?: style["strokeWidth"].double(2.0)) * density).toFloat()
        zIndex = z
        isGeodesic = geodesic
        isClickable = tappable
      }
    }
    feature.getProperty("marker-color")?.let { GJson.parseColor(it) }?.let { color ->
      val hsv = FloatArray(3)
      Color.colorToHSV(color, hsv)
      feature.pointStyle = GeoJsonPointStyle().apply {
        icon = BitmapDescriptorFactory.defaultMarker(hsv[0])
        title = feature.getProperty("title") ?: feature.getProperty("name")
      }
    }
  }
}

// MARK: Feature layers (data-driven styling)

private val clickListenerAdded = java.util.WeakHashMap<FeatureLayer, Boolean>()

/**
 * `google.featureLayers`: style Google's boundaries (`featureType`) or a
 * dataset (`datasetId`). Needs a Map ID whose style has the layer on.
 */
internal fun GoogleMapEngine.applyFeatureLayers() {
  val map = map ?: return
  val wanted = mutableMapOf<String, String>()
  for (item in options["featureLayers"].array) {
    val datasetId = item["datasetId"].string
    val type = featureType(item["featureType"].string ?: "")
    val key = if (datasetId != null) "dataset:$datasetId" else type?.let { "type:$it" } ?: continue
    wanted[key] = item.toString()
    if (featureLayerKeys[key] == item.toString()) continue
    val options = if (datasetId != null) FeatureLayerOptions.builder().featureType(FeatureType.DATASET).datasetId(datasetId).build()
    else FeatureLayerOptions.builder().featureType(type!!).build()
    val layer = try {
      map.getFeatureLayer(options)
    } catch (error: Exception) {
      reportError("the feature layer $key is not available: ${error.message}")
      continue
    }
    if (!layer.isAvailable) {
      reportError("the feature layer $key is not available. It needs a mapId whose map style has it turned on (Cloud console)")
    }
    val styles = GoogleFeatureStyles(item)
    layer.setFeatureStyle { feature -> styles.style(feature) }
    if (clickListenerAdded[layer] != true) {
      clickListenerAdded[layer] = true
      layer.addOnFeatureClickListener { event -> featuresTapped(event, key) }
    }
  }
  for (key in featureLayerKeys.keys.toList()) if (key !in wanted) {
    val options = if (key.startsWith("dataset:")) {
      FeatureLayerOptions.builder().featureType(FeatureType.DATASET).datasetId(key.removePrefix("dataset:")).build()
    } else FeatureLayerOptions.builder().featureType(key.removePrefix("type:")).build()
    runCatching { map.getFeatureLayer(options).setFeatureStyle { null } }
  }
  featureLayerKeys.clear()
  featureLayerKeys.putAll(wanted)
}

private fun featureType(name: String): String? = when (name.uppercase().replace("-", "_")) {
  "COUNTRY" -> FeatureType.COUNTRY
  "ADMINISTRATIVE_AREA_LEVEL_1", "ADMINISTRATIVEAREALEVEL1" -> FeatureType.ADMINISTRATIVE_AREA_LEVEL_1
  "ADMINISTRATIVE_AREA_LEVEL_2", "ADMINISTRATIVEAREALEVEL2" -> FeatureType.ADMINISTRATIVE_AREA_LEVEL_2
  "LOCALITY" -> FeatureType.LOCALITY
  "POSTAL_CODE", "POSTALCODE" -> FeatureType.POSTAL_CODE
  "SCHOOL_DISTRICT", "SCHOOLDISTRICT" -> FeatureType.SCHOOL_DISTRICT
  else -> null
}

private fun GoogleMapEngine.featuresTapped(event: FeatureClickEvent, layer: String) {
  val list = JSONArray()
  for (feature in event.features) {
    val entry = JSONObject().put("featureType", feature.featureType)
    if (feature is PlaceFeature) entry.put("placeId", feature.placeId)
    if (feature is DatasetFeature) {
      entry.put("datasetId", feature.datasetId)
      entry.put("attributes", JSONObject(feature.datasetAttributes as Map<*, *>))
    }
    list.put(entry)
  }
  emit("featureClick", GOut.obj("featureType" to layer.substringAfter(":"), "layer" to layer, "features" to list,
    "latitude" to event.latLng.latitude, "longitude" to event.latLng.longitude))
}

/** A feature layer's styles: `style`, `placeStyles` by place ID, `attributeStyles` for datasets. */
class GoogleFeatureStyles(item: GJson) {
  private val base: FeatureStyle? = if (item["style"].exists) style(item["style"]) else null
  private val byPlace: Map<String, FeatureStyle> = item["placeStyles"].keys.associateWith { style(item["placeStyles"][it]) }
  private val attribute: String? = item["attributeStyles"]["attribute"].string
  private val byValue: Map<String, FeatureStyle> =
    item["attributeStyles"]["values"].keys.associateWith { style(item["attributeStyles"]["values"][it]) }

  fun style(feature: com.google.android.gms.maps.model.Feature): FeatureStyle? {
    if (feature is PlaceFeature) byPlace[feature.placeId]?.let { return it }
    if (feature is DatasetFeature && attribute != null) {
      feature.datasetAttributes[attribute]?.let { value -> byValue[value]?.let { return it } }
    }
    return base
  }

  companion object {
    fun style(json: GJson): FeatureStyle {
      val builder = FeatureStyle.builder()
      json["fillColor"].color?.let { builder.fillColor(it) }
      json["strokeColor"].color?.let { builder.strokeColor(it) }
      json["strokeWidth"].double?.let { builder.strokeWidth(it.toFloat()) }
      json["pointRadius"].double?.let { builder.pointRadius(it.toFloat()) }
      return builder.build()
    }
  }
}
