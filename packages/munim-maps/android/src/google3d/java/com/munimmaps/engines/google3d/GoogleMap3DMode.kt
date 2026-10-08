package com.munimmaps.engines.google3d

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.View
import com.google.android.gms.maps3d.GoogleMap3D
import com.google.android.gms.maps3d.Map3DView
import com.google.android.gms.maps3d.OnMap3DViewReadyCallback
import com.google.android.gms.maps3d.model.AltitudeMode
import com.google.android.gms.maps3d.model.Camera
import com.google.android.gms.maps3d.model.FlyAroundOptions
import com.google.android.gms.maps3d.model.FlyToOptions
import com.google.android.gms.maps3d.model.Hole
import com.google.android.gms.maps3d.model.LatLngAltitude
import com.google.android.gms.maps3d.model.Map3DMode
import com.google.android.gms.maps3d.model.Marker
import com.google.android.gms.maps3d.model.MarkerOptions
import com.google.android.gms.maps3d.model.Model
import com.google.android.gms.maps3d.model.ModelOptions
import com.google.android.gms.maps3d.model.Orientation
import com.google.android.gms.maps3d.model.PinConfiguration
import com.google.android.gms.maps3d.model.Polygon
import com.google.android.gms.maps3d.model.PolygonOptions
import com.google.android.gms.maps3d.model.Polyline
import com.google.android.gms.maps3d.model.PolylineOptions
import com.google.android.gms.maps3d.model.Vector3D
import com.margelo.nitro.munimmaps.MapAltitudeReference
import com.margelo.nitro.munimmaps.MapCamera
import com.margelo.nitro.munimmaps.NativeMapModel
import com.margelo.nitro.munimmaps.NativeMarker
import com.margelo.nitro.munimmaps.NativePolygon
import com.margelo.nitro.munimmaps.NativePolyline
import com.munimmaps.engines.google.GJson
import com.munimmaps.engines.google.GOut
import com.munimmaps.engines.google.Google3DHost
import com.munimmaps.engines.google.Google3DMode
import com.munimmaps.models.ModelAssets
import java.io.File
import java.security.MessageDigest
import org.json.JSONObject
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan

/**
 * The Google engine's photorealistic 3D mode on the Maps 3D SDK for Android:
 * munim-maps' models as Google glTF models (`Model`), polylines, polygons
 * and markers as Google's own, the camera as Google's (`range` = munim-maps'
 * camera distance). Needs the Map Tiles API and the Maps 3D SDK for Android
 * turned on for the key.
 */
class GoogleMap3DMode(
  private val context: Context,
  private val host: Google3DHost,
  initialCamera: MapCamera?,
) : Google3DMode {
  private val mapView = Map3DView(context)
  override val view: View get() = mapView
  private val main = Handler(Looper.getMainLooper())
  private var map: GoogleMap3D? = null
  private var options = GJson(null)
  private var pendingCamera: MapCamera? = initialCamera
  private var models: Array<NativeMapModel> = emptyArray()
  private var markers: Array<NativeMarker> = emptyArray()
  private var polylines: Array<NativePolyline> = emptyArray()
  private var polygons: Array<NativePolygon> = emptyArray()
  private val nativeModels = mutableMapOf<String, Pair<String, Model>>()
  private val nativeMarkers = mutableMapOf<String, Marker>()
  private val nativePolylines = mutableMapOf<String, Polyline>()
  private val nativePolygons = mutableMapOf<String, Polygon>()
  private val modelUrls = mutableMapOf<String, String>()
  /** Model heights in metres from their glTF POSITION bounds, for `screenSize`. */
  private val modelHeights = mutableMapOf<String, Double>()
  /** The scale last given to each screen-sized model. */
  private val lastScales = mutableMapOf<String, Double>()
  private var destroyed = false
  private var resumed = false
  private var lastCamera: Camera? = null
  private var mapReady = false

  /**
   * The camera as munim-maps knows it. The Maps 3D SDK (0.2.0) reports
   * gestures through its camera listener and `getCamera()`, but not cameras
   * set in code (`setCamera`, `flyCameraTo`): `getCamera()` keeps the camera
   * of the last gesture (at first, its whole-Earth default). So the camera
   * set in code is kept here (a flight's destination as soon as it starts),
   * and a gesture replaces it.
   */
  private var knownCamera: Camera? = null

  private val motionTick = object : Runnable {
    override fun run() {
      if (destroyed) return
      moveModels()
      if (models.any { it.motion.isNotEmpty() }) main.postDelayed(this, 50)
    }
  }

  init {
    mapView.onCreate(null)
    mapView.getMap3DViewAsync(object : OnMap3DViewReadyCallback {
      override fun onMap3DViewReady(googleMap3D: GoogleMap3D) {
        if (destroyed) return
        map = googleMap3D
        // Called with the rendering progress (0-100) every time the scene
        // loads more; the map is ready once. The camera and objects given to
        // the SDK before this point are lost (it starts on its whole-Earth
        // camera with an empty scene), so they are applied here.
        googleMap3D.setOnMapReadyListener {
          if (mapReady || destroyed) return@setOnMapReadyListener
          mapReady = true
          pendingCamera?.let { setCamera(it, 0.0) }
          pendingCamera = null
          applyModels()
          applyMarkers()
          applyPolylines()
          applyPolygons()
          host.ready()
        }
        googleMap3D.setCameraChangedListener { camera ->
          lastCamera = camera
          // Before the map is ready this is the SDK's default camera, not ours.
          if (mapReady) knownCamera = camera
          host.cameraChanged(munim(camera), false)
          updateScales()
        }
        googleMap3D.setOnMapSteadyListener { steady ->
          host.emit("map3dSteady", GOut.obj("steady" to steady))
          if (steady) (knownCamera ?: lastCamera)?.let { host.cameraChanged(munim(it), true) }
        }
        googleMap3D.setCameraAnimationEndListener {
          knownCamera?.let { host.cameraChanged(munim(it), true) }
          host.emit("cameraAnimationEnd", GOut.obj())
        }
        googleMap3D.setMap3DClickListener { location, placeId ->
          host.press(location.latitude, location.longitude, placeId)
        }
        applyOptions()
      }

      override fun onError(error: Exception) {
        host.error("the Maps 3D SDK failed to start: ${error.message} (it needs current Google Play services, which download its module, and the Map Tiles API and the Maps 3D SDK for Android on the key)")
      }
    })
  }

  // MARK: Lifecycle

  override fun resume() {
    if (resumed || destroyed) return
    resumed = true
    mapView.onStart()
    mapView.onResume()
  }

  override fun pause() {
    if (!resumed || destroyed) return
    resumed = false
    mapView.onPause()
    mapView.onStop()
  }

  override fun destroy() {
    if (destroyed) return
    pause()
    destroyed = true
    main.removeCallbacks(motionTick)
    mapView.onDestroy()
  }

  // MARK: Options

  override fun setOptions(options: GJson) {
    this.options = options
    applyOptions()
    applyModels()
  }

  private fun applyOptions() {
    val map = map ?: return
    val mode = if (options["mapType"].string == "satellite" || options["map3dMode"].string == "satellite") Map3DMode.SATELLITE
    else Map3DMode.HYBRID
    if (map.getMapMode() != mode) map.setMapMode(mode)
  }

  // MARK: Camera

  private fun munim(c: Camera): MapCamera {
    val center = c.center ?: LatLngAltitude(0.0, 0.0, 0.0)
    return MapCamera(center.latitude, center.longitude, c.range ?: 1000.0, c.tilt ?: 0.0, c.heading ?: 0.0)
  }

  private fun google(c: MapCamera, altitude: Double = 0.0): Camera =
    Camera(LatLngAltitude(c.latitude, c.longitude, altitude), c.heading, c.pitch.coerceIn(0.0, 90.0), 0.0, maxOf(1.0, c.distance))

  override fun setCamera(camera: MapCamera, durationMs: Double) {
    val map = map
    if (map == null || !mapReady) {
      pendingCamera = camera
      return
    }
    moveCamera(map, google(camera), durationMs.toLong())
  }

  /** Moves Google's camera (a flight when `durationMs` > 0) and remembers where to. */
  private fun moveCamera(map: GoogleMap3D, camera: Camera, durationMs: Long) {
    if (durationMs > 0) map.flyCameraTo(FlyToOptions(camera, durationMs)) else map.setCamera(camera)
    knownCamera = camera
    updateScales()
    // A flight reports its end camera when the animation ends.
    if (durationMs <= 0) host.cameraChanged(munim(camera), true)
  }

  /** The camera now: the one set in code or by the last gesture (see [knownCamera]). */
  private fun currentCamera(map: GoogleMap3D): Camera? = knownCamera ?: map.getCamera()

  override fun getCamera(): MapCamera? =
    pendingCamera ?: map?.let { currentCamera(it) }?.let { munim(it) }

  // MARK: Models (Google glTF models)

  override fun setModels(models: Array<NativeMapModel>) {
    this.models = models
    applyModels()
  }

  /** A URL Google can load: http(s) as is, anything else copied to a file. */
  private fun modelUrl(uri: String, completion: (String?) -> Unit) {
    if (uri.startsWith("file://")) return completion(uri)
    modelUrls[uri]?.let { return completion(it) }
    ModelAssets.load(context, uri) { result ->
      val bytes = result.getOrNull() ?: return@load completion(null)
      glbHeight(bytes)?.let { modelHeights[uri] = it }
      val name = MessageDigest.getInstance("SHA-1").digest(uri.toByteArray()).joinToString("") { "%02x".format(it) }
      val file = File(context.cacheDir, "munim-maps-3d-$name.glb")
      if (!file.exists()) file.writeBytes(bytes)
      val url = "file://${file.absolutePath}"
      modelUrls[uri] = url
      completion(url)
    }
  }

  private fun position(m: NativeMapModel, latitude: Double, longitude: Double, altitude: Double) =
    LatLngAltitude(latitude, longitude, altitude)

  private fun altitudeMode(m: NativeMapModel) =
    if (m.altitudeReference == MapAltitudeReference.SEA) AltitudeMode.ABSOLUTE else AltitudeMode.RELATIVE_TO_GROUND

  /**
   * Google's Maps 3D SDK reads glTF files Z-up and turns a model's +Z to its
   * heading; munim-maps' models (like every glTF) are Y-up and face -Z. So
   * they are stood up (tilt -90) and turned 180°, as on iOS: without this the
   * bus stood on its tail and the balloon lay on its side (checked on a Galaxy).
   */
  private fun orientation(heading: Double) = Orientation((heading + 180.0).mod(360.0), -90.0, 0.0)

  /**
   * `scale` × `google.modelScale`, and for `screenSize` the scale that makes
   * the model that many points tall at its distance from Google's camera
   * (35° vertical field of view), as on iOS and in the 3D layer.
   */
  private fun scale(m: NativeMapModel, latitude: Double = m.latitude, longitude: Double = m.longitude,
                    altitude: Double = m.altitude): Double {
    var scale = options["modelScale"].double(1.0) * (if (m.scale > 0) m.scale else 1.0)
    val height = modelHeights[m.uri] ?: return scale
    val c = knownCamera ?: lastCamera ?: return scale
    val viewPoints = mapView.height / context.resources.displayMetrics.density
    if (m.screenSize <= 0 || height <= 0 || viewPoints <= 0) return scale
    val center = c.center ?: return scale
    val tilt = Math.toRadians(c.tilt ?: 0.0)
    val heading = Math.toRadians(c.heading ?: 0.0)
    val range = c.range ?: 1000.0
    val back = range * sin(tilt)
    val metresPerDegree = 111_320.0
    val north = (latitude - center.latitude) * metresPerDegree
    val east = (longitude - center.longitude) * metresPerDegree * cos(Math.toRadians(center.latitude))
    val eyeNorth = -back * cos(heading)
    val eyeEast = -back * sin(heading)
    val eyeUp = range * cos(tilt)
    val dn = north - eyeNorth
    val de = east - eyeEast
    val du = altitude - eyeUp
    val depth = max(1.0, sqrt(dn * dn + de * de + du * du))
    val metresPerPoint = 2 * depth * tan(Math.toRadians(35.0) / 2) / viewPoints
    scale *= m.screenSize * metresPerPoint / height
    return scale
  }

  /**
   * Screen-sized models follow the camera's distance (on camera changes).
   * The Maps 3D SDK (0.2.0) keeps drawing a model at the scale it was added
   * with (setting `scale` later changes nothing on screen, checked on a
   * Galaxy), so a model whose scale changes is added again.
   */
  private fun updateScales() {
    val map = map?.takeIf { mapReady } ?: return
    if (models.none { it.screenSize > 0 }) return
    for (m in models) {
      if (m.screenSize <= 0) continue
      val (key, model) = nativeModels[m.id] ?: continue
      val s = scale(m)
      val old = lastScales[m.id]
      if (old != null && kotlin.math.abs(s / max(old, 1e-9) - 1) < 0.03) continue
      val url = model.url ?: continue
      val position = model.position ?: position(m, m.latitude, m.longitude, m.altitude)
      val orientation = model.orientation ?: orientation(m.heading)
      model.remove()
      val added = map.addModel(ModelOptions(m.id, position, url, altitudeMode(m), Vector3D(s, s, s), orientation))
      added.setClickListener { host.modelPressed(m.id) }
      nativeModels[m.id] = key to added
      lastScales[m.id] = s
    }
  }

  /** The height of a GLB's meshes (glTF is Y-up), or null if it can't be read. */
  private fun glbHeight(bytes: ByteArray): Double? = runCatching {
    if (bytes.size < 20 || bytes[0] != 'g'.code.toByte() || bytes[1] != 'l'.code.toByte()) return null
    val length = (bytes[12].toInt() and 0xff) or ((bytes[13].toInt() and 0xff) shl 8) or
      ((bytes[14].toInt() and 0xff) shl 16) or ((bytes[15].toInt() and 0xff) shl 24)
    val gltf = JSONObject(String(bytes, 20, length, Charsets.UTF_8))
    val accessors = gltf.optJSONArray("accessors") ?: return null
    val meshes = gltf.optJSONArray("meshes") ?: return null
    var lo = Double.POSITIVE_INFINITY
    var hi = Double.NEGATIVE_INFINITY
    for (i in 0 until meshes.length()) {
      val primitives = meshes.getJSONObject(i).optJSONArray("primitives") ?: continue
      for (j in 0 until primitives.length()) {
        val index = primitives.getJSONObject(j).optJSONObject("attributes")?.optInt("POSITION", -1) ?: -1
        if (index < 0) continue
        val accessor = accessors.getJSONObject(index)
        val min = accessor.optJSONArray("min") ?: continue
        val maxs = accessor.optJSONArray("max") ?: continue
        lo = minOf(lo, min.getDouble(1))
        hi = maxOf(hi, maxs.getDouble(1))
      }
    }
    if (hi > lo) hi - lo else null
  }.getOrNull()

  private fun applyModels() {
    val map = map?.takeIf { mapReady } ?: return
    val wanted = models.filter { it.visible && it.uri.isNotEmpty() }.associateBy { it.id }
    for (id in nativeModels.keys.toList()) if (id !in wanted) nativeModels.remove(id)?.second?.remove()
    if (models.any { it.visible && it.uri.isEmpty() }) {
      host.error("Google 3D draws glTF models only; built-in shapes, pictures and labels need the 2D map with the munim overlay")
    }
    for ((id, m) in wanted) {
      val key = "${m.uri}|${m.latitude}|${m.longitude}|${m.altitude}|${m.heading}|${m.scale}|${m.screenSize}|${m.altitudeReference}"
      val existing = nativeModels[id]
      if (existing != null && existing.first == key) continue
      if (existing != null && existing.second.url == modelUrls[m.uri]) {
        val s = scale(m)
        if (lastScales[id]?.let { kotlin.math.abs(s / max(it, 1e-9) - 1) < 1e-6 } == true &&
          existing.second.altitudeMode == altitudeMode(m)) {
          existing.second.position = position(m, m.latitude, m.longitude, m.altitude)
          existing.second.orientation = orientation(m.heading)
          nativeModels[id] = key to existing.second
          continue
        }
        existing.second.remove()
        lastScales[id] = s
        val model = map.addModel(ModelOptions(id, position(m, m.latitude, m.longitude, m.altitude), existing.second.url,
          altitudeMode(m), Vector3D(s, s, s), orientation(m.heading)))
        model.setClickListener { host.modelPressed(id) }
        nativeModels[id] = key to model
        continue
      }
      modelUrl(m.uri) { url ->
        if (url == null) return@modelUrl host.error("could not load the model ${m.uri}")
        if (destroyed || this.map !== map) return@modelUrl
        nativeModels.remove(id)?.second?.remove()
        val s = scale(m)
        lastScales[id] = s
        val model = map.addModel(ModelOptions(id, position(m, m.latitude, m.longitude, m.altitude), url,
          altitudeMode(m), Vector3D(s, s, s), orientation(m.heading)))
        model.setClickListener { host.modelPressed(id) }
        nativeModels[id] = key to model
      }
    }
    main.removeCallbacks(motionTick)
    if (models.any { it.motion.isNotEmpty() }) main.post(motionTick)
  }

  /** Models with `motion` move along their keyframes on the shared clock. */
  private fun moveModels() {
    val now = System.currentTimeMillis() / 1000.0
    for (m in models) {
      if (m.motion.isEmpty()) continue
      val model = nativeModels[m.id]?.second ?: continue
      val frames = m.motion
      var t = now - m.motionStart
      val span = frames.last().t - frames.first().t
      if (m.motionLoop && span > 0) t = frames.first().t + (t - frames.first().t).mod(span)
      val (lat, lng, alt, heading) = when {
        t <= frames.first().t -> frames.first().let { listOf(it.latitude, it.longitude, it.altitude, it.heading) }
        t >= frames.last().t -> frames.last().let { listOf(it.latitude, it.longitude, it.altitude, it.heading) }
        else -> {
          var i = 1
          while (i < frames.size - 1 && frames[i].t < t) i++
          val a = frames[i - 1]
          val b = frames[i]
          val f = (t - a.t) / maxOf(1e-9, b.t - a.t)
          val turn = ((b.heading - a.heading) % 360 + 540) % 360 - 180
          listOf(a.latitude + (b.latitude - a.latitude) * f, a.longitude + (b.longitude - a.longitude) * f,
            a.altitude + (b.altitude - a.altitude) * f, a.heading + turn * f)
        }
      }
      model.position = position(m, lat, lng, alt)
      model.orientation = orientation(heading)
    }
  }

  // MARK: Markers, polylines, polygons

  override fun setMarkers(markers: Array<NativeMarker>) {
    this.markers = markers
    applyMarkers()
  }

  private fun applyMarkers() {
    val map = map?.takeIf { mapReady } ?: return
    nativeMarkers.values.forEach { it.remove() }
    nativeMarkers.clear()
    for (m in markers) {
      if (!m.visible) continue
      val options = MarkerOptions()
      options.id = m.id
      options.position = LatLngAltitude(m.latitude, m.longitude, 0.0)
      options.altitudeMode = AltitudeMode.CLAMP_TO_GROUND
      options.label = m.title
      options.isExtruded = false
      options.isDrawnWhenOccluded = true
      options.zIndex = m.zIndex.toInt()
      GJson.parseColor(m.color)?.let { color ->
        options.setStyle(PinConfiguration.builder().setBackgroundColor(color).build())
      }
      val marker = map.addMarker(options) ?: continue
      marker.setClickListener { host.markerPressed(m.id) }
      nativeMarkers[m.id] = marker
    }
  }

  override fun setPolylines(polylines: Array<NativePolyline>) {
    this.polylines = polylines
    applyPolylines()
  }

  private fun applyPolylines() {
    val map = map?.takeIf { mapReady } ?: return
    nativePolylines.values.forEach { it.remove() }
    nativePolylines.clear()
    for (p in polylines) {
      if (p.coordinates.size < 2) continue
      val options = PolylineOptions()
      options.id = p.id
      options.path = p.coordinates.map { LatLngAltitude(it.latitude, it.longitude, 0.0) }
      options.altitudeMode = AltitudeMode.CLAMP_TO_GROUND
      options.strokeColor = GJson.parseColor(p.strokeColor) ?: 0xFF0A84FF.toInt()
      options.strokeWidth = p.strokeWidth
      options.geodesic = p.geodesic
      options.zIndex = p.zIndex.toInt()
      options.drawsOccludedSegments = true
      nativePolylines[p.id] = map.addPolyline(options)
    }
  }

  override fun setPolygons(polygons: Array<NativePolygon>) {
    this.polygons = polygons
    applyPolygons()
  }

  private fun applyPolygons() {
    val map = map?.takeIf { mapReady } ?: return
    nativePolygons.values.forEach { it.remove() }
    nativePolygons.clear()
    for (p in polygons) {
      if (p.coordinates.size < 3) continue
      val options = PolygonOptions()
      options.id = p.id
      options.path = p.coordinates.map { LatLngAltitude(it.latitude, it.longitude, 0.0) }
      options.innerPaths = p.holes.map { ring -> Hole(ring.map { LatLngAltitude(it.latitude, it.longitude, 0.0) }) }
      options.altitudeMode = AltitudeMode.CLAMP_TO_GROUND
      options.fillColor = GJson.parseColor(p.fillColor) ?: 0x330A84FF
      options.strokeColor = GJson.parseColor(p.strokeColor) ?: 0xFF0A84FF.toInt()
      options.strokeWidth = p.strokeWidth
      options.zIndex = p.zIndex.toInt()
      options.drawsOccludedSegments = true
      nativePolygons[p.id] = map.addPolygon(options)
    }
  }

  // MARK: Commands

  override fun command(name: String, args: GJson, completion: (Result<String>) -> Unit): Boolean {
    val map = map
    if (map == null || !mapReady) {
      completion(Result.failure(IllegalStateException("Google Maps: the 3D map is not ready yet")))
      return true
    }
    fun camera(json: GJson): Camera {
      val current = currentCamera(map)
      val center = current?.center ?: LatLngAltitude(0.0, 0.0, 0.0)
      return Camera(
        LatLngAltitude(json["latitude"].double(center.latitude), json["longitude"].double(center.longitude), json["altitude"].double(center.altitude)),
        json["heading"].double(current?.heading ?: 0.0), json["tilt"].double(current?.tilt ?: 60.0),
        json["roll"].double(current?.roll ?: 0.0), json["range"].double(current?.range ?: 1000.0),
      )
    }
    when (name) {
      "flyTo" -> moveCamera(map, camera(args), maxOf(1L, args["duration"].double(2000.0).toLong()))
      "flyAround" -> {
        val around = camera(args)
        map.flyCameraAround(FlyAroundOptions(around, args["duration"].double(10000.0).toLong(), args["rounds"].double(1.0)))
        knownCamera = around
      }
      "stopCameraAnimation" -> map.stopCameraAnimation()
      "getCamera3d" -> {
        val c = currentCamera(map)
        val center = c?.center
        completion(Result.success(GOut.obj("latitude" to center?.latitude, "longitude" to center?.longitude,
          "altitude" to center?.altitude, "heading" to c?.heading, "tilt" to c?.tilt, "roll" to c?.roll, "range" to c?.range).toString()))
        return true
      }
      "setCamera3d" -> moveCamera(map, camera(args), 0)
      else -> return false
    }
    completion(Result.success("null"))
    return true
  }
}
