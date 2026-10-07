package com.munimmaps.engines.google

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.graphics.Color
import android.graphics.Point
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import com.facebook.react.bridge.ReactContext
import com.google.android.gms.maps.StreetViewPanorama
import com.google.android.gms.maps.StreetViewPanoramaOptions
import com.google.android.gms.maps.StreetViewPanoramaView
import com.google.android.gms.maps.model.StreetViewPanoramaCamera
import com.google.android.gms.maps.model.StreetViewPanoramaLocation
import com.google.android.gms.maps.model.StreetViewPanoramaOrientation
import com.google.android.gms.maps.model.StreetViewSource
import org.json.JSONArray
import org.json.JSONObject

// Street View: Google's panoramas (`StreetViewPanoramaView`) over the map
// (`presentation: 'overlay'`) or over the whole screen (`'fullScreen'`,
// what `openLookAround` does on the Google engine).

/** A Street View panorama with a close button. */
class GoogleStreetView(
  context: Context,
  private val engine: GoogleMapEngine,
  options: StreetViewPanoramaOptions,
  private val args: GJson,
  private val opened: (Result<JSONObject>) -> Unit,
) : FrameLayout(context) {
  val panoramaView = StreetViewPanoramaView(context, options)
  var panorama: StreetViewPanorama? = null
  private var openReported = false
  private var resumed = false

  init {
    setBackgroundColor(Color.BLACK)
    addView(panoramaView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    panoramaView.onCreate(null)
    if (args["closeButton"].bool(true)) {
      val density = context.resources.displayMetrics.density
      val close = TextView(context).apply {
        text = "✕"
        textSize = 18f
        setTextColor(Color.WHITE)
        gravity = Gravity.CENTER
        contentDescription = "Close Street View"
        background = GradientDrawable().apply {
          shape = GradientDrawable.OVAL
          setColor(Color.argb(140, 0, 0, 0))
        }
        setOnClickListener { engine.closeStreetView() }
      }
      val size = (40 * density).toInt()
      addView(close, LayoutParams(size, size, Gravity.TOP or Gravity.END).apply {
        topMargin = (12 * density).toInt()
        marginEnd = (12 * density).toInt()
      })
    }
    panoramaView.getStreetViewPanoramaAsync { pano -> ready(pano) }
  }

  private fun ready(pano: StreetViewPanorama) {
    panorama = pano
    apply(args)
    pano.setOnStreetViewPanoramaChangeListener { location ->
      if (location == null) {
        engine.emit("streetViewError", GOut.obj("message" to "No Street View here"))
        if (!openReported) {
          openReported = true
          opened(Result.failure(IllegalStateException("Google Maps: no Street View here")))
        }
        return@setOnStreetViewPanoramaChangeListener
      }
      val info = info(location)
      engine.emit("streetViewChange", info)
      if (!openReported) {
        openReported = true
        engine.emit("streetViewOpen", info)
        opened(Result.success(info))
      }
    }
    pano.setOnStreetViewPanoramaCameraChangeListener { engine.emit("streetViewCamera", camera(it)) }
    pano.setOnStreetViewPanoramaClickListener { orientation ->
      val p = pano.orientationToPoint(orientation)
      val density = resources.displayMetrics.density
      engine.emit("streetViewTap", GOut.obj("x" to (p?.x ?: 0) / density, "y" to (p?.y ?: 0) / density,
        "heading" to orientation.bearing, "pitch" to orientation.tilt))
    }
    pano.setOnStreetViewPanoramaLongClickListener { orientation ->
      engine.emit("streetViewLongPress", GOut.obj("heading" to orientation.bearing, "pitch" to orientation.tilt))
    }
  }

  /** Camera and gestures from `streetView.open` / `setOptions`. */
  fun apply(options: GJson) {
    val pano = panorama ?: return
    if (options["heading"].exists || options["pitch"].exists || options["zoom"].exists) setCamera(options, 0)
    val gestures = options["gestures"]
    gestures.bool?.let {
      pano.isPanningGesturesEnabled = it
      pano.isZoomGesturesEnabled = it
      pano.isUserNavigationEnabled = it
    }
    (gestures["orientation"].bool ?: options["orientationGestures"].bool)?.let { pano.isPanningGesturesEnabled = it }
    (gestures["zoom"].bool ?: options["zoomGestures"].bool)?.let { pano.isZoomGesturesEnabled = it }
    (gestures["navigation"].bool ?: options["navigationGestures"].bool)?.let { pano.isUserNavigationEnabled = it }
    options["streetNamesHidden"].bool?.let { pano.isStreetNamesEnabled = !it }
    options["navigationLinksHidden"].bool?.let { if (it) pano.isUserNavigationEnabled = false }
  }

  fun setCamera(options: GJson, durationMs: Long) {
    val pano = panorama ?: return
    val current = pano.panoramaCamera
    val camera = StreetViewPanoramaCamera.Builder(current)
      .bearing(options["heading"].double(current.bearing.toDouble()).toFloat())
      .tilt(options["pitch"].double(current.tilt.toDouble()).toFloat().coerceIn(-90f, 90f))
      .zoom(options["zoom"].double(current.zoom.toDouble()).toFloat())
      .build()
    pano.animateTo(camera, maxOf(0L, durationMs))
  }

  val cameraInfo: JSONObject get() = panorama?.panoramaCamera?.let { camera(it) } ?: JSONObject()
  val locationInfo: JSONObject get() = panorama?.location?.let { info(it) } ?: JSONObject().put("panoramaId", JSONObject.NULL)

  fun orientationForPoint(x: Double, y: Double): JSONObject {
    val density = resources.displayMetrics.density
    val o = panorama?.pointToOrientation(Point((x * density).toInt(), (y * density).toInt())) ?: return JSONObject()
    return GOut.obj("heading" to o.bearing, "pitch" to o.tilt)
  }

  fun pointForOrientation(heading: Double, pitch: Double): JSONObject {
    val density = resources.displayMetrics.density
    val p = panorama?.orientationToPoint(StreetViewPanoramaOrientation(pitch.toFloat(), heading.toFloat())) ?: return JSONObject()
    return GOut.obj("x" to p.x / density, "y" to p.y / density)
  }

  fun resume() {
    if (resumed) return
    resumed = true
    panoramaView.onStart()
    panoramaView.onResume()
  }

  fun pause() {
    if (!resumed) return
    resumed = false
    panoramaView.onPause()
    panoramaView.onStop()
  }

  fun destroy() {
    pause()
    panoramaView.onDestroy()
  }

  companion object {
    fun info(location: StreetViewPanoramaLocation): JSONObject {
      val links = JSONArray()
      location.links?.forEach { links.put(GOut.obj("heading" to it.bearing, "panoramaId" to it.panoId)) }
      return GOut.obj("panoramaId" to location.panoId, "latitude" to location.position.latitude,
        "longitude" to location.position.longitude, "links" to links)
    }

    fun camera(c: StreetViewPanoramaCamera) = GOut.obj("heading" to c.bearing, "pitch" to c.tilt, "zoom" to c.zoom)

    fun options(args: GJson): StreetViewPanoramaOptions? {
      val options = StreetViewPanoramaOptions()
      val source = if (args["source"].string == "outdoor") StreetViewSource.OUTDOOR else StreetViewSource.DEFAULT
      val id = args["panoramaId"].string
      val position = args.latLng
      when {
        id != null -> options.panoramaId(id)
        position != null -> options.position(position, args["radius"].double(50.0).toInt(), source)
        else -> return null
      }
      return options
    }
  }
}

/** `streetView.open`: shows the panorama nearest a point (or by ID). */
internal fun GoogleMapEngine.openStreetView(args: GJson, completion: (Result<JSONObject>) -> Unit) {
  val options = GoogleStreetView.options(args)
    ?: return completion(Result.failure(IllegalArgumentException("Google Maps: streetView.open needs latitude and longitude, or panoramaId")))
  closeStreetView()
  val street = GoogleStreetView(context, this, options, args) { result ->
    if (result.isFailure) closeStreetView()
    completion(result)
  }
  streetView = street
  val host: ViewGroup = if (args["presentation"].string == "fullScreen") {
    activity()?.findViewById(android.R.id.content) ?: (view as ViewGroup)
  } else view as ViewGroup
  host.addView(street, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
  street.resume()
}

internal fun GoogleMapEngine.closeStreetView() {
  val street = streetView ?: return
  streetView = null
  (street.parent as? ViewGroup)?.removeView(street)
  street.destroy()
  emit("streetViewClose")
}

/** Whether Google has a panorama near a point: asks a hidden panorama. */
internal fun GoogleMapEngine.streetViewCoverage(args: GJson, completion: (JSONObject?) -> Unit) {
  val options = GoogleStreetView.options(args) ?: return completion(null)
  val probe = StreetViewPanoramaView(context, options)
  probe.onCreate(null)
  var done = false
  fun finish(result: JSONObject?) {
    if (done) return
    done = true
    probe.onDestroy()
    completion(result)
  }
  probe.getStreetViewPanoramaAsync { pano ->
    pano.setOnStreetViewPanoramaChangeListener { location -> finish(location?.let { GoogleStreetView.info(it) }) }
  }
  main.postDelayed({ finish(null) }, 10_000)
}

internal fun GoogleMapEngine.activity(): Activity? {
  (context as? ReactContext)?.currentActivity?.let { return it }
  var c: Context? = context
  while (c is ContextWrapper) {
    if (c is Activity) return c
    c = c.baseContext
  }
  return null
}
