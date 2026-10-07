#if canImport(MapboxMaps)
import MapboxMaps
import MapKit
import UIKit

/// `MapboxOffline` (src/providers/mapbox.ts): style packs from Mapbox's
/// `OfflineManager` and tile regions from its `TileStore`. Needs no map.
enum MapboxOffline {
  typealias Completion = (Result<Any, Error>) -> Void

  private static let offlineManager = OfflineManager()
  private static var tileStore: TileStore { TileStore.default }
  /// Downloads in flight, by tile region id or style URL, for `cancel`.
  private static var downloads: [String: Cancelable] = [:]

  static func call(
    _ method: String, args: [String: Any], emit: @escaping (String, Any) -> Void, completion: @escaping Completion
  ) {
    let token = MunimMapsConfiguration.shared.mapboxAccessToken
    if !token.isEmpty, MapboxOptions.accessToken != token { MapboxOptions.accessToken = token }
    @Sendable func main(_ result: Result<Any, Error>) { DispatchQueue.main.async { completion(result) } }
    func fail(_ message: String) { completion(.failure(MunimMapEngineError("Mapbox \(method): \(message)"))) }

    switch method {
    case "offline.loadStylePack":
      guard let url = args["styleUri"] as? String, let uri = StyleURI(rawValue: url) else { return fail("needs styleUri") }
      guard let options = StylePackLoadOptions(
        glyphsRasterizationMode: glyphsMode(args["glyphsRasterizationMode"]),
        metadata: args["metadata"], acceptExpired: MapboxJSON.bool(args["acceptExpired"]) ?? false)
      else { return fail("metadata must be JSON") }
      downloads[url]?.cancel()
      downloads[url] = offlineManager.loadStylePack(for: uri, loadOptions: options, progress: { p in
        let payload: [String: Any] = [
          "id": url, "kind": "stylePack",
          "requiredResourceCount": p.requiredResourceCount, "completedResourceCount": p.completedResourceCount,
          "completedResourceSize": p.completedResourceSize, "erroredResourceCount": p.erroredResourceCount,
          "loadedResourceCount": p.loadedResourceCount, "loadedResourceSize": p.loadedResourceSize,
        ]
        DispatchQueue.main.async { emit("offline.progress", payload) }
      }, completion: { result in
        DispatchQueue.main.async { downloads[url] = nil }
        main(result.map(stylePackJSON))
      })

    case "offline.loadTileRegion", "offline.estimateTileRegion":
      let id = args["id"] as? String ?? "estimate-\(UUID().uuidString)"
      guard let geometry = geometry(args) else { return fail("needs geometry or bounds") }
      let styleURI = (args["styleUri"] as? String).flatMap(StyleURI.init(rawValue:)) ?? .standard
      let minZoom = UInt8(max(0, min(22, MapboxJSON.double(args["minZoom"]) ?? 0)))
      let maxZoom = UInt8(max(Double(minZoom), min(22, MapboxJSON.double(args["maxZoom"]) ?? 16)))
      let descriptor = offlineManager.createTilesetDescriptor(for: TilesetDescriptorOptions(
        styleURI: styleURI, zoomRange: minZoom...maxZoom,
        pixelRatio: MapboxJSON.double(args["pixelRatio"]).map(Float.init),
        tilesets: args["tilesets"] as? [String]))
      let restriction: NetworkRestriction
      switch args["networkRestriction"] as? String {
      case "disallowExpensive": restriction = .disallowExpensive
      case "disallowAll": restriction = .disallowAll
      default: restriction = .none
      }
      guard let options = TileRegionLoadOptions(
        geometry: geometry, descriptors: [descriptor], metadata: args["metadata"],
        acceptExpired: MapboxJSON.bool(args["acceptExpired"]) ?? false, networkRestriction: restriction)
      else { return fail("metadata must be JSON") }
      if method == "offline.estimateTileRegion" {
        tileStore.estimateTileRegion(forId: id, loadOptions: options, progress: { _ in }, completion: { result in
          main(result.map { ["storageSize": $0.storageSize, "transferSize": $0.transferSize] as [String: Any] })
        })
        return
      }
      downloads[id]?.cancel()
      downloads[id] = tileStore.loadTileRegion(forId: id, loadOptions: options, progress: { p in
        let payload: [String: Any] = [
          "id": id, "kind": "tileRegion",
          "requiredResourceCount": p.requiredResourceCount, "completedResourceCount": p.completedResourceCount,
          "completedResourceSize": p.completedResourceSize, "erroredResourceCount": p.erroredResourceCount,
          "loadedResourceCount": p.loadedResourceCount, "loadedResourceSize": p.loadedResourceSize,
        ]
        DispatchQueue.main.async { emit("offline.progress", payload) }
      }, completion: { result in
        DispatchQueue.main.async { downloads[id] = nil }
        main(result.map(tileRegionJSON))
      })

    case "accessToken":
      // For MapboxServices in JavaScript: the public token the app has.
      completion(.success(MapboxOptions.accessToken))
    case "offline.cancel":
      guard let id = args["id"] as? String else { return fail("needs id") }
      let download = downloads.removeValue(forKey: id)
      download?.cancel()
      completion(.success(download != nil))

    case "offline.tileRegions":
      tileStore.allTileRegions { main($0.map { $0.map(tileRegionJSON) }) }
    case "offline.tileRegion":
      guard let id = args["id"] as? String else { return fail("needs id") }
      tileStore.tileRegion(forId: id) { main($0.map(tileRegionJSON)) }
    case "offline.tileRegionMetadata":
      guard let id = args["id"] as? String else { return fail("needs id") }
      tileStore.tileRegionMetadata(forId: id) { main($0.map { $0 as Any }) }
    case "offline.removeTileRegion":
      guard let id = args["id"] as? String else { return fail("needs id") }
      tileStore.removeRegion(forId: id) { result in main(result.map { _ in NSNull() }) }
    case "offline.stylePacks":
      offlineManager.allStylePacks { main($0.map { $0.map(stylePackJSON) }) }
    case "offline.stylePackMetadata":
      guard let url = args["styleUri"] as? String, let uri = StyleURI(rawValue: url) else { return fail("needs styleUri") }
      offlineManager.stylePackMetadata(for: uri) { main($0.map { $0 as Any }) }
    case "offline.removeStylePack":
      guard let url = args["styleUri"] as? String, let uri = StyleURI(rawValue: url) else { return fail("needs styleUri") }
      offlineManager.removeStylePack(for: uri) { result in main(result.map { _ in NSNull() }) }
    case "offline.setTileStoreQuota":
      guard let bytes = MapboxJSON.double(args["bytes"]) else { return fail("needs bytes") }
      tileStore.setOptionForKey(TileStoreOptions.diskQuota, value: Int(bytes))
      completion(.success(NSNull()))
    case "offline.setConnected":
      OfflineSwitch.shared.isMapboxStackConnected = MapboxJSON.bool(args["connected"]) ?? true
      completion(.success(NSNull()))
    case "offline.clearData":
      MapboxMap.clearData { error in
        if let error { main(.failure(error)) } else { main(.success(NSNull())) }
      }
    default:
      completion(.failure(MunimMapEngineError("Mapbox has no method \"\(method)\"")))
    }
  }

  private static func glyphsMode(_ value: Any?) -> GlyphsRasterizationMode {
    switch value as? String {
    case "allGlyphsRasterizedLocally": return .allGlyphsRasterizedLocally
    case "noGlyphsRasterizedLocally": return .noGlyphsRasterizedLocally
    default: return .ideographsRasterizedLocally
    }
  }

  private static func geometry(_ args: [String: Any]) -> Geometry? {
    if let json = args["geometry"], let geometry = try? MapboxJSON.decode(Geometry.self, from: json) { return geometry }
    guard let bounds = args["bounds"] as? [String: Any],
          let sw = MapboxJSON.coordinate(bounds["southwest"]), let ne = MapboxJSON.coordinate(bounds["northeast"])
    else { return nil }
    let nw = CLLocationCoordinate2D(latitude: ne.latitude, longitude: sw.longitude)
    let se = CLLocationCoordinate2D(latitude: sw.latitude, longitude: ne.longitude)
    return .polygon(Polygon([[sw, se, ne, nw, sw]]))
  }

  private static func tileRegionJSON(_ r: TileRegion) -> Any {
    var json: [String: Any] = [
      "id": r.id, "requiredResourceCount": r.requiredResourceCount,
      "completedResourceCount": r.completedResourceCount, "completedResourceSize": r.completedResourceSize,
    ]
    if let expires = r.expires { json["expires"] = expires.timeIntervalSince1970 * 1000 }
    return json
  }

  private static func stylePackJSON(_ p: StylePack) -> Any {
    var json: [String: Any] = [
      "styleUri": p.styleURI, "requiredResourceCount": p.requiredResourceCount,
      "completedResourceCount": p.completedResourceCount, "completedResourceSize": p.completedResourceSize,
      "glyphsRasterizationMode": String(describing: p.glyphsRasterizationMode),
    ]
    if let expires = p.expires { json["expires"] = expires.timeIntervalSince1970 * 1000 }
    return json
  }
}
#endif
