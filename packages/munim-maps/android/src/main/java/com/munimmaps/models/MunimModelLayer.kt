package com.munimmaps.models

import android.content.Context
import android.view.TextureView
import android.view.View
import com.margelo.nitro.munimmaps.MapAlignmentReport
import com.margelo.nitro.munimmaps.MapModelLighting
import com.margelo.nitro.munimmaps.NativeMapModel
import com.margelo.nitro.munimmaps.NativeMapPath
import com.margelo.nitro.munimmaps.NativeMapZone
import com.munimmaps.engine.MapCameraSource

/**
 * munim-maps' 3D layer on Android: draws GLB / glTF models over any engine's
 * map with Filament, from the engine's [MapCameraSource]. The Android twin
 * of iOS's `MunimModelLayer`.
 *
 * Add [view] over the map view (it never takes touches) and [attach] it to
 * the engine's camera source. For taps, the engine asks [modelHit] before
 * treating a tap as a map press.
 *
 * Phase 1 draws GLB / glTF models (position, altitude, heading, scale,
 * screen size, tint, spin, motion keyframes, visibility). Shapes, pictures,
 * labels, stems, effects, zones, paths, terrain and building occlusion are
 * accepted and reported as not drawn yet.
 */
class MunimModelLayer(context: Context) {
  private val textureView = TextureView(context).apply {
    isOpaque = false
    isClickable = false
    isFocusable = false
    importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
  }
  private val renderer = ModelRenderer(context, textureView) { message -> onError?.invoke(message) }

  /** The view to place over the map. */
  val view: View get() = textureView

  var onModelPress: ((String) -> Unit)? = null
  var onError: ((String) -> Unit)? = null

  var models: Array<NativeMapModel> = emptyArray()
    set(value) {
      field = value
      renderer.setModels(value)
    }

  var zones: Array<NativeMapZone> = emptyArray()
    set(value) {
      field = value
      if (value.isNotEmpty()) renderer.reportOnce("zones are not drawn on Android yet")
    }

  var paths: Array<NativeMapPath> = emptyArray()
    set(value) {
      field = value
      if (value.isNotEmpty()) renderer.reportOnce("paths are not drawn on Android yet")
    }

  var lighting: MapModelLighting = MapModelLighting.AUTO
    set(value) {
      field = value
      renderer.lighting = value
    }

  /** Hide every model while the camera is farther than this, in metres. */
  var maxCameraDistance: Double = 50_000.0
    set(value) {
      field = value
      renderer.maxCameraDistance = value
    }

  var buildingOcclusion = false
    set(value) {
      field = value
      if (value) renderer.reportOnce("occlusion=\"buildings\" is not supported on Android yet")
    }
  var buildingTilesUrl = ""
  var followsTerrain = false

  val isAttached: Boolean get() = renderer.source?.cameraView != null

  fun attach(source: MapCameraSource) = renderer.attach(source)

  fun detach() = renderer.detach()

  /** Draw on the next frame (camera moved, size changed). */
  fun setNeedsRender() = renderer.setNeedsRender()

  /** Id of the nearest model drawn under a point, in pixels in the map view. */
  fun modelHit(x: Float, y: Float): String? = renderer.modelHit(x.toDouble(), y.toDouble())

  /** Handles a tap: true (and `onModelPress`) when it hit a model. */
  fun handleTap(x: Float, y: Float): Boolean {
    val id = modelHit(x, y) ?: return false
    onModelPress?.invoke(id)
    return true
  }

  fun measureAlignment(): MapAlignmentReport = renderer.measureAlignment()

  /** Frees Filament's resources. The layer is not used again. */
  fun destroy() = renderer.destroy()
}
