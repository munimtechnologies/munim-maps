import MapKit
import Metal
import QuartzCore
import SceneKit
import UIKit
import simd

/// The view a renderer draws into. It never takes touches, so the map under
/// it keeps every gesture.
final class MapModelHostView: UIView {
  var onWindowChange: (() -> Void)?
  var onLayout: (() -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    backgroundColor = .clear
    isOpaque = false
    clipsToBounds = true
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    onWindowChange?()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?()
  }
}

/// Draws 3D models over an `MKMapView`, matching its camera.
///
/// The models are rendered by SceneKit into a Metal layer that lies exactly
/// over the map. The SceneKit camera is rebuilt from the map's camera at the
/// end of each run-loop pass (an observer that runs just before Core
/// Animation commits), SceneKit's transaction is flushed so the frame really
/// uses those positions, and the drawable is presented straight from the
/// GPU. Measured against MapKit's own overlays mid-animation, the models land
/// in the same frame as the map.
final class MapModelRenderer: NSObject, UIGestureRecognizerDelegate {
  let hostView: MapModelHostView

  var onModelPress: ((String) -> Void)?
  var onError: ((String) -> Void)?

  var lighting: MapModelLighting = .auto {
    didSet { setNeedsRender() }
  }

  var maxCameraDistance: Double = 50_000 {
    didSet { setNeedsRender() }
  }

  private(set) weak var mapView: MKMapView?

  private let metalLayer = CAMetalLayer()
  private let device: MTLDevice?
  private let commandQueue: MTLCommandQueue?
  private let sceneRenderer: SCNRenderer?
  private let scene = SCNScene()
  private let cameraNode = SCNNode()
  private let modelsRoot = SCNNode()
  private let ambientLight = SCNNode()
  private let sunLight = SCNNode()

  private var entries: [String: Entry] = [:]
  private var zoneEntries: [String: ZoneEntry] = [:]
  private let zonesRoot = SCNNode()
  private var tapRecognizer: UITapGestureRecognizer?
  private var displayLink: CADisplayLink?
  private var commitObserver: CFRunLoopObserver?
  private var lastRendered: MapCameraSnapshot?
  private var lastSnapshot: MapCameraSnapshot?
  private var needsRender = true
  private var animationsActive = false
  private var colorTexture: MTLTexture?
  private var depthTexture: MTLTexture?
  private var reportedRenderError = false
  private var nightLighting = false

  private static let sampleCount = 4

  init(hostView: MapModelHostView) {
    self.hostView = hostView
    device = MTLCreateSystemDefaultDevice()
    commandQueue = device?.makeCommandQueue()
    sceneRenderer = device.map { SCNRenderer(device: $0, options: nil) }
    super.init()

    metalLayer.device = device
    metalLayer.pixelFormat = .bgra8Unorm_srgb
    metalLayer.isOpaque = false
    metalLayer.framebufferOnly = true
    metalLayer.allowsNextDrawableTimeout = true
    metalLayer.backgroundColor = UIColor.clear.cgColor
    hostView.layer.addSublayer(metalLayer)

    let camera = SCNCamera()
    camera.automaticallyAdjustsZRange = false
    cameraNode.camera = camera
    scene.rootNode.addChildNode(cameraNode)
    scene.rootNode.addChildNode(modelsRoot)
    scene.rootNode.addChildNode(zonesRoot)

    ambientLight.light = SCNLight()
    ambientLight.light?.type = .ambient
    scene.rootNode.addChildNode(ambientLight)

    let sun = SCNLight()
    sun.type = .directional
    sun.castsShadow = false
    sunLight.light = sun
    // Afternoon sun from the south-west.
    sunLight.simdOrientation = simd_quatf(angle: -.pi / 4, axis: SIMD3(0, 1, 0))
      * simd_quatf(angle: -.pi / 3, axis: SIMD3(1, 0, 0))
    scene.rootNode.addChildNode(sunLight)

    scene.lightingEnvironment.contents = MapModelNodes.environmentImage
    applyLighting(night: false)

    if let sceneRenderer {
      sceneRenderer.scene = scene
      sceneRenderer.pointOfView = cameraNode
      sceneRenderer.autoenablesDefaultLighting = false
      sceneRenderer.isPlaying = true
      sceneRenderer.loops = true
    }
  }

  deinit {
    stopFrameLoop()
  }

  // MARK: Attaching

  var isAttached: Bool { mapView != nil }

  func attach(to mapView: MKMapView) {
    if self.mapView === mapView { return }
    detach()
    self.mapView = mapView

    let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
    tap.cancelsTouchesInView = false
    tap.delaysTouchesEnded = false
    tap.delegate = self
    mapView.addGestureRecognizer(tap)
    tapRecognizer = tap

    if device == nil || sceneRenderer == nil {
      onError?("Metal is not available on this device, so munim-maps cannot draw models")
    }
    lastRendered = nil
    setNeedsRender()
    updateFrameLoop()
  }

  func detach() {
    if let tapRecognizer {
      tapRecognizer.view?.removeGestureRecognizer(tapRecognizer)
    }
    tapRecognizer = nil
    mapView = nil
    stopFrameLoop()
    clearDrawable()
  }

  /// Starts or stops the per-frame work depending on whether there is
  /// anything on screen to keep in step with.
  func updateFrameLoop() {
    if mapView != nil, hostView.window != nil {
      startFrameLoop()
      setNeedsRender()
    } else {
      stopFrameLoop()
    }
  }

  private func startFrameLoop() {
    if displayLink == nil {
      let link = CADisplayLink(target: DisplayLinkTarget(self), selector: #selector(DisplayLinkTarget.tick))
      link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
      link.add(to: .main, forMode: .common)
      displayLink = link
    }
    if commitObserver == nil {
      // Core Animation commits at order 2,000,000; run just before it so the
      // map has already moved for this frame.
      let observer = CFRunLoopObserverCreateWithHandler(
        kCFAllocatorDefault,
        CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.exit.rawValue,
        true,
        1_999_000
      ) { [weak self] _, _ in
        self?.renderIfNeeded()
      }
      CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
      commitObserver = observer
    }
  }

  private func stopFrameLoop() {
    displayLink?.invalidate()
    displayLink = nil
    if let commitObserver {
      CFRunLoopRemoveObserver(CFRunLoopGetMain(), commitObserver, .commonModes)
      CFRunLoopObserverInvalidate(commitObserver)
    }
    commitObserver = nil
  }

  fileprivate func displayLinkFired() {
    // Waking the run loop every frame is enough: the commit observer then
    // checks whether the camera moved. Animated models redraw every frame.
    if animationsActive { needsRender = true }
  }

  func setNeedsRender() {
    needsRender = true
  }

  // MARK: Models

  func setModels(_ models: [NativeMapModel]) {
    var seen = Set<String>()
    for model in models {
      guard !seen.contains(model.id) else {
        onError?("Duplicate model id \"\(model.id)\"; only the first is drawn")
        continue
      }
      seen.insert(model.id)
      if let entry = entries[model.id] {
        entry.update(model, renderer: self)
      } else {
        let entry = Entry(model: model)
        entries[model.id] = entry
        entry.addNodes(to: modelsRoot)
        entry.update(model, renderer: self, force: true)
      }
    }
    for (id, entry) in entries where !seen.contains(id) {
      entry.removeNodes()
      entries[id] = nil
    }
    refreshAnimationState()
    setNeedsRender()
  }

  func setZones(_ zones: [NativeMapZone]) {
    var seen = Set<String>()
    for zone in zones where !seen.contains(zone.id) {
      seen.insert(zone.id)
      if let entry = zoneEntries[zone.id] {
        entry.update(zone)
      } else {
        let entry = ZoneEntry(zone: zone)
        zoneEntries[zone.id] = entry
        zonesRoot.addChildNode(entry.node)
      }
    }
    for (id, entry) in zoneEntries where !seen.contains(id) {
      entry.node.removeFromParentNode()
      zoneEntries[id] = nil
    }
    setNeedsRender()
  }

  fileprivate func refreshAnimationState() {
    animationsActive = entries.values.contains { $0.isAnimating }
  }

  fileprivate func reportError(_ message: String) {
    onError?(message)
  }

  // MARK: Rendering

  private func renderIfNeeded() {
    guard let mapView, hostView.window != nil, !hostView.isHidden else { return }
    guard let snapshot = MapCameraSnapshot.read(
      from: mapView, previousFocalLength: lastSnapshot?.focalLength ?? 0)
    else { return }
    lastSnapshot = snapshot

    let night = resolveNight(for: mapView)
    if night != nightLighting {
      applyLighting(night: night)
      needsRender = true
    }

    if !needsRender, snapshot == lastRendered { return }
    needsRender = false
    lastRendered = snapshot
    render(snapshot, mapView: mapView)
  }

  private func render(_ snapshot: MapCameraSnapshot, mapView: MKMapView) {
    guard let device, let commandQueue, let sceneRenderer else { return }

    let scale = hostView.window?.screen.scale ?? UIScreen.main.scale
    let frame = mapView.convert(mapView.bounds, to: hostView)
    let drawableSize = CGSize(
      width: (frame.width * scale).rounded(),
      height: (frame.height * scale).rounded())
    guard drawableSize.width >= 1, drawableSize.height >= 1 else { return }

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if metalLayer.frame != frame { metalLayer.frame = frame }
    metalLayer.contentsScale = scale
    if metalLayer.drawableSize != drawableSize { metalLayer.drawableSize = drawableSize }
    CATransaction.commit()

    // SceneKit only hands node changes to its renderer when a transaction
    // flushes, normally at the end of the run loop. Flush now, or this frame
    // would draw the previous frame's positions (one frame behind the map,
    // and never catching up once the map stops).
    SCNTransaction.begin()
    SCNTransaction.disableActions = true
    updateScene(for: snapshot)
    SCNTransaction.commit()
    SCNTransaction.flush()

    guard let drawable = metalLayer.nextDrawable() else {
      // Try again on the next pass rather than leaving a stale frame up.
      needsRender = true
      return
    }
    ensureTargets(device: device, size: drawableSize)
    guard let colorTexture, let depthTexture,
          let commandBuffer = commandQueue.makeCommandBuffer()
    else { return }

    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = colorTexture
    pass.colorAttachments[0].resolveTexture = drawable.texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .multisampleResolve
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    pass.depthAttachment.texture = depthTexture
    pass.depthAttachment.loadAction = .clear
    pass.depthAttachment.storeAction = .dontCare
    pass.depthAttachment.clearDepth = 1

    sceneRenderer.render(
      atTime: CACurrentMediaTime(),
      viewport: CGRect(origin: .zero, size: drawableSize),
      commandBuffer: commandBuffer,
      passDescriptor: pass)
    // Present straight from the GPU, the way MapKit presents the map.
    // Presenting through the Core Animation transaction instead
    // (`presentsWithTransaction`) measured several frames behind the map.
    commandBuffer.present(drawable)
    commandBuffer.commit()
  }

  private func ensureTargets(device: MTLDevice, size: CGSize) {
    let width = Int(size.width)
    let height = Int(size.height)
    if let colorTexture, colorTexture.width == width, colorTexture.height == height { return }

    let color = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: metalLayer.pixelFormat, width: width, height: height, mipmapped: false)
    color.textureType = .type2DMultisample
    color.sampleCount = Self.sampleCount
    color.usage = .renderTarget
    color.storageMode = .memoryless
    colorTexture = device.makeTexture(descriptor: color)

    let depth = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
    depth.textureType = .type2DMultisample
    depth.sampleCount = Self.sampleCount
    depth.usage = .renderTarget
    depth.storageMode = .memoryless
    depthTexture = device.makeTexture(descriptor: depth)
  }

  private func clearDrawable() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    metalLayer.frame = .zero
    CATransaction.commit()
    lastRendered = nil
  }

  /// Moves the camera and every model to match `snapshot`.
  private func updateScene(for snapshot: MapCameraSnapshot) {
    cameraNode.simdTransform = snapshot.cameraTransform
    cameraNode.camera?.zNear = Double(snapshot.nearPlane)
    cameraNode.camera?.zFar = Double(snapshot.farPlane)
    cameraNode.camera?.projectionTransform = SCNMatrix4(snapshot.projection)

    let tooFar = snapshot.distance > maxCameraDistance
    modelsRoot.isHidden = tooFar
    zonesRoot.isHidden = tooFar
    if tooFar { return }

    for entry in entries.values {
      entry.place(in: snapshot)
    }
    for zone in zoneEntries.values {
      zone.place(in: snapshot)
    }
  }

  private func resolveNight(for mapView: MKMapView) -> Bool {
    switch lighting {
    case .day: return false
    case .night: return true
    case .auto: return mapView.traitCollection.userInterfaceStyle == .dark
    }
  }

  private func applyLighting(night: Bool) {
    nightLighting = night
    ambientLight.light?.intensity = night ? 180 : 420
    ambientLight.light?.color = night
      ? UIColor(red: 0.6, green: 0.68, blue: 1, alpha: 1) : UIColor.white
    sunLight.light?.intensity = night ? 220 : 1100
    sunLight.light?.color = night
      ? UIColor(red: 0.7, green: 0.78, blue: 1, alpha: 1) : UIColor(white: 1, alpha: 1)
    scene.lightingEnvironment.intensity = night ? 0.25 : 1
  }

  // MARK: Taps

  @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
    guard recognizer.state == .ended, let mapView, let snapshot = lastRendered,
          !modelsRoot.isHidden
    else { return }
    let point = recognizer.location(in: mapView)
    var best: (id: String, depth: Float)?
    for entry in entries.values {
      guard let hit = entry.hitTest(point, in: snapshot) else { continue }
      if best == nil || hit < best!.depth { best = (entry.id, hit) }
    }
    if let best { onModelPress?(best.id) }
  }

  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
  ) -> Bool { true }

  // MARK: Measuring

  /// Compares where each model's ground point is drawn with where MapKit
  /// draws the same coordinate, and checks the rendered pixels.
  func measureAlignment() -> MapAlignmentReport {
    guard let mapView,
          let snapshot = MapCameraSnapshot.read(
            from: mapView, previousFocalLength: lastSnapshot?.focalLength ?? 0)
    else {
      return MapAlignmentReport(
        attached: mapView != nil, modelsMeasured: 0, maxErrorPoints: -1,
        meanErrorPoints: -1, modelsVisibleInRender: 0, cameraDistance: 0,
        cameraPitch: 0, cameraHeading: 0, fieldOfViewDegrees: 0)
    }
    SCNTransaction.begin()
    SCNTransaction.disableActions = true
    updateScene(for: snapshot)
    SCNTransaction.commit()
    SCNTransaction.flush()

    var errors: [Double] = []
    var targets: [CGPoint] = []
    for entry in entries.values where entry.model.visible {
      let coordinate = CLLocationCoordinate2D(
        latitude: entry.model.latitude, longitude: entry.model.longitude)
      let ground = snapshot.scenePosition(
        latitude: coordinate.latitude, longitude: coordinate.longitude, altitude: 0)
      guard let ours = snapshot.project(ground)?.point else { continue }
      guard mapView.bounds.insetBy(dx: 4, dy: 4).contains(ours) else { continue }
      let theirs = mapView.convert(coordinate, toPointTo: mapView)
      errors.append(Double(hypot(ours.x - theirs.x, ours.y - theirs.y)))
      if let middle = entry.middlePoint(in: snapshot) { targets.append(middle) }
    }

    var visible = 0
    if let sceneRenderer, !targets.isEmpty {
      let size = snapshot.mapSize
      let image = sceneRenderer.snapshot(
        atTime: CACurrentMediaTime(), with: size, antialiasingMode: .none)
      for target in targets where image.mapModelAlpha(at: target) > 0.5 {
        visible += 1
      }
    }

    return MapAlignmentReport(
      attached: true,
      modelsMeasured: Double(errors.count),
      maxErrorPoints: errors.max() ?? 0,
      meanErrorPoints: errors.isEmpty ? 0 : errors.reduce(0, +) / Double(errors.count),
      modelsVisibleInRender: Double(visible),
      cameraDistance: snapshot.distance,
      cameraPitch: snapshot.pitch,
      cameraHeading: snapshot.heading,
      fieldOfViewDegrees: snapshot.fieldOfView * 180 / .pi)
  }
}

/// Breaks the retain cycle between `CADisplayLink` and its target.
private final class DisplayLinkTarget: NSObject {
  weak var owner: MapModelRenderer?

  init(_ owner: MapModelRenderer) {
    self.owner = owner
  }

  @objc func tick() {
    owner?.displayLinkFired()
  }
}

// MARK: - Entry

private final class Entry {
  let id: String
  /// Positioned on the map and turned to the model's heading.
  let root = SCNNode()
  /// Carries the spin action and the screen-size scale.
  let body = SCNNode()
  /// Line from the ground up to a floating model, and its dot on the ground.
  /// Kept outside `root` so the model's scale does not stretch them.
  let stem = MapModelNodes.stemNode(color: .white)
  let stemDot = MapModelNodes.stemNode(color: .white)
  /// Text pill above the model, kept at a fixed size on screen.
  private var labelNode: SCNNode?
  private let labelHolder = SCNNode()
  private var content: SCNNode?
  private var shadow: SCNNode?
  private(set) var model: NativeMapModel
  private var contentKey = ""
  private var loadGeneration = 0
  private var contentHeight: Float = 1
  private var contentRadius: Float = 1
  private var hasEmbeddedAnimations = false
  private var currentScale: Float = 1

  init(model: NativeMapModel) {
    id = model.id
    self.model = model
    root.addChildNode(body)
    stem.isHidden = true
    stemDot.isHidden = true
  }

  func addNodes(to parent: SCNNode) {
    parent.addChildNode(root)
    parent.addChildNode(stem)
    parent.addChildNode(stemDot)
    parent.addChildNode(labelHolder)
  }

  func removeNodes() {
    root.removeFromParentNode()
    stem.removeFromParentNode()
    stemDot.removeFromParentNode()
    labelHolder.removeFromParentNode()
  }

  /// Screen-size models and stems are resized whenever the camera moves,
  /// which already triggers a redraw, so only real motion counts here.
  var isAnimating: Bool {
    model.visible && (model.spinDegreesPerSecond != 0
      || (model.playAnimations && hasEmbeddedAnimations))
  }

  func update(_ model: NativeMapModel, renderer: MapModelRenderer, force: Bool = false) {
    let previous = self.model
    self.model = model
    root.isHidden = !model.visible

    let key = [
      model.uri, model.shape.stringValue, "\(model.width)", "\(model.height)",
      "\(model.length)", model.color, "\(model.emissive)", model.imageUri,
      model.imageBorderColor, "\(model.imageBorderWidth)", model.imageBadge,
      model.imageUri.isEmpty ? "" : "\(model.screenSize)",
    ].joined(separator: "|")
    if force || key != contentKey {
      contentKey = key
      loadContent(renderer: renderer)
    }

    if force || previous.spinDegreesPerSecond != model.spinDegreesPerSecond {
      body.removeAction(forKey: "spin")
      if model.spinDegreesPerSecond != 0 {
        let radians = CGFloat(-model.spinDegreesPerSecond * .pi / 180)
        body.runAction(.repeatForever(.rotateBy(x: 0, y: radians, z: 0, duration: 1)), forKey: "spin")
      }
    }
    if force || previous.playAnimations != model.playAnimations, let content {
      MapModelNodes.setAnimationsPlaying(model.playAnimations, in: content)
    }
    if force || previous.groundShadow != model.groundShadow {
      shadow?.isHidden = !model.groundShadow
    }
    if force || previous.tintColor != model.tintColor {
      applyTint()
    }
    if force || previous.label != model.label {
      labelNode?.removeFromParentNode()
      labelNode = model.label.isEmpty ? nil : MapModelNodes.labelNode(text: model.label)
      if let labelNode { labelHolder.addChildNode(labelNode) }
    }
    labelHolder.isHidden = !model.visible
    if force || previous.stemColor != model.stemColor {
      let color = UIColor(mapModelHex: model.stemColor) ?? .white
      stem.geometry?.firstMaterial?.diffuse.contents = color
      stemDot.geometry?.firstMaterial?.diffuse.contents = color
    }
  }

  private func loadContent(renderer: MapModelRenderer) {
    loadGeneration += 1
    let generation = loadGeneration
    if !model.imageUri.isEmpty {
      let snapshot = model
      MapModelNodes.loadImage(uri: model.imageUri) { [weak self, weak renderer] result in
        DispatchQueue.main.async {
          guard let self, let renderer, generation == self.loadGeneration else { return }
          switch result {
          case .success(let image):
            self.install(MapModelNodes.avatarNode(image: image, model: snapshot), renderer: renderer)
          case .failure(let error):
            renderer.reportError("Could not load image for \"\(self.id)\": \(error.localizedDescription)")
          }
        }
      }
      return
    }
    if model.shape != .none || model.uri.isEmpty {
      install(MapModelNodes.shapeNode(for: model), renderer: renderer)
      return
    }
    MapModelNodes.loadAsset(uri: model.uri) { [weak self, weak renderer] result in
      DispatchQueue.main.async {
        guard let self, let renderer, generation == self.loadGeneration else { return }
        switch result {
        case .success(let node):
          self.install(node, renderer: renderer)
        case .failure(let error):
          renderer.reportError("Could not load model \"\(self.id)\": \(error.localizedDescription)")
        }
      }
    }
  }

  private func install(_ node: SCNNode?, renderer: MapModelRenderer) {
    content?.removeFromParentNode()
    shadow?.removeFromParentNode()
    content = node
    shadow = nil
    guard let node else { return }
    body.addChildNode(node)

    let bounds = MapModelNodes.subtreeBounds(node)
    let minimum = bounds?.0 ?? .zero
    let maximum = bounds?.1 ?? SIMD3(1, 1, 1)
    let extent = maximum - minimum
    contentHeight = max(0.01, extent.y)
    contentRadius = max(0.01, simd_length(extent) / 2)

    let shadowNode = MapModelNodes.groundShadowNode(diameter: max(extent.x, extent.z) * 1.6)
    shadowNode.isHidden = !model.groundShadow
    body.addChildNode(shadowNode)
    shadow = shadowNode

    applyTint()
    hasEmbeddedAnimations = MapModelNodes.hasAnimations(node)
    if hasEmbeddedAnimations {
      MapModelNodes.setAnimationsPlaying(model.playAnimations, in: node)
    }
    renderer.refreshAnimationState()
    renderer.setNeedsRender()
  }

  func place(in snapshot: MapCameraSnapshot) {
    var position = snapshot.scenePosition(
      latitude: model.latitude, longitude: model.longitude, altitude: model.altitude)
    let focal = Float(snapshot.focalLength)
    if model.liftPoints != 0, let depth = snapshot.project(position)?.depth, depth > 0 {
      position.y += Float(model.liftPoints) * depth / focal
    }
    root.simdPosition = position
    root.simdOrientation = simd_quatf(angle: Float(-model.heading * .pi / 180), axis: SIMD3(0, 1, 0))

    var scale = Float(model.scale)
    if model.screenSize > 0, let depth = snapshot.project(position)?.depth, depth > 0 {
      // Height on screen is focal * height / depth.
      let targetHeight = Float(model.screenSize) * depth / Float(snapshot.focalLength)
      scale *= targetHeight / contentHeight
    }
    if scale != currentScale {
      currentScale = scale
      root.simdScale = SIMD3(repeating: scale)
    }
    placeStem(in: snapshot, top: position)
    placeLabel(in: snapshot, base: position)
  }

  /// Puts the label 22 points tall, 4 points above the top of the model.
  private func placeLabel(in snapshot: MapCameraSnapshot, base: SIMD3<Float>) {
    guard labelNode != nil, model.visible else { return }
    let top = base + SIMD3(0, (content == nil ? 0 : contentHeight) * currentScale, 0)
    let depth = max(1, snapshot.project(top)?.depth ?? Float(snapshot.distance))
    let pointsToMeters = depth / Float(snapshot.focalLength)
    labelHolder.simdPosition = top + SIMD3(0, 4 * pointsToMeters, 0)
    labelHolder.simdScale = SIMD3(repeating: 22 * pointsToMeters)
  }

  /// Original paint colours, so clearing the tint restores them.
  private var originalPaint: [ObjectIdentifier: Any] = [:]

  /// Recolours materials named `paint…` (the export may add `_2`, `_3`).
  private func applyTint() {
    guard let content else { return }
    let tint = UIColor(mapModelHex: model.tintColor)
    content.enumerateHierarchy { node, _ in
      for material in node.geometry?.materials ?? [] {
        guard material.name?.lowercased().hasPrefix("paint") == true else { continue }
        let key = ObjectIdentifier(material)
        if originalPaint[key] == nil, let contents = material.diffuse.contents {
          originalPaint[key] = contents
        }
        material.diffuse.contents = tint ?? originalPaint[key]
      }
    }
  }

  /// Keeps the stem about 2 points wide and the dot about 8 points across.
  private func placeStem(in snapshot: MapCameraSnapshot, top: SIMD3<Float>) {
    let show = model.visible && model.stem && model.altitude > 0.5
    stem.isHidden = !show
    stemDot.isHidden = !show
    guard show else { return }
    let ground = SIMD3(top.x, 0, top.z)
    let middle = (ground + top) / 2
    let focal = Float(snapshot.focalLength)
    let middleDepth = max(1, snapshot.project(middle)?.depth ?? Float(snapshot.distance))
    let groundDepth = max(1, snapshot.project(ground)?.depth ?? Float(snapshot.distance))
    let width = 2 * middleDepth / focal
    stem.simdPosition = middle
    stem.simdScale = SIMD3(width, top.y, width)
    let dot = 8 * groundDepth / focal
    stemDot.simdPosition = ground + SIMD3(0, 0.2, 0)
    stemDot.simdScale = SIMD3(dot, 0.05, dot)
  }

  /// Screen point halfway up the model.
  func middlePoint(in snapshot: MapCameraSnapshot) -> CGPoint? {
    guard content != nil else { return nil }
    let base = root.simdPosition
    let middle = base + SIMD3(0, contentHeight * currentScale / 2, 0)
    return snapshot.project(middle)?.point
  }

  /// Depth of the model if `point` falls on it.
  func hitTest(_ point: CGPoint, in snapshot: MapCameraSnapshot) -> Float? {
    guard model.visible, content != nil else { return nil }
    let base = root.simdPosition
    let center = base + SIMD3(0, contentHeight * currentScale / 2, 0)
    guard let projected = snapshot.project(center), projected.depth > 0 else { return nil }
    let radius = CGFloat(Float(snapshot.focalLength) * contentRadius * currentScale / projected.depth)
    let slop = max(radius, 22)
    let dx = point.x - projected.point.x
    let dy = point.y - projected.point.y
    return dx * dx + dy * dy <= slop * slop ? projected.depth : nil
  }
}

private extension UIImage {
  /// Alpha (0...1) of the pixel at `point`, in points.
  func mapModelAlpha(at point: CGPoint) -> CGFloat {
    guard let cgImage else { return 0 }
    let x = Int(point.x * scale)
    let y = Int(point.y * scale)
    guard x >= 0, y >= 0, x < cgImage.width, y < cgImage.height else { return 0 }
    var pixel = [UInt8](repeating: 0, count: 4)
    guard let context = CGContext(
      data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return 0 }
    context.translateBy(x: CGFloat(-x), y: CGFloat(y - cgImage.height + 1))
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    return CGFloat(pixel[3]) / 255
  }
}

// MARK: - Zones

/// A see-through wall on a zone outline, built once in metres around the
/// zone's first point and moved with the map each frame.
private final class ZoneEntry {
  let node = SCNNode()
  private var zone: NativeMapZone
  private var key = ""
  private var anchor = CLLocationCoordinate2D()

  init(zone: NativeMapZone) {
    self.zone = zone
    update(zone, force: true)
  }

  func update(_ zone: NativeMapZone, force: Bool = false) {
    self.zone = zone
    node.isHidden = !zone.visible
    let points = zone.points.map { "\($0.latitude),\($0.longitude)" }.joined(separator: ";")
    let newKey = "\(points)|\(zone.height)|\(zone.color)"
    guard force || newKey != key else { return }
    key = newKey
    node.geometry = buildGeometry()
  }

  func place(in snapshot: MapCameraSnapshot) {
    guard zone.visible, node.geometry != nil else { return }
    node.simdPosition = snapshot.scenePosition(
      latitude: anchor.latitude, longitude: anchor.longitude, altitude: 0)
  }

  private func buildGeometry() -> SCNGeometry? {
    let coordinates = zone.points.map {
      CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
    }
    guard coordinates.count >= 2, let first = coordinates.first else { return nil }
    anchor = first
    let origin = MKMapPoint(first)
    let scale = MKMetersPerMapPointAtLatitude(first.latitude)
    let ground: [SIMD3<Float>] = coordinates.map {
      let point = MKMapPoint($0)
      return SIMD3(Float((point.x - origin.x) * scale), 0, Float((point.y - origin.y) * scale))
    }
    let height = Float(max(0.5, zone.height))
    let color = UIColor(mapModelHex: zone.color) ?? UIColor(red: 0, green: 0.48, blue: 1, alpha: 0.25)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    // Premultiplied colours. The wall is see-through (the colour's alpha,
    // lighter towards the top) between two solid bands, like a map outline
    // stood up as a fence.
    func rgba(_ alpha: CGFloat) -> SIMD4<Float> {
      SIMD4(Float(r * alpha), Float(g * alpha), Float(b * alpha), Float(alpha))
    }
    let band = min(height * 0.25, max(0.8, height * 0.05))
    let layers: [(Float, Float, SIMD4<Float>, SIMD4<Float>)] = [ // (y0, y1, colour at y0, colour at y1)
      (0, band, rgba(0.95), rgba(0.95)),
      (band, height - band, rgba(a), rgba(a * 0.45)),
      (height - band, height, rgba(0.95), rgba(0.95)),
    ]

    var positions: [SCNVector3] = []
    var colors: [SIMD4<Float>] = []
    var indices: [UInt32] = []
    let count = ground.count
    let closed = count >= 3
    for i in 0..<(closed ? count : count - 1) {
      let p0 = ground[i]
      let p1 = ground[(i + 1) % count]
      for (y0, y1, c0, c1) in layers {
        let base = UInt32(positions.count)
        positions += [
          SCNVector3(p0.x, y0, p0.z), SCNVector3(p1.x, y0, p1.z),
          SCNVector3(p1.x, y1, p1.z), SCNVector3(p0.x, y1, p0.z),
        ]
        colors += [c0, c0, c1, c1]
        indices += [base, base + 1, base + 2, base, base + 2, base + 3]
      }
    }
    let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
    let colorSource = SCNGeometrySource(
      data: colorData, semantic: .color, vectorCount: colors.count,
      usesFloatComponents: true, componentsPerVector: 4,
      bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
      dataStride: MemoryLayout<SIMD4<Float>>.stride)
    let geometry = SCNGeometry(
      sources: [SCNGeometrySource(vertices: positions), colorSource],
      elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    let material = SCNMaterial()
    material.lightingModel = .constant
    material.diffuse.contents = UIColor.white
    material.blendMode = .alpha
    material.transparencyMode = .singleLayer
    material.isDoubleSided = true
    material.writesToDepthBuffer = false
    geometry.materials = [material]
    node.renderingOrder = 50
    node.castsShadow = false
    return geometry
  }
}
