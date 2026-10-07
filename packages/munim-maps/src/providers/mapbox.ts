/**
 * Options only the Mapbox engine reads (`provider="mapbox"`), passed as
 * `mapbox={{ … }}` on `MunimMapView`. Owned by the Mapbox engine: add
 * options here and read them natively from the `providerOptions` JSON.
 * The style itself is `styleUrl` (default Mapbox Standard).
 */
export interface MapboxMapOptions {
  /** `globe` (default, like Mapbox's own apps) or flat `mercator`. */
  projection?: 'globe' | 'mercator'
  /** Mapbox Standard's light preset. Default follows `colorScheme`. */
  lightPreset?: 'dawn' | 'day' | 'dusk' | 'night'
  /** 3D terrain from Mapbox Terrain-DEM, with this exaggeration (0 for none). */
  terrainExaggeration?: number
}
