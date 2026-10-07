// Expo config plugin for munim-maps: chooses the map engines built into the
// app and writes their keys into the native config.
//
//   ["munim-maps", {
//     "providers": ["google", "maplibre"],        // engines besides MapKit (iOS) / MapLibre (Android)
//     "ios": { "providers": ["mapbox"] },           // per platform, added to `providers`
//     "android": { "providers": ["cesium"] },
//     "googleMapsApiKey": "…" | { "ios": "…", "android": "…" },
//     "mapboxAccessToken": "pk.…",
//     "cesiumIonToken": "…",
//     "cesium": { "bundled": true },               // CesiumJS in the app (13 MB) instead of from jsDelivr
//     "googleMaps3d": true                         // Android: Google's photorealistic 3D SDK
//   }]
//
// iOS: Podfile.properties.json `munimMaps.providers` (the podspec turns
// those subspecs on), Info.plist `MunimMapsGoogleMapsApiKey`,
// `MBXAccessToken`, `MunimMapsCesiumIonToken`.
// Android: gradle.properties `munimMaps.<provider>=true`, manifest
// `com.google.android.geo.API_KEY` and `munimmaps.cesium_ion_token`
// meta-data, and the `mapbox_access_token` string resource.
let plugins
try {
  plugins = require('expo/config-plugins')
} catch {
  plugins = require('@expo/config-plugins')
}
const {
  AndroidConfig,
  withAndroidManifest,
  withGradleProperties,
  withInfoPlist,
  withPodfileProperties,
  withProjectBuildGradle,
  withStringsXml,
} = plugins

const MAPBOX_MAVEN = 'https://api.mapbox.com/downloads/v2/releases/maven'

/**
 * Adds Mapbox's Maven repository (public, no secret token) to the app's
 * `allprojects.repositories`: the app resolves the Mapbox SDK that comes
 * through munim-maps.
 */
function addMapboxMaven(gradle) {
  if (gradle.includes(MAPBOX_MAVEN)) return gradle
  const line = `    maven { url '${MAPBOX_MAVEN}' }\n`
  const match = /allprojects\s*\{\s*repositories\s*\{[^\n]*\n/.exec(gradle)
  if (match) {
    const at = match.index + match[0].length
    return gradle.slice(0, at) + line + gradle.slice(at)
  }
  return `${gradle}\nallprojects {\n  repositories {\n${line}  }\n}\n`
}

const PROVIDERS = ['mapkit', 'google', 'mapbox', 'maplibre', 'cesium']

function list(value, where) {
  if (value == null) return []
  if (!Array.isArray(value)) {
    throw new TypeError(`munim-maps: ${where} must be an array of providers`)
  }
  for (const provider of value) {
    if (!PROVIDERS.includes(provider)) {
      throw new TypeError(
        `munim-maps: unknown provider "${provider}" in ${where} (${PROVIDERS.join(', ')})`
      )
    }
  }
  return value
}

function providersFor(options, platform) {
  const all = [
    ...list(options.providers, 'providers'),
    ...list(options[platform]?.providers, `${platform}.providers`),
  ]
  // MapKit is always there on iOS and does not exist on Android.
  return [...new Set(all)].filter((p) => p !== 'mapkit')
}

/** `cesium: { bundled: true }`: CesiumJS in the app instead of from jsDelivr. */
function cesiumBundled(options, providers) {
  return providers.includes('cesium') && options.cesium?.bundled === true
}

function keyFor(value, platform) {
  if (value == null) return undefined
  if (typeof value === 'string') return value
  return value[platform]
}

function setMetaData(application, name, value) {
  if (value) {
    AndroidConfig.Manifest.addMetaDataItemToMainApplication(
      application,
      name,
      value
    )
  } else {
    AndroidConfig.Manifest.removeMetaDataItemFromMainApplication(
      application,
      name
    )
  }
}

function withMunimMapsIos(config, options) {
  const providers = providersFor(options, 'ios')
  config = withPodfileProperties(config, (c) => {
    if (providers.length > 0) {
      c.modResults['munimMaps.providers'] = providers.join(',')
    } else {
      delete c.modResults['munimMaps.providers']
    }
    if (cesiumBundled(options, providers)) {
      c.modResults['munimMaps.cesiumBundled'] = 'true'
    } else {
      delete c.modResults['munimMaps.cesiumBundled']
    }
    return c
  })
  config = withInfoPlist(config, (c) => {
    const entries = {
      MunimMapsGoogleMapsApiKey: keyFor(options.googleMapsApiKey, 'ios'),
      MBXAccessToken: options.mapboxAccessToken,
      MunimMapsCesiumIonToken: options.cesiumIonToken,
    }
    for (const [key, value] of Object.entries(entries)) {
      if (value) c.modResults[key] = value
    }
    return c
  })
  return config
}

function withMunimMapsAndroid(config, options) {
  const providers = providersFor(options, 'android')
  config = withGradleProperties(config, (c) => {
    const props = c.modResults
    for (const provider of PROVIDERS.filter((p) => p !== 'mapkit')) {
      const key = `munimMaps.${provider}`
      const index = props.findIndex(
        (item) => item.type === 'property' && item.key === key
      )
      if (index >= 0) props.splice(index, 1)
      if (providers.includes(provider)) {
        props.push({ type: 'property', key, value: 'true' })
      }
    }
    // Google's photorealistic 3D map SDK (google={{ mode: '3d' }}).
    const index3d = props.findIndex(
      (item) =>
        item.type === 'property' && item.key === 'munimMaps.googleMaps3d'
    )
    if (index3d >= 0) props.splice(index3d, 1)
    if (options.googleMaps3d && providers.includes('google')) {
      props.push({
        type: 'property',
        key: 'munimMaps.googleMaps3d',
        value: 'true',
      })
    }
    // CesiumJS in the APK (cesium: { bundled: true }).
    const indexCesium = props.findIndex(
      (item) =>
        item.type === 'property' && item.key === 'munimMaps.cesiumBundled'
    )
    if (indexCesium >= 0) props.splice(indexCesium, 1)
    if (cesiumBundled(options, providers)) {
      props.push({
        type: 'property',
        key: 'munimMaps.cesiumBundled',
        value: 'true',
      })
    }
    return c
  })
  config = withAndroidManifest(config, (c) => {
    const application = AndroidConfig.Manifest.getMainApplicationOrThrow(
      c.modResults
    )
    setMetaData(
      application,
      'com.google.android.geo.API_KEY',
      keyFor(options.googleMapsApiKey, 'android')
    )
    setMetaData(
      application,
      'munimmaps.cesium_ion_token',
      options.cesiumIonToken
    )
    return c
  })
  if (providers.includes('mapbox')) {
    config = withProjectBuildGradle(config, (c) => {
      if (c.modResults.language === 'groovy') {
        c.modResults.contents = addMapboxMaven(c.modResults.contents)
      }
      return c
    })
  }
  if (options.mapboxAccessToken) {
    config = withStringsXml(config, (c) => {
      c.modResults = AndroidConfig.Strings.setStringItem(
        [
          AndroidConfig.Resources.buildResourceItem({
            name: 'mapbox_access_token',
            value: options.mapboxAccessToken,
            translatable: false,
          }),
        ],
        c.modResults
      )
      return c
    })
  }
  return config
}

/**
 * Bundling CesiumJS copies it from the app's own `cesium` package at build
 * time (munim-maps does not ship it): say so at prebuild when that package
 * is missing or not the version the engine is written for.
 */
function checkBundledCesium(config, options) {
  const bundled = ['ios', 'android'].some((platform) =>
    cesiumBundled(options, providersFor(options, platform))
  )
  if (!bundled) return
  const {
    resolveCesium,
    versionWarning,
  } = require('./scripts/cesium/copy-cesium')
  try {
    const warning = versionWarning(
      resolveCesium({ root: config._internal?.projectRoot ?? process.cwd() })
    )
    if (warning) console.warn(`munim-maps: ${warning}`)
  } catch (error) {
    console.warn(`munim-maps: ${error.message}`)
  }
}

module.exports = function withMunimMaps(config, options = {}) {
  checkBundledCesium(config, options)
  config = withMunimMapsIos(config, options)
  config = withMunimMapsAndroid(config, options)
  return config
}

module.exports.addMapboxMaven = addMapboxMaven
