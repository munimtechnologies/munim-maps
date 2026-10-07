#if canImport(MapboxMaps)
import MapboxMaps
import MapKit
import UIKit

/// Pictures for the marker styles MapKit draws itself (pin, balloon); the
/// others come from munim-maps' shared `MarkerImages`.
enum MapboxMarkerImages {
  private static let cache = NSCache<NSString, UIImage>()

  static func key(_ m: MunimMarker, selected: Bool, hasPhoto: Bool) -> String {
    let badges = m.badges.map { "\($0.text)/\($0.position.rawValue)/\($0.color)/\($0.textColor)" }.joined(separator: ";")
    let text = [m.style.rawValue, m.color, m.glyph, m.glyphSymbol, m.selectedGlyphSymbol, m.glyphColor, m.imageUri,
                "\(m.imageSize)", m.borderColor, "\(m.borderWidth)", badges, m.title, "\(selected)", "\(hasPhoto)"]
      .joined(separator: "|")
    return String(UInt(bitPattern: text.hashValue), radix: 36)
  }

  private static func renderer(_ size: CGSize, _ scale: CGFloat) -> UIGraphicsImageRenderer {
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = false
    return UIGraphicsImageRenderer(size: size, format: format)
  }

  /// The classic map pin: a round head on a short needle, bottom at the tip.
  static func pin(_ m: MunimMarker, scale: CGFloat) -> UIImage {
    let cacheKey = "pin|\(m.color)|\(scale)" as NSString
    if let image = cache.object(forKey: cacheKey) { return image }
    let color = UIColor(mapModelHex: m.color) ?? .systemRed
    let size = CGSize(width: 22, height: 40)
    let image = renderer(size, scale).image { context in
      let cg = context.cgContext
      cg.setStrokeColor(UIColor(white: 0.35, alpha: 1).cgColor)
      cg.setLineWidth(2)
      cg.move(to: CGPoint(x: 11, y: 18))
      cg.addLine(to: CGPoint(x: 11, y: 39))
      cg.strokePath()
      cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor(white: 0, alpha: 0.3).cgColor)
      color.setFill()
      cg.fillEllipse(in: CGRect(x: 2, y: 1, width: 18, height: 18))
      cg.setShadow(offset: .zero, blur: 0, color: nil)
      UIColor(white: 1, alpha: 0.45).setFill()
      cg.fillEllipse(in: CGRect(x: 6, y: 4, width: 6, height: 6))
    }
    cache.setObject(image, forKey: cacheKey)
    return image
  }

  /// MapKit's balloon marker: a round balloon with a point, a glyph inside.
  static func balloon(_ m: MunimMarker, selected: Bool, scale: CGFloat) -> UIImage {
    let cacheKey = "balloon|\(m.color)|\(m.glyph)|\(m.glyphSymbol)|\(m.selectedGlyphSymbol)|\(m.glyphColor)|\(selected)|\(scale)" as NSString
    if let image = cache.object(forKey: cacheKey) { return image }
    let color = UIColor(mapModelHex: m.color) ?? .systemRed
    let glyphColor = UIColor(mapModelHex: m.glyphColor) ?? .white
    let d: CGFloat = selected ? 44 : 30
    let size = CGSize(width: d + 4, height: d * 1.32 + 4)
    let image = renderer(size, scale).image { context in
      let cg = context.cgContext
      let center = CGPoint(x: size.width / 2, y: d / 2 + 2)
      let path = UIBezierPath()
      path.addArc(withCenter: center, radius: d / 2, startAngle: .pi * 0.75, endAngle: .pi * 0.25, clockwise: true)
      path.addLine(to: CGPoint(x: center.x, y: size.height - 2))
      path.close()
      cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor(white: 0, alpha: 0.3).cgColor)
      color.setFill()
      path.fill()
      cg.setShadow(offset: .zero, blur: 0, color: nil)
      UIColor.white.withAlphaComponent(0.9).setStroke()
      path.lineWidth = 1.5
      path.stroke()
      let symbolName = selected && !m.selectedGlyphSymbol.isEmpty ? m.selectedGlyphSymbol : m.glyphSymbol
      if !symbolName.isEmpty, let symbol = UIImage(
        systemName: symbolName, withConfiguration: UIImage.SymbolConfiguration(pointSize: d * 0.42, weight: .semibold))?
        .withTintColor(glyphColor, renderingMode: .alwaysOriginal) {
        symbol.draw(at: CGPoint(x: center.x - symbol.size.width / 2, y: center.y - symbol.size.height / 2))
      } else {
        let text = (m.glyph.isEmpty ? "●" : m.glyph) as NSString
        let font = UIFont.systemFont(ofSize: m.glyph.isEmpty ? d * 0.28 : d * 0.45, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: glyphColor]
        let textSize = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2), withAttributes: attributes)
      }
    }
    cache.setObject(image, forKey: cacheKey)
    return image
  }

  /// While a picture loads: a small grey dot.
  static func placeholder(_ m: MunimMarker, scale: CGFloat) -> UIImage {
    let d = CGFloat(m.imageSize > 0 ? min(m.imageSize, 24) : 14)
    return renderer(CGSize(width: d, height: d), scale).image { context in
      UIColor(white: 0.75, alpha: 0.9).setFill()
      context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: d, height: d))
    }
  }
}

/// Images and model files from URIs: `http(s)://`, `file://`, absolute
/// paths, `data:` URIs and Metro / bundled assets.
enum MapboxImages {
  static func url(for uri: String) -> URL? {
    if uri.hasPrefix("/") { return URL(fileURLWithPath: uri) }
    if let url = URL(string: uri), url.scheme != nil { return url }
    if let path = Bundle.main.path(forResource: uri, ofType: nil) { return URL(fileURLWithPath: path) }
    return nil
  }

  static func loadSync(_ uri: String) -> UIImage? {
    if let data = dataURI(uri) { return UIImage(data: data, scale: UIScreen.main.scale) }
    if uri.hasPrefix("/") { return UIImage(contentsOfFile: uri) }
    if let url = URL(string: uri), url.isFileURL { return UIImage(contentsOfFile: url.path) }
    return UIImage(named: uri)
  }

  static func load(uri: String, completion: @escaping (UIImage?) -> Void) {
    if let image = loadSync(uri) { return completion(image) }
    MapModelNodes.loadImage(uri: uri) { result in
      DispatchQueue.main.async {
        switch result {
        case .success(let image): completion(image)
        case .failure: completion(nil)
        }
      }
    }
  }

  private static func dataURI(_ uri: String) -> Data? {
    guard uri.hasPrefix("data:"), let comma = uri.firstIndex(of: ",") else { return nil }
    return Data(base64Encoded: String(uri[uri.index(after: comma)...]))
  }

  /// Mapbox loads models itself from `http(s)://`, `file://` and `asset://`;
  /// Metro's development URLs are downloaded to a file first.
  static func resolveModelURI(_ uri: String, completion: @escaping (String) -> Void) {
    if uri.hasPrefix("/") { return completion(URL(fileURLWithPath: uri).absoluteString) }
    guard let url = URL(string: uri), url.scheme == "http" || url.scheme == "https",
          url.host == "localhost" || url.host?.hasPrefix("192.168.") == true || url.host?.hasPrefix("10.") == true
    else { return completion(uri) }
    URLSession.shared.downloadTask(with: url) { location, _, _ in
      guard let location else { return DispatchQueue.main.async { completion(uri) } }
      let destination = FileManager.default.temporaryDirectory.appendingPathComponent("munim-mapbox-\(url.lastPathComponent)")
      try? FileManager.default.removeItem(at: destination)
      try? FileManager.default.moveItem(at: location, to: destination)
      DispatchQueue.main.async { completion(destination.absoluteString) }
    }.resume()
  }
}

/// Reverse geocoding with Mapbox's Geocoding API v6 and the public token.
enum MapboxGeocoder {
  static func reverse(_ coordinate: CLLocationCoordinate2D, completion: @escaping (Result<MunimAddress, Error>) -> Void) {
    let token = MapboxOptions.accessToken
    guard !token.isEmpty, var components = URLComponents(string: "https://api.mapbox.com/search/geocode/v6/reverse") else {
      return completion(.failure(MunimMapEngineError("Mapbox: no access token for geocoding")))
    }
    components.queryItems = [
      URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
      URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
      URLQueryItem(name: "access_token", value: token),
    ]
    guard let url = components.url else { return completion(.failure(MunimMapEngineError("Mapbox: bad geocoding URL"))) }
    URLSession.shared.dataTask(with: url) { data, response, error in
      let result: Result<MunimAddress, Error> = Result {
        if let error { throw error }
        guard let data, let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
          throw MunimMapEngineError("Mapbox: no geocoding result")
        }
        if let code = (response as? HTTPURLResponse)?.statusCode, code >= 400 {
          throw MunimMapEngineError("Mapbox geocoding \(code): \(json["message"] as? String ?? "")")
        }
        guard let feature = (json["features"] as? [[String: Any]])?.first,
              let properties = feature["properties"] as? [String: Any] else {
          throw MunimMapEngineError("Mapbox: nothing found here")
        }
        let context = properties["context"] as? [String: Any] ?? [:]
        func name(_ key: String) -> String { (context[key] as? [String: Any])?["name"] as? String ?? "" }
        let address = context["address"] as? [String: Any]
        let street = (address?["name"] as? String) ?? name("street")
        let country = context["country"] as? [String: Any]
        return MunimAddress(
          name: properties["name"] as? String ?? "",
          street: street,
          city: name("place").isEmpty ? name("locality") : name("place"),
          region: name("region"),
          postalCode: name("postcode"),
          country: country?["name"] as? String ?? "",
          countryCode: (country?["country_code"] as? String ?? "").uppercased(),
          formatted: properties["full_address"] as? String ?? properties["place_formatted"] as? String ?? "")
      }
      DispatchQueue.main.async { completion(result) }
    }.resume()
  }
}
#endif
