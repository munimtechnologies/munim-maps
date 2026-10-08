#!/bin/bash
# Embeds Google's Maps 3D SDK (the `GoogleMaps3D` Swift package) in the app.
#
# NitroMunimMaps compiles and links against the package (React Native's
# `spm_dependency` in NitroMunimMaps.podspec), and Xcode merges the package's
# wrapper into the pod's static library, so the app links the SDK through the
# pod. What a static-library pod cannot do is put the SDK's dynamic framework
# and its resource bundle in the app. Linking the package product into the
# app target as well would, but then the wrapper is linked twice and Debug
# builds stop with duplicate `Bundle.module` symbols. So this copies both from
# the build folder into the app and signs the framework, as Xcode would.
#
# Run it as the app target's last build phase. The Expo config plugin adds it
# (`googleMaps3d: true`); without Expo add a Run Script phase that runs
#   bash "${SRCROOT}/../node_modules/munim-maps/scripts/google3d/embed-google-maps-3d.sh"
set -euo pipefail

products="${BUILT_PRODUCTS_DIR:?run from an Xcode build phase}"
framework=""
for dir in "$products" "$products/NitroMunimMaps" "$products/PackageFrameworks" "$products/NitroMunimMaps/PackageFrameworks"; do
  if [ -d "$dir/GoogleMaps3D.framework" ]; then
    framework="$dir/GoogleMaps3D.framework"
    break
  fi
done
if [ -z "$framework" ]; then
  echo "error: munim-maps: GoogleMaps3D.framework is not in $products. Is the Google 3D map on for CocoaPods (\"munimMaps.googleMaps3d\": \"true\" in ios/Podfile.properties.json, then pod install)?"
  exit 1
fi

destination="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
mkdir -p "$destination"
rsync -a --delete --exclude Headers --exclude PrivateHeaders --exclude Modules "$framework" "$destination/"
if [ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --preserve-metadata=identifier,entitlements,flags \
    --timestamp=none "$destination/GoogleMaps3D.framework"
fi

for dir in "$products" "$products/NitroMunimMaps"; do
  if [ -d "$dir/GoogleMaps3D_GoogleMaps3DTarget.bundle" ]; then
    rsync -a --delete "$dir/GoogleMaps3D_GoogleMaps3DTarget.bundle" "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/"
    break
  fi
done
