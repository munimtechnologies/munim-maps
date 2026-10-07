#if canImport(MapboxMaps)
import MapboxMaps
import MapKit
import UIKit

// The Mapbox engine: Mapbox Maps SDK v11 (`MapView`).
//
// Compiled only when the `NitroMunimMaps/Mapbox` subspec is installed
// (its SDK can be imported). This file is the phase 1 stub:
// the engine is registered (`MunimMapEngines`) and shows a placeholder.
//
// To implement it (everything stays inside ios/Engines/Mapbox/):
// 1. Write `MapboxMapEngine: UIView, MunimMapEngine, MunimMapEngineDefaults`
//    that hosts the SDK's map view filling itself, with `provider = .mapbox`.
// 2. Own a `MunimModelLayer`, add its `view` above the map view (it never
//    takes touches), and `modelLayer.attach(to: <MapCameraSource>)` with a
//    source that turns the SDK's camera into `MapCameraState` every frame
//    (centre, distance in metres, pitch, heading, focal length from the
//    vertical field of view, viewport, globe, terrain, dark appearance),
//    `screenPoint(for:)` from the SDK's own projection (for
//    `measureAlignment`) and `visibleRegion()`.
//    Notes: `MapboxOptions.accessToken = MunimMapsConfiguration.shared.mapboxAccessToken`; style from `styleURL` / `MunimMapsConfiguration.shared.mapboxStyleURL`; camera from `mapboxMap.cameraState` (36.87° vertical field of view, 512-point tiles), or an exact matrix from a custom layer into `MapCameraState.projectionOverride`.
// 3. Implement the `MunimMapEngine` properties and methods it supports
//    (markers, shapes, camera, events…); `MunimMapEngineDefaults` covers the
//    rest with `onError` "not supported yet". Read `providerOptions` (the
//    JavaScript `mapbox={…}` prop, decoded) and `styleURL`.
// 4. Set `isImplemented = true` below and return the engine from `make()`.
// 5. Test: example app's provider picker (`munimmapsexample://providers/mapbox`)
//    shows a map with a GLB vehicle on it, and `measureAlignment()` is
//    within a point or two.

enum MapboxMapEngineFactory: MunimMapEngineFactory {
  static let isImplemented = false
  static func make() -> MunimMapEngine {
    UnavailableMapEngine(
      provider: .mapbox,
      reason: "The Mapbox engine is built in but not implemented yet.")
  }
}
#endif
