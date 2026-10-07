import MapKit
import UIKit

// MARK: - Annotations

/// A marker on a `MunimMapView`. `coordinate` is KVO-observable, so moving a
/// marker animates it.
final class MunimAnnotation: NSObject, MKAnnotation {
  let id: String
  @objc dynamic var coordinate: CLLocationCoordinate2D
  var title: String?
  var subtitle: String?
  var marker: MunimMarker

  init(marker: MunimMarker) {
    id = marker.id
    self.marker = marker
    coordinate = CLLocationCoordinate2D(latitude: marker.latitude, longitude: marker.longitude)
    title = marker.title.isEmpty ? nil : marker.title
    subtitle = marker.subtitle.isEmpty ? nil : marker.subtitle
  }
}

// MARK: - Overlays

protocol MunimOverlay: MKOverlay {
  var id: String { get }
  var zIndex: Double { get }
}

final class PolylineOverlay: MKPolyline, MunimOverlay {
  var id = ""
  var style: MunimPolyline?
  var zIndex: Double { style?.zIndex ?? 0 }
}

final class PolygonOverlay: MKPolygon, MunimOverlay {
  var id = ""
  var style: MunimPolygon?
  var zIndex: Double { style?.zIndex ?? 0 }
}

final class CircleOverlay: MKCircle, MunimOverlay {
  var id = ""
  var style: MunimCircle?
  var zIndex: Double { style?.zIndex ?? 0 }
}

final class TileOverlay: MKTileOverlay, MunimOverlay {
  var id = ""
  var style: MunimTileOverlay?
  var zIndex: Double { style?.zIndex ?? 0 }
}

func parseDashPattern(_ text: String) -> [NSNumber]? {
  let values = text.split(whereSeparator: { $0 == "," || $0 == " " })
    .compactMap { Double($0) }
    .filter { $0 > 0 }
  return values.count >= 2 ? values.map { NSNumber(value: $0) } : nil
}

// MARK: - Marker images

enum MarkerImages {
  private static let cache = NSCache<NSString, UIImage>()

  /// The image for an `avatar`, `image`, `label` or `dot` marker. `photo` is
  /// the loaded picture (nil while loading or for styles without one).
  static func image(for marker: MunimMarker, photo: UIImage?, scale: CGFloat) -> UIImage? {
    let key = cacheKey(marker, hasPhoto: photo != nil) as NSString
    if let cached = cache.object(forKey: key) { return cached }
    let image: UIImage?
    switch marker.style {
    case .avatar: image = avatar(marker, photo: photo, scale: scale)
    case .image: image = picture(marker, photo: photo, scale: scale)
    case .label: image = label(marker, scale: scale)
    case .dot: image = dot(marker, scale: scale)
    case .pin, .marker: image = nil
    }
    if let image { cache.setObject(image, forKey: key) }
    return image
  }

  private static func cacheKey(_ m: MunimMarker, hasPhoto: Bool) -> String {
    let badges = m.badges.map { "\($0.text)/\($0.position.stringValue)/\($0.color)/\($0.textColor)" }
      .joined(separator: ";")
    return [m.style.stringValue, m.imageUri, "\(hasPhoto)", "\(m.imageSize)", m.color,
            m.borderColor, "\(m.borderWidth)", badges, m.title].joined(separator: "|")
  }

  private static func renderer(_ size: CGSize, _ scale: CGFloat) -> UIGraphicsImageRenderer {
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    format.opaque = false
    return UIGraphicsImageRenderer(size: size, format: format)
  }

  private static func avatar(_ m: MunimMarker, photo: UIImage?, scale: CGFloat) -> UIImage {
    let d = CGFloat(m.imageSize > 0 ? m.imageSize : 44)
    let pad: CGFloat = 8 // room for corner badges
    let size = CGSize(width: d + pad * 2, height: d + pad * 2)
    return renderer(size, scale).image { context in
      let cg = context.cgContext
      let circle = CGRect(x: pad, y: pad, width: d, height: d)
      cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor(white: 0, alpha: 0.25).cgColor)
      (UIColor(mapModelHex: m.borderColor) ?? .white).setFill()
      cg.fillEllipse(in: circle)
      cg.setShadow(offset: .zero, blur: 0, color: nil)
      let ring = CGFloat(max(0, m.borderWidth))
      let inner = circle.insetBy(dx: ring, dy: ring)
      cg.saveGState()
      cg.addEllipse(in: inner)
      cg.clip()
      UIColor(white: 0.88, alpha: 1).setFill()
      cg.fill(inner)
      if let photo { drawAspectFill(photo, in: inner) }
      cg.restoreGState()
      drawBadges(m.badges, around: circle, in: cg)
    }
  }

  private static func picture(_ m: MunimMarker, photo: UIImage?, scale: CGFloat) -> UIImage? {
    guard let photo else { return nil }
    let w = CGFloat(m.imageSize > 0 ? m.imageSize : photo.size.width)
    let h = w * photo.size.height / max(1, photo.size.width)
    let pad: CGFloat = m.badges.isEmpty ? 0 : 8
    return renderer(CGSize(width: w + pad * 2, height: h + pad * 2), scale).image { context in
      let rect = CGRect(x: pad, y: pad, width: w, height: h)
      photo.draw(in: rect)
      drawBadges(m.badges, around: rect, in: context.cgContext)
    }
  }

  private static func label(_ m: MunimMarker, scale: CGFloat) -> UIImage {
    let font = UIFont.systemFont(ofSize: 13, weight: .semibold)
    let text = (m.title.isEmpty ? " " : m.title) as NSString
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
    let textSize = text.size(withAttributes: attributes)
    let size = CGSize(width: ceil(textSize.width) + 20, height: 26)
    return renderer(size, scale).image { _ in
      let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
      (UIColor(mapModelHex: m.color) ?? UIColor(white: 0.1, alpha: 0.9)).setFill()
      UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).fill()
      text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                withAttributes: attributes)
    }
  }

  private static func dot(_ m: MunimMarker, scale: CGFloat) -> UIImage {
    let d = CGFloat(m.imageSize > 0 ? m.imageSize : 14)
    return renderer(CGSize(width: d, height: d), scale).image { context in
      let rect = CGRect(x: 0, y: 0, width: d, height: d)
      (UIColor(mapModelHex: m.borderColor) ?? .white).setFill()
      context.cgContext.fillEllipse(in: rect)
      let ring = CGFloat(m.borderWidth > 0 ? m.borderWidth : 2)
      (UIColor(mapModelHex: m.color) ?? .systemBlue).setFill()
      context.cgContext.fillEllipse(in: rect.insetBy(dx: ring, dy: ring))
    }
  }

  private static func drawAspectFill(_ image: UIImage, in rect: CGRect) {
    let s = max(rect.width / max(1, image.size.width), rect.height / max(1, image.size.height))
    let size = CGSize(width: image.size.width * s, height: image.size.height * s)
    image.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                          width: size.width, height: size.height))
  }

  private static func drawBadges(_ badges: [MunimMarkerBadge], around rect: CGRect, in cg: CGContext) {
    for badge in badges where !badge.text.isEmpty {
      let font = UIFont.systemFont(ofSize: 10, weight: .heavy)
      let color = UIColor(mapModelHex: badge.textColor) ?? .white
      let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
      let text = badge.text as NSString
      let textSize = text.size(withAttributes: attributes)
      let h: CGFloat = 18
      let w = max(h, ceil(textSize.width) + 9)
      let center: CGPoint
      switch badge.position {
      case .topLeft: center = CGPoint(x: rect.minX + w / 2 - 6, y: rect.minY + h / 2 - 6)
      case .topRight: center = CGPoint(x: rect.maxX - w / 2 + 6, y: rect.minY + h / 2 - 6)
      case .bottomLeft: center = CGPoint(x: rect.minX + w / 2 - 6, y: rect.maxY - h / 2 + 6)
      case .bottomRight: center = CGPoint(x: rect.maxX - w / 2 + 6, y: rect.maxY - h / 2 + 6)
      case .bottom: center = CGPoint(x: rect.midX, y: rect.maxY - h / 2 + 6)
      }
      let pill = CGRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)
      let path = UIBezierPath(roundedRect: pill, cornerRadius: h / 2)
      (UIColor(mapModelHex: badge.color) ?? UIColor(white: 0.07, alpha: 1)).setFill()
      path.fill()
      UIColor.white.setStroke()
      path.lineWidth = 1.5
      path.stroke()
      text.draw(at: CGPoint(x: pill.midX - textSize.width / 2, y: pill.midY - textSize.height / 2),
                withAttributes: attributes)
    }
  }
}

// MARK: - Controller

/// Keeps a map's markers and overlays in step with the props, and answers
/// the map delegate's questions about them.
final class MapFeatureController {
  weak var mapView: MKMapView?
  private(set) var annotations: [String: MunimAnnotation] = [:]
  private var overlays: [String: MunimOverlay] = [:]
  private var overlayKeys: [String: String] = [:]
  private var photos: [String: UIImage] = [:]
  private var loadingPhotos: Set<String> = []
  /// Cluster looks by clustering id.
  var clusterStyles: [String: MunimClusterStyle] = [:] {
    didSet { refreshClusters() }
  }
  var onError: ((String) -> Void)?

  init(mapView: MKMapView) {
    self.mapView = mapView
  }

  // MARK: Markers

  func setMarkers(_ markers: [MunimMarker]) {
    guard let mapView else { return }
    var seen = Set<String>()
    var toAdd: [MunimAnnotation] = []
    for marker in markers where !seen.contains(marker.id) {
      seen.insert(marker.id)
      if let existing = annotations[marker.id] {
        let old = existing.marker
        existing.marker = marker
        existing.title = marker.title.isEmpty ? nil : marker.title
        existing.subtitle = marker.subtitle.isEmpty ? nil : marker.subtitle
        if old.latitude != marker.latitude || old.longitude != marker.longitude {
          existing.coordinate = CLLocationCoordinate2D(latitude: marker.latitude, longitude: marker.longitude)
        }
        if let view = mapView.view(for: existing) { configure(view, for: existing) }
      } else {
        let annotation = MunimAnnotation(marker: marker)
        annotations[marker.id] = annotation
        toAdd.append(annotation)
      }
      if !marker.imageUri.isEmpty { loadPhoto(marker.imageUri) }
    }
    let removed = annotations.filter { !seen.contains($0.key) }
    for (id, annotation) in removed {
      mapView.removeAnnotation(annotation)
      annotations[id] = nil
    }
    if !toAdd.isEmpty { mapView.addAnnotations(toAdd) }
  }

  private func loadPhoto(_ uri: String) {
    guard photos[uri] == nil, !loadingPhotos.contains(uri) else { return }
    loadingPhotos.insert(uri)
    MapModelNodes.loadImage(uri: uri) { [weak self] result in
      DispatchQueue.main.async {
        guard let self else { return }
        self.loadingPhotos.remove(uri)
        switch result {
        case .success(let image):
          self.photos[uri] = image
          self.refreshViews(using: uri)
        case .failure(let error):
          self.onError?("Could not load marker image: \(error.localizedDescription)")
        }
      }
    }
  }

  private func refreshViews(using uri: String) {
    guard let mapView else { return }
    for annotation in annotations.values
    where annotation.marker.imageUri == uri
      || annotation.marker.leftCalloutAccessory.imageUri == uri
      || annotation.marker.rightCalloutAccessory.imageUri == uri
    {
      if let view = mapView.view(for: annotation) { configure(view, for: annotation) }
    }
  }

  private func refreshClusters() {
    guard let mapView else { return }
    for case let cluster as MKClusterAnnotation in mapView.annotations {
      if let view = mapView.view(for: cluster) as? MKMarkerAnnotationView { configureCluster(view, cluster) }
    }
  }

  static let clusterReuse = "munim-cluster"

  /// The view for a cluster with a style, or nil for MapKit's default.
  func clusterView(for cluster: MKClusterAnnotation, in mapView: MKMapView) -> MKAnnotationView? {
    guard let style = style(for: cluster) else { return nil }
    let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.clusterReuse) as? MKMarkerAnnotationView
      ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: Self.clusterReuse)
    view.annotation = cluster
    configureCluster(view, cluster, style: style)
    return view
  }

  func clusteringId(of cluster: MKClusterAnnotation) -> String {
    cluster.memberAnnotations.lazy.compactMap { ($0 as? MunimAnnotation)?.marker.clusteringId }.first ?? ""
  }

  private func style(for cluster: MKClusterAnnotation) -> MunimClusterStyle? {
    clusterStyles[clusteringId(of: cluster)]
  }

  private func configureCluster(_ view: MKMarkerAnnotationView, _ cluster: MKClusterAnnotation,
                                style given: MunimClusterStyle? = nil) {
    guard let style = given ?? self.style(for: cluster) else { return }
    let count = "\(cluster.memberAnnotations.count)"
    func fill(_ text: String) -> String { text.replacingOccurrences(of: "{count}", with: count) }
    view.markerTintColor = UIColor(mapModelHex: style.color)
    view.glyphTintColor = UIColor(mapModelHex: style.glyphColor)
    if !style.glyphSymbol.isEmpty, let symbol = UIImage(systemName: style.glyphSymbol) {
      view.glyphImage = symbol
      view.glyphText = nil
    } else {
      view.glyphImage = nil
      view.glyphText = style.glyph.isEmpty ? count : fill(style.glyph)
    }
    if !style.title.isEmpty { cluster.title = fill(style.title) }
    if !style.subtitle.isEmpty { cluster.subtitle = fill(style.subtitle) }
    view.displayPriority = MKFeatureDisplayPriority(rawValue: Float(min(1000, max(0, style.displayPriority))))
  }

  static let pinReuse = "munim-pin"
  static let markerReuse = "munim-marker"
  static let imageReuse = "munim-image"

  func view(for annotation: MunimAnnotation, in mapView: MKMapView) -> MKAnnotationView {
    let reuse: String
    switch annotation.marker.style {
    case .pin: reuse = Self.pinReuse
    case .marker: reuse = Self.markerReuse
    default: reuse = Self.imageReuse
    }
    let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuse)
      ?? {
        switch annotation.marker.style {
        case .pin: return MKPinAnnotationView(annotation: annotation, reuseIdentifier: reuse)
        case .marker: return MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: reuse)
        default: return MKAnnotationView(annotation: annotation, reuseIdentifier: reuse)
        }
      }()
    view.annotation = annotation
    configure(view, for: annotation)
    return view
  }

  func configure(_ view: MKAnnotationView, for annotation: MunimAnnotation) {
    let m = annotation.marker
    let color = UIColor(mapModelHex: m.color)
    view.canShowCallout = m.calloutEnabled && annotation.title != nil
    if view.canShowCallout {
      view.leftCalloutAccessoryView = accessoryView(m.leftCalloutAccessory, tag: Self.leftAccessoryTag)
      view.rightCalloutAccessoryView = accessoryView(m.rightCalloutAccessory, tag: Self.rightAccessoryTag)
      view.detailCalloutAccessoryView = m.calloutDetail.isEmpty ? nil : detailLabel(m.calloutDetail)
    } else {
      view.leftCalloutAccessoryView = nil
      view.rightCalloutAccessoryView = nil
      view.detailCalloutAccessoryView = nil
    }
    view.isDraggable = m.draggable
    view.alpha = CGFloat(min(1, max(0, m.opacity)))
    view.isHidden = !m.visible
    view.clusteringIdentifier = m.clusteringId.isEmpty ? nil : m.clusteringId
    view.zPriority = MKAnnotationViewZPriority(rawValue: Float(min(1000, max(0, 500 + m.zIndex))))
    view.displayPriority = MKFeatureDisplayPriority(rawValue: Float(min(1000, max(0, m.displayPriority))))
    switch m.collisionMode {
    case .rectangle: view.collisionMode = .rectangle
    case .circle: view.collisionMode = .circle
    case .none: view.collisionMode = .none
    }
    switch m.style {
    case .pin:
      (view as? MKPinAnnotationView)?.pinTintColor = color ?? .systemRed
    case .marker:
      if let marker = view as? MKMarkerAnnotationView {
        marker.markerTintColor = color
        marker.glyphTintColor = UIColor(mapModelHex: m.glyphColor)
        if !m.glyphSymbol.isEmpty, let symbol = UIImage(systemName: m.glyphSymbol) {
          marker.glyphImage = symbol
          marker.glyphText = nil
        } else {
          marker.glyphImage = nil
          marker.glyphText = m.glyph.isEmpty ? nil : m.glyph
        }
        marker.selectedGlyphImage = m.selectedGlyphSymbol.isEmpty ? nil : UIImage(systemName: m.selectedGlyphSymbol)
        marker.titleVisibility = m.titleVisibility.mapKit
        marker.subtitleVisibility = m.subtitleVisibility.mapKit
        marker.animatesWhenAdded = m.animatesWhenAdded
      }
    default:
      let scale = view.window?.screen.scale ?? UIScreen.main.scale
      if let snapshot = viewImages[m.id] {
        view.image = snapshot
      } else {
        view.image = MarkerImages.image(for: m, photo: photos[m.imageUri], scale: scale)
      }
      if let image = view.image {
        // MapKit centres the image on the coordinate; move it to the anchor.
        view.centerOffset = CGPoint(
          x: (0.5 - CGFloat(m.anchorX)) * image.size.width,
          y: (0.5 - CGFloat(m.anchorY)) * image.size.height)
      }
    }
  }

  // MARK: Callouts

  static let leftAccessoryTag = 7_101
  static let rightAccessoryTag = 7_102

  private func accessoryView(_ accessory: MunimCalloutAccessory, tag: Int) -> UIView? {
    let tint = UIColor(mapModelHex: accessory.color)
    let made: UIView?
    switch accessory.kind {
    case .none: made = nil
    case .detail: made = UIButton(type: .detailDisclosure)
    case .info: made = UIButton(type: .infoLight)
    case .button:
      let button = UIButton(type: .system)
      if !accessory.symbol.isEmpty, let symbol = UIImage(systemName: accessory.symbol) {
        button.setImage(symbol, for: .normal)
      }
      if !accessory.text.isEmpty { button.setTitle(accessory.text, for: .normal) }
      button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
      button.sizeToFit()
      button.frame.size = CGSize(width: max(32, button.frame.width + 8), height: max(32, button.frame.height))
      made = button
    case .image:
      var image: UIImage?
      if !accessory.symbol.isEmpty {
        image = UIImage(systemName: accessory.symbol)
      } else if !accessory.imageUri.isEmpty {
        image = photos[accessory.imageUri]
        if image == nil { loadPhoto(accessory.imageUri) }
      }
      let imageView = UIImageView(image: image)
      imageView.contentMode = .scaleAspectFill
      imageView.clipsToBounds = true
      imageView.layer.cornerRadius = accessory.symbol.isEmpty ? 6 : 0
      imageView.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
      if !accessory.symbol.isEmpty { imageView.contentMode = .scaleAspectFit }
      made = imageView
    }
    if let tint { made?.tintColor = tint }
    made?.tag = tag
    return made
  }

  private func detailLabel(_ text: String) -> UILabel {
    let label = UILabel()
    label.text = text
    label.numberOfLines = 0
    label.font = .preferredFont(forTextStyle: .subheadline)
    label.textColor = .secondaryLabel
    return label
  }

  // MARK: View markers

  /// Snapshots of React Native views (`MarkerView`), by marker id.
  private(set) var viewImages: [String: UIImage] = [:]

  func setViewImage(_ image: UIImage?, for id: String) {
    viewImages[id] = image
    if let annotation = annotations[id], let view = mapView?.view(for: annotation) {
      configure(view, for: annotation)
    }
  }

  // MARK: Overlays

  func setPolylines(_ items: [MunimPolyline]) {
    sync(prefix: "line", items: items, id: \.id, key: { p in
      "\(p.coordinates.map { "\($0.latitude),\($0.longitude)" })|\(p.geodesic)|\(p.strokeColor)|\(p.strokeWidth)|\(p.dashPattern)|\(p.lineCap.stringValue)|\(p.zIndex)"
    }) { p in
      var coordinates = p.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
      let line: PolylineOverlay
      if p.geodesic {
        // MKGeodesicPolyline's initialiser always returns an
        // MKGeodesicPolyline, never a subclass (setting a subclass's
        // properties on it corrupts memory), so take its curved points.
        let curve = MKGeodesicPolyline(coordinates: &coordinates, count: coordinates.count)
        line = PolylineOverlay(points: curve.points(), count: curve.pointCount)
      } else {
        line = PolylineOverlay(coordinates: &coordinates, count: coordinates.count)
      }
      line.id = p.id; line.style = p
      return line
    }
  }

  func setPolygons(_ items: [MunimPolygon]) {
    sync(prefix: "polygon", items: items, id: \.id, key: { p in
      "\(p.coordinates.map { "\($0.latitude),\($0.longitude)" })|\(p.holes.map { $0.map { "\($0.latitude),\($0.longitude)" } })|\(p.strokeColor)|\(p.fillColor)|\(p.strokeWidth)|\(p.dashPattern)|\(p.zIndex)"
    }) { p in
      let holes: [MKPolygon] = p.holes.map { ring in
        var c = ring.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        return MKPolygon(coordinates: &c, count: c.count)
      }
      var coordinates = p.coordinates.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
      let polygon = PolygonOverlay(coordinates: &coordinates, count: coordinates.count, interiorPolygons: holes)
      polygon.id = p.id; polygon.style = p
      return polygon
    }
  }

  func setCircles(_ items: [MunimCircle]) {
    sync(prefix: "circle", items: items, id: \.id, key: { c in
      "\(c.latitude),\(c.longitude)|\(c.radius)|\(c.strokeColor)|\(c.fillColor)|\(c.strokeWidth)|\(c.dashPattern)|\(c.zIndex)"
    }) { c in
      let circle = CircleOverlay(center: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude), radius: c.radius)
      circle.id = c.id; circle.style = c
      return circle
    }
  }

  func setTileOverlays(_ items: [MunimTileOverlay]) {
    sync(prefix: "tile", items: items, id: \.id, key: { t in
      "\(t.urlTemplate)|\(t.replacesMap)|\(t.minimumZoom)|\(t.maximumZoom)|\(t.opacity)|\(t.zIndex)"
    }) { t in
      let overlay = TileOverlay(urlTemplate: t.urlTemplate)
      overlay.id = t.id; overlay.style = t
      overlay.canReplaceMapContent = t.replacesMap
      if t.minimumZoom > 0 { overlay.minimumZ = Int(t.minimumZoom) }
      if t.maximumZoom > 0 { overlay.maximumZ = Int(t.maximumZoom) }
      return overlay
    }
  }

  /// Replaces overlays whose content changed, keeping their order by zIndex.
  private func sync<T>(prefix: String, items: [T], id: (T) -> String, key: (T) -> String,
                       make: (T) -> MunimOverlay) {
    guard let mapView else { return }
    var seen = Set<String>()
    for item in items {
      let itemKey = "\(prefix):\(id(item))"
      guard !seen.contains(itemKey) else { continue }
      seen.insert(itemKey)
      let contentKey = key(item)
      if overlayKeys[itemKey] == contentKey { continue }
      if let old = overlays[itemKey] { mapView.removeOverlay(old) }
      let overlay = make(item)
      overlays[itemKey] = overlay
      overlayKeys[itemKey] = contentKey
      insertSorted(overlay, into: mapView)
    }
    for (itemKey, overlay) in overlays where itemKey.hasPrefix("\(prefix):") && !seen.contains(itemKey) {
      mapView.removeOverlay(overlay)
      overlays[itemKey] = nil
      overlayKeys[itemKey] = nil
    }
  }

  private func insertSorted(_ overlay: MunimOverlay, into mapView: MKMapView) {
    let level: MKOverlayLevel = overlay is TileOverlay ? .aboveRoads : .aboveLabels
    let existing = mapView.overlays(in: level).compactMap { $0 as? MunimOverlay }
    let index = existing.firstIndex { $0.zIndex > overlay.zIndex } ?? existing.count
    mapView.insertOverlay(overlay, at: index, level: level)
  }

  func renderer(for overlay: MKOverlay) -> MKOverlayRenderer? {
    func stroke(_ r: MKOverlayPathRenderer, color: String, width: Double, dash: String) {
      r.strokeColor = UIColor(mapModelHex: color) ?? .systemBlue
      r.lineWidth = CGFloat(width)
      r.lineDashPattern = parseDashPattern(dash)
    }
    switch overlay {
    case let line as PolylineOverlay:
      let r = MKPolylineRenderer(polyline: line)
      if let s = line.style { stroke(r, color: s.strokeColor, width: s.strokeWidth, dash: s.dashPattern); r.lineCap = lineCap(s.lineCap) }
      return r
    case let polygon as PolygonOverlay:
      let r = MKPolygonRenderer(polygon: polygon)
      if let s = polygon.style {
        stroke(r, color: s.strokeColor, width: s.strokeWidth, dash: s.dashPattern)
        r.fillColor = UIColor(mapModelHex: s.fillColor)
      }
      return r
    case let circle as CircleOverlay:
      let r = MKCircleRenderer(circle: circle)
      if let s = circle.style {
        stroke(r, color: s.strokeColor, width: s.strokeWidth, dash: s.dashPattern)
        r.fillColor = UIColor(mapModelHex: s.fillColor)
      }
      return r
    case let tiles as TileOverlay:
      let r = MKTileOverlayRenderer(tileOverlay: tiles)
      r.alpha = CGFloat(tiles.style?.opacity ?? 1)
      return r
    default:
      return nil
    }
  }

  private func lineCap(_ cap: MunimLineCap) -> CGLineCap {
    switch cap {
    case .round: return .round
    case .butt: return .butt
    case .square: return .square
    }
  }

  /// Bounding map rect of the given markers (all when `ids` is empty).
  func mapRect(forMarkers ids: Set<String>) -> MKMapRect? {
    let points = annotations.values
      .filter { ids.isEmpty || ids.contains($0.id) }
      .map { MKMapPoint($0.coordinate) }
    return MapFeatureController.boundingRect(points)
  }

  static func boundingRect(_ points: [MKMapPoint]) -> MKMapRect? {
    guard let first = points.first else { return nil }
    var rect = MKMapRect(origin: first, size: MKMapSize(width: 0, height: 0))
    for p in points.dropFirst() { rect = rect.union(MKMapRect(origin: p, size: MKMapSize(width: 0, height: 0))) }
    // Give a single point a sensible size.
    if rect.size.width < 1 { rect = rect.insetBy(dx: -2_000, dy: -2_000) }
    return rect
  }
}
