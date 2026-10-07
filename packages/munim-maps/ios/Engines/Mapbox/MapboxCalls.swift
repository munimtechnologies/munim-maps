#if canImport(MapboxMaps)
@_spi(Experimental) import MapboxMaps
import Combine
import MapKit
import UIKit

/// `mapboxMap(ref)` methods (`MapboxMapMethods` in src/providers/mapbox.ts),
/// called through `providerCall`.
enum MapboxCalls {
  typealias Completion = (Result<Any, Error>) -> Void

  static func call(_ method: String, args: [String: Any], engine e: MapboxMapEngine, completion: @escaping Completion) {
    let map = e.mapboxMap
    func done(_ value: Any = NSNull()) { completion(.success(value)) }
    func fail(_ message: String) { completion(.failure(MunimMapEngineError("Mapbox \(method): \(message)"))) }
    func string(_ key: String) -> String? { args[key] as? String }
    func run(_ body: () throws -> Any) {
      do { completion(.success(try body())) } catch { completion(.failure(error)) }
    }
    func nullCallback(_ result: Result<NSNull, Error>) {
      switch result {
      case .success: done()
      case .failure(let error): completion(.failure(error))
      }
    }

    switch method {
    // MARK: Queries
    case "queryRenderedFeatures":
      let filter = args["filter"].flatMap { try? MapboxJSON.decode(Exp.self, from: $0) }
      if let set = featureset(args["featureset"]) {
        let finish: (Result<[FeaturesetFeature], Error>) -> Void = { result in
          switch result {
          case .success(let features): done(features.map(featuresetFeatureJSON))
          case .failure(let error): completion(.failure(error))
          }
        }
        if let point = point(args["point"]) {
          map.queryRenderedFeatures(with: point, featureset: set, filter: filter, completion: finish)
        } else if let box = box(args["box"]) {
          map.queryRenderedFeatures(with: box, featureset: set, filter: filter, completion: finish)
        } else {
          map.queryRenderedFeatures(featureset: set, filter: filter, completion: finish)
        }
        return
      }
      let options = RenderedQueryOptions(layerIds: args["layerIds"] as? [String], filter: filter)
      let finish: (Result<[QueriedRenderedFeature], Error>) -> Void = { result in
        switch result {
        case .success(let features):
          done(features.map { f -> [String: Any] in
            var json = queriedFeatureJSON(f.queriedFeature)
            json["layers"] = f.layers
            return json
          })
        case .failure(let error): completion(.failure(error))
        }
      }
      if let point = point(args["point"]) {
        _ = map.queryRenderedFeatures(with: point, options: options, completion: finish)
      } else if let box = box(args["box"]) {
        _ = map.queryRenderedFeatures(with: box, options: options, completion: finish)
      } else {
        _ = map.queryRenderedFeatures(with: CGRect(origin: .zero, size: e.mapView.bounds.size), options: options, completion: finish)
      }

    case "querySourceFeatures":
      guard let sourceId = string("sourceId") else { return fail("needs sourceId") }
      let filter = args["filter"] ?? ["has", "$type"]
      let options = SourceQueryOptions(sourceLayerIds: args["sourceLayerIds"] as? [String], filter: filter)
      map.querySourceFeatures(for: sourceId, options: options) { result in
        switch result {
        case .success(let features): done(features.map { queriedFeatureJSON($0.queriedFeature) })
        case .failure(let error): completion(.failure(error))
        }
      }

    case "getClusterExpansionZoom", "getClusterLeaves", "getClusterChildren":
      guard let sourceId = string("sourceId"), let clusterJSON = args["cluster"],
            let cluster = try? MapboxJSON.decode(Feature.self, from: clusterJSON) else { return fail("needs sourceId and cluster") }
      let finish: (Result<FeatureExtensionValue, Error>) -> Void = { result in
        switch result {
        case .success(let value):
          if method == "getClusterExpansionZoom" {
            done(value.value ?? NSNull())
          } else {
            done((value.features ?? []).map { MapboxJSON.plain($0) })
          }
        case .failure(let error): completion(.failure(error))
        }
      }
      switch method {
      case "getClusterExpansionZoom":
        map.getGeoJsonClusterExpansionZoom(forSourceId: sourceId, feature: cluster, completion: finish)
      case "getClusterLeaves":
        map.getGeoJsonClusterLeaves(
          forSourceId: sourceId, feature: cluster,
          limit: UInt64(MapboxJSON.double(args["limit"]) ?? 10), offset: UInt64(MapboxJSON.double(args["offset"]) ?? 0),
          completion: finish)
      default:
        map.getGeoJsonClusterChildren(forSourceId: sourceId, feature: cluster, completion: finish)
      }

    // MARK: Feature state
    case "setFeatureState", "getFeatureState", "removeFeatureState":
      guard let featureId = string("featureId") ?? MapboxJSON.double(args["featureId"]).map({ String(Int($0)) }) else {
        return fail("needs featureId")
      }
      if let set = featureset(args["featureset"]) {
        let id = FeaturesetFeatureId(id: featureId, namespace: string("featureNamespace"))
        switch method {
        case "setFeatureState":
          guard let stateJSON = args["state"], let state = try? MapboxJSON.decode(JSONObject.self, from: stateJSON) else {
            return fail("needs state")
          }
          map.setFeatureState(featureset: set, featureId: id, state: state) { error in
            if let error { completion(.failure(error)) } else { done() }
          }
        case "getFeatureState":
          map.getFeatureState(featureset: set, featureId: id) { result in
            switch result {
            case .success(let state): done(MapboxJSON.plain(state))
            case .failure(let error): completion(.failure(error))
            }
          }
        default:
          map.removeFeatureState(featureset: set, featureId: id, stateKey: string("stateKey")) { error in
            if let error { completion(.failure(error)) } else { done() }
          }
        }
        return
      }
      guard let sourceId = string("sourceId") else { return fail("needs sourceId or featureset") }
      let layer = string("sourceLayerId")
      switch method {
      case "setFeatureState":
        guard let state = args["state"] as? [String: Any] else { return fail("needs state") }
        _ = map.setFeatureState(sourceId: sourceId, sourceLayerId: layer, featureId: featureId, state: state, callback: nullCallback)
      case "getFeatureState":
        _ = map.getFeatureState(sourceId: sourceId, sourceLayerId: layer, featureId: featureId) { result in
          switch result {
          case .success(let state): done(state)
          case .failure(let error): completion(.failure(error))
          }
        }
      default:
        _ = map.removeFeatureState(
          sourceId: sourceId, sourceLayerId: layer, featureId: featureId, stateKey: string("stateKey"), callback: nullCallback)
      }

    case "resetFeatureStates":
      if let set = featureset(args["featureset"]) {
        map.resetFeatureStates(featureset: set) { error in
          if let error { completion(.failure(error)) } else { done() }
        }
      } else if let sourceId = string("sourceId") {
        _ = map.resetFeatureStates(sourceId: sourceId, sourceLayerId: string("sourceLayerId"), callback: nullCallback)
      } else {
        fail("needs sourceId or featureset")
      }

    // MARK: Sources and layers
    case "updateGeoJSONSource":
      guard let sourceId = string("sourceId"), let data = args["data"] else { return fail("needs sourceId and data") }
      run {
        let text = (data as? String) ?? MunimProviderJSON.string(data)
        if text.hasPrefix("http") || text.hasPrefix("mapbox:") {
          map.updateGeoJSONSource(withId: sourceId, data: .url(URL(string: text)!), dataId: string("dataId"))
        } else {
          map.updateGeoJSONSource(withId: sourceId, data: .string(text), dataId: string("dataId"))
        }
        return NSNull()
      }
    case "addGeoJSONSourceFeatures", "updateGeoJSONSourceFeatures":
      guard let sourceId = string("sourceId"), let list = args["features"] as? [Any] else { return fail("needs sourceId and features") }
      run {
        let features = try list.map { try MapboxJSON.decode(Feature.self, from: $0) }
        if method == "addGeoJSONSourceFeatures" {
          map.addGeoJSONSourceFeatures(forSourceId: sourceId, features: features, dataId: string("dataId"))
        } else {
          map.updateGeoJSONSourceFeatures(forSourceId: sourceId, features: features, dataId: string("dataId"))
        }
        return NSNull()
      }
    case "removeGeoJSONSourceFeatures":
      guard let sourceId = string("sourceId"), let ids = args["featureIds"] as? [String] else { return fail("needs sourceId and featureIds") }
      map.removeGeoJSONSourceFeatures(forSourceId: sourceId, featureIds: ids, dataId: string("dataId"))
      done()
    case "setLayerProperties":
      guard let id = string("layerId"), let properties = args["properties"] as? [String: Any] else { return fail("needs layerId and properties") }
      run { try map.setLayerProperties(for: id, properties: properties); return NSNull() }
    case "getLayerProperties":
      guard let id = string("layerId") else { return fail("needs layerId") }
      run { try map.layerProperties(for: id) }
    case "setSourceProperties":
      guard let id = string("sourceId"), let properties = args["properties"] as? [String: Any] else { return fail("needs sourceId and properties") }
      run { try map.setSourceProperties(for: id, properties: properties); return NSNull() }
    case "getSourceProperties":
      guard let id = string("sourceId") else { return fail("needs sourceId") }
      run { try map.sourceProperties(for: id) }
    case "moveLayer":
      guard let id = string("layerId") else { return fail("needs layerId") }
      run {
        if let slot = string("slot") { try map.setLayerProperty(for: id, property: "slot", value: slot) }
        if let position = MapboxMapEngine.layerPosition(args) { try map.moveLayer(withId: id, to: position) }
        return NSNull()
      }
    case "getStyleJson":
      done(map.styleJSON)
    case "getLayers":
      done(map.allLayerIdentifiers.map { ["id": $0.id, "type": $0.type.rawValue] })
    case "getSources":
      done(map.allSourceIdentifiers.map { ["id": $0.id, "type": $0.type.rawValue] })
    case "getSlots":
      done(map.allSlotIdentifiers.map(\.rawValue))
    case "getStyleImports":
      done(map.styleImports.map { ["id": $0.id, "type": $0.type] })
    case "getStyleImportSchema":
      guard let id = string("importId") else { return fail("needs importId") }
      run { try map.getStyleImportSchema(for: id) }
    case "getStyleImportConfig":
      guard let id = string("importId") else { return fail("needs importId") }
      run { try map.getStyleImportConfigProperties(for: id).mapValues { $0.value } }
    case "setStyleImportConfig":
      guard let id = string("importId"), let config = args["config"] as? [String: Any] else { return fail("needs importId and config") }
      run { try map.setStyleImportConfigProperties(for: id, configs: config); return NSNull() }
    case "getFeaturesets":
      done(map.featuresets.map {
        ["featuresetId": $0.featuresetId ?? NSNull(), "importId": $0.importId ?? NSNull(), "layerId": $0.layerId ?? NSNull()]
      })

    // MARK: Camera
    case "getCameraState":
      done(cameraStateJSON(map.cameraState))
    case "setCamera":
      e.stopFlight()
      map.setCamera(to: cameraOptions(args["camera"]))
      done()
    case "easeTo":
      e.stopFlight()
      let curve: UIView.AnimationCurve
      switch string("curve") {
      case "linear": curve = .linear
      case "easeIn": curve = .easeIn
      case "easeOut": curve = .easeOut
      default: curve = .easeInOut
      }
      e.mapView.camera.ease(
        to: cameraOptions(args["camera"]), duration: (MapboxJSON.double(args["duration"]) ?? 500) / 1000, curve: curve
      ) { position in done(position == .end) }
    case "flyTo":
      e.stopFlight()
      e.mapView.camera.fly(to: cameraOptions(args["camera"]), duration: MapboxJSON.double(args["duration"]).map { $0 / 1000 }) {
        position in done(position == .end)
      }
    case "cancelCameraAnimations":
      e.mapView.camera.cancelAnimations()
      e.stopFlight()
      done()
    case "cameraForCoordinates":
      let coordinates = (args["coordinates"] as? [Any] ?? []).compactMap(MapboxJSON.coordinate)
      guard !coordinates.isEmpty else { return fail("needs coordinates") }
      run {
        let base = CameraOptions(
          bearing: MapboxJSON.double(args["bearing"]), pitch: MapboxJSON.double(args["pitch"]).map { CGFloat($0) })
        let camera = try map.camera(
          for: coordinates, camera: base, coordinatesPadding: MapboxJSON.insets(args["padding"]),
          maxZoom: MapboxJSON.double(args["maxZoom"]), offset: nil)
        return cameraOptionsJSON(camera)
      }
    case "getBounds":
      let b = map.coordinateBounds(for: CameraOptions(cameraState: map.cameraState))
      done(["southwest": coordinateJSON(b.southwest), "northeast": coordinateJSON(b.northeast)])
    case "getElevation":
      guard let c = MapboxJSON.coordinate(args) else { return fail("needs latitude and longitude") }
      done(map.elevation(at: c) ?? NSNull())
    case "setViewport":
      setViewport(args, engine: e, completion: completion)

    case "getFreeCamera":
      let free = map.freeCameraOptions
      done(["position": ["latitude": free.location.latitude, "longitude": free.location.longitude, "altitude": free.altitude]])
    case "setFreeCamera":
      e.stopFlight()
      let free = map.freeCameraOptions
      if let p = args["position"] as? [String: Any], let c = MapboxJSON.coordinate(p) {
        free.location = c
        if let altitude = MapboxJSON.double(p["altitude"]) { free.altitude = altitude }
      }
      if let l = args["lookAt"] as? [String: Any], let c = MapboxJSON.coordinate(l) {
        free.lookAtPoint(forLocation: c, altitude: MapboxJSON.double(l["altitude"]) ?? 0)
      } else if let pitch = MapboxJSON.double(args["pitch"]), let bearing = MapboxJSON.double(args["bearing"]) {
        free.setPitchBearingForPitch(pitch, bearing: bearing)
      }
      map.freeCameraOptions = free
      done()
    case "getCameraBounds":
      let b = map.cameraBounds
      done(["bounds": ["southwest": coordinateJSON(b.bounds.southwest), "northeast": coordinateJSON(b.bounds.northeast)],
            "minZoom": b.minZoom, "maxZoom": b.maxZoom, "minPitch": b.minPitch, "maxPitch": b.maxPitch])
    case "getStyleDefaultCamera":
      done(cameraOptionsJSON(map.styleDefaultCamera))
    case "tileCover":
      let tiles = map.tileCover(for: TileCoverOptions(
        tileSize: UInt16(MapboxJSON.double(args["tileSize"]) ?? 512),
        minZoom: UInt8(MapboxJSON.double(args["minZoom"]) ?? 0),
        maxZoom: UInt8(MapboxJSON.double(args["maxZoom"]) ?? 22),
        roundZoom: MapboxJSON.bool(args["roundZoom"]) ?? false))
      done(tiles.map { ["z": Int($0.canonical.z), "x": Int($0.canonical.x), "y": Int($0.canonical.y),
                        "overscaledZ": Int($0.overscaledZ), "wrap": Int($0.wrap)] })
    case "collectPerformanceStatistics":
      let duration = MapboxJSON.double(args["durationMs"]) ?? 1000
      var token: AnyCancelable?
      token = map.collectPerformanceStatistics(
        PerformanceStatisticsOptions([.cumulative, .perFrame], samplingDurationMillis: duration)
      ) { stats in
        var json: [String: Any] = [
          "collectionDurationMillis": stats.collectionDurationMillis,
          "mapRenderDuration": ["maxMillis": stats.mapRenderDurationStatistics.maxMillis,
                                "medianMillis": stats.mapRenderDurationStatistics.medianMillis],
        ]
        if let c = stats.cumulativeStatistics {
          json["cumulative"] = ["drawCalls": c.drawCalls ?? NSNull(), "textureBytes": c.textureBytes ?? NSNull(),
                                "vertexBytes": c.vertexBytes ?? NSNull()]
        }
        done(json)
        token = nil
      }
      _ = token
    case "setLocationOverride":
      guard let c = MapboxJSON.coordinate(args) else { return fail("needs latitude and longitude") }
      let clLocation = CLLocation(
        coordinate: c, altitude: MapboxJSON.double(args["altitude"]) ?? 0,
        horizontalAccuracy: MapboxJSON.double(args["accuracy"]) ?? 5, verticalAccuracy: 5,
        course: MapboxJSON.double(args["course"]) ?? -1, speed: MapboxJSON.double(args["speed"]) ?? -1,
        timestamp: Date())
      let location = Location(clLocation: clLocation)
      let heading = Heading(direction: MapboxJSON.double(args["heading"]) ?? clLocation.course, accuracy: 5)
      if let subject = e.content.locationSubject {
        subject.send([location])
        e.content.headingSubject?.send(heading)
      } else {
        let subject = CurrentValueSubject<[Location], Never>([location])
        let headings = CurrentValueSubject<Heading, Never>(heading)
        e.content.locationSubject = subject
        e.content.headingSubject = headings
        e.content.originalDataModel = e.mapView.location.dataModel
        e.mapView.location.dataModel = LocationDataModel(
          location: subject.eraseToAnyPublisher(), heading: headings.eraseToAnyPublisher())
      }
      done()
    case "clearLocationOverride":
      if let original = e.content.originalDataModel { e.mapView.location.dataModel = original }
      e.content.locationSubject = nil
      e.content.headingSubject = nil
      e.content.originalDataModel = nil
      done()

    // MARK: Snapshots and housekeeping
    case "snapshot":
      MapboxSnapshots.snapshot(args, engine: e, completion: completion)
    case "triggerRepaint":
      map.triggerRepaint()
      done()
    case "reduceMemoryUse":
      map.reduceMemoryUse()
      done()

    default:
      completion(.failure(MunimMapEngineError("Mapbox has no method \"\(method)\"")))
    }
  }

  // MARK: Viewport

  private static func setViewport(_ args: [String: Any], engine e: MapboxMapEngine, completion: @escaping Completion) {
    let viewport: ViewportManager = e.mapView.viewport
    let transition: ViewportTransition? = MapboxJSON.double(args["duration"]).map { duration in
      duration <= 0 ? viewport.makeImmediateViewportTransition() as ViewportTransition
        : viewport.makeDefaultViewportTransition(options: DefaultViewportTransitionOptions(maxDuration: duration / 1000))
    }
    switch args["state"] as? String {
    case "followPuck":
      let bearing: FollowPuckViewportStateBearing
      switch args["bearing"] {
      case let name as String where name == "course": bearing = .course
      case let name as String where name == "heading": bearing = .heading
      default: bearing = MapboxJSON.double(args["bearing"]).map { .constant($0) } ?? .heading
      }
      let state = viewport.makeFollowPuckViewportState(options: FollowPuckViewportStateOptions(
        padding: MapboxJSON.insets(args["padding"]),
        zoom: MapboxJSON.double(args["zoom"]).map { CGFloat($0) } ?? 16.35,
        bearing: bearing,
        pitch: MapboxJSON.double(args["pitch"]).map { CGFloat($0) } ?? 45))
      viewport.transition(to: state, transition: transition) { completion(.success($0)) }
    case "overview":
      let coordinates = (args["coordinates"] as? [Any] ?? []).compactMap(MapboxJSON.coordinate)
      guard !coordinates.isEmpty else {
        return completion(.failure(MunimMapEngineError("Mapbox setViewport: overview needs coordinates")))
      }
      let geometry: Geometry = coordinates.count == 1 ? .point(Point(coordinates[0])) : .lineString(LineString(coordinates))
      let state = viewport.makeOverviewViewportState(options: OverviewViewportStateOptions(
        geometry: geometry,
        geometryPadding: MapboxJSON.insets(args["padding"]) ?? .zero,
        bearing: MapboxJSON.double(args["bearing"]) ?? 0,
        pitch: MapboxJSON.double(args["pitch"]).map { CGFloat($0) } ?? 0,
        animationDuration: (MapboxJSON.double(args["duration"]) ?? 1000) / 1000))
      viewport.transition(to: state, transition: transition) { completion(.success($0)) }
    default:
      viewport.idle()
      completion(.success(true))
    }
  }

  // MARK: JSON

  static func featureset(_ value: Any?) -> FeaturesetDescriptor<FeaturesetFeature>? {
    guard let d = value as? [String: Any] else { return nil }
    if let id = d["featuresetId"] as? String { return .featureset(id, importId: d["importId"] as? String ?? "basemap") }
    if let layer = d["layerId"] as? String { return .layer(layer) }
    return nil
  }

  static func point(_ value: Any?) -> CGPoint? {
    guard let d = value as? [String: Any], let x = MapboxJSON.double(d["x"]), let y = MapboxJSON.double(d["y"]) else { return nil }
    return CGPoint(x: x, y: y)
  }

  static func box(_ value: Any?) -> CGRect? {
    guard let d = value as? [String: Any], let x1 = MapboxJSON.double(d["x1"]), let y1 = MapboxJSON.double(d["y1"]),
          let x2 = MapboxJSON.double(d["x2"]), let y2 = MapboxJSON.double(d["y2"]) else { return nil }
    return CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
  }

  static func coordinateJSON(_ c: CLLocationCoordinate2D) -> [String: Any] {
    ["latitude": c.latitude, "longitude": c.longitude]
  }

  static func insetsJSON(_ i: UIEdgeInsets) -> [String: Any] {
    ["top": i.top, "left": i.left, "bottom": i.bottom, "right": i.right]
  }

  static func cameraStateJSON(_ s: CameraState) -> [String: Any] {
    ["center": coordinateJSON(s.center), "zoom": s.zoom, "bearing": s.bearing, "pitch": s.pitch,
     "padding": insetsJSON(s.padding)]
  }

  static func cameraOptionsJSON(_ c: CameraOptions) -> [String: Any] {
    var json: [String: Any] = [:]
    if let center = c.center { json["center"] = coordinateJSON(center) }
    if let zoom = c.zoom { json["zoom"] = zoom }
    if let bearing = c.bearing { json["bearing"] = bearing }
    if let pitch = c.pitch { json["pitch"] = pitch }
    if let padding = c.padding { json["padding"] = insetsJSON(padding) }
    return json
  }

  static func cameraOptions(_ value: Any?) -> CameraOptions {
    let d = value as? [String: Any] ?? [:]
    return CameraOptions(
      center: MapboxJSON.coordinate(d["center"]),
      padding: MapboxJSON.insets(d["padding"]),
      anchor: point(d["anchor"]),
      zoom: MapboxJSON.double(d["zoom"]).map { CGFloat($0) },
      bearing: MapboxJSON.double(d["bearing"]),
      pitch: MapboxJSON.double(d["pitch"]).map { CGFloat($0) })
  }

  static func queriedFeatureJSON(_ q: QueriedFeature) -> [String: Any] {
    ["feature": MapboxJSON.plain(q.feature), "source": q.source, "sourceLayer": q.sourceLayer ?? NSNull(),
     "state": q.state]
  }

  static func featuresetFeatureJSON(_ f: FeaturesetFeature) -> [String: Any] {
    ["feature": MapboxJSON.plain(f.originalFeature),
     "source": "", "state": MapboxJSON.plain(f.state),
     "featureId": f.id?.id ?? NSNull(), "featureNamespace": f.id?.namespace ?? NSNull(),
     "featureset": ["featuresetId": f.featureset.featuresetId ?? NSNull(),
                    "importId": f.featureset.importId ?? NSNull(),
                    "layerId": f.featureset.layerId ?? NSNull()]]
  }
}

/// Off-screen maps drawn by Mapbox's `Snapshotter`.
enum MapboxSnapshots {
  /// Kept alive until they finish.
  private static var running: [UUID: Snapshotter] = [:]

  static func snapshot(_ args: [String: Any], engine e: MapboxMapEngine, completion: @escaping MapboxCalls.Completion) {
    let width = MapboxJSON.double(args["width"]) ?? Double(e.mapView.bounds.width)
    let height = MapboxJSON.double(args["height"]) ?? Double(e.mapView.bounds.height)
    guard width >= 1, height >= 1 else {
      return completion(.failure(MunimMapEngineError("Mapbox snapshot: needs a size")))
    }
    var options = MapSnapshotOptions(
      size: CGSize(width: width, height: height),
      pixelRatio: CGFloat(MapboxJSON.double(args["pixelRatio"]) ?? Double(UIScreen.main.scale)))
    options.showsLogo = MapboxJSON.bool(args["showsLogo"]) ?? true
    options.showsAttribution = MapboxJSON.bool(args["showsAttribution"]) ?? true
    let snapshotter = Snapshotter(options: options)
    let id = UUID()
    running[id] = snapshotter
    if let json = args["styleJson"] {
      snapshotter.styleJSON = (json as? String) ?? MunimProviderJSON.string(json)
    } else if let url = args["styleUrl"] as? String, let uri = StyleURI(rawValue: url) {
      snapshotter.styleURI = uri
    } else if let uri = e.mapboxMap.styleURI {
      snapshotter.styleURI = uri
    } else {
      snapshotter.styleJSON = e.mapboxMap.styleJSON
    }
    if let camera = args["camera"] {
      snapshotter.setCamera(to: MapboxCalls.cameraOptions(camera))
    } else {
      snapshotter.setCamera(to: CameraOptions(cameraState: e.mapboxMap.cameraState))
    }
    snapshotter.start(overlayHandler: nil) { result in
      running[id] = nil
      switch result {
      case .success(let image):
        completion(Result { try MapboxFiles.writePNG(image, prefix: "mapbox-snapshotter").path })
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }
}
#endif
