# munim-maps-vehicles

The [munim-maps](https://github.com/munimtechnologies/munim-maps) vehicle catalogue: 57 detailed, tintable 3D models (cars, vans, trucks, buses, bikes, scooters, motorcycles, trams and trains, boats, airliners, jets, a helicopter, a balloon, rockets, Starbase and satellites), each as USDZ and GLB. Generated from code, with no logos or brand names; paint recolours with `tint`, models face north at heading 0, are sized in real metres and sit on the ground.

munim-maps itself ships no models, so an app only gets the ones it shows: from a CDN, cached on the device, or bundled one model at a time.

## Installation

```bash
npx expo install munim-maps-vehicles   # Expo
npm install munim-maps-vehicles        # React Native CLI
```

## From a CDN (default)

```tsx
import { MunimMapView } from 'munim-maps'
import { VEHICLES } from 'munim-maps-vehicles'

<MunimMapView
  initialCamera={camera}
  models={[{ id: 'ride', coordinate, source: VEHICLES['car-ev'], tint: '#E5484D', heading: 90, screenSize: 15 }]}
/>
```

`VEHICLES[name]` is `{ uri, usdz, glb }`: the model on [jsDelivr](https://www.jsdelivr.com) at this package's version (`https://cdn.jsdelivr.net/npm/munim-maps-vehicles@<version>/usdz/<name>.usdz` and `/glb/<name>.glb`). munim-maps picks the format the engine draws (USDZ where its SceneKit layer draws the model on iOS, GLB for Mapbox's and Cesium's own models and on Android), downloads it the first time it is shown and keeps it in the app's cache folder, so it works offline afterwards. The versioned URLs never change, so an app keeps getting the models it was built with.

Self-host by copying the package's `usdz/` and `glb/` folders to your server:

```ts
import { configureMunimMapsVehicles } from 'munim-maps-vehicles'

configureMunimMapsVehicles({ baseUrl: 'https://cdn.example.com/vehicles/' }) // before rendering maps
```

## Bundled in the app

For models that must work offline from the first launch, import them one by one. Each import pulls in only that model's file:

```tsx
import carEv from 'munim-maps-vehicles/bundled/car-ev'        // USDZ on iOS, GLB on Android
import carEvGlb from 'munim-maps-vehicles/bundled/glb/car-ev' // GLB everywhere (Mapbox's or Cesium's own models on iOS)

{ id: 'ride', coordinate, source: carEv, tint: '#E5484D', screenSize: 15 }
```

Metro has to know the extensions:

```js
// metro.config.js
config.resolver.assetExts.push('usdz', 'glb')
```

## API

| Export | |
| --- | --- |
| `VEHICLES` | Every model by name, as a remote source `{ uri, usdz, glb }` |
| `VEHICLE_NAMES`, `VehicleName` | The names and their type |
| `vehicleSource(name)` | `VEHICLES[name]`, throwing for an unknown name |
| `configureMunimMapsVehicles({ baseUrl })` | Where the models load from (`undefined`: jsDelivr) |
| `MUNIM_MAPS_VEHICLES_VERSION` | The version the URLs point at |
| `munim-maps-vehicles/bundled/<name>` | One bundled model: USDZ on iOS, GLB elsewhere |
| `munim-maps-vehicles/bundled/glb/<name>` | One bundled model as GLB on every platform |

Swift apps (munim-maps' Swift Package): `MunimVehicles.url("car-ev")` (USDZ) and `MunimVehicles.glbURL("car-ev")` point at the same files; `MunimVehicles.baseURL` self-hosts them.

The catalogue, with pictures of every model, is in the [munim-maps README](https://github.com/munimtechnologies/munim-maps#-vehicle-catalogue). The models are built by `scripts/vehicles/make-vehicles.swift` in the munim-maps repository:

```bash
swiftc -O scripts/vehicles/make-vehicles.swift -o /tmp/make-vehicles
/tmp/make-vehicles packages/munim-maps-vehicles/usdz packages/munim-maps-vehicles/glb
node scripts/vehicles/write-catalogue.mjs   # names, bundled entries, Swift names
```

## License

Apache-2.0
