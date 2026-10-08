#if canImport(GoogleMaps)
import GoogleMaps
import GoogleMapsUtils
import MapKit
import UIKit

// Markers on Google: plain `GMSMarker`s, or `GMSAdvancedMarker`s with pins
// and collision behaviour on maps with a Map ID; clustering with Google
// Maps Utils (`GMUClusterManager`, one per `clusteringId`); info windows.

extension GoogleMapEngine {
  /// Whether markers are advanced markers: needs a Map ID.
  var usesAdvancedMarkers: Bool { !(options["mapId"].string ?? "").isEmpty }

  func markerOptions(_ id: String) -> GoogleJSON { options["markers"][id] }

  // MARK: MarkerView

  public func setViewMarker(_ marker: MunimMarker, image: UIImage?) {
    viewMarkers[marker.id] = marker
    viewMarkerImages[marker.id] = image
    applyMarkers()
  }

  public func setViewMarkerImage(_ image: UIImage?, id: String) {
    viewMarkerImages[id] = image
    if let marker = gmsMarkers[id], let image { marker.icon = image }
  }

  public func removeViewMarker(_ id: String) {
    viewMarkers[id] = nil
    viewMarkerImages[id] = nil
    applyMarkers()
  }

  // MARK: Applying

  func applyMarkers() {
    mode3d?.setMarkers(markers + viewMarkers.values)
    guard let mapView else { return }
    var wanted: [String: MunimMarker] = [:]
    for m in markers { wanted[m.id] = m }
    for (id, m) in viewMarkers { wanted[id] = m }

    var touchedClusters: Set<String> = []
    // Remove what went away.
    for (id, marker) in gmsMarkers where wanted[id] == nil {
      removeMarker(marker, id: id, touched: &touchedClusters)
    }
    for (id, m) in wanted {
      let extras = markerOptions(id)
      let advanced = usesAdvancedMarkers && extras["advanced"].bool(true)
      let clusterId = m.visible ? m.clusteringId : ""
      var marker = gmsMarkers[id]
      if let existing = marker, (existing is GMSAdvancedMarker) != advanced || clusterIds[id] != clusterId {
        removeMarker(existing, id: id, touched: &touchedClusters)
        marker = nil
      }
      let isNew = marker == nil
      let gm = marker ?? (advanced ? GMSAdvancedMarker() : GMSMarker())
      let moved = !isNew && (gm.position.latitude != m.latitude || gm.position.longitude != m.longitude)
      let extrasKey = extras.exists ? String(describing: extras.raw!) : ""
      if isNew || markerData[id] != m || moved || markerExtras[id] != extrasKey {
        configure(gm, m, extras: extras, isNew: isNew)
      }
      markerExtras[id] = extrasKey
      markerData[id] = m
      gmsMarkers[id] = gm
      if clusterId.isEmpty {
        gm.map = m.visible ? mapView : nil
        clusterIds[id] = nil
      } else {
        let manager = clusterManager(for: clusterId, mapView: mapView)
        if isNew || clusterIds[id] != clusterId {
          manager.add(gm)
        } else if moved {
          manager.remove(gm)
          manager.add(gm)
        }
        clusterIds[id] = clusterId
        touchedClusters.insert(clusterId)
      }
    }
    for id in markerData.keys where wanted[id] == nil {
      markerData[id] = nil
      markerExtras[id] = nil
    }
    for clusterId in touchedClusters { clusterManagers[clusterId]?.cluster() }
    // Drop managers nobody uses.
    let used = Set(clusterIds.values)
    for (clusterId, manager) in clusterManagers where !used.contains(clusterId) {
      manager.clearItems()
      manager.cluster()
      clusterManagers[clusterId] = nil
    }
  }

  private func removeMarker(_ marker: GMSMarker, id: String, touched: inout Set<String>) {
    if let clusterId = clusterIds[id], let manager = clusterManagers[clusterId] {
      manager.remove(marker)
      touched.insert(clusterId)
    }
    marker.map = nil
    gmsMarkers[id] = nil
    clusterIds[id] = nil
    if selectedMarkerId == id { selectedMarkerId = nil }
  }

  private func configure(_ gm: GMSMarker, _ m: MunimMarker, extras: GoogleJSON, isNew: Bool) {
    gm.userData = m.id
    gm.position = CLLocationCoordinate2D(latitude: m.latitude, longitude: m.longitude)
    if m.calloutEnabled {
      gm.title = m.title.isEmpty ? nil : m.title
      let detail = m.calloutDetail.isEmpty ? m.subtitle : m.calloutDetail
      gm.snippet = detail.isEmpty ? nil : detail
    } else {
      gm.title = nil
      gm.snippet = nil
    }
    gm.tracksViewChanges = false
    gm.tracksInfoWindowChanges = false
    gm.zIndex = Int32(clamping: Int(m.zIndex.rounded()))
    gm.isDraggable = m.draggable
    gm.opacity = Float(max(0, min(1, m.opacity)))
    if isNew { gm.appearAnimation = m.animatesWhenAdded ? .pop : .none }

    let scale = window?.screen.scale ?? UIScreen.main.scale
    var anchor = CGPoint(x: m.anchorX, y: m.anchorY)
    if viewMarkers[m.id] != nil {
      gm.icon = viewMarkerImages[m.id] ?? GoogleMarkerIcons.transparent
    } else {
      switch m.style {
      case .pin, .marker:
        anchor = CGPoint(x: 0.5, y: 1)
        gm.icon = pinIcon(m, extras: extras["pin"], advanced: gm is GMSAdvancedMarker, scale: scale)
      case .image, .avatar:
        if !m.imageUri.isEmpty, photos[m.imageUri] == nil { loadPhoto(m.imageUri) }
        gm.icon = MarkerImages.image(for: m, photo: photos[m.imageUri], scale: scale)
      case .label, .dot:
        gm.icon = MarkerImages.image(for: m, photo: nil, scale: scale)
      }
    }
    if let x = extras["anchor"]["x"].double, let y = extras["anchor"]["y"].double { anchor = CGPoint(x: x, y: y) }
    gm.groundAnchor = anchor
    if let advanced = gm as? GMSAdvancedMarker {
      switch extras["collisionBehavior"].string {
      case "required": advanced.collisionBehavior = .required
      case "requiredAndHidesOptional": advanced.collisionBehavior = .requiredAndHidesOptional
      case "optionalAndHidesLowerPriority": advanced.collisionBehavior = .optionalAndHidesLowerPriority
      default:
        if m.displayPriority >= 1000 || m.collisionMode == .none {
          advanced.collisionBehavior = m.displayPriority >= 1000 ? .requiredAndHidesOptional : .required
        } else {
          advanced.collisionBehavior = .optionalAndHidesLowerPriority
        }
      }
    }
    configureExtras(gm, extras)
  }

  /// Options only Google markers have (`google.markers[id]`).
  private func configureExtras(_ gm: GMSMarker, _ extras: GoogleJSON) {
    gm.isFlat = extras["flat"].bool(false)
    gm.rotation = extras["rotation"].double(0)
    let window = extras["infoWindowAnchor"]
    gm.infoWindowAnchor = CGPoint(x: window["x"].double(0.5), y: window["y"].double(0))
    if let opacity = extras["opacity"].double { gm.opacity = Float(opacity) }
    if let z = extras["zIndex"].double { gm.zIndex = Int32(clamping: Int(z)) }
  }

  /// Google's pin: an advanced marker's `GMSPinImage`, the classic pin
  /// tinted, or a balloon with the glyph drawn by munim-maps.
  private func pinIcon(_ m: MunimMarker, extras: GoogleJSON, advanced: Bool, scale: CGFloat) -> UIImage? {
    let color = extras["background"].color ?? UIColor(mapModelHex: m.color)
    if advanced {
      let options = GMSPinImageOptions()
      options.backgroundColor = color
      options.borderColor = extras["border"].color ?? (m.borderColor.isEmpty ? nil : UIColor(mapModelHex: m.borderColor))
      let text = extras["glyph"].string ?? (m.style == .marker ? m.glyph : "")
      let glyphColor = extras["glyphColor"].color ?? UIColor(mapModelHex: m.glyphColor)
      if let uri = extras["glyphImageUri"].string, let image = photos[uri] {
        options.glyph = GMSPinImageGlyph(image: image)
      } else if let uri = extras["glyphImageUri"].string {
        loadPhoto(uri)
      } else if !text.isEmpty {
        options.glyph = GMSPinImageGlyph(text: text, textColor: glyphColor ?? .white)
      } else if let glyphColor {
        options.glyph = GMSPinImageGlyph(glyphColor: glyphColor)
      }
      return GMSPinImage(options: options)
    }
    if m.style == .marker, !m.glyph.isEmpty {
      return GoogleMarkerIcons.balloon(
        color: color ?? UIColor(red: 0.92, green: 0.26, blue: 0.21, alpha: 1), glyph: m.glyph,
        glyphColor: UIColor(mapModelHex: m.glyphColor) ?? .white, scale: scale)
    }
    return GMSMarker.markerImage(with: color)
  }

  func loadPhoto(_ uri: String) {
    guard photos[uri] == nil, !loadingPhotos.contains(uri) else { return }
    loadingPhotos.insert(uri)
    MapModelNodes.loadImage(uri: uri) { [weak self] result in
      DispatchQueue.main.async {
        guard let self else { return }
        self.loadingPhotos.remove(uri)
        switch result {
        case .success(let image):
          self.photos[uri] = image
          for (id, m) in self.markerData where m.imageUri == uri || self.markerOptions(id)["pin"]["glyphImageUri"].string == uri {
            if let gm = self.gmsMarkers[id] {
              self.configure(gm, m, extras: self.markerOptions(id), isNew: false)
            }
          }
          self.applyGoogleImages(uri)
        case .failure(let error):
          self.onError?("Google Maps: could not load the image \(uri): \(error.localizedDescription)")
        }
      }
    }
  }

  // MARK: Selection

  /// Returns true: the engine handles selection (Google would otherwise
  /// also move the camera to the marker).
  func markerTapped(_ marker: GMSMarker) -> Bool {
    if let cluster = marker.userData as? GMUCluster {
      let ids = cluster.items.compactMap { ($0 as? GMSMarker)?.userData as? String }
      let clusterId = ids.lazy.compactMap { self.clusterIds[$0] }.first ?? ""
      onClusterPress?(clusterId, ids, cluster.position)
      emit("clusterPress", ["clusteringId": clusterId, "markerIds": ids,
                            "latitude": cluster.position.latitude, "longitude": cluster.position.longitude])
      return true
    }
    guard let id = marker.userData as? String else { return false }
    if let previous = selectedMarkerId, previous != id { onMarkerDeselect?(previous) }
    selectedMarkerId = id
    onMarkerPress?(id)
    mapView?.selectedMarker = marker.title != nil || marker.snippet != nil ? marker : nil
    return true
  }

  public func selectMarker(_ id: String) {
    guard let marker = gmsMarkers[id] else { return }
    if let previous = selectedMarkerId, previous != id { onMarkerDeselect?(previous) }
    selectedMarkerId = id
    mapView?.selectedMarker = marker.title != nil || marker.snippet != nil ? marker : nil
  }

  public func deselectMarker(_ id: String) {
    guard selectedMarkerId == id else { return }
    selectedMarkerId = nil
    mapView?.selectedMarker = nil
    onMarkerDeselect?(id)
  }

  // MARK: Info windows

  /// A custom info window when the marker has a callout detail or
  /// accessories (or `google.markers[id].infoWindow`); nil for Google's own.
  func infoWindow(for marker: GMSMarker) -> UIView? {
    guard let id = marker.userData as? String, let m = markerData[id] else { return nil }
    let style = markerOptions(id)["infoWindow"]
    let custom = style.exists || !m.calloutDetail.isEmpty || m.leftCalloutAccessory.kind != .none
      || ![.none, .detail].contains(m.rightCalloutAccessory.kind)
    guard custom else { return nil }
    return GoogleMarkerIcons.infoWindow(
      title: m.title, detail: m.calloutDetail.isEmpty ? m.subtitle : m.calloutDetail,
      left: accessoryImage(m.leftCalloutAccessory), right: accessoryImage(m.rightCalloutAccessory),
      rightText: m.rightCalloutAccessory.kind == .button ? m.rightCalloutAccessory.text : "",
      background: style["backgroundColor"].color ?? .systemBackground,
      textColor: style["textColor"].color ?? .label,
      maxWidth: CGFloat(style["maxWidth"].double(260)))
  }

  private func accessoryImage(_ accessory: MunimCalloutAccessory) -> UIImage? {
    let tint = UIColor(mapModelHex: accessory.color) ?? tintColor ?? .systemBlue
    switch accessory.kind {
    case .none: return nil
    case .detail: return UIImage(systemName: "chevron.right.circle")?.withTintColor(tint, renderingMode: .alwaysOriginal)
    case .info: return UIImage(systemName: "info.circle")?.withTintColor(tint, renderingMode: .alwaysOriginal)
    case .button, .image:
      if !accessory.symbol.isEmpty {
        return UIImage(systemName: accessory.symbol)?.withTintColor(tint, renderingMode: .alwaysOriginal)
      }
      if !accessory.imageUri.isEmpty {
        if let photo = photos[accessory.imageUri] { return photo }
        loadPhoto(accessory.imageUri)
      }
      return nil
    }
  }

  // MARK: Clustering

  func clusterManager(for clusterId: String, mapView: GMSMapView) -> GMUClusterManager {
    if let manager = clusterManagers[clusterId] { return manager }
    let algorithm: GMUClusterAlgorithm
    switch options["clusterAlgorithm"].string {
    case "gridBased": algorithm = GMUGridBasedClusterAlgorithm()
    case "simple": algorithm = GMUSimpleClusterAlgorithm()
    default: algorithm = GMUNonHierarchicalDistanceBasedAlgorithm()
    }
    let generator = GoogleClusterIconGenerator(engine: self, clusterId: clusterId)
    let renderer = GMUDefaultClusterRenderer(mapView: mapView, clusterIconGenerator: generator)
    renderer.animatesClusters = options["animatesClusters"].bool(true)
    if let size = options["clusterMinimumSize"].double { renderer.minimumClusterSize = UInt(max(2, size)) }
    if let zoom = options["clusterMaxZoom"].double { renderer.maximumClusterZoom = UInt(max(0, zoom)) }
    let manager = GMUClusterManager(map: mapView, algorithm: algorithm, renderer: renderer)
    clusterManagers[clusterId] = manager
    return manager
  }

  func reclusterAll() {
    for manager in clusterManagers.values { manager.cluster() }
  }

  func clusterStyle(_ clusterId: String) -> MunimClusterStyle? {
    clusterStyles.first { $0.clusteringId == clusterId }
  }
}

/// Cluster balloons in the cluster's `clusterStyles` colours, with the
/// count or the style's glyph (`{count}` is the count).
final class GoogleClusterIconGenerator: NSObject, GMUClusterIconGenerator {
  private weak var engine: GoogleMapEngine?
  private let clusterId: String

  init(engine: GoogleMapEngine, clusterId: String) {
    self.engine = engine
    self.clusterId = clusterId
  }

  func icon(forSize size: UInt) -> UIImage {
    let style = engine?.clusterStyle(clusterId)
    let text = (style?.glyph.isEmpty ?? true) ? "\(size)" : style!.glyph.replacingOccurrences(of: "{count}", with: "\(size)")
    return GoogleMarkerIcons.cluster(
      text: text,
      color: style.flatMap { UIColor(mapModelHex: $0.color) } ?? UIColor(red: 0.04, green: 0.52, blue: 1, alpha: 1),
      textColor: style.flatMap { UIColor(mapModelHex: $0.glyphColor) } ?? .white,
      count: Int(size), scale: engine?.window?.screen.scale ?? UIScreen.main.scale)
  }
}

/// Pictures the Google engine draws itself.
enum GoogleMarkerIcons {
  static let transparent = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image { _ in }

  /// A balloon pin with a glyph (for `style: 'marker'` without a Map ID).
  static func balloon(color: UIColor, glyph: String, glyphColor: UIColor, scale: CGFloat) -> UIImage {
    let size = CGSize(width: 30, height: 42)
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
      let cg = context.cgContext
      let r: CGFloat = 14
      let center = CGPoint(x: size.width / 2, y: r + 1)
      let path = UIBezierPath()
      path.addArc(withCenter: center, radius: r, startAngle: .pi * 0.8, endAngle: .pi * 0.2, clockwise: true)
      path.addQuadCurve(to: CGPoint(x: size.width / 2, y: size.height - 1), controlPoint: CGPoint(x: center.x + 4, y: center.y + r + 6))
      path.addQuadCurve(to: CGPoint(x: center.x + r * cos(.pi * 0.8), y: center.y + r * sin(.pi * 0.8)),
                        controlPoint: CGPoint(x: center.x - 4, y: center.y + r + 6))
      path.close()
      cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor.black.withAlphaComponent(0.35).cgColor)
      color.setFill()
      path.fill()
      cg.setShadow(offset: .zero, blur: 0, color: nil)
      UIColor.black.withAlphaComponent(0.2).setStroke()
      path.lineWidth = 1
      path.stroke()
      let font = UIFont.systemFont(ofSize: glyph.count > 2 ? 10 : 14, weight: .semibold)
      let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: glyphColor]
      let text = glyph as NSString
      let textSize = text.size(withAttributes: attributes)
      text.draw(at: CGPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2), withAttributes: attributes)
    }
  }

  static func cluster(text: String, color: UIColor, textColor: UIColor, count: Int, scale: CGFloat) -> UIImage {
    let diameter: CGFloat = count < 10 ? 34 : count < 100 ? 40 : count < 1000 ? 46 : 52
    let font = UIFont.systemFont(ofSize: diameter * 0.36, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
    let textSize = (text as NSString).size(withAttributes: attributes)
    let width = max(diameter, textSize.width + 16)
    let size = CGSize(width: width + 4, height: diameter + 4)
    let format = UIGraphicsImageRendererFormat()
    format.scale = scale
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
      let rect = CGRect(x: 2, y: 2, width: width, height: diameter)
      let path = UIBezierPath(roundedRect: rect, cornerRadius: diameter / 2)
      context.cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: UIColor.black.withAlphaComponent(0.3).cgColor)
      color.setFill()
      path.fill()
      context.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
      UIColor.white.setStroke()
      path.lineWidth = 2
      path.stroke()
      (text as NSString).draw(
        at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2), withAttributes: attributes)
    }
  }

  /// A callout: title, detail lines and accessories. Google draws info
  /// windows as pictures, so the whole window is one tap (`onCalloutPress`).
  static func infoWindow(
    title: String, detail: String, left: UIImage?, right: UIImage?, rightText: String,
    background: UIColor, textColor: UIColor, maxWidth: CGFloat
  ) -> UIView {
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 10
    if let left {
      let view = UIImageView(image: left)
      view.contentMode = .scaleAspectFit
      view.widthAnchor.constraint(equalToConstant: 28).isActive = true
      view.heightAnchor.constraint(equalToConstant: 28).isActive = true
      stack.addArrangedSubview(view)
    }
    let texts = UIStackView()
    texts.axis = .vertical
    texts.spacing = 2
    if !title.isEmpty {
      let label = UILabel()
      label.text = title
      label.font = .preferredFont(forTextStyle: .headline)
      label.textColor = textColor
      label.numberOfLines = 2
      texts.addArrangedSubview(label)
    }
    if !detail.isEmpty {
      let label = UILabel()
      label.text = detail
      label.font = .preferredFont(forTextStyle: .subheadline)
      label.textColor = textColor.withAlphaComponent(0.75)
      label.numberOfLines = 0
      texts.addArrangedSubview(label)
    }
    stack.addArrangedSubview(texts)
    if !rightText.isEmpty {
      let label = UILabel()
      label.text = rightText
      label.font = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
      label.textColor = .systemBlue
      stack.addArrangedSubview(label)
    } else if let right {
      let view = UIImageView(image: right)
      view.contentMode = .scaleAspectFit
      view.widthAnchor.constraint(equalToConstant: 24).isActive = true
      view.heightAnchor.constraint(equalToConstant: 24).isActive = true
      stack.addArrangedSubview(view)
    }
    let container = UIView()
    container.backgroundColor = background
    container.layer.cornerRadius = 12
    container.layer.borderColor = UIColor.separator.cgColor
    container.layer.borderWidth = 0.5
    stack.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
      stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
      stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
      stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
      container.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
    ])
    let size = container.systemLayoutSizeFitting(
      CGSize(width: maxWidth, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .fittingSizeLevel, verticalFittingPriority: .fittingSizeLevel)
    container.frame = CGRect(origin: .zero, size: CGSize(width: min(maxWidth, size.width), height: size.height))
    container.layoutIfNeeded()
    return container
  }
}

private extension UIFont {
  func withWeight(_ weight: UIFont.Weight) -> UIFont {
    UIFont.systemFont(ofSize: pointSize, weight: weight)
  }
}
#endif
