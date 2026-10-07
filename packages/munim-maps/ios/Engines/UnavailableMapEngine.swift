import MapKit
import UIKit

/// What a map shows when its engine is not built into the app, or not
/// implemented yet: a plain panel saying so. It reports the reason through
/// `onError` once it has a listener.
@_expose(!Cxx)
public final class UnavailableMapEngine: UIView, MunimMapEngine, MunimMapEngineDefaults {
  public let provider: MunimMapProvider
  public let reason: String
  public let modelLayer = MunimModelLayer()
  public var view: UIView { self }
  public var initialCamera: MunimCamera?

  private let label = UILabel()
  private var reported = false

  public init(provider: MunimMapProvider, reason: String) {
    self.provider = provider
    self.reason = reason
    super.init(frame: .zero)
    backgroundColor = UIColor { $0.userInterfaceStyle == .dark
      ? UIColor(white: 0.12, alpha: 1) : UIColor(white: 0.93, alpha: 1) }
    label.text = "\(provider.displayName)\n\n\(reason)"
    label.numberOfLines = 0
    label.textAlignment = .center
    label.font = .preferredFont(forTextStyle: .footnote)
    label.textColor = .secondaryLabel
    label.translatesAutoresizingMaskIntoConstraints = false
    addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: centerXAnchor),
      label.centerYAnchor.constraint(equalTo: centerYAnchor),
      label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
      label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
    ])
  }

  public required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  public override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil { report() }
  }

  private func report() {
    guard !reported, let onError, window != nil else { return }
    reported = true
    onError(reason)
  }

  public var onMapReady: (() -> Void)?
  public var onPress: ((CLLocationCoordinate2D, CGPoint) -> Void)?
  public var onLongPress: ((CLLocationCoordinate2D, CGPoint) -> Void)?
  public var onCameraMove: ((MunimCamera) -> Void)?
  public var onCameraChange: ((MunimCamera) -> Void)?
  public var onMarkerPress: ((String) -> Void)?
  public var onMarkerDeselect: ((String) -> Void)?
  public var onCalloutPress: ((String) -> Void)?
  public var onCalloutAccessoryPress: ((String, String) -> Void)?
  public var onClusterPress: ((String, [String], CLLocationCoordinate2D) -> Void)?
  public var onOverlayPress: ((String, String, CLLocationCoordinate2D) -> Void)?
  public var onMarkerDragStart: ((String, CLLocationCoordinate2D) -> Void)?
  public var onMarkerDragEnd: ((String, CLLocationCoordinate2D) -> Void)?
  public var onUserLocationChange: ((CLLocation) -> Void)?
  public var onMapFeaturePress: ((MunimMapFeature) -> Void)?
  public var onUserTrackingModeChange: ((MKUserTrackingMode) -> Void)?
  public var onError: ((String) -> Void)? {
    didSet { report() }
  }

  // Nothing is drawn, so nothing to complain about per feature.
  public var markers: [MunimMarker] = []
  public var polylines: [MunimPolyline] = []
  public var polygons: [MunimPolygon] = []
  public var circles: [MunimCircle] = []
  public var tileOverlays: [MunimTileOverlay] = []
  public var showsUserLocation = false
  public var userTrackingMode: MKUserTrackingMode = .none
  public func setCamera(_ camera: MunimCamera, animated: Bool) {}
  public func setRegion(_ region: MKCoordinateRegion, duration: TimeInterval) {}
  public func fit(coordinates: [CLLocationCoordinate2D], padding: UIEdgeInsets, animated: Bool) {}
  public func fitMarkers(_ ids: Set<String>, padding: UIEdgeInsets, animated: Bool) {}
  public func flyCamera(_ keyframes: [MunimCameraKeyframe], start: Double, loop: Bool) {}
  public func setViewMarker(_ marker: MunimMarker, image: UIImage?) {}
}
