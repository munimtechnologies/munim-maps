package com.munimmaps.engines.maplibre

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.drawable.GradientDrawable
import android.view.View
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.pow

/**
 * A scale bar (MapLibre Android has none): the longest round distance that
 * fits in a quarter of the map's width, metric or imperial.
 */
internal class ScaleBarView(context: Context) : View(context) {
  private val density = context.resources.displayMetrics.density
  var metric = true
  /** Metres per pixel at the map's centre. */
  var metersPerPixel = 0.0
    set(value) {
      if (field != value) {
        field = value
        invalidate()
      }
    }
  private val line = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    color = Color.parseColor("#3A3A3C")
    strokeWidth = 2 * density
    style = Paint.Style.STROKE
  }
  private val halo = Paint(line).apply {
    color = Color.WHITE
    strokeWidth = 4 * density
  }
  private val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    color = Color.parseColor("#1C1C1E")
    textSize = 11 * density
    setShadowLayer(2f, 0f, 0f, Color.WHITE)
  }

  override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
    setMeasuredDimension((140 * density).toInt(), (28 * density).toInt())
  }

  private fun nice(value: Double): Double {
    if (value <= 0) return 0.0
    val p = 10.0.pow(floor(log10(value)))
    val f = value / p
    return p * when {
      f >= 5 -> 5.0
      f >= 2 -> 2.0
      else -> 1.0
    }
  }

  override fun onDraw(canvas: Canvas) {
    if (metersPerPixel <= 0) return
    val maxPx = width * 0.9
    val unit = if (metric) 1.0 else 0.3048
    val maxValue = maxPx * metersPerPixel / unit
    var value = nice(maxValue)
    var label: String
    if (metric) {
      label = if (value >= 1000) "${trim(value / 1000)} km" else "${trim(value)} m"
    } else {
      if (maxValue >= 5280) {
        value = nice(maxValue / 5280) * 5280
        label = "${trim(value / 5280)} mi"
      } else {
        label = "${trim(value)} ft"
      }
    }
    val px = (value * unit / metersPerPixel).toFloat()
    val y = height - 4 * density
    val path = Path().apply {
      moveTo(2 * density, y - 6 * density)
      lineTo(2 * density, y)
      lineTo(2 * density + px, y)
      lineTo(2 * density + px, y - 6 * density)
    }
    canvas.drawPath(path, halo)
    canvas.drawPath(path, line)
    canvas.drawText(label, 4 * density, y - 8 * density, text)
  }

  private fun trim(v: Double): String = if (v == floor(v)) v.toLong().toString() else "%.1f".format(v)
}

/** munim-maps' user tracking button: cycles none → follow → follow with heading. */
internal class TrackingButton(context: Context) : View(context) {
  private val density = context.resources.displayMetrics.density
  var mode = 0
    set(value) {
      field = value
      invalidate()
    }
  private val arrow = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = MarkerBitmaps.SYSTEM_BLUE }
  private val outline = Paint(Paint.ANTI_ALIAS_FLAG).apply {
    color = MarkerBitmaps.SYSTEM_BLUE
    style = Paint.Style.STROKE
    strokeWidth = 1.6f * density
    strokeJoin = Paint.Join.ROUND
  }

  init {
    background = GradientDrawable().apply {
      cornerRadius = 10 * density
      setColor(Color.WHITE)
    }
    elevation = 4 * density
    contentDescription = "Track location"
  }

  override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
    val s = (44 * density).toInt()
    setMeasuredDimension(s, s)
  }

  override fun onDraw(canvas: Canvas) {
    val cx = width / 2f
    val cy = height / 2f
    val r = 9 * density
    val path = Path().apply {
      moveTo(cx + r, cy - r)
      lineTo(cx - r, cy - r * 0.1f)
      lineTo(cx - r * 0.1f, cy + r * 0.1f)
      lineTo(cx + r * 0.1f, cy + r)
      close()
    }
    canvas.drawPath(path, if (mode == 0) outline else arrow)
    if (mode == 2) canvas.drawCircle(cx, cy + r + 4 * density, 2 * density, arrow)
  }
}
