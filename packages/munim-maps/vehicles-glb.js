// The vehicle catalogue moved to its own package in munim-maps 0.5.0. Its
// sources carry both formats and munim-maps picks GLB where an engine needs
// glTF, so there is no separate GLB entry any more.
//
//   npm install munim-maps-vehicles
//   import { VEHICLES } from 'munim-maps-vehicles'
//   import carEv from 'munim-maps-vehicles/bundled/glb/car-ev'  // one GLB inside the app
throw new Error(
  "munim-maps: munim-maps/vehicles-glb moved to the munim-maps-vehicles package. Install it (npm install munim-maps-vehicles) and use VEHICLES from 'munim-maps-vehicles' (munim-maps picks GLB where the engine draws glTF), or bundle one GLB with import car from 'munim-maps-vehicles/bundled/glb/car-ev'."
)
