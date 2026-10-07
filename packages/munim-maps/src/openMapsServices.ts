import type { MapCoordinate } from './specs/MapModelLayer.nitro'
import { decodePolyline } from './providers/googleServices'

/**
 * OpenStreetMap services for any engine (the MapLibre engine's
 * `addressForCoordinate` uses the same Nominatim endpoint natively):
 * Nominatim geocoding, Photon search-as-you-type, OSRM or Valhalla routing.
 *
 * The defaults are the projects' public demo servers, which are for light
 * use only: Nominatim allows at most one request a second with an
 * identifying User-Agent and no bulk geocoding
 * (https://operations.osmfoundation.org/policies/nominatim/); the OSRM and
 * Valhalla demo servers are for testing. Point the endpoints at your own
 * servers or a hosted provider (`configureOpenMapsServices`) before
 * shipping. munim-maps spaces Nominatim requests a second apart.
 */
export interface OpenMapsEndpoints {
  /** Default `https://nominatim.openstreetmap.org`. */
  nominatim?: string
  /** Default `https://photon.komoot.io`. */
  photon?: string
  /** Default `https://router.project-osrm.org`. */
  osrm?: string
  /** Default `https://valhalla1.openstreetmap.de`. */
  valhalla?: string
  /** Sent as User-Agent / `Referer` where the platform allows it. */
  userAgent?: string
  /** Nominatim asks bulk users to add a contact address. */
  email?: string
}

export interface OpenMapsPlace {
  name: string
  /** One-line address. */
  formatted: string
  latitude: number
  longitude: number
  street: string
  houseNumber: string
  city: string
  region: string
  postalCode: string
  country: string
  countryCode: string
  /** OpenStreetMap category and type, such as `amenity` / `cafe`. */
  category: string
  type: string
  /** `node/123`, `way/456`… */
  osmId: string
  /** [south, west, north, east] when known. */
  bounds?: [number, number, number, number]
}

export type OpenMapsProfile = 'driving' | 'walking' | 'cycling'

export interface OpenMapsRouteStep {
  instruction: string
  distance: number
  duration: number
  name: string
  latitude: number
  longitude: number
}

export interface OpenMapsRoute {
  /** Metres. */
  distance: number
  /** Seconds. */
  duration: number
  coordinates: MapCoordinate[]
  steps: OpenMapsRouteStep[]
}

let endpoints: Required<Omit<OpenMapsEndpoints, 'email'>> & { email: string } =
  {
    nominatim: 'https://nominatim.openstreetmap.org',
    photon: 'https://photon.komoot.io',
    osrm: 'https://router.project-osrm.org',
    valhalla: 'https://valhalla1.openstreetmap.de',
    userAgent: 'munim-maps (https://github.com/munimtechnologies/munim-maps)',
    email: '',
  }

/** Sets the service endpoints for the whole app. */
export function configureOpenMapsServices(next: OpenMapsEndpoints) {
  endpoints = {
    ...endpoints,
    ...Object.fromEntries(
      Object.entries(next).filter(([, v]) => typeof v === 'string' && v)
    ),
  }
}

let lastNominatim = 0

async function nominatimSlot() {
  const wait = lastNominatim + 1000 - Date.now()
  lastNominatim = Date.now() + Math.max(0, wait)
  if (wait > 0) await new Promise<void>((resolve) => setTimeout(resolve, wait))
}

async function getJson(url: string): Promise<any> {
  const response = await fetch(url, {
    headers: {
      'Accept': 'application/json',
      'User-Agent': endpoints.userAgent,
    },
  })
  if (!response.ok) {
    throw new Error(`${response.status} ${response.statusText} from ${url}`)
  }
  return response.json()
}

function query(params: Record<string, string | number | undefined>) {
  return Object.entries(params)
    .filter(([, v]) => v !== undefined && v !== '')
    .map(([k, v]) => `${k}=${encodeURIComponent(String(v))}`)
    .join('&')
}

function fromNominatim(item: any): OpenMapsPlace {
  const a = item.address ?? {}
  const box = item.boundingbox?.map(Number)
  return {
    name: item.name || a.amenity || a.shop || a.road || item.display_name || '',
    formatted: item.display_name ?? '',
    latitude: Number(item.lat),
    longitude: Number(item.lon),
    street: a.road ?? a.pedestrian ?? a.footway ?? '',
    houseNumber: a.house_number ?? '',
    city: a.city ?? a.town ?? a.village ?? a.hamlet ?? '',
    region: a.state ?? a.region ?? '',
    postalCode: a.postcode ?? '',
    country: a.country ?? '',
    countryCode: (a.country_code ?? '').toUpperCase(),
    category: item.category ?? item.class ?? '',
    type: item.type ?? '',
    osmId:
      item.osm_type && item.osm_id ? `${item.osm_type}/${item.osm_id}` : '',
    bounds: box?.length === 4 ? [box[0], box[2], box[1], box[3]] : undefined,
  }
}

function fromPhoton(feature: any): OpenMapsPlace {
  const p = feature.properties ?? {}
  const [longitude, latitude] = feature.geometry?.coordinates ?? [0, 0]
  const parts = [
    p.name,
    [p.street, p.housenumber].filter(Boolean).join(' '),
    p.city,
    p.state,
    p.country,
  ].filter(Boolean)
  const extent = p.extent as number[] | undefined
  return {
    name: p.name ?? p.street ?? '',
    formatted: parts.join(', '),
    latitude,
    longitude,
    street: p.street ?? '',
    houseNumber: p.housenumber ?? '',
    city: p.city ?? p.town ?? p.village ?? '',
    region: p.state ?? '',
    postalCode: p.postcode ?? '',
    country: p.country ?? '',
    countryCode: (p.countrycode ?? '').toUpperCase(),
    category: p.osm_key ?? '',
    type: p.osm_value ?? '',
    osmId:
      p.osm_type && p.osm_id
        ? `${{ N: 'node', W: 'way', R: 'relation' }[p.osm_type as 'N'] ?? p.osm_type}/${p.osm_id}`
        : '',
    bounds:
      extent?.length === 4
        ? [extent[3]!, extent[0]!, extent[1]!, extent[2]!]
        : undefined,
  }
}

export const openMapsServices = {
  /** The address at a coordinate (Nominatim `reverse`). */
  async reverseGeocode(
    coordinate: MapCoordinate,
    options: { language?: string; zoom?: number } = {}
  ): Promise<OpenMapsPlace> {
    await nominatimSlot()
    const json = await getJson(
      `${endpoints.nominatim}/reverse?${query({
        'format': 'jsonv2',
        'addressdetails': 1,
        'lat': coordinate.latitude,
        'lon': coordinate.longitude,
        'zoom': options.zoom,
        'accept-language': options.language,
        'email': endpoints.email,
      })}`
    )
    if (json.error) throw new Error(String(json.error))
    return fromNominatim(json)
  },

  /** Places matching a query (Nominatim `search`). */
  async geocode(
    text: string,
    options: {
      limit?: number
      language?: string
      /** ISO 3166-1 alpha-2 codes. */
      countryCodes?: string[]
      /** Prefer results in [west, south, east, north]. */
      viewbox?: [number, number, number, number]
      bounded?: boolean
    } = {}
  ): Promise<OpenMapsPlace[]> {
    await nominatimSlot()
    const json = await getJson(
      `${endpoints.nominatim}/search?${query({
        'format': 'jsonv2',
        'addressdetails': 1,
        'q': text,
        'limit': options.limit ?? 10,
        'accept-language': options.language,
        'countrycodes': options.countryCodes?.join(','),
        'viewbox': options.viewbox?.join(','),
        'bounded': options.bounded ? 1 : undefined,
        'email': endpoints.email,
      })}`
    )
    return (json as any[]).map(fromNominatim)
  },

  /** Search as you type (Photon), biased towards `near`. */
  async search(
    text: string,
    options: { limit?: number; language?: string; near?: MapCoordinate } = {}
  ): Promise<OpenMapsPlace[]> {
    const json = await getJson(
      `${endpoints.photon}/api/?${query({
        q: text,
        limit: options.limit ?? 10,
        lang: options.language,
        lat: options.near?.latitude,
        lon: options.near?.longitude,
      })}`
    )
    return ((json.features ?? []) as any[]).map(fromPhoton)
  },

  /** Routes through the waypoints (OSRM by default, or Valhalla). */
  async route(
    waypoints: MapCoordinate[],
    options: {
      profile?: OpenMapsProfile
      engine?: 'osrm' | 'valhalla'
      alternatives?: boolean
      language?: string
    } = {}
  ): Promise<OpenMapsRoute[]> {
    if (waypoints.length < 2)
      throw new Error('A route needs two or more waypoints')
    const profile = options.profile ?? 'driving'
    if ((options.engine ?? 'osrm') === 'osrm') {
      const path = waypoints
        .map((w) => `${w.longitude},${w.latitude}`)
        .join(';')
      const osrmProfile = {
        driving: 'driving',
        walking: 'foot',
        cycling: 'bike',
      }[profile]
      const json = await getJson(
        `${endpoints.osrm}/route/v1/${osrmProfile}/${path}?${query({
          overview: 'full',
          geometries: 'geojson',
          steps: 'true',
          alternatives: options.alternatives ? 'true' : 'false',
        })}`
      )
      if (json.code !== 'Ok') throw new Error(json.message ?? json.code)
      return (json.routes as any[]).map((route) => ({
        distance: route.distance,
        duration: route.duration,
        coordinates: (route.geometry.coordinates as [number, number][]).map(
          ([longitude, latitude]) => ({ latitude, longitude })
        ),
        steps: (route.legs as any[]).flatMap((leg) =>
          (leg.steps as any[]).map((step) => ({
            instruction: [
              step.maneuver?.type,
              step.maneuver?.modifier,
              step.name,
            ]
              .filter(Boolean)
              .join(' '),
            distance: step.distance,
            duration: step.duration,
            name: step.name ?? '',
            latitude: step.maneuver?.location?.[1] ?? 0,
            longitude: step.maneuver?.location?.[0] ?? 0,
          }))
        ),
      }))
    }
    const costing = {
      driving: 'auto',
      walking: 'pedestrian',
      cycling: 'bicycle',
    }[profile]
    const request = {
      locations: waypoints.map((w) => ({ lat: w.latitude, lon: w.longitude })),
      costing,
      alternates: options.alternatives ? 2 : 0,
      language: options.language,
      units: 'kilometers',
    }
    const json = await getJson(
      `${endpoints.valhalla}/route?json=${encodeURIComponent(JSON.stringify(request))}`
    )
    const trips = [
      json.trip,
      ...((json.alternates ?? []) as any[]).map((a) => a.trip),
    ].filter(Boolean)
    return trips.map((trip: any) => {
      const coordinates = (trip.legs as any[]).flatMap((leg) =>
        decodePolyline(leg.shape, 6)
      )
      return {
        distance: trip.summary.length * 1000,
        duration: trip.summary.time,
        coordinates,
        steps: (trip.legs as any[]).flatMap((leg) =>
          (leg.maneuvers as any[]).map((m) => {
            const at = coordinates[m.begin_shape_index] ?? {
              latitude: 0,
              longitude: 0,
            }
            return {
              instruction: m.instruction ?? '',
              distance: (m.length ?? 0) * 1000,
              duration: m.time ?? 0,
              name: (m.street_names ?? [])[0] ?? '',
              latitude: at.latitude,
              longitude: at.longitude,
            }
          })
        ),
      }
    })
  },
}
