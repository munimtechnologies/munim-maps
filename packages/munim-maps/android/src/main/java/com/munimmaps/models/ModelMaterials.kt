package com.munimmaps.models

import android.graphics.Bitmap
import com.google.android.filament.Colors
import com.google.android.filament.Engine
import com.google.android.filament.Material
import com.google.android.filament.MaterialInstance
import com.google.android.filament.Texture
import com.google.android.filament.TextureSampler
import com.google.android.filament.gltfio.MaterialProvider
import com.google.android.filament.gltfio.UbershaderProvider
import java.nio.ByteBuffer
import kotlin.math.pow

/**
 * Materials for what munim-maps builds itself (shapes, pictures, labels,
 * stems, zones, paths, effects, occluders), taken from gltfio's ubershader
 * so no extra compiled Filament materials ship with the library.
 *
 * Unlit materials multiply a texture (white when none) by the vertex
 * colour. Blended ones expect premultiplied colours: vertex colours from
 * [linear] with `premultiplied = true`, and Android bitmaps, which are
 * premultiplied already.
 */
internal class ModelMaterials(private val engine: Engine, private val provider: UbershaderProvider) {
  private val uvmap = IntArray(8).also { it[0] = 1 } // glTF texcoord 0 → UV0
  val sampler = TextureSampler(
    TextureSampler.MinFilter.LINEAR_MIPMAP_LINEAR, TextureSampler.MagFilter.LINEAR, TextureSampler.WrapMode.CLAMP_TO_EDGE)
  val white: Texture = Texture.Builder()
    .width(1).height(1).levels(1)
    .format(Texture.InternalFormat.SRGB8_A8)
    .sampler(Texture.Sampler.SAMPLER_2D)
    .build(engine)
    .also {
      val pixel = ByteBuffer.allocateDirect(4).put(byteArrayOf(-1, -1, -1, -1))
      pixel.flip()
      it.setImage(engine, 0, Texture.PixelBufferDescriptor(pixel, Texture.Format.RGBA, Texture.Type.UBYTE))
    }

  /**
   * An unlit material. [blend] draws see-through (premultiplied colours);
   * [onTop] ignores the depth buffer, for markers that stay in front of
   * buildings; [occluder] only writes depth.
   */
  fun unlit(
    texture: Texture? = null,
    blend: Boolean = true,
    depthWrite: Boolean = !blend,
    onTop: Boolean = false,
    occluder: Boolean = false,
    doubleSided: Boolean = true,
    label: String = "munim",
  ): MaterialInstance {
    val key = MaterialProvider.MaterialKey().apply {
      this.unlit = true
      this.doubleSided = doubleSided
      hasVertexColors = true
      hasBaseColorTexture = true
      baseColorUV = 0
      alphaMode = if (blend) ALPHA_BLEND else ALPHA_OPAQUE
    }
    val mi = provider.createMaterialInstance(key, uvmap.copyOf(), label, null)
      ?: error("gltfio has no unlit material")
    mi.setParameter("baseColorFactor", 1f, 1f, 1f, 1f)
    mi.setParameter("baseColorMap", texture ?: white, sampler)
    mi.setDoubleSided(doubleSided)
    mi.setCullingMode(if (doubleSided) Material.CullingMode.NONE else Material.CullingMode.BACK)
    if (blend) mi.setTransparencyMode(Material.TransparencyMode.DEFAULT)
    mi.setDepthWrite(depthWrite || occluder)
    if (onTop) mi.setDepthCulling(false)
    if (occluder) mi.setColorWrite(false)
    return mi
  }

  /** A physically based material in one colour (`#RRGGBB[AA]`), for built-in shapes. */
  fun lit(color: FloatArray, metallic: Float, roughness: Float, emissive: Boolean): MaterialInstance {
    val blend = color[3] < 1f
    val key = MaterialProvider.MaterialKey().apply {
      unlit = false
      doubleSided = false
      hasVertexColors = true
      alphaMode = if (blend) ALPHA_BLEND else ALPHA_OPAQUE
    }
    val mi = provider.createMaterialInstance(key, uvmap.copyOf(), "munim-shape", null)
      ?: error("gltfio has no lit material")
    mi.setParameter("baseColorFactor", Colors.RgbaType.SRGB, color[0], color[1], color[2], color[3])
    mi.setParameter("metallicFactor", metallic)
    mi.setParameter("roughnessFactor", roughness)
    mi.setParameter("normalScale", 1f)
    mi.setParameter("aoStrength", 1f)
    mi.setParameter("emissiveStrength", 1f)
    if (emissive) {
      val linear = Colors.toLinear(Colors.RgbType.SRGB, color[0], color[1], color[2])
      mi.setParameter("emissiveFactor", linear[0], linear[1], linear[2])
    } else {
      mi.setParameter("emissiveFactor", 0f, 0f, 0f)
    }
    if (mi.material.hasParameter("clearCoatFactor")) mi.setParameter("clearCoatFactor", 0f)
    return mi
  }

  /**
   * A texture with mipmaps from a bitmap, in linear colour premultiplied by
   * alpha (half floats). Unlit blended materials output their colour as is,
   * so it must be premultiplied after linearising: an sRGB texture of
   * Android's premultiplied pixels would decode `rgb * a` as `(rgb * a)^2.2`
   * and turn soft edges and puffs grey.
   */
  fun texture(bitmap: Bitmap): Texture {
    val width = bitmap.width
    val height = bitmap.height
    val levels = 1 + (31 - Integer.numberOfLeadingZeros(maxOf(width, height)))
    val texture = Texture.Builder()
      .width(width).height(height).levels(levels)
      .format(Texture.InternalFormat.RGBA16F)
      .sampler(Texture.Sampler.SAMPLER_2D)
      .usage(Texture.Usage.DEFAULT or Texture.Usage.GEN_MIPMAPPABLE)
      .build(engine)
    val pixels = IntArray(width * height)
    bitmap.getPixels(pixels, 0, width, 0, 0, width, height) // unpremultiplied ARGB
    val buffer = ByteBuffer.allocateDirect(width * height * 8).order(java.nio.ByteOrder.nativeOrder())
    val lut = SRGB_TO_LINEAR
    for (p in pixels) {
      val a = ((p ushr 24) and 0xff) / 255f
      buffer.putShort(android.util.Half.toHalf(lut[(p shr 16) and 0xff] * a))
      buffer.putShort(android.util.Half.toHalf(lut[(p shr 8) and 0xff] * a))
      buffer.putShort(android.util.Half.toHalf(lut[p and 0xff] * a))
      buffer.putShort(android.util.Half.toHalf(a))
    }
    buffer.flip()
    texture.setImage(engine, 0, Texture.PixelBufferDescriptor(buffer, Texture.Format.RGBA, Texture.Type.HALF))
    texture.generateMipmaps(engine)
    return texture
  }

  fun destroy() {
    engine.destroyTexture(white)
  }

  companion object {
    private const val ALPHA_OPAQUE = 0
    private const val ALPHA_BLEND = 2

    private val SRGB_TO_LINEAR = FloatArray(256) { i ->
      val c = i / 255f
      if (c <= 0.04045f) c / 12.92f else ((c + 0.055f) / 1.055f).pow(2.4f)
    }

    /** sRGB `#RRGGBB[AA]` (already parsed) to linear, optionally premultiplied. */
    fun linear(color: FloatArray, premultiplied: Boolean = true, alpha: Float = color[3]): FloatArray {
      fun channel(c: Float) = if (c <= 0.04045f) c / 12.92f else ((c + 0.055f) / 1.055f).pow(2.4f)
      val a = if (premultiplied) alpha else 1f
      return floatArrayOf(channel(color[0]) * a, channel(color[1]) * a, channel(color[2]) * a, alpha)
    }
  }
}
