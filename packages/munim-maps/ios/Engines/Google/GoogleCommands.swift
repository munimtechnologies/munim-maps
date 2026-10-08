#if canImport(GoogleMaps)
import GoogleMaps
import UIKit

// Methods only Google has, called from JavaScript with
// `providerCommand(command, args)` (typed in `googleMap(ref)`).

extension GoogleMapEngine {
  public func providerCommand(
    _ command: String, arguments: [String: Any], completion: @escaping (Result<Any, Error>) -> Void
  ) {
    let args = GoogleJSON(arguments)
    if let mode3d, mode3d.command(command, args, completion: completion) { return }
    func done(_ value: Any = NSNull()) { completion(.success(value)) }
    func fail(_ message: String) { completion(.failure(MunimMapEngineError("Google Maps: \(message)"))) }

    // Street View works without the map view.
    if command.hasPrefix("streetView.") {
      return streetViewCommand(String(command.dropFirst("streetView.".count)), args, completion: completion)
    }
    if command == "sdkInfo" {
      return done(["platform": "ios", "version": GMSServices.sdkVersion(), "longVersion": GMSServices.sdkLongVersion(),
                   "openSourceLicenseInfo": args["licenses"].bool(false) ? GMSServices.openSourceLicenseInfo() : ""])
    }
    guard let mapView else { return fail("the map is not ready yet") }
    let duration = args["duration"].double(0) / 1000

    switch command {
    case "getCameraPosition":
      done(GoogleOut.camera(mapView.camera))

    case "moveCamera", "animateCamera":
      let current = mapView.camera
      let target = args.coordinate ?? current.target
      let position = GMSCameraPosition(
        target: target, zoom: Float(args["zoom"].double(Double(current.zoom))),
        bearing: args["bearing"].double(current.bearing), viewingAngle: args["tilt"].double(current.viewingAngle))
      stopFlight()
      if command == "moveCamera" {
        mapView.camera = position
      } else if duration > 0 {
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        mapView.animate(to: position)
        CATransaction.commit()
      } else {
        mapView.animate(to: position)
      }
      modelLayer.setNeedsRender()
      done()

    case "zoomIn": move(GMSCameraUpdate.zoomIn(), duration: duration); done()
    case "zoomOut": move(GMSCameraUpdate.zoomOut(), duration: duration); done()
    case "zoomTo": move(GMSCameraUpdate.zoom(to: Float(args["zoom"].double(Double(mapView.camera.zoom)))), duration: duration); done()
    case "zoomBy":
      let amount = Float(args["amount"].double(1))
      if let x = args["x"].double, let y = args["y"].double {
        move(GMSCameraUpdate.zoom(by: amount, at: CGPoint(x: x, y: y)), duration: duration)
      } else {
        move(GMSCameraUpdate.zoom(by: amount), duration: duration)
      }
      done()
    case "scrollBy":
      move(GMSCameraUpdate.scrollBy(x: CGFloat(args["x"].double(0)), y: CGFloat(args["y"].double(0))), duration: duration)
      done()
    case "fitBounds":
      guard let bounds = args.bounds else { return fail("fitBounds needs southwest and northeast") }
      let p = args["padding"]
      let insets = p.double.map { UIEdgeInsets(top: $0, left: $0, bottom: $0, right: $0) }
        ?? UIEdgeInsets(top: p["top"].double(0), left: p["left"].double(0), bottom: p["bottom"].double(0), right: p["right"].double(0))
      move(GMSCameraUpdate.fit(bounds, with: insets), duration: duration)
      done()
    case "stopAnimation":
      stopFlight()
      mapView.layer.removeAllAnimations()
      mapView.moveCamera(GMSCameraUpdate.setCamera(mapView.camera))
      done()

    case "getProjection":
      let region = mapView.projection.visibleRegion()
      done([
        "nearLeft": GoogleOut.coordinate(region.nearLeft), "nearRight": GoogleOut.coordinate(region.nearRight),
        "farLeft": GoogleOut.coordinate(region.farLeft), "farRight": GoogleOut.coordinate(region.farRight),
        "bounds": GoogleOut.bounds(GMSCoordinateBounds(region: region)),
        "camera": GoogleOut.camera(mapView.camera),
        "pointsPerMeter": 1 / metersPerPoint,
      ])
    case "pointsForMeters":
      let at = args.coordinate ?? mapView.camera.target
      done(Double(mapView.projection.points(forMeters: args["meters"].double(1), at: at)))
    case "containsCoordinate":
      guard let c = args.coordinate else { return fail("containsCoordinate needs latitude and longitude") }
      done(mapView.projection.contains(c))

    case "getMapCapabilities":
      done(Self.capabilities(mapView.mapCapabilities))
    case "getMyLocation":
      guard let location = mapView.myLocation else { return done() }
      done(["latitude": location.coordinate.latitude, "longitude": location.coordinate.longitude,
            "altitude": location.altitude, "accuracy": location.horizontalAccuracy,
            "heading": location.course, "speed": location.speed])

    case "getIndoorBuilding":
      let display = mapView.indoorDisplay
      done(Self.building(display.activeBuilding, active: display.activeLevel))
    case "setIndoorLevel":
      guard let building = mapView.indoorDisplay.activeBuilding else { return fail("no indoor building is focused") }
      let index = Int(args["index"].double(-1))
      let level = building.levels.indices.contains(index)
        ? building.levels[index]
        : building.levels.first { $0.shortName == args["shortName"].string || $0.name == args["name"].string }
      guard let level else { return fail("no such level") }
      mapView.indoorDisplay.activeLevel = level
      done()

    case "showInfoWindow": selectMarker(args["id"].string ?? ""); done()
    case "hideInfoWindow": deselectMarker(args["id"].string ?? ""); done()
    case "clearTileCache": clearTileCache(id: args["id"].string); done()

    case "cameraDiagnostics":
      let state = cameraSource?.cameraState(previous: nil)
      done([
        "fieldOfViewDegrees": GoogleCameraSource.fieldOfView * 180 / .pi,
        "fieldOfViewMeasured": GoogleCameraSource.fieldOfViewMeasured,
        "distance": state?.distance ?? -1,
        "distanceFromZoom": GoogleCameraSource.distance(
          zoom: Double(mapView.camera.zoom), latitude: mapView.camera.target.latitude, height: mapView.bounds.height),
        "focalLength": state?.focalLength ?? -1,
        "camera": GoogleOut.camera(mapView.camera),
        "centerX": Double(state?.centerPoint.x ?? -1), "centerY": Double(state?.centerPoint.y ?? -1),
        "width": Double(mapView.bounds.width), "height": Double(mapView.bounds.height),
      ])

    default:
      fail("unknown command \"\(command)\"")
    }
  }

  private func streetViewCommand(_ command: String, _ args: GoogleJSON, completion: @escaping (Result<Any, Error>) -> Void) {
    func done(_ value: Any = NSNull()) { completion(.success(value)) }
    func fail(_ message: String) { completion(.failure(MunimMapEngineError("Google Maps: \(message)"))) }
    switch command {
    case "open":
      openStreetView(args, completion: completion)
    case "close":
      closeStreetView()
      done()
    case "hasCoverage":
      guard let coordinate = args.coordinate else { return fail("hasCoverage needs latitude and longitude") }
      let source: GMSPanoramaSource = args["source"].string == "outdoor" ? .outside : .default
      panoramaService.requestPanoramaNearCoordinate(
        coordinate, radius: UInt(max(1, args["radius"].double(50))), source: source
      ) { panorama, _ in
        DispatchQueue.main.async { done(panorama.map(GoogleStreetView.info) ?? NSNull()) }
      }
    default:
      guard let street = streetView else { return fail("Street View is not open") }
      switch command {
      case "setCamera":
        street.setCamera(args, duration: args["duration"].double(0) / 1000)
        done()
      case "getCamera":
        done(street.cameraInfo)
      case "getLocation":
        done(street.info)
      case "moveTo":
        if let id = args["panoramaId"].string {
          street.panoramaView.move(toPanoramaID: id)
        } else if let c = args.coordinate {
          street.panoramaView.moveNearCoordinate(
            c, radius: UInt(max(1, args["radius"].double(50))),
            source: args["source"].string == "outdoor" ? .outside : .default)
        } else {
          return fail("moveTo needs latitude and longitude, or panoramaId")
        }
        done()
      case "setOptions":
        street.apply(args)
        done()
      case "orientationForPoint":
        let o = street.panoramaView.orientation(for: CGPoint(x: args["x"].double(0), y: args["y"].double(0)))
        done(["heading": o.heading, "pitch": o.pitch])
      case "pointForOrientation":
        let p = street.panoramaView.point(for: GMSOrientation(heading: args["heading"].double(0), pitch: args["pitch"].double(0)))
        done(["x": Double(p.x), "y": Double(p.y)])
      default:
        fail("unknown command \"streetView.\(command)\"")
      }
    }
  }
}
#endif
