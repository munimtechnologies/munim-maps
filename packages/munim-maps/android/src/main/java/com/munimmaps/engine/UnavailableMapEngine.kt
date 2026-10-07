package com.munimmaps.engine

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import com.margelo.nitro.munimmaps.MapProvider
import com.munimmaps.models.MunimModelLayer

/**
 * What a map shows when its engine is not built into the app, or not
 * implemented yet: a plain panel saying so. Reports the reason through
 * `onError` once a listener is set.
 */
class UnavailableMapEngine(
  context: Context,
  override val provider: MapProvider,
  val reason: String,
) : MunimMapEngine {
  private val frame = FrameLayout(context)
  override val view: View get() = frame
  override val modelLayer = MunimModelLayer(context)
  private var reported = false

  override var listener: MunimMapEngineListener? = null
    set(value) {
      field = value
      if (value != null && !reported) {
        reported = true
        value.onError(reason)
      }
    }

  init {
    val dark = (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
      Configuration.UI_MODE_NIGHT_YES
    frame.setBackgroundColor(if (dark) Color.rgb(31, 31, 31) else Color.rgb(237, 237, 237))
    val label = TextView(context).apply {
      text = "${provider.displayName}\n\n$reason"
      gravity = Gravity.CENTER
      setTextColor(if (dark) Color.LTGRAY else Color.DKGRAY)
      textSize = 13f
      val pad = (24 * context.resources.displayMetrics.density).toInt()
      setPadding(pad, pad, pad, pad)
    }
    frame.addView(label, FrameLayout.LayoutParams(
      FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
  }

  override fun reportUnsupported(what: String) {}
}
