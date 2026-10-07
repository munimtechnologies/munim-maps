package com.margelo.nitro.munimmaps

import com.margelo.nitro.NitroModules
import com.margelo.nitro.core.Promise
import com.munimmaps.models.MunimTerrain

/** React Native `groundElevation()` on Android: the 3D layer's [MunimTerrain] sampler. */
class HybridMunimTerrain : HybridMunimTerrainSpec() {
  override fun groundElevation(coordinates: Array<MapCoordinate>): Promise<DoubleArray> {
    NitroModules.applicationContext?.let { MunimTerrain.init(it) }
    val promise = Promise<DoubleArray>()
    MunimTerrain.groundElevations(coordinates.map { it.latitude to it.longitude }) { result ->
      result.fold({ promise.resolve(it) }, { promise.reject(it) })
    }
    return promise
  }
}
