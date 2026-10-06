import type { ImageSourcePropType } from 'react-native'
import type {
  LineCap,
  MarkerBadge,
  MarkerBadgePosition,
  MarkerStyle,
  NativeCircle,
  NativeMarker,
  NativePolygon,
  NativePolyline,
  NativeTileOverlay,
} from './specs/MapFeatures.nitro'

type LatLng = { latitude: number; longitude: number }

/** A marker on a `MunimMapView`. Only `id` and `coordinate` are required. */
export interface MapMarker {
  id: string
  coordinate: LatLng
  title?: string
  subtitle?: string
  /** Default `marker` (MapKit's balloon). */
  style?: MarkerStyle
  /** Pin, balloon, dot or label colour. */
  color?: string
  /** Text or emoji in a `marker` balloon. */
  glyph?: string
  /** Picture for `image` and `avatar`: `require()`, URL or `{ uri }`. */
  image?: number | string | { uri: string } | ImageSourcePropType
  /** Width in points for `image`, diameter for `avatar` and `dot`. */
  size?: number
  border?: { color?: string; width?: number }
  /** Small pills around an `avatar` or `image`, such as a floor or an emoji. */
  badges?: {
    text: string
    position?: MarkerBadgePosition
    color?: string
    textColor?: string
  }[]
  /** Where the coordinate sits in the marker, 0...1. Default the centre (bottom for images). */
  anchor?: { x: number; y: number }
  zIndex?: number
  draggable?: boolean
  /** Markers sharing an id merge into a count when they overlap. */
  clusteringId?: string
  /** Show MapKit's callout (title, subtitle) on tap. Default false. */
  callout?: boolean
  opacity?: number
  visible?: boolean
}

export interface MapPolyline {
  id: string
  coordinates: LatLng[]
  strokeColor?: string
  strokeWidth?: number
  /** Dash and gap lengths in points, such as `[4, 10]`. */
  dashPattern?: number[]
  geodesic?: boolean
  lineCap?: LineCap
  zIndex?: number
}

export interface MapPolygon {
  id: string
  coordinates: LatLng[]
  holes?: LatLng[][]
  strokeColor?: string
  fillColor?: string
  strokeWidth?: number
  dashPattern?: number[]
  zIndex?: number
}

export interface MapCircle {
  id: string
  center: LatLng
  /** Metres. */
  radius: number
  strokeColor?: string
  fillColor?: string
  strokeWidth?: number
  dashPattern?: number[]
  zIndex?: number
}

export interface MapTileOverlay {
  id: string
  /** `https://tile.example.com/{z}/{x}/{y}.png`. */
  urlTemplate: string
  /** Hide Apple's map under the tiles. Default false. */
  replacesMap?: boolean
  minimumZoom?: number
  maximumZoom?: number
  opacity?: number
  zIndex?: number
}

function resolveImage(image: MapMarker['image']): string {
  if (image == null) return ''
  if (typeof image === 'string') return image
  if (typeof image === 'number') {
    const { Image } = require('react-native') as typeof import('react-native')
    return Image.resolveAssetSource(image)?.uri ?? ''
  }
  if (Array.isArray(image)) return image[0]?.uri ?? ''
  return (image as { uri?: string }).uri ?? ''
}

const dash = (pattern?: number[]) =>
  pattern && pattern.length >= 2 ? pattern.join(',') : ''

export function toNativeMarker(marker: MapMarker): NativeMarker {
  const style = marker.style ?? 'marker'
  const badges: MarkerBadge[] = (marker.badges ?? []).map((badge) => ({
    text: badge.text,
    position: badge.position ?? 'bottom',
    color: badge.color ?? '',
    textColor: badge.textColor ?? '',
  }))
  return {
    id: marker.id,
    latitude: marker.coordinate.latitude,
    longitude: marker.coordinate.longitude,
    title: marker.title ?? '',
    subtitle: marker.subtitle ?? '',
    style,
    color: marker.color ?? '',
    glyph: marker.glyph ?? '',
    imageUri: resolveImage(marker.image),
    imageSize: marker.size ?? 0,
    borderColor: marker.border?.color ?? '',
    borderWidth: marker.border?.width ?? (style === 'avatar' ? 2 : 0),
    badges,
    anchorX: marker.anchor?.x ?? 0.5,
    anchorY: marker.anchor?.y ?? (style === 'image' ? 1 : 0.5),
    zIndex: marker.zIndex ?? 0,
    draggable: marker.draggable ?? false,
    clusteringId: marker.clusteringId ?? '',
    calloutEnabled: marker.callout ?? false,
    opacity: marker.opacity ?? 1,
    visible: marker.visible ?? true,
  }
}

export function toNativePolyline(line: MapPolyline): NativePolyline {
  return {
    id: line.id,
    coordinates: line.coordinates.map((c) => ({
      latitude: c.latitude,
      longitude: c.longitude,
    })),
    strokeColor: line.strokeColor ?? '#0A84FF',
    strokeWidth: line.strokeWidth ?? 3,
    dashPattern: dash(line.dashPattern),
    geodesic: line.geodesic ?? false,
    lineCap: line.lineCap ?? 'round',
    zIndex: line.zIndex ?? 0,
  }
}

export function toNativePolygon(polygon: MapPolygon): NativePolygon {
  return {
    id: polygon.id,
    coordinates: polygon.coordinates.map((c) => ({
      latitude: c.latitude,
      longitude: c.longitude,
    })),
    holes: (polygon.holes ?? []).map((ring) =>
      ring.map((c) => ({ latitude: c.latitude, longitude: c.longitude }))
    ),
    strokeColor: polygon.strokeColor ?? '#0A84FF',
    fillColor: polygon.fillColor ?? '#0A84FF33',
    strokeWidth: polygon.strokeWidth ?? 2,
    dashPattern: dash(polygon.dashPattern),
    zIndex: polygon.zIndex ?? 0,
  }
}

export function toNativeCircle(circle: MapCircle): NativeCircle {
  return {
    id: circle.id,
    latitude: circle.center.latitude,
    longitude: circle.center.longitude,
    radius: circle.radius,
    strokeColor: circle.strokeColor ?? '#0A84FF',
    fillColor: circle.fillColor ?? '#0A84FF33',
    strokeWidth: circle.strokeWidth ?? 2,
    dashPattern: dash(circle.dashPattern),
    zIndex: circle.zIndex ?? 0,
  }
}

export function toNativeTileOverlay(
  overlay: MapTileOverlay
): NativeTileOverlay {
  return {
    id: overlay.id,
    urlTemplate: overlay.urlTemplate,
    replacesMap: overlay.replacesMap ?? false,
    minimumZoom: overlay.minimumZoom ?? 0,
    maximumZoom: overlay.maximumZoom ?? 0,
    opacity: overlay.opacity ?? 1,
    zIndex: overlay.zIndex ?? 0,
  }
}
