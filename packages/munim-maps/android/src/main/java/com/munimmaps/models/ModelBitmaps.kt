package com.munimmaps.models

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import com.margelo.nitro.munimmaps.NativeMapModel
import kotlin.math.ceil
import kotlin.math.max

/** The pictures iOS draws with UIKit (MapModelNodes), drawn with Android's Canvas. */
internal object ModelBitmaps {
  /** A PNG or JPEG's bytes as a bitmap, or null. */
  fun decode(bytes: ByteArray): Bitmap? = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)

  /**
   * A round picture with an optional ring and a badge pill under it (as
   * iOS's `avatarTexture`): 192 pixels across, wider when the badge needs it.
   */
  fun avatar(image: Bitmap, model: NativeMapModel): Bitmap {
    val diameter = 192f
    val pixelsPerPoint = diameter / (if (model.screenSize > 0) model.screenSize else 44.0).toFloat()
    val badge = model.imageBadge
    val badgeHeight = if (badge.isEmpty()) 0f else 64f
    val text = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = Color.WHITE
      textSize = 40f
      typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }
    val textWidth = if (badge.isEmpty()) 0f else text.measureText(badge)
    val pillWidth = if (badge.isEmpty()) 0f else textWidth + 36
    val width = ceil(max(diameter, pillWidth + 6)).toInt()
    val height = ceil(diameter + badgeHeight * 0.6f).toInt()
    val ringColor = parseColor(model.imageBorderColor)
    val ring = if (ringColor == null) 0f else max(0.0, model.imageBorderWidth).toFloat() * pixelsPerPoint

    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val circle = RectF((width - diameter) / 2, 0f, (width + diameter) / 2, diameter)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    if (ringColor != null && ring > 0) {
      paint.color = argb(ringColor)
      canvas.drawOval(circle, paint)
    }
    val photo = RectF(circle.left + ring, circle.top + ring, circle.right - ring, circle.bottom - ring)
    canvas.save()
    canvas.clipPath(Path().apply { addOval(photo, Path.Direction.CW) })
    paint.color = Color.rgb(230, 230, 230)
    canvas.drawRect(photo, paint)
    // Aspect-fill the picture into the circle.
    val scale = max(photo.width() / max(1, image.width), photo.height() / max(1, image.height))
    val w = image.width * scale
    val h = image.height * scale
    canvas.drawBitmap(image, null, RectF(photo.centerX() - w / 2, photo.centerY() - h / 2,
      photo.centerX() + w / 2, photo.centerY() + h / 2), paint)
    canvas.restore()

    if (badge.isNotEmpty()) {
      val pill = RectF((width - pillWidth) / 2, height - badgeHeight, (width + pillWidth) / 2, height - 6f)
      // White text needs a dark pill: light rings get a near-black pill outlined in the ring colour.
      val pillColor = ringColor?.takeIf { luminance(it) < 0.6f }?.let { argb(it) } ?: Color.rgb(28, 28, 28)
      paint.style = Paint.Style.FILL
      paint.color = pillColor
      val radius = pill.height() / 2
      canvas.drawRoundRect(pill, radius, radius, paint)
      paint.style = Paint.Style.STROKE
      paint.strokeWidth = 5f
      paint.color = ringColor?.let { argb(it) } ?: Color.WHITE
      canvas.drawRoundRect(pill, radius, radius, paint)
      val metrics = text.fontMetrics
      canvas.drawText(badge, pill.centerX() - textWidth / 2, pill.centerY() - (metrics.ascent + metrics.descent) / 2, text)
    }
    return bitmap
  }

  /** A dark text pill, 64 pixels tall (as iOS's `labelNode`). */
  fun label(text: String): Bitmap {
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      color = Color.WHITE
      textSize = 40f
      typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }
    val textWidth = paint.measureText(text)
    val height = 64
    val width = ceil(textWidth + 40).toInt()
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    val pill = RectF(2f, 2f, width - 2f, height - 2f)
    val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(217, 20, 20, 20) }
    canvas.drawRoundRect(pill, pill.height() / 2, pill.height() / 2, fill)
    val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      style = Paint.Style.STROKE
      strokeWidth = 3f
      color = Color.argb(230, 255, 255, 255)
    }
    canvas.drawRoundRect(pill, pill.height() / 2, pill.height() / 2, stroke)
    val metrics = paint.fontMetrics
    canvas.drawText(text, (width - textWidth) / 2, height / 2f - (metrics.ascent + metrics.descent) / 2, paint)
    return bitmap
  }

  /** A soft round shadow, black at 38% in the middle. */
  val shadow: Bitmap by lazy { radial(128, intArrayOf(Color.argb(97, 0, 0, 0), Color.argb(0, 0, 0, 0)), floatArrayOf(0f, 1f)) }

  /** A soft white puff that particle colours tint. */
  val particle: Bitmap by lazy {
    radial(64, intArrayOf(Color.WHITE, Color.argb(140, 255, 255, 255), Color.argb(0, 255, 255, 255)), floatArrayOf(0f, 0.45f, 1f))
  }

  private fun radial(size: Int, colors: IntArray, stops: FloatArray): Bitmap {
    val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      shader = RadialGradient(size / 2f, size / 2f, size / 2f, colors, stops, Shader.TileMode.CLAMP)
    }
    Canvas(bitmap).drawRect(0f, 0f, size.toFloat(), size.toFloat(), paint)
    return bitmap
  }

  private fun argb(c: FloatArray) =
    Color.argb((c[3] * 255).toInt(), (c[0] * 255).toInt(), (c[1] * 255).toInt(), (c[2] * 255).toInt())

  private fun luminance(c: FloatArray) = 0.2126f * c[0] + 0.7152f * c[1] + 0.0722f * c[2]
}
