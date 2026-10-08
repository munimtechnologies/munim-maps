#if MUNIM_MAPS_GOOGLE3D && canImport(GoogleMaps3D) && canImport(GoogleMaps)
import CoreLocation
import CryptoKit
import GoogleMaps3D
import SwiftUI
import UIKit

// The Google engine's photorealistic 3D mode on the Maps 3D SDK for iOS
// (`GoogleMaps3D`, Google's Swift package, added by the
// `NitroMunimMaps/Google3D` subspec). The SDK's map is a SwiftUI view, so it
// is hosted in a `UIHostingController` inside the Google engine's UIKit
// view: munim-maps' models become Google glTF `Model`s, polylines, polygons
// and markers Google's own, and the camera Google's (`range` = munim-maps'
// camera distance). Needs the Map Tiles API and the Maps 3D SDK for iOS
// turned on for the key.

/// The 3D mode the Google engine switches to for `google.mode: '3d'`.
final class GoogleMap3DMode: Google3DMode {
  private weak var engine: GoogleMapEngine?
  private let scene: Google3DScene
  private let host: Google3DHostingView
  var view: UIView { host }

  private var options = GoogleJSON([String: Any]())
  private var models: [MunimModel] = []
  private var destroyed = false

  /// glTF files Google can read, by model URI and tint: the cached download,
  /// or a recoloured copy for `tint`.
  private var files: [String: URL] = [:]
  private var infos: [String: GLBInfo] = [:]
  private var loading = Set<String>()
  private var reportedErrors = Set<String>()
  private var motionLink: CADisplayLink?
  private var lastScales: [String: Double] = [:]

  init(engine: GoogleMapEngine, camera: MunimCamera?) {
    self.engine = engine
    GoogleMaps3D.Map.apiKey = MunimMapsConfiguration.shared.googleMapsApiKey
    let start = camera.map(Self.google) ?? GoogleMaps3D.Camera(
      center: LatLngAltitude(latitude: 0, longitude: 0, altitude: 0), range: 20_000_000)
    scene = Google3DScene(camera: start)
    host = Google3DHostingView(scene: scene)
    scene.owner = self
    host.onWindow = { [weak self] in self?.scene.viewAppeared() }
  }

  func destroy() {
    guard !destroyed else { return }
    destroyed = true
    motionLink?.invalidate()
    motionLink = nil
    scene.stop()
    host.detach()
  }

  // MARK: Events from the scene

  fileprivate func ready() {
    engine?.map3dReady()
  }

  fileprivate func emit(_ name: String, _ data: [String: Any] = [:]) {
    engine?.emit(name, data)
  }

  fileprivate func cameraChanged(_ camera: GoogleMaps3D.Camera, idle: Bool) {
    engine?.map3dCameraChanged(Self.munim(camera), idle: idle)
    // Screen-sized models are resized when the camera stops: a resize makes
    // Google load the model again (see `publish`).
    if idle { updateScales() }
  }

  fileprivate func tapped(_ info: MapTapInfo) {
    let coordinate = CLLocationCoordinate2D(latitude: info.location.latitude, longitude: info.location.longitude)
    switch info.content {
    case .place(let id): engine?.map3dPress(coordinate, placeId: id)
    default: engine?.map3dPress(coordinate, placeId: nil)
    }
  }

  fileprivate func modelTapped(_ id: String) { engine?.map3dModelPressed(id) }
  fileprivate func markerTapped(_ id: String) { engine?.map3dMarkerPressed(id) }

  private func error(_ message: String) {
    guard reportedErrors.insert(message).inserted else { return }
    engine?.map3dError(message)
  }

  // MARK: Options

  func setOptions(_ options: GoogleJSON) {
    let scaleChanged = options["modelScale"].double != self.options["modelScale"].double
    self.options = options
    let satellite = options["mapType"].string == "satellite" || options["map3dMode"].string == "satellite"
    let mode: MapMode = satellite ? .satellite : .hybrid
    if scene.mode != mode { scene.mode = mode }
    if scaleChanged { applyModels() }
  }

  // MARK: Camera

  static func google(_ c: MunimCamera) -> GoogleMaps3D.Camera {
    GoogleMaps3D.Camera(
      center: LatLngAltitude(latitude: c.latitude, longitude: c.longitude, altitude: 0),
      heading: c.heading, tilt: min(max(c.pitch, 0), 90), roll: 0, range: max(1, c.distance))
  }

  static func munim(_ c: GoogleMaps3D.Camera) -> MunimCamera {
    MunimCamera(latitude: c.center.latitude, longitude: c.center.longitude, distance: c.range,
                pitch: c.tilt, heading: c.heading)
  }

  var camera: MunimCamera? { Self.munim(scene.knownCamera) }

  func setCamera(_ camera: MunimCamera, duration: TimeInterval) {
    let target = Self.google(camera)
    if duration > 0 { scene.fly(to: target, duration: duration) } else { scene.jump(to: target) }
  }

  // MARK: Models (Google glTF models)

  func setModels(_ models: [MunimModel]) {
    self.models = models
    applyModels()
  }

  private static func isGLTF(_ uri: String) -> Bool {
    let path = (URL(string: uri)?.path ?? uri).lowercased()
    return path.hasSuffix(".glb") || path.hasSuffix(".gltf")
  }

  private static func fileKey(_ model: MunimModel) -> String { model.uri + "|" + model.tintColor }

  private func applyModels() {
    guard !destroyed else { return }
    var items: [Google3DScene.ModelItem] = []
    let now = Date().timeIntervalSince1970
    for model in models where model.visible {
      guard !model.uri.isEmpty else {
        error("Google 3D draws glTF models only; built-in shapes, pictures and labels need the 2D map with the munim overlay")
        continue
      }
      guard Self.isGLTF(model.uri) else {
        error("Google 3D draws glTF / GLB models only (\(URL(string: model.uri)?.lastPathComponent ?? model.uri))")
        continue
      }
      guard let url = files[Self.fileKey(model)] else {
        load(model)
        continue
      }
      items.append(item(model, url: url, now: now))
    }
    publish(items, inPlace: false)
    lastScales = Dictionary(items.map { ($0.id, $0.scale) }, uniquingKeysWith: { a, _ in a })
    updateClock()
  }

  private func item(_ model: MunimModel, url: URL, now: Double) -> Google3DScene.ModelItem {
    let pose = model.pose(at: now)
    var heading = pose.heading
    if model.spinDegreesPerSecond != 0 {
      heading += (model.spinDegreesPerSecond * now).truncatingRemainder(dividingBy: 360)
    }
    // munim-maps' glTF models face -Z; Google turns their +Z to the heading
    // (checked on an iPad: heading 0 drew the bus facing south without this).
    heading = ((heading + 180).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    return Google3DScene.ModelItem(
      id: model.id,
      position: LatLngAltitude(latitude: pose.latitude, longitude: pose.longitude, altitude: pose.altitude),
      url: url,
      altitudeMode: model.altitudeReference == .sea ? .absolute : .relativeToGround,
      scale: scale(model, pose: pose),
      heading: heading)
  }

  /// `scale` × `google.modelScale`, and for `screenSize` the scale that
  /// makes the model that many points tall at its distance from Google's
  /// camera (35° vertical field of view), like the 3D layer.
  private func scale(_ model: MunimModel, pose: MunimPose) -> Double {
    var scale = options["modelScale"].double(1) * (model.scale > 0 ? model.scale : 1)
    guard model.screenSize > 0, let height = infos[model.uri]?.height, height > 0,
          host.bounds.height > 0 else { return scale }
    let c = scene.knownCamera
    let tilt = c.tilt * .pi / 180
    let heading = c.heading * .pi / 180
    let back = c.range * sin(tilt)
    let metresPerDegree = 111_320.0
    let north = (pose.latitude - c.center.latitude) * metresPerDegree
    let east = (pose.longitude - c.center.longitude) * metresPerDegree * cos(c.center.latitude * .pi / 180)
    let eye = (north: -back * cos(heading), east: -back * sin(heading), up: c.range * cos(tilt))
    let depth = max(1, sqrt(pow(north - eye.north, 2) + pow(east - eye.east, 2) + pow(pose.altitude - eye.up, 2)))
    let fov = c.fieldOfView.radians > 0 ? c.fieldOfView.radians : 35 * .pi / 180
    let metresPerPoint = 2 * depth * tan(fov / 2) / Double(host.bounds.height)
    scale *= model.screenSize * metresPerPoint / height
    return scale
  }

  /// Screen-sized models follow the camera's distance.
  private func updateScales() {
    guard models.contains(where: { $0.screenSize > 0 }), motionLink == nil else { return }
    let now = Date().timeIntervalSince1970
    var changed = false
    var items = scene.models
    for i in items.indices {
      guard let model = models.first(where: { $0.id == items[i].id }), model.screenSize > 0 else { continue }
      let s = scale(model, pose: model.pose(at: now))
      if let old = lastScales[model.id], abs(s / max(old, 1e-9) - 1) < 0.03 { continue }
      items[i].scale = s
      lastScales[model.id] = s
      changed = true
    }
    if changed { publish(items, inPlace: false) }
  }

  /// Hands the models to the map. The Maps 3D SDK (1.0) applies a change to
  /// a model it already shows one SwiftUI update late (measured on an iPad:
  /// every nudge of position, heading or scale showed the previous one), so
  /// a still model that changes is shown as a new model (a new identity in
  /// the `ForEach`), which Google draws exactly. Models moving on the frame
  /// clock (`inPlace`) are updated in place, where one frame late is not
  /// visible.
  private func publish(_ items: [Google3DScene.ModelItem], inPlace: Bool) {
    let previous = Dictionary(scene.models.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    scene.models = items.map { item in
      var item = item
      guard let old = previous[item.id] else { return item }
      item.generation = old.generation
      if !inPlace, !old.sameLook(as: item) { item.generation += 1 }
      return item
    }
  }

  /// Downloads (into munim-maps' cache) and, with `tint`, recolours the
  /// model's `paint*` materials in a copy Google reads.
  private func load(_ model: MunimModel) {
    let key = Self.fileKey(model)
    guard !loading.contains(key) else { return }
    loading.insert(key)
    let uri = model.uri
    let tint = UIColor(mapModelHex: model.tintColor)
    MapModelNodes.resolveLocalURL(uri: uri) { [weak self] result in
      DispatchQueue.global(qos: .utility).async {
        var file: URL?
        var info: GLBInfo?
        var failure: String?
        switch result {
        case .success(let url):
          let data = try? Data(contentsOf: url)
          info = data.flatMap(GLBInfo.parse)
          file = url
          if let tint, let data {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            tint.getRed(&r, green: &g, blue: &b, alpha: &a)
            if let tinted = GLBInfo.tinted(data, rgba: [Double(r), Double(g), Double(b), Double(a)]) {
              let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
              let copy = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("munim-maps", isDirectory: true)
                .appendingPathComponent("google3d-\(name).glb")
              try? FileManager.default.createDirectory(
                at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
              if (try? tinted.write(to: copy, options: .atomic)) != nil { file = copy }
            }
          }
        case .failure(let error):
          failure = error.localizedDescription
        }
        DispatchQueue.main.async {
          guard let self, !self.destroyed else { return }
          self.loading.remove(key)
          if let info { self.infos[uri] = info }
          if let file {
            self.files[key] = file
            self.applyModels()
          } else {
            self.error("could not load the model \(uri): \(failure ?? "no data")")
          }
        }
      }
    }
  }

  /// Models with `motion` or spin move on the frame clock.
  private func updateClock() {
    let needsFrames = models.contains { $0.visible && ($0.motion.count > 1 || $0.spinDegreesPerSecond != 0) }
    if needsFrames, motionLink == nil {
      let link = CADisplayLink(target: Google3DTarget(self), selector: #selector(Google3DTarget.tick))
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
      link.add(to: .main, forMode: .common)
      motionLink = link
    } else if !needsFrames {
      motionLink?.invalidate()
      motionLink = nil
    }
  }

  fileprivate func tick() {
    let now = Date().timeIntervalSince1970
    let byId = Dictionary(models.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    publish(scene.models.map { current in
      guard let model = byId[current.id] else { return current }
      return item(model, url: current.url, now: now)
    }, inPlace: true)
  }

  // MARK: Markers, polylines, polygons

  func setMarkers(_ markers: [MunimMarker]) {
    scene.markers = markers.filter(\.visible).sorted { $0.id < $1.id }.map { m in
      Google3DScene.MarkerItem(
        id: m.id, position: LatLngAltitude(latitude: m.latitude, longitude: m.longitude, altitude: 0),
        label: m.title, color: UIColor(mapModelHex: m.color), zIndex: Int32(clamping: Int(m.zIndex)))
    }
  }

  func setPolylines(_ polylines: [MunimPolyline]) {
    scene.polylines = polylines.filter { $0.coordinates.count >= 2 }.map { p in
      Google3DScene.PolylineItem(
        id: p.id, path: p.coordinates.map { LatLngAltitude(latitude: $0.latitude, longitude: $0.longitude, altitude: 0) },
        color: UIColor(mapModelHex: p.strokeColor) ?? .systemBlue, width: p.strokeWidth, geodesic: p.geodesic,
        zIndex: Int32(clamping: Int(p.zIndex)))
    }
  }

  func setPolygons(_ polygons: [MunimPolygon]) {
    scene.polygons = polygons.filter { $0.coordinates.count >= 3 }.map { p in
      func ring(_ points: [CLLocationCoordinate2D]) -> [LatLngAltitude] {
        points.map { LatLngAltitude(latitude: $0.latitude, longitude: $0.longitude, altitude: 0) }
      }
      return Google3DScene.PolygonItem(
        id: p.id, path: ring(p.coordinates), holes: p.holes.map(ring),
        fill: UIColor(mapModelHex: p.fillColor) ?? UIColor.systemBlue.withAlphaComponent(0.2),
        stroke: UIColor(mapModelHex: p.strokeColor) ?? .systemBlue, width: p.strokeWidth,
        zIndex: Int32(clamping: Int(p.zIndex)))
    }
  }

  // MARK: Commands

  func command(_ name: String, _ args: GoogleJSON, completion: @escaping (Result<Any, Error>) -> Void) -> Bool {
    func camera() -> GoogleMaps3D.Camera {
      let current = scene.knownCamera
      return GoogleMaps3D.Camera(
        center: LatLngAltitude(
          latitude: args["latitude"].double(current.center.latitude),
          longitude: args["longitude"].double(current.center.longitude),
          altitude: args["altitude"].double(current.center.altitude)),
        heading: args["heading"].double(current.heading), tilt: args["tilt"].double(current.tilt),
        roll: args["roll"].double(current.roll), range: max(1, args["range"].double(current.range)))
    }
    switch name {
    case "flyTo":
      scene.fly(to: camera(), duration: max(0.001, args["duration"].double(2000) / 1000))
    case "flyAround":
      scene.fly(around: camera(), duration: max(0.001, args["duration"].double(10000) / 1000),
                rounds: args["rounds"].double(1))
    case "stopCameraAnimation":
      scene.stopFlight()
    case "getCamera3d":
      let c = scene.knownCamera
      completion(.success([
        "latitude": c.center.latitude, "longitude": c.center.longitude, "altitude": c.center.altitude,
        "heading": c.heading, "tilt": c.tilt, "roll": c.roll, "range": c.range,
      ]))
      return true
    case "setCamera3d":
      scene.jump(to: camera())
    case "map3dDiagnostics":
      completion(.success(scene.debugInfo()))
      return true
    default:
      return false
    }
    completion(.success(NSNull()))
    return true
  }
}

/// What the SwiftUI map shows. Content is published (SwiftUI redraws the
/// map's content when it changes); the camera is not: Google writes it
/// through the binding on every gesture frame, and munim-maps only bumps
/// `cameraRevision` when it moves the camera itself.
final class Google3DScene: ObservableObject {
  struct ModelItem: Identifiable {
    let id: String
    var position: LatLngAltitude
    var url: URL
    var altitudeMode: AltitudeMode
    var scale: Double
    var heading: Double
    /// Bumped when a still model changes, so the map makes it again.
    var generation = 0
    var key: String { "\(id)#\(generation)" }

    func sameLook(as other: ModelItem) -> Bool {
      position == other.position && url == other.url && altitudeMode == other.altitudeMode
        && scale == other.scale && heading == other.heading
    }
  }

  // Markers, polylines and polygons are identified by their whole value, so
  // a changed one is drawn anew (see `GoogleMap3DMode.publish`).

  struct MarkerItem: Identifiable, Hashable {
    let id: String
    var position: LatLngAltitude
    var label: String
    var color: UIColor?
    var zIndex: Int32
  }

  struct PolylineItem: Identifiable, Hashable {
    let id: String
    var path: [LatLngAltitude]
    var color: UIColor
    var width: Double
    var geodesic: Bool
    var zIndex: Int32
  }

  struct PolygonItem: Identifiable, Hashable {
    let id: String
    var path: [LatLngAltitude]
    var holes: [[LatLngAltitude]]
    var fill: UIColor
    var stroke: UIColor
    var width: Double
    var zIndex: Int32
  }

  @Published var mode: MapMode = .hybrid
  @Published var models: [ModelItem] = []
  @Published var markers: [MarkerItem] = []
  @Published var polylines: [PolylineItem] = []
  @Published var polygons: [PolygonItem] = []
  /// Bumped when munim-maps moves the camera, so the map reads the binding again.
  @Published private(set) var cameraRevision = 0

  /// The binding's value: what the map last reported, or what munim-maps set.
  private(set) var camera: GoogleMaps3D.Camera
  /// The camera as munim-maps knows it: what it set last (each frame of a
  /// flight), or what the map reported after a gesture.
  private(set) var knownCamera: GoogleMaps3D.Camera
  /// munim-maps' own flight (`flyTo`, `flyAround`, animated camera moves),
  /// stepped once a frame through the binding. The SDK's `flyCameraTo` /
  /// `flyCameraAround` modifiers fly to the camera of the previous SwiftUI
  /// update (measured on an iPad: the first flight went to the map's
  /// starting camera), and cannot be stopped.
  private var flight: Google3DFlight?
  private var flightLink: CADisplayLink?
  private var flying: Bool { flight != nil }

  weak var owner: GoogleMap3DMode?
  private var readyReported = false
  private var readyTimer: Timer?
  private var idleTimer: Timer?
  private var moving = false
  private var mapWrites = 0
  private var log: [String] = []

  init(camera: GoogleMaps3D.Camera) {
    self.camera = camera
    knownCamera = camera
  }

  func stop() {
    flightLink?.invalidate()
    flightLink = nil
    flight = nil
    readyTimer?.invalidate()
    idleTimer?.invalidate()
    owner = nil
  }

  private func note(_ line: String) {
    log.append(line)
    if log.count > 80 { log.removeFirst(log.count - 80) }
  }

  // The SDK has no ready callback on iOS: the map is ready when it first
  // reports its camera, or a moment after it is on screen.
  func viewAppeared() {
    guard !readyReported, readyTimer == nil else { return }
    readyTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
      self?.markReady("appeared")
    }
  }

  private func markReady(_ reason: String) {
    guard !readyReported else { return }
    readyReported = true
    readyTimer?.invalidate()
    note("ready (\(reason))")
    owner?.ready()
  }

  /// Google moved the camera (a gesture), or echoed one munim-maps set.
  func cameraFromMap(_ value: GoogleMaps3D.Camera) {
    mapWrites += 1
    let echo = Self.close(value, camera, loose: true)
    if !echo || mapWrites <= 3 { note("map wrote camera \(Self.describe(value))\(flying ? " (flying)" : "")") }
    markReady("camera")
    guard !echo else { return }
    // A gesture ends munim-maps' flight, like the SDK's own.
    if flying { endFlight(completed: false) }
    camera = value
    knownCamera = value
    if !moving {
      moving = true
      owner?.emit("map3dSteady", ["steady": false])
    }
    owner?.cameraChanged(value, idle: false)
    scheduleIdle()
  }

  private func scheduleIdle() {
    idleTimer?.invalidate()
    idleTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
      guard let self, !self.flying else { return }
      self.moving = false
      self.owner?.emit("map3dSteady", ["steady": true])
      self.owner?.cameraChanged(self.knownCamera, idle: true)
    }
  }

  /// Sets the camera the map reads from the binding.
  private func show(_ target: GoogleMaps3D.Camera) {
    camera = target
    knownCamera = target
    cameraRevision += 1
  }

  /// Moves the camera at once.
  func jump(to target: GoogleMaps3D.Camera) {
    if flying { endFlight(completed: false) }
    show(target)
    note("jump to \(Self.describe(target))")
    owner?.cameraChanged(target, idle: true)
  }

  /// Flies to `target` over `duration` seconds: centre, heading, tilt and
  /// roll eased, range eased in log space and raised mid-flight when the
  /// centre moves far, like Google's own flights.
  func fly(to target: GoogleMaps3D.Camera, duration: TimeInterval) {
    start(Google3DFlight(from: knownCamera, to: target, duration: duration, rounds: 0))
    note("fly to \(Self.describe(target)) over \(duration) s")
  }

  /// Circles `target`'s centre `rounds` times (heading +360° a round) over `duration` seconds.
  func fly(around target: GoogleMaps3D.Camera, duration: TimeInterval, rounds: Double) {
    start(Google3DFlight(from: target, to: target, duration: duration, rounds: rounds))
    note("fly around \(Self.describe(target)) \(rounds)x over \(duration) s")
  }

  private func start(_ next: Google3DFlight) {
    let wasFlying = flying
    flight = next
    if flightLink == nil {
      let link = CADisplayLink(target: Google3DSceneTarget(self), selector: #selector(Google3DSceneTarget.tick))
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
      link.add(to: .main, forMode: .common)
      flightLink = link
    }
    idleTimer?.invalidate()
    if !wasFlying, !moving {
      moving = true
      owner?.emit("map3dSteady", ["steady": false])
    }
    step()
  }

  /// Stops a flight where it is.
  func stopFlight() {
    guard flying else { return }
    note("stopped at \(Self.describe(knownCamera))")
    endFlight(completed: false)
  }

  fileprivate func step() {
    guard let flight else { return }
    let (camera, done) = flight.camera(at: CACurrentMediaTime())
    show(camera)
    owner?.cameraChanged(camera, idle: false)
    if done { endFlight(completed: true) }
  }

  private func endFlight(completed: Bool) {
    flight = nil
    flightLink?.invalidate()
    flightLink = nil
    if completed { note("flight ended at \(Self.describe(knownCamera))") }
    owner?.emit("cameraAnimationEnd")
    moving = false
    owner?.emit("map3dSteady", ["steady": true])
    owner?.cameraChanged(knownCamera, idle: true)
  }

  func debugInfo() -> [String: Any] {
    ["mapWrites": mapWrites, "flying": flying, "ready": readyReported, "log": log,
     "binding": Self.describe(camera), "known": Self.describe(knownCamera),
     "markers": markers.count, "polylines": polylines.count, "polygons": polygons.count,
     "models": models.map { ["id": $0.id, "url": $0.url.absoluteString, "scale": $0.scale, "heading": $0.heading] }]
  }

  /// Whether two cameras are the same view (`loose`: as the SDK reports
  /// back a camera it was given, rounded).
  static func close(_ a: GoogleMaps3D.Camera, _ b: GoogleMaps3D.Camera, loose: Bool = false) -> Bool {
    let degrees = loose ? 1e-6 : 1e-9
    let angle = loose ? 0.05 : 1e-6
    let turn = abs((a.heading - b.heading + 540).truncatingRemainder(dividingBy: 360) - 180)
    return abs(a.center.latitude - b.center.latitude) < degrees && abs(a.center.longitude - b.center.longitude) < degrees
      && abs(a.center.altitude - b.center.altitude) < (loose ? 0.5 : 1e-3) && turn < angle
      && abs(a.tilt - b.tilt) < angle && abs(a.range - b.range) < max(1e-3, loose ? b.range * 1e-4 : 0)
      && abs(a.roll - b.roll) < angle
  }

  static func describe(_ c: GoogleMaps3D.Camera) -> String {
    String(format: "%.5f,%.5f alt %.0f h %.1f t %.1f r %.0f", c.center.latitude, c.center.longitude,
           c.center.altitude, c.heading, c.tilt, c.range)
  }
}

/// Google's SwiftUI 3D map with munim-maps' content.
struct Google3DMapView: View {
  @ObservedObject var scene: Google3DScene

  var body: some View {
    let scene = self.scene
    let _ = scene.cameraRevision
    let binding = Binding<GoogleMaps3D.Camera>(
      get: { [scene] in scene.camera },
      set: { [scene] value in scene.cameraFromMap(value) })
    GoogleMaps3D.Map(camera: binding, mode: scene.mode) {
      ForEach(scene.models, id: \.key) { item in
        GoogleMaps3D.Model(
          position: item.position, url: item.url, altitudeMode: item.altitudeMode,
          scale: Vector3D(x: item.scale, y: item.scale, z: item.scale),
          // Google reads glTF files Z-up; munim-maps' (like every glTF) are
          // Y-up, so they are stood up: tilt -90 (checked on an iPad, +90
          // put them upside down under the street).
          orientation: Orientation3D(heading: item.heading, tilt: -90, roll: 0)
        )
        .onTap { [weak scene] in scene?.owner?.modelTapped(item.id) }
      }
      ForEach(scene.polygons, id: \.self) { item in
        GoogleMaps3D.Polygon(path: item.path, innerPaths: item.holes, altitudeMode: .clampToGround, zIndex: item.zIndex)
          .style(GoogleMaps3D.Polygon.StyleOptions(
            fillColor: item.fill, strokeColor: item.stroke, strokeWidth: item.width, drawsOccludedSegments: true))
      }
      ForEach(scene.polylines, id: \.self) { item in
        GoogleMaps3D.Polyline(path: item.path, altitudeMode: .clampToGround, zIndex: item.zIndex)
          .stroke(GoogleMaps3D.Polyline.StrokeStyle(strokeColor: item.color, strokeWidth: item.width))
          .contour(GoogleMaps3D.Polyline.ContourStyle(geodesic: item.geodesic, drawOccludedSegments: true))
      }
      ForEach(scene.markers, id: \.self) { item in
        GoogleMaps3D.Marker3D(
          position: item.position, altitudeMode: .clampToGround, drawsWhenOccluded: true,
          zIndex: item.zIndex, label: item.label, style: Self.style(item.color))
        .onTap { [weak scene] in scene?.owner?.markerTapped(item.id) }
      }
    }
    .onTap { [weak scene] info in scene?.owner?.tapped(info) }
    .ignoresSafeArea()
  }

  private static func style(_ color: UIColor?) -> Marker3D.Style {
    guard let color else { return .default }
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    let border = UIColor(hue: h, saturation: s, brightness: b * 0.8, alpha: a)
    return .pin(Pin.Configuration(backgroundColor: Color(uiColor: color), borderColor: Color(uiColor: border)))
  }
}

/// The UIKit view the Google engine shows: hosts the SwiftUI map, and adds
/// its hosting controller to the nearest view controller once on screen.
final class Google3DHostingView: UIView {
  private let controller: UIHostingController<Google3DMapView>
  var onWindow: (() -> Void)?

  init(scene: Google3DScene) {
    controller = UIHostingController(rootView: Google3DMapView(scene: scene))
    super.init(frame: .zero)
    clipsToBounds = true
    backgroundColor = .black
    if #available(iOS 16.4, *) { controller.safeAreaRegions = [] }
    controller.view.backgroundColor = .black
    controller.view.frame = bounds
    controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(controller.view)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    guard window != nil else { return }
    if controller.parent == nil, let parent = nearestViewController() {
      parent.addChild(controller)
      controller.didMove(toParent: parent)
    }
    onWindow?()
  }

  private func nearestViewController() -> UIViewController? {
    var responder: UIResponder? = superview
    while let current = responder {
      if let controller = current as? UIViewController { return controller }
      responder = current.next
    }
    return nil
  }

  func detach() {
    onWindow = nil
    if controller.parent != nil {
      controller.willMove(toParent: nil)
      controller.removeFromParent()
    }
  }
}

/// A camera flight munim-maps steps itself (see `Google3DScene.flight`).
struct Google3DFlight {
  let from: GoogleMaps3D.Camera
  let to: GoogleMaps3D.Camera
  let duration: TimeInterval
  /// Above 0: circle `to`'s centre this many times instead of flying.
  let rounds: Double
  let start = CACurrentMediaTime()

  func camera(at time: CFTimeInterval) -> (GoogleMaps3D.Camera, done: Bool) {
    let x = duration > 0 ? min(1, max(0, (time - start) / duration)) : 1
    if rounds > 0 {
      var c = to
      c.heading = (to.heading + 360 * rounds * x).truncatingRemainder(dividingBy: 360)
      return (c, x >= 1)
    }
    let e = x * x * (3 - 2 * x)
    func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * e }
    let turn = ((to.heading - from.heading).truncatingRemainder(dividingBy: 360) + 540)
      .truncatingRemainder(dividingBy: 360) - 180
    var c = to
    c.center = LatLngAltitude(
      latitude: mix(from.center.latitude, to.center.latitude),
      longitude: mix(from.center.longitude, to.center.longitude),
      altitude: mix(from.center.altitude, to.center.altitude))
    c.heading = ((from.heading + turn * e).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    c.tilt = mix(from.tilt, to.tilt)
    c.roll = mix(from.roll, to.roll)
    let a = log(max(1, from.range))
    let b = log(max(1, to.range))
    var range = exp(a + (b - a) * e)
    // Far flights rise to see both ends on the way.
    let north = (to.center.latitude - from.center.latitude) * 111_320
    let east = (to.center.longitude - from.center.longitude) * 111_320 * cos(from.center.latitude * .pi / 180)
    let ground = (north * north + east * east).squareRoot()
    range += max(0, ground - max(from.range, to.range)) * sin(.pi * e)
    c.range = range
    return (c, x >= 1)
  }
}

/// Breaks the retain cycle between the flight's `CADisplayLink` and the scene.
private final class Google3DSceneTarget: NSObject {
  weak var owner: Google3DScene?
  init(_ owner: Google3DScene) { self.owner = owner }
  @objc func tick() { owner?.step() }
}

/// Breaks the retain cycle between the motion `CADisplayLink` and the mode.
private final class Google3DTarget: NSObject {
  weak var owner: GoogleMap3DMode?
  init(_ owner: GoogleMap3DMode) { self.owner = owner }
  @objc func tick() { owner?.tick() }
}
#endif
