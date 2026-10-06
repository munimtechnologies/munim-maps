import CoreGraphics
import CoreLocation
import Foundation
import ImageIO

/// What a model's or path's `altitude` is measured from.
@_expose(!Cxx)
public enum MunimAltitudeReference: String, Sendable {
  /// Metres above the ground under it (the default).
  case ground
  /// Metres above sea level, such as a phone's GPS altitude. The ground
  /// height there is looked up from terrain tiles and taken off.
  case sea

  var stringValue: String { rawValue }
}

/// Ground height above sea level anywhere on Earth, from terrain tiles.
///
/// MapKit does not expose terrain height, so this reads the free, public
/// [Terrarium elevation tiles](https://registry.opendata.aws/terrain-tiles/)
/// on AWS (PNG tiles where `height = R * 256 + G + B / 256 - 32768` metres),
/// at zoom 14 (about 7-10 m per pixel) with bilinear sampling. Tiles are kept
/// in memory and in the app's Caches folder, and a tile is only ever fetched
/// once at a time.
///
/// ```swift
/// let heights = try await MunimTerrain.shared.groundElevations(for: [coordinate])
/// ```
///
/// Heights are above mean sea level, the same datum as `CLLocation.altitude`,
/// and usually within a few metres. Under the sea they are the sea floor.
@_expose(!Cxx)
public final class MunimTerrain: @unchecked Sendable {
  public static let shared = MunimTerrain()

  /// Posted on the main thread whenever a tile finishes loading, so drawing
  /// that waited for it can be redone.
  public static let didLoadTileNotification = Notification.Name("MunimTerrainDidLoadTile")
  /// Posted on the main thread when a tile cannot be loaded; `userInfo["message"]` says why.
  public static let didFailNotification = Notification.Name("MunimTerrainDidFail")

  /// `{z}/{x}/{y}` template of Terrarium-encoded PNG tiles. Change it to
  /// serve the tiles yourself.
  public var tileURLTemplate = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"

  static let zoom = 14
  static let tileSize = 256
  /// Decoded tiles kept in memory (256 KB each).
  private static let memoryTiles = 64
  /// A failed tile is not asked for again until this many seconds later.
  private static let retryInterval: TimeInterval = 30

  struct TileKey: Hashable {
    let z: Int, x: Int, y: Int
  }

  private let lock = NSLock()
  /// Heights in metres, row by row from the north-west corner.
  private var tiles: [TileKey: [Float]] = [:]
  private var lastUsed: [TileKey: UInt64] = [:]
  private var useCounter: UInt64 = 0
  private var waiting: [TileKey: [(Result<[Float], Error>) -> Void]] = [:]
  private var failedAt: [TileKey: Date] = [:]
  private let workQueue = DispatchQueue(label: "munim-maps.terrain", qos: .utility, attributes: .concurrent)

  private static let cacheDirectory: URL = FileManager.default
    .urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("munim-maps-terrain", isDirectory: true)

  public init() {}

  public enum TerrainError: Error, LocalizedError {
    case download(String)
    case decode(String)

    public var errorDescription: String? {
      switch self {
      case .download(let message), .decode(let message): return message
      }
    }
  }

  // MARK: Public API

  /// Ground heights above sea level, in metres, one per coordinate.
  /// Fails if a tile cannot be loaded.
  public func groundElevations(
    for coordinates: [CLLocationCoordinate2D],
    completion: @escaping (Result<[Double], Error>) -> Void
  ) {
    let keys = Set(coordinates.flatMap { Self.tileKeys(for: $0) })
    guard !keys.isEmpty else { return completion(.success([])) }
    // Keep the tiles this request needs, whatever the memory cache evicts.
    var loaded: [TileKey: [Float]] = [:]
    var failure: Error?
    let collect = NSLock()
    let group = DispatchGroup()
    for key in keys {
      group.enter()
      load(key, retryFailed: true) { result in
        collect.lock()
        switch result {
        case .success(let heights): loaded[key] = heights
        case .failure(let error): failure = failure ?? error
        }
        collect.unlock()
        group.leave()
      }
    }
    group.notify(queue: workQueue) {
      if let failure { return completion(.failure(failure)) }
      let heights = coordinates.map { Self.sample($0) { loaded[$0] } ?? .nan }
      completion(.success(heights))
    }
  }

  /// Ground heights above sea level, in metres, one per coordinate.
  @available(iOS 13.0, *)
  public func groundElevations(for coordinates: [CLLocationCoordinate2D]) async throws -> [Double] {
    try await withCheckedThrowingContinuation { continuation in
      groundElevations(for: coordinates) { continuation.resume(with: $0) }
    }
  }

  /// The ground height at `coordinate` if its tiles are already in memory;
  /// otherwise nil, and the tiles are requested (watch
  /// `didLoadTileNotification`). Cheap enough to call every frame.
  public func cachedGroundElevation(at coordinate: CLLocationCoordinate2D) -> Double? {
    lock.lock()
    let value = Self.sample(coordinate) { key in
      guard let heights = tiles[key] else { return nil }
      useCounter += 1
      lastUsed[key] = useCounter
      return heights
    }
    lock.unlock()
    if value == nil { prefetch([coordinate]) }
    return value
  }

  /// Starts loading the tiles under `coordinates`, at most `limit` tiles.
  public func prefetch(_ coordinates: [CLLocationCoordinate2D], limit: Int = 32) {
    var keys: [TileKey] = []
    var seen = Set<TileKey>()
    for coordinate in coordinates {
      for key in Self.tileKeys(for: coordinate) where seen.insert(key).inserted {
        keys.append(key)
      }
      if keys.count >= limit { break }
    }
    for key in keys.prefix(limit) { load(key, retryFailed: false) { _ in } }
  }

  // MARK: Tiles

  private func load(_ key: TileKey, retryFailed: Bool, completion: @escaping (Result<[Float], Error>) -> Void) {
    lock.lock()
    if let heights = tiles[key] {
      lock.unlock()
      return completion(.success(heights))
    }
    if !retryFailed, let failed = failedAt[key], Date().timeIntervalSince(failed) < Self.retryInterval {
      lock.unlock()
      return completion(.failure(TerrainError.download("Elevation tile \(key.z)/\(key.x)/\(key.y) failed recently")))
    }
    if waiting[key] != nil {
      waiting[key]?.append(completion)
      lock.unlock()
      return
    }
    waiting[key] = [completion]
    let template = tileURLTemplate
    lock.unlock()

    workQueue.async { [self] in
      let cacheURL = Self.cacheDirectory.appendingPathComponent(
        "\(abs(Self.stableHash(template)))-\(key.z)-\(key.x)-\(key.y).png")
      if let cached = try? Data(contentsOf: cacheURL), let heights = Self.decode(png: cached) {
        return finish(key, .success(heights))
      }
      let urlString = template
        .replacingOccurrences(of: "{z}", with: "\(key.z)")
        .replacingOccurrences(of: "{x}", with: "\(key.x)")
        .replacingOccurrences(of: "{y}", with: "\(key.y)")
      guard let url = URL(string: urlString) else {
        return finish(key, .failure(TerrainError.download("Bad elevation tile URL \(urlString)")))
      }
      var request = URLRequest(url: url)
      request.setValue("munim-maps (https://github.com/munimtechnologies/munim-maps)", forHTTPHeaderField: "User-Agent")
      URLSession.shared.dataTask(with: request) { [self] data, response, error in
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard let data, error == nil, (200..<300).contains(status) || status == 0 else {
          let reason = error?.localizedDescription ?? "HTTP \(status)"
          return finish(key, .failure(TerrainError.download(
            "Could not load elevation tile \(key.z)/\(key.x)/\(key.y): \(reason)")))
        }
        guard let heights = Self.decode(png: data) else {
          return finish(key, .failure(TerrainError.decode(
            "Could not read elevation tile \(key.z)/\(key.x)/\(key.y)")))
        }
        try? FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
        finish(key, .success(heights))
      }.resume()
    }
  }

  private func finish(_ key: TileKey, _ result: Result<[Float], Error>) {
    lock.lock()
    switch result {
    case .success(let heights):
      tiles[key] = heights
      useCounter += 1
      lastUsed[key] = useCounter
      failedAt[key] = nil
      if tiles.count > Self.memoryTiles, let oldest = lastUsed.min(by: { $0.value < $1.value })?.key {
        tiles[oldest] = nil
        lastUsed[oldest] = nil
      }
    case .failure:
      failedAt[key] = Date()
    }
    let callbacks = waiting.removeValue(forKey: key) ?? []
    lock.unlock()
    for callback in callbacks { callback(result) }
    DispatchQueue.main.async {
      switch result {
      case .success:
        NotificationCenter.default.post(name: Self.didLoadTileNotification, object: self)
      case .failure(let error):
        NotificationCenter.default.post(
          name: Self.didFailNotification, object: self, userInfo: ["message": error.localizedDescription])
      }
    }
  }

  /// A hash that stays the same between launches (unlike `hashValue`), for
  /// cache file names.
  private static func stableHash(_ string: String) -> Int {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in string.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 1_099_511_628_211
    }
    return Int(truncatingIfNeeded: hash & 0x7fff_ffff_ffff)
  }

  // MARK: Sampling

  /// Global pixel position at `zoom`, measured so whole numbers are pixel
  /// centres.
  private static func pixel(for coordinate: CLLocationCoordinate2D) -> (x: Double, y: Double) {
    let size = Double(1 << zoom) * Double(tileSize)
    let latitude = min(85.051_128, max(-85.051_128, coordinate.latitude)) * .pi / 180
    var longitude = coordinate.longitude.truncatingRemainder(dividingBy: 360)
    if longitude >= 180 { longitude -= 360 }
    if longitude < -180 { longitude += 360 }
    let x = (longitude + 180) / 360 * size
    let y = (1 - asinh(tan(latitude)) / .pi) / 2 * size
    return (x - 0.5, y - 0.5)
  }

  /// The four pixels around a point, wrapped east-west and clamped at the poles.
  private static func corners(for coordinate: CLLocationCoordinate2D)
    -> (pixels: [(x: Int, y: Int)], fx: Double, fy: Double)
  {
    let size = (1 << zoom) * tileSize
    let p = pixel(for: coordinate)
    let x0 = Int(floor(p.x))
    let y0 = Int(floor(p.y))
    let wrap = { (x: Int) in ((x % size) + size) % size }
    let clamp = { (y: Int) in min(size - 1, max(0, y)) }
    let pixels = [(x0, y0), (x0 + 1, y0), (x0, y0 + 1), (x0 + 1, y0 + 1)].map { (wrap($0.0), clamp($0.1)) }
    return (pixels, p.x - Double(x0), p.y - Double(y0))
  }

  static func tileKeys(for coordinate: CLLocationCoordinate2D) -> [TileKey] {
    guard CLLocationCoordinate2DIsValid(coordinate) else { return [] }
    var keys: [TileKey] = []
    for pixel in corners(for: coordinate).pixels {
      let key = TileKey(z: zoom, x: pixel.x / tileSize, y: pixel.y / tileSize)
      if !keys.contains(key) { keys.append(key) }
    }
    return keys
  }

  /// Bilinear height at `coordinate`, or nil when a tile is missing.
  static func sample(_ coordinate: CLLocationCoordinate2D, tile: (TileKey) -> [Float]?) -> Double? {
    guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
    let (pixels, fx, fy) = corners(for: coordinate)
    var values: [Double] = []
    values.reserveCapacity(4)
    for pixel in pixels {
      let key = TileKey(z: zoom, x: pixel.x / tileSize, y: pixel.y / tileSize)
      guard let heights = tile(key) else { return nil }
      values.append(Double(heights[(pixel.y % tileSize) * tileSize + pixel.x % tileSize]))
    }
    let top = values[0] + (values[1] - values[0]) * fx
    let bottom = values[2] + (values[3] - values[2]) * fx
    return top + (bottom - top) * fy
  }

  // MARK: Decoding

  /// Heights from a Terrarium PNG, read from the raw pixel bytes so no
  /// colour management can change them.
  static func decode(png data: Data) -> [Float]? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary),
          image.width == tileSize, image.height == tileSize
    else { return nil }
    if image.bitsPerComponent == 8, image.bitsPerPixel == 24 || image.bitsPerPixel == 32,
       let raw = image.dataProvider?.data, let bytes = CFDataGetBytePtr(raw)
    {
      let stride = image.bitsPerPixel / 8
      let alpha = image.alphaInfo
      let alphaFirst = alpha == .first || alpha == .premultipliedFirst || alpha == .noneSkipFirst
      let littleEndian = image.bitmapInfo.contains(.byteOrder32Little)
      // Offsets of R, G and B within a pixel.
      let offsets: (Int, Int, Int)
      if stride == 3 {
        offsets = (0, 1, 2)
      } else if littleEndian {
        offsets = alphaFirst ? (2, 1, 0) : (3, 2, 1)
      } else {
        offsets = alphaFirst ? (1, 2, 3) : (0, 1, 2)
      }
      return heights(bytes: bytes, bytesPerRow: image.bytesPerRow, stride: stride, offsets: offsets)
    }
    // Other layouts (palette or 16-bit PNGs): draw into plain 8-bit RGBA in
    // the image's own colour space, which does not convert the values.
    let space = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
    guard space.model == .rgb else { return nil }
    var pixels = [UInt8](repeating: 0, count: tileSize * tileSize * 4)
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard let context = CGContext(
        data: buffer.baseAddress, width: tileSize, height: tileSize, bitsPerComponent: 8,
        bytesPerRow: tileSize * 4, space: space,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
      else { return false }
      context.interpolationQuality = .none
      context.draw(image, in: CGRect(x: 0, y: 0, width: tileSize, height: tileSize))
      return true
    }
    guard drawn else { return nil }
    return pixels.withUnsafeBufferPointer { buffer in
      heights(bytes: buffer.baseAddress!, bytesPerRow: tileSize * 4, stride: 4, offsets: (0, 1, 2))
    }
  }

  private static func heights(
    bytes: UnsafePointer<UInt8>, bytesPerRow: Int, stride: Int, offsets: (Int, Int, Int)
  ) -> [Float] {
    var result = [Float](repeating: 0, count: tileSize * tileSize)
    for y in 0..<tileSize {
      let row = bytes + y * bytesPerRow
      for x in 0..<tileSize {
        let p = row + x * stride
        let r = Float(p[offsets.0]), g = Float(p[offsets.1]), b = Float(p[offsets.2])
        result[y * tileSize + x] = r * 256 + g + b / 256 - 32768
      }
    }
    return result
  }
}
