@file:OptIn(MapboxExperimental::class)

package com.munimmaps.engines.mapbox

import android.view.Choreographer
import com.mapbox.common.Cancelable
import com.mapbox.maps.ClickInteraction
import com.mapbox.maps.MapboxExperimental
import com.margelo.nitro.munimmaps.MapAltitudeReference
import com.margelo.nitro.munimmaps.MapModelEffect
import com.margelo.nitro.munimmaps.MapModelShape
import com.margelo.nitro.munimmaps.MotionKeyframe
import com.margelo.nitro.munimmaps.NativeMapModel
import com.munimmaps.models.ModelAssets
import org.json.JSONArray
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin

/**
 * munim-maps' models drawn by Mapbox itself (`mapbox.modelRendering`), the
 * Android twin of iOS's `MapboxNativeModels`: glTF / GLB models become
 * entries of a Mapbox `model` source drawn by two `model` layers (ground and
 * sea level), so Mapbox lights them, casts their shadows and hides them
 * behind its 3D buildings and terrain. Position, altitude, heading, spin,
 * `motion`, `scale`, `screenSize` and `tint` (a colour override on the
 * model's `paint*` materials) are applied; what the model layer cannot draw
 * (labels, stems, effects, occluders, built-in shapes, pictures, lift)
 * stays on munim-maps' Filament layer.
 *
 * - `auto` (default): models that are only a glTF body are native.
 * - `native`: every glTF model is native; an overlay copy without the body
 *   keeps its label, stem and effects.
 * - `overlay`: everything on the Filament layer.
 */
internal class MapboxNativeModels(private val engine: MapboxMapEngine) {
  private var all: Array<NativeMapModel> = emptyArray()
  var native: List<NativeMapModel> = emptyList()
    private set
  var overlay: Array<NativeMapModel> = emptyArray()
    private set
  private var mode = "auto"
  private val infos = mutableMapOf<String, GlbInfo>()
  private val resolved = mutableMapOf<String, String>()
  private val loading = mutableSetOf<String>()
  private var installed = false
  private var lastJson = ""
  private var ticking = false
  private val interactions = mutableListOf<Cancelable>()

  private val frame = object : Choreographer.FrameCallback {
    override fun doFrame(frameTimeNanos: Long) {
      if (!ticking || engine.destroyed) return
      update()
      Choreographer.getInstance().postFrameCallback(this)
    }
  }

  init {
    // Taps on native models: before annotations' and the map's own taps.
    for (layer in listOf(GROUND_LAYER, SEA_LAYER, ANIMATED_LAYER, ANIMATED_SEA_LAYER)) {
      interactions += engine.map.addInteraction(ClickInteraction.layer(layer) { feature, _ ->
        val id = feature.properties.optString("id", "").ifEmpty { feature.originalFeature.id() ?: "" }
        if (id.isEmpty()) return@layer false
        engine.modelLayer.onModelPress?.invoke(id)
        true
      })
    }
  }

  /** Splits the models; returns the ones the Filament layer draws. */
  fun setModels(models: Array<NativeMapModel>): Array<NativeMapModel> {
    all = models
    split()
    update()
    return overlay
  }

  /** `modelRendering` from `mapbox={{…}}`. */
  fun setMode(value: String) {
    val next = if (value == "native" || value == "overlay") value else "auto"
    if (next == mode) return
    mode = next
    split()
    engine.modelLayer.models = overlay
    update()
  }

  private fun split() {
    val natives = mutableListOf<NativeMapModel>()
    val rest = mutableListOf<NativeMapModel>()
    for (model in all) {
      if (mode == "overlay" || !model.visible || !isGltf(model.uri)) {
        rest.add(model)
        continue
      }
      val extras = model.label.isNotEmpty() || model.stem || model.effect != MapModelEffect.NONE || model.occluder
      if (mode == "auto") {
        // The model layer does not play glTF animations: animated files stay on the Filament layer.
        val animated = model.playAnimations && infos[model.uri]?.hasAnimations == true
        if (extras || model.liftPoints != 0.0 || animated) rest.add(model) else natives.add(model)
      } else {
        natives.add(model)
        // The Filament layer keeps the label, stem and effects without the body.
        if (extras) rest.add(model.copy(uri = "", shape = MapModelShape.NONE))
      }
    }
    native = natives
    overlay = rest.toTypedArray()
    for (model in natives) prepare(model.uri)
    updateClock()
  }

  /** Resolves the URI for Mapbox and reads the GLB's height and `paint*` materials, once per file. */
  private fun prepare(uri: String) {
    if (uri in loading || (infos.containsKey(uri) && resolved.containsKey(uri))) return
    loading.add(uri)
    var pending = 2
    fun done() {
      if (--pending == 0) {
        loading.remove(uri)
        update()
      }
    }
    engine.style.modelUri(uri) { file ->
      if (file != null) resolved[uri] = file else engine.report("native model: could not load $uri")
      done()
    }
    ModelAssets.load(engine.context, uri) { result ->
      result.getOrNull()?.let { bytes ->
        MapboxMapEngine.executor.execute {
          val info = runCatching { GlbInfo.parse(bytes) }.getOrNull()
          engine.main.post {
            if (info != null) infos[uri] = info
            // An animated file moves its models back to the Filament layer.
            if (info?.hasAnimations == true) {
              split()
              engine.modelLayer.models = overlay
            }
            done()
          }
        }
      } ?: done()
    }
  }

  // Drawing

  fun styleLoaded() {
    installed = false
    lastJson = ""
    update()
  }

  private fun animated(model: NativeMapModel) = model.motion.size > 1 || model.spinDegreesPerSecond != 0.0

  /** Rebuilds the model sources from the models' poses now. */
  fun update() {
    if (engine.destroyed || !engine.styleLoaded) return
    updateAnimated()
    val map = engine.map
    val models = entries(native.filter { !animated(it) })
    if (models.length() == 0) {
      if (installed || map.styleSourceExists(SOURCE)) uninstall()
      return
    }
    val json = models.toString()
    if (json == lastJson && installed) return
    lastJson = json
    if (!installed || !map.styleSourceExists(SOURCE)) {
      uninstall()
      lastJson = json
      MapboxJson.error(map.addStyleSource(SOURCE, MapboxJson.value(JSONObject().put("type", "model").put("models", models))))?.let {
        engine.report("native models: $it")
        return
      }
      addLayer(GROUND_LAYER, false)
      addLayer(SEA_LAYER, true)
      installed = true
    } else {
      MapboxJson.error(map.setStyleSourceProperty(SOURCE, "models", MapboxJson.value(models)))?.let { engine.report("native models: $it") }
    }
  }

  /** Moving and spinning models: their own model source, location-indicator models updated every frame. */
  private fun updateAnimated() {
    val map = engine.map
    val moving = native.filter { animated(it) }
    if (moving.isEmpty()) {
      for (id in listOf(ANIMATED_LAYER, ANIMATED_SEA_LAYER)) if (map.styleLayerExists(id)) map.removeStyleLayer(id)
      if (map.styleSourceExists(ANIMATED_SOURCE)) map.removeStyleSource(ANIMATED_SOURCE)
      return
    }
    val models = entries(moving)
    if (!map.styleSourceExists(ANIMATED_SOURCE)) {
      MapboxJson.error(map.addStyleSource(ANIMATED_SOURCE, MapboxJson.value(JSONObject().put("type", "model").put("models", models))))?.let {
        engine.report("native models: $it")
        return
      }
      addLayer(ANIMATED_LAYER, false, ANIMATED_SOURCE, indicator = true)
      addLayer(ANIMATED_SEA_LAYER, true, ANIMATED_SOURCE, indicator = true)
    } else {
      MapboxJson.error(map.setStyleSourceProperty(ANIMATED_SOURCE, "models", MapboxJson.value(models)))?.let { engine.report("native models: $it") }
    }
    val keys = models.keys()
    while (keys.hasNext()) {
      val id = keys.next()
      val props = models.optJSONObject(id)?.optJSONObject("featureProperties") ?: continue
      val state = JSONObject().put("scale", props.optJSONArray("scale")).put("translation", props.optJSONArray("translation"))
      map.setFeatureState(ANIMATED_SOURCE, id, MapboxJson.value(state)) { }
    }
  }

  private fun addLayer(id: String, sea: Boolean, source: String = SOURCE, indicator: Boolean = false) {
    val filter = JSONArray().put(if (sea) "==" else "!=").put(JSONArray().put("get").put("sea")).put(true)
    fun stateOr(key: String) = JSONArray().put("array").put("number").put(3).put(
      JSONArray().put("coalesce").put(JSONArray().put("feature-state").put(key)).put(JSONArray().put("get").put(key)))
    val layer = JSONObject()
      .put("id", id).put("type", "model").put("source", source)
      .put("filter", filter)
      .put("paint", JSONObject()
        .put("model-type", if (indicator) "location-indicator" else "common-3d")
        .put("model-scale", if (indicator) stateOr("scale") else JSONArray().put("get").put("scale"))
        .put("model-translation", if (indicator) stateOr("translation") else JSONArray().put("get").put("translation"))
        .put("model-cast-shadows", true)
        .put("model-receive-shadows", true)
        .put("model-emissive-strength", JSONArray().put("get").put("emissive"))
        .put("model-opacity", JSONArray().put("get").put("opacity"))
        .put("model-elevation-reference", if (sea) "sea" else "ground"))
    if (engine.style.slots().contains("middle")) layer.put("slot", "middle")
    MapboxJson.error(engine.map.addStyleLayer(MapboxJson.value(layer), null))?.let { engine.report("native models: $it") }
  }

  private fun uninstall() {
    val map = engine.map
    for (id in listOf(GROUND_LAYER, SEA_LAYER)) if (map.styleLayerExists(id)) map.removeStyleLayer(id)
    if (map.styleSourceExists(SOURCE)) map.removeStyleSource(SOURCE)
    if (native.none { animated(it) }) {
      for (id in listOf(ANIMATED_LAYER, ANIMATED_SEA_LAYER)) if (map.styleLayerExists(id)) map.removeStyleLayer(id)
      if (map.styleSourceExists(ANIMATED_SOURCE)) map.removeStyleSource(ANIMATED_SOURCE)
    }
    installed = false
    lastJson = ""
  }

  private fun entries(models: List<NativeMapModel>): JSONObject {
    val result = JSONObject()
    val now = System.currentTimeMillis() / 1000.0
    val camera = if (models.any { it.screenSize > 0 }) engine.cameraState(null) else null
    for (model in models) {
      val uri = resolved[model.uri] ?: continue
      val info = infos[model.uri]
      val pose = pose(model, now)
      var heading = pose[3]
      if (model.spinDegreesPerSecond != 0.0) heading += (model.spinDegreesPerSecond * now) % 360
      // munim-maps' glTF models face -Z; Mapbox's model layer draws heading 0
      // facing south without this (measured on the iPad: heading 90 put the
      // fire truck's cab west).
      heading += 180
      heading = (heading % 360 + 360) % 360
      var scale = model.scale
      if (model.screenSize > 0) {
        val height = info?.height ?: 0.0
        if (camera == null || height <= 0) continue
        // Same rule as the 3D layer: `screenSize` points tall on screen.
        val depth = camera.project(camera.scenePosition(pose[0], pose[1], pose[2]))?.get(2) ?: continue
        if (depth <= 0) continue
        scale *= model.screenSize * camera.pixelRatio * depth / camera.focalLength / height
      }
      val entry = JSONObject()
        .put("uri", uri)
        .put("position", JSONArray().put(pose[1]).put(pose[0]))
        .put("orientation", JSONArray().put(0).put(0).put(heading))
        .put("featureProperties", JSONObject()
          .put("id", model.id)
          .put("scale", JSONArray().put(scale).put(scale).put(scale))
          .put("translation", JSONArray().put(0).put(0).put(pose[2]))
          .put("sea", model.altitudeReference == MapAltitudeReference.SEA)
          .put("emissive", if (model.emissive) 1 else 0)
          .put("opacity", 1))
      val tint = MapboxColors.parse(model.tintColor)
      val names = info?.paintMaterials ?: emptyList()
      if (tint != null && names.isNotEmpty()) {
        val overrides = JSONObject()
        names.forEach { overrides.put(it, JSONObject().put("model-color", MapboxColors.css(tint)).put("model-color-mix-intensity", 1.0)) }
        entry.put("materialOverrides", overrides)
      }
      result.put(model.id, entry)
    }
    return result
  }

  // Clock: moving and spinning models are updated every frame.

  private fun updateClock() {
    val needsFrames = native.any { it.motion.size > 1 || it.spinDegreesPerSecond != 0.0 }
    if (needsFrames && !ticking) {
      ticking = true
      Choreographer.getInstance().postFrameCallback(frame)
    } else if (!needsFrames && ticking) {
      ticking = false
      Choreographer.getInstance().removeFrameCallback(frame)
    }
  }

  /** The camera moved: screen-sized models change size. */
  fun cameraChanged() {
    if (!ticking && native.any { it.screenSize > 0 }) update()
  }

  fun destroy() {
    ticking = false
    Choreographer.getInstance().removeFrameCallback(frame)
    interactions.forEach { it.cancel() }
    interactions.clear()
  }

  companion object {
    const val SOURCE = "munim-native-models"
    const val GROUND_LAYER = "munim-native-models"
    const val SEA_LAYER = "munim-native-models-sea"
    const val ANIMATED_SOURCE = "munim-native-animated"
    const val ANIMATED_LAYER = "munim-native-animated"
    const val ANIMATED_SEA_LAYER = "munim-native-animated-sea"

    private val NOT_GLTF = setOf("usdz", "usd", "usda", "usdc", "scn", "obj", "dae", "fbx", "stl", "ply", "reality")

    /**
     * glTF / GLB by extension; React Native release builds name bundled
     * files without one (raw resources), and Android's 3D layer only draws
     * glTF, so names without a known other extension count as glTF.
     */
    fun isGltf(uri: String): Boolean {
      if (uri.isBlank()) return false
      val path = (android.net.Uri.parse(uri).path ?: uri).lowercase()
      if (path.endsWith(".glb") || path.endsWith(".gltf")) return true
      val ext = path.substringAfterLast('/').substringAfterLast('.', "")
      return ext.isEmpty() || ext !in NOT_GLTF && ext.length > 4
    }

    /** latitude, longitude, altitude, heading at `now`, from the motion keyframes (as the 3D layer does). */
    fun pose(model: NativeMapModel, now: Double): DoubleArray {
      val frames = model.motion
      if (frames.isEmpty()) return doubleArrayOf(model.latitude, model.longitude, model.altitude, model.heading)
      val first = frames.first()
      val last = frames.last()
      var t = now - model.motionStart
      val span = last.t - first.t
      if (model.motionLoop && span > 0) t = first.t + ((t - first.t) % span + span) % span
      if (frames.size == 1 || t <= first.t) {
        return doubleArrayOf(first.latitude, first.longitude, first.altitude, heading(first.heading, frames, 0))
      }
      if (t >= last.t) {
        return doubleArrayOf(last.latitude, last.longitude, last.altitude, heading(last.heading, frames, frames.size - 2))
      }
      var i = 1
      while (i < frames.size - 1 && frames[i].t < t) i++
      val a = frames[i - 1]
      val b = frames[i]
      val f = if (b.t > a.t) (t - a.t) / (b.t - a.t) else 0.0
      val heading = if (a.heading >= 0 && b.heading >= 0) {
        val turn = ((b.heading - a.heading) % 360 + 540) % 360 - 180
        a.heading + turn * f
      } else {
        bearing(a.latitude, a.longitude, b.latitude, b.longitude)
      }
      return doubleArrayOf(
        a.latitude + (b.latitude - a.latitude) * f,
        a.longitude + (b.longitude - a.longitude) * f,
        a.altitude + (b.altitude - a.altitude) * f,
        heading,
      )
    }

    private fun heading(value: Double, frames: Array<MotionKeyframe>, segment: Int): Double {
      if (value >= 0 || frames.size < 2) return maxOf(0.0, value)
      val a = frames[segment]
      val b = frames[segment + 1]
      return bearing(a.latitude, a.longitude, b.latitude, b.longitude)
    }

    private fun bearing(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
      val p1 = lat1 * PI / 180
      val p2 = lat2 * PI / 180
      val dl = (lon2 - lon1) * PI / 180
      val y = sin(dl) * cos(p2)
      val x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
      return (atan2(y, x) * 180 / PI + 360) % 360
    }
  }
}

/**
 * What the native renderer needs from a glTF file: its height (for
 * `screenSize`) and the names of its `paint*` materials (for `tint`).
 */
internal class GlbInfo(val height: Double, val paintMaterials: List<String>, val hasAnimations: Boolean = false) {
  companion object {
    /** Reads the JSON chunk of a GLB (or a .gltf file). */
    fun parse(data: ByteArray): GlbInfo? {
      val text = if (data.size >= 20 && data[0] == 'g'.code.toByte() && data[1] == 'l'.code.toByte() &&
        data[2] == 'T'.code.toByte() && data[3] == 'F'.code.toByte()
      ) {
        val length = ByteBuffer.wrap(data, 12, 4).order(ByteOrder.LITTLE_ENDIAN).int
        if (20 + length > data.size) return null
        String(data, 20, length, Charsets.UTF_8)
      } else {
        String(data, Charsets.UTF_8)
      }
      val json = JSONObject(text)
      val accessors = json.optJSONArray("accessors") ?: JSONArray()
      val meshes = json.optJSONArray("meshes") ?: JSONArray()
      val nodes = json.optJSONArray("nodes") ?: JSONArray()
      val materials = json.optJSONArray("materials") ?: JSONArray()

      fun corners(mesh: Int): List<DoubleArray> {
        val out = mutableListOf<DoubleArray>()
        val primitives = meshes.optJSONObject(mesh)?.optJSONArray("primitives") ?: return out
        for (i in 0 until primitives.length()) {
          val position = primitives.optJSONObject(i)?.optJSONObject("attributes")?.opt("POSITION") as? Int ?: continue
          val accessor = accessors.optJSONObject(position) ?: continue
          val lo = accessor.optJSONArray("min") ?: continue
          val hi = accessor.optJSONArray("max") ?: continue
          if (lo.length() != 3 || hi.length() != 3) continue
          for (x in listOf(lo.optDouble(0), hi.optDouble(0))) for (y in listOf(lo.optDouble(1), hi.optDouble(1))) {
            for (z in listOf(lo.optDouble(2), hi.optDouble(2))) out.add(doubleArrayOf(x, y, z))
          }
        }
        return out
      }

      var minY = Double.POSITIVE_INFINITY
      var maxY = Double.NEGATIVE_INFINITY
      fun visit(index: Int, parent: DoubleArray, depth: Int) {
        val node = nodes.optJSONObject(index) ?: return
        if (depth > 64) return
        val world = Mat4.mul(parent, Mat4.of(node))
        if (node.has("mesh")) {
          for (c in corners(node.optInt("mesh"))) {
            val y = world[1] * c[0] + world[5] * c[1] + world[9] * c[2] + world[13]
            minY = minOf(minY, y)
            maxY = maxOf(maxY, y)
          }
        }
        node.optJSONArray("children")?.let { children -> for (i in 0 until children.length()) visit(children.optInt(i), world, depth + 1) }
      }
      val scenes = json.optJSONArray("scenes")
      val roots = scenes?.optJSONObject(json.optInt("scene", 0))?.optJSONArray("nodes")
      if (roots != null) for (i in 0 until roots.length()) visit(roots.optInt(i), Mat4.IDENTITY, 0)
      else for (i in 0 until nodes.length()) visit(i, Mat4.IDENTITY, 0)
      if (!minY.isFinite()) {
        // No scene graph: the meshes as they are.
        for (m in 0 until meshes.length()) for (c in corners(m)) {
          minY = minOf(minY, c[1])
          maxY = maxOf(maxY, c[1])
        }
      }
      val height = if (maxY > minY) maxY - minY else 0.0
      val paint = (0 until materials.length()).mapNotNull { materials.optJSONObject(it)?.optString("name", "")?.takeIf { n -> n.isNotEmpty() } }
        .filter { it.lowercase().startsWith("paint") }
      val animated = (json.optJSONArray("animations")?.length() ?: 0) > 0
      return GlbInfo(height, paint, animated)
    }
  }
}

/** Column-major 4x4 matrices for glTF node transforms. */
private object Mat4 {
  val IDENTITY = doubleArrayOf(1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0)

  fun mul(a: DoubleArray, b: DoubleArray): DoubleArray = DoubleArray(16) { i ->
    val col = i / 4
    val row = i % 4
    var s = 0.0
    for (k in 0 until 4) s += a[k * 4 + row] * b[col * 4 + k]
    s
  }

  /** A node's local transform: `matrix`, or translation * rotation * scale. */
  fun of(node: JSONObject): DoubleArray {
    node.optJSONArray("matrix")?.takeIf { it.length() == 16 }?.let { m -> return DoubleArray(16) { m.optDouble(it) } }
    var result = IDENTITY
    node.optJSONArray("scale")?.takeIf { it.length() == 3 }?.let { s ->
      result = doubleArrayOf(s.optDouble(0), 0.0, 0.0, 0.0, 0.0, s.optDouble(1), 0.0, 0.0, 0.0, 0.0, s.optDouble(2), 0.0, 0.0, 0.0, 0.0, 1.0)
    }
    node.optJSONArray("rotation")?.takeIf { it.length() == 4 }?.let { q ->
      val x = q.optDouble(0)
      val y = q.optDouble(1)
      val z = q.optDouble(2)
      val w = q.optDouble(3)
      val r = doubleArrayOf(
        1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w), 0.0,
        2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w), 0.0,
        2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y), 0.0,
        0.0, 0.0, 0.0, 1.0,
      )
      result = mul(r, result)
    }
    node.optJSONArray("translation")?.takeIf { it.length() == 3 }?.let { t ->
      val m = IDENTITY.copyOf()
      m[12] = t.optDouble(0)
      m[13] = t.optDouble(1)
      m[14] = t.optDouble(2)
      result = mul(m, result)
    }
    return result
  }
}
