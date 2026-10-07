import MapKit
import NitroModules
import UIKit

/// React Native `LookAroundView`: Apple's `MKLookAroundViewController`
/// embedded as a child of the screen's view controller. iOS 16+; shows
/// nothing earlier.
final class HybridLookAroundView: HybridLookAroundViewSpec {
  private let container = LookAroundContainer()
  var view: UIView { container }

  override init() {
    super.init()
    container.owner = self
  }

  var latitude: Double = 0 { didSet { if oldValue != latitude { container.placeChanged() } } }
  var longitude: Double = 0 { didSet { if oldValue != longitude { container.placeChanged() } } }
  var mapItemId = "" { didSet { if oldValue != mapItemId { container.placeChanged() } } }
  var showsRoadLabels = true { didSet { container.applyOptions() } }
  var pointsOfInterest = "all" { didSet { container.applyOptions() } }
  var navigationEnabled = true { didSet { container.applyOptions() } }
  var badgePosition: LookAroundBadgePosition = .topleading { didSet { container.applyOptions() } }
  var onSceneChange: ((_ available: Bool) -> Void)?
  var onFullScreenChange: ((_ fullScreen: Bool) -> Void)?
  var onError: ((_ message: String) -> Void)?
}

private final class LookAroundContainer: UIView {
  weak var owner: HybridLookAroundView?
  private var controller: UIViewController?
  private var delegateRelay: AnyObject?
  private var loadGeneration = 0
  private var pendingLoad = false

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      embed()
      if pendingLoad || controller == nil { placeChanged() }
    } else {
      unembed()
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    controller?.view.frame = bounds
  }

  private func parentController() -> UIViewController? {
    var responder: UIResponder? = self
    while let current = responder {
      if let found = current as? UIViewController { return found }
      responder = current.next
    }
    return nil
  }

  private func embed() {
    guard #available(iOS 16.0, *) else { return }
    let lookAround: MKLookAroundViewController
    if let existing = controller as? MKLookAroundViewController {
      lookAround = existing
    } else {
      lookAround = MKLookAroundViewController()
      let relay = LookAroundRelay()
      relay.container = self
      lookAround.delegate = relay
      delegateRelay = relay
      controller = lookAround
      applyOptions()
    }
    guard lookAround.parent == nil else { return }
    let parent = parentController()
    parent?.addChild(lookAround)
    lookAround.view.frame = bounds
    addSubview(lookAround.view)
    lookAround.didMove(toParent: parent)
  }

  private func unembed() {
    guard let controller, controller.parent != nil || controller.view.superview != nil else { return }
    // Full screen Look Around takes the view out of the window too; keep it then.
    if controller.presentedViewController != nil { return }
    controller.willMove(toParent: nil)
    controller.view.removeFromSuperview()
    controller.removeFromParent()
  }

  func applyOptions() {
    guard #available(iOS 16.0, *), let owner, let lookAround = controller as? MKLookAroundViewController else { return }
    lookAround.showsRoadLabels = owner.showsRoadLabels
    lookAround.isNavigationEnabled = owner.navigationEnabled
    lookAround.pointOfInterestFilter = MapServiceParsing.pointOfInterestFilter(owner.pointsOfInterest) ?? .includingAll
    switch owner.badgePosition {
    case .topleading: lookAround.badgePosition = .topLeading
    case .toptrailing: lookAround.badgePosition = .topTrailing
    case .bottomtrailing: lookAround.badgePosition = .bottomTrailing
    }
  }

  /// Fetches the scene for the current place once the view is on screen
  /// (props arrive one by one; this coalesces them).
  func placeChanged() {
    guard window != nil else { pendingLoad = true; return }
    pendingLoad = false
    loadGeneration += 1
    let generation = loadGeneration
    DispatchQueue.main.async { [weak self] in
      guard let self, generation == self.loadGeneration else { return }
      self.load(generation)
    }
  }

  private func load(_ generation: Int) {
    guard #available(iOS 16.0, *), let owner else { return }
    if owner.mapItemId.isEmpty, owner.latitude == 0, owner.longitude == 0 { return }
    let coordinate = CLLocationCoordinate2D(latitude: owner.latitude, longitude: owner.longitude)
    LookAroundScenes.scene(coordinate: coordinate, mapItemId: owner.mapItemId) { [weak self] scene, error in
      DispatchQueue.main.async {
        guard let self, generation == self.loadGeneration, let owner = self.owner else { return }
        (self.controller as? MKLookAroundViewController)?.scene = scene
        owner.onSceneChange?(scene != nil)
        if scene == nil, let error { owner.onError?(error.localizedDescription) }
      }
    }
  }

  fileprivate func fullScreenChanged(_ fullScreen: Bool) {
    owner?.onFullScreenChange?(fullScreen)
  }
}

@available(iOS 16.0, *)
private final class LookAroundRelay: NSObject, MKLookAroundViewControllerDelegate {
  weak var container: LookAroundContainer?

  func lookAroundViewControllerDidPresentFullScreen(_ viewController: MKLookAroundViewController) {
    container?.fullScreenChanged(true)
  }

  func lookAroundViewControllerDidDismissFullScreen(_ viewController: MKLookAroundViewController) {
    container?.fullScreenChanged(false)
  }
}
