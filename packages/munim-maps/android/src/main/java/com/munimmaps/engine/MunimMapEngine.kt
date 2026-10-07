package com.munimmaps.engine

import android.content.Context
import android.view.View
import com.margelo.nitro.munimmaps.CalloutAccessoryEvent
import com.margelo.nitro.munimmaps.CameraKeyframe
import com.margelo.nitro.munimmaps.ClusterPressEvent
import com.margelo.nitro.munimmaps.EdgeInsets
import com.margelo.nitro.munimmaps.FeatureVisibility
import com.margelo.nitro.munimmaps.MapAddress
import com.margelo.nitro.munimmaps.MapAlignmentReport
import com.margelo.nitro.munimmaps.MapCamera
import com.margelo.nitro.munimmaps.MapCameraEasing
import com.margelo.nitro.munimmaps.MapColorScheme
import com.margelo.nitro.munimmaps.MapCoordinate
import com.margelo.nitro.munimmaps.MapElevation
import com.margelo.nitro.munimmaps.MapFeatureEvent
import com.margelo.nitro.munimmaps.MapPoint
import com.margelo.nitro.munimmaps.MapPressEvent
import com.margelo.nitro.munimmaps.MapProvider
import com.margelo.nitro.munimmaps.MapRegion
import com.margelo.nitro.munimmaps.MapStyle
import com.margelo.nitro.munimmaps.MarkerDragEvent
import com.margelo.nitro.munimmaps.NativeCircle
import com.margelo.nitro.munimmaps.NativeClusterStyle
import com.margelo.nitro.munimmaps.NativeMarker
import com.margelo.nitro.munimmaps.NativePolygon
import com.margelo.nitro.munimmaps.NativePolyline
import com.margelo.nitro.munimmaps.NativeTileOverlay
import com.margelo.nitro.munimmaps.OverlayPressEvent
import com.margelo.nitro.munimmaps.UserLocationEvent
import com.margelo.nitro.munimmaps.UserTrackingMode
import com.munimmaps.models.MunimModelLayer
import org.json.JSONObject

/**
 * Events an engine reports. [com.margelo.nitro.munimmaps.HybridMunimMapView]
 * implements this and forwards to JavaScript; engines call it.
 */
interface MunimMapEngineListener {
  fun onMapReady() {}
  /** A tap on the map (not on a marker, model or tappable overlay). */
  fun onPress(event: MapPressEvent) {}
  fun onLongPress(event: MapPressEvent) {}
  /** While the camera moves, about once a frame. */
  fun onCameraMove(camera: MapCamera) {}
  /** When the camera stops. */
  fun onCameraChange(camera: MapCamera) {}
  fun onMarkerPress(id: String) {}
  fun onMarkerDeselect(id: String) {}
  fun onCalloutPress(id: String) {}
  fun onCalloutAccessoryPress(event: CalloutAccessoryEvent) {}
  fun onClusterPress(event: ClusterPressEvent) {}
  /** Only while [MunimMapEngine.overlayPressEnabled]; taken instead of onPress. */
  fun onOverlayPress(event: OverlayPressEvent) {}
  fun onMarkerDragStart(event: MarkerDragEvent) {}
  fun onMarkerDragEnd(event: MarkerDragEvent) {}
  fun onUserLocationChange(location: UserLocationEvent) {}
  fun onUserTrackingModeChange(mode: UserTrackingMode) {}
  fun onMapFeaturePress(feature: MapFeatureEvent) {}
  /** An event only this engine has (`onProviderEvent`): its name and data as JSON. */
  fun onProviderEvent(name: String, json: String) {}
  fun onError(message: String) {}
}

/** How the registry makes one engine (one per provider source set). */
interface MunimMapEngineFactory {
  /** False while the engine is a stub that shows a placeholder. */
  val isImplemented: Boolean
  fun create(context: Context): MunimMapEngine
}

/**
 * One map engine behind `MunimMapView` on Android: Google Maps, Mapbox,
 * MapLibre or Cesium. The Android twin of iOS's `MunimMapEngine`
 * (ios/Engines/MunimMapEngine.swift).
 *
 * [MunimMapContainerView] owns one engine at a time and puts [view] in
 * itself; [com.margelo.nitro.munimmaps.HybridMunimMapView] sets the
 * properties below as React props change and receives events through
 * [listener]. The engine draws the map and its 2D features with its own SDK.
 *
 * 3D models, zones and paths are not the engine's job: every engine owns a
 * [MunimModelLayer] ([modelLayer]), adds `modelLayer.view` over its map view
 * and attaches it to a [MapCameraSource] that turns the SDK's camera into
 * [MapCameraState] every frame. The host sets models, lighting, occlusion
 * and so on on that layer directly, so the Filament renderer draws the same
 * GLB models over every engine.
 *
 * Everything has a default: props are ignored and methods report "not
 * supported yet" through [listener], so an engine can be built up feature by
 * feature. Values use the Nitro-generated types (the same as JavaScript's).
 */
interface MunimMapEngine {
  val provider: MapProvider
  val view: View
  val modelLayer: MunimModelLayer
  var listener: MunimMapEngineListener?

  fun reportUnsupported(what: String) {
    listener?.onError("${provider.displayName}: $what is not supported yet")
  }

  /** Tear down the SDK's view (onDestroy); the engine is not used again. */
  fun destroy() {}

  // Provider settings

  /** MapLibre / Mapbox style URL; empty for the engine's default. */
  fun setStyleUrl(url: String) {}
  /** The active provider's own options (`maplibre={{…}}` in JavaScript). */
  fun setProviderOptions(options: JSONObject) {}

  // 2D content

  fun setMarkers(markers: Array<NativeMarker>) { if (markers.isNotEmpty()) reportUnsupported("markers") }
  fun setPolylines(polylines: Array<NativePolyline>) { if (polylines.isNotEmpty()) reportUnsupported("polylines") }
  fun setPolygons(polygons: Array<NativePolygon>) { if (polygons.isNotEmpty()) reportUnsupported("polygons") }
  fun setCircles(circles: Array<NativeCircle>) { if (circles.isNotEmpty()) reportUnsupported("circles") }
  fun setTileOverlays(overlays: Array<NativeTileOverlay>) { if (overlays.isNotEmpty()) reportUnsupported("tileOverlays") }
  fun setClusterStyles(styles: Array<NativeClusterStyle>) {}

  // Look

  /** Applied once, when the map first has a size. */
  fun setInitialCamera(camera: MapCamera) {}
  fun setMapStyle(style: MapStyle) {}
  fun setElevation(elevation: MapElevation) {}
  fun setGlobe(globe: Boolean) {}
  fun setColorScheme(scheme: MapColorScheme) {}
  fun setShowsBuildings(shows: Boolean) {}
  fun setShowsUserLocation(shows: Boolean) { if (shows) reportUnsupported("showsUserLocation") }
  fun setShowsTraffic(shows: Boolean) {}
  /** `all`, `none`, or comma-separated categories. */
  fun setPointsOfInterest(filter: String) {}

  // Controls

  fun setCompassVisibility(visibility: FeatureVisibility) {}
  fun setScaleVisibility(visibility: FeatureVisibility) {}
  fun setShowsUserTrackingButton(shows: Boolean) {}

  // Gestures and limits

  fun setUserTrackingMode(mode: UserTrackingMode) { if (mode != UserTrackingMode.NONE) reportUnsupported("userTrackingMode") }
  fun setGestures(zoom: Boolean, scroll: Boolean, rotate: Boolean, pitch: Boolean) {}
  /** Closest and farthest camera distance in metres; 0 for the engine's. */
  fun setCameraDistanceRange(min: Double, max: Double) {}
  /** Keep the camera's centre inside this region; null for none. */
  fun setCameraBoundary(region: MapRegion?) {}
  /** Space covered by the app's own UI, in points. */
  fun setMapPadding(padding: EdgeInsets) {}
  /** Whether taps are hit-tested against tappable overlays. */
  fun setOverlayPressEnabled(enabled: Boolean) {}

  // Camera

  fun getCamera(): MapCamera? = null
  fun setCamera(camera: MapCamera, animated: Boolean) { reportUnsupported("setCamera") }
  fun animateCamera(camera: MapCamera, durationMs: Double, easing: MapCameraEasing) {
    setCamera(camera, durationMs > 0)
  }
  fun flyCamera(keyframes: Array<CameraKeyframe>, start: Double, loop: Boolean) { reportUnsupported("flyCamera") }
  fun stopFlight() {}
  fun getVisibleRegion(): MapRegion? = null
  fun setRegion(region: MapRegion, durationMs: Double) { reportUnsupported("setRegion") }
  fun fitToCoordinates(coordinates: Array<MapCoordinate>, padding: EdgeInsets, animated: Boolean) {
    reportUnsupported("fitToCoordinates")
  }
  /** Frames these markers (all when empty). */
  fun fitToMarkers(ids: Set<String>, padding: EdgeInsets, animated: Boolean) { reportUnsupported("fitToMarkers") }
  /** In points, like iOS and JavaScript. */
  fun pointForCoordinate(coordinate: MapCoordinate): MapPoint? = null
  fun coordinateForPoint(point: MapPoint): MapCoordinate? = null

  // Methods

  fun selectMarker(id: String) {}
  fun deselectMarker(id: String) {}
  /** Writes a PNG of the map and returns its path. */
  fun takeSnapshot(width: Double, height: Double, completion: (Result<String>) -> Unit) {
    completion(Result.failure(UnsupportedOperationException("${provider.displayName}: takeSnapshot is not supported yet")))
  }
  fun addressForCoordinate(coordinate: MapCoordinate, completion: (Result<MapAddress>) -> Unit) {
    completion(Result.failure(UnsupportedOperationException("${provider.displayName}: addressForCoordinate is not supported yet")))
  }
  /** How far the 3D layer is from where the engine draws the same points. */
  fun measureAlignment(): MapAlignmentReport = modelLayer.measureAlignment()
  /** Id of the tappable overlay a tap at `point` (points) would hit, or empty. */
  fun overlayAtPoint(point: MapPoint): String = ""

  /**
   * A method only this engine has (`providerCommand` in JavaScript): `args`
   * is the decoded JSON; complete with the result as JSON text (`null` for
   * none).
   */
  fun providerCommand(command: String, args: JSONObject, completion: (Result<String>) -> Unit) {
    completion(Result.failure(UnsupportedOperationException("${provider.displayName} has no command \"$command\"")))
  }
}

/** The name people know it by, for messages. */
val MapProvider.displayName: String
  get() = when (this) {
    MapProvider.MAPKIT -> "MapKit"
    MapProvider.GOOGLE -> "Google Maps"
    MapProvider.MAPBOX -> "Mapbox"
    MapProvider.MAPLIBRE -> "MapLibre"
    MapProvider.CESIUM -> "Cesium"
  }

/** The JavaScript / Gradle name (`maplibre`). */
val MapProvider.id: String
  get() = name.lowercase()
