#if canImport(GoogleMaps)
import GoogleMaps
import MapKit
import UIKit

// The Google engine: Google Maps SDK for iOS (`GMSMapView`).
//
// Compiled only when the `NitroMunimMaps/Google` subspec is installed
// (its SDK can be imported). This file is the phase 1 stub:
// the engine is registered (`MunimMapEngines`) and shows a placeholder.
//
// To implement it (everything stays inside ios/Engines/Google/):
// 1. Write `GoogleMapEngine: UIView, MunimMapEngine, MunimMapEngineDefaults`
//    that hosts the SDK's map view filling itself, with `provider = .google`.
// 2. Own a `MunimModelLayer`, add its `view` above the map view (it never
//    takes touches), and `modelLayer.attach(to: <MapCameraSource>)` with a
//    source that turns the SDK's camera into `MapCameraState` every frame
//    (centre, distance in metres, pitch, heading, focal length from the
//    vertical field of view, viewport, globe, terrain, dark appearance),
//    `screenPoint(for:)` from the SDK's own projection (for
//    `measureAlignment`) and `visibleRegion()`.
//    Notes: GMSServices.provideAPIKey(MunimMapsConfiguration.shared.googleMapsApiKey) before the first `GMSMapView`; `GMSCameraPosition` zoom → `MapCameraState` (Google uses a 30° vertical field of view and 256-point tiles).
// 3. Implement the `MunimMapEngine` properties and methods it supports
//    (markers, shapes, camera, events…); `MunimMapEngineDefaults` covers the
//    rest with `onError` "not supported yet". Read `providerOptions` (the
//    JavaScript `google={…}` prop, decoded) and `styleURL`.
// 4. Set `isImplemented = true` below and return the engine from `make()`.
// 5. Test: example app's provider picker (`munimmapsexample://providers/google`)
//    shows a map with a GLB vehicle on it, and `measureAlignment()` is
//    within a point or two.

enum GoogleMapEngineFactory: MunimMapEngineFactory {
  static let isImplemented = false
  static func make() -> MunimMapEngine {
    UnavailableMapEngine(
      provider: .google,
      reason: "The Google engine is built in but not implemented yet.")
  }
}
#endif
