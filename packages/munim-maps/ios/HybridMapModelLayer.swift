import MapKit
import NitroModules
import UIKit

/// React Native `MapModelLayer`: a `MunimModelLayer` that finds the map on
/// screen (react-native-maps puts its `testID` in `accessibilityIdentifier`).
final class HybridMapModelLayer: HybridMapModelLayerSpec {
  private let layer = MunimModelLayer()
  var view: UIView { layer.view }

  override init() {
    super.init()
    layer.autoAttach = true
    layer.onModelPress = { [weak self] id in self?.onModelPress?(id) }
    layer.onAttachChange = { [weak self] attached in self?.onAttachChange?(attached) }
    layer.onError = { [weak self] message in self?.onError?(message) }
  }

  var models: [NativeMapModel] = [] {
    didSet { layer.models = models.map(\.core) }
  }

  var zones: [NativeMapZone] = [] {
    didSet { layer.zones = zones.map(\.core) }
  }

  var paths: [NativeMapPath] = [] {
    didSet { layer.paths = paths.map(\.core) }
  }

  var occlusion: MapOcclusion = .none {
    didSet { layer.buildingOcclusion = occlusion == .buildings }
  }

  var buildingTilesUrl: String = "" {
    didSet { layer.buildingTilesURL = buildingTilesUrl }
  }

  var followTerrain: Bool = false {
    didSet { layer.followsTerrain = followTerrain }
  }

  var mapTestID: String = "" {
    didSet { layer.mapIdentifier = mapTestID }
  }

  var lighting: MapModelLighting = .auto {
    didSet { layer.lighting = lighting.core }
  }

  var maxCameraDistance: Double = 50_000 {
    didSet { layer.maxCameraDistance = maxCameraDistance }
  }

  var realisticElevation: Bool = false {
    didSet { layer.realisticElevation = realisticElevation }
  }

  var globe: Bool = false {
    didSet { layer.globe = globe }
  }

  var onModelPress: ((_ id: String) -> Void)?
  var onAttachChange: ((_ attached: Bool) -> Void)?
  var onError: ((_ message: String) -> Void)?

  func isAttached() throws -> Bool {
    onMain { self.layer.isAttached }
  }

  func measureAlignment() throws -> Promise<MapAlignmentReport> {
    mainPromise { self.layer.measureAlignment().nitro }
  }
}
