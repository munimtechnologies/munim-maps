#if canImport(MapLibre)
import MapLibre
import MapKit
import UIKit

/// munim-maps' 2D features on MapLibre (iOS): markers, clusters, callouts,
/// dragging, polylines, polygons, circles and tile overlays, drawn as
/// GeoJSON sources with style layers so they sit in MapLibre's own layer
/// stack and survive style changes (`restore(_:)` after every style load).
/// The Android engine does the same (MapLibreFeatures.kt).
final class MapLibreFeatures {
  static let slotUser = "munim-slot-user"
  static let slotShapes = "munim-slot-shapes"
  static let slotMarkers = "munim-slot-markers"
  private static let markersSource = "munim-markers"
  private static let clusterPrefix = "munim-cluster|"

  weak var mapView: MLNMapView?
  private var style: MLNStyle? { mapView?.style }
  var onError: ((String) -> Void)?
  var onMarkerPress: ((String) -> Void)?
  var onMarkerDeselect: ((String) -> Void)?
  var onCalloutPress: ((String) -> Void)?
  var onCalloutAccessoryPress: ((String, String) -> Void)?
  var onClusterPress: ((String, [String], CLLocationCoordinate2D) -> Void)?
  var onOverlayPress: ((String, String, CLLocationCoordinate2D) -> Void)?
  var onMarkerDragStart: ((String, CLLocationCoordinate2D) -> Void)?
  var onMarkerDragEnd: ((String, CLLocationCoordinate2D) -> Void)?
  /// Each move while dragging.
  var onMarkerDrag: ((String, CLLocationCoordinate2D) -> Void)?

  private(set) var markers: [MunimMarker] = []
  private var markerIds: [String: MunimMarker] = [:]
  private var viewMarkerImages: [String: UIImage] = [:]
  var clusterStyles: [MunimClusterStyle] = [] {
    didSet {
      if let style { for layer in style.layers where layer.identifier.hasSuffix("|clusters") { style.removeLayer(layer) } }
      clusterImages.removeAll()
      markerSources.removeAll()
      apply()
    }
  }
  var polylines: [MunimPolyline] = [] { didSet { applyShapes() } }
  var polygons: [MunimPolygon] = [] { didSet { applyShapes() } }
  var circles: [MunimCircle] = [] { didSet { applyShapes() } }
  var tileOverlays: [MunimTileOverlay] = [] { didSet { applyTileOverlays() } }

  private var photos: [String: UIImage] = [:]
  private var loading = Set<String>()
  private var images = Set<String>()
  private var clusterImages = Set<String>()
  private var markerSources = Set<String>()
  private var shapeLayers: [String] = []
  private var shapeSources: [String] = []
  private var tileLayers: [String] = []
  private var hiddenForTiles: [String] = []
  private var titleFont: [String]?
  private(set) var firstLabelLayer: String?
  private(set) var selectedId: String?
  private var dragging: String?
  private let callout = MapLibreCalloutView()

  // MARK: Style

  /// After every style load: slots, images, every feature.
  func restore(_ style: MLNStyle) {
    images.removeAll()
    clusterImages.removeAll()
    markerSources.removeAll()
    shapeLayers.removeAll()
    shapeSources.removeAll()
    tileLayers.removeAll()
    hiddenForTiles.removeAll()
    firstLabelLayer = style.layers.first { $0 is MLNSymbolStyleLayer }?.identifier
    titleFont = style.layers.lazy.compactMap { ($0 as? MLNSymbolStyleLayer)?.textFontNames?.constantValue as? [String] }
      .first { !$0.isEmpty }
    if titleFont == nil {
      // Fonts set as expressions: the first literal list.
      titleFont = style.layers.lazy.compactMap { layer -> [String]? in
        guard let json = (layer as? MLNSymbolStyleLayer)?.textFontNames?.mgl_jsonExpressionObject as? [Any] else { return nil }
        return (json.last as? [String]) ?? ((json.count == 2 ? json[1] : nil) as? [String])
      }.first
    }
    for slot in [Self.slotUser, Self.slotShapes, Self.slotMarkers] where style.layer(withIdentifier: slot) == nil {
      let layer = MLNBackgroundStyleLayer(identifier: slot)
      layer.isVisible = false
      style.addLayer(layer)
    }
    applyTileOverlays()
    applyShapes()
    apply()
  }

  // MARK: Markers

  func setMarkers(_ value: [MunimMarker]) {
    markers = value
    markerIds = Dictionary(value.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    for m in value where !m.imageUri.isEmpty && (m.style == .image || m.style == .avatar) { loadPhoto(m.imageUri) }
    if let selectedId, markerIds[selectedId] == nil { hideCallout() }
    apply()
  }

  /// A `MarkerView`: a React Native view drawn to an image, as an image marker.
  func setViewMarker(_ marker: MunimMarker, image: UIImage?) {
    var m = marker
    m.style = .image
    m.imageUri = "munim-view:\(marker.id)"
    if let image { viewMarkerImages[marker.id] = image; photos[m.imageUri] = image }
    var list = markers.filter { $0.id != marker.id }
    list.append(m)
    setMarkers(list)
  }

  func setViewMarkerImage(_ image: UIImage?, id: String) {
    guard let image else { return }
    viewMarkerImages[id] = image
    photos["munim-view:\(id)"] = image
    images.removeAll()
    apply()
  }

  func removeViewMarker(_ id: String) {
    viewMarkerImages[id] = nil
    photos["munim-view:\(id)"] = nil
    setMarkers(markers.filter { $0.id != id })
  }

  func marker(_ id: String) -> MunimMarker? { markerIds[id] }

  private func loadPhoto(_ uri: String) {
    guard photos[uri] == nil, !loading.contains(uri), !uri.hasPrefix("munim-view:") else { return }
    loading.insert(uri)
    let url = uri.hasPrefix("/") ? URL(fileURLWithPath: uri) : URL(string: uri)
    guard let url else { return }
    URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
      let image = data.flatMap { UIImage(data: $0) }
      DispatchQueue.main.async {
        guard let self else { return }
        self.loading.remove(uri)
        if let image {
          self.photos[uri] = image
          self.images.removeAll()
          self.apply()
        } else {
          self.onError?("MapLibre: could not load marker image \(uri): \(error?.localizedDescription ?? "not an image")")
        }
      }
    }.resume()
  }

  private var scale: CGFloat { mapView?.window?.screen.scale ?? UIScreen.main.scale }

  /// The image for a marker, its name in the style, and its anchor (0…1).
  private func image(for m: MunimMarker, selected: Bool) -> (name: String, image: UIImage, anchor: CGPoint)? {
    let photo = photos[m.imageUri]
    var drawn: UIImage?
    var anchor = CGPoint(x: m.anchorX, y: m.anchorY)
    switch m.style {
    case .pin:
      drawn = MapLibreMarkerArt.pin(color: MapLibreMarkerArt.color(m.color, .systemRed), scale: scale)
      anchor = CGPoint(x: 0.5, y: 1)
    case .marker:
      drawn = MapLibreMarkerArt.balloon(
        fill: MapLibreMarkerArt.color(m.color, .systemRed), glyph: m.glyph, symbol: selected && !m.selectedGlyphSymbol.isEmpty ? m.selectedGlyphSymbol : m.glyphSymbol,
        glyphColor: MapLibreMarkerArt.color(m.glyphColor, .white), selected: selected, scale: scale)
      anchor = CGPoint(x: 0.5, y: 1)
      // The title under the balloon, as MapKit draws it (no glyphs needed from the style).
      if let balloon = drawn, !m.title.isEmpty, m.titleVisibility != .hidden {
        let titled = MapLibreMarkerArt.titled(balloon, title: m.title, scale: scale)
        drawn = titled.image
        anchor = CGPoint(x: 0.5, y: titled.anchorY)
      }
    default:
      drawn = MarkerImages.image(for: m, photo: photo, scale: scale)
    }
    guard let drawn else { return nil }
    let key = [m.style.rawValue, m.imageUri, "\(photo != nil)", "\(m.imageSize)", m.color, m.glyph, m.glyphSymbol,
               m.selectedGlyphSymbol, m.glyphColor, m.borderColor, "\(m.borderWidth)", m.title, "\(selected)",
               m.badges.map { "\($0.text)\($0.position.rawValue)\($0.color)\($0.textColor)" }.joined()].joined(separator: "|")
    let name = "munim-m|\(key.hashValue)"
    if !images.contains(name) {
      style?.setImage(drawn, forName: name)
      images.insert(name)
    }
    return (name, drawn, anchor)
  }

  private func feature(_ m: MunimMarker) -> MLNPointFeature? {
    let selected = m.id == selectedId && m.style == .marker
    guard let (name, image, anchor) = image(for: m, selected: selected) else { return nil }
    let feature = MLNPointFeature()
    feature.coordinate = CLLocationCoordinate2D(latitude: m.latitude, longitude: m.longitude)
    feature.identifier = m.id
    let required = m.displayPriority >= 1000 || m.collisionMode == .none
    feature.attributes = [
      "id": m.id,
      "icon": name,
      "offset": [(0.5 - anchor.x) * image.size.width, (0.5 - anchor.y) * image.size.height],
      "sort": m.zIndex + m.displayPriority / 10_000,
      "opacity": m.opacity,
      "req": required,
    ]
    return feature
  }

  func apply() {
    guard let style else { return }
    let visible = markers.filter(\.visible)
    var groups = Dictionary(grouping: visible, by: \.clusteringId)
    if groups[""] == nil { groups[""] = [] }
    var wanted = Set<String>()
    for (clusterId, members) in groups {
      let sourceId = clusterId.isEmpty ? Self.markersSource : "\(Self.markersSource)-c-\(clusterId)"
      wanted.insert(sourceId)
      let shape = MLNShapeCollectionFeature(shapes: members.compactMap(feature))
      if let source = style.source(withIdentifier: sourceId) as? MLNShapeSource {
        source.shape = shape
      } else {
        var options: [MLNShapeSourceOption: Any] = [:]
        if !clusterId.isEmpty {
          options[.clustered] = true
          options[.clusterRadius] = 48
          options[.maximumZoomLevelForClustering] = 18
        }
        let source = MLNShapeSource(identifier: sourceId, shape: shape, options: options)
        style.addSource(source)
        addMarkerLayers(style, source: source, clusterId: clusterId)
      }
      markerSources.insert(sourceId)
    }
    for sourceId in markerSources where !wanted.contains(sourceId) {
      for layer in style.layers where layer.identifier.hasPrefix("\(sourceId)|") { style.removeLayer(layer) }
      if let source = style.source(withIdentifier: sourceId) { style.removeSource(source) }
      markerSources.remove(sourceId)
    }
    positionCallout()
  }

  private func addMarkerLayers(_ style: MLNStyle, source: MLNShapeSource, clusterId: String) {
    guard let slot = style.layer(withIdentifier: Self.slotMarkers) else { return }
    for required in [false, true] {
      let layer = MLNSymbolStyleLayer(identifier: "\(source.identifier)|\(required ? "req" : "opt")", source: source)
      layer.iconImageName = NSExpression(forKeyPath: "icon")
      layer.iconOffset = NSExpression(mglJSONObject: ["get", "offset"])
      layer.iconAllowsOverlap = NSExpression(forConstantValue: required)
      layer.iconIgnoresPlacement = NSExpression(forConstantValue: required)
      layer.symbolSortKey = NSExpression(forKeyPath: "sort")
      layer.iconOpacity = NSExpression(forKeyPath: "opacity")
      layer.predicate = NSPredicate(mglJSONObject: ["all", ["!", ["has", "point_count"]], ["==", ["get", "req"], required]])
      style.insertLayer(layer, below: slot)
    }
    if !clusterId.isEmpty {
      let clusters = MLNSymbolStyleLayer(identifier: "\(source.identifier)|clusters", source: source)
      clusters.iconImageName = NSExpression(mglJSONObject: [
        "concat", "\(Self.clusterPrefix)\(clusterId)|", ["to-string", ["get", "point_count"]],
      ])
      clusters.iconAnchor = NSExpression(mglJSONObject: ["let", "a", "bottom", ["var", "a"]])
      clusters.iconAllowsOverlap = NSExpression(forConstantValue: true)
      clusters.iconIgnoresPlacement = NSExpression(forConstantValue: true)
      clusters.predicate = NSPredicate(mglJSONObject: ["has", "point_count"])
      style.insertLayer(clusters, below: slot)
    }
  }

  /// Draws cluster balloons on demand (`mapView(_:didFailToLoadImage:)`).
  func image(missing name: String) -> UIImage? {
    guard name.hasPrefix(Self.clusterPrefix) else { return nil }
    let parts = name.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    guard parts.count >= 3 else { return nil }
    let style = clusterStyles.first { $0.clusteringId == parts[1] }
    let count = parts[2]
    let glyph = (style?.glyph.isEmpty == false ? style!.glyph : "{count}").replacingOccurrences(of: "{count}", with: count)
    return MapLibreMarkerArt.balloon(
      fill: MapLibreMarkerArt.color(style?.color ?? "", .systemBlue), glyph: glyph, symbol: "",
      glyphColor: MapLibreMarkerArt.color(style?.glyphColor ?? "", .white), selected: false, scale: scale)
  }

  private var markerLayerIds: Set<String> {
    Set(markerSources.flatMap { ["\($0)|req", "\($0)|opt"] })
  }

  func marker(at point: CGPoint) -> MunimMarker? {
    guard let mapView, !markerSources.isEmpty else { return nil }
    let rect = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
    let hits = mapView.visibleFeatures(in: rect, styleLayerIdentifiers: markerLayerIds)
    return hits.compactMap { ($0.attribute(forKey: "id") as? String).flatMap { markerIds[$0] } }.max { $0.zIndex < $1.zIndex }
  }

  /// A tap at `point`: markers, clusters, callouts. True if taken.
  func handleTap(at point: CGPoint) -> Bool {
    guard let mapView, let style else { return false }
    for sourceId in markerSources where sourceId != Self.markersSource {
      let hits = mapView.visibleFeatures(at: point, styleLayerIdentifiers: ["\(sourceId)|clusters"])
      if let cluster = hits.first as? MLNPointFeatureCluster,
         let source = style.source(withIdentifier: sourceId) as? MLNShapeSource {
        let leaves = source.leaves(of: cluster, offset: 0, limit: 10_000)
        let ids = leaves.compactMap { $0.attribute(forKey: "id") as? String }
        onClusterPress?(String(sourceId.dropFirst("\(Self.markersSource)-c-".count)), ids, cluster.coordinate)
        return true
      }
    }
    if let marker = marker(at: point) {
      select(marker.id)
      return true
    }
    if selectedId != nil { deselect() }
    return false
  }

  func select(_ id: String) {
    guard let marker = markerIds[id] else { return }
    if let selectedId, selectedId != id { deselect() }
    selectedId = id
    onMarkerPress?(id)
    if marker.style == .marker { apply() }
    if marker.calloutEnabled && !(marker.title.isEmpty && marker.subtitle.isEmpty && marker.calloutDetail.isEmpty) {
      showCallout(marker)
    }
  }

  func deselect(_ id: String? = nil) {
    guard let current = selectedId else { return }
    if let id, id != current { return }
    selectedId = nil
    hideCallout()
    onMarkerDeselect?(current)
    if markerIds[current]?.style == .marker { apply() }
  }

  // MARK: Callouts

  private func showCallout(_ marker: MunimMarker) {
    guard let mapView else { return }
    callout.bind(marker, onPress: { [weak self] in self?.onCalloutPress?(marker.id) }) { [weak self] side in
      self?.onCalloutAccessoryPress?(marker.id, side)
    }
    if callout.superview !== mapView.superview { mapView.superview?.addSubview(callout) }
    callout.superview?.bringSubviewToFront(callout)
    callout.isHidden = false
    positionCallout()
  }

  private func hideCallout() {
    callout.isHidden = true
  }

  /// Keeps the callout over its marker; call on every camera move.
  func positionCallout() {
    guard !callout.isHidden, let mapView, let id = selectedId, let marker = markerIds[id] else { return }
    let point = mapView.convert(CLLocationCoordinate2D(latitude: marker.latitude, longitude: marker.longitude), toPointTo: callout.superview)
    let height: CGFloat
    if let drawn = image(for: marker, selected: marker.style == .marker) {
      height = drawn.image.size.height * drawn.anchor.y
    } else {
      height = 0
    }
    let size = callout.systemLayoutSizeFitting(CGSize(width: 280, height: 0), withHorizontalFittingPriority: .fittingSizeLevel, verticalFittingPriority: .fittingSizeLevel)
    let width = min(280, size.width)
    callout.frame = CGRect(x: point.x - width / 2, y: point.y - height - size.height - 4, width: width, height: size.height)
  }

  // MARK: Dragging

  /// Long press on a draggable marker: drag it until the finger lifts.
  func handleLongPress(_ gesture: UILongPressGestureRecognizer) -> Bool {
    guard let mapView else { return false }
    let point = gesture.location(in: mapView)
    switch gesture.state {
    case .began:
      guard let marker = marker(at: point), marker.draggable else { return false }
      hideCallout()
      dragging = marker.id
      onMarkerDragStart?(marker.id, CLLocationCoordinate2D(latitude: marker.latitude, longitude: marker.longitude))
      return true
    case .changed:
      guard let id = dragging else { return false }
      let coordinate = mapView.convert(CGPoint(x: point.x, y: point.y - 30), toCoordinateFrom: mapView)
      move(id, to: coordinate)
      onMarkerDrag?(id, coordinate)
      return true
    case .ended, .cancelled, .failed:
      guard let id = dragging else { return false }
      dragging = nil
      if let m = markerIds[id] { onMarkerDragEnd?(id, CLLocationCoordinate2D(latitude: m.latitude, longitude: m.longitude)) }
      return true
    default:
      return dragging != nil
    }
  }

  var isDragging: Bool { dragging != nil }

  private func move(_ id: String, to coordinate: CLLocationCoordinate2D) {
    guard let index = markers.firstIndex(where: { $0.id == id }) else { return }
    markers[index].latitude = coordinate.latitude
    markers[index].longitude = coordinate.longitude
    markerIds[id] = markers[index]
    apply()
  }

  // MARK: Shapes

  private func color(_ value: String, _ fallback: UIColor) -> UIColor {
    MapLibreMarkerArt.color(value, fallback)
  }

  private func dashes(_ pattern: String, width: Double) -> [Double]? {
    let parts = pattern.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard parts.count >= 2 else { return nil }
    // MapLibre dashes are in line widths; munim-maps' in points.
    return parts.map { $0 / max(0.5, width) }
  }

  private func cap(_ cap: MunimLineCap) -> String { cap.rawValue }
  private func join(_ join: MunimLineJoin) -> String { join.rawValue }

  private func constant(_ value: Any) -> NSExpression {
    MapLibreStyleSpec.expression(value)
  }

  func applyShapes() {
    guard let style else { return }
    for id in shapeLayers { if let layer = style.layer(withIdentifier: id) { style.removeLayer(layer) } }
    for id in shapeSources { if let source = style.source(withIdentifier: id) { style.removeSource(source) } }
    shapeLayers.removeAll()
    shapeSources.removeAll()
    struct Shape { var z: Double; var level: MunimOverlayLevel; var add: (MLNStyle, MLNStyleLayer) -> Void }
    var shapes: [Shape] = []
    for p in polygons { shapes.append(Shape(z: p.zIndex, level: p.level) { s, below in self.addPolygon(s, p, below: below) }) }
    for c in circles { shapes.append(Shape(z: c.zIndex, level: c.level) { s, below in self.addCircle(s, c, below: below) }) }
    for l in polylines { shapes.append(Shape(z: l.zIndex, level: l.level) { s, below in self.addPolyline(s, l, below: below) }) }
    for shape in shapes.sorted(by: { $0.z < $1.z }) {
      let belowId = shape.level == .aboveRoads ? (firstLabelLayer ?? Self.slotShapes) : Self.slotShapes
      guard let below = style.layer(withIdentifier: belowId) ?? style.layer(withIdentifier: Self.slotShapes) else { continue }
      shape.add(style, below)
    }
  }

  private func addSource(_ style: MLNStyle, id: String, shape: MLNShape, lineMetrics: Bool = false) -> MLNShapeSource {
    let source = MLNShapeSource(identifier: id, shape: shape, options: lineMetrics ? [.lineDistanceMetrics: true] : nil)
    style.addSource(source)
    shapeSources.append(id)
    return source
  }

  private func insert(_ style: MLNStyle, _ layer: MLNStyleLayer, below: MLNStyleLayer) {
    style.insertLayer(layer, below: below)
    shapeLayers.append(layer.identifier)
  }

  private func addPolyline(_ style: MLNStyle, _ line: MunimPolyline, below: MLNStyleLayer) {
    var points = line.coordinates
    if line.geodesic { points = MapLibreGeo.densify(points) }
    points = MapLibreGeo.slice(points, start: line.strokeStart, end: line.strokeEnd)
    guard points.count >= 2 else { return }
    let id = "munim-shape|polyline|\(line.id)"
    let colors = line.strokeColors.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    let feature = MLNPolylineFeature(coordinates: points, count: UInt(points.count))
    feature.attributes = ["id": id]
    let source = addSource(style, id: id, shape: feature, lineMetrics: colors.count > 1)
    let layer = MLNLineStyleLayer(identifier: id, source: source)
    layer.lineColor = NSExpression(forConstantValue: color(line.strokeColor, .systemBlue))
    layer.lineWidth = NSExpression(forConstantValue: line.strokeWidth)
    layer.lineCap = constant(cap(line.lineCap))
    layer.lineJoin = constant(join(line.lineJoin))
    if let d = dashes(line.dashPattern, width: line.strokeWidth) { layer.lineDashPattern = NSExpression(forConstantValue: d) }
    if colors.count > 1 {
      let locations = line.strokeColorLocations.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
      var stops: [Any] = []
      var last = -1.0
      for (i, c) in colors.enumerated() {
        let at = min(1, max(0, i < locations.count ? locations[i] : Double(i) / Double(colors.count - 1)))
        guard at > last else { continue }
        last = at
        stops.append(at)
        stops.append(MapLibreMarkerArt.css(c, .systemBlue))
      }
      layer.lineGradient = NSExpression(mglJSONObject: ["interpolate", ["linear"], ["line-progress"]] + stops)
    }
    insert(style, layer, below: below)
  }

  private func addFill(_ style: MLNStyle, id: String, rings: [[CLLocationCoordinate2D]], fill: String, stroke: String,
                       width: Double, dash: String, join: MunimLineJoin, below: MLNStyleLayer) {
    guard let outer = rings.first, outer.count >= 3 else { return }
    let holes = rings.dropFirst().filter { $0.count >= 3 }.map { MLNPolygon(coordinates: $0, count: UInt($0.count)) }
    let feature = MLNPolygonFeature(coordinates: outer, count: UInt(outer.count), interiorPolygons: holes)
    feature.attributes = ["id": id]
    let source = addSource(style, id: id, shape: feature)
    let fillLayer = MLNFillStyleLayer(identifier: "\(id)|fill", source: source)
    fillLayer.fillColor = NSExpression(forConstantValue: color(fill, UIColor.systemBlue.withAlphaComponent(0.2)))
    insert(style, fillLayer, below: below)
    if width > 0 {
      let line = MLNLineStyleLayer(identifier: "\(id)|line", source: source)
      line.lineColor = NSExpression(forConstantValue: color(stroke, .systemBlue))
      line.lineWidth = NSExpression(forConstantValue: width)
      line.lineJoin = constant(self.join(join))
      if let d = dashes(dash, width: width) { line.lineDashPattern = NSExpression(forConstantValue: d) }
      insert(style, line, below: below)
    }
  }

  private func addPolygon(_ style: MLNStyle, _ p: MunimPolygon, below: MLNStyleLayer) {
    addFill(style, id: "munim-shape|polygon|\(p.id)", rings: [p.coordinates] + p.holes, fill: p.fillColor,
            stroke: p.strokeColor, width: p.strokeWidth, dash: p.dashPattern, join: p.lineJoin, below: below)
  }

  private func addCircle(_ style: MLNStyle, _ c: MunimCircle, below: MLNStyleLayer) {
    addFill(style, id: "munim-shape|circle|\(c.id)", rings: [MapLibreGeo.circle(latitude: c.latitude, longitude: c.longitude, radius: c.radius)],
            fill: c.fillColor, stroke: c.strokeColor, width: c.strokeWidth, dash: c.dashPattern, join: .round, below: below)
  }

  private var tappable: Set<String> {
    Set(polylines.filter(\.tappable).map { "polyline|\($0.id)" }
      + polygons.filter(\.tappable).map { "polygon|\($0.id)" }
      + circles.filter(\.tappable).map { "circle|\($0.id)" })
  }

  /// The topmost tappable overlay at a point: id and kind.
  func overlay(at point: CGPoint) -> (id: String, kind: String)? {
    guard let mapView, !shapeLayers.isEmpty else { return nil }
    let rect = CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16)
    let wanted = tappable
    for feature in mapView.visibleFeatures(in: rect, styleLayerIdentifiers: Set(shapeLayers)) {
      guard let id = feature.attribute(forKey: "id") as? String else { continue }
      let parts = id.split(separator: "|", maxSplits: 2).map(String.init)
      guard parts.count == 3 else { continue }
      if wanted.contains("\(parts[1])|\(parts[2])") { return (parts[2], parts[1]) }
    }
    return nil
  }

  // MARK: Tile overlays

  private func applyTileOverlays() {
    guard let style else { return }
    for id in tileLayers {
      if let layer = style.layer(withIdentifier: id) { style.removeLayer(layer) }
      if let source = style.source(withIdentifier: id) { style.removeSource(source) }
    }
    tileLayers.removeAll()
    for id in hiddenForTiles { style.layer(withIdentifier: id)?.isVisible = true }
    hiddenForTiles.removeAll()
    for overlay in tileOverlays.sorted(by: { $0.zIndex < $1.zIndex }) {
      let id = "munim-tiles|\(overlay.id)"
      var options: [MLNTileSourceOption: Any] = [.tileSize: 256]
      if overlay.minimumZoom > 0 { options[.minimumZoomLevel] = overlay.minimumZoom }
      if overlay.maximumZoom > 0 { options[.maximumZoomLevel] = overlay.maximumZoom }
      let source = MLNRasterTileSource(identifier: id, tileURLTemplates: [overlay.urlTemplate], options: options)
      style.addSource(source)
      let layer = MLNRasterStyleLayer(identifier: id, source: source)
      layer.rasterOpacity = NSExpression(forConstantValue: overlay.opacity)
      let belowId = overlay.level == .aboveLabels ? Self.slotShapes : (firstLabelLayer ?? Self.slotShapes)
      if let below = style.layer(withIdentifier: belowId) { style.insertLayer(layer, below: below) } else { style.addLayer(layer) }
      tileLayers.append(id)
    }
    if tileOverlays.contains(where: \.replacesMap) {
      for layer in style.layers where !layer.identifier.hasPrefix("munim-") && layer.isVisible {
        layer.isVisible = false
        hiddenForTiles.append(layer.identifier)
      }
    }
  }

  func coordinates(of ids: Set<String>) -> [CLLocationCoordinate2D] {
    markers.filter { ids.isEmpty || ids.contains($0.id) }.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
  }
}

/// Great circles, circles on the sphere and partial lines.
enum MapLibreGeo {
  static let radius = 6_371_008.8

  static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
    let dLat = (b.latitude - a.latitude) * .pi / 180
    let dLon = (b.longitude - a.longitude) * .pi / 180
    let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
    return 2 * radius * asin(min(1, sqrt(h)))
  }

  /// Points every ~50 km along great circles between the points.
  static func densify(_ points: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
    guard points.count >= 2 else { return points }
    var out: [CLLocationCoordinate2D] = []
    for i in 0..<(points.count - 1) {
      let a = points[i], b = points[i + 1]
      let d = distance(a, b)
      let steps = max(1, min(256, Int(d / 50_000)))
      let lat1 = a.latitude * .pi / 180, lon1 = a.longitude * .pi / 180
      let lat2 = b.latitude * .pi / 180, lon2 = b.longitude * .pi / 180
      let delta = d / radius
      for s in 0..<steps {
        if delta < 1e-9 { out.append(a); continue }
        let f = Double(s) / Double(steps)
        let A = sin((1 - f) * delta) / sin(delta)
        let B = sin(f * delta) / sin(delta)
        let x = A * cos(lat1) * cos(lon1) + B * cos(lat2) * cos(lon2)
        let y = A * cos(lat1) * sin(lon1) + B * cos(lat2) * sin(lon2)
        let z = A * sin(lat1) + B * sin(lat2)
        var lon = atan2(y, x) * 180 / .pi
        if let prev = out.last {
          while lon - prev.longitude > 180 { lon -= 360 }
          while lon - prev.longitude < -180 { lon += 360 }
        }
        out.append(CLLocationCoordinate2D(latitude: atan2(z, sqrt(x * x + y * y)) * 180 / .pi, longitude: lon))
      }
    }
    out.append(points[points.count - 1])
    return out
  }

  /// A ring of points `radius` metres from the centre.
  static func circle(latitude: Double, longitude: Double, radius r: Double, segments: Int = 72) -> [CLLocationCoordinate2D] {
    let lat = latitude * .pi / 180, lon = longitude * .pi / 180, d = r / radius
    return (0...segments).map { i in
      let bearing = 2 * Double.pi * Double(i) / Double(segments)
      let lat2 = asin(sin(lat) * cos(d) + cos(lat) * sin(d) * cos(bearing))
      let lon2 = lon + atan2(sin(bearing) * sin(d) * cos(lat), cos(d) - sin(lat) * sin(lat2))
      return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }
  }

  /// The part of a line from `start` to `end` (0…1 of its length).
  static func slice(_ points: [CLLocationCoordinate2D], start: Double, end: Double) -> [CLLocationCoordinate2D] {
    guard points.count >= 2, start > 0 || end < 1 else { return points }
    let s = min(1, max(0, start)), e = min(1, max(0, end))
    guard e > s else { return [] }
    let lengths = (0..<(points.count - 1)).map { distance(points[$0], points[$0 + 1]) }
    let total = lengths.reduce(0, +)
    guard total > 0 else { return points }
    var out: [CLLocationCoordinate2D] = []
    var walked = 0.0
    for i in lengths.indices {
      let a = points[i], b = points[i + 1]
      let from = walked / total, to = (walked + lengths[i]) / total
      walked += lengths[i]
      if to < s || from > e { continue }
      func at(_ f: Double) -> CLLocationCoordinate2D {
        let t = to - from < 1e-12 ? 0 : (f - from) / (to - from)
        return CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t, longitude: a.longitude + (b.longitude - a.longitude) * t)
      }
      if out.isEmpty { out.append(from < s ? at(s) : a) }
      out.append(to > e ? at(e) : b)
      if to > e { break }
    }
    return out
  }
}

/// Pin and balloon images (MapKit's look) and colour parsing.
enum MapLibreMarkerArt {
  static func color(_ value: String, _ fallback: UIColor) -> UIColor {
    var s = value.trimmingCharacters(in: .whitespaces)
    guard !s.isEmpty else { return fallback }
    if s.hasPrefix("rgb") {
      let parts = s.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" }.split(separator: ",")
        .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
      guard parts.count >= 3 else { return fallback }
      return UIColor(red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, alpha: parts.count > 3 ? parts[3] : 1)
    }
    if s.hasPrefix("#") { s.removeFirst() }
    if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
    guard let n = UInt64(s, radix: 16) else {
      switch value.lowercased() {
      case "red": return .systemRed
      case "blue": return .systemBlue
      case "green": return .systemGreen
      case "black": return .black
      case "white": return .white
      case "orange": return .systemOrange
      case "yellow": return .systemYellow
      case "purple": return .systemPurple
      default: return fallback
      }
    }
    if s.count == 8 {
      return UIColor(red: CGFloat((n >> 24) & 0xFF) / 255, green: CGFloat((n >> 16) & 0xFF) / 255,
                     blue: CGFloat((n >> 8) & 0xFF) / 255, alpha: CGFloat(n & 0xFF) / 255)
    }
    return UIColor(red: CGFloat((n >> 16) & 0xFF) / 255, green: CGFloat((n >> 8) & 0xFF) / 255, blue: CGFloat(n & 0xFF) / 255, alpha: 1)
  }

  static func css(_ value: String, _ fallback: UIColor) -> String {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color(value, fallback).getRed(&r, green: &g, blue: &b, alpha: &a)
    return "rgba(\(Int(r * 255)),\(Int(g * 255)),\(Int(b * 255)),\(a))"
  }

  private static func renderer(_ size: CGSize, _ scale: CGFloat) -> UIGraphicsImageRenderer {
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = false
    return UIGraphicsImageRenderer(size: size, format: format)
  }

  static func pin(color: UIColor, scale: CGFloat) -> UIImage {
    renderer(CGSize(width: 28, height: 40), scale).image { ctx in
      let cg = ctx.cgContext
      UIColor.systemGray.setFill()
      cg.fill(CGRect(x: 13, y: 18, width: 2, height: 21))
      cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 2.5, color: UIColor.black.withAlphaComponent(0.35).cgColor)
      color.setFill()
      cg.fillEllipse(in: CGRect(x: 4, y: 2, width: 20, height: 20))
      cg.setShadow(offset: .zero, blur: 0)
      UIColor.white.withAlphaComponent(0.4).setFill()
      cg.fillEllipse(in: CGRect(x: 8, y: 6, width: 6, height: 6))
    }
  }

  /// A balloon with its title under it; the anchor stays on the balloon's point.
  static func titled(_ balloon: UIImage, title: String, scale: CGFloat) -> (image: UIImage, anchorY: CGFloat) {
    let font = UIFont.systemFont(ofSize: 11, weight: .semibold)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(white: 0.11, alpha: 1)]
    let text = String(title.prefix(32)) as NSString
    let textSize = text.size(withAttributes: attrs)
    let width = max(balloon.size.width, textSize.width + 8)
    let height = balloon.size.height + textSize.height + 2
    let image = renderer(CGSize(width: width, height: height), scale).image { ctx in
      balloon.draw(at: CGPoint(x: (width - balloon.size.width) / 2, y: 0))
      let origin = CGPoint(x: (width - textSize.width) / 2, y: balloon.size.height + 1)
      let halo: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white, .strokeColor: UIColor.white, .strokeWidth: 6]
      text.draw(at: origin, withAttributes: halo)
      text.draw(at: origin, withAttributes: attrs)
      _ = ctx
    }
    return (image, balloon.size.height / height)
  }

  /// MapKit's marker balloon: a circle with a point under it, glyph inside.
  static func balloon(fill: UIColor, glyph: String, symbol: String, glyphColor: UIColor, selected: Bool, scale: CGFloat) -> UIImage {
    let k: CGFloat = selected ? 1.5 : 1
    let size = CGSize(width: 34 * k, height: 44 * k)
    return renderer(size, scale).image { ctx in
      let cg = ctx.cgContext
      let r = 14 * k
      let c = CGPoint(x: size.width / 2, y: r + 2 * k)
      let path = UIBezierPath(arcCenter: c, radius: r, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
      path.move(to: CGPoint(x: c.x - r * 0.55, y: c.y + r * 0.8))
      path.addLine(to: CGPoint(x: c.x, y: size.height - 3 * k))
      path.addLine(to: CGPoint(x: c.x + r * 0.55, y: c.y + r * 0.8))
      path.close()
      cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 2.5, color: UIColor.black.withAlphaComponent(0.35).cgColor)
      fill.setFill()
      path.fill()
      cg.setShadow(offset: .zero, blur: 0)
      if !symbol.isEmpty, let image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 13 * k, weight: .semibold))?
        .withTintColor(glyphColor, renderingMode: .alwaysOriginal) {
        image.draw(at: CGPoint(x: c.x - image.size.width / 2, y: c.y - image.size.height / 2))
      } else if !glyph.isEmpty {
        let text = String(glyph.prefix(4)) as NSString
        let font = UIFont.systemFont(ofSize: (glyph.count > 2 ? 10 : 14) * k, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: glyphColor]
        let s = text.size(withAttributes: attrs)
        text.draw(at: CGPoint(x: c.x - s.width / 2, y: c.y - s.height / 2), withAttributes: attrs)
      } else {
        glyphColor.setFill()
        cg.fillEllipse(in: CGRect(x: c.x - 4.5 * k, y: c.y - 4.5 * k, width: 9 * k, height: 9 * k))
      }
    }
  }
}

/// munim-maps' callout on MapLibre: title, subtitle or detail, accessories.
final class MapLibreCalloutView: UIView {
  private let title = UILabel()
  private let subtitle = UILabel()
  private let left = UIButton(type: .system)
  private let right = UIButton(type: .system)
  private let stack = UIStackView()
  private var onPress: (() -> Void)?
  private var onAccessory: ((String) -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .systemBackground
    layer.cornerRadius = 12
    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOpacity = 0.2
    layer.shadowRadius = 6
    layer.shadowOffset = CGSize(width: 0, height: 2)
    isHidden = true
    title.font = .systemFont(ofSize: 15, weight: .semibold)
    subtitle.font = .systemFont(ofSize: 13)
    subtitle.textColor = .secondaryLabel
    subtitle.numberOfLines = 6
    let texts = UIStackView(arrangedSubviews: [title, subtitle])
    texts.axis = .vertical
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 8
    stack.addArrangedSubview(left)
    stack.addArrangedSubview(texts)
    stack.addArrangedSubview(right)
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
      widthAnchor.constraint(lessThanOrEqualToConstant: 280),
    ])
    addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    left.addTarget(self, action: #selector(leftTapped), for: .touchUpInside)
    right.addTarget(self, action: #selector(rightTapped), for: .touchUpInside)
  }

  required init?(coder: NSCoder) { fatalError() }

  @objc private func tapped() { onPress?() }
  @objc private func leftTapped() { onAccessory?("left") }
  @objc private func rightTapped() { onAccessory?("right") }

  func bind(_ marker: MunimMarker, onPress: @escaping () -> Void, onAccessory: @escaping (String) -> Void) {
    self.onPress = onPress
    self.onAccessory = onAccessory
    title.text = marker.title
    title.isHidden = marker.title.isEmpty
    let sub = marker.calloutDetail.isEmpty ? marker.subtitle : marker.calloutDetail
    subtitle.text = sub
    subtitle.isHidden = sub.isEmpty
    bind(left, marker.leftCalloutAccessory)
    bind(right, marker.rightCalloutAccessory)
  }

  private func bind(_ button: UIButton, _ accessory: MunimCalloutAccessory) {
    button.setTitle(nil, for: .normal)
    button.setImage(nil, for: .normal)
    switch accessory.kind {
    case .none:
      button.isHidden = true
    case .detail:
      button.setImage(UIImage(systemName: "chevron.right"), for: .normal)
    case .info:
      button.setImage(UIImage(systemName: "info.circle"), for: .normal)
    case .button, .image:
      if !accessory.symbol.isEmpty {
        button.setImage(UIImage(systemName: accessory.symbol), for: .normal)
      } else {
        button.setTitle(accessory.text.isEmpty ? "›" : accessory.text, for: .normal)
      }
    }
    button.isHidden = accessory.kind == .none
    button.isUserInteractionEnabled = accessory.kind != .image
    if !accessory.color.isEmpty { button.tintColor = MapLibreMarkerArt.color(accessory.color, .systemBlue) }
  }
}
#endif
