#!/usr/bin/env node
// Bundled CesiumJS (opt-in): copies the minified CesiumJS build from the
// app's own `cesium` npm dependency into the app at build time. munim-maps
// does not ship CesiumJS; by default the Cesium engine loads it from jsDelivr.
//
//   node copy-cesium.js --root <dir> --dest <dir>/Cesium   copy (skips when up to date)
//   node copy-cesium.js --root <dir> --resolve             print { dir, version, pinned } as JSON
//
// --root: where to resolve `cesium` from (the app, or its ios/ or android/
// folder). --cesium-dir <dir> or MUNIM_MAPS_CESIUM_DIR uses that `cesium`
// package folder instead. --no-version-warning silences the version check.
//
// Called by NitroMunimMaps.podspec (at `pod install`, into the
// MunimMapsCesium resource bundle) and android/build.gradle (a task that
// writes generated assets) when bundling is on: the Expo plugin's
// `cesium: { bundled: true }`, `MUNIM_MAPS_CESIUM_BUNDLED=1` /
// "munimMaps.cesiumBundled" for CocoaPods, `munimMaps.cesiumBundled=true` for
// Gradle.
//
// Only the minified build is copied (Cesium.js, Workers, ThirdParty, Assets,
// Widgets; about 13 MB), with CesiumJS's licence (LICENSE.md, Apache-2.0)
// and third-party notices (ThirdParty.json) next to it.
'use strict'

const fs = require('fs')
const path = require('path')

/**
 * The CesiumJS version the engine's page is written for and the engines
 * load from jsDelivr (CesiumSupport.swift `cesiumVersion`,
 * CesiumMapEngine.kt `CESIUM_VERSION`). The app's `cesium` should match.
 */
const CESIUM_VERSION = '1.146.0'

const PARTS = ['Cesium.js', 'Workers', 'ThirdParty', 'Assets', 'Widgets']
const NOTICES = ['LICENSE.md', 'ThirdParty.json']

function args(argv) {
  const out = { warn: true }
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i]
    if (arg === '--root') out.root = argv[++i]
    else if (arg === '--dest') out.dest = argv[++i]
    else if (arg === '--cesium-dir') out.cesiumDir = argv[++i]
    else if (arg === '--resolve') out.resolve = true
    else if (arg === '--no-version-warning') out.warn = false
    else fail(`unknown argument ${arg}`)
  }
  return out
}

function fail(message) {
  throw new Error(message)
}

function exit(message) {
  console.error(`error: munim-maps: ${message}`)
  process.exit(1)
}

/** The app's `cesium` package folder and version. */
function resolveCesium(options) {
  let dir = options.cesiumDir || process.env.MUNIM_MAPS_CESIUM_DIR
  if (!dir) {
    const root = path.resolve(options.root || process.cwd())
    try {
      dir = path.dirname(
        require.resolve('cesium/package.json', { paths: [root] })
      )
    } catch {
      fail(
        'bundling CesiumJS (cesium: { bundled: true }, munimMaps.cesiumBundled, ' +
          'MUNIM_MAPS_CESIUM_BUNDLED) needs the `cesium` npm package in the app: ' +
          `npm install cesium@${CESIUM_VERSION} (resolved from ${root})`
      )
    }
  }
  dir = path.resolve(dir)
  let version
  try {
    version = JSON.parse(
      fs.readFileSync(path.join(dir, 'package.json'), 'utf8')
    ).version
  } catch {
    fail(`no package.json in the cesium folder ${dir}`)
  }
  if (!fs.existsSync(path.join(dir, 'Build', 'Cesium', 'Cesium.js'))) {
    fail(`no Build/Cesium/Cesium.js in ${dir} (cesium@${version})`)
  }
  return { dir, version, pinned: CESIUM_VERSION }
}

function versionWarning(found) {
  if (found.version === CESIUM_VERSION) return undefined
  return (
    `the app's cesium is ${found.version}, but munim-maps' Cesium engine is ` +
    `written for and tested with CesiumJS ${CESIUM_VERSION} (the version it ` +
    `loads from jsDelivr). Pin "cesium": "${CESIUM_VERSION}" in package.json.`
  )
}

function copy(found, dest) {
  dest = path.resolve(dest)
  // VERSION is written last, so a copy with the right VERSION is complete.
  try {
    if (
      fs.readFileSync(path.join(dest, 'VERSION'), 'utf8').trim() ===
      found.version
    ) {
      console.log(`munim-maps: CesiumJS ${found.version} already in ${dest}`)
      return
    }
  } catch {}
  const build = path.join(found.dir, 'Build', 'Cesium')
  fs.rmSync(dest, { recursive: true, force: true })
  fs.mkdirSync(dest, { recursive: true })
  for (const part of PARTS) {
    fs.cpSync(path.join(build, part), path.join(dest, part), {
      recursive: true,
    })
  }
  // Apache-2.0: the licence and third-party notices travel with the code.
  for (const notice of NOTICES) {
    const file = path.join(found.dir, notice)
    if (fs.existsSync(file)) fs.copyFileSync(file, path.join(dest, notice))
  }
  fs.writeFileSync(path.join(dest, 'VERSION'), `${found.version}\n`)
  console.log(`munim-maps: copied CesiumJS ${found.version} into ${dest}`)
}

if (require.main === module) {
  try {
    const options = args(process.argv.slice(2))
    const found = resolveCesium(options)
    const warning = versionWarning(found)
    if (options.resolve) {
      console.log(JSON.stringify({ ...found, warning }))
    } else {
      if (!options.dest) fail('--dest <folder> is required')
      if (warning && options.warn) {
        console.error(`warning: munim-maps: ${warning}`)
      }
      copy(found, options.dest)
    }
  } catch (error) {
    exit(error.message)
  }
}

module.exports = { CESIUM_VERSION, resolveCesium, versionWarning, copy }
