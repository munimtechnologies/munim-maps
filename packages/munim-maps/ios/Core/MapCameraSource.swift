import MapKit
import UIKit

/// Where munim-maps' 3D layer (`MunimModelLayer`) gets its camera from: a map
/// engine's view. MapKit's is `MapKitCameraSource`; every other engine
/// (Google Maps, Mapbox, MapLibre, Cesium) provides one for its own map view
/// and attaches its model layer with `MunimModelLayer.attach(to:)`.
///
/// The layer asks for the camera once a frame, just before Core Animation
/// commits (so models land in the same frame as the map when the engine
/// draws on the main thread's frame clock), and only redraws when the state
/// changed.
public protocol MapCameraSource: AnyObject {
  /// The map's view. The 3D layer lines its drawing up with this view's
  /// frame, recognises taps on models on it, and stops drawing while it is
  /// off screen. Nil when the map has gone away.
  var cameraView: UIView? { get }

  /// The camera now. `previous` is the state returned last time, to carry
  /// values measured over several frames (MapKit's focal length). Nil while
  /// the map cannot answer, for example before it has a size.
  func cameraState(previous: MapCameraState?) -> MapCameraState?

  /// Where the engine itself draws a coordinate, in `cameraView`'s
  /// coordinates. Used to measure the 3D layer against the map
  /// (`measureAlignment`); nil when unknown.
  func screenPoint(for coordinate: CLLocationCoordinate2D) -> CGPoint?

  /// The area on screen, for loading building footprints around the camera
  /// (`buildingOcclusion`). Nil when unknown.
  func visibleRegion() -> MKCoordinateRegion?
}
