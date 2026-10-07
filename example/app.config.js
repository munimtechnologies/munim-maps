// Adds munim-maps' config plugin to app.json, with development keys read at
// build time (never committed): from example/.env.local, else
// ~/.config/munim-maps/keys.env. Both are KEY=value files:
//   GOOGLE_MAPS_API_KEY=…
//   MAPBOX_ACCESS_TOKEN=pk.…
//   CESIUM_ION_TOKEN=…
// Engines to build in besides MapKit (iOS) and MapLibre (Android):
//   MUNIM_MAPS_PROVIDERS=google,mapbox npx expo prebuild
// (or MUNIM_MAPS_PROVIDERS in one of the files above).
const fs = require('fs')
const os = require('os')
const path = require('path')

function readEnvFile(file) {
  try {
    const values = {}
    for (const line of fs.readFileSync(file, 'utf8').split('\n')) {
      const match = /^\s*(?:export\s+)?([A-Z0-9_]+)\s*=\s*(.*?)\s*$/.exec(line)
      if (!match) continue
      values[match[1]] = match[2].replace(/^(['"])(.*)\1$/, '$2')
    }
    return values
  } catch {
    return {}
  }
}

const keys = {
  ...readEnvFile(path.join(os.homedir(), '.config/munim-maps/keys.env')),
  ...readEnvFile(path.join(__dirname, '.env.local')),
}
const providers = (process.env.MUNIM_MAPS_PROVIDERS ?? keys.MUNIM_MAPS_PROVIDERS ?? '')
  .split(',')
  .map((p) => p.trim())
  .filter(Boolean)

// react-native-maps registers its Google map component whenever the
// GoogleMaps pod is in the app (which munim-maps' Google engine adds), so
// its Google subspec has to be built too, or the app crashes at launch
// (RCTThirdPartyComponentsProvider: RNMapsGoogleMapView missing).
function withReactNativeMapsGoogle(config) {
  if (!providers.includes('google')) return config
  let plugins
  try {
    plugins = require('expo/config-plugins')
  } catch {
    plugins = require('@expo/config-plugins')
  }
  return plugins.withPodfile(config, (c) => {
    const line =
      "  pod 'react-native-maps/Google', :path => File.dirname(`node --print \"require.resolve('react-native-maps/package.json')\"`)"
    if (!c.modResults.contents.includes("react-native-maps/Google")) {
      c.modResults.contents = c.modResults.contents.replace(
        /(\n\s*use_expo_modules!\n)/,
        `$1${line}\n`
      )
    }
    return c
  })
}

// Models from a local server before munim-maps-vehicles is published
// (EXPO_PUBLIC_MUNIM_MAPS_VEHICLES_BASE_URL=http://localhost:8000/ with
// `adb reverse tcp:8000 tcp:8000` on Android): release builds refuse
// cleartext http unless the manifest allows it.
function withLocalVehicleServer(config) {
  if (!/^http:\/\//.test(process.env.EXPO_PUBLIC_MUNIM_MAPS_VEHICLES_BASE_URL ?? '')) return config
  let plugins
  try {
    plugins = require('expo/config-plugins')
  } catch {
    plugins = require('@expo/config-plugins')
  }
  return plugins.withAndroidManifest(config, (c) => {
    const app = plugins.AndroidConfig.Manifest.getMainApplicationOrThrow(c.modResults)
    app.$['android:usesCleartextTraffic'] = 'true'
    return c
  })
}

// @rnmapbox/maps (Android only here, see react-native.config.js) resolves
// the Mapbox SDK from Mapbox's Maven repository, which munim-maps' plugin
// only adds with its own Mapbox engine.
function withMapboxMaven(config) {
  if (providers.includes('mapbox')) return config
  let plugins
  try {
    plugins = require('expo/config-plugins')
  } catch {
    plugins = require('@expo/config-plugins')
  }
  return plugins.withProjectBuildGradle(config, (c) => {
    const url = 'https://api.mapbox.com/downloads/v2/releases/maven'
    if (!c.modResults.contents.includes(url)) {
      c.modResults.contents += `\nallprojects {\n  repositories {\n    maven { url '${url}' }\n  }\n}\n`
    }
    return c
  })
}

module.exports = ({ config }) => withMapboxMaven(withLocalVehicleServer(withReactNativeMapsGoogle({
  ...config,
  // The Google screen's web-service check (Places, Geocoding, Routes) needs
  // the key in JavaScript; it is only in local builds, never committed.
  // The @rnmapbox/maps screen (Android) sets its token from here too.
  extra: {
    ...(config.extra ?? {}),
    googleMapsApiKey: keys.GOOGLE_MAPS_API_KEY || undefined,
    mapboxAccessToken: keys.MAPBOX_ACCESS_TOKEN || undefined,
  },
  plugins: [
    ...(config.plugins ?? []),
    [
      'munim-maps',
      {
        providers,
        googleMapsApiKey: keys.GOOGLE_MAPS_API_KEY || undefined,
        mapboxAccessToken: keys.MAPBOX_ACCESS_TOKEN || undefined,
        cesiumIonToken: keys.CESIUM_ION_TOKEN || undefined,
        // Android: Google's photorealistic 3D SDK for google={{ mode: '3d' }}.
        googleMaps3d: true,
      },
    ],
  ],
})))
