package com.munimmaps.engines.maplibre

import android.content.Context
import android.graphics.PointF
import android.view.View
import android.widget.FrameLayout
import com.margelo.nitro.munimmaps.EdgeInsets
import com.margelo.nitro.munimmaps.MapCamera
import com.margelo.nitro.munimmaps.MapCameraEasing
import com.margelo.nitro.munimmaps.MapCoordinate
import com.margelo.nitro.munimmaps.MapPoint
import com.margelo.nitro.munimmaps.MapPressEvent
import com.margelo.nitro.munimmaps.MapProvider
import com.margelo.nitro.munimmaps.MapRegion
import com.munimmaps.engine.MapCameraSource
import com.munimmaps.engine.MapCameraState
import com.munimmaps.engine.MunimMapEngine
import com.munimmaps.engine.MunimMapEngineFactory
import com.munimmaps.engine.MunimMapEngineListener
import com.munimmaps.engine.MunimMapsConfiguration
import com.munimmaps.models.MunimModelLayer
import org.json.JSONObject
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.geometry.LatLngBounds
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapLibreMapOptions
import org.maplibre.android.maps.MapView
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.tan

object MapLibreMapEngineFactory : MunimMapEngineFactory {
  override val isImplemented = true
  override fun create(context: Context): MunimMapEngine = MapLibreMapEngine(context)
}

/**
 * The MapLibre engine on Android: MapLibre Native's `MapView` with an
 * OpenFreeMap style by default (OpenStreetMap data, no key), and munim-maps'
 * Filament 3D layer over it.
 *
 * Phase 1 (the pipeline proof): style, camera (initial camera, set / animate
 * / get, regions, fit, point and coordinate conversion), gestures, taps and
 * camera events, and GLB models. Markers, shapes and the rest come with the
 * MapLibre provider work (see docs/providers.md).
 */
class MapLibreMapEngine(context: Context) : MunimMapEngine, MapCameraSource {
  override val provider = MapProvider.MAPLIBRE
  override var listener: MunimMapEngineListener? = null

  private val density = context.resources.displayMetrics.density.toDouble()
  private val mapView: MapView
  private val root: FrameLayout
  override val modelLayer = MunimModelLayer(context)
  override val view: View get() = root

  private var map: MapLibreMap? = null
  private var styleUrl = ""
  private var styleLoaded = false
  private var initialCamera: MapCamera? = null
  private var appliedInitialCamera = false
  private var destroyed = false
  private var started = false

  init {
    MapLibre.getInstance(context.applicationContext)
    mapView = MapView(context, MapLibreMapOptions.createFromAttributes(context).textureMode(false))
    root = object : FrameLayout(context) {
      override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        start()
      }

      override fun onDetachedFromWindow() {
        stop()
        super.onDetachedFromWindow()
      }
    }
    root.addView(mapView, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    root.addView(modelLayer.view, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    mapView.onCreate(null)
    mapView.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
      applyInitialCameraIfReady()
      modelLayer.setNeedsRender()
    }
    mapView.getMapAsync { map -> mapReady(map) }
    modelLayer.attach(this)
  }

  private fun start() {
    if (started || destroyed) return
    started = true
    mapView.onStart()
    mapView.onResume()
  }

  private fun stop() {
    if (!started || destroyed) return
    started = false
    mapView.onPause()
    mapView.onStop()
  }

  override fun destroy() {
    if (destroyed) return
    stop()
    destroyed = true
    modelLayer.destroy()
    mapView.onDestroy()
  }

  private fun mapReady(map: MapLibreMap) {
    if (destroyed) return
    this.map = map
    map.setMaxPitchPreference(85.0)
    map.uiSettings.isAttributionEnabled = true
    map.uiSettings.isLogoEnabled = false
    map.addOnCameraMoveListener {
      modelLayer.setNeedsRender()
      getCamera()?.let { listener?.onCameraMove(it) }
    }
    map.addOnCameraIdleListener {
      modelLayer.setNeedsRender()
      getCamera()?.let { listener?.onCameraChange(it) }
    }
    map.addOnMapClickListener { latLng ->
      val point = map.projection.toScreenLocation(latLng)
      if (modelLayer.handleTap(point.x, point.y)) return@addOnMapClickListener true
      listener?.onPress(MapPressEvent(latLng.latitude, latLng.longitude, point.x / density, point.y / density))
      false
    }
    map.addOnMapLongClickListener { latLng ->
      val point = map.projection.toScreenLocation(latLng)
      listener?.onLongPress(MapPressEvent(latLng.latitude, latLng.longitude, point.x / density, point.y / density))
      false
    }
    loadStyle()
    applyInitialCameraIfReady()
  }

  private fun loadStyle() {
    val map = map ?: return
    val url = styleUrl.ifEmpty { MunimMapsConfiguration.maplibreStyleUrl }
    styleLoaded = false
    map.setStyle(url) {
      styleLoaded = true
      modelLayer.setNeedsRender()
      listener?.onMapReady()
    }
  }

  // Props

  override fun setStyleUrl(url: String) {
    if (url == styleUrl) return
    styleUrl = url
    if (map != null) loadStyle()
  }

  override fun setProviderOptions(options: JSONObject) {}

  override fun setInitialCamera(camera: MapCamera) {
    initialCamera = camera
    applyInitialCameraIfReady()
  }

  private fun applyInitialCameraIfReady() {
    if (appliedInitialCamera) return
    val camera = initialCamera ?: return
    val map = map ?: return
    if (mapView.height <= 0) return
    appliedInitialCamera = true
    map.moveCamera(CameraUpdateFactory.newCameraPosition(position(camera)))
  }

  override fun setGestures(zoom: Boolean, scroll: Boolean, rotate: Boolean, pitch: Boolean) {
    val settings = map?.uiSettings ?: return
    settings.isZoomGesturesEnabled = zoom
    settings.isScrollGesturesEnabled = scroll
    settings.isRotateGesturesEnabled = rotate
    settings.isTiltGesturesEnabled = pitch
  }

  override fun setMapPadding(padding: EdgeInsets) {
    // The 3D layer assumes the centre coordinate is drawn at the view's
    // centre; padding comes with the MapLibre provider work.
  }

  // Camera: MapLibre zooms; munim-maps speaks metres from the camera.

  /** Vertical field of view in radians (MapLibre's default is 36.87°). */
  private fun fieldOfView(position: CameraPosition?): Double {
    val fov = position?.fov ?: 0.0
    return if (fov > 1 && fov < 180) fov * PI / 180 else DEFAULT_FOV
  }

  private fun heightPoints(): Double = maxOf(1.0, mapView.height / density)

  /** Metres from the camera to the centre at this zoom (512-point tiles). */
  private fun distance(zoom: Double, latitude: Double, fov: Double): Double {
    val metersPerPoint = cos(latitude * PI / 180) * 2 * PI * MapCameraState.MERCATOR_RADIUS / (TILE_SIZE * 2.0.pow(zoom))
    return heightPoints() / 2 / tan(fov / 2) * metersPerPoint
  }

  private fun zoom(distance: Double, latitude: Double, fov: Double): Double {
    val points = heightPoints() / 2 / tan(fov / 2)
    val worldMeters = cos(latitude * PI / 180) * 2 * PI * MapCameraState.MERCATOR_RADIUS
    return ln(points * worldMeters / (TILE_SIZE * maxOf(1.0, distance))) / ln(2.0)
  }

  private fun position(camera: MapCamera): CameraPosition {
    val fov = fieldOfView(map?.cameraPosition)
    return CameraPosition.Builder()
      .target(LatLng(camera.latitude, camera.longitude))
      .zoom(zoom(camera.distance, camera.latitude, fov))
      .tilt(camera.pitch)
      .bearing(camera.heading)
      .build()
  }

  override fun getCamera(): MapCamera? {
    val position = map?.cameraPosition ?: return null
    val target = position.target ?: return null
    return MapCamera(target.latitude, target.longitude,
      distance(position.zoom, target.latitude, fieldOfView(position)), position.tilt, position.bearing)
  }

  override fun setCamera(camera: MapCamera, animated: Boolean) {
    val map = map ?: return
    val update = CameraUpdateFactory.newCameraPosition(position(camera))
    if (animated) map.animateCamera(update) else map.moveCamera(update)
  }

  override fun animateCamera(camera: MapCamera, durationMs: Double, easing: MapCameraEasing) {
    val map = map ?: return
    val update = CameraUpdateFactory.newCameraPosition(position(camera))
    if (durationMs <= 0) map.moveCamera(update) else map.easeCamera(update, durationMs.toInt(), easing == MapCameraEasing.EASEINOUT)
  }

  override fun getVisibleRegion(): MapRegion? {
    val bounds = map?.projection?.visibleRegion?.latLngBounds ?: return null
    val center = bounds.center
    return MapRegion(center.latitude, center.longitude, bounds.latitudeSpan, bounds.longitudeSpan)
  }

  override fun setRegion(region: MapRegion, durationMs: Double) {
    val map = map ?: return
    val bounds = LatLngBounds.Builder()
      .include(LatLng(region.latitude - region.latitudeDelta / 2, region.longitude - region.longitudeDelta / 2))
      .include(LatLng(region.latitude + region.latitudeDelta / 2, region.longitude + region.longitudeDelta / 2))
      .build()
    val update = CameraUpdateFactory.newLatLngBounds(bounds, 0)
    if (durationMs > 0) map.animateCamera(update, durationMs.toInt()) else map.moveCamera(update)
  }

  override fun fitToCoordinates(coordinates: Array<MapCoordinate>, padding: EdgeInsets, animated: Boolean) {
    val map = map ?: return
    if (coordinates.isEmpty()) return
    if (coordinates.size == 1) {
      val c = coordinates[0]
      map.moveCamera(CameraUpdateFactory.newLatLng(LatLng(c.latitude, c.longitude)))
      return
    }
    val builder = LatLngBounds.Builder()
    coordinates.forEach { builder.include(LatLng(it.latitude, it.longitude)) }
    val update = CameraUpdateFactory.newLatLngBounds(builder.build(),
      (padding.left * density).toInt(), (padding.top * density).toInt(),
      (padding.right * density).toInt(), (padding.bottom * density).toInt())
    if (animated) map.animateCamera(update) else map.moveCamera(update)
  }

  override fun pointForCoordinate(coordinate: MapCoordinate): MapPoint? {
    val point = map?.projection?.toScreenLocation(LatLng(coordinate.latitude, coordinate.longitude)) ?: return null
    return MapPoint(point.x / density, point.y / density)
  }

  override fun coordinateForPoint(point: MapPoint): MapCoordinate? {
    val latLng = map?.projection?.fromScreenLocation(PointF((point.x * density).toFloat(), (point.y * density).toFloat()))
      ?: return null
    return MapCoordinate(latLng.latitude, latLng.longitude)
  }

  // MapCameraSource

  override val cameraView: View? get() = if (destroyed) null else mapView

  override fun cameraState(previous: MapCameraState?): MapCameraState? {
    val map = map ?: return null
    if (!styleLoaded) return null
    val width = mapView.width.toDouble()
    val height = mapView.height.toDouble()
    if (width < 1 || height < 1) return null
    val position = map.cameraPosition
    val target = position.target ?: return null
    val fov = fieldOfView(position)
    val distance = distance(position.zoom, target.latitude, fov)
    return MapCameraState(
      latitude = target.latitude,
      longitude = target.longitude,
      distance = distance,
      altitude = distance * cos(position.tilt * PI / 180),
      pitch = position.tilt,
      heading = position.bearing,
      width = width,
      height = height,
      focalLength = MapCameraState.focalLength(height, fov),
      centerX = width / 2,
      centerY = height / 2,
      pixelRatio = density,
    )
  }

  override fun screenPoint(latitude: Double, longitude: Double): PointF? =
    map?.projection?.toScreenLocation(LatLng(latitude, longitude))

  companion object {
    /** MapLibre's vertical field of view: 2 atan(1/3), about 36.87°. */
    private val DEFAULT_FOV = 0.6435011087932844
    private const val TILE_SIZE = 512.0
  }
}
