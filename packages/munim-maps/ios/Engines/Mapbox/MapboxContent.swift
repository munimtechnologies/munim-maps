#if canImport(MapboxMaps)
@_spi(Experimental) import MapboxMaps
import MapKit
import UIKit

/// munim-maps' 2D content on a Mapbox map.
///
/// - Markers are Mapbox point annotations (one `PointAnnotationManager` per
///   `clusteringId` and overlap rule, so clusters and collisions work like
///   Mapbox's own), with munim-maps' marker pictures as their icons.
/// - `MarkerView`s are Mapbox view annotations (a `UIImageView` of the React
///   Native views), draggable with Mapbox's view annotation dragging.
/// - Polylines, polygons, circles and tile overlays are GeoJSON / raster
///   sources with their own layers, so every line feature (dashes,
///   gradients, caps, joins) maps onto the style spec. They sit in Mapbox
///   Standard's `middle` slot (`aboveRoads`) or `top` slot (`aboveLabels`).
final class MapboxContentState {
  var markers: [MunimMarker] = []
  var managers: [String: PointAnnotationManager] = [:]
  var photos: [String: UIImage] = [:]
  var loadingPhotos = Set<String>()
  var selectedMarker: String?
  var callout: ViewAnnotation?
  var viewMarkers: [String: MapboxViewMarker] = [:]
  var polylines: [MunimPolyline] = []
  var polygons: [MunimPolygon] = []
  var circles: [MunimCircle] = []
  var tileOverlays: [MunimTileOverlay] = []
  var clusterStyles: [MunimClusterStyle] = []
  /// Shape layers in drawing order: (shape id, kind, layer ids, source id).
  var shapes: [(id: String, kind: String, layers: [String], source: String)] = []
  var shapeSignature = ""
  var tileIds: [String] = []
  var trackingButton: UIButton?
  var interactions: [AnyCancelable] = []
  var lastInteractionFeatures: [String: FeaturesetFeature] = [:]
}

final class MapboxViewMarker {
  var marker: MunimMarker
  let annotation: ViewAnnotation
  let imageView: UIImageView
  init(marker: MunimMarker, annotation: ViewAnnotation, imageView: UIImageView) {
    self.marker = marker
    self.annotation = annotation
    self.imageView = imageView
  }
}

extension MapboxMapEngine {
  // MARK: Markers

  var markers: [MunimMarker] {
    get { content.markers }
    set {
      content.markers = newValue
      updateMarkers()
    }
  }

  var clusterStyles: [MunimClusterStyle] {
    get { content.clusterStyles }
    set {
      content.clusterStyles = newValue
      // Cluster looks are set when a manager is made: remake them.
      for id in content.managers.keys { mapView.annotations.removeAnnotationManager(withId: id) }
      content.managers = [:]
      updateMarkers()
    }
  }

  func reapplyContent() {
    rebuildShapes(force: true)
    updateTileOverlays(force: true)
  }

  private static func allowsOverlap(_ m: MunimMarker) -> Bool {
    m.collisionMode == .none || m.displayPriority >= 1000
  }

  func updateMarkers() {
    let visible = content.markers.filter(\.visible)
    var groups: [String: [MunimMarker]] = [:]
    for marker in visible {
      groups["\(marker.clusteringId)|\(Self.allowsOverlap(marker))", default: []].append(marker)
    }
    for (key, manager) in content.managers where groups[key] == nil {
      manager.annotations = []
      mapView.annotations.removeAnnotationManager(withId: manager.id)
      content.managers[key] = nil
    }
    for (key, members) in groups {
      let manager = content.managers[key] ?? makeManager(key: key, sample: members[0])
      content.managers[key] = manager
      manager.annotations = members.map(annotation(for:))
    }
  }

  private func makeManager(key: String, sample: MunimMarker) -> PointAnnotationManager {
    let clusteringId = sample.clusteringId
    var clusterOptions: ClusterOptions?
    if !clusteringId.isEmpty {
      let look = content.clusterStyles.first { $0.clusteringId == clusteringId }
      let color = UIColor(mapModelHex: look?.color ?? "") ?? .systemBlue
      let textColor = UIColor(mapModelHex: look?.glyphColor ?? "") ?? .white
      var text: Value<String> = .expression(Exp(.toString) { Exp(.get) { "point_count" } })
      if let glyph = look?.glyph, !glyph.isEmpty {
        let parts = glyph.components(separatedBy: "{count}")
        let json: [Any] = ["concat"] + parts.enumerated().flatMap { index, part -> [Any] in
          index == 0 ? [part] : [["to-string", ["get", "point_count"]], part]
        }
        if let exp = try? MapboxJSON.decode(Exp.self, from: json) { text = .expression(exp) }
      }
      clusterOptions = ClusterOptions(
        circleRadius: .constant(18), circleColor: .constant(StyleColor(color)),
        textColor: .constant(StyleColor(textColor)), textSize: .constant(13), textField: text)
    }
    let id = "munim-markers-" + String(UInt(bitPattern: key.hashValue), radix: 36)
    let manager = mapView.annotations.makePointAnnotationManager(
      id: id, layerPosition: nil, clusterOptions: clusterOptions,
      onClusterTap: { [weak self] context in self?.clusterTapped(clusteringId: clusteringId, managerId: id, context: context) })
    let overlap = Self.allowsOverlap(sample)
    manager.iconAllowOverlap = overlap
    manager.textAllowOverlap = overlap
    manager.iconIgnorePlacement = overlap
    manager.textOptional = true
    if hasSlots { manager.slot = "top" }
    return manager
  }

  private func clusterTapped(clusteringId: String, managerId: String, context: AnnotationClusterGestureContext) {
    guard let manager = content.managers.values.first(where: { $0.id == managerId }) else { return }
    let sourceId = manager.sourceId
    _ = mapboxMap.queryRenderedFeatures(with: context.point, options: RenderedQueryOptions(layerIds: nil, filter: nil)) {
      [weak self] result in
      guard let self, case .success(let features) = result,
            let cluster = features.first(where: {
              $0.queriedFeature.source == sourceId && $0.queriedFeature.feature.properties?["cluster"] != nil
            })?.queriedFeature.feature
      else { return }
      self.mapboxMap.getGeoJsonClusterLeaves(forSourceId: sourceId, feature: cluster, limit: 10_000, offset: 0) { leaves in
        let ids: [String]
        if case .success(let extension_) = leaves {
          ids = (extension_.features ?? []).compactMap { feature in
            switch feature.identifier {
            case .string(let s): return s
            case .number(let n): return String(n)
            default: return nil
            }
          }
        } else {
          ids = []
        }
        DispatchQueue.main.async { self.onClusterPress?(clusteringId, ids, context.coordinate) }
      }
    }
  }

  private func photo(for marker: MunimMarker) -> UIImage? {
    guard marker.style == .image || marker.style == .avatar, !marker.imageUri.isEmpty else { return nil }
    if let photo = content.photos[marker.imageUri] { return photo }
    let uri = marker.imageUri
    if !content.loadingPhotos.contains(uri) {
      content.loadingPhotos.insert(uri)
      MapModelNodes.loadImage(uri: uri) { [weak self] result in
        DispatchQueue.main.async {
          guard let self else { return }
          self.content.loadingPhotos.remove(uri)
          if case .success(let image) = result {
            self.content.photos[uri] = image
            self.updateMarkers()
          }
        }
      }
    }
    return nil
  }

  func markerImage(_ marker: MunimMarker) -> UIImage {
    let scale = window?.screen.scale ?? UIScreen.main.scale
    switch marker.style {
    case .pin: return MapboxMarkerImages.pin(marker, scale: scale)
    case .marker: return MapboxMarkerImages.balloon(marker, selected: content.selectedMarker == marker.id, scale: scale)
    default:
      return MarkerImages.image(for: marker, photo: photo(for: marker), scale: scale)
        ?? MapboxMarkerImages.placeholder(marker, scale: scale)
    }
  }

  private func annotation(for marker: MunimMarker) -> PointAnnotation {
    let id = marker.id
    var a = PointAnnotation(
      id: id, coordinate: CLLocationCoordinate2D(latitude: marker.latitude, longitude: marker.longitude),
      isSelected: content.selectedMarker == id, isDraggable: marker.draggable)
    let image = markerImage(marker)
    let name = "munim-marker-" + MapboxMarkerImages.key(marker, selected: content.selectedMarker == id,
                                                         hasPhoto: content.photos[marker.imageUri] != nil)
    a.image = .init(image: image, name: name)
    a.iconAnchor = .topLeft
    a.iconOffset = [-marker.anchorX * Double(image.size.width), -marker.anchorY * Double(image.size.height)]
    a.symbolSortKey = marker.zIndex
    a.iconOpacity = marker.opacity
    let showsTitle = (marker.style == .pin || marker.style == .marker) && !marker.title.isEmpty
      && marker.titleVisibility != .hidden
    if showsTitle {
      let showsSubtitle = marker.subtitleVisibility == .visible && !marker.subtitle.isEmpty
      a.textField = showsSubtitle ? marker.title + "\n" + marker.subtitle : marker.title
      a.textAnchor = .top
      a.textSize = 12
      a.textOffset = [0, (1 - marker.anchorY) * Double(image.size.height) / 12 + 0.2]
      a.textColor = StyleColor(isDark ? .white : UIColor(white: 0.1, alpha: 1))
      a.textHaloColor = StyleColor(isDark ? .black : .white)
      a.textHaloWidth = 1.2
      a.textOpacity = marker.opacity
    }
    a.tapHandler = { [weak self] _ in
      self?.markerTapped(id)
      return true
    }
    if marker.draggable {
      a.dragBeginHandler = { [weak self] annotation, _ in
        self?.onMarkerDragStart?(id, annotation.point.coordinates)
        return true
      }
      a.dragChangeHandler = { [weak self] annotation, _ in
        self?.onMarkerDrag?(id, annotation.point.coordinates)
      }
      a.dragEndHandler = { [weak self] annotation, _ in
        guard let self else { return }
        let c = annotation.point.coordinates
        if let i = self.content.markers.firstIndex(where: { $0.id == id }) {
          self.content.markers[i].latitude = c.latitude
          self.content.markers[i].longitude = c.longitude
        }
        self.onMarkerDragEnd?(id, c)
      }
    }
    return a
  }

  // MARK: Selection and callouts

  func markerTapped(_ id: String) {
    if let current = content.selectedMarker, current != id { deselectMarker(current) }
    onMarkerPress?(id)
    select(id)
  }

  func selectMarker(_ id: String) {
    if let current = content.selectedMarker, current != id { deselectMarker(current) }
    select(id)
  }

  private func select(_ id: String) {
    content.selectedMarker = id
    content.callout?.remove()
    content.callout = nil
    if let marker = content.markers.first(where: { $0.id == id }) {
      if marker.style == .marker { updateMarkers() } // the selected balloon is bigger
      if marker.calloutEnabled, !marker.title.isEmpty {
        let height = Double(markerImage(marker).size.height)
        showCallout(for: marker, above: marker.anchorY * height)
      }
    } else if let viewMarker = content.viewMarkers[id] {
      let marker = viewMarker.marker
      if marker.calloutEnabled, !marker.title.isEmpty {
        showCallout(for: marker, above: marker.anchorY * Double(viewMarker.imageView.bounds.height))
      }
    }
  }

  func deselectMarker(_ id: String) {
    guard content.selectedMarker == id else { return }
    content.selectedMarker = nil
    content.callout?.remove()
    content.callout = nil
    if content.markers.first(where: { $0.id == id })?.style == .marker { updateMarkers() }
    onMarkerDeselect?(id)
  }

  private func showCallout(for marker: MunimMarker, above height: Double) {
    let view = MapboxCalloutView(marker: marker, dark: isDark)
    let id = marker.id
    view.onPress = { [weak self] in self?.onCalloutPress?(id) }
    view.onAccessory = { [weak self] side in self?.onCalloutAccessoryPress?(id, side) }
    let callout = ViewAnnotation(
      coordinate: CLLocationCoordinate2D(latitude: marker.latitude, longitude: marker.longitude), view: view)
    callout.variableAnchors = [ViewAnnotationAnchorConfig(anchor: .bottom, offsetY: height + 6)]
    callout.allowOverlap = true
    callout.priority = 10_000
    mapView.viewAnnotations.add(callout)
    content.callout = callout
  }

  // MARK: MarkerView: view annotations

  func setViewMarker(_ marker: MunimMarker, image: UIImage?) {
    if let existing = content.viewMarkers[marker.id] {
      existing.marker = marker
      if let image { existing.imageView.image = image }
      configure(existing)
      return
    }
    let imageView = UIImageView(image: image)
    imageView.isUserInteractionEnabled = true
    let annotation = ViewAnnotation(
      coordinate: CLLocationCoordinate2D(latitude: marker.latitude, longitude: marker.longitude), view: imageView)
    let entry = MapboxViewMarker(marker: marker, annotation: annotation, imageView: imageView)
    let id = marker.id
    imageView.addGestureRecognizer(MapboxTapRecognizer { [weak self] in self?.markerTapped(id) })
    annotation.onDraggingChanged = { [weak self, weak annotation] dragging in
      guard let self, let c = annotation?.anchorCoordinate ?? self.content.viewMarkers[id].map({
        CLLocationCoordinate2D(latitude: $0.marker.latitude, longitude: $0.marker.longitude)
      }) else { return }
      if dragging {
        self.onMarkerDragStart?(id, c)
      } else {
        self.content.viewMarkers[id]?.marker.latitude = c.latitude
        self.content.viewMarkers[id]?.marker.longitude = c.longitude
        self.onMarkerDragEnd?(id, c)
      }
    }
    annotation.onDragCoordinateChanged = { [weak self] c in self?.onMarkerDrag?(id, c) }
    content.viewMarkers[id] = entry
    configure(entry)
    mapView.viewAnnotations.add(annotation)
  }

  private func configure(_ entry: MapboxViewMarker) {
    let m = entry.marker
    let size = entry.imageView.image?.size ?? .zero
    entry.imageView.frame = CGRect(origin: entry.imageView.frame.origin, size: size)
    entry.imageView.alpha = CGFloat(m.opacity)
    let a = entry.annotation
    if !a.isDragging {
      a.annotatedFeature = .geometry(Point(CLLocationCoordinate2D(latitude: m.latitude, longitude: m.longitude)))
    }
    a.variableAnchors = [ViewAnnotationAnchorConfig(
      anchor: .center,
      offsetX: (0.5 - m.anchorX) * size.width,
      offsetY: (m.anchorY - 0.5) * size.height)]
    a.allowOverlap = Self.allowsOverlap(m)
    a.allowOverlapWithPuck = true
    a.priority = Int(m.zIndex)
    a.visible = m.visible
    a.isDraggable = m.draggable
    a.setNeedsUpdateSize()
  }

  func setViewMarkerImage(_ image: UIImage?, id: String) {
    guard let entry = content.viewMarkers[id], let image else { return }
    let resized = entry.imageView.image?.size != image.size
    entry.imageView.image = image
    if resized { configure(entry) }
  }

  func removeViewMarker(_ id: String) {
    content.viewMarkers[id]?.annotation.remove()
    content.viewMarkers[id] = nil
    if content.selectedMarker == id { deselectMarker(id) }
  }

  // MARK: Shapes

  var polylines: [MunimPolyline] {
    get { content.polylines }
    set { content.polylines = newValue; rebuildShapes(force: false) }
  }

  var polygons: [MunimPolygon] {
    get { content.polygons }
    set { content.polygons = newValue; rebuildShapes(force: false) }
  }

  var circles: [MunimCircle] {
    get { content.circles }
    set { content.circles = newValue; rebuildShapes(force: false) }
  }

  private struct ShapeSpec {
    var id: String
    var kind: String
    var zIndex: Double
    var level: MunimOverlayLevel
    var geometry: [String: Any]
    /// Layers: (suffix, style layer without id/source).
    var layers: [(String, [String: Any])]
    var lineMetrics = false
  }

  private static func rgba(_ hex: String, _ fallback: UIColor) -> String {
    (UIColor(mapModelHex: hex) ?? fallback).styleString
  }

  private static func dashArray(_ pattern: String, width: Double) -> [Double]? {
    let values = pattern.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
    guard values.count >= 2, values.contains(where: { $0 > 0 }) else { return nil }
    // Mapbox dashes are in line widths; munim-maps' in points.
    return values.map { $0 / max(0.5, width) }
  }

  private static func lineLayer(color: String, width: Double, dash: String, cap: String, join: String) -> [String: Any] {
    var paint: [String: Any] = ["line-color": color, "line-width": width, "line-emissive-strength": 1]
    if let d = dashArray(dash, width: width) { paint["line-dasharray"] = d }
    return ["type": "line", "layout": ["line-cap": cap, "line-join": join], "paint": paint]
  }

  private func shapeSpecs() -> [ShapeSpec] {
    var specs: [ShapeSpec] = []
    for c in content.circles {
      let ring = MapboxGeometry.circle(
        center: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude), radius: c.radius)
      var layers: [(String, [String: Any])] = [
        ("fill", ["type": "fill", "paint": [
          "fill-color": Self.rgba(c.fillColor, .clear), "fill-emissive-strength": 1] as [String: Any]]),
      ]
      if c.strokeWidth > 0 {
        layers.append(("line", Self.lineLayer(
          color: Self.rgba(c.strokeColor, .systemBlue), width: c.strokeWidth, dash: c.dashPattern,
          cap: "round", join: "round")))
      }
      specs.append(ShapeSpec(
        id: c.id, kind: "circle", zIndex: c.zIndex, level: c.level,
        geometry: ["type": "Polygon", "coordinates": [ring]], layers: layers))
    }
    for p in content.polygons {
      let rings = ([p.coordinates] + p.holes).filter { $0.count >= 3 }.map(MapboxGeometry.ring)
      guard !rings.isEmpty else { continue }
      var layers: [(String, [String: Any])] = [
        ("fill", ["type": "fill", "paint": [
          "fill-color": Self.rgba(p.fillColor, .clear), "fill-emissive-strength": 1] as [String: Any]]),
      ]
      if p.strokeWidth > 0 {
        layers.append(("line", Self.lineLayer(
          color: Self.rgba(p.strokeColor, .systemBlue), width: p.strokeWidth, dash: p.dashPattern,
          cap: "round", join: p.lineJoin.rawValue)))
      }
      specs.append(ShapeSpec(
        id: p.id, kind: "polygon", zIndex: p.zIndex, level: p.level,
        geometry: ["type": "Polygon", "coordinates": rings], layers: layers))
    }
    for l in content.polylines {
      var coordinates = l.geodesic ? MapboxGeometry.geodesic(l.coordinates) : l.coordinates
      coordinates = MapboxGeometry.trim(coordinates, from: l.strokeStart, to: l.strokeEnd)
      guard coordinates.count >= 2 else { continue }
      var layer = Self.lineLayer(
        color: Self.rgba(l.strokeColor, .systemBlue), width: l.strokeWidth, dash: l.dashPattern,
        cap: l.lineCap == .square ? "square" : l.lineCap == .butt ? "butt" : "round", join: l.lineJoin.rawValue)
      let colors = l.strokeColors.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
      var metrics = false
      if colors.count >= 2 {
        let given = l.strokeColorLocations.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        var stops: [Any] = ["interpolate", ["linear"], ["line-progress"]]
        var last = -1.0
        for (i, color) in colors.enumerated() {
          var at = given.count == colors.count ? given[i] : Double(i) / Double(colors.count - 1)
          at = min(1, max(last + 1e-6, at))
          last = at
          stops.append(at)
          stops.append(Self.rgba(color, .systemBlue))
        }
        var paint = layer["paint"] as? [String: Any] ?? [:]
        paint["line-gradient"] = stops
        paint["line-color"] = nil
        layer["paint"] = paint
        metrics = true
      }
      specs.append(ShapeSpec(
        id: l.id, kind: "polyline", zIndex: l.zIndex, level: l.level,
        geometry: ["type": "LineString", "coordinates": coordinates.map { [$0.longitude, $0.latitude] }],
        layers: [("line", layer)], lineMetrics: metrics))
    }
    let kindOrder = ["circle": 0, "polygon": 1, "polyline": 2]
    return specs.enumerated().sorted {
      if $0.element.zIndex != $1.element.zIndex { return $0.element.zIndex < $1.element.zIndex }
      if $0.element.kind != $1.element.kind { return kindOrder[$0.element.kind, default: 0] < kindOrder[$1.element.kind, default: 0] }
      return $0.offset < $1.offset
    }.map(\.element)
  }

  /// Puts a munim-maps layer in Standard's slot for its level, or (other
  /// styles) under the first label layer for `aboveRoads`.
  private func place(_ layer: inout [String: Any], level: MunimOverlayLevel) -> LayerPosition? {
    if hasSlots {
      layer["slot"] = level == .aboveLabels ? "top" : "middle"
      return nil
    }
    guard level == .aboveRoads else { return nil }
    let firstSymbol = mapboxMap.allLayerIdentifiers.first { $0.type == .symbol }
    return firstSymbol.map { .below($0.id) }
  }

  func rebuildShapes(force: Bool) {
    guard mapboxMap.isStyleLoaded else { return }
    let specs = shapeSpecs()
    let signature = specs.map { "\($0.kind):\($0.id):\($0.level.rawValue):\($0.lineMetrics):\($0.layers.map(\.0))" }
      .joined(separator: "|")
    if !force, signature == content.shapeSignature {
      // Same shapes in the same order: update in place.
      for spec in specs {
        let source = "munim-\(spec.kind)-\(spec.id)"
        try? mapboxMap.setSourceProperty(for: source, property: "data", value: ["type": "Feature", "properties": [:], "geometry": spec.geometry])
        for (suffix, layer) in spec.layers {
          var update: [String: Any] = [:]
          update["paint"] = layer["paint"]
          update["layout"] = layer["layout"]
          try? mapboxMap.setLayerProperties(for: "\(source)-\(suffix)", properties: update)
        }
      }
      return
    }
    for shape in content.shapes {
      for layer in shape.layers where mapboxMap.layerExists(withId: layer) { try? mapboxMap.removeLayer(withId: layer) }
      if mapboxMap.sourceExists(withId: shape.source) { try? mapboxMap.removeSource(withId: shape.source) }
    }
    content.shapes = []
    content.shapeSignature = signature
    for spec in specs {
      let source = "munim-\(spec.kind)-\(spec.id)"
      do {
        var properties: [String: Any] = [
          "type": "geojson",
          "data": ["type": "Feature", "properties": [:], "geometry": spec.geometry],
        ]
        if spec.lineMetrics { properties["lineMetrics"] = true }
        try mapboxMap.addSource(withId: source, properties: properties)
        var ids: [String] = []
        for (suffix, layer) in spec.layers {
          var full = layer
          full["id"] = "\(source)-\(suffix)"
          full["source"] = source
          let position = place(&full, level: spec.level)
          try mapboxMap.addLayer(with: full, layerPosition: position)
          ids.append("\(source)-\(suffix)")
        }
        content.shapes.append((spec.id, spec.kind, ids, source))
      } catch {
        onError?("Mapbox: \(spec.kind) \(spec.id): \(error.localizedDescription)")
      }
    }
  }

  /// The topmost tappable shape at a point, hit-tested on screen.
  func overlayHit(at point: CGPoint) -> (id: String, kind: String)? {
    let tappable: [String: Bool] = Dictionary(uniqueKeysWithValues:
      content.polylines.map { ("polyline:" + $0.id, $0.tappable) }
        + content.polygons.map { ("polygon:" + $0.id, $0.tappable) }
        + content.circles.map { ("circle:" + $0.id, $0.tappable) })
    for shape in content.shapes.reversed() where tappable["\(shape.kind):\(shape.id)"] == true {
      switch shape.kind {
      case "polyline":
        guard let line = content.polylines.first(where: { $0.id == shape.id }) else { continue }
        let points = (line.geodesic ? MapboxGeometry.geodesic(line.coordinates) : line.coordinates).map(mapboxMap.point(for:))
        let tolerance = max(12, line.strokeWidth / 2 + 6)
        if zip(points, points.dropFirst()).contains(where: { MapboxGeometry.distance(point, $0, $1) <= tolerance }) {
          return (shape.id, "polyline")
        }
      case "polygon":
        guard let polygon = content.polygons.first(where: { $0.id == shape.id }) else { continue }
        let outer = polygon.coordinates.map(mapboxMap.point(for:))
        if MapboxGeometry.contains(outer, point),
           !polygon.holes.contains(where: { MapboxGeometry.contains($0.map(mapboxMap.point(for:)), point) }) {
          return (shape.id, "polygon")
        }
      case "circle":
        guard let circle = content.circles.first(where: { $0.id == shape.id }) else { continue }
        let center = CLLocation(latitude: circle.latitude, longitude: circle.longitude)
        let c = mapboxMap.coordinate(for: point)
        if center.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)) <= circle.radius {
          return (shape.id, "circle")
        }
      default: break
      }
    }
    return nil
  }

  func overlayHit(at point: CGPoint, completion: @escaping ((id: String, kind: String)?) -> Void) {
    completion(overlayHit(at: point))
  }

  // MARK: Tile overlays

  var tileOverlays: [MunimTileOverlay] {
    get { content.tileOverlays }
    set { content.tileOverlays = newValue; updateTileOverlays(force: false) }
  }

  func updateTileOverlays(force: Bool) {
    guard mapboxMap.isStyleLoaded else { return }
    for id in content.tileIds {
      if mapboxMap.layerExists(withId: id) { try? mapboxMap.removeLayer(withId: id) }
      if mapboxMap.sourceExists(withId: id) { try? mapboxMap.removeSource(withId: id) }
    }
    content.tileIds = []
    for overlay in content.tileOverlays.sorted(by: { $0.zIndex < $1.zIndex }) {
      let id = "munim-tiles-\(overlay.id)"
      do {
        var source: [String: Any] = ["type": "raster", "tiles": [overlay.urlTemplate], "tileSize": 256]
        if overlay.minimumZoom > 0 { source["minzoom"] = overlay.minimumZoom }
        if overlay.maximumZoom > 0 { source["maxzoom"] = overlay.maximumZoom }
        try mapboxMap.addSource(withId: id, properties: source)
        var layer: [String: Any] = [
          "id": id, "type": "raster", "source": id,
          "paint": ["raster-opacity": overlay.opacity, "raster-emissive-strength": 1] as [String: Any],
        ]
        let position = place(&layer, level: overlay.replacesMap ? .aboveLabels : overlay.level)
        try mapboxMap.addLayer(with: layer, layerPosition: position)
        content.tileIds.append(id)
      } catch {
        onError?("Mapbox: tile overlay \(overlay.id): \(error.localizedDescription)")
      }
    }
  }

  // MARK: Tracking button

  func trackingButtonFrame() -> CGRect {
    let size: CGFloat = 44
    let insets = safeAreaInsets
    return CGRect(x: bounds.width - size - 12 - insets.right, y: bounds.height - size - 40 - insets.bottom,
                  width: size, height: size)
  }

  func updateTrackingButton() {
    guard showsUserTrackingButton else {
      content.trackingButton?.removeFromSuperview()
      content.trackingButton = nil
      return
    }
    let button: UIButton
    if let existing = content.trackingButton {
      button = existing
    } else {
      button = UIButton(type: .system)
      button.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.92)
      button.layer.cornerRadius = 10
      button.layer.shadowOpacity = 0.2
      button.layer.shadowRadius = 4
      button.layer.shadowOffset = CGSize(width: 0, height: 1)
      button.addAction(UIAction { [weak self] _ in self?.cycleTrackingMode() }, for: .touchUpInside)
      addSubview(button)
      content.trackingButton = button
    }
    let symbol: String
    switch userTrackingMode {
    case .follow: symbol = "location.fill"
    case .followWithHeading: symbol = "location.north.line.fill"
    default: symbol = "location"
    }
    button.setImage(UIImage(systemName: symbol), for: .normal)
    button.frame = trackingButtonFrame()
  }

  private func cycleTrackingMode() {
    let next: MKUserTrackingMode
    switch userTrackingMode {
    case .none: next = .follow
    case .follow: next = .followWithHeading
    default: next = .none
    }
    userTrackingMode = next
    onUserTrackingModeChange?(next)
  }

  // MARK: Featureset taps (`selectableMapFeatures`, `mapbox.interactions`)

  func applyInteractions() {
    content.interactions.forEach { $0.cancel() }
    content.interactions = []
    // `selectableMapFeatures` on Mapbox Standard's featuresets.
    var sets: [(String, String)] = []
    if selectableFeatures.contains(.pointsOfInterest) {
      sets += [("poi", "pointOfInterest"), ("landmark-icons", "pointOfInterest")]
    }
    if selectableFeatures.contains(.territories) { sets.append(("place-labels", "territory")) }
    for (featureset, kind) in sets {
      let interaction = TapInteraction(.featureset(featureset, importId: "basemap")) { [weak self] feature, context in
        guard let self else { return false }
        let properties = MapboxJSON.plain(feature.properties) as? [String: Any] ?? [:]
        let title = properties["name"] as? String ?? ""
        var coordinate = context.coordinate
        if case .point(let p) = feature.geometry { coordinate = p.coordinates }
        let category = (properties["class"] as? String) ?? (properties["group"] as? String) ?? (properties["type"] as? String) ?? ""
        self.onMapFeaturePress?(MunimMapFeature(
          title: title, coordinate: coordinate, kind: kind, category: category,
          id: feature.id.map { "\(featureset):\($0.id)" } ?? ""))
        return true
      }
      content.interactions.append(AnyCancelable(mapboxMap.addInteraction(interaction)))
    }
    // `mapbox.interactions`.
    for item in mapboxOptions["interactions"] as? [[String: Any]] ?? [] {
      guard let id = item["id"] as? String else { continue }
      let descriptor: FeaturesetDescriptor<FeaturesetFeature>
      if let f = item["featureset"] as? [String: Any], let set = f["featuresetId"] as? String {
        descriptor = .featureset(set, importId: f["importId"] as? String ?? "basemap")
      } else if let layer = item["layerId"] as? String {
        descriptor = .layer(layer)
      } else {
        onError?("Mapbox: interaction \(id) needs a featureset or layerId")
        continue
      }
      let filter = item["filter"].flatMap { try? MapboxJSON.decode(Exp.self, from: $0) }
      let consume = MapboxJSON.bool(item["consume"]) ?? true
      let setState = item["setState"] as? [String: Any]
      let type = item["type"] as? String ?? "tap"
      let action: (FeaturesetFeature, InteractionContext) -> Bool = { [weak self] feature, context in
        guard let self else { return false }
        if let setState, let state = try? MapboxJSON.decode(JSONObject.self, from: setState) {
          if let previous = self.content.lastInteractionFeatures[id] {
            let keys = Array(setState.keys)
            for key in keys { self.mapboxMap.removeFeatureState(previous, stateKey: key) }
          }
          self.mapboxMap.setFeatureState(feature, state: state)
          self.content.lastInteractionFeatures[id] = feature
        }
        self.emit("interaction", [
          "id": id, "type": type,
          "feature": MapboxJSON.plain(feature.originalFeature),
          "featureId": feature.id?.id ?? NSNull(),
          "featureNamespace": feature.id?.namespace ?? NSNull(),
          "featureset": [
            "featuresetId": feature.featureset.featuresetId ?? NSNull(),
            "importId": feature.featureset.importId ?? NSNull(),
            "layerId": feature.featureset.layerId ?? NSNull(),
          ],
          "state": MapboxJSON.plain(feature.state),
          "coordinate": ["latitude": context.coordinate.latitude, "longitude": context.coordinate.longitude],
          "point": ["x": context.point.x, "y": context.point.y],
        ])
        return consume
      }
      let cancelable: Cancelable = type == "longPress"
        ? mapboxMap.addInteraction(LongPressInteraction(descriptor, filter: filter, action: action))
        : mapboxMap.addInteraction(TapInteraction(descriptor, filter: filter, action: action))
      content.interactions.append(AnyCancelable(cancelable))
    }
  }
}

/// A tap recogniser with a closure.
final class MapboxTapRecognizer: UITapGestureRecognizer {
  private let handler: () -> Void
  init(_ handler: @escaping () -> Void) {
    self.handler = handler
    super.init(target: nil, action: nil)
    addTarget(self, action: #selector(fire))
  }
  @objc private func fire() { handler() }
}

/// The callout of a selected marker: title, subtitle or detail, accessories.
final class MapboxCalloutView: UIView {
  var onPress: (() -> Void)?
  var onAccessory: ((String) -> Void)?

  init(marker: MunimMarker, dark: Bool) {
    super.init(frame: .zero)
    backgroundColor = dark ? UIColor(white: 0.15, alpha: 0.97) : UIColor(white: 1, alpha: 0.97)
    layer.cornerRadius = 12
    layer.shadowOpacity = 0.25
    layer.shadowRadius = 6
    layer.shadowOffset = CGSize(width: 0, height: 2)
    let title = UILabel()
    title.text = marker.title
    title.font = .systemFont(ofSize: 15, weight: .semibold)
    title.textColor = dark ? .white : .label
    let detailText = marker.calloutDetail.isEmpty ? marker.subtitle : marker.calloutDetail
    let detail = UILabel()
    detail.text = detailText
    detail.font = .systemFont(ofSize: 13)
    detail.textColor = .secondaryLabel
    detail.numberOfLines = marker.calloutDetail.isEmpty ? 1 : 4
    let texts = UIStackView(arrangedSubviews: detailText.isEmpty ? [title] : [title, detail])
    texts.axis = .vertical
    texts.spacing = 2
    var row: [UIView] = []
    if let left = accessory(marker.leftCalloutAccessory, side: "left") { row.append(left) }
    row.append(texts)
    if let right = accessory(marker.rightCalloutAccessory, side: "right") { row.append(right) }
    let stack = UIStackView(arrangedSubviews: row)
    stack.axis = .horizontal
    stack.spacing = 10
    stack.alignment = .center
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
      widthAnchor.constraint(lessThanOrEqualToConstant: 280),
    ])
    addGestureRecognizer(MapboxTapRecognizer { [weak self] in self?.onPress?() })
    frame.size = systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

  private func accessory(_ a: MunimCalloutAccessory, side: String) -> UIView? {
    let button: UIButton
    switch a.kind {
    case .none: return nil
    case .detail: button = UIButton(type: .detailDisclosure)
    case .info: button = UIButton(type: .infoLight)
    case .button:
      button = UIButton(type: .system)
      if !a.symbol.isEmpty { button.setImage(UIImage(systemName: a.symbol), for: .normal) }
      if !a.text.isEmpty { button.setTitle(a.text, for: .normal) }
    case .image:
      let view = UIImageView(image: a.symbol.isEmpty ? nil : UIImage(systemName: a.symbol))
      if let c = UIColor(mapModelHex: a.color) { view.tintColor = c }
      if !a.imageUri.isEmpty {
        MapModelNodes.loadImage(uri: a.imageUri) { result in
          if case .success(let image) = result { DispatchQueue.main.async { view.image = image } }
        }
      }
      view.contentMode = .scaleAspectFit
      view.widthAnchor.constraint(equalToConstant: 32).isActive = true
      view.heightAnchor.constraint(equalToConstant: 32).isActive = true
      return view
    }
    if let c = UIColor(mapModelHex: a.color) { button.tintColor = c }
    button.addAction(UIAction { [weak self] _ in self?.onAccessory?(side) }, for: .touchUpInside)
    return button
  }
}

/// Geometry helpers for shapes.
enum MapboxGeometry {
  static func ring(_ coordinates: [CLLocationCoordinate2D]) -> [[Double]] {
    var ring = coordinates.map { [$0.longitude, $0.latitude] }
    if let first = ring.first, first != ring.last { ring.append(first) }
    return ring
  }

  /// A circle of `radius` metres as a closed ring.
  static func circle(center: CLLocationCoordinate2D, radius: Double, segments: Int = 96) -> [[Double]] {
    let r = radius / 6_371_008.8
    let lat = center.latitude * .pi / 180
    let lng = center.longitude * .pi / 180
    var ring: [[Double]] = (0...segments).map { i in
      let bearing = Double(i % segments) / Double(segments) * 2 * .pi
      let lat2 = asin(sin(lat) * cos(r) + cos(lat) * sin(r) * cos(bearing))
      let lng2 = lng + atan2(sin(bearing) * sin(r) * cos(lat), cos(r) - sin(lat) * sin(lat2))
      return [lng2 * 180 / .pi, lat2 * 180 / .pi]
    }
    ring[segments] = ring[0]
    return ring
  }

  /// Great-circle points between each pair, about every 50 km.
  static func geodesic(_ coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
    guard coordinates.count >= 2 else { return coordinates }
    var result = [coordinates[0]]
    for (a, b) in zip(coordinates, coordinates.dropFirst()) {
      let d = CLLocation(latitude: a.latitude, longitude: a.longitude)
        .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
      let steps = max(1, min(256, Int(d / 50_000)))
      let p1 = vector(a), p2 = vector(b)
      let omega = acos(max(-1, min(1, p1.x * p2.x + p1.y * p2.y + p1.z * p2.z)))
      for i in 1...steps {
        let f = Double(i) / Double(steps)
        if omega < 1e-9 || i == steps { result.append(i == steps ? b : a); continue }
        let s1 = sin((1 - f) * omega) / sin(omega), s2 = sin(f * omega) / sin(omega)
        let x = s1 * p1.x + s2 * p2.x, y = s1 * p1.y + s2 * p2.y, z = s1 * p1.z + s2 * p2.z
        result.append(CLLocationCoordinate2D(latitude: atan2(z, sqrt(x * x + y * y)) * 180 / .pi,
                                             longitude: atan2(y, x) * 180 / .pi))
      }
    }
    return result
  }

  private static func vector(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double, z: Double) {
    let lat = c.latitude * .pi / 180, lng = c.longitude * .pi / 180
    return (cos(lat) * cos(lng), cos(lat) * sin(lng), sin(lat))
  }

  /// The part of a line from `start` to `end` (0...1 of its length).
  static func trim(_ coordinates: [CLLocationCoordinate2D], from start: Double, to end: Double) -> [CLLocationCoordinate2D] {
    let s = max(0, min(1, start)), e = max(0, min(1, end))
    guard coordinates.count >= 2, s > 0 || e < 1 else { return coordinates }
    guard e > s else { return [] }
    let points = coordinates.map { MKMapPoint($0) }
    var lengths = [0.0]
    for (a, b) in zip(points, points.dropFirst()) { lengths.append(lengths.last! + a.distance(to: b)) }
    let total = lengths.last!
    guard total > 0 else { return coordinates }
    func at(_ d: Double) -> CLLocationCoordinate2D {
      var i = 1
      while i < lengths.count - 1, lengths[i] < d { i += 1 }
      let f = (d - lengths[i - 1]) / max(1e-9, lengths[i] - lengths[i - 1])
      return MKMapPoint(x: points[i - 1].x + (points[i].x - points[i - 1].x) * f,
                        y: points[i - 1].y + (points[i].y - points[i - 1].y) * f).coordinate
    }
    let from = s * total, to = e * total
    var result = [at(from)]
    for (i, length) in lengths.enumerated() where length > from && length < to { result.append(coordinates[i]) }
    result.append(at(to))
    return result
  }

  static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
    let dx = b.x - a.x, dy = b.y - a.y
    let length = dx * dx + dy * dy
    let t = length > 0 ? max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / length)) : 0
    let x = a.x + t * dx - p.x, y = a.y + t * dy - p.y
    return Double(sqrt(x * x + y * y))
  }

  static func contains(_ polygon: [CGPoint], _ p: CGPoint) -> Bool {
    guard polygon.count >= 3 else { return false }
    var inside = false
    var j = polygon.count - 1
    for i in 0..<polygon.count {
      let a = polygon[i], b = polygon[j]
      if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
      j = i
    }
    return inside
  }
}
#endif
