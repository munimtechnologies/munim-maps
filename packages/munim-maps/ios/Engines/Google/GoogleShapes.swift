#if canImport(GoogleMaps)
import GoogleMaps
import GoogleMapsUtils
import MapKit
import UIKit

// Polylines, polygons, circles, tile overlays, ground overlays and heatmaps
// on Google, and hit-testing the shared shapes for `onOverlayPress`.

extension GoogleMapEngine {
  /// Ground points per screen point now (for dashes and tap tolerances).
  var metersPerPoint: Double {
    guard let mapView else { return 1 }
    if let state = cameraSource?.cameraState(previous: nil), state.focalLength > 0 {
      return state.distance / state.focalLength
    }
    return 1 / GoogleCameraSource.pointsPerMeter(
      zoom: Double(mapView.camera.zoom), latitude: mapView.camera.target.latitude)
  }

  // MARK: Polylines

  func applyPolylines() {
    mode3d?.setPolylines(polylines)
    guard let mapView else { return }
    var wanted = Set<String>()
    for p in polylines {
      wanted.insert(p.id)
      let line = gmsPolylines[p.id] ?? GMSPolyline()
      configure(line, p)
      line.map = mapView
      gmsPolylines[p.id] = line
    }
    for (id, line) in gmsPolylines where !wanted.contains(id) {
      line.map = nil
      gmsPolylines[id] = nil
    }
    dashZoom = mapView.camera.zoom
  }

  private func configure(_ line: GMSPolyline, _ p: MunimPolyline) {
    let extras = options["polylines"][p.id]
    let path = Self.trimmed(p.coordinates, from: p.strokeStart, to: p.strokeEnd)
    line.path = path
    line.strokeWidth = CGFloat(extras["width"].double(p.strokeWidth))
    let color = UIColor(mapModelHex: p.strokeColor) ?? .systemBlue
    line.strokeColor = color
    line.geodesic = p.geodesic
    line.zIndex = Int32(clamping: Int(p.zIndex.rounded()))
    line.isTappable = false
    line.userData = ["kind": "polyline", "id": p.id]
    line.title = p.id
    line.spans = spans(for: p, path: path, color: color, extras: extras)
  }

  private func spans(for p: MunimPolyline, path: GMSPath, color: UIColor, extras: GoogleJSON) -> [GMSStyleSpan]? {
    // Explicit spans: [{ color, toColor, segments, stampImageUri }].
    let custom = extras["spans"].array
    if !custom.isEmpty {
      return custom.map { span -> GMSStyleSpan in
        let from = span["color"].color ?? color
        let style = span["toColor"].color.map { GMSStrokeStyle.gradient(from: from, to: $0) }
          ?? GMSStrokeStyle.solidColor(from)
        if let uri = span["stampImageUri"].string { applyStamp(style, uri: uri, sprite: false) }
        let segments = span["segments"].double(1)
        return GMSStyleSpan(style: style, segments: segments)
      }
    }
    // A texture or sprite stamped along the whole line.
    if let uri = extras["stamp"]["imageUri"].string {
      let sprite = extras["stamp"]["kind"].string == "sprite"
      let style = sprite ? GMSStrokeStyle.transparentStroke(withStamp: GMSSpriteStyle(image: GoogleMarkerIcons.transparent))
        : GMSStrokeStyle.solidColor(color)
      applyStamp(style, uri: uri, sprite: sprite)
      return [GMSStyleSpan(style: style)]
    }
    // A gradient along the line, one gradient span per segment.
    let colors = p.strokeColors.split(separator: ",").compactMap {
      UIColor(mapModelHex: $0.trimmingCharacters(in: .whitespaces))
    }
    if colors.count >= 2, path.count() >= 2 {
      let given = p.strokeColorLocations.split(separator: ",").compactMap {
        Double($0.trimmingCharacters(in: .whitespaces))
      }
      let stops = given.count == colors.count
        ? given : colors.indices.map { Double($0) / Double(colors.count - 1) }
      let fractions = Self.cumulativeFractions(path)
      return (0..<Int(path.count()) - 1).map { i in
        GMSStyleSpan(
          style: GMSStrokeStyle.gradient(
            from: Self.color(at: fractions[i], colors: colors, stops: stops),
            to: Self.color(at: fractions[i + 1], colors: colors, stops: stops)),
          segments: 1)
      }
    }
    // Dashes: Google iOS has no stroke patterns, so they are drawn as
    // spans in metres at the current zoom (redone when the zoom changes).
    let pattern = dashPattern(p.dashPattern, extras: extras["pattern"])
    if !pattern.isEmpty {
      let perPoint = metersPerPoint
      var styles: [GMSStrokeStyle] = []
      var lengths: [NSNumber] = []
      for (i, length) in pattern.enumerated() {
        styles.append(i % 2 == 0 ? GMSStrokeStyle.solidColor(color) : GMSStrokeStyle.solidColor(.clear))
        lengths.append(NSNumber(value: max(0.01, length * perPoint)))
      }
      return GMSStyleSpans(path, styles, lengths, .rhumb)
    }
    return nil
  }

  /// Dash and gap lengths in points: `google.polylines[id].pattern`
  /// (`[{ type: 'dash' | 'gap' | 'dot', length }]`) or `dashPattern`.
  private func dashPattern(_ text: String, extras: GoogleJSON) -> [Double] {
    let items = extras.array
    if !items.isEmpty {
      var lengths: [Double] = []
      for item in items {
        let length = item["length"].double(item["type"].string == "dot" ? 1 : 10)
        let isGap = item["type"].string == "gap"
        // Alternate drawn and gap lengths, merging neighbours of the same kind.
        if lengths.count % 2 == (isGap ? 1 : 0) {
          lengths.append(length)
        } else if !lengths.isEmpty {
          lengths[lengths.count - 1] += length
        } else {
          lengths.append(0)
          lengths.append(length)
        }
      }
      if lengths.count % 2 == 1 { lengths.append(0) }
      return lengths
    }
    let values = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard !values.isEmpty, values.contains(where: { $0 > 0 }) else { return [] }
    return values.count % 2 == 0 ? values : values + values
  }

  private func applyStamp(_ style: GMSStrokeStyle, uri: String, sprite: Bool) {
    if let image = photos[uri] {
      style.stampStyle = sprite ? GMSSpriteStyle(image: image) : GMSTextureStyle(image: image)
    } else {
      loadPhoto(uri)
    }
  }

  /// Re-applies what uses an image once it has loaded.
  func applyGoogleImages(_ uri: String) {
    applyPolylines()
    applyGroundOverlays()
  }

  /// Dashes are in metres on Google; redo them when the zoom changed.
  func updateDashesIfZoomChanged() {
    guard let mapView, abs(mapView.camera.zoom - dashZoom) > 0.25 else { return }
    dashZoom = mapView.camera.zoom
    for p in polylines where !p.dashPattern.isEmpty || options["polylines"][p.id]["pattern"].exists {
      if let line = gmsPolylines[p.id] {
        line.spans = spans(for: p, path: line.path ?? GMSPath(), color: line.strokeColor,
                           extras: options["polylines"][p.id])
      }
    }
  }

  /// The part of a line between two fractions of its length.
  static func trimmed(_ coordinates: [CLLocationCoordinate2D], from start: Double, to end: Double) -> GMSPath {
    let path = GMSMutablePath()
    guard coordinates.count >= 2, start > 0 || end < 1 else {
      coordinates.forEach { path.add($0) }
      return path
    }
    var lengths: [Double] = [0]
    for i in 1..<coordinates.count {
      lengths.append(lengths[i - 1] + GMSGeometryDistance(coordinates[i - 1], coordinates[i]))
    }
    let total = lengths.last ?? 0
    guard total > 0 else { return path }
    let a = max(0, min(1, start)) * total, b = max(0, min(1, end)) * total
    guard b > a else { return path }
    func point(at distance: Double) -> CLLocationCoordinate2D {
      var i = 1
      while i < lengths.count - 1, lengths[i] < distance { i += 1 }
      let span = lengths[i] - lengths[i - 1]
      let f = span > 0 ? (distance - lengths[i - 1]) / span : 0
      return GMSGeometryInterpolate(coordinates[i - 1], coordinates[i], f)
    }
    path.add(point(at: a))
    for i in 1..<coordinates.count - 1 where lengths[i] > a && lengths[i] < b { path.add(coordinates[i]) }
    path.add(point(at: b))
    return path
  }

  static func cumulativeFractions(_ path: GMSPath) -> [Double] {
    var lengths: [Double] = [0]
    let count = Int(path.count())
    for i in 1..<max(1, count) {
      lengths.append(lengths[i - 1] + GMSGeometryDistance(path.coordinate(at: UInt(i - 1)), path.coordinate(at: UInt(i))))
    }
    let total = max(1e-9, lengths.last ?? 0)
    return lengths.map { $0 / total }
  }

  static func color(at f: Double, colors: [UIColor], stops: [Double]) -> UIColor {
    guard let first = colors.first, let last = colors.last else { return .systemBlue }
    if f <= stops[0] { return first }
    for i in 1..<colors.count where f <= stops[i] {
      let span = max(1e-9, stops[i] - stops[i - 1])
      return mix(colors[i - 1], colors[i], (f - stops[i - 1]) / span)
    }
    return last
  }

  static func mix(_ a: UIColor, _ b: UIColor, _ t: Double) -> UIColor {
    var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
    var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
    a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
    b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
    let t = CGFloat(t)
    return UIColor(red: ar + (br - ar) * t, green: ag + (bg - ag) * t, blue: ab + (bb - ab) * t, alpha: aa + (ba - aa) * t)
  }

  // MARK: Polygons and circles

  func applyPolygons() {
    mode3d?.setPolygons(polygons)
    guard let mapView else { return }
    var wanted = Set<String>()
    for p in polygons {
      wanted.insert(p.id)
      let extras = options["polygons"][p.id]
      let polygon = gmsPolygons[p.id] ?? GMSPolygon()
      let path = GMSMutablePath()
      p.coordinates.forEach { path.add($0) }
      polygon.path = path
      polygon.holes = p.holes.map { ring in
        let hole = GMSMutablePath()
        ring.forEach { hole.add($0) }
        return hole
      }
      polygon.strokeColor = UIColor(mapModelHex: p.strokeColor)
      polygon.fillColor = UIColor(mapModelHex: p.fillColor)
      polygon.strokeWidth = CGFloat(p.strokeWidth)
      polygon.geodesic = extras["geodesic"].bool(false)
      polygon.zIndex = Int32(clamping: Int(p.zIndex.rounded()))
      polygon.isTappable = false
      polygon.userData = ["kind": "polygon", "id": p.id]
      polygon.title = p.id
      polygon.map = mapView
      gmsPolygons[p.id] = polygon
    }
    for (id, polygon) in gmsPolygons where !wanted.contains(id) {
      polygon.map = nil
      gmsPolygons[id] = nil
    }
  }

  func applyCircles() {
    guard let mapView else { return }
    var wanted = Set<String>()
    for c in circles {
      wanted.insert(c.id)
      let circle = gmsCircles[c.id] ?? GMSCircle()
      circle.position = CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
      circle.radius = c.radius
      circle.strokeColor = UIColor(mapModelHex: c.strokeColor)
      circle.fillColor = UIColor(mapModelHex: c.fillColor)
      circle.strokeWidth = CGFloat(c.strokeWidth)
      circle.zIndex = Int32(clamping: Int(c.zIndex.rounded()))
      circle.isTappable = false
      circle.userData = ["kind": "circle", "id": c.id]
      circle.title = c.id
      circle.map = mapView
      gmsCircles[c.id] = circle
    }
    for (id, circle) in gmsCircles where !wanted.contains(id) {
      circle.map = nil
      gmsCircles[id] = nil
    }
  }

  // MARK: Hit testing

  /// The topmost tappable shape under `point`.
  public func overlayHit(at point: CGPoint) -> (id: String, kind: String)? {
    guard let mapView else { return nil }
    let coordinate = mapView.projection.coordinate(for: point)
    guard CLLocationCoordinate2DIsValid(coordinate) else { return nil }
    let perPoint = metersPerPoint
    var best: (id: String, kind: String, z: Double, order: Int)?
    func consider(_ id: String, _ kind: String, _ z: Double, _ order: Int) {
      if best == nil || z > best!.z || (z == best!.z && order > best!.order) { best = (id, kind, z, order) }
    }
    for (i, p) in polygons.enumerated() where p.tappable {
      let path = GMSMutablePath()
      p.coordinates.forEach { path.add($0) }
      let inHole = p.holes.contains { ring in
        let hole = GMSMutablePath()
        ring.forEach { hole.add($0) }
        return GMSGeometryContainsLocation(coordinate, hole, false)
      }
      if GMSGeometryContainsLocation(coordinate, path, false) && !inHole {
        consider(p.id, "polygon", p.zIndex, 1000 + i)
      }
    }
    for (i, c) in circles.enumerated() where c.tappable {
      let center = CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
      if GMSGeometryDistance(center, coordinate) <= c.radius + perPoint * 4 {
        consider(c.id, "circle", c.zIndex, 2000 + i)
      }
    }
    for (i, p) in polylines.enumerated() where p.tappable {
      let path = GMSMutablePath()
      p.coordinates.forEach { path.add($0) }
      let tolerance = (p.strokeWidth / 2 + 8) * perPoint
      if GMSGeometryIsLocationOnPathTolerance(coordinate, path, p.geodesic, tolerance) {
        consider(p.id, "polyline", p.zIndex, 3000 + i)
      }
    }
    return best.map { ($0.id, $0.kind) }
  }

  // MARK: Tile overlays

  func applyTileOverlays() {
    guard let mapView else { return }
    var wanted = Set<String>()
    for t in tileOverlays {
      wanted.insert(t.id)
      let extras = options["tileOverlays"][t.id]
      let key = "\(t.urlTemplate)|\(t.minimumZoom)|\(t.maximumZoom)"
      var layer = tileLayers[t.id]
      if layer == nil || (layer?.userDataKey != key) {
        layer?.map = nil
        let template = t.urlTemplate
        let minZoom = t.minimumZoom, maxZoom = t.maximumZoom
        let urlLayer = GMSURLTileLayer { x, y, zoom in
          if minZoom > 0, Double(zoom) < minZoom { return nil }
          if maxZoom > 0, Double(zoom) > maxZoom { return nil }
          return Self.tileURL(template, x: x, y: y, zoom: zoom)
        }
        urlLayer.userDataKey = key
        layer = urlLayer
      }
      guard let layer else { continue }
      layer.opacity = Float(t.opacity)
      layer.zIndex = Int32(clamping: Int(t.zIndex.rounded()))
      layer.tileSize = Int(extras["tileSize"].double(256))
      layer.fadeIn = extras["fadeIn"].bool(true)
      if let agent = extras["userAgent"].string { (layer as? GMSURLTileLayer)?.userAgent = agent }
      layer.map = mapView
      tileLayers[t.id] = layer
    }
    for (id, layer) in tileLayers where !wanted.contains(id) {
      layer.map = nil
      tileLayers[id] = nil
    }
  }

  /// `{x}`, `{y}`, `{z}`, `{-y}` (TMS), `{quadkey}`, `{s}` (a, b, c).
  static func tileURL(_ template: String, x: UInt, y: UInt, zoom: UInt) -> URL? {
    var quadkey = ""
    if template.contains("{quadkey}") {
      for i in stride(from: Int(zoom), to: 0, by: -1) {
        let mask = UInt(1) << UInt(i - 1)
        var digit = 0
        if x & mask != 0 { digit += 1 }
        if y & mask != 0 { digit += 2 }
        quadkey += "\(digit)"
      }
    }
    let flipped = (UInt(1) << zoom) - 1 - y
    let text = template
      .replacingOccurrences(of: "{x}", with: "\(x)")
      .replacingOccurrences(of: "{-y}", with: "\(flipped)")
      .replacingOccurrences(of: "{y}", with: "\(y)")
      .replacingOccurrences(of: "{z}", with: "\(zoom)")
      .replacingOccurrences(of: "{quadkey}", with: quadkey)
      .replacingOccurrences(of: "{s}", with: ["a", "b", "c"][Int((x + y) % 3)])
    if text.hasPrefix("/") { return URL(fileURLWithPath: text) }
    return URL(string: text)
  }

  /// Adds your own tile layer (a `GMSSyncTileLayer` or `GMSTileLayer`
  /// subclass) under an id; `removeTileLayer` takes it off.
  public func addTileLayer(_ layer: GMSTileLayer, id: String) {
    customTileLayers[id]?.map = nil
    customTileLayers[id] = layer
    layer.map = mapView
  }

  public func removeTileLayer(id: String) {
    customTileLayers[id]?.map = nil
    customTileLayers[id] = nil
  }

  func clearTileCache(id: String?) {
    for (key, layer) in tileLayers.merging(customTileLayers, uniquingKeysWith: { a, _ in a })
    where id == nil || key == id {
      layer.clearTileCache()
    }
    for (key, layer) in heatmapLayers where id == nil || key == id { layer.clearTileCache() }
  }

  // MARK: Ground overlays

  /// `google.groundOverlays`: images laid on the ground.
  func applyGroundOverlays() {
    guard let mapView else { return }
    var wanted = Set<String>()
    for item in options["groundOverlays"].array {
      guard let id = item["id"].string, let uri = item["imageUri"].string ?? item["image"].string else { continue }
      wanted.insert(id)
      guard let image = photos[uri] else {
        loadPhoto(uri)
        continue
      }
      let overlay = groundOverlays[id] ?? GMSGroundOverlay()
      overlay.icon = image
      if let bounds = item["bounds"].bounds {
        overlay.bounds = bounds
      } else if let position = item["position"].coordinate {
        let width = item["width"].double(100)
        let height = item["height"].double(width * Double(image.size.height / max(1, image.size.width)))
        let anchor = CGPoint(x: item["anchor"]["x"].double(0.5), y: item["anchor"]["y"].double(0.5))
        let west = GMSGeometryOffset(position, width * Double(anchor.x), 270)
        let east = GMSGeometryOffset(position, width * Double(1 - anchor.x), 90)
        let north = GMSGeometryOffset(position, height * Double(anchor.y), 0)
        let south = GMSGeometryOffset(position, height * Double(1 - anchor.y), 180)
        overlay.bounds = GMSCoordinateBounds(
          coordinate: CLLocationCoordinate2D(latitude: south.latitude, longitude: west.longitude),
          coordinate: CLLocationCoordinate2D(latitude: north.latitude, longitude: east.longitude))
      }
      if let x = item["anchor"]["x"].double, let y = item["anchor"]["y"].double {
        overlay.anchor = CGPoint(x: x, y: y)
      }
      overlay.bearing = item["bearing"].double(0)
      overlay.opacity = Float(item["opacity"].double(1 - item["transparency"].double(0)))
      overlay.zIndex = Int32(clamping: Int(item["zIndex"].double(0)))
      overlay.isTappable = item["tappable"].bool(false)
      overlay.userData = ["kind": "groundOverlay", "id": id]
      overlay.map = item["visible"].bool(true) ? mapView : nil
      groundOverlays[id] = overlay
    }
    for (id, overlay) in groundOverlays where !wanted.contains(id) {
      overlay.map = nil
      groundOverlays[id] = nil
    }
  }

  // MARK: Heatmaps

  /// `google.heatmaps`: weighted points drawn as a heat map (Utils).
  func applyHeatmaps() {
    guard let mapView else { return }
    var wanted = Set<String>()
    for item in options["heatmaps"].array {
      guard let id = item["id"].string else { continue }
      wanted.insert(id)
      let key = String(describing: item.raw ?? "")
      if heatmapLayers[id] != nil, overlayKeys["heatmap:\(id)"] == key { continue }
      overlayKeys["heatmap:\(id)"] = key
      let layer = heatmapLayers[id] ?? GMUHeatmapTileLayer()
      layer.weightedData = item["points"].array.compactMap { point in
        point.coordinate.map { GMUWeightedLatLng(coordinate: $0, intensity: Float(point["weight"].double(1))) }
      }
      layer.radius = UInt(max(10, min(50, item["radius"].double(20))))
      layer.opacity = Float(item["opacity"].double(0.7))
      layer.zIndex = Int32(clamping: Int(item["zIndex"].double(0)))
      let colors = item["gradient"]["colors"].array.compactMap(\.color)
      if colors.count >= 2 {
        let given = item["gradient"]["startPoints"].array.compactMap(\.double)
        let starts = given.count == colors.count ? given : colors.indices.map {
          0.2 + 0.8 * Double($0) / Double(colors.count - 1)
        }
        layer.gradient = GMUGradient(
          colors: colors, startPoints: starts.map { NSNumber(value: $0) },
          colorMapSize: UInt(item["gradient"]["colorMapSize"].double(256)))
      }
      if let low = item["minimumZoomIntensity"].double { layer.minimumZoomIntensity = UInt(low) }
      if let high = item["maximumZoomIntensity"].double { layer.maximumZoomIntensity = UInt(high) }
      layer.clearTileCache()
      layer.map = mapView
      heatmapLayers[id] = layer
    }
    for (id, layer) in heatmapLayers where !wanted.contains(id) {
      overlayKeys["heatmap:\(id)"] = nil
      layer.map = nil
      heatmapLayers[id] = nil
    }
  }

  // MARK: Google-only overlays

  func applyGoogleOverlays() {
    applyGroundOverlays()
    applyHeatmaps()
    applyKmlLayers()
    applyGeoJsonLayers()
    applyFeatureLayers()
  }

  /// Taps on overlays Google hit-tests itself (ground overlays, KML and
  /// GeoJSON features).
  func overlayTapped(_ overlay: GMSOverlay) {
    guard let info = overlay.userData as? [String: Any], let kind = info["kind"] as? String else { return }
    switch kind {
    case "groundOverlay":
      emit("groundOverlayPress", ["id": info["id"] ?? ""])
    case "kml":
      emit("kmlFeaturePress", ["layerId": info["layer"] ?? "", "title": overlay.title ?? "",
                               "snippet": (overlay as? GMSMarker)?.snippet ?? ""])
    case "geojson":
      emit("geoJsonFeaturePress", ["layerId": info["layer"] ?? "", "featureId": info["feature"] ?? "",
                                   "properties": info["properties"] ?? [:]])
    default:
      break
    }
  }
}

private var userDataKeyHandle: UInt8 = 0

extension GMSTileLayer {
  /// What the layer was made from, to know when to remake it.
  var userDataKey: String? {
    get { objc_getAssociatedObject(self, &userDataKeyHandle) as? String }
    set { objc_setAssociatedObject(self, &userDataKeyHandle, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC) }
  }
}
#endif
