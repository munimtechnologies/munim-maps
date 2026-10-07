package com.munimmaps.engines.google

import android.content.res.Configuration
import android.graphics.Point
import android.graphics.PointF
import android.view.View
import com.google.android.gms.maps.GoogleMap
import com.google.android.gms.maps.MapView
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.MapColorScheme
import com.munimmaps.engine.MapCameraSource
import com.munimmaps.engine.MapCameraState
import com.munimmaps.engine.MapViewAdapter
import kotlin.math.PI
import kotlin.math.abs
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
  // Starts at the 30° measured on Android (Maps SDK 19 and 20, Galaxy A14).
  @Volatile var fieldOfView: Double = PI / 6
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
   * Null padding (a map someone else owns, whose padding Google does not
   * report) asks Google's projection where it draws the target.
   */
  fun state(map: GoogleMap, view: View, padding: IntArray?, density: Double, dark: Boolean): MapCameraState? {
    val width = view.width.toDouble()
    val height = view.height.toDouble()
    if (width < 1 || height < 1) return null
    val position = map.cameraPosition
    val target = position.target
    val projection = map.projection
    val drawn = if (padding == null) projection.toScreenLocation(target) else null
    val cx = if (drawn != null) drawn.x.toDouble() else padding!![0] + (width - padding[0] - padding[2]) / 2
    val cy = if (drawn != null) drawn.y.toDouble() else padding!![1] + (height - padding[1] - padding[3]) / 2
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

    val padded = abs(cx - width / 2) > 1.5 || abs(cy - height / 2) > 1.5
    if (padded) {
      return paddedState(projection, target.latitude, target.longitude, cx, cy, k, pitch, heading, width, height, density, dark)
    }

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

  /**
   * With map padding the target is drawn off the view's middle. Google can
   * either keep the camera pointing at the view's middle (the target seen
   * off-axis) or move its centre of perspective to the target; both are
   * built from the field of view measured without padding and the ground
   * scale through the target ([k], pixels per metre: the focal length over
   * the target's depth), and the one that draws a ground point low on the
   * screen where Google does wins. The foreshortening measurement is skipped
   * here: it assumes the target is straight ahead.
   */
  private fun paddedState(
    projection: com.google.android.gms.maps.Projection,
    latitude: Double,
    longitude: Double,
    cx: Double,
    cy: Double,
    k: Double,
    pitch: Double,
    heading: Double,
    width: Double,
    height: Double,
    density: Double,
    dark: Boolean,
  ): MapCameraState? {
    val f = focalLength(height)
    // The target's depth along the optical axis, then the camera-to-target vector in the scene.
    val depth = f / k
    val local = doubleArrayOf((cx - width / 2) / f * depth, -(cy - height / 2) / f * depth, -depth)
    val world = MapCameraState.mul(MapCameraState.rotation(heading, pitch), local)
    val offAxis = MapCameraState(
      latitude = latitude, longitude = longitude,
      distance = MapCameraState.norm(world), altitude = -world[1],
      pitch = pitch, heading = heading, width = width, height = height, focalLength = f,
      centerX = cx, centerY = cy, darkAppearance = dark, pixelRatio = density,
    )
    val shifted = offAxis.copy(
      distance = depth, altitude = depth * cos(pitch * PI / 180), principalX = cx, principalY = cy)
    val candidates = listOf(offAxis, shifted).filter { it.distance.isFinite() && it.distance > 0 && it.altitude > 0 }
    val probe = Point((width / 2).roundToInt(), (height * 0.8).roundToInt())
    val ground = projection.fromScreenLocation(probe)
    return candidates.minByOrNull { state ->
      val p = state.project(state.scenePosition(ground.latitude, ground.longitude, 0.0))
      if (p == null) Double.MAX_VALUE else hypot(p[0] - probe.x, p[1] - probe.y)
    }
  }
}

/**
 * Lets `MapModelLayer` draw over another library's Google `MapView`
 * (react-native-maps on Android, with or without `provider="google"`).
 * Compiled whenever the Maps SDK is in the app: with munim-maps' own Google
 * engine (`munimMaps.google=true`) or with react-native-maps (found by its
 * Gradle project), against the SDK the app already has.
 *
 * It never sets listeners on the `GoogleMap` (react-native-maps owns its
 * single camera listeners); the 3D layer reads the camera every frame.
 */
object GoogleMapViewAdapter : MapViewAdapter {
  override fun cameraSource(view: View): MapCameraSource? =
    if (view is MapView) GoogleViewCameraSource(view) else null
}

/** A camera source for a Google `MapView` this library does not own. */
class GoogleViewCameraSource(private val mapView: MapView) : MapCameraSource {
  private var map: GoogleMap? = null
  private val density = mapView.resources.displayMetrics.density.toDouble()

  init {
    mapView.getMapAsync { map = it }
  }

  override val cameraView: View? get() = if (mapView.isAttachedToWindow) mapView else null

  override fun cameraState(previous: MapCameraState?): MapCameraState? {
    val map = map ?: return null
    return GoogleCamera.state(map, mapView, null, density, isDark(map))
  }

  /** Google draws dark when the system is dark and the map follows it (Maps SDK 19+). */
  private fun isDark(map: GoogleMap): Boolean {
    val night = mapView.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
    return try {
      when (map.mapColorScheme) {
        MapColorScheme.DARK -> true
        MapColorScheme.LIGHT -> false
        else -> night == Configuration.UI_MODE_NIGHT_YES
      }
    } catch (_: Throwable) {
      false
    }
  }

  override fun screenPoint(latitude: Double, longitude: Double): PointF? {
    val p = map?.projection?.toScreenLocation(LatLng(latitude, longitude)) ?: return null
    return PointF(p.x.toFloat(), p.y.toFloat())
  }
}
