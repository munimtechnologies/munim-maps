package com.munimmaps.engine

import android.content.Context
import android.graphics.Bitmap
import android.widget.FrameLayout
import com.margelo.nitro.munimmaps.MapProvider
import com.margelo.nitro.munimmaps.NativeCircle
import com.margelo.nitro.munimmaps.NativeMarker
import com.margelo.nitro.munimmaps.NativePolygon

/**
 * Shows one map engine at a time, filling itself, and swaps engines when the
 * provider changes. React Native's `MunimMapView` is one of these.
 *
 * React Native lays its views out itself and does not run Android layout
 * passes for native children, so this measures and lays out its children
 * whenever it is laid out or a child asks for layout.
 */
class MunimMapContainerView(context: Context) : FrameLayout(context) {
  var engine: MunimMapEngine? = null
    private set

  private val shapeTransitions = MunimShapeTransitions(
    drawCircles = { engine?.setCircles(it) },
    drawPolygons = { engine?.setPolygons(it) },
  )

  private val markerTransitions = MunimMarkerTransitions(
    draw = { engine?.setMarkers(it) },
    drawViewMarker = { marker, image -> engine?.setViewMarker(marker, image) },
    move = { engine?.moveMarkers(it) ?: true },
  )

  /** Sets the engine's markers, gliding the ones with an `animationDuration` to their new coordinate. */
  fun setMarkers(markers: Array<NativeMarker>) {
    markerTransitions.setMarkers(markers, passThrough = engine?.animatesMarkerTransitions ?: false)
  }

  /** A `MarkerView`'s marker and picture, gliding like [setMarkers]. */
  fun setViewMarker(marker: NativeMarker, image: Bitmap?) {
    markerTransitions.setViewMarker(marker, image, passThrough = engine?.animatesMarkerTransitions ?: false)
  }

  fun setViewMarkerImage(image: Bitmap?, id: String) {
    markerTransitions.setViewMarkerImage(image, id)
    engine?.setViewMarkerImage(image, id)
  }

  fun removeViewMarker(id: String) {
    markerTransitions.removeViewMarker(id)
    engine?.removeViewMarker(id)
  }

  /** Sets the engine's circles, gliding the ones with an `animationDuration` from where they are drawn now. */
  fun setCircles(circles: Array<NativeCircle>) {
    shapeTransitions.setCircles(circles, passThrough = engine?.animatesShapeTransitions ?: false)
  }

  /** Sets the engine's polygons; see [setCircles]. */
  fun setPolygons(polygons: Array<NativePolygon>) {
    shapeTransitions.setPolygons(polygons, passThrough = engine?.animatesShapeTransitions ?: false)
  }

  /**
   * Replaces the engine when [provider] (or, for providers with more than one
   * renderer, the one [options] ask for) differs; returns the new one, or
   * null when unchanged.
   */
  fun setProvider(provider: MapProvider, options: org.json.JSONObject = org.json.JSONObject()): MunimMapEngine? {
    val variant = MunimMapEngines.variant(provider, options)
    val current = engine
    if (current != null && current.provider == provider && current.variant == variant) return null
    shapeTransitions.finish()
    markerTransitions.finish()
    markerTransitions.reset()
    engine?.let {
      removeView(it.view)
      it.destroy()
    }
    val next = MunimMapEngines.create(provider, context, options)
    engine = next
    addView(next.view, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    layoutChildren()
    // `MarkerView`s stay on the map when the engine changes.
    markerTransitions.resendViewMarkers()
    return next
  }

  fun destroy() {
    shapeTransitions.finish()
    markerTransitions.clear()
    engine?.destroy()
    engine = null
    removeAllViews()
  }

  override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
    super.onLayout(changed, left, top, right, bottom)
    layoutChildren()
  }

  private fun layoutChildren() {
    val w = width
    val h = height
    if (w <= 0 || h <= 0) return
    for (i in 0 until childCount) {
      val child = getChildAt(i)
      child.measure(MeasureSpec.makeMeasureSpec(w, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(h, MeasureSpec.EXACTLY))
      child.layout(0, 0, w, h)
    }
  }

  private val measureAndLayout = Runnable {
    measure(MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY))
    layout(left, top, right, bottom)
  }

  override fun requestLayout() {
    super.requestLayout()
    // React Native does not lay out native children; do it on the next frame.
    @Suppress("SENSELESS_COMPARISON")
    if (measureAndLayout != null) post(measureAndLayout)
  }
}
