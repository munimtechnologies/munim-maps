import CoreLocation
import NitroModules

/// React Native `groundElevation()`: the core `MunimTerrain` sampler.
final class HybridMunimTerrain: HybridMunimTerrainSpec {
  func groundElevation(coordinates: [MapCoordinate]) throws -> Promise<[Double]> {
    let promise = Promise<[Double]>()
    MunimTerrain.shared.groundElevations(for: coordinates.map(CLLocationCoordinate2D.init)) { result in
      switch result {
      case .success(let heights): promise.resolve(withResult: heights)
      case .failure(let error): promise.reject(withError: error)
      }
    }
    return promise
  }
}
