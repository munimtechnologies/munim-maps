@file:OptIn(MapboxExperimental::class)

package com.munimmaps.engines.mapbox

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.mapbox.geojson.Point
import com.mapbox.maps.MapboxExperimental
import com.mapbox.maps.ViewAnnotationAnchor
import com.mapbox.maps.ViewAnnotationAnchorConfig
import com.mapbox.maps.ViewAnnotationOptions
import com.mapbox.maps.extension.style.expressions.generated.Expression
import com.mapbox.maps.extension.style.layers.properties.generated.IconAnchor
import com.mapbox.maps.plugin.annotation.AnnotationConfig
import com.mapbox.maps.plugin.annotation.AnnotationSourceOptions
import com.mapbox.maps.plugin.annotation.ClusterOptions
import com.mapbox.maps.plugin.annotation.OnClusterClickListener
import com.mapbox.maps.plugin.annotation.annotations
import com.mapbox.maps.plugin.annotation.generated.OnPointAnnotationClickListener
import com.mapbox.maps.plugin.annotation.generated.OnPointAnnotationDragListener
import com.mapbox.maps.plugin.annotation.generated.PointAnnotation
import com.mapbox.maps.plugin.annotation.generated.PointAnnotationManager
import com.mapbox.maps.plugin.annotation.generated.PointAnnotationOptions
import com.mapbox.maps.plugin.annotation.generated.createPointAnnotationManager
import com.mapbox.maps.viewannotation.geometry
import com.margelo.nitro.munimmaps.CalloutAccessoryEvent
import com.margelo.nitro.munimmaps.CalloutAccessoryKind
import com.margelo.nitro.munimmaps.CalloutAccessorySide
import com.margelo.nitro.munimmaps.ClusterPressEvent
import com.margelo.nitro.munimmaps.MapCoordinate
import com.margelo.nitro.munimmaps.MarkerCollisionMode
import com.margelo.nitro.munimmaps.MarkerDragEvent
import com.margelo.nitro.munimmaps.MarkerStyle
import com.margelo.nitro.munimmaps.NativeCalloutAccessory
import com.margelo.nitro.munimmaps.NativeClusterStyle
import com.margelo.nitro.munimmaps.NativeMarker
import org.json.JSONArray

/**
 * Markers and `MarkerView`s on Mapbox.
 *
 * - Markers are point annotations with munim-maps' marker images
 *   ([MapboxMarkerImages]), one `PointAnnotationManager` per clustering id
 *   (with Mapbox's GeoJSON clustering, coloured by `clusterStyles`) and per
 *   collision behaviour (`icon-allow-overlap` is per layer). `zIndex` is the
 *   symbol sort key; dragging uses the annotation plugin's drag.
 * - A tap selects the marker (`onMarkerPress`; the previous one gets
 *   `onMarkerDeselect`), draws pins and balloons bigger, and shows a callout
 *   (title, subtitle or detail, accessories) as a view annotation over it.
 * - `MarkerView`s are view annotations showing the views' bitmap, anchored at
 *   `anchorX` / `anchorY`; draggable ones are point annotations with the
 *   bitmap as their icon, since view annotations cannot be dragged.
 */
internal class MapboxAnnotations(private val engine: MapboxMapEngine) {
  private var markers: Array<NativeMarker> = emptyArray()
  private var clusterStyles: Map<String, NativeClusterStyle> = emptyMap()

  private class Placed(val marker: NativeMarker, val managerKey: String, val annotation: PointAnnotation, val image: MarkerImage?)

  private val managers = mutableMapOf<String, PointAnnotationManager>()
  private var managerCount = 0
  private val managerSources = mutableMapOf<String, String>()
  private val placed = mutableMapOf<String, Placed>()
  /** Annotation id to marker id (markers and draggable MarkerViews). */
  private val markerIds = mutableMapOf<String, String>()
  private var selected: String? = null
  private var callout: View? = null
  private var calloutFor: String? = null

  private class ViewMarker(var marker: NativeMarker, var bitmap: Bitmap?, var view: ImageView?)

  private val viewMarkers = mutableMapOf<String, ViewMarker>()

  private val density get() = engine.density

  fun setMarkers(value: Array<NativeMarker>) {
    markers = value
    sync()
  }

  fun setClusterStyles(styles: Array<NativeClusterStyle>) {
    val next = styles.associateBy { it.clusteringId }
    if (next == clusterStyles) return
    // Cluster colours are fixed when a manager is made: make those again.
    val changed = (next.keys + clusterStyles.keys).filter { next[it] != clusterStyles[it] }.toSet()
    clusterStyles = next
    for (key in managers.keys.toList()) {
      if (key.substringBefore('|').removePrefix("cluster:") in changed) dropManager(key)
    }
    sync()
  }

  fun styleLoaded() {
    // The annotation plugin re-adds its layers itself; callouts and view annotations stay.
  }

  // Managers

  private fun managerKey(m: NativeMarker): String {
    val overlap = m.collisionMode == MarkerCollisionMode.NONE || m.displayPriority >= 1000
    return "cluster:${m.clusteringId}|overlap:$overlap"
  }

  private fun manager(key: String): PointAnnotationManager {
    managers[key]?.let { return it }
    val clusteringId = key.substringBefore('|').removePrefix("cluster:")
    val overlap = key.endsWith("overlap:true")
    val n = managerCount++
    val id = "munim-markers-$n"
    val sourceOptions = if (clusteringId.isNotEmpty()) {
      val style = clusterStyles[clusteringId]
      val color = MapboxColors.parse(style?.color) ?: Color.rgb(10, 132, 255)
      val textColor = MapboxColors.parse(style?.glyphColor) ?: Color.WHITE
      AnnotationSourceOptions(clusterOptions = ClusterOptions(
        cluster = true,
        clusterRadius = 50,
        circleRadius = 18.0,
        textColor = textColor,
        textSize = 13.0,
        // ClusterOptions wants an Expression (a bindgen Value crashes when the
        // annotation plugin builds its cluster text layer).
        textField = clusterText(style?.glyph ?: "").let { text ->
          if (text is String) Expression.literal(text) else Expression.fromRaw(text.toString())
        },
        colorLevels = listOf(Pair(0, color)),
      ))
    } else null
    val manager = engine.mapView.annotations.createPointAnnotationManager(AnnotationConfig(null, id, id, sourceOptions))
    manager.iconAllowOverlap = overlap
    manager.iconIgnorePlacement = overlap
    manager.addClickListener(OnPointAnnotationClickListener { annotation ->
      val markerId = markerIds[annotation.id] ?: return@OnPointAnnotationClickListener false
      markerTapped(markerId)
      true
    })
    manager.addDragListener(object : OnPointAnnotationDragListener {
      override fun onAnnotationDragStarted(annotation: com.mapbox.maps.plugin.annotation.Annotation<*>) =
        drag(annotation) { engine.listener?.onMarkerDragStart(it) }

      override fun onAnnotationDrag(annotation: com.mapbox.maps.plugin.annotation.Annotation<*>) =
        drag(annotation) { engine.listener?.onMarkerDrag(it) }

      override fun onAnnotationDragFinished(annotation: com.mapbox.maps.plugin.annotation.Annotation<*>) =
        drag(annotation) { engine.listener?.onMarkerDragEnd(it) }
    })
    if (clusteringId.isNotEmpty()) {
      manager.addClusterClickListener(OnClusterClickListener { cluster ->
        clusterTapped(clusteringId, id, cluster.originalFeature)
        true
      })
    }
    managers[key] = manager
    managerSources[key] = id
    return manager
  }

  /** `{count}` in the cluster glyph becomes the number of markers; empty shows the count. */
  private fun clusterText(glyph: String): Any {
    val count = JSONArray().put("to-string").put(JSONArray().put("get").put("point_count"))
    if (glyph.isEmpty()) return count
    if (!glyph.contains("{count}")) return glyph
    val parts = glyph.split("{count}")
    val concat = JSONArray().put("concat")
    parts.forEachIndexed { i, part ->
      if (part.isNotEmpty()) concat.put(part)
      if (i < parts.size - 1) concat.put(count)
    }
    return concat
  }

  private fun dropManager(key: String) {
    val manager = managers.remove(key) ?: return
    managerSources.remove(key)
    for ((id, p) in placed.toList()) if (p.managerKey == key) {
      markerIds.remove(p.annotation.id)
      placed.remove(id)
    }
    engine.mapView.annotations.removeAnnotationManager(manager)
  }

  private fun drag(annotation: com.mapbox.maps.plugin.annotation.Annotation<*>, send: (MarkerDragEvent) -> Unit) {
    val markerId = markerIds[annotation.id] ?: return
    val point = (annotation as? PointAnnotation)?.point ?: return
    send(MarkerDragEvent(markerId, point.latitude(), point.longitude()))
    if (calloutFor == markerId) hideCallout()
  }

  // Markers

  private fun sync() {
    val wanted = markers.filter { it.visible }.associateBy { it.id }
    for ((id, p) in placed.toList()) {
      if (id in viewMarkers) continue
      val next = wanted[id]
      if (next == null || managerKey(next) != p.managerKey) {
        managers[p.managerKey]?.delete(p.annotation)
        markerIds.remove(p.annotation.id)
        placed.remove(id)
        if (next == null && selected == id) deselect(id)
      }
    }
    for (marker in wanted.values) {
      val previous = placed[marker.id]
      if (previous != null && previous.marker == marker) continue
      place(marker, previous)
    }
  }

  private fun place(marker: NativeMarker, previous: Placed?) {
    val isSelected = selected == marker.id
    val photo = if (marker.style == MarkerStyle.IMAGE || marker.style == MarkerStyle.AVATAR) MarkerPhotos.cached(marker.imageUri) else null
    if (photo == null && marker.imageUri.isNotEmpty() && (marker.style == MarkerStyle.IMAGE || marker.style == MarkerStyle.AVATAR)) {
      MarkerPhotos.load(engine.context, marker.imageUri) { bitmap ->
        if (bitmap == null) engine.report("marker ${marker.id}: could not load ${marker.imageUri}")
        val current = markers.firstOrNull { it.id == marker.id } ?: return@load
        if (bitmap != null && !engine.destroyed) place(current, placed[current.id])
      }
    }
    val image = MapboxMarkerImages.image(engine.context, marker, photo, isSelected)
    val point = Point.fromLngLat(marker.longitude, marker.latitude)
    val key = managerKey(marker)
    val manager = manager(key)
    if (previous != null && previous.managerKey == key) {
      val a = previous.annotation
      a.point = point
      apply(a, marker, image)
      manager.update(a)
      placed[marker.id] = Placed(marker, key, a, image)
    } else {
      val options = PointAnnotationOptions().withPoint(point).withDraggable(marker.draggable)
      val annotation = manager.create(options)
      apply(annotation, marker, image)
      manager.update(annotation)
      markerIds[annotation.id] = marker.id
      placed[marker.id] = Placed(marker, key, annotation, image)
    }
  }

  private fun apply(a: PointAnnotation, marker: NativeMarker, image: MarkerImage?) {
    if (image != null) {
      a.iconImageBitmap = image.bitmap
      a.iconAnchor = IconAnchor.TOP_LEFT
      a.iconOffset = listOf(-image.anchorX / density, -image.anchorY / density)
    }
    a.iconOpacity = if (image == null) 0.0 else marker.opacity.coerceIn(0.0, 1.0)
    a.symbolSortKey = marker.zIndex
    a.isDraggable = marker.draggable
  }

  fun coordinates(ids: Set<String>): List<MapCoordinate> {
    val all = markers.filter { it.visible }.map { it.id to MapCoordinate(it.latitude, it.longitude) } +
      viewMarkers.values.map { it.marker.id to MapCoordinate(it.marker.latitude, it.marker.longitude) }
    return all.filter { ids.isEmpty() || it.first in ids }.map { it.second }
  }

  // Selection and callouts

  private fun markerTapped(id: String) {
    engine.listener?.onMarkerPress(id)
    select(id, false)
  }

  fun select(id: String, programmatic: Boolean) {
    if (selected == id) return
    selected?.let { deselect(it) }
    selected = id
    restyle(id)
    showCallout(id)
  }

  fun deselect(id: String) {
    if (selected != id) return
    selected = null
    hideCallout()
    restyle(id)
    engine.listener?.onMarkerDeselect(id)
  }

  /** A tap on the map: deselects. Never takes the tap. */
  fun handleMapClick(): Boolean {
    selected?.let { deselect(it) }
    return false
  }

  /** Pins and balloons grow while selected. */
  private fun restyle(id: String) {
    val p = placed[id] ?: return
    if (id in viewMarkers) return
    if (p.marker.style != MarkerStyle.PIN && p.marker.style != MarkerStyle.MARKER) return
    place(p.marker, p)
  }

  private fun showCallout(id: String) {
    hideCallout()
    val marker = markers.firstOrNull { it.id == id } ?: viewMarkers[id]?.marker ?: return
    if (!marker.calloutEnabled || (marker.title.isEmpty() && marker.subtitle.isEmpty() && marker.calloutDetail.isEmpty())) return
    val view = calloutView(marker)
    // The callout sits above the marker's picture.
    val top = when {
      viewMarkers[id] != null -> viewMarkers[id]!!.bitmap?.let { it.height * marker.anchorY } ?: 0.0
      else -> placed[id]?.image?.anchorY?.toDouble() ?: 0.0
    }
    val options = ViewAnnotationOptions.Builder()
      .geometry(Point.fromLngLat(marker.longitude, marker.latitude))
      .variableAnchors(listOf(ViewAnnotationAnchorConfig.Builder().anchor(ViewAnnotationAnchor.BOTTOM).offsetY(top + 6 * density).build()))
      .allowOverlap(true)
      .priority(Long.MAX_VALUE / 2)
      .build()
    engine.mapView.viewAnnotationManager.addViewAnnotation(view, options)
    callout = view
    calloutFor = id
  }

  private fun hideCallout() {
    callout?.let { engine.mapView.viewAnnotationManager.removeViewAnnotation(it) }
    callout = null
    calloutFor = null
  }

  private fun calloutView(marker: NativeMarker): View {
    val ctx = engine.context
    val d = density.toFloat()
    val row = LinearLayout(ctx).apply {
      orientation = LinearLayout.HORIZONTAL
      gravity = Gravity.CENTER_VERTICAL
      background = GradientDrawable().apply {
        setColor(Color.WHITE)
        cornerRadius = 12 * d
      }
      elevation = 6 * d
      setPadding((12 * d).toInt(), (8 * d).toInt(), (12 * d).toInt(), (8 * d).toInt())
      setOnClickListener { engine.listener?.onCalloutPress(marker.id) }
    }
    accessory(marker, marker.leftCalloutAccessory, CalloutAccessorySide.LEFT)?.let { row.addView(it) }
    val texts = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
    if (marker.title.isNotEmpty()) {
      texts.addView(TextView(ctx).apply {
        text = marker.title
        setTextColor(Color.rgb(28, 28, 30))
        textSize = 15f
        typeface = Typeface.DEFAULT_BOLD
      })
    }
    val detail = marker.calloutDetail.ifEmpty { marker.subtitle }
    if (detail.isNotEmpty()) {
      texts.addView(TextView(ctx).apply {
        text = detail
        setTextColor(Color.rgb(99, 99, 102))
        textSize = 13f
        maxWidth = (240 * d).toInt()
      })
    }
    row.addView(texts)
    accessory(marker, marker.rightCalloutAccessory, CalloutAccessorySide.RIGHT)?.let { row.addView(it) }
    // A view annotation: Mapbox's FrameLayout needs margin layout params.
    row.layoutParams = android.widget.FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
    return row
  }

  /** A callout accessory: text or ⓘ button, or a picture. */
  private fun accessory(marker: NativeMarker, a: NativeCalloutAccessory, side: CalloutAccessorySide): View? {
    val ctx = engine.context
    val d = density.toFloat()
    val tint = MapboxColors.parse(a.color) ?: Color.rgb(10, 132, 255)
    val view: View = when (a.kind) {
      CalloutAccessoryKind.NONE -> return null
      CalloutAccessoryKind.DETAIL, CalloutAccessoryKind.INFO -> TextView(ctx).apply {
        text = "ⓘ"
        textSize = 20f
        setTextColor(tint)
      }
      CalloutAccessoryKind.BUTTON -> TextView(ctx).apply {
        text = a.text.ifEmpty { a.symbol.ifEmpty { "›" } }
        textSize = 15f
        typeface = Typeface.DEFAULT_BOLD
        setTextColor(tint)
      }
      CalloutAccessoryKind.IMAGE -> {
        if (a.imageUri.isEmpty()) return null
        ImageView(ctx).apply {
          layoutParams = LinearLayout.LayoutParams((32 * d).toInt(), (32 * d).toInt())
          scaleType = ImageView.ScaleType.CENTER_CROP
          MarkerPhotos.load(ctx, a.imageUri) { bitmap -> if (bitmap != null) setImageBitmap(bitmap) }
        }
      }
    }
    val margin = (8 * d).toInt()
    val params = (view.layoutParams as? LinearLayout.LayoutParams)
      ?: LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT)
    if (side == CalloutAccessorySide.LEFT) params.rightMargin = margin else params.leftMargin = margin
    view.layoutParams = params
    if (a.kind != CalloutAccessoryKind.IMAGE) {
      view.setOnClickListener { engine.listener?.onCalloutAccessoryPress(CalloutAccessoryEvent(marker.id, side)) }
    }
    return view
  }

  // Clusters

  private fun clusterTapped(clusteringId: String, sourceId: String, feature: com.mapbox.geojson.Feature) {
    val point = feature.geometry() as? Point
    engine.map.getGeoJsonClusterLeaves(sourceId, feature, 10_000L, 0L) { result ->
      val leaves = result.value?.featureCollection ?: emptyList()
      val ids = leaves.mapNotNull { leaf ->
        val annotationId = leaf.id() ?: leaf.getStringProperty("PointAnnotation")
        annotationId?.let { markerIds[it] }
      }
      engine.main.post {
        engine.listener?.onClusterPress(ClusterPressEvent(clusteringId, ids.joinToString(","),
          point?.latitude() ?: 0.0, point?.longitude() ?: 0.0))
      }
    }
  }

  // MarkerView

  fun setViewMarker(marker: NativeMarker, image: Bitmap?) {
    val existing = viewMarkers[marker.id]
    if (existing == null) {
      viewMarkers[marker.id] = ViewMarker(marker, image, null)
    } else {
      existing.marker = marker
      if (image != null) existing.bitmap = image
    }
    showViewMarker(marker.id)
  }

  fun setViewMarkerImage(image: Bitmap?, id: String) {
    val vm = viewMarkers[id] ?: return
    vm.bitmap = image
    showViewMarker(id)
  }

  fun removeViewMarker(id: String) {
    val vm = viewMarkers.remove(id) ?: return
    vm.view?.let { engine.mapView.viewAnnotationManager.removeViewAnnotation(it) }
    placed.remove(id)?.let { p ->
      managers[p.managerKey]?.delete(p.annotation)
      markerIds.remove(p.annotation.id)
    }
    if (selected == id) deselect(id)
  }

  private fun showViewMarker(id: String) {
    val vm = viewMarkers[id] ?: return
    val marker = vm.marker
    val bitmap = vm.bitmap
    if (marker.draggable) {
      // View annotations cannot be dragged: a point annotation with the views' picture.
      vm.view?.let { engine.mapView.viewAnnotationManager.removeViewAnnotation(it) }
      vm.view = null
      if (bitmap == null) return
      val key = "viewmarkers|overlap:true"
      val manager = manager(key)
      val point = Point.fromLngLat(marker.longitude, marker.latitude)
      val previous = placed[id]
      val a = if (previous != null && previous.managerKey == key) previous.annotation
      else manager.create(PointAnnotationOptions().withPoint(point).withDraggable(true)).also { markerIds[it.id] = id }
      a.point = point
      a.iconImageBitmap = bitmap
      a.iconAnchor = IconAnchor.TOP_LEFT
      a.iconOffset = listOf(-marker.anchorX * bitmap.width / density, -marker.anchorY * bitmap.height / density)
      a.iconOpacity = marker.opacity.coerceIn(0.0, 1.0)
      a.symbolSortKey = marker.zIndex
      a.isDraggable = true
      manager.update(a)
      placed[id] = Placed(marker, key, a, MarkerImage(bitmap, (marker.anchorX * bitmap.width).toFloat(), (marker.anchorY * bitmap.height).toFloat()))
      return
    }
    // Not draggable: a view annotation.
    placed.remove(id)?.let { p ->
      managers[p.managerKey]?.delete(p.annotation)
      markerIds.remove(p.annotation.id)
    }
    val w = bitmap?.width ?: 1
    val h = bitmap?.height ?: 1
    val view = vm.view ?: ImageView(engine.context).also { iv ->
      iv.setOnClickListener { markerTapped(id) }
      vm.view = iv
    }
    view.setImageBitmap(bitmap)
    view.alpha = marker.opacity.toFloat().coerceIn(0f, 1f)
    // Mapbox puts view annotations in a FrameLayout, which measures children
    // with margins: plain ViewGroup.LayoutParams crash it on the next layout.
    view.layoutParams = android.widget.FrameLayout.LayoutParams(w, h)
    val anchor = ViewAnnotationAnchorConfig.Builder()
      .anchor(ViewAnnotationAnchor.CENTER)
      .offsetX((0.5 - marker.anchorX) * w)
      .offsetY((marker.anchorY - 0.5) * h)
      .build()
    val overlap = marker.collisionMode == MarkerCollisionMode.NONE || marker.displayPriority >= 1000
    val options = ViewAnnotationOptions.Builder()
      .geometry(Point.fromLngLat(marker.longitude, marker.latitude))
      .width(w.toDouble())
      .height(h.toDouble())
      .variableAnchors(listOf(anchor))
      .allowOverlap(overlap)
      .visible(marker.visible && bitmap != null)
      .priority(marker.zIndex.toLong())
      .build()
    val manager = engine.mapView.viewAnnotationManager
    // Registered with the manager is not the same as attached: the view only
    // gets a parent on the next layout, so a second update before that (a
    // MarkerView re-renders right away) must update, not add again (Mapbox
    // throws "Trying to add view annotation that was already added").
    val registered = manager.getViewAnnotationOptions(view) != null
    if (!registered || !manager.updateViewAnnotation(view, options)) {
      if (registered) manager.removeViewAnnotation(view)
      manager.addViewAnnotation(view, options)
    }
  }

  fun destroy() {
    hideCallout()
    for (manager in managers.values) engine.mapView.annotations.removeAnnotationManager(manager)
    managers.clear()
  }
}
