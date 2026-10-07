package com.munimmaps.engines.maplibre

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.util.LruCache
import com.margelo.nitro.munimmaps.FeatureVisibility
import com.margelo.nitro.munimmaps.MarkerBadgePosition
import com.margelo.nitro.munimmaps.MarkerStyle
import com.margelo.nitro.munimmaps.NativeClusterStyle
import com.margelo.nitro.munimmaps.NativeMarker
import kotlin.math.max
import kotlin.math.min

/**
 * Draws munim-maps' marker looks as bitmaps for MapLibre's symbol layers:
 * MapKit's pin and balloon, pictures, avatars with a ring and badges, text
 * pills and dots, plus cluster balloons. Sizes are in points, drawn at
 * `density` pixels per point.
 */
internal object MarkerBitmaps {
  private val cache = object : LruCache<String, Bitmap>(24 * 1024 * 1024) {
    override fun sizeOf(key: String, value: Bitmap) = value.byteCount
  }

  /** The image and where its anchor is (0…1 of its size). */
  data class Drawn(val bitmap: Bitmap, val anchorX: Double, val anchorY: Double)

  fun color(value: String, fallback: Int): Int {
    val s = value.trim()
    if (s.isEmpty()) return fallback
    return try {
      if (s.startsWith("#") && (s.length == 9)) {
        // #RRGGBBAA (CSS) → ARGB
        val rgba = s.substring(1).toLong(16)
        val a = (rgba and 0xFF).toInt()
        val rgb = (rgba shr 8).toInt()
        Color.argb(a, Color.red(rgb), Color.green(rgb), Color.blue(rgb))
      } else if (s.startsWith("#") && s.length == 4) {
        val r = s[1].toString().repeat(2)
        val g = s[2].toString().repeat(2)
        val b = s[3].toString().repeat(2)
        Color.parseColor("#$r$g$b")
      } else if (s.startsWith("rgb")) {
        val parts = s.substringAfter("(").substringBefore(")").split(",").map { it.trim() }
        val a = if (parts.size > 3) (parts[3].toDouble() * 255).toInt() else 255
        Color.argb(a, parts[0].toDouble().toInt(), parts[1].toDouble().toInt(), parts[2].toDouble().toInt())
      } else {
        Color.parseColor(s)
      }
    } catch (_: Exception) {
      fallback
    }
  }

  /** CSS colour for MapLibre's style (`rgba(…)`), from any munim colour. */
  fun css(value: String, fallback: Int): String {
    val c = color(value, fallback)
    return "rgba(${Color.red(c)},${Color.green(c)},${Color.blue(c)},${Color.alpha(c) / 255.0})"
  }

  const val SYSTEM_RED = 0xFFFF3B30.toInt()
  const val SYSTEM_BLUE = 0xFF0A84FF.toInt()

  fun key(m: NativeMarker, hasPhoto: Boolean): String = listOf(
    m.style.name, m.imageUri, hasPhoto, m.imageSize, m.color, m.glyph, m.glyphColor, m.borderColor,
    m.borderWidth, m.title, m.badges.joinToString(";") { "${it.text}/${it.position}/${it.color}/${it.textColor}" },
  ).joinToString("|")

  fun draw(m: NativeMarker, photo: Bitmap?, density: Float, selected: Boolean = false): Drawn {
    val cacheKey = key(m, photo != null) + "|" + density + "|" + selected
    val (defaultX, defaultY) = defaultAnchor(m.style)
    cache.get(cacheKey)?.let { return Drawn(it, defaultX, defaultY) }
    val bitmap = when (m.style) {
      MarkerStyle.PIN -> pin(m, density)
      MarkerStyle.MARKER -> balloon(color(m.color, SYSTEM_RED), m.glyph, color(m.glyphColor, Color.WHITE), density, selected).let {
        if (m.title.isNotEmpty() && m.titleVisibility != FeatureVisibility.HIDDEN) titled(it, m.title, density) else it
      }
      MarkerStyle.IMAGE -> picture(m, photo, density)
      MarkerStyle.AVATAR -> avatar(m, photo, density)
      MarkerStyle.LABEL -> label(m, density)
      MarkerStyle.DOT -> dot(m, density)
    }
    cache.put(cacheKey, bitmap)
    return Drawn(bitmap, defaultX, defaultY)
  }

  /** MapKit-like default anchors: pins and balloons stand on the point. */
  fun defaultAnchor(style: MarkerStyle): Pair<Double, Double> = when (style) {
    MarkerStyle.PIN -> 0.5 to 1.0
    MarkerStyle.MARKER -> 0.5 to 1.0
    else -> 0.5 to 0.5
  }

  private fun bitmap(widthPt: Float, heightPt: Float, density: Float): Pair<Bitmap, Canvas> {
    val b = Bitmap.createBitmap(max(1, (widthPt * density).toInt()), max(1, (heightPt * density).toInt()), Bitmap.Config.ARGB_8888)
    val c = Canvas(b)
    c.scale(density, density)
    return b to c
  }

  private fun paint(color: Int) = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }

  private fun shadow(p: Paint) {
    p.setShadowLayer(2.5f, 0f, 1f, 0x55000000)
  }

  private fun pin(m: NativeMarker, density: Float): Bitmap {
    val (b, c) = bitmap(28f, 40f, density)
    val head = paint(color(m.color, SYSTEM_RED)).also(::shadow)
    c.drawRect(13f, 18f, 15f, 39f, paint(0xFF8E8E93.toInt()))
    c.drawCircle(14f, 12f, 10f, head)
    c.drawCircle(11f, 9f, 3f, paint(0x66FFFFFF))
    return b
  }

  /** Height of the balloon itself in a titled marker image, 0…1 (its point is the anchor). */
  fun balloonFraction(m: NativeMarker, bitmap: Bitmap, density: Float, selected: Boolean): Double {
    if (m.style != MarkerStyle.MARKER || m.title.isEmpty() || m.titleVisibility == FeatureVisibility.HIDDEN) return 1.0
    val balloonPx = (if (selected) 44f * 1.5f else 44f) * density
    return (balloonPx / bitmap.height).toDouble()
  }

  /** A balloon with its title under it, as MapKit draws it (no style glyphs needed). */
  fun titled(balloon: Bitmap, title: String, density: Float): Bitmap {
    val t = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = 0xFF1C1C1E.toInt()
      textSize = 11f
      typeface = Typeface.DEFAULT_BOLD
      textAlign = Paint.Align.CENTER
    }
    val halo = Paint(t).apply {
      color = Color.WHITE
      style = Paint.Style.STROKE
      strokeWidth = 3f
    }
    val text = title.take(32)
    val bw = balloon.width / density
    val bh = balloon.height / density
    val w = max(bw, t.measureText(text) + 8f)
    val h = bh + 15f
    val (b, c) = bitmap(w, h, density)
    c.save()
    c.scale(1 / density, 1 / density)
    c.drawBitmap(balloon, (w - bw) / 2 * density, 0f, null)
    c.restore()
    c.drawText(text, w / 2, bh + 11f, halo)
    c.drawText(text, w / 2, bh + 11f, t)
    return b
  }

  /** MapKit's marker balloon: a circle with a point under it, glyph inside. */
  fun balloon(fill: Int, glyph: String, glyphColor: Int, density: Float, selected: Boolean = false): Bitmap {
    val scale = if (selected) 1.5f else 1f
    val w = 34f * scale
    val h = 44f * scale
    val (b, c) = bitmap(w, h, density)
    val r = 14f * scale
    val cx = w / 2
    val cy = r + 2f * scale
    val path = Path().apply {
      addCircle(cx, cy, r, Path.Direction.CW)
      moveTo(cx - r * 0.55f, cy + r * 0.8f)
      lineTo(cx, h - 3f * scale)
      lineTo(cx + r * 0.55f, cy + r * 0.8f)
      close()
    }
    val p = paint(fill).also(::shadow)
    c.drawPath(path, p)
    if (glyph.isNotEmpty()) {
      val t = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = glyphColor
        textSize = (if (glyph.length > 2) 10f else 14f) * scale
        typeface = Typeface.DEFAULT_BOLD
        textAlign = Paint.Align.CENTER
      }
      val text = if (glyph.length > 4) glyph.take(4) else glyph
      c.drawText(text, cx, cy - (t.descent() + t.ascent()) / 2, t)
    } else {
      c.drawCircle(cx, cy, 4.5f * scale, paint(glyphColor))
    }
    return b
  }

  private fun picture(m: NativeMarker, photo: Bitmap?, density: Float): Bitmap {
    val w = (if (m.imageSize > 0) m.imageSize else 32.0).toFloat()
    if (photo == null) {
      val (b, c) = bitmap(w, w, density)
      c.drawRoundRect(RectF(0f, 0f, w, w), 6f, 6f, paint(0x33000000))
      return b
    }
    val h = w * photo.height / max(1, photo.width)
    val (b, c) = bitmap(w, h, density)
    c.drawBitmap(photo, null, RectF(0f, 0f, w, h), Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG))
    drawBadges(c, m, RectF(0f, 0f, w, h))
    return b
  }

  private fun avatar(m: NativeMarker, photo: Bitmap?, density: Float): Bitmap {
    val d = (if (m.imageSize > 0) m.imageSize else 44.0).toFloat()
    val ring = (if (m.borderWidth > 0) m.borderWidth else 2.0).toFloat()
    val pad = 10f
    val size = d + pad * 2
    val (b, c) = bitmap(size, size, density)
    val rect = RectF(pad, pad, pad + d, pad + d)
    val ringPaint = paint(color(m.borderColor, Color.WHITE)).also(::shadow)
    c.drawOval(rect, ringPaint)
    val inner = RectF(rect.left + ring, rect.top + ring, rect.right - ring, rect.bottom - ring)
    if (photo != null) {
      val shader = BitmapShader(photo, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP)
      val scale = max(inner.width() / photo.width, inner.height() / photo.height)
      val matrix = Matrix().apply {
        setScale(scale, scale)
        postTranslate(inner.left + (inner.width() - photo.width * scale) / 2, inner.top + (inner.height() - photo.height * scale) / 2)
      }
      shader.setLocalMatrix(matrix)
      c.drawOval(inner, Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply { this.shader = shader })
    } else {
      c.drawOval(inner, paint(color(m.color, 0xFFD1D1D6.toInt())))
      val initials = m.title.split(" ").filter { it.isNotEmpty() }.take(2).joinToString("") { it.take(1) }.uppercase()
      if (initials.isNotEmpty()) {
        val t = Paint(Paint.ANTI_ALIAS_FLAG).apply {
          color = Color.WHITE
          textSize = d * 0.38f
          typeface = Typeface.DEFAULT_BOLD
          textAlign = Paint.Align.CENTER
        }
        c.drawText(initials, inner.centerX(), inner.centerY() - (t.descent() + t.ascent()) / 2, t)
      }
    }
    drawBadges(c, m, rect)
    return b
  }

  private fun drawBadges(c: Canvas, m: NativeMarker, rect: RectF) {
    for (badge in m.badges) {
      if (badge.text.isEmpty()) continue
      val t = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = color(badge.textColor, Color.WHITE)
        textSize = 10f
        typeface = Typeface.DEFAULT_BOLD
        textAlign = Paint.Align.CENTER
      }
      val w = max(16f, t.measureText(badge.text) + 8f)
      val h = 15f
      val (x, y) = when (badge.position) {
        MarkerBadgePosition.TOP_LEFT -> rect.left + w / 2 - 4f to rect.top + h / 2 - 4f
        MarkerBadgePosition.TOP_RIGHT -> rect.right - w / 2 + 4f to rect.top + h / 2 - 4f
        MarkerBadgePosition.BOTTOM_LEFT -> rect.left + w / 2 - 4f to rect.bottom - h / 2 + 4f
        MarkerBadgePosition.BOTTOM_RIGHT -> rect.right - w / 2 + 4f to rect.bottom - h / 2 + 4f
        MarkerBadgePosition.BOTTOM -> rect.centerX() to rect.bottom - h / 2 + 6f
      }
      val pill = RectF(x - w / 2, y - h / 2, x + w / 2, y + h / 2)
      c.drawRoundRect(pill, h / 2, h / 2, paint(color(badge.color, 0xE6111111.toInt())).also(::shadow))
      c.drawText(badge.text, x, y - (t.descent() + t.ascent()) / 2, t)
    }
  }

  private fun label(m: NativeMarker, density: Float): Bitmap {
    val t = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = color(m.glyphColor, Color.WHITE)
      textSize = 13f
      typeface = Typeface.DEFAULT_BOLD
      textAlign = Paint.Align.CENTER
    }
    val text = m.title.ifEmpty { m.glyph }
    val w = min(240f, t.measureText(text) + 20f)
    val h = 26f
    val (b, c) = bitmap(w + 4f, h + 4f, density)
    val pill = RectF(2f, 2f, 2f + w, 2f + h)
    c.drawRoundRect(pill, h / 2, h / 2, paint(color(m.color, 0xE6111111.toInt())).also(::shadow))
    c.drawText(text, pill.centerX(), pill.centerY() - (t.descent() + t.ascent()) / 2, t)
    return b
  }

  private fun dot(m: NativeMarker, density: Float): Bitmap {
    val d = (if (m.imageSize > 0) m.imageSize else 12.0).toFloat()
    val ring = (if (m.borderWidth > 0) m.borderWidth else 2.0).toFloat()
    val (b, c) = bitmap(d + 4f, d + 4f, density)
    c.drawCircle(d / 2 + 2f, d / 2 + 2f, d / 2, paint(color(m.borderColor, Color.WHITE)).also(::shadow))
    c.drawCircle(d / 2 + 2f, d / 2 + 2f, d / 2 - ring, paint(color(m.color, SYSTEM_BLUE)))
    return b
  }

  /** A cluster balloon with the count (or the style's glyph with `{count}`). */
  fun cluster(style: NativeClusterStyle?, count: Int, density: Float): Bitmap {
    val glyph = (style?.glyph?.takeIf { it.isNotEmpty() } ?: "{count}").replace("{count}", count.toString())
    return balloon(color(style?.color ?: "", SYSTEM_BLUE), glyph, color(style?.glyphColor ?: "", Color.WHITE), density)
  }
}
