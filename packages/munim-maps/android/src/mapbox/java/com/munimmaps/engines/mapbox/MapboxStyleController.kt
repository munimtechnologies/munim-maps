@file:OptIn(MapboxExperimental::class)

package com.munimmaps.engines.mapbox

import android.content.res.Configuration
import android.graphics.Bitmap
import com.mapbox.bindgen.Value
import com.mapbox.common.Cancelable
import com.mapbox.maps.ClickInteraction
import com.mapbox.maps.ImageContent
import com.mapbox.maps.ImageStretches
import com.mapbox.maps.ImportPosition
import com.mapbox.maps.LayerPosition
import com.mapbox.maps.LongClickInteraction
import com.mapbox.maps.MapboxExperimental
import com.mapbox.maps.interactions.FeatureState
import com.mapbox.maps.interactions.FeaturesetFeature
import com.mapbox.maps.toMapboxImage
import com.margelo.nitro.munimmaps.MapColorScheme
import com.margelo.nitro.munimmaps.MapElevation
import com.margelo.nitro.munimmaps.MapStyle
import com.munimmaps.models.ModelAssets
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Mapbox's style, from the shared props and `mapbox={{…}}`:
 *
 * - The style itself: `styleJson`, else `styleUrl`, else the configured
 *   default, else from `mapStyle` (Mapbox Standard; Standard Satellite for
 *   `hybrid` / `imagery`).
 * - Standard's configuration (the `basemap` import): `mapStyle` (`muted` is
 *   the faded theme, `imagery` hides roads and labels), `colorScheme` (night
 *   light preset when dark), `showsBuildings`, `pointsOfInterest`, then
 *   `standard`, `lightPreset` and `importConfig`.
 * - Projection, atmosphere, terrain, lights, snow, rain, colour theme,
 *   imports, sources, layers, images and models: declarative, diffed against
 *   what was applied last, and re-applied after every style load (a style
 *   load drops everything added at runtime).
 * - Events (`events`) and featureset / layer interactions (`interactions`).
 */
internal class MapboxStyleController(private val engine: MapboxMapEngine) {
  private var options = JSONObject()

  /** The style that is loaded (or loading), as `uri:…` or `json:…`. */
  private var loadedKey: String? = null
  private var refreshPosted = false

  // What the loaded style had before we changed it, to restore on removal.
  private var original = JSONObject()

  // What was applied to the loaded style.
  private var appliedConfig = mutableMapOf<String, Any?>()
  private var appliedImports = mutableMapOf<String, JSONObject>()
  private var appliedSources = mutableMapOf<String, JSONObject>()
  private var appliedLayers = mutableListOf<JSONObject>()
  private var appliedImages = mutableMapOf<String, JSONObject>()
  private var appliedModels = mutableMapOf<String, String>()
  private var appliedProjection: String? = null
  private var appliedTopLevel = mutableMapOf<String, Any?>()
  private var trafficOn = false
  private var basemapSchema: JSONObject? = null

  /** Read by the 3D layer every frame. */
  var isGlobe = false
    private set
  var terrainOn = false
    private set
  var isDark = false
    private set

  private val events = mutableMapOf<String, Cancelable>()
  private var eventNames = setOf<String>()
  private val interactionCancelables = mutableListOf<Cancelable>()
  private var appliedInteractions: JSONArray? = null
  private val selectedByInteraction = mutableMapOf<String, FeaturesetFeature<FeatureState>>()

  fun setOptions(next: JSONObject) {
    options = next
    updateEvents()
    updateInteractions()
    scheduleRefresh()
  }

  /** Coalesces prop changes into one refresh on the next main-loop turn. */
  fun scheduleRefresh() {
    if (refreshPosted) return
    refreshPosted = true
    engine.main.post {
      refreshPosted = false
      if (!engine.destroyed) refresh()
    }
  }

  private fun styleKey(): Pair<String, Boolean> {
    options.opt("styleJson")?.let { json ->
      val text = when (json) {
        is JSONObject -> json.toString()
        is String -> json
        else -> null
      }
      if (!text.isNullOrBlank()) return text to true
    }
    if (engine.styleUrl.isNotBlank()) return engine.styleUrl to false
    val configured = com.munimmaps.engine.MunimMapsConfiguration.mapboxStyleUrl
    if (configured.isNotBlank()) return configured to false
    return when (engine.mapStyle) {
      MapStyle.HYBRID, MapStyle.IMAGERY -> STANDARD_SATELLITE to false
      else -> STANDARD to false
    }
  }

  private fun refresh() {
    val (style, isJson) = styleKey()
    val key = (if (isJson) "json:" else "uri:") + style
    if (key != loadedKey) {
      loadedKey = key
      engine.loadStyle(if (isJson) null else style, if (isJson) style else null) { styleLoaded() }
      return
    }
    if (engine.styleLoaded) applyAll()
  }

  private fun styleLoaded() {
    val map = engine.map
    original = (MapboxJson.parse(map.styleJSON) as? JSONObject) ?: JSONObject()
    appliedConfig.clear()
    appliedImports.clear()
    appliedSources.clear()
    appliedLayers.clear()
    appliedImages.clear()
    appliedModels.clear()
    appliedProjection = null
    appliedTopLevel.clear()
    trafficOn = false
    basemapSchema = null
    selectedByInteraction.clear()
    applyAll()
  }

  private fun applyAll() {
    if (!engine.styleLoaded) return
    applyImports()
    applyBasemapConfig()
    applyProjection()
    applyTopLevel()
    applyImages()
    applyModels()
    applySources()
    applyLayers()
    applyTraffic()
    applyRendering()
    engine.modelLayer.setNeedsRender()
  }

  // Standard

  private val hasBasemap: Boolean
    get() = engine.map.getStyleImports().any { it.id == BASEMAP }

  private fun systemDark(): Boolean =
    (engine.context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES

  private fun wantsDark(): Boolean = when (engine.colorScheme) {
    MapColorScheme.DARK -> true
    MapColorScheme.LIGHT -> false
    MapColorScheme.SYSTEM -> systemDark()
  }

  /** The `basemap` config from the shared props, then `standard`, `lightPreset`, `importConfig.basemap`. */
  private fun desiredBasemapConfig(): Map<String, Any?> {
    val config = linkedMapOf<String, Any?>()
    config["lightPreset"] = if (wantsDark()) "night" else "day"
    config["show3dObjects"] = engine.showsBuildings
    when (engine.mapStyle) {
      MapStyle.MUTED -> config["theme"] = "faded"
      MapStyle.IMAGERY -> {
        for (k in listOf("showRoadsAndTransit", "showPlaceLabels", "showPointOfInterestLabels", "showTransitLabels",
          "showRoadLabels", "showAdminBoundaries", "showLandmarkIcons", "showLandmarkIconLabels")) config[k] = false
      }
      else -> {}
    }
    when (engine.pointsOfInterest.trim()) {
      "none" -> config["showPointOfInterestLabels"] = false
      "", "all" -> if (engine.mapStyle != MapStyle.IMAGERY) config["showPointOfInterestLabels"] = true
      else -> {}
    }
    // Only keys this style's basemap knows (Standard and Standard Satellite differ).
    val schema = schema()
    if (schema != null) config.keys.retainAll { schema.has(it) }
    options.optJSONObject("standard")?.let { standard -> standard.keys().forEach { config[it] = standard.opt(it) } }
    options.optString("lightPreset", "").takeIf { it.isNotEmpty() }?.let { config["lightPreset"] = it }
    options.optJSONObject("importConfig")?.optJSONObject(BASEMAP)?.let { c -> c.keys().forEach { config[it] = c.opt(it) } }
    return config
  }

  private fun schema(): JSONObject? {
    basemapSchema?.let { return it }
    val result = engine.map.getStyleImportSchema(BASEMAP)
    val json = result.value?.let { MapboxJson.json(it) as? JSONObject }
    basemapSchema = json
    return json
  }

  private fun applyBasemapConfig() {
    val map = engine.map
    if (!hasBasemap) {
      isDark = wantsDark() && (loadedKey?.contains("dark") == true || loadedKey?.contains("night") == true)
      applyImportConfigs()
      return
    }
    val desired = desiredBasemapConfig()
    val changed = HashMap<String, Value>()
    for ((k, v) in desired) {
      if (appliedConfig.containsKey(k) && MapboxJson.same(appliedConfig[k], v)) continue
      changed[k] = MapboxJson.value(v)
    }
    // Keys no longer set go back to the style's defaults.
    for (k in appliedConfig.keys - desired.keys) {
      val default = schema()?.optJSONObject(k)?.opt("default")
      if (default != null) changed[k] = MapboxJson.value(default)
    }
    for ((k, v) in changed) {
      MapboxJson.error(map.setStyleImportConfigProperty(BASEMAP, k, v))?.let { engine.report("standard.$k: $it") }
    }
    appliedConfig = desired.toMutableMap()
    val preset = desired["lightPreset"] as? String
    isDark = preset == "night" || preset == "dusk"
    applyImportConfigs()
  }

  /** `importConfig` for imports other than `basemap`. */
  private fun applyImportConfigs() {
    val all = options.optJSONObject("importConfig") ?: return
    for (importId in all.keys()) {
      if (importId == BASEMAP && hasBasemap) continue
      val config = all.optJSONObject(importId) ?: continue
      val key = "importConfig:$importId"
      if (MapboxJson.same(appliedTopLevel[key], config)) continue
      val map = HashMap<String, Value>()
      config.keys().forEach { map[it] = MapboxJson.value(config.opt(it)) }
      MapboxJson.error(engine.map.setStyleImportConfigProperties(importId, map))?.let { engine.report("importConfig.$importId: $it") }
      appliedTopLevel[key] = config
    }
  }

  // Imports

  private fun applyImports() {
    val map = engine.map
    val wanted = linkedMapOf<String, JSONObject>()
    options.optJSONArray("imports")?.let { list ->
      for (i in 0 until list.length()) list.optJSONObject(i)?.let { item -> item.optString("id").takeIf { it.isNotEmpty() }?.let { wanted[it] = item } }
    }
    for (id in appliedImports.keys - wanted.keys) map.removeStyleImport(id)
    for ((id, item) in wanted) {
      val previous = appliedImports[id]
      if (previous != null && MapboxJson.same(previous, item)) continue
      val config = HashMap<String, Value>()
      item.optJSONObject("config")?.let { c -> c.keys().forEach { config[it] = MapboxJson.value(c.opt(it)) } }
      val json = item.opt("json")?.let { if (it is JSONObject) it.toString() else it as? String }
      val url = item.optString("url", "")
      val sameSource = previous != null && MapboxJson.same(previous.opt("json"), item.opt("json")) && previous.optString("url") == url
      val error = if (previous != null && sameSource) {
        map.setStyleImportConfigProperties(id, config).error
      } else if (previous != null) {
        if (json != null) map.updateStyleImportWithJSON(id, json, config).error
        else map.updateStyleImportWithURI(id, url, config).error
      } else {
        val position = item.optString("beforeId", "").takeIf { it.isNotEmpty() }?.let { ImportPosition(null, it, null) }
        if (json != null) map.addStyleImportFromJSON(id, json, config, position).error
        else map.addStyleImportFromURI(id, url, config, position).error
      }
      if (error != null) engine.report("import $id: $error") else appliedImports[id] = item
    }
    appliedImports.keys.retainAll(wanted.keys)
  }

  // Projection, atmosphere, terrain, lights, snow, rain, colour theme

  private fun applyProjection() {
    val name = options.optString("projection", "").ifEmpty { if (engine.globe) "globe" else "mercator" }
    isGlobe = name == "globe"
    if (name == appliedProjection) return
    MapboxJson.error(engine.map.setStyleProjection(MapboxJson.value(JSONObject().put("name", name))))?.let { engine.report("projection: $it") }
    appliedProjection = name
  }

  private fun applyTopLevel() {
    val map = engine.map
    // Atmosphere (fog)
    setTopLevel("atmosphere", options.opt("atmosphere"), "fog") { map.setStyleAtmosphere(it) }
    // Terrain
    val terrain = desiredTerrain()
    terrainOn = terrain != null && terrain != JSONObject.NULL
    if (terrain is JSONObject && terrain.optString("source") == TERRAIN_SOURCE && !map.styleSourceExists(TERRAIN_SOURCE)) {
      map.addStyleSource(TERRAIN_SOURCE, MapboxJson.value(JSONObject()
        .put("type", "raster-dem").put("url", "mapbox://mapbox.mapbox-terrain-dem-v1").put("tileSize", 514).put("maxzoom", 14)))
    }
    setTopLevel("terrain", terrain ?: UNSET, "terrain") { map.setStyleTerrain(it) }
    // Lights
    setTopLevel("lights", options.opt("lights"), "lights") { map.setStyleLights(it) }
    // Snow and rain (experimental in the SDK)
    setTopLevel("snow", options.opt("snow"), "snow") { map.setStyleSnow(it) }
    setTopLevel("rain", options.opt("rain"), "rain") { map.setStyleRain(it) }
    // Colour theme
    val theme = options.opt("colorTheme")
    if (!MapboxJson.same(appliedTopLevel["colorTheme"], theme)) {
      when {
        theme is JSONObject && theme.optString("data").isNotEmpty() -> {
          val data = theme.optString("data").substringAfter("base64,")
          MapboxJson.error(map.setStyleColorTheme(data))?.let { engine.report("colorTheme: $it") }
          if (hasBasemap) map.setImportColorTheme(BASEMAP, data)
        }
        theme == false -> {
          map.setStyleColorTheme(null as com.mapbox.maps.ColorTheme?)
          if (hasBasemap) map.setImportColorTheme(BASEMAP, null as com.mapbox.maps.ColorTheme?)
        }
        appliedTopLevel.containsKey("colorTheme") -> map.setInitialStyleColorTheme()
      }
      appliedTopLevel["colorTheme"] = theme
    }
  }

  /**
   * One top-level style property (`fog`, `terrain`, `lights`, `snow`,
   * `rain`): an object sets it, `false` removes it, absent restores what the
   * style had.
   */
  private fun setTopLevel(key: String, value: Any?, styleKey: String, set: (Value) -> com.mapbox.bindgen.Expected<String, com.mapbox.bindgen.None>) {
    val wanted = if (value == null) UNSET else value
    if (appliedTopLevel.containsKey(key) && MapboxJson.same(appliedTopLevel[key], wanted)) return
    if (!appliedTopLevel.containsKey(key) && wanted == UNSET) {
      appliedTopLevel[key] = UNSET
      return
    }
    val applied = when {
      wanted == UNSET -> original.opt(styleKey)?.let { MapboxJson.value(it) } ?: Value.nullValue()
      wanted == false || wanted == JSONObject.NULL -> Value.nullValue()
      else -> MapboxJson.value(wanted)
    }
    MapboxJson.error(set(applied))?.let { engine.report("$key: $it") }
    appliedTopLevel[key] = wanted
  }

  /** The terrain to set: the option, the exaggeration shorthand, or the default for realistic imagery. */
  private fun desiredTerrain(): Any? {
    val option = options.opt("terrain")
    val exaggeration = if (options.has("terrainExaggeration")) options.optDouble("terrainExaggeration", 1.0) else null
    if (exaggeration != null && exaggeration <= 0) return false
    val terrain: Any? = when (option) {
      is JSONObject -> JSONObject(option.toString()).apply { if (!has("source")) put("source", TERRAIN_SOURCE) }
      true -> JSONObject().put("source", TERRAIN_SOURCE).put("exaggeration", 1)
      false -> false
      else -> {
        val auto = engine.elevation == MapElevation.REALISTIC && (engine.mapStyle == MapStyle.HYBRID || engine.mapStyle == MapStyle.IMAGERY)
        if (auto || exaggeration != null) JSONObject().put("source", TERRAIN_SOURCE).put("exaggeration", 1) else null
      }
    }
    if (terrain is JSONObject && exaggeration != null) terrain.put("exaggeration", exaggeration)
    return terrain
  }

  // Sources and layers

  private fun applySources() {
    val map = engine.map
    val wanted = linkedMapOf<String, JSONObject>()
    options.optJSONObject("sources")?.let { all -> all.keys().forEach { id -> all.optJSONObject(id)?.let { wanted[id] = it } } }
    // Removed sources: their layers go first.
    for (id in appliedSources.keys - wanted.keys) {
      removeLayersUsing(id)
      map.removeStyleSource(id)
    }
    appliedSources.keys.retainAll(wanted.keys)
    for ((id, source) in wanted) {
      val previous = appliedSources[id]
      if (previous != null && MapboxJson.same(previous, source)) continue
      if (previous != null && previous.optString("type") == source.optString("type")) {
        val changed = JSONObject()
        for (k in source.keys()) if (!MapboxJson.same(previous.opt(k), source.opt(k))) changed.put(k, source.opt(k))
        if (map.setStyleSourceProperties(id, MapboxJson.value(changed)).error == null) {
          appliedSources[id] = source
          continue
        }
      }
      if (previous != null || map.styleSourceExists(id)) {
        val layers = removeLayersUsing(id)
        map.removeStyleSource(id)
        addSource(id, source)
        layers.forEach { addLayer(it, null) }
      } else {
        addSource(id, source)
      }
    }
  }

  private fun addSource(id: String, source: JSONObject) {
    val error = engine.map.addStyleSource(id, MapboxJson.value(source)).error
    if (error != null) engine.report("source $id: $error") else appliedSources[id] = source
  }

  /** Removes our layers that draw [sourceId]; returns them so they can come back. */
  private fun removeLayersUsing(sourceId: String): List<JSONObject> {
    val removed = appliedLayers.filter { it.optString("source") == sourceId }
    removed.forEach { engine.map.removeStyleLayer(it.optString("id")) }
    appliedLayers.removeAll(removed)
    return removed
  }

  private fun layerJson(layer: JSONObject): JSONObject {
    val json = JSONObject(layer.toString())
    json.remove("beforeId")
    json.remove("aboveId")
    json.remove("index")
    return json
  }

  private fun position(layer: JSONObject, previousId: String?): LayerPosition? {
    layer.optString("beforeId", "").takeIf { it.isNotEmpty() }?.let { return LayerPosition(null, it, null) }
    layer.optString("aboveId", "").takeIf { it.isNotEmpty() }?.let { return LayerPosition(it, null, null) }
    if (layer.has("index")) return LayerPosition(null, null, layer.optInt("index"))
    // In order: above the previous layer of the list in the same slot.
    return previousId?.let { LayerPosition(it, null, null) }
  }

  private fun addLayer(layer: JSONObject, position: LayerPosition?): Boolean {
    val id = layer.optString("id")
    val error = engine.map.addStyleLayer(MapboxJson.value(layerJson(layer)), position).error
    if (error != null) {
      engine.report("layer $id: $error")
      return false
    }
    appliedLayers.add(layer)
    return true
  }

  private fun applyLayers() {
    val map = engine.map
    val wanted = mutableListOf<JSONObject>()
    options.optJSONArray("layers")?.let { list -> for (i in 0 until list.length()) list.optJSONObject(i)?.let { if (it.optString("id").isNotEmpty()) wanted.add(it) } }
    val wantedIds = wanted.map { it.optString("id") }.toSet()
    for (layer in appliedLayers.toList()) {
      if (layer.optString("id") !in wantedIds) {
        map.removeStyleLayer(layer.optString("id"))
        appliedLayers.remove(layer)
      }
    }
    var previousInSlot = mutableMapOf<String, String>()
    for (layer in wanted) {
      val id = layer.optString("id")
      val slot = layer.optString("slot", "")
      val previous = appliedLayers.firstOrNull { it.optString("id") == id }
      val position = position(layer, previousInSlot[slot])
      if (previous == null) {
        if (map.styleLayerExists(id)) map.removeStyleLayer(id)
        addLayer(layer, position)
      } else if (!MapboxJson.same(previous, layer)) {
        val structural = listOf("type", "source", "source-layer").any { previous.optString(it) != layer.optString(it) }
        if (structural) {
          map.removeStyleLayer(id)
          appliedLayers.remove(previous)
          addLayer(layer, position)
        } else {
          val update = JSONObject()
          for (group in listOf("paint", "layout")) {
            val before = previous.optJSONObject(group) ?: JSONObject()
            val after = layer.optJSONObject(group) ?: JSONObject()
            val diff = JSONObject()
            after.keys().forEach { if (!MapboxJson.same(before.opt(it), after.opt(it))) diff.put(it, after.opt(it)) }
            before.keys().forEach { if (!after.has(it)) diff.put(it, JSONObject.NULL) }
            if (diff.length() > 0) update.put(group, diff)
          }
          for (k in listOf("filter", "minzoom", "maxzoom", "slot")) {
            if (!MapboxJson.same(previous.opt(k), layer.opt(k))) update.put(k, layer.opt(k) ?: JSONObject.NULL)
          }
          if (update.length() > 0) {
            MapboxJson.error(map.setStyleLayerProperties(id, MapboxJson.value(update)))?.let { engine.report("layer $id: $it") }
          }
          val moved = listOf("beforeId", "aboveId", "index").any { !MapboxJson.same(previous.opt(it), layer.opt(it)) }
          if (moved && position != null) map.moveStyleLayer(id, position)
          appliedLayers[appliedLayers.indexOf(previous)] = layer
        }
      }
      previousInSlot[slot] = id
    }
  }

  // Images and models

  private fun applyImages() {
    val map = engine.map
    val wanted = linkedMapOf<String, JSONObject>()
    options.optJSONObject("images")?.let { all -> all.keys().forEach { id -> all.optJSONObject(id)?.let { wanted[id] = it } } }
    for (id in appliedImages.keys - wanted.keys) map.removeStyleImage(id)
    appliedImages.keys.retainAll(wanted.keys)
    for ((id, image) in wanted) {
      if (appliedImages[id]?.let { MapboxJson.same(it, image) } == true) continue
      appliedImages[id] = image
      val uri = image.optString("uri")
      MarkerPhotos.load(engine.context, uri) { bitmap ->
        if (engine.destroyed || appliedImages[id] !== image || !engine.styleLoaded) return@load
        if (bitmap == null) {
          engine.report("image $id: could not load $uri")
          return@load
        }
        addImage(id, image, bitmap)
      }
    }
  }

  private fun addImage(id: String, image: JSONObject, bitmap: Bitmap) {
    val argb = if (bitmap.config == Bitmap.Config.ARGB_8888) bitmap else bitmap.copy(Bitmap.Config.ARGB_8888, false)
    val scale = if (image.has("scale")) image.optDouble("scale", engine.density).toFloat() else engine.density.toFloat()
    fun stretches(key: String) = image.optJSONArray(key)?.let { list ->
      (0 until list.length()).mapNotNull { i -> list.optJSONArray(i)?.let { ImageStretches(it.optDouble(0).toFloat(), it.optDouble(1).toFloat()) } }
    } ?: emptyList()
    val content = image.optJSONArray("content")?.let {
      ImageContent(it.optDouble(0).toFloat(), it.optDouble(1).toFloat(), it.optDouble(2).toFloat(), it.optDouble(3).toFloat())
    }
    MapboxJson.error(engine.map.addStyleImage(id, scale, argb.toMapboxImage(), image.optBoolean("sdf", false),
      stretches("stretchX"), stretches("stretchY"), content))?.let { engine.report("image $id: $it") }
  }

  private fun applyModels() {
    val map = engine.map
    val wanted = linkedMapOf<String, String>()
    options.optJSONObject("models")?.let { all -> all.keys().forEach { id -> all.optString(id).takeIf { it.isNotEmpty() }?.let { wanted[id] = it } } }
    for (id in appliedModels.keys - wanted.keys) map.removeStyleModel(id)
    appliedModels.keys.retainAll(wanted.keys)
    for ((id, uri) in wanted) {
      if (appliedModels[id] == uri) continue
      appliedModels[id] = uri
      modelUri(uri) { resolved ->
        if (engine.destroyed || appliedModels[id] != uri || !engine.styleLoaded) return@modelUri
        if (resolved == null) {
          engine.report("model $id: could not load $uri")
          return@modelUri
        }
        MapboxJson.error(engine.map.addStyleModel(id, resolved))?.let { engine.report("model $id: $it") }
      }
    }
  }

  /**
   * A model URI Mapbox can read: `http(s)://`, `file://`, `asset://` and
   * `mapbox://` as they are; React Native release-build names (raw
   * resources) are copied to a cache file first.
   */
  fun modelUri(uri: String, completion: (String?) -> Unit) {
    val scheme = android.net.Uri.parse(uri).scheme?.lowercase()
    when {
      // Remote files go through munim-maps' disk cache (offline after the
      // first load); Metro's dev server is read fresh by Mapbox.
      (scheme == "http" || scheme == "https") && ModelAssets.cacheFile(engine.context, uri) != null ->
        ModelAssets.load(engine.context, uri) { result ->
          val file = ModelAssets.cacheFile(engine.context, uri)
          completion(if (result.isSuccess && file != null && file.isFile) "file://${file.absolutePath}" else uri)
        }
      scheme == "http" || scheme == "https" || scheme == "file" || scheme == "mapbox" -> completion(uri)
      scheme == "asset" -> completion("asset://" + uri.removePrefix("asset:").trimStart('/'))
      uri.startsWith("/") -> completion("file://$uri")
      else -> ModelAssets.load(engine.context, uri) { result ->
        val bytes = result.getOrNull()
        if (bytes == null) {
          completion(null)
        } else {
          val file = File(engine.context.cacheDir, "munim-maps-model-${uri.hashCode()}.glb")
          runCatching { if (!file.exists() || file.length() != bytes.size.toLong()) file.writeBytes(bytes) }
          completion("file://${file.absolutePath}")
        }
      }
    }
  }

  // Traffic

  private fun applyTraffic() {
    val map = engine.map
    if (engine.showsTraffic == trafficOn) return
    if (engine.showsTraffic) {
      if (!map.styleSourceExists(TRAFFIC_SOURCE)) {
        map.addStyleSource(TRAFFIC_SOURCE, MapboxJson.value(JSONObject().put("type", "vector").put("url", "mapbox://mapbox.mapbox-traffic-v1")))
      }
      val layer = JSONObject()
        .put("id", TRAFFIC_LAYER).put("type", "line").put("source", TRAFFIC_SOURCE).put("source-layer", "traffic")
        .put("layout", JSONObject().put("line-join", "round").put("line-cap", "round"))
        .put("paint", JSONObject()
          .put("line-width", JSONArray("[\"interpolate\",[\"exponential\",1.5],[\"zoom\"],10,1.5,14,3,18,9]"))
          .put("line-color", JSONArray("[\"match\",[\"get\",\"congestion\"],\"low\",\"#34C759\",\"moderate\",\"#FFCC00\",\"heavy\",\"#FF9500\",\"severe\",\"#FF3B30\",\"#8E8E93\"]"))
          .put("line-offset", JSONArray("[\"interpolate\",[\"linear\"],[\"zoom\"],10,0.5,18,4]")))
      if (slots().contains("middle")) layer.put("slot", "middle")
      val position = if (slots().contains("middle")) null else firstSymbolLayer()?.let { LayerPosition(null, it, null) }
      MapboxJson.error(map.addStyleLayer(MapboxJson.value(layer), position))?.let { engine.report("traffic: $it") }
    } else {
      if (map.styleLayerExists(TRAFFIC_LAYER)) map.removeStyleLayer(TRAFFIC_LAYER)
      if (map.styleSourceExists(TRAFFIC_SOURCE)) map.removeStyleSource(TRAFFIC_SOURCE)
    }
    trafficOn = engine.showsTraffic
  }

  fun slots(): List<String> = try {
    engine.map.styleSlots
  } catch (_: Throwable) {
    emptyList()
  }

  /** The first symbol layer of a classic style (labels start there). */
  fun firstSymbolLayer(): String? {
    val map = engine.map
    return map.styleLayers.firstOrNull { it.type == "symbol" && !it.id.startsWith("mapbox-android-") && !it.id.startsWith("munim-") }?.id
  }

  // Rendering and debug

  private var appliedRendering: JSONObject? = null
  private var appliedDebug: JSONArray? = null

  private fun applyRendering() {
    val map = engine.map
    val rendering = options.optJSONObject("rendering") ?: JSONObject()
    if (!MapboxJson.same(appliedRendering, rendering)) {
      appliedRendering = rendering
      if (rendering.has("preferredFramesPerSecond")) engine.mapView.setMaximumFps(rendering.optInt("preferredFramesPerSecond", 60))
      if (rendering.has("prefetchZoomDelta")) map.setPrefetchZoomDelta(rendering.optInt("prefetchZoomDelta", 4).toByte())
      if (rendering.has("tileCacheBudgetMegabytes")) {
        map.setTileCacheBudget(com.mapbox.maps.TileCacheBudget.valueOf(
          com.mapbox.maps.TileCacheBudgetInMegabytes(rendering.optLong("tileCacheBudgetMegabytes"))))
      }
      when (rendering.optString("constrainMode", "")) {
        "none" -> map.setConstrainMode(com.mapbox.maps.ConstrainMode.NONE)
        "heightOnly" -> map.setConstrainMode(com.mapbox.maps.ConstrainMode.HEIGHT_ONLY)
        "widthAndHeight" -> map.setConstrainMode(com.mapbox.maps.ConstrainMode.WIDTH_AND_HEIGHT)
      }
      when (rendering.optString("viewportMode", "")) {
        "default" -> map.setViewportMode(com.mapbox.maps.ViewportMode.DEFAULT)
        "flippedY" -> map.setViewportMode(com.mapbox.maps.ViewportMode.FLIPPED_Y)
      }
      when (rendering.optString("northOrientation", "")) {
        "upwards" -> map.setNorthOrientation(com.mapbox.maps.NorthOrientation.UPWARDS)
        "rightwards" -> map.setNorthOrientation(com.mapbox.maps.NorthOrientation.RIGHTWARDS)
        "downwards" -> map.setNorthOrientation(com.mapbox.maps.NorthOrientation.DOWNWARDS)
        "leftwards" -> map.setNorthOrientation(com.mapbox.maps.NorthOrientation.LEFTWARDS)
      }
      if (rendering.has("transitionDuration") || rendering.has("transitionDelay")) {
        map.setStyleTransition(com.mapbox.maps.TransitionOptions.Builder()
          .duration(rendering.optLong("transitionDuration", 300))
          .delay(rendering.optLong("transitionDelay", 0))
          .build())
      }
    }
    val debug = options.optJSONArray("debug") ?: JSONArray()
    if (!MapboxJson.same(appliedDebug, debug)) {
      appliedDebug = debug
      engine.mapView.debugOptions = MapboxJson.strings(debug).mapNotNull { DEBUG[it] }.toSet()
    }
  }

  // Events

  /** Sends a Mapbox event to `onProviderEvent` if `events` lists it. */
  fun emit(name: String, payload: () -> JSONObject) {
    if (name !in eventNames) return
    engine.listener?.onProviderEvent(name, payload().toString())
  }

  /** Map-level events every map has; the rest subscribe on demand ([updateEvents]). */
  fun subscribeEvents() = updateEvents()

  private fun updateEvents() {
    val names = MapboxJson.strings(options.optJSONArray("events")).toSet()
    eventNames = names
    val map = engine.map
    for (name in events.keys - names) events.remove(name)?.cancel()
    for (name in names - events.keys) {
      val cancelable: Cancelable? = when (name) {
        "mapLoaded" -> map.subscribeMapLoaded { emit(name) { JSONObject() } }
        "styleLoaded" -> map.subscribeStyleLoaded { emit(name) { JSONObject() } }
        "styleDataLoaded" -> map.subscribeStyleDataLoaded { e -> emit(name) { JSONObject().put("type", e.type.name.lowercase()) } }
        "styleImageMissing" -> map.subscribeStyleImageMissing { e -> emit(name) { JSONObject().put("imageId", e.imageId) } }
        "styleImageRemoveUnused" -> map.subscribeStyleImageRemoveUnused { e -> emit(name) { JSONObject().put("imageId", e.imageId) } }
        "sourceDataLoaded" -> map.subscribeSourceDataLoaded { e ->
          emit(name) {
            JSONObject().put("sourceId", e.sourceId).put("type", e.type.name.lowercase())
              .put("loaded", e.loaded ?: JSONObject.NULL)
              .put("tileId", e.tileId?.let { JSONObject().put("z", it.z.toInt()).put("x", it.x).put("y", it.y) } ?: JSONObject.NULL)
              .put("dataId", e.dataId ?: JSONObject.NULL)
          }
        }
        "sourceAdded" -> map.subscribeSourceAdded { e -> emit(name) { JSONObject().put("sourceId", e.sourceId) } }
        "sourceRemoved" -> map.subscribeSourceRemoved { e -> emit(name) { JSONObject().put("sourceId", e.sourceId) } }
        "renderFrameStarted" -> map.subscribeRenderFrameStarted { emit(name) { JSONObject() } }
        "renderFrameFinished" -> map.subscribeRenderFrameFinished { e ->
          emit(name) {
            JSONObject().put("renderMode", e.renderMode.name.lowercase()).put("needsRepaint", e.needsRepaint)
              .put("placementChanged", e.placementChanged)
          }
        }
        "resourceRequest" -> map.subscribeResourceRequest { e ->
          emit(name) {
            JSONObject().put("source", e.source.name.lowercase()).put("url", e.request.url)
              .put("resource", e.request.resource.name.lowercase()).put("cancelled", e.cancelled)
              .put("dataSource", e.response?.source?.name?.lowercase() ?: JSONObject.NULL)
              .put("error", e.response?.error?.message ?: JSONObject.NULL)
          }
        }
        // cameraChanged, mapIdle and mapLoadingError come from the engine's own subscriptions.
        else -> null
      }
      if (cancelable != null) events[name] = cancelable
    }
  }

  // Interactions

  private fun updateInteractions() {
    val list = options.optJSONArray("interactions") ?: JSONArray()
    if (MapboxJson.same(appliedInteractions, list)) return
    appliedInteractions = list
    interactionCancelables.forEach { it.cancel() }
    interactionCancelables.clear()
    clearInteractionStates()
    val map = engine.map
    for (i in 0 until list.length()) {
      val item = list.optJSONObject(i) ?: continue
      val id = item.optString("id")
      val longPress = item.optString("type") == "longPress"
      val filter = item.opt("filter")?.let { MapboxJson.value(it) }
      val consume = item.optBoolean("consume", true)
      val featureset = item.optJSONObject("featureset")
      val layerId = item.optString("layerId", "")
      val handler: (FeaturesetFeature<FeatureState>, com.mapbox.maps.InteractionContext) -> Boolean = { feature, context ->
        interactionHit(id, item, feature, context, if (longPress) "longPress" else "tap")
        consume
      }
      val interaction = when {
        featureset != null -> {
          val fsId = featureset.optString("featuresetId")
          val importId = featureset.optString("importId", "").ifEmpty { null }
          if (longPress) LongClickInteraction.featureset(fsId, importId, filter, null, handler)
          else ClickInteraction.featureset(fsId, importId, filter, null, handler)
        }
        layerId.isNotEmpty() -> {
          if (longPress) LongClickInteraction.layer(layerId, filter, null, handler)
          else ClickInteraction.layer(layerId, filter, null, handler)
        }
        else -> null
      } ?: continue
      interactionCancelables.add(map.addInteraction(interaction))
    }
  }

  private fun interactionHit(
    id: String,
    item: JSONObject,
    feature: FeaturesetFeature<FeatureState>,
    context: com.mapbox.maps.InteractionContext,
    type: String,
  ) {
    val map = engine.map
    val setState = item.optJSONObject("setState")
    if (setState != null) {
      selectedByInteraction.remove(id)?.let { previous ->
        for (k in setState.keys()) map.removeFeatureState(previous, com.mapbox.maps.interactions.FeatureStateKey.create(k))
      }
      map.setFeatureState(feature, JsonFeatureState.build(setState))
      selectedByInteraction[id] = feature
    }
    val descriptor = feature.descriptor
    val target = JSONObject()
    when (descriptor) {
      is com.mapbox.maps.interactions.TypedFeaturesetDescriptor.Featureset -> {
        target.put("featuresetId", descriptor.featuresetId)
        descriptor.importId?.let { target.put("importId", it) }
      }
      is com.mapbox.maps.interactions.TypedFeaturesetDescriptor.Layer -> target.put("layerId", descriptor.layerId)
      else -> {}
    }
    val coordinate = context.coordinateInfo.coordinate
    val payload = JSONObject()
      .put("id", id)
      .put("type", type)
      .put("feature", MapboxJson.feature(feature.originalFeature))
      .put("featureId", feature.id?.featureId ?: JSONObject.NULL)
      .put("featureNamespace", feature.id?.featureNamespace ?: JSONObject.NULL)
      .put("featureset", target)
      .put("state", MapboxJson.parse(feature.state.asJsonString()))
      .put("coordinate", MapboxJson.coordinate(coordinate))
      .put("point", JSONObject().put("x", context.screenCoordinate.x / engine.density).put("y", context.screenCoordinate.y / engine.density))
    engine.listener?.onProviderEvent("interaction", payload.toString())
  }

  // Taps on Mapbox Standard's places (`selectableMapFeatures` → `onMapFeaturePress`)

  private val selectableCancelables = mutableListOf<Cancelable>()
  private var selectable: Set<String> = emptySet()

  fun setSelectableFeatures(features: String) {
    val next = features.split(",").map { it.trim() }.filter { it.isNotEmpty() }.toSet()
    if (next == selectable) return
    selectable = next
    selectableCancelables.forEach { it.cancel() }
    selectableCancelables.clear()
    val sets = mutableListOf<Pair<String, String>>()
    if ("pointsOfInterest" in next) sets += listOf("poi" to "pointOfInterest", "landmark-icons" to "pointOfInterest")
    if ("territories" in next) sets += "place-labels" to "territory"
    for ((featureset, kind) in sets) {
      val handler: (FeaturesetFeature<FeatureState>, com.mapbox.maps.InteractionContext) -> Boolean = { feature, context ->
        val original = feature.originalFeature
        val properties = original.properties()
        fun text(key: String) = properties?.get(key)?.takeIf { it.isJsonPrimitive }?.asString ?: ""
        val category = text("class").ifEmpty { text("group") }.ifEmpty { text("type") }
        val point = original.geometry() as? com.mapbox.geojson.Point ?: context.coordinateInfo.coordinate
        val id = feature.id?.featureId?.let { "$featureset:$it" } ?: ""
        engine.listener?.onMapFeaturePress(
          com.margelo.nitro.munimmaps.MapFeatureEvent(text("name"), point.latitude(), point.longitude(), kind, category, id)
        )
        true
      }
      selectableCancelables.add(engine.map.addInteraction(ClickInteraction.featureset(featureset, "basemap", null, null, handler)))
    }
  }

  private fun clearInteractionStates() {
    val map = engine.map
    for ((_, feature) in selectedByInteraction) runCatching { map.removeFeatureState(feature) }
    selectedByInteraction.clear()
  }

  fun destroy() {
    events.values.forEach { it.cancel() }
    events.clear()
    interactionCancelables.forEach { it.cancel() }
    interactionCancelables.clear()
    selectableCancelables.forEach { it.cancel() }
    selectableCancelables.clear()
  }

  companion object {
    const val STANDARD = "mapbox://styles/mapbox/standard"
    const val STANDARD_SATELLITE = "mapbox://styles/mapbox/standard-satellite"
    const val BASEMAP = "basemap"
    const val TERRAIN_SOURCE = "munim-terrain-dem"
    const val TRAFFIC_SOURCE = "munim-traffic"
    const val TRAFFIC_LAYER = "munim-traffic"
    private val UNSET = Any()

    /** `debug` names to the MapView's debug options (native ones plus the camera and padding views). */
    private val DEBUG = mapOf(
      "tileBorders" to com.mapbox.maps.debugoptions.MapViewDebugOptions.TILE_BORDERS,
      "parseStatus" to com.mapbox.maps.debugoptions.MapViewDebugOptions.PARSE_STATUS,
      "timestamps" to com.mapbox.maps.debugoptions.MapViewDebugOptions.TIMESTAMPS,
      "collision" to com.mapbox.maps.debugoptions.MapViewDebugOptions.COLLISION,
      "overdraw" to com.mapbox.maps.debugoptions.MapViewDebugOptions.OVERDRAW,
      "stencilClip" to com.mapbox.maps.debugoptions.MapViewDebugOptions.STENCIL_CLIP,
      "depthBuffer" to com.mapbox.maps.debugoptions.MapViewDebugOptions.DEPTH_BUFFER,
      "modelBounds" to com.mapbox.maps.debugoptions.MapViewDebugOptions.MODEL_BOUNDS,
      "terrainWireframe" to com.mapbox.maps.debugoptions.MapViewDebugOptions.TERRAIN_WIREFRAME,
      "layers2DWireframe" to com.mapbox.maps.debugoptions.MapViewDebugOptions.LAYERS2_DWIREFRAME,
      "layers3DWireframe" to com.mapbox.maps.debugoptions.MapViewDebugOptions.LAYERS3_DWIREFRAME,
      "light" to com.mapbox.maps.debugoptions.MapViewDebugOptions.LIGHT,
      "camera" to com.mapbox.maps.debugoptions.MapViewDebugOptions.CAMERA,
      "padding" to com.mapbox.maps.debugoptions.MapViewDebugOptions.PADDING,
    )
  }
}

/** Feature state from JSON (any JSON value per key), for `setFeatureState`. */
internal object JsonFeatureState {
  fun build(state: JSONObject): FeatureState = Builder(state).build()

  private class Builder(state: JSONObject) : FeatureState.Builder() {
    init {
      state.keys().forEach { rawStateMap[it] = MapboxJson.value(state.opt(it)) }
    }
  }
}
