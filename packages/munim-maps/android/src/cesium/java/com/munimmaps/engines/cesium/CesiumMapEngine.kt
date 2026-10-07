package com.munimmaps.engines.cesium

import android.content.Context
import com.margelo.nitro.munimmaps.MapProvider
import com.munimmaps.engine.MunimMapEngine
import com.munimmaps.engine.MunimMapEngineFactory
import com.munimmaps.engine.UnavailableMapEngine

/**
 * The Cesium engine: Cesium (a 3D globe with terrain and 3D Tiles; the engine decides how: Cesium Native or CesiumJS in a WebView).
 *
 * Compiled only when the app sets `munimMaps.cesium=true` (this source set and
 * the SDK are added by android/build.gradle). This is the phase 1 stub: the
 * engine is registered (`MunimMapEngines` finds this factory by name) and
 * shows a placeholder.
 *
 * To implement it (everything stays inside android/src/cesium/):
 * 1. Write `CesiumMapEngine(context) : MunimMapEngine, MapCameraSource` that
 *    hosts the SDK's map view in a FrameLayout with `modelLayer.view` on top,
 *    and calls `modelLayer.attach(this)`. See the MapLibre engine
 *    (android/src/maplibre/…/MapLibreMapEngine.kt) for the pattern: lifecycle,
 *    camera to [com.munimmaps.engine.MapCameraState] (centre, distance in
 *    metres, pitch, heading, focal length in pixels, viewport, centre point),
 *    `screenPoint` from the SDK's projection, taps through
 *    `modelLayer.handleTap` first.
 *    Notes: `MunimMapsConfiguration.cesiumIonToken`; `MapCameraState(globe = true, drawsTerrain = true)`.
 * 2. Override the `MunimMapEngine` setters and methods it supports; the
 *    defaults report "not supported yet" through the listener.
 * 3. Set `isImplemented = true` and return the engine from `create`.
 * 4. Test: the example's provider picker (`munimmapsexample://providers/cesium`)
 *    shows the map with a GLB vehicle, and `measureAlignment()` is within a
 *    point or two.
 */
object CesiumMapEngineFactory : MunimMapEngineFactory {
  override val isImplemented = false

  override fun create(context: Context): MunimMapEngine =
    UnavailableMapEngine(context, MapProvider.CESIUM, "The Cesium engine is built in but not implemented yet.")
}
