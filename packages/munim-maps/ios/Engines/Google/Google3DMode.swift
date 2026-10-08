#if canImport(GoogleMaps)
import UIKit

// Google's photorealistic 3D map (`google={{ mode: '3d' }}`): the Maps 3D
// SDK for iOS (`GoogleMaps3D`, a SwiftUI Swift package), where munim-maps'
// models are Google's own glTF models and polylines, polygons and markers
// are drawn natively. It lives in the `NitroMunimMaps/Google3D` subspec
// (Engines/Google3D), which adds the Swift package; the Google engine works
// without it and reports an error for `mode: '3d'`.

/// What the Google engine asks of the 3D mode (`GoogleMap3DMode`).
protocol Google3DMode: AnyObject {
  /// The 3D map's view, laid over (and instead of) the 2D map.
  var view: UIView { get }
  func setOptions(_ options: GoogleJSON)
  func setModels(_ models: [MunimModel])
  func setMarkers(_ markers: [MunimMarker])
  func setPolylines(_ polylines: [MunimPolyline])
  func setPolygons(_ polygons: [MunimPolygon])
  /// Moves the camera, flying over `duration` seconds when above 0.
  func setCamera(_ camera: MunimCamera, duration: TimeInterval)
  var camera: MunimCamera? { get }
  /// Google 3D's own methods (`flyTo`, `flyAround`, `stopCameraAnimation`,
  /// `getCamera3d`, `setCamera3d`); false when the name is not one.
  func command(_ name: String, _ args: GoogleJSON, completion: @escaping (Result<Any, Error>) -> Void) -> Bool
  func destroy()
}

enum Google3DModes {
  /// Whether the Maps 3D SDK is built in (the `NitroMunimMaps/Google3D`
  /// subspec, with `munimMaps.googleMaps3d`).
  static var isAvailable: Bool {
    #if MUNIM_MAPS_GOOGLE3D && canImport(GoogleMaps3D)
    return true
    #else
    return false
    #endif
  }

  static func make(engine: GoogleMapEngine, camera: MunimCamera?) -> Google3DMode? {
    #if MUNIM_MAPS_GOOGLE3D && canImport(GoogleMaps3D)
    return GoogleMap3DMode(engine: engine, camera: camera)
    #else
    return nil
    #endif
  }
}
#endif
