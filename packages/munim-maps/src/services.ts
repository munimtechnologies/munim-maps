import { Platform } from 'react-native'
import { NitroModules } from 'react-native-nitro-modules'
import type { MapItem, MapRegion } from './specs/MapFeatures.nitro'
import type {
  DirectionsMode,
  Eta,
  MapServices,
  NativeWaypoint,
  Route as NativeRoute,
  SearchCompleter as NativeSearchCompleter,
  SearchCompletion as NativeSearchCompletion,
  TransportType,
} from './specs/MapServices.nitro'
import type {
  MapCamera,
  MapColorScheme,
  MapElevation,
  MapStyle,
} from './specs/MunimMapView.nitro'

type LatLng = { latitude: number; longitude: number }

/**
 * MapKit's services, usable without a map on screen: search, autocomplete,
 * points of interest, directions and travel times, geocoding, places by id,
 * Apple Maps hand-off, map and Look Around images. iOS only; everything
 * rejects (or returns nothing) elsewhere.
 */

let services: MapServices | undefined
function native(): MapServices {
  if (Platform.OS !== 'ios') {
    throw new Error('munim-maps: MapKit services are iOS only')
  }
  services ??= NitroModules.createHybridObject<MapServices>('MapServices')
  return services
}

async function call<T>(run: (s: MapServices) => Promise<T>): Promise<T> {
  return run(native())
}

const NO_REGION: MapRegion = {
  latitude: 0,
  longitude: 0,
  latitudeDelta: 0,
  longitudeDelta: 0,
}

/**
 * A point-of-interest category: MapKit's raw value (`'MKPOICategoryCafe'`)
 * or its short name (`'cafe'`, `'evCharger'`, `'nationalPark'`).
 */
export type PointOfInterestCategory = string

/** `'MKPOICategoryCafe'` for `'cafe'`; raw values pass through. */
export function pointOfInterestCategory(name: string): string {
  if (name.startsWith('MKPOICategory')) return name
  return `MKPOICategory${name.charAt(0).toUpperCase()}${name.slice(1)}`
}

/** `'all'`, `'none'` or categories, as the native side takes it. */
export function pointsOfInterestFilter(
  filter: 'all' | 'none' | PointOfInterestCategory[] | undefined
): string {
  if (filter == null || filter === 'all') return 'all'
  if (filter === 'none') return 'none'
  return filter.map(pointOfInterestCategory).join(',')
}

export type SearchResultType = 'address' | 'pointOfInterest' | 'physicalFeature'

export interface SearchOptions {
  query: string
  /** Search near here (results are biased to it). */
  region?: MapRegion
  /** Keep results inside `region` (iOS 18+). Default false. */
  regionRequired?: boolean
  /** Default all. `physicalFeature` needs iOS 18. */
  resultTypes?: SearchResultType[]
  /** Only these categories of points of interest. Default all. */
  pointsOfInterest?: 'all' | 'none' | PointOfInterestCategory[]
}

/** `MKLocalSearch`: places matching a query, such as "coffee" or an address. */
export function searchPlaces(options: SearchOptions): Promise<MapItem[]> {
  return call((s) =>
    s.searchPlaces({
      query: options.query,
      region: options.region ?? NO_REGION,
      resultTypes: (options.resultTypes ?? []).join(','),
      pointsOfInterest: pointsOfInterestFilter(options.pointsOfInterest),
      regionRequired: options.regionRequired ?? false,
    })
  )
}

/** One suggestion from a `SearchCompleter`. */
export interface SearchCompletion {
  title: string
  subtitle: string
  /** The matched characters of `title`, as `[start, length]` pairs (UTF-16). */
  titleHighlights: [number, number][]
  subtitleHighlights: [number, number][]
  /** Its position in the latest results, for `resolve`. */
  index: number
}

export type CompleterResultType =
  'address' | 'pointOfInterest' | 'query' | 'physicalFeature'

export interface SearchCompleterOptions {
  region?: MapRegion
  /** Default all. */
  resultTypes?: CompleterResultType[]
  pointsOfInterest?: 'all' | 'none' | PointOfInterestCategory[]
  onResults: (results: SearchCompletion[]) => void
  onError?: (message: string) => void
}

/** `MKLocalSearchCompleter`: suggestions while the user types. */
export interface SearchCompleter {
  /** Updates the suggestions; `onResults` fires when they arrive. */
  setQuery(query: string): void
  setRegion(region: MapRegion): void
  setResultTypes(types: CompleterResultType[]): void
  setPointsOfInterest(filter: 'all' | 'none' | PointOfInterestCategory[]): void
  /** The places behind a suggestion (`completion.index`). */
  resolve(completion: SearchCompletion | number): Promise<MapItem[]>
  cancel(): void
}

function ranges(text: string): [number, number][] {
  if (!text) return []
  return text.split(';').map((pair) => {
    const [start, length] = pair.split(',').map(Number)
    return [start ?? 0, length ?? 0]
  })
}

function toCompletion(c: NativeSearchCompletion): SearchCompletion {
  return {
    title: c.title,
    subtitle: c.subtitle,
    titleHighlights: ranges(c.titleHighlights),
    subtitleHighlights: ranges(c.subtitleHighlights),
    index: c.index,
  }
}

/**
 * Creates an autocomplete session (`MKLocalSearchCompleter`). Keep it while
 * the search field is up and call `setQuery` on every keystroke.
 *
 * ```ts
 * const completer = createSearchCompleter({ region, onResults: setSuggestions })
 * completer.setQuery('coff')
 * const [place] = await completer.resolve(suggestions[0])
 * ```
 */
export function createSearchCompleter(
  options: SearchCompleterOptions
): SearchCompleter {
  const completer: NativeSearchCompleter = native().createSearchCompleter()
  completer.setListener(
    (results) => options.onResults(results.map(toCompletion)),
    (message) => options.onError?.(message)
  )
  if (options.region) completer.setRegion(options.region)
  if (options.resultTypes)
    completer.setResultTypes(options.resultTypes.join(','))
  if (options.pointsOfInterest)
    completer.setPointsOfInterest(
      pointsOfInterestFilter(options.pointsOfInterest)
    )
  return {
    setQuery: (query) => completer.setQuery(query),
    setRegion: (region) => completer.setRegion(region),
    setResultTypes: (types) => completer.setResultTypes(types.join(',')),
    setPointsOfInterest: (filter) =>
      completer.setPointsOfInterest(pointsOfInterestFilter(filter)),
    resolve: (completion) =>
      completer.resolve(
        typeof completion === 'number' ? completion : completion.index
      ),
    cancel: () => completer.cancel(),
  }
}

export interface PointsOfInterestOptions {
  /** Around a centre, up to MapKit's 2 km radius… */
  center?: LatLng
  /** Metres. Default 500. */
  radius?: number
  /** …or inside a region. */
  region?: MapRegion
  categories?: 'all' | PointOfInterestCategory[]
}

/** `MKLocalPointsOfInterestRequest`: points of interest around a place, no query needed. */
export function pointsOfInterest(
  options: PointsOfInterestOptions
): Promise<MapItem[]> {
  const center =
    options.center ??
    (options.region
      ? {
          latitude: options.region.latitude,
          longitude: options.region.longitude,
        }
      : { latitude: 0, longitude: 0 })
  return call((s) =>
    s.pointsOfInterest({
      latitude: center.latitude,
      longitude: center.longitude,
      radius: options.region && !options.center ? 0 : (options.radius ?? 500),
      region: options.region ?? NO_REGION,
      pointsOfInterest: pointsOfInterestFilter(options.categories),
    })
  )
}

/** A start or end of a route: a coordinate, a place, or the user. */
export type Waypoint =
  LatLng | MapItem | { mapItemId: string } | 'currentLocation'

function toWaypoint(point: Waypoint): NativeWaypoint {
  if (point === 'currentLocation') {
    return { latitude: 0, longitude: 0, mapItemId: '', currentLocation: true }
  }
  if ('mapItemId' in point) {
    return {
      latitude: 0,
      longitude: 0,
      mapItemId: point.mapItemId,
      currentLocation: false,
    }
  }
  const item = point as Partial<MapItem> & LatLng
  return {
    latitude: item.latitude,
    longitude: item.longitude,
    mapItemId: item.identifier ?? '',
    currentLocation: item.isCurrentLocation ?? false,
  }
}

export type { TransportType, DirectionsMode, Eta }

export interface DirectionsOptions {
  from: Waypoint
  to: Waypoint
  /**
   * Default `'automobile'`. `'transit'` only works for `eta` (MapKit gives
   * no transit routes); `'cycling'` needs iOS 14.
   */
  transportType?: TransportType
  /** Ask for more than one route. Default false. */
  alternates?: boolean
  departureDate?: Date
  arrivalDate?: Date
  avoidTolls?: boolean
  avoidHighways?: boolean
}

export interface RouteStep {
  instructions: string
  notice: string
  /** Metres. */
  distance: number
  transportType: TransportType
  coordinates: LatLng[]
}

export interface Route {
  name: string
  /** Metres. */
  distance: number
  /** Seconds. */
  expectedTravelTime: number
  transportType: TransportType
  advisoryNotices: string[]
  hasTolls: boolean
  hasHighways: boolean
  /** The full route, ready for a `polylines` entry (see `routePolyline`). */
  coordinates: LatLng[]
  steps: RouteStep[]
}

function toRoute(route: NativeRoute): Route {
  return {
    ...route,
    advisoryNotices: route.advisoryNotices
      ? route.advisoryNotices.split('\n')
      : [],
  }
}

function toDirectionsRequest(options: DirectionsOptions) {
  return {
    from: toWaypoint(options.from),
    to: toWaypoint(options.to),
    transportType: options.transportType ?? 'automobile',
    alternates: options.alternates ?? false,
    departureDate: options.departureDate
      ? options.departureDate.getTime() / 1000
      : 0,
    arrivalDate: options.arrivalDate ? options.arrivalDate.getTime() / 1000 : 0,
    avoidTolls: options.avoidTolls ?? false,
    avoidHighways: options.avoidHighways ?? false,
  } as const
}

/** `MKDirections`: routes with their lines and turn-by-turn steps. */
export async function directions(options: DirectionsOptions): Promise<Route[]> {
  const routes = await call((s) => s.directions(toDirectionsRequest(options)))
  return routes.map(toRoute)
}

/** `MKDirections.calculateETA`: travel time without the route's geometry (works for transit). */
export function eta(options: DirectionsOptions): Promise<Eta> {
  return call((s) => s.eta(toDirectionsRequest(options)))
}

/**
 * Places for an address (iOS 26 `MKGeocodingRequest`, `CLGeocoder` before).
 * `region` biases the results.
 */
export function geocode(
  address: string,
  region?: MapRegion
): Promise<MapItem[]> {
  return call((s) => s.geocode(address, region ?? NO_REGION))
}

/** Places at a coordinate (iOS 26 `MKReverseGeocodingRequest`, `CLGeocoder` before). */
export function reverseGeocode(coordinate: LatLng): Promise<MapItem[]> {
  return call((s) =>
    s.reverseGeocode({
      latitude: coordinate.latitude,
      longitude: coordinate.longitude,
    })
  )
}

/** A place by its `MapItem.identifier` (`MKMapItemRequest`, iOS 18+). */
export function mapItem(identifier: string): Promise<MapItem> {
  return call((s) => s.mapItem(identifier))
}

export interface OpenInMapsOptions {
  /** Open directions to the last place. Default none (just show the places). */
  directionsMode?: DirectionsMode
  camera?: MapCamera
  region?: MapRegion
  mapStyle?: MapStyle
  showsTraffic?: boolean
}

/**
 * Opens Apple Maps on places (`MKMapItem.openMaps`): items from search, or
 * just `{ latitude, longitude, name }`. With `directionsMode`, directions
 * from the first to the last (one place: from the user).
 */
export function openInMaps(
  items: (MapItem | (LatLng & { name?: string }))[],
  options: OpenInMapsOptions = {}
): Promise<boolean> {
  const full = items.map((item): MapItem => ({
    identifier: '',
    name: '',
    phoneNumber: '',
    url: '',
    category: '',
    timeZone: '',
    address: {
      name: '',
      street: '',
      city: '',
      region: '',
      postalCode: '',
      country: '',
      countryCode: '',
      formatted: '',
      shortAddress: '',
    },
    isCurrentLocation: false,
    ...item,
  }))
  return call((s) =>
    s.openInMaps(full, {
      directionsMode: options.directionsMode ?? 'none',
      camera: options.camera ?? {
        latitude: 0,
        longitude: 0,
        distance: 0,
        pitch: 0,
        heading: 0,
      },
      region: options.region ?? NO_REGION,
      mapStyle: options.mapStyle ?? 'standard',
      showsTraffic: options.showsTraffic ?? false,
    })
  )
}

export interface MapSnapshotOptions {
  /** What to show: a region… */
  region?: MapRegion
  /** …or a camera. */
  camera?: MapCamera
  /** Points. */
  width: number
  height: number
  mapStyle?: MapStyle
  elevation?: MapElevation
  colorScheme?: MapColorScheme
  pointsOfInterest?: 'all' | 'none' | PointOfInterestCategory[]
  showsBuildings?: boolean
  showsTraffic?: boolean
}

/** `MKMapSnapshotter`: a PNG of a map, no view needed. Resolves its file path. */
export function mapSnapshot(options: MapSnapshotOptions): Promise<string> {
  return call((s) =>
    s.snapshot({
      region: options.region ?? NO_REGION,
      camera: options.camera ?? {
        latitude: options.region?.latitude ?? 0,
        longitude: options.region?.longitude ?? 0,
        distance: 1000,
        pitch: 0,
        heading: 0,
      },
      width: options.width,
      height: options.height,
      mapStyle: options.mapStyle ?? 'standard',
      elevation: options.elevation ?? 'flat',
      colorScheme: options.colorScheme ?? 'system',
      pointsOfInterest: pointsOfInterestFilter(options.pointsOfInterest),
      showsBuildings: options.showsBuildings ?? true,
      showsTraffic: options.showsTraffic ?? false,
    })
  )
}

/** Whether Apple has Look Around imagery at a coordinate. */
export function hasLookAround(coordinate: LatLng): Promise<boolean> {
  return call((s) =>
    s.hasLookAround({
      latitude: coordinate.latitude,
      longitude: coordinate.longitude,
    })
  )
}

export interface LookAroundSnapshotOptions {
  /** Where, or `mapItemId`. */
  coordinate?: LatLng
  mapItemId?: string
  /** Points. */
  width: number
  height: number
  pointsOfInterest?: 'all' | 'none' | PointOfInterestCategory[]
  colorScheme?: MapColorScheme
}

/** `MKLookAroundSnapshotter`: a PNG of the street-level view. Resolves its file path. */
export function lookAroundSnapshot(
  options: LookAroundSnapshotOptions
): Promise<string> {
  return call((s) =>
    s.lookAroundSnapshot(
      {
        latitude: options.coordinate?.latitude ?? 0,
        longitude: options.coordinate?.longitude ?? 0,
      },
      options.mapItemId ?? '',
      options.width,
      options.height,
      pointsOfInterestFilter(options.pointsOfInterest),
      options.colorScheme ?? 'system'
    )
  )
}

/**
 * Apple's place card for a place id (`MKMapItemDetailViewController`, iOS
 * 18+), as a sheet: hours, photos, ratings, call and directions buttons.
 * Resolves false where it is not available.
 */
export function presentPlaceCard(identifier: string): Promise<boolean> {
  return call((s) => s.presentPlaceCard(identifier))
}

/** `MKDistanceFormatter`: "1.2 mi" or "2 km", in the user's locale. */
export function formatDistance(
  meters: number,
  options: {
    units?: 'default' | 'metric' | 'imperial' | 'imperialWithYards'
    style?: 'default' | 'abbreviated' | 'full'
  } = {}
): string {
  return native().formatDistance(
    meters,
    options.units ?? 'default',
    options.style ?? 'default'
  )
}

/**
 * A `polylines` entry drawing a route like Apple Maps: under the labels,
 * with a round cap and join.
 */
export function routePolyline(
  route: Pick<Route, 'coordinates'>,
  style: {
    id: string
    strokeColor?: string
    strokeColors?: string[]
    strokeWidth?: number
  }
) {
  return {
    id: style.id,
    coordinates: route.coordinates,
    strokeColor: style.strokeColor ?? '#0A84FF',
    strokeColors: style.strokeColors,
    strokeWidth: style.strokeWidth ?? 6,
    lineCap: 'round' as const,
    lineJoin: 'round' as const,
    level: 'aboveRoads' as const,
  }
}
