package com.munimmaps.engines.mapbox

import android.graphics.PointF
import android.view.View
import com.mapbox.geojson.Point
import com.mapbox.maps.MapView
import com.mapbox.maps.MapboxMap
import com.mapbox.maps.StylePropertyValueKind
import com.mapbox.maps.plugin.gestures.OnMapClickListener
import com.mapbox.maps.plugin.gestures.gestures
import com.munimmaps.engine.MapCameraSource
import com.munimmaps.engine.MapCameraState
import com.munimmaps.engine.MapViewAdapter
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.tan

/**
 * Lets `MapModelLayer` draw over another library's Mapbox `MapView`
 * (`@rnmapbox/maps`). Compiled whenever the Mapbox Maps SDK is in the app:
 * with munim-maps' own Mapbox engine (`munimMaps.mapbox=true`) or with
 * `@rnmapbox/maps` (found by its Gradle project), against the SDK the app
 * already has, so it adds nothing to the APK.
 *
 * The camera is Mapbox's own: a pinhole with a vertical field of view of
 * 2 atan(1/3) (36.87°, or the camera's `verticalFov`), 512-point tiles, the
 * centre drawn at the middle of the padded viewport. That is exactly the
 * camera munim-maps' Mapbox engine uses, so models line up to a fraction of
 * a pixel with Mapbox's own `pixelForCoordinate`.
 */
object MapboxMapViewAdapter : MapViewAdapter {
  override fun cameraSource(view: View): MapCameraSource? =
    if (view is MapView) MapboxViewCameraSource(view) else null
}

/** A camera source for a Mapbox `MapView` this library does not own. */
class MapboxViewCameraSource(private val mapView: MapView) : MapCameraSource {
  private val map: MapboxMap = mapView.mapboxMap
  private val density = mapView.resources.displayMetrics.density.toDouble()

  override val cameraView: View? get() = if (mapView.isAttachedToWindow) mapView else null

  override fun cameraState(previous: MapCameraState?): MapCameraState? {
    val width = mapView.width.toDouble()
    val height = mapView.height.toDouble()
    if (width < 1 || height < 1) return null
    val cs = try {
      if (!map.isStyleLoaded()) return null
      map.cameraState
    } catch (_: Exception) {
      // The map is being destroyed.
      return null
    }
    val center = cs.center
    val fov = fieldOfView(cs)
    // Metres from the camera to the centre: half the height in points over
    // tan(fov / 2), times metres per point at this zoom (512-point tiles).
    val metersPerPoint = cos(center.latitude() * PI / 180) * 2 * PI * MapCameraState.MERCATOR_RADIUS /
      (TILE_SIZE * 2.0.pow(cs.zoom))
    val distance = height / density / 2 / tan(fov / 2) * metersPerPoint
    if (!distance.isFinite() || distance <= 0) return null
    val padding = cs.padding
    val centerX = padding.left + (width - padding.left - padding.right) / 2
    val centerY = padding.top + (height - padding.top - padding.bottom) / 2
    return MapCameraState(
      latitude = center.latitude(),
      longitude = center.longitude(),
      distance = distance,
      altitude = distance * cos(cs.pitch * PI / 180),
      pitch = cs.pitch,
      heading = cs.bearing,
      width = width,
      height = height,
      focalLength = MapCameraState.focalLength(height, fov),
      centerX = centerX,
      centerY = centerY,
      // Mapbox moves its centre of perspective to the padded centre.
      principalX = centerX,
      principalY = centerY,
      globe = cs.zoom < GLOBE_ZOOM && styleString { map.getStyleProjectionProperty("name") } == "globe",
      drawsTerrain = hasTerrain(),
      darkAppearance = isDark(),
      pixelRatio = density,
    )
  }

  override fun screenPoint(latitude: Double, longitude: Double): PointF? {
    val p = try {
      map.pixelForCoordinate(Point.fromLngLat(longitude, latitude))
    } catch (_: Exception) {
      return null
    }
    if (p.x < 0 && p.y < 0) return null
    return PointF(p.x.toFloat(), p.y.toFloat())
  }

  private var clickListener: OnMapClickListener? = null

  /**
   * Taps through Mapbox's gestures plugin, which takes any number of click
   * listeners: `@rnmapbox/maps` keeps its own (and its `onPress`), and a tap
   * on a model is not passed on to listeners added after this one.
   */
  override fun setTapListener(listener: ((x: Float, y: Float) -> Boolean)?) {
    try {
      clickListener?.let { mapView.gestures.removeOnMapClickListener(it) }
      clickListener = null
      if (listener == null) return
      val click = OnMapClickListener { point ->
        val p = map.pixelForCoordinate(point)
        listener(p.x.toFloat(), p.y.toFloat())
      }
      mapView.gestures.addOnMapClickListener(click)
      clickListener = click
    } catch (_: Throwable) {
      // No gestures plugin in this map.
    }
  }

  /**
   * Mapbox's vertical field of view. `CameraState.verticalFov` is only in
   * newer SDKs than some `@rnmapbox/maps` versions build with (this file
   * compiles against theirs), so it is read by reflection.
   */
  private fun fieldOfView(cs: com.mapbox.maps.CameraState): Double {
    val degrees = (verticalFov?.invoke(cs) as? Double) ?: 0.0
    return if (degrees > 1 && degrees < 179) degrees * PI / 180 else DEFAULT_FOV
  }

  private fun hasTerrain(): Boolean = try {
    map.getStyleTerrainProperty("source").kind != StylePropertyValueKind.UNDEFINED
  } catch (_: Throwable) {
    false
  }

  /** Mapbox Standard's `lightPreset` at night or dusk. */
  private fun isDark(): Boolean {
    val preset = try {
      map.getStyleImportConfigProperty("basemap", "lightPreset").value?.value?.contents as? String
    } catch (_: Throwable) {
      null
    }
    return preset == "night" || preset == "dusk"
  }

  private inline fun styleString(read: () -> com.mapbox.maps.StylePropertyValue): String? = try {
    read().value.contents as? String
  } catch (_: Throwable) {
    null
  }

  private companion object {
    /** Mapbox's vertical field of view: 2 atan(1/3), about 36.87°. */
    const val DEFAULT_FOV = 0.6435011087932844
    const val TILE_SIZE = 512.0

    /** Below this zoom Mapbox's globe projection draws a sphere. */
    const val GLOBE_ZOOM = 5.5

    val verticalFov: java.lang.reflect.Method? = try {
      com.mapbox.maps.CameraState::class.java.getMethod("getVerticalFov")
    } catch (_: NoSuchMethodException) {
      null
    }
  }
}
