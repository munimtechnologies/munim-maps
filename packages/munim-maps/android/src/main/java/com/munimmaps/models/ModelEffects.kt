package com.munimmaps.models

import com.google.android.filament.Engine
import com.google.android.filament.Scene
import com.google.android.filament.Texture
import com.margelo.nitro.munimmaps.MapModelEffect
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.random.Random

/**
 * Exhaust, smoke and contrails: the Android twin of iOS's `EffectNode`
 * (SceneKit particle systems), simulated on the CPU and drawn as
 * camera-facing puffs in one dynamic mesh.
 *
 * Particles live in the model's own units (base at the origin, y up, z to
 * the back), so they scale and turn with it; [update] is handed the model's
 * transform every frame.
 */
internal class ModelEffect(
  private val engine: Engine,
  private val scene: Scene,
  private val materials: ModelMaterials,
  particleTexture: Texture,
  effect: MapModelEffect,
  height: Float,
  width: Float,
  origins: List<FloatArray>,
) {
  private class Emitter(
    val birthRate: Float,
    val life: Float,
    val lifeVariation: Float,
    val size: Float,
    val growth: Float,
    var speed: Float,
    var speedVariation: Float,
    /** Half-angle of the emission cone, degrees. */
    val spread: Float,
    val additive: Boolean,
    /** (time 0…1, linear premultiplied-ready rgba) stops. */
    val colors: List<Pair<Float, FloatArray>>,
    val direction: FloatArray,
    val origin: FloatArray,
    /** Sphere radius, or a box when [box] is set. */
    val radius: Float,
    val box: FloatArray? = null,
    val acceleration: FloatArray = floatArrayOf(0f, 0f, 0f),
    val damping: Float = 0f,
    val stopsAtGround: Boolean = false,
    val followsMotion: Boolean = false,
  ) {
    var rate = birthRate
    var currentLife = life
    var currentLifeVariation = lifeVariation
    var pending = 0f
    val particles = ArrayList<Particle>()
  }

  private class Particle(val p: FloatArray, val v: FloatArray, var age: Float, val life: Float, val size: Float)

  private class Glow(val part: MeshPart, val depth: Float, val position: FloatArray, val scale: FloatArray, val opacity: Float)

  private val emitters = mutableListOf<Emitter>()
  private val glows = mutableListOf<Glow>()
  private val mesh = MeshData()
  private val part = MeshPart(engine, MeshData(), materials.unlit(particleTexture, blend = true, label = "munim-effect"),
    channel = 2, priority = 6, dynamic = true)
  private val random = Random(System.nanoTime())
  private var visible = false

  var intensity = 1f
    set(value) {
      val clamped = value.coerceIn(0f, 1f)
      if (clamped != field) {
        field = clamped
        apply()
      }
    }

  /** How far the model's base is above the ground, in its own units. */
  var groundDistance = Float.MAX_VALUE
    set(value) {
      if (abs(value - field) > 0.01f) {
        field = value
        apply()
      }
    }

  /** How fast the model moves, in its own units per second (contrails stay put). */
  var speed = 0f
    set(value) {
      if (abs(value - field) <= 0.01f) return
      field = value
      for (e in emitters) if (e.followsMotion) {
        e.speed = value
        e.speedVariation = 0f
      }
    }

  init {
    build(effect, height, width, origins)
    apply()
  }

  private fun rgba(r: Float, g: Float, b: Float, a: Float) = floatArrayOf(r, g, b, a)
  private fun white(w: Float, a: Float) = floatArrayOf(w, w, w, a)

  private fun build(effect: MapModelEffect, height: Float, width: Float, origins: List<FloatArray>) {
    when (effect) {
      MapModelEffect.NONE -> {}
      MapModelEffect.EXHAUST -> {
        // A methane engine cluster like Starship's: a long, clean flame,
        // white-hot at the nozzles, shock diamonds, a faint trail.
        val h = height
        val w = min(width, h * 0.08f)
        val plume = h * 0.45f
        val down = floatArrayOf(0f, -1f, 0f)
        emitters += Emitter(1600f, 0.3f, 0.04f, w * 0.8f, 1.3f, plume / 0.3f, plume / 0.3f * 0.2f, 1f, false,
          listOf(0f to rgba(1f, 0.97f, 0.9f, 1f), 0.25f to rgba(1f, 0.88f, 0.5f, 0.95f),
            0.6f to rgba(1f, 0.6f, 0.22f, 0.75f), 1f to rgba(0.95f, 0.42f, 0.15f, 0f)),
          down, floatArrayOf(0f, h * 0.005f, 0f), w * 0.3f, stopsAtGround = true)
        emitters += Emitter(800f, 0.18f, 0.03f, w * 0.5f, 0.8f, plume / 0.3f, plume / 0.3f * 0.2f, 0.6f, true,
          listOf(0f to rgba(1f, 0.95f, 0.85f, 0.9f), 1f to rgba(1f, 0.7f, 0.4f, 0f)),
          down, floatArrayOf(0f, h * 0.005f, 0f), w * 0.18f, stopsAtGround = true)
        for (i in 0 until 4) {
          val depth = w * (0.55f + i * 0.75f)
          val size = w * (0.32f - i * 0.04f)
          val sphere = MeshData().also { Shapes.sphere(it, 0.5f, 0f, rings = 10, segments = 16) }
          val opacity = 0.55f - i * 0.1f
          val color = ModelMaterials.linear(floatArrayOf(1f, 0.78f, 0.86f, 1f), premultiplied = false)
          sphere.setColor(color[0] * opacity, color[1] * opacity, color[2] * opacity, 0f) // additive
          val glow = MeshPart(engine, sphere, materials.unlit(blend = true, label = "munim-glow"), channel = 2, priority = 6)
          glows += Glow(glow, depth, floatArrayOf(0f, -depth, 0f), floatArrayOf(size, size * 1.6f, size), opacity)
        }
        emitters += Emitter(40f, 1.4f, 0.3f, w * 0.5f, 2.4f, h * 0.35f, h * 0.35f * 0.2f, 3f, false,
          listOf(0f to white(0.97f, 0f), 0.2f to white(0.95f, 0.16f), 1f to white(0.9f, 0f)),
          down, floatArrayOf(0f, -plume * 0.9f, 0f), w * 0.25f, stopsAtGround = true)
      }
      MapModelEffect.CONTRAIL -> {
        // One trail per engine, thrown backwards at the model's own speed so it hangs in the sky.
        val engines = origins.ifEmpty {
          listOf(floatArrayOf(-width * 0.17f, height * 0.3f, 0f), floatArrayOf(width * 0.17f, height * 0.3f, 0f))
        }
        for (origin in engines) {
          emitters += Emitter(120f, 7f, 0.5f, width * 0.06f, 5f, 0f, 0f, 0.4f, false,
            listOf(0f to white(1f, 0f), 0.03f to white(1f, 0.85f), 0.5f to white(0.98f, 0.45f), 1f to white(0.97f, 0f)),
            floatArrayOf(0f, 0f, 1f), origin, width * 0.01f, followsMotion = true)
        }
      }
      MapModelEffect.SMOKE -> {
        // A launch-pad cloud: boils up low, then rolls out across the ground.
        val h = height
        val w = width
        emitters += Emitter(14f, 4.5f, 1.2f, w * 0.09f, 2.2f, h * 0.22f, h * 0.22f * 0.2f, 40f, false,
          listOf(0f to white(0.96f, 0f), 0.12f to white(0.93f, 0.65f), 0.6f to rgba(0.86f, 0.85f, 0.83f, 0.4f), 1f to white(0.85f, 0f)),
          floatArrayOf(0f, 1f, 0f), floatArrayOf(0f, h * 0.08f, 0f), 0f,
          box = floatArrayOf(w * 0.12f, h * 0.05f, w * 0.12f), acceleration = floatArrayOf(0f, h * 0.015f, 0f), damping = 0.3f)
        emitters += Emitter(16f, 3.5f, 1f, w * 0.06f, 2.4f, w * 0.42f, w * 0.42f * 0.2f, 90f, false,
          listOf(0f to white(0.95f, 0f), 0.1f to rgba(0.88f, 0.86f, 0.83f, 0.6f), 1f to white(0.86f, 0f)),
          normalize(floatArrayOf(0f, 0.05f, 0f)), floatArrayOf(0f, h * 0.04f, 0f), w * 0.04f, damping = 0.9f)
      }
    }
    // Colours to linear once.
    for (e in emitters) for (stop in e.colors) {
      val linear = ModelMaterials.linear(stop.second, premultiplied = false)
      for (k in 0..2) stop.second[k] = linear[k]
    }
  }

  /** Throttles by intensity and keeps downward plumes above the ground (as iOS). */
  private fun apply() {
    for (glow in glows) {
      glow.part.material.setParameter("baseColorFactor", intensity, intensity, intensity, intensity)
    }
    for (e in emitters) {
      var rate = e.birthRate * intensity
      if (e.stopsAtGround) {
        val room = groundDistance + e.origin[1]
        val fastest = e.speed + e.speedVariation
        if (room <= 0.5f || fastest <= 0f) {
          rate = 0f
        } else {
          val scale = min(1f, room / (fastest * (e.life + e.lifeVariation)))
          e.currentLife = e.life * scale
          e.currentLifeVariation = e.lifeVariation * scale
        }
      }
      e.rate = rate
    }
  }

  /**
   * Steps the particles by [dt] seconds and rebuilds the puffs for this
   * frame. [model] is the model's transform (column-major, its own units to
   * the scene); [right] and [up] are the camera's axes, [eye] its position.
   */
  fun update(dt: Float, model: FloatArray, scale: Float, right: FloatArray, up: FloatArray, eye: FloatArray, show: Boolean) {
    visible = show
    part.show(scene, show)
    for (glow in glows) {
      val on = show && intensity >= 0.3f && glow.depth <= groundDistance
      glow.part.show(scene, on)
      if (on) {
        val m = model.copyOf()
        // model * T(position) * S(scale)
        val p = glow.position
        for (r in 0..2) m[12 + r] = model[r] * p[0] + model[4 + r] * p[1] + model[8 + r] * p[2] + model[12 + r]
        for (c in 0..2) for (r in 0..2) m[c * 4 + r] = model[c * 4 + r] * glow.scale[c]
        glow.part.setTransform(m)
      }
    }
    if (!show) return
    val step = dt.coerceIn(0f, 0.1f)
    for (e in emitters) simulate(e, step)
    draw(model, scale, right, up, eye)
  }

  private fun simulate(e: Emitter, dt: Float) {
    val iterator = e.particles.iterator()
    while (iterator.hasNext()) {
      val p = iterator.next()
      p.age += dt
      if (p.age >= p.life) {
        iterator.remove()
        continue
      }
      for (k in 0..2) {
        p.v[k] += e.acceleration[k] * dt
        if (e.damping > 0) p.v[k] *= max(0f, 1 - e.damping * dt)
        p.p[k] += p.v[k] * dt
      }
    }
    e.pending += e.rate * dt
    var births = e.pending.toInt()
    e.pending -= births
    births = min(births, 2_000)
    repeat(births) {
      val position = e.origin.copyOf()
      if (e.box != null) {
        for (k in 0..2) position[k] += (random.nextFloat() - 0.5f) * e.box[k]
      } else if (e.radius > 0) {
        val d = randomUnit()
        for (k in 0..2) position[k] += d[k] * e.radius
      }
      val direction = randomInCone(e.direction, e.spread)
      val speed = e.speed + (random.nextFloat() * 2 - 1) * e.speedVariation
      val life = max(0.01f, e.currentLife + (random.nextFloat() * 2 - 1) * e.currentLifeVariation)
      val size = e.size + (random.nextFloat() * 2 - 1) * e.size * 0.25f
      // Spread the births over the frame so puffs do not come in rows.
      val age = random.nextFloat() * dt
      val v = FloatArray(3) { direction[it] * speed }
      val p = FloatArray(3) { position[it] + v[it] * age }
      e.particles.add(Particle(p, v, age, life, size))
    }
  }

  private fun draw(model: FloatArray, scale: Float, right: FloatArray, up: FloatArray, eye: FloatArray) {
    mesh.clear()
    // Every puff in the scene, farthest first (one renderable, so sort here).
    val all = ArrayList<Triple<Emitter, Particle, FloatArray>>()
    for (e in emitters) for (p in e.particles) {
      val w = FloatArray(4)
      for (r in 0..2) w[r] = model[r] * p.p[0] + model[4 + r] * p.p[1] + model[8 + r] * p.p[2] + model[12 + r]
      val dx = w[0] - eye[0]
      val dy = w[1] - eye[1]
      val dz = w[2] - eye[2]
      w[3] = dx * dx + dy * dy + dz * dz
      all.add(Triple(e, p, w))
    }
    all.sortByDescending { it.third[3] }
    val color = FloatArray(4)
    for ((e, p, w) in all) {
      val f = (p.age / p.life).coerceIn(0f, 1f)
      val half = p.size * (1 + (e.growth - 1) * f) * scale / 2
      gradient(e.colors, f, color)
      val a = color[3]
      val r = color[0] * a
      val g = color[1] * a
      val b = color[2] * a
      val alpha = if (e.additive) 0f else a
      val i = mesh.vertex(w[0] - (right[0] + up[0]) * half, w[1] - (right[1] + up[1]) * half, w[2] - (right[2] + up[2]) * half,
        r = r, g = g, b = b, a = alpha, u = 0f, v = 1f)
      mesh.vertex(w[0] + (right[0] - up[0]) * half, w[1] + (right[1] - up[1]) * half, w[2] + (right[2] - up[2]) * half,
        r = r, g = g, b = b, a = alpha, u = 1f, v = 1f)
      mesh.vertex(w[0] + (right[0] + up[0]) * half, w[1] + (right[1] + up[1]) * half, w[2] + (right[2] + up[2]) * half,
        r = r, g = g, b = b, a = alpha, u = 1f, v = 0f)
      mesh.vertex(w[0] - (right[0] - up[0]) * half, w[1] - (right[1] - up[1]) * half, w[2] - (right[2] - up[2]) * half,
        r = r, g = g, b = b, a = alpha, u = 0f, v = 0f)
      mesh.quad(i, i + 1, i + 2, i + 3)
    }
    part.update(mesh)
  }

  val isEmpty: Boolean get() = emitters.isEmpty() && glows.isEmpty()

  private fun gradient(stops: List<Pair<Float, FloatArray>>, f: Float, out: FloatArray) {
    var i = 1
    while (i < stops.size - 1 && stops[i].first < f) i++
    val (t0, c0) = stops[i - 1]
    val (t1, c1) = stops[i]
    val k = if (t1 > t0) ((f - t0) / (t1 - t0)).coerceIn(0f, 1f) else 0f
    for (n in 0..3) out[n] = c0[n] + (c1[n] - c0[n]) * k
  }

  private fun randomUnit(): FloatArray {
    val z = random.nextFloat() * 2 - 1
    val t = random.nextFloat() * 2 * PI.toFloat()
    val r = sqrt(max(0f, 1 - z * z))
    return floatArrayOf(r * cos(t), r * sin(t), z)
  }

  private fun randomInCone(direction: FloatArray, spreadDegrees: Float): FloatArray {
    if (spreadDegrees <= 0f) return direction
    val angle = min(180f, spreadDegrees) * PI.toFloat() / 180
    // Uniform over the cap.
    val cosAngle = 1 - random.nextFloat() * (1 - cos(angle))
    val sinAngle = sqrt(max(0f, 1 - cosAngle * cosAngle))
    val phi = random.nextFloat() * 2 * PI.toFloat()
    val d = normalize(direction)
    val helper = if (abs(d[1]) < 0.9f) floatArrayOf(0f, 1f, 0f) else floatArrayOf(1f, 0f, 0f)
    val u = normalize(Shapes.cross(helper, d))
    val v = Shapes.cross(d, u)
    return FloatArray(3) { d[it] * cosAngle + (u[it] * cos(phi) + v[it] * sin(phi)) * sinAngle }
  }

  private fun normalize(v: FloatArray): FloatArray {
    val l = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).takeIf { it > 0 } ?: 1f
    return floatArrayOf(v[0] / l, v[1] / l, v[2] / l)
  }

  fun destroy() {
    part.destroy(scene)
    for (glow in glows) glow.part.destroy(scene)
  }
}
