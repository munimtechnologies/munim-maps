package com.margelo.nitro.munimmaps

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import com.facebook.react.uimanager.ThemedReactContext
import com.munimmaps.engine.MunimMapContainerView
import com.munimmaps.engine.MunimMapEngine

/**
 * React Native `MarkerView` on Android: draws its React Native children into
 * a bitmap and hands it to the `MunimMapView` it sits in as a marker
 * ([MunimMapEngine.setViewMarker]), like iOS's `HybridMarkerView`.
 *
 * Android's Nitro views cannot hold React children, so the JavaScript side
 * lays the marker out differently: `MunimMapView` puts its children in an
 * off-screen sibling of the map, and each `MarkerView` is a container with
 * the children's view first and this (1-point, empty) view after it. This
 * view draws its first sibling and finds the map among its ancestors'
 * children.
 *
 * It draws when something changed, not on every React render: the marker's
 * props (JavaScript keeps the same object while they are equal), the
 * children (`renderKey`, a hash of them), or the children's view itself
 * (invalidated: a picture finished loading, text changed, it was laid out
 * again), checked before each frame with [View.isDirty]. The map only gets
 * a picture that looks different from the last one. `tracksViewChanges`
 * draws 15 times a second on top.
 */
class HybridMarkerView(context: ThemedReactContext) : HybridMarkerViewSpec() {
  private val main = Handler(Looper.getMainLooper())
  private var map: MunimMapEngine? = null
  private var registeredId = ""
  private val pending = mutableListOf<Runnable>()
  private val density = context.resources.displayMetrics.densityDpi

  /** The last picture handed to the map, to skip identical ones. */
  private var lastBitmap: Bitmap? = null
  private var lastWidth = 0
  private var lastHeight = 0
  private var markerChanged = false
  private var contentChanged = false
  private var dirtyDrawQueued = false

  /** Before each frame: the children were invalidated or resized since the last picture. */
  private val preDraw = ViewTreeObserver.OnPreDrawListener {
    val content = content()
    if (content != null && registeredId.isNotEmpty() && !dirtyDrawQueued &&
      (content.isDirty || content.width != lastWidth || content.height != lastHeight)
    ) {
      dirtyDrawQueued = true
      main.post {
        dirtyDrawQueued = false
        draw()
      }
    }
    true
  }

  private val host = object : View(context) {
    override fun onAttachedToWindow() {
      super.onAttachedToWindow()
      viewTreeObserver.addOnPreDrawListener(preDraw)
      register()
      trackingChanged()
      scheduleRedraws()
    }

    override fun onDetachedFromWindow() {
      viewTreeObserver.removeOnPreDrawListener(preDraw)
      unregister()
      stopTracking()
      pending.forEach { main.removeCallbacks(it) }
      pending.clear()
      super.onDetachedFromWindow()
    }
  }

  override val view: View get() = host

  // Nitro sets a prop only when JavaScript passes a different value.
  override var marker: NativeMarker = DEFAULT_MARKER
    set(value) {
      field = value
      markerChanged = true
    }
  override var tracksViewChanges: Boolean = false
    set(value) {
      if (field == value) return
      field = value
      main.post { trackingChanged() }
    }
  override var renderKey: Double = 0.0
    set(value) {
      if (field == value) return
      field = value
      contentChanged = true
    }

  override fun afterUpdate() {
    val newMarker = markerChanged
    val newContent = contentChanged
    markerChanged = false
    contentChanged = false
    if (!newMarker && !newContent) return
    main.post {
      if (newMarker) {
        if (marker.id != registeredId) unregister()
        // Replaces the marker with this id: position, anchor, title…
        register()
      }
      scheduleRedraws()
    }
  }

  override fun redraw() {
    main.post { draw(force = true) }
  }

  /**
   * Fabric lays the children out and draws them after props arrive, so
   * draw a few times after a change; unchanged pictures do not reach the map.
   */
  private fun scheduleRedraws() {
    pending.forEach { main.removeCallbacks(it) }
    pending.clear()
    for (delay in longArrayOf(0, 150, 500)) {
      val work = Runnable { draw() }
      pending += work
      main.postDelayed(work, delay)
    }
  }

  private val track = object : Runnable {
    override fun run() {
      draw()
      main.postDelayed(this, 1000L / 15)
    }
  }
  private var tracking = false

  private fun trackingChanged() {
    val wanted = tracksViewChanges && host.isAttachedToWindow
    if (wanted && !tracking) {
      tracking = true
      main.post(track)
    } else if (!wanted) {
      stopTracking()
    }
  }

  private fun stopTracking() {
    tracking = false
    main.removeCallbacks(track)
  }

  /** The engine of the `MunimMapView` this marker belongs to. */
  private fun findMap(): MunimMapEngine? {
    var ancestor = host.parent as? ViewGroup
    var depth = 0
    while (ancestor != null && depth < 10) {
      for (i in 0 until ancestor.childCount) {
        val child = ancestor.getChildAt(i)
        if (child is MunimMapContainerView) return child.engine
      }
      ancestor = ancestor.parent as? ViewGroup
      depth += 1
    }
    return null
  }

  private fun register() {
    if (!host.isAttachedToWindow || marker.id.isEmpty()) return
    val engine = map ?: findMap() ?: return
    map = engine
    registeredId = marker.id
    val bitmap = snapshot()
    remember(bitmap)
    engine.setViewMarker(marker, bitmap)
  }

  private fun unregister() {
    if (registeredId.isEmpty()) return
    map?.removeViewMarker(registeredId)
    registeredId = ""
    lastBitmap = null
  }

  private fun remember(bitmap: Bitmap?) {
    lastBitmap = bitmap
    val content = content()
    lastWidth = content?.width ?: 0
    lastHeight = content?.height ?: 0
  }

  /** The children's view: the container's first child that is not this view. */
  private fun content(): View? {
    val container = host.parent as? ViewGroup ?: return null
    for (i in 0 until container.childCount) {
      val child = container.getChildAt(i)
      if (child !== host) return child
    }
    return null
  }

  private fun snapshot(): Bitmap? {
    val content = content() ?: return null
    if (content.width < 1 || content.height < 1) return null
    val bitmap = Bitmap.createBitmap(content.width, content.height, Bitmap.Config.ARGB_8888)
    bitmap.density = density
    content.draw(Canvas(bitmap))
    return bitmap
  }

  /** Draws the children; the map gets the picture when it changed (or always, with [force]). */
  private fun draw(force: Boolean = false) {
    if (!host.isAttachedToWindow) return
    if (registeredId.isEmpty()) {
      register()
      return
    }
    val bitmap = snapshot()
    val last = lastBitmap
    if (!force && bitmap != null && last != null && !last.isRecycled && bitmap.sameAs(last)) {
      remember(last)
      return
    }
    remember(bitmap)
    map?.setViewMarkerImage(bitmap, registeredId)
  }

  companion object {
    private val NO_ACCESSORY = NativeCalloutAccessory(CalloutAccessoryKind.NONE, "", "", "", "")
    val DEFAULT_MARKER = NativeMarker(
      id = "", latitude = 0.0, longitude = 0.0, title = "", subtitle = "", style = MarkerStyle.IMAGE,
      color = "", glyph = "", imageUri = "", imageSize = 0.0, borderColor = "", borderWidth = 0.0,
      badges = emptyArray(), anchorX = 0.5, anchorY = 0.5, zIndex = 0.0, draggable = false,
      clusteringId = "", calloutEnabled = false, opacity = 1.0, visible = true, displayPriority = 1000.0,
      collisionMode = MarkerCollisionMode.RECTANGLE, titleVisibility = FeatureVisibility.ADAPTIVE,
      subtitleVisibility = FeatureVisibility.ADAPTIVE, glyphSymbol = "", selectedGlyphSymbol = "",
      glyphColor = "", animatesWhenAdded = false, leftCalloutAccessory = NO_ACCESSORY,
      rightCalloutAccessory = NO_ACCESSORY, calloutDetail = "",
    )
  }
}
