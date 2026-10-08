// MapLibre GL JS and three.js versions are pinned in three places that must
// agree: the bundling script (the versions apps should install), the iOS
// engine and the Android engine (the jsDelivr URLs and the disk cache). The
// npm package must not carry GL JS or three.js themselves.
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..')
const pkg = path.join(root, 'packages/munim-maps')
const require = createRequire(import.meta.url)
const { MAPLIBRE_GL_VERSION, THREE_VERSION } = require(path.join(pkg, 'scripts/maplibre/copy-maplibre-web.js'))

const pins = [
  ['ios/Engines/MapLibreWeb/MapLibreWebSupport.swift', /static let maplibreVersion = "([^"]+)"/, MAPLIBRE_GL_VERSION],
  ['ios/Engines/MapLibreWeb/MapLibreWebSupport.swift', /static let threeVersion = "([^"]+)"/, THREE_VERSION],
  ['android/src/maplibreWeb/java/com/munimmaps/engines/maplibreweb/MapLibreWebEngine.kt', /const val MAPLIBRE_GL_VERSION = "([^"]+)"/, MAPLIBRE_GL_VERSION],
  ['android/src/maplibreWeb/java/com/munimmaps/engines/maplibreweb/MapLibreWebEngine.kt', /const val THREE_VERSION = "([^"]+)"/, THREE_VERSION],
]
let failed = false
for (const [file, pattern, wanted] of pins) {
  const found = pattern.exec(readFileSync(path.join(pkg, file), 'utf8'))?.[1]
  if (found !== wanted) {
    console.error(`${file}: ${found}, copy-maplibre-web.js pins ${wanted}`)
    failed = true
  }
}
const files = JSON.parse(readFileSync(path.join(pkg, 'package.json'), 'utf8')).files
if (files.some((entry) => entry === 'maplibre' || entry.startsWith('maplibre/build'))) {
  console.error('package.json files: munim-maps must not ship MapLibre GL JS or three.js (only maplibre/page)')
  failed = true
}
if (failed) process.exit(1)
console.log(`MapLibre GL JS ${MAPLIBRE_GL_VERSION} and three.js ${THREE_VERSION} pinned consistently`)
