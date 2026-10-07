import type { VehicleName } from './vehicles'

export type { VehicleName }

/**
 * Bundled glTF binary (.glb) asset ids on every platform, to pass as a
 * model's `source`, for engines that need glTF on iOS too (such as Mapbox's
 * native model layer). Same models and names as `VEHICLES`.
 */
export const VEHICLES_GLB: Record<VehicleName, number>
export const VEHICLE_GLB_NAMES: VehicleName[]
