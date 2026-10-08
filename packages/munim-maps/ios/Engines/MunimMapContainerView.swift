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
