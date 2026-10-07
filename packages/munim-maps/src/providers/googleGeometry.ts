/**
 * Google's geometry utilities (`GMSGeometryUtils` on iOS, `SphericalUtil` /
 * `PolyUtil` in android-maps-utils) in JavaScript, with Google's formulas
 * and Earth radius, so results match the SDKs on both platforms without a
 * native call. Distances are metres, headings degrees clockwise from north.
 */
import type { MapCoordinate } from '../specs/MapModelLayer.nitro'
import { decodePolyline, encodePolyline } from './googleServices'

/** The Earth radius Google's utilities use. */
const R = 6_371_009
const rad = (d: number) => (d * Math.PI) / 180
const deg = (r: number) => (r * 180) / Math.PI

function hav(x: number) {
  const s = Math.sin(x / 2)
  return s * s
}

function arcHav(x: number) {
  return 2 * Math.asin(Math.sqrt(x))
}

function havDistance(lat1: number, lat2: number, dLng: number) {
  return hav(lat1 - lat2) + hav(dLng) * Math.cos(lat1) * Math.cos(lat2)
}

function angleBetween(a: MapCoordinate, b: MapCoordinate) {
  return arcHav(
    havDistance(
      rad(a.latitude),
      rad(b.latitude),
      rad(a.longitude - b.longitude)
    )
  )
}

function wrap(n: number, min: number, max: number) {
  return n >= min && n < max
    ? n
    : ((((n - min) % (max - min)) + (max - min)) % (max - min)) + min
}

export const googleGeometry = {
  /** Great-circle distance between two points. */
  computeDistanceBetween(a: MapCoordinate, b: MapCoordinate): number {
    return angleBetween(a, b) * R
  },

  /** Initial heading from `from` to `to`, -180…180. */
  computeHeading(from: MapCoordinate, to: MapCoordinate): number {
    const lat1 = rad(from.latitude)
    const lat2 = rad(to.latitude)
    const dLng = rad(to.longitude - from.longitude)
    const h = Math.atan2(
      Math.sin(dLng) * Math.cos(lat2),
      Math.cos(lat1) * Math.sin(lat2) -
        Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLng)
    )
    return wrap(deg(h), -180, 180)
  },

  /** The point `distance` metres from `from` on `heading`. */
  computeOffset(
    from: MapCoordinate,
    distance: number,
    heading: number
  ): MapCoordinate {
    const d = distance / R
    const h = rad(heading)
    const lat = rad(from.latitude)
    const lng = rad(from.longitude)
    const cosD = Math.cos(d)
    const sinD = Math.sin(d)
    const sinLat = Math.sin(lat)
    const cosLat = Math.cos(lat)
    const sinLat2 = cosD * sinLat + sinD * cosLat * Math.cos(h)
    const dLng = Math.atan2(
      sinD * cosLat * Math.sin(h),
      cosD - sinLat * sinLat2
    )
    return {
      latitude: deg(Math.asin(sinLat2)),
      longitude: wrap(deg(lng + dLng), -180, 180),
    }
  },

  /** The point `fraction` of the way from `from` to `to` on the great circle. */
  interpolate(
    from: MapCoordinate,
    to: MapCoordinate,
    fraction: number
  ): MapCoordinate {
    const lat1 = rad(from.latitude)
    const lng1 = rad(from.longitude)
    const lat2 = rad(to.latitude)
    const lng2 = rad(to.longitude)
    const angle = angleBetween(from, to)
    const sinAngle = Math.sin(angle)
    if (sinAngle < 1e-6) {
      return {
        latitude: from.latitude + fraction * (to.latitude - from.latitude),
        longitude: from.longitude + fraction * (to.longitude - from.longitude),
      }
    }
    const a = Math.sin((1 - fraction) * angle) / sinAngle
    const b = Math.sin(fraction * angle) / sinAngle
    const x =
      a * Math.cos(lat1) * Math.cos(lng1) + b * Math.cos(lat2) * Math.cos(lng2)
    const y =
      a * Math.cos(lat1) * Math.sin(lng1) + b * Math.cos(lat2) * Math.sin(lng2)
    const z = a * Math.sin(lat1) + b * Math.sin(lat2)
    return {
      latitude: deg(Math.atan2(z, Math.sqrt(x * x + y * y))),
      longitude: deg(Math.atan2(y, x)),
    }
  },

  /** Length of a path. */
  computeLength(path: MapCoordinate[]): number {
    let total = 0
    for (let i = 1; i < path.length; i++)
      total += angleBetween(path[i - 1]!, path[i]!)
    return total * R
  },

  /** Signed area of a closed path in square metres (counter-clockwise positive). */
  computeSignedArea(path: MapCoordinate[]): number {
    if (path.length < 3) return 0
    let total = 0
    const prev = path[path.length - 1]!
    let prevTanLat = Math.tan((Math.PI / 2 - rad(prev.latitude)) / 2)
    let prevLng = rad(prev.longitude)
    for (const point of path) {
      const tanLat = Math.tan((Math.PI / 2 - rad(point.latitude)) / 2)
      const lng = rad(point.longitude)
      const dLng = lng - prevLng
      const t = tanLat * prevTanLat
      total += 2 * Math.atan2(t * Math.sin(dLng), 1 + t * Math.cos(dLng))
      prevTanLat = tanLat
      prevLng = lng
    }
    return total * R * R
  },

  /** Area of a closed path in square metres. */
  computeArea(path: MapCoordinate[]): number {
    return Math.abs(googleGeometry.computeSignedArea(path))
  },

  /** Whether a point is inside a polygon (rhumb edges; geodesic edges differ only when very long). */
  containsLocation(point: MapCoordinate, polygon: MapCoordinate[]): boolean {
    // Ray casting on the Mercator plane.
    const y = Math.log(Math.tan(Math.PI / 4 + rad(point.latitude) / 2))
    const x = rad(point.longitude)
    let inside = false
    for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      const a = polygon[i]!
      const b = polygon[j]!
      const ay = Math.log(Math.tan(Math.PI / 4 + rad(a.latitude) / 2))
      const by = Math.log(Math.tan(Math.PI / 4 + rad(b.latitude) / 2))
      let ax = rad(a.longitude)
      let bx = rad(b.longitude)
      if (Math.abs(ax - x) > Math.PI) ax += ax < x ? 2 * Math.PI : -2 * Math.PI
      if (Math.abs(bx - x) > Math.PI) bx += bx < x ? 2 * Math.PI : -2 * Math.PI
      if (ay > y !== by > y && x < ((bx - ax) * (y - ay)) / (by - ay) + ax)
        inside = !inside
    }
    return inside
  },

  /** Whether a point is within `tolerance` metres of a path. */
  isLocationOnPath(
    point: MapCoordinate,
    path: MapCoordinate[],
    tolerance = 0.1
  ): boolean {
    for (let i = 1; i < path.length; i++) {
      const a = path[i - 1]!
      const b = path[i]!
      // Distance to the segment, by sampling the closest point along it.
      const length = googleGeometry.computeDistanceBetween(a, b)
      const steps = Math.max(1, Math.ceil(length / Math.max(1, tolerance)))
      let lo = 0
      let hi = 1
      for (let k = 0; k < 40 && steps > 1; k++) {
        const m1 = lo + (hi - lo) / 3
        const m2 = hi - (hi - lo) / 3
        const d1 = googleGeometry.computeDistanceBetween(
          point,
          googleGeometry.interpolate(a, b, m1)
        )
        const d2 = googleGeometry.computeDistanceBetween(
          point,
          googleGeometry.interpolate(a, b, m2)
        )
        if (d1 < d2) hi = m2
        else lo = m1
      }
      const closest = googleGeometry.interpolate(a, b, (lo + hi) / 2)
      if (googleGeometry.computeDistanceBetween(point, closest) <= tolerance)
        return true
    }
    return false
  },

  /** Whether a point is within `tolerance` metres of a polygon's edge. */
  isLocationOnEdge(
    point: MapCoordinate,
    polygon: MapCoordinate[],
    tolerance = 0.1
  ): boolean {
    if (polygon.length === 0) return false
    return googleGeometry.isLocationOnPath(
      point,
      [...polygon, polygon[0]!],
      tolerance
    )
  },

  encodePath: encodePolyline,
  decodePath: decodePolyline,
}
