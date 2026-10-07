// swift-tools-version: 5.9
// munim-maps for native iOS apps (UIKit and SwiftUI), without React Native.
import PackageDescription

let package = Package(
  name: "MunimMaps",
  platforms: [.iOS(.v16)],
  products: [
    .library(name: "MunimMaps", targets: ["MunimMaps"]),
    .library(name: "MunimMapsVehicles", targets: ["MunimMapsVehicles"]),
  ],
  targets: [
    .target(
      name: "MunimMaps",
      path: "packages/munim-maps/ios",
      // The core, the engine interface and the MapKit engine. The other
      // engines' folders compile to nothing without their SDKs.
      sources: ["Core", "Engines"]
    ),
    // The vehicle catalogue's names and URLs; the models load from the
    // munim-maps-vehicles package on jsDelivr (cached on the device).
    .target(
      name: "MunimMapsVehicles",
      path: "packages/munim-maps/ios/Vehicles"
    ),
  ]
)
