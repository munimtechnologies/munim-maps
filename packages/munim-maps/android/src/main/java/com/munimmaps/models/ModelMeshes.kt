package com.munimmaps.models

import com.google.android.filament.Box
import com.google.android.filament.Engine
import com.google.android.filament.EntityManager
import com.google.android.filament.IndexBuffer
import com.google.android.filament.MaterialInstance
import com.google.android.filament.RenderableManager
import com.google.android.filament.Scene
import com.google.android.filament.SurfaceOrientation
import com.google.android.filament.VertexBuffer
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/**
 * Triangles built on the CPU: positions, normals (for lit materials),
 * vertex colours (linear, premultiplied by alpha) and texture coordinates.
 * The Android twin of the SceneKit geometry iOS builds in MapModelNodes.
 */
internal class MeshData {
  var positions = FloatArray(256)
  var normals = FloatArray(256)
  var colors = FloatArray(256)
  var uvs = FloatArray(128)
  var indices = IntArray(256)
  var vertexCount = 0
    private set
  var indexCount = 0
    private set

  fun clear() {
    vertexCount = 0
    indexCount = 0
  }

  fun vertex(
    x: Float, y: Float, z: Float,
    nx: Float = 0f, ny: Float = 1f, nz: Float = 0f,
    r: Float = 1f, g: Float = 1f, b: Float = 1f, a: Float = 1f,
    u: Float = 0f, v: Float = 0f,
  ): Int {
    val i = vertexCount
    if ((i + 1) * 4 > colors.size) grow()
    positions[i * 3] = x; positions[i * 3 + 1] = y; positions[i * 3 + 2] = z
    normals[i * 3] = nx; normals[i * 3 + 1] = ny; normals[i * 3 + 2] = nz
    colors[i * 4] = r; colors[i * 4 + 1] = g; colors[i * 4 + 2] = b; colors[i * 4 + 3] = a
    uvs[i * 2] = u; uvs[i * 2 + 1] = v
    vertexCount = i + 1
    return i
  }

  fun triangle(a: Int, b: Int, c: Int) {
    if (indexCount + 3 > indices.size) indices = indices.copyOf(indices.size * 2)
    indices[indexCount] = a; indices[indexCount + 1] = b; indices[indexCount + 2] = c
    indexCount += 3
  }

  fun quad(a: Int, b: Int, c: Int, d: Int) {
    triangle(a, b, c)
    triangle(a, c, d)
  }

  private fun grow() {
    positions = positions.copyOf(positions.size * 2)
    normals = normals.copyOf(normals.size * 2)
    colors = colors.copyOf(colors.size * 2)
    uvs = uvs.copyOf(uvs.size * 2)
  }

  /** Smallest and largest corner. */
  fun bounds(): Pair<FloatArray, FloatArray>? {
    if (vertexCount == 0) return null
    val lo = floatArrayOf(Float.MAX_VALUE, Float.MAX_VALUE, Float.MAX_VALUE)
    val hi = floatArrayOf(-Float.MAX_VALUE, -Float.MAX_VALUE, -Float.MAX_VALUE)
    for (i in 0 until vertexCount) for (k in 0..2) {
      lo[k] = min(lo[k], positions[i * 3 + k])
      hi[k] = max(hi[k], positions[i * 3 + k])
    }
    return lo to hi
  }

  /** Scales every vertex, fixing the normals (inverse transpose). */
  fun scale(sx: Float, sy: Float, sz: Float) {
    for (i in 0 until vertexCount) {
      positions[i * 3] *= sx; positions[i * 3 + 1] *= sy; positions[i * 3 + 2] *= sz
      val nx = normals[i * 3] / sx
      val ny = normals[i * 3 + 1] / sy
      val nz = normals[i * 3 + 2] / sz
      val l = sqrt(nx * nx + ny * ny + nz * nz).takeIf { it > 0 } ?: 1f
      normals[i * 3] = nx / l; normals[i * 3 + 1] = ny / l; normals[i * 3 + 2] = nz / l
    }
  }

  /** Moves the bounding box so its base is centred on the origin. */
  fun normalize() {
    val (lo, hi) = bounds() ?: return
    val cx = (lo[0] + hi[0]) / 2
    val cz = (lo[2] + hi[2]) / 2
    for (i in 0 until vertexCount) {
      positions[i * 3] -= cx; positions[i * 3 + 1] -= lo[1]; positions[i * 3 + 2] -= cz
    }
  }

  fun setColor(r: Float, g: Float, b: Float, a: Float) {
    for (i in 0 until vertexCount) {
      colors[i * 4] = r; colors[i * 4 + 1] = g; colors[i * 4 + 2] = b; colors[i * 4 + 3] = a
    }
  }
}

/**
 * One Filament renderable built from [MeshData], with the material it was
 * given (owned: destroyed with it unless [ownsMaterial] is false). [dynamic]
 * meshes can be refilled every frame ([update]).
 */
internal class MeshPart(
  private val engine: Engine,
  data: MeshData,
  val material: MaterialInstance,
  private val lit: Boolean = false,
  channel: Int = 2,
  priority: Int = 4,
  private val dynamic: Boolean = false,
  private val ownsMaterial: Boolean = true,
) {
  val entity: Int = EntityManager.get().create()
  private var vertexBuffer: VertexBuffer? = null
  private var indexBuffer: IndexBuffer? = null
  private var vertexCapacity = 0
  private var indexCapacity = 0
  /** Two CPU buffers in turn, so a frame never overwrites one still being uploaded. */
  private val staging = arrayOfNulls<ByteBuffer>(2)
  private val indexStaging = arrayOfNulls<ByteBuffer>(2)
  private var flip = 0
  var inScene = false
    private set
  private var destroyed = false

  private val stride get() = if (lit) 52 else 36

  init {
    allocate(max(4, data.vertexCount), max(3, data.indexCount))
    RenderableManager.Builder(1)
      .geometry(0, RenderableManager.PrimitiveType.TRIANGLES, vertexBuffer!!, indexBuffer!!, 0, 3)
      .material(0, material)
      .boundingBox(Box(0f, 0f, 0f, 1e7f, 1e7f, 1e7f))
      .culling(false)
      .castShadows(false)
      .receiveShadows(false)
      .channel(channel)
      .priority(priority)
      .build(engine, entity)
    update(data)
  }

  private fun allocate(vertices: Int, indices: Int) {
    vertexBuffer?.let { engine.destroyVertexBuffer(it) }
    indexBuffer?.let { engine.destroyIndexBuffer(it) }
    vertexCapacity = vertices
    indexCapacity = indices
    val builder = VertexBuffer.Builder()
      .bufferCount(1)
      .vertexCount(vertices)
      .attribute(VertexBuffer.VertexAttribute.POSITION, 0, VertexBuffer.AttributeType.FLOAT3, 0, stride)
      .attribute(VertexBuffer.VertexAttribute.COLOR, 0, VertexBuffer.AttributeType.FLOAT4, 12, stride)
      .attribute(VertexBuffer.VertexAttribute.UV0, 0, VertexBuffer.AttributeType.FLOAT2, 28, stride)
      .attribute(VertexBuffer.VertexAttribute.UV1, 0, VertexBuffer.AttributeType.FLOAT2, 28, stride)
    if (lit) builder.attribute(VertexBuffer.VertexAttribute.TANGENTS, 0, VertexBuffer.AttributeType.FLOAT4, 36, stride)
    vertexBuffer = builder.build(engine)
    indexBuffer = IndexBuffer.Builder()
      .indexCount(indices)
      .bufferType(IndexBuffer.Builder.IndexType.UINT)
      .build(engine)
    staging.fill(null)
    indexStaging.fill(null)
  }

  /** Replaces the triangles (dynamic meshes may grow). */
  fun update(source: MeshData) {
    if (destroyed) return
    // Nothing to draw: one degenerate triangle, which draws no pixels.
    val data = if (source.vertexCount == 0 || source.indexCount == 0) EMPTY else source
    val vertices = data.vertexCount
    val indices = data.indexCount
    val rm = engine.renderableManager
    val instance = rm.getInstance(entity)
    if (vertices > vertexCapacity || indices > indexCapacity) {
      val grow = if (dynamic) 2 else 1
      allocate(max(vertices * grow, 4), max(indices * grow, 3))
    }
    flip = 1 - flip
    val vbytes = vertices * stride
    var vb = staging[flip]
    if (vb == null || vb.capacity() < vbytes) {
      vb = ByteBuffer.allocateDirect(vertexCapacity * stride).order(ByteOrder.nativeOrder())
      staging[flip] = vb
    }
    vb!!.clear()
    val tangents = if (lit) tangentFrames(data) else null
    for (i in 0 until vertices) {
      vb.putFloat(data.positions[i * 3]).putFloat(data.positions[i * 3 + 1]).putFloat(data.positions[i * 3 + 2])
      vb.putFloat(data.colors[i * 4]).putFloat(data.colors[i * 4 + 1]).putFloat(data.colors[i * 4 + 2]).putFloat(data.colors[i * 4 + 3])
      vb.putFloat(data.uvs[i * 2]).putFloat(data.uvs[i * 2 + 1])
      if (tangents != null) {
        vb.putFloat(tangents[i * 4]).putFloat(tangents[i * 4 + 1]).putFloat(tangents[i * 4 + 2]).putFloat(tangents[i * 4 + 3])
      }
    }
    vb.flip()
    vertexBuffer!!.setBufferAt(engine, 0, vb, 0, vbytes)

    var ib = indexStaging[flip]
    if (ib == null || ib.capacity() < indices * 4) {
      ib = ByteBuffer.allocateDirect(indexCapacity * 4).order(ByteOrder.nativeOrder())
      indexStaging[flip] = ib
    }
    ib!!.clear()
    for (i in 0 until indices) ib.putInt(data.indices[i])
    ib.flip()
    indexBuffer!!.setBuffer(engine, ib, 0, indices * 4)
    rm.setGeometryAt(instance, 0, RenderableManager.PrimitiveType.TRIANGLES, vertexBuffer!!, indexBuffer!!, 0, indices)
  }

  private fun tangentFrames(data: MeshData): FloatArray {
    val n = data.vertexCount
    val normals = ByteBuffer.allocateDirect(n * 12).order(ByteOrder.nativeOrder())
    for (i in 0 until n * 3) normals.putFloat(data.normals[i])
    normals.flip()
    val orientation = SurfaceOrientation.Builder().vertexCount(n).normals(normals).build()
    val quats = ByteBuffer.allocateDirect(n * 16).order(ByteOrder.nativeOrder())
    orientation.getQuatsAsFloat(quats)
    orientation.destroy()
    val result = FloatArray(n * 4)
    quats.rewind()
    quats.asFloatBuffer().get(result)
    return result
  }

  fun show(scene: Scene, visible: Boolean) {
    if (destroyed || visible == inScene) return
    if (visible) scene.addEntity(entity) else scene.removeEntity(entity)
    inScene = visible
  }

  /** Column-major 4x4. */
  fun setTransform(matrix: FloatArray) {
    if (destroyed) return
    val tm = engine.transformManager
    if (!tm.hasComponent(entity)) tm.create(entity)
    tm.setTransform(tm.getInstance(entity), matrix)
  }

  fun destroy(scene: Scene) {
    if (destroyed) return
    show(scene, false)
    destroyed = true
    engine.destroyEntity(entity)
    EntityManager.get().destroy(entity)
    vertexBuffer?.let { engine.destroyVertexBuffer(it) }
    indexBuffer?.let { engine.destroyIndexBuffer(it) }
    if (ownsMaterial) engine.destroyMaterialInstance(material)
  }

  private companion object {
    val EMPTY = MeshData().apply {
      vertex(0f, 0f, 0f, a = 0f)
      triangle(0, 0, 0)
    }
  }
}

/** Built-in shapes and helper meshes, base centred on the origin unless noted. */
internal object Shapes {
  private const val SEGMENTS = 32

  /** A `w` x `h` x `l` shape, lit, in one colour (premultiplied linear). */
  fun shape(kind: String, w: Float, h: Float, l: Float): MeshData? {
    val mesh = MeshData()
    when (kind) {
      "box" -> box(mesh)
      "sphere", "capsule" -> sphere(mesh, 0.5f, 0.5f)
      "cylinder" -> cylinder(mesh, 0.5f, 0.5f, SEGMENTS, caps = true)
      "cone" -> cylinder(mesh, 0.5f, 0f, SEGMENTS, caps = true)
      "pyramid" -> pyramid(mesh)
      "gem" -> gem(mesh)
      else -> return null
    }
    mesh.scale(max(0.01f, w), max(0.01f, h), max(0.01f, l))
    mesh.normalize()
    return mesh
  }

  /** Unit cube, y 0…1. */
  private fun box(m: MeshData) {
    val faces = arrayOf(
      floatArrayOf(0f, 0f, 1f), floatArrayOf(0f, 0f, -1f), floatArrayOf(1f, 0f, 0f),
      floatArrayOf(-1f, 0f, 0f), floatArrayOf(0f, 1f, 0f), floatArrayOf(0f, -1f, 0f),
    )
    for (n in faces) {
      // Two axes across the face.
      val u = if (n[1] != 0f) floatArrayOf(1f, 0f, 0f) else floatArrayOf(-n[2], 0f, n[0])
      val v = cross(n, u)
      val base = m.vertexCount
      for ((su, sv) in listOf(-1f to -1f, 1f to -1f, 1f to 1f, -1f to 1f)) {
        m.vertex(
          n[0] * 0.5f + u[0] * 0.5f * su + v[0] * 0.5f * sv,
          0.5f + n[1] * 0.5f + u[1] * 0.5f * su + v[1] * 0.5f * sv,
          n[2] * 0.5f + u[2] * 0.5f * su + v[2] * 0.5f * sv,
          n[0], n[1], n[2],
        )
      }
      m.quad(base, base + 1, base + 2, base + 3)
    }
  }

  /** Radius `r`, centred at height `cy`. */
  fun sphere(m: MeshData, r: Float, cy: Float, rings: Int = 16, segments: Int = SEGMENTS) {
    val base = m.vertexCount
    for (i in 0..rings) {
      val phi = PI * i / rings
      for (j in 0..segments) {
        val theta = 2 * PI * j / segments
        val nx = (sin(phi) * cos(theta)).toFloat()
        val ny = cos(phi).toFloat()
        val nz = (sin(phi) * sin(theta)).toFloat()
        m.vertex(nx * r, cy + ny * r, nz * r, nx, ny, nz, u = j.toFloat() / segments, v = i.toFloat() / rings)
      }
    }
    for (i in 0 until rings) for (j in 0 until segments) {
      val a = base + i * (segments + 1) + j
      val b = a + segments + 1
      m.triangle(a, a + 1, b)
      m.triangle(a + 1, b + 1, b)
    }
  }

  /** Bottom radius `r0`, top radius `r1`, y 0…1. */
  fun cylinder(m: MeshData, r0: Float, r1: Float, segments: Int, caps: Boolean, y0: Float = 0f, y1: Float = 1f) {
    val slope = (r0 - r1) / (y1 - y0)
    val base = m.vertexCount
    for (j in 0..segments) {
      val theta = 2 * PI * j / segments
      val c = cos(theta).toFloat()
      val s = sin(theta).toFloat()
      val len = sqrt(1 + slope * slope)
      m.vertex(c * r0, y0, s * r0, c / len, slope / len, s / len)
      m.vertex(c * r1, y1, s * r1, c / len, slope / len, s / len)
    }
    for (j in 0 until segments) {
      val a = base + j * 2
      m.triangle(a, a + 1, a + 2)
      m.triangle(a + 1, a + 3, a + 2)
    }
    if (!caps) return
    for ((y, r, up) in listOf(Triple(y0, r0, -1f), Triple(y1, r1, 1f))) {
      if (r <= 0f) continue
      val center = m.vertex(0f, y, 0f, 0f, up, 0f)
      val ring = m.vertexCount
      for (j in 0..segments) {
        val theta = 2 * PI * j / segments
        m.vertex(cos(theta).toFloat() * r, y, sin(theta).toFloat() * r, 0f, up, 0f)
      }
      for (j in 0 until segments) {
        if (up > 0) m.triangle(center, ring + j + 1, ring + j) else m.triangle(center, ring + j, ring + j + 1)
      }
    }
  }

  private fun pyramid(m: MeshData) {
    val apex = floatArrayOf(0f, 1f, 0f)
    val corners = arrayOf(
      floatArrayOf(-0.5f, 0f, 0.5f), floatArrayOf(0.5f, 0f, 0.5f),
      floatArrayOf(0.5f, 0f, -0.5f), floatArrayOf(-0.5f, 0f, -0.5f),
    )
    for (i in 0..3) flatTriangle(m, corners[i], corners[(i + 1) % 4], apex)
    flatTriangle(m, corners[0], corners[3], corners[2])
    flatTriangle(m, corners[0], corners[2], corners[1])
  }

  /** A six-sided double pyramid, taller above the girdle (as iOS). */
  private fun gem(m: MeshData) {
    val sides = 6
    val girdle = 0.35f
    val ring = Array(sides) { i ->
      val angle = i.toFloat() / sides * 2 * PI.toFloat()
      floatArrayOf(cos(angle) * 0.5f, girdle, sin(angle) * 0.5f)
    }
    val top = floatArrayOf(0f, 1f, 0f)
    val bottom = floatArrayOf(0f, 0f, 0f)
    for (i in 0 until sides) {
      val a = ring[i]
      val b = ring[(i + 1) % sides]
      flatTriangle(m, top, b, a)
      flatTriangle(m, bottom, a, b)
    }
  }

  private fun flatTriangle(m: MeshData, a: FloatArray, b: FloatArray, c: FloatArray) {
    val n = normalize(cross(sub(b, a), sub(c, a)))
    val i = m.vertex(a[0], a[1], a[2], n[0], n[1], n[2])
    m.vertex(b[0], b[1], b[2], n[0], n[1], n[2])
    m.vertex(c[0], c[1], c[2], n[0], n[1], n[2])
    m.triangle(i, i + 1, i + 2)
  }

  /** A `width` x 1 rectangle facing +z, centred on the origin, v = 0 at the top. */
  fun quad(width: Float, height: Float = 1f): MeshData {
    val m = MeshData()
    val w = width / 2
    val h = height / 2
    m.vertex(-w, -h, 0f, 0f, 0f, 1f, u = 0f, v = 1f)
    m.vertex(w, -h, 0f, 0f, 0f, 1f, u = 1f, v = 1f)
    m.vertex(w, h, 0f, 0f, 0f, 1f, u = 1f, v = 0f)
    m.vertex(-w, h, 0f, 0f, 0f, 1f, u = 0f, v = 0f)
    m.quad(0, 1, 2, 3)
    return m
  }

  /** A 1 x 1 square lying flat (facing up), centred on the origin. */
  fun groundQuad(): MeshData {
    val m = MeshData()
    m.vertex(-0.5f, 0f, 0.5f, u = 0f, v = 1f)
    m.vertex(0.5f, 0f, 0.5f, u = 1f, v = 1f)
    m.vertex(0.5f, 0f, -0.5f, u = 1f, v = 0f)
    m.vertex(-0.5f, 0f, -0.5f, u = 0f, v = 0f)
    m.quad(0, 1, 2, 3)
    return m
  }

  /** Radius 0.5, height 1, centred on the origin (stems and their dots). */
  fun stem(segments: Int = 8): MeshData {
    val m = MeshData()
    cylinder(m, 0.5f, 0.5f, segments, caps = true, y0 = -0.5f, y1 = 0.5f)
    return m
  }

  fun cross(a: FloatArray, b: FloatArray) = floatArrayOf(
    a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])

  private fun sub(a: FloatArray, b: FloatArray) = floatArrayOf(a[0] - b[0], a[1] - b[1], a[2] - b[2])

  private fun normalize(v: FloatArray): FloatArray {
    val l = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).takeIf { it > 0 } ?: 1f
    return floatArrayOf(v[0] / l, v[1] / l, v[2] / l)
  }
}
