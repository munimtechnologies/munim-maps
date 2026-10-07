import CoreLocation
import MapKit
import NitroModules
import UIKit

// Nitro's generated prop types → the plain Swift types in Core.

extension CLLocationCoordinate2D {
  init(_ c: MapCoordinate) {
    self.init(latitude: c.latitude, longitude: c.longitude)
  }
}

extension NativeMapModel {
  var core: MunimModel {
    var model = MunimModel(
      id: id, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
      altitude: altitude, heading: heading, scale: scale, uri: uri,
      shape: MunimShape(rawValue: shape.stringValue) ?? .box,
      width: width, height: height, length: length, color: color, tintColor: tintColor,
      emissive: emissive, spinDegreesPerSecond: spinDegreesPerSecond, playAnimations: playAnimations,
      screenSize: screenSize, groundShadow: groundShadow, imageUri: imageUri,
      imageBorderColor: imageBorderColor, imageBorderWidth: imageBorderWidth, imageBadge: imageBadge,
      liftPoints: liftPoints, label: label, stem: stem, stemColor: stemColor,
      effect: MunimEffect(rawValue: effect.stringValue) ?? .none, effectIntensity: effectIntensity,
      visible: visible)
    model.motion = motion.map {
      MunimKeyframe(t: $0.t, latitude: $0.latitude, longitude: $0.longitude, altitude: $0.altitude, heading: $0.heading)
    }
    model.motionStart = motionStart
    model.motionLoop = motionLoop
    model.occluder = occluder
    model.altitudeReference = altitudeReference.core
    model.effectOrigins = effectOrigins.split(separator: ";").compactMap { point in
      let v = point.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
      return v.count == 3 ? SIMD3(v[0], v[1], v[2]) : nil
    }
    // The JS side has already resolved these; keep them exactly.
    model.shape = MunimShape(rawValue: shape.stringValue) ?? .box
    model.screenSize = screenSize
    model.groundShadow = groundShadow
    return model
  }
}

extension NativeMapPath {
  var core: MunimPath {
    MunimPath(id: id, coordinates: points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) },
              altitudes: points.map(\.altitude), color: color, width: width, closed: closed,
              altitudeReference: altitudeReference.core, visible: visible)
  }
}

extension NativeMapZone {
  var core: MunimZone {
    MunimZone(id: id, points: points.map(CLLocationCoordinate2D.init), height: height, color: color, visible: visible)
  }
}

extension MapAltitudeReference {
  var core: MunimAltitudeReference { MunimAltitudeReference(rawValue: stringValue) ?? .ground }
}

extension MapModelLighting {
  var core: MunimLighting { MunimLighting(rawValue: stringValue) ?? .auto }
}

extension MunimAlignmentReport {
  var nitro: MapAlignmentReport {
    MapAlignmentReport(
      attached: attached, modelsMeasured: modelsMeasured, maxErrorPoints: maxErrorPoints,
      meanErrorPoints: meanErrorPoints, modelsVisibleInRender: modelsVisibleInRender,
      cameraDistance: cameraDistance, cameraPitch: cameraPitch, cameraHeading: cameraHeading,
      fieldOfViewDegrees: fieldOfViewDegrees)
  }
}

extension NativeMarker {
  var core: MunimMarker {
    var marker = MunimMarker(
      id: id, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
      title: title, subtitle: subtitle, style: MunimMarkerStyle(rawValue: style.stringValue) ?? .marker,
      color: color, glyph: glyph, imageUri: imageUri, imageSize: imageSize, borderColor: borderColor,
      borderWidth: borderWidth,
      badges: badges.map {
        MunimMarkerBadge(text: $0.text, position: MunimBadgePosition(rawValue: $0.position.stringValue) ?? .bottom,
                         color: $0.color, textColor: $0.textColor)
      },
      anchorX: anchorX, anchorY: anchorY, zIndex: zIndex, draggable: draggable, clusteringId: clusteringId,
      calloutEnabled: calloutEnabled, opacity: opacity, visible: visible)
    marker.displayPriority = displayPriority
    marker.collisionMode = MunimCollisionMode(rawValue: collisionMode.stringValue) ?? .rectangle
    marker.titleVisibility = titleVisibility.core
    marker.subtitleVisibility = subtitleVisibility.core
    marker.glyphSymbol = glyphSymbol
    marker.selectedGlyphSymbol = selectedGlyphSymbol
    marker.glyphColor = glyphColor
    marker.animatesWhenAdded = animatesWhenAdded
    marker.leftCalloutAccessory = leftCalloutAccessory.core
    marker.rightCalloutAccessory = rightCalloutAccessory.core
    marker.calloutDetail = calloutDetail
    return marker
  }
}

extension NativeCalloutAccessory {
  var core: MunimCalloutAccessory {
    MunimCalloutAccessory(kind: MunimCalloutAccessory.Kind(rawValue: kind.stringValue) ?? .none, text: text,
                          symbol: symbol, imageUri: imageUri, color: color)
  }
}

extension NativeClusterStyle {
  var core: MunimClusterStyle {
    MunimClusterStyle(clusteringId: clusteringId, color: color, glyphColor: glyphColor, glyph: glyph,
                      glyphSymbol: glyphSymbol, title: title, subtitle: subtitle, displayPriority: displayPriority)
  }
}

extension MapAddress {
  static let empty = MapAddress(name: "", street: "", city: "", region: "", postalCode: "", country: "",
                                countryCode: "", formatted: "", shortAddress: "")
}

extension MapItem {
  /// A Nitro `MapItem` from MapKit's.
  init(_ item: MKMapItem) {
    var identifier = ""
    if #available(iOS 18.0, *) { identifier = item.identifier?.rawValue ?? "" }
    let coordinate = mapItemCoordinate(item)
    self.init(
      identifier: identifier, name: item.name ?? "", phoneNumber: item.phoneNumber ?? "",
      url: item.url?.absoluteString ?? "", category: item.pointOfInterestCategory?.rawValue ?? "",
      timeZone: item.timeZone?.identifier ?? "", latitude: coordinate.latitude, longitude: coordinate.longitude,
      address: mapItemAddress(item), isCurrentLocation: item.isCurrentLocation)
  }
}

/// Where a map item is: `location` on iOS 26, its placemark before.
func mapItemCoordinate(_ item: MKMapItem) -> CLLocationCoordinate2D {
  #if compiler(>=6.2)
  if #available(iOS 26.0, *) { return item.location.coordinate }
  #endif
  return legacyPlacemark(item).coordinate
}

/// The placemark is deprecated on iOS 26 but still the only source of the
/// address parts (street, postal code…), so it is read here only.
@available(iOS, deprecated: 26.0)
private func legacyPlacemark(_ item: MKMapItem) -> MKPlacemark { item.placemark }

func mapItemAddress(_ item: MKMapItem) -> MapAddress {
  let p = legacyPlacemark(item)
  let street = [p.subThoroughfare, p.thoroughfare].compactMap { $0 }.joined(separator: " ")
  var formatted = [p.name, street.isEmpty ? nil : street, p.locality, p.administrativeArea, p.postalCode, p.country]
    .compactMap { $0 }
    .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    .joined(separator: ", ")
  var short = [street, p.locality ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
  #if compiler(>=6.2)
  if #available(iOS 26.0, *), let address = item.address {
    formatted = address.fullAddress.replacingOccurrences(of: "\n", with: ", ")
    if let value = address.shortAddress { short = value }
  }
  #endif
  return MapAddress(
    name: item.name ?? p.name ?? "", street: street, city: p.locality ?? "", region: p.administrativeArea ?? "",
    postalCode: p.postalCode ?? "", country: p.country ?? "", countryCode: p.isoCountryCode ?? "",
    formatted: formatted, shortAddress: short)
}

extension NativePolyline {
  var core: MunimPolyline {
    var line = MunimPolyline(
      id: id, coordinates: coordinates.map(CLLocationCoordinate2D.init), strokeColor: strokeColor,
      strokeWidth: strokeWidth, dashPattern: dashPattern, geodesic: geodesic,
      lineCap: MunimLineCap(rawValue: lineCap.stringValue) ?? .round, zIndex: zIndex)
    line.strokeColors = strokeColors
    line.strokeColorLocations = strokeColorLocations
    line.lineJoin = MunimLineJoin(rawValue: lineJoin.stringValue) ?? .round
    line.strokeStart = strokeStart
    line.strokeEnd = strokeEnd
    line.level = level.core
    line.tappable = tappable
    return line
  }
}

extension NativePolygon {
  var core: MunimPolygon {
    var polygon = MunimPolygon(
      id: id, coordinates: coordinates.map(CLLocationCoordinate2D.init),
      holes: holes.map { $0.map(CLLocationCoordinate2D.init) }, strokeColor: strokeColor,
      fillColor: fillColor, strokeWidth: strokeWidth, dashPattern: dashPattern, zIndex: zIndex)
    polygon.lineJoin = MunimLineJoin(rawValue: lineJoin.stringValue) ?? .round
    polygon.level = level.core
    polygon.tappable = tappable
    return polygon
  }
}

extension NativeCircle {
  var core: MunimCircle {
    var circle = MunimCircle(
      id: id, center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), radius: radius,
      strokeColor: strokeColor, fillColor: fillColor, strokeWidth: strokeWidth,
      dashPattern: dashPattern, zIndex: zIndex)
    circle.level = level.core
    circle.tappable = tappable
    return circle
  }
}

extension NativeTileOverlay {
  var core: MunimTileOverlay {
    var tiles = MunimTileOverlay(
      id: id, urlTemplate: urlTemplate, replacesMap: replacesMap, minimumZoom: minimumZoom,
      maximumZoom: maximumZoom, opacity: opacity, zIndex: zIndex)
    tiles.level = level.core
    return tiles
  }
}

extension OverlayLevel {
  var core: MunimOverlayLevel { MunimOverlayLevel(rawValue: stringValue) ?? .aboveLabels }
}

extension FeatureVisibility {
  var core: MunimFeatureVisibility { MunimFeatureVisibility(rawValue: stringValue) ?? .adaptive }
}

extension UserTrackingMode {
  var mapKit: MKUserTrackingMode {
    switch self {
    case .none: return .none
    case .follow: return .follow
    case .followwithheading: return .followWithHeading
    }
  }

  init(_ mode: MKUserTrackingMode) {
    switch mode {
    case .follow: self = .follow
    case .followWithHeading: self = .followwithheading
    default: self = .none
    }
  }
}

extension MapCamera {
  var core: MunimCamera {
    MunimCamera(latitude: latitude, longitude: longitude, distance: distance, pitch: pitch, heading: heading)
  }
}

extension MunimCamera {
  var nitro: MapCamera {
    MapCamera(latitude: latitude, longitude: longitude, distance: distance, pitch: pitch, heading: heading)
  }
}

extension MapRegion {
  var mapKit: MKCoordinateRegion {
    MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                       span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta))
  }
}

extension EdgeInsets {
  var uiKit: UIEdgeInsets {
    UIEdgeInsets(top: CGFloat(top), left: CGFloat(left), bottom: CGFloat(bottom), right: CGFloat(right))
  }
}

/// Runs `work` on the main thread and returns its result.
func onMain<T>(_ work: () -> T) -> T {
  if Thread.isMainThread { return work() }
  return DispatchQueue.main.sync(execute: work)
}

/// A Nitro promise resolved on the main thread.
func mainPromise<T>(_ work: @escaping () -> T) -> Promise<T> {
  let promise = Promise<T>()
  DispatchQueue.main.async { promise.resolve(withResult: work()) }
  return promise
}
