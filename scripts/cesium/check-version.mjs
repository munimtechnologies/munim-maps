// The CesiumJS version is pinned in three places that must agree: the
// bundling script (the version apps should install), the iOS engine and the
// Android engine (the jsDelivr URL and the disk cache). The npm package must
// not carry CesiumJS itself.
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')
const pkg = path.join(root, 'packages/munim-maps')
const require = createRequire(import.meta.url)
const { CESIUM_VERSION } = require(path.join(pkg, 'scripts/cesium/copy-cesium.js'))

const pins = {
  'ios/Engines/Cesium/CesiumSupport.swift': /static let cesiumVersion = "([^"]+)"/,
  'android/src/cesium/java/com/munimmaps/engines/cesium/CesiumMapEngine.kt': /const val CESIUM_VERSION = "([^"]+)"/,
}
let failed = false
for (const [file, pattern] of Object.entries(pins)) {
  const found = pattern.exec(readFileSync(path.join(pkg, file), 'utf8'))?.[1]
  if (found !== CESIUM_VERSION) {
    console.error(`${file}: CesiumJS ${found}, copy-cesium.js pins ${CESIUM_VERSION}`)
    failed = true
  }
}
const files = JSON.parse(readFileSync(path.join(pkg, 'package.json'), 'utf8')).files
if (files.some((entry) => entry === 'cesium' || entry.startsWith('cesium/cesiumjs') || entry.startsWith('cesium/build'))) {
  console.error('package.json files: munim-maps must not ship CesiumJS (only cesium/page)')
  failed = true
}
if (failed) process.exit(1)
console.log(`CesiumJS ${CESIUM_VERSION} pinned consistently`)
