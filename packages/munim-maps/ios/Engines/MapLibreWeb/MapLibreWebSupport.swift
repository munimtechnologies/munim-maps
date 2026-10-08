#if MUNIM_MAPS_MAPLIBRE_WEB
import CoreLocation
import Foundation
import UIKit
import WebKit
import simd

// The MapLibre GL JS renderer's plumbing: serving its page, GL JS and
// three.js to the WebView (from jsDelivr at pinned versions, kept on disk,
// or bundled), values to JSON, and GL JS's camera maths for the
// synchronous getters without a round trip to JavaScript.

/// Serves `munim-maplibre://app/…` to the renderer's WKWebView:
/// - `/…` the page (`MunimMapsMapLibre.bundle/munim-maplibre`),
/// - `/maplibre-gl/…` MapLibre GL JS `dist/` files and `/three/…` three.js
///   files: bundled (`MUNIM_MAPS_MAPLIBRE_BUNDLED`, copied from the app's own
///   `maplibre-gl` and `three` packages), or from jsDelivr at the pinned
///   versions, kept on disk after the first load (so the page is
///   same-origin: workers, ES modules, no CSP or CORS changes, and it works
///   offline afterwards),
/// - `/resource?uri=…` the app's files (`file://`, paths, Metro's `http://`)
///   and remote glTF models through munim-maps' model cache,
/// - `/tile/<host>/<path>` https tiles fetched with an identifying User-Agent.
final class MapLibreWebSchemeHandler: NSObject, WKURLSchemeHandler {
  static let scheme = "munim-maplibre"
  static let base = "munim-maplibre://app/"

  /// MapLibre GL JS version the page is written for (and the bundled copy must be).
  static let maplibreVersion = "5.24.0"
  /// three.js version the 3D layer is written for.
  static let threeVersion = "0.186.1"

  /// The `munim-maplibre` folder in the pod's resource bundle.
  static let root: URL? = {
    for bundle in [Bundle(for: MapLibreWebSchemeHandler.self), Bundle.main] {
      if let url = bundle.url(forResource: "MunimMapsMapLibre", withExtension: "bundle"),
         let resources = Bundle(url: url)?.resourceURL
      {
        let folder = resources.appendingPathComponent("munim-maplibre")
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent("index.html").path) { return folder }
      }
      if let folder = bundle.resourceURL?.appendingPathComponent("munim-maplibre"),
         FileManager.default.fileExists(atPath: folder.appendingPathComponent("index.html").path)
      {
        return folder
      }
    }
    return nil
  }()

  /// One of the two libraries the page loads from its own origin.
  struct Library {
    let name: String
    let version: String
    /// Where it comes from when it is not bundled.
    let baseURL: URL
    /// Bundled copy (`<bundle>/<name>`), if the app bundles it.
    let bundled: URL?
    /// Downloaded files (Caches, so iOS may reclaim them).
    let cache: URL

    init(name: String, version: String, cdnPath: String, plistKey: String) {
      self.name = name
      self.version = version
      if let custom = Bundle.main.object(forInfoDictionaryKey: plistKey) as? String, !custom.isEmpty,
         let url = URL(string: custom.hasSuffix("/") ? custom : custom + "/")
      {
        baseURL = url
      } else {
        baseURL = URL(string: "https://cdn.jsdelivr.net/npm/\(name)@\(version)/\(cdnPath)")!
      }
      var found: URL?
      if let root = MapLibreWebSchemeHandler.root {
        for folder in [root.appendingPathComponent(name), root.deletingLastPathComponent().appendingPathComponent(name)]
        where FileManager.default.fileExists(atPath: folder.appendingPathComponent("package.json").path)
          || FileManager.default.fileExists(atPath: folder.appendingPathComponent("maplibre-gl.js").path)
        {
          found = folder
          break
        }
      }
      bundled = found
      cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("munim-maps-maplibre", isDirectory: true)
        .appendingPathComponent("\(name)@\(version)", isDirectory: true)
    }
  }

  static let maplibre = Library(name: "maplibre-gl", version: maplibreVersion, cdnPath: "dist/", plistKey: "MunimMapsMapLibreGLBaseURL")
  static let three = Library(name: "three", version: threeVersion, cdnPath: "", plistKey: "MunimMapsThreeBaseURL")

  private var active = Set<ObjectIdentifier>()
  private let queue = DispatchQueue(label: "munim-maps.maplibre-web.files", qos: .userInitiated, attributes: .concurrent)

  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 256 << 20, diskPath: "munim-maps-maplibre-tiles")
    configuration.requestCachePolicy = .useProtocolCachePolicy
    configuration.httpMaximumConnectionsPerHost = 6
    return URLSession(configuration: configuration)
  }()

  static let userAgent: String = {
    let app = Bundle.main.bundleIdentifier ?? "app"
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1"
    return "munim-maps-maplibre/1.0 (\(app)/\(version); +https://github.com/munimtechnologies/munim-maps)"
  }()

  func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
    active.insert(ObjectIdentifier(task))
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
    if relative.hasPrefix("maplibre-gl/") { return library(Self.maplibre, String(relative.dropFirst("maplibre-gl/".count)), task: task) }
    if relative.hasPrefix("three/") { return library(Self.three, String(relative.dropFirst("three/".count)), task: task) }
    let file = root.appendingPathComponent(relative.isEmpty ? "index.html" : relative).standardizedFileURL
    guard file.path.hasPrefix(root.standardizedFileURL.path) else { return fail(task, status: 403) }
    read(file, mime: Self.mime(for: file.pathExtension), task: task)
  }

  func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
    active.remove(ObjectIdentifier(task))
  }

  private func read(_ file: URL, mime: String, task: WKURLSchemeTask) {
    queue.async {
      let data = try? Data(contentsOf: file, options: .mappedIfSafe)
      DispatchQueue.main.async {
        if let data { self.finish(task, data: data, mime: mime) } else { self.fail(task, status: 404) }
      }
    }
  }

  private func library(_ lib: Library, _ relative: String, task: WKURLSchemeTask) {
    guard !relative.isEmpty, !relative.split(separator: "/").contains("..") else { return fail(task, status: 403) }
    let mime = Self.mime(for: (relative as NSString).pathExtension)
    if let bundled = lib.bundled {
      // The bundled copy is the package as published: `.min.js` names the
      // page asks jsDelivr for are the plain files there.
      var file = bundled.appendingPathComponent(relative)
      if !FileManager.default.fileExists(atPath: file.path), relative.hasSuffix(".min.js") {
        file = bundled.appendingPathComponent(String(relative.dropLast(".min.js".count)) + ".js")
      }
      return read(file, mime: mime, task: task)
    }
    let cached = lib.cache.appendingPathComponent(relative)
    queue.async {
      if let data = try? Data(contentsOf: cached, options: .mappedIfSafe) {
        DispatchQueue.main.async { self.finish(task, data: data, mime: mime) }
        return
      }
      var request = URLRequest(url: lib.baseURL.appendingPathComponent(relative))
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
    if uri.hasPrefix("http://") || uri.hasPrefix("https://") {
      // Remote models go through munim-maps' disk cache (Caches/munim-maps).
      let ext = (URL(string: uri)?.pathExtension ?? "").lowercased()
      guard ["glb", "gltf"].contains(ext) else { return fetch(uri, task: task) }
      MapModelNodes.resolveLocalURL(uri: uri) { result in
        guard case .success(let file) = result else {
          DispatchQueue.main.async { self.fail(task, status: 502) }
          return
        }
        self.read(file, mime: Self.mime(for: ext), task: task)
      }
      return
    }
    let path = uri.hasPrefix("file://") ? (URL(string: uri)?.path ?? "") : uri
    let file = URL(fileURLWithPath: path).standardizedFileURL
    // Only the app's own files: its bundle and its container.
    let allowed = [Bundle.main.bundleURL.standardizedFileURL.path, URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path, "/private" + NSHomeDirectory()]
    guard allowed.contains(where: { file.path.hasPrefix($0) }) else { return fail(task, status: 403) }
    read(file, mime: Self.mime(for: file.pathExtension), task: task)
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
    case "json", "geojson": return "application/json"
    case "wasm": return "application/wasm"
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "gif": return "image/gif"
    case "svg": return "image/svg+xml"
    case "webp": return "image/webp"
    case "glb": return "model/gltf-binary"
    case "gltf": return "model/gltf+json"
    default: return "application/octet-stream"
    }
  }
}

/// Forwards script messages without the WebView keeping the engine alive.
final class MapLibreWebScriptHandler: NSObject, WKScriptMessageHandler {
  weak var target: WKScriptMessageHandler?
  init(_ target: WKScriptMessageHandler) { self.target = target }
  func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
    target?.userContentController(controller, didReceive: message)
  }
}

// MARK: - JSON

enum MapLibreWebJSON {
  /// A JSON-ready value for munim-maps' Swift values (structs, enums,
  /// coordinates), by reflection, so the page sees the same field names.
  static func value(_ any: Any) -> Any {
    // Only CFBoolean is a boolean (`0 as Any is Bool` is true for an NSNumber).
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
      if mirror.displayStyle == .optional { return mirror.children.first.map { value($0.value) } ?? NSNull() }
      if mirror.displayStyle == .collection || mirror.displayStyle == .set { return mirror.children.map { value($0.value) } }
      if mirror.displayStyle == .enum { return "\(any)" }
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

// MARK: - GL JS's camera maths

/// The camera GL JS last reported (`{ t: 'cam' }`): the munim camera, the
/// viewport, and the matrices GL JS gives custom layers (Mercator and globe,
/// with the transition between them), for point <-> coordinate conversion at
/// the height of the ground at the centre.
struct MapLibreWebCamera {
  var latitude = 0.0
  var longitude = 0.0
  var distance = 10_000_000.0
  var pitch = 0.0
  var heading = 0.0
  var zoom = 0.0
  var fovy = 0.6435011087932844
  var width = 0.0
  var height = 0.0
  var centerX = 0.0
  var centerY = 0.0
  var globe = false
  var transition = 0.0
  var terrain = false
  var dark = false
  var centerElevation = 0.0
  var main = matrix_identity_double4x4
  var fallback = matrix_identity_double4x4
  var region: MKCoordinateRegionValue?

  struct MKCoordinateRegionValue {
    var latitude, longitude, latitudeDelta, longitudeDelta: Double
  }

  init() {}

  init(_ s: [String: Any], previous: MapLibreWebCamera?) {
    func d(_ key: String, _ fallback: Double) -> Double { (s[key] as? NSNumber)?.doubleValue ?? fallback }
    latitude = d("latitude", 0)
    longitude = d("longitude", 0)
    distance = d("distance", 1000)
    pitch = d("pitch", 0)
    heading = d("heading", 0)
    zoom = d("zoom", 0)
    fovy = d("fovy", 0.6435011087932844)
    width = d("width", 0)
    height = d("height", 0)
    centerX = d("centerX", width / 2)
    centerY = d("centerY", height / 2)
    globe = s["globe"] as? Bool ?? false
    transition = d("transition", 0)
    terrain = s["terrain"] as? Bool ?? false
    dark = s["dark"] as? Bool ?? false
    centerElevation = d("centerElevation", 0)
    if let m = s["mainMatrix"] as? [NSNumber], m.count == 16 { main = Self.matrix(m) }
    if let m = s["fallbackMatrix"] as? [NSNumber], m.count == 16 { fallback = Self.matrix(m) }
    if let r = s["region"] as? [String: Any] {
      func rd(_ key: String) -> Double { (r[key] as? NSNumber)?.doubleValue ?? 0 }
      region = MKCoordinateRegionValue(latitude: rd("latitude"), longitude: rd("longitude"), latitudeDelta: rd("latitudeDelta"), longitudeDelta: rd("longitudeDelta"))
    } else {
      region = previous?.region
    }
  }

  /// GL JS's matrices are column-major arrays.
  static func matrix(_ v: [NSNumber]) -> simd_double4x4 {
    let d = v.map(\.doubleValue)
    return simd_double4x4(columns: (
      SIMD4(d[0], d[1], d[2], d[3]), SIMD4(d[4], d[5], d[6], d[7]),
      SIMD4(d[8], d[9], d[10], d[11]), SIMD4(d[12], d[13], d[14], d[15])))
  }

  var munim: MunimCamera {
    MunimCamera(latitude: latitude, longitude: longitude, distance: distance, pitch: pitch, heading: heading)
  }

  static let earthRadius = 6_371_008.8 // GL JS's

  /// GL JS's `MercatorCoordinate.fromLngLat`.
  static func mercator(latitude: Double, longitude: Double, altitude: Double) -> SIMD3<Double> {
    let x = (180 + longitude) / 360
    let y = (180 - (180 / .pi * log(tan(.pi / 4 + latitude * .pi / 360)))) / 360
    let meter = 1 / (2 * .pi * earthRadius * cos(latitude * .pi / 180))
    return SIMD3(x, y, altitude * meter)
  }

  static func sphere(latitude: Double, longitude: Double, altitude: Double) -> SIMD3<Double> {
    let l = longitude * .pi / 180
    let f = latitude * .pi / 180
    let r = 1 + altitude / earthRadius
    return SIMD3(sin(l) * cos(f) * r, sin(f) * r, cos(l) * cos(f) * r)
  }

  /// Where GL JS draws a coordinate (at the centre's ground height), in points.
  func screenPoint(latitude: Double, longitude: Double) -> CGPoint? {
    guard width > 0 else { return nil }
    let m = Self.mercator(latitude: latitude, longitude: longitude, altitude: centerElevation)
    var clip: SIMD4<Double>
    if transition <= 0 {
      clip = main * SIMD4(m, 1)
    } else {
      let g = main * SIMD4(Self.sphere(latitude: latitude, longitude: longitude, altitude: centerElevation), 1)
      if transition >= 0.999 {
        clip = g
      } else {
        let f = fallback * SIMD4(m, 1)
        clip = f + (g - f) * transition
      }
    }
    guard clip.w > 1e-12 else { return nil }
    return CGPoint(x: (clip.x / clip.w + 1) / 2 * width, y: (1 - clip.y / clip.w) / 2 * height)
  }

  /// The coordinate under a point, on the ground at the centre's height.
  func coordinate(at point: CGPoint) -> CLLocationCoordinate2D? {
    guard width > 0, height > 0 else { return nil }
    let useGlobe = transition >= 0.5
    let matrix = useGlobe || transition <= 0 ? main : fallback
    let inverse = matrix.inverse
    let x = Double(point.x) / width * 2 - 1
    let y = 1 - Double(point.y) / height * 2
    func unproject(_ z: Double) -> SIMD3<Double> {
      let v = inverse * SIMD4(x, y, z, 1)
      return SIMD3(v.x, v.y, v.z) / v.w
    }
    let near = unproject(-1)
    let far = unproject(1)
    let dir = far - near
    if useGlobe {
      let r = 1 + centerElevation / Self.earthRadius
      let d = simd_normalize(dir)
      let b = 2 * simd_dot(near, d)
      let c = simd_dot(near, near) - r * r
      let disc = b * b - 4 * c
      guard disc >= 0 else { return nil }
      let t = (-b - sqrt(disc)) / 2
      guard t > 0 else { return nil }
      let p = (near + d * t) / r
      return CLLocationCoordinate2D(latitude: asin(max(-1, min(1, p.y))) * 180 / .pi, longitude: atan2(p.x, p.z) * 180 / .pi)
    }
    let z = Self.mercator(latitude: latitude, longitude: longitude, altitude: centerElevation).z
    guard abs(dir.z) > 1e-15 else { return nil }
    let t = (z - near.z) / dir.z
    let p = near + dir * t
    let longitude = p.x * 360 - 180
    let latitude = 360 / .pi * atan(exp((180 - p.y * 360) * .pi / 180)) - 90
    return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }
}
#endif
