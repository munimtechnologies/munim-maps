/**
 * Options only the MapLibre engine reads (`provider="maplibre"`), passed as
 * `maplibre={{ … }}` on `MunimMapView`. Owned by the MapLibre engine: add
 * options here and read them natively from the `providerOptions` JSON.
 * The style itself is `styleUrl` (default OpenFreeMap Liberty: OpenStreetMap
 * data, no key).
 */
export interface MapLibreMapOptions {
  /** `mercator` (default) or `globe` when zoomed out (MapLibre Native 11+). */
  projection?: 'mercator' | 'globe'
  /** Pixel ratio for raster tiles; default the screen's. */
  pixelRatio?: number
}
