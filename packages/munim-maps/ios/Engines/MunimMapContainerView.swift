import UIKit

/// Shows one map engine at a time, filling itself, and swaps engines when
/// the provider changes. React Native's `MunimMapView` is one of these.
@_expose(!Cxx)
public final class MunimMapContainerView: UIView {
  public private(set) var engine: MunimMapEngine

  public init(provider: MunimMapProvider = .mapkit) {
    engine = MunimMapEngines.make(provider)
    super.init(frame: .zero)
    install(engine.view)
    shapeTransitions.draw = { [weak self] circles, polygons in
      guard let engine = self?.engine else { return }
      if let circles { engine.circles = circles }
      if let polygons { engine.polygons = polygons }
    }
    markerTransitions.draw = { [weak self] markers in self?.engine.markers = markers }
    markerTransitions.drawViewMarker = { [weak self] marker, image in self?.engine.setViewMarker(marker, image: image) }
    markerTransitions.move = { [weak self] positions in self?.engine.moveMarkers(positions) ?? true }
  }

  private let markerTransitions = MunimMarkerTransitions()

  /// Sets the engine's markers, gliding the ones with an `animationDuration`
  /// from where they are drawn now to their new coordinate.
  public func setMarkers(_ markers: [MunimMarker]) {
    markerTransitions.setMarkers(markers, passThrough: engine.animatesMarkerTransitions)
  }

  /// A `MarkerView`'s marker and picture, gliding like `setMarkers`.
  public func setViewMarker(_ marker: MunimMarker, image: UIImage?) {
    markerTransitions.setViewMarker(marker, image: image, passThrough: engine.animatesMarkerTransitions)
  }

  public func setViewMarkerImage(_ image: UIImage?, id: String) {
    markerTransitions.setViewMarkerImage(image, id: id)
    engine.setViewMarkerImage(image, id: id)
  }

  public func removeViewMarker(_ id: String) {
    markerTransitions.removeViewMarker(id)
    engine.removeViewMarker(id)
  }

  private let shapeTransitions = MunimShapeTransitions { _, _ in }

  /// Sets the engine's circles, gliding the ones with an
  /// `animationDuration` from where they are drawn now.
  public func setCircles(_ circles: [MunimCircle]) {
    shapeTransitions.setCircles(circles, passThrough: engine.animatesShapeTransitions)
  }

  /// Sets the engine's polygons; see `setCircles`.
  public func setPolygons(_ polygons: [MunimPolygon]) {
    shapeTransitions.setPolygons(polygons, passThrough: engine.animatesShapeTransitions)
  }

  public required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  public var provider: MunimMapProvider { engine.provider }

  /// Replaces the engine when `provider` (or, for providers with more than
  /// one renderer, the one `options` asks for) differs from the current one.
  /// Returns the new engine, or nil when nothing changed; the caller then
  /// sets every property on it again.
  @discardableResult
  public func setProvider(_ provider: MunimMapProvider, options: [String: Any] = [:]) -> MunimMapEngine? {
    let variant = MunimMapEngines.variant(for: provider, options: options)
    guard provider != engine.provider || variant != engine.variant else { return nil }
    shapeTransitions.finish()
    markerTransitions.finish()
    markerTransitions.reset()
    engine.view.removeFromSuperview()
    engine = MunimMapEngines.make(provider, options: options)
    install(engine.view)
    // `MarkerView`s stay on the map when the engine changes.
    markerTransitions.resendViewMarkers()
    return engine
  }

  private func install(_ view: UIView) {
    view.frame = bounds
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(view)
  }
}
