#!/bin/bash
# Development only (not in the npm package): fetches a CesiumJS version from
# npm and copies its minified build the way an app's bundled build gets it
# (packages/munim-maps/scripts/cesium/copy-cesium.js), into a folder that is
# not committed. Use it to see what bundling ships (size, files) or to try a
# new version before bumping the pin.
#
#   scripts/cesium/vendor-cesium.sh [version] [dest]
#
# Defaults: the pinned version (copy-cesium.js CESIUM_VERSION, the same as
# CesiumSupport.swift `cesiumVersion` and CesiumMapEngine.kt
# `CESIUM_VERSION`; bump them together and test both platforms, see
# docs/providers.md) into packages/munim-maps/cesium/build/Cesium, the folder
# the podspec bundles from (git-ignored, outside the package's `files`).
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
copy="$repo/packages/munim-maps/scripts/cesium/copy-cesium.js"
pinned="$(node -p "require('$copy').CESIUM_VERSION")"
version="${1:-$pinned}"
dest="${2:-$repo/packages/munim-maps/cesium/build/Cesium}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

(cd "$work" && npm pack "cesium@$version" --silent >/dev/null)
mkdir -p "$work/x"
tar -xzf "$work/cesium-$version.tgz" -C "$work/x"
node "$copy" --cesium-dir "$work/x/package" --dest "$dest"
du -sh "$dest"
