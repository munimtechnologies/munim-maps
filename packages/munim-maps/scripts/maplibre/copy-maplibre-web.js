#!/usr/bin/env node
// Bundled MapLibre GL JS (opt-in): copies GL JS from the app's own
// `maplibre-gl` npm dependency, and three.js (munim-maps' 3D layer inside GL
// JS) from the app's `three` dependency, into the app at build time.
// munim-maps does not ship either; by default the GL JS renderer loads them
// from jsDelivr at the pinned versions and keeps them on disk.
//
//   node copy-maplibre-web.js --root <dir> --dest <dir>       copy (skips when up to date)
//   node copy-maplibre-web.js --root <dir> --resolve          print what would be copied as JSON
//
// --root: where to resolve the packages from (the app, or its ios/ or
// android/ folder). --maplibre-dir / --three-dir (or MUNIM_MAPS_MAPLIBRE_GL_DIR,
// MUNIM_MAPS_THREE_DIR) use those package folders instead.
// --no-version-warning silences the version check.
//
// Called by NitroMunimMaps.podspec (at `pod install`, into the
// MunimMapsMapLibre resource bundle) and android/build.gradle (a task that
// writes generated assets) when bundling is on: the Expo plugin's
// `maplibre: { bundledWeb: true }`, `MUNIM_MAPS_MAPLIBRE_BUNDLED=1` /
// "munimMaps.maplibreBundled" for CocoaPods, `munimMaps.maplibreBundled=true`
// for Gradle.
//
// Copied: `<dest>/maplibre-gl/` = GL JS's dist/maplibre-gl.js and
// maplibre-gl.css with LICENSE.txt (BSD-3-Clause, about 1.1 MB);
// `<dest>/three/` = build/three.module.js, build/three.core.js and the
// three addons the 3D layer imports (GLTFLoader, SkeletonUtils,
// BufferGeometryUtils, RoomEnvironment) with LICENSE (MIT, about 2.2 MB).
// three is optional: without it, the 3D layer loads three.js from jsDelivr.
'use strict'

const fs = require('fs')
const path = require('path')

/**
 * The versions the page is written for and the engines load from jsDelivr
 * (MapLibreWebSupport.swift, MapLibreWebEngine.kt). The app's packages should match.
 */
const MAPLIBRE_GL_VERSION = '5.24.0'
const THREE_VERSION = '0.186.1'

const MAPLIBRE_FILES = ['dist/maplibre-gl.js', 'dist/maplibre-gl.css', 'LICENSE.txt']
const THREE_FILES = [
  'build/three.module.js',
  'build/three.core.js',
  'examples/jsm/loaders/GLTFLoader.js',
  'examples/jsm/utils/SkeletonUtils.js',
  'examples/jsm/utils/BufferGeometryUtils.js',
  'examples/jsm/environments/RoomEnvironment.js',
  'LICENSE',
  'package.json',
]

function args(argv) {
  const out = { warn: true }
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === '--root') out.root = argv[++i]
    else if (arg === '--dest') out.dest = argv[++i]
    else if (arg === '--maplibre-dir') out.maplibreDir = argv[++i]
    else if (arg === '--three-dir') out.threeDir = argv[++i]
    else if (arg === '--resolve') out.resolve = true
    else if (arg === '--no-version-warning') out.warn = false
    else throw new Error(`unknown argument ${arg}`)
  }
  return out
}

function packageDir(name, explicit, root) {
  if (explicit) return path.resolve(explicit)
  try {
    return path.dirname(require.resolve(`${name}/package.json`, { paths: [root] }))
  } catch {
    return undefined
  }
}

function version(dir) {
  try {
    return JSON.parse(fs.readFileSync(path.join(dir, 'package.json'), 'utf8')).version
  } catch {
    return undefined
  }
}

/** The app's `maplibre-gl` (required) and `three` (optional) packages. */
function resolvePackages(options) {
  const root = path.resolve(options.root || process.cwd())
  const maplibreDir = packageDir('maplibre-gl', options.maplibreDir || process.env.MUNIM_MAPS_MAPLIBRE_GL_DIR, root)
  if (!maplibreDir) {
    throw new Error(
      'bundling MapLibre GL JS (maplibre: { bundledWeb: true }, munimMaps.maplibreBundled, ' +
        'MUNIM_MAPS_MAPLIBRE_BUNDLED) needs the `maplibre-gl` npm package in the app: ' +
        `npm install maplibre-gl@${MAPLIBRE_GL_VERSION} (resolved from ${root})`
    )
  }
  const maplibre = { dir: maplibreDir, version: version(maplibreDir), pinned: MAPLIBRE_GL_VERSION }
  if (!fs.existsSync(path.join(maplibreDir, 'dist', 'maplibre-gl.js'))) {
    throw new Error(`no dist/maplibre-gl.js in ${maplibreDir} (maplibre-gl@${maplibre.version}; GL JS 6 is ES modules only, use ${MAPLIBRE_GL_VERSION})`)
  }
  const threeDir = packageDir('three', options.threeDir || process.env.MUNIM_MAPS_THREE_DIR, root)
  const three = threeDir ? { dir: threeDir, version: version(threeDir), pinned: THREE_VERSION } : undefined
  return { maplibre, three }
}

function warnings(found) {
  const out = []
  if (found.maplibre.version !== MAPLIBRE_GL_VERSION) {
    out.push(`the app's maplibre-gl is ${found.maplibre.version}, but munim-maps' GL JS renderer is written for and tested with ${MAPLIBRE_GL_VERSION} (the version it loads from jsDelivr). Pin "maplibre-gl": "${MAPLIBRE_GL_VERSION}" in package.json.`)
  }
  if (!found.three) {
    out.push(`no \`three\` package in the app: the 3D layer will load three.js ${THREE_VERSION} from jsDelivr (npm install three@${THREE_VERSION} to bundle it too).`)
  } else if (found.three.version !== THREE_VERSION) {
    out.push(`the app's three is ${found.three.version}, but munim-maps' 3D layer is written for and tested with ${THREE_VERSION}. Pin "three": "${THREE_VERSION}" in package.json.`)
  }
  return out
}

function copyFiles(from, files, dest, flatten) {
  for (const file of files) {
    const source = path.join(from, file)
    if (!fs.existsSync(source)) throw new Error(`missing ${source}`)
    const target = path.join(dest, flatten ? path.basename(file) : file)
    fs.mkdirSync(path.dirname(target), { recursive: true })
    fs.copyFileSync(source, target)
  }
}

function copy(found, dest) {
  dest = path.resolve(dest)
  const stamp = `maplibre-gl@${found.maplibre.version} three@${found.three ? found.three.version : '-'}`
  // VERSION is written last, so a copy with the right VERSION is complete.
  try {
    if (fs.readFileSync(path.join(dest, 'VERSION'), 'utf8').trim() === stamp) {
      console.log(`munim-maps: ${stamp} already in ${dest}`)
      return
    }
  } catch {}
  fs.rmSync(dest, { recursive: true, force: true })
  fs.mkdirSync(dest, { recursive: true })
  // BSD-3-Clause and MIT: the licences travel with the code.
  copyFiles(found.maplibre.dir, MAPLIBRE_FILES, path.join(dest, 'maplibre-gl'), true)
  if (found.three) copyFiles(found.three.dir, THREE_FILES, path.join(dest, 'three'), false)
  fs.writeFileSync(path.join(dest, 'VERSION'), `${stamp}\n`)
  console.log(`munim-maps: copied ${stamp} into ${dest}`)
}

if (require.main === module) {
  try {
    const options = args(process.argv.slice(2))
    const found = resolvePackages(options)
    const warning = warnings(found)
    if (options.resolve) {
      console.log(JSON.stringify({ ...found, warning: warning.join(' ') || undefined }))
    } else {
      if (!options.dest) throw new Error('--dest <folder> is required')
      if (options.warn) for (const w of warning) console.error(`warning: munim-maps: ${w}`)
      copy(found, options.dest)
    }
  } catch (error) {
    console.error(`error: munim-maps: ${error.message}`)
    process.exit(1)
  }
}

module.exports = { MAPLIBRE_GL_VERSION, THREE_VERSION, resolvePackages, warnings, copy }
