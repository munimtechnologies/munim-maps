package com.munimmaps.engines.google

import android.content.Context
import android.view.View
import com.margelo.nitro.munimmaps.MapCamera
import com.margelo.nitro.munimmaps.NativeMapModel
import com.margelo.nitro.munimmaps.NativeMarker
import com.margelo.nitro.munimmaps.NativePolygon
import com.margelo.nitro.munimmaps.NativePolyline
import org.json.JSONObject

/**
 * Google's photorealistic 3D map (`google={{ mode: '3d' }}`): the Maps 3D
 * SDK for Android (`play-services-maps3d`), where munim-maps' models are
 * Google's own glTF models and polylines, polygons and markers are drawn
 * natively. It lives in its own source set (`src/google3d`), built with
 * `munimMaps.googleMaps3d=true`, and is found by name so the Google engine
 * works without it.
 */
interface Google3DMode {
  val view: View
  fun setOptions(options: GJson)
  fun setModels(models: Array<NativeMapModel>)
  fun setMarkers(markers: Array<NativeMarker>)
  fun setPolylines(polylines: Array<NativePolyline>)
  fun setPolygons(polygons: Array<NativePolygon>)
  fun setCamera(camera: MapCamera, durationMs: Double)
  fun getCamera(): MapCamera?
  /** Google 3D's own methods (`flyTo`, `flyAround`, `stopCameraAnimation`…); false when unknown. */
  fun command(name: String, args: GJson, completion: (Result<String>) -> Unit): Boolean
  fun resume()
  fun pause()
  fun destroy()
}

/** What the 3D mode reports back to the engine. */
interface Google3DHost {
  fun emit(name: String, data: JSONObject)
  fun error(message: String)
  fun ready()
  fun press(latitude: Double, longitude: Double, placeId: String?)
  fun cameraChanged(camera: MapCamera, idle: Boolean)
  fun modelPressed(id: String)
  fun markerPressed(id: String)
}

object Google3DModes {
  private const val CLASS = "com.munimmaps.engines.google3d.GoogleMap3DMode"

  /** Whether the 3D SDK is built in (`munimMaps.googleMaps3d=true`). */
  val isAvailable: Boolean by lazy { runCatching { Class.forName(CLASS) }.isSuccess }

  fun create(context: Context, host: Google3DHost, camera: MapCamera?): Google3DMode? = try {
    Class.forName(CLASS)
      .getConstructor(Context::class.java, Google3DHost::class.java, MapCamera::class.java)
      .newInstance(context, host, camera) as Google3DMode
  } catch (_: ReflectiveOperationException) {
    null
  }
}
