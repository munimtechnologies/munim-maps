// The vehicle catalogue moved to its own package in munim-maps 0.5.0, so
// apps that do not use it no longer download 34 MB of models with
// munim-maps (and apps that do no longer bundle all 57).
//
//   npm install munim-maps-vehicles
//   import { VEHICLES } from 'munim-maps-vehicles'            // from a CDN, cached on device
//   import carEv from 'munim-maps-vehicles/bundled/car-ev'     // one model inside the app
//
// This entry stays only to say so.
throw new Error(
  "munim-maps: the vehicle catalogue moved to the munim-maps-vehicles package. Install it (npm install munim-maps-vehicles) and import { VEHICLES } from 'munim-maps-vehicles' (models load from a CDN and are cached on the device), or import a single model into the app with import car from 'munim-maps-vehicles/bundled/car-ev'. See the munim-maps README, Vehicle Catalogue."
)
