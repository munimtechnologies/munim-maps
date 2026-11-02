package com.munimmaps.engine

import android.os.SystemClock
import android.view.Choreographer
import com.margelo.nitro.munimmaps.MapCoordinate
import com.margelo.nitro.munimmaps.NativeCircle
import com.margelo.nitro.munimmaps.NativePolygon

/**
 * Glides circles and polygons to new geometry (`animationDuration`): keeps
 * what is drawn now, and while a transition runs hands the engine the
 * shapes in between, once a frame, from a [Choreographer] callback that only
 * runs then. Main thread only.
 *
 * Style changes (colours, widths) apply at once; only the geometry moves. A
 * polygon glides only when its new rings have the same vertex counts;
 * otherwise it jumps.
 */
class MunimShapeTransitions(
  private val drawCircles: (Array<NativeCircle>) -> Unit,
  private val drawPolygons: (Array<NativePolygon>) -> Unit,
) {
  private class Run<T>(val from: T, var to: T, val start: Long, val duration: Long)

  private var circleTargets: Array<NativeCircle> = emptyArray()
  private var polygonTargets: Array<NativePolygon> = emptyArray()
  /** The props' geometry, by id (what is drawn when nothing glides). */
  private var drawnCircles = HashMap<String, NativeCircle>()
  private var drawnPolygons = HashMap<String, NativePolygon>()
  private var circleRuns = HashMap<String, Run<NativeCircle>>()
  private var polygonRuns = HashMap<String, Run<NativePolygon>>()
  private var scheduled = false
  private val frameCallback = Choreographer.FrameCallback { tick() }

  val isAnimating get() = circleRuns.isNotEmpty() || polygonRuns.isNotEmpty()

  /** New circles. [passThrough] (an engine that animates by itself) sends them unchanged. */
  fun setCircles(circles: Array<NativeCircle>, passThrough: Boolean = false) {
    val now = now()
    val runs = HashMap<String, Run<NativeCircle>>()
    val drawn = HashMap<String, NativeCircle>()
    for (target in circles) {
      if (drawn.containsKey(target.id)) continue
      drawn[target.id] = target
      if (passThrough || target.animationDuration <= 0) continue
      val current = currentCircle(target.id, now) ?: continue
      val running = circleRuns[target.id]
      if (running != null && sameGeometry(running.to, target)) {
        // Already gliding there (the same props again): carry on; frames
        // take their style from `to`.
        running.to = target
        runs[target.id] = running
        continue
      }
      val from = target.copy(latitude = current.latitude, longitude = current.longitude, radius = current.radius)
      if (sameGeometry(from, target)) continue
      runs[target.id] = Run(from, target, now, (target.animationDuration * 1_000_000).toLong())
    }
    circleTargets = circles
    drawnCircles = drawn
    circleRuns = runs
    drawCircles(frameCircles(now))
    schedule()
  }

  /** New polygons; see [setCircles]. */
  fun setPolygons(polygons: Array<NativePolygon>, passThrough: Boolean = false) {
    val now = now()
    val runs = HashMap<String, Run<NativePolygon>>()
    val drawn = HashMap<String, NativePolygon>()
    for (target in polygons) {
      if (drawn.containsKey(target.id)) continue
      drawn[target.id] = target
      if (passThrough || target.animationDuration <= 0) continue
      val current = currentPolygon(target.id, now) ?: continue
      if (!sameShape(current, target)) continue
      val running = polygonRuns[target.id]
      if (running != null && sameGeometry(running.to, target)) {
        running.to = target
        runs[target.id] = running
        continue
      }
      val from = target.copy(coordinates = current.coordinates, holes = current.holes)
      if (sameGeometry(from, target)) continue
      runs[target.id] = Run(from, target, now, (target.animationDuration * 1_000_000).toLong())
    }
    polygonTargets = polygons
    drawnPolygons = drawn
    polygonRuns = runs
    drawPolygons(framePolygons(now))
    schedule()
  }

  /** Stops every transition (the shapes jump to their targets). */
  fun finish() {
    val circles = circleRuns.isNotEmpty()
    val polygons = polygonRuns.isNotEmpty()
    circleRuns = HashMap()
    polygonRuns = HashMap()
    stop()
    if (circles) drawCircles(circleTargets)
    if (polygons) drawPolygons(polygonTargets)
  }

  // Frames

  private fun now() = SystemClock.uptimeMillis() * 1_000_000

  private fun currentCircle(id: String, time: Long): NativeCircle? =
    circleRuns[id]?.let { circle(it, time) } ?: drawnCircles[id]

  private fun currentPolygon(id: String, time: Long): NativePolygon? =
    polygonRuns[id]?.let { polygon(it, time) } ?: drawnPolygons[id]

  private fun frameCircles(time: Long): Array<NativeCircle> =
    if (circleRuns.isEmpty()) circleTargets else Array(circleTargets.size) { i ->
      val c = circleTargets[i]
      circleRuns[c.id]?.let { circle(it, time) } ?: c
    }

  private fun framePolygons(time: Long): Array<NativePolygon> =
    if (polygonRuns.isEmpty()) polygonTargets else Array(polygonTargets.size) { i ->
      val p = polygonTargets[i]
      polygonRuns[p.id]?.let { polygon(it, time) } ?: p
    }

  private fun tick() {
    scheduled = false
    val now = now()
    val circles = if (circleRuns.isEmpty()) null else frameCircles(now)
    val polygons = if (polygonRuns.isEmpty()) null else framePolygons(now)
    circleRuns.entries.removeAll { now >= it.value.start + it.value.duration }
    polygonRuns.entries.removeAll { now >= it.value.start + it.value.duration }
    schedule()
    circles?.let(drawCircles)
    polygons?.let(drawPolygons)
  }

  private fun schedule() {
    if (isAnimating && !scheduled) {
      scheduled = true
      Choreographer.getInstance().postFrameCallback(frameCallback)
    } else if (!isAnimating) {
      stop()
    }
  }

  private fun stop() {
    if (scheduled) {
      Choreographer.getInstance().removeFrameCallback(frameCallback)
      scheduled = false
    }
  }

  companion object {
    private fun progress(run: Run<*>, time: Long): Double =
      if (run.duration <= 0) 1.0 else ((time - run.start).toDouble() / run.duration).coerceIn(0.0, 1.0)

    fun lerp(a: Double, b: Double, t: Double) = a + (b - a) * t

    /** Longitude the short way round the antimeridian. */
    fun lerpLongitude(a: Double, b: Double, t: Double): Double {
      var delta = (b - a) % 360
      if (delta > 180) delta -= 360 else if (delta < -180) delta += 360
      var value = a + delta * t
      if (value > 180) value -= 360 else if (value < -180) value += 360
      return value
    }

    private fun lerp(a: MapCoordinate, b: MapCoordinate, t: Double) =
      MapCoordinate(lerp(a.latitude, b.latitude, t), lerpLongitude(a.longitude, b.longitude, t))

    private fun circle(run: Run<NativeCircle>, time: Long): NativeCircle {
      val t = progress(run, time)
      if (t >= 1) return run.to
      return run.to.copy(
        latitude = lerp(run.from.latitude, run.to.latitude, t),
        longitude = lerpLongitude(run.from.longitude, run.to.longitude, t),
        radius = lerp(run.from.radius, run.to.radius, t),
      )
    }

    private fun polygon(run: Run<NativePolygon>, time: Long): NativePolygon {
      val t = progress(run, time)
      if (t >= 1) return run.to
      val from = run.from
      val to = run.to
      return to.copy(
        coordinates = Array(to.coordinates.size) { i -> lerp(from.coordinates[i], to.coordinates[i], t) },
        holes = Array(to.holes.size) { h -> Array(to.holes[h].size) { i -> lerp(from.holes[h][i], to.holes[h][i], t) } },
      )
    }

    /** Same number of rings and vertices, so vertices can move pairwise. */
    fun sameShape(a: NativePolygon, b: NativePolygon) =
      a.coordinates.size == b.coordinates.size && a.holes.size == b.holes.size &&
        a.holes.indices.all { a.holes[it].size == b.holes[it].size }

    fun sameGeometry(a: NativeCircle, b: NativeCircle) =
      a.latitude == b.latitude && a.longitude == b.longitude && a.radius == b.radius

    fun sameGeometry(a: NativePolygon, b: NativePolygon) =
      a.coordinates.contentEquals(b.coordinates) && a.holes.size == b.holes.size &&
        a.holes.indices.all { a.holes[it].contentEquals(b.holes[it]) }
  }
}
