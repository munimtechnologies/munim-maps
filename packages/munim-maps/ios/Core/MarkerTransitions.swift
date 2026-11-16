import CoreLocation
import QuartzCore
import UIKit

/// Glides markers to new coordinates (`animationDuration`), like
/// react-native-maps' `animateMarkerToCoordinate`: keeps where each marker is
/// drawn now, and while a glide runs moves the gliding markers once a frame,
/// from a display link that only runs then.
///
/// It handles both kinds of marker: the `markers` list and `MarkerView`s
/// (view markers, one at a time with their picture). Everything but the
/// position applies at once. A new coordinate while a marker glides starts
/// from where it is drawn; the same coordinate again carries on.
///
/// Each frame the gliding markers' positions go to `move`, which an engine
/// that can move a marker in place (MapKit, Google Maps) answers with `true`;
/// otherwise the whole list goes to `draw` (and each gliding view marker to
/// `drawViewMarker`). When the glides end, `draw` gets the props as given, so
/// the engine ends on exactly what JavaScript sent.
public final class MunimMarkerTransitions {
  /// Every marker of the list as drawn now.
  public var draw: ([MunimMarker]) -> Void
  /// A view marker as drawn now, with its picture.
  public var drawViewMarker: (MunimMarker, UIImage?) -> Void
  /// The gliding markers' positions this frame, by id. `true` when the
  /// engine moved them itself.
  public var move: ([String: CLLocationCoordinate2D]) -> Bool

  private struct Run {
    var from: CLLocationCoordinate2D
    var to: CLLocationCoordinate2D
    var start: CFTimeInterval
    var duration: CFTimeInterval
  }

  private var targets: [MunimMarker] = []
  /// The props' positions, by id (what is drawn when nothing glides).
  private var drawn: [String: CLLocationCoordinate2D] = [:]
  private var runs: [String: Run] = [:]
  private var viewTargets: [String: (marker: MunimMarker, image: UIImage?)] = [:]
  private var viewRuns: [String: Run] = [:]
  private var link: CADisplayLink?

  public init(
    draw: @escaping ([MunimMarker]) -> Void = { _ in },
    drawViewMarker: @escaping (MunimMarker, UIImage?) -> Void = { _, _ in },
    move: @escaping ([String: CLLocationCoordinate2D]) -> Bool = { _ in false }
  ) {
    self.draw = draw
    self.drawViewMarker = drawViewMarker
    self.move = move
  }

  deinit { link?.invalidate() }

  public var isAnimating: Bool { link != nil }

  /// New markers. `passThrough` (an engine that glides markers itself)
  /// sends them unchanged.
  public func setMarkers(_ markers: [MunimMarker], passThrough: Bool = false) {
    let now = CACurrentMediaTime()
    var next: [String: Run] = [:]
    var positions: [String: CLLocationCoordinate2D] = [:]
    for target in markers where positions[target.id] == nil {
      let to = target.coordinate
      positions[target.id] = to
      guard !passThrough, target.animationDuration > 0,
            let current = position(target.id, at: now) else { continue }
      if let run = runs[target.id], Self.same(run.to, to) {
        // Already gliding there (the same props again): carry on.
        next[target.id] = run
        continue
      }
      guard !Self.same(current, to) else { continue }
      next[target.id] = Run(from: current, to: to, start: now, duration: target.animationDuration / 1000)
    }
    targets = markers
    drawn = positions
    runs = next
    draw(frame(at: now))
    updateLink()
  }

  /// A `MarkerView`'s marker and picture; see `setMarkers`.
  public func setViewMarker(_ marker: MunimMarker, image: UIImage?, passThrough: Bool = false) {
    let now = CACurrentMediaTime()
    let to = marker.coordinate
    let current = viewRuns[marker.id].map { Self.position($0, at: now) } ?? viewTargets[marker.id]?.marker.coordinate
    viewTargets[marker.id] = (marker, image)
    if passThrough || marker.animationDuration <= 0 || current == nil {
      viewRuns[marker.id] = nil
    } else if let run = viewRuns[marker.id], Self.same(run.to, to) {
      // Carry on.
    } else if let current, !Self.same(current, to) {
      viewRuns[marker.id] = Run(from: current, to: to, start: now, duration: marker.animationDuration / 1000)
    } else {
      viewRuns[marker.id] = nil
    }
    drawViewMarker(viewFrame(marker.id, at: now) ?? marker, image)
    updateLink()
  }

  /// A new picture for a view marker (where it is drawn now).
  public func setViewMarkerImage(_ image: UIImage?, id: String) {
    guard var entry = viewTargets[id] else { return }
    entry.image = image
    viewTargets[id] = entry
  }

  public func removeViewMarker(_ id: String) {
    viewTargets[id] = nil
    viewRuns[id] = nil
    updateLink()
  }

  /// Stops every glide (the markers jump to their targets).
  public func finish() {
    let hadRuns = !runs.isEmpty
    let views = viewRuns.keys
    runs = [:]
    viewRuns = [:]
    updateLink()
    if hadRuns { draw(targets) }
    for id in views { if let entry = viewTargets[id] { drawViewMarker(entry.marker, entry.image) } }
  }

  /// Forgets the list and every glide (a new engine starts empty); the view
  /// markers are kept for `resendViewMarkers`.
  public func reset() {
    targets = []
    drawn = [:]
    runs = [:]
    viewRuns = [:]
    updateLink()
  }

  /// Sends every view marker again, to a new engine.
  public func resendViewMarkers() {
    for entry in viewTargets.values { drawViewMarker(entry.marker, entry.image) }
  }

  // MARK: Frames

  private func position(_ id: String, at time: CFTimeInterval) -> CLLocationCoordinate2D? {
    if let run = runs[id] { return Self.position(run, at: time) }
    return drawn[id]
  }

  private func frame(at time: CFTimeInterval) -> [MunimMarker] {
    guard !runs.isEmpty else { return targets }
    return targets.map { m in
      guard let run = runs[m.id] else { return m }
      var moved = m
      let p = Self.position(run, at: time)
      moved.latitude = p.latitude
      moved.longitude = p.longitude
      return moved
    }
  }

  private func viewFrame(_ id: String, at time: CFTimeInterval) -> MunimMarker? {
    guard let run = viewRuns[id], var marker = viewTargets[id]?.marker else { return nil }
    let p = Self.position(run, at: time)
    marker.latitude = p.latitude
    marker.longitude = p.longitude
    return marker
  }

  @objc private func tick(_ link: CADisplayLink) {
    let now = CACurrentMediaTime()
    var positions: [String: CLLocationCoordinate2D] = [:]
    for (id, run) in runs { positions[id] = Self.position(run, at: now) }
    for (id, run) in viewRuns { positions[id] = Self.position(run, at: now) }
    let movedInPlace = move(positions)
    let gliding = !runs.isEmpty
    let glidingViews = Array(viewRuns.keys)
    let ended = runs.filter { now >= $0.value.start + $0.value.duration }.keys
    let endedViews = Set(viewRuns.filter { now >= $0.value.start + $0.value.duration }.keys)
    for id in ended { runs[id] = nil }
    for id in endedViews { viewRuns[id] = nil }
    // Engines that cannot move markers in place get the list every frame;
    // the others get it once a glide ends, so they end on the props as given.
    if gliding && (!movedInPlace || !ended.isEmpty) { draw(frame(at: now)) }
    for id in glidingViews where !movedInPlace || endedViews.contains(id) {
      guard let entry = viewTargets[id] else { continue }
      drawViewMarker(viewFrame(id, at: now) ?? entry.marker, entry.image)
    }
    updateLink()
  }

  private func updateLink() {
    let running = !runs.isEmpty || !viewRuns.isEmpty
    if running, link == nil {
      let link = CADisplayLink(target: WeakTarget(self), selector: #selector(WeakTarget.tick(_:)))
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 60)
      link.add(to: .main, forMode: .common)
      self.link = link
    } else if !running, let link {
      link.invalidate()
      self.link = nil
    }
  }

  /// The display link holds its target strongly.
  private final class WeakTarget: NSObject {
    weak var owner: MunimMarkerTransitions?
    init(_ owner: MunimMarkerTransitions) { self.owner = owner }
    @objc func tick(_ link: CADisplayLink) {
      if let owner { owner.tick(link) } else { link.invalidate() }
    }
  }

  // MARK: Interpolation

  private static func position(_ run: Run, at time: CFTimeInterval) -> CLLocationCoordinate2D {
    let t = MunimShapeTransitions.progress(start: run.start, duration: run.duration, at: time)
    return t >= 1 ? run.to : MunimShapeTransitions.lerp(run.from, run.to, t)
  }

  private static func same(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
    a.latitude == b.latitude && a.longitude == b.longitude
  }
}
