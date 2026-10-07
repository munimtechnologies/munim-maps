package com.munimmaps.models

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.Executors

/**
 * Loads model files (GLB / glTF with embedded buffers) as bytes, off the main
 * thread, and caches them by URI so models sharing a file read it once.
 *
 * Understands what JavaScript hands over: `http(s)://` (Metro in
 * development, or any server), `file://` and absolute paths, `asset:/` (the
 * APK's assets), and bare names, which is how React Native release builds
 * refer to `require()`d files (Android raw resources, such as
 * `node_modules_munimmaps_vehicles_glb_carev`).
 *
 * Remote files (other than Metro's dev server) are kept in the app's cache
 * directory (`munim-maps/`, named by a hash of the URL), so models such as
 * munim-maps-vehicles' load once and work offline afterwards.
 */
object ModelAssets {
  private val executor = Executors.newFixedThreadPool(2)
  private val main = Handler(Looper.getMainLooper())
  private val cache = object : LinkedHashMap<String, ByteArray>(16, 0.75f, true) {
    override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, ByteArray>?) = size > 24
  }
  private val waiting = mutableMapOf<String, MutableList<(Result<ByteArray>) -> Unit>>()

  /** Calls back on the main thread. */
  fun load(context: Context, uri: String, completion: (Result<ByteArray>) -> Unit) {
    synchronized(this) {
      cache[uri]?.let { bytes ->
        main.post { completion(Result.success(bytes)) }
        return
      }
      waiting[uri]?.let {
        it.add(completion)
        return
      }
      waiting[uri] = mutableListOf(completion)
    }
    val app = context.applicationContext
    executor.execute {
      val result = runCatching { read(app, uri) }
      val callbacks = synchronized(this) {
        result.getOrNull()?.let { cache[uri] = it }
        waiting.remove(uri) ?: mutableListOf()
      }
      main.post { callbacks.forEach { it(result) } }
    }
  }

  /**
   * Where a remote file is kept, or null for Metro's dev server (its files
   * change on reload) and other schemes.
   */
  fun cacheFile(context: Context, uri: String): File? {
    val parsed = Uri.parse(uri)
    val scheme = parsed.scheme?.lowercase()
    if ((scheme != "http" && scheme != "https") || parsed.port == 8081) return null
    val digest = MessageDigest.getInstance("SHA-256").digest(uri.toByteArray())
      .joinToString("") { "%02x".format(it) }
    val ext = (parsed.lastPathSegment ?: "").substringAfterLast('.', "").lowercase()
      .takeIf { it.isNotEmpty() && it.length <= 5 } ?: "bin"
    return File(File(context.applicationContext.cacheDir, "munim-maps"), "$digest.$ext")
  }

  /** Reads a file on the calling thread (a background one), through the disk cache. */
  fun readBlocking(context: Context, uri: String): ByteArray = read(context.applicationContext, uri)

  private fun read(context: Context, uri: String): ByteArray {
    val parsed = Uri.parse(uri)
    return when (parsed.scheme?.lowercase()) {
      "http", "https" -> {
        val cached = cacheFile(context, uri)
        if (cached != null && cached.isFile) return cached.readBytes()
        val connection = URL(uri).openConnection() as HttpURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        val bytes = try {
          if (connection.responseCode !in 200..299) error("HTTP ${connection.responseCode} for $uri")
          connection.inputStream.use { it.readBytes() }
        } finally {
          connection.disconnect()
        }
        if (cached != null) {
          runCatching {
            cached.parentFile?.mkdirs()
            val part = File(cached.path + ".part")
            part.writeBytes(bytes)
            part.renameTo(cached)
          }
        }
        bytes
      }
      "file" -> File(parsed.path ?: error("Bad file URI $uri")).readBytes()
      "asset" -> context.assets.open(uri.removePrefix("asset:/").trimStart('/')).use { it.readBytes() }
      "android.resource", "res" -> {
        val name = parsed.lastPathSegment ?: error("Bad resource URI $uri")
        readRaw(context, name)
      }
      null, "" -> if (uri.startsWith("/")) File(uri).readBytes() else readRaw(context, uri)
      else -> error("Cannot load $uri")
    }
  }

  private fun readRaw(context: Context, name: String): ByteArray {
    // Release builds put `require()`d models in res/raw and pictures in res/drawable-*.
    val base = name.substringBeforeLast('.')
    val id = context.resources.getIdentifier(base, "raw", context.packageName).takeIf { it != 0 }
      ?: context.resources.getIdentifier(base, "drawable", context.packageName)
    if (id == 0) error("No raw or drawable resource named $name")
    return context.resources.openRawResource(id).use { it.readBytes() }
  }
}
