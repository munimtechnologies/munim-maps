import MapKit
import NitroModules
import UIKit

/// A MapKit map with models built in, for apps that do not already have one.
final class HybridMunimMapView: HybridMunimMapViewSpec {
  let view: UIView

  private let container = MapContainerView()
  private let mapView = MKMapView()
  private let hostView = MapModelHostView()
  private let renderer: MapModelRenderer
  private lazy var delegate = MapDelegate(owner: self)
  private var appliedInitialCamera = false

  override init() {
    view = container
    renderer = MapModelRenderer(hostView: hostView)
    super.init()

    mapView.frame = container.bounds
    mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    mapView.delegate = delegate
    container.addSubview(mapView)

    hostView.frame = container.bounds
    hostView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    container.addSubview(hostView)

    container.onLayout = { [weak self] in self?.layoutChanged() }
    hostView.onWindowChange = { [weak self] in self?.renderer.updateFrameLoop() }
    renderer.onModelPress = { [weak self] id in self?.onModelPress?(id) }
    renderer.onError = { [weak self] message in self?.onError?(message) }
    renderer.attach(to: mapView)
    applyConfiguration()
  }

  var models: [NativeMapModel] = [] {
    didSet { renderer.setModels(models) }
  }

  var initialCamera = MapCamera(latitude: 0, longitude: 0, distance: 0, pitch: 0, heading: 0) {
    didSet { applyInitialCameraIfReady() }
  }

  var mapStyle: MapStyle = .standard {
    didSet { if oldValue != mapStyle { applyConfiguration() } }
  }

  var elevation: MapElevation = .realistic {
    didSet { if oldValue != elevation { applyConfiguration() } }
  }

  var colorScheme: MapColorScheme = .system {
    didSet {
      switch colorScheme {
      case .system: mapView.overrideUserInterfaceStyle = .unspecified
      case .light: mapView.overrideUserInterfaceStyle = .light
      case .dark: mapView.overrideUserInterfaceStyle = .dark
      }
      renderer.setNeedsRender()
    }
  }

  var showsBuildings = true {
    didSet { mapView.showsBuildings = showsBuildings }
  }

  var showsUserLocation = false {
    didSet { mapView.showsUserLocation = showsUserLocation }
  }

  var lighting: MapModelLighting = .auto {
    didSet { renderer.lighting = lighting }
  }

  var maxCameraDistance: Double = 50_000 {
    didSet { renderer.maxCameraDistance = maxCameraDistance }
  }

  var onModelPress: ((_ id: String) -> Void)?
  var onCameraChange: ((_ camera: MapCamera) -> Void)?
  var onError: ((_ message: String) -> Void)?

  func setCamera(camera: MapCamera, animated: Bool) throws {
    DispatchQueue.main.async {
      self.mapView.setCamera(Self.mapKitCamera(camera), animated: animated)
      self.renderer.setNeedsRender()
    }
  }

  func getCamera() throws -> Promise<MapCamera> {
    let promise = Promise<MapCamera>()
    DispatchQueue.main.async {
      promise.resolve(withResult: self.currentCamera())
    }
    return promise
  }

  func measureAlignment() throws -> Promise<MapAlignmentReport> {
    let promise = Promise<MapAlignmentReport>()
    DispatchQueue.main.async {
      promise.resolve(withResult: self.renderer.measureAlignment())
    }
    return promise
  }

  // MARK: Internals

  fileprivate func cameraDidChange() {
    onCameraChange?(currentCamera())
  }

  private func currentCamera() -> MapCamera {
    let camera = mapView.camera
    return MapCamera(
      latitude: camera.centerCoordinate.latitude,
      longitude: camera.centerCoordinate.longitude,
      distance: camera.centerCoordinateDistance,
      pitch: Double(camera.pitch),
      heading: camera.heading)
  }

  private func layoutChanged() {
    applyInitialCameraIfReady()
    renderer.setNeedsRender()
  }

  private func applyInitialCameraIfReady() {
    guard !appliedInitialCamera, initialCamera.distance > 0,
          container.bounds.width > 0, container.bounds.height > 0
    else { return }
    appliedInitialCamera = true
    mapView.setCamera(Self.mapKitCamera(initialCamera), animated: false)
  }

  private static func mapKitCamera(_ camera: MapCamera) -> MKMapCamera {
    MKMapCamera(
      lookingAtCenter: CLLocationCoordinate2D(latitude: camera.latitude, longitude: camera.longitude),
      fromDistance: camera.distance,
      pitch: CGFloat(camera.pitch),
      heading: camera.heading)
  }

  private func applyConfiguration() {
    if #available(iOS 16.0, *) {
      let elevationStyle: MKMapConfiguration.ElevationStyle =
        elevation == .realistic ? .realistic : .flat
      let configuration: MKMapConfiguration
      switch mapStyle {
      case .standard:
        configuration = MKStandardMapConfiguration(elevationStyle: elevationStyle, emphasisStyle: .default)
      case .muted:
        configuration = MKStandardMapConfiguration(elevationStyle: elevationStyle, emphasisStyle: .muted)
      case .hybrid:
        configuration = MKHybridMapConfiguration(elevationStyle: elevationStyle)
      case .imagery:
        configuration = MKImageryMapConfiguration(elevationStyle: elevationStyle)
      }
      mapView.preferredConfiguration = configuration
    } else {
      switch mapStyle {
      case .standard, .muted: mapView.mapType = .standard
      case .hybrid: mapView.mapType = elevation == .realistic ? .hybridFlyover : .hybrid
      case .imagery: mapView.mapType = elevation == .realistic ? .satelliteFlyover : .satellite
      }
    }
    renderer.setNeedsRender()
  }
}

private final class MapContainerView: UIView {
  var onLayout: (() -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?()
  }
}

private final class MapDelegate: NSObject, MKMapViewDelegate {
  weak var owner: HybridMunimMapView?

  init(owner: HybridMunimMapView) {
    self.owner = owner
  }

  func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
    owner?.cameraDidChange()
  }
}
