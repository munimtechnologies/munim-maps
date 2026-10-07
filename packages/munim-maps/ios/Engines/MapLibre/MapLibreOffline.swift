#if canImport(MapLibre)
import Foundation
import MapLibre

/// MapLibre offline packs on iOS (`MLNOfflineStorage`): tile pyramids or
/// shapes, downloaded into MapLibre's database and used automatically
/// without a network. Packs carry JSON context (`{ name, metadata }`);
/// progress goes to every MapLibre map as `offlineProgress` /
/// `offlineError` events. The Android twin is MapLibreOffline.kt.
final class MapLibreOffline: NSObject {
  static let shared = MapLibreOffline()

  /// (event name, JSON payload) sinks: the maps on screen.
  private var sinks: [ObjectIdentifier: (String, String) -> Void] = [:]

  override init() {
    super.init()
    let center = NotificationCenter.default
    center.addObserver(self, selector: #selector(progress(_:)), name: .MLNOfflinePackProgressChanged, object: nil)
    center.addObserver(self, selector: #selector(failed(_:)), name: .MLNOfflinePackError, object: nil)
    center.addObserver(self, selector: #selector(limit(_:)), name: .MLNOfflinePackMaximumMapboxTilesReached, object: nil)
  }

  func add(sink owner: AnyObject, _ sink: @escaping (String, String) -> Void) {
    sinks[ObjectIdentifier(owner)] = sink
  }

  func remove(sink owner: AnyObject) {
    sinks[ObjectIdentifier(owner)] = nil
  }

  private func emit(_ name: String, _ payload: [String: Any]) {
    let json = (try? JSONSerialization.data(withJSONObject: payload)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    for sink in sinks.values { sink(name, json) }
  }

  private static func id(_ pack: MLNOfflinePack) -> String {
    pack.regionId.map { "\($0)" } ?? String(UInt(bitPattern: ObjectIdentifier(pack).hashValue))
  }

  static func json(_ pack: MLNOfflinePack) -> [String: Any] {
    let context = (try? JSONSerialization.jsonObject(with: pack.context)) as? [String: Any] ?? [:]
    let state: String
    switch pack.state {
    case .inactive: state = "inactive"
    case .active: state = "active"
    case .complete: state = "complete"
    case .invalid: state = "invalid"
    default: state = "unknown"
    }
    let p = pack.progress
    return [
      "id": id(pack),
      "name": context["name"] as? String ?? "",
      "metadata": context["metadata"] as? [String: Any] ?? [:],
      "state": state,
      "completedResources": p.countOfResourcesCompleted,
      "expectedResources": p.countOfResourcesExpected,
      "completedTiles": p.countOfTilesCompleted,
      "completedBytes": p.countOfBytesCompleted,
      "isComplete": pack.state == .complete,
    ]
  }

  @objc private func progress(_ note: Notification) {
    guard let pack = note.object as? MLNOfflinePack else { return }
    emit("offlineProgress", Self.json(pack))
  }

  @objc private func failed(_ note: Notification) {
    guard let pack = note.object as? MLNOfflinePack else { return }
    let error = note.userInfo?[MLNOfflinePackUserInfoKey.error] as? NSError
    emit("offlineError", ["id": Self.id(pack), "message": error?.localizedDescription ?? "unknown error"])
  }

  @objc private func limit(_ note: Notification) {
    guard let pack = note.object as? MLNOfflinePack else { return }
    emit("offlineError", ["id": Self.id(pack), "reason": "tileCountLimit", "message": "Tile count limit reached"])
  }

  private func pack(_ id: String) -> MLNOfflinePack? {
    MLNOfflineStorage.shared.packs?.first { Self.id($0) == id }
  }

  private func json(_ value: Any) -> String {
    (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
  }

  /// Runs an `offline…` command; false if `command` is not one.
  func run(_ command: String, args: [String: Any], styleURL: URL?, completion: @escaping (Result<String, Error>) -> Void) -> Bool {
    let storage = MLNOfflineStorage.shared
    func done(_ error: Error?) {
      if let error { completion(.failure(error)) } else { completion(.success("null")) }
    }
    func unknown() { completion(.failure(MapLibreStyleSpec.SpecError(message: "Unknown pack '\(args["id"] ?? "")'"))) }
    switch command {
    case "offlineCreatePack":
      let minZoom = (args["minZoom"] as? NSNumber)?.doubleValue ?? 0
      let maxZoom = (args["maxZoom"] as? NSNumber)?.doubleValue ?? 16
      let style = (args["styleUrl"] as? String).flatMap(URL.init(string:)) ?? styleURL
      let region: MLNOfflineRegion
      if let geometry = args["geometry"] as? [String: Any],
         let data = try? JSONSerialization.data(withJSONObject: geometry),
         let shape = try? MLNShape(data: data, encoding: String.Encoding.utf8.rawValue) {
        let r = MLNShapeOfflineRegion(styleURL: style, shape: shape, fromZoomLevel: minZoom, toZoomLevel: maxZoom)
        r.includesIdeographicGlyphs = args["includeIdeographs"] as? Bool ?? false
        region = r
      } else if let b = args["bounds"] as? [String: Any] {
        func n(_ k: String) -> Double { (b[k] as? NSNumber)?.doubleValue ?? 0 }
        let bounds = MLNCoordinateBounds(
          sw: CLLocationCoordinate2D(latitude: n("south"), longitude: n("west")),
          ne: CLLocationCoordinate2D(latitude: n("north"), longitude: n("east")))
        let r = MLNTilePyramidOfflineRegion(styleURL: style, bounds: bounds, fromZoomLevel: minZoom, toZoomLevel: maxZoom)
        r.includesIdeographicGlyphs = args["includeIdeographs"] as? Bool ?? false
        region = r
      } else {
        completion(.failure(MapLibreStyleSpec.SpecError(message: "offlineCreatePack needs bounds or geometry")))
        return true
      }
      let context: [String: Any] = ["name": args["name"] as? String ?? "", "metadata": args["metadata"] as? [String: Any] ?? [:]]
      let data = (try? JSONSerialization.data(withJSONObject: context)) ?? Data()
      storage.addPack(for: region, withContext: data) { pack, error in
        if let error { return completion(.failure(error)) }
        guard let pack else { return completion(.failure(MapLibreStyleSpec.SpecError(message: "no pack"))) }
        pack.resume()
        var out = Self.json(pack)
        out["state"] = "active"
        completion(.success(self.json(out)))
      }
    case "offlineListPacks":
      completion(.success(json((storage.packs ?? []).map(Self.json))))
    case "offlineResumePack":
      guard let pack = pack(args["id"] as? String ?? "") else { unknown(); return true }
      pack.resume()
      done(nil)
    case "offlineSuspendPack":
      guard let pack = pack(args["id"] as? String ?? "") else { unknown(); return true }
      pack.suspend()
      done(nil)
    case "offlineDeletePack":
      guard let pack = pack(args["id"] as? String ?? "") else { unknown(); return true }
      storage.removePack(pack) { done($0) }
    case "offlineInvalidatePack":
      guard let pack = pack(args["id"] as? String ?? "") else { unknown(); return true }
      storage.invalidatePack(pack) { done($0) }
    case "offlineSetAmbientCacheSize":
      storage.setMaximumAmbientCacheSize(UInt((args["bytes"] as? NSNumber)?.uint64Value ?? 50 * 1024 * 1024)) { done($0) }
    case "offlineClearAmbientCache":
      storage.clearAmbientCache { done($0) }
    case "offlineInvalidateAmbientCache":
      storage.invalidateAmbientCache { done($0) }
    case "offlineResetDatabase":
      storage.resetDatabase { done($0) }
    case "offlineMergeDatabase":
      storage.addContents(ofFile: args["path"] as? String ?? "") { _, packs, error in
        if let error { return completion(.failure(error)) }
        completion(.success(self.json((packs ?? []).map(Self.json))))
      }
    default:
      return false
    }
    return true
  }
}
#endif
