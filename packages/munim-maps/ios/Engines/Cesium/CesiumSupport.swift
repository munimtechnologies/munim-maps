#if MUNIM_MAPS_CESIUM
import CoreLocation
import Foundation
import UIKit
import WebKit
import simd

// The Cesium engine's plumbing: serving the bundled CesiumJS to the
// WebView, values to JSON, and Cesium's camera maths for the synchronous
// getters (point <-> coordinate) without a round trip to JavaScript.

/// Serves `munim-cesium://app/…` to the engine's WKWebView:
/// - `/…` the engine's page (`MunimMapsCesium.bundle/munim-cesium`),
/// - `/Cesium/…` CesiumJS: bundled (`MUNIM_MAPS_CESIUM_BUNDLED`), or from
///   jsDelivr at the pinned version, kept on disk after the first load (so
///   the page stays same-origin and works offline afterwards),
/// - `/resource?uri=…` the app's files (`file://`, paths, Metro's `http://`),
/// - `/tile/<host>/<path>` https tiles fetched with an identifying
///   User-Agent (OpenStreetMap's tile policy asks apps to identify
///   themselves; WebKit sends no Referer from a custom scheme).
final class CesiumSchemeHandler: NSObject, WKURLSchemeHandler {
  static let scheme = "munim-cesium"
  static let base = "munim-cesium://app/"

  /// The `munim-cesium` folder in the pod's resource bundle.
  static let root: URL? = {
    let bundles = [Bundle(for: CesiumSchemeHandler.self), Bundle.main]
    for bundle in bundles {
      if let url = bundle.url(forResource: "MunimMapsCesium", withExtension: "bundle"),
         let resources = Bundle(url: url)?.resourceURL
      {
        let folder = resources.appendingPathComponent("munim-cesium")
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent("index.html").path) { return folder }
      }
      if let folder = bundle.resourceURL?.appendingPathComponent("munim-cesium"),
         FileManager.default.fileExists(atPath: folder.appendingPathComponent("index.html").path)
      {
        return folder
      }
    }
    return nil
  }()

  private var active = Set<ObjectIdentifier>()
  private let queue = DispatchQueue(label: "munim-maps.cesium.files", qos: .userInitiated, attributes: .concurrent)

  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 256 << 20, diskPath: "munim-maps-cesium-tiles")
    configuration.requestCachePolicy = .useProtocolCachePolicy
    configuration.httpMaximumConnectionsPerHost = 6
    return URLSession(configuration: configuration)
  }()

  static let userAgent: String = {
    let app = Bundle.main.bundleIdentifier ?? "app"
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1"
    return "munim-maps-cesium/1.0 (\(app)/\(version); +https://github.com/munimtechnologies/munim-maps)"
  }()

  func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
    let id = ObjectIdentifier(task)
    active.insert(id)
    guard let url = task.request.url else { return fail(task, status: 400) }
    let path = url.path
    if path == "/resource" {
      let uri = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "uri" }?.value ?? ""
      return resource(uri, task: task)
    }
    if path.hasPrefix("/tile/") {
      var target = "https://" + path.dropFirst("/tile/".count)
      if let query = url.query { target += "?" + query }
      return fetch(target, task: task)
    }
    guard let root = Self.root else { return fail(task, status: 404) }
    let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
    if relative.hasPrefix("Cesium/") { return cesiumJS(String(relative.dropFirst("Cesium/".count)), task: task) }
    let file = root.appendingPathComponent(relative.isEmpty ? "index.html" : relative).standardizedFileURL
    guard file.path.hasPrefix(root.standardizedFileURL.path) else { return fail(task, status: 403) }
    queue.async {
      let data = try? Data(contentsOf: file, options: .mappedIfSafe)
      DispatchQueue.main.async {
        if let data { self.finish(task, data: data, mime: Self.mime(for: file.pathExtension)) } else { self.fail(task, status: 404) }
      }
    }
  }

  func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
    active.remove(ObjectIdentifier(task))
  }

  // MARK: CesiumJS

  /// The CesiumJS version the page is written for (and the bundled copy is).
  static let cesiumVersion = "1.146.0"

  /// Where CesiumJS comes from when it is not bundled: jsDelivr at the pinned
  /// version, or Info.plist `MunimMapsCesiumBaseURL` (a self-hosted
  /// `Build/Cesium/` folder of the same version).
  static let cesiumBaseURL: URL = {
    if let custom = Bundle.main.object(forInfoDictionaryKey: "MunimMapsCesiumBaseURL") as? String, !custom.isEmpty,
       let url = URL(string: custom.hasSuffix("/") ? custom : custom + "/")
    {
      return url
    }
    return URL(string: "https://cdn.jsdelivr.net/npm/cesium@\(CesiumSchemeHandler.cesiumVersion)/Build/Cesium/")!
  }()

  /// The bundled CesiumJS folder, if the app bundles it.
  static let bundledCesium: URL? = {
    guard let root = CesiumSchemeHandler.root else { return nil }
    for folder in [root.appendingPathComponent("Cesium"), root.deletingLastPathComponent().appendingPathComponent("Cesium")]
    where FileManager.default.fileExists(atPath: folder.appendingPathComponent("Cesium.js").path) {
      return folder
    }
    return nil
  }()

  /// Downloaded CesiumJS files, by version (Caches, so iOS may reclaim them).
  static let cesiumCache: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("munim-maps-cesium", isDirectory: true)
    .appendingPathComponent(CesiumSchemeHandler.cesiumVersion, isDirectory: true)

  private func cesiumJS(_ relative: String, task: WKURLSchemeTask) {
    guard !relative.isEmpty, !relative.split(separator: "/").contains("..") else { return fail(task, status: 403) }
    let mime = Self.mime(for: (relative as NSString).pathExtension)
    if let bundled = Self.bundledCesium {
      let file = bundled.appendingPathComponent(relative)
      queue.async {
        let data = try? Data(contentsOf: file, options: .mappedIfSafe)
        DispatchQueue.main.async {
          if let data { self.finish(task, data: data, mime: mime) } else { self.fail(task, status: 404) }
        }
      }
      return
    }
    let cached = Self.cesiumCache.appendingPathComponent(relative)
    queue.async {
      if let data = try? Data(contentsOf: cached, options: .mappedIfSafe) {
        DispatchQueue.main.async { self.finish(task, data: data, mime: mime) }
        return
      }
      let url = Self.cesiumBaseURL.appendingPathComponent(relative)
      var request = URLRequest(url: url)
      request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
      Self.session.dataTask(with: request) { data, response, _ in
        let status = (response as? HTTPURLResponse)?.statusCode ?? 502
        if let data, (200..<300).contains(status) {
          try? FileManager.default.createDirectory(at: cached.deletingLastPathComponent(), withIntermediateDirectories: true)
          try? data.write(to: cached, options: .atomic)
          DispatchQueue.main.async { self.finish(task, data: data, mime: mime) }
        } else {
          DispatchQueue.main.async { self.fail(task, status: status) }
        }
      }.resume()
    }
  }

  private func resource(_ uri: String, task: WKURLSchemeTask) {
    if uri.hasPrefix("http://") || uri.hasPrefix("https://") { return fetch(uri, task: task) }
    let path: String
    if uri.hasPrefix("file://") { path = URL(string: uri)?.path ?? "" } else { path = uri }
    let file = URL(fileURLWithPath: path).standardizedFileURL
    // Only the app's own files: its bundle and its container.
    let allowed = [Bundle.main.bundleURL.standardizedFileURL.path, URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path, "/private" + NSHomeDirectory()]
    guard allowed.contains(where: { file.path.hasPrefix($0) }) else { return fail(task, status: 403) }
    queue.async {
      let data = try? Data(contentsOf: file, options: .mappedIfSafe)
      DispatchQueue.main.async {
        if let data { self.finish(task, data: data, mime: Self.mime(for: file.pathExtension)) } else { self.fail(task, status: 404) }
      }
    }
  }

  private func fetch(_ target: String, task: WKURLSchemeTask) {
    guard let url = URL(string: target) else { return fail(task, status: 400) }
    var request = URLRequest(url: url)
    request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
    Self.session.dataTask(with: request) { data, response, _ in
      DispatchQueue.main.async {
        let http = response as? HTTPURLResponse
        guard let data, let http, (200..<300).contains(http.statusCode) else {
          self.fail(task, status: http?.statusCode ?? 502)
          return
        }
        self.finish(task, data: data, mime: http.mimeType ?? Self.mime(for: url.pathExtension))
      }
    }.resume()
  }

  private func finish(_ task: WKURLSchemeTask, data: Data, mime: String) {
    guard active.remove(ObjectIdentifier(task)) != nil, let url = task.request.url else { return }
    let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
      "Content-Type": mime,
      "Content-Length": String(data.count),
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": "no-cache",
    ])!
    task.didReceive(response)
    task.didReceive(data)
    task.didFinish()
  }

  private func fail(_ task: WKURLSchemeTask, status: Int) {
    guard active.remove(ObjectIdentifier(task)) != nil, let url = task.request.url else { return }
    let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [
      "Content-Type": "text/plain", "Access-Control-Allow-Origin": "*",
    ])!
    task.didReceive(response)
    task.didReceive(Data())
    task.didFinish()
  }

  static func mime(for ext: String) -> String {
    switch ext.lowercased() {
    case "html": return "text/html; charset=utf-8"
    case "js", "mjs", "cjs": return "text/javascript; charset=utf-8"
    case "css": return "text/css; charset=utf-8"
    case "json", "czml", "geojson", "topojson": return "application/json"
    case "wasm": return "application/wasm"
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "gif": return "image/gif"
    case "svg": return "image/svg+xml"
    case "webp": return "image/webp"
    case "ktx2": return "image/ktx2"
    case "glb": return "model/gltf-binary"
    case "gltf": return "model/gltf+json"
    case "kml": return "application/vnd.google-earth.kml+xml"
    case "kmz": return "application/vnd.google-earth.kmz"
    case "gpx", "xml": return "application/xml"
    case "b3dm", "i3dm", "pnts", "cmpt", "subtree", "terrain", "bin", "pbf", "mvt": return "application/octet-stream"
    default: return "application/octet-stream"
    }
  }
}

/// Forwards script messages without the WebView keeping the engine alive.
final class CesiumScriptHandler: NSObject, WKScriptMessageHandler {
  weak var target: WKScriptMessageHandler?
  init(_ target: WKScriptMessageHandler) { self.target = target }
  func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
    target?.userContentController(controller, didReceive: message)
  }
}

// MARK: - JSON

enum CesiumJSON {
  /// A JSON-ready value for munim-maps' Swift values (structs, enums,
  /// coordinates), by reflection, so the web side sees the same field names.
  static func value(_ any: Any) -> Any {
    // Numbers from JSONSerialization (the `cesium` options, results) and
    // Swift numbers both bridge to NSNumber; only CFBoolean is a boolean
    // (`0 as Any is Bool` is true for an NSNumber, so test the CF type).
    if let n = any as? NSNumber {
      if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue }
      return n.doubleValue.isFinite ? n : NSNumber(value: 0)
    }
    switch any {
    case is NSNull: return NSNull()
    case let v as String: return v
    case let v as Bool: return v
    case let v as Int: return v
    case let v as Double: return v.isFinite ? v : 0
    case let v as Float: return v.isFinite ? Double(v) : 0
    case let v as CGFloat: return Double(v)
    case let v as CLLocationCoordinate2D: return ["latitude": v.latitude, "longitude": v.longitude]
    case let v as SIMD3<Float>: return [Double(v.x), Double(v.y), Double(v.z)]
    case let v as [String: Any]: return v.mapValues { value($0) }
    case let v as [Any]: return v.map { value($0) }
    case let v as any RawRepresentable: return "\(v.rawValue)"
    default:
      let mirror = Mirror(reflecting: any)
      if mirror.displayStyle == .optional {
        return mirror.children.first.map { value($0.value) } ?? NSNull()
      }
      if mirror.displayStyle == .collection || mirror.displayStyle == .set {
        return mirror.children.map { value($0.value) }
      }
      if mirror.displayStyle == .enum {
        return "\(any)"
      }
      var out: [String: Any] = [:]
      var m: Mirror? = mirror
      while let current = m {
        for child in current.children {
          guard let label = child.label else { continue }
          out[label.hasPrefix("_") ? String(label.dropFirst()) : label] = value(child.value)
        }
        m = current.superclassMirror
      }
      return out
    }
  }

  static func string(_ any: Any) -> String {
    let wrapped = value(any)
    if JSONSerialization.isValidJSONObject(wrapped),
       let data = try? JSONSerialization.data(withJSONObject: wrapped, options: [.fragmentsAllowed])
    {
      return String(decoding: data, as: UTF8.self)
    }
    if let data = try? JSONSerialization.data(withJSONObject: [wrapped], options: []) {
      let text = String(decoding: data, as: UTF8.self)
      return String(text.dropFirst().dropLast())
    }
    return "null"
  }

  static func parse(_ text: String) -> Any? {
    try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed])
  }
}

// MARK: - Cesium's camera maths

/// The camera Cesium last reported (`{ t: 'cam' }`), with what the native
/// side needs: the munim camera, the viewport, and Cesium's own view and
/// projection matrices for exact point <-> coordinate conversion.
struct CesiumCameraSnapshot {
  var latitude = 0.0
  var longitude = 0.0
  var centerHeight = 0.0
  var distance = 10_000_000.0
  var pitch = 0.0
  var heading = 0.0
  var fovy = Double.pi / 3
  var width = 0.0
  var height = 0.0
  var centerX = 0.0
  var centerY = 0.0
  var globe = true
  var terrain = false
  var dark = false
  var view = matrix_identity_double4x4
  var projection = matrix_identity_double4x4
  var region: (latitude: Double, longitude: Double, latitudeDelta: Double, longitudeDelta: Double)?

  init() {}

  init(_ s: [String: Any], previous: CesiumCameraSnapshot?) {
    func d(_ key: String, _ fallback: Double) -> Double { (s[key] as? NSNumber)?.doubleValue ?? fallback }
    latitude = d("latitude", 0)
    longitude = d("longitude", 0)
    centerHeight = d("centerHeight", 0)
    distance = d("distance", 1000)
    pitch = d("pitch", 0)
    heading = d("heading", 0)
    fovy = d("fovy", .pi / 3)
    width = d("width", 0)
    height = d("height", 0)
    centerX = d("centerX", width / 2)
    centerY = d("centerY", height / 2)
    globe = s["globe"] as? Bool ?? true
    terrain = s["terrain"] as? Bool ?? false
    dark = s["dark"] as? Bool ?? false
    if let v = s["view"] as? [NSNumber], v.count == 16 { view = Self.matrix(v) }
    if let p = s["projection"] as? [NSNumber], p.count == 16 { projection = Self.matrix(p) }
    if let r = s["region"] as? [String: Any] {
      func rd(_ key: String) -> Double { (r[key] as? NSNumber)?.doubleValue ?? 0 }
      region = (rd("latitude"), rd("longitude"), rd("latitudeDelta"), rd("longitudeDelta"))
    } else {
      region = previous?.region
    }
  }

  /// Cesium's matrices are column-major arrays.
  static func matrix(_ v: [NSNumber]) -> simd_double4x4 {
    let d = v.map(\.doubleValue)
    return simd_double4x4(columns: (
      SIMD4(d[0], d[1], d[2], d[3]),
      SIMD4(d[4], d[5], d[6], d[7]),
      SIMD4(d[8], d[9], d[10], d[11]),
      SIMD4(d[12], d[13], d[14], d[15])
    ))
  }

  var munim: MunimCamera {
    MunimCamera(latitude: latitude, longitude: longitude, distance: distance, pitch: pitch, heading: heading)
  }

  // WGS84
  static let a = 6_378_137.0
  static let b = 6_356_752.314245179
  static let e2 = 1 - (b * b) / (a * a)

  static func ecef(latitude: Double, longitude: Double, height: Double) -> SIMD3<Double> {
    let phi = latitude * .pi / 180
    let lambda = longitude * .pi / 180
    let n = a / sqrt(1 - e2 * sin(phi) * sin(phi))
    return SIMD3((n + height) * cos(phi) * cos(lambda), (n + height) * cos(phi) * sin(lambda), (n * (1 - e2) + height) * sin(phi))
  }

  static func geodetic(_ p: SIMD3<Double>) -> (latitude: Double, longitude: Double, height: Double) {
    let lon = atan2(p.y, p.x)
    let r = sqrt(p.x * p.x + p.y * p.y)
    var lat = atan2(p.z, r * (1 - e2))
    var h = 0.0
    for _ in 0..<6 {
      let n = a / sqrt(1 - e2 * sin(lat) * sin(lat))
      h = r / max(1e-9, cos(lat)) - n
      lat = atan2(p.z, r * (1 - e2 * n / (n + h)))
    }
    return (lat * 180 / .pi, lon * 180 / .pi, h)
  }

  /// Where Cesium draws a coordinate, in points; nil when behind the camera.
  func screenPoint(latitude: Double, longitude: Double, height: Double? = nil) -> CGPoint? {
    guard width > 0 else { return nil }
    let p = Self.ecef(latitude: latitude, longitude: longitude, height: height ?? centerHeight)
    let clip = projection * (view * SIMD4(p, 1))
    guard clip.w > 1e-9 else { return nil }
    let ndc = SIMD2(clip.x, clip.y) / clip.w
    return CGPoint(x: (ndc.x + 1) / 2 * width, y: (1 - ndc.y) / 2 * self.height)
  }

  /// The coordinate under a point, on the ellipsoid raised to the centre's height.
  func coordinate(at point: CGPoint) -> CLLocationCoordinate2D? {
    guard width > 0, height > 0 else { return nil }
    let inverse = (projection * view).inverse
    let x = Double(point.x) / width * 2 - 1
    let y = 1 - Double(point.y) / height * 2
    func unproject(_ z: Double) -> SIMD3<Double> {
      let v = inverse * SIMD4(x, y, z, 1)
      return SIMD3(v.x, v.y, v.z) / v.w
    }
    let near = unproject(-1)
    let far = unproject(1)
    let dir = simd_normalize(far - near)
    let h = centerHeight
    let scale = SIMD3(1 / (Self.a + h), 1 / (Self.a + h), 1 / (Self.b + h))
    let o = near * scale
    let dv = dir * scale
    let qa = simd_dot(dv, dv)
    let qb = 2 * simd_dot(o, dv)
    let qc = simd_dot(o, o) - 1
    let disc = qb * qb - 4 * qa * qc
    guard disc >= 0 else { return nil }
    let t = (-qb - sqrt(disc)) / (2 * qa)
    guard t > 0 else { return nil }
    let hit = near + dir * t
    let g = Self.geodetic(hit)
    return CLLocationCoordinate2D(latitude: g.latitude, longitude: g.longitude)
  }
}
#endif
