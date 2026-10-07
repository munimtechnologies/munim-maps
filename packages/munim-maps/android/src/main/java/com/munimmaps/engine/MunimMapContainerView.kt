package com.munimmaps.engine

import android.content.Context
import android.widget.FrameLayout
import com.margelo.nitro.munimmaps.MapProvider

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

  /** Replaces the engine when [provider] differs; returns the new one, or null when unchanged. */
  fun setProvider(provider: MapProvider): MunimMapEngine? {
    if (engine?.provider == provider) return null
    engine?.let {
      removeView(it.view)
      it.destroy()
    }
    val next = MunimMapEngines.create(provider, context)
    engine = next
    addView(next.view, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    layoutChildren()
    return next
  }

  fun destroy() {
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
