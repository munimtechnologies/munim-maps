package com.munimmaps.engines.maplibre

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.PointF
import android.graphics.RectF
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import com.margelo.nitro.munimmaps.CalloutAccessoryEvent
import com.margelo.nitro.munimmaps.CalloutAccessoryKind
import com.margelo.nitro.munimmaps.CalloutAccessorySide
import com.margelo.nitro.munimmaps.ClusterPressEvent
import com.margelo.nitro.munimmaps.FeatureVisibility
import com.margelo.nitro.munimmaps.LineCap
import com.margelo.nitro.munimmaps.LineJoin
import com.margelo.nitro.munimmaps.MapCoordinate
import com.margelo.nitro.munimmaps.MarkerCollisionMode
import com.margelo.nitro.munimmaps.MarkerDragEvent
import com.margelo.nitro.munimmaps.MarkerStyle
import com.margelo.nitro.munimmaps.NativeCalloutAccessory
import com.margelo.nitro.munimmaps.NativeCircle
import com.margelo.nitro.munimmaps.NativeClusterStyle
import com.margelo.nitro.munimmaps.NativeMarker
import com.margelo.nitro.munimmaps.NativePolygon
import com.margelo.nitro.munimmaps.NativePolyline
import com.margelo.nitro.munimmaps.NativeTileOverlay
import com.margelo.nitro.munimmaps.OverlayLevel
import com.margelo.nitro.munimmaps.OverlayPressEvent
import com.munimmaps.engine.MunimMapEngineListener
import com.munimmaps.models.ModelAssets
import org.json.JSONArray
import org.json.JSONObject
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.Style
import org.maplibre.android.style.expressions.Expression
import org.maplibre.android.style.layers.BackgroundLayer
import org.maplibre.android.style.layers.FillLayer
import org.maplibre.android.style.layers.Layer
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.PropertyFactory
import org.maplibre.android.style.layers.RasterLayer
import org.maplibre.android.style.layers.SymbolLayer
import org.maplibre.android.style.sources.GeoJsonOptions
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.android.style.sources.RasterSource
import org.maplibre.android.style.sources.TileSet
import org.maplibre.geojson.Feature
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * munim-maps' 2D features on MapLibre (Android): markers, clusters,
 * callouts, dragging, polylines, polygons, circles and tile overlays, drawn
 * as GeoJSON sources with style layers so they sit in MapLibre's own layer
 * stack and survive style changes ([restore] after every style load).
 */
internal class MapLibreFeatures(
  private val context: Context,
  private val root: FrameLayout,
  private val listenerProvider: () -> MunimMapEngineListener?,
) {
  private val density = context.resources.displayMetrics.density
  private val main = Handler(Looper.getMainLooper())
  var map: MapLibreMap? = null
  private var style: Style? = null

  private var markers: Array<NativeMarker> = emptyArray()
  private var clusterStyles: Map<String, NativeClusterStyle> = emptyMap()
  private var polylines: Array<NativePolyline> = emptyArray()
  private var polygons: Array<NativePolygon> = emptyArray()
  private var circles: Array<NativeCircle> = emptyArray()
  private var tileOverlays: Array<NativeTileOverlay> = emptyArray()
  private val photos = HashMap<String, Bitmap>()
  private val loading = HashSet<String>()
  private val images = HashMap<String, Bitmap>()
  private val markerIds = HashMap<String, NativeMarker>()
  private var markerSources = HashSet<String>()
  private var shapeLayers = ArrayList<String>()
  private var shapeSources = ArrayList<String>()
  private var tileLayers = ArrayList<String>()
  private var hiddenForTiles = ArrayList<String>()
  /** Text font for marker titles, from the style's own labels. */
  private var titleFont: Array<String>? = null
  var overlayPressEnabled = false
  var selectedId: String? = null
    private set

  private val callout = CalloutView(context)
  private var dragging: NativeMarker? = null

  init {
    callout.visibility = View.GONE
    root.addView(callout, FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT))
  }

  // Layer slots, from the bottom: base style, user layers, shapes, markers.
  companion object {
    const val SLOT_USER = "munim-slot-user"
    const val SLOT_SHAPES = "munim-slot-shapes"
    const val SLOT_MARKERS = "munim-slot-markers"
    private const val MARKERS = "munim-markers"
    private const val CLUSTER_PREFIX = "munim-cluster|"
    const val EARTH_RADIUS = 6_371_008.8
  }

  /** The first symbol layer of the base style: `aboveRoads` goes under it. */
  var firstLabelLayer: String? = null
    private set

  /** After every style load: slots, images, every feature. */
  fun restore(style: Style) {
    this.style = style
    images.clear()
    markerSources.clear()
    shapeLayers.clear()
    shapeSources.clear()
    tileLayers.clear()
    hiddenForTiles.clear()
    val layers = style.layers
    firstLabelLayer = layers.firstOrNull { it is SymbolLayer }?.id
    titleFont = layers.asSequence().filterIsInstance<SymbolLayer>()
      .mapNotNull { (it.textFont.value as? Array<*>)?.filterIsInstance<String>()?.toTypedArray() }
      .firstOrNull { it.isNotEmpty() }
    for (slot in listOf(SLOT_USER, SLOT_SHAPES, SLOT_MARKERS)) {
      if (style.getLayer(slot) == null) {
        style.addLayer(BackgroundLayer(slot).withProperties(PropertyFactory.visibility("none")))
      }
    }
    applyTileOverlays()
    applyShapes()
    applyMarkers()
  }

  fun detachStyle() {
    style = null
  }

  // MARK: Markers

  fun setMarkers(value: Array<NativeMarker>) {
    markers = value
    markerIds.clear()
    value.forEach { markerIds[it.id] = it }
    for (m in value) {
      if (m.imageUri.isNotEmpty() && (m.style == MarkerStyle.IMAGE || m.style == MarkerStyle.AVATAR)) loadPhoto(m.imageUri)
    }
    if (selectedId != null && markerIds[selectedId!!] == null) hideCallout()
    applyMarkers()
  }

  fun setClusterStyles(value: Array<NativeClusterStyle>) {
    clusterStyles = value.associateBy { it.clusteringId }
    style?.let { s -> s.layers.filter { it.id.startsWith("munim-clusters-") }.forEach { s.removeLayer(it) } }
    applyMarkers()
  }

  /** An extra image marker (a React Native view drawn to a bitmap). */
  fun marker(id: String): NativeMarker? = markerIds[id]

  private fun loadPhoto(uri: String) {
    if (photos.containsKey(uri) || !loading.add(uri)) return
    ModelAssets.load(context, uri) { result ->
      result.onSuccess { bytes ->
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        main.post {
          loading.remove(uri)
          if (bitmap != null) {
            photos[uri] = bitmap
            applyMarkers()
          }
        }
      }.onFailure { error ->
        main.post {
          loading.remove(uri)
          listenerProvider()?.onError("MapLibre: could not load marker image $uri: ${error.message}")
        }
      }
    }
  }

  private fun imageName(m: NativeMarker, selected: Boolean): String {
    val drawn = MarkerBitmaps.draw(m, photos[m.imageUri], density, selected)
    val name = "munim-m|" + Integer.toHexString((MarkerBitmaps.key(m, photos[m.imageUri] != null) + selected).hashCode())
    if (!images.containsKey(name)) {
      drawn.bitmap.density = (density * 160).toInt()
      images[name] = drawn.bitmap
      style?.addImage(name, drawn.bitmap)
    }
    return name
  }

  private fun markerFeature(m: NativeMarker): JSONObject {
    val selected = m.id == selectedId && m.style == MarkerStyle.MARKER
    val name = imageName(m, selected)
    val bitmap = images[name]!!
    val w = bitmap.width / density
    val h = bitmap.height / density
    val (ax, ay) = if (m.style == MarkerStyle.PIN || m.style == MarkerStyle.MARKER) {
      MarkerBitmaps.defaultAnchor(m.style)
    } else m.anchorX to m.anchorY
    val required = m.displayPriority >= 1000 || m.collisionMode == MarkerCollisionMode.NONE
    val showsTitle = m.style == MarkerStyle.MARKER && m.title.isNotEmpty() && m.titleVisibility != FeatureVisibility.HIDDEN
    return JSONObject()
      .put("type", "Feature")
      .put("id", m.id)
      .put("geometry", JSONObject().put("type", "Point").put("coordinates", JSONArray().put(m.longitude).put(m.latitude)))
      .put("properties", JSONObject()
        .put("id", m.id)
        .put("icon", name)
        .put("offset", JSONArray().put((0.5 - ax) * w).put((0.5 - ay) * h))
        .put("sort", m.zIndex + m.displayPriority / 10_000.0)
        .put("opacity", m.opacity)
        .put("req", required)
        .put("title", if (showsTitle) m.title else "")
        .put("titleOffset", h * (1 - ay)))
  }

  private fun collection(features: List<JSONObject>): String =
    JSONObject().put("type", "FeatureCollection").put("features", JSONArray(features)).toString()

  private fun applyMarkers() {
    val style = style ?: return
    val visible = markers.filter { it.visible }
    val groups = visible.groupBy { it.clusteringId }
    val wanted = HashSet<String>()
    for ((clusterId, members) in groups + (if (groups.containsKey("")) emptyMap() else mapOf("" to emptyList()))) {
      val sourceId = if (clusterId.isEmpty()) MARKERS else "$MARKERS-c-$clusterId"
      wanted.add(sourceId)
      val json = collection(members.map(::markerFeature))
      val source = style.getSourceAs<GeoJsonSource>(sourceId)
      if (source != null) {
        source.setGeoJson(json)
      } else {
        val options = GeoJsonOptions()
        if (clusterId.isNotEmpty()) options.withCluster(true).withClusterRadius(48).withClusterMaxZoom(18)
        style.addSource(GeoJsonSource(sourceId, json, options))
        addMarkerLayers(style, sourceId, clusterId)
      }
      markerSources.add(sourceId)
    }
    for (sourceId in markerSources.toList()) {
      if (sourceId !in wanted) {
        style.layers.filter { it.id.startsWith("$sourceId|") }.forEach { style.removeLayer(it) }
        style.removeSource(sourceId)
        markerSources.remove(sourceId)
      }
    }
    positionCallout()
  }

  private fun addMarkerLayers(style: Style, sourceId: String, clusterId: String) {
    val notCluster = Expression.not(Expression.has("point_count"))
    for (required in listOf(false, true)) {
      val layer = SymbolLayer("$sourceId|${if (required) "req" else "opt"}", sourceId).withProperties(
        PropertyFactory.iconImage(Expression.get("icon")),
        PropertyFactory.iconOffset(Expression.get("offset")),
        PropertyFactory.iconAllowOverlap(required),
        PropertyFactory.iconIgnorePlacement(required),
        PropertyFactory.symbolSortKey(Expression.get("sort")),
        PropertyFactory.iconOpacity(Expression.get("opacity")),
        PropertyFactory.textField(Expression.get("title")),
        PropertyFactory.textSize(11f),
        PropertyFactory.textAnchor("top"),
        PropertyFactory.textOptional(true),
        PropertyFactory.textOffset(Expression.array(Expression.literal(arrayOf(0f, 0.2f)))),
        PropertyFactory.textHaloColor("rgba(255,255,255,0.9)"),
        PropertyFactory.textHaloWidth(1.2f),
        PropertyFactory.textColor("#1C1C1E"),
      )
      titleFont?.let { layer.setProperties(PropertyFactory.textFont(it)) }
      layer.setFilter(Expression.all(notCluster, Expression.eq(Expression.get("req"), required)))
      style.addLayerBelow(layer, SLOT_MARKERS)
    }
    if (clusterId.isNotEmpty()) {
      val clusters = SymbolLayer("$sourceId|clusters", sourceId).withProperties(
        PropertyFactory.iconImage(Expression.concat(Expression.literal("$CLUSTER_PREFIX$clusterId|"), Expression.toString(Expression.get("point_count")))),
        PropertyFactory.iconAnchor("bottom"),
        PropertyFactory.iconAllowOverlap(true),
        PropertyFactory.iconIgnorePlacement(true),
      )
      clusters.setFilter(Expression.has("point_count"))
      style.addLayerBelow(clusters, SLOT_MARKERS)
    }
  }

  /** Draws cluster balloons on demand (`OnStyleImageMissingListener`). */
  fun imageMissing(id: String): Boolean {
    if (!id.startsWith(CLUSTER_PREFIX)) return false
    val parts = id.split("|")
    if (parts.size < 3) return false
    val bitmap = MarkerBitmaps.cluster(clusterStyles[parts[1]], parts[2].toIntOrNull() ?: 0, density)
    bitmap.density = (density * 160).toInt()
    style?.addImage(id, bitmap)
    return true
  }

  private val markerLayerIds: Array<String>
    get() = markerSources.flatMap { listOf("$it|req", "$it|opt") }.toTypedArray()

  private val clusterLayerIds: Array<String>
    get() = markerSources.filter { it != MARKERS }.map { "$it|clusters" }.toTypedArray()

  /** The marker at a screen point (pixels), topmost first. */
  fun markerAt(point: PointF): NativeMarker? {
    val map = map ?: return null
    if (markerSources.isEmpty()) return null
    val box = RectF(point.x - 6 * density, point.y - 6 * density, point.x + 6 * density, point.y + 6 * density)
    val hits = map.queryRenderedFeatures(box, *markerLayerIds)
    return hits.asSequence().mapNotNull { markerIds[it.getStringProperty("id") ?: return@mapNotNull null] }
      .maxByOrNull { it.zIndex }
  }

  private fun clusterAt(point: PointF): Pair<String, Feature>? {
    val map = map ?: return null
    val ids = clusterLayerIds
    if (ids.isEmpty()) return null
    val hit = map.queryRenderedFeatures(point, *ids).firstOrNull() ?: return null
    val source = markerSources.firstOrNull { s -> s != MARKERS && map.queryRenderedFeatures(point, "$s|clusters").isNotEmpty() }
      ?: return null
    return source to hit
  }

  /** A tap at `point` (pixels): markers, clusters, callouts. True if taken. */
  fun handleTap(point: PointF): Boolean {
    clusterAt(point)?.let { (sourceId, feature) ->
      val style = style ?: return true
      val source = style.getSourceAs<GeoJsonSource>(sourceId) ?: return true
      val leaves = source.getClusterLeaves(feature, Long.MAX_VALUE, 0).features().orEmpty()
      val ids = leaves.mapNotNull { it.getStringProperty("id") }
      val coordinate = (feature.geometry() as? org.maplibre.geojson.Point)
      listenerProvider()?.onClusterPress(ClusterPressEvent(
        sourceId.removePrefix("$MARKERS-c-"), ids.joinToString(","),
        coordinate?.latitude() ?: 0.0, coordinate?.longitude() ?: 0.0))
      return true
    }
    val marker = markerAt(point)
    if (marker != null) {
      select(marker.id, fromTap = true)
      return true
    }
    if (selectedId != null) {
      deselect()
    }
    return false
  }

  fun select(id: String, fromTap: Boolean = false) {
    val marker = markerIds[id] ?: return
    if (selectedId != null && selectedId != id) deselect()
    selectedId = id
    listenerProvider()?.onMarkerPress(id)
    if (marker.style == MarkerStyle.MARKER) applyMarkers()
    if (marker.calloutEnabled && (marker.title.isNotEmpty() || marker.subtitle.isNotEmpty() || marker.calloutDetail.isNotEmpty())) {
      showCallout(marker)
    }
  }

  fun deselect(id: String? = null) {
    val current = selectedId ?: return
    if (id != null && id != current) return
    selectedId = null
    hideCallout()
    listenerProvider()?.onMarkerDeselect(current)
    if (markerIds[current]?.style == MarkerStyle.MARKER) applyMarkers()
  }

  // MARK: Callouts

  private fun showCallout(marker: NativeMarker) {
    callout.bind(marker, onPress = { listenerProvider()?.onCalloutPress(marker.id) }, onAccessory = { side ->
      listenerProvider()?.onCalloutAccessoryPress(CalloutAccessoryEvent(marker.id, side))
    })
    callout.visibility = View.VISIBLE
    callout.bringToFront()
    callout.post { positionCallout() }
  }

  private fun hideCallout() {
    callout.visibility = View.GONE
  }

  /** Keeps the callout over its marker; call on every camera move. */
  fun positionCallout() {
    if (callout.visibility != View.VISIBLE) return
    val map = map ?: return
    val marker = markerIds[selectedId ?: return] ?: return hideCallout()
    val p = map.projection.toScreenLocation(LatLng(marker.latitude, marker.longitude))
    val name = imageName(marker, marker.style == MarkerStyle.MARKER)
    val bitmap = images[name]
    val (_, ay) = if (marker.style == MarkerStyle.PIN || marker.style == MarkerStyle.MARKER) MarkerBitmaps.defaultAnchor(marker.style) else marker.anchorX to marker.anchorY
    val top = p.y - (bitmap?.height ?: 0) * ay.toFloat()
    callout.translationX = p.x - callout.width / 2f
    callout.translationY = top - callout.height - 4 * density
  }

  // MARK: Dragging

  /** Called with every touch before the map sees it; true while dragging. */
  fun onTouch(event: MotionEvent): Boolean {
    val marker = dragging ?: return false
    val map = map ?: return false
    when (event.actionMasked) {
      MotionEvent.ACTION_MOVE -> {
        val latLng = map.projection.fromScreenLocation(PointF(event.x, event.y - 30 * density))
        moveMarker(marker.id, latLng)
        listenerProvider()?.onMarkerDrag(MarkerDragEvent(marker.id, latLng.latitude, latLng.longitude))
      }
      MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
        val m = markerIds[marker.id] ?: marker
        dragging = null
        map.uiSettings.isScrollGesturesEnabled = scrollWasEnabled
        listenerProvider()?.onMarkerDragEnd(MarkerDragEvent(m.id, m.latitude, m.longitude))
      }
    }
    return true
  }

  private var scrollWasEnabled = true

  /** A long press: starts dragging a draggable marker under it. */
  fun handleLongPress(point: PointF): Boolean {
    val marker = markerAt(point) ?: return false
    if (!marker.draggable) return false
    val map = map ?: return false
    hideCallout()
    dragging = marker
    scrollWasEnabled = map.uiSettings.isScrollGesturesEnabled
    map.uiSettings.isScrollGesturesEnabled = false
    listenerProvider()?.onMarkerDragStart(MarkerDragEvent(marker.id, marker.latitude, marker.longitude))
    return true
  }

  private fun moveMarker(id: String, latLng: LatLng) {
    val index = markers.indexOfFirst { it.id == id }
    if (index < 0) return
    val moved = markers[index].copy(latitude = latLng.latitude, longitude = latLng.longitude)
    markers = markers.copyOf().also { it[index] = moved }
    markerIds[id] = moved
    applyMarkers()
  }

  // MARK: Shapes

  fun setShapes(polylines: Array<NativePolyline>? = null, polygons: Array<NativePolygon>? = null, circles: Array<NativeCircle>? = null) {
    polylines?.let { this.polylines = it }
    polygons?.let { this.polygons = it }
    circles?.let { this.circles = it }
    applyShapes()
  }

  private data class Shape(val id: String, val kind: String, val z: Double, val level: OverlayLevel, val apply: (Style, String) -> Unit)

  private fun applyShapes() {
    val style = style ?: return
    shapeLayers.forEach { if (style.getLayer(it) != null) style.removeLayer(it) }
    shapeSources.forEach { if (style.getSource(it) != null) style.removeSource(it) }
    shapeLayers.clear()
    shapeSources.clear()
    val shapes = ArrayList<Shape>()
    polygons.forEach { p -> shapes.add(Shape(p.id, "polygon", p.zIndex, p.level) { s, below -> addPolygon(s, p, below) }) }
    circles.forEach { c -> shapes.add(Shape(c.id, "circle", c.zIndex, c.level) { s, below -> addCircle(s, c, below) }) }
    polylines.forEach { l -> shapes.add(Shape(l.id, "polyline", l.zIndex, l.level) { s, below -> addPolyline(s, l, below) }) }
    // Lowest zIndex first; each goes under its level's slot, so later ones end up on top.
    for (shape in shapes.sortedBy { it.z }) {
      val below = if (shape.level == OverlayLevel.ABOVEROADS) (firstLabelLayer ?: SLOT_SHAPES) else SLOT_SHAPES
      shape.apply(style, below)
    }
  }

  private fun dashArray(pattern: String, width: Double): Array<Float>? {
    val parts = pattern.split(",").mapNotNull { it.trim().toFloatOrNull() }
    if (parts.size < 2) return null
    // MapLibre dashes are in line widths; munim-maps' in points.
    val w = max(0.5, width).toFloat()
    return parts.map { it / w }.toTypedArray()
  }

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

  private fun lineString(points: List<MapCoordinate>): JSONObject =
    JSONObject().put("type", "LineString").put("coordinates", JSONArray(points.map { JSONArray().put(it.longitude).put(it.latitude) }))

  private fun addSource(style: Style, id: String, geometry: JSONObject, lineMetrics: Boolean = false) {
    val feature = JSONObject().put("type", "Feature").put("properties", JSONObject().put("id", id)).put("geometry", geometry)
    style.addSource(GeoJsonSource(id, feature.toString(), GeoJsonOptions().withLineMetrics(lineMetrics)))
    shapeSources.add(id)
  }

  private fun addLayer(style: Style, layer: Layer, below: String) {
    style.addLayerBelow(layer, below)
    shapeLayers.add(layer.id)
  }

  private fun addPolyline(style: Style, line: NativePolyline, below: String) {
    var points = line.coordinates.toList()
    if (line.geodesic) points = Geo.densify(points)
    points = Geo.slice(points, line.strokeStart, line.strokeEnd)
    if (points.size < 2) return
    val id = "munim-shape|polyline|${line.id}"
    val colors = line.strokeColors.split(",").map { it.trim() }.filter { it.isNotEmpty() }
    addSource(style, id, lineString(points), lineMetrics = colors.size > 1)
    val layer = LineLayer(id, id).withProperties(
      PropertyFactory.lineColor(MarkerBitmaps.css(line.strokeColor, MarkerBitmaps.SYSTEM_BLUE)),
      PropertyFactory.lineWidth(line.strokeWidth.toFloat()),
      PropertyFactory.lineCap(cap(line.lineCap)),
      PropertyFactory.lineJoin(join(line.lineJoin)),
    )
    dashArray(line.dashPattern, line.strokeWidth)?.let { layer.setProperties(PropertyFactory.lineDasharray(it)) }
    if (colors.size > 1) {
      val locations = line.strokeColorLocations.split(",").mapNotNull { it.trim().toDoubleOrNull() }
      val stops = colors.mapIndexed { i, c ->
        val at = locations.getOrNull(i) ?: (i.toDouble() / (colors.size - 1))
        Expression.stop(at.coerceIn(0.0, 1.0), Expression.color(MarkerBitmaps.color(c, MarkerBitmaps.SYSTEM_BLUE)))
      }.distinctBy { it.toString() }
      layer.setProperties(PropertyFactory.lineGradient(Expression.interpolate(Expression.linear(), Expression.lineProgress(), *stops.toTypedArray())))
    }
    addLayer(style, layer, below)
  }

  private fun ring(points: List<MapCoordinate>): JSONArray {
    val ring = JSONArray(points.map { JSONArray().put(it.longitude).put(it.latitude) })
    if (points.isNotEmpty() && (points.first().latitude != points.last().latitude || points.first().longitude != points.last().longitude)) {
      ring.put(JSONArray().put(points.first().longitude).put(points.first().latitude))
    }
    return ring
  }

  private fun addFill(style: Style, id: String, rings: List<List<MapCoordinate>>, fill: String, stroke: String, width: Double,
                      dash: String, join: LineJoin, below: String) {
    if (rings.firstOrNull().orEmpty().size < 3) return
    addSource(style, id, JSONObject().put("type", "Polygon").put("coordinates", JSONArray(rings.map(::ring))))
    addLayer(style, FillLayer("$id|fill", id).withProperties(
      PropertyFactory.fillColor(MarkerBitmaps.css(fill, 0x330A84FF)),
      PropertyFactory.fillAntialias(true),
    ), below)
    if (width > 0) {
      val line = LineLayer("$id|line", id).withProperties(
        PropertyFactory.lineColor(MarkerBitmaps.css(stroke, MarkerBitmaps.SYSTEM_BLUE)),
        PropertyFactory.lineWidth(width.toFloat()),
        PropertyFactory.lineJoin(join(join)),
      )
      dashArray(dash, width)?.let { line.setProperties(PropertyFactory.lineDasharray(it)) }
      addLayer(style, line, below)
    }
  }

  private fun addPolygon(style: Style, p: NativePolygon, below: String) {
    addFill(style, "munim-shape|polygon|${p.id}", listOf(p.coordinates.toList()) + p.holes.map { it.toList() },
      p.fillColor, p.strokeColor, p.strokeWidth, p.dashPattern, p.lineJoin, below)
  }

  private fun addCircle(style: Style, c: NativeCircle, below: String) {
    addFill(style, "munim-shape|circle|${c.id}", listOf(Geo.circle(c.latitude, c.longitude, c.radius)),
      c.fillColor, c.strokeColor, c.strokeWidth, c.dashPattern, LineJoin.ROUND, below)
  }

  private val tappable: Set<String>
    get() = buildSet {
      polylines.filter { it.tappable }.forEach { add("polyline|${it.id}") }
      polygons.filter { it.tappable }.forEach { add("polygon|${it.id}") }
      circles.filter { it.tappable }.forEach { add("circle|${it.id}") }
    }

  /** The topmost tappable overlay at a point (pixels): id and kind. */
  fun overlayAt(point: PointF): Pair<String, String>? {
    val map = map ?: return null
    if (shapeLayers.isEmpty()) return null
    val box = RectF(point.x - 8 * density, point.y - 8 * density, point.x + 8 * density, point.y + 8 * density)
    val wanted = tappable
    // queryRenderedFeatures returns the topmost first.
    for (feature in map.queryRenderedFeatures(box, *shapeLayers.toTypedArray())) {
      val id = feature.getStringProperty("id") ?: continue
      val parts = id.split("|")
      if (parts.size < 3) continue
      val key = "${parts[1]}|${parts.subList(2, parts.size).joinToString("|")}"
      if (key in wanted) return parts.subList(2, parts.size).joinToString("|") to parts[1]
    }
    return null
  }

  fun handleOverlayTap(point: PointF, latLng: LatLng): Boolean {
    if (!overlayPressEnabled) return false
    val (id, kind) = overlayAt(point) ?: return false
    listenerProvider()?.onOverlayPress(OverlayPressEvent(id, kind, latLng.latitude, latLng.longitude))
    return true
  }

  // MARK: Tile overlays

  fun setTileOverlays(value: Array<NativeTileOverlay>) {
    tileOverlays = value
    applyTileOverlays()
  }

  private fun applyTileOverlays() {
    val style = style ?: return
    tileLayers.forEach { id ->
      if (style.getLayer(id) != null) style.removeLayer(id)
      if (style.getSource(id) != null) style.removeSource(id)
    }
    tileLayers.clear()
    hiddenForTiles.forEach { style.getLayer(it)?.setProperties(PropertyFactory.visibility("visible")) }
    hiddenForTiles.clear()
    for (overlay in tileOverlays.sortedBy { it.zIndex }) {
      val id = "munim-tiles|${overlay.id}"
      val set = TileSet("2.2.0", overlay.urlTemplate)
      if (overlay.minimumZoom > 0) set.minZoom = overlay.minimumZoom.toFloat()
      if (overlay.maximumZoom > 0) set.maxZoom = overlay.maximumZoom.toFloat()
      style.addSource(RasterSource(id, set, 256))
      val layer = RasterLayer(id, id).withProperties(PropertyFactory.rasterOpacity(overlay.opacity.toFloat()))
      val below = if (overlay.level == OverlayLevel.ABOVELABELS) SLOT_SHAPES else (firstLabelLayer ?: SLOT_SHAPES)
      style.addLayerBelow(layer, below)
      tileLayers.add(id)
    }
    if (tileOverlays.any { it.replacesMap }) {
      // Hide the base style, keep the overlays and munim-maps' own layers.
      for (layer in style.layers) {
        if (layer.id.startsWith("munim-")) continue
        if (layer.visibility.value == "none") continue
        layer.setProperties(PropertyFactory.visibility("none"))
        hiddenForTiles.add(layer.id)
      }
    }
  }

  /** Bounds of the markers with these ids (all when empty). */
  fun markerCoordinates(ids: Set<String>): List<MapCoordinate> =
    markers.filter { ids.isEmpty() || it.id in ids }.map { MapCoordinate(it.latitude, it.longitude) }
}

/** Great circles, circles on the sphere and partial lines. */
internal object Geo {
  private const val R = MapLibreFeatures.EARTH_RADIUS

  private fun rad(d: Double) = d * PI / 180
  private fun deg(r: Double) = r * 180 / PI

  /** Points every ~50 km along great circles between the points. */
  fun densify(points: List<MapCoordinate>): List<MapCoordinate> {
    if (points.size < 2) return points
    val out = ArrayList<MapCoordinate>()
    for (i in 0 until points.size - 1) {
      val a = points[i]
      val b = points[i + 1]
      val d = distance(a, b)
      val steps = max(1, min(256, (d / 50_000).toInt()))
      val lat1 = rad(a.latitude)
      val lon1 = rad(a.longitude)
      val lat2 = rad(b.latitude)
      val lon2 = rad(b.longitude)
      val delta = d / R
      for (s in 0 until steps) {
        val f = s.toDouble() / steps
        if (delta < 1e-9) {
          out.add(a)
          continue
        }
        val A = sin((1 - f) * delta) / sin(delta)
        val B = sin(f * delta) / sin(delta)
        val x = A * cos(lat1) * cos(lon1) + B * cos(lat2) * cos(lon2)
        val y = A * cos(lat1) * sin(lon1) + B * cos(lat2) * sin(lon2)
        val z = A * sin(lat1) + B * sin(lat2)
        var lon = deg(atan2(y, x))
        // Keep longitudes continuous across the antimeridian.
        out.lastOrNull()?.let { prev -> while (lon - prev.longitude > 180) lon -= 360; while (lon - prev.longitude < -180) lon += 360 }
        out.add(MapCoordinate(deg(atan2(z, sqrt(x * x + y * y))), lon))
      }
    }
    out.add(points.last())
    return out
  }

  fun distance(a: MapCoordinate, b: MapCoordinate): Double {
    val dLat = rad(b.latitude - a.latitude)
    val dLon = rad(b.longitude - a.longitude)
    val h = sin(dLat / 2) * sin(dLat / 2) + cos(rad(a.latitude)) * cos(rad(b.latitude)) * sin(dLon / 2) * sin(dLon / 2)
    return 2 * R * asin(min(1.0, sqrt(h)))
  }

  /** A ring of points `radius` metres from the centre. */
  fun circle(latitude: Double, longitude: Double, radius: Double, segments: Int = 72): List<MapCoordinate> {
    val lat = rad(latitude)
    val lon = rad(longitude)
    val d = radius / R
    return (0..segments).map { i ->
      val bearing = 2 * PI * i / segments
      val lat2 = asin(sin(lat) * cos(d) + cos(lat) * sin(d) * cos(bearing))
      val lon2 = lon + atan2(sin(bearing) * sin(d) * cos(lat), cos(d) - sin(lat) * sin(lat2))
      MapCoordinate(deg(lat2), deg(lon2))
    }
  }

  /** The part of a line from `start` to `end` (0…1 of its length). */
  fun slice(points: List<MapCoordinate>, start: Double, end: Double): List<MapCoordinate> {
    if (points.size < 2 || (start <= 0 && end >= 1)) return points
    val s = start.coerceIn(0.0, 1.0)
    val e = end.coerceIn(0.0, 1.0)
    if (e <= s) return emptyList()
    val lengths = (0 until points.size - 1).map { hypot(points[it + 1].latitude - points[it].latitude, (points[it + 1].longitude - points[it].longitude) * cos(rad(points[it].latitude))) }
    val total = lengths.sum()
    if (total <= 0) return points
    val out = ArrayList<MapCoordinate>()
    var walked = 0.0
    for (i in lengths.indices) {
      val a = points[i]
      val b = points[i + 1]
      val from = walked / total
      val to = (walked + lengths[i]) / total
      walked += lengths[i]
      if (to < s || from > e) continue
      fun at(f: Double): MapCoordinate {
        val t = if (to - from < 1e-12) 0.0 else (f - from) / (to - from)
        return MapCoordinate(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t)
      }
      if (out.isEmpty()) out.add(if (from < s) at(s) else a)
      out.add(if (to > e) at(e) else b)
      if (to > e) break
    }
    return out
  }

  fun approximately(a: Double, b: Double) = abs(a - b) < 1e-9
}

/** munim-maps' callout on Android: title, subtitle or detail, accessories. */
internal class CalloutView(context: Context) : LinearLayout(context) {
  private val density = context.resources.displayMetrics.density
  private val title = TextView(context)
  private val subtitle = TextView(context)
  private val left = TextView(context)
  private val right = TextView(context)
  private val maxWidthPx = (280 * density).toInt()

  init {
    orientation = HORIZONTAL
    gravity = Gravity.CENTER_VERTICAL
    val pad = (10 * density).toInt()
    setPadding(pad, (8 * density).toInt(), pad, (8 * density).toInt())
    background = GradientDrawable().apply {
      cornerRadius = 12 * density
      setColor(Color.WHITE)
    }
    elevation = 6 * density
    val texts = LinearLayout(context).apply { orientation = VERTICAL }
    title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
    title.setTextColor(Color.BLACK)
    title.paint.isFakeBoldText = true
    title.maxLines = 1
    title.ellipsize = TextUtils.TruncateAt.END
    subtitle.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
    subtitle.setTextColor(0xFF6C6C70.toInt())
    subtitle.maxLines = 6
    texts.addView(title)
    texts.addView(subtitle)
    for (button in listOf(left, right)) {
      button.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
      button.setTextColor(MarkerBitmaps.SYSTEM_BLUE)
      button.setPadding(pad / 2, 0, pad / 2, 0)
    }
    addView(left)
    addView(texts)
    addView(right)
  }

  override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
    super.onMeasure(MeasureSpec.makeMeasureSpec(maxWidthPx, MeasureSpec.AT_MOST), heightMeasureSpec)
  }

  fun bind(marker: NativeMarker, onPress: () -> Unit, onAccessory: (CalloutAccessorySide) -> Unit) {
    title.text = marker.title
    title.visibility = if (marker.title.isEmpty()) GONE else VISIBLE
    val sub = marker.calloutDetail.ifEmpty { marker.subtitle }
    subtitle.text = sub
    subtitle.visibility = if (sub.isEmpty()) GONE else VISIBLE
    bindAccessory(left, marker.leftCalloutAccessory) { onAccessory(CalloutAccessorySide.LEFT) }
    bindAccessory(right, marker.rightCalloutAccessory) { onAccessory(CalloutAccessorySide.RIGHT) }
    setOnClickListener { onPress() }
  }

  private fun bindAccessory(view: TextView, accessory: NativeCalloutAccessory, onTap: () -> Unit) {
    val text = when (accessory.kind) {
      CalloutAccessoryKind.NONE -> ""
      CalloutAccessoryKind.DETAIL -> "›"
      CalloutAccessoryKind.INFO -> "ⓘ"
      CalloutAccessoryKind.BUTTON -> accessory.text.ifEmpty { "›" }
      CalloutAccessoryKind.IMAGE -> accessory.text
    }
    view.text = text
    view.visibility = if (text.isEmpty()) GONE else VISIBLE
    if (accessory.color.isNotEmpty()) view.setTextColor(MarkerBitmaps.color(accessory.color, MarkerBitmaps.SYSTEM_BLUE))
    val tappable = accessory.kind != CalloutAccessoryKind.IMAGE && accessory.kind != CalloutAccessoryKind.NONE
    view.setOnClickListener(if (tappable) View.OnClickListener { onTap() } else null)
    view.isClickable = tappable
  }
}
