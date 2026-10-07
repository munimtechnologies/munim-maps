#if MUNIM_MAPS_CESIUM
import MapKit
import UIKit

// The Cesium engine: Cesium (a 3D globe with terrain and 3D Tiles; Cesium Native or CesiumJS in a `WKWebView`, the engine decides).
//
// Compiled only when the `NitroMunimMaps/Cesium` subspec is installed
// (it defines MUNIM_MAPS_CESIUM). This file is the phase 1 stub:
// the engine is registered (`MunimMapEngines`) and shows a placeholder.
//
// To implement it (everything stays inside ios/Engines/Cesium/):
// 1. Write `CesiumMapEngine: UIView, MunimMapEngine, MunimMapEngineDefaults`
//    that hosts the SDK's map view filling itself, with `provider = .cesium`.
// 2. Own a `MunimModelLayer`, add its `view` above the map view (it never
//    takes touches), and `modelLayer.attach(to: <MapCameraSource>)` with a
//    source that turns the SDK's camera into `MapCameraState` every frame
//    (centre, distance in metres, pitch, heading, focal length from the
//    vertical field of view, viewport, globe, terrain, dark appearance),
//    `screenPoint(for:)` from the SDK's own projection (for
//    `measureAlignment`) and `visibleRegion()`.
//    Notes: `MunimMapsConfiguration.shared.cesiumIonToken`; `MapCameraState.globe = true`, `drawsTerrain = true`; Cesium hands out an exact view and projection: pass them as `cameraTransformOverride` / `projectionOverride`.
// 3. Implement the `MunimMapEngine` properties and methods it supports
//    (markers, shapes, camera, events…); `MunimMapEngineDefaults` covers the
//    rest with `onError` "not supported yet". Read `providerOptions` (the
//    JavaScript `cesium={…}` prop, decoded) and `styleURL`.
// 4. Set `isImplemented = true` below and return the engine from `make()`.
// 5. Test: example app's provider picker (`munimmapsexample://providers/cesium`)
//    shows a map with a GLB vehicle on it, and `measureAlignment()` is
//    within a point or two.

enum CesiumMapEngineFactory: MunimMapEngineFactory {
  static let isImplemented = false
  static func make() -> MunimMapEngine {
    UnavailableMapEngine(
      provider: .cesium,
      reason: "The Cesium engine is built in but not implemented yet.")
  }
}
#endif
