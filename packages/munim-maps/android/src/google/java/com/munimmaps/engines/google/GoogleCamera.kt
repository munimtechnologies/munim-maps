package com.munimmaps.engines.google

import android.graphics.Point
import android.graphics.PointF
import android.view.View
import com.google.android.gms.maps.GoogleMap
import com.google.android.gms.maps.MapView
import com.google.android.gms.maps.model.LatLng
import com.munimmaps.engine.MapCameraSource
import com.munimmaps.engine.MapCameraState
import com.munimmaps.engine.MapViewAdapter
import kotlin.math.PI
import kotlin.math.atan
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Google's camera for munim-maps' 3D layer. Google publishes a zoom level,
 * not a camera distance or field of view, so both are measured from its own
 * projection: the ground scale on the screen row through the camera target
 * gives pixels per metre at the target's depth and, while the map is
 * tilted, how a point further up the screen is foreshortened gives the
 * distance to the target. Their product is the focal length, kept (as a
 * field of view) for flat views. The Android twin of iOS's
 * `GoogleCameraSource`.
 */
object GoogleCamera {
  /** Google's vertical field of view in radians, measured once a map is tilted. */
  @Volatile var fieldOfView: Double = 2 * atan(0.5)
  @Volatile var fieldOfViewMeasured = false
  private const val R = MapCameraState.MERCATOR_RADIUS

  /** Ground pixels per metre at a zoom level (256-dp tiles). */
  fun pixelsPerMeter(zoom: Double, latitude: Double, density: Double): Double =
    256 * density * 2.0.pow(zoom) / (2 * PI * R * maxOf(0.01, cos(latitude * PI / 180)))

  fun focalLength(heightPx: Double): Double = MapCameraState.focalLength(maxOf(1.0, heightPx), fieldOfView)

  /** Metres from the camera to the target at a zoom level. */
  fun distance(zoom: Double, latitude: Double, heightPx: Double, density: Double): Double =
    focalLength(heightPx) / pixelsPerMeter(zoom, latitude, density)

  /** The zoom level that puts the camera `distance` metres from the target. */
  fun zoom(distance: Double, latitude: Double, heightPx: Double, density: Double): Double {
    val perMeter = focalLength(heightPx) / maxOf(1.0, distance)
    return ln(perMeter * 2 * PI * R * maxOf(0.01, cos(latitude * PI / 180)) / (256 * density)) / ln(2.0)
  }

  /**
   * The camera now, or null while the map cannot answer. [padding] is
   * left, top, right, bottom in pixels: Google centres the target there.
   */
  fun state(map: GoogleMap, view: View, padding: IntArray, density: Double, dark: Boolean): MapCameraState? {
    val width = view.width.toDouble()
    val height = view.height.toDouble()
    if (width < 1 || height < 1) return null
    val position = map.cameraPosition
    val target = position.target
    val projection = map.projection
    val cx = padding[0] + (width - padding[0] - padding[2]) / 2
    val cy = padding[1] + (height - padding[1] - padding[3]) / 2
    val pitch = position.tilt.toDouble()
    val heading = position.bearing.toDouble()
    val metersPerMapPoint = MapCameraState.metersPerMapPoint(target.latitude)
    val (tx, ty) = MapCameraState.mapPoint(target.latitude, target.longitude)

    // Pixels per metre at the target's depth, along the row through it.
    val half = minOf(60 * density, width / 4).roundToInt()
    val row = cy.roundToInt()
    val left = projection.fromScreenLocation(Point(cx.roundToInt() - half, row))
    val right = projection.fromScreenLocation(Point(cx.roundToInt() + half, row))
    val (lx, ly) = MapCameraState.mapPoint(left.latitude, left.longitude)
    val (rx, ry) = MapCameraState.mapPoint(right.latitude, right.longitude)
    val meters = hypot(rx - lx, ry - ly) * metersPerMapPoint
    val k = if (meters.isFinite() && meters > 0) 2.0 * half / meters
    else pixelsPerMeter(position.zoom.toDouble(), target.latitude, density)

    var focal: Double? = null
    if (pitch >= 10) {
      val upY = (cy - minOf(cy * 0.6, height / 4)).roundToInt()
      val h = cy - upY
      if (h > 10) {
        val far = projection.fromScreenLocation(Point(cx.roundToInt(), upY))
        val (fx, fy) = MapCameraState.mapPoint(far.latitude, far.longitude)
        val east = (fx - tx) * metersPerMapPoint
        val north = -(fy - ty) * metersPerMapPoint
        val theta = heading * PI / 180
        val s = east * sin(theta) + north * cos(theta)
        val tilt = pitch * PI / 180
        val denominator = k * s * cos(tilt) - h
        if (s > 0 && denominator > 1e-9) {
          val d = h * s * sin(tilt) / denominator
          if (d.isFinite() && d > 0) focal = k * d
        }
      }
    }
    focal?.let {
      val fov = 2 * atan(height / 2 / it)
      if (fov.isFinite() && fov > 0.05 && fov < 2.5) {
        fieldOfView = if (fieldOfViewMeasured) fieldOfView * 0.8 + fov * 0.2 else fov
        fieldOfViewMeasured = true
      }
    }
    val f = focal ?: focalLength(height)
    val distance = f / k
    if (!distance.isFinite() || distance <= 0) return null
    return MapCameraState(
      latitude = target.latitude,
      longitude = target.longitude,
      distance = distance,
      altitude = distance * cos(pitch * PI / 180),
      pitch = pitch,
      heading = heading,
      width = width,
      height = height,
      focalLength = f,
      centerX = cx,
      centerY = cy,
      darkAppearance = dark,
      pixelRatio = density,
    )
  }
}

/**
 * Lets `MapModelLayer` draw over another library's Google `MapView`
 * (react-native-maps with `provider="google"`).
 */
object GoogleMapViewAdapter : MapViewAdapter {
  override fun cameraSource(view: View): MapCameraSource? =
    if (view is MapView) GoogleViewCameraSource(view) else null
}

/** A camera source for a Google `MapView` this engine does not own. */
class GoogleViewCameraSource(private val mapView: MapView) : MapCameraSource {
  private var map: GoogleMap? = null
  private val density = mapView.resources.displayMetrics.density.toDouble()

  init {
    mapView.getMapAsync { map = it }
  }

  override val cameraView: View? get() = if (mapView.isAttachedToWindow) mapView else null

  override fun cameraState(previous: MapCameraState?): MapCameraState? {
    val map = map ?: return null
    return GoogleCamera.state(map, mapView, IntArray(4), density, false)
  }

  override fun screenPoint(latitude: Double, longitude: Double): PointF? {
    val p = map?.projection?.toScreenLocation(LatLng(latitude, longitude)) ?: return null
    return PointF(p.x.toFloat(), p.y.toFloat())
  }
}
