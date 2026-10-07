// munim-maps-vehicles: the munim-maps vehicle catalogue (57 models made by
// scripts/vehicles/make-vehicles.swift; paint is recoloured with `tint`).
//
// `VEHICLES[name]` is a remote source: the model's USDZ and GLB on jsDelivr
// at this package's version. munim-maps picks the format each engine needs
// (USDZ where SceneKit draws it on iOS, GLB elsewhere), downloads it the
// first time and keeps it on disk, so the app works offline afterwards. For
// models inside the app instead, import
// `munim-maps-vehicles/bundled/<name>` (one file per model).
const { VEHICLE_NAMES } = require('./names')

const VERSION = '0.5.0'
const CDN = `https://cdn.jsdelivr.net/npm/munim-maps-vehicles@${VERSION}/`

let baseUrl = CDN
const sources = new Map()

function vehicleSource(name) {
  if (!VEHICLE_NAMES.includes(name)) {
    throw new Error(`munim-maps-vehicles: no vehicle named "${name}"`)
  }
  let source = sources.get(name)
  if (!source) {
    const glb = `${baseUrl}glb/${name}.glb`
    source = Object.freeze({ uri: glb, glb, usdz: `${baseUrl}usdz/${name}.usdz` })
    sources.set(name, source)
  }
  return source
}

/**
 * Where the models load from: a folder holding this package's `usdz/` and
 * `glb/` folders (your own server or CDN). `baseUrl: undefined` goes back to
 * jsDelivr. Call it before rendering maps.
 */
function configureMunimMapsVehicles(options = {}) {
  const next = options.baseUrl
    ? options.baseUrl.endsWith('/')
      ? options.baseUrl
      : `${options.baseUrl}/`
    : CDN
  if (next === baseUrl) return
  baseUrl = next
  sources.clear()
}

const VEHICLES = {}
for (const name of VEHICLE_NAMES) {
  Object.defineProperty(VEHICLES, name, {
    enumerable: true,
    get: () => vehicleSource(name),
  })
}
Object.freeze(VEHICLES)

module.exports = {
  VEHICLES,
  VEHICLE_NAMES,
  MUNIM_MAPS_VEHICLES_VERSION: VERSION,
  vehicleSource,
  configureMunimMapsVehicles,
}
