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

# CesiumJS loads from a pinned CDN by default; munim-maps does not ship it.
# Bundle it in the app (13 MB, offline from the first launch) with
# MUNIM_MAPS_CESIUM_BUNDLED=1 or "munimMaps.cesiumBundled": "true" in
# ios/Podfile.properties.json (the Expo config plugin's
# `cesium: { bundled: true }` writes it). The minified build is then copied
# from the app's own `cesium` npm package (pin the version the engine is
# written for, see scripts/cesium/copy-cesium.js) at `pod install`.
munim_maps_cesium_bundled = lambda do
  value = ENV["MUNIM_MAPS_CESIUM_BUNDLED"]
  if value.nil?
    begin
      root = Pod::Config.instance.installation_root
      properties = File.join(root.to_s, "Podfile.properties.json")
      value = JSON.parse(File.read(properties))["munimMaps.cesiumBundled"] if File.exist?(properties)
    rescue StandardError
      value = nil
    end
  end
  ["1", "true", "yes"].include?(value.to_s.strip.downcase)
end

# Google's photorealistic 3D map (`google={{ mode: '3d' }}`) is the Maps 3D
# SDK for iOS, which Google ships only as a Swift package (`GoogleMaps3D`).
# Turn it on with MUNIM_MAPS_GOOGLE_MAPS_3D=1 or "munimMaps.googleMaps3d":
# "true" in ios/Podfile.properties.json (the Expo config plugin's
# `googleMaps3d: true` writes it), next to the Google engine: the
# `NitroMunimMaps/Google3D` subspec is then on, and React Native's
# `spm_dependency` adds the Swift package to this pod in the Pods project.
munim_maps_google_maps_3d = lambda do
  value = ENV["MUNIM_MAPS_GOOGLE_MAPS_3D"]
  if value.nil?
    begin
      root = Pod::Config.instance.installation_root
      properties = File.join(root.to_s, "Podfile.properties.json")
      value = JSON.parse(File.read(properties))["munimMaps.googleMaps3d"] if File.exist?(properties)
    rescue StandardError
      value = nil
    end
  end
  ["1", "true", "yes"].include?(value.to_s.strip.downcase)
end

# Copies CesiumJS from the app's `cesium` package into cesium/build/Cesium
# (skipped when it is already there) and returns that folder for the
# MunimMapsCesium resource bundle.
munim_maps_copy_cesium = lambda do
  require "open3"
  dest = File.join(__dir__, "cesium", "build", "Cesium")
  root = begin
    Pod::Config.instance.installation_root.to_s
  rescue StandardError
    Dir.pwd
  end
  script = File.join(__dir__, "scripts", "cesium", "copy-cesium.js")
  out, err, status = Open3.capture3("node", script, "--root", root, "--dest", dest)
  unless status.success?
    message = err.strip.sub(/^error: /, "")
    message = "munim-maps: could not bundle CesiumJS" if message.empty?
    raise(defined?(Pod::Informative) ? Pod::Informative : RuntimeError, message)
  end
  err.each_line do |line|
    message = line.strip.sub(/^warning: /, "")
    next if message.empty?
    defined?(Pod::UI) ? Pod::UI.warn(message) : warn(message)
  end
  Pod::UI.puts(out.strip) if defined?(Pod::UI) && !out.strip.empty?
  "cesium/build/Cesium"
end

Pod::Spec.new do |s|
  s.name         = "NitroMunimMaps"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  # Google Maps 10 and its Utils need iOS 16, so the pod does too with the
  # Google engine on (apps that add `NitroMunimMaps/Google` by hand without
  # MUNIM_MAPS_PROVIDERS / Podfile.properties.json need iOS 16 themselves).
  ios_minimum = min_ios_version_supported
  if munim_maps_providers.call.include?("google") && Gem::Version.new(ios_minimum.to_s) < Gem::Version.new("16.0")
    ios_minimum = "16.0"
  end
  s.platforms    = { :ios => ios_minimum }
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
    # GoogleMaps 9.4+ with Utils 6.1+ (react-native-maps' Google subspec pins
    # 9.4.0 / 6.1.0); 10.x with Utils 7 otherwise.
    ss.dependency "GoogleMaps", ">= 9.4"
    ss.dependency "Google-Maps-iOS-Utils", ">= 6.1"
  end

  s.subspec "Mapbox" do |ss|
    ss.source_files = "ios/Engines/Mapbox/**/*.swift"
    ss.dependency "MapboxMaps", "~> 11.32"
  end

  s.subspec "MapLibre" do |ss|
    ss.source_files = "ios/Engines/MapLibre/**/*.swift"
    ss.dependency "MapLibre", ">= 6.30"
  end

  # The engine's page (cesium/page/munim-cesium) runs in a WKWebView the
  # engine owns. CesiumJS (Apache-2.0, pinned in CesiumSupport) comes from
  # jsDelivr through the engine's URL handler and is cached on disk, or from
  # this resource bundle when bundled (copied from the app's `cesium`
  # package, with its LICENSE.md and ThirdParty.json; 13 MB).
  s.subspec "Cesium" do |ss|
    ss.source_files = "ios/Engines/Cesium/**/*.swift"
    ss.frameworks = "WebKit", "CoreLocation"
    cesium_resources = ["cesium/page/munim-cesium"]
    cesium_resources << munim_maps_copy_cesium.call if munim_maps_cesium_bundled.call
    ss.resource_bundles = { "MunimMapsCesium" => cesium_resources }
    ss.pod_target_xcconfig = { "SWIFT_ACTIVE_COMPILATION_CONDITIONS" => "$(inherited) MUNIM_MAPS_CESIUM" }
  end

  # Google's photorealistic 3D map (Maps 3D SDK for iOS, iOS 16+): the
  # SwiftUI `GoogleMaps3D` map hosted in the Google engine's view. The Swift
  # package itself is added below with React Native's `spm_dependency`.
  s.subspec "Google3D" do |ss|
    ss.dependency "NitroMunimMaps/Google"
    ss.source_files = "ios/Engines/Google3D/**/*.swift"
    ss.frameworks = "SwiftUI"
    ss.pod_target_xcconfig = { "SWIFT_ACTIVE_COMPILATION_CONDITIONS" => "$(inherited) MUNIM_MAPS_GOOGLE3D" }
  end

  providers = munim_maps_providers.call
  subspecs = providers.map { |p| munim_maps_subspecs[p] }
  google_3d = providers.include?("google") && munim_maps_google_maps_3d.call
  subspecs << "Google3D" if google_3d
  s.default_subspecs = subspecs.empty? ? :none : subspecs

  if google_3d
    unless defined?(spm_dependency)
      raise(defined?(Pod::Informative) ? Pod::Informative : RuntimeError,
            "munim-maps: the Google 3D map needs React Native's spm_dependency (require react_native_pods.rb in the Podfile)")
    end
    # Pinned like the Android SDK; MUNIM_MAPS_GOOGLE_MAPS_3D_VERSION overrides it.
    spm_dependency(s,
      url: "https://github.com/googlemaps/ios-maps-3d-sdk",
      requirement: { kind: "exactVersion", version: ENV["MUNIM_MAPS_GOOGLE_MAPS_3D_VERSION"] || "1.0.0" },
      products: ["GoogleMaps3D"])
  end
end
