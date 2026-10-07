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
    MunimMarker(
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
  }
}

extension NativePolyline {
  var core: MunimPolyline {
    MunimPolyline(id: id, coordinates: coordinates.map(CLLocationCoordinate2D.init), strokeColor: strokeColor,
                  strokeWidth: strokeWidth, dashPattern: dashPattern, geodesic: geodesic,
                  lineCap: MunimLineCap(rawValue: lineCap.stringValue) ?? .round, zIndex: zIndex)
  }
}

extension NativePolygon {
  var core: MunimPolygon {
    MunimPolygon(id: id, coordinates: coordinates.map(CLLocationCoordinate2D.init),
                 holes: holes.map { $0.map(CLLocationCoordinate2D.init) }, strokeColor: strokeColor,
                 fillColor: fillColor, strokeWidth: strokeWidth, dashPattern: dashPattern, zIndex: zIndex)
  }
}

extension NativeCircle {
  var core: MunimCircle {
    MunimCircle(id: id, center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), radius: radius,
                strokeColor: strokeColor, fillColor: fillColor, strokeWidth: strokeWidth,
                dashPattern: dashPattern, zIndex: zIndex)
  }
}

extension NativeTileOverlay {
  var core: MunimTileOverlay {
    MunimTileOverlay(id: id, urlTemplate: urlTemplate, replacesMap: replacesMap, minimumZoom: minimumZoom,
                     maximumZoom: maximumZoom, opacity: opacity, zIndex: zIndex)
  }
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
