package com.margelo.nitro.munimmaps

import com.munimmaps.engine.MunimMapEngines
import com.munimmaps.engine.MunimMapsConfiguration
import com.munimmaps.engine.id

/** React Native `configureMunimMaps()` and the engines this build has. */
class HybridMunimMapsConfig : HybridMunimMapsConfigSpec() {
  override fun configure(configuration: NativeMapsConfiguration) {
    // Empty keeps what the manifest and resources set.
    if (configuration.googleMapsApiKey.isNotEmpty()) MunimMapsConfiguration.googleMapsApiKey = configuration.googleMapsApiKey
    if (configuration.mapboxAccessToken.isNotEmpty()) MunimMapsConfiguration.mapboxAccessToken = configuration.mapboxAccessToken
    if (configuration.cesiumIonToken.isNotEmpty()) MunimMapsConfiguration.cesiumIonToken = configuration.cesiumIonToken
    if (configuration.maplibreStyleUrl.isNotEmpty()) MunimMapsConfiguration.maplibreStyleUrl = configuration.maplibreStyleUrl
    if (configuration.mapboxStyleUrl.isNotEmpty()) MunimMapsConfiguration.mapboxStyleUrl = configuration.mapboxStyleUrl
  }

  override fun availableProviders(): String = MunimMapEngines.available.joinToString(",") { it.id }

  override fun installedProviders(): String = MunimMapEngines.installed.joinToString(",") { it.id }
}
