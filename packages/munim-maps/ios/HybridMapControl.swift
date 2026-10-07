import NitroModules
import UIKit

/// React Native `MapCompass`, `MapScale` and `MapUserTrackingButton`: a
/// MapKit control driving the `MunimMapView` with the same `mapScope`.
final class HybridMapControl: HybridMapControlSpec {
  private let control = MunimMapControlView(frame: .zero)
  var view: UIView { control }

  var kind: MapControlKind = .compass {
    didSet { control.kind = MunimMapControlView.Kind(rawValue: kind.stringValue) ?? .compass }
  }
  var mapScope = "" { didSet { control.mapScope = mapScope } }
  var visibility: FeatureVisibility = .adaptive { didSet { control.visibility = visibility.core } }
  var scaleAlignment: MapScaleAlignment = .leading { didSet { control.scaleAlignment = scaleAlignment.stringValue } }
}
