require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

# Map engines besides MapKit are opt-in, so a default install pulls in no
# extra SDKs. Turn them on with any of:
#   - the subspecs, in the Podfile:  pod 'NitroMunimMaps/Google', :path => '../node_modules/munim-maps'
#   - MUNIM_MAPS_PROVIDERS=google,maplibre pod install
#   - "munimMaps.providers": "google,maplibre" in ios/Podfile.properties.json
#     (the Expo config plugin's `providers` option writes this)
munim_maps_subspecs = {
  "google" => "Google",
  "mapbox" => "Mapbox",
  "maplibre" => "MapLibre",
  "cesium" => "Cesium",
}

munim_maps_providers = lambda do
  list = ENV["MUNIM_MAPS_PROVIDERS"]
  if list.nil?
    begin
      root = Pod::Config.instance.installation_root
      properties = File.join(root.to_s, "Podfile.properties.json")
      list = JSON.parse(File.read(properties))["munimMaps.providers"] if File.exist?(properties)
    rescue StandardError
      list = nil
    end
  end
  (list || "").split(",").map { |p| p.strip.downcase }.select { |p| munim_maps_subspecs.key?(p) }.uniq
end

Pod::Spec.new do |s|
  s.name         = "NitroMunimMaps"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => "https://github.com/munimtechnologies/munim-maps.git", :tag => "v#{s.version}" }
  s.frameworks   = "MapKit", "SceneKit", "Metal", "ModelIO", "QuartzCore"

  s.source_files = [
    # React Native views (Swift), the shared core, the engine interface and
    # the MapKit engine. ios/Vehicles is the Swift Package's resource target
    # and is not part of the pod. Other engines are in their subspecs.
    "ios/*.{swift,m,mm,h}",
    "ios/Core/**/*.swift",
    "ios/Engines/*.swift",
    "ios/Engines/MapKit/**/*.swift",
    # Implementation (C++ objects)
    "cpp/**/*.{hpp,cpp}",
  ]

  load 'nitrogen/generated/ios/NitroMunimMaps+autolinking.rb'
  add_nitrogen_files(s)

  s.dependency 'React-jsi'
  s.dependency 'React-callinvoker'
  install_modules_dependencies(s)

  # Each engine's folder is wrapped in `#if canImport(<SDK>)` (Cesium:
  # `#if MUNIM_MAPS_CESIUM`), so it compiles only with its subspec.
  s.subspec "Google" do |ss|
    ss.source_files = "ios/Engines/Google/**/*.swift"
    # Maps SDK for iOS 10 and Google Maps Utils 7 (clustering, heatmaps,
    # KML, GeoJSON).
    ss.dependency "GoogleMaps", ">= 10.0"
    ss.dependency "Google-Maps-iOS-Utils", ">= 7.0"
  end

  s.subspec "Mapbox" do |ss|
    ss.source_files = "ios/Engines/Mapbox/**/*.swift"
    ss.dependency "MapboxMaps", ">= 11.0"
  end

  s.subspec "MapLibre" do |ss|
    ss.source_files = "ios/Engines/MapLibre/**/*.swift"
    ss.dependency "MapLibre", ">= 6.0"
  end

  s.subspec "Cesium" do |ss|
    ss.source_files = "ios/Engines/Cesium/**/*.swift"
    ss.pod_target_xcconfig = { "SWIFT_ACTIVE_COMPILATION_CONDITIONS" => "$(inherited) MUNIM_MAPS_CESIUM" }
  end

  providers = munim_maps_providers.call
  s.default_subspecs = providers.empty? ? :none : providers.map { |p| munim_maps_subspecs[p] }
end
