require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

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
    # React Native views (Swift) and the shared core. ios/Vehicles is the
    # Swift Package's resource target and is not part of the pod.
    "ios/*.{swift,m,mm,h}",
    "ios/Core/**/*.swift",
    # Implementation (C++ objects)
    "cpp/**/*.{hpp,cpp}",
  ]

  load 'nitrogen/generated/ios/NitroMunimMaps+autolinking.rb'
  add_nitrogen_files(s)

  s.dependency 'React-jsi'
  s.dependency 'React-callinvoker'
  install_modules_dependencies(s)
end
