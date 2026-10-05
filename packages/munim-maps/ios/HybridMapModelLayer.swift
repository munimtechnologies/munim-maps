import MapKit
import NitroModules
import UIKit

/// Draws models over a MapKit map that something else owns, such as
/// react-native-maps. Render it on top of the map; it finds the map by
/// `testID` or, by default, as the nearest MapKit map on screen.
final class HybridMapModelLayer: HybridMapModelLayerSpec {
  let view: UIView

  private let hostView = MapModelHostView()
  private let renderer: MapModelRenderer
  private var searchTimer: Timer?
  private var reportedAttached = false

  override init() {
    view = hostView
    renderer = MapModelRenderer(hostView: hostView)
    super.init()
    hostView.onWindowChange = { [weak self] in self?.windowChanged() }
    hostView.onLayout = { [weak self] in self?.renderer.setNeedsRender() }
    renderer.onModelPress = { [weak self] id in self?.onModelPress?(id) }
    renderer.onError = { [weak self] message in self?.onError?(message) }
  }

  deinit {
    searchTimer?.invalidate()
  }

  var models: [NativeMapModel] = [] {
    didSet { renderer.setModels(models) }
  }

  var mapTestID: String = "" {
    didSet {
      if oldValue != mapTestID {
        renderer.detach()
        attachIfPossible()
      }
    }
  }

  var lighting: MapModelLighting = .auto {
    didSet { renderer.lighting = lighting }
  }

  var maxCameraDistance: Double = 50_000 {
    didSet { renderer.maxCameraDistance = maxCameraDistance }
  }

  var onModelPress: ((_ id: String) -> Void)?
  var onAttachChange: ((_ attached: Bool) -> Void)?
  var onError: ((_ message: String) -> Void)?

  func isAttached() throws -> Bool {
    onMain { self.renderer.isAttached }
  }

  func measureAlignment() throws -> Promise<MapAlignmentReport> {
    let promise = Promise<MapAlignmentReport>()
    DispatchQueue.main.async {
      promise.resolve(withResult: self.renderer.measureAlignment())
    }
    return promise
  }

  // MARK: Finding the map

  private func windowChanged() {
    if hostView.window == nil {
      searchTimer?.invalidate()
      searchTimer = nil
      renderer.updateFrameLoop()
      return
    }
    attachIfPossible()
  }

  /// React Native may mount the map after this view, so keep looking for a
  /// few seconds, and look again whenever the map we had goes away.
  private func attachIfPossible() {
    guard hostView.window != nil else { return }
    if let mapView = renderer.mapView, mapView.window != nil, matches(mapView) {
      renderer.updateFrameLoop()
      reportAttached(true)
      return
    }
    if let mapView = findMapView() {
      renderer.attach(to: mapView)
      reportAttached(true)
      searchTimer?.invalidate()
      searchTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
        self?.checkStillAttached()
      }
    } else {
      renderer.detach()
      reportAttached(false)
      if searchTimer == nil || searchTimer?.timeInterval != 0.25 {
        searchTimer?.invalidate()
        searchTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
          self?.attachIfPossible()
        }
      }
    }
  }

  private func checkStillAttached() {
    guard let mapView = renderer.mapView, mapView.window != nil else {
      attachIfPossible()
      return
    }
  }

  private func reportAttached(_ attached: Bool) {
    guard attached != reportedAttached else { return }
    reportedAttached = attached
    onAttachChange?(attached)
  }

  private func matches(_ mapView: MKMapView) -> Bool {
    guard !mapTestID.isEmpty else { return true }
    var current: UIView? = mapView
    while let view = current {
      if view.accessibilityIdentifier == mapTestID { return true }
      current = view.superview
    }
    return false
  }

  private func findMapView() -> MKMapView? {
    guard let window = hostView.window else { return nil }

    if !mapTestID.isEmpty {
      guard let tagged = firstView(in: window, where: { $0.accessibilityIdentifier == mapTestID })
      else { return nil }
      return firstMapView(in: tagged)
    }

    // Walk up from this view and take the map that overlaps it most at the
    // first level that has one.
    let ownFrame = hostView.convert(hostView.bounds, to: window)
    var ancestor = hostView.superview
    var depth = 0
    while let current = ancestor, depth < 10 {
      var candidates: [MKMapView] = []
      collectMapViews(in: current, into: &candidates)
      if !candidates.isEmpty {
        return candidates.max { a, b in
          overlap(a, with: ownFrame, in: window) < overlap(b, with: ownFrame, in: window)
        }
      }
      ancestor = current.superview
      depth += 1
    }
    return nil
  }

  private func overlap(_ mapView: MKMapView, with frame: CGRect, in window: UIWindow) -> CGFloat {
    let intersection = mapView.convert(mapView.bounds, to: window).intersection(frame)
    return intersection.isNull ? 0 : intersection.width * intersection.height
  }

  private func collectMapViews(in view: UIView, into result: inout [MKMapView]) {
    if view === hostView { return }
    if let mapView = view as? MKMapView {
      result.append(mapView)
      return
    }
    for subview in view.subviews {
      collectMapViews(in: subview, into: &result)
    }
  }

  private func firstMapView(in view: UIView) -> MKMapView? {
    var result: [MKMapView] = []
    collectMapViews(in: view, into: &result)
    return result.first
  }

  private func firstView(in view: UIView, where predicate: (UIView) -> Bool) -> UIView? {
    if predicate(view) { return view }
    for subview in view.subviews {
      if let found = firstView(in: subview, where: predicate) { return found }
    }
    return nil
  }
}

/// Runs `work` on the main thread and returns its result.
func onMain<T>(_ work: () -> T) -> T {
  if Thread.isMainThread { return work() }
  return DispatchQueue.main.sync(execute: work)
}
