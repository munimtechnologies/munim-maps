package com.munimmaps.engine

import android.content.Context
import android.content.pm.PackageManager

/**
 * Keys and defaults every engine reads: set from JavaScript with
 * `configureMunimMaps`, or from the app's manifest and resources (the Expo
 * config plugin writes them): `com.google.android.geo.API_KEY` and
 * `munimmaps.cesium_ion_token` meta-data, the `mapbox_access_token` string.
 * The Android twin of iOS's `MunimMapsConfiguration`.
 */
object MunimMapsConfiguration {
  /** OpenFreeMap's Liberty style: OpenStreetMap data, free, no key. */
  const val OPEN_FREE_MAP_STYLE_URL = "https://tiles.openfreemap.org/styles/liberty"

  /** Google Maps only reads its key from the manifest; this is for reference. */
  @Volatile var googleMapsApiKey = ""
  @Volatile var mapboxAccessToken = ""
  @Volatile var cesiumIonToken = ""
  @Volatile var maplibreStyleUrl = OPEN_FREE_MAP_STYLE_URL
  /** Empty is Mapbox Standard. */
  @Volatile var mapboxStyleUrl = ""

  private var loaded = false

  /** Reads the manifest and resources once; values set from JavaScript win. */
  @Synchronized
  fun load(context: Context) {
    if (loaded) return
    loaded = true
    val app = context.applicationContext
    val meta = try {
      app.packageManager.getApplicationInfo(app.packageName, PackageManager.GET_META_DATA).metaData
    } catch (_: Exception) {
      null
    }
    if (googleMapsApiKey.isEmpty()) googleMapsApiKey = meta?.getString("com.google.android.geo.API_KEY") ?: ""
    if (cesiumIonToken.isEmpty()) cesiumIonToken = meta?.getString("munimmaps.cesium_ion_token") ?: ""
    if (mapboxAccessToken.isEmpty()) {
      val id = app.resources.getIdentifier("mapbox_access_token", "string", app.packageName)
      if (id != 0) mapboxAccessToken = app.getString(id)
    }
  }
}
