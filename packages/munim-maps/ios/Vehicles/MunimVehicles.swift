import Foundation

/// The munim-maps vehicle catalogue for native apps: 57 USDZ models (cars,
/// trucks, buses, bikes, motorcycles, trains, boats, aircraft, rockets and
/// satellites) whose paint takes `MunimModel.tintColor`.
///
/// ```swift
/// let car = MunimModel(id: "car", coordinate: c, uri: MunimVehicles.url("car-ev")!.absoluteString,
///                      tintColor: "#E5484D", screenSize: 18)
/// ```
public enum MunimVehicles {
  /// Every model name, such as `car-sedan` or `rocket-starship`.
  public static var names: [String] {
    (Bundle.module.urls(forResourcesWithExtension: "usdz", subdirectory: "Models") ?? [])
      .map { $0.deletingPathExtension().lastPathComponent }
      .sorted()
  }

  /// The file URL of a model, or nil if there is no such name.
  public static func url(_ name: String) -> URL? {
    Bundle.module.url(forResource: name, withExtension: "usdz", subdirectory: "Models")
  }
}
