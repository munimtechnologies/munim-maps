package com.munimmaps.engine

import android.content.Context
import com.margelo.nitro.munimmaps.MapProvider

/**
 * The engines built into this app, and making them.
 *
 * Each engine lives in its own Gradle source set
 * (`android/src/<provider>/java/com/munimmaps/engines/<provider>/`), added to
 * the build only when its Gradle property is on (`munimMaps.google=true`…;
 * MapLibre is on unless `munimMaps.maplibre=false`), together with its SDK.
 * The registry finds the engine's factory by name, so nothing here refers to
 * an engine that may not be compiled. Consumer ProGuard rules keep them.
 */
object MunimMapEngines {
  private val factoryClasses = mapOf(
    MapProvider.GOOGLE to "com.munimmaps.engines.google.GoogleMapEngineFactory",
    MapProvider.MAPBOX to "com.munimmaps.engines.mapbox.MapboxMapEngineFactory",
    MapProvider.MAPLIBRE to "com.munimmaps.engines.maplibre.MapLibreMapEngineFactory",
    MapProvider.CESIUM to "com.munimmaps.engines.cesium.CesiumMapEngineFactory",
  )

  private val factories = mutableMapOf<MapProvider, MunimMapEngineFactory?>()

  @Synchronized
  private fun factory(provider: MapProvider): MunimMapEngineFactory? =
    factories.getOrPut(provider) {
      val name = factoryClasses[provider] ?: return@getOrPut null
      try {
        Class.forName(name).getField("INSTANCE").get(null) as? MunimMapEngineFactory
      } catch (_: ReflectiveOperationException) {
        null
      }
    }

  /** Engines whose SDK is built in, implemented yet or not. */
  val installed: List<MapProvider>
    get() = MapProvider.entries.filter { factory(it) != null }

  /** Engines that are built in and draw a map. */
  val available: List<MapProvider>
    get() = MapProvider.entries.filter { factory(it)?.isImplemented == true }

  /** Runs an engine-level command (no map needed) on [provider]'s engine, on the main thread. */
  fun providerCommand(
    provider: MapProvider,
    context: Context,
    command: String,
    args: org.json.JSONObject,
    emit: (String, Any?) -> Unit,
    completion: (Result<String>) -> Unit,
  ) {
    val factory = factory(provider)
    if (factory == null) {
      completion(Result.failure(IllegalStateException("${provider.displayName} is not built into this app")))
      return
    }
    factory.providerCommand(context, command, args, emit, completion)
  }

  /** A new engine for [provider], or a placeholder saying why there is none. */
  fun create(provider: MapProvider, context: Context): MunimMapEngine {
    val factory = factory(provider)
    if (factory != null) return factory.create(context)
    val reason = if (provider == MapProvider.MAPKIT) {
      "MapKit is Apple's and only exists on iOS. Use provider=\"maplibre\" or \"google\" on Android."
    } else {
      "${provider.displayName} is not built into this app. Set munimMaps.${provider.id}=true in " +
        "android/gradle.properties (or the Expo config plugin's providers option) and rebuild."
    }
    return UnavailableMapEngine(context, provider, reason)
  }
}
