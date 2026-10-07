/**
 * Options only the Cesium engine reads (`provider="cesium"`), passed as
 * `cesium={{ … }}` on `MunimMapView`. Owned by the Cesium engine: add
 * options here and read them natively from the `providerOptions` JSON.
 * Cesium ion assets need `configureMunimMaps({ cesiumIonToken })`.
 */
export interface CesiumMapOptions {
  /** `world` (Cesium World Terrain, ion) or a smooth `ellipsoid`. Default `world` with a token. */
  terrain?: 'world' | 'ellipsoid'
  /** Imagery under everything. Default Bing aerial (ion), or OpenStreetMap without a token. */
  imagery?: 'aerial' | 'aerialWithLabels' | 'road' | 'openStreetMap'
  /** 3D Tiles to stream: ion asset ids or tileset.json URLs. */
  tilesets?: { ionAssetId?: number; url?: string }[]
  /** Google Photorealistic 3D Tiles through ion (asset 2275207). Default false. */
  photorealistic?: boolean
}
