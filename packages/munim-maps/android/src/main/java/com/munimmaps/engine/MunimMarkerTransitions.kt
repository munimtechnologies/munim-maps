package com.munimmaps.engine

import android.graphics.Bitmap
import android.os.SystemClock
import android.view.Choreographer
import com.margelo.nitro.munimmaps.MapCoordinate
import com.margelo.nitro.munimmaps.NativeMarker

/**
 * Glides markers to new coordinates (`animationDuration`), like
 * react-native-maps' `animateMarkerToCoordinate`: keeps where each marker is
 * drawn now, and while a glide runs moves the gliding markers once a frame,
 * from a [Choreographer] callback that only runs then. Main thread only.
 *
 * It handles the `markers` list and `MarkerView`s (view markers, one at a
 * time with their picture). Everything but the position applies at once. A
 * new coordinate while a marker glides starts from where it is drawn; the
 * same coordinate again carries on.
 *
 * Each frame the gliding markers' positions go to [move], which an engine
 * that moves markers in place (Google Maps) answers with `true`; otherwise
 * the whole list goes to [draw] (and each gliding view marker to
 * [drawViewMarker]). When the glides end, [draw] gets the props as given.
 */
class MunimMarkerTransitions(
  private val draw: (Array<NativeMarker>) -> Unit,
  private val drawViewMarker: (NativeMarker, Bitmap?) -> Unit,
  private val move: (Map<String, MapCoordinate>) -> Boolean,
) {
  private class Run(val from: MapCoordinate, val to: MapCoordinate, val start: Long, val duration: Long)
  private class ViewTarget(val marker: NativeMarker, var image: Bitmap?)

  private var targets: Array<NativeMarker> = emptyArray()
  /** The props' positions, by id (what is drawn when nothing glides). */
  private var drawn = HashMap<String, MapCoordinate>()
  private var runs = HashMap<String, Run>()
  private val viewTargets = HashMap<String, ViewTarget>()
  private val viewRuns = HashMap<String, Run>()
  private var scheduled = false
  private val frameCallback = Choreographer.FrameCallback { tick() }

  val isAnimating get() = runs.isNotEmpty() || viewRuns.isNotEmpty()

  /** New markers. [passThrough] (an engine that glides markers itself) sends them unchanged. */
  fun setMarkers(markers: Array<NativeMarker>, passThrough: Boolean = false) {
    val now = now()
    val next = HashMap<String, Run>()
    val positions = HashMap<String, MapCoordinate>()
    for (target in markers) {
      if (positions.containsKey(target.id)) continue
      val to = MapCoordinate(target.latitude, target.longitude)
      positions[target.id] = to
      if (passThrough || target.animationDuration <= 0) continue
      val current = position(target.id, now) ?: continue
      val running = runs[target.id]
      if (running != null && same(running.to, to)) {
        // Already gliding there (the same props again): carry on.
        next[target.id] = running
        continue
      }
      if (same(current, to)) continue
      next[target.id] = Run(current, to, now, (target.animationDuration * 1_000_000).toLong())
    }
    targets = markers
    drawn = positions
    runs = next
    draw(frame(now))
    schedule()
  }

  /** A `MarkerView`'s marker and picture; see [setMarkers]. */
  fun setViewMarker(marker: NativeMarker, image: Bitmap?, passThrough: Boolean = false) {
    val now = now()
    val to = MapCoordinate(marker.latitude, marker.longitude)
    val current = viewRuns[marker.id]?.let { position(it, now) }
      ?: viewTargets[marker.id]?.marker?.let { MapCoordinate(it.latitude, it.longitude) }
    viewTargets[marker.id] = ViewTarget(marker, image)
    val running = viewRuns[marker.id]
    when {
      passThrough || marker.animationDuration <= 0 || current == null -> viewRuns.remove(marker.id)
      running != null && same(running.to, to) -> {}
      !same(current, to) -> viewRuns[marker.id] = Run(current, to, now, (marker.animationDuration * 1_000_000).toLong())
      else -> viewRuns.remove(marker.id)
    }
    drawViewMarker(viewFrame(marker.id, now) ?: marker, image)
    schedule()
  }

  /** A new picture for a view marker. */
  fun setViewMarkerImage(image: Bitmap?, id: String) {
    viewTargets[id]?.image = image
  }

  fun removeViewMarker(id: String) {
    viewTargets.remove(id)
    viewRuns.remove(id)
    schedule()
  }

  /** Stops every glide (the markers jump to their targets). */
  fun finish() {
    val hadRuns = runs.isNotEmpty()
    val views = viewRuns.keys.toList()
    runs = HashMap()
    viewRuns.clear()
    stop()
    if (hadRuns) draw(targets)
    for (id in views) viewTargets[id]?.let { drawViewMarker(it.marker, it.image) }
  }

  /** Forgets the list and every glide (a new engine starts empty); view markers are kept for [resendViewMarkers]. */
  fun reset() {
    targets = emptyArray()
    drawn = HashMap()
    runs = HashMap()
    viewRuns.clear()
    stop()
  }

  /** Sends every view marker again, to a new engine. */
  fun resendViewMarkers() {
    for (entry in viewTargets.values.toList()) drawViewMarker(entry.marker, entry.image)
  }

  /** Forgets everything, view markers included (the map is going away). */
  fun clear() {
    reset()
    viewTargets.clear()
  }

  // Frames

  private fun now() = SystemClock.uptimeMillis() * 1_000_000

  private fun position(id: String, time: Long): MapCoordinate? = runs[id]?.let { position(it, time) } ?: drawn[id]

  private fun frame(time: Long): Array<NativeMarker> =
    if (runs.isEmpty()) targets else Array(targets.size) { i ->
      val m = targets[i]
      val run = runs[m.id]
      if (run == null) m else position(run, time).let { m.copy(latitude = it.latitude, longitude = it.longitude) }
    }

  private fun viewFrame(id: String, time: Long): NativeMarker? {
    val run = viewRuns[id] ?: return null
    val marker = viewTargets[id]?.marker ?: return null
    val p = position(run, time)
    return marker.copy(latitude = p.latitude, longitude = p.longitude)
  }

  private fun tick() {
    scheduled = false
    val now = now()
    val positions = HashMap<String, MapCoordinate>()
    for ((id, run) in runs) positions[id] = position(run, now)
    for ((id, run) in viewRuns) positions[id] = position(run, now)
    val movedInPlace = move(positions)
    val gliding = runs.isNotEmpty()
    val glidingViews = viewRuns.keys.toList()
    val ended = runs.filterValues { now >= it.start + it.duration }.keys
    val endedViews = viewRuns.filterValues { now >= it.start + it.duration }.keys
    for (id in ended) runs.remove(id)
    for (id in endedViews) viewRuns.remove(id)
    // Engines that cannot move markers in place get the list every frame;
    // the others get it once a glide ends, so they end on the props as given.
    if (gliding && (!movedInPlace || ended.isNotEmpty())) draw(frame(now))
    for (id in glidingViews) {
      if (movedInPlace && id !in endedViews) continue
      val target = viewTargets[id] ?: continue
      drawViewMarker(viewFrame(id, now) ?: target.marker, target.image)
    }
    schedule()
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

  private companion object {
    fun progress(run: Run, time: Long): Double =
      if (run.duration <= 0) 1.0 else ((time - run.start).toDouble() / run.duration).coerceIn(0.0, 1.0)

    fun position(run: Run, time: Long): MapCoordinate {
      val t = progress(run, time)
      if (t >= 1) return run.to
      return MapCoordinate(
        MunimShapeTransitions.lerp(run.from.latitude, run.to.latitude, t),
        MunimShapeTransitions.lerpLongitude(run.from.longitude, run.to.longitude, t),
      )
    }

    fun same(a: MapCoordinate, b: MapCoordinate) = a.latitude == b.latitude && a.longitude == b.longitude
  }
}
