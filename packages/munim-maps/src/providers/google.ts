/**
 * Options only the Google Maps engine reads (`provider="google"`), passed as
 * `google={{ … }}` on `MunimMapView`. Owned by the Google engine: add
 * options here and read them natively from the `providerOptions` JSON.
 */
export interface GoogleMapOptions {
  /**
   * A cloud-based map style's Map ID (Google Cloud console). Needed for
   * advanced markers and vector features. Applied when the map is created.
   */
  mapId?: string
  /**
   * Google's base map. Default follows `mapStyle` (`standard` → `normal`,
   * `hybrid` → `hybrid`, `imagery` → `satellite`).
   */
  mapType?: 'normal' | 'satellite' | 'hybrid' | 'terrain' | 'none'
  /** Indoor floor plans. Default false. */
  indoorEnabled?: boolean
  /** Android: the lightweight bitmap map (no gestures). Default false. */
  liteMode?: boolean
}
