import type { HybridObject } from 'react-native-nitro-modules'
import type { MapCoordinate } from './MapModelLayer.nitro'

/**
 * Ground height above sea level, from the free public Terrarium elevation
 * tiles on AWS (zoom 14, bilinear), cached in memory and on disk.
 */
export interface MunimTerrain extends HybridObject<{ ios: 'swift'; android: 'kotlin' }> {
  /**
   * Metres above sea level, one per coordinate. Negative under the sea (the
   * sea floor) and in places below sea level. Rejects if a tile cannot be
   * loaded.
   */
  groundElevation(coordinates: MapCoordinate[]): Promise<number[]>
}
