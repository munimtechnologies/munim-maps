import NitroModules
import UIKit

/// React Native `MarkerView`: draws its React Native children (siblings of
/// this view inside the component's container, laid out off screen) into
/// an image, and hands it to the `MunimMapView` it sits in as a marker.
final class HybridMarkerView: HybridMarkerViewSpec {
  private let host = MarkerViewHost()
  var view: UIView { host }

  override init() {
    super.init()
    host.owner = self
  }

  var marker = MarkerViewDefaults.marker { didSet { host.propsChanged() } }
  var tracksViewChanges = false { didSet { host.trackingChanged() } }
  var renderKey: Double = 0 { didSet { host.scheduleRedraws() } }

  func redraw() throws {
    DispatchQueue.main.async { self.host.redraw() }
  }
}

enum MarkerViewDefaults {
  static let accessory = NativeCalloutAccessory(kind: .none, text: "", symbol: "", imageUri: "", color: "")
  static let marker = NativeMarker(
    id: "", latitude: 0, longitude: 0, title: "", subtitle: "", style: .image, color: "", glyph: "",
    imageUri: "", imageSize: 0, borderColor: "", borderWidth: 0, badges: [], anchorX: 0.5, anchorY: 0.5,
    zIndex: 0, draggable: false, clusteringId: "", calloutEnabled: false, opacity: 1, visible: true,
    displayPriority: 1000, collisionMode: .rectangle, titleVisibility: .adaptive, subtitleVisibility: .adaptive,
    glyphSymbol: "", selectedGlyphSymbol: "", glyphColor: "", animatesWhenAdded: false,
    leftCalloutAccessory: accessory, rightCalloutAccessory: accessory, calloutDetail: "")
}

private final class MarkerViewHost: UIView {
  weak var owner: HybridMarkerView?
  private weak var map: MunimMapKitView?
  private var registeredId = ""
  private var trackTimer: Timer?
  private var pendingRedraws: [DispatchWorkItem] = []

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      register()
      trackingChanged()
    } else {
      unregister()
      trackTimer?.invalidate()
      trackTimer = nil
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    scheduleRedraws()
  }

  /// The children are drawn by Fabric after props arrive, and pictures load
  /// later still, so draw a few times after every change.
  func scheduleRedraws() {
    pendingRedraws.forEach { $0.cancel() }
    pendingRedraws = [0.0, 0.1, 0.4, 1.2].map { delay in
      let work = DispatchWorkItem { [weak self] in self?.redraw() }
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
      return work
    }
  }

  func propsChanged() {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      if let id = self.owner?.marker.id, id != self.registeredId { self.unregister() }
      self.register()
      self.scheduleRedraws()
    }
  }

  func trackingChanged() {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let tracking = self.owner?.tracksViewChanges == true && self.window != nil
      if tracking, self.trackTimer == nil {
        let timer = Timer(timeInterval: 1.0 / 15, repeats: true) { [weak self] _ in self?.redraw() }
        RunLoop.main.add(timer, forMode: .common)
        self.trackTimer = timer
      } else if !tracking {
        self.trackTimer?.invalidate()
        self.trackTimer = nil
      }
    }
  }

  /// The `MunimMapKitView` of the `MunimMapView` this marker is a child of:
  /// a sibling of one of this view's containers.
  private func findMap() -> MunimMapKitView? {
    var ancestor = superview
    var depth = 0
    while let current = ancestor, depth < 8 {
      for sibling in current.subviews {
        if let map = sibling as? MunimMapKitView { return map }
      }
      ancestor = current.superview
      depth += 1
    }
    return nil
  }

  private func register() {
    guard window != nil, let owner, !owner.marker.id.isEmpty else { return }
    guard let map = map ?? findMap() else { return }
    self.map = map
    registeredId = owner.marker.id
    map.setViewMarker(owner.marker.core, image: snapshot())
  }

  private func unregister() {
    guard !registeredId.isEmpty else { return }
    map?.removeViewMarker(registeredId)
    registeredId = ""
  }

  /// Draws the React Native children: everything in the container except
  /// this (empty) view.
  private func snapshot() -> UIImage? {
    guard let container = superview, container.bounds.width >= 1, container.bounds.height >= 1 else { return nil }
    let format = UIGraphicsImageRendererFormat()
    format.scale = window?.screen.scale ?? UIScreen.main.scale
    format.opaque = false
    return UIGraphicsImageRenderer(bounds: container.bounds, format: format).image { context in
      for child in container.subviews where child !== self && !child.isHidden {
        context.cgContext.saveGState()
        context.cgContext.translateBy(x: child.frame.minX, y: child.frame.minY)
        child.layer.render(in: context.cgContext)
        context.cgContext.restoreGState()
      }
    }
  }

  func redraw() {
    guard window != nil else { return }
    if registeredId.isEmpty { register(); return }
    map?.setViewMarkerImage(snapshot(), id: registeredId)
  }

  deinit {
    trackTimer?.invalidate()
    if !registeredId.isEmpty, let map {
      let id = registeredId
      DispatchQueue.main.async { map.removeViewMarker(id) }
    }
  }
}
