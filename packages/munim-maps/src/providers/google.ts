/**
 * Options only the Google Maps engine reads (`provider="google"`), passed as
 * `google={{ … }}` on `MunimMapView`, plus Google's own events
 * (`onProviderEvent`, typed `GoogleMapEvent`) and methods (`googleMap(ref)`).
 *
 * Shared props keep their meaning on Google: `mapStyle` picks the map type,
 * `colorScheme` dark mode, `showsBuildings`, `showsTraffic`,
 * `pointsOfInterest` (as a JSON style), markers, shapes, tile overlays,
 * clustering, camera limits, padding, gestures and the 3D layer. Everything
 * Google has beyond that is here.
 */
import type { MapCoordinate } from '../specs/MapModelLayer.nitro'
import {
  providerCommand,
  type MapProviderEvent,
  type ProviderCommandTarget,
} from './index'

/** `#RRGGBB`, `#RRGGBBAA` or `#RGB`. */
export type GoogleColor = string

/** South-west and north-east corners. */
export interface GoogleLatLngBounds {
  southwest: MapCoordinate
  northeast: MapCoordinate
}

/** A marker's extras, by marker id in `google.markers`. */
export interface GoogleMarkerOptions {
  /** Lie flat on the map (turns and tilts with it). Default false. */
  flat?: boolean
  /** Degrees clockwise. Default 0. */
  rotation?: number
  /** Where the info window points to, in the icon (0…1). Default `{ x: 0.5, y: 0 }`. */
  infoWindowAnchor?: { x: number; y: number }
  /** Overrides the marker's anchor in its icon (0…1). */
  anchor?: { x: number; y: number }
  /**
   * On a map with a `mapId` markers are advanced markers (pins, collision
   * behaviour); false keeps this one a classic marker. Default true.
   */
  advanced?: boolean
  /** Advanced markers: how it gives way to others. Default from `displayPriority` / `collisionMode`. */
  collisionBehavior?:
    | 'required'
    | 'requiredAndHidesOptional'
    | 'optionalAndHidesLowerPriority'
  /** Google's pin (`style: 'pin' | 'marker'`): colours and glyph. */
  pin?: {
    background?: GoogleColor
    border?: GoogleColor
    /** Text in the pin (advanced markers). Default the marker's `glyph`. */
    glyph?: string
    glyphColor?: GoogleColor
    /** A picture in the pin instead of text. */
    glyphImageUri?: string
  }
  /** A custom info window (drawn by munim-maps) with these colours. */
  infoWindow?: {
    backgroundColor?: GoogleColor
    textColor?: GoogleColor
    maxWidth?: number
  }
  opacity?: number
  zIndex?: number
}

export type GooglePatternItem = {
  type: 'dash' | 'gap' | 'dot'
  /** Points (pixels on Android). Dots ignore it on Android. */
  length?: number
}

export type GoogleCap =
  | 'butt'
  | 'round'
  | 'square'
  | {
      /** A picture at the end of the line (Android). */
      imageUri: string
      /** Stroke width the picture is drawn for. Default 10. */
      refWidth?: number
    }

/** A polyline's extras, by polyline id in `google.polylines`. */
export interface GooglePolylineOptions {
  /**
   * Styled spans along the line, each over `segments` path segments: a
   * colour, a gradient (`color` → `toColor`) or a stamped picture.
   */
  spans?: {
    color?: GoogleColor
    toColor?: GoogleColor
    segments?: number
    stampImageUri?: string
  }[]
  /** Dashes, gaps and dots. iOS draws them as spans at the current zoom. */
  pattern?: GooglePatternItem[]
  /** A picture repeated along the line: `texture` (tinted by the stroke) or `sprite`. */
  stamp?: { imageUri: string; kind?: 'texture' | 'sprite' }
  /** Android: line ends. iOS draws round ends. */
  startCap?: GoogleCap
  endCap?: GoogleCap
  /** Android: corners (also from `lineJoin`). */
  jointType?: 'miter' | 'bevel' | 'round'
  /** Overrides `strokeWidth`. */
  width?: number
}

/** A polygon's extras, by polygon id in `google.polygons`. */
export interface GooglePolygonOptions {
  /** Edges follow the curve of the Earth. Default false. */
  geodesic?: boolean
  /** Android: dashed outline (also from `dashPattern`). */
  strokePattern?: GooglePatternItem[]
  /** Android: outline corners (also from `lineJoin`). */
  strokeJointType?: 'miter' | 'bevel' | 'round'
}

/** A circle's extras, by circle id in `google.circles`. */
export interface GoogleCircleOptions {
  /** Android: dashed outline (also from `dashPattern`). */
  strokePattern?: GooglePatternItem[]
}

/** A tile overlay's extras, by tile overlay id in `google.tileOverlays`. */
export interface GoogleTileOverlayOptions {
  /** Points per tile side (iOS; 512 for retina tiles). Default 256. */
  tileSize?: number
  /** Fade tiles in. Default true. */
  fadeIn?: boolean
  /** iOS: the User-Agent sent for tiles. */
  userAgent?: string
}

/** An image laid on the ground. */
export interface GoogleGroundOverlay {
  id: string
  /** `https://`, `file://` or a path; `require()`d images resolve in JavaScript first. */
  imageUri: string
  /** Where it lies: these corners, or `position` + `width` (metres). */
  bounds?: GoogleLatLngBounds
  position?: MapCoordinate
  width?: number
  /** Metres; default keeps the image's aspect. */
  height?: number
  /** Which point of the image sits on `position` (0…1). Default the centre. */
  anchor?: { x: number; y: number }
  /** Degrees clockwise. */
  bearing?: number
  opacity?: number
  zIndex?: number
  visible?: boolean
  /** Taps fire the `groundOverlayPress` event. */
  tappable?: boolean
}

export interface GoogleHeatmap {
  id: string
  points: { latitude: number; longitude: number; weight?: number }[]
  /** Blur radius in points, 10…50. Default 20. */
  radius?: number
  opacity?: number
  zIndex?: number
  gradient?: {
    colors: GoogleColor[]
    /** 0…1, increasing, one per colour. */
    startPoints?: number[]
    colorMapSize?: number
  }
  /** Android: the intensity drawn at full colour (default from the data). */
  maxIntensity?: number
  /** iOS: zoom levels the intensity is scaled between. */
  minimumZoomIntensity?: number
  maximumZoomIntensity?: number
}

export interface GoogleKmlLayer {
  id: string
  /** `https://` or `file://` KML (not KMZ on iOS), or `data`: the KML text. */
  url?: string
  data?: string
  zIndex?: number
}

export interface GoogleGeoJsonStyle {
  strokeColor?: GoogleColor
  strokeWidth?: number
  fillColor?: GoogleColor
  /** Marker colour for points. */
  pointColor?: GoogleColor
  zIndex?: number
  geodesic?: boolean
  /** Taps fire `geoJsonFeaturePress`. Default true. */
  tappable?: boolean
}

export interface GoogleGeoJsonLayer {
  id: string
  /** A GeoJSON object or text, or `url` to load. */
  geojson?: object | string
  url?: string
  /** Default style; features' simplestyle properties win. */
  style?: GoogleGeoJsonStyle
}

export interface GoogleFeatureStyle {
  fillColor?: GoogleColor
  strokeColor?: GoogleColor
  strokeWidth?: number
  /** Datasets: radius of point features. */
  pointRadius?: number
}

/**
 * Data-driven styling: Google's boundaries or your dataset, styled on the
 * map. Needs a `mapId` whose map style has the layer turned on.
 */
export interface GoogleFeatureLayer {
  featureType?:
    | 'COUNTRY'
    | 'ADMINISTRATIVE_AREA_LEVEL_1'
    | 'ADMINISTRATIVE_AREA_LEVEL_2'
    | 'LOCALITY'
    | 'POSTAL_CODE'
    | 'SCHOOL_DISTRICT'
  /** A dataset's id (instead of `featureType`). */
  datasetId?: string
  /** Every feature. */
  style?: GoogleFeatureStyle
  /** By place ID (boundaries). */
  placeStyles?: Record<string, GoogleFeatureStyle>
  /** Datasets: by an attribute's value. */
  attributeStyles?: {
    attribute: string
    values: Record<string, GoogleFeatureStyle>
  }
}

export interface GoogleMapOptions {
  /**
   * A cloud-based map style's Map ID (Google Cloud console): cloud styling,
   * advanced markers, data-driven styling. Applied when the map is made, so
   * changing it remakes the map. `'DEMO_MAP_ID'` works for trying things.
   */
  mapId?: string
  /** Google's base map; default follows `mapStyle` (`standard` → `normal`, `hybrid`, `imagery` → `satellite`). */
  mapType?: 'normal' | 'satellite' | 'hybrid' | 'terrain' | 'none'
  /**
   * A JSON map style (Google's styling wizard output): an array of rules or
   * its text. Not with `mapId`. `styleUrl` can load one from a URL.
   */
  styleJson?: string | object[]
  /** Public transport lines. Default false. */
  transitEnabled?: boolean
  /** Indoor floor plans. Default false. */
  indoorEnabled?: boolean
  /** The indoor level picker. Default on with `indoorEnabled`. */
  indoorLevelPicker?: boolean
  /** Android: a lightweight, non-interactive bitmap map. Applied when the map is made. Default false. */
  liteMode?: boolean
  /** Shown while tiles load. */
  backgroundColor?: GoogleColor
  /** iOS: how often the map redraws. */
  preferredFrameRate?: 'powerSave' | 'conservative' | 'maximum'
  /** iOS: hide the map's accessibility elements. */
  accessibilityElementsHidden?: boolean
  /** Android: the map's content description. */
  contentDescription?: string
  /** Show the compass (while rotated). Default from `compassVisibility`. */
  compass?: boolean
  /** The my-location button. Default `showsUserTrackingButton`. */
  myLocationButton?: boolean
  /** Android: + / − buttons. Default false. */
  zoomControls?: boolean
  /** Android: directions / open-in-Maps buttons on marker tap. Default false. */
  mapToolbar?: boolean
  /** Keep panning while pinching or rotating. Default true. */
  scrollGesturesDuringRotateOrZoom?: boolean
  /** iOS: the map takes all gestures in its view. Default true. */
  consumesGesturesInView?: boolean
  /** iOS: how `mapPadding` reacts to the safe area. */
  paddingAdjustmentBehavior?: 'always' | 'automatic' | 'never'
  /** Zoom limits in Google's levels (2…21); win over `cameraDistanceRange`. */
  minZoom?: number
  maxZoom?: number
  /** Keep the camera target in these bounds (instead of `cameraBoundary`). */
  cameraTargetBounds?: GoogleLatLngBounds
  /** Clustering: `nonHierarchicalDistanceBased` (default), `gridBased` or `simple` (iOS). */
  clusterAlgorithm?: 'nonHierarchicalDistanceBased' | 'gridBased' | 'simple'
  /** Fewest markers drawn as a cluster. Default 4 (Utils). */
  clusterMinimumSize?: number
  /** iOS: no clusters above this zoom. */
  clusterMaxZoom?: number
  /** Animate clusters splitting and merging. Default true. */
  animatesClusters?: boolean
  /** Extras by marker id. */
  markers?: Record<string, GoogleMarkerOptions>
  /** Extras by polyline id. */
  polylines?: Record<string, GooglePolylineOptions>
  /** Extras by polygon id. */
  polygons?: Record<string, GooglePolygonOptions>
  /** Extras by circle id. */
  circles?: Record<string, GoogleCircleOptions>
  /** Extras by tile overlay id. */
  tileOverlays?: Record<string, GoogleTileOverlayOptions>
  groundOverlays?: GoogleGroundOverlay[]
  heatmaps?: GoogleHeatmap[]
  kmlLayers?: GoogleKmlLayer[]
  geoJsonLayers?: GoogleGeoJsonLayer[]
  featureLayers?: GoogleFeatureLayer[]
}

// MARK: Events

export interface GoogleIndoorBuilding {
  levels: { name: string; shortName: string }[]
  defaultLevelIndex: number
  activeLevelIndex: number
  underground: boolean
}

export interface GoogleStreetViewLocation {
  panoramaId: string
  latitude: number
  longitude: number
  links: { heading: number; panoramaId: string }[]
}

export interface GoogleStreetViewCamera {
  heading: number
  pitch: number
  zoom: number
  /** iOS only. */
  fov?: number
}

/** Google's own events, from `onProviderEvent` when `provider` is `google`. */
export type GoogleMapEvent =
  | { name: 'mapLoaded'; data: {} }
  | {
      name: 'cameraMoveStarted'
      data: { reason: 'gesture' | 'apiAnimation' | 'developerAnimation' }
    }
  | { name: 'cameraMoveCanceled'; data: {} }
  | {
      name: 'poiClick'
      data: { placeId: string; name: string; latitude: number; longitude: number }
    }
  | { name: 'infoWindowPress' | 'infoWindowLongPress' | 'infoWindowClose'; data: { id: string } }
  | { name: 'markerDrag'; data: { id: string; latitude: number; longitude: number } }
  | {
      name: 'clusterPress'
      data: { clusteringId: string; markerIds: string[]; latitude: number; longitude: number }
    }
  | { name: 'myLocationButtonPress'; data: {} }
  | { name: 'myLocationPress'; data: { latitude: number; longitude: number } }
  | { name: 'tilesRenderingStarted' | 'tilesRenderingFinished' | 'snapshotReady'; data: {} }
  | {
      name: 'mapCapabilitiesChanged'
      data: { advancedMarkers: boolean; dataDrivenStyling: boolean; spritePolylines?: boolean }
    }
  | { name: 'indoorBuildingFocused'; data: GoogleIndoorBuilding | {} }
  | {
      name: 'indoorLevelActivated'
      data: { name: string; shortName: string; index: number; building: GoogleIndoorBuilding | {} }
    }
  | {
      name: 'featureClick'
      data: {
        featureType: string
        latitude: number
        longitude: number
        features: {
          featureType: string
          placeId?: string
          datasetId?: string
          attributes?: Record<string, string>
        }[]
      }
    }
  | { name: 'groundOverlayPress'; data: { id: string } }
  | { name: 'kmlLayerLoaded'; data: { id: string; placemarks: number } }
  | { name: 'kmlFeaturePress'; data: { layerId: string; title: string; snippet: string } }
  | { name: 'geoJsonLayerLoaded'; data: { id: string; features: number } }
  | {
      name: 'geoJsonFeaturePress'
      data: { layerId: string; featureId: string; properties: Record<string, unknown> }
    }
  | { name: 'streetViewOpen' | 'streetViewChange'; data: GoogleStreetViewLocation }
  | { name: 'streetViewCamera'; data: GoogleStreetViewCamera }
  | { name: 'streetViewTap'; data: { x: number; y: number; heading: number; pitch: number } }
  | { name: 'streetViewMarkerPress'; data: { id: string } }
  | { name: 'streetViewError'; data: { message: string; latitude?: number; longitude?: number; panoramaId?: string } }
  | { name: 'streetViewClose'; data: {} }

/** Narrows an `onProviderEvent` event to Google's, or undefined. */
export function googleEvent(event: MapProviderEvent): GoogleMapEvent | undefined {
  return event.provider === 'google'
    ? ({ name: event.name, data: event.data ?? {} } as GoogleMapEvent)
    : undefined
}

// MARK: Methods

/** Google's camera, in Google's units. */
export interface GoogleCameraPosition {
  latitude: number
  longitude: number
  zoom: number
  /** Degrees clockwise from north. */
  bearing: number
  /** Degrees from straight down. */
  tilt: number
}

export interface GoogleProjection {
  nearLeft: MapCoordinate
  nearRight: MapCoordinate
  farLeft: MapCoordinate
  farRight: MapCoordinate
  bounds: GoogleLatLngBounds
  camera: GoogleCameraPosition
  pointsPerMeter: number
}

export interface GoogleStreetViewOptions {
  /** Find the panorama nearest this point… */
  latitude?: number
  longitude?: number
  /** …within this many metres. Default 50. */
  radius?: number
  /** `outdoor` skips indoor panoramas. */
  source?: 'default' | 'outdoor'
  /** …or open this panorama. */
  panoramaId?: string
  heading?: number
  pitch?: number
  zoom?: number
  /** iOS: field of view in degrees. */
  fov?: number
  /** `overlay` covers the map (default); `fullScreen` presents it (iOS) or covers the screen. */
  presentation?: 'overlay' | 'fullScreen'
  /** A close button (default true). */
  closeButton?: boolean
  /** Turn all gestures on / off, or each one. */
  gestures?: boolean | { orientation?: boolean; zoom?: boolean; navigation?: boolean }
  navigationLinksHidden?: boolean
  streetNamesHidden?: boolean
  /** iOS: show the map's markers in the panorama. */
  showMarkers?: boolean
}

/**
 * Google's own methods on a `MunimMapView` ref (`provider="google"`):
 *
 * ```ts
 * const google = googleMap(ref.current!)
 * await google.animateCamera({ zoom: 18, tilt: 60 }, 800)
 * await google.streetView.open({ latitude, longitude })
 * ```
 */
export function googleMap(map: ProviderCommandTarget) {
  const call = <T = null>(command: string, args: object = {}) =>
    providerCommand<T>(map, command, args)
  return {
    /** Google's camera in its own units. */
    getCameraPosition: () => call<GoogleCameraPosition>('getCameraPosition'),
    /** Jumps; fields left out keep their value. */
    moveCamera: (camera: Partial<GoogleCameraPosition>) => call('moveCamera', camera),
    /** Google's own animation, over `durationMs` (its default length when 0). */
    animateCamera: (camera: Partial<GoogleCameraPosition>, durationMs = 0) =>
      call('animateCamera', { ...camera, duration: durationMs }),
    zoomIn: (durationMs = 0) => call('zoomIn', { duration: durationMs }),
    zoomOut: (durationMs = 0) => call('zoomOut', { duration: durationMs }),
    zoomTo: (zoom: number, durationMs = 0) => call('zoomTo', { zoom, duration: durationMs }),
    /** Around the screen point `focus` when given. */
    zoomBy: (amount: number, focus?: { x: number; y: number }, durationMs = 0) =>
      call('zoomBy', { amount, ...focus, duration: durationMs }),
    /** Pans by points. */
    scrollBy: (x: number, y: number, durationMs = 0) =>
      call('scrollBy', { x, y, duration: durationMs }),
    fitBounds: (
      bounds: GoogleLatLngBounds,
      padding: number | { top?: number; left?: number; bottom?: number; right?: number } = 0,
      durationMs = 0
    ) => call('fitBounds', { ...bounds, padding, duration: durationMs }),
    stopAnimation: () => call('stopAnimation'),
    /** The visible area's four corners, bounds and scale. */
    getProjection: () => call<GoogleProjection>('getProjection'),
    /** How many points `meters` covers at a coordinate (default the target). */
    pointsForMeters: (meters: number, at?: MapCoordinate) =>
      call<number>('pointsForMeters', { meters, ...at }),
    containsCoordinate: (coordinate: MapCoordinate) =>
      call<boolean>('containsCoordinate', coordinate),
    getMapCapabilities: () =>
      call<{ advancedMarkers: boolean; dataDrivenStyling: boolean; spritePolylines?: boolean }>(
        'getMapCapabilities'
      ),
    getMyLocation: () =>
      call<{
        latitude: number
        longitude: number
        altitude: number
        accuracy: number
        heading: number
        speed: number
      } | null>('getMyLocation'),
    getIndoorBuilding: () => call<GoogleIndoorBuilding | {}>('getIndoorBuilding'),
    /** By index in the focused building's levels, or by `name` / `shortName`. */
    setIndoorLevel: (level: number | { name?: string; shortName?: string }) =>
      call('setIndoorLevel', typeof level === 'number' ? { index: level } : level),
    showInfoWindow: (id: string) => call('showInfoWindow', { id }),
    hideInfoWindow: (id: string) => call('hideInfoWindow', { id }),
    /** Reloads a tile overlay's or heatmap's tiles (all when no id). */
    clearTileCache: (id?: string) => call('clearTileCache', id ? { id } : {}),
    /** The SDK's version (and its open-source licences when asked). */
    sdkInfo: (licenses = false) =>
      call<{ platform: string; version: string; longVersion?: string; openSourceLicenseInfo: string }>(
        'sdkInfo',
        { licenses }
      ),
    /** How munim-maps reads Google's camera for the 3D layer. */
    cameraDiagnostics: () => call<Record<string, unknown>>('cameraDiagnostics'),
    streetView: {
      /** Finds and shows a panorama; resolves with where it is. */
      open: (options: GoogleStreetViewOptions) =>
        call<GoogleStreetViewLocation>('streetView.open', options),
      close: () => call('streetView.close'),
      /** The panorama nearest a point, or null when Google has none. */
      hasCoverage: (
        coordinate: MapCoordinate,
        options: { radius?: number; source?: 'default' | 'outdoor' } = {}
      ) => call<GoogleStreetViewLocation | null>('streetView.hasCoverage', { ...coordinate, ...options }),
      setCamera: (camera: Partial<GoogleStreetViewCamera>, durationMs = 0) =>
        call('streetView.setCamera', { ...camera, duration: durationMs }),
      getCamera: () => call<GoogleStreetViewCamera>('streetView.getCamera'),
      getLocation: () => call<GoogleStreetViewLocation>('streetView.getLocation'),
      moveTo: (
        target:
          | { panoramaId: string }
          | (MapCoordinate & { radius?: number; source?: 'default' | 'outdoor' })
      ) => call('streetView.moveTo', target),
      setOptions: (options: Pick<
        GoogleStreetViewOptions,
        'gestures' | 'navigationLinksHidden' | 'streetNamesHidden'
      >) => call('streetView.setOptions', options),
      orientationForPoint: (point: { x: number; y: number }) =>
        call<{ heading: number; pitch: number }>('streetView.orientationForPoint', point),
      pointForOrientation: (orientation: { heading: number; pitch: number }) =>
        call<{ x: number; y: number }>('streetView.pointForOrientation', orientation),
    },
  }
}

export type GoogleMapMethods = ReturnType<typeof googleMap>
