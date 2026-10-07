import MapKit
import UIKit

/// MapKit is the reference `MunimMapEngine`: `MunimMapKitView` implements
/// every requirement itself (it does not adopt `MunimMapEngineDefaults`, so
/// the compiler checks that nothing falls back to a default).
extension MunimMapKitView: MunimMapEngine {
  public var provider: MunimMapProvider { .mapkit }
  public var view: UIView { self }
  /// MapKit has no style URLs.
  public var styleURL: String {
    get { "" }
    set {}
  }
  /// MapKit's options are `MunimMapKitView`'s own properties.
  public var providerOptions: [String: Any] {
    get { [:] }
    set {}
  }
}

enum MapKitMapEngineFactory: MunimMapEngineFactory {
  static let isImplemented = true
  static func make() -> MunimMapEngine { MunimMapKitView(frame: .zero) }
}
