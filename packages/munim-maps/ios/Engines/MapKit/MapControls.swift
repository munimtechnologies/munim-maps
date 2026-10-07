import CoreLocation
import MapKit
import UIKit

extension MunimFeatureVisibility {
  var mapKit: MKFeatureVisibility {
    switch self {
    case .adaptive: return .adaptive
    case .visible: return .visible
    case .hidden: return .hidden
    }
  }
}

/// Maps by `mapScope`, so standalone controls placed elsewhere in a layout
/// (`MunimMapControlView`) can find the map they drive.
@_expose(!Cxx)
public enum MunimMapScopes {
  /// Posted on the main thread when a map registers or leaves a scope.
  public static let didChange = Notification.Name("MunimMapScopesDidChange")

  private static let maps = NSMapTable<NSString, MunimMapKitView>.strongToWeakObjects()

  /// The map currently using `scope`, if any.
  public static func map(for scope: String) -> MunimMapKitView? {
    scope.isEmpty ? nil : maps.object(forKey: scope as NSString)
  }

  static func register(_ map: MunimMapKitView, scope: String, previous: String) {
    if !previous.isEmpty, maps.object(forKey: previous as NSString) === map {
      maps.removeObject(forKey: previous as NSString)
    }
    if !scope.isEmpty { maps.setObject(map, forKey: scope as NSString) }
    NotificationCenter.default.post(name: didChange, object: nil)
  }
}

/// A MapKit control that drives a `MunimMapKitView` from anywhere in the
/// view hierarchy, like SwiftUI's `MapCompass(scope:)`: the compass, the
/// scale legend or the user tracking button.
@_expose(!Cxx)
public final class MunimMapControlView: UIView {
  @_expose(!Cxx)
  public enum Kind: String, Sendable { case compass, scale, userTrackingButton }

  public var kind: Kind = .compass { didSet { if oldValue != kind { rebuild() } } }
  /// The `mapScope` of the map to drive.
  public var mapScope = "" { didSet { if oldValue != mapScope { connect() } } }
  /// For the compass and the scale.
  public var visibility: MunimFeatureVisibility = .adaptive { didSet { applyStyle() } }
  /// Where the scale's legend sits: `"leading"`, `"trailing"` or `"center"` (iOS 26).
  public var scaleAlignment = "leading" { didSet { applyStyle() } }

  private var control: UIView?

  public override init(frame: CGRect) {
    super.init(frame: frame)
    NotificationCenter.default.addObserver(
      self, selector: #selector(scopesChanged), name: MunimMapScopes.didChange, object: nil)
    rebuild()
  }

  public required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  @objc private func scopesChanged() { connect() }

  public override func didMoveToWindow() {
    super.didMoveToWindow()
    connect()
  }

  public override func layoutSubviews() {
    super.layoutSubviews()
    guard let control else { return }
    let size = control.intrinsicContentSize
    let width = size.width > 0 && kind != .scale ? size.width : bounds.width
    let height = size.height > 0 ? size.height : bounds.height
    control.frame = CGRect(
      x: kind == .scale ? 0 : (bounds.width - width) / 2,
      y: (bounds.height - height) / 2, width: kind == .scale ? bounds.width : width, height: height)
  }

  private func rebuild() {
    control?.removeFromSuperview()
    let made: UIView
    switch kind {
    case .compass: made = MKCompassButton(mapView: nil)
    case .scale: made = MKScaleView(mapView: nil)
    case .userTrackingButton: made = MKUserTrackingButton(mapView: nil)
    }
    control = made
    addSubview(made)
    applyStyle()
    connect()
    setNeedsLayout()
  }

  private func applyStyle() {
    switch control {
    case let compass as MKCompassButton:
      compass.compassVisibility = visibility.mapKit
    case let scale as MKScaleView:
      scale.scaleVisibility = visibility.mapKit
      scale.legendAlignment = Self.alignment(scaleAlignment)
    default: break
    }
  }

  static func alignment(_ name: String) -> MKScaleView.Alignment {
    switch name {
    case "trailing": return .trailing
    case "center":
      #if compiler(>=6.2)
      if #available(iOS 26.0, *) { return .center }
      #endif
      return .leading
    default: return .leading
    }
  }

  private func connect() {
    let map = window == nil ? nil : MunimMapScopes.map(for: mapScope)?.mapView
    switch control {
    case let compass as MKCompassButton: if compass.mapView !== map { compass.mapView = map }
    case let scale as MKScaleView: if scale.mapView !== map { scale.mapView = map }
    case let button as MKUserTrackingButton: if button.mapView !== map { button.mapView = map }
    default: break
    }
  }
}

/// Asks for when-in-use location access the first time the map needs the
/// user's location (MapKit does not ask on its own), and reports changes.
final class MapLocationAuthorization: NSObject, CLLocationManagerDelegate {
  private var manager: CLLocationManager?
  var onAuthorized: (() -> Void)?

  func requestIfNeeded() {
    let manager = self.manager ?? CLLocationManager()
    if self.manager == nil {
      manager.delegate = self
      self.manager = manager
    }
    if manager.authorizationStatus == .notDetermined,
       Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") != nil {
      manager.requestWhenInUseAuthorization()
    }
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    switch manager.authorizationStatus {
    case .authorizedAlways, .authorizedWhenInUse: onAuthorized?()
    default: break
    }
  }
}
