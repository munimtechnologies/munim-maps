package com.munimmaps.models

import android.content.Context
import android.view.Choreographer
import android.view.Surface
import android.view.TextureView
import com.google.android.filament.Camera
import com.google.android.filament.Colors
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.IndirectLight
import com.google.android.filament.LightManager
import com.google.android.filament.Renderer
import com.google.android.filament.Scene
import com.google.android.filament.SwapChain
import com.google.android.filament.View
import com.google.android.filament.Viewport
import com.google.android.filament.android.UiHelper
import com.google.android.filament.gltfio.AssetLoader
import com.google.android.filament.gltfio.FilamentAsset
import com.google.android.filament.gltfio.ResourceLoader
import com.google.android.filament.gltfio.UbershaderProvider
import com.google.android.filament.utils.Utils
import com.margelo.nitro.munimmaps.MapAlignmentReport
import com.margelo.nitro.munimmaps.MapModelLighting
import com.margelo.nitro.munimmaps.MapModelShape
import com.margelo.nitro.munimmaps.NativeMapModel
import com.munimmaps.engine.MapCameraSource
import com.munimmaps.engine.MapCameraState
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

/**
 * Filament renderer behind [MunimModelLayer]: a transparent TextureView over
 * the map, redrawn on Choreographer frames whenever the engine's camera
 * ([MapCameraState]) or the models change. The scene follows iOS: metres
 * around the map's centre coordinate, x east, y up, z south.
 */
internal class ModelRenderer(
  private val context: Context,
  textureView: TextureView,
  private val reportError: (String) -> Unit,
) : Choreographer.FrameCallback {
  companion object {
    init {
      Utils.init()
    }
  }

  private val engine = Engine.create()
  private val renderer: Renderer = engine.createRenderer()
  private val scene: Scene = engine.createScene()
  private val view: View = engine.createView()
  private val cameraEntity = EntityManager.get().create()
  private val camera: Camera = engine.createCamera(cameraEntity)
  private val sun = EntityManager.get().create()
  private var indirectLight: IndirectLight? = null
  private val materialProvider = UbershaderProvider(engine)
  private val assetLoader = AssetLoader(engine, materialProvider, EntityManager.get())
  private val resourceLoader = ResourceLoader(engine)
  private val uiHelper = UiHelper(UiHelper.ContextErrorPolicy.DONT_CHECK)
  private var swapChain: SwapChain? = null
  private var destroyed = false

  var source: MapCameraSource? = null
    private set
  private var frameScheduled = false
  private var needsRender = true
  private var lastState: MapCameraState? = null
  private var lastRendered: MapCameraState? = null
  private var nightLighting: Boolean? = null
  private val reported = mutableSetOf<String>()

  var lighting: MapModelLighting = MapModelLighting.AUTO
    set(value) {
      field = value
      needsRender = true
    }

  var maxCameraDistance = 50_000.0
    set(value) {
      field = value
      needsRender = true
    }

  private val entries = linkedMapOf<String, Entry>()

  init {
    view.scene = scene
    view.camera = camera
    view.blendMode = View.BlendMode.TRANSLUCENT
    view.setShadowingEnabled(false)
    view.multiSampleAntiAliasingOptions = view.multiSampleAntiAliasingOptions.apply {
      enabled = true
      sampleCount = 4
    }
    renderer.clearOptions = renderer.clearOptions.apply {
      clear = true
      clearColor = doubleArrayOf(0.0, 0.0, 0.0, 0.0)
    }
    camera.setExposure(16f, 1f / 125f, 100f)
    // Afternoon sun from the south-west, as on iOS.
    LightManager.Builder(LightManager.Type.DIRECTIONAL)
      .color(1f, 1f, 1f)
      .intensity(100_000f)
      .direction(0.354f, -0.866f, -0.354f)
      .castShadows(false)
      .build(engine, sun)
    scene.addEntity(sun)
    applyLighting(night = false)

    uiHelper.isOpaque = false
    uiHelper.renderCallback = object : UiHelper.RendererCallback {
      override fun onNativeWindowChanged(surface: Surface) {
        swapChain?.let { engine.destroySwapChain(it) }
        swapChain = engine.createSwapChain(surface, uiHelper.swapChainFlags)
        needsRender = true
        scheduleFrame()
      }

      override fun onDetachedFromSurface() {
        swapChain?.let {
          engine.destroySwapChain(it)
          engine.flushAndWait()
        }
        swapChain = null
      }

      override fun onResized(width: Int, height: Int) {
        view.viewport = Viewport(0, 0, width, height)
        needsRender = true
        scheduleFrame()
      }
    }
    uiHelper.attachTo(textureView)
  }

  fun reportOnce(message: String) {
    if (reported.add(message)) reportError(message)
  }

  // Attaching

  fun attach(source: MapCameraSource) {
    this.source = source
    lastRendered = null
    needsRender = true
    scheduleFrame()
  }

  fun detach() {
    source = null
    if (frameScheduled) Choreographer.getInstance().removeFrameCallback(this)
    frameScheduled = false
  }

  fun setNeedsRender() {
    needsRender = true
    scheduleFrame()
  }

  private fun scheduleFrame() {
    if (destroyed || frameScheduled || source == null) return
    frameScheduled = true
    Choreographer.getInstance().postFrameCallback(this)
  }

  // Models

  fun setModels(models: Array<NativeMapModel>) {
    if (destroyed) return
    val seen = HashSet<String>()
    for (model in models) {
      if (!seen.add(model.id)) {
        reportOnce("Duplicate model id \"${model.id}\"; only the first is drawn")
        continue
      }
      val entry = entries.getOrPut(model.id) { Entry(model) }
      val previous = entry.model
      entry.model = model
      when {
        model.imageUri.isNotEmpty() -> reportOnce("Pictures (image models) are not drawn on Android yet")
        model.uri.isEmpty() && model.shape != MapModelShape.NONE ->
          reportOnce("Built-in shapes are not drawn on Android yet; use a GLB file")
      }
      if (model.label.isNotEmpty()) reportOnce("Model labels are not drawn on Android yet")
      if (entry.loadedUri != model.uri && entry.loadingUri != model.uri) {
        load(entry)
      } else if (previous.tintColor != model.tintColor) {
        // Back to the file's colours means loading it again.
        if (model.tintColor.isEmpty()) load(entry) else entry.asset?.let { applyTint(it, model.tintColor) }
      }
    }
    for (id in entries.keys.toList()) {
      if (id !in seen) entries.remove(id)?.let { destroyAsset(it) }
    }
    setNeedsRender()
  }

  private fun load(entry: Entry) {
    destroyAsset(entry)
    val uri = entry.model.uri
    entry.loadingUri = uri
    if (uri.isEmpty()) return
    ModelAssets.load(context, uri) { result ->
      if (destroyed || entries[entry.model.id] !== entry || entry.loadingUri != uri) return@load
      entry.loadingUri = null
      result.onFailure { reportError("Could not load model \"${entry.model.id}\": ${it.message}") }
      result.onSuccess { bytes ->
        val buffer = ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder())
        buffer.put(bytes)
        buffer.flip()
        val asset = assetLoader.createAsset(buffer)
        if (asset == null) {
          reportError("Could not read model \"${entry.model.id}\" ($uri): not a glTF / GLB file")
          return@onSuccess
        }
        resourceLoader.loadResources(asset)
        asset.releaseSourceData()
        entry.asset = asset
        entry.loadedUri = uri
        val box = asset.boundingBox
        entry.center = box.center.copyOf()
        entry.halfExtent = box.halfExtent.copyOf()
        applyTint(asset, entry.model.tintColor)
        setNeedsRender()
      }
    }
  }

  /** Recolours the materials named `paint…`, like iOS. Empty keeps the file's colours. */
  private fun applyTint(asset: FilamentAsset, tint: String) {
    val color = parseColor(tint) ?: return
    val rm = engine.renderableManager
    for (entity in asset.entities) {
      if (!rm.hasComponent(entity)) continue
      val instance = rm.getInstance(entity)
      for (primitive in 0 until rm.getPrimitiveCount(instance)) {
        val material = rm.getMaterialInstanceAt(instance, primitive)
        if (material.name.startsWith("paint")) {
          material.setParameter("baseColorFactor", Colors.RgbaType.SRGB, color[0], color[1], color[2], color[3])
        }
      }
    }
  }

  private fun destroyAsset(entry: Entry) {
    entry.asset?.let {
      if (entry.inScene) scene.removeEntities(it.entities)
      assetLoader.destroyAsset(it)
    }
    entry.asset = null
    entry.inScene = false
    entry.loadedUri = null
    entry.loadingUri = null
  }

  // Frames

  override fun doFrame(frameTimeNanos: Long) {
    frameScheduled = false
    if (destroyed) return
    val source = source ?: return
    val mapView = source.cameraView
    if (mapView == null || !mapView.isAttachedToWindow) return
    scheduleFrame()
    val state = source.cameraState(lastState) ?: return
    lastState = state
    val night = when (lighting) {
      MapModelLighting.DAY -> false
      MapModelLighting.NIGHT -> true
      MapModelLighting.AUTO -> state.darkAppearance
    }
    if (night != nightLighting) {
      applyLighting(night)
      needsRender = true
    }
    val animating = entries.values.any { it.asset != null && it.isAnimating }
    if (!needsRender && !animating && state == lastRendered) return
    val chain = swapChain ?: return
    if (!uiHelper.isReadyToRender) return
    needsRender = false
    lastRendered = state
    updateScene(state)
    if (renderer.beginFrame(chain, frameTimeNanos)) {
      renderer.render(view)
      renderer.endFrame()
    }
  }

  private fun applyLighting(night: Boolean) {
    nightLighting = night
    indirectLight?.let { engine.destroyIndirectLight(it) }
    val ambient = if (night) floatArrayOf(0.6f, 0.68f, 1f) else floatArrayOf(1f, 1f, 1f)
    val light = IndirectLight.Builder()
      .irradiance(1, ambient)
      .intensity(if (night) 9_000f else 28_000f)
      .build(engine)
    scene.indirectLight = light
    indirectLight = light
    val lm = engine.lightManager
    val instance = lm.getInstance(sun)
    lm.setIntensity(instance, if (night) 20_000f else 100_000f)
    if (night) lm.setColor(instance, 0.7f, 0.78f, 1f) else lm.setColor(instance, 1f, 1f, 1f)
  }

  private fun updateScene(state: MapCameraState) {
    val aspect = if (state.height > 0) state.width / state.height else 1.0
    camera.setProjection(
      state.fieldOfView * 180 / PI, aspect, state.nearPlane, state.farPlane, Camera.Fov.VERTICAL)
    camera.setModelMatrix(state.cameraTransform)
    val tooFar = state.distance > maxCameraDistance
    val now = System.currentTimeMillis() / 1000.0
    val tm = engine.transformManager
    for (entry in entries.values) {
      val asset = entry.asset ?: continue
      val show = !tooFar && entry.model.visible && entry.place(state, now)
      if (show != entry.inScene) {
        if (show) scene.addEntities(asset.entities) else scene.removeEntities(asset.entities)
        entry.inScene = show
      }
      if (show) tm.setTransform(tm.getInstance(asset.root), entry.transform)
    }
  }

  // Taps and measuring

  fun modelHit(x: Double, y: Double): String? {
    val state = lastRendered ?: return null
    var best: Pair<String, Double>? = null
    for (entry in entries.values) {
      if (!entry.inScene) continue
      val center = entry.centerPosition ?: continue
      val projected = state.project(center) ?: continue
      val radius = maxOf(entry.screenRadius(state, projected[2]), 22 * state.pixelRatio)
      if (hypot(projected[0] - x, projected[1] - y) > radius) continue
      if (best == null || projected[2] < best.second) best = entry.model.id to projected[2]
    }
    return best?.first
  }

  fun measureAlignment(): MapAlignmentReport {
    val source = source
    val state = source?.cameraState(lastState)
    if (source == null || state == null) {
      return MapAlignmentReport(source?.cameraView != null, 0.0, -1.0, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    }
    val errors = mutableListOf<Double>()
    var drawn = 0
    for (entry in entries.values) {
      if (!entry.model.visible) continue
      val ground = state.scenePosition(entry.latitude, entry.longitude, 0.0)
      val ours = state.project(ground) ?: continue
      if (ours[0] < 4 || ours[1] < 4 || ours[0] > state.width - 4 || ours[1] > state.height - 4) continue
      val theirs = source.screenPoint(entry.latitude, entry.longitude) ?: continue
      errors.add(hypot(ours[0] - theirs.x, ours[1] - theirs.y) / state.pixelRatio)
      if (entry.inScene) drawn++
    }
    return MapAlignmentReport(
      attached = true,
      modelsMeasured = errors.size.toDouble(),
      maxErrorPoints = errors.maxOrNull() ?: 0.0,
      meanErrorPoints = if (errors.isEmpty()) 0.0 else errors.average(),
      modelsVisibleInRender = drawn.toDouble(),
      cameraDistance = state.distance,
      cameraPitch = state.pitch,
      cameraHeading = state.heading,
      fieldOfViewDegrees = state.fieldOfView * 180 / PI,
    )
  }

  fun destroy() {
    if (destroyed) return
    detach()
    destroyed = true
    for (entry in entries.values) destroyAsset(entry)
    entries.clear()
    uiHelper.detach()
    swapChain?.let { engine.destroySwapChain(it) }
    swapChain = null
    resourceLoader.destroy()
    assetLoader.destroy()
    materialProvider.destroyMaterials()
    materialProvider.destroy()
    indirectLight?.let { engine.destroyIndirectLight(it) }
    engine.destroyEntity(sun)
    engine.destroyRenderer(renderer)
    engine.destroyView(view)
    engine.destroyScene(scene)
    engine.destroyCameraComponent(cameraEntity)
    EntityManager.get().destroy(sun)
    EntityManager.get().destroy(cameraEntity)
    engine.destroy()
  }

  /** One model and the Filament asset drawing it. */
  private class Entry(var model: NativeMapModel) {
    var asset: FilamentAsset? = null
    var loadedUri: String? = null
    var loadingUri: String? = null
    var inScene = false
    var center = floatArrayOf(0f, 0f, 0f)
    var halfExtent = floatArrayOf(0.5f, 0.5f, 0.5f)
    val transform = FloatArray(16)
    var latitude = model.latitude
    var longitude = model.longitude
    var centerPosition: DoubleArray? = null
    private var scale = 1.0

    val isAnimating: Boolean
      get() = model.motion.isNotEmpty() || model.spinDegreesPerSecond != 0.0

    val contentHeight: Double get() = maxOf(1e-3, 2.0 * halfExtent[1])

    fun screenRadius(state: MapCameraState, depth: Double): Double {
      val size = maxOf(halfExtent[0], halfExtent[1], halfExtent[2]) * scale
      return size * state.focalLength / maxOf(depth, 1e-3)
    }

    /** Positions the model for this frame; false when it cannot be placed. */
    fun place(state: MapCameraState, now: Double): Boolean {
      val pose = pose(now)
      latitude = pose[0]
      longitude = pose[1]
      val position = state.scenePosition(pose[0], pose[1], pose[2])
      var s = model.scale
      if (model.screenSize > 0) {
        val depth = state.project(position)?.get(2) ?: return false
        if (depth <= 0) return false
        s *= model.screenSize * state.pixelRatio * depth / state.focalLength / contentHeight
      }
      scale = s
      val spin = model.spinDegreesPerSecond * now
      val yaw = (-(pose[3] + spin)) * PI / 180
      // glTF models face +z; iOS turns them half a turn so they face like
      // USDZ ones (GLTFLoader.makeScene), so the catalogue's headings match.
      val turn = yaw + PI
      val c = cos(turn)
      val sn = sin(turn)
      // T(position) * Ry(turn) * S(s) * T(-center, -minY, -center)
      val ox = -center[0].toDouble()
      val oy = -(center[1] - halfExtent[1]).toDouble()
      val oz = -center[2].toDouble()
      val tx = position[0] + s * (c * ox + sn * oz)
      val ty = position[1] + s * oy
      val tz = position[2] + s * (-sn * ox + c * oz)
      transform[0] = (c * s).toFloat(); transform[1] = 0f; transform[2] = (-sn * s).toFloat(); transform[3] = 0f
      transform[4] = 0f; transform[5] = s.toFloat(); transform[6] = 0f; transform[7] = 0f
      transform[8] = (sn * s).toFloat(); transform[9] = 0f; transform[10] = (c * s).toFloat(); transform[11] = 0f
      transform[12] = tx.toFloat(); transform[13] = ty.toFloat(); transform[14] = tz.toFloat(); transform[15] = 1f
      centerPosition = doubleArrayOf(position[0], position[1] + contentHeight * s / 2, position[2])
      return true
    }

    /** latitude, longitude, altitude, heading at `now`, from the motion keyframes. */
    private fun pose(now: Double): DoubleArray {
      val frames = model.motion
      if (frames.isEmpty()) return doubleArrayOf(model.latitude, model.longitude, model.altitude, model.heading)
      val first = frames.first()
      val last = frames.last()
      var t = now - model.motionStart
      val span = last.t - first.t
      if (model.motionLoop && span > 0) {
        t = first.t + ((t - first.t) % span + span) % span
      }
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

    private fun heading(value: Double, frames: Array<com.margelo.nitro.munimmaps.MotionKeyframe>, segment: Int): Double {
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

/** `#RRGGBB` or `#RRGGBBAA` as sRGB floats, or null. */
internal fun parseColor(value: String): FloatArray? {
  val hex = value.trim().removePrefix("#")
  if (hex.length != 6 && hex.length != 8) return null
  val n = hex.toLongOrNull(16) ?: return null
  return if (hex.length == 6) {
    floatArrayOf(((n shr 16) and 0xFF) / 255f, ((n shr 8) and 0xFF) / 255f, (n and 0xFF) / 255f, 1f)
  } else {
    floatArrayOf(((n shr 24) and 0xFF) / 255f, ((n shr 16) and 0xFF) / 255f, ((n shr 8) and 0xFF) / 255f, (n and 0xFF) / 255f)
  }
}
