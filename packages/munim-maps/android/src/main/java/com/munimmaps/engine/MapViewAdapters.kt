package com.munimmaps.engine

import android.view.View
import android.view.ViewGroup

/**
 * Turns another library's map view into a [MapCameraSource], so
 * `MapModelLayer` can draw over it: react-native-maps' Google `MapView`
 * (`com.google.android.gms.maps.MapView`) and `@rnmapbox/maps`'
 * (`com.mapbox.maps.MapView`). Each built-in adapter lives in its own source
 * set (`src/googleView`, `src/mapboxView`), compiled only when its SDK is in
 * the app, and is found here by class name, like the engines.
 */
fun interface MapViewAdapter {
  /** A camera source for `view` when it is a map this adapter knows, else null. */
  fun cameraSource(view: View): MapCameraSource?
}

object MapViewAdapters {
  /** Built-in adapters, by class name (kept by `proguard-rules.pro`). */
  private val builtIn = listOf(
    "com.munimmaps.engines.google.GoogleMapViewAdapter",
    "com.munimmaps.engines.mapbox.MapboxMapViewAdapter",
  )
  private val adapters = mutableListOf<MapViewAdapter>()
  private var loaded = false

  /** Adds an adapter for another map SDK's view. */
  @Synchronized
  fun register(adapter: MapViewAdapter) {
    if (adapters.none { it === adapter }) adapters.add(adapter)
  }

  @Synchronized
  private fun all(): List<MapViewAdapter> {
    if (!loaded) {
      loaded = true
      for (name in builtIn) {
        try {
          (Class.forName(name).getField("INSTANCE").get(null) as? MapViewAdapter)?.let { register(it) }
        } catch (_: ReflectiveOperationException) {
          // Its SDK is not in this app, so it was not compiled.
        } catch (_: LinkageError) {
          // Compiled, but the SDK is missing at run time.
        }
      }
    }
    return adapters.toList()
  }

  /** Whether no adapter is built in or registered. */
  val isEmpty: Boolean get() = all().isEmpty()

  /** A camera source for the first map found inside `root` (itself included). */
  fun find(root: View, skip: View? = null): MapCameraSource? = find(root, skip, all())

  private fun find(root: View, skip: View?, adapters: List<MapViewAdapter>): MapCameraSource? {
    if (root === skip) return null
    for (adapter in adapters) adapter.cameraSource(root)?.let { return it }
    if (root is ViewGroup) {
      for (i in 0 until root.childCount) find(root.getChildAt(i), skip, adapters)?.let { return it }
    }
    return null
  }
}
