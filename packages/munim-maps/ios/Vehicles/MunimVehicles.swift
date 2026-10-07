import Foundation

/// The munim-maps vehicle catalogue for native apps: 57 models (cars,
/// trucks, buses, bikes, motorcycles, trains, boats, aircraft, rockets and
/// satellites) whose paint takes `MunimModel.tintColor`.
///
/// The models are not in this package: they live in the `munim-maps-vehicles`
/// npm package and load from jsDelivr at a pinned version. munim-maps
/// downloads a model the first time it is shown and keeps it in the app's
/// Caches folder, so it works offline afterwards. Point `baseURL` at your own
/// server (a copy of the package's `usdz/` and `glb/` folders) to self-host.
///
/// ```swift
/// let car = MunimModel(id: "car", coordinate: c, uri: MunimVehicles.url("car-ev")!.absoluteString,
///                      tintColor: "#E5484D", screenSize: 18)
/// ```
public enum MunimVehicles {
  /// The munim-maps-vehicles version the URLs point at.
  public static let version = "0.5.0"

  /// Where the models are: a folder with `usdz/` and `glb/` inside.
  public static var baseURL = URL(string: "https://cdn.jsdelivr.net/npm/munim-maps-vehicles@\(version)/")!

  /// Every model name, such as `car-sedan` or `rocket-starship`.
  public static let names: [String] = [
    "balloon",
    "bike-city",
    "bike-mountain",
    "bike-road",
    "boat-jetski",
    "boat-sail",
    "boat-speed",
    "boat-yacht",
    "bus-city",
    "bus-school",
    "car-convertible",
    "car-ev",
    "car-hatchback",
    "car-minivan",
    "car-offroader",
    "car-pickup",
    "car-police",
    "car-sedan",
    "car-sports",
    "car-supercar",
    "car-suv",
    "car-taxi",
    "car-wagon",
    "heli-light",
    "jet-f16",
    "jet-f22",
    "jet-f35",
    "jet-yf23",
    "motorcycle-cruiser",
    "motorcycle-dirt",
    "motorcycle-sport",
    "plane-airliner",
    "plane-jet",
    "plane-prop",
    "plane-widebody",
    "rail-highspeed",
    "rail-tram",
    "rocket-falcon9",
    "rocket-saturnv",
    "rocket-shuttle",
    "rocket-starship",
    "satellite-cubesat",
    "satellite-dragon",
    "satellite-gps",
    "satellite-hubble",
    "satellite-iss",
    "satellite-jwst",
    "satellite-starlink",
    "scooter-kick",
    "scooter-moped",
    "starbase-mount",
    "starbase-tower",
    "truck-box",
    "truck-fire",
    "truck-semi",
    "van-ambulance",
    "van-delivery",
  ]

  /// The USDZ model (SceneKit, MapKit), or nil if there is no such name.
  public static func url(_ name: String) -> URL? {
    names.contains(name) ? baseURL.appendingPathComponent("usdz/\(name).usdz") : nil
  }

  /// The glTF binary model (Mapbox's and Cesium's own model layers), or nil
  /// if there is no such name.
  public static func glbURL(_ name: String) -> URL? {
    names.contains(name) ? baseURL.appendingPathComponent("glb/\(name).glb") : nil
  }
}
