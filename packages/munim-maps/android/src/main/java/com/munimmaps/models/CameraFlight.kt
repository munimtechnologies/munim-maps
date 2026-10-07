package com.munimmaps.models

import com.margelo.nitro.munimmaps.CameraKeyframe
import com.margelo.nitro.munimmaps.MapCamera
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.max

/**
 * `flyCamera` for every engine: the camera keyframes, interpolated on the
 * 3D layer's own frame clock (the same clock as models' `motion`), so a
 * camera following a moving model stays on it. The Android twin of the
 * MapKit engine's flight. The layer steps it at the start of each frame,
 * before it reads the engine's camera, so models and map move together.
 */
internal class CameraFlight(keyframes: Array<CameraKeyframe>, private val start: Double, private val loop: Boolean) {
  private val frames = keyframes.sortedBy { it.t }

  /** The camera at `now` (seconds since 1970), and whether the flight has ended. */
  fun step(now: Double): Pair<MapCamera, Boolean> {
    val first = frames.first()
    val last = frames.last()
    var t = now - start
    val span = last.t - first.t
    if (loop && span > 0) {
      t = first.t + (t - first.t) % span
      if (t < first.t) t += span
    }
    return when {
      t <= first.t -> first.camera to false
      t >= last.t -> last.camera to !loop
      else -> {
        var i = 1
        while (i < frames.size - 1 && frames[i].t < t) i++
        val a = frames[i - 1]
        val b = frames[i]
        interpolate(a.camera, b.camera, (t - a.t) / max(1e-9, b.t - a.t)) to false
      }
    }
  }

  companion object {
    fun interpolate(a: MapCamera, b: MapCamera, f: Double): MapCamera {
      val turn = (((b.heading - a.heading) % 360) + 540) % 360 - 180
      return MapCamera(
        latitude = a.latitude + (b.latitude - a.latitude) * f,
        longitude = a.longitude + (b.longitude - a.longitude) * f,
        // Zoom at a steady rate in scale, not in metres.
        distance = exp(ln(max(1.0, a.distance)) + (ln(max(1.0, b.distance)) - ln(max(1.0, a.distance))) * f),
        pitch = a.pitch + (b.pitch - a.pitch) * f,
        heading = ((a.heading + turn * f) % 360 + 360) % 360,
      )
    }
  }
}
