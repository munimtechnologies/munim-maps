#if canImport(GoogleMaps)
import GoogleMaps
import UIKit

// Street View: Google's panoramas (`GMSPanoramaView`), shown over the map
// (`presentation: 'overlay'`) or full screen (`'fullScreen'`, what
// `openLookAround` does on the Google engine), with camera, navigation and
// events through the engine.

/// A Street View panorama with a close button.
final class GoogleStreetView: UIView, GMSPanoramaViewDelegate {
  let panoramaView: GMSPanoramaView
  private weak var engine: GoogleMapEngine?
  private let closeButton = UIButton(type: .system)
  var onClose: (() -> Void)?

  init(engine: GoogleMapEngine, panorama: GMSPanorama, options: GoogleJSON) {
    self.engine = engine
    panoramaView = GMSPanoramaView(frame: .zero)
    super.init(frame: .zero)
    backgroundColor = .black
    panoramaView.frame = bounds
    panoramaView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    panoramaView.delegate = self
    addSubview(panoramaView)
    panoramaView.panorama = panorama
    apply(options)

    if options["closeButton"].bool(true) {
      var configuration = UIButton.Configuration.filled()
      configuration.image = UIImage(systemName: "xmark")
      configuration.cornerStyle = .capsule
      configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.55)
      configuration.baseForegroundColor = .white
      closeButton.configuration = configuration
      closeButton.accessibilityLabel = "Close Street View"
      closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
      closeButton.translatesAutoresizingMaskIntoConstraints = false
      addSubview(closeButton)
      NSLayoutConstraint.activate([
        closeButton.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 12),
        closeButton.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -12),
        closeButton.widthAnchor.constraint(equalToConstant: 40),
        closeButton.heightAnchor.constraint(equalToConstant: 40),
      ])
    }
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  /// Camera, gestures and labels from `streetView.open` / `setOptions`.
  func apply(_ options: GoogleJSON) {
    if options["heading"].exists || options["pitch"].exists || options["zoom"].exists || options["fov"].exists {
      setCamera(options, duration: 0)
    }
    let gestures = options["gestures"]
    if let all = gestures.bool { panoramaView.setAllGesturesEnabled(all) }
    if let v = gestures["orientation"].bool ?? options["orientationGestures"].bool { panoramaView.orientationGestures = v }
    if let v = gestures["zoom"].bool ?? options["zoomGestures"].bool { panoramaView.zoomGestures = v }
    if let v = gestures["navigation"].bool ?? options["navigationGestures"].bool { panoramaView.navigationGestures = v }
    if let v = options["navigationLinksHidden"].bool { panoramaView.navigationLinksHidden = v }
    if let v = options["streetNamesHidden"].bool { panoramaView.streetNamesHidden = v }
  }

  func setCamera(_ options: GoogleJSON, duration: TimeInterval) {
    let current = panoramaView.camera
    let heading = options["heading"].double(current.orientation.heading)
    let pitch = options["pitch"].double(current.orientation.pitch)
    let zoom = Float(options["zoom"].double(Double(current.zoom)))
    let fov = options["fov"].double(current.fov)
    let camera = GMSPanoramaCamera(heading: heading, pitch: pitch, zoom: zoom, fov: fov)
    if duration > 0 {
      panoramaView.animate(to: camera, animationDuration: duration)
    } else {
      panoramaView.camera = camera
    }
  }

  var info: [String: Any] {
    guard let panorama = panoramaView.panorama else { return ["panoramaId": NSNull()] }
    return GoogleStreetView.info(panorama)
  }

  var cameraInfo: [String: Any] {
    let camera = panoramaView.camera
    return ["heading": camera.orientation.heading, "pitch": camera.orientation.pitch,
            "zoom": Double(camera.zoom), "fov": camera.fov]
  }

  static func info(_ panorama: GMSPanorama) -> [String: Any] {
    ["panoramaId": panorama.panoramaID,
     "latitude": panorama.coordinate.latitude, "longitude": panorama.coordinate.longitude,
     "links": panorama.links.map { ["heading": Double($0.heading), "panoramaId": $0.panoramaID] }]
  }

  @objc private func closeTapped() {
    onClose?()
  }

  // MARK: GMSPanoramaViewDelegate

  func panoramaView(_ view: GMSPanoramaView, didMoveTo panorama: GMSPanorama?) {
    guard let panorama else { return }
    engine?.emit("streetViewChange", GoogleStreetView.info(panorama))
  }

  func panoramaView(_ view: GMSPanoramaView, error: Error, onMoveNearCoordinate coordinate: CLLocationCoordinate2D) {
    engine?.emit("streetViewError", ["message": error.localizedDescription,
                                     "latitude": coordinate.latitude, "longitude": coordinate.longitude])
  }

  func panoramaView(_ view: GMSPanoramaView, error: Error, onMoveToPanoramaID panoramaID: String) {
    engine?.emit("streetViewError", ["message": error.localizedDescription, "panoramaId": panoramaID])
  }

  func panoramaView(_ panoramaView: GMSPanoramaView, didMove camera: GMSPanoramaCamera) {
    engine?.emit("streetViewCamera", cameraInfo)
  }

  func panoramaView(_ panoramaView: GMSPanoramaView, didTap point: CGPoint) {
    let orientation = panoramaView.orientation(for: point)
    engine?.emit("streetViewTap", ["x": Double(point.x), "y": Double(point.y),
                                   "heading": orientation.heading, "pitch": orientation.pitch])
  }

  func panoramaView(_ panoramaView: GMSPanoramaView, didTap marker: GMSMarker) -> Bool {
    if let id = marker.userData as? String { engine?.emit("streetViewMarkerPress", ["id": id]) }
    return false
  }
}

/// Full-screen Street View.
final class GoogleStreetViewController: UIViewController {
  let streetView: GoogleStreetView

  init(streetView: GoogleStreetView) {
    self.streetView = streetView
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .fullScreen
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override func loadView() {
    view = streetView
  }
}

extension GoogleMapEngine {
  /// `streetView.open`: finds a panorama (`latitude` / `longitude` with
  /// `radius` and `source: 'outdoor'`, or `panoramaId`) and shows it.
  func openStreetView(_ args: GoogleJSON, completion: @escaping (Result<Any, Error>) -> Void) {
    let service = panoramaService
    let found: GMSPanoramaCallback = { [weak self] panorama, error in
      DispatchQueue.main.async {
        guard let self else { return }
        guard let panorama else {
          completion(.failure(MunimMapEngineError(
            "Google Maps: no Street View here\(error.map { " (\($0.localizedDescription))" } ?? "")")))
          return
        }
        self.showStreetView(panorama, args: args)
        completion(.success(GoogleStreetView.info(panorama)))
      }
    }
    if let id = args["panoramaId"].string {
      service.requestPanorama(withID: id, callback: found)
    } else if let coordinate = args.coordinate {
      let source: GMSPanoramaSource = args["source"].string == "outdoor" ? .outside : .default
      let radius = UInt(max(1, args["radius"].double(50)))
      service.requestPanoramaNearCoordinate(coordinate, radius: radius, source: source, callback: found)
    } else {
      completion(.failure(MunimMapEngineError("Google Maps: streetView.open needs latitude and longitude, or panoramaId")))
    }
  }

  private func showStreetView(_ panorama: GMSPanorama, args: GoogleJSON) {
    closeStreetView()
    let street = GoogleStreetView(engine: self, panorama: panorama, options: args)
    street.onClose = { [weak self] in self?.closeStreetView() }
    streetView = street
    if args["showMarkers"].bool(false) {
      for marker in gmsMarkers.values { marker.panoramaView = street.panoramaView }
    }
    if args["presentation"].string == "fullScreen", let presenter = topViewController() {
      presenter.present(GoogleStreetViewController(streetView: street), animated: true)
    } else {
      street.frame = bounds
      street.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      addSubview(street)
    }
    emit("streetViewOpen", GoogleStreetView.info(panorama))
  }

  func closeStreetView() {
    guard let street = streetView else { return }
    streetView = nil
    for marker in gmsMarkers.values where marker.panoramaView === street.panoramaView { marker.panoramaView = nil }
    if let controller = street.next as? GoogleStreetViewController {
      controller.dismiss(animated: true)
    } else {
      street.removeFromSuperview()
    }
    emit("streetViewClose")
  }

  private func topViewController() -> UIViewController? {
    var controller = window?.rootViewController
    while let presented = controller?.presentedViewController { controller = presented }
    return controller
  }
}
#endif
