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

  // JavaScript passes `marker` on only when it changed (it keeps the same
  // object otherwise), and `renderKey` is a hash of the children: each
  // setter means something to draw.
  var marker = MarkerViewDefaults.marker { didSet { host.propsChanged() } }
  var tracksViewChanges = false {
    didSet { if tracksViewChanges != oldValue { host.trackingChanged() } }
  }
  var renderKey: Double = 0 {
    didSet { if renderKey != oldValue { host.contentChanged() } }
  }

  func redraw() throws {
    DispatchQueue.main.async { self.host.redraw(force: true) }
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

/// Draws the children into the marker's picture when something changed:
/// the children (JavaScript's `renderKey`), their size, or a picture in them
/// (an image view's `image`, watched with KVO, so an image that loads
/// seconds later still shows). Each change draws a few times over half a
/// second, as Fabric mounts and lays the children out after the props
/// arrive; the map only gets a new picture when it looks different.
/// `tracksViewChanges` draws 15 times a second on top. The marker's own
/// props (position, title, anchor…) are not in the picture: a new value
/// goes to the map with the picture it has.
private final class MarkerViewHost: UIView {
  weak var owner: HybridMarkerView?
  private weak var map: (any MunimMapEngine)?
  private var registeredId = ""
  private var trackTimer: Timer?
  private var pendingRedraws: [DispatchWorkItem] = []
  /// The last picture handed to the map, and its pixels.
  private var lastImage: UIImage?
  private var lastPixels: Data?
  private var lastSize: CGSize = .zero
  private var imageObservations: [ObjectIdentifier: (view: Weak<UIImageView>, observation: NSKeyValueObservation)] = [:]

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      register()
      trackingChanged()
      scheduleRedraws()
    } else {
      unregister()
      trackTimer?.invalidate()
      trackTimer = nil
      pendingRedraws.forEach { $0.cancel() }
      pendingRedraws = []
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    // The children's size changed (the container is laid out at their size).
    let size = superview?.bounds.size ?? bounds.size
    if size != lastSize {
      lastSize = size
      scheduleRedraws()
    }
  }

  /// The children are drawn by Fabric after props arrive, so draw a few
  /// times after a change; unchanged pictures do not reach the map.
  func scheduleRedraws() {
    pendingRedraws.forEach { $0.cancel() }
    pendingRedraws = [0.0, 0.15, 0.5].map { delay in
      let work = DispatchWorkItem { [weak self] in self?.redraw() }
      DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
      return work
    }
  }

  func contentChanged() {
    DispatchQueue.main.async { [weak self] in self?.scheduleRedraws() }
  }

  func propsChanged() {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let id = self.owner?.marker.id ?? ""
      if !self.registeredId.isEmpty, id == self.registeredId {
        // Same marker, new position, title, anchor…: it goes to the map
        // with the picture it has (setViewMarker replaces the one with this
        // id). Nothing in the picture changed, so nothing is drawn: a map
        // whose markers move every second does not redraw them all.
        self.register()
        return
      }
      self.unregister()
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
      } else if !tracking, let timer = self.trackTimer {
        timer.invalidate()
        self.trackTimer = nil
        // The last frames, as the children settle (react-native-maps also
        // draws once more when tracking stops).
        if self.window != nil { self.scheduleRedraws() }
      }
    }
  }

  /// Watches every image view in the children: a picture that finishes
  /// loading (or changes) draws the marker again.
  private func observeImages() {
    guard let container = superview else { return }
    imageObservations = imageObservations.filter { $0.value.view.value != nil }
    var stack: [UIView] = [container]
    while let view = stack.popLast() {
      if let imageView = view as? UIImageView {
        let key = ObjectIdentifier(imageView)
        if imageObservations[key] == nil {
          let observation = imageView.observe(\.image, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.scheduleRedraws() }
          }
          imageObservations[key] = (Weak(imageView), observation)
        }
      }
      stack.append(contentsOf: view.subviews)
    }
  }

  /// The engine of the `MunimMapView` this marker is a child of:
  /// a sibling of one of this view's containers.
  private func findMap() -> (any MunimMapEngine)? {
    var ancestor = superview
    var depth = 0
    while let current = ancestor, depth < 8 {
      for sibling in current.subviews {
        if let container = sibling as? MunimMapContainerView { return container.engine }
      }
      ancestor = current.superview
      depth += 1
    }
    return nil
  }

  /// Adds the marker to the map, or sends it again with new props. A new
  /// marker is drawn first; one already on the map keeps its picture.
  private func register() {
    guard window != nil, let owner, !owner.marker.id.isEmpty else { return }
    guard let map = map ?? findMap() else { return }
    self.map = map
    if registeredId != owner.marker.id || lastPixels == nil {
      let image = snapshot()
      lastImage = image
      lastPixels = Self.pixels(image)
    }
    registeredId = owner.marker.id
    map.setViewMarker(owner.marker.core, image: lastImage)
    observeImages()
  }

  private func unregister() {
    guard !registeredId.isEmpty else { return }
    map?.removeViewMarker(registeredId)
    registeredId = ""
    lastImage = nil
    lastPixels = nil
  }

  /// Draws the React Native children: everything in the container except
  /// this (empty) view.
  private func snapshot() -> UIImage? {
    guard let container = superview, container.bounds.width >= 1, container.bounds.height >= 1 else { return nil }
    let format = UIGraphicsImageRendererFormat()
    format.scale = window?.screen.scale ?? UIScreen.main.scale
    format.opaque = false
    let restore = Self.showImages(in: container)
    defer { restore() }
    // The whole container, so the children's own transforms apply; this
    // view is empty and draws nothing.
    return UIGraphicsImageRenderer(bounds: container.bounds, format: format).image { context in
      container.layer.render(in: context.cgContext)
    }
  }

  /// `render(in:)` draws each layer's `contents`, and an image view's
  /// layer does not reliably hold its `image` there: UIKit fills it for
  /// the screen, when it displays the view, and these children are laid out
  /// far off screen. An image view whose picture loaded (its `image` is
  /// set, `onLoad` fired) could draw as an empty frame: the marker showed
  /// the photo, then a later picture of the same children (taken for any
  /// change) showed the circle around it with nothing inside. So, for the
  /// drawing, each image view's layer gets its own `image`; what was in it
  /// goes back right after, in the same transaction, so the screen never
  /// sees the change. Pictures this cannot put in a layer as they are
  /// (template images drawn in a tint, resizable or animated images,
  /// rotated ones) keep the layer's own contents.
  private static func showImages(in root: UIView) -> () -> Void {
    var saved: [(layer: CALayer, contents: Any?, scale: CGFloat, gravity: CALayerContentsGravity)] = []
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    var stack: [UIView] = [root]
    while let view = stack.popLast() {
      stack.append(contentsOf: view.subviews)
      guard let imageView = view as? UIImageView, !imageView.isHidden,
            let image = imageView.image, let cgImage = image.cgImage,
            image.renderingMode != .alwaysTemplate, !image.isSymbolImage,
            image.images == nil, image.imageOrientation == .up,
            image.capInsets == .zero, image.resizingMode == .stretch,
            let gravity = contentsGravity(imageView.contentMode)
      else { continue }
      let layer = imageView.layer
      saved.append((layer, layer.contents, layer.contentsScale, layer.contentsGravity))
      layer.contents = cgImage
      layer.contentsScale = image.scale
      layer.contentsGravity = gravity
    }
    CATransaction.commit()
    return {
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      for entry in saved {
        entry.layer.contents = entry.contents
        entry.layer.contentsScale = entry.scale
        entry.layer.contentsGravity = entry.gravity
      }
      CATransaction.commit()
    }
  }

  /// How a layer places its contents for an image view's `contentMode`:
  /// the modes React Native's `resizeMode` uses (`cover`, `contain`,
  /// `stretch`, `center`). The edge modes are left alone (a layer's top and
  /// bottom depend on whether its contents are flipped).
  private static func contentsGravity(_ mode: UIView.ContentMode) -> CALayerContentsGravity? {
    switch mode {
    case .scaleToFill: return .resize
    case .scaleAspectFit: return .resizeAspect
    case .scaleAspectFill: return .resizeAspectFill
    case .center: return .center
    default: return nil
    }
  }

  /// The image's pixels, to tell whether a new picture looks different.
  private static func pixels(_ image: UIImage?) -> Data? {
    guard let data = image?.cgImage?.dataProvider?.data else { return nil }
    return data as Data
  }

  /// Draws the children; the map gets the picture when it changed (or
  /// always, with `force`).
  func redraw(force: Bool = false) {
    guard window != nil else { return }
    if registeredId.isEmpty { register(); return }
    let image = snapshot()
    observeImages()
    let pixels = Self.pixels(image)
    if !force, let pixels, pixels == lastPixels { return }
    lastImage = image
    lastPixels = pixels
    map?.setViewMarkerImage(image, id: registeredId)
  }

  deinit {
    trackTimer?.invalidate()
    pendingRedraws.forEach { $0.cancel() }
    if !registeredId.isEmpty, let map {
      let id = registeredId
      DispatchQueue.main.async { map.removeViewMarker(id) }
    }
  }
}

/// A weak reference, to keep views in a dictionary without holding them.
private final class Weak<Value: AnyObject> {
  weak var value: Value?
  init(_ value: Value) { self.value = value }
}
