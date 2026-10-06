import type { MapCoordinate } from './MapModelLayer.nitro'

/**
 * Native map features for `MunimMapView`: markers, shapes and tile
 * overlays, everything react-native-maps draws on iOS, as plain data.
 *
 * Every field is required so no optional struct or enum crosses the bridge
 * (margelo/nitro#1319); the JavaScript wrapper fills the defaults.
 */

/**
 * - `pin`: the classic MapKit pin.
 * - `marker`: MapKit's balloon marker, with `glyph` text or emoji inside.
 * - `image`: a picture from `imageUri`, `imageSize` points wide.
 * - `avatar`: a round picture with a ring and corner badges.
 * - `label`: a text pill (`title`).
 * - `dot`: a small filled circle.
 */
export type MarkerStyle =
  'pin' | 'marker' | 'image' | 'avatar' | 'label' | 'dot'

export type MarkerBadgePosition =
  'top-left' | 'top-right' | 'bottom-left' | 'bottom-right' | 'bottom'

/** A small pill on an avatar or image marker, such as `5F` or an emoji. */
export interface MarkerBadge {
  text: string
  position: MarkerBadgePosition
  /** Pill colour; empty for near-black. */
  color: string
  /** Text colour; empty for white. */
  textColor: string
}

export interface NativeMarker {
  id: string
  latitude: number
  longitude: number
  title: string
  subtitle: string
  style: MarkerStyle
  /** Pin, balloon, dot or label colour. */
  color: string
  /** Text or emoji in a `marker` balloon. */
  glyph: string
  /** `file://`, absolute path or `http(s)://` PNG/JPEG for `image` and `avatar`. */
  imageUri: string
  /** Width in points for `image`, diameter for `avatar` and `dot`. */
  imageSize: number
  borderColor: string
  /** Ring width in points. */
  borderWidth: number
  badges: MarkerBadge[]
  /** Anchor in the marker image, 0...1 (0.5, 1 is the bottom centre). */
  anchorX: number
  anchorY: number
  zIndex: number
  draggable: boolean
  /** Markers with the same id merge into a count when they overlap. */
  clusteringId: string
  /** Show MapKit's callout with the title and subtitle on tap. */
  calloutEnabled: boolean
  /** Fade the marker, 0...1. */
  opacity: number
  visible: boolean
}

export type LineCap = 'round' | 'butt' | 'square'

export interface NativePolyline {
  id: string
  coordinates: MapCoordinate[]
  strokeColor: string
  strokeWidth: number
  /** Dash and gap lengths in points, alternating; empty for a solid line. */
  dashPattern: string
  /** Follow the curve of the Earth between points. */
  geodesic: boolean
  lineCap: LineCap
  zIndex: number
}

export interface NativePolygon {
  id: string
  coordinates: MapCoordinate[]
  /** Cut-outs, each a ring of coordinates. */
  holes: MapCoordinate[][]
  strokeColor: string
  fillColor: string
  strokeWidth: number
  dashPattern: string
  zIndex: number
}

export interface NativeCircle {
  id: string
  latitude: number
  longitude: number
  /** Metres. */
  radius: number
  strokeColor: string
  fillColor: string
  strokeWidth: number
  dashPattern: string
  zIndex: number
}

export interface NativeTileOverlay {
  id: string
  /** `https://tile.example.com/{z}/{x}/{y}.png`. */
  urlTemplate: string
  /** Hide Apple's map under the tiles (your own base map). */
  replacesMap: boolean
  minimumZoom: number
  maximumZoom: number
  opacity: number
  zIndex: number
}

export interface MapPoint {
  x: number
  y: number
}

export interface MapRegion {
  latitude: number
  longitude: number
  latitudeDelta: number
  longitudeDelta: number
}

export interface MapPressEvent {
  latitude: number
  longitude: number
  x: number
  y: number
}

export interface MarkerDragEvent {
  id: string
  latitude: number
  longitude: number
}

export interface UserLocationEvent {
  latitude: number
  longitude: number
  /** Metres above sea level. */
  altitude: number
  horizontalAccuracy: number
  verticalAccuracy: number
  /** Degrees, or -1 when unknown. */
  heading: number
  /** Metres per second, or -1 when unknown. */
  speed: number
}

/** A place on Apple's map that the user tapped (`selectableMapFeatures`). */
export interface MapFeatureEvent {
  title: string
  latitude: number
  longitude: number
  /** `pointOfInterest`, `territory` or `physicalFeature`. */
  kind: string
  /** The point-of-interest category, such as `MKPOICategoryCafe`, or empty. */
  category: string
}

export interface MapAddress {
  name: string
  street: string
  city: string
  region: string
  postalCode: string
  country: string
  countryCode: string
  formatted: string
}
