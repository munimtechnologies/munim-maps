#!/bin/bash
# Copies the CesiumJS build the Cesium engine bundles (opt-in) into
# cesium/cesiumjs/munim-cesium/Cesium/, from the `cesium` npm package at a pinned
# version. Only the minified build is kept (Cesium.js, Workers, ThirdParty,
# Assets, Widgets): no unminified build, no ES module copies.
#
#   scripts/cesium/vendor-cesium.sh [version]
#
# The version is pinned in cesium/cesiumjs/munim-cesium/Cesium/VERSION and
# in the engines' CDN URL (CesiumMapEngine.swift / .kt, `cesiumVersion`);
# bump them together and test both platforms (see docs/providers.md).
set -euo pipefail

here="$(cd "$(dirname "$0")/../.." && pwd)"
version="${1:-$(cat "$here/cesium/cesiumjs/munim-cesium/Cesium/VERSION" 2>/dev/null || echo 1.146.0)}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

(cd "$work" && npm pack "cesium@$version" --silent >/dev/null)
mkdir -p "$work/x"
tar -xzf "$work/cesium-$version.tgz" -C "$work/x"
build="$work/x/package/Build/Cesium"
[ -f "$build/Cesium.js" ] || { echo "No Build/Cesium/Cesium.js in cesium@$version" >&2; exit 1; }

dest="$here/cesium/cesiumjs/munim-cesium/Cesium"
rm -rf "$dest"
mkdir -p "$dest"
cp "$build/Cesium.js" "$dest/"
cp -R "$build/Workers" "$build/ThirdParty" "$build/Assets" "$build/Widgets" "$dest/"
# Licence and third-party notices travel with the code (Apache-2.0).
cp "$work/x/package/LICENSE.md" "$dest/LICENSE.md"
cp "$work/x/package/ThirdParty.json" "$dest/ThirdParty.json"
echo "$version" > "$dest/VERSION"
du -sh "$dest"
echo "CesiumJS $version vendored into $dest"
