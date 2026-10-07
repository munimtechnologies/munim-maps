import type { ImageSourcePropType } from 'react-native'
import type {
  CalloutAccessoryKind,
  FeatureVisibility,
  LineCap,
  LineJoin,
  OverlayLevel,
  MarkerCollisionMode,
  NativeCalloutAccessory,
  NativeClusterStyle,
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

/**
 * How much a marker matters when markers overlap: `'required'` (1000, never
 * hidden, the default), `'high'` (750), `'low'` (250), or 0...1000.
 */
export type MarkerDisplayPriority = 'required' | 'high' | 'low' | number

/**
 * A button or picture at one end of a marker's callout. `'detail'` and
 * `'info'` are UIKit's round buttons; `{ text }` or `{ symbol }` makes a
 * button; `{ image }` or `{ symbol, button: false }` a picture. Taps fire
 * `onCalloutAccessoryPress` (and `onCalloutPress`).
 */
export type CalloutAccessory =
  | 'detail'
  | 'info'
  | {
      text?: string
      /** SF Symbol name, such as `'phone.fill'`. */
      symbol?: string
      image?: number | string | { uri: string }
      /** Default true, false for `image`. */
      button?: boolean
      color?: string
    }

/** The look of a cluster of markers sharing `clusteringId`. */
export interface MapClusterStyle {
  clusteringId: string
  /** Balloon colour. */
  color?: string
  glyphColor?: string
  /** Text in the balloon; `{count}` is the number of markers. Default the count. */
  glyph?: string
  /** SF Symbol in the balloon instead of text. */
  glyphSymbol?: string
  /** Title under the balloon, such as `'{count} cafés'`. */
  title?: string
  subtitle?: string
  displayPriority?: MarkerDisplayPriority
}

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
  /** Left end of the callout. Default none. */
  calloutLeft?: CalloutAccessory | null
  /** Right end of the callout. Default `'detail'`; `null` for none. */
  calloutRight?: CalloutAccessory | null
  /** Several lines of text in the callout, in place of the subtitle. */
  calloutDetail?: string
  opacity?: number
  visible?: boolean
  /** What MapKit hides first where markers overlap. Default `'required'`. */
  displayPriority?: MarkerDisplayPriority
  /** The shape MapKit uses to find overlaps. Default `'rectangle'`. */
  collisionMode?: MarkerCollisionMode
  /** `marker` style: when the title shows under the balloon. Default `'adaptive'`. */
  titleVisibility?: FeatureVisibility
  subtitleVisibility?: FeatureVisibility
  /** `marker` style: an SF Symbol in the balloon, such as `'cup.and.saucer.fill'`. */
  glyphSymbol?: string
  /** `marker` style: the SF Symbol while selected. */
  selectedGlyphSymbol?: string
  /** `marker` style: colour of the glyph. Default white. */
  glyphColor?: string
  /** `marker` style: MapKit's drop-in animation when added. Default false. */
  animatesWhenAdded?: boolean
}

/** Shared by polylines, polygons and circles. */
interface OverlayOptions {
  /**
   * `'aboveLabels'` (default) draws over MapKit's labels; `'aboveRoads'`
   * draws under labels and buildings, like Apple Maps' routes.
   */
  level?: OverlayLevel
  /** Taps on it fire the map's `onOverlayPress`. Default true. */
  tappable?: boolean
}

export interface MapPolyline extends OverlayOptions {
  id: string
  coordinates: LatLng[]
  strokeColor?: string
  /**
   * A gradient along the line (MKGradientPolylineRenderer): two or more
   * colours, from the first coordinate to the last.
   */
  strokeColors?: string[]
  /** Where each of `strokeColors` sits along the line, 0...1. Default evenly spaced. */
  strokeColorLocations?: number[]
  strokeWidth?: number
  /** Dash and gap lengths in points, such as `[4, 10]`. */
  dashPattern?: number[]
  geodesic?: boolean
  lineCap?: LineCap
  /** Default `'round'`. */
  lineJoin?: LineJoin
  /**
   * Draw only part of the line, 0...1 of its length (default 0 and 1).
   * Change `strokeEnd` over time to animate a route being drawn; it updates
   * in place.
   */
  strokeStart?: number
  strokeEnd?: number
  zIndex?: number
}

export interface MapPolygon extends OverlayOptions {
  id: string
  coordinates: LatLng[]
  holes?: LatLng[][]
  strokeColor?: string
  fillColor?: string
  strokeWidth?: number
  dashPattern?: number[]
  lineJoin?: LineJoin
  zIndex?: number
}

export interface MapCircle extends OverlayOptions {
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
  /** Default `'aboveRoads'` (under labels); `'aboveLabels'` covers them. */
  level?: OverlayLevel
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

export function displayPriorityValue(
  priority: MarkerDisplayPriority | undefined
): number {
  if (priority === 'high') return 750
  if (priority === 'low') return 250
  if (typeof priority === 'number') return Math.min(1000, Math.max(0, priority))
  return 1000
}

const NO_ACCESSORY: NativeCalloutAccessory = {
  kind: 'none',
  text: '',
  symbol: '',
  imageUri: '',
  color: '',
}

function toNativeAccessory(
  accessory: CalloutAccessory | null | undefined
): NativeCalloutAccessory {
  if (accessory == null) return NO_ACCESSORY
  if (accessory === 'detail' || accessory === 'info') {
    return { ...NO_ACCESSORY, kind: accessory }
  }
  const imageUri = resolveImage(accessory.image)
  const kind: CalloutAccessoryKind =
    (accessory.button ?? !imageUri) ? 'button' : 'image'
  return {
    kind,
    text: accessory.text ?? '',
    symbol: accessory.symbol ?? '',
    imageUri,
    color: accessory.color ?? '',
  }
}

export function toNativeClusterStyle(
  style: MapClusterStyle
): NativeClusterStyle {
  return {
    clusteringId: style.clusteringId,
    color: style.color ?? '',
    glyphColor: style.glyphColor ?? '',
    glyph: style.glyph ?? '',
    glyphSymbol: style.glyphSymbol ?? '',
    title: style.title ?? '',
    subtitle: style.subtitle ?? '',
    displayPriority: displayPriorityValue(style.displayPriority),
  }
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
    displayPriority: displayPriorityValue(marker.displayPriority),
    collisionMode: marker.collisionMode ?? 'rectangle',
    titleVisibility: marker.titleVisibility ?? 'adaptive',
    subtitleVisibility: marker.subtitleVisibility ?? 'adaptive',
    glyphSymbol: marker.glyphSymbol ?? '',
    selectedGlyphSymbol: marker.selectedGlyphSymbol ?? '',
    glyphColor: marker.glyphColor ?? '',
    animatesWhenAdded: marker.animatesWhenAdded ?? false,
    leftCalloutAccessory: toNativeAccessory(marker.calloutLeft),
    rightCalloutAccessory: toNativeAccessory(
      marker.calloutRight === undefined ? 'detail' : marker.calloutRight
    ),
    calloutDetail: marker.calloutDetail ?? '',
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
    strokeColors: (line.strokeColors ?? []).join(','),
    strokeColorLocations: (line.strokeColorLocations ?? []).join(','),
    lineJoin: line.lineJoin ?? 'round',
    strokeStart: line.strokeStart ?? 0,
    strokeEnd: line.strokeEnd ?? 1,
    level: line.level ?? 'aboveLabels',
    tappable: line.tappable ?? true,
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
    lineJoin: polygon.lineJoin ?? 'round',
    level: polygon.level ?? 'aboveLabels',
    tappable: polygon.tappable ?? true,
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
    level: circle.level ?? 'aboveLabels',
    tappable: circle.tappable ?? true,
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
    level: overlay.level ?? 'aboveRoads',
  }
}
