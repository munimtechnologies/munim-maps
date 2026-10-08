package com.munimmaps.engine

import android.content.Context
import com.margelo.nitro.munimmaps.MapProvider
import org.json.JSONObject

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
    get() = MapProvider.entries.filter { factory(it) != null || (it == MapProvider.MAPLIBRE && hasMapLibreWeb) }

  /** Engines that are built in and draw a map. */
  val available: List<MapProvider>
    get() = MapProvider.entries.filter { factory(it)?.isImplemented == true || (it == MapProvider.MAPLIBRE && hasMapLibreWeb) }

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

  private const val MAPLIBRE_WEB_FACTORY = "com.munimmaps.engines.maplibreweb.MapLibreWebEngineFactory"

  private val mapLibreWeb: MunimMapEngineFactory? by lazy {
    try {
      Class.forName(MAPLIBRE_WEB_FACTORY).getField("INSTANCE").get(null) as? MunimMapEngineFactory
    } catch (_: ReflectiveOperationException) {
      null
    }
  }

  /** Whether this app has MapLibre GL JS (`munimMaps.maplibreWeb`, on with MapLibre by default). */
  val hasMapLibreWeb: Boolean get() = mapLibreWeb != null

  /** Whether this app has MapLibre Native. */
  val hasMapLibreNative: Boolean get() = factory(MapProvider.MAPLIBRE) != null

  /**
   * Options that only MapLibre GL JS can draw: the globe and other
   * projections, 3D terrain, sky. (JavaScript also counts the `globe` prop
   * and sends `renderer: "web"`.)
   */
  fun mapLibreNeedsWeb(options: JSONObject): Boolean {
    val projection = options.opt("projection")
    if (projection is String && projection != "mercator") return true
    if (projection is JSONObject) return true
    for (key in listOf("terrain", "sky")) {
      val v = options.opt(key)
      if (v == true || v is JSONObject) return true
    }
    return false
  }

  /**
   * Which implementation of [provider] [options] ask for (`""` is the
   * default one). MapLibre: `renderer` `web` (GL JS), `native` (MapLibre
   * Native) or `auto` (Native unless [mapLibreNeedsWeb]), within what the
   * app has built in.
   */
  fun variant(provider: MapProvider, options: JSONObject): String {
    if (provider != MapProvider.MAPLIBRE || !hasMapLibreWeb) return ""
    if (!hasMapLibreNative) return "web"
    return when (options.optString("renderer", "auto")) {
      "web" -> "web"
      "native" -> ""
      else -> if (mapLibreNeedsWeb(options)) "web" else ""
    }
  }

  /** A new engine for [provider] and the renderer [options] ask for. */
  fun create(provider: MapProvider, context: Context, options: JSONObject): MunimMapEngine {
    if (variant(provider, options) == "web") mapLibreWeb?.let { return it.create(context) }
    return create(provider, context)
  }

  /** A new engine for [provider], or a placeholder saying why there is none. */
  fun create(provider: MapProvider, context: Context): MunimMapEngine {
    val factory = factory(provider) ?: if (provider == MapProvider.MAPLIBRE) mapLibreWeb else null
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
