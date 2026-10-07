import MapKit
import UIKit

/// Draws 3D models, zones and paths over an `MKMapView` you already have,
/// or over any engine's map through its `MapCameraSource` (`attach(to:)`).
///
/// ```swift
/// let layer = MunimModelLayer()
/// layer.install(over: mapView)          // adds its view above the map
/// layer.models = [MunimModel(id: "car", coordinate: c, uri: url.absoluteString, screenSize: 18)]
/// layer.onModelPress = { id in print(id) }
/// ```
///
/// Or add `layer.view` yourself, covering the map, and call `attach(to:)`.
/// With `autoAttach` the layer finds the map on its own: the map whose
/// `accessibilityIdentifier` is `mapIdentifier`, or the nearest map on screen.
@_expose(!Cxx)
public final class MunimModelLayer: NSObject {
  /// The view to place over the map. It never takes touches.
  public let view: UIView

  private let hostView = MapModelHostView()
  private let renderer: MapModelRenderer
  private var searchTimer: Timer?
  private var reportedAttached = false

  public var models: [MunimModel] = [] {
    didSet { renderer.setModels(models) }
  }

  public var zones: [MunimZone] = [] {
    didSet { renderer.setZones(zones) }
  }

  /// Hides models behind buildings, which MapKit cannot do because it does
  /// not share its depth buffer. Building footprints and heights come from
  /// vector tiles around the camera (OpenStreetMap data from OpenFreeMap by
  /// default, so the visible area is requested from that server). Avatars,
  /// labels and stems always stay visible.
  public var buildingOcclusion: Bool {
    get { renderer.buildings.enabled }
    set { renderer.buildings.enabled = newValue; renderer.setNeedsRender() }
  }

  /// `{z}/{x}/{y}` URL of Mapbox Vector Tiles with an OpenMapTiles
  /// `building` layer, for `buildingOcclusion`. Empty uses OpenFreeMap.
  public var buildingTilesURL: String {
    get { renderer.buildings.tileURLTemplate }
    set { renderer.buildings.tileURLTemplate = newValue }
  }

  /// Keeps models, paths and zones whose altitude is above the ground on
  /// MapKit's 3D terrain, which it draws for satellite imagery (`hybrid`,
  /// `imagery`) with realistic elevation. MapKit does not share terrain
  /// heights, so they are looked up with `MunimTerrain` (public elevation
  /// tiles, so the area is requested from AWS). Models above sea level
  /// (`altitudeReference = .sea`) always follow the terrain. Off by default.
  public var followsTerrain: Bool {
    get { renderer.followsTerrain }
    set { renderer.followsTerrain = newValue }
  }

  /// Lines drawn in 3D: above the ground and on the globe.
  public var paths: [MunimPath] = [] {
    didSet { renderer.setPaths(paths) }
  }

  public var lighting: MunimLighting = .auto {
    didSet { renderer.lighting = lighting }
  }

  /// Hide everything when the camera is farther away than this, in metres.
  public var maxCameraDistance: Double = 50_000 {
    didSet { renderer.maxCameraDistance = maxCameraDistance }
  }

  /// Keeps the map's standard and hybrid styles on realistic elevation, as
  /// Apple Maps does: 3D terrain and landmarks up close. A map library that
  /// sets a flat style (react-native-maps' `standard` type) is switched over
  /// every time it changes the style. iOS 16+.
  public var realisticElevation = false {
    didSet { updateMapStyleHooks() }
  }

  /// Shows the standard style as a globe when zoomed far out, as Apple Maps
  /// does (MapKit's public API only does this for satellite imagery).
  ///
  /// This uses a switch inside MapKit that is not public API: it can stop
  /// working in an iOS update (the map then stays flat) and App Review may
  /// reject an app for it. Check `isGlobeAvailable` to see whether it took.
  public var globe = false {
    didSet { if oldValue != globe { updateMapStyleHooks() } }
  }

  /// Whether this iOS has the switch `globe` relies on. False until attached.
  public var isGlobeAvailable: Bool {
    renderer.mapView.map(MapGlobe.isAvailable(on:)) ?? false
  }

  /// Look for the map automatically when the layer joins a window.
  public var autoAttach = false {
    didSet { if autoAttach { attachIfPossible() } }
  }

  /// With `autoAttach`, the `accessibilityIdentifier` of the map (or a view
  /// containing it). Empty means the nearest map.
  public var mapIdentifier = "" {
    didSet {
      if oldValue != mapIdentifier, autoAttach {
        renderer.detach()
        attachIfPossible()
      }
    }
  }

  public var onModelPress: ((String) -> Void)?
  public var onAttachChange: ((Bool) -> Void)?
  public var onError: ((String) -> Void)?

  public override init() {
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

  public var isAttached: Bool { renderer.isAttached }
  public var mapView: MKMapView? { renderer.mapView }

  /// Adds the layer's view above `mapView`, sized to it, and attaches.
  public func install(over mapView: MKMapView) {
    if let superview = mapView.superview {
      hostView.frame = mapView.frame
      hostView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      superview.insertSubview(hostView, aboveSubview: mapView)
    }
    attach(to: mapView)
  }

  public func attach(to mapView: MKMapView) {
    renderer.attach(to: mapView)
    renderer.updateFrameLoop()
    reportAttached(true)
    keepMapStyle()
  }

  /// Draws over any engine's map: Google Maps, Mapbox, MapLibre or Cesium
  /// engines hand in their `MapCameraSource`. Put `view` over the engine's
  /// map view first. The source is held weakly.
  public func attach(to source: MapCameraSource) {
    renderer.attach(to: source)
    renderer.updateFrameLoop()
    reportAttached(true)
  }

  public func detach() {
    renderer.detach()
    reportAttached(false)
  }

  /// Compares the drawn models with MapKit's own projection.
  public func measureAlignment() -> MunimAlignmentReport {
    renderer.measureAlignment()
  }

  /// The id of the model under `point`, in the map's coordinates.
  public func modelHit(at point: CGPoint) -> String? {
    renderer.modelHit(at: point)
  }

  func setNeedsRender() {
    renderer.setNeedsRender()
  }

  private var globeOn: MKMapView?

  private func updateMapStyleHooks() {
    let needsHook = realisticElevation || globe
    renderer.beforeFrame = needsHook ? { [weak self] in self?.keepMapStyle() } : nil
    keepMapStyle()
  }

  /// Runs before every frame while either option is on: map libraries reset
  /// the style whenever their props change.
  private func keepMapStyle() {
    if realisticElevation { keepRealisticElevation() }
    let map = renderer.mapView
    if globe, let map {
      MapGlobe.set(true, on: map)
      globeOn = map
    } else if let previous = globeOn {
      MapGlobe.set(false, on: previous)
      globeOn = nil
    }
  }

  private func keepRealisticElevation() {
    guard #available(iOS 16.0, *), let map = renderer.mapView else { return }
    let current = map.preferredConfiguration
    if let standard = current as? MKStandardMapConfiguration, standard.elevationStyle != .realistic {
      let realistic = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: standard.emphasisStyle)
      realistic.pointOfInterestFilter = standard.pointOfInterestFilter
      realistic.showsTraffic = standard.showsTraffic
      map.preferredConfiguration = realistic
    } else if let hybrid = current as? MKHybridMapConfiguration, hybrid.elevationStyle != .realistic {
      let realistic = MKHybridMapConfiguration(elevationStyle: .realistic)
      realistic.pointOfInterestFilter = hybrid.pointOfInterestFilter
      realistic.showsTraffic = hybrid.showsTraffic
      map.preferredConfiguration = realistic
    } else if let imagery = current as? MKImageryMapConfiguration, imagery.elevationStyle != .realistic {
      map.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
    }
  }

  // MARK: Finding the map

  private func windowChanged() {
    if hostView.window == nil {
      searchTimer?.invalidate()
      searchTimer = nil
      renderer.updateFrameLoop()
      return
    }
    if autoAttach { attachIfPossible() } else { renderer.updateFrameLoop() }
  }

  /// The map may appear after this view, so keep looking for a few seconds,
  /// and look again whenever the map we had goes away.
  private func attachIfPossible() {
    guard hostView.window != nil else { return }
    if let mapView = renderer.mapView, mapView.window != nil, matches(mapView) {
      renderer.updateFrameLoop()
      reportAttached(true)
      return
    }
    if let mapView = findMapView() {
      renderer.attach(to: mapView)
      keepMapStyle()
      reportAttached(true)
      schedule(every: 1) { [weak self] in self?.checkStillAttached() }
    } else {
      renderer.detach()
      reportAttached(false)
      schedule(every: 0.25) { [weak self] in self?.attachIfPossible() }
    }
  }

  private func schedule(every interval: TimeInterval, _ block: @escaping () -> Void) {
    if let searchTimer, searchTimer.timeInterval == interval { return }
    searchTimer?.invalidate()
    searchTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in block() }
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
    guard !mapIdentifier.isEmpty else { return true }
    var current: UIView? = mapView
    while let view = current {
      if view.accessibilityIdentifier == mapIdentifier { return true }
      current = view.superview
    }
    return false
  }

  private func findMapView() -> MKMapView? {
    guard let window = hostView.window else { return nil }
    if !mapIdentifier.isEmpty {
      guard let tagged = firstView(in: window, where: { $0.accessibilityIdentifier == mapIdentifier })
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
    for subview in view.subviews { collectMapViews(in: subview, into: &result) }
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
