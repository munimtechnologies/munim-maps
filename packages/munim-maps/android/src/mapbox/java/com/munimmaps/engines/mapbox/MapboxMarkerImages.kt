package com.munimmaps.engines.mapbox

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.LruCache
import com.margelo.nitro.munimmaps.FeatureVisibility
import com.margelo.nitro.munimmaps.MarkerBadge
import com.margelo.nitro.munimmaps.MarkerBadgePosition
import com.margelo.nitro.munimmaps.MarkerStyle
import com.margelo.nitro.munimmaps.NativeMarker
import com.munimmaps.models.ModelAssets
import java.util.concurrent.Executors
import kotlin.math.ceil
import kotlin.math.max

/**
 * A marker's picture: the bitmap and where the coordinate sits in it, in
 * pixels. Mapbox draws it with `icon-anchor: top-left` and an `icon-offset`
 * of minus that point.
 */
internal class MarkerImage(val bitmap: Bitmap, val anchorX: Float, val anchorY: Float)

/**
 * Draws munim-maps' marker styles for Mapbox (the Android twin of iOS's
 * `MarkerImages`): MapKit's pin, the balloon `marker` with its glyph (and the
 * title under it), `image`, `avatar` with its ring and badges, `label` and
 * `dot`. Images from `imageUri` load once, off the main thread
 * ([MarkerPhotos]).
 */
internal object MapboxMarkerImages {
  private val cache = LruCache<String, MarkerImage>(128)

  /** The image for a marker, or null while its photo loads (image style). */
  fun image(context: Context, marker: NativeMarker, photo: Bitmap?, selected: Boolean): MarkerImage? {
    val density = context.resources.displayMetrics.density
    val key = key(marker, photo, selected)
    cache.get(key)?.let { return it }
    val image = when (marker.style) {
      MarkerStyle.PIN -> pin(marker, density, selected)
      MarkerStyle.MARKER -> balloon(marker, density, selected)
      MarkerStyle.IMAGE -> picture(marker, photo, density) ?: return null
      MarkerStyle.AVATAR -> avatar(marker, photo, density)
      MarkerStyle.LABEL -> label(marker, density)
      MarkerStyle.DOT -> dot(marker, density)
    }
    cache.put(key, image)
    return image
  }

  private fun key(m: NativeMarker, photo: Bitmap?, selected: Boolean): String {
    val badges = m.badges.joinToString(";") { "${it.text}/${it.position}/${it.color}/${it.textColor}" }
    return listOf(m.style, m.imageUri, System.identityHashCode(photo), m.imageSize, m.color, m.glyph, m.glyphColor,
      m.borderColor, m.borderWidth, badges, m.title, m.subtitle, m.titleVisibility, m.subtitleVisibility,
      m.anchorX, m.anchorY, selected).joinToString("|")
  }

  private fun bitmap(w: Float, h: Float, density: Float): Pair<Bitmap, Canvas> {
    val bitmap = Bitmap.createBitmap(max(1, ceil(w * density).toInt()), max(1, ceil(h * density).toInt()), Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    canvas.scale(density, density)
    return bitmap to canvas
  }

  private fun paint(color: Int) = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }

  private val red = Color.rgb(255, 59, 48)

  /** MapKit's pin: a round head on a needle; the tip is the coordinate. */
  private fun pin(m: NativeMarker, density: Float, selected: Boolean): MarkerImage {
    val s = if (selected) 1.2f else 1f
    val w = 26f * s
    val h = 44f * s
    val (bitmap, canvas) = bitmap(w, h, density)
    val color = MapboxColors.parse(m.color) ?: red
    val head = 9f * s
    val cx = w / 2
    val cy = head + 2f * s
    // Needle
    val needle = paint(Color.rgb(120, 120, 128)).apply { strokeWidth = 2f * s; strokeCap = Paint.Cap.ROUND }
    canvas.drawLine(cx, cy, cx, h - 1f * s, needle)
    // Head with a soft shadow and a highlight.
    val shadow = paint(Color.argb(70, 0, 0, 0))
    canvas.drawCircle(cx + 0.6f * s, cy + 1f * s, head, shadow)
    canvas.drawCircle(cx, cy, head, paint(color))
    canvas.drawCircle(cx - head * 0.35f, cy - head * 0.35f, head * 0.3f, paint(Color.argb(110, 255, 255, 255)))
    return MarkerImage(bitmap, cx * density, (h - 1f * s) * density)
  }

  /** MapKit's balloon marker: a round balloon with a tail, the glyph inside, the title under it. */
  private fun balloon(m: NativeMarker, density: Float, selected: Boolean): MarkerImage {
    val s = if (selected) 1.35f else 1f
    val d = 30f * s
    val tail = 8f * s
    val color = MapboxColors.parse(m.color) ?: red
    val glyphColor = MapboxColors.parse(m.glyphColor) ?: Color.WHITE
    val showTitle = m.title.isNotEmpty() && m.titleVisibility != FeatureVisibility.HIDDEN
    val showSubtitle = m.subtitle.isNotEmpty() && m.subtitleVisibility != FeatureVisibility.HIDDEN && (selected || m.subtitleVisibility == FeatureVisibility.VISIBLE)
    val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      textSize = 12f
      typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
      textAlign = Paint.Align.CENTER
    }
    val subtitlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      textSize = 11f
      textAlign = Paint.Align.CENTER
    }
    val titleWidth = if (showTitle) titlePaint.measureText(m.title) + 6 else 0f
    val subtitleWidth = if (showSubtitle) subtitlePaint.measureText(m.subtitle) + 6 else 0f
    val w = maxOf(d + 4, titleWidth, subtitleWidth)
    val textHeight = (if (showTitle) 15f else 0f) + (if (showSubtitle) 14f else 0f)
    val h = d + tail + 2 + textHeight
    val (bitmap, canvas) = bitmap(w, h, density)
    val cx = w / 2
    val r = d / 2
    val cy = r + 1
    val tipY = d + tail
    val path = Path().apply {
      addCircle(cx, cy, r, Path.Direction.CW)
      moveTo(cx - r * 0.55f, cy + r * 0.8f)
      lineTo(cx, tipY)
      lineTo(cx + r * 0.55f, cy + r * 0.8f)
      close()
    }
    canvas.save()
    canvas.translate(0f, 1f)
    canvas.drawPath(path, paint(Color.argb(60, 0, 0, 0)))
    canvas.restore()
    canvas.drawPath(path, paint(color))
    // SF Symbols (`glyphSymbol`) are Apple's; Android draws the text glyph or a dot.
    val glyph = m.glyph
    if (glyph.isNotEmpty()) {
      val glyphPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = glyphColor
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        textSize = if (glyph.length <= 2) 15f * s else 11f * s
      }
      val fm = glyphPaint.fontMetrics
      canvas.drawText(glyph, cx, cy - (fm.ascent + fm.descent) / 2, glyphPaint)
    } else {
      canvas.drawCircle(cx, cy, r * 0.28f, paint(glyphColor))
    }
    var y = tipY + 2
    fun drawOutlined(text: String, p: Paint, color: Int) {
      val fm = p.fontMetrics
      val baseline = y - fm.ascent
      p.style = Paint.Style.STROKE
      p.strokeWidth = 3f
      p.color = Color.WHITE
      canvas.drawText(text, cx, baseline, p)
      p.style = Paint.Style.FILL
      p.color = color
      canvas.drawText(text, cx, baseline, p)
    }
    if (showTitle) {
      drawOutlined(m.title, titlePaint, Color.rgb(28, 28, 30))
      y += 15f
    }
    if (showSubtitle) drawOutlined(m.subtitle, subtitlePaint, Color.rgb(99, 99, 102))
    return MarkerImage(bitmap, cx * density, tipY * density)
  }

  private fun picture(m: NativeMarker, photo: Bitmap?, density: Float): MarkerImage? {
    photo ?: return null
    val w = (if (m.imageSize > 0) m.imageSize.toFloat() else photo.width / density)
    val h = w * photo.height / max(1, photo.width)
    val pad = if (m.badges.isEmpty()) 0f else 8f
    val (bitmap, canvas) = bitmap(w + pad * 2, h + pad * 2, density)
    val rect = RectF(pad, pad, pad + w, pad + h)
    canvas.drawBitmap(photo, null, rect, Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
    drawBadges(canvas, m.badges, rect)
    return anchored(m, bitmap)
  }

  private fun avatar(m: NativeMarker, photo: Bitmap?, density: Float): MarkerImage {
    val d = if (m.imageSize > 0) m.imageSize.toFloat() else 44f
    val pad = 8f
    val (bitmap, canvas) = bitmap(d + pad * 2, d + pad * 2, density)
    val circle = RectF(pad, pad, pad + d, pad + d)
    val ring = paint(MapboxColors.parse(m.borderColor) ?: Color.WHITE).apply { setShadowLayer(3f, 0f, 1f, Color.argb(64, 0, 0, 0)) }
    canvas.drawOval(circle, ring)
    val inset = max(0.0, m.borderWidth).toFloat()
    val inner = RectF(circle.left + inset, circle.top + inset, circle.right - inset, circle.bottom - inset)
    canvas.save()
    canvas.clipPath(Path().apply { addOval(inner, Path.Direction.CW) })
    canvas.drawRect(inner, paint(Color.rgb(224, 224, 224)))
    if (photo != null) {
      val scale = max(inner.width() / max(1, photo.width), inner.height() / max(1, photo.height))
      val pw = photo.width * scale
      val ph = photo.height * scale
      canvas.drawBitmap(photo, null, RectF(inner.centerX() - pw / 2, inner.centerY() - ph / 2, inner.centerX() + pw / 2, inner.centerY() + ph / 2),
        Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
    }
    canvas.restore()
    drawBadges(canvas, m.badges, circle)
    return anchored(m, bitmap)
  }

  private fun label(m: NativeMarker, density: Float): MarkerImage {
    val text = m.title.ifEmpty { " " }
    val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      textSize = 13f
      typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
      color = Color.WHITE
    }
    val w = ceil(p.measureText(text)) + 20f
    val h = 26f
    val (bitmap, canvas) = bitmap(w, h, density)
    val rect = RectF(1f, 1f, w - 1f, h - 1f)
    canvas.drawRoundRect(rect, rect.height() / 2, rect.height() / 2, paint(MapboxColors.parse(m.color) ?: Color.argb(230, 26, 26, 26)))
    val fm = p.fontMetrics
    canvas.drawText(text, 10f, h / 2 - (fm.ascent + fm.descent) / 2, p)
    return anchored(m, bitmap)
  }

  private fun dot(m: NativeMarker, density: Float): MarkerImage {
    val d = if (m.imageSize > 0) m.imageSize.toFloat() else 14f
    val (bitmap, canvas) = bitmap(d, d, density)
    canvas.drawOval(RectF(0f, 0f, d, d), paint(MapboxColors.parse(m.borderColor) ?: Color.WHITE))
    val ring = if (m.borderWidth > 0) m.borderWidth.toFloat() else 2f
    canvas.drawOval(RectF(ring, ring, d - ring, d - ring), paint(MapboxColors.parse(m.color) ?: Color.rgb(10, 132, 255)))
    return anchored(m, bitmap)
  }

  private fun anchored(m: NativeMarker, bitmap: Bitmap) =
    MarkerImage(bitmap, (m.anchorX.toFloat() * bitmap.width), (m.anchorY.toFloat() * bitmap.height))

  private fun drawBadges(canvas: Canvas, badges: Array<MarkerBadge>, rect: RectF) {
    for (badge in badges) {
      if (badge.text.isEmpty()) continue
      val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = 10f
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        color = MapboxColors.parse(badge.textColor) ?: Color.WHITE
        textAlign = Paint.Align.CENTER
      }
      val h = 18f
      val w = max(h, ceil(p.measureText(badge.text)) + 9f)
      val (cx, cy) = when (badge.position) {
        MarkerBadgePosition.TOP_LEFT -> rect.left + w / 2 - 6 to rect.top + h / 2 - 6
        MarkerBadgePosition.TOP_RIGHT -> rect.right - w / 2 + 6 to rect.top + h / 2 - 6
        MarkerBadgePosition.BOTTOM_LEFT -> rect.left + w / 2 - 6 to rect.bottom - h / 2 + 6
        MarkerBadgePosition.BOTTOM_RIGHT -> rect.right - w / 2 + 6 to rect.bottom - h / 2 + 6
        MarkerBadgePosition.BOTTOM -> rect.centerX() to rect.bottom - h / 2 + 6
      }
      val pill = RectF(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)
      canvas.drawRoundRect(pill, h / 2, h / 2, paint(MapboxColors.parse(badge.color) ?: Color.rgb(18, 18, 18)))
      canvas.drawRoundRect(pill, h / 2, h / 2, Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = 1.5f
        color = Color.WHITE
      })
      val fm = p.fontMetrics
      canvas.drawText(badge.text, pill.centerX(), pill.centerY() - (fm.ascent + fm.descent) / 2, p)
    }
  }

  /** A cluster balloon: a circle in the cluster colour with the text. */
  fun cluster(context: Context, color: Int, textColor: Int, text: String): MarkerImage {
    val density = context.resources.displayMetrics.density
    val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      textSize = 13f
      typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
      this.color = textColor
      textAlign = Paint.Align.CENTER
    }
    val d = max(34f, p.measureText(text) + 16f)
    val (bitmap, canvas) = bitmap(d, 34f, density)
    canvas.drawRoundRect(RectF(1f, 1f, d - 1f, 33f), 16f, 16f, paint(color))
    val fm = p.fontMetrics
    canvas.drawText(text, d / 2, 17f - (fm.ascent + fm.descent) / 2, p)
    return MarkerImage(bitmap, bitmap.width / 2f, bitmap.height / 2f)
  }
}

/**
 * Pictures from URIs (marker images, avatars, style images, puck images):
 * `http(s)://`, `file://`, absolute paths, `data:` URIs, `asset:/`, and
 * React Native release-build names (drawable or raw resources). Decoded off
 * the main thread, cached, delivered on the main thread.
 */
internal object MarkerPhotos {
  private val cache = LruCache<String, Bitmap>(48)
  private val executor = Executors.newFixedThreadPool(2)
  private val main = Handler(Looper.getMainLooper())
  private val waiting = mutableMapOf<String, MutableList<(Bitmap?) -> Unit>>()

  fun cached(uri: String): Bitmap? = if (uri.isEmpty()) null else cache.get(uri)

  fun load(context: Context, uri: String, completion: (Bitmap?) -> Unit) {
    if (uri.isEmpty()) {
      completion(null)
      return
    }
    cache.get(uri)?.let {
      completion(it)
      return
    }
    synchronized(waiting) {
      waiting[uri]?.let {
        it.add(completion)
        return
      }
      waiting[uri] = mutableListOf(completion)
    }
    val app = context.applicationContext
    fun finish(bitmap: Bitmap?) {
      if (bitmap != null) cache.put(uri, bitmap)
      val callbacks = synchronized(waiting) { waiting.remove(uri) ?: mutableListOf() }
      main.post { callbacks.forEach { it(bitmap) } }
    }
    val local = decodeLocal(app, uri)
    if (local != null || uri.startsWith("data:")) {
      finish(local)
      return
    }
    ModelAssets.load(app, uri) { result ->
      val bytes = result.getOrNull()
      if (bytes == null) {
        finish(null)
      } else {
        executor.execute { finish(BitmapFactory.decodeByteArray(bytes, 0, bytes.size)) }
      }
    }
  }

  /** `data:` URIs and drawable resources, decoded right away; null for everything else. */
  private fun decodeLocal(context: Context, uri: String): Bitmap? {
    if (uri.startsWith("data:")) {
      val comma = uri.indexOf(',')
      if (comma < 0) return null
      return try {
        val bytes = Base64.decode(uri.substring(comma + 1), Base64.DEFAULT)
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
      } catch (_: Exception) {
        null
      }
    }
    val parsed = Uri.parse(uri)
    if (parsed.scheme.isNullOrEmpty() && !uri.startsWith("/")) {
      val name = uri.substringBeforeLast('.')
      val id = context.resources.getIdentifier(name, "drawable", context.packageName)
      if (id != 0) return BitmapFactory.decodeResource(context.resources, id)
    }
    return null
  }
}
