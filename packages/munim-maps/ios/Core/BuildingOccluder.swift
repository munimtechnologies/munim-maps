import Foundation
import MapKit
import SceneKit
import simd

/// Hides models behind buildings.
///
/// MapKit does not share its depth buffer, so on its own a car behind a
/// building is drawn in front of it. This loads building footprints and
/// heights from vector tiles (the OpenMapTiles `building` layer, by default
/// from OpenFreeMap) around the camera and draws their walls into the depth
/// buffer only: nothing shows, but models behind them are hidden. Walls are
/// enough for anything on the ground outside a building, and avatars,
/// labels and stems are drawn on top, so people inside buildings still show.
final class BuildingOccluder {
  /// Holds one node per loaded tile.
  let root = SCNNode()

  var enabled = false {
    didSet {
      root.isHidden = !enabled
      if !enabled { cancelAll() }
    }
  }

  /// `{z}/{x}/{y}` template of Mapbox Vector Tiles with an OpenMapTiles
  /// `building` layer (`render_height`, `render_min_height`). Empty uses
  /// OpenFreeMap.
  var tileURLTemplate = "" {
    didSet {
      if oldValue != tileURLTemplate {
        resolvedTemplate = nil
        cancelAll()
        for tile in tiles.values { tile.node.removeFromParentNode() }
        tiles = [:]
      }
    }
  }

  var onError: ((String) -> Void)?
  /// Called when a tile finishes loading, so the frame can be redrawn.
  var onChange: (() -> Void)?

  private static let zoom = 14
  /// Beyond this camera distance buildings are too small to matter.
  private static let maxDistance: Double = 9_000
  private static let maxTiles = 9
  private static let openFreeMapTileJSON = URL(string: "https://tiles.openfreemap.org/planet")!

  private final class Tile {
    let node: SCNNode = {
      // Walls must be in the depth buffer before any model is drawn;
      // renderingOrder is per node, not inherited.
      let node = SCNNode()
      node.renderingOrder = -20
      return node
    }()
    /// North-west corner, where the tile's geometry is anchored.
    let anchor: CLLocationCoordinate2D
    var task: URLSessionDataTask?
    var loaded = false

    init(anchor: CLLocationCoordinate2D) { self.anchor = anchor }
  }

  private var tiles: [String: Tile] = [:]
  private var resolvedTemplate: String?
  private var resolvingTemplate = false
  private var reportedError = false
  private let decodeQueue = DispatchQueue(label: "munim-maps.buildings", qos: .utility)

  private static let material: SCNMaterial = {
    let m = SCNMaterial()
    m.colorBufferWriteMask = []
    m.writesToDepthBuffer = true
    m.readsFromDepthBuffer = true
    m.isDoubleSided = true
    m.lightingModel = .constant
    return m
  }()

  init() {
    root.renderingOrder = -20
    root.isHidden = true
  }

  /// Loads tiles around the camera and moves the loaded ones into place.
  func update(for snapshot: MapCameraSnapshot, mapView: MKMapView) {
    guard enabled else { return }
    let active = !snapshot.globe && snapshot.distance < Self.maxDistance
    root.isHidden = !active
    guard active else { return }
    requestTiles(around: mapView.region)
    for tile in tiles.values where tile.loaded {
      tile.node.simdPosition = snapshot.scenePosition(
        latitude: tile.anchor.latitude, longitude: tile.anchor.longitude, altitude: 0)
    }
  }

  // MARK: Tiles

  private func requestTiles(around region: MKCoordinateRegion) {
    guard let template = resolvedTemplateOrResolve() else { return }
    // The visible region, a little larger, as z14 tile indices.
    let latPad = region.span.latitudeDelta * 0.6
    let lonPad = region.span.longitudeDelta * 0.6
    let north = min(85, region.center.latitude + latPad)
    let south = max(-85, region.center.latitude - latPad)
    let west = region.center.longitude - lonPad
    let east = region.center.longitude + lonPad
    let (x0, y0) = Self.tileIndex(latitude: north, longitude: west)
    let (x1, y1) = Self.tileIndex(latitude: south, longitude: east)
    var wanted: [(Int, Int)] = []
    for x in min(x0, x1)...max(x0, x1) {
      for y in min(y0, y1)...max(y0, y1) { wanted.append((x, y)) }
    }
    // Nearest first, and never too many.
    let (cx, cy) = Self.tileIndex(latitude: region.center.latitude, longitude: region.center.longitude)
    wanted.sort { abs($0.0 - cx) + abs($0.1 - cy) < abs($1.0 - cx) + abs($1.1 - cy) }
    let keep = Set(wanted.prefix(Self.maxTiles).map { "\($0.0)/\($0.1)" })

    for key in tiles.keys where !keep.contains(key) {
      tiles[key]?.task?.cancel()
      tiles[key]?.node.removeFromParentNode()
      tiles[key] = nil
    }
    for (x, y) in wanted.prefix(Self.maxTiles) where tiles["\(x)/\(y)"] == nil {
      load(x: x, y: y, template: template)
    }
  }

  private func load(x: Int, y: Int, template: String) {
    let key = "\(x)/\(y)"
    let anchor = Self.coordinate(x: Double(x), y: Double(y))
    let tile = Tile(anchor: anchor)
    tiles[key] = tile
    let urlString = template
      .replacingOccurrences(of: "{z}", with: "\(Self.zoom)")
      .replacingOccurrences(of: "{x}", with: "\(x)")
      .replacingOccurrences(of: "{y}", with: "\(y)")
    guard let url = URL(string: urlString) else { return }

    let cacheURL = Self.cacheDirectory.appendingPathComponent(
      "\(abs(template.hashValue))-\(Self.zoom)-\(x)-\(y).pbf")
    let build: (Data) -> Void = { [weak self] data in
      self?.decodeQueue.async {
        let geometry = Self.wallGeometry(tileData: data, x: x, y: y)
        DispatchQueue.main.async {
          guard let self, self.tiles[key] === tile else { return }
          tile.node.geometry = geometry
          tile.loaded = true
          self.root.addChildNode(tile.node)
          self.onChange?()
        }
      }
    }
    if let cached = try? Data(contentsOf: cacheURL) {
      build(cached)
      return
    }
    var request = URLRequest(url: url)
    request.setValue("munim-maps (https://github.com/munimtechnologies/munim-maps)", forHTTPHeaderField: "User-Agent")
    tile.task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      guard let data, error == nil, (200..<300).contains(status) || status == 0 else {
        if (error as? URLError)?.code == .cancelled { return }
        DispatchQueue.main.async {
          // Let the tile be retried later, and say so once.
          if self?.tiles[key] === tile { self?.tiles[key] = nil }
          self?.reportOnce("Could not load building tile \(key): \(error?.localizedDescription ?? "HTTP \(status)")")
        }
        return
      }
      try? FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: true)
      try? data.write(to: cacheURL)
      build(data)
    }
    tile.task?.resume()
  }

  /// OpenFreeMap's tile URLs are versioned, so read the current one from its
  /// TileJSON once.
  private func resolvedTemplateOrResolve() -> String? {
    if !tileURLTemplate.isEmpty { return tileURLTemplate }
    if let resolvedTemplate { return resolvedTemplate }
    guard !resolvingTemplate else { return nil }
    resolvingTemplate = true
    URLSession.shared.dataTask(with: Self.openFreeMapTileJSON) { [weak self] data, _, error in
      let template = data
        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        .flatMap { ($0["tiles"] as? [String])?.first }
      DispatchQueue.main.async {
        guard let self else { return }
        self.resolvingTemplate = false
        if let template {
          self.resolvedTemplate = template
          self.onChange?()
        } else {
          self.reportOnce("Could not read the building tile index: \(error?.localizedDescription ?? "no tiles")")
        }
      }
    }.resume()
    return nil
  }

  private func cancelAll() {
    for tile in tiles.values { tile.task?.cancel() }
  }

  private func reportOnce(_ message: String) {
    guard !reportedError else { return }
    reportedError = true
    onError?(message)
  }

  private static let cacheDirectory: URL = FileManager.default
    .urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("munim-maps-buildings", isDirectory: true)

  // MARK: Geometry

  static func tileIndex(latitude: Double, longitude: Double) -> (Int, Int) {
    let n = Double(1 << zoom)
    let x = (longitude + 180) / 360 * n
    let lat = latitude * .pi / 180
    let y = (1 - asinh(tan(lat)) / .pi) / 2 * n
    return (Int(floor(x)), Int(floor(y)))
  }

  /// Coordinate of a (fractional) tile position.
  static func coordinate(x: Double, y: Double) -> CLLocationCoordinate2D {
    let n = Double(1 << zoom)
    let longitude = x / n * 360 - 180
    let latitude = atan(sinh(.pi * (1 - 2 * y / n))) * 180 / .pi
    return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
  }

  /// Walls for every building ring in the tile, in metres east and south of
  /// the tile's north-west corner, the layout the renderer uses.
  static func wallGeometry(tileData: Data, x: Int, y: Int) -> SCNGeometry? {
    guard let buildings = try? VectorTile.buildings(in: tileData), !buildings.isEmpty else { return nil }
    let origin = MKMapPoint(coordinate(x: Double(x), y: Double(y)))
    let far = MKMapPoint(coordinate(x: Double(x + 1), y: Double(y + 1)))
    let center = coordinate(x: Double(x) + 0.5, y: Double(y) + 0.5)
    let metersPerPoint = MKMetersPerMapPointAtLatitude(center.latitude)
    var vertices: [SCNVector3] = []
    var indices: [UInt32] = []
    for building in buildings where !building.hide3D && building.height > building.minHeight {
      let extent = Double(building.extent)
      let top = Float(building.height)
      let bottom = Float(building.minHeight)
      for ring in building.rings where ring.count >= 3 {
        let points = ring.map { p -> SIMD2<Float> in
          let mx = origin.x + (far.x - origin.x) * Double(p.x) / extent
          let my = origin.y + (far.y - origin.y) * Double(p.y) / extent
          return SIMD2(Float((mx - origin.x) * metersPerPoint), Float((my - origin.y) * metersPerPoint))
        }
        for i in 0..<points.count {
          let a = points[i]
          let b = points[(i + 1) % points.count]
          if a == b { continue }
          let base = UInt32(vertices.count)
          vertices += [
            SCNVector3(a.x, bottom, a.y), SCNVector3(b.x, bottom, b.y),
            SCNVector3(b.x, top, b.y), SCNVector3(a.x, top, a.y),
          ]
          indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        }
      }
    }
    guard !vertices.isEmpty else { return nil }
    let geometry = SCNGeometry(
      sources: [SCNGeometrySource(vertices: vertices)],
      elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    geometry.materials = [material]
    return geometry
  }
}

/// The parts of a Mapbox Vector Tile that building occlusion needs.
enum VectorTile {
  struct Building {
    var height: Double
    var minHeight: Double
    /// Outlines whose parts are drawn separately.
    var hide3D: Bool
    var extent: Int
    var rings: [[SIMD2<Int32>]]
  }

  enum DecodeError: Error { case truncated }

  /// Polygons of the `building` layer with their heights in metres.
  static func buildings(in data: Data) throws -> [Building] {
    var bytes = [UInt8](data)
    if bytes.count > 2, bytes[0] == 0x1f, bytes[1] == 0x8b {
      bytes = try gunzip(bytes)
    }
    var result: [Building] = []
    var reader = Reader(bytes: bytes[...])
    while !reader.atEnd {
      let (field, wire) = try reader.key()
      guard field == 3, wire == 2 else { try reader.skip(wire); continue }
      let layer = try reader.lengthDelimited()
      if let buildings = try decodeLayer(layer) { result += buildings }
    }
    return result
  }

  private static func decodeLayer(_ data: ArraySlice<UInt8>) throws -> [Building]? {
    var reader = Reader(bytes: data)
    var name = ""
    var keys: [String] = []
    var values: [Double?] = []
    var features: [ArraySlice<UInt8>] = []
    var extent = 4096
    while !reader.atEnd {
      let (field, wire) = try reader.key()
      switch (field, wire) {
      case (1, 2): name = String(decoding: try reader.lengthDelimited(), as: UTF8.self)
      case (2, 2): features.append(try reader.lengthDelimited())
      case (3, 2): keys.append(String(decoding: try reader.lengthDelimited(), as: UTF8.self))
      case (4, 2): values.append(try decodeValue(try reader.lengthDelimited()))
      case (5, 0): extent = Int(try reader.varint())
      default: try reader.skip(wire)
      }
      // Skip other layers without decoding their features.
      if field == 1, name != "building" { return nil }
    }
    guard name == "building" else { return nil }
    let heightKey = keys.firstIndex(of: "render_height")
    let minKey = keys.firstIndex(of: "render_min_height")
    let hideKey = keys.firstIndex(of: "hide_3d")
    return try features.compactMap { feature in
      var reader = Reader(bytes: feature)
      var tags: [Int] = []
      var type = 0
      var geometry: [UInt32] = []
      while !reader.atEnd {
        let (field, wire) = try reader.key()
        switch (field, wire) {
        case (2, 2): tags = try packedVarints(try reader.lengthDelimited()).map { Int($0) }
        case (3, 0): type = Int(try reader.varint())
        case (4, 2): geometry = try packedVarints(try reader.lengthDelimited()).map { UInt32(truncatingIfNeeded: $0) }
        default: try reader.skip(wire)
        }
      }
      guard type == 3 else { return nil } // polygons only
      var height = 10.0
      var minHeight = 0.0
      var hide3D = false
      var i = 0
      while i + 1 < tags.count {
        let key = tags[i]
        let value = tags[i + 1] < values.count ? values[tags[i + 1]] : nil
        if key == heightKey, let value { height = value }
        if key == minKey, let value { minHeight = value }
        if key == hideKey, let value { hide3D = value != 0 }
        i += 2
      }
      return Building(height: height, minHeight: minHeight, hide3D: hide3D, extent: extent,
                      rings: rings(from: geometry))
    }
  }

  /// Numbers only; strings become nil. Booleans are 0 or 1.
  private static func decodeValue(_ data: ArraySlice<UInt8>) throws -> Double? {
    var reader = Reader(bytes: data)
    var value: Double?
    while !reader.atEnd {
      let (field, wire) = try reader.key()
      switch (field, wire) {
      case (2, 5): value = Double(Float(bitPattern: try reader.fixed32()))
      case (3, 1): value = Double(bitPattern: try reader.fixed64())
      case (4, 0): value = Double(Int64(bitPattern: try reader.varint()))
      case (5, 0): value = Double(try reader.varint())
      case (6, 0):
        let raw = try reader.varint()
        value = Double(Int64(bitPattern: (raw >> 1) ^ (0 &- (raw & 1))))
      case (7, 0): value = try reader.varint() != 0 ? 1 : 0
      default: try reader.skip(wire)
      }
    }
    return value
  }

  /// Decodes MoveTo / LineTo / ClosePath commands into closed rings.
  private static func rings(from commands: [UInt32]) -> [[SIMD2<Int32>]] {
    var rings: [[SIMD2<Int32>]] = []
    var ring: [SIMD2<Int32>] = []
    var cursor = SIMD2<Int32>(0, 0)
    var i = 0
    func zigzag(_ v: UInt32) -> Int32 { Int32(bitPattern: (v >> 1) ^ (0 &- (v & 1))) }
    while i < commands.count {
      let command = commands[i] & 0x7
      let count = Int(commands[i] >> 3)
      i += 1
      switch command {
      case 1, 2: // MoveTo, LineTo
        if command == 1, !ring.isEmpty { rings.append(ring); ring = [] }
        for _ in 0..<count where i + 1 < commands.count {
          cursor &+= SIMD2(zigzag(commands[i]), zigzag(commands[i + 1]))
          ring.append(cursor)
          i += 2
        }
      case 7: // ClosePath
        if !ring.isEmpty { rings.append(ring); ring = [] }
      default:
        return rings
      }
    }
    if !ring.isEmpty { rings.append(ring) }
    return rings
  }

  private static func packedVarints(_ data: ArraySlice<UInt8>) throws -> [UInt64] {
    var reader = Reader(bytes: data)
    var result: [UInt64] = []
    while !reader.atEnd { result.append(try reader.varint()) }
    return result
  }

  private struct Reader {
    var bytes: ArraySlice<UInt8>
    var atEnd: Bool { bytes.isEmpty }

    mutating func varint() throws -> UInt64 {
      var result: UInt64 = 0
      var shift: UInt64 = 0
      while true {
        guard let byte = bytes.popFirst() else { throw DecodeError.truncated }
        result |= UInt64(byte & 0x7f) << shift
        if byte < 0x80 { return result }
        shift += 7
        if shift > 63 { throw DecodeError.truncated }
      }
    }

    mutating func key() throws -> (Int, Int) {
      let key = try varint()
      return (Int(key >> 3), Int(key & 7))
    }

    mutating func lengthDelimited() throws -> ArraySlice<UInt8> {
      let length = Int(try varint())
      guard bytes.count >= length else { throw DecodeError.truncated }
      let slice = bytes.prefix(length)
      bytes = bytes.dropFirst(length)
      return slice
    }

    mutating func fixed32() throws -> UInt32 {
      guard bytes.count >= 4 else { throw DecodeError.truncated }
      var v: UInt32 = 0
      for (i, b) in bytes.prefix(4).enumerated() { v |= UInt32(b) << (8 * UInt32(i)) }
      bytes = bytes.dropFirst(4)
      return v
    }

    mutating func fixed64() throws -> UInt64 {
      guard bytes.count >= 8 else { throw DecodeError.truncated }
      var v: UInt64 = 0
      for (i, b) in bytes.prefix(8).enumerated() { v |= UInt64(b) << (8 * UInt64(i)) }
      bytes = bytes.dropFirst(8)
      return v
    }

    mutating func skip(_ wire: Int) throws {
      switch wire {
      case 0: _ = try varint()
      case 1: _ = try fixed64()
      case 2: _ = try lengthDelimited()
      case 5: _ = try fixed32()
      default: throw DecodeError.truncated
      }
    }
  }

  /// Tiles served with `Content-Encoding: gzip` arrive decoded; some servers
  /// store them gzipped, so inflate those here.
  private static func gunzip(_ bytes: [UInt8]) throws -> [UInt8] {
    guard bytes.count > 18 else { throw DecodeError.truncated }
    var offset = 10
    let flags = bytes[3]
    if flags & 0x04 != 0 { offset += 2 + Int(bytes[10]) | (Int(bytes[11]) << 8) }
    if flags & 0x08 != 0 { while offset < bytes.count, bytes[offset] != 0 { offset += 1 }; offset += 1 }
    if flags & 0x10 != 0 { while offset < bytes.count, bytes[offset] != 0 { offset += 1 }; offset += 1 }
    if flags & 0x02 != 0 { offset += 2 }
    let deflated = Data(bytes[offset..<(bytes.count - 8)])
    let size = Int(bytes[bytes.count - 4]) | Int(bytes[bytes.count - 3]) << 8
      | Int(bytes[bytes.count - 2]) << 16 | Int(bytes[bytes.count - 1]) << 24
    let inflated = try (deflated as NSData).decompressed(using: .zlib) as Data
    guard inflated.count == size || size == 0 else { return [UInt8](inflated) }
    return [UInt8](inflated)
  }
}
