// Expo config plugin for munim-maps: chooses the map engines built into the
// app and writes their keys into the native config.
//
//   ["munim-maps", {
//     "providers": ["google", "maplibre"],        // engines besides MapKit (iOS) / MapLibre (Android)
//     "ios": { "providers": ["mapbox"] },           // per platform, added to `providers`
//     "android": { "providers": ["cesium"] },
//     "googleMapsApiKey": "…" | { "ios": "…", "android": "…" },
//     "mapboxAccessToken": "pk.…",
//     "cesiumIonToken": "…"
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
  withStringsXml,
} = plugins

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

module.exports = function withMunimMaps(config, options = {}) {
  config = withMunimMapsIos(config, options)
  config = withMunimMapsAndroid(config, options)
  return config
}
