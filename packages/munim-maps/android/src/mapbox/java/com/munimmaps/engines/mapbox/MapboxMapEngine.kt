package com.munimmaps.engines.mapbox

import android.content.Context
import com.margelo.nitro.munimmaps.MapProvider
import com.munimmaps.engine.MunimMapEngine
import com.munimmaps.engine.MunimMapEngineFactory
import com.munimmaps.engine.UnavailableMapEngine

/**
 * The Mapbox engine: Mapbox Maps SDK for Android v11 (`com.mapbox.maps.MapView`).
 *
 * Compiled only when the app sets `munimMaps.mapbox=true` (this source set and
 * the SDK are added by android/build.gradle). This is the phase 1 stub: the
 * engine is registered (`MunimMapEngines` finds this factory by name) and
 * shows a placeholder.
 *
 * To implement it (everything stays inside android/src/mapbox/):
 * 1. Write `MapboxMapEngine(context) : MunimMapEngine, MapCameraSource` that
 *    hosts the SDK's map view in a FrameLayout with `modelLayer.view` on top,
 *    and calls `modelLayer.attach(this)`. See the MapLibre engine
 *    (android/src/maplibre/…/MapLibreMapEngine.kt) for the pattern: lifecycle,
 *    camera to [com.munimmaps.engine.MapCameraState] (centre, distance in
 *    metres, pitch, heading, focal length in pixels, viewport, centre point),
 *    `screenPoint` from the SDK's projection, taps through
 *    `modelLayer.handleTap` first.
 *    Notes: `MapboxOptions.accessToken = MunimMapsConfiguration.mapboxAccessToken`; style from `setStyleUrl` or `MunimMapsConfiguration.mapboxStyleUrl`; camera from `mapboxMap.cameraState` (512-dp tiles, 36.87° vertical field of view).
 * 2. Override the `MunimMapEngine` setters and methods it supports; the
 *    defaults report "not supported yet" through the listener.
 * 3. Set `isImplemented = true` and return the engine from `create`.
 * 4. Test: the example's provider picker (`munimmapsexample://providers/mapbox`)
 *    shows the map with a GLB vehicle, and `measureAlignment()` is within a
 *    point or two.
 */
object MapboxMapEngineFactory : MunimMapEngineFactory {
  override val isImplemented = false

  override fun create(context: Context): MunimMapEngine =
    UnavailableMapEngine(context, MapProvider.MAPBOX, "The Mapbox engine is built in but not implemented yet.")
}
