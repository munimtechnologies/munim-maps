package com.margelo.nitro.munimmaps

import android.os.Handler
import android.os.Looper
import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.Promise
import com.munimmaps.engine.MunimMapEngines
import com.munimmaps.engine.ProviderJson
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

  override fun providerCall(provider: String, method: String, argsJson: String): Promise<String> {
    val promise = Promise<String>()
    val engine = MapProvider.entries.firstOrNull { it.id == provider }
    if (engine == null) {
      promise.reject(IllegalArgumentException("Unknown map provider \"$provider\""))
      return promise
    }
    val context = NitroModules.applicationContext
    if (context == null) {
      promise.reject(IllegalStateException("React Native is not ready"))
      return promise
    }
    val args = ProviderJson.objectOf(argsJson)
    Handler(Looper.getMainLooper()).post {
      try {
        MunimMapEngines.providerCall(
          engine, context, method, args,
          emit = { name, payload -> eventListener?.invoke(provider, name, ProviderJson.stringOf(payload)) },
        ) { result -> result.fold({ promise.resolve(ProviderJson.stringOf(it)) }, { promise.reject(it) }) }
      } catch (error: Throwable) {
        promise.reject(error)
      }
    }
    return promise
  }

  override fun setProviderEventListener(listener: (provider: String, name: String, json: String) -> Unit) {
    eventListener = listener
  }

  companion object {
    /** Engine-level events go to the last listener set. */
    @Volatile private var eventListener: ((String, String, String) -> Unit)? = null
  }
}
