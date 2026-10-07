import { configureMunimMapsVehicles } from 'munim-maps-vehicles'

// munim-maps-vehicles loads models from jsDelivr. To test a build before the
// package is published (or to self-host), build with
// EXPO_PUBLIC_MUNIM_MAPS_VEHICLES_BASE_URL=http://<mac>:8000/ and serve
// packages/munim-maps-vehicles there (python3 -m http.server 8000).
const baseUrl = process.env.EXPO_PUBLIC_MUNIM_MAPS_VEHICLES_BASE_URL
if (baseUrl) configureMunimMapsVehicles({ baseUrl })
