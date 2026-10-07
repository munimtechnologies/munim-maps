/**
 * Google's web services, called with your own key: Places API (New)
 * (autocomplete, place details, text and nearby search, photos), the
 * Geocoding API and the Routes API (routes and route matrices).
 *
 * These are not part of the Maps SDKs, so the key needs each API turned on
 * in the Google Cloud console, and they are billed per request. A key
 * restricted to the Maps SDK for iOS / Android does not work here. Better:
 * call them from your server (keep the key there) and pass the results to
 * the map. From the app, give a separate key restricted to these APIs and to
 * your app (`iosBundleId`, or `androidPackage` + `androidCertSha1`), which
 * are sent as the `X-Ios-Bundle-Identifier` / `X-Android-*` headers Google
 * checks for app-restricted keys.
 *
 * ```ts
 * const google = googleMapsServices({ apiKey })
 * const { suggestions } = await google.places.autocomplete({ input: 'pizza', origin })
 * ```
 */
import { Platform } from 'react-native'
import type { MapCoordinate } from '../specs/MapModelLayer.nitro'

export interface GoogleServicesOptions {
  apiKey: string
  /** iOS: your app's bundle ID, for keys restricted to iOS apps. */
  iosBundleId?: string
  /** Android: your package name and signing certificate SHA-1, for keys restricted to Android apps. */
  androidPackage?: string
  androidCertSha1?: string
  /** BCP-47 language for results, such as `en`. */
  languageCode?: string
  /** CLDR region, such as `us`. */
  regionCode?: string
  /** Your own `fetch` (proxying, tests). */
  fetch?: typeof fetch
}

/** An error from a Google web service, with Google's status. */
export class GoogleServiceError extends Error {
  constructor(
    message: string,
    /** HTTP status, or 0 for a network error. */
    readonly httpStatus: number,
    /** Google's status, such as `PERMISSION_DENIED` or `REQUEST_DENIED`. */
    readonly status: string
  ) {
    super(message)
    this.name = 'GoogleServiceError'
  }
}

export interface GoogleLocalizedText {
  text: string
  languageCode?: string
}

/** A place from Places API (New); the fields you asked for. */
export interface GooglePlace {
  id?: string
  name?: string
  displayName?: GoogleLocalizedText
  formattedAddress?: string
  shortFormattedAddress?: string
  location?: MapCoordinate
  types?: string[]
  primaryType?: string
  rating?: number
  userRatingCount?: number
  priceLevel?: string
  websiteUri?: string
  nationalPhoneNumber?: string
  internationalPhoneNumber?: string
  googleMapsUri?: string
  businessStatus?: string
  utcOffsetMinutes?: number
  regularOpeningHours?: { openNow?: boolean; weekdayDescriptions?: string[] }
  photos?: { name: string; widthPx: number; heightPx: number; authorAttributions?: unknown[] }[]
  viewport?: { low: MapCoordinate; high: MapCoordinate }
  [field: string]: unknown
}

export interface GoogleAutocompleteSuggestion {
  placePrediction?: {
    placeId: string
    place: string
    text: { text: string }
    structuredFormat?: { mainText: { text: string }; secondaryText?: { text: string } }
    types?: string[]
    distanceMeters?: number
  }
  queryPrediction?: { text: { text: string } }
}

/** Where to look: around a point, or inside a rectangle. */
export type GoogleLocationBias =
  | { circle: { center: MapCoordinate; radius: number } }
  | { rectangle: { low: MapCoordinate; high: MapCoordinate } }

export type GoogleTravelMode = 'DRIVE' | 'BICYCLE' | 'WALK' | 'TWO_WHEELER' | 'TRANSIT'

export interface GoogleWaypoint {
  /** A coordinate, a place ID, or an address. */
  location?: MapCoordinate
  placeId?: string
  address?: string
  /** Stop here (false: pass through). */
  via?: boolean
}

export interface GoogleRoute {
  distanceMeters?: number
  /** `"123s"`. */
  duration?: string
  staticDuration?: string
  polyline?: { encodedPolyline: string }
  /** `polyline` decoded. */
  coordinates: MapCoordinate[]
  description?: string
  legs?: unknown[]
  travelAdvisory?: unknown
  routeLabels?: string[]
  [field: string]: unknown
}

const DEFAULT_PLACE_FIELDS = [
  'id',
  'displayName',
  'formattedAddress',
  'location',
  'types',
  'primaryType',
  'rating',
  'userRatingCount',
  'googleMapsUri',
  'websiteUri',
  'nationalPhoneNumber',
  'regularOpeningHours',
  'photos',
  'viewport',
]

const DEFAULT_ROUTE_FIELDS = [
  'routes.distanceMeters',
  'routes.duration',
  'routes.staticDuration',
  'routes.polyline.encodedPolyline',
  'routes.description',
  'routes.routeLabels',
  'routes.legs.distanceMeters',
  'routes.legs.duration',
  'routes.legs.startLocation',
  'routes.legs.endLocation',
  'routes.legs.steps.navigationInstruction',
  'routes.legs.steps.distanceMeters',
  'routes.legs.steps.staticDuration',
]

function waypoint(w: GoogleWaypoint | MapCoordinate) {
  if ('latitude' in w) return { location: { latLng: w } }
  const out: Record<string, unknown> = {}
  if (w.location) out.location = { latLng: w.location }
  if (w.placeId) out.placeId = w.placeId
  if (w.address) out.address = w.address
  if (w.via) out.via = true
  return out
}

/** Google's web services with your key (see the module's notes on keys and billing). */
export function googleMapsServices(options: GoogleServicesOptions) {
  const doFetch = options.fetch ?? fetch

  function headers(fieldMask?: string): Record<string, string> {
    const h: Record<string, string> = {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': options.apiKey,
    }
    if (fieldMask) h['X-Goog-FieldMask'] = fieldMask
    if (Platform.OS === 'ios' && options.iosBundleId) {
      h['X-Ios-Bundle-Identifier'] = options.iosBundleId
    }
    if (Platform.OS === 'android' && options.androidPackage) {
      h['X-Android-Package'] = options.androidPackage
      if (options.androidCertSha1) h['X-Android-Cert'] = options.androidCertSha1
    }
    return h
  }

  async function request<T>(
    url: string,
    init: { method: 'GET' | 'POST'; body?: unknown; fieldMask?: string }
  ): Promise<T> {
    let response: Response
    try {
      response = await doFetch(url, {
        method: init.method,
        headers: headers(init.fieldMask),
        body: init.body === undefined ? undefined : JSON.stringify(init.body),
      })
    } catch (error) {
      throw new GoogleServiceError(String(error), 0, 'NETWORK_ERROR')
    }
    const text = await response.text()
    let json: any = null
    try {
      json = text ? JSON.parse(text) : null
    } catch {
      json = null
    }
    if (!response.ok) {
      const e = json?.error
      throw new GoogleServiceError(
        e?.message ?? `HTTP ${response.status}`,
        response.status,
        e?.status ?? 'HTTP_ERROR'
      )
    }
    // The Geocoding API reports errors in the body with HTTP 200.
    if (json && typeof json.status === 'string' && json.status !== 'OK' && json.status !== 'ZERO_RESULTS') {
      throw new GoogleServiceError(json.error_message ?? json.status, response.status, json.status)
    }
    return json as T
  }

  const language = (o: { languageCode?: string }) =>
    o.languageCode ?? options.languageCode
  const region = (o: { regionCode?: string }) => o.regionCode ?? options.regionCode

  const places = {
    /** Suggestions as the user types (Autocomplete (New)). Use one `sessionToken` per typing session. */
    autocomplete: (q: {
      input: string
      locationBias?: GoogleLocationBias
      locationRestriction?: GoogleLocationBias
      /** Where the user is, for distances. */
      origin?: MapCoordinate
      includedPrimaryTypes?: string[]
      includedRegionCodes?: string[]
      includeQueryPredictions?: boolean
      sessionToken?: string
      languageCode?: string
      regionCode?: string
    }) =>
      request<{ suggestions?: GoogleAutocompleteSuggestion[] }>(
        'https://places.googleapis.com/v1/places:autocomplete',
        {
          method: 'POST',
          body: { ...q, languageCode: language(q), regionCode: region(q) },
        }
      ).then((r) => ({ suggestions: r?.suggestions ?? [] })),

    /** A place by ID (Place Details (New)), with `fields` (default: the common ones). */
    details: (
      placeId: string,
      q: { fields?: string[]; sessionToken?: string; languageCode?: string; regionCode?: string } = {}
    ) => {
      const params = new URLSearchParams()
      const lang = language(q)
      const reg = region(q)
      if (lang) params.set('languageCode', lang)
      if (reg) params.set('regionCode', reg)
      if (q.sessionToken) params.set('sessionToken', q.sessionToken)
      const query = params.toString()
      return request<GooglePlace>(
        `https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}${query ? `?${query}` : ''}`,
        { method: 'GET', fieldMask: (q.fields ?? DEFAULT_PLACE_FIELDS).join(',') }
      )
    },

    /** Places matching text, such as "pizza in Chicago" (Text Search (New)). */
    searchText: (q: {
      textQuery: string
      locationBias?: GoogleLocationBias
      locationRestriction?: { rectangle: { low: MapCoordinate; high: MapCoordinate } }
      includedType?: string
      openNow?: boolean
      minRating?: number
      maxResultCount?: number
      rankPreference?: 'RELEVANCE' | 'DISTANCE'
      fields?: string[]
      languageCode?: string
      regionCode?: string
    }) => {
      const { fields, ...body } = q
      return request<{ places?: GooglePlace[] }>(
        'https://places.googleapis.com/v1/places:searchText',
        {
          method: 'POST',
          body: { ...body, languageCode: language(q), regionCode: region(q) },
          fieldMask: (fields ?? DEFAULT_PLACE_FIELDS).map((f) => `places.${f}`).join(','),
        }
      ).then((r) => r?.places ?? [])
    },

    /** Places of some types around a point (Nearby Search (New)). */
    searchNearby: (q: {
      center: MapCoordinate
      radius: number
      includedTypes?: string[]
      excludedTypes?: string[]
      maxResultCount?: number
      rankPreference?: 'POPULARITY' | 'DISTANCE'
      fields?: string[]
      languageCode?: string
      regionCode?: string
    }) => {
      const { center, radius, fields, ...rest } = q
      return request<{ places?: GooglePlace[] }>(
        'https://places.googleapis.com/v1/places:searchNearby',
        {
          method: 'POST',
          body: {
            ...rest,
            locationRestriction: { circle: { center, radius } },
            languageCode: language(q),
            regionCode: region(q),
          },
          fieldMask: (fields ?? DEFAULT_PLACE_FIELDS).map((f) => `places.${f}`).join(','),
        }
      ).then((r) => r?.places ?? [])
    },

    /** A short-lived URL for a place photo (`place.photos[i].name`). */
    photoUrl: (
      photoName: string,
      size: { maxWidthPx?: number; maxHeightPx?: number } = { maxWidthPx: 800 }
    ) => {
      const params = new URLSearchParams({ skipHttpRedirect: 'true' })
      if (size.maxWidthPx) params.set('maxWidthPx', String(size.maxWidthPx))
      if (size.maxHeightPx) params.set('maxHeightPx', String(size.maxHeightPx))
      return request<{ photoUri: string }>(
        `https://places.googleapis.com/v1/${photoName}/media?${params}`,
        { method: 'GET' }
      ).then((r) => r.photoUri)
    },

    /** A new session token for autocomplete + details billing. */
    newSessionToken: () =>
      'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
        const r = (Math.random() * 16) | 0
        return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16)
      }),
  }

  type GeocodeResult = {
    formatted_address: string
    place_id: string
    types: string[]
    geometry: { location: { lat: number; lng: number }; location_type: string }
    address_components: { long_name: string; short_name: string; types: string[] }[]
  }

  const toGeocode = (r: GeocodeResult) => ({
    formattedAddress: r.formatted_address,
    placeId: r.place_id,
    types: r.types,
    location: { latitude: r.geometry.location.lat, longitude: r.geometry.location.lng },
    locationType: r.geometry.location_type,
    components: r.address_components,
  })

  const geocoding = {
    /** An address to coordinates (Geocoding API). */
    geocode: (address: string, q: { bounds?: { low: MapCoordinate; high: MapCoordinate }; components?: string; languageCode?: string; regionCode?: string } = {}) => {
      const params = new URLSearchParams({ address, key: options.apiKey })
      const lang = language(q)
      const reg = region(q)
      if (lang) params.set('language', lang)
      if (reg) params.set('region', reg)
      if (q.components) params.set('components', q.components)
      if (q.bounds) {
        params.set('bounds', `${q.bounds.low.latitude},${q.bounds.low.longitude}|${q.bounds.high.latitude},${q.bounds.high.longitude}`)
      }
      return request<{ results: GeocodeResult[] }>(
        `https://maps.googleapis.com/maps/api/geocode/json?${params}`,
        { method: 'GET' }
      ).then((r) => (r?.results ?? []).map(toGeocode))
    },
    /** Coordinates to addresses (Geocoding API). */
    reverseGeocode: (coordinate: MapCoordinate, q: { resultType?: string[]; languageCode?: string } = {}) => {
      const params = new URLSearchParams({
        latlng: `${coordinate.latitude},${coordinate.longitude}`,
        key: options.apiKey,
      })
      const lang = language(q)
      if (lang) params.set('language', lang)
      if (q.resultType?.length) params.set('result_type', q.resultType.join('|'))
      return request<{ results: GeocodeResult[] }>(
        `https://maps.googleapis.com/maps/api/geocode/json?${params}`,
        { method: 'GET' }
      ).then((r) => (r?.results ?? []).map(toGeocode))
    },
  }

  const routes = {
    /** Routes between two points (Routes API `computeRoutes`), each with its line decoded. */
    computeRoutes: async (q: {
      origin: GoogleWaypoint | MapCoordinate
      destination: GoogleWaypoint | MapCoordinate
      intermediates?: (GoogleWaypoint | MapCoordinate)[]
      travelMode?: GoogleTravelMode
      routingPreference?: 'TRAFFIC_UNAWARE' | 'TRAFFIC_AWARE' | 'TRAFFIC_AWARE_OPTIMAL'
      computeAlternativeRoutes?: boolean
      routeModifiers?: { avoidTolls?: boolean; avoidHighways?: boolean; avoidFerries?: boolean; avoidIndoor?: boolean }
      departureTime?: string
      units?: 'METRIC' | 'IMPERIAL'
      fields?: string[]
      languageCode?: string
      regionCode?: string
    }) => {
      const { fields, origin, destination, intermediates, ...rest } = q
      const result = await request<{ routes?: ({ polyline?: { encodedPolyline: string } } & Record<string, unknown>)[] }>(
        'https://routes.googleapis.com/directions/v2:computeRoutes',
        {
          method: 'POST',
          body: {
            ...rest,
            origin: waypoint(origin),
            destination: waypoint(destination),
            intermediates: intermediates?.map(waypoint),
            languageCode: language(q),
            regionCode: region(q),
          },
          fieldMask: (fields ?? DEFAULT_ROUTE_FIELDS).join(','),
        }
      )
      return (result?.routes ?? []).map((route) => ({
        ...route,
        coordinates: route.polyline?.encodedPolyline
          ? decodePolyline(route.polyline.encodedPolyline)
          : [],
      })) as GoogleRoute[]
    },

    /** Distances and durations between every origin and destination (`computeRouteMatrix`). */
    computeRouteMatrix: (q: {
      origins: (GoogleWaypoint | MapCoordinate)[]
      destinations: (GoogleWaypoint | MapCoordinate)[]
      travelMode?: GoogleTravelMode
      routingPreference?: 'TRAFFIC_UNAWARE' | 'TRAFFIC_AWARE' | 'TRAFFIC_AWARE_OPTIMAL'
      fields?: string[]
    }) =>
      request<
        {
          originIndex: number
          destinationIndex: number
          distanceMeters?: number
          duration?: string
          condition?: string
          status?: unknown
        }[]
      >('https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix', {
        method: 'POST',
        body: {
          origins: q.origins.map((o) => ({ waypoint: waypoint(o) })),
          destinations: q.destinations.map((d) => ({ waypoint: waypoint(d) })),
          travelMode: q.travelMode,
          routingPreference: q.routingPreference,
        },
        fieldMask: (
          q.fields ?? ['originIndex', 'destinationIndex', 'distanceMeters', 'duration', 'condition', 'status']
        ).join(','),
      }).then((r) => r ?? []),
  }

  return { places, geocoding, routes }
}

export type GoogleMapsServices = ReturnType<typeof googleMapsServices>

/** Decodes Google's encoded polyline format (precision 5 by default). */
export function decodePolyline(encoded: string, precision = 5): MapCoordinate[] {
  const factor = 10 ** precision
  const out: MapCoordinate[] = []
  let index = 0
  let lat = 0
  let lng = 0
  while (index < encoded.length) {
    for (const which of [0, 1]) {
      let result = 0
      let shift = 0
      let byte: number
      do {
        byte = encoded.charCodeAt(index++) - 63
        result |= (byte & 0x1f) << shift
        shift += 5
      } while (byte >= 0x20 && index < encoded.length)
      const delta = result & 1 ? ~(result >> 1) : result >> 1
      if (which === 0) lat += delta
      else lng += delta
    }
    out.push({ latitude: lat / factor, longitude: lng / factor })
  }
  return out
}

/** Encodes coordinates in Google's polyline format. */
export function encodePolyline(coordinates: MapCoordinate[], precision = 5): string {
  const factor = 10 ** precision
  let out = ''
  let lastLat = 0
  let lastLng = 0
  const encode = (value: number) => {
    let v = value < 0 ? ~(value << 1) : value << 1
    let s = ''
    while (v >= 0x20) {
      s += String.fromCharCode((0x20 | (v & 0x1f)) + 63)
      v >>= 5
    }
    return s + String.fromCharCode(v + 63)
  }
  for (const c of coordinates) {
    const lat = Math.round(c.latitude * factor)
    const lng = Math.round(c.longitude * factor)
    out += encode(lat - lastLat) + encode(lng - lastLng)
    lastLat = lat
    lastLng = lng
  }
  return out
}
