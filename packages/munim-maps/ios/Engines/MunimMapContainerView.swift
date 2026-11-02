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
    engine.view.removeFromSuperview()
    engine = MunimMapEngines.make(provider, options: options)
    install(engine.view)
    return engine
  }

  private func install(_ view: UIView) {
    view.frame = bounds
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(view)
  }
}
