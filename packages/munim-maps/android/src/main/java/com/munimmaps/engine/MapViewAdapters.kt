package com.munimmaps.engine

import android.view.View
import android.view.ViewGroup

/**
 * Turns another library's map view into a [MapCameraSource], so
 * `MapModelLayer` can draw over it (react-native-maps' Google `MapView`,
 * MapLibre React Native, Mapbox's `@rnmapbox/maps`…). Engines register
 * adapters for their SDK's view class from their source set.
 */
fun interface MapViewAdapter {
  /** A camera source for `view` when it is a map this adapter knows, else null. */
  fun cameraSource(view: View): MapCameraSource?
}

object MapViewAdapters {
  private val adapters = mutableListOf<MapViewAdapter>()

  @Synchronized
  fun register(adapter: MapViewAdapter) {
    adapters.add(adapter)
  }

  @Synchronized
  private fun all(): List<MapViewAdapter> = adapters.toList()

  /** A camera source for the first map found inside `root` (itself included). */
  fun find(root: View, skip: View? = null): MapCameraSource? {
    if (root === skip) return null
    for (adapter in all()) adapter.cameraSource(root)?.let { return it }
    if (root is ViewGroup) {
      for (i in 0 until root.childCount) find(root.getChildAt(i), skip)?.let { return it }
    }
    return null
  }
}
