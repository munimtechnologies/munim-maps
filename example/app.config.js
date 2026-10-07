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

module.exports = ({ config }) => ({
  ...config,
  // The Google screen's web-service check (Places, Geocoding, Routes) needs
  // the key in JavaScript; it is only in local builds, never committed.
  extra: { ...(config.extra ?? {}), googleMapsApiKey: keys.GOOGLE_MAPS_API_KEY || undefined },
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
})
