import type { VehicleName } from './names'

export { VEHICLE_NAMES, type VehicleName } from './names'

/**
 * A vehicle on a server: munim-maps picks `usdz` where SceneKit draws the
 * model on iOS and `glb` elsewhere (Android, Mapbox's and Cesium's own
 * models). `uri` is the GLB, for anything that reads a plain `{ uri }`.
 * Pass it as a model's `source`.
 */
export interface VehicleSource {
  readonly uri: string
  readonly glb: string
  readonly usdz: string
}

/**
 * Every vehicle as a remote source on jsDelivr, pinned to this package's
 * version. munim-maps downloads a model the first time it is shown and keeps
 * it on disk. For models inside the app, import
 * `munim-maps-vehicles/bundled/<name>` instead.
 */
export declare const VEHICLES: Readonly<Record<VehicleName, VehicleSource>>

/** The version the URLs point at. */
export declare const MUNIM_MAPS_VEHICLES_VERSION: string

/** `VEHICLES[name]`; throws for an unknown name. */
export declare function vehicleSource(name: VehicleName): VehicleSource

export interface MunimMapsVehiclesOptions {
  /**
   * A folder holding this package's `usdz/` and `glb/` folders (your own
   * server or CDN). Leave out for jsDelivr.
   */
  baseUrl?: string
}

/** Where the models load from. Call it before rendering maps. */
export declare function configureMunimMapsVehicles(
  options?: MunimMapsVehiclesOptions
): void
