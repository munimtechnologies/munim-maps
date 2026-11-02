import CoreLocation
import QuartzCore

/// Glides circles and polygons to new geometry (`animationDuration`): keeps
/// what is drawn now, and while a transition runs hands the engine the
/// shapes in between, once a frame, from a display link that only runs then.
///
/// Style changes (colours, widths) apply at once; only the geometry moves.
/// A polygon glides only when its new rings have the same vertex counts;
/// otherwise it jumps.
public final class MunimShapeTransitions {
  /// Receives the shapes to draw now: circles, polygons, or both.
  public var draw: (_ circles: [MunimCircle]?, _ polygons: [MunimPolygon]?) -> Void

  private struct Run<Shape> {
    var from: Shape
    var to: Shape
    var start: CFTimeInterval
    var duration: CFTimeInterval
  }

  private var circleTargets: [MunimCircle] = []
  private var polygonTargets: [MunimPolygon] = []
  /// The geometry drawn last, by id.
  private var drawnCircles: [String: MunimCircle] = [:]
  private var drawnPolygons: [String: MunimPolygon] = [:]
  private var circleRuns: [String: Run<MunimCircle>] = [:]
  private var polygonRuns: [String: Run<MunimPolygon>] = [:]
  private var link: CADisplayLink?

  public init(draw: @escaping (_ circles: [MunimCircle]?, _ polygons: [MunimPolygon]?) -> Void) {
    self.draw = draw
  }

  deinit { link?.invalidate() }

  public var isAnimating: Bool { link != nil }

  /// New circles. `passThrough` (an engine that animates by itself) sends
  /// them unchanged.
  public func setCircles(_ circles: [MunimCircle], passThrough: Bool = false) {
    let now = CACurrentMediaTime()
    var runs: [String: Run<MunimCircle>] = [:]
    var drawn: [String: MunimCircle] = [:]
    for target in circles where drawn[target.id] == nil {
      drawn[target.id] = target
      guard !passThrough, target.animationDuration > 0,
            let current = currentCircle(target.id, at: now) else { continue }
      if var run = circleRuns[target.id], Self.sameGeometry(run.to, target) {
        // Already gliding there (the same props again): carry on;
        // frames take their style from `to`.
        run.to = target
        runs[target.id] = run
        continue
      }
      var from = target
      from.latitude = current.latitude
      from.longitude = current.longitude
      from.radius = current.radius
      guard !Self.sameGeometry(from, target) else { continue }
      runs[target.id] = Run(from: from, to: target, start: now, duration: target.animationDuration / 1000)
    }
    circleTargets = circles
    drawnCircles = drawn
    circleRuns = runs
    draw(frameCircles(at: now), nil)
    updateLink()
  }

  /// New polygons; see `setCircles`.
  public func setPolygons(_ polygons: [MunimPolygon], passThrough: Bool = false) {
    let now = CACurrentMediaTime()
    var runs: [String: Run<MunimPolygon>] = [:]
    var drawn: [String: MunimPolygon] = [:]
    for target in polygons where drawn[target.id] == nil {
      drawn[target.id] = target
      guard !passThrough, target.animationDuration > 0,
            let current = currentPolygon(target.id, at: now),
            Self.sameShape(current, target) else { continue }
      if var run = polygonRuns[target.id], Self.sameGeometry(run.to, target) {
        run.to = target
        runs[target.id] = run
        continue
      }
      var from = target
      from.coordinates = current.coordinates
      from.holes = current.holes
      guard !Self.sameGeometry(from, target) else { continue }
      runs[target.id] = Run(from: from, to: target, start: now, duration: target.animationDuration / 1000)
    }
    polygonTargets = polygons
    drawnPolygons = drawn
    polygonRuns = runs
    draw(nil, framePolygons(at: now))
    updateLink()
  }

  /// Stops every transition where it is now (the shapes jump to their targets).
  public func finish() {
    let hadCircles = !circleRuns.isEmpty, hadPolygons = !polygonRuns.isEmpty
    circleRuns = [:]
    polygonRuns = [:]
    updateLink()
    if hadCircles || hadPolygons {
      draw(hadCircles ? circleTargets : nil, hadPolygons ? polygonTargets : nil)
    }
  }

  // MARK: Frames

  private func currentCircle(_ id: String, at time: CFTimeInterval) -> MunimCircle? {
    if let run = circleRuns[id] { return Self.circle(run, at: time) }
    return drawnCircles[id]
  }

  private func currentPolygon(_ id: String, at time: CFTimeInterval) -> MunimPolygon? {
    if let run = polygonRuns[id] { return Self.polygon(run, at: time) }
    return drawnPolygons[id]
  }

  private func frameCircles(at time: CFTimeInterval) -> [MunimCircle] {
    guard !circleRuns.isEmpty else { return circleTargets }
    return circleTargets.map { c in circleRuns[c.id].map { Self.circle($0, at: time) } ?? c }
  }

  private func framePolygons(at time: CFTimeInterval) -> [MunimPolygon] {
    guard !polygonRuns.isEmpty else { return polygonTargets }
    return polygonTargets.map { p in polygonRuns[p.id].map { Self.polygon($0, at: time) } ?? p }
  }

  @objc private func tick(_ link: CADisplayLink) {
    let now = CACurrentMediaTime()
    let circles = circleRuns.isEmpty ? nil : frameCircles(at: now)
    let polygons = polygonRuns.isEmpty ? nil : framePolygons(at: now)
    circleRuns = circleRuns.filter { now < $0.value.start + $0.value.duration }
    polygonRuns = polygonRuns.filter { now < $0.value.start + $0.value.duration }
    updateLink()
    if circles != nil || polygons != nil { draw(circles, polygons) }
  }

  private func updateLink() {
    let running = !circleRuns.isEmpty || !polygonRuns.isEmpty
    if running, link == nil {
      let link = CADisplayLink(target: WeakTarget(self), selector: #selector(WeakTarget.tick(_:)))
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
      link.add(to: .main, forMode: .common)
      self.link = link
    } else if !running, let link {
      link.invalidate()
      self.link = nil
    }
  }

  /// The display link holds its target strongly.
  private final class WeakTarget: NSObject {
    weak var owner: MunimShapeTransitions?
    init(_ owner: MunimShapeTransitions) { self.owner = owner }
    @objc func tick(_ link: CADisplayLink) {
      if let owner { owner.tick(link) } else { link.invalidate() }
    }
  }

  // MARK: Interpolation

  static func progress(start: CFTimeInterval, duration: CFTimeInterval, at time: CFTimeInterval) -> Double {
    duration > 0 ? min(1, max(0, (time - start) / duration)) : 1
  }

  static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

  /// Longitude the short way round the antimeridian.
  static func lerpLongitude(_ a: Double, _ b: Double, _ t: Double) -> Double {
    var delta = (b - a).truncatingRemainder(dividingBy: 360)
    if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }
    var value = a + delta * t
    if value > 180 { value -= 360 } else if value < -180 { value += 360 }
    return value
  }

  static func lerp(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ t: Double) -> CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: lerp(a.latitude, b.latitude, t), longitude: lerpLongitude(a.longitude, b.longitude, t))
  }

  private static func circle(_ run: Run<MunimCircle>, at time: CFTimeInterval) -> MunimCircle {
    let t = progress(start: run.start, duration: run.duration, at: time)
    if t >= 1 { return run.to }
    var c = run.to
    c.latitude = lerp(run.from.latitude, run.to.latitude, t)
    c.longitude = lerpLongitude(run.from.longitude, run.to.longitude, t)
    c.radius = lerp(run.from.radius, run.to.radius, t)
    return c
  }

  private static func polygon(_ run: Run<MunimPolygon>, at time: CFTimeInterval) -> MunimPolygon {
    let t = progress(start: run.start, duration: run.duration, at: time)
    if t >= 1 { return run.to }
    var p = run.to
    p.coordinates = zip(run.from.coordinates, run.to.coordinates).map { lerp($0, $1, t) }
    p.holes = zip(run.from.holes, run.to.holes).map { from, to in zip(from, to).map { lerp($0, $1, t) } }
    return p
  }

  /// Same number of rings and vertices, so vertices can move pairwise.
  static func sameShape(_ a: MunimPolygon, _ b: MunimPolygon) -> Bool {
    a.coordinates.count == b.coordinates.count && a.holes.map(\.count) == b.holes.map(\.count)
  }

  static func sameGeometry(_ a: MunimCircle, _ b: MunimCircle) -> Bool {
    a.latitude == b.latitude && a.longitude == b.longitude && a.radius == b.radius
  }

  static func sameGeometry(_ a: MunimPolygon, _ b: MunimPolygon) -> Bool {
    func same(_ x: [CLLocationCoordinate2D], _ y: [CLLocationCoordinate2D]) -> Bool {
      x.count == y.count && zip(x, y).allSatisfy { $0.latitude == $1.latitude && $0.longitude == $1.longitude }
    }
    return same(a.coordinates, b.coordinates) && a.holes.count == b.holes.count
      && zip(a.holes, b.holes).allSatisfy { same($0, $1) }
  }
}
