// A smoke test of the published API (npm run check).
const assert = require('node:assert')
const pkg = require('./package.json')
const {
  VEHICLES,
  VEHICLE_NAMES,
  MUNIM_MAPS_VEHICLES_VERSION,
  configureMunimMapsVehicles,
  vehicleSource,
} = require('./index')

assert.strictEqual(MUNIM_MAPS_VEHICLES_VERSION, pkg.version, 'index.js VERSION must match package.json')
assert.strictEqual(Object.keys(VEHICLES).length, VEHICLE_NAMES.length)
const base = `https://cdn.jsdelivr.net/npm/munim-maps-vehicles@${pkg.version}/`
assert.deepStrictEqual(VEHICLES['car-ev'], {
  uri: `${base}glb/car-ev.glb`,
  glb: `${base}glb/car-ev.glb`,
  usdz: `${base}usdz/car-ev.usdz`,
})
assert.strictEqual(VEHICLES['car-ev'], VEHICLES['car-ev'], 'sources are stable objects')
configureMunimMapsVehicles({ baseUrl: 'http://192.168.1.2:8000' })
assert.strictEqual(VEHICLES.balloon.usdz, 'http://192.168.1.2:8000/usdz/balloon.usdz')
configureMunimMapsVehicles({})
assert.strictEqual(VEHICLES.balloon.glb, `${base}glb/balloon.glb`)
assert.throws(() => vehicleSource('car-flying'))
const swift = require('node:fs').readFileSync(`${__dirname}/../munim-maps/ios/Vehicles/MunimVehicles.swift`, 'utf8')
assert.ok(swift.includes(`public static let version = "${pkg.version}"`), 'MunimVehicles.version must match package.json')
console.log(`munim-maps-vehicles ${pkg.version}: ${VEHICLE_NAMES.length} models, API ok`)
