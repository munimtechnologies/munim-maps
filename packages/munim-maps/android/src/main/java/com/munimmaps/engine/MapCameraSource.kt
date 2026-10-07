package com.munimmaps.engine

import android.graphics.PointF
import android.view.View

/**
 * Where munim-maps' 3D layer ([com.munimmaps.models.MunimModelLayer]) gets
 * its camera from: a map engine's view. The Android twin of iOS's
 * `MapCameraSource`. Every engine provides one for its map view and attaches
 * its model layer with `modelLayer.attach(source)`.
 *
 * The layer asks for the camera every frame (Choreographer) and redraws when
 * it changed; call [com.munimmaps.models.MunimModelLayer.setNeedsRender]
 * from the engine's camera-move listener to draw sooner.
 */
interface MapCameraSource {
  /** The map's view. The 3D layer lines up with it; null when it has gone away. */
  val cameraView: View?

  /** The camera now; null while the map cannot answer (no size, no style yet). */
  fun cameraState(previous: MapCameraState?): MapCameraState?

  /**
   * Where the engine itself draws a coordinate, in pixels in [cameraView], to
   * measure the 3D layer against the map (`measureAlignment`). Null if unknown.
   */
  fun screenPoint(latitude: Double, longitude: Double): PointF?
}
