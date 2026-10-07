package com.munimmaps.engines.google

import android.graphics.Color
import android.graphics.Point
import com.google.android.gms.maps.model.BitmapDescriptorFactory
import com.google.android.gms.maps.model.ButtCap
import com.google.android.gms.maps.model.Cap
import com.google.android.gms.maps.model.CircleOptions
import com.google.android.gms.maps.model.CustomCap
import com.google.android.gms.maps.model.Dash
import com.google.android.gms.maps.model.Dot
import com.google.android.gms.maps.model.Gap
import com.google.android.gms.maps.model.GroundOverlayOptions
import com.google.android.gms.maps.model.JointType
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.PatternItem
import com.google.android.gms.maps.model.PolygonOptions
import com.google.android.gms.maps.model.PolylineOptions
import com.google.android.gms.maps.model.RoundCap
import com.google.android.gms.maps.model.SpriteStyle
import com.google.android.gms.maps.model.SquareCap
import com.google.android.gms.maps.model.StrokeStyle
import com.google.android.gms.maps.model.StyleSpan
import com.google.android.gms.maps.model.TextureStyle
import com.google.android.gms.maps.model.Tile
import com.google.android.gms.maps.model.TileOverlayOptions
import com.google.android.gms.maps.model.TileProvider
import com.google.maps.android.PolyUtil
import com.google.maps.android.SphericalUtil
import com.google.maps.android.heatmaps.Gradient
import com.google.maps.android.heatmaps.HeatmapTileProvider
import com.google.maps.android.heatmaps.WeightedLatLng
import com.margelo.nitro.munimmaps.LineCap
import com.margelo.nitro.munimmaps.LineJoin
import com.margelo.nitro.munimmaps.NativePolyline
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

// Polylines, polygons, circles, tile overlays, ground overlays and heatmaps
// on Google (Android), and hit-testing the shared shapes.

// MARK: Polylines

internal fun GoogleMapEngine.applyPolylines() {
  val map = map ?: return
  val wanted = polylines.map { it.id }.toSet()
  for (p in polylines) {
    val extras = options["polylines"][p.id]
    val points = trimmed(p.coordinates.map { LatLng(it.latitude, it.longitude) }, p.strokeStart, p.strokeEnd)
    val color = GJson.parseColor(p.strokeColor) ?: Color.rgb(10, 132, 255)
    val line = gmsPolylines[p.id] ?: map.addPolyline(PolylineOptions().add(LatLng(0.0, 0.0))).also { gmsPolylines[p.id] = it }
    line.points = points
    line.color = color
    line.width = (extras["width"].double ?: p.strokeWidth).toFloat() * density.toFloat()
    line.isGeodesic = p.geodesic
    line.zIndex = p.zIndex.toFloat()
    line.isClickable = false
    line.tag = p.id
    line.jointType = jointType(extras["jointType"].string, p.lineJoin)
    line.startCap = cap(extras["startCap"], p.lineCap)
    line.endCap = cap(extras["endCap"], p.lineCap)
    line.pattern = pattern(extras["pattern"], p.dashPattern)
    line.spans = spans(p, points, color, extras)
  }
  for (id in gmsPolylines.keys.toList()) if (id !in wanted) gmsPolylines.remove(id)?.remove()
}

private fun GoogleMapEngine.spans(p: NativePolyline, points: List<LatLng>, color: Int, extras: GJson): List<StyleSpan> {
  val custom = extras["spans"].array
  if (custom.isNotEmpty()) {
    return custom.map { span ->
      val from = span["color"].color ?: color
      val builder = span["toColor"].color?.let { StrokeStyle.gradientBuilder(from, it) } ?: StrokeStyle.colorBuilder(from)
      span["stampImageUri"].string?.let { uri -> photos[uri]?.let { builder.stamp(TextureStyle.newBuilder(BitmapDescriptorFactory.fromBitmap(it)).build()) } ?: loadPhoto(uri) }
      StyleSpan(builder.build(), span["segments"].double(1.0))
    }
  }
  extras["stamp"]["imageUri"].string?.let { uri ->
    val bitmap = photos[uri] ?: run { loadPhoto(uri); null } ?: return emptyList()
    val descriptor = BitmapDescriptorFactory.fromBitmap(bitmap)
    val style = if (extras["stamp"]["kind"].string == "sprite") {
      StrokeStyle.transparentColorBuilder().stamp(SpriteStyle.newBuilder(descriptor).build()).build()
    } else {
      StrokeStyle.colorBuilder(color).stamp(TextureStyle.newBuilder(descriptor).build()).build()
    }
    return listOf(StyleSpan(style))
  }
  val colors = p.strokeColors.split(",").mapNotNull { GJson.parseColor(it.trim()) }
  if (colors.size >= 2 && points.size >= 2) {
    val given = p.strokeColorLocations.split(",").mapNotNull { it.trim().toDoubleOrNull() }
    val stops = if (given.size == colors.size) given else colors.indices.map { it.toDouble() / (colors.size - 1) }
    val lengths = mutableListOf(0.0)
    for (i in 1 until points.size) lengths.add(lengths[i - 1] + SphericalUtil.computeDistanceBetween(points[i - 1], points[i]))
    val total = maxOf(1e-9, lengths.last())
    return (0 until points.size - 1).map { i ->
      StyleSpan(StrokeStyle.gradientBuilder(colorAt(lengths[i] / total, colors, stops), colorAt(lengths[i + 1] / total, colors, stops)).build(), 1.0)
    }
  }
  return emptyList()
}

private fun colorAt(f: Double, colors: List<Int>, stops: List<Double>): Int {
  if (f <= stops[0]) return colors[0]
  for (i in 1 until colors.size) if (f <= stops[i]) {
    val t = ((f - stops[i - 1]) / maxOf(1e-9, stops[i] - stops[i - 1])).toFloat()
    val a = colors[i - 1]
    val b = colors[i]
    return Color.argb(
      (Color.alpha(a) + (Color.alpha(b) - Color.alpha(a)) * t).toInt(),
      (Color.red(a) + (Color.red(b) - Color.red(a)) * t).toInt(),
      (Color.green(a) + (Color.green(b) - Color.green(a)) * t).toInt(),
      (Color.blue(a) + (Color.blue(b) - Color.blue(a)) * t).toInt(),
    )
  }
  return colors.last()
}

/** `google.…pattern` (`[{ type, length }]`, lengths in points) or `dashPattern`. */
internal fun GoogleMapEngine.pattern(items: GJson, dash: String): List<PatternItem>? {
  val list = items.array
  if (list.isNotEmpty()) {
    return list.map {
      val length = (it["length"].double(10.0) * density).toFloat()
      when (it["type"].string) {
        "gap" -> Gap(length)
        "dot" -> Dot()
        else -> Dash(length)
      }
    }
  }
  val values = dash.split(",").mapNotNull { it.trim().toDoubleOrNull() }
  if (values.isEmpty() || values.none { it > 0 }) return null
  val even = if (values.size % 2 == 0) values else values + values
  return even.mapIndexed { i, v -> if (i % 2 == 0) Dash((v * density).toFloat()) else Gap((v * density).toFloat()) }
}

internal fun jointType(name: String?, join: LineJoin): Int = when (name) {
  "miter" -> JointType.DEFAULT
  "bevel" -> JointType.BEVEL
  "round" -> JointType.ROUND
  else -> when (join) {
    LineJoin.MITER -> JointType.DEFAULT
    LineJoin.BEVEL -> JointType.BEVEL
    LineJoin.ROUND -> JointType.ROUND
  }
}

private fun GoogleMapEngine.cap(json: GJson, lineCap: LineCap): Cap {
  json["imageUri"].string?.let { uri ->
    val bitmap = photos[uri] ?: run { loadPhoto(uri); null }
    if (bitmap != null) return CustomCap(BitmapDescriptorFactory.fromBitmap(bitmap), json["refWidth"].double(10.0).toFloat())
  }
  return when (json.string ?: lineCap.name.lowercase()) {
    "butt" -> ButtCap()
    "square" -> SquareCap()
    else -> RoundCap()
  }
}

/** The part of a line between two fractions of its length. */
internal fun trimmed(points: List<LatLng>, start: Double, end: Double): List<LatLng> {
  if (points.size < 2 || (start <= 0 && end >= 1)) return points
  val lengths = mutableListOf(0.0)
  for (i in 1 until points.size) lengths.add(lengths[i - 1] + SphericalUtil.computeDistanceBetween(points[i - 1], points[i]))
  val total = lengths.last()
  if (total <= 0) return points
  val a = start.coerceIn(0.0, 1.0) * total
  val b = end.coerceIn(0.0, 1.0) * total
  if (b <= a) return emptyList()
  fun at(d: Double): LatLng {
    var i = 1
    while (i < lengths.size - 1 && lengths[i] < d) i++
    val span = lengths[i] - lengths[i - 1]
    return SphericalUtil.interpolate(points[i - 1], points[i], if (span > 0) (d - lengths[i - 1]) / span else 0.0)
  }
  val out = mutableListOf(at(a))
  for (i in 1 until points.size - 1) if (lengths[i] > a && lengths[i] < b) out.add(points[i])
  out.add(at(b))
  return out
}

// MARK: Polygons and circles

internal fun GoogleMapEngine.applyPolygons() {
  val map = map ?: return
  val wanted = polygons.map { it.id }.toSet()
  for (p in polygons) {
    val extras = options["polygons"][p.id]
    val points = p.coordinates.map { LatLng(it.latitude, it.longitude) }
    if (points.size < 3) continue
    val polygon = gmsPolygons[p.id] ?: map.addPolygon(PolygonOptions().addAll(points)).also { gmsPolygons[p.id] = it }
    polygon.points = points
    polygon.holes = p.holes.map { ring -> ring.map { LatLng(it.latitude, it.longitude) } }.filter { it.size >= 3 }
    polygon.strokeColor = GJson.parseColor(p.strokeColor) ?: Color.TRANSPARENT
    polygon.fillColor = GJson.parseColor(p.fillColor) ?: Color.TRANSPARENT
    polygon.strokeWidth = p.strokeWidth.toFloat() * density.toFloat()
    polygon.isGeodesic = extras["geodesic"].bool(false)
    polygon.zIndex = p.zIndex.toFloat()
    polygon.isClickable = false
    polygon.strokeJointType = jointType(extras["strokeJointType"].string, p.lineJoin)
    polygon.strokePattern = pattern(extras["strokePattern"], p.dashPattern)
    polygon.tag = p.id
  }
  for (id in gmsPolygons.keys.toList()) if (id !in wanted) gmsPolygons.remove(id)?.remove()
}

internal fun GoogleMapEngine.applyCircles() {
  val map = map ?: return
  val wanted = circles.map { it.id }.toSet()
  for (c in circles) {
    val extras = options["circles"][c.id]
    val circle = gmsCircles[c.id] ?: map.addCircle(CircleOptions().center(LatLng(c.latitude, c.longitude)).radius(c.radius)).also { gmsCircles[c.id] = it }
    circle.center = LatLng(c.latitude, c.longitude)
    circle.radius = c.radius
    circle.strokeColor = GJson.parseColor(c.strokeColor) ?: Color.TRANSPARENT
    circle.fillColor = GJson.parseColor(c.fillColor) ?: Color.TRANSPARENT
    circle.strokeWidth = c.strokeWidth.toFloat() * density.toFloat()
    circle.zIndex = c.zIndex.toFloat()
    circle.isClickable = false
    circle.strokePattern = pattern(extras["strokePattern"], c.dashPattern)
    circle.tag = c.id
  }
  for (id in gmsCircles.keys.toList()) if (id !in wanted) gmsCircles.remove(id)?.remove()
}

// MARK: Hit testing

/** Metres per pixel at the camera target now. */
internal fun GoogleMapEngine.metersPerPixel(): Double {
  val map = map ?: return 1.0
  val view = mapView ?: return 1.0
  GoogleCamera.state(map, view, paddingPx(), density, false)?.let { return it.distance / it.focalLength }
  return 1 / GoogleCamera.pixelsPerMeter(map.cameraPosition.zoom.toDouble(), map.cameraPosition.target.latitude, density)
}

/** The topmost tappable shape under a point in pixels: id and kind. */
internal fun GoogleMapEngine.overlayHit(x: Double, y: Double): Pair<String, String>? {
  val map = map ?: return null
  val c = map.projection.fromScreenLocation(Point(x.toInt(), y.toInt()))
  val perPixel = metersPerPixel()
  var best: Triple<String, String, Double>? = null
  var bestOrder = -1
  fun consider(id: String, kind: String, z: Double, order: Int) {
    val b = best
    if (b == null || z > b.third || (z == b.third && order > bestOrder)) {
      best = Triple(id, kind, z)
      bestOrder = order
    }
  }
  polygons.forEachIndexed { i, p ->
    if (!p.tappable) return@forEachIndexed
    val ring = p.coordinates.map { LatLng(it.latitude, it.longitude) }
    val inHole = p.holes.any { hole -> PolyUtil.containsLocation(c, hole.map { LatLng(it.latitude, it.longitude) }, false) }
    if (PolyUtil.containsLocation(c, ring, false) && !inHole) consider(p.id, "polygon", p.zIndex, 1000 + i)
  }
  circles.forEachIndexed { i, ci ->
    if (ci.tappable && SphericalUtil.computeDistanceBetween(LatLng(ci.latitude, ci.longitude), c) <= ci.radius + 4 * density * perPixel) {
      consider(ci.id, "circle", ci.zIndex, 2000 + i)
    }
  }
  polylines.forEachIndexed { i, p ->
    if (!p.tappable) return@forEachIndexed
    val tolerance = (p.strokeWidth / 2 + 8) * density * perPixel
    if (PolyUtil.isLocationOnPath(c, p.coordinates.map { LatLng(it.latitude, it.longitude) }, p.geodesic, tolerance)) {
      consider(p.id, "polyline", p.zIndex, 3000 + i)
    }
  }
  return best?.let { it.first to it.second }
}

// MARK: Tile overlays

/** Tiles from a URL template (`{x}`, `{y}`, `{z}`, `{-y}`, `{quadkey}`, `{s}`), `file://` and paths included. */
class GoogleTemplateTileProvider(
  private val template: String,
  private val minZoom: Double,
  private val maxZoom: Double,
  private val tileSize: Int,
) : TileProvider {
  override fun getTile(x: Int, y: Int, zoom: Int): Tile? {
    if (minZoom > 0 && zoom < minZoom) return TileProvider.NO_TILE
    if (maxZoom > 0 && zoom > maxZoom) return TileProvider.NO_TILE
    val url = url(template, x, y, zoom)
    return try {
      val bytes = if (url.startsWith("/")) File(url).readBytes() else {
        val connection = URL(url).openConnection()
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        if (connection is HttpURLConnection && connection.responseCode !in 200..299) return TileProvider.NO_TILE
        connection.getInputStream().use { it.readBytes() }
      }
      Tile(tileSize, tileSize, bytes)
    } catch (_: Exception) {
      TileProvider.NO_TILE
    }
  }

  companion object {
    fun url(template: String, x: Int, y: Int, zoom: Int): String {
      var quadkey = ""
      if (template.contains("{quadkey}")) {
        for (i in zoom downTo 1) {
          val mask = 1 shl (i - 1)
          var digit = 0
          if (x and mask != 0) digit += 1
          if (y and mask != 0) digit += 2
          quadkey += digit
        }
      }
      val flipped = (1 shl zoom) - 1 - y
      return template.replace("{x}", "$x").replace("{-y}", "$flipped").replace("{y}", "$y").replace("{z}", "$zoom")
        .replace("{quadkey}", quadkey).replace("{s}", listOf("a", "b", "c")[(x + y).mod(3)])
    }
  }
}

internal fun GoogleMapEngine.applyTileOverlays() {
  val map = map ?: return
  val wanted = tileOverlays.map { it.id }.toSet()
  for (t in tileOverlays) {
    val extras = options["tileOverlays"][t.id]
    val tileSize = extras["tileSize"].double(256.0).toInt()
    val key = "${t.urlTemplate}|${t.minimumZoom}|${t.maximumZoom}|$tileSize"
    val existing = tileLayers[t.id]
    val overlay = if (existing != null && existing.first == key) existing.second else {
      existing?.second?.remove()
      map.addTileOverlay(TileOverlayOptions().tileProvider(GoogleTemplateTileProvider(t.urlTemplate, t.minimumZoom, t.maximumZoom, tileSize)))
        ?.also { tileLayers[t.id] = key to it } ?: continue
    }
    overlay.transparency = (1 - t.opacity).toFloat().coerceIn(0f, 1f)
    overlay.zIndex = t.zIndex.toFloat()
    overlay.fadeIn = extras["fadeIn"].bool(true)
  }
  for (id in tileLayers.keys.toList()) if (id !in wanted) tileLayers.remove(id)?.second?.remove()
}

/** Adds your own TileProvider under an id (Kotlin); `removeTileLayer` takes it off. */
fun GoogleMapEngine.addTileLayer(provider: TileProvider, id: String, zIndex: Float = 0f) {
  customTileLayers.remove(id)?.remove()
  map?.addTileOverlay(TileOverlayOptions().tileProvider(provider).zIndex(zIndex))?.let { customTileLayers[id] = it }
}

fun GoogleMapEngine.removeTileLayer(id: String) {
  customTileLayers.remove(id)?.remove()
}

internal fun GoogleMapEngine.clearTileCache(id: String?) {
  for ((key, value) in tileLayers) if (id == null || key == id) value.second.clearTileCache()
  for ((key, value) in customTileLayers) if (id == null || key == id) value.clearTileCache()
  for ((key, value) in heatmaps) if (id == null || key == id) value.second.clearTileCache()
}

// MARK: Ground overlays

internal fun GoogleMapEngine.applyGroundOverlays() {
  val collection = groundOverlayCollection ?: return
  val wanted = mutableSetOf<String>()
  for (item in options["groundOverlays"].array) {
    val id = item["id"].string ?: continue
    val uri = item["imageUri"].string ?: item["image"].string ?: continue
    wanted.add(id)
    val bitmap = photos[uri] ?: run { loadPhoto(uri); null } ?: continue
    val key = "ground:$id"
    if (groundOverlays[id] != null && overlayKeys[key] == item.toString()) continue
    overlayKeys[key] = item.toString()
    groundOverlays.remove(id)?.let { collection.remove(it) }
    val options = GroundOverlayOptions().image(BitmapDescriptorFactory.fromBitmap(bitmap))
    val bounds = item["bounds"].bounds
    val position = item["position"].latLng
    if (bounds != null) {
      options.positionFromBounds(bounds)
    } else if (position != null) {
      val width = item["width"].double(100.0).toFloat()
      val height = item["height"].double?.toFloat()
      if (height != null) options.position(position, width, height) else options.position(position, width)
      options.anchor(item["anchor"]["x"].double(0.5).toFloat(), item["anchor"]["y"].double(0.5).toFloat())
    } else continue
    options.bearing(item["bearing"].double(0.0).toFloat())
      .transparency((1 - item["opacity"].double(1 - item["transparency"].double(0.0))).toFloat().coerceIn(0f, 1f))
      .zIndex(item["zIndex"].double(0.0).toFloat())
      .clickable(item["tappable"].bool(false))
      .visible(item["visible"].bool(true))
    collection.addGroundOverlay(options)?.let {
      it.tag = id
      groundOverlays[id] = it
    }
  }
  for (id in groundOverlays.keys.toList()) if (id !in wanted) {
    overlayKeys.remove("ground:$id")
    groundOverlays.remove(id)?.let { collection.remove(it) }
  }
}

// MARK: Heatmaps

internal fun GoogleMapEngine.applyHeatmaps() {
  val map = map ?: return
  val wanted = mutableSetOf<String>()
  for (item in options["heatmaps"].array) {
    val id = item["id"].string ?: continue
    wanted.add(id)
    val key = "heatmap:$id"
    if (heatmaps[id] != null && overlayKeys[key] == item.toString()) continue
    overlayKeys[key] = item.toString()
    val data = item["points"].array.mapNotNull { p -> p.latLng?.let { WeightedLatLng(it, p["weight"].double(1.0)) } }
    if (data.isEmpty()) continue
    val builder = HeatmapTileProvider.Builder().weightedData(data)
      .radius(item["radius"].double(20.0).toInt().coerceIn(10, 50))
      .opacity(item["opacity"].double(0.7))
    item["maxIntensity"].double?.let { builder.maxIntensity(it) }
    val colors = item["gradient"]["colors"].array.mapNotNull { it.color }
    if (colors.size >= 2) {
      val given = item["gradient"]["startPoints"].array.mapNotNull { it.double?.toFloat() }
      val starts = if (given.size == colors.size) given else colors.indices.map { 0.2f + 0.8f * it / (colors.size - 1) }
      builder.gradient(Gradient(colors.toIntArray(), starts.toFloatArray(), item["gradient"]["colorMapSize"].double(256.0).toInt()))
    }
    heatmaps.remove(id)?.second?.remove()
    val provider = builder.build()
    map.addTileOverlay(TileOverlayOptions().tileProvider(provider).zIndex(item["zIndex"].double(0.0).toFloat()))?.let {
      heatmaps[id] = provider to it
    }
  }
  for (id in heatmaps.keys.toList()) if (id !in wanted) {
    overlayKeys.remove("heatmap:$id")
    heatmaps.remove(id)?.second?.remove()
  }
}

internal fun GoogleMapEngine.applyGoogleOverlays() {
  applyGroundOverlays()
  applyHeatmaps()
  applyDataLayers()
  applyFeatureLayers()
}
