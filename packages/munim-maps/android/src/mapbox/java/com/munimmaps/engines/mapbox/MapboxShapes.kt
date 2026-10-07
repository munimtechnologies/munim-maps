package com.munimmaps.engines.mapbox

import com.mapbox.geojson.Feature
import com.mapbox.geojson.LineString
import com.mapbox.geojson.Point
import com.mapbox.geojson.Polygon
import com.mapbox.maps.GeoJSONSourceData
import com.mapbox.maps.LayerPosition
import com.margelo.nitro.munimmaps.LineCap
import com.margelo.nitro.munimmaps.LineJoin
import com.margelo.nitro.munimmaps.NativeCircle
import com.margelo.nitro.munimmaps.NativePolygon
import com.margelo.nitro.munimmaps.NativePolyline
import com.margelo.nitro.munimmaps.NativeTileOverlay
import com.margelo.nitro.munimmaps.OverlayLevel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Polylines, polygons, circles and tile overlays on Mapbox.
 *
 * Each shape is its own GeoJSON source (raster source for tile overlays)
 * with its own layers, rather than one annotation manager per kind: that
 * gives every shape its own z-order (`zIndex` across kinds, like MapKit),
 * its own slot (`level`: Standard's `middle` above roads, `top` above
 * labels), `line-gradient` (needs `lineMetrics` on the source) and
 * `strokeStart` / `strokeEnd` trimming. Updates are diffed: data changes go
 * through `setStyleGeoJSONSourceData`, paint changes through
 * `setStyleLayerProperties`, so animating a line does not re-create it.
 *
 * Tile overlays with `replacesMap` go in the `top` slot (over the basemap,
 * its labels and 3D buildings), and every other shape follows them there so
 * it stays visible over the new base map. Styles without slots get the same
 * order with layer positions (below the first label layer for `aboveRoads`).
 *
 * Taps are hit-tested in screen space ([hit]), so `overlayAtPoint` answers
 * synchronously.
 */
internal class MapboxShapes(private val engine: MapboxMapEngine) {
  private var polylines: Array<NativePolyline> = emptyArray()
  private var polygons: Array<NativePolygon> = emptyArray()
  private var circles: Array<NativeCircle> = emptyArray()
  private var tiles: Array<NativeTileOverlay> = emptyArray()

  private class Shape(
    val key: String,
    val id: String,
    val kind: String,
    val z: Double,
    val order: Int,
    val source: JSONObject,
    val layers: List<JSONObject>,
    val tappable: Boolean,
    /** Screen hit testing: a line (with its half-width in points) or rings. */
    val line: List<Point>? = null,
    val halfWidth: Double = 0.0,
    val rings: List<List<Point>>? = null,
  )

  private val applied = LinkedHashMap<String, Shape>()
  private var current: List<Shape> = emptyList()
  private var syncPosted = false

  fun setPolylines(value: Array<NativePolyline>) {
    polylines = value
    scheduleSync()
  }

  fun setPolygons(value: Array<NativePolygon>) {
    polygons = value
    scheduleSync()
  }

  fun setCircles(value: Array<NativeCircle>) {
    circles = value
    scheduleSync()
  }

  fun setTileOverlays(value: Array<NativeTileOverlay>) {
    tiles = value
    scheduleSync()
  }

  /** A style load dropped every runtime source and layer. */
  fun styleLoaded() {
    applied.clear()
    sync()
  }

  private fun scheduleSync() {
    if (syncPosted) return
    syncPosted = true
    engine.main.post {
      syncPosted = false
      if (!engine.destroyed) sync()
    }
  }

  // Building the desired shapes

  private fun slot(level: OverlayLevel, replacing: Boolean): String =
    if (replacing || level == OverlayLevel.ABOVELABELS) "top" else "middle"

  private fun cap(cap: LineCap) = when (cap) {
    LineCap.ROUND -> "round"
    LineCap.BUTT -> "butt"
    LineCap.SQUARE -> "square"
  }

  private fun join(join: LineJoin) = when (join) {
    LineJoin.ROUND -> "round"
    LineJoin.BEVEL -> "bevel"
    LineJoin.MITER -> "miter"
  }

  /** `10,5` in points to `line-dasharray` in line widths. */
  private fun dashes(pattern: String, width: Double): JSONArray? {
    val values = pattern.split(',', ' ').mapNotNull { it.trim().toDoubleOrNull() }.filter { it >= 0 }
    if (values.isEmpty() || values.all { it == 0.0 }) return null
    val w = maxOf(0.5, width)
    return JSONArray().also { array -> values.forEach { array.put(it / w) } }
  }

  private fun geojson(feature: Feature, lineMetrics: Boolean = false): JSONObject = JSONObject()
    .put("type", "geojson")
    .put("data", MapboxJson.feature(feature))
    .apply { if (lineMetrics) put("lineMetrics", true) }

  private fun polyline(p: NativePolyline, index: Int, replacing: Boolean): Shape? {
    if (p.coordinates.size < 2) return null
    val points = if (p.geodesic) MapboxGeo.geodesic(p.coordinates.toList()) else MapboxGeo.points(p.coordinates)
    val key = "polyline:${p.id}"
    val layerId = "munim-polyline-${p.id}"
    val colors = MapboxColors.split(p.strokeColors)
    val start = p.strokeStart.coerceIn(0.0, 1.0)
    val end = p.strokeEnd.coerceIn(0.0, 1.0)
    val trimmed = start > 0.0 || end < 1.0
    val gradient = colors.size >= 2 || trimmed
    val paint = JSONObject().put("line-width", p.strokeWidth.coerceAtLeast(0.0))
    val color = MapboxColors.css(p.strokeColor, "rgba(10, 132, 255, 1)")
    if (gradient) {
      // line-progress based colour: the gradient stops, and transparent outside strokeStart...strokeEnd.
      val colorExpression: Any = if (colors.size >= 2) {
        val locations = p.strokeColorLocations.split(',').mapNotNull { it.trim().toDoubleOrNull() }
        val stops = JSONArray().put("interpolate").put(JSONArray().put("linear")).put(JSONArray().put("line-progress"))
        var last = -1.0
        colors.forEachIndexed { i, c ->
          var at = locations.getOrNull(i) ?: (i.toDouble() / (colors.size - 1))
          at = at.coerceIn(0.0, 1.0)
          if (at <= last) at = minOf(1.0, last + 1e-6)
          last = at
          stops.put(at).put(MapboxColors.css(c, color))
        }
        stops
      } else color
      val expression = if (trimmed) {
        JSONArray().put("case")
          .put(JSONArray().put("all")
            .put(JSONArray().put(">=").put(JSONArray().put("line-progress")).put(start))
            .put(JSONArray().put("<=").put(JSONArray().put("line-progress")).put(end)))
          .put(colorExpression)
          .put("rgba(0, 0, 0, 0)")
      } else colorExpression
      paint.put("line-gradient", expression)
    } else {
      paint.put("line-color", color)
      dashes(p.dashPattern, p.strokeWidth)?.let { paint.put("line-dasharray", it) }
    }
    val layer = JSONObject()
      .put("id", layerId).put("type", "line").put("source", layerId)
      .put("layout", JSONObject().put("line-cap", cap(p.lineCap)).put("line-join", join(p.lineJoin)))
      .put("paint", paint)
      .put("slot", slot(p.level, replacing))
    return Shape(key, p.id, "polyline", p.zIndex, 300 + index, geojson(Feature.fromGeometry(LineString.fromLngLats(points)), gradient),
      listOf(layer), p.tappable, line = points, halfWidth = p.strokeWidth / 2)
  }

  private fun area(
    kind: String, id: String, index: Int, rings: List<List<Point>>, fill: String, stroke: String, strokeWidth: Double,
    dashPattern: String, lineJoin: LineJoin, z: Double, level: OverlayLevel, tappable: Boolean, replacing: Boolean, orderBase: Int,
  ): Shape? {
    if (rings.isEmpty() || rings[0].size < 3) return null
    val layerId = "munim-$kind-$id"
    val slot = slot(level, replacing)
    val fillLayer = JSONObject()
      .put("id", "$layerId-fill").put("type", "fill").put("source", layerId)
      .put("paint", JSONObject().put("fill-color", MapboxColors.css(fill, "rgba(10, 132, 255, 0.2)")))
      .put("slot", slot)
    val layers = mutableListOf(fillLayer)
    if (strokeWidth > 0) {
      val paint = JSONObject().put("line-color", MapboxColors.css(stroke, "rgba(10, 132, 255, 1)")).put("line-width", strokeWidth)
      dashes(dashPattern, strokeWidth)?.let { paint.put("line-dasharray", it) }
      layers.add(JSONObject()
        .put("id", "$layerId-line").put("type", "line").put("source", layerId)
        .put("layout", JSONObject().put("line-join", join(lineJoin)))
        .put("paint", paint)
        .put("slot", slot))
    }
    val polygon = Polygon.fromLngLats(rings.map { MapboxGeo.closed(it) })
    return Shape("$kind:$id", id, kind, z, orderBase + index, geojson(Feature.fromGeometry(polygon)), layers, tappable, rings = rings)
  }

  private fun tile(t: NativeTileOverlay, index: Int, replacing: Boolean): Shape? {
    if (t.urlTemplate.isBlank()) return null
    val layerId = "munim-tiles-${t.id}"
    val source = JSONObject().put("type", "raster").put("tiles", JSONArray().put(t.urlTemplate)).put("tileSize", 256)
    if (t.minimumZoom > 0) source.put("minzoom", t.minimumZoom)
    if (t.maximumZoom > 0) source.put("maxzoom", t.maximumZoom)
    val layer = JSONObject()
      .put("id", layerId).put("type", "raster").put("source", layerId)
      .put("paint", JSONObject().put("raster-opacity", t.opacity.coerceIn(0.0, 1.0)).put("raster-fade-duration", 0))
      .put("slot", slot(t.level, replacing || t.replacesMap))
    return Shape("tiles:${t.id}", t.id, "tileOverlay", t.zIndex, (if (t.replacesMap) 0 else 100) + index, source, listOf(layer), false)
  }

  private fun desired(): List<Shape> {
    val replacing = tiles.any { it.replacesMap }
    val out = mutableListOf<Shape>()
    tiles.forEachIndexed { i, t -> tile(t, i, replacing)?.let(out::add) }
    polygons.forEachIndexed { i, p ->
      val rings = listOf(MapboxGeo.points(p.coordinates)) + p.holes.map { MapboxGeo.points(it) }.filter { it.size >= 3 }
      area("polygon", p.id, i, rings, p.fillColor, p.strokeColor, p.strokeWidth, p.dashPattern, p.lineJoin, p.zIndex, p.level,
        p.tappable, replacing, 1000)?.let(out::add)
    }
    circles.forEachIndexed { i, c ->
      if (c.radius <= 0) return@forEachIndexed
      area("circle", c.id, i, listOf(MapboxGeo.circle(c.latitude, c.longitude, c.radius)), c.fillColor, c.strokeColor, c.strokeWidth,
        c.dashPattern, LineJoin.ROUND, c.zIndex, c.level, c.tappable, replacing, 2000)?.let(out::add)
    }
    polylines.forEachIndexed { i, p -> polyline(p, i, replacing)?.let(out::add) }
    // MapKit order: zIndex, then tile overlays under shapes, then the order given.
    return out.sortedWith(compareBy<Shape>({ it.z }, { if (it.kind == "tileOverlay") 0 else 1 }, { it.order }))
  }

  // Applying

  private fun sync() {
    if (!engine.styleLoaded) return
    val map = engine.map
    val wanted = desired()
    current = wanted
    val wantedKeys = wanted.map { it.key }.toSet()
    // Removed shapes (or shapes whose layer set changed): layers first, then the source.
    for ((key, shape) in applied.toList()) {
      val next = wanted.firstOrNull { it.key == key }
      if (next == null || next.layers.map { it.optString("id") } != shape.layers.map { it.optString("id") } ||
        next.source.optString("type") != shape.source.optString("type") ||
        next.source.optBoolean("lineMetrics") != shape.source.optBoolean("lineMetrics")
      ) {
        remove(shape)
        applied.remove(key)
      }
    }
    val hasSlots = engine.style.slots().isNotEmpty()
    var orderChanged = false
    for (shape in wanted) {
      val previous = applied[shape.key]
      if (previous == null) {
        add(shape, hasSlots)
        orderChanged = true
        applied[shape.key] = shape
        continue
      }
      update(previous, shape, hasSlots)
      applied[shape.key] = shape
    }
    applied.keys.retainAll(wantedKeys)
    if (orderChanged || orderDiffers(wanted)) reorder(wanted, hasSlots)
  }

  private fun remove(shape: Shape) {
    val map = engine.map
    shape.layers.forEach { layer -> layer.optString("id").let { if (map.styleLayerExists(it)) map.removeStyleLayer(it) } }
    val sourceId = shape.layers.first().optString("source")
    if (map.styleSourceExists(sourceId)) map.removeStyleSource(sourceId)
  }

  private fun layerFor(layer: JSONObject, hasSlots: Boolean): JSONObject =
    if (hasSlots) layer else JSONObject(layer.toString()).apply { remove("slot") }

  private fun add(shape: Shape, hasSlots: Boolean) {
    val map = engine.map
    val sourceId = shape.layers.first().optString("source")
    if (map.styleSourceExists(sourceId)) remove(shape)
    MapboxJson.error(map.addStyleSource(sourceId, MapboxJson.value(shape.source)))?.let {
      engine.report("${shape.kind} ${shape.id}: $it")
      return
    }
    for (layer in shape.layers) {
      // Without slots, shapes under labels go below the first label layer; reorder() fixes the order among ours.
      val position = if (!hasSlots && layer.optString("slot") == "middle") engine.style.firstSymbolLayer()?.let { LayerPosition(null, it, null) } else null
      MapboxJson.error(map.addStyleLayer(MapboxJson.value(layerFor(layer, hasSlots)), position))?.let {
        engine.report("${shape.kind} ${shape.id}: $it")
      }
    }
  }

  private fun update(previous: Shape, shape: Shape, hasSlots: Boolean) {
    val map = engine.map
    val sourceId = shape.layers.first().optString("source")
    if (!MapboxJson.same(previous.source, shape.source)) {
      if (shape.source.optString("type") == "geojson") {
        val data = shape.source.optJSONObject("data")
        if (data != null) map.setStyleGeoJSONSourceData(sourceId, "", GeoJSONSourceData.valueOf(MapboxJson.featureFrom(data)))
      } else {
        // Raster tiles: tiles / zoom range changes need a new source.
        remove(previous)
        add(shape, hasSlots)
        return
      }
    }
    for ((i, layer) in shape.layers.withIndex()) {
      val before = previous.layers[i]
      if (MapboxJson.same(before, layer)) continue
      val update = JSONObject()
      for (group in listOf("paint", "layout")) {
        val a = before.optJSONObject(group) ?: JSONObject()
        val b = layer.optJSONObject(group) ?: JSONObject()
        val diff = JSONObject()
        b.keys().forEach { if (!MapboxJson.same(a.opt(it), b.opt(it))) diff.put(it, b.opt(it)) }
        a.keys().forEach { if (!b.has(it)) diff.put(it, JSONObject.NULL) }
        if (diff.length() > 0) update.put(group, diff)
      }
      if (hasSlots && before.optString("slot") != layer.optString("slot")) update.put("slot", layer.optString("slot"))
      if (update.length() > 0) {
        MapboxJson.error(map.setStyleLayerProperties(layer.optString("id"), MapboxJson.value(update)))?.let {
          engine.report("${shape.kind} ${shape.id}: $it")
        }
      }
    }
  }

  private fun ourLayerIds(shapes: List<Shape>): List<String> = shapes.flatMap { s -> s.layers.map { it.optString("id") } }

  private fun orderDiffers(wanted: List<Shape>): Boolean {
    val ids = ourLayerIds(wanted)
    val set = ids.toSet()
    val now = engine.map.styleLayers.map { it.id }.filter { it in set }
    return now != ids
  }

  /** Puts our layers in the wanted order: from the top, each one goes right below the next in its slot. */
  private fun reorder(wanted: List<Shape>, hasSlots: Boolean) {
    val map = engine.map
    val layers = wanted.flatMap { it.layers }
    val bySlot = if (hasSlots) layers.groupBy { it.optString("slot") } else mapOf("" to layers)
    for ((_, list) in bySlot) {
      for (i in list.size - 2 downTo 0) {
        val id = list[i].optString("id")
        val next = list[i + 1].optString("id")
        if (map.styleLayerExists(id) && map.styleLayerExists(next)) map.moveStyleLayer(id, LayerPosition(null, next, null))
      }
    }
  }

  // Hit testing

  /** The topmost tappable shape at a pixel: its id and kind (`polyline`, `polygon`, `circle`). */
  fun hit(x: Double, y: Double): Pair<String, String>? {
    if (!engine.styleLoaded) return null
    val map = engine.map
    val view = engine.mapView
    if (x < 0 || y < 0 || x > view.width || y > view.height) return null
    val slop = 10 * engine.density
    for (shape in current.asReversed()) {
      if (!shape.tappable) continue
      shape.line?.let { line ->
        // Segment by segment between on-screen points only (see onScreen).
        val xy = map.pixelsForCoordinates(densify(line, closed = false))
        val reach = shape.halfWidth * engine.density + slop
        for (i in 0 until xy.size - 1) {
          if (!onScreen(xy[i]) || !onScreen(xy[i + 1])) continue
          if (MapboxGeo.distanceToPolyline(x, y, listOf(xy[i], xy[i + 1])) <= reach) return shape.id to shape.kind
        }
      }
      shape.rings?.let { rings ->
        fun ring(points: List<Point>) = map.pixelsForCoordinates(densify(points, closed = true)).filter { onScreen(it) }
        val outer = ring(rings[0])
        if (outer.size >= 3 && MapboxGeo.inside(x, y, outer) && rings.drop(1).none { MapboxGeo.inside(x, y, ring(it)) }) {
          return shape.id to shape.kind
        }
      }
    }
    return null
  }

  /**
   * Mapbox answers ScreenCoordinate(-1, -1) for a coordinate outside the
   * map view, so a shape reaching off screen used to be hit-tested against
   * the top-left corner (a line below the screen "hit" any tap that was
   * also projected from off screen).
   */
  private fun onScreen(p: com.mapbox.maps.ScreenCoordinate) = !(p.x == -1.0 && p.y == -1.0)

  /** Extra points along each edge, so the on-screen part of a long edge still has points. */
  private fun densify(points: List<Point>, closed: Boolean, steps: Int = 16): List<Point> {
    if (points.size < 2) return points
    val out = ArrayList<Point>(points.size * steps + 1)
    val edges = if (closed) points.size else points.size - 1
    for (i in 0 until edges) {
      val a = points[i]
      val b = points[(i + 1) % points.size]
      for (s in 0 until steps) {
        val t = s.toDouble() / steps
        out.add(Point.fromLngLat(a.longitude() + (b.longitude() - a.longitude()) * t, a.latitude() + (b.latitude() - a.latitude()) * t))
      }
    }
    if (!closed) out.add(points.last())
    return out
  }
}
