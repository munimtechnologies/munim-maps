package com.munimmaps.engine

import kotlin.math.PI
import kotlin.math.atan
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.ln
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.tan

/**
 * The camera of a map engine, as munim-maps' 3D layer draws with it: the
 * Android twin of iOS's `MapCameraState` (ios/Core/MapCameraState.swift),
 * with the same scene layout and maths.
 *
 * Every engine (Google Maps, Mapbox, MapLibre, Cesium) describes its camera
 * with this, once a frame ([MapCameraSource.cameraState]), and the Filament
 * renderer ([com.munimmaps.models.ModelRenderer]) only ever reads this.
 *
 * The scene is laid out in metres around the centre coordinate: x east, y up,
 * z south (so -z is north). Positions come from Web Mercator. The camera is a
 * pinhole centred on the view, with [focalLength] in pixels, turned to
 * [heading] and [pitch], [altitude] metres above the ground; the ray through
 * [centerX], [centerY] (where the engine draws the centre coordinate, in
 * pixels) meets the ground at the origin. On a [globe], positions are on a
 * sphere and the camera sits [distance] metres back along that ray.
 */
data class MapCameraState(
  val latitude: Double,
  val longitude: Double,
  /** Metres from the camera to the centre coordinate. */
  val distance: Double,
  /** Height of the camera above the ground, in metres. */
  val altitude: Double,
  /** Degrees from straight down. */
  val pitch: Double,
  /** Degrees clockwise from north. */
  val heading: Double,
  /** The map's size in pixels: the viewport. */
  val width: Double,
  val height: Double,
  /** Focal length in pixels: half the height over tan(half the vertical field of view). */
  val focalLength: Double,
  /** Where the centre coordinate is drawn, in pixels. */
  val centerX: Double,
  val centerY: Double,
  val globe: Boolean = false,
  /** The engine raises the ground to real terrain heights. */
  val drawsTerrain: Boolean = false,
  /** The map is drawn dark, for `lighting = auto`. */
  val darkAppearance: Boolean = false,
  /** Pixels per point (density), to size things given in points. */
  val pixelRatio: Double = 1.0,
) {
  /** Vertical field of view in radians. */
  val fieldOfView: Double
    get() = if (focalLength > 0 && height > 0) 2 * atan(height / 2 / focalLength) else PI / 6

  val nearPlane: Double get() = maxOf(0.5, distance * 0.01)
  val farPlane: Double get() = if (globe) distance + 2 * EARTH_RADIUS else maxOf(10_000.0, distance * 60)

  /** Camera rotation as a 3x3 matrix (columns: right, up, back), row-major in a DoubleArray(9). */
  val rotation: DoubleArray get() = rotation(heading, pitch)

  /** World direction of the ray through a pixel (not normalised). */
  fun ray(x: Double, y: Double): DoubleArray {
    val local = doubleArrayOf((x - width / 2) / focalLength, -(y - height / 2) / focalLength, -1.0)
    return mul(rotation, local)
  }

  /** Camera position in the scene. */
  val position: DoubleArray
    get() {
      val d = ray(centerX, centerY)
      if (globe) {
        val n = norm(d)
        return doubleArrayOf(-d[0] / n * distance, -d[1] / n * distance, -d[2] / n * distance)
      }
      if (d[1] >= -1e-5) {
        val f = mul(rotation, doubleArrayOf(0.0, 0.0, -1.0))
        return doubleArrayOf(-f[0] * distance, -f[1] * distance, -f[2] * distance)
      }
      val k = altitude / -d[1]
      return doubleArrayOf(-d[0] * k, -d[1] * k, -d[2] * k)
    }

  /** Camera to scene, column-major 4x4 (Filament's `setModelMatrix`). */
  val cameraTransform: DoubleArray
    get() {
      val r = rotation
      val p = position
      return doubleArrayOf(
        r[0], r[3], r[6], 0.0,
        r[1], r[4], r[7], 0.0,
        r[2], r[5], r[8], 0.0,
        p[0], p[1], p[2], 1.0,
      )
    }

  /** Scene position of a coordinate, `altitude` metres above the ground. */
  fun scenePosition(latitude: Double, longitude: Double, altitude: Double): DoubleArray {
    if (globe) return globePosition(latitude, longitude, altitude)
    val scale = metersPerMapPoint(this.latitude)
    val (cx, cy) = mapPoint(this.latitude, this.longitude)
    val (x, y) = mapPoint(latitude, longitude)
    return doubleArrayOf((x - cx) * scale, altitude, (y - cy) * scale)
  }

  /** Unit vector pointing up at a coordinate (y on the flat map). */
  fun localUp(latitude: Double, longitude: Double): DoubleArray {
    if (!globe) return doubleArrayOf(0.0, 1.0, 0.0)
    val center = enu(this.latitude, this.longitude)
    val up = enu(latitude, longitude)[2]
    return toScene(up, center)
  }

  /** Pixel position and depth of a scene position; null when behind the camera. */
  fun project(p: DoubleArray): DoubleArray? {
    val r = rotation
    val c = position
    val v = doubleArrayOf(p[0] - c[0], p[1] - c[1], p[2] - c[2])
    // Camera space: rotation transposed.
    val ex = r[0] * v[0] + r[3] * v[1] + r[6] * v[2]
    val ey = r[1] * v[0] + r[4] * v[1] + r[7] * v[2]
    val ez = r[2] * v[0] + r[5] * v[1] + r[8] * v[2]
    if (-ez < 1e-4) return null
    val x = width / 2 + ex / -ez * focalLength
    val y = height / 2 - ey / -ez * focalLength
    return doubleArrayOf(x, y, -ez)
  }

  private fun globePosition(latitude: Double, longitude: Double, altitude: Double): DoubleArray {
    val r = EARTH_RADIUS
    val center = enu(this.latitude, this.longitude)
    val up = enu(latitude, longitude)[2]
    val d = DoubleArray(3) { up[it] * (r + altitude) - center[2][it] * r }
    return toScene(d, center)
  }

  companion object {
    const val EARTH_RADIUS = 6_371_008.8
    /** Web Mercator's sphere (EPSG:3857), as every tile engine uses. */
    const val MERCATOR_RADIUS = 6_378_137.0
    /** MapKit's world size in map points, kept so maths match iOS. */
    const val WORLD_SIZE = 268_435_456.0

    /** Focal length in pixels for a vertical field of view in radians. */
    fun focalLength(height: Double, verticalFieldOfView: Double): Double = height / 2 / tan(verticalFieldOfView / 2)

    fun mapPoint(latitude: Double, longitude: Double): Pair<Double, Double> {
      val x = (longitude + 180) / 360 * WORLD_SIZE
      val phi = latitude.coerceIn(-85.05112878, 85.05112878) * PI / 180
      val y = (1 - ln(tan(phi) + 1 / cos(phi)) / PI) / 2 * WORLD_SIZE
      return x to y
    }

    fun coordinate(x: Double, y: Double): Pair<Double, Double> {
      val longitude = x / WORLD_SIZE * 360 - 180
      val n = PI - 2 * PI * y / WORLD_SIZE
      val latitude = 180 / PI * atan(0.5 * (exp(n) - exp(-n)))
      return latitude to longitude
    }

    fun metersPerMapPoint(latitude: Double): Double =
      cos(latitude * PI / 180) * 2 * PI * MERCATOR_RADIUS / WORLD_SIZE

    /** Row-major 3x3: yaw by -heading about y, then tilt from looking straight down. */
    fun rotation(heading: Double, pitch: Double): DoubleArray {
      val h = -heading * PI / 180
      val t = -(PI / 2 - pitch * PI / 180)
      val yaw = doubleArrayOf(cos(h), 0.0, sin(h), 0.0, 1.0, 0.0, -sin(h), 0.0, cos(h))
      val tilt = doubleArrayOf(1.0, 0.0, 0.0, 0.0, cos(t), -sin(t), 0.0, sin(t), cos(t))
      return mul3(yaw, tilt)
    }

    private fun mul3(a: DoubleArray, b: DoubleArray): DoubleArray = DoubleArray(9) { i ->
      val row = i / 3
      val col = i % 3
      a[row * 3] * b[col] + a[row * 3 + 1] * b[3 + col] + a[row * 3 + 2] * b[6 + col]
    }

    fun mul(m: DoubleArray, v: DoubleArray): DoubleArray = doubleArrayOf(
      m[0] * v[0] + m[1] * v[1] + m[2] * v[2],
      m[3] * v[0] + m[4] * v[1] + m[5] * v[2],
      m[6] * v[0] + m[7] * v[1] + m[8] * v[2],
    )

    fun norm(v: DoubleArray): Double = sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])

    /** East, north, up unit vectors at a coordinate, in Earth-centred axes. */
    private fun enu(latitude: Double, longitude: Double): Array<DoubleArray> {
      val phi = latitude * PI / 180
      val lambda = longitude * PI / 180
      return arrayOf(
        doubleArrayOf(-sin(lambda), cos(lambda), 0.0),
        doubleArrayOf(-sin(phi) * cos(lambda), -sin(phi) * sin(lambda), cos(phi)),
        doubleArrayOf(cos(phi) * cos(lambda), cos(phi) * sin(lambda), sin(phi)),
      )
    }

    private fun dot(a: DoubleArray, b: DoubleArray) = a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

    private fun toScene(v: DoubleArray, center: Array<DoubleArray>) =
      doubleArrayOf(dot(v, center[0]), dot(v, center[2]), -dot(v, center[1]))
  }
}
