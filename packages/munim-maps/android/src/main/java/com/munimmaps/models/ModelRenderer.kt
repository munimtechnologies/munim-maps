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
import com.google.android.filament.Texture
import com.google.android.filament.View
import com.google.android.filament.Viewport
import com.google.android.filament.android.UiHelper
import com.google.android.filament.gltfio.AssetLoader
import com.google.android.filament.gltfio.FilamentAsset
import com.google.android.filament.gltfio.ResourceLoader
import com.google.android.filament.gltfio.UbershaderProvider
import com.google.android.filament.utils.Utils
import com.margelo.nitro.munimmaps.CameraKeyframe
import com.margelo.nitro.munimmaps.MapAlignmentReport
import com.margelo.nitro.munimmaps.MapAltitudeReference
import com.margelo.nitro.munimmaps.MapCamera
import com.margelo.nitro.munimmaps.MapModelEffect
import com.margelo.nitro.munimmaps.MapModelLighting
import com.margelo.nitro.munimmaps.MapModelShape
import com.margelo.nitro.munimmaps.MotionKeyframe
import com.margelo.nitro.munimmaps.NativeMapModel
import com.margelo.nitro.munimmaps.NativeMapPath
import com.margelo.nitro.munimmaps.NativeMapZone
import com.munimmaps.engine.MapCameraSource
import com.munimmaps.engine.MapCameraState
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Filament renderer behind [MunimModelLayer]: a transparent TextureView over
 * the map, redrawn on Choreographer frames whenever the engine's camera
 * ([MapCameraState]) or the content changes. The Android twin of iOS's
 * `MapModelRenderer`, with the same scene: metres around the map's centre
 * coordinate, x east, y up, z south.
 *
 * Draw order (Filament channels): 1 depth-only occluders (buildings, the
 * Earth on a globe, `occluder` models), 2 models, shadows, zones, paths and
 * effects, 3 markers drawn over everything (avatars, labels, stems).
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

    private const val CHANNEL_OCCLUDERS = 1
    private const val CHANNEL_MODELS = 2
    private const val CHANNEL_ON_TOP = 3
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
  private val materials = ModelMaterials(engine, materialProvider)
  private var particleTextureValue: Texture? = null
  private var shadowTextureValue: Texture? = null
  private val particleTexture: Texture
    get() = particleTextureValue ?: materials.texture(ModelBitmaps.particle).also { particleTextureValue = it }
  private val shadowTexture: Texture
    get() = shadowTextureValue ?: materials.texture(ModelBitmaps.shadow).also { shadowTextureValue = it }
  val buildings = BuildingOccluder(context, engine, scene, materials)
  /** On a globe, the Earth itself in depth only, so the far side is hidden. */
  private val earth: MeshPart

  var source: MapCameraSource? = null
    private set
  private var frameScheduled = false
  private var needsRender = true
  private var lastState: MapCameraState? = null
  private var lastRendered: MapCameraState? = null
  private var lastFrameNanos = 0L
  private var nightLighting: Boolean? = null
  private val reported = mutableSetOf<String>()
  private var flight: CameraFlight? = null
  private var flightApply: ((MapCamera) -> Unit)? = null

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

  /** Keeps models, paths and zones above the ground on an engine's 3D terrain. */
  var followsTerrain = false
    set(value) {
      field = value
      refreshTerrainUse()
      setNeedsRender()
    }
  private var usesTerrain = false
  private var lastCenterGround: Double? = null
  private var reportedTerrainError = false
  private val terrainListener: (Boolean, String?) -> Unit = { ok, message ->
    if (usesTerrain && !destroyed) {
      if (ok) setNeedsRender()
      else if (!reportedTerrainError) {
        reportedTerrainError = true
        reportError(message ?: "Could not load terrain")
      }
    }
  }

  private val entries = linkedMapOf<String, Entry>()
  private val zoneEntries = linkedMapOf<String, ZoneEntry>()
  private val pathEntries = linkedMapOf<String, PathEntry>()

  init {
    MunimTerrain.init(context)
    MunimTerrain.addListener(terrainListener)
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

    // A little inside the real radius so models on the ground never sink into it.
    val sphere = MeshData().also {
      Shapes.sphere(it, (MapCameraState.EARTH_RADIUS * 0.9995).toFloat(), 0f, rings = 96, segments = 192)
    }
    earth = MeshPart(engine, sphere, materials.unlit(blend = false, occluder = true, label = "munim-earth"),
      channel = CHANNEL_OCCLUDERS, priority = 0)

    buildings.onChange = { setNeedsRender() }
    buildings.onError = { reportError(it) }

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

  // Camera flights

  fun flyCamera(keyframes: Array<CameraKeyframe>, start: Double, loop: Boolean, apply: (MapCamera) -> Unit) {
    if (keyframes.size < 2) {
      stopFlight()
      keyframes.firstOrNull()?.let { apply(it.camera) }
      return
    }
    flight = CameraFlight(keyframes, start, loop)
    flightApply = apply
    stepFlight()
    setNeedsRender()
  }

  fun stopFlight() {
    flight = null
    flightApply = null
  }

  val isFlying: Boolean get() = flight != null

  private fun stepFlight() {
    val flight = flight ?: return
    val (camera, ended) = flight.step(System.currentTimeMillis() / 1000.0)
    flightApply?.invoke(camera)
    if (ended) stopFlight()
    needsRender = true
  }

  // Content

  fun setModels(models: Array<NativeMapModel>) {
    if (destroyed) return
    val seen = HashSet<String>()
    for (model in models) {
      if (!seen.add(model.id)) {
        reportOnce("Duplicate model id \"${model.id}\"; only the first is drawn")
        continue
      }
      val existing = entries[model.id]
      if (existing != null) existing.update(model, force = false)
      else entries[model.id] = Entry(model).also { it.update(model, force = true) }
    }
    for (id in entries.keys.toList()) {
      if (id !in seen) entries.remove(id)?.destroy()
    }
    refreshTerrainUse()
    setNeedsRender()
  }

  fun setZones(zones: Array<NativeMapZone>) {
    if (destroyed) return
    val seen = HashSet<String>()
    for (zone in zones) {
      if (!seen.add(zone.id)) continue
      val existing = zoneEntries[zone.id]
      if (existing != null) existing.update(zone, force = false) else zoneEntries[zone.id] = ZoneEntry(zone)
    }
    for (id in zoneEntries.keys.toList()) {
      if (id !in seen) zoneEntries.remove(id)?.destroy()
    }
    setNeedsRender()
  }

  fun setPaths(paths: Array<NativeMapPath>) {
    if (destroyed) return
    val seen = HashSet<String>()
    for (path in paths) {
      if (!seen.add(path.id)) continue
      val existing = pathEntries[path.id]
      if (existing != null) existing.path = path else pathEntries[path.id] = PathEntry(path)
    }
    for (id in pathEntries.keys.toList()) {
      if (id !in seen) pathEntries.remove(id)?.destroy()
    }
    refreshTerrainUse()
    setNeedsRender()
  }

  private fun refreshTerrainUse() {
    usesTerrain = followsTerrain ||
      entries.values.any { it.model.altitudeReference == MapAltitudeReference.SEA } ||
      pathEntries.values.any { it.path.altitudeReference == MapAltitudeReference.SEA }
  }

  /** How the ground is drawn this frame. */
  private fun terrainFrame(state: MapCameraState): TerrainFrame {
    if (!usesTerrain || !state.drawsTerrain) return TerrainFrame(false, null, followsTerrain)
    // Engines draw 3D terrain around a camera centred on the ground at the
    // centre coordinate, so the scene's ground plane is at that height.
    groundHeight(state.latitude, state.longitude)?.let { lastCenterGround = it }
    return TerrainFrame(true, lastCenterGround, followsTerrain)
  }

  // Frames

  override fun doFrame(frameTimeNanos: Long) {
    frameScheduled = false
    if (destroyed) return
    val source = source ?: return
    val mapView = source.cameraView
    if (mapView == null || !mapView.isAttachedToWindow) return
    scheduleFrame()
    val dt = if (lastFrameNanos == 0L) 0.0 else (frameTimeNanos - lastFrameNanos) / 1e9
    lastFrameNanos = frameTimeNanos
    stepFlight()
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
    val animating = entries.values.any { it.isAnimating }
    if (!needsRender && !animating && state == lastRendered) return
    val chain = swapChain ?: return
    if (!uiHelper.isReadyToRender) return
    needsRender = false
    lastRendered = state
    updateScene(state, dt.toFloat())
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

  private fun updateScene(state: MapCameraState, dt: Float) {
    val aspect = if (state.height > 0) state.width / state.height else 1.0
    camera.setProjection(
      state.fieldOfView * 180 / PI, aspect, state.nearPlane, state.farPlane, Camera.Fov.VERTICAL)
    camera.setModelMatrix(state.cameraTransform)

    if (buildings.enabled) buildings.update(state)
    earth.show(scene, state.globe)
    if (state.globe) earth.setTransform(translation(0.0, -MapCameraState.EARTH_RADIUS, 0.0))

    val frame = FrameContext(state, terrainFrame(state), System.currentTimeMillis() / 1000.0, dt)
    val tooFar = state.distance > maxCameraDistance
    for (entry in entries.values) entry.place(frame, !tooFar)
    for (zone in zoneEntries.values) zone.place(frame, !tooFar)
    for (path in pathEntries.values) path.place(frame, !tooFar)
  }

  /** Height of the ground above sea level (below counts as sea level), or null until its tile loads. */
  private fun groundHeight(latitude: Double, longitude: Double): Double? =
    MunimTerrain.cachedGroundElevation(latitude, longitude)?.let { max(0.0, it) }

  // Taps and measuring

  fun modelHit(x: Double, y: Double): String? {
    val state = lastRendered ?: return null
    if (state.distance > maxCameraDistance) return null
    var best: Pair<String, Double>? = null
    for (entry in entries.values) {
      val depth = entry.hitTest(x, y, state) ?: continue
      if (best == null || depth < best.second) best = entry.model.id to depth
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
      val ground = state.scenePosition(entry.model.latitude, entry.model.longitude, 0.0)
      if (state.globe) {
        // Only the side of the globe facing the camera.
        val up = state.localUp(entry.model.latitude, entry.model.longitude)
        val eye = state.position
        if (up[0] * (eye[0] - ground[0]) + up[1] * (eye[1] - ground[1]) + up[2] * (eye[2] - ground[2]) <= 0) continue
      }
      val ours = state.project(ground) ?: continue
      if (ours[0] < 4 || ours[1] < 4 || ours[0] > state.width - 4 || ours[1] > state.height - 4) continue
      val theirs = source.screenPoint(entry.model.latitude, entry.model.longitude) ?: continue
      errors.add(hypot(ours[0] - theirs.x, ours[1] - theirs.y) / state.pixelRatio)
      if (entry.isDrawnOnScreen(state)) drawn++
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
    MunimTerrain.removeListener(terrainListener)
    for (entry in entries.values) entry.destroy()
    for (zone in zoneEntries.values) zone.destroy()
    for (path in pathEntries.values) path.destroy()
    entries.clear()
    zoneEntries.clear()
    pathEntries.clear()
    buildings.destroy()
    earth.destroy(scene)
    destroyed = true
    uiHelper.detach()
    swapChain?.let { engine.destroySwapChain(it) }
    swapChain = null
    particleTextureValue?.let { engine.destroyTexture(it) }
    shadowTextureValue?.let { engine.destroyTexture(it) }
    materials.destroy()
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

  /** What every entry needs this frame. */
  private class FrameContext(val state: MapCameraState, val terrain: TerrainFrame, val now: Double, val dt: Float) {
    val eye = state.position
    private val r = state.rotation
    val right = floatArrayOf(r[0].toFloat(), r[3].toFloat(), r[6].toFloat())
    val up = floatArrayOf(r[1].toFloat(), r[4].toFloat(), r[7].toFloat())
    val back = floatArrayOf(r[2].toFloat(), r[5].toFloat(), r[8].toFloat())
    val eyeF = floatArrayOf(eye[0].toFloat(), eye[1].toFloat(), eye[2].toFloat())

    /** Metres per screen point at this depth. */
    fun metersPerPoint(depth: Double) = state.pixelRatio * depth / state.focalLength

    fun depth(p: DoubleArray) = state.project(p)?.get(2)

    /** Facing the camera: T(center) * camera rotation * S(scale). */
    fun billboard(center: DoubleArray, scale: Double): FloatArray {
      val s = scale.toFloat()
      return floatArrayOf(
        right[0] * s, right[1] * s, right[2] * s, 0f,
        up[0] * s, up[1] * s, up[2] * s, 0f,
        back[0] * s, back[1] * s, back[2] * s, 0f,
        center[0].toFloat(), center[1].toFloat(), center[2].toFloat(), 1f,
      )
    }
  }

  /** How the ground is drawn this frame, for placing things on terrain. */
  private class TerrainFrame(
    /** The engine draws 3D terrain, with the scene's ground plane at the height of the ground at the centre. */
    val drawn: Boolean,
    val centerGround: Double?,
    val follow: Boolean,
  ) {
    fun lifts(reference: MapAltitudeReference) = drawn && (reference == MapAltitudeReference.SEA || follow)
    fun needsGround(reference: MapAltitudeReference) = reference == MapAltitudeReference.SEA || lifts(reference)
  }

  // MARK: - Models

  /** One model: its content (a GLB, a shape or a picture) and the shadow, stem, label and effect around it. */
  private inner class Entry(var model: NativeMapModel) {
    private var contentKey = ""
    private var loadGeneration = 0
    /** A glTF / GLB file. */
    private var asset: FilamentAsset? = null
    private var assetInScene = false
    private var animationCount = 0
    /** A built-in shape. */
    private var mesh: MeshPart? = null
    /** A picture facing the camera. */
    private var picture: MeshPart? = null
    private var pictureTexture: Texture? = null
    private var pictureAspect = 1f
    private val hasContent get() = asset != null || mesh != null || picture != null
    /** Bounds of the content, base centred on the origin (model units). */
    private var lo = floatArrayOf(-0.5f, 0f, -0.5f)
    private var hi = floatArrayOf(0.5f, 1f, 0.5f)
    /** Moves a glTF file so its base is centred on the origin. */
    private var assetOffset = floatArrayOf(0f, 0f, 0f)
    private val contentHeight get() = max(0.01f, hi[1] - lo[1])
    private val contentWidth get() = max(0.01f, max(hi[0] - lo[0], hi[2] - lo[2]))
    private val contentRadius: Float
      get() {
        val dx = hi[0] - lo[0]
        val dy = hi[1] - lo[1]
        val dz = hi[2] - lo[2]
        return max(0.01f, sqrt(dx * dx + dy * dy + dz * dz) / 2)
      }
    private var shadow: MeshPart? = null
    private var label: MeshPart? = null
    private var labelTexture: Texture? = null
    private var labelAspect = 1f
    private var stem: MeshPart? = null
    private var stemDot: MeshPart? = null
    private var effect: ModelEffect? = null
    private var effectKey = ""

    private var scale = 1.0
    private var altitude = 0.0
    private var lastGround: Double? = null
    private var waitingForGround = false
    /** This frame: the model's transform, base and up. */
    private val body = FloatArray(16)
    private var base = doubleArrayOf(0.0, 0.0, 0.0)
    private var up = doubleArrayOf(0.0, 1.0, 0.0)
    private var placed = false

    val isAnimating: Boolean
      get() = model.visible && (model.spinDegreesPerSecond != 0.0 ||
        (model.playAnimations && animationCount > 0) ||
        (model.effect != MapModelEffect.NONE && model.effectIntensity > 0) ||
        model.motion.size > 1)

    fun update(next: NativeMapModel, force: Boolean) {
      val previous = model
      model = next
      if (next.altitudeReference == MapAltitudeReference.SEA && (force ||
          previous.altitudeReference != MapAltitudeReference.SEA || previous.motion.size != next.motion.size ||
          previous.motionStart != next.motionStart)) {
        prefetchTerrain()
      }
      val key = listOf(
        next.uri, next.shape.name, next.width, next.height, next.length, next.color, next.emissive, next.imageUri,
        next.imageBorderColor, next.imageBorderWidth, next.imageBadge,
        if (next.imageUri.isEmpty()) "" else next.screenSize, next.occluder,
      ).joinToString("|")
      if (force || key != contentKey) {
        contentKey = key
        loadContent()
      } else if (previous.tintColor != next.tintColor) {
        asset?.let { if (next.tintColor.isEmpty()) loadContent() else applyTint(it) }
      }
      updateEffect()
      if (force || previous.label != next.label) {
        label?.destroy(scene)
        labelTexture?.let { engine.destroyTexture(it) }
        label = null
        labelTexture = null
        if (next.label.isNotEmpty()) {
          val bitmap = ModelBitmaps.label(next.label)
          labelAspect = bitmap.width.toFloat() / bitmap.height
          val texture = materials.texture(bitmap)
          labelTexture = texture
          label = MeshPart(engine, Shapes.quad(labelAspect), materials.unlit(texture, blend = true, onTop = true, label = "munim-label"),
            channel = CHANNEL_ON_TOP, priority = 7)
        }
      }
      if (force || previous.stemColor != next.stemColor || previous.stem != next.stem) {
        stem?.destroy(scene)
        stemDot?.destroy(scene)
        stem = null
        stemDot = null
        if (next.stem) {
          val color = ModelMaterials.linear(parseColor(next.stemColor) ?: floatArrayOf(1f, 1f, 1f, 1f), premultiplied = false)
          val cylinder = Shapes.stem().also { it.setColor(color[0], color[1], color[2], 1f) }
          stem = MeshPart(engine, cylinder, materials.unlit(blend = false, onTop = true, label = "munim-stem"),
            channel = CHANNEL_ON_TOP, priority = 5)
          stemDot = MeshPart(engine, cylinder, materials.unlit(blend = false, onTop = true, label = "munim-stem"),
            channel = CHANNEL_ON_TOP, priority = 5)
        }
      }
      if (force || previous.groundShadow != next.groundShadow) updateShadow()
      if (asset != null && (force || previous.playAnimations != next.playAnimations) && !next.playAnimations) {
        asset?.instance?.animator?.let { animator ->
          for (i in 0 until animationCount) animator.applyAnimation(i, 0f)
          animator.updateBoneMatrices()
        }
      }
    }

    private fun prefetchTerrain() {
      val points = mutableListOf(model.latitude to model.longitude)
      val frames = model.motion
      for (i in 1 until frames.size) {
        val a = frames[i - 1]
        val b = frames[i]
        val dy = (b.latitude - a.latitude) * 111_320
        val dx = (b.longitude - a.longitude) * 111_320 * cos(a.latitude * PI / 180)
        // A sample every kilometre catches every tile on the way.
        val steps = (hypot(dx, dy) / 1000).toInt().coerceIn(1, 200)
        for (k in 0..steps) {
          val f = k.toDouble() / steps
          points.add((a.latitude + (b.latitude - a.latitude) * f) to (a.longitude + (b.longitude - a.longitude) * f))
        }
      }
      MunimTerrain.prefetch(points)
    }

    // Content

    private fun clearContent() {
      asset?.let {
        if (assetInScene) scene.removeEntities(it.entities)
        assetLoader.destroyAsset(it)
      }
      asset = null
      assetInScene = false
      animationCount = 0
      mesh?.destroy(scene)
      mesh = null
      picture?.destroy(scene)
      picture = null
      pictureTexture?.let { engine.destroyTexture(it) }
      pictureTexture = null
    }

    private fun loadContent() {
      loadGeneration += 1
      val generation = loadGeneration
      val m = model
      if (m.imageUri.isNotEmpty()) {
        ModelAssets.load(context, m.imageUri) { result ->
          if (destroyed || entries[m.id] !== this || generation != loadGeneration) return@load
          val image = result.getOrNull()?.let { ModelBitmaps.decode(it) }
          if (image == null) {
            reportError("Could not load image for \"${m.id}\": " +
              (result.exceptionOrNull()?.message ?: "${m.imageUri} is not a PNG or JPEG"))
            return@load
          }
          clearContent()
          val bitmap = ModelBitmaps.avatar(image, model)
          pictureAspect = bitmap.width.toFloat() / bitmap.height
          val texture = materials.texture(bitmap)
          pictureTexture = texture
          picture = MeshPart(engine, Shapes.quad(pictureAspect), materials.unlit(texture, blend = true, onTop = true, label = "munim-picture"),
            channel = CHANNEL_ON_TOP, priority = 6)
          setBounds(floatArrayOf(-pictureAspect / 2, 0f, 0f), floatArrayOf(pictureAspect / 2, 1f, 0f))
          installed()
        }
        return
      }
      if (m.shape != MapModelShape.NONE || m.uri.isEmpty()) {
        clearContent()
        val data = Shapes.shape(m.shape.name.lowercase(), m.width.toFloat(), m.height.toFloat(), m.length.toFloat())
        if (data != null) {
          val color = parseColor(m.color) ?: floatArrayOf(0.04f, 0.52f, 1f, 1f)
          val material = if (m.occluder) materials.unlit(blend = false, occluder = true, label = "munim-occluder")
          else materials.lit(color, metallic = 0.1f, roughness = 0.45f, emissive = m.emissive)
          mesh = MeshPart(engine, data, material, lit = !m.occluder,
            channel = if (m.occluder) CHANNEL_OCCLUDERS else CHANNEL_MODELS, priority = if (m.occluder) 0 else 4)
          data.bounds()?.let { (l, h) -> setBounds(l, h) }
        }
        installed()
        return
      }
      val uri = m.uri
      ModelAssets.load(context, uri) { result ->
        if (destroyed || entries[m.id] !== this || generation != loadGeneration) return@load
        result.onFailure { reportError("Could not load model \"${m.id}\": ${it.message}") }
        result.onSuccess { bytes ->
          val buffer = ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder())
          buffer.put(bytes)
          buffer.flip()
          val loaded = assetLoader.createAsset(buffer)
          if (loaded == null) {
            reportError("Could not read model \"${m.id}\" ($uri): not a glTF / GLB file")
            return@onSuccess
          }
          resourceLoader.loadResources(loaded)
          loaded.releaseSourceData()
          clearContent()
          asset = loaded
          val box = loaded.boundingBox
          val c = box.center
          val e = box.halfExtent
          assetOffset = floatArrayOf(-c[0], -(c[1] - e[1]), -c[2])
          setBounds(floatArrayOf(-e[0], 0f, -e[2]), floatArrayOf(e[0], 2 * e[1], e[2]))
          animationCount = loaded.instance?.animator?.animationCount ?: 0
          val rm = engine.renderableManager
          for (entity in loaded.renderableEntities) {
            val instance = rm.getInstance(entity)
            if (model.occluder) {
              rm.setChannel(instance, CHANNEL_OCCLUDERS)
              rm.setPriority(instance, 0)
              for (p in 0 until rm.getPrimitiveCount(instance)) {
                val mi = rm.getMaterialInstanceAt(instance, p)
                mi.setColorWrite(false)
                mi.setDepthWrite(true)
              }
            } else {
              rm.setChannel(instance, CHANNEL_MODELS)
            }
          }
          applyTint(loaded)
          installed()
        }
      }
    }

    private fun setBounds(l: FloatArray, h: FloatArray) {
      lo = l
      hi = h
    }

    private fun installed() {
      effectKey = ""
      updateEffect()
      updateShadow()
      setNeedsRender()
    }

    private fun updateShadow() {
      shadow?.destroy(scene)
      shadow = null
      if (!model.groundShadow || !hasContent || model.occluder) return
      shadow = MeshPart(engine, Shapes.groundQuad(), materials.unlit(shadowTexture, blend = true, label = "munim-shadow"),
        channel = CHANNEL_MODELS, priority = 3)
    }

    /** Recolours the materials named `paint…` (exports may add `_2`, `_3`), as iOS. */
    private fun applyTint(asset: FilamentAsset) {
      val color = parseColor(model.tintColor) ?: return
      val rm = engine.renderableManager
      for (entity in asset.renderableEntities) {
        val instance = rm.getInstance(entity)
        for (primitive in 0 until rm.getPrimitiveCount(instance)) {
          val material = rm.getMaterialInstanceAt(instance, primitive)
          if (material.name.lowercase().startsWith("paint")) {
            material.setParameter("baseColorFactor", Colors.RgbaType.SRGB, color[0], color[1], color[2], color[3])
          }
        }
      }
    }

    private fun updateEffect() {
      if (model.effect == MapModelEffect.NONE) {
        effect?.destroy()
        effect = null
        effectKey = ""
        return
      }
      // Sized to the content when there is some, otherwise to `width` / `height`.
      val h = if (hasContent) contentHeight else model.height.toFloat()
      val w = if (hasContent) contentWidth else model.width.toFloat()
      val key = "${model.effect}|$h|$w|${model.effectOrigins}"
      if (key != effectKey) {
        effectKey = key
        effect?.destroy()
        effect = ModelEffect(engine, scene, materials, particleTexture, model.effect, h, w, parseOrigins(model.effectOrigins))
      }
      effect?.intensity = model.effectIntensity.toFloat()
    }

    // Placing

    private fun hideAll() {
      asset?.let { if (assetInScene) scene.removeEntities(it.entities) }
      assetInScene = false
      mesh?.show(scene, false)
      picture?.show(scene, false)
      shadow?.show(scene, false)
      label?.show(scene, false)
      stem?.show(scene, false)
      stemDot?.show(scene, false)
      effect?.update(0f, body, 1f, floatArrayOf(1f, 0f, 0f), floatArrayOf(0f, 1f, 0f), floatArrayOf(0f, 0f, 0f), false)
      placed = false
    }

    fun place(frame: FrameContext, allowed: Boolean) {
      if (!allowed || !model.visible) return hideAll()
      val state = frame.state
      val pose = pose(model, frame.now)
      var altitude = pose[2]
      var groundLevel = 0.0
      val reference = model.altitudeReference
      if (frame.terrain.needsGround(reference)) {
        groundHeight(pose[0], pose[1])?.let { lastGround = it }
        val ground = lastGround
        if (ground == null || (frame.terrain.lifts(reference) && frame.terrain.centerGround == null)) {
          waitingForGround = true
          return hideAll()
        }
        if (reference == MapAltitudeReference.SEA) altitude -= ground
        val center = frame.terrain.centerGround
        if (frame.terrain.lifts(reference) && center != null) groundLevel = ground - center
      }
      waitingForGround = false
      this.altitude = altitude
      val ground = state.scenePosition(pose[0], pose[1], groundLevel)
      val local = state.localOrientation(pose[0], pose[1])
      up = doubleArrayOf(local[1], local[4], local[7])
      var position = state.scenePosition(pose[0], pose[1], groundLevel + altitude)
      if (model.liftPoints != 0.0) {
        val depth = frame.depth(position)
        if (depth != null && depth > 0) {
          val lift = model.liftPoints * frame.metersPerPoint(depth)
          position = doubleArrayOf(position[0] + up[0] * lift, position[1] + up[1] * lift, position[2] + up[2] * lift)
        }
      }
      base = position
      var s = model.scale
      if (model.screenSize > 0) {
        val depth = frame.depth(position)
        if (depth == null || depth <= 0) return hideAll()
        // Height on screen is focal * height / depth.
        s *= model.screenSize * frame.metersPerPoint(depth) / contentHeight
      }
      scale = s
      val heading = pose[3] + model.spinDegreesPerSecond * frame.now
      compose(position, local, -heading * PI / 180, s, body)
      placed = true

      asset?.let { asset ->
        if (!assetInScene) {
          scene.addEntities(asset.entities)
          assetInScene = true
        }
        // glTF models face +z; iOS turns them half a turn (GLTFLoader) so the catalogue's headings match.
        val content = multiply(body, multiply(rotationY(PI), translation(assetOffset[0].toDouble(), assetOffset[1].toDouble(), assetOffset[2].toDouble())))
        val tm = engine.transformManager
        tm.setTransform(tm.getInstance(asset.root), content)
        if (model.playAnimations && animationCount > 0) {
          val animator = asset.instance?.animator
          if (animator != null) {
            for (i in 0 until animationCount) {
              val duration = animator.getAnimationDuration(i)
              animator.applyAnimation(i, if (duration > 0) (frame.now % duration).toFloat() else 0f)
            }
            animator.updateBoneMatrices()
          }
        }
      }
      mesh?.let {
        it.show(scene, true)
        it.setTransform(body)
      }
      picture?.let {
        it.show(scene, true)
        val c = doubleArrayOf(position[0] + up[0] * 0.5 * s, position[1] + up[1] * 0.5 * s, position[2] + up[2] * 0.5 * s)
        it.setTransform(frame.billboard(c, s))
      }
      shadow?.let {
        it.show(scene, true)
        val d = (max(hi[0] - lo[0], hi[2] - lo[2]) * 1.6).toDouble()
        it.setTransform(multiply(body, multiply(translation(0.0, 0.05, 0.0), scaling(d, 1.0, d))))
      }
      effect?.let { effect ->
        if (s > 0) {
          effect.groundDistance = (altitude / s).toFloat()
          if (model.effect == MapModelEffect.CONTRAIL) {
            // Ground speed from the motion, in model units.
            val ahead = pose(model, frame.now + 0.2)
            val dy = (ahead[0] - pose[0]) * 111_320
            val dx = (ahead[1] - pose[1]) * 111_320 * cos(pose[0] * PI / 180)
            effect.speed = (hypot(dx, dy) / 0.2 / s).toFloat()
          }
        }
        effect.update(frame.dt, body, s.toFloat(), frame.right, frame.up, frame.eyeF, true)
      }
      placeStem(frame, position, ground, local)
      placeLabel(frame, position)
    }

    /** About 2 points wide, with an 8-point dot on the ground. */
    private fun placeStem(frame: FrameContext, top: DoubleArray, ground: DoubleArray, local: DoubleArray) {
      val stem = stem ?: return
      val dot = stemDot ?: return
      val show = model.stem && altitude > 0.5
      stem.show(scene, show)
      dot.show(scene, show)
      if (!show) return
      val middle = DoubleArray(3) { (ground[it] + top[it]) / 2 }
      val length = sqrt((0..2).sumOf { (top[it] - ground[it]) * (top[it] - ground[it]) })
      val middleDepth = max(1.0, frame.depth(middle) ?: frame.state.distance)
      val groundDepth = max(1.0, frame.depth(ground) ?: frame.state.distance)
      val width = 2 * frame.metersPerPoint(middleDepth)
      stem.setTransform(composeScaled(middle, local, width, length, width))
      val d = 8 * frame.metersPerPoint(groundDepth)
      val dotCenter = DoubleArray(3) { ground[it] + up[it] * 0.2 }
      dot.setTransform(composeScaled(dotCenter, local, d, 0.05, d))
    }

    /** 22 points tall, 4 points above the top of the model. */
    private fun placeLabel(frame: FrameContext, position: DoubleArray) {
      val label = label ?: return
      label.show(scene, true)
      val height = (if (hasContent) contentHeight else 0f) * scale
      val top = DoubleArray(3) { position[it] + up[it] * height }
      val depth = max(1.0, frame.depth(top) ?: frame.state.distance)
      val mpp = frame.metersPerPoint(depth)
      val size = 22 * mpp
      val center = DoubleArray(3) { top[it] + up[it] * (4 * mpp + size / 2) }
      label.setTransform(frame.billboard(center, size))
    }

    /** Depth of the model if the pixel falls on it. */
    fun hitTest(x: Double, y: Double, state: MapCameraState): Double? {
      if (!model.visible || waitingForGround || !hasContent || !placed) return null
      val h = contentHeight * scale / 2
      val center = doubleArrayOf(base[0] + up[0] * h, base[1] + up[1] * h, base[2] + up[2] * h)
      val projected = state.project(center) ?: return null
      val radius = state.focalLength * contentRadius * scale / projected[2]
      val slop = max(radius, 22 * state.pixelRatio)
      return if (hypot(x - projected[0], y - projected[1]) <= slop) projected[2] else null
    }

    /** Whether the model's bounding box is on screen this frame. */
    fun isDrawnOnScreen(state: MapCameraState): Boolean {
      if (!placed || !hasContent) return false
      var minX = Double.MAX_VALUE
      var minY = Double.MAX_VALUE
      var maxX = -Double.MAX_VALUE
      var maxY = -Double.MAX_VALUE
      for (i in 0 until 8) {
        val cx = if (i and 1 == 0) lo[0] else hi[0]
        val cy = if (i and 2 == 0) lo[1] else hi[1]
        val cz = if (i and 4 == 0) lo[2] else hi[2]
        val w = DoubleArray(3) { r -> (body[r] * cx + body[4 + r] * cy + body[8 + r] * cz + body[12 + r]).toDouble() }
        val p = state.project(w) ?: continue
        minX = min(minX, p[0]); maxX = max(maxX, p[0]); minY = min(minY, p[1]); maxY = max(maxY, p[1])
      }
      return maxX >= 0 && maxY >= 0 && minX <= state.width && minY <= state.height
    }

    fun destroy() {
      loadGeneration += 1
      clearContent()
      shadow?.destroy(scene)
      label?.destroy(scene)
      labelTexture?.let { engine.destroyTexture(it) }
      stem?.destroy(scene)
      stemDot?.destroy(scene)
      effect?.destroy()
    }
  }

  // MARK: - Zones

  /** A see-through wall on a zone outline, built once in metres around its first point. */
  private inner class ZoneEntry(private var zone: NativeMapZone) {
    private var part: MeshPart? = null
    private var key = ""
    private var anchor = 0.0 to 0.0
    private var anchorGround: Double? = null

    init {
      update(zone, force = true)
    }

    fun update(next: NativeMapZone, force: Boolean) {
      zone = next
      val newKey = next.points.joinToString(";") { "${it.latitude},${it.longitude}" } + "|${next.height}|${next.color}"
      if (!force && newKey == key) return
      key = newKey
      part?.destroy(scene)
      part = build()?.let {
        MeshPart(engine, it, materials.unlit(blend = true, label = "munim-zone"), channel = CHANNEL_MODELS, priority = 5)
      }
      anchorGround = null
    }

    private fun build(): MeshData? {
      val points = zone.points
      if (points.size < 2) return null
      val first = points[0]
      anchor = first.latitude to first.longitude
      val origin = MapCameraState.mapPoint(first.latitude, first.longitude)
      val scale = MapCameraState.metersPerMapPoint(first.latitude)
      val ground = points.map {
        val p = MapCameraState.mapPoint(it.latitude, it.longitude)
        floatArrayOf(((p.first - origin.first) * scale).toFloat(), ((p.second - origin.second) * scale).toFloat())
      }
      val height = max(0.5, zone.height).toFloat()
      val color = parseColor(zone.color) ?: floatArrayOf(0f, 0.48f, 1f, 0.25f)
      val linear = ModelMaterials.linear(color, premultiplied = false)
      // Premultiplied colours: see-through (lighter towards the top) between two solid bands.
      fun rgba(alpha: Float) = floatArrayOf(linear[0] * alpha, linear[1] * alpha, linear[2] * alpha, alpha)
      val band = min(height * 0.25f, max(0.8f, height * 0.05f))
      val a = color[3]
      val layers = listOf(
        listOf(0f, band) to (rgba(0.95f) to rgba(0.95f)),
        listOf(band, height - band) to (rgba(a) to rgba(a * 0.45f)),
        listOf(height - band, height) to (rgba(0.95f) to rgba(0.95f)),
      )
      val mesh = MeshData()
      val count = ground.size
      val closed = count >= 3
      for (i in 0 until if (closed) count else count - 1) {
        val p0 = ground[i]
        val p1 = ground[(i + 1) % count]
        for ((ys, colors) in layers) {
          val (c0, c1) = colors
          val v = mesh.vertex(p0[0], ys[0], p0[1], r = c0[0], g = c0[1], b = c0[2], a = c0[3])
          mesh.vertex(p1[0], ys[0], p1[1], r = c0[0], g = c0[1], b = c0[2], a = c0[3])
          mesh.vertex(p1[0], ys[1], p1[1], r = c1[0], g = c1[1], b = c1[2], a = c1[3])
          mesh.vertex(p0[0], ys[1], p0[1], r = c1[0], g = c1[1], b = c1[2], a = c1[3])
          mesh.quad(v, v + 1, v + 2, v + 3)
        }
      }
      return mesh
    }

    /** With `followTerrain` on 3D terrain the wall stands on the ground at its first point. */
    fun place(frame: FrameContext, allowed: Boolean) {
      val part = part ?: return
      val show = allowed && zone.visible
      part.show(scene, show)
      if (!show) return
      var level = 0.0
      if (frame.terrain.lifts(MapAltitudeReference.GROUND)) {
        if (anchorGround == null) anchorGround = groundHeight(anchor.first, anchor.second)
        val ground = anchorGround
        val center = frame.terrain.centerGround
        if (ground != null && center != null) level = ground - center
      }
      val position = frame.state.scenePosition(anchor.first, anchor.second, level)
      val local = frame.state.localOrientation(anchor.first, anchor.second)
      val m = FloatArray(16)
      compose(position, local, 0.0, 1.0, m)
      part.setTransform(m)
    }

    fun destroy() {
      part?.destroy(scene)
    }
  }

  // MARK: - Paths

  /** A ribbon a fixed number of points wide, rebuilt each frame so it keeps facing the camera. */
  private inner class PathEntry(path: NativeMapPath) {
    var path: NativeMapPath = path
      set(value) {
        val old = field
        field = value
        if (old.altitudeReference != value.altitudeReference || old.points.size != value.points.size ||
          old.points.indices.any { old.points[it].latitude != value.points[it].latitude || old.points[it].longitude != value.points[it].longitude }) {
          grounds = arrayOfNulls(0)
        }
      }
    private val mesh = MeshData()
    private val part = MeshPart(engine, MeshData(), materials.unlit(blend = true, label = "munim-path"),
      channel = CHANNEL_MODELS, priority = 5, dynamic = true)
    /** For paths above sea level: the ground under each point, filled in as tiles load. */
    private var grounds = arrayOfNulls<Double>(0)

    private fun groundHeights(): DoubleArray? {
      if (grounds.size != path.points.size) grounds = arrayOfNulls(path.points.size)
      var complete = true
      for ((i, p) in path.points.withIndex()) {
        if (grounds[i] == null) grounds[i] = groundHeight(p.latitude, p.longitude)
        if (grounds[i] == null) complete = false
      }
      return if (complete) DoubleArray(grounds.size) { grounds[it] ?: 0.0 } else null
    }

    fun place(frame: FrameContext, allowed: Boolean) {
      val count = path.points.size
      if (!allowed || !path.visible || count < 2) {
        part.show(scene, false)
        return
      }
      val state = frame.state
      // Scene height of each point: above sea level, less the ground there
      // (flat map) or less the ground at the centre (3D terrain); above the
      // ground, plus the rise of the drawn terrain when following it.
      val reference = path.altitudeReference
      var ground: DoubleArray? = null
      var center = 0.0
      if (frame.terrain.needsGround(reference)) {
        val heights = groundHeights()
        if (heights == null || (frame.terrain.lifts(reference) && frame.terrain.centerGround == null)) {
          part.show(scene, false)
          return
        }
        ground = heights
        center = frame.terrain.centerGround ?: 0.0
      }
      val lifted = frame.terrain.lifts(reference)
      val points = path.points.mapIndexed { i, p ->
        var altitude = p.altitude
        if (ground != null) {
          if (reference == MapAltitudeReference.SEA) altitude -= ground[i]
          if (lifted) altitude += ground[i] - center
        }
        state.scenePosition(p.latitude, p.longitude, altitude)
      }
      val color = ModelMaterials.linear(parseColor(path.color) ?: floatArrayOf(1f, 1f, 1f, 1f))
      val eye = frame.eye
      val halfWidth = max(0.5, path.width) / 2
      val closed = path.closed && count >= 3
      mesh.clear()
      val n = if (closed) count + 1 else count
      for (i in 0 until n) {
        val index = i % count
        val p = points[index]
        val previous = if (closed) points[(index + count - 1) % count] else points[max(0, index - 1)]
        val next = if (closed) points[(index + 1) % count] else points[min(count - 1, index + 1)]
        val along = DoubleArray(3) { next[it] - previous[it] }
        val toEye = DoubleArray(3) { eye[it] - p[it] }
        var side = doubleArrayOf(
          along[1] * toEye[2] - along[2] * toEye[1],
          along[2] * toEye[0] - along[0] * toEye[2],
          along[0] * toEye[1] - along[1] * toEye[0])
        val length = MapCameraState.norm(side)
        side = if (length > 0) DoubleArray(3) { side[it] / length } else doubleArrayOf(1.0, 0.0, 0.0)
        val depth = max(1.0, MapCameraState.norm(toEye))
        val offset = halfWidth * state.pixelRatio * depth / state.focalLength
        mesh.vertex((p[0] - side[0] * offset).toFloat(), (p[1] - side[1] * offset).toFloat(), (p[2] - side[2] * offset).toFloat(),
          r = color[0], g = color[1], b = color[2], a = color[3])
        mesh.vertex((p[0] + side[0] * offset).toFloat(), (p[1] + side[1] * offset).toFloat(), (p[2] + side[2] * offset).toFloat(),
          r = color[0], g = color[1], b = color[2], a = color[3])
        if (i > 0) {
          val v = i * 2
          mesh.quad(v - 2, v, v + 1, v - 1)
        }
      }
      part.update(mesh)
      part.setTransform(IDENTITY)
      part.show(scene, true)
    }

    fun destroy() {
      part.destroy(scene)
    }
  }
}

// MARK: - Maths

private val IDENTITY = floatArrayOf(1f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 1f)

/** T(position) * local * Ry(yaw) * S(scale), column-major into [out]. `local` is row-major 3x3. */
private fun compose(position: DoubleArray, local: DoubleArray, yaw: Double, scale: Double, out: FloatArray) {
  val c = cos(yaw)
  val s = sin(yaw)
  // Columns of Ry: (c, 0, -s), (0, 1, 0), (s, 0, c).
  val ry = arrayOf(doubleArrayOf(c, 0.0, -s), doubleArrayOf(0.0, 1.0, 0.0), doubleArrayOf(s, 0.0, c))
  for (col in 0..2) {
    val v = ry[col]
    for (row in 0..2) {
      out[col * 4 + row] = ((local[row * 3] * v[0] + local[row * 3 + 1] * v[1] + local[row * 3 + 2] * v[2]) * scale).toFloat()
    }
    out[col * 4 + 3] = 0f
  }
  out[12] = position[0].toFloat(); out[13] = position[1].toFloat(); out[14] = position[2].toFloat(); out[15] = 1f
}

/** T(position) * local * S(sx, sy, sz). */
private fun composeScaled(position: DoubleArray, local: DoubleArray, sx: Double, sy: Double, sz: Double): FloatArray {
  val scales = doubleArrayOf(sx, sy, sz)
  val out = FloatArray(16)
  for (col in 0..2) for (row in 0..2) out[col * 4 + row] = (local[row * 3 + col] * scales[col]).toFloat()
  out[12] = position[0].toFloat(); out[13] = position[1].toFloat(); out[14] = position[2].toFloat(); out[15] = 1f
  return out
}

private fun translation(x: Double, y: Double, z: Double) =
  floatArrayOf(1f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 1f, 0f, x.toFloat(), y.toFloat(), z.toFloat(), 1f)

private fun scaling(x: Double, y: Double, z: Double) =
  floatArrayOf(x.toFloat(), 0f, 0f, 0f, 0f, y.toFloat(), 0f, 0f, 0f, 0f, z.toFloat(), 0f, 0f, 0f, 0f, 1f)

private fun rotationY(angle: Double): FloatArray {
  val c = cos(angle).toFloat()
  val s = sin(angle).toFloat()
  return floatArrayOf(c, 0f, -s, 0f, 0f, 1f, 0f, 0f, s, 0f, c, 0f, 0f, 0f, 0f, 1f)
}

/** Column-major a * b. */
private fun multiply(a: FloatArray, b: FloatArray): FloatArray {
  val out = FloatArray(16)
  for (col in 0..3) for (row in 0..3) {
    var sum = 0f
    for (k in 0..3) sum += a[k * 4 + row] * b[col * 4 + k]
    out[col * 4 + row] = sum
  }
  return out
}

/** Where a model is at `time` (seconds since 1970): latitude, longitude, altitude, heading (as iOS). */
private fun pose(model: NativeMapModel, time: Double): DoubleArray {
  val motion = model.motion
  val first = motion.firstOrNull() ?: return doubleArrayOf(model.latitude, model.longitude, model.altitude, model.heading)
  val last = motion.last()
  if (motion.size < 2 || last.t <= first.t) {
    return doubleArrayOf(first.latitude, first.longitude, first.altitude, if (first.heading >= 0) first.heading else model.heading)
  }
  var t = time - model.motionStart
  if (model.motionLoop) {
    val span = last.t - first.t
    t = first.t + (t - first.t) % span
    if (t < first.t) t += span
  }
  t = t.coerceIn(first.t, last.t)
  var i = 1
  while (i < motion.size - 1 && motion[i].t < t) i++
  val a: MotionKeyframe = motion[i - 1]
  val b: MotionKeyframe = motion[i]
  val f = if (b.t > a.t) (t - a.t) / (b.t - a.t) else 0.0
  var heading = model.heading
  if (a.heading >= 0 && b.heading >= 0) {
    val turn = ((b.heading - a.heading) % 360 + 540) % 360 - 180
    heading = a.heading + turn * f
  } else {
    // Face along the segment.
    val dy = b.latitude - a.latitude
    val dx = (b.longitude - a.longitude) * cos(a.latitude * PI / 180)
    if (abs(dx) + abs(dy) > 1e-12) heading = (atan2(dx, dy) * 180 / PI + 360) % 360
  }
  return doubleArrayOf(
    a.latitude + (b.latitude - a.latitude) * f,
    a.longitude + (b.longitude - a.longitude) * f,
    a.altitude + (b.altitude - a.altitude) * f,
    heading,
  )
}

/** `x,y,z;x,y,z` in the model's own metres. */
private fun parseOrigins(value: String): List<FloatArray> = value.split(";").mapNotNull { point ->
  val v = point.split(",").mapNotNull { it.trim().toFloatOrNull() }
  if (v.size == 3) v.toFloatArray() else null
}

/** `#RGB`, `#RRGGBB` or `#RRGGBBAA` as sRGB floats, or null. */
internal fun parseColor(value: String): FloatArray? {
  var hex = value.trim().removePrefix("#")
  if (hex.length == 3) hex = hex.map { "$it$it" }.joinToString("")
  if (hex.length != 6 && hex.length != 8) return null
  val n = hex.toLongOrNull(16) ?: return null
  return if (hex.length == 6) {
    floatArrayOf(((n shr 16) and 0xFF) / 255f, ((n shr 8) and 0xFF) / 255f, (n and 0xFF) / 255f, 1f)
  } else {
    floatArrayOf(((n shr 24) and 0xFF) / 255f, ((n shr 16) and 0xFF) / 255f, ((n shr 8) and 0xFF) / 255f, (n and 0xFF) / 255f)
  }
}
