import type { HybridObject } from 'react-native-nitro-modules'
import type { MapCoordinate } from './MapModelLayer.nitro'
import type { MapItem, MapRegion } from './MapFeatures.nitro'
import type {
  MapCamera,
  MapColorScheme,
  MapElevation,
  MapStyle,
} from './MunimMapView.nitro'

/**
 * MapKit's services (search, directions, geocoding, places, snapshots,
 * Look Around imagery), not tied to a map view.
 *
 * Every field is required so no optional struct or enum crosses the bridge
 * (margelo/nitro#1319), and lists of strings travel as one string (Nitro
 * 0.36 cannot hand `string[]` to Swift on Xcode 26); the JavaScript wrapper
 * in `services.ts` fills the defaults and splits them.
 */

export interface NativeSearchRequest {
  query: string
  /** Zero deltas for none. */
  region: MapRegion
  /** Comma-separated `address`, `pointOfInterest`, `physicalFeature` (iOS 18); empty for all. */
  resultTypes: string
  /** `all`, `none`, or comma-separated `MKPOICategory…` values. */
  pointsOfInterest: string
  /** Keep results inside `region` (iOS 18). */
  regionRequired: boolean
}

export interface SearchCompletion {
  title: string
  subtitle: string
  /** `start,length` pairs separated by `;`, the matched characters of the title. */
  titleHighlights: string
  subtitleHighlights: string
  /** Position in the completer's current results, for `resolve`. */
  index: number
}

/** `MKLocalSearchCompleter`: suggestions while the user types. */
export interface SearchCompleter extends HybridObject<{ ios: 'swift' }> {
  setQuery(query: string): void
  /** Zero deltas for none. */
  setRegion(region: MapRegion): void
  /** Comma-separated `address`, `pointOfInterest`, `query`, `physicalFeature` (iOS 18); empty for all. */
  setResultTypes(types: string): void
  setPointsOfInterest(filter: string): void
  setListener(
    onResults: (results: SearchCompletion[]) => void,
    onError: (message: string) => void
  ): void
  /** The places behind one of the current results. */
  resolve(index: number): Promise<MapItem[]>
  cancel(): void
}

export interface NativePointsOfInterestRequest {
  latitude: number
  longitude: number
  /** Metres around the centre; 0 to use `region`. Capped at MapKit's 2 km. */
  radius: number
  region: MapRegion
  /** `all`, `none`, or comma-separated `MKPOICategory…` values. */
  pointsOfInterest: string
}

/** A start or end of directions: a place id, the user, or a coordinate. */
export interface NativeWaypoint {
  latitude: number
  longitude: number
  /** An `MKMapItem.Identifier` (iOS 18+); wins over the coordinate. */
  mapItemId: string
  currentLocation: boolean
}

export type TransportType =
  'automobile' | 'walking' | 'transit' | 'cycling' | 'any'

export interface NativeDirectionsRequest {
  from: NativeWaypoint
  to: NativeWaypoint
  transportType: TransportType
  alternates: boolean
  /** Seconds since 1970, or 0. */
  departureDate: number
  arrivalDate: number
  avoidTolls: boolean
  avoidHighways: boolean
}

export interface RouteStep {
  instructions: string
  notice: string
  distance: number
  transportType: TransportType
  coordinates: MapCoordinate[]
}

export interface Route {
  name: string
  /** Metres. */
  distance: number
  /** Seconds. */
  expectedTravelTime: number
  transportType: TransportType
  /** Joined with newlines. */
  advisoryNotices: string
  hasTolls: boolean
  hasHighways: boolean
  coordinates: MapCoordinate[]
  steps: RouteStep[]
}

export interface Eta {
  /** Seconds. */
  expectedTravelTime: number
  /** Metres. */
  distance: number
  /** Seconds since 1970. */
  expectedArrivalDate: number
  expectedDepartureDate: number
  transportType: TransportType
}

/** `automatic` uses the person's preferred mode in Apple Maps. */
export type DirectionsMode =
  'none' | 'automatic' | 'driving' | 'walking' | 'transit' | 'cycling'

export interface NativeOpenInMapsOptions {
  directionsMode: DirectionsMode
  /** Zero distance for none. */
  camera: MapCamera
  /** Zero deltas for none. */
  region: MapRegion
  mapStyle: MapStyle
  showsTraffic: boolean
}

export interface NativeSnapshotRequest {
  /** Zero deltas to use `camera`. */
  region: MapRegion
  camera: MapCamera
  width: number
  height: number
  mapStyle: MapStyle
  elevation: MapElevation
  colorScheme: MapColorScheme
  pointsOfInterest: string
  showsBuildings: boolean
  showsTraffic: boolean
}

export interface MapServices extends HybridObject<{ ios: 'swift' }> {
  searchPlaces(request: NativeSearchRequest): Promise<MapItem[]>
  createSearchCompleter(): SearchCompleter
  pointsOfInterest(request: NativePointsOfInterestRequest): Promise<MapItem[]>
  directions(request: NativeDirectionsRequest): Promise<Route[]>
  eta(request: NativeDirectionsRequest): Promise<Eta>
  /** `region` (zero deltas for none) biases the results. */
  geocode(address: string, region: MapRegion): Promise<MapItem[]>
  reverseGeocode(coordinate: MapCoordinate): Promise<MapItem[]>
  /** iOS 18+. */
  mapItem(identifier: string): Promise<MapItem>
  /** Places: `identifier` when set, else the coordinate (and `name`). */
  openInMaps(
    items: MapItem[],
    options: NativeOpenInMapsOptions
  ): Promise<boolean>
  /** Writes a PNG and returns its path. */
  snapshot(request: NativeSnapshotRequest): Promise<string>
  hasLookAround(coordinate: MapCoordinate): Promise<boolean>
  /** Writes a PNG of the Look Around view at a coordinate (or place id) and returns its path. */
  lookAroundSnapshot(
    coordinate: MapCoordinate,
    mapItemId: string,
    width: number,
    height: number,
    pointsOfInterest: string,
    colorScheme: MapColorScheme
  ): Promise<string>
  /** `MKDistanceFormatter`: `units` `default`, `metric`, `imperial`, `imperialWithYards`; `style` `default`, `abbreviated`, `full`. */
  formatDistance(meters: number, units: string, style: string): string
}
