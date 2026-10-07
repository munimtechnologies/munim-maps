package com.munimmaps.engines.google

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.text.TextUtils
import android.util.LruCache
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import com.google.android.gms.maps.GoogleMap
import com.google.android.gms.maps.model.AdvancedMarkerOptions
import com.google.android.gms.maps.model.BitmapDescriptor
import com.google.android.gms.maps.model.BitmapDescriptorFactory
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.Marker
import com.google.android.gms.maps.model.MarkerOptions
import com.google.android.gms.maps.model.PinConfig
import com.google.maps.android.clustering.Cluster
import com.google.maps.android.clustering.ClusterItem
import com.google.maps.android.clustering.ClusterManager
import com.google.maps.android.clustering.algo.GridBasedAlgorithm
import com.google.maps.android.clustering.algo.NonHierarchicalDistanceBasedAlgorithm
import com.google.maps.android.clustering.view.DefaultClusterRenderer
import com.google.maps.android.collections.MarkerManager
import com.margelo.nitro.munimmaps.CalloutAccessoryKind
import com.margelo.nitro.munimmaps.ClusterPressEvent
import com.margelo.nitro.munimmaps.MarkerBadgePosition
import com.margelo.nitro.munimmaps.MarkerCollisionMode
import com.margelo.nitro.munimmaps.MarkerDragEvent
import com.margelo.nitro.munimmaps.MarkerStyle
import com.margelo.nitro.munimmaps.NativeMarker
import com.munimmaps.models.ModelAssets
import org.json.JSONArray
import kotlin.math.max
import kotlin.math.min

// Markers on Google (Android): classic markers, or advanced markers with
// pins and collision behaviour on maps with a Map ID; clustering with
// android-maps-utils (one ClusterManager per `clusteringId`, sharing the
// engine's MarkerManager); info windows.

/** A clustered marker, for android-maps-utils. */
class GoogleClusterItem(val id: String, var latLng: LatLng, var itemTitle: String?, var itemSnippet: String?, var z: Float) : ClusterItem {
  /** The `clusteringId` this item is in. */
  var tag: String = ""
  override fun getPosition(): LatLng = latLng
  override fun getTitle(): String? = itemTitle
  override fun getSnippet(): String? = itemSnippet
  override fun getZIndex(): Float = z
}

internal fun GoogleMapEngine.markerOptions(id: String): GJson = options["markers"][id]

internal val GoogleMapEngine.usesAdvancedMarkers: Boolean
  get() = !options["mapId"].string.isNullOrEmpty()

internal fun GoogleMapEngine.markerId(marker: Marker): String? = marker.tag as? String

internal fun GoogleMapEngine.setUpMarkerCollection(collection: MarkerManager.Collection) {
  collection.setOnMarkerClickListener { marker -> markerTapped(marker) }
  collection.setOnMarkerDragListener(object : GoogleMap.OnMarkerDragListener {
    override fun onMarkerDragStart(marker: Marker) {
      val id = markerId(marker) ?: return
      listener?.onMarkerDragStart(MarkerDragEvent(id, marker.position.latitude, marker.position.longitude))
    }

    override fun onMarkerDrag(marker: Marker) {
      val id = markerId(marker) ?: return
      emit("markerDrag", GOut.obj("id" to id, "latitude" to marker.position.latitude, "longitude" to marker.position.longitude))
    }

    override fun onMarkerDragEnd(marker: Marker) {
      val id = markerId(marker) ?: return
      markerData[id]?.let { markerData[id] = it.copy(latitude = marker.position.latitude, longitude = marker.position.longitude) }
      listener?.onMarkerDragEnd(MarkerDragEvent(id, marker.position.latitude, marker.position.longitude))
    }
  })
  collection.setOnInfoWindowClickListener { marker -> infoWindowTapped(marker) }
  collection.setOnInfoWindowLongClickListener { marker ->
    markerId(marker)?.let { emit("infoWindowLongPress", GOut.obj("id" to it)) }
  }
  collection.setInfoWindowAdapter(GoogleInfoWindowAdapter(this))
}

private fun GoogleMapEngine.infoWindowTapped(marker: Marker) {
  val id = markerId(marker) ?: return
  listener?.onCalloutPress(id)
  emit("infoWindowPress", GOut.obj("id" to id))
}

/** Handles selection itself (Google would also move the camera to the marker). */
internal fun GoogleMapEngine.markerTapped(marker: Marker): Boolean {
  val id = markerId(marker) ?: return false
  if (selectedMarkerId != null && selectedMarkerId != id) listener?.onMarkerDeselect(selectedMarkerId!!)
  selectedMarkerId = id
  listener?.onMarkerPress(id)
  if (marker.title != null || marker.snippet != null) marker.showInfoWindow()
  return true
}

internal fun GoogleMapEngine.selectMarkerById(id: String) {
  val marker = gmsMarkers[id] ?: return
  if (selectedMarkerId != null && selectedMarkerId != id) listener?.onMarkerDeselect(selectedMarkerId!!)
  selectedMarkerId = id
  if (marker.title != null || marker.snippet != null) marker.showInfoWindow()
}

internal fun GoogleMapEngine.deselectMarkerById(id: String) {
  if (selectedMarkerId != id) return
  selectedMarkerId = null
  gmsMarkers[id]?.hideInfoWindow()
  listener?.onMarkerDeselect(id)
}

// MARK: Applying

internal fun GoogleMapEngine.applyMarkers() {
  val map = map ?: return
  val collection = markerCollection ?: return
  val wanted = markers.associateBy { it.id }
  val touched = mutableSetOf<String>()

  for (id in gmsMarkers.keys.toList()) if (id !in wanted) removePlainMarker(id)
  for (id in clusterItems.keys.toList()) if (id !in wanted || wanted[id]?.clusteringId.isNullOrEmpty() || wanted[id]?.visible == false) {
    removeClusterItem(id, touched)
  }

  for ((id, m) in wanted) {
    val extras = markerOptions(id)
    val extrasKey = extras.toString()
    val clusterId = if (m.visible) m.clusteringId else ""
    if (clusterId.isNotEmpty()) {
      removePlainMarker(id)
      val item = clusterItems[id]
      val manager = clusterManager(clusterId, map)
      val title = if (m.calloutEnabled) m.title.ifEmpty { null } else null
      val snippet = if (m.calloutEnabled) m.calloutDetail.ifEmpty { m.subtitle }.ifEmpty { null } else null
      if (item == null || (item.tag != clusterId)) {
        item?.let { removeClusterItem(id, touched) }
        val next = GoogleClusterItem(id, LatLng(m.latitude, m.longitude), title, snippet, m.zIndex.toFloat())
        next.tag = clusterId
        clusterItems[id] = next
        manager.addItem(next)
      } else if (markerData[id] != m || markerExtras[id] != extrasKey) {
        item.latLng = LatLng(m.latitude, m.longitude)
        item.itemTitle = title
        item.itemSnippet = snippet
        item.z = m.zIndex.toFloat()
        manager.updateItem(item)
      }
      touched.add(clusterId)
    } else {
      val advanced = usesAdvancedMarkers && extras["advanced"].bool(true)
      val collision = if (advanced) collisionBehavior(m, extras) else -1
      var marker = gmsMarkers[id]
      if (marker != null && ((marker is com.google.android.gms.maps.model.AdvancedMarker) != advanced ||
          (advanced && advancedCollision[marker] != collision))) {
        // Collision behaviour is only taken when an advanced marker is made.
        removePlainMarker(id)
        marker = null
      }
      if (marker == null) {
        val options = if (advanced) AdvancedMarkerOptions().collisionBehavior(collision) else MarkerOptions()
        options.position(LatLng(m.latitude, m.longitude))
        if (m.animatesWhenAdded) options.alpha(1f)
        marker = (if (options is AdvancedMarkerOptions) collection.addMarker(options) else collection.addMarker(options)) ?: continue
        if (advanced) advancedCollision[marker] = collision
        marker.tag = id
        gmsMarkers[id] = marker
        configureMarker(marker, m, extras)
      } else if (markerData[id] != m || markerExtras[id] != extrasKey) {
        configureMarker(marker, m, extras)
      }
    }
    markerData[id] = m
    markerExtras[id] = extrasKey
  }
  for (id in markerData.keys.toList()) if (id !in wanted) {
    markerData.remove(id)
    markerExtras.remove(id)
  }
  for (clusterId in touched) clusterManagers[clusterId]?.cluster()
  val used = clusterItems.values.map { it.tag }.toSet()
  for (clusterId in clusterManagers.keys.toList()) if (clusterId !in used) {
    clusterManagers.remove(clusterId)?.let {
      it.clearItems()
      it.cluster()
    }
  }
}

private fun GoogleMapEngine.removePlainMarker(id: String) {
  val marker = gmsMarkers.remove(id) ?: return
  markerCollection?.remove(marker)
  if (selectedMarkerId == id) selectedMarkerId = null
}

private fun GoogleMapEngine.removeClusterItem(id: String, touched: MutableSet<String>) {
  val item = clusterItems.remove(id) ?: return
  clusterManagers[item.tag]?.removeItem(item)
  touched.add(item.tag)
}

private fun GoogleMapEngine.configureMarker(marker: Marker, m: NativeMarker, extras: GJson) {
  marker.position = LatLng(m.latitude, m.longitude)
  if (m.calloutEnabled) {
    marker.title = m.title.ifEmpty { null }
    marker.snippet = m.calloutDetail.ifEmpty { m.subtitle }.ifEmpty { null }
  } else {
    marker.title = null
    marker.snippet = null
  }
  marker.zIndex = (extras["zIndex"].double ?: m.zIndex).toFloat()
  marker.isDraggable = m.draggable
  marker.alpha = (extras["opacity"].double ?: m.opacity).toFloat().coerceIn(0f, 1f)
  marker.isVisible = m.visible
  marker.isFlat = extras["flat"].bool(false)
  marker.rotation = extras["rotation"].double(0.0).toFloat()
  marker.setInfoWindowAnchor(extras["infoWindowAnchor"]["x"].double(0.5).toFloat(), extras["infoWindowAnchor"]["y"].double(0.0).toFloat())
  val (icon, anchor) = markerIcon(m, extras, marker is com.google.android.gms.maps.model.AdvancedMarker)
  icon?.let { marker.setIcon(it) }
  val ax = extras["anchor"]["x"].double ?: anchor.first
  val ay = extras["anchor"]["y"].double ?: anchor.second
  marker.setAnchor(ax.toFloat(), ay.toFloat())
}

private val advancedCollision = java.util.WeakHashMap<Marker, Int>()

internal fun collisionBehavior(m: NativeMarker, extras: GJson): Int = when (extras["collisionBehavior"].string) {
  "required" -> AdvancedMarkerOptions.CollisionBehavior.REQUIRED
  "requiredAndHidesOptional" -> AdvancedMarkerOptions.CollisionBehavior.REQUIRED_AND_HIDES_OPTIONAL
  "optionalAndHidesLowerPriority" -> AdvancedMarkerOptions.CollisionBehavior.OPTIONAL_AND_HIDES_LOWER_PRIORITY
  else -> when {
    m.displayPriority >= 1000 -> AdvancedMarkerOptions.CollisionBehavior.REQUIRED_AND_HIDES_OPTIONAL
    m.collisionMode == MarkerCollisionMode.NONE -> AdvancedMarkerOptions.CollisionBehavior.REQUIRED
    else -> AdvancedMarkerOptions.CollisionBehavior.OPTIONAL_AND_HIDES_LOWER_PRIORITY
  }
}

/** The icon and its default anchor for a marker. */
internal fun GoogleMapEngine.markerIcon(m: NativeMarker, extras: GJson, advanced: Boolean): Pair<BitmapDescriptor?, Pair<Double, Double>> {
  val pin = extras["pin"]
  return when (m.style) {
    MarkerStyle.PIN, MarkerStyle.MARKER -> {
      val color = pin["background"].color ?: GJson.parseColor(m.color)
      val descriptor = if (advanced) {
        val builder = PinConfig.builder()
        color?.let { builder.setBackgroundColor(it) }
        (pin["border"].color ?: GJson.parseColor(m.borderColor))?.let { builder.setBorderColor(it) }
        val text = pin["glyph"].string ?: if (m.style == MarkerStyle.MARKER) m.glyph else ""
        val glyphColor = pin["glyphColor"].color ?: GJson.parseColor(m.glyphColor)
        val imageUri = pin["glyphImageUri"].string
        when {
          imageUri != null -> photos[imageUri]?.let { builder.setGlyph(PinConfig.Glyph(BitmapDescriptorFactory.fromBitmap(it))) }
            ?: loadPhoto(imageUri)
          text.isNotEmpty() -> builder.setGlyph(PinConfig.Glyph(text, glyphColor ?: Color.WHITE))
          glyphColor != null -> builder.setGlyph(PinConfig.Glyph(glyphColor))
        }
        BitmapDescriptorFactory.fromPinConfig(builder.build())
      } else if (m.style == MarkerStyle.MARKER && m.glyph.isNotEmpty()) {
        BitmapDescriptorFactory.fromBitmap(GoogleMarkerIcons.balloon(color ?: Color.rgb(234, 67, 53), m.glyph,
          GJson.parseColor(m.glyphColor) ?: Color.WHITE, density.toFloat()))
      } else if (color != null) {
        val hsv = FloatArray(3)
        Color.colorToHSV(color, hsv)
        BitmapDescriptorFactory.defaultMarker(hsv[0])
      } else {
        BitmapDescriptorFactory.defaultMarker()
      }
      descriptor to (0.5 to 1.0)
    }
    MarkerStyle.IMAGE, MarkerStyle.AVATAR -> {
      val photo = if (m.imageUri.isNotEmpty()) photos[m.imageUri] ?: run { loadPhoto(m.imageUri); null } else null
      BitmapDescriptorFactory.fromBitmap(GoogleMarkerIcons.image(m, photo, density.toFloat())) to (m.anchorX to m.anchorY)
    }
    MarkerStyle.LABEL, MarkerStyle.DOT ->
      BitmapDescriptorFactory.fromBitmap(GoogleMarkerIcons.image(m, null, density.toFloat())) to (m.anchorX to m.anchorY)
  }
}

/** Loads a picture (marker photos, glyphs, ground overlays, stamps), then re-applies what uses it. */
internal fun GoogleMapEngine.loadPhoto(uri: String) {
  if (photos.containsKey(uri) || !loadingPhotos.add(uri)) return
  ModelAssets.load(context, uri) { result ->
    loadingPhotos.remove(uri)
    val bitmap = result.getOrNull()?.let { BitmapFactory.decodeByteArray(it, 0, it.size) } ?: drawable(uri)
    if (bitmap == null) {
      reportError("could not load the image $uri: ${result.exceptionOrNull()?.message ?: "not a picture"}")
      return@load
    }
    photos[uri] = bitmap
    for (id in markerData.keys) markerExtras[id] = ""
    applyMarkers()
    clusterManagers.values.forEach { it.cluster() }
    applyPolylines()
    applyGroundOverlays()
  }
}

/** Images `require()`d in a release build are drawable resources named after the file. */
private fun GoogleMapEngine.drawable(uri: String): Bitmap? {
  if (uri.contains("://") || uri.startsWith("/")) return null
  val id = context.resources.getIdentifier(uri.substringBeforeLast('.'), "drawable", context.packageName)
  return if (id == 0) null else BitmapFactory.decodeResource(context.resources, id)
}

// MARK: Clustering

internal fun GoogleMapEngine.clusterManager(clusterId: String, map: GoogleMap): ClusterManager<GoogleClusterItem> {
  clusterManagers[clusterId]?.let { return it }
  val manager = ClusterManager<GoogleClusterItem>(context, map, markerManager!!)
  when (options["clusterAlgorithm"].string) {
    "gridBased" -> manager.setAlgorithm(GridBasedAlgorithm())
    else -> manager.setAlgorithm(NonHierarchicalDistanceBasedAlgorithm())
  }
  val renderer = GoogleClusterRenderer(context, map, manager, this, clusterId)
  options["clusterMinimumSize"].double?.let { renderer.minClusterSize = max(2, it.toInt()) }
  manager.renderer = renderer
  manager.setAnimation(options["animatesClusters"].bool(true))
  manager.setOnClusterClickListener { cluster ->
    val ids = cluster.items.map { it.id }
    listener?.onClusterPress(ClusterPressEvent(clusterId, ids.joinToString(","), cluster.position.latitude, cluster.position.longitude))
    emit("clusterPress", GOut.obj("clusteringId" to clusterId, "markerIds" to JSONArray(ids),
      "latitude" to cluster.position.latitude, "longitude" to cluster.position.longitude))
    true
  }
  manager.setOnClusterItemClickListener { item ->
    renderer.getMarker(item)?.let { markerTapped(it) } ?: run {
      selectedMarkerId = item.id
      listener?.onMarkerPress(item.id)
    }
    true
  }
  manager.setOnClusterItemInfoWindowClickListener { item ->
    listener?.onCalloutPress(item.id)
    emit("infoWindowPress", GOut.obj("id" to item.id))
  }
  manager.markerCollection.setInfoWindowAdapter(GoogleInfoWindowAdapter(this))
  clusterManagers[clusterId] = manager
  return manager
}

/** Clustered markers drawn like the others; cluster balloons in `clusterStyles`. */
class GoogleClusterRenderer(
  context: Context,
  map: GoogleMap,
  manager: ClusterManager<GoogleClusterItem>,
  private val engine: GoogleMapEngine,
  private val clusterId: String,
) : DefaultClusterRenderer<GoogleClusterItem>(context, map, manager) {
  override fun onBeforeClusterItemRendered(item: GoogleClusterItem, markerOptions: MarkerOptions) {
    val m = engine.markerData[item.id] ?: return
    val (icon, anchor) = engine.markerIcon(m, engine.markerOptions(item.id), false)
    icon?.let { markerOptions.icon(it) }
    markerOptions.anchor(anchor.first.toFloat(), anchor.second.toFloat())
    markerOptions.title(item.title).snippet(item.snippet).zIndex(item.z).alpha(m.opacity.toFloat())
  }

  override fun onClusterItemRendered(item: GoogleClusterItem, marker: Marker) {
    marker.tag = item.id
  }

  override fun onClusterItemUpdated(item: GoogleClusterItem, marker: Marker) {
    val m = engine.markerData[item.id] ?: return
    val (icon, anchor) = engine.markerIcon(m, engine.markerOptions(item.id), false)
    icon?.let { marker.setIcon(it) }
    marker.setAnchor(anchor.first.toFloat(), anchor.second.toFloat())
    marker.position = item.position
    marker.title = item.title
    marker.snippet = item.snippet
    marker.tag = item.id
  }

  override fun onBeforeClusterRendered(cluster: Cluster<GoogleClusterItem>, markerOptions: MarkerOptions) {
    markerOptions.icon(icon(cluster.size)).anchor(0.5f, 0.5f)
  }

  override fun onClusterUpdated(cluster: Cluster<GoogleClusterItem>, marker: Marker) {
    marker.setIcon(icon(cluster.size))
  }

  private fun icon(size: Int): BitmapDescriptor {
    val style = engine.clusterStyles.firstOrNull { it.clusteringId == clusterId }
    val text = style?.glyph?.takeIf { it.isNotEmpty() }?.replace("{count}", "$size") ?: "$size"
    return BitmapDescriptorFactory.fromBitmap(GoogleMarkerIcons.cluster(
      text, style?.let { GJson.parseColor(it.color) } ?: Color.rgb(10, 132, 255),
      style?.let { GJson.parseColor(it.glyphColor) } ?: Color.WHITE, size, engine.density.toFloat()))
  }
}

// MARK: Info windows

/** A drawn callout when a marker has a detail or accessories (or `google.markers[id].infoWindow`). */
class GoogleInfoWindowAdapter(private val engine: GoogleMapEngine) : GoogleMap.InfoWindowAdapter {
  override fun getInfoWindow(marker: Marker): View? {
    val id = marker.tag as? String ?: return null
    val m = engine.markerData[id] ?: return null
    val style = engine.markerOptions(id)["infoWindow"]
    val custom = style.exists || m.calloutDetail.isNotEmpty() || m.leftCalloutAccessory.kind != CalloutAccessoryKind.NONE ||
      (m.rightCalloutAccessory.kind != CalloutAccessoryKind.NONE && m.rightCalloutAccessory.kind != CalloutAccessoryKind.DETAIL)
    if (!custom) return null
    val density = engine.density.toFloat()
    val context = engine.context
    val row = LinearLayout(context).apply {
      orientation = LinearLayout.HORIZONTAL
      gravity = Gravity.CENTER_VERTICAL
      val pad = (12 * density).toInt()
      setPadding(pad, (10 * density).toInt(), pad, (10 * density).toInt())
      background = android.graphics.drawable.GradientDrawable().apply {
        cornerRadius = 12 * density
        setColor(style["backgroundColor"].color ?: Color.WHITE)
        setStroke(1, Color.argb(40, 0, 0, 0))
      }
    }
    val textColor = style["textColor"].color ?: Color.BLACK
    val texts = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
    if (m.title.isNotEmpty()) texts.addView(TextView(context).apply {
      text = m.title
      setTextColor(textColor)
      typeface = Typeface.DEFAULT_BOLD
      textSize = 15f
      maxLines = 2
      ellipsize = TextUtils.TruncateAt.END
    })
    val detail = m.calloutDetail.ifEmpty { m.subtitle }
    if (detail.isNotEmpty()) texts.addView(TextView(context).apply {
      text = detail
      setTextColor(Color.argb(190, Color.red(textColor), Color.green(textColor), Color.blue(textColor)))
      textSize = 13f
    })
    texts.maxWidth((style["maxWidth"].double(260.0) * density).toInt())
    row.addView(texts)
    val right = m.rightCalloutAccessory
    if (right.kind == CalloutAccessoryKind.BUTTON && right.text.isNotEmpty()) {
      row.addView(TextView(context).apply {
        text = right.text
        setTextColor(GJson.parseColor(right.color) ?: Color.rgb(10, 132, 255))
        typeface = Typeface.DEFAULT_BOLD
        setPadding((10 * density).toInt(), 0, 0, 0)
      })
    }
    return row
  }

  override fun getInfoContents(marker: Marker): View? = null

  private fun LinearLayout.maxWidth(px: Int) {
    for (i in 0 until childCount) (getChildAt(i) as? TextView)?.maxWidth = px
  }
}

// MARK: Pictures

/** Marker pictures drawn by the engine (the Android twin of iOS's `MarkerImages`). */
object GoogleMarkerIcons {
  private val cache = LruCache<String, Bitmap>(64)

  /** `image`, `avatar`, `label` or `dot`. */
  fun image(m: NativeMarker, photo: Bitmap?, density: Float): Bitmap {
    val key = listOf(m.style.name, m.imageUri, photo != null, m.imageSize, m.color, m.borderColor, m.borderWidth, m.title,
      m.badges.joinToString(";") { "${it.text}/${it.position}/${it.color}/${it.textColor}" }).joinToString("|")
    cache.get(key)?.let { return it }
    val bitmap = when (m.style) {
      MarkerStyle.AVATAR -> avatar(m, photo, density)
      MarkerStyle.IMAGE -> picture(m, photo, density)
      MarkerStyle.LABEL -> label(m, density)
      else -> dot(m, density)
    }
    cache.put(key, bitmap)
    return bitmap
  }

  private fun avatar(m: NativeMarker, photo: Bitmap?, density: Float): Bitmap {
    val d = (if (m.imageSize > 0) m.imageSize else 44.0).toFloat()
    val pad = 14f
    val size = d + pad * 2
    val bitmap = Bitmap.createBitmap((size * density).toInt(), (size * density).toInt(), Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    canvas.scale(density, density)
    val rect = RectF(pad, pad, pad + d, pad + d)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    paint.color = Color.argb(70, 0, 0, 0)
    canvas.drawCircle(rect.centerX(), rect.centerY() + 1, d / 2 + 1, paint)
    if (photo != null) {
      val shader = BitmapShader(photo, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
      val scale = max(d / photo.width, d / photo.height)
      val matrix = Matrix()
      matrix.setScale(scale, scale)
      matrix.postTranslate(rect.left + (d - photo.width * scale) / 2, rect.top + (d - photo.height * scale) / 2)
      shader.setLocalMatrix(matrix)
      paint.color = Color.WHITE
      paint.shader = shader
      canvas.drawCircle(rect.centerX(), rect.centerY(), d / 2, paint)
      paint.shader = null
    } else {
      paint.color = GJson.parseColor(m.color) ?: Color.rgb(142, 142, 147)
      canvas.drawCircle(rect.centerX(), rect.centerY(), d / 2, paint)
      initials(canvas, m.title, rect)
    }
    val ring = m.borderWidth.toFloat()
    if (ring > 0) {
      paint.style = Paint.Style.STROKE
      paint.strokeWidth = ring
      paint.color = GJson.parseColor(m.borderColor) ?: Color.WHITE
      canvas.drawCircle(rect.centerX(), rect.centerY(), d / 2 - ring / 2, paint)
    }
    badges(canvas, m, rect)
    return bitmap
  }

  private fun picture(m: NativeMarker, photo: Bitmap?, density: Float): Bitmap {
    val width = (if (m.imageSize > 0) m.imageSize else 32.0).toFloat()
    val height = if (photo != null) width * photo.height / max(1, photo.width) else width
    val pad = 12f
    val bitmap = Bitmap.createBitmap(((width + pad * 2) * density).toInt(), ((height + pad * 2) * density).toInt(), Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    canvas.scale(density, density)
    val rect = RectF(pad, pad, pad + width, pad + height)
    if (photo != null) canvas.drawBitmap(photo, null, rect, Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG))
    badges(canvas, m, rect)
    return bitmap
  }

  private fun label(m: NativeMarker, density: Float): Bitmap {
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      textSize = 13f
      typeface = Typeface.DEFAULT_BOLD
      color = Color.WHITE
    }
    val text = m.title.ifEmpty { " " }
    val w = paint.measureText(text) + 20
    val h = 26f
    val bitmap = Bitmap.createBitmap(((w + 4) * density).toInt(), ((h + 4) * density).toInt(), Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    canvas.scale(density, density)
    val rect = RectF(2f, 2f, 2 + w, 2 + h)
    val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = GJson.parseColor(m.color) ?: Color.rgb(28, 28, 30) }
    canvas.drawRoundRect(rect, h / 2, h / 2, fill)
    canvas.drawText(text, rect.left + 10, rect.centerY() - (paint.ascent() + paint.descent()) / 2, paint)
    return bitmap
  }

  private fun dot(m: NativeMarker, density: Float): Bitmap {
    val d = (if (m.imageSize > 0) m.imageSize else 12.0).toFloat()
    val size = d + 4
    val bitmap = Bitmap.createBitmap((size * density).toInt(), (size * density).toInt(), Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    canvas.scale(density, density)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    paint.color = Color.WHITE
    canvas.drawCircle(size / 2, size / 2, d / 2 + 1.5f, paint)
    paint.color = GJson.parseColor(m.color) ?: Color.rgb(10, 132, 255)
    canvas.drawCircle(size / 2, size / 2, d / 2, paint)
    return bitmap
  }

  private fun initials(canvas: Canvas, title: String, rect: RectF) {
    val text = title.split(" ").filter { it.isNotEmpty() }.take(2).joinToString("") { it.first().uppercase() }
    if (text.isEmpty()) return
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = Color.WHITE
      textSize = rect.height() * 0.38f
      typeface = Typeface.DEFAULT_BOLD
      textAlign = Paint.Align.CENTER
    }
    canvas.drawText(text, rect.centerX(), rect.centerY() - (paint.ascent() + paint.descent()) / 2, paint)
  }

  private fun badges(canvas: Canvas, m: NativeMarker, rect: RectF) {
    for (badge in m.badges) {
      val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = 11f
        typeface = Typeface.DEFAULT_BOLD
        color = GJson.parseColor(badge.textColor) ?: Color.WHITE
        textAlign = Paint.Align.CENTER
      }
      val w = max(18f, paint.measureText(badge.text) + 10)
      val h = 18f
      val (cx, cy) = when (badge.position) {
        MarkerBadgePosition.TOP_LEFT -> rect.left + 4 to rect.top + 4
        MarkerBadgePosition.TOP_RIGHT -> rect.right - 4 to rect.top + 4
        MarkerBadgePosition.BOTTOM_LEFT -> rect.left + 4 to rect.bottom - 4
        MarkerBadgePosition.BOTTOM_RIGHT -> rect.right - 4 to rect.bottom - 4
        MarkerBadgePosition.BOTTOM -> rect.centerX() to rect.bottom
      }
      val pill = RectF(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)
      val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = GJson.parseColor(badge.color) ?: Color.rgb(28, 28, 30) }
      canvas.drawRoundRect(pill, h / 2, h / 2, fill)
      canvas.drawText(badge.text, pill.centerX(), pill.centerY() - (paint.ascent() + paint.descent()) / 2, paint)
    }
  }

  /** A balloon pin with a glyph (style `marker` without a Map ID). */
  fun balloon(color: Int, glyph: String, glyphColor: Int, density: Float): Bitmap {
    val w = 30f
    val h = 42f
    val bitmap = Bitmap.createBitmap((w * density).toInt(), (h * density).toInt(), Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    canvas.scale(density, density)
    val r = 14f
    val cx = w / 2
    val cy = r + 1
    val path = Path()
    path.addCircle(cx, cy, r, Path.Direction.CW)
    path.moveTo(cx - r * 0.75f, cy + r * 0.66f)
    path.quadTo(cx - 2, cy + r + 8, cx, h - 1)
    path.quadTo(cx + 2, cy + r + 8, cx + r * 0.75f, cy + r * 0.66f)
    path.close()
    val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    paint.color = color
    paint.setShadowLayer(2f, 0f, 1f, Color.argb(90, 0, 0, 0))
    canvas.drawPath(path, paint)
    val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      this.color = glyphColor
      textSize = if (glyph.length > 2) 10f else 14f
      typeface = Typeface.DEFAULT_BOLD
      textAlign = Paint.Align.CENTER
    }
    canvas.drawText(glyph, cx, cy - (text.ascent() + text.descent()) / 2, text)
    return bitmap
  }

  fun cluster(label: String, color: Int, textColor: Int, count: Int, density: Float): Bitmap {
    val d = when {
      count < 10 -> 34f
      count < 100 -> 40f
      count < 1000 -> 46f
      else -> 52f
    }
    val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      this.color = textColor
      textSize = d * 0.36f
      typeface = Typeface.DEFAULT_BOLD
      textAlign = Paint.Align.CENTER
    }
    val w = max(d, text.measureText(label) + 16)
    val bitmap = Bitmap.createBitmap(((w + 4) * density).toInt(), ((d + 4) * density).toInt(), Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    canvas.scale(density, density)
    val rect = RectF(2f, 2f, 2 + w, 2 + d)
    val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      this.color = color
      setShadowLayer(2f, 0f, 1f, Color.argb(80, 0, 0, 0))
    }
    canvas.drawRoundRect(rect, d / 2, d / 2, fill)
    val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      style = Paint.Style.STROKE
      strokeWidth = 2f
      this.color = Color.WHITE
    }
    canvas.drawRoundRect(rect, d / 2, d / 2, ring)
    canvas.drawText(label, rect.centerX(), rect.centerY() - (text.ascent() + text.descent()) / 2, text)
    return bitmap
  }

  @Suppress("unused")
  private fun clamp(v: Float) = min(1f, max(0f, v))
}
