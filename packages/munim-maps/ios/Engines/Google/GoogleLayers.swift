#if canImport(GoogleMaps)
import GoogleMaps
import GoogleMapsUtils
import UIKit

// KML and GeoJSON layers (Google Maps Utils) and data-driven styling of
// Google's boundaries and datasets (feature layers, needs a Map ID).

extension GoogleMapEngine {
  // MARK: Loading

  /// The bytes of a layer: inline `data` / `geojson`, or `url` / `uri`.
  private func loadLayerData(_ item: GoogleJSON, inline: String, completion: @escaping (Data?) -> Void) {
    switch item[inline].raw {
    case let text as String:
      return completion(Data(text.utf8))
    case let object as [String: Any]:
      return completion(try? JSONSerialization.data(withJSONObject: object))
    default:
      break
    }
    guard let text = item["url"].string ?? item["uri"].string else { return completion(nil) }
    let url = text.hasPrefix("/") ? URL(fileURLWithPath: text) : URL(string: text)
    guard let url else { return completion(nil) }
    URLSession.shared.dataTask(with: url) { data, _, _ in
      DispatchQueue.main.async { completion(data) }
    }.resume()
  }

  private static func sourceKey(_ item: GoogleJSON) -> String {
    String(describing: item.raw ?? "")
  }

  // MARK: KML

  /// `google.kmlLayers`: `[{ id, url | uri | data }]`, drawn with KML styles.
  func applyKmlLayers() {
    guard let mapView else { return }
    var wanted = Set<String>()
    for item in options["kmlLayers"].array {
      guard let id = item["id"].string else { continue }
      wanted.insert(id)
      let key = Self.sourceKey(item)
      guard kmlSources[id] != key else { continue }
      kmlSources[id] = key
      kmlRenderers[id]?.clear()
      kmlRenderers[id] = nil
      loadLayerData(item, inline: "data") { [weak self] data in
        guard let self, self.kmlSources[id] == key, let mapView = self.mapView else { return }
        guard let data else {
          self.onError?("Google Maps: could not load the KML layer \(id)")
          return
        }
        let parser = GMUKMLParser(data: data)
        parser.parse()
        let renderer = GMUGeometryRenderer(
          map: mapView, geometries: parser.placemarks, styles: parser.styles, styleMaps: parser.styleMaps)
        renderer.render()
        Self.overlays(of: renderer).forEach { overlay in
          overlay.userData = ["kind": "kml", "layer": id]
          overlay.zIndex = Int32(clamping: Int(item["zIndex"].double(Double(overlay.zIndex))))
        }
        self.kmlRenderers[id] = renderer
        self.emit("kmlLayerLoaded", ["id": id, "placemarks": parser.placemarks.count])
      }
    }
    for (id, renderer) in kmlRenderers where !wanted.contains(id) {
      renderer.clear()
      kmlRenderers[id] = nil
    }
    for id in kmlSources.keys where !wanted.contains(id) { kmlSources[id] = nil }
    _ = mapView
  }

  /// The overlays a geometry renderer put on the map (its `mapOverlays`).
  private static func overlays(of renderer: GMUGeometryRenderer) -> [GMSOverlay] {
    let selector = NSSelectorFromString("mapOverlays")
    guard renderer.responds(to: selector) else { return [] }
    return renderer.perform(selector)?.takeUnretainedValue() as? [GMSOverlay] ?? []
  }

  // MARK: GeoJSON

  /// `google.geoJsonLayers`: `[{ id, geojson | url | uri, style }]`. Each
  /// feature's simplestyle properties (`stroke`, `stroke-width`, `fill`,
  /// `fill-opacity`, `marker-color`, `title`) override the layer's style.
  func applyGeoJsonLayers() {
    var wanted = Set<String>()
    for item in options["geoJsonLayers"].array {
      guard let id = item["id"].string else { continue }
      wanted.insert(id)
      let key = Self.sourceKey(item)
      guard geoJsonSources[id] != key else { continue }
      geoJsonSources[id] = key
      geoJsonOverlays[id]?.forEach { $0.map = nil }
      geoJsonOverlays[id] = nil
      loadLayerData(item, inline: "geojson") { [weak self] data in
        guard let self, self.geoJsonSources[id] == key, let mapView = self.mapView else { return }
        guard let data else {
          self.onError?("Google Maps: could not load the GeoJSON layer \(id)")
          return
        }
        let parser = GMUGeoJSONParser(data: data)
        parser.parse()
        var overlays: [GMSOverlay] = []
        for case let feature as GMUFeature in parser.features {
          overlays += self.render(feature: feature, layer: id, style: item["style"], on: mapView)
        }
        self.geoJsonOverlays[id] = overlays
        self.emit("geoJsonLayerLoaded", ["id": id, "features": parser.features.count])
      }
    }
    for (id, overlays) in geoJsonOverlays where !wanted.contains(id) {
      overlays.forEach { $0.map = nil }
      geoJsonOverlays[id] = nil
    }
    for id in geoJsonSources.keys where !wanted.contains(id) { geoJsonSources[id] = nil }
  }

  private func render(feature: GMUFeature, layer: String, style: GoogleJSON, on mapView: GMSMapView) -> [GMSOverlay] {
    let properties = feature.properties ?? [:]
    let props = GoogleJSON(properties)
    func color(_ key: String, opacity: String, fallback: UIColor?) -> UIColor? {
      guard let base = props[key].color ?? fallback else { return nil }
      if let alpha = props[opacity].double { return base.withAlphaComponent(alpha) }
      return base
    }
    let stroke = color("stroke", opacity: "stroke-opacity", fallback: style["strokeColor"].color ?? .systemBlue)
    let fill = color("fill", opacity: "fill-opacity",
                     fallback: style["fillColor"].color ?? UIColor.systemBlue.withAlphaComponent(0.25))
    let width = CGFloat(props["stroke-width"].double ?? style["strokeWidth"].double(2))
    let zIndex = Int32(clamping: Int(style["zIndex"].double(0)))
    let geodesic = style["geodesic"].bool(false)
    let tappable = style["tappable"].bool(true)
    let info: [String: Any] = ["kind": "geojson", "layer": layer, "feature": feature.identifier ?? "",
                               "properties": GoogleMapEngine.jsonSafe(properties)]
    let title = props["title"].string ?? props["name"].string

    func draw(_ geometry: GMUGeometry) -> [GMSOverlay] {
      switch geometry {
      case let point as GMUPoint:
        let marker = GMSMarker(position: point.coordinate)
        marker.icon = GMSMarker.markerImage(with: props["marker-color"].color ?? style["pointColor"].color)
        marker.title = title
        marker.userData = info
        marker.zIndex = zIndex
        marker.map = mapView
        return [marker]
      case let line as GMULineString:
        let polyline = GMSPolyline(path: line.path)
        polyline.strokeColor = stroke ?? .systemBlue
        polyline.strokeWidth = width
        polyline.geodesic = geodesic
        polyline.zIndex = zIndex
        polyline.isTappable = tappable
        polyline.title = title
        polyline.userData = info
        polyline.map = mapView
        return [polyline]
      case let polygon as GMUPolygon:
        guard let outer = polygon.paths.first else { return [] }
        let shape = GMSPolygon(path: outer)
        shape.holes = Array(polygon.paths.dropFirst())
        shape.strokeColor = stroke
        shape.fillColor = fill
        shape.strokeWidth = width
        shape.geodesic = geodesic
        shape.zIndex = zIndex
        shape.isTappable = tappable
        shape.title = title
        shape.userData = info
        shape.map = mapView
        return [shape]
      case let collection as GMUGeometryCollection:
        return collection.geometries.flatMap(draw)
      default:
        return []
      }
    }
    return draw(feature.geometry)
  }

  /// Property values that JSONSerialization accepts.
  static func jsonSafe(_ value: Any) -> Any {
    switch value {
    case let dictionary as [String: Any]: return dictionary.mapValues(jsonSafe)
    case let array as [Any]: return array.map(jsonSafe)
    case is String, is NSNumber, is NSNull: return value
    default: return String(describing: value)
    }
  }

  // MARK: Feature layers (data-driven styling)

  /// `google.featureLayers`: style Google's boundaries (`featureType`:
  /// `COUNTRY`, `ADMINISTRATIVE_AREA_LEVEL_1`, `ADMINISTRATIVE_AREA_LEVEL_2`,
  /// `LOCALITY`, `POSTAL_CODE`, `SCHOOL_DISTRICT`) or a dataset
  /// (`datasetId`). Needs a Map ID whose style has those layers on.
  func applyFeatureLayers() {
    guard let mapView else { return }
    var wanted: [String: String] = [:]
    for item in options["featureLayers"].array {
      let styles = GoogleFeatureStyles(item)
      if let datasetId = item["datasetId"].string {
        let key = "dataset:\(datasetId)"
        wanted[key] = Self.sourceKey(item)
        guard featureLayerIds[key] != wanted[key] else { continue }
        let layer = mapView.datasetFeatureLayer(of: datasetId)
        if !layer.isAvailable { reportFeatureLayerUnavailable(key) }
        layer.style = { feature in styles.style(placeId: nil, attributes: feature.datasetAttributes) }
      } else if let type = Self.featureType(item["featureType"].string ?? "") {
        let key = "type:\(type.rawValue)"
        wanted[key] = Self.sourceKey(item)
        guard featureLayerIds[key] != wanted[key] else { continue }
        let layer = mapView.featureLayer(of: type)
        if !layer.isAvailable { reportFeatureLayerUnavailable(key) }
        layer.style = { feature in styles.style(placeId: feature.placeID, attributes: [:]) }
      }
    }
    for key in featureLayerIds.keys where wanted[key] == nil {
      if key.hasPrefix("dataset:") {
        mapView.datasetFeatureLayer(of: String(key.dropFirst("dataset:".count))).style = nil
      } else if let type = Self.featureType(String(key.dropFirst("type:".count))) {
        mapView.featureLayer(of: type).style = nil
      }
    }
    featureLayerIds = wanted
  }

  private func reportFeatureLayerUnavailable(_ key: String) {
    onError?("Google Maps: the feature layer \(key) is not available. It needs a mapId whose map style has it turned on (Cloud console)")
  }

  static func featureType(_ name: String) -> FeatureType? {
    switch name.uppercased().replacingOccurrences(of: "-", with: "_") {
    case "COUNTRY": return .country
    case "ADMINISTRATIVE_AREA_LEVEL_1", "ADMINISTRATIVEAREALEVEL1": return .administrativeAreaLevel1
    case "ADMINISTRATIVE_AREA_LEVEL_2", "ADMINISTRATIVEAREALEVEL2": return .administrativeAreaLevel2
    case "LOCALITY": return .locality
    case "POSTAL_CODE", "POSTALCODE": return .postalCode
    case "SCHOOL_DISTRICT", "SCHOOLDISTRICT": return .schoolDistrict
    default: return nil
    }
  }

  func featuresTapped(_ features: [Feature], layer: FeatureLayer<Feature>, at location: CLLocationCoordinate2D) {
    let list: [[String: Any]] = features.map { feature in
      var entry: [String: Any] = ["featureType": feature.featureType().rawValue]
      if let place = feature as? PlaceFeature { entry["placeId"] = place.placeID }
      if let dataset = feature as? DatasetFeature {
        entry["datasetId"] = dataset.datasetID
        entry["attributes"] = dataset.datasetAttributes
      }
      return entry
    }
    emit("featureClick", ["featureType": layer.featureType.rawValue, "features": list,
                          "latitude": location.latitude, "longitude": location.longitude])
  }
}

/// A feature layer's styles: `style` for every feature, `placeStyles`
/// by place ID, and for datasets `attributeStyles` (`{ attribute, values }`).
struct GoogleFeatureStyles {
  let base: FeatureStyle?
  let byPlace: [String: FeatureStyle]
  let attribute: String?
  let byValue: [String: FeatureStyle]

  init(_ item: GoogleJSON) {
    base = item["style"].exists ? Self.style(item["style"]) : nil
    var places: [String: FeatureStyle] = [:]
    for key in item["placeStyles"].keys { places[key] = Self.style(item["placeStyles"][key]) }
    byPlace = places
    attribute = item["attributeStyles"]["attribute"].string
    var values: [String: FeatureStyle] = [:]
    for key in item["attributeStyles"]["values"].keys {
      values[key] = Self.style(item["attributeStyles"]["values"][key])
    }
    byValue = values
  }

  func style(placeId: String?, attributes: [String: String]) -> FeatureStyle? {
    if let placeId, let style = byPlace[placeId] { return style }
    if let attribute, let value = attributes[attribute], let style = byValue[value] { return style }
    return base
  }

  static func style(_ json: GoogleJSON) -> FeatureStyle {
    let style = MutableFeatureStyle()
    style.fillColor = json["fillColor"].color
    style.strokeColor = json["strokeColor"].color
    if let width = json["strokeWidth"].double { style.strokeWidth = CGFloat(width) }
    if let radius = json["pointRadius"].double { style.pointRadius = CGFloat(radius) }
    return style
  }
}
#endif
