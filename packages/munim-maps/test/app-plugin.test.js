const assert = require('node:assert/strict')
const { test } = require('node:test')
const plugin = require('../app.plugin.js')

const { androidGradleProperties, applyGradleProperties } = plugin

test('android.providers is the whole set of Android engines', () => {
  const props = androidGradleProperties({ android: { providers: ['mapbox'] } })
  assert.equal(props['munimMaps.mapbox'], 'true')
  assert.equal(props['munimMaps.maplibre'], 'false')
  assert.equal(props['munimMaps.maplibreWeb'], 'false')
  assert.equal(props['munimMaps.google'], 'false')
  assert.equal(props['munimMaps.cesium'], 'false')
})

test('top-level and Android lists combine; MapKit is ignored on Android', () => {
  const props = androidGradleProperties({
    providers: ['mapkit', 'google'],
    android: { providers: ['maplibre'] },
  })
  assert.equal(props['munimMaps.google'], 'true')
  assert.equal(props['munimMaps.maplibre'], 'true')
  assert.equal(props['munimMaps.maplibreWeb'], 'true')
  assert.equal(props['munimMaps.mapbox'], 'false')
})

test('maplibre: { web: false } drops MapLibre GL JS only', () => {
  const props = androidGradleProperties({
    android: { providers: ['maplibre'] },
    maplibre: { web: false },
  })
  assert.equal(props['munimMaps.maplibre'], 'true')
  assert.equal(props['munimMaps.maplibreWeb'], 'false')
  const unlisted = androidGradleProperties({ maplibre: { web: false } })
  assert.equal(unlisted['munimMaps.maplibre'], null)
  assert.equal(unlisted['munimMaps.maplibreWeb'], 'false')
})

test('without a providers list, the library default applies (keys left out)', () => {
  for (const options of [
    {},
    { ios: { providers: ['mapbox'] } },
    { providers: [] },
    { providers: ['mapkit'], android: { providers: [] } },
  ]) {
    const props = androidGradleProperties(options)
    for (const engine of [
      'google',
      'mapbox',
      'maplibre',
      'cesium',
      'maplibreWeb',
    ]) {
      assert.equal(props[`munimMaps.${engine}`], null, JSON.stringify(options))
    }
  }
})

test('bundled MapLibre web assets need MapLibre in the build', () => {
  assert.equal(
    androidGradleProperties({
      android: { providers: ['mapbox'] },
      maplibre: { bundledWeb: true },
    })['munimMaps.maplibreBundled'],
    null
  )
  assert.equal(
    androidGradleProperties({ maplibre: { bundledWeb: true } })[
      'munimMaps.maplibreBundled'
    ],
    'true'
  )
})

test('applyGradleProperties replaces old values and removes left-out keys', () => {
  const props = [
    { type: 'comment', value: 'keep me' },
    { type: 'property', key: 'munimMaps.maplibre', value: 'true' },
    { type: 'property', key: 'munimMaps.googleMaps3d', value: 'true' },
    { type: 'property', key: 'other', value: '1' },
  ]
  applyGradleProperties(
    props,
    androidGradleProperties({ android: { providers: ['mapbox'] } })
  )
  const get = (key) =>
    props.find((p) => p.type === 'property' && p.key === key)?.value
  assert.equal(get('munimMaps.maplibre'), 'false')
  assert.equal(get('munimMaps.mapbox'), 'true')
  assert.equal(get('munimMaps.googleMaps3d'), undefined)
  assert.equal(get('other'), '1')
  assert.equal(props.filter((p) => p.key === 'munimMaps.maplibre').length, 1)
})

test('the Expo plugin writes them through withGradleProperties', async () => {
  const config = plugin(
    { name: 'app', slug: 'app', _internal: { projectRoot: __dirname } },
    { android: { providers: ['mapbox'] } }
  )
  const mod = config.mods?.android?.gradleProperties
  assert.equal(typeof mod, 'function')
  const result = await mod({
    ...config,
    modResults: [
      { type: 'property', key: 'munimMaps.maplibre', value: 'true' },
    ],
    modRequest: {
      platform: 'android',
      modName: 'gradleProperties',
      projectRoot: __dirname,
      platformProjectRoot: __dirname,
      introspect: true,
    },
  })
  const values = Object.fromEntries(
    result.modResults
      .filter((p) => p.type === 'property')
      .map((p) => [p.key, p.value])
  )
  assert.equal(values['munimMaps.maplibre'], 'false')
  assert.equal(values['munimMaps.maplibreWeb'], 'false')
  assert.equal(values['munimMaps.mapbox'], 'true')
})
