import MapKit
import NitroModules
import UIKit

/// React Native `MapServices`: MapKit's search, directions, geocoding,
/// places and snapshots, not tied to a map view.
final class HybridMapServices: HybridMapServicesSpec {
  // MARK: Search

  func searchPlaces(request: NativeSearchRequest) throws -> Promise<[MapItem]> {
    let promise = Promise<[MapItem]>()
    DispatchQueue.main.async {
      let search = MKLocalSearch.Request()
      search.naturalLanguageQuery = request.query
      if let region = request.region.optional { search.region = region }
      search.resultTypes = MapServiceParsing.searchResultTypes(request.resultTypes)
      search.pointOfInterestFilter = MapServiceParsing.pointOfInterestFilter(request.pointsOfInterest)
      if #available(iOS 18.0, *), request.regionRequired { search.regionPriority = .required }
      MKLocalSearch(request: search).start { response, error in
        MapServiceParsing.resolveItems(promise, response?.mapItems, error)
      }
    }
    return promise
  }

  func createSearchCompleter() throws -> any HybridSearchCompleterSpec {
    HybridSearchCompleter()
  }

  func pointsOfInterest(request: NativePointsOfInterestRequest) throws -> Promise<[MapItem]> {
    let promise = Promise<[MapItem]>()
    DispatchQueue.main.async {
      let poi: MKLocalPointsOfInterestRequest
      if request.radius > 0 || request.region.optional == nil {
        poi = MKLocalPointsOfInterestRequest(
          center: CLLocationCoordinate2D(latitude: request.latitude, longitude: request.longitude),
          radius: min(max(1, request.radius), MKLocalPointsOfInterestRequest.maxRadius))
      } else {
        poi = MKLocalPointsOfInterestRequest(coordinateRegion: request.region.mapKit)
      }
      poi.pointOfInterestFilter = MapServiceParsing.pointOfInterestFilter(request.pointsOfInterest)
      MKLocalSearch(request: poi).start { response, error in
        MapServiceParsing.resolveItems(promise, response?.mapItems, error)
      }
    }
    return promise
  }

  // MARK: Directions

  func directions(request: NativeDirectionsRequest) throws -> Promise<[Route]> {
    let promise = Promise<[Route]>()
    makeDirections(request) { result in
      switch result {
      case .failure(let error): promise.reject(withError: error)
      case .success(let directions):
        directions.calculate { response, error in
          guard let response else {
            return promise.reject(withError: error ?? MapServiceError("No route found"))
          }
          promise.resolve(withResult: response.routes.map(Route.init))
        }
      }
    }
    return promise
  }

  func eta(request: NativeDirectionsRequest) throws -> Promise<Eta> {
    let promise = Promise<Eta>()
    makeDirections(request) { result in
      switch result {
      case .failure(let error): promise.reject(withError: error)
      case .success(let directions):
        directions.calculateETA { response, error in
          guard let response else {
            return promise.reject(withError: error ?? MapServiceError("No route found"))
          }
          promise.resolve(withResult: Eta(
            expectedTravelTime: response.expectedTravelTime, distance: response.distance,
            expectedArrivalDate: response.expectedArrivalDate.timeIntervalSince1970,
            expectedDepartureDate: response.expectedDepartureDate.timeIntervalSince1970,
            transportType: TransportType(response.transportType)))
        }
      }
    }
    return promise
  }

  private func makeDirections(_ request: NativeDirectionsRequest, completion: @escaping (Result<MKDirections, Error>) -> Void) {
    DispatchQueue.main.async {
      MapServiceParsing.mapItem(for: request.from) { from in
        MapServiceParsing.mapItem(for: request.to) { to in
          guard let from, let to else {
            return completion(.failure(MapServiceError("Could not find the start or the end of the route")))
          }
          let directions = MKDirections.Request()
          directions.source = from
          directions.destination = to
          directions.transportType = request.transportType.mapKit
          directions.requestsAlternateRoutes = request.alternates
          if request.departureDate > 0 { directions.departureDate = Date(timeIntervalSince1970: request.departureDate) }
          if request.arrivalDate > 0 { directions.arrivalDate = Date(timeIntervalSince1970: request.arrivalDate) }
          if #available(iOS 16.0, *) {
            directions.tollPreference = request.avoidTolls ? .avoid : .any
            directions.highwayPreference = request.avoidHighways ? .avoid : .any
          }
          completion(.success(MKDirections(request: directions)))
        }
      }
    }
  }

  // MARK: Geocoding and places

  func geocode(address: String, region: MapRegion) throws -> Promise<[MapItem]> {
    let promise = Promise<[MapItem]>()
    DispatchQueue.main.async {
      #if compiler(>=6.2)
      if #available(iOS 26.0, *), let request = MKGeocodingRequest(addressString: address) {
        if let region = region.optional { request.region = region }
        request.getMapItems { items, error in MapServiceParsing.resolveItems(promise, items, error) }
        return
      }
      #endif
      let geocoder = CLGeocoder()
      let area = region.optional.map { r -> CLRegion in
        let center = r.center
        let radius = CLLocation(latitude: center.latitude, longitude: center.longitude).distance(
          from: CLLocation(latitude: center.latitude + r.span.latitudeDelta / 2, longitude: center.longitude))
        return CLCircularRegion(center: center, radius: radius, identifier: "munim-maps-geocode")
      }
      geocoder.geocodeAddressString(address, in: area, preferredLocale: nil) { placemarks, error in
        MapServiceParsing.resolveItems(promise, placemarks?.map(MapServiceParsing.mapItem(from:)), error)
      }
    }
    return promise
  }

  func reverseGeocode(coordinate: MapCoordinate) throws -> Promise<[MapItem]> {
    let promise = Promise<[MapItem]>()
    let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    DispatchQueue.main.async {
      #if compiler(>=6.2)
      if #available(iOS 26.0, *), let request = MKReverseGeocodingRequest(location: location) {
        request.getMapItems { items, error in MapServiceParsing.resolveItems(promise, items, error) }
        return
      }
      #endif
      CLGeocoder().reverseGeocodeLocation(location) { placemarks, error in
        MapServiceParsing.resolveItems(promise, placemarks?.map(MapServiceParsing.mapItem(from:)), error)
      }
    }
    return promise
  }

  func mapItem(identifier: String) throws -> Promise<MapItem> {
    let promise = Promise<MapItem>()
    DispatchQueue.main.async {
      MapServiceParsing.mapItem(identifier: identifier) { item, error in
        if let item { promise.resolve(withResult: MapItem(item)) } else { promise.reject(withError: error) }
      }
    }
    return promise
  }

  // MARK: Apple Maps

  func openInMaps(items: [MapItem], options: NativeOpenInMapsOptions) throws -> Promise<Bool> {
    let promise = Promise<Bool>()
    DispatchQueue.main.async {
      let group = DispatchGroup()
      var resolved = [MKMapItem?](repeating: nil, count: items.count)
      for (index, item) in items.enumerated() {
        group.enter()
        MapServiceParsing.mapItem(from: item) { found in
          resolved[index] = found
          group.leave()
        }
      }
      group.notify(queue: .main) {
        var launch: [String: Any] = [:]
        if let mode = options.directionsMode.launchValue { launch[MKLaunchOptionsDirectionsModeKey] = mode }
        if options.camera.distance > 0 {
          launch[MKLaunchOptionsCameraKey] = MunimMapKitView.mapKitCamera(options.camera.core)
        }
        if let region = options.region.optional {
          launch[MKLaunchOptionsMapCenterKey] = NSValue(mkCoordinate: region.center)
          launch[MKLaunchOptionsMapSpanKey] = NSValue(mkCoordinateSpan: region.span)
        }
        launch[MKLaunchOptionsMapTypeKey] = NSNumber(value: options.mapStyle.mapType.rawValue)
        if options.showsTraffic { launch[MKLaunchOptionsShowsTrafficKey] = true }
        let found = resolved.compactMap { $0 }
        guard !found.isEmpty else { return promise.reject(withError: MapServiceError("No places to open")) }
        MKMapItem.openMaps(with: found, launchOptions: launch, from: nil) { promise.resolve(withResult: $0) }
      }
    }
    return promise
  }

  func presentPlaceCard(identifier: String) throws -> Promise<Bool> {
    let promise = Promise<Bool>()
    DispatchQueue.main.async {
      guard #available(iOS 18.0, *) else { return promise.resolve(withResult: false) }
      MapServiceParsing.mapItem(identifier: identifier) { item, error in
        guard let item else { return promise.reject(withError: error) }
        guard let presenter = MapServiceParsing.topViewController() else { return promise.resolve(withResult: false) }
        let controller = MKMapItemDetailViewController(mapItem: item)
        let closer = PlaceCardCloser()
        controller.delegate = closer
        objc_setAssociatedObject(controller, &PlaceCardCloser.key, closer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController { sheet.detents = [.medium(), .large()] }
        presenter.present(controller, animated: true)
        promise.resolve(withResult: true)
      }
    }
    return promise
  }

  func formatDistance(meters: Double, units: String, style: String) throws -> String {
    let formatter = MKDistanceFormatter()
    switch units {
    case "metric": formatter.units = .metric
    case "imperial": formatter.units = .imperial
    case "imperialWithYards": formatter.units = .imperialWithYards
    default: formatter.units = .default
    }
    switch style {
    case "abbreviated": formatter.unitStyle = .abbreviated
    case "full": formatter.unitStyle = .full
    default: formatter.unitStyle = .default
    }
    return formatter.string(fromDistance: meters)
  }

  // MARK: Images

  func snapshot(request: NativeSnapshotRequest) throws -> Promise<String> {
    let promise = Promise<String>()
    DispatchQueue.main.async {
      let options = MKMapSnapshotter.Options()
      if let region = request.region.optional {
        options.region = region
      } else {
        options.camera = MunimMapKitView.mapKitCamera(request.camera.core)
      }
      options.size = CGSize(width: max(1, request.width), height: max(1, request.height))
      let style: UIUserInterfaceStyle = request.colorScheme == .dark ? .dark : request.colorScheme == .light ? .light : .unspecified
      options.traitCollection = UITraitCollection(traitsFrom: [
        UITraitCollection(userInterfaceStyle: style),
        UITraitCollection(displayScale: UIScreen.main.scale),
      ])
      let filter = MapServiceParsing.pointOfInterestFilter(request.pointsOfInterest) ?? .includingAll
      if #available(iOS 17.0, *) {
        options.preferredConfiguration = MapServiceParsing.configuration(
          style: request.mapStyle, elevation: request.elevation, filter: filter, traffic: request.showsTraffic)
      } else {
        options.mapType = request.mapStyle.mapType
        options.pointOfInterestFilter = filter
      }
      options.showsBuildings = request.showsBuildings
      MKMapSnapshotter(options: options).start { snapshot, error in
        guard let image = snapshot?.image else {
          return promise.reject(withError: error ?? MapServiceError("Snapshot failed"))
        }
        MapServiceParsing.resolvePNG(promise, image, prefix: "snapshot")
      }
    }
    return promise
  }

  func hasLookAround(coordinate: MapCoordinate) throws -> Promise<Bool> {
    let promise = Promise<Bool>()
    DispatchQueue.main.async {
      guard #available(iOS 16.0, *) else { return promise.resolve(withResult: false) }
      MKLookAroundSceneRequest(coordinate: CLLocationCoordinate2D(coordinate)).getSceneWithCompletionHandler { scene, _ in
        promise.resolve(withResult: scene != nil)
      }
    }
    return promise
  }

  func lookAroundSnapshot(coordinate: MapCoordinate, mapItemId: String, width: Double, height: Double,
                          pointsOfInterest: String, colorScheme: MapColorScheme) throws -> Promise<String> {
    let promise = Promise<String>()
    DispatchQueue.main.async {
      guard #available(iOS 16.0, *) else {
        return promise.reject(withError: MapServiceError("Look Around needs iOS 16"))
      }
      LookAroundScenes.scene(coordinate: CLLocationCoordinate2D(coordinate), mapItemId: mapItemId) { scene, error in
        guard let scene else { return promise.reject(withError: error ?? MapServiceError("No Look Around imagery here")) }
        let options = MKLookAroundSnapshotter.Options()
        options.size = CGSize(width: max(1, width), height: max(1, height))
        options.pointOfInterestFilter = MapServiceParsing.pointOfInterestFilter(pointsOfInterest)
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : colorScheme == .light ? .light : .unspecified
        options.traitCollection = UITraitCollection(userInterfaceStyle: style)
        let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)
        snapshotter.getSnapshotWithCompletionHandler { snapshot, error in
          withExtendedLifetime(snapshotter) {}
          guard let image = snapshot?.image else {
            return promise.reject(withError: error ?? MapServiceError("Look Around snapshot failed"))
          }
          MapServiceParsing.resolvePNG(promise, image, prefix: "lookaround")
        }
      }
    }
    return promise
  }
}

/// Dismisses a place card when its Done button is tapped.
@available(iOS 18.0, *)
private final class PlaceCardCloser: NSObject, MKMapItemDetailViewControllerDelegate {
  static var key: UInt8 = 0

  func mapItemDetailViewControllerDidFinish(_ detailViewController: MKMapItemDetailViewController) {
    detailViewController.dismiss(animated: true)
  }
}

struct MapServiceError: LocalizedError {
  let message: String
  init(_ message: String) { self.message = message }
  var errorDescription: String? { message }
}

/// Look Around scenes from a coordinate or a place id.
@available(iOS 16.0, *)
enum LookAroundScenes {
  static func scene(coordinate: CLLocationCoordinate2D, mapItemId: String,
                    completion: @escaping (MKLookAroundScene?, Error?) -> Void) {
    if !mapItemId.isEmpty {
      MapServiceParsing.mapItem(identifier: mapItemId) { item, error in
        guard let item else { return completion(nil, error) }
        MKLookAroundSceneRequest(mapItem: item).getSceneWithCompletionHandler { completion($0, $1) }
      }
    } else {
      MKLookAroundSceneRequest(coordinate: coordinate).getSceneWithCompletionHandler { completion($0, $1) }
    }
  }
}

/// Conversions shared by the services.
enum MapServiceParsing {
  static func resolveItems(_ promise: Promise<[MapItem]>, _ items: [MKMapItem]?, _ error: Error?) {
    if let items {
      promise.resolve(withResult: items.map(MapItem.init))
    } else if let error = error as? MKError, error.code == .placemarkNotFound {
      promise.resolve(withResult: [])
    } else if let error = error as? CLError, error.code == .geocodeFoundNoResult {
      promise.resolve(withResult: [])
    } else {
      promise.reject(withError: error ?? MapServiceError("No results"))
    }
  }

  static func resolvePNG(_ promise: Promise<String>, _ image: UIImage, prefix: String) {
    guard let data = image.pngData() else { return promise.reject(withError: MapServiceError("Could not encode the image")) }
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("munim-maps-\(prefix)-\(UUID().uuidString).png")
    do {
      try data.write(to: url)
      promise.resolve(withResult: url.path)
    } catch {
      promise.reject(withError: error)
    }
  }

  /// `address,pointOfInterest,physicalFeature`; empty for all.
  static func searchResultTypes(_ text: String) -> MKLocalSearch.ResultType {
    var types: MKLocalSearch.ResultType = []
    for name in names(text) {
      switch name {
      case "address": types.insert(.address)
      case "pointOfInterest": types.insert(.pointOfInterest)
      case "physicalFeature": if #available(iOS 18.0, *) { types.insert(.physicalFeature) }
      default: break
      }
    }
    if types.isEmpty {
      types = [.address, .pointOfInterest]
      if #available(iOS 18.0, *) { types.insert(.physicalFeature) }
    }
    return types
  }

  static func completerResultTypes(_ text: String) -> MKLocalSearchCompleter.ResultType {
    var types: MKLocalSearchCompleter.ResultType = []
    for name in names(text) {
      switch name {
      case "address": types.insert(.address)
      case "pointOfInterest": types.insert(.pointOfInterest)
      case "query": types.insert(.query)
      case "physicalFeature": if #available(iOS 18.0, *) { types.insert(.physicalFeature) }
      default: break
      }
    }
    if types.isEmpty {
      types = [.address, .pointOfInterest, .query]
      if #available(iOS 18.0, *) { types.insert(.physicalFeature) }
    }
    return types
  }

  /// `all` (or empty), `none`, or `MKPOICategory…` values.
  static func pointOfInterestFilter(_ text: String) -> MKPointOfInterestFilter? {
    switch text.trimmingCharacters(in: .whitespaces) {
    case "", "all": return nil
    case "none": return .excludingAll
    default: return MKPointOfInterestFilter(including: names(text).map { MKPointOfInterestCategory(rawValue: $0) })
    }
  }

  static func names(_ text: String) -> [String] {
    text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
  }

  @available(iOS 16.0, *)
  static func configuration(style: MapStyle, elevation: MapElevation, filter: MKPointOfInterestFilter,
                            traffic: Bool) -> MKMapConfiguration {
    let elevationStyle: MKMapConfiguration.ElevationStyle = elevation == .realistic ? .realistic : .flat
    switch style {
    case .standard, .muted:
      let standard = MKStandardMapConfiguration(elevationStyle: elevationStyle,
                                                emphasisStyle: style == .muted ? .muted : .default)
      standard.pointOfInterestFilter = filter
      standard.showsTraffic = traffic
      return standard
    case .hybrid:
      let hybrid = MKHybridMapConfiguration(elevationStyle: elevationStyle)
      hybrid.pointOfInterestFilter = filter
      hybrid.showsTraffic = traffic
      return hybrid
    case .imagery:
      return MKImageryMapConfiguration(elevationStyle: elevationStyle)
    }
  }

  static func mapItem(identifier: String, completion: @escaping (MKMapItem?, Error) -> Void) {
    guard #available(iOS 18.0, *) else {
      return completion(nil, MapServiceError("Place ids need iOS 18"))
    }
    guard let id = MKMapItem.Identifier(rawValue: identifier) else {
      return completion(nil, MapServiceError("Not a place id: \(identifier)"))
    }
    MKMapItemRequest(mapItemIdentifier: id).getMapItem { item, error in
      completion(item, error ?? MapServiceError("No place with id \(identifier)"))
    }
  }

  /// A map item at a coordinate, with a name.
  static func mapItem(at coordinate: CLLocationCoordinate2D, name: String) -> MKMapItem {
    let item: MKMapItem
    #if compiler(>=6.2)
    if #available(iOS 26.0, *) {
      item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
    } else {
      item = legacyMapItem(coordinate)
    }
    #else
    item = legacyMapItem(coordinate)
    #endif
    if !name.isEmpty { item.name = name }
    return item
  }

  @available(iOS, deprecated: 26.0)
  private static func legacyMapItem(_ coordinate: CLLocationCoordinate2D) -> MKMapItem {
    MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
  }

  @available(iOS, deprecated: 26.0)
  static func mapItem(from placemark: CLPlacemark) -> MKMapItem {
    let item = MKMapItem(placemark: MKPlacemark(placemark: placemark))
    item.name = placemark.name
    return item
  }

  static func mapItem(for waypoint: NativeWaypoint, completion: @escaping (MKMapItem?) -> Void) {
    if waypoint.currentLocation { return completion(MKMapItem.forCurrentLocation()) }
    if !waypoint.mapItemId.isEmpty {
      return mapItem(identifier: waypoint.mapItemId) { item, _ in completion(item) }
    }
    completion(mapItem(at: CLLocationCoordinate2D(latitude: waypoint.latitude, longitude: waypoint.longitude), name: ""))
  }

  static func mapItem(from item: MapItem, completion: @escaping (MKMapItem?) -> Void) {
    if item.isCurrentLocation { return completion(MKMapItem.forCurrentLocation()) }
    let fallback = { mapItem(at: CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude), name: item.name) }
    guard !item.identifier.isEmpty else { return completion(fallback()) }
    mapItem(identifier: item.identifier) { found, _ in completion(found ?? fallback()) }
  }

  static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
    var controller = window?.rootViewController
    while let presented = controller?.presentedViewController { controller = presented }
    return controller
  }
}

extension MapRegion {
  /// The region, or nil for zero deltas.
  var optional: MKCoordinateRegion? { latitudeDelta > 0 && longitudeDelta > 0 ? mapKit : nil }
}

extension MapStyle {
  var mapType: MKMapType {
    switch self {
    case .standard: return .standard
    case .muted: return .mutedStandard
    case .hybrid: return .hybrid
    case .imagery: return .satellite
    }
  }
}

extension DirectionsMode {
  var launchValue: String? {
    switch self {
    case .none: return nil
    case .automatic: return MKLaunchOptionsDirectionsModeDefault
    case .driving: return MKLaunchOptionsDirectionsModeDriving
    case .walking: return MKLaunchOptionsDirectionsModeWalking
    case .transit: return MKLaunchOptionsDirectionsModeTransit
    case .cycling: return MKLaunchOptionsDirectionsModeCycling
    }
  }
}

extension TransportType {
  var mapKit: MKDirectionsTransportType {
    switch self {
    case .automobile: return .automobile
    case .walking: return .walking
    case .transit: return .transit
    case .cycling: return .cycling
    case .any: return .any
    }
  }

  init(_ type: MKDirectionsTransportType) {
    if type.contains(.automobile) { self = .automobile }
    else if type.contains(.walking) { self = .walking }
    else if type.contains(.transit) { self = .transit }
    else if type.contains(.cycling) { self = .cycling }
    else { self = .any }
  }
}

extension MKMultiPoint {
  var mapCoordinates: [MapCoordinate] {
    var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
    getCoordinates(&coordinates, range: NSRange(location: 0, length: pointCount))
    return coordinates.map { MapCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
  }
}

extension Route {
  init(_ route: MKRoute) {
    var hasTolls = false
    var hasHighways = false
    if #available(iOS 16.0, *) {
      hasTolls = route.hasTolls
      hasHighways = route.hasHighways
    }
    self.init(
      name: route.name, distance: route.distance, expectedTravelTime: route.expectedTravelTime,
      transportType: TransportType(route.transportType),
      advisoryNotices: route.advisoryNotices.joined(separator: "\n"), hasTolls: hasTolls,
      hasHighways: hasHighways, coordinates: route.polyline.mapCoordinates,
      steps: route.steps.map {
        RouteStep(instructions: $0.instructions, notice: $0.notice ?? "", distance: $0.distance,
                  transportType: TransportType($0.transportType), coordinates: $0.polyline.mapCoordinates)
      })
  }
}

// MARK: - Search completer

/// React Native `SearchCompleter`: `MKLocalSearchCompleter`.
final class HybridSearchCompleter: HybridSearchCompleterSpec {
  private lazy var completer: MKLocalSearchCompleter = onMain {
    let completer = MKLocalSearchCompleter()
    completer.delegate = relay
    return completer
  }
  private let relay = CompleterRelay()

  override init() {
    super.init()
    relay.owner = self
  }

  func setQuery(query: String) throws {
    DispatchQueue.main.async { self.completer.queryFragment = query }
  }

  func setRegion(region: MapRegion) throws {
    DispatchQueue.main.async {
      if let value = region.optional { self.completer.region = value }
    }
  }

  func setResultTypes(types: String) throws {
    DispatchQueue.main.async { self.completer.resultTypes = MapServiceParsing.completerResultTypes(types) }
  }

  func setPointsOfInterest(filter: String) throws {
    DispatchQueue.main.async { self.completer.pointOfInterestFilter = MapServiceParsing.pointOfInterestFilter(filter) }
  }

  func setListener(onResults: @escaping ([SearchCompletion]) -> Void, onError: @escaping (String) -> Void) throws {
    relay.onResults = onResults
    relay.onError = onError
  }

  func resolve(index: Double) throws -> Promise<[MapItem]> {
    let promise = Promise<[MapItem]>()
    DispatchQueue.main.async {
      let results = self.completer.results
      let i = Int(index)
      guard i >= 0, i < results.count else {
        return promise.reject(withError: MapServiceError("No completion at \(i)"))
      }
      MKLocalSearch(request: MKLocalSearch.Request(completion: results[i])).start { response, error in
        MapServiceParsing.resolveItems(promise, response?.mapItems, error)
      }
    }
    return promise
  }

  func cancel() throws {
    DispatchQueue.main.async { self.completer.cancel() }
  }
}

private final class CompleterRelay: NSObject, MKLocalSearchCompleterDelegate {
  weak var owner: HybridSearchCompleter?
  var onResults: (([SearchCompletion]) -> Void)?
  var onError: ((String) -> Void)?

  func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
    let results = completer.results.enumerated().map { index, result in
      SearchCompletion(
        title: result.title, subtitle: result.subtitle,
        titleHighlights: Self.ranges(result.titleHighlightRanges),
        subtitleHighlights: Self.ranges(result.subtitleHighlightRanges), index: Double(index))
    }
    onResults?(results)
  }

  func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
    onError?(error.localizedDescription)
  }

  private static func ranges(_ values: [NSValue]) -> String {
    values.map { "\($0.rangeValue.location),\($0.rangeValue.length)" }.joined(separator: ";")
  }
}
