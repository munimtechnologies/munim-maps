package com.munimmaps.engines.google

import android.content.Context
import com.margelo.nitro.munimmaps.MapProvider
import com.munimmaps.engine.MunimMapEngine
import com.munimmaps.engine.MunimMapEngineFactory
import com.munimmaps.engine.UnavailableMapEngine

/**
 * The Google engine: Google Maps SDK for Android (`com.google.android.gms.maps.MapView`).
 *
 * Compiled only when the app sets `munimMaps.google=true` (this source set and
 * the SDK are added by android/build.gradle). This is the phase 1 stub: the
 * engine is registered (`MunimMapEngines` finds this factory by name) and
 * shows a placeholder.
 *
 * To implement it (everything stays inside android/src/google/):
 * 1. Write `GoogleMapEngine(context) : MunimMapEngine, MapCameraSource` that
 *    hosts the SDK's map view in a FrameLayout with `modelLayer.view` on top,
 *    and calls `modelLayer.attach(this)`. See the MapLibre engine
 *    (android/src/maplibre/…/MapLibreMapEngine.kt) for the pattern: lifecycle,
 *    camera to [com.munimmaps.engine.MapCameraState] (centre, distance in
 *    metres, pitch, heading, focal length in pixels, viewport, centre point),
 *    `screenPoint` from the SDK's projection, taps through
 *    `modelLayer.handleTap` first.
 *    Notes: the key comes from the app manifest (`com.google.android.geo.API_KEY`); Google uses 256-dp tiles and a vertical field of view you measure (about 30°) against `projection.toScreenLocation`; also register a `MapViewAdapter` for `com.google.android.gms.maps.MapView` so `MapModelLayer` draws over react-native-maps.
 * 2. Override the `MunimMapEngine` setters and methods it supports; the
 *    defaults report "not supported yet" through the listener.
 * 3. Set `isImplemented = true` and return the engine from `create`.
 * 4. Test: the example's provider picker (`munimmapsexample://providers/google`)
 *    shows the map with a GLB vehicle, and `measureAlignment()` is within a
 *    point or two.
 */
object GoogleMapEngineFactory : MunimMapEngineFactory {
  override val isImplemented = false

  override fun create(context: Context): MunimMapEngine =
    UnavailableMapEngine(context, MapProvider.GOOGLE, "The Google engine is built in but not implemented yet.")
}
