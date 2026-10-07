package com.munimmaps.models

import android.content.Context
import android.view.TextureView
import android.view.View
import com.margelo.nitro.munimmaps.CameraKeyframe
import com.margelo.nitro.munimmaps.MapAlignmentReport
import com.margelo.nitro.munimmaps.MapCamera
import com.margelo.nitro.munimmaps.MapModelLighting
import com.margelo.nitro.munimmaps.NativeMapModel
import com.margelo.nitro.munimmaps.NativeMapPath
import com.margelo.nitro.munimmaps.NativeMapZone
import com.munimmaps.engine.MapCameraSource

/**
 * munim-maps' 3D layer on Android: draws models, pictures, labels, zones,
 * paths and effects over any engine's map with Filament, from the engine's
 * [MapCameraSource]. The Android twin of iOS's `MunimModelLayer`.
 *
 * Add [view] over the map view (it never takes touches) and [attach] it to
 * the engine's camera source. For taps, the engine asks [modelHit] before
 * treating a tap as a map press. Engines get `flyCamera` from [flyCamera]:
 * the flight is stepped on the layer's frame clock, before the camera is
 * read, so the map and the models move together.
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
      renderer.setZones(value)
    }

  /** Lines drawn in 3D: above the ground and on the globe. */
  var paths: Array<NativeMapPath> = emptyArray()
    set(value) {
      field = value
      renderer.setPaths(value)
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

  /**
   * Hides models behind buildings, which map engines cannot do because they
   * do not share their depth buffer. Footprints and heights come from vector
   * tiles around the camera (OpenStreetMap data from OpenFreeMap by default).
   * Avatars, labels and stems always stay visible.
   */
  var buildingOcclusion = false
    set(value) {
      field = value
      renderer.buildings.enabled = value
      renderer.setNeedsRender()
    }

  /** `{z}/{x}/{y}` URL of vector tiles with an OpenMapTiles `building` layer; empty uses OpenFreeMap. */
  var buildingTilesUrl = ""
    set(value) {
      field = value
      renderer.buildings.tileUrlTemplate = value
    }

  /**
   * Keeps models, paths and zones above the ground on the engine's 3D
   * terrain (when it draws some: `MapCameraState.drawsTerrain`), with ground
   * heights from [MunimTerrain]. Models above sea level always follow it.
   */
  var followsTerrain = false
    set(value) {
      field = value
      renderer.followsTerrain = value
    }

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

  /**
   * Flies the camera through keyframes, `t` seconds after `start` (seconds
   * since 1970, the clock of models' `motion`), stepping it every frame with
   * [apply] (the engine's `setCamera(camera, false)`). Any other camera call
   * should stop it ([stopFlight]).
   */
  fun flyCamera(keyframes: Array<CameraKeyframe>, start: Double, loop: Boolean, apply: (MapCamera) -> Unit) =
    renderer.flyCamera(keyframes, start, loop, apply)

  fun stopFlight() = renderer.stopFlight()

  val isFlying: Boolean get() = renderer.isFlying

  /** Frees Filament's resources. The layer is not used again. */
  fun destroy() = renderer.destroy()
}
