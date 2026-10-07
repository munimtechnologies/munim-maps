#if canImport(MapLibre)
import Foundation
import MapLibre
import UIKit

/// MapLibre style-spec JSON (sources, layers, properties, filters) onto
/// MapLibre iOS's runtime styling API.
///
/// Property values go through `NSExpression(mglJSONObject:)`. Plain values
/// are wrapped in a `let` expression first, so the SDK hands them to the
/// native style parser as JSON (which coerces colours from strings and
/// reads enums by name) instead of its typed constant path, which expects
/// `UIColor`s and `NSValue`s. Style-spec names map to the SDK's key-value
/// names (`text-field` → `text`, `line-dasharray` → `lineDashPattern`…);
/// unknown names and malformed expressions are reported instead of raising
/// Objective-C exceptions.
enum MapLibreStyleSpec {
  struct SpecError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
  }

  /// Style-spec property names whose key-value name is not the camel-cased name.
  private static let renamed: [String: String] = [
    "circle-pitch-scale": "circleScaleAlignment",
    "circle-translate": "circleTranslation",
    "circle-translate-anchor": "circleTranslationAnchor",
    "fill-antialias": "fillAntialiased",
    "fill-translate": "fillTranslation",
    "fill-translate-anchor": "fillTranslationAnchor",
    "fill-extrusion-translate": "fillExtrusionTranslation",
    "fill-extrusion-translate-anchor": "fillExtrusionTranslationAnchor",
    "fill-extrusion-vertical-gradient": "fillExtrusionHasVerticalGradient",
    "icon-allow-overlap": "iconAllowsOverlap",
    "icon-ignore-placement": "iconIgnoresPlacement",
    "icon-image": "iconImageName",
    "icon-keep-upright": "keepsIconUpright",
    "icon-rotate": "iconRotation",
    "icon-size": "iconScale",
    "icon-translate": "iconTranslation",
    "icon-translate-anchor": "iconTranslationAnchor",
    "line-dasharray": "lineDashPattern",
    "line-translate": "lineTranslation",
    "line-translate-anchor": "lineTranslationAnchor",
    "raster-brightness-min": "minimumRasterBrightness",
    "raster-brightness-max": "maximumRasterBrightness",
    "raster-hue-rotate": "rasterHueRotation",
    "raster-resampling": "rasterResamplingMode",
    "symbol-avoid-edges": "symbolAvoidsEdges",
    "text-allow-overlap": "textAllowsOverlap",
    "text-field": "text",
    "text-font": "textFontNames",
    "text-ignore-placement": "textIgnoresPlacement",
    "text-justify": "textJustification",
    "text-keep-upright": "keepsTextUpright",
    "text-max-angle": "maximumTextAngle",
    "text-max-width": "maximumTextWidth",
    "text-rotate": "textRotation",
    "text-size": "textFontSize",
    "text-translate": "textTranslation",
    "text-translate-anchor": "textTranslationAnchor",
    "text-writing-mode": "textWritingModes",
    "heatmap-intensity": "heatmapIntensity",
  ]

  /// Expression operators of the style spec: an array starting with one of
  /// these is an expression; any other array is a literal.
  private static let operators: Set<String> = [
    "let", "var", "literal", "array", "at", "in", "index-of", "slice", "case", "match", "coalesce", "step",
    "interpolate", "interpolate-hcl", "interpolate-lab", "ln2", "pi", "e", "typeof", "string", "number",
    "number-format", "boolean", "object", "collator", "format", "image", "to-boolean", "to-color", "to-number",
    "to-string", "to-rgba", "rgb", "rgba", "get", "has", "length", "properties", "feature-state", "geometry-type",
    "id", "zoom", "heatmap-density", "line-progress", "accumulated", "elevation", "+", "*", "-", "/", "%", "^",
    "sqrt", "log10", "ln", "log2", "sin", "cos", "tan", "asin", "acos", "atan", "min", "max", "round", "abs",
    "ceil", "floor", "distance", "within", "==", "!=", ">", "<", ">=", "<=", "all", "any", "!", "is-supported-script",
    "upcase", "downcase", "concat", "resolved-locale", "split", "join", "global-state", "semiliteral",
    "config", "!has", "!in", "none",
  ]

  static func isExpression(_ value: Any) -> Bool {
    guard let array = value as? [Any], let op = array.first as? String else { return false }
    return operators.contains(op)
  }

  /// The SDK's key-value name for a style-spec property.
  static func key(for property: String) -> String {
    if let name = renamed[property] { return name }
    var out = ""
    var upper = false
    for c in property {
      if c == "-" {
        upper = true
      } else {
        out.append(upper ? Character(c.uppercased()) : c)
        upper = false
      }
    }
    return out
  }

  /// A property value as an expression the SDK sends to the style parser.
  static func expression(_ value: Any) -> NSExpression {
    if isExpression(value) { return NSExpression(mglJSONObject: value) }
    let literal: Any = (value is [Any] || value is [String: Any]) ? ["literal", value] : value
    return NSExpression(mglJSONObject: ["let", "munim", literal, ["var", "munim"]])
  }

  static func setProperty(_ layer: MLNStyleLayer, name: String, value: Any?) throws {
    if name == "visibility" {
      layer.isVisible = (value as? String) != "none"
      return
    }
    let key = key(for: name)
    let setter = NSSelectorFromString("set\(key.prefix(1).uppercased())\(key.dropFirst()):")
    guard layer.responds(to: setter) else {
      throw SpecError(message: "\(type(of: layer)) has no property '\(name)'")
    }
    if let value, !(value is NSNull) {
      layer.setValue(expression(value), forKey: key)
    } else {
      layer.setValue(nil, forKey: key)
    }
  }

  static func setProperties(_ layer: MLNStyleLayer, _ properties: [String: Any]) throws {
    for (name, value) in properties { try setProperty(layer, name: name, value: value) }
  }

  static func setFilter(_ layer: MLNStyleLayer, _ filter: Any?) throws {
    guard let vector = layer as? MLNVectorStyleLayer else { throw SpecError(message: "\(layer.identifier) has no filter") }
    guard let filter, !(filter is NSNull) else {
      vector.predicate = nil
      return
    }
    guard isExpression(filter) else { throw SpecError(message: "the filter must be an expression") }
    vector.predicate = NSPredicate(mglJSONObject: filter)
  }

  private static func number(_ value: Any?) -> Double? {
    (value as? NSNumber)?.doubleValue
  }

  private static func tileOptions(_ json: [String: Any]) -> [MLNTileSourceOption: Any] {
    var options: [MLNTileSourceOption: Any] = [:]
    if let v = number(json["minzoom"]) { options[.minimumZoomLevel] = v }
    if let v = number(json["maxzoom"]) { options[.maximumZoomLevel] = v }
    if let v = number(json["tileSize"]) { options[.tileSize] = v }
    if let b = json["bounds"] as? [NSNumber], b.count == 4 {
      let bounds = MLNCoordinateBounds(
        sw: CLLocationCoordinate2D(latitude: b[1].doubleValue, longitude: b[0].doubleValue),
        ne: CLLocationCoordinate2D(latitude: b[3].doubleValue, longitude: b[2].doubleValue))
      options[.coordinateBounds] = NSValue(mlnCoordinateBounds: bounds)
    }
    if let attribution = json["attribution"] as? String { options[.attributionHTMLString] = attribution }
    if (json["scheme"] as? String) == "tms" {
      options[.tileCoordinateSystem] = NSNumber(value: MLNTileCoordinateSystem.TMS.rawValue)
    }
    switch json["encoding"] as? String {
    case "terrarium": options[.demEncoding] = NSNumber(value: MLNDEMEncoding.terrarium.rawValue)
    case "mapbox": options[.demEncoding] = NSNumber(value: MLNDEMEncoding.mapbox.rawValue)
    case "mlt": options[.vectorTileSourceOptionEncoding] = NSNumber(value: MLNVectorTileSourceEncoding.MLT.rawValue)
    default: break
    }
    return options
  }

  /// GeoJSON (object, string or URL) as an `MLNShape`.
  static func shape(_ data: Any?) throws -> MLNShape? {
    let json: Data
    switch data {
    case let string as String:
      guard string.trimmingCharacters(in: .whitespaces).hasPrefix("{") else { return nil }
      json = Data(string.utf8)
    case let object as [String: Any]:
      json = try JSONSerialization.data(withJSONObject: object)
    default:
      return MLNShapeCollectionFeature(shapes: [])
    }
    return try MLNShape(data: json, encoding: String.Encoding.utf8.rawValue)
  }

  /// A style-spec source object as a MapLibre source.
  static func source(id: String, _ json: [String: Any]) throws -> MLNSource {
    let type = json["type"] as? String ?? ""
    let url = json["url"] as? String
    let tiles = json["tiles"] as? [String] ?? []
    let options = tileOptions(json)
    switch type {
    case "vector":
      if !tiles.isEmpty { return MLNVectorTileSource(identifier: id, tileURLTemplates: tiles, options: options) }
      guard let url else { throw SpecError(message: "vector source '\(id)' needs url or tiles") }
      return MLNVectorTileSource(identifier: id, configurationURLString: url)
    case "raster":
      if !tiles.isEmpty { return MLNRasterTileSource(identifier: id, tileURLTemplates: tiles, options: options) }
      guard let url, let u = URL(string: url) else { throw SpecError(message: "raster source '\(id)' needs url or tiles") }
      return MLNRasterTileSource(identifier: id, configurationURL: u, tileSize: CGFloat(number(json["tileSize"]) ?? 512))
    case "raster-dem":
      if !tiles.isEmpty { return MLNRasterDEMSource(identifier: id, tileURLTemplates: tiles, options: options) }
      guard let url, let u = URL(string: url) else { throw SpecError(message: "raster-dem source '\(id)' needs url or tiles") }
      return MLNRasterDEMSource(identifier: id, configurationURL: u, tileSize: CGFloat(number(json["tileSize"]) ?? 512))
    case "geojson":
      var shapeOptions: [MLNShapeSourceOption: Any] = [:]
      if let v = json["cluster"] as? Bool { shapeOptions[.clustered] = v }
      if let v = number(json["clusterRadius"]) { shapeOptions[.clusterRadius] = v }
      if let v = number(json["clusterMaxZoom"]) { shapeOptions[.maximumZoomLevelForClustering] = v }
      if let v = number(json["clusterMinPoints"]) { shapeOptions[.clusterMinPoints] = v }
      if let v = json["lineMetrics"] as? Bool { shapeOptions[.lineDistanceMetrics] = v }
      if let v = number(json["tolerance"]) { shapeOptions[.simplificationTolerance] = v }
      if let v = number(json["buffer"]) { shapeOptions[.buffer] = v }
      if let v = number(json["maxzoom"]) { shapeOptions[.maximumZoomLevel] = v }
      if let v = number(json["minzoom"]) { shapeOptions[.minimumZoomLevel] = v }
      if let string = json["data"] as? String, !string.trimmingCharacters(in: .whitespaces).hasPrefix("{"),
         let u = URL(string: string) {
        return MLNShapeSource(identifier: id, url: u, options: shapeOptions)
      }
      return MLNShapeSource(identifier: id, shape: try shape(json["data"]), options: shapeOptions)
    case "image":
      guard let corners = json["coordinates"] as? [[NSNumber]], corners.count == 4, let url, let u = URL(string: url) else {
        throw SpecError(message: "image source '\(id)' needs url and four coordinates")
      }
      func c(_ i: Int) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: corners[i][1].doubleValue, longitude: corners[i][0].doubleValue)
      }
      let quad = MLNCoordinateQuad(topLeft: c(0), bottomLeft: c(3), bottomRight: c(2), topRight: c(1))
      return MLNImageSource(identifier: id, coordinateQuad: quad, url: u)
    default:
      throw SpecError(message: "unknown source type '\(type)' for '\(id)'")
    }
  }

  /// A style-spec layer object as a MapLibre layer (not added yet).
  static func layer(_ json: [String: Any], in style: MLNStyle) throws -> MLNStyleLayer {
    guard let id = json["id"] as? String else { throw SpecError(message: "a layer needs an id") }
    let type = json["type"] as? String ?? ""
    let layer: MLNStyleLayer
    if type == "background" {
      layer = MLNBackgroundStyleLayer(identifier: id)
    } else {
      guard let sourceId = json["source"] as? String, let source = style.source(withIdentifier: sourceId) else {
        throw SpecError(message: "layer '\(id)' needs a source in the style")
      }
      switch type {
      case "fill": layer = MLNFillStyleLayer(identifier: id, source: source)
      case "line": layer = MLNLineStyleLayer(identifier: id, source: source)
      case "symbol": layer = MLNSymbolStyleLayer(identifier: id, source: source)
      case "circle": layer = MLNCircleStyleLayer(identifier: id, source: source)
      case "heatmap": layer = MLNHeatmapStyleLayer(identifier: id, source: source)
      case "fill-extrusion": layer = MLNFillExtrusionStyleLayer(identifier: id, source: source)
      case "raster": layer = MLNRasterStyleLayer(identifier: id, source: source)
      case "hillshade": layer = MLNHillshadeStyleLayer(identifier: id, source: source)
      case "color-relief": layer = MLNColorReliefStyleLayer(identifier: id, source: source)
      default: throw SpecError(message: "unknown layer type '\(type)' for '\(id)'")
      }
    }
    if let sourceLayer = json["source-layer"] as? String, let vector = layer as? MLNVectorStyleLayer {
      vector.sourceLayerIdentifier = sourceLayer
    }
    if let v = number(json["minzoom"]) { layer.minimumZoomLevel = Float(v) }
    if let v = number(json["maxzoom"]) { layer.maximumZoomLevel = Float(v) }
    if let filter = json["filter"] { try setFilter(layer, filter) }
    if let layout = json["layout"] as? [String: Any] { try setProperties(layer, layout) }
    if let paint = json["paint"] as? [String: Any] { try setProperties(layer, paint) }
    return layer
  }

  /// Adds a layer below `beforeId` when it exists, else below `fallback`, else on top.
  static func add(_ layer: MLNStyleLayer, to style: MLNStyle, below beforeId: String?, fallback: String?) {
    if let beforeId, !beforeId.isEmpty, let sibling = style.layer(withIdentifier: beforeId) {
      style.insertLayer(layer, below: sibling)
    } else if let fallback, let sibling = style.layer(withIdentifier: fallback) {
      style.insertLayer(layer, below: sibling)
    } else {
      style.addLayer(layer)
    }
  }

  /// A feature as GeoJSON.
  static func json(_ feature: MLNFeature) -> Any {
    feature.geoJSONDictionary()
  }
}
#endif
