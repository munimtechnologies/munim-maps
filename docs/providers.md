# Map providers

munim-maps draws the same React Native API (`MunimMapView`, models, markers, shapes, camera, events) on five map engines, on iOS and Android:

| Provider | `provider=` | iOS | Android | Key |
| --- | --- | --- | --- | --- |
| Apple MapKit | `'mapkit'` | Built in, the default | — (Apple only) | None |
| Google Maps | `'google'` | ✅ `NitroMunimMaps/Google` subspec; photorealistic 3D with `munimMaps.googleMaps3d` (`NitroMunimMaps/Google3D`, Google's `GoogleMaps3D` Swift package) | ✅ `munimMaps.google=true` (the default when on); photorealistic 3D with `munimMaps.googleMaps3d=true` | Google Maps SDK key |
| Mapbox | `'mapbox'` | ✅ `NitroMunimMaps/Mapbox` subspec (Mapbox Maps SDK 11.32) | ✅ `munimMaps.mapbox=true` (11.32, `android-ndk27`) | Mapbox public token (`pk.…`) |
| MapLibre (open maps) | `'maplibre'` | ✅ `NitroMunimMaps/MapLibre` subspec (MapLibre Native 6.30+) | ✅ Built in (`munimMaps.maplibre=false` to drop it); the default without Google | None: OpenStreetMap data from [OpenFreeMap](https://openfreemap.org) |
| Cesium | `'cesium'` | ✅ `NitroMunimMaps/Cesium` subspec (CesiumJS 1.146 in a WKWebView, from jsDelivr or bundled) | ✅ `munimMaps.cesium=true` (in a WebView) | None: OpenStreetMap imagery, ellipsoid. A Cesium ion token adds terrain, Bing imagery, OSM Buildings and ion assets |

Engines other than MapKit (iOS) and MapLibre (Android) are opt-in at build time, so an app only ships the SDKs it uses. An engine that is not built in, or not implemented yet, shows a placeholder saying so and reports it through `onError`.

## Using it

```tsx
import { MunimMapView, configureMunimMaps } from 'munim-maps'
import { VEHICLES } from 'munim-maps-vehicles' // from a CDN; munim-maps picks USDZ or GLB per engine

configureMunimMaps({
  mapboxAccessToken: 'pk.…',          // or the config plugin / Info.plist / strings.xml
  cesiumIonToken: '…',
  googleMapsApiKey: '…',              // iOS; Android reads the manifest
  defaultProvider: 'maplibre',         // for maps without `provider`
})

<MunimMapView
  provider="google"                   // 'mapkit' | 'google' | 'mapbox' | 'maplibre' | 'cesium'
  styleUrl="https://tiles.openfreemap.org/styles/liberty" // MapLibre / Mapbox
  google={{ mapId: '…' }}             // options only one engine reads
  mapbox={{ projection: 'globe' }}
  maplibre={{ projection: 'globe' }}
  cesium={{ terrain: 'world', photorealistic: true }}
  initialCamera={{ latitude: 41.88, longitude: -87.63, distance: 900, pitch: 55, heading: 30 }}
  models={[{ id: 'bus', coordinate: { latitude: 41.883, longitude: -87.628 }, source: VEHICLES['bus-city'] }]}
  modelRendering="auto"                // the engine draws models when it can, else munim-maps' 3D layer
  onProviderEvent={({ provider, name, data }) => {}} // events only this engine has
/>
```

- `provider` defaults to `'mapkit'` on iOS; on Android to `'google'` when the Google engine is built in, else `'maplibre'`. `configureMunimMaps({ defaultProvider })` changes it.
- `availableProviders()` lists the engines that are built in and work; `installedProviders()` the ones whose SDK is built in; `isProviderAvailable(p)`; `MAP_PROVIDERS` lists all five.
- Every existing prop, event and method keeps its meaning on every engine. Options only one engine has go in that engine's prop (`google`, `mapbox`, `maplibre`, `cesium`, `mapkit`); they reach the native engine as JSON (`providerOptions`), so engines add options without changing the shared spec. Their TypeScript types are in `src/providers/<provider>.ts`.

### Expo config plugin

```json
["munim-maps", {
  "providers": ["google", "mapbox"],
  "ios": { "providers": ["cesium"] },
  "android": { "providers": [] },
  "googleMapsApiKey": { "ios": "…", "android": "…" },
  "mapboxAccessToken": "pk.…",
  "cesiumIonToken": "…",
  "cesium": { "bundled": false },
  "googleMaps3d": false
}]
```

- **iOS**: writes `munimMaps.providers` (and `munimMaps.cesiumBundled`, `munimMaps.googleMaps3d`) to `ios/Podfile.properties.json`; the podspec turns those subspecs on (`NitroMunimMaps/Google`…). With `googleMaps3d` it also adds Google's `GoogleMaps3D` Swift package to the app target in the Xcode project (see the Google 3D notes below). Keys go to Info.plist: `MunimMapsGoogleMapsApiKey`, `MBXAccessToken`, `MunimMapsCesiumIonToken`. With the Google engine the pod needs iOS 16.
- **Android**: writes `munimMaps.<provider>=true` (and `munimMaps.googleMaps3d`, `munimMaps.cesiumBundled`) to `android/gradle.properties`; `android/build.gradle` adds that engine's source set and SDK. With Mapbox it adds Mapbox's Maven repository (public, no secret token) to the app's `android/build.gradle` `allprojects.repositories`. Keys go to the manifest (`com.google.android.geo.API_KEY`, `munimmaps.cesium_ion_token` meta-data) and `mapbox_access_token` in strings.xml.
- `cesium: { bundled: true }` puts CesiumJS (13 MB) in the app, copied from the app's own `cesium` npm package (`npm install cesium@1.146.0`; prebuild warns when it is missing or another version); by default the Cesium engine loads it from jsDelivr the first time and keeps it on disk (see [Cesium engine](#cesium-engine)).
- `googleMaps3d: true` adds Google's photorealistic 3D SDK (`google={{ mode: '3d' }}`) on both platforms: the Maps 3D SDK for iOS (Swift package) and for Android.

### Without Expo

- **iOS**: `pod 'NitroMunimMaps/Google', :path => '../node_modules/munim-maps'` (and `/Mapbox`, `/MapLibre`, `/Cesium`) in the Podfile, or `MUNIM_MAPS_PROVIDERS=google,maplibre pod install`. `MUNIM_MAPS_CESIUM_BUNDLED=1` bundles CesiumJS from the app's `cesium` package (`MUNIM_MAPS_CESIUM_DIR=<folder>` for another one). The Google engine needs iOS 16; for Google's photorealistic 3D map set `"munimMaps.googleMaps3d": "true"` in `ios/Podfile.properties.json` (or `MUNIM_MAPS_GOOGLE_MAPS_3D=1 pod install`) next to the Google engine, and add the `GoogleMaps3D` product of `https://github.com/googlemaps/ios-maps-3d-sdk` (exact version 1.0.0) to the app target in Xcode (File > Add Package Dependencies), so the app embeds its framework. Apps that also use react-native-maps need `pod 'react-native-maps/Google'` (react-native-maps registers its Google map whenever the GoogleMaps pod is present, and the app stops at launch without it).
- **Android**: `munimMaps.google=true` (and `mapbox`, `cesium`; `maplibre=false` to drop MapLibre; `googleMaps3d`, `cesiumBundled` with `cesiumDir` to copy CesiumJS from somewhere else than the app's `cesium` package) in `android/gradle.properties`. With Mapbox, add `maven { url 'https://api.mapbox.com/downloads/v2/releases/maven' }` to `allprojects.repositories` in `android/build.gradle`. SDK versions can be pinned with `munimMaps.maplibreVersion`, `munimMaps.googleMapsVersion`, `munimMaps.googleMapsUtilsVersion`, `munimMaps.googleMaps3dVersion`, `munimMaps.mapboxVersion`, `munimMaps.filamentVersion`.

## Shared API across engines

### Who draws the models: `modelRendering`

`modelRendering` on `MunimMapView` (`'auto'` by default) says who draws `models`:

| Engine | `auto` | `native` | `overlay` |
| --- | --- | --- | --- |
| MapKit (iOS) | munim-maps' 3D layer (SceneKit) | the 3D layer (MapKit has no 3D models) | the 3D layer |
| Google 2D map (iOS, Android) | the 3D layer | the 3D layer, with an `onError` saying so | the 3D layer |
| Google 3D map (`google={{ mode: '3d' }}`, iOS and Android) | Google's glTF `Model`s | Google's models | Google's models, with an `onError` (its camera has no projection the overlay can follow) |
| Mapbox (iOS, Android) | Mapbox's `model` layer for still glTF bodies; the 3D layer for animated files, labels, stems, effects, occluders, USDZ and shapes | every glTF body in Mapbox; their labels, stems and effects on the 3D layer | everything on the 3D layer |
| MapLibre (iOS, Android) | the 3D layer | the 3D layer | the 3D layer |
| Cesium (iOS, Android) | Cesium entities and glTF models for everything Cesium can draw (avatars, labels, stems, shapes, effects, zones and paths too); USDZ / SCN / OBJ files and occluders on the 3D layer | everything as Cesium entities (USDZ and occluders skipped) | everything on the 3D layer over the WebView |

Native models are lit and shadowed with the map and hidden by its own buildings and terrain; the 3D layer draws over the map (with `occlusion="buildings"` to hide models behind buildings). `google.modelRendering`, `mapbox.modelRendering` and `cesium.modelRendering` are aliases (the shared prop wins); Cesium's older `modelRenderer` still works. Natively, every engine takes the app's 3D content through one hook with defaults: `setModels` / `setZones` / `setPaths` (Swift `MunimMapEngine`, Kotlin `MunimMapEngine`): an engine draws what it can and hands the rest to `modelLayer`; `modelLayerDidChange()` tells it the layer's lighting, occlusion, terrain or distance settings changed.

### Engine-only methods and events

Every engine adds methods and events without changing the shared spec, through one channel:

- `ref.current.providerCommand(command, argsJson)` resolves with JSON text; `providerCommand(ref.current, command, args)` parses it. Typed wrappers: `googleMap(ref)`, `mapboxMap(ref)`, `maplibreCommands(ref)`, `cesiumCommands(ref)`.
- `onProviderEvent({ provider, name, data })` on `MunimMapView`, `data` parsed from JSON. Narrow it with `googleEvent(event)`, `parseCesiumEvent(event)`, `MapLibreEventName`, `MapboxMapOptions.events`.
- `callProvider(provider, command, args)` and `addProviderEventListener(provider, listener)` for engine-level commands that need no map (Mapbox's offline downloads), through `MunimMapsConfig`.
- Native: Swift `MunimMapEngine.providerCommand(_:arguments:completion:)` (JSON-compatible values) and `setProviderEventHandler(_:)`; Kotlin `MunimMapEngine.providerCommand(command, args: JSONObject, completion)` (JSON text) and `MunimMapEngineListener.onProviderEvent(name, json)`; `MunimMapEngineFactory.providerCommand(…)` on both for map-less commands. The host sends `ProviderEvent { provider, name, json }` to JavaScript. Everything has a default (reject / drop).

### Markers and regions

- `onMarkerDrag`: a dragged marker's position while it moves, between `onMarkerDragStart` and `onMarkerDragEnd`, on every engine: MapKit (a display link reads the dragged view, since MapKit only sets the coordinate on drop), Google (`mapView(_:didDrag:)`, `OnMarkerDragListener.onMarkerDrag`), Mapbox, MapLibre, Cesium (the page's drag handler). Natively `MunimMapEngine.onMarkerDrag` (Swift) and `MunimMapEngineListener.onMarkerDrag` (Kotlin), defaulted.
- `MarkerView` on Android: `MunimMapView` keeps its children off screen next to the map (Android's Nitro views cannot hold React children); each `MarkerView` draws its children into a bitmap (again on every change with `tracksViewChanges`) and calls `MunimMapEngine.setViewMarker` / `setViewMarkerImage` / `removeViewMarker`. Mapbox shows it as a view annotation; Google, MapLibre and Cesium as an image marker with the marker's `anchor`, `zIndex`, callout, taps and dragging.
- react-native-maps' region API: `initialRegion`, a controlled `region` (the map jumps to it when it changes; the region reported by `onRegionChangeComplete` does not move it again), `onRegionChangeStart`, `onRegionChangeComplete(region)` and `ref.animateToRegion(region, ms)`. They are built on `setRegion`, `getVisibleRegion` and the camera events, so they work on every engine (`munimmapsexample://providers/<provider>/check`: 5 of 5 on every engine on the iPad). Mapbox and MapLibre keep the camera's pitch and heading when they frame a region, so on a pitched map the visible region (and what `onRegionChangeComplete` reports) is larger than the region asked for. `initialCamera` is optional when a region is given.
- `selectableMapFeatures` reaches every engine on both platforms (`setSelectableMapFeatures` on Android): MapKit's places, Google's POIs, Mapbox Standard's featuresets (POIs, landmarks, place labels), MapLibre's OpenMapTiles layers, Cesium's 3D Tiles features.

### Models: the vehicle catalogue and remote files

- munim-maps ships no models. The vehicle catalogue (57 tintable models) is the `munim-maps-vehicles` package: `VEHICLES[name]` is a source with both formats on jsDelivr at the package's version (`{ uri, usdz, glb }`); munim-maps picks USDZ where its SceneKit layer draws the model on iOS (MapKit, MapLibre, the Google 2D map, or `modelRendering: 'overlay'`) and GLB where the engine draws glTF itself (Mapbox, Cesium) and on Android. `munim-maps-vehicles/bundled/<name>` bundles one model in the app instead (USDZ on iOS, GLB elsewhere; `bundled/glb/<name>` is GLB everywhere). `configureMunimMapsVehicles({ baseUrl })` points the catalogue at your own server.
- Remote models (`http(s)://`) are downloaded once and kept in the app's cache folder (iOS `Caches/munim-maps`, Android `cache/munim-maps`), named by a hash of the URL, so a map works offline after its first load. The SceneKit and Filament layers, Mapbox's model layer and Cesium all read the cached file. Metro's development server (port 8081) is always read fresh. Google's 3D map downloads its models itself.

### Coming from react-native-maps (and @rnmapbox/maps)

What an app moving off react-native-maps (MapKit on iOS) or @rnmapbox/maps (Mapbox Standard on Android) needs, engine by engine. ✅ works · 🔨 built, not yet checked on a device · 🟡 partly (note) · — not in the SDK.

| Need | munim-maps | MapKit | Google | Mapbox | MapLibre | Cesium |
| --- | --- | --- | --- | --- | --- | --- |
| Controlled `region`, `initialRegion` | `region`, `initialRegion` (JavaScript, on `setRegion`) | ✅ | ✅ | ✅ | ✅ | ✅
| `onRegionChangeStart`, `onRegionChangeComplete(region)` | same names (from the camera events + `getVisibleRegion`) | ✅ | ✅ | ✅ | ✅ | ✅
| `animateToRegion(region, ms)` | `ref.animateToRegion` (= `setRegion(region, ms)`) | ✅ | ✅ | ✅ | ✅ | ✅ |
| `animateCamera({ pitch }, { duration })` | `animateCamera({ ...(await getCamera()), pitch }, ms, 'easeInOut')` (a whole camera, in metres) | ✅ | ✅ | ✅ | ✅ | ✅ |
| `fitToCoordinates(coords, { edgePadding, animated })` | `fitToCoordinates(coords, edgePadding, animated)` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `mapType` standard / hybrid with 3D | `mapStyle="standard" \| "hybrid"`, `elevation="realistic"`, `showsBuildings` | ✅ | 🟡 hybrid, no 3D terrain (Google 2D) | ✅ Standard / Standard Satellite with terrain | 🟡 satellite needs your own tiles (`maplibre.satelliteTilesUrl`) | ✅ Bing (token) or Esri imagery on terrain |
| `showsUserLocation`, `showsCompass`, `pitchEnabled`, `rotateEnabled`, `scrollEnabled`, `zoomEnabled`, `testID` | same | ✅ | ✅ | ✅ | ✅ | ✅ |
| Markers with React children: `anchor`, `zIndex`, `tracksViewChanges`, title, description, `onPress` | `MarkerView` | ✅ | ✅ | ✅ (view annotations) | ✅ | ✅
| Draggable markers: drag start, continuous drag, drag end | `draggable`, `onMarkerDragStart`, `onMarkerDrag`, `onMarkerDragEnd` | 🔨 continuous drag new | ✅ | ✅ | ✅ | ✅ Android · 🔨 iOS
| `Circle`, `Polygon`, `Polyline` with stroke and fill | `circles`, `polygons`, `polylines` | ✅ | ✅ | ✅ | ✅ | ✅ |
| Dashes `[4, 10]`, `[6, 4]` | `dashPattern` | ✅ | 🟡 iOS draws them as spans in metres · ✅ Android | ✅ | ✅ | ✅ |
| Follow the user with heading, re-armed by setting the mode again | `userTrackingMode="followWithHeading"` + `onUserTrackingModeChange` | ✅ | 🟡 munim-maps follows (Google has no tracking modes) | ✅ Mapbox viewport | ✅ location component | ✅ |
| User puck with a heading cone and a pulse | `showsUserLocation` + the engine's puck options | ✅ MapKit's own (heading beam while following with heading) | 🟡 Google's blue dot (no cone or pulse options) | ✅ `mapbox.puck` (`bearing: 'heading'`, `pulsing`) | 🟡 Android: `maplibre.location` `pulse`, compass render mode; iOS: MapLibre's heading indicator | 🟡 a dot drawn by the page; heading follows the camera |
| 3D models, globe and lighting in the same map | `models`, `globe`, `lighting` | ✅ (globe: a private switch) | 🟡 no globe | ✅ | 🟡 no globe (MapLibre Native) | ✅ |

## Feature matrix

✅ works · 🔨 built and compiled, not yet checked on a device · 🟡 partly (see note) · — does not apply. MapKit is iOS only; Android's 3D layer is Filament, iOS's is SceneKit, and both read the same camera state from every engine.

| Feature | MapKit iOS | Google iOS | Google Android | Mapbox iOS | Mapbox Android | MapLibre iOS | MapLibre Android | Cesium iOS | Cesium Android |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Map on screen | ✅ | ✅ | 🔨 | ✅ | 🔨 | ✅ | ✅ | ✅ | ✅ |
| `styleUrl` / built-in styles (`mapStyle`) | ✅ styles | ✅ map types, JSON styles, `styleUrl` = JSON style | 🔨 | ✅ | 🔨 | ✅ | ✅ `styleUrl` | ✅ `mapStyle`, `cesium.imagery` | ✅ `mapStyle`, `cesium.imagery` |
| Dark mode (`colorScheme`) | ✅ | ✅ | 🔨 | ✅ | 🔨 | ✅ | 🔨 | ✅ | ✅ |
| 3D buildings, terrain (`elevation`, `showsBuildings`) | ✅ | ✅ buildings; no terrain | 🔨 | ✅ | 🔨 | 🟡 buildings, no 3D terrain | 🟡 buildings, no 3D terrain | ✅ ion token | ✅ ion token |
| Globe (`globe`) | ✅ | — | — | ✅ | 🔨 | — (not in MapLibre Native) | — | ✅ always | ✅ always |
| `initialCamera`, `setCamera`, `animateCamera`, `getCamera` | ✅ | ✅ | 🔨 | ✅ | 🔨 | ✅ | ✅ | ✅ | ✅ |
| `flyCamera` / `stopFlight` | ✅ | ✅ | 🔨 | ✅ | 🔨 | ✅ | 🟡 built, not yet device-checked | ✅ | ✅ |
| `setRegion`, `getVisibleRegion`, `fitToCoordinates` | ✅ | ✅ | 🔨 | ✅ | 🔨 | ✅ | ✅ | ✅ | ✅ |
| `pointForCoordinate`, `coordinateForPoint` | ✅ | ✅ | 🔨 | ✅ | 🔨 | ✅ | ✅ | ✅ | ✅ |
| Gestures on/off | ✅ | ✅ | 🔨 | ✅ | 🔨 | ✅ | ✅ | ✅ | ✅ |
| Camera limits, boundary, `mapPadding` | ✅ | ✅ | 🔨 | ✅ | 🔨 | ✅ | 🔨 | ✅ | ✅ |
| `onMapReady`, `onPress`, `onLongPress`, `onCameraMove`, `onCameraChange` | ✅ | ✅ | 🔨 | ✅ | 🔨 | ✅ | ✅ | ✅ | ✅ |
| Markers (pin, balloon, image, avatar, label, dot), callouts, dragging | ✅ | ✅ | 🔨 | ✅ | 🔨 | ✅ | 🔨 | ✅ | ✅ |
| Clustering (`clusteringId`, `clusterStyles`) | ✅ | ✅ Utils | 🔨 | ✅ | 🔨 | ✅ | 🔨 | ✅ | ✅ |
| `MarkerView` (React Native views as markers) | ✅ | ✅ | 🔨 | ✅ | 🔨 | ✅ | 🔨 | ✅ | 🔨 |
| `onMarkerDrag` (continuous drag) | 🔨 | ✅ | 🔨 | ✅ | 🔨 | ✅ | 🔨 | 🔨 | 🔨 |
| `region`, `initialRegion`, `onRegionChangeStart`, `onRegionChangeComplete`, `animateToRegion` | ✅ | ✅ | 🔨 | ✅ | 🔨 | ✅ | 🔨 | ✅ | 🔨 |
| `modelRendering` (engine-drawn models) | — overlay only | ✅ 3D mode | 🔨 3D mode | ✅ | 🔨 | — overlay only | — overlay only | ✅ | ✅ |
| Polylines, polygons, circles | ✅ | ✅ | 🔨 | ✅ | 🔨 | ✅ | 🔨 | ✅ | ✅ |
| Gradient / animated polylines, overlay taps | ✅ | ✅ | 🔨 | ✅ | 🔨 | ✅ | 🔨 | ✅ | ✅ |
| Tile overlays | ✅ | ✅ | 🔨 | ✅ | 🔨 | ✅ | 🔨 | ✅ | ✅ |
| User location, tracking modes | ✅ | 🟡 tracking by munim-maps | 🔨 | ✅ | 🔨 | ✅ | 🔨 | ✅ | ✅ |
| Compass, scale, tracking button | ✅ | 🟡 compass, my-location button; no scale | 🔨 | ✅ | 🔨 | ✅ | 🔨 | ✅ | ✅ |
| Points of interest filter, traffic | ✅ | ✅ | 🔨 | 🟡 POI labels all or none; traffic ✅ | 🔨 | 🟡 POIs, no traffic data | 🟡 POIs, no traffic data | — | — |
| Tappable places (`onMapFeaturePress`) | ✅ | ✅ POIs (place IDs) | 🔨 | ✅ Standard featuresets | 🔨 Standard featuresets | ✅ | 🔨 | 🟡 3D Tiles features | 🟡 3D Tiles features |
| Place cards (`selectionAccessory`), Look Around | ✅ | 🟡 Street View for Look Around | 🟡 Street View for Look Around; phone test pending | — | — | — | — | — | — |
| `takeSnapshot`, `addressForCoordinate` | ✅ | ✅ | 🔨 | ✅ | 🔨 | ✅ | 🔨 | ✅ | ✅ |
| 3D models: GLB / glTF | ✅ | ✅ | 🔨 | ✅ | 🔨 | ✅ | ✅ | ✅ Cesium | ✅ Cesium |
| 3D models: USDZ, USD, SCN, OBJ… | ✅ | ✅ | — | ✅ | — | ✅ | — | ✅ native layer | — |
| Model heading, altitude, scale, `screenSize`, `tint`, spin, `motion` | ✅ | ✅ | 🔨 | ✅ | 🔨 | ✅ | ✅ | ✅ | ✅ |
| Built-in shapes, pictures (avatars), labels, stems, `lift` | ✅ | ✅ | 🔨 | ✅ | 🔨 | ✅ | ✅ | ✅ | ✅ |
| Effects (exhaust, smoke, contrail), occluders | ✅ | ✅ | 🔨 | ✅ | 🔨 | ✅ | ✅ | ✅ (occluders: native layer) | ✅ (occluders: native layer) |
| Zones, paths | ✅ | ✅ | 🔨 | ✅ | 🔨 | ✅ | ✅ | ✅ | ✅ |
| `occlusion="buildings"` | ✅ | ✅ | 🔨 | ✅ | 🔨 | ✅ | ✅ | ✅ real depth | ✅ real depth |
| Terrain (`altitudeReference: 'sea'`, `followTerrain`, `groundElevation`) | ✅ | ✅ sea level (Google 2D has no terrain) | 🔨 | ✅ | 🔨 | ✅ | 🟡 built, not yet device-checked | ✅ Cesium terrain | ✅ Cesium terrain |
| `onModelPress` | ✅ | ✅ | 🔨 | ✅ | 🔨 | ✅ | ✅ | ✅ | ✅ |
| `measureAlignment` (3D layer vs the engine's own projection) | ✅ | ✅ ≤ 1.7 pt (iPad) | 🔨 | ✅ | 🔨 | ✅ | ✅ | ✅ | ✅ |
| `MapModelLayer` over another library's map | ✅ react-native-maps, expo-maps | — | ✅ react-native-maps (≤ 0.35 pt; no `onModelPress`) | — | ✅ `@rnmapbox/maps` (≤ 0.09 pt, padding included) | — | — | — | — |
| MapKit services (search, directions, geocoding) | ✅ | — | — | — | — | — | — | — | — |

## Architecture

```
MunimMapView (JS)  ──provider, props──▶  HybridMunimMapView (Swift / Kotlin)
                                            │
                                            ▼
                                   MunimMapContainerView ── one engine at a time
                                            │
           ┌──────────────┬──────────────┬──┴───────────┬──────────────┐
         MapKit         Google         Mapbox        MapLibre        Cesium      (MunimMapEngine)
           │ map view + 2D features with its own SDK
           │ MapCameraSource ──MapCameraState every frame──▶ MunimModelLayer (3D: SceneKit on iOS, Filament on Android)
```

### iOS (`packages/munim-maps/ios/`)

| File | What |
| --- | --- |
| `Engines/MunimMapEngine.swift` | `MunimMapProvider`, the `MunimMapEngine` protocol (props, events, camera, methods) and `MunimMapEngineDefaults` (adopt it for "not supported yet" defaults) |
| `Engines/MunimMapEngines.swift` | Registry: `installed`, `available`, `make(provider)`; the `#if canImport(…)` switch over each engine's factory |
| `Engines/MunimMapContainerView.swift` | Hosts one engine, swaps on provider change |
| `Engines/UnavailableMapEngine.swift` | The placeholder |
| `Engines/MunimMapsConfiguration.swift` | Keys and default styles (JS `configureMunimMaps`, Info.plist) |
| `Core/MapCameraState.swift` | The camera every engine describes: centre, distance, altitude, pitch, heading, viewport, focal length (field of view), centre point, globe, terrain, dark; scene positions (Web Mercator / sphere) and projection; optional exact matrices |
| `Core/MapCameraSource.swift` | What an engine gives the 3D layer: `cameraView`, `cameraState(previous:)`, `screenPoint(for:)`, `visibleRegion()` |
| `Core/MunimModelLayer.swift`, `Core/MapModelRenderer.swift` | The SceneKit 3D layer; `attach(to: MapCameraSource)` |
| `Engines/MapKit/` | The MapKit engine (`MunimMapKitView`, the reference implementation; it does not adopt the defaults, so the compiler checks it implements everything) and `MapKitCameraSource` |
| `Engines/Google/`, `Mapbox/`, `MapLibre/`, `Cesium/` | One folder per engine, each wrapped in `#if canImport(GoogleMaps)` / `MapboxMaps` / `MapLibre` / `#if MUNIM_MAPS_CESIUM`, compiled only with its subspec |
| `Engines/Google3D/` | Google's photorealistic 3D map (`GoogleMap3DMode`, the SwiftUI `GoogleMaps3D` map in a `UIHostingController`), wrapped in `#if MUNIM_MAPS_GOOGLE3D && canImport(GoogleMaps3D)`, compiled only with the `NitroMunimMaps/Google3D` subspec; the Google engine reaches it through `Google3DMode` |
| `Core/GLBInfo.swift` | A glTF file's height (for `screenSize`), `paint*` materials and animations, read by engines that draw glTF themselves; `GLBInfo.tinted` recolours `paint*` materials in a GLB copy |

### Android (`packages/munim-maps/android/`)

| File | What |
| --- | --- |
| `src/main/java/com/munimmaps/engine/MunimMapEngine.kt` | `MunimMapEngine` interface (setters, camera, methods, all with defaults), `MunimMapEngineListener` (events), `MunimMapEngineFactory` |
| `…/engine/MunimMapEngines.kt` | Registry; finds `com.munimmaps.engines.<provider>.<Name>MapEngineFactory` by name (kept by `proguard-rules.pro`) |
| `…/engine/MunimMapContainerView.kt`, `UnavailableMapEngine.kt`, `MunimMapsConfiguration.kt` | Host, placeholder, keys |
| `…/engine/MapCameraState.kt`, `MapCameraSource.kt` | The same camera model as iOS, in pixels |
| `…/engine/MapViewAdapters.kt` | Adapters that let `MapModelLayer` draw over other libraries' map views, found by class name |
| `src/googleView/java/…/engines/google/GoogleCamera.kt` | Google's camera from its projection (the Google engine's and react-native-maps'), and the adapter for a Google `MapView` munim-maps does not own |
| `src/mapboxView/java/…/engines/mapbox/MapboxMapViewAdapter.kt` | The adapter for a Mapbox `MapView` munim-maps does not own (`@rnmapbox/maps`) |
| `…/models/MunimModelLayer.kt`, `ModelRenderer.kt`, `ModelAssets.kt` | The Filament 3D layer (transparent TextureView, gltfio), asset loading (Metro URLs, raw and drawable resources, files, assets) |
| `…/models/ModelMeshes.kt`, `ModelMaterials.kt`, `ModelBitmaps.kt` | Geometry built on the CPU (shapes, quads, stems, walls, ribbons), materials from gltfio's ubershader (no extra compiled materials), the Canvas-drawn pictures (avatars, labels, shadow, puffs) |
| `…/models/ModelEffects.kt`, `BuildingOccluder.kt`, `TerrainElevation.kt`, `CameraFlight.kt` | Particle effects, building occlusion (vector tiles), `MunimTerrain` (Terrarium tiles), `flyCamera` on the layer's frame clock |
| `…/com/margelo/nitro/munimmaps/Hybrid*.kt` | The Nitro views and `MunimMapsConfig` |
| `src/<provider>/java/com/munimmaps/engines/<provider>/` | One source set per engine, compiled only when `munimMaps.<provider>=true` (MapLibre: on by default) |
| `src/googleView/java`, `src/mapboxView/java` | `MapModelLayer`'s adapters, compiled with their engine or when react-native-maps / `@rnmapbox/maps` is a Gradle project of the app (the SDK `compileOnly`, at the version `@rnmapbox/maps` builds with); `munimMaps.googleView` / `munimMaps.mapboxView` override |

## The Android 3D layer

`MunimModelLayer` on Android (Filament 1.75.1) matches iOS's SceneKit layer feature for feature, and only reads `MapCameraState`, so every Android engine that provides a `MapCameraSource` gets all of it. The reference is iOS's `MapModelRenderer.swift`, `MapModelNodes.swift`, `MunimModelLayer.swift`, `BuildingOccluder.swift` and `TerrainElevation.swift`.

| iOS 3D layer feature | Android | How |
| --- | --- | --- |
| GLB / glTF models, heading, altitude, scale, spin, `motion` | ✅ | gltfio assets; glTF models turned half a turn as iOS's `GLTFLoader` does; the same keyframe maths (`pose`) |
| Embedded animations (`playAnimations`) | ✅ | gltfio `Animator`, looped on the frame clock |
| `screenSize`, `lift`, `tint` (materials named `paint…`), `groundShadow` | ✅ | Scaled by depth / focal length each frame; tint on `baseColorFactor`; a soft shadow quad under the model |
| USDZ, USD, SCN, OBJ… | — | Apple formats; `munim-maps-vehicles` sources resolve to GLB on Android |
| Built-in shapes (`box`, `sphere`, `cylinder`, `cone`, `capsule`, `pyramid`, `gem`), `color`, `emissive`, see-through colours | ✅ | Meshes built on the CPU, lit with gltfio's ubershader (as iOS: `capsule` is SceneKit's 1 × 1 capsule, a sphere stretched to `size`; the box has no chamfer) |
| Pictures (`image`, `imageBorder`, `badge`), always facing the camera, drawn over buildings | ✅ | The avatar bitmap drawn with Canvas exactly as iOS draws it, on a camera-facing quad in Filament channel 3 with depth testing off |
| Labels (22 pt pill, 4 pt above the model), stems (2 pt line, 8 pt dot) | ✅ | Same sizes, drawn on top |
| Effects: `exhaust`, `smoke`, `contrail`, `effectIntensity`, `effectOrigins` | ✅ | iOS's SceneKit particle systems simulated on the CPU (same birth rates, lives, sizes, growth, speeds, spreads, colour ramps, damping, plumes stopping at the ground, contrails thrown back at the model's speed) and drawn as sorted camera-facing puffs; shock diamonds as glowing spheres |
| `occluder` models | ✅ | Depth only, drawn first (channel 1) |
| Zones (walls with solid bands, fading up) | ✅ | Same geometry and colours |
| Paths (3D ribbons, fixed width in points, `closed`, on the globe) | ✅ | Rebuilt every frame to face the camera, as iOS |
| `occlusion="buildings"`, `buildingTilesUrl` | ✅ | Kotlin port of the vector-tile decoder; z14 OpenMapTiles `building` walls (OpenFreeMap by default) in depth only, within 9 km, nine tiles nearest first, cached in the app's cache folder |
| Globe: the Earth hides the far side | ✅ | A depth-only sphere when `MapCameraState.globe` |
| Terrain: `altitudeReference: 'sea'`, `followTerrain`, `groundElevation()` | ✅ (built; not yet checked on the phone) | `MunimTerrain` in Kotlin (Terrarium PNG tiles, zoom 14, bilinear, memory + disk cache, read without colour management); lifting onto drawn terrain needs an engine that sets `drawsTerrain` |
| `lighting` (`auto` follows the map's dark mode) | ✅ | Sun + ambient light, as phase 1 |
| `maxCameraDistance` | ✅ | |
| `onModelPress` / `modelHit` | ✅ | iOS's hit test (bounding radius, 22 pt slop, nearest wins) |
| `measureAlignment` | ✅ | `modelsVisibleInRender` counts models whose bounds are on screen (iOS reads the rendered pixels) |
| `flyCamera` / `stopFlight` | ✅ every engine (built; not yet checked on the phone) | `MunimMapEngine`'s default steps the keyframes on the layer's frame clock with `setCamera`, before the layer reads the camera, so the map and the models move together; other camera calls stop it |
| `realisticElevation`, `globe` on `MapModelLayer` | — | MapKit switches |
| `MapModelLayer` over another library's map | ✅ react-native-maps (Google), `@rnmapbox/maps` | `MapViewAdapters` finds the library's map view; the layer's view is laid over it before every draw; camera read every frame (no listeners on the library's map); map padding: Mapbox moves its centre of perspective, so `MapCameraState.principalX/Y` and Filament's camera shift; Google's padded camera is picked from two models by its own projection |

Additive blending (the exhaust core and shock diamonds) is exact: unlit blended ubershader materials output premultiplied colour, so a zero alpha adds. Textures are uploaded as linear premultiplied half floats for the same reason.

## Building an engine (checklist)

Each provider works only inside its own folders, so engines can be built in parallel:

- iOS: `ios/Engines/<Name>/`, and the subspec block for it in `NitroMunimMaps.podspec`.
- Android: `android/src/<provider>/`, and that provider's dependency lines in `android/build.gradle`.
- JavaScript: `src/providers/<provider>.ts` (its options type).
- Docs: its columns in the matrix above, its README section.

Shared files (`MunimMapEngine.swift/.kt`, `MapCameraState`, the model layers, the specs) change only by agreement. If an engine needs a new hook, add it with a default so no other engine has to change.

For each engine:

1. **Map**: host the SDK's view filling the engine view; lifecycle (Android `onStart`/`onResume`/`onPause`/`onStop`/`onDestroy` on attach/detach/destroy); keys from `MunimMapsConfiguration`; style from `styleUrl` / options.
2. **3D layer**: own a `MunimModelLayer`, put its view over the map, `attach` it to a `MapCameraSource` that fills `MapCameraState` from the SDK's camera: centre, distance in metres (from zoom: `distance = height / 2 / tan(fov / 2) × metres per point`, with the SDK's tile size: 256 for Google, 512 for Mapbox and MapLibre), pitch, heading, viewport, focal length from the vertical field of view, the centre point (view centre, or shifted by padding), `globe`, `drawsTerrain`, `darkAppearance`. Engines with an exact matrix (Mapbox / MapLibre custom layers, Cesium) can pass it (`cameraTransformOverride`, `projectionOverride` on iOS). Tell the layer to redraw from the SDK's camera-move callback.
3. **Check it**: `measureAlignment()` compares the 3D layer's projection of every model's ground point with the SDK's own `screenPoint`; aim for under a point or two at several zooms, pitches and headings.
4. **Taps**: ask the model layer first (`modelHit` / `handleTap`), then report `onPress`.
5. **Props and methods**: everything in `MunimMapEngine` the SDK can do: markers (reuse `MarkerImages` on iOS for the pin, avatar, label and dot images), shapes, overlays, camera, controls, gestures, user location, snapshots, events. What it cannot do keeps the default (`onError` "not supported yet") and gets a — or note in the matrix.
6. **Provider extras**: options in `src/providers/<provider>.ts`, read natively from `providerOptions`.
7. **Flip it on**: `isImplemented = true` in the engine's factory; fill its matrix columns.
8. **Test** in the example: `munimmapsexample://providers/<provider>` (iOS: `MUNIM_MAPS_PROVIDERS=<provider> npx expo prebuild`, then build; Android: the same variable before prebuild, or `munimMaps.<provider>=true` in `example/android/gradle.properties`). Keys come from `example/.env.local` or `~/.config/munim-maps/keys.env`, never committed. On iOS, keep the MapKit self-test (plain launch) at 47/47.

## Testing

- **Example deep links** (checks never run on their own, except the MapKit self-test on a plain iOS launch, `Documents/munim-maps-selftest.json`, which includes the MapKit parity screen's checks):
  - `munimmapsexample://providers[/<provider>][/check]`: the engine picker, which opens every other screen (Android starts here); `/check` runs the shared region checks on that engine (`Documents/munim-maps-shared-checks-<provider>.json`, `MUNIM_MAPS_SHARED` log lines).
  - `munimmapsexample://google[/3d][/checks]` (`Documents/munim-maps-google-checks.json`; `/3d`: Google's photorealistic 3D map, `munim-maps-google-3d-checks.json` with the iOS map's `map3dDiagnostics`), `mapbox[/checks|/native]` (`munim-maps-mapbox-checks.json`), `maplibre[/check]` (`munim-maps-maplibre-check.json`), `cesium[/checks]` (`munim-maps-cesium-checks.json`): each engine's screen with every feature group; the suffix runs its checks.
  - `munimmapsexample://layer3d[/<provider>][/check][/cam/lat,lon,distance,pitch,heading][/noocclusion]`: every 3D layer group on one engine.
  - `munimmapsexample://layer/<rnmapbox|rnmaps-google>[/check|/pan|/pan45|/pan45pad][/tex]` (Android): `MapModelLayer` over `@rnmapbox/maps` or react-native-maps (Google). `/check` sets the host's camera with its own API at seven poses (the last with 160 points of padding) and through a host animation, and measures the layer against the host's projection (`MUNIM_MAPS_LAYER_OVER` lines). `/pan…` shows a probe (the host's magenta circle under munim-maps' green tile, pitched 45° and padded with `pan45pad`, the Mapbox map in a TextureView with `/tex`): `example/scripts/layer-pan.sh` drags the map and saves frames during the drag, `example/scripts/layer-probe.py` measures circle and tile on each frame, `example/scripts/run-check.sh` runs any deep link and keeps its log.
  - `munimmapsexample://parity`, `terrain`, `expomaps`, `features`, `globe`, `cities`, `orbit`, `demo/<shot>`, `lagtest` (iOS).
  - Models come from munim-maps-vehicles on jsDelivr; before it is published, build with `EXPO_PUBLIC_MUNIM_MAPS_VEHICLES_BASE_URL=<url>` and serve `packages/munim-maps-vehicles` there (`python3 -m http.server`, or a tunnel to it). A fast compile check of the engine code without the SDKs: typecheck `ios/Core` and `ios/Engines` with `swiftc -typecheck -sdk iphonesimulator`, adding empty stand-in modules named `GoogleMaps`, `MapboxMaps`, `MapLibre` (`-I`) and `-D MUNIM_MAPS_CESIUM` to compile every engine's stub.
- **Android 3D layer**: `munimmapsexample://layer3d/<provider>` shows every 3D group on one engine; add `/check` (or tap Run checks) to measure the layer against the engine at six cameras and four points of a `flyCamera` flight (`adb logcat | grep MUNIM_MAPS_LAYER3D`). `cam/lat,lon,distance,pitch,heading` sets the camera, `noocclusion` turns building occlusion off.
- **Integration build (0.5.0 candidate), iPad Air M3, iPadOS 27.0.1, every engine in one Release build, models from munim-maps-vehicles over the network, CesiumJS from jsDelivr**: MapKit self-test 47/47, Google checks 30/30, Mapbox 38/38, MapLibre 27/27, Cesium 26/26, shared region checks 5/5 on each of the five engines. Android (the same release APK with every engine, arm64 Google Play emulator, API 35; no phone was on USB; models from munim-maps-vehicles over the network, CesiumJS from jsDelivr): MapLibre 27/27, Google 30/30 (Places, Geocoding and Routes answer), Mapbox 38/38 (the offline tile-region check timed out in 2 of 6 runs on the emulator's network), Cesium 26/26, shared region checks 5/5 on each of the four engines, the 3D layer on MapLibre within 0.46 pt at six cameras and a `flyCamera` flight; continuous `onMarkerDrag` (11 to 12 events per drag), `MarkerView`, taps, effects and building occlusion checked by hand on every engine; CesiumJS bundled from the app's `cesium` package loads with no network (23/26: the three failures are tiles and geocoding). Not checked on the emulator: Google's photorealistic 3D map (its Google Play services cannot download the Maps 3D module; checked on the phone below), the GPS-driven puck heading.
- **0.5.0 release candidate, physical phone (Samsung Galaxy A14 SM-S146VL, Android 15), release APK with every engine**: Google 30/30, Google photorealistic 3D 6/6 (native Google 3D models), Mapbox 38/38, MapLibre 27/27, Cesium 25/26 and shared region checks 5/5 on Google, Mapbox and MapLibre (Cesium 4/5): the two Cesium misses are timing flakes on this slow phone, where Cesium's camera settles late; the 3D layer on MapLibre within 0.41 pt; `MarkerView` and continuous `onMarkerDrag` on all four engines. iPad (same candidate): MapKit 47/47, Google 30/30, Mapbox 38/38, MapLibre 27/27, Cesium 26/26, region checks 5/5 on all five; one vehicle at the same `screenSize` draws within 3% of the same size on MapKit, Mapbox and Cesium.
- **`MapModelLayer` over other libraries' maps (0.5.1 candidate), Galaxy A14 SM-S146VL, Android 15, release APK**: `@rnmapbox/maps` 10.3.7 (Mapbox 11.32 with every engine built in; 11.23.1, `@rnmapbox/maps`' own, with munim-maps' Google and Mapbox engines off) within 0.09 pt of Mapbox's projection at seven cameras (one with 160 points of padding) and 14 samples of a camera animation; react-native-maps 1.27.2 (Google) within 0.35 pt (0.19 pt padded, animation 0.29 pt), field of view measured at 30°. Screenshots during drags (`layer-pan.sh` + `layer-probe.py`, a 30 m circle drawn by the host under munim-maps' 16 m tile): within 2 pt during a 2.5-second drag on both, pitched 45° and padded included, 0 to 0.8 pt once the map stops; a fast 1.2-second flick on Mapbox was one frame apart (4.5 pt) mid-drag. Taps on models over `@rnmapbox/maps` fire `onModelPress`. munim-maps' own engines on the same build: Mapbox checks 38/38, Google 30/30, 3D layer on Mapbox within 0.10 pt and on Google within 0.56 pt.
- **Google photorealistic 3D on iOS (0.5.1 candidate), iPad Air M3, iPadOS 27.0.1, Release build with every engine plus `NitroMunimMaps/Google3D` (GoogleMaps3D 1.0.0 through the pod's `spm_dependency` and the app target), models from munim-maps-vehicles over the network**: Google 3D checks 6/6 (munim models drawn by Google, checked on screenshots: upright, heading 0 facing north, `tint` and `screenSize` applied, `motion` moving in place, changed models redrawn), Google 2D checks 30/30, MapKit self-test 47/47. Not checked unattended: camera reporting from touch gestures (the camera binding), place taps, and what a key without the Maps 3D SDK for iOS shows.
- **Android**: the example starts on the engine picker (MapLibre by default) and logs `MUNIM_MAPS_PROVIDERS … alignment {…}` every 3 s (`adb logcat | grep MUNIM_MAPS`). Build with `./gradlew :app:assembleRelease -PreactNativeArchitectures=arm64-v8a` (from `example/android`, after `npx expo prebuild --platform android`) for an arm64 phone or emulator. Phase 1 was checked on an Android 15 phone: MapLibre with the GLB vehicles, 3D layer within 0.41 pt of MapLibre's own projection.

## Google Maps engine checklist

Every public capability of the Maps SDK for iOS (`GoogleMaps` 10.x, CocoaPods) and the Maps SDK for Android (`play-services-maps` 20.x), plus Google Maps Utils (iOS `Google-Maps-iOS-Utils` 7.x, Android `android-maps-utils` 3.20 by default), mapped to munim-maps. Shared props and methods work as on every engine; Google-only options go in `google={{ … }}` (`GoogleMapOptions`, `src/providers/google.ts`), Google-only events arrive in `onProviderEvent` (`provider: 'google'`, typed as `GoogleMapEvent`) and Google-only methods go through `providerCommand` (typed wrapper: `googleMap(ref)`). Status: ✅ done · 🟡 partly (see note) · — not offered, with the reason · ⏳ not done yet. iOS was checked on an iPad (the Google screen's 30 checks: 30 passed, 3D layer within 1.7 pt of Google's projection at five cameras; the photorealistic 3D map's 6 checks passed with Google drawing munim models natively). Android was checked on a Galaxy A14 (Android 15): the same 30 checks passed, and the photorealistic 3D map's 6 checks passed with Google drawing munim models natively.

| SDK capability (iOS / Android API) | munim-maps API | iOS | Android |
| --- | --- | --- | --- |
| **Map** | | | |
| Map view (`GMSMapView(options:)` / `MapView` + lifecycle) | `provider="google"` | ✅ | ✅ |
| API key (`GMSServices.provideAPIKey` / manifest `com.google.android.geo.API_KEY`) | `configureMunimMaps({ googleMapsApiKey })`, Info.plist `MunimMapsGoogleMapsApiKey`, Expo plugin `googleMapsApiKey` | ✅ | ✅ |
| Map types normal / satellite / hybrid / terrain / none (`mapType`) | `mapStyle` (`standard`, `hybrid`, `imagery`) or `google.mapType` | ✅ | ✅ |
| Cloud-based map styling, Map ID (`GMSMapID` / `GoogleMapOptions.mapId`) | `google.mapId` (applied when the map is created) | ✅ | ✅ |
| JSON styling (`GMSMapStyle(jsonString:)` / `MapStyleOptions`) | `google.styleJson` (string or array) | ✅ | ✅ |
| Dark mode (`overrideUserInterfaceStyle` / `setMapColorScheme`) | `colorScheme` | ✅ | ✅ |
| 3D buildings (`buildingsEnabled`) | `showsBuildings` | ✅ | ✅ |
| Traffic, transit (`trafficEnabled`, `transitEnabled`) | `showsTraffic`, `google.transitEnabled` | ✅ | ✅ |
| Points of interest on/off and by category | `pointsOfInterest` (`'none'` or categories, as a JSON style; not with `mapId`) | ✅ | ✅ |
| Indoor maps (`indoorEnabled`), level picker | `google.indoorEnabled`, `google.indoorLevelPicker` | ✅ | ✅ |
| Active building / level events (`GMSIndoorDisplayDelegate` / `OnIndoorStateChangeListener`) | events `indoorBuildingFocused`, `indoorLevelActivated` | ✅ | ✅ |
| Set the active level (`indoorDisplay.activeLevel` / `IndoorLevel.activate()`) | commands `setIndoorLevel`, `getIndoorBuilding` | ✅ | ✅ |
| Lite mode (`GoogleMapOptions.liteMode`) | `google.liteMode` | — Android only | ✅ |
| Background colour, frame rate (`backgroundColor`, `preferredFrameRate`) | `google.backgroundColor`, `google.preferredFrameRate` (iOS) | ✅ | ✅ |
| Map capabilities (`mapCapabilities` + change event) | command `getMapCapabilities`, event `mapCapabilitiesChanged` | ✅ | 🟡 no sprite-polyline flag on Android |
| Accessibility (`accessibilityElementsHidden` / `setContentDescription`) | `google.accessibilityElementsHidden`, `google.contentDescription` | ✅ | ✅ |
| **Controls and gestures** | | | |
| Compass (`compassButton` / `setCompassEnabled`) | `compassVisibility` (Google shows it only while rotated) | ✅ | ✅ |
| My location layer + button (`myLocationEnabled`, `myLocationButton`) | `showsUserLocation`, `showsUserTrackingButton` or `google.myLocationButton` | ✅ | ✅ |
| Zoom controls (`setZoomControlsEnabled`) | `google.zoomControls` | — Android only | ✅ |
| Map toolbar (`setMapToolbarEnabled`) | `google.mapToolbar` | — Android only | ✅ |
| Scroll / zoom / tilt / rotate gestures | `scrollEnabled`, `zoomEnabled`, `pitchEnabled`, `rotateEnabled` | ✅ | ✅ |
| Scroll during rotate or zoom | `google.scrollGesturesDuringRotateOrZoom` | ✅ | ✅ |
| Consumes gestures in view (`consumesGesturesInView`) | `google.consumesGesturesInView` | ✅ | — iOS only |
| Scale bar | `scaleVisibility` | — not in the SDK | — not in the SDK |
| User tracking (follow, follow with heading) | `userTrackingMode` (munim-maps follows location updates; Google has no tracking mode) | 🟡 follows `myLocation`; heading from the compass | 🟡 follows the location; heading from its bearing |
| **Camera** | | | |
| Camera position (target, zoom, bearing, tilt) | `initialCamera`, `setCamera`, `getCamera` (metres; zoom converted with 256-point tiles); commands `moveCamera`, `animateCamera`, `getCameraPosition` in Google's units | ✅ | ✅ |
| Animations with durations (`CATransaction` + `animate` / `animateCamera(update, ms, cb)`) | `animateCamera(camera, ms, easing)`, `flyCamera`, `setRegion(r, ms)` | ✅ | ✅ |
| Camera updates: zoom in / out / by / to, scroll by, fit bounds | commands `zoomIn`, `zoomOut`, `zoomBy`, `zoomTo`, `scrollBy`; `fitToCoordinates`, `fitToMarkers` | ✅ | ✅ |
| Stop animation (`stopAnimation`) | `stopFlight`, command `stopAnimation` | ✅ | ✅ |
| Padding (`padding`, `paddingAdjustmentBehavior`) | `mapPadding`, `google.paddingAdjustmentBehavior` (iOS) | ✅ | ✅ |
| Min / max zoom (`setMinZoom:maxZoom:` / `setMin/MaxZoomPreference`) | `cameraDistanceRange`, or `google.minZoom` / `google.maxZoom` | ✅ | ✅ |
| Camera target bounds (`cameraTargetBounds` / `setLatLngBoundsForCameraTarget`) | `cameraBoundary`, or `google.cameraTargetBounds` | ✅ | ✅ |
| Projection: point ↔ coordinate, visible region (four corners), metres → points | `pointForCoordinate`, `coordinateForPoint`, `getVisibleRegion`, command `getProjection` | ✅ | ✅ |
| **Events** | | | |
| Map ready, map loaded (`OnMapLoadedCallback` / first tiles rendered) | `onMapReady`, event `mapLoaded` | ✅ | ✅ |
| Camera move started (with reason), move, idle, cancelled | event `cameraMoveStarted` (`gesture`, `apiAnimation`, `developerAnimation`), `onCameraMove`, `onCameraChange`, event `cameraMoveCanceled` (Android) | ✅ | ✅ |
| Tap, long press | `onPress`, `onLongPress` | ✅ | ✅ |
| POI tap (`didTapPOIWithPlaceID` / `OnPoiClickListener`) | `onMapFeaturePress` (`id` is the place ID), event `poiClick` | ✅ | ✅ |
| Tiles rendering started / finished (iOS) | events `tilesRenderingStarted`, `tilesRenderingFinished` | ✅ | — iOS only |
| My location button / dot taps | events `myLocationButtonPress`, `myLocationPress` | ✅ | ✅ |
| User location changes | `onUserLocationChange` | ✅ | ✅ |
| **Markers** | | | |
| Default marker, coloured (`markerImageWithColor` / `defaultMarker(hue)`) | `style: 'pin'`, `color` | ✅ | ✅ |
| Icon images, view icons (`icon`, `iconView`) | `style: 'image' / 'avatar' / 'label' / 'dot' / 'marker'`, `MarkerView` | ✅ | ✅ |
| Anchors, info window anchor (`groundAnchor`, `infoWindowAnchor`) | `anchor`, `google.markers[id].infoWindowAnchor` | ✅ | ✅ |
| Info windows: title + snippet, custom windows (`markerInfoWindow` / `InfoWindowAdapter`) | `title`, `description`, `calloutDetail`; accessories drawn in a custom window | 🟡 one tap target (Google draws them as pictures) | 🟡 one tap target |
| Info window tap / long press / close | `onCalloutPress`, events `infoWindowLongPress`, `infoWindowClose` | ✅ | ✅ |
| Draggable, drag start / drag / end | `draggable`, `onMarkerDragStart`, event `markerDrag`, `onMarkerDragEnd` | ✅ | ✅ |
| Flat, rotation, opacity, zIndex, visible | `google.markers[id].flat`, `.rotation`, `opacity`, `zIndex`, `visible` | ✅ | ✅ |
| Appear animation (`appearAnimation`) | `animatesWhenAdded` | ✅ | — not in the SDK |
| Advanced markers with pins (`GMSAdvancedMarker` + `GMSPinImageOptions` / `AdvancedMarkerOptions` + `PinConfig`): background, border, glyph text, colour or image | automatic for `pin` / `marker` on a map with a `mapId`; `google.markers[id].pin` | 🟡 built; needs a Map ID, not exercised on device | 🟡 built; needs a Map ID, not exercised on device |
| Collision behaviour (`collisionBehavior`) | `displayPriority` + `collisionMode`, or `google.markers[id].collisionBehavior` | 🟡 advanced markers only (Map ID) | 🟡 advanced markers only (Map ID) |
| Select / deselect (`selectedMarker` / `showInfoWindow`) | `selectMarker`, `deselectMarker`, `onMarkerPress`, `onMarkerDeselect` | ✅ | ✅ |
| Clustering (Utils `GMUClusterManager` / `ClusterManager`) | `clusteringId`, `clusterStyles`, `onClusterPress`, `google.clusterAlgorithm` | ✅ | ✅ |
| **Shapes and overlays** | | | |
| Polylines: colour, width, geodesic, zIndex, tappable | `polylines` | ✅ | ✅ |
| Stroke spans and gradients (`GMSStyleSpan` / `StyleSpan`) | `strokeColors` + `strokeColorLocations`, `google.polylines[id].spans` | ✅ | ✅ |
| Patterns (dash / gap / dot) | `dashPattern`, `google.polylines[id].pattern` (iOS draws them as spans) | 🟡 spans in metres, redone on zoom | ✅ |
| Caps and joints (`startCap`, `endCap`, `jointType`) | `lineCap`, `lineJoin`, `google.polylines[id].startCap` / `endCap` | — not in the iOS SDK | ✅ |
| Texture stamps (`GMSTextureStyle`, `GMSSpriteStyle` / `TextureStyle`, `SpriteStyle`) | `google.polylines[id].stamp` | ✅ | ✅ |
| Partial lines | `strokeStart`, `strokeEnd` | ✅ | ✅ |
| Polygons with holes, geodesic, stroke pattern and joints | `polygons`, `google.polygons[id]` | 🟡 no stroke patterns or joints in the iOS SDK | ✅ |
| Circles | `circles` | ✅ | ✅ |
| Overlay taps | `onOverlayPress`, `overlayAtPoint` | ✅ | ✅ |
| Ground overlays (an image on the ground: bounds, or position + width; bearing, opacity, anchor, tappable) | `google.groundOverlays`, event `groundOverlayPress` | ✅ | ✅ |
| Tile overlays: URL templates, opacity, zIndex, fade-in, tile size, clear cache | `tileOverlays` (`{x}`, `{y}`, `{z}`, `{-y}`, `{quadkey}`), `google.tileOverlays[id]`, command `clearTileCache` | ✅ | ✅ |
| Custom tile providers (`GMSSyncTileLayer` / `TileProvider`) | `file://` templates from JavaScript; native code: the engine's `customTileLayers` hook | ✅ | ✅ |
| Heatmaps, weighted, gradients (Utils) | `google.heatmaps` | ✅ | ✅ |
| KML layers (Utils) | `google.kmlLayers`, event `kmlFeaturePress` | ✅ | ✅ |
| GeoJSON layers (Utils) | `google.geoJsonLayers`, event `geoJsonFeaturePress` | ✅ | ✅ |
| Data-driven styling for boundaries (feature layers: country, admin areas 1 and 2, locality, postal code, school district) | `google.featureLayers` (needs a `mapId` with those layers on), event `featureClick` | 🟡 built; needs a Map ID with the layers on, not testable with the dev key | 🟡 same |
| Data-driven styling for datasets | `google.featureLayers[].datasetId` | 🟡 built; needs a dataset on the Cloud project | 🟡 same |
| **Street View** | | | |
| Panorama view (`GMSPanoramaView` / `StreetViewPanoramaView`) near a coordinate, by ID, radius, outdoor source | `openLookAround` (Street View on this engine), command `streetView.open` | ✅ | ✅ |
| Coverage check (`GMSPanoramaService` / panorama location) | `hasLookAround`, command `streetView.hasCoverage` | ✅ | ✅ |
| Panorama camera (heading, pitch, zoom, FOV), animated | command `streetView.setCamera` | ✅ | ✅ |
| Links, navigation, gestures, street names | `streetView.open` options, command `streetView.moveTo` | ✅ | ✅ |
| Panorama events (change, camera, tap, error) | events `streetViewChange`, `streetViewCamera`, `streetViewTap`, `streetViewError` | ✅ | ✅ |
| **Snapshot and services** | | | |
| Snapshot | `takeSnapshot` | ✅ | ✅ |
| Reverse geocoding (`GMSGeocoder`; Android has none in the SDK, so `android.location.Geocoder`) | `addressForCoordinate` | ✅ (falls back to Apple's geocoder) | ✅ |
| Geometry utils (distance, heading, offset, area, encode / decode polylines, contains / on-edge) | `googleGeometry` (JavaScript, Google's formulas) | ✅ | ✅ |
| SDK version, open-source licences | command `sdkInfo` | ✅ | ✅ |
| Places (autocomplete, place details, text / nearby search, photos) | `googlePlaces` (Places API (New) web service, your key) | 🟡 built; the dev key has no Places API | 🟡 same |
| Geocoding, Routes (directions, route matrix) | `googleGeocoding`, `googleRoutes` (web services, your key; better from your server) | 🟡 built; the dev key has neither API | 🟡 same |
| **3D** | | | |
| munim 3D layer (models, paths, zones, effects) on Google's camera | `models`, `paths`, `zones`, `measureAlignment` | ✅ | ✅ |
| Photorealistic 3D maps (Maps 3D SDK): camera, fly-to / fly-around, glTF models, polylines, polygons, markers, map mode, clicks | `google.mode: '3d'` (+ `modelRendering`, `map3dMode`, `modelScale`), `googleMap(ref).flyTo` / `flyAround` / `stopCameraAnimation` / `getCamera3d` / `setCamera3d`, events `map3dReady`, `map3dSteady`, `cameraAnimationEnd`, `modeChange` | ✅ `GoogleMaps3D` 1.0 (Swift package, `munimMaps.googleMaps3d`): 6/6 on an iPad, munim models drawn by Google | ✅ `play-services-maps3d` 0.2.0 (`munimMaps.googleMaps3d=true`): 6/6 on a Galaxy A14, munim models drawn by Google; devices whose Google Play services cannot download the Maps 3D module fail inside Google's SDK |

Notes:

- **3D layer alignment.** Google publishes a zoom, not a camera distance or field of view. `GoogleCameraSource` (iOS) and `GoogleCamera` (Android) measure both from Google's own projection every frame: the ground scale along the screen row through the target gives points per metre at the target's depth, and the foreshortening of a point further up the screen gives the camera distance while the map is tilted; their product is the focal length (kept as a field of view for flat views). `googleMap(ref).cameraDiagnostics()` shows the numbers.
- **iOS SDK versions.** GoogleMaps 9.4 or later with Google Maps Utils 6.1 or later (10.x with Utils 7 when nothing else pins them; react-native-maps' Google subspec pins 9.4.0 / 6.1.0, and must be added when react-native-maps is in the app, because it registers its Google component whenever the GoogleMaps pod exists). `transitEnabled` needs 10.x. The pod's iOS minimum becomes 16.0 with the Google engine on.
- **Model rendering.** The 2D Maps SDKs have no 3D models, so on the 2D map `models` are always drawn by munim-maps' overlay (`modelRendering: 'native'` reports that). `google={{ mode: '3d' }}` switches the engine to Google's photorealistic 3D map (Maps 3D SDK: `Map3DView` on Android, the SwiftUI `Map` on iOS): `modelRendering: 'auto'` (default) or `'native'` draws every glTF model (`uri`) as a Google `Model` (position, altitude mode from `altitudeReference`, heading, `scale` × `google.modelScale`, `motion` keyframes stepped natively, taps to `onModelPress`), and polylines, polygons and markers natively; the overlay cannot follow Google 3D's camera (no projection API), so `'overlay'` falls back to native with an error. Built-in shapes, pictures, labels, effects, zones and paths need the 2D map. Local GLBs are copied to the cache and passed as `file://` URLs. On iOS two-format sources (`munim-maps-vehicles`) resolve to GLB in 3D mode.
- **What the 3D mode needs:** `munimMaps.googleMaps3d=true` in gradle.properties and `"munimMaps.googleMaps3d": "true"` in ios/Podfile.properties.json (both written by the Expo plugin's `googleMaps3d: true`), and a key with the **Map Tiles API** and the **Maps 3D SDK for Android** / **Maps 3D SDK for iOS** enabled (with 3D billing). Android: `play-services-maps3d` 0.2.0 is used because 0.2.2 is built with Kotlin 2.3, which React Native's Kotlin 2.1 compiler cannot read (`munimMaps.googleMaps3dVersion` overrides it).
- **The iOS 3D map** (`Engines/Google3D/GoogleMap3DMode.swift`). Google ships the Maps 3D SDK for iOS only as a Swift package (`https://github.com/googlemaps/ios-maps-3d-sdk`, product `GoogleMaps3D` 1.0.0, iOS 16, a dynamic framework plus a resource bundle) with a SwiftUI API. munim-maps hosts the SwiftUI `Map` in a `UIHostingController` inside the Google engine's view (the 2D `GMSMapView` stays underneath, hidden) and hands it the same key (`Map.apiKey`).
  - **Installing it.** The `NitroMunimMaps/Google3D` subspec adds the sources, and the podspec adds the package to the NitroMunimMaps pod with React Native's `spm_dependency` so the pod compiles against it. That alone is not enough with static pods (the Expo and React Native default): Xcode links a package product of a static-library pod into the app but does not embed its framework, so the app stops at launch with `Library not loaded: @rpath/GoogleMaps3D.framework/GoogleMaps3D`. The config plugin therefore also adds the package product to the app target in the Xcode project (`addGoogleMaps3dPackage`, idempotent, removed again when `googleMaps3d` is off), so Xcode embeds `GoogleMaps3D.framework` and copies `GoogleMaps3D_GoogleMaps3DTarget.bundle`. Without Expo, add the `GoogleMaps3D` product to the app target in Xcode (the same exact version). `MUNIM_MAPS_GOOGLE_MAPS_3D_VERSION` (at prebuild and `pod install`) changes the version in both places.
  - **Camera.** The SwiftUI map takes a camera binding: munim-maps sets it for `setCamera3d`, the shared camera methods and every frame of a flight, and reads gestures back through it. `flyTo` and `flyAround` are flown by munim-maps on the frame clock (centre, heading, tilt and roll eased, range eased in log space and raised mid-flight for far flights; `flyAround` turns the heading 360° a round), because the SDK's own `flyCameraTo` / `flyCameraAround` modifiers flew to the camera of the previous SwiftUI update (measured: the first flight went to the map's starting camera) and cannot be stopped. So `stopCameraAnimation` stops where the camera is, and `getCamera3d` returns the camera now, also mid-flight (Android returns a flight's destination as soon as it starts). A gesture ends a flight.
  - **Events.** The iOS SDK has no ready, steady or error callbacks: `map3dReady` (and `onMapReady`) come 1.5 s after the 3D map is on screen, or when it first reports a camera; `map3dSteady` is `false` while the camera moves and `true` 0.4 s after it stops or when a flight ends (on Android it follows Google's scene loading); `cameraAnimationEnd` when a flight ends or is stopped; `modeChange` when the 3D map comes and goes. Problems inside the SDK (such as a key without the Maps 3D SDK for iOS) are not reported to munim-maps.
  - **Models.** Google reads glTF files Z-up and turns +Z to the heading, so munim-maps stands every model up (`tilt` -90) and turns it 180° (checked on the iPad: heading 0 faces north). Android's `play-services-maps3d` reads them the same way and gets the same `Orientation(heading + 180, -90, 0)` (checked on a Galaxy A14, where models had stood on their tails before). `screenSize` is approximated from the distance between Google's camera and the model (35° vertical field of view) and applied when the camera stops; `tint` recolours the model's `paint*` materials in a GLB copy in munim-maps' cache. The SDK applies a change to a model it already shows one SwiftUI update late (measured by moving, turning and resizing models one step at a time: each step showed the previous one), so a still model that changes is drawn as a new model, and moving models (`motion`, spin) are updated in place, where a frame late does not show. Markers, polylines and polygons are drawn anew when they change too (as a precaution: only models were measured). `googleMap(ref).map3dDiagnostics()` returns the camera log, flight state and models as the map has them.
- **Not in the SDKs**, so not offered: a scale bar, a globe, a 2D/3D button, Apple's place cards and MapKit's search (use `googleMapsServices` or MapKit's services, which work with any engine on iOS), tracking modes (munim-maps follows the user itself).
- **Engine-only events and methods** go through the shared `onProviderEvent` / `providerCommand` (added for every engine, with defaults, so no other engine changes). Google's continuous marker drag (iOS `mapView(_:didDrag:)`, Android `OnMarkerDragListener.onMarkerDrag` in `setUpMarkerCollection`) feeds the shared `onMarkerDrag` and the `markerDrag` event.

## Mapbox engine

Mapbox Maps SDK **11.32** on both platforms (`MapboxMaps ~> 11.32` pod; `com.mapbox.maps:android-ndk27:11.32.0`, 16 KB page aligned; both download without a secret token). Needs a public token (`pk.…`): `configureMunimMaps({ mapboxAccessToken })`, the config plugin's `mapboxAccessToken` (Info.plist `MBXAccessToken`, Android `mapbox_access_token` string), never a secret `sk.` token in an app.

- Shared API: everything in the matrix above maps onto Mapbox (details in the checklist).
- `mapbox={{ … }}` (`MapboxMapOptions`, src/providers/mapbox.ts): declarative style objects written exactly as the [Mapbox Style Specification](https://docs.mapbox.com/style-spec/) and handed to the SDK unchanged (`addLayer(with:)` / `addStyleLayer(Value)`), diffed between renders; map options (gestures, ornaments, puck, camera bounds, rendering, debug); `events` and `interactions`.
- `mapboxMap(ref.current).<method>(args)` (`MapboxMapMethods`): queries, feature state, cluster expansion, partial GeoJSON updates, runtime style edits, style imports, featuresets, Mapbox's camera in zoom levels, free camera, viewport, snapshots, elevation, location override, statistics.
- `MapboxOffline`: style packs and tile regions, with progress through `addListener`; `MapboxServices`: Geocoding v6, Search Box, Directions, Matrix, Isochrone over HTTPS with the public token (billed per request by Mapbox beyond the free tier; temporary geocoding results may not be stored, per Mapbox's terms).
- Native models: `mapbox.modelRendering` (`auto` by default) hands glTF models to a Mapbox `model` source drawn by two `model` layers (`munim-native-models`, `munim-native-models-sea`) through the shared `setModels` hook (iOS and Android: the engine keeps what Mapbox draws and gives the rest to its `modelLayer`). Remote glTF files are read from munim-maps' disk cache.
- 3D: munim-maps' layer (SceneKit / Filament) is aligned to Mapbox's camera: 36.87° vertical field of view, 512-point tiles, an off-centre projection when the camera has padding (iOS), globe below zoom 5.5, `drawsTerrain` with terrain on. Mapbox's own glTF `model` layer works too (`models` + a `model` layer); munim-maps' models stay in front of Mapbox's 3D buildings (no shared depth buffer) unless `occlusion="buildings"`.

### Mapbox checklist

Every capability of the SDKs' public surface (iOS `MapboxMaps` and Android `com.mapbox.maps` + plugins + `extension-style`), with its munim-maps API. ✅ done · 🟡 partly (note) · — not offered (reason).

| Capability | munim-maps API | iOS | Android | Note |
| --- | --- | --- | --- | --- |
| Map view, token, lifecycle | `provider="mapbox"`, `configureMunimMaps({ mapboxAccessToken })` | ✅ | 🔨 | Missing token → `onError`. |
| Styles: Standard, Standard Satellite, Streets, Outdoors, Light, Dark, Satellite, Satellite Streets, Navigation | `styleUrl` + `MAPBOX_STYLES`; `mapStyle` (`standard`/`muted` → Standard, `hybrid`/`imagery` → Standard Satellite) | ✅ | 🔨 | |
| Custom style URL / JSON | `styleUrl`, `mapbox.styleJson` | ✅ | 🔨 | |
| Standard config (light presets day/dawn/dusk/night, theme default/faded/monochrome/custom, 3D objects/buildings/trees/landmarks/facades, POI/transit/place/road labels, pedestrian roads, landmark icons, admin boundaries, fonts, density…) | `mapbox.standard`, `mapbox.lightPreset`; `colorScheme` → preset, `showsBuildings` → `show3dObjects`, `pointsOfInterest: 'none'` → labels off | ✅ | 🔨 | Unknown keys pass through. |
| Style imports (add/update/move/remove, config, schema) | `mapbox.imports`, `mapbox.importConfig`; `getStyleImports`, `getStyleImportSchema`, `getStyleImportConfig`, `setStyleImportConfig` | ✅ | 🔨 | |
| Colour themes (LUT) | `mapbox.colorTheme` | ✅ | 🔨 | Experimental in the SDK. |
| Globe / Mercator projection | `globe`, `mapbox.projection` | ✅ | 🔨 | |
| Atmosphere / fog | `mapbox.atmosphere` | ✅ | 🔨 | |
| Terrain (raster-dem, exaggeration) | `mapbox.terrain`, `terrainExaggeration`; on for `hybrid`/`imagery` + `elevation="realistic"`; `getElevation` | ✅ | 🔨 | |
| Lights (flat, ambient + directional) | `mapbox.lights` | ✅ | 🔨 | |
| Snow, rain | `mapbox.snow`, `mapbox.rain` | ✅ | 🔨 | Experimental in the SDK. |
| Sources: vector, raster, raster-dem, raster-array, GeoJSON (clustering, cluster properties, line metrics), image, model, batched-model | `mapbox.sources` (style-spec JSON) | ✅ | 🔨 | |
| GeoJSON partial updates | `updateGeoJSONSource`, `add/update/removeGeoJSONSourceFeatures` | ✅ | 🔨 | |
| Video source | — | — | — | Not in the mobile SDKs (GL JS only). |
| Custom geometry / custom raster sources (tiles produced in code) | — | — | — | Need native per-tile callbacks; use a GeoJSON source or a `{z}/{x}/{y}` URL instead. |
| Layers: fill, line (dash, gradient, trim, pattern), symbol, circle, heatmap, fill-extrusion, raster, raster-particle, hillshade, background, sky, model, location-indicator, slot, clip, building | `mapbox.layers` (style-spec JSON incl. `slot`, positions `beforeId`/`aboveId`/`index`) | ✅ | 🔨 | |
| Expressions, feature state in paint | style-spec JSON; `setFeatureState`, `getFeatureState`, `removeFeatureState`, `resetFeatureStates` (by source or featureset) | ✅ | 🔨 | |
| Runtime styling | `setLayerProperties`, `getLayerProperties`, `setSourceProperties`, `getSourceProperties`, `moveLayer`, `getLayers`, `getSources`, `getSlots`, `getStyleJson` | ✅ | 🔨 | |
| Persistent layers | — | — | — | munim-maps re-adds its layers after every style load, which covers it. |
| Custom (Metal / OpenGL) layers | — | — | — | munim-maps' own 3D layer is the native drawing hook. |
| Images (SDF, stretch, content, scale) | `mapbox.images` | ✅ | 🔨 | `http(s)`, `file`, `data:` and bundled URIs. |
| glTF models for `model` layers | `mapbox.models` | ✅ | 🔨 | `VEHICLES[name].glb` from munim-maps-vehicles works. |
| Queries | `queryRenderedFeatures` (point, box, viewport; layers, filter, featureset), `querySourceFeatures` | ✅ | 🔨 | |
| Cluster expansion | `getClusterExpansionZoom`, `getClusterLeaves`, `getClusterChildren` | ✅ | 🔨 | |
| Featuresets and interactions (Standard POIs, buildings, place labels, landmarks; layers) with feature state | `mapbox.interactions` → `onProviderEvent('interaction')`; `selectableMapFeatures` → `onMapFeaturePress`; `getFeaturesets` | ✅ | 🔨 | Hover is not a mobile gesture. |
| Point annotations (images, text, drag, clustering) | `markers` (all six styles), `clusteringId`, `clusterStyles`, `onClusterPress`, `draggable`, `onMarkerDrag*` | ✅ | 🔨 | One manager per clustering id. |
| Polyline / polygon / circle annotations | `polylines`, `polygons`, `circles` (as GeoJSON layers in Standard's slots) | ✅ | 🔨 | Layers rather than annotation managers, so gradients, trims and dashes per shape work. |
| View annotations (anchors, overlap, priority, dragging) | `MarkerView`; callouts (`callout`, accessories) | ✅ | 🔨 | Draggable `MarkerView` uses Mapbox's view annotation drag. |
| Camera (set, ease, fly, cancel, bounds, padding, anchors) | shared camera API; `getCameraState`, `setCamera`, `easeTo`, `flyTo`, `cancelCameraAnimations`, `cameraForCoordinates`, `getBounds`, `getCameraBounds`, `getStyleDefaultCamera`; `mapbox.cameraBounds`; `cameraDistanceRange`, `cameraBoundary`, `mapPadding` | ✅ | 🔨 | |
| Free camera | `getFreeCamera`, `setFreeCamera` | ✅ | 🔨 | |
| Gestures (pan, pinch, rotate, pitch, double tap / touch, quick zoom, pan mode, deceleration, focal point) | `zoomEnabled`… + `mapbox.gestures` | ✅ | 🔨 | |
| Ornaments: compass, scale bar, logo, attribution | `compassVisibility`, `scaleVisibility` + `mapbox.ornaments` | ✅ | 🔨 | Logo and attribution stay visible (Mapbox's terms). |
| Indoor selector | — | — | — | Restricted Mapbox indoor data. |
| Location puck 2D / 3D, bearing heading / course, pulsing, accuracy ring | `showsUserLocation` + `mapbox.puck`; `onUserLocationChange` | ✅ | 🔨 | |
| Custom location data | `setLocationOverride`, `clearLocationOverride` | ✅ | 🔨 | |
| Viewport: follow puck, overview, idle, transitions, status | `userTrackingMode` (`follow`, `followWithHeading`), `showsUserTrackingButton`, `setViewport`; `onProviderEvent('viewportStatus')` | ✅ | 🔨 | Panning away drops to `none` + `onUserTrackingModeChange`. |
| Map events | `mapbox.events`: `mapLoaded`, `mapIdle`, `mapLoadingError`, `styleLoaded`, `styleDataLoaded`, `styleImageMissing`, `styleImageRemoveUnused`, `sourceDataLoaded`, `sourceAdded`, `sourceRemoved`, `cameraChanged`, `renderFrameStarted`, `renderFrameFinished`, `resourceRequest` | ✅ | 🔨 | Plus the shared `onMapReady`, `onCameraMove`, `onCameraChange`, `onPress`, `onLongPress`. |
| Snapshots | `takeSnapshot` (the view), `snapshot` (Mapbox `Snapshotter`, any style / camera / size) | ✅ | 🔨 | |
| Offline: style packs, tile regions, estimates, metadata, quota, offline switch, clear data | `MapboxOffline` | ✅ | 🔨 | |
| Map options (constrain mode, viewport mode, north orientation, prefetch, tile cache, frame rate, style transition) | `mapbox.rendering` | ✅ | 🔨 | |
| Debug overlays | `mapbox.debug` | 🟡 | 🔨 | iOS has no wireframe options; Android has all. |
| Performance statistics | `collectPerformanceStatistics` | ✅ | 🔨 | |
| Tile cover | `tileCover` | ✅ | 🔨 | |
| Map recorder / player | — | — | — | Experimental SDK debugging tool. |
| SwiftUI `Map`, Jetpack Compose `MapboxMap` | — | — | — | munim-maps wraps the UIKit / Android View API. |
| Search SDK, Navigation SDK | `MapboxServices` (web APIs) | ✅ JS | ✅ JS | Separate SDKs with their own licences; the web APIs cover search and routes. |
| Reverse geocoding | `addressForCoordinate` (Geocoding v6) | ✅ | 🔨 | |
| munim 3D layer (models, avatars, paths, zones, effects) | `models`, `zones`, `paths`, `measureAlignment` | ✅ | 🔨 | |
| Native models (Mapbox `model` source + layers) | `mapbox.modelRendering` (`auto` default, `native`, `overlay`): glTF bodies with position, altitude / sea level, heading, spin, `motion`, `scale`, `screenSize`, `tint` (material overrides on `paint*`), `onModelPress` | ✅ | 🔨 | Avatars, labels, stems, effects, occluders, USDZ / built-in shapes, zones and paths stay on the 3D layer. |

Testing: `munimmapsexample://mapbox` (example/MapboxScreen.tsx) shows every group; **Run checks** or `munimmapsexample://mapbox/checks` runs the checks (`MUNIM_MAPS_MAPBOX check …` in the log). Fast iOS compile loop: build the `MapboxMaps` pod scheme once (`xcodebuild -scheme MapboxMaps -configuration Release -destination generic/platform=iOS`) and typecheck `ios/Core`, `ios/Engines/*.swift`, `ios/Engines/MapKit` and `ios/Engines/Mapbox` against it with `swiftc -typecheck -I <products>/MapboxMaps -Xcc -fmodule-map-file=<products>/MapboxMaps/MapboxMaps.modulemap -F <products>/XCFrameworkIntermediates/{MapboxCoreMaps,MapboxCommon,Turf}`.

## MapLibre engine checklist (open maps)

Every capability in the public surface of MapLibre Native for iOS (6.30, the newest on CocoaPods: the `MLN…` headers) and Android (13.6.1: `org.maplibre.android…`), mapped to the munim-maps API. Status per platform: ✅ done · 🔨 built (compiles, in the example), on-device check pending · 🟡 partly (note) · ❌ left out (reason given). iOS was checked on an iPad Air (M3) with the example's 27 MapLibre checks (27/27); the Android phone was disconnected for this round, so Android rows are 🔨. Shared rows are the props, events and methods every engine has; MapLibre-only ones are `maplibre={{…}}` options (`MapLibreMapOptions`), commands (`maplibreCommands(ref)`, which call `ref.providerCommand(name, json)`) and events (`onProviderEvent`).

### Map and style

| SDK capability | iOS | Android | munim-maps API | iOS | Android |
| --- | --- | --- | --- | --- | --- |
| Map view, lifecycle | `MLNMapView` | `MapView` + `onStart…onDestroy` | `provider="maplibre"` | ✅ | 🔨 |
| Style from URL | `styleURL` | `setStyle(String)` | `styleUrl` | ✅ | 🔨 |
| Style from JSON | `styleJSON` | `Style.Builder().fromJson` | `maplibre.styleJson` (string or object) | ✅ | 🔨 |
| OpenFreeMap styles, no key | — | — | `maplibre.style`: `liberty` (default), `bright`, `positron`, `dark`, `fiord` | ✅ | 🔨 |
| Keyed providers | `MLNSettings.apiKey`, `MLNTileServerOptions`, `useWellKnownTileServer` | `MapLibre.getInstance(ctx, key, WellKnownTileServer)`, `TileServerOptions` | `maplibre.style`: `maptiler-*`, `stadia-*` with `maplibre.apiKey` (the style URL carries the key) | ✅ | 🔨 |
| Predefined styles | `MLNStyle.predefinedStyles`, `MLNDefaultStyle` | `Style.getPredefinedStyles`, `DefaultStyle` | `maplibre.style: 'demotiles'` (the SDKs' own list is MapLibre's demo tiles) | ✅ | 🔨 |
| `mapStyle` standard / muted | — | — | `standard` → Liberty, `muted` → Positron | ✅ | 🔨 |
| `mapStyle` hybrid / imagery | raster source | raster source | needs `maplibre.satelliteTilesUrl` (there is no keyless satellite imagery); `hybrid` keeps roads and labels over it | ✅ | 🔨 |
| Dark mode | — | — | `colorScheme="dark"` → `maplibre.darkStyle` (default OpenFreeMap Dark) | ✅ | 🔨 |
| Reload style | `reloadStyle:` | `setStyle` again | command `reloadStyle` | ✅ | 🔨 |
| Style switching at runtime | `styleURL =` | `setStyle` | change `styleUrl` / `maplibre.style`; markers, shapes and runtime layers come back on the new style | ✅ | 🔨 |
| Style transition | `MLNStyle.transition` | `Style.setTransition` | `maplibre.transition { duration, delay }` (ms) | ✅ | 🔨 |
| Placement transitions | `performsPlacementTransitions` | no API | `maplibre.placementTransitions` | ✅ | ❌ no Android API |
| Light | `MLNLight` | `Style.getLight()` | `maplibre.light` (style-spec `light`) | ✅ | 🔨 |
| Label language | `localizeLabelsIntoLocale:` | no API | `maplibre.labelLanguage` (rewrites `text-field` to `name:<lang>` with a fallback, on both) | ✅ | 🔨 |
| Local CJK glyphs | `MLNIdeographicFontFamilyName` (Info.plist) | `MapLibreMapOptions.localIdeographFontFamily` | Android: `maplibre.localIdeographFontFamily`; iOS: the Info.plist key | ❌ Info.plist only | 🔨 |
| Globe projection | not in MapLibre Native (GL JS only) | not in MapLibre Native | `globe` / `maplibre.projection: 'globe'` report "not supported" | ❌ SDK has none | ❌ SDK has none |
| 3D terrain | not in MapLibre Native | not in MapLibre Native | `elevation="realistic"` stays flat; hillshade and color relief instead | ❌ SDK has none | ❌ SDK has none |
| 3D buildings | `fill-extrusion` layers | same | `showsBuildings` toggles the style's building layers | ✅ | 🔨 |
| Points of interest | style `poi` layers | same | `pointsOfInterest` (`all`, `none`, OpenMapTiles `class` names) | ✅ | 🔨 |
| Traffic | no traffic data in OpenStreetMap | same | `showsTraffic` reports unsupported | ❌ no data | ❌ no data |

### Runtime styling (the whole style spec)

| SDK capability | iOS | Android | munim-maps API | iOS | Android |
| --- | --- | --- | --- | --- | --- |
| Sources: vector, raster, raster-dem, geojson, image | `MLNVectorTileSource`, `MLNRasterTileSource`, `MLNRasterDEMSource`, `MLNShapeSource`, `MLNImageSource` | `VectorSource`, `RasterSource`, `RasterDemSource`, `GeoJsonSource`, `ImageSource` | `maplibre.sources` (style-spec source objects); commands `addSource`, `removeSource` | ✅ | 🔨 |
| Tile templates, TileJSON, scheme, bounds, zoom range, attribution, tile size, DEM encoding | `MLNTileSourceOption…` | `TileSet` | the style-spec keys (`tiles`, `url`, `scheme`, `bounds`, `minzoom`, `maxzoom`, `tileSize`, `encoding`, `attribution`) | ✅ | 🔨 |
| PMTiles | `pmtiles://` URLs | same | `url: 'pmtiles://https://…'` | ✅ | 🔨 |
| MapLibre Tiles (MLT) | `encoding: 'mlt'` | same | the source's `encoding` | ✅ | 🔨 |
| GeoJSON: cluster, clusterRadius, clusterMaxZoom, lineMetrics, tolerance, buffer, maxzoom | `MLNShapeSourceOption…` | `GeoJsonOptions` | geojson source keys | ✅ | 🔨 |
| GeoJSON `clusterProperties` | `MLNShapeSourceOptionClusterProperties` | no API | ❌ Android has no API; left out on both so a map means the same everywhere | ❌ | ❌ |
| Update GeoJSON | `MLNShapeSource.shape`, `URL` | `setGeoJson`, `setUri` | command `setGeoJson`, or new `maplibre.sources` | ✅ | 🔨 |
| Computed / custom geometry sources | `MLNComputedShapeSource` | `CustomGeometrySource`, `CustomVectorSource` | ❌ they call native code for every tile; GeoJSON or a tile server covers the same ground | ❌ | ❌ |
| Source tuning (prefetch delta, volatile, overscale, update interval) | no API | `Source.setPrefetchZoomDelta`… | ❌ Android only and rarely needed; `maplibre.rendering.prefetchZoomDelta` covers the map | ❌ | ❌ |
| Layers: fill, line, symbol, circle, heatmap, fill-extrusion, raster, hillshade, color-relief, background | `MLN…StyleLayer` | `…Layer` | `maplibre.layers` (style-spec layers + `beforeId`); commands `addLayer`, `removeLayer`, `moveLayer` | ✅ | 🔨 |
| Paint and layout properties, expressions | KVC with `NSExpression(mlnJSONObject:)` | `PaintPropertyValue`, `LayoutPropertyValue` | style-spec JSON as is; commands `setPaintProperty`, `setLayoutProperty` | ✅ | 🔨 |
| Filters | `predicate` (`NSPredicate(mlnJSONObject:)`) | `setFilter(Expression)` | the layer's `filter`; command `setFilter` | ✅ | 🔨 |
| Layer zoom range, visibility, source layer | `minimumZoomLevel`, `isVisible`, `sourceLayerIdentifier` | `setMinZoom`, `visibility` | `minzoom`, `maxzoom`, `layout.visibility`, `source-layer`; command `setLayerZoomRange` | ✅ | 🔨 |
| Style images (icons, patterns, SDF) | `setImage:forName:` (template images for SDF) | `addImage(id, bitmap, sdf)` | `maplibre.images { name: uri \| { uri, sdf } }`; commands `addImage`, `removeImage` | ✅ | 🔨 |
| Missing images | `didFailToLoadImage:` | `OnStyleImageMissingListener` | event `styleImageMissing` | ✅ | 🔨 |
| Feature state | `MLNShapeSource` / `MLNVectorTileSource` `setFeatureState…` | `setFeatureState`, `getFeatureState`, `removeFeatureState` | commands `setFeatureState`, `getFeatureState`, `removeFeatureState` | ✅ | 🔨 |
| Hillshade from public elevation data | `MLNRasterDEMSource` + `MLNHillshadeStyleLayer` | `RasterDemSource` + `HillshadeLayer` | `maplibre.hillshade` (`true` or options; AWS Terrain Tiles, keyless) | ✅ | 🔨 |
| Color relief | `MLNColorReliefStyleLayer` | `ColorReliefLayer` | `maplibre.colorRelief` | ✅ | 🔨 |
| Custom native layers | `MLNCustomStyleLayer`, `MLNPluginLayer` | `CustomLayer` | ❌ native drawing code, not data; munim-maps' 3D layer covers models | ❌ | ❌ |
| Style out | `MLNStyle.styleJSON` | `Style.getJson` | command `getStyle` (layer ids, source ids, style JSON) | ✅ | 🔨 |

### Camera, gestures, ornaments

| SDK capability | iOS | Android | munim-maps API | iOS | Android |
| --- | --- | --- | --- | --- | --- |
| Camera get / set / animate | `camera`, `setCamera:withDuration:animationTimingFunction:` | `cameraPosition`, `moveCamera`, `easeCamera` | `initialCamera`, `setCamera`, `animateCamera`, `getCamera` | ✅ | 🔨 |
| Fly-to (zoom-out arc) | `flyToCamera:withDuration:…` | `animateCamera` | command `flyTo { camera, durationMs }` | ✅ | 🔨 |
| Keyframed flights | — | — | `flyCamera`, `stopFlight` (munim-maps' frame clock) | ✅ | 🔨 |
| Regions and fitting | `setVisibleCoordinateBounds:edgePadding:`, `cameraThatFitsCoordinateBounds:` | `newLatLngBounds`, `getCameraForLatLngBounds` | `setRegion`, `getVisibleRegion`, `fitToCoordinates`, `fitToMarkers` | ✅ | 🔨 |
| Projection | `convertPoint:…`, `convertCoordinate:…`, `metersPerPointAtLatitude:` | `Projection` | `pointForCoordinate`, `coordinateForPoint`; command `metersPerPoint` | ✅ | 🔨 |
| Padding | `contentInset` | `setPadding` | `mapPadding` | ✅ | 🔨 |
| Zoom and pitch limits | `minimumZoomLevel`, `maximumZoomLevel`, `minimumPitch`, `maximumPitch` | `setMin/MaxZoomPreference`, `setMin/MaxPitchPreference` | `cameraDistanceRange`; `maplibre.camera { minZoom, maxZoom, minPitch, maxPitch }` | ✅ | 🔨 |
| Camera bounds | `maximumScreenBounds` | `setLatLngBoundsForCameraTarget` | `cameraBoundary` | ✅ | 🔨 |
| Camera roll | `MLNMapCamera.roll` | `CameraPosition.roll` | `maplibre.camera.roll` | ✅ | 🔨 |
| Field of view | fixed 36.87° | `CameraPosition.fov` | read for the 3D layer | ✅ | 🔨 |
| Reset north / position | `resetNorth`, `resetPosition` | `resetNorth` | commands `resetNorth`, `resetPosition` | ✅ | 🔨 |
| Gestures on/off | `zoomEnabled`, `scrollEnabled`, `rotateEnabled`, `pitchEnabled` | `UiSettings` | `zoomEnabled`, `scrollEnabled`, `rotateEnabled`, `pitchEnabled` | ✅ | 🔨 |
| Gesture tuning | `quickZoomReversed`, `panScrollingMode`, `toleranceForSnappingToNorth`, `decelerationRate`, `anchorRotateOrZoomGesturesToCenterCoordinate`, `hapticFeedbackEnabled` | `UiSettings`: double tap, quick zoom, fling / scale / rotate velocity, horizontal scroll, `disableRotateWhenScaling`, `increaseRotateThresholdWhenScaling` | `maplibre.gestures { … }` (each key on the platforms that have it) | ✅ | 🔨 |
| Compass | `showsCompassView`, `compassView.compassVisibility`, position, margins | `UiSettings.compass…` (gravity, margins, fade when facing north) | `compassVisibility`; `maplibre.ornaments.compass { position, margin }` | ✅ | 🔨 |
| Scale bar | `showsScale`, `scaleBarPosition`, margins, `scaleBarUsesMetricSystem` | none in the SDK | `scaleVisibility` (Android: munim-maps draws one); `maplibre.ornaments.scaleBar { position, margin, metric }` | ✅ | 🔨 |
| Logo, attribution | `showsLogoView`, `showsAttributionButton`, positions, margins | `UiSettings.logo…`, `attribution…` | `maplibre.ornaments.logo`, `.attribution` (attribution stays on by default, as OpenStreetMap's licence asks) | ✅ | 🔨 |
| Rendering | `preferredFramesPerSecond`, `prefetchesTiles`, `tileCacheEnabled`, `tileLod…`, `frustumOffset`, `debugMask`, `enableRenderingStatsView:` | `setMaximumFps`, `setPrefetchZoomDelta`, `setTileCacheEnabled`, `setTileLod…`, `setFrustumOffset`, `setDebugActive`, `enableRenderingStatsView` | `maplibre.rendering { maxFps, prefetchTiles, prefetchZoomDelta, tileCache, tileLodScale, tileLodMinRadius, tileLodPitchThreshold, tileLodZoomShift, frustumOffset, debug, renderingStats }` | ✅ | 🔨 |
| Surface options | — | `MapLibreMapOptions` texture mode, translucency, `pixelRatio`, `foregroundLoadColor`; Vulkan / OpenGL AAR flavours | `maplibre.pixelRatio`, `maplibre.foregroundLoadColor`; texture mode stays off (the 3D layer is its own view); the backend is the AAR flavour | — | 🔨 |
| Action journal | `MLNActionJournalOptions` | `MapLibreMapOptions.actionJournal…` | ❌ diagnostics for MapLibre's own developers | ❌ | ❌ |

### Markers and shapes

munim-maps draws markers and shapes on MapLibre as GeoJSON sources with style layers, not the SDKs' annotation views, so clustering, collision and ordering work the same on both platforms. They stand in for the SDKs' annotation classes (`MLNPointAnnotation`, `MLNAnnotationView`, `MLNAnnotationImage`, `MLNCalloutView`, `MLNPolyline`, `MLNPolygon`; Android's deprecated `Marker`, `Polyline`, `Polygon`, `InfoWindow`).

| Capability | munim-maps API | iOS | Android |
| --- | --- | --- | --- |
| Point markers: pin, balloon with glyph, image, avatar with badges, label, dot | `markers` (`style`) | ✅ | 🔨 |
| Anchor, z order, opacity, visibility, collision, display priority | `anchorX/Y`, `zIndex`, `opacity`, `visible`, `collisionMode`, `displayPriority` (symbol sort key, allow-overlap) | ✅ | 🔨 |
| Callouts with title, subtitle, accessories | `calloutEnabled`, `onCalloutPress`, `onCalloutAccessoryPress` (munim-maps' callout view) | ✅ | 🔨 |
| Select / deselect | `selectMarker`, `deselectMarker`, `onMarkerPress`, `onMarkerDeselect` | ✅ | 🔨 |
| Dragging | `draggable`, `onMarkerDragStart`, `onMarkerDragEnd` (long press, then drag) | ✅ | 🔨 |
| Clustering | `clusteringId`, `clusterStyles`, `onClusterPress` (GeoJSON clustering per `clusteringId`) | ✅ | 🔨 |
| React Native views as markers | `MarkerView` (drawn as an image marker) | ✅ | 🔨 (an image in the style, from the shared Android `MarkerView`) |
| Polylines: colour, width, dashes, caps, joins, geodesic, gradient, partial stroke | `polylines` (`line-gradient`; geodesic lines densified; `strokeStart` / `strokeEnd` cut the line) | ✅ | 🔨 |
| Polygons with holes, circles | `polygons`, `circles` (geodesic rings) | ✅ | 🔨 |
| Overlay level | `level`: `aboveRoads` (below the first label layer) or `aboveLabels` | ✅ | 🔨 |
| Overlay taps | `onOverlayPress`, `overlayAtPoint` | ✅ | 🔨 |
| Tile overlays | `tileOverlays` (raster source and layer; `replacesMap` hides the style's layers) | ✅ | 🔨 |

### User location

| SDK capability | iOS | Android | munim-maps API | iOS | Android |
| --- | --- | --- | --- | --- | --- |
| Show location | `showsUserLocation` | `LocationComponent` | `showsUserLocation` | ✅ | 🔨 |
| Tracking modes | `MLNUserTrackingMode` none, follow, followWithHeading, followWithCourse | `CameraMode` NONE, TRACKING, TRACKING_COMPASS, TRACKING_GPS; `RenderMode` NORMAL, COMPASS, GPS | `userTrackingMode`, `onUserTrackingModeChange`; `maplibre.location.course` follows the course instead of the heading | ✅ | 🔨 |
| Location updates | `didUpdateUserLocation:` | `LocationEngine` callbacks | `onUserLocationChange` | ✅ | 🔨 |
| Puck look | `MLNUserLocationAnnotationViewStyle`, `showsUserHeadingIndicator`, `userLocationVerticalAlignment` | `LocationComponentOptions` (colours, accuracy ring, pulse, bearing) | `maplibre.location { puckColor, accuracyColor, pulse, pulseColor, showsHeading, verticalAlignment, renderMode }` | ✅ | 🔨 |
| Tracking button | — | — | `showsUserTrackingButton` (munim-maps' button) | ✅ | 🔨 |
| Custom location sources | `MLNLocationManager` | `LocationEngine` | ❌ app code; munim-maps uses the platform's location services | ❌ | ❌ |

### Queries, snapshots, offline, network

| SDK capability | iOS | Android | munim-maps API | iOS | Android |
| --- | --- | --- | --- | --- | --- |
| Rendered features at a point or in a box, by layer and filter | `visibleFeaturesAtPoint:inStyleLayersWithIdentifiers:predicate:` | `queryRenderedFeatures` | command `queryRenderedFeatures { point \| box, layers, filter }` → GeoJSON | ✅ | 🔨 |
| Source features | `MLNVectorTileSource.featuresInSourceLayersWithIdentifiers:predicate:`, `MLNShapeSource.featuresMatchingPredicate:` | `querySourceFeatures` | command `querySourceFeatures { source, sourceLayers, filter }` | ✅ | 🔨 |
| Cluster leaves, children, expansion zoom | `MLNShapeSource.leavesOfCluster:…`, `childrenOfCluster:`, `zoomLevelForExpandingCluster:` | `getClusterLeaves`, `getClusterChildren`, `getClusterExpansionZoom` | commands of the same names | ✅ | 🔨 |
| Tapping base-map places | `visibleFeaturesAtPoint:` | `queryRenderedFeatures` | `onMapFeaturePress`, `selectableMapFeatures` (OpenMapTiles `poi`, `place`, `water_name`, `mountain_peak`) | ✅ | 🔨 |
| Snapshot of the view | — | `MapLibreMap.snapshot` | `takeSnapshot` | ✅ | 🔨 |
| Snapshotter (offscreen; any style, camera, size) | `MLNMapSnapshotter` | `MapSnapshotter` | command `snapshot { width, height, styleUrl, camera, showsLogo }` | ✅ | 🔨 |
| Offline packs: create (tile pyramid or shape), list, resume, suspend, delete, invalidate, progress, metadata | `MLNOfflineStorage`, `MLNOfflinePack`, `MLNTilePyramidOfflineRegion`, `MLNShapeOfflineRegion` | `OfflineManager`, `OfflineRegion`, `OfflineTilePyramidRegionDefinition`, `OfflineGeometryRegionDefinition` | commands `offlineCreatePack`, `offlineListPacks`, `offlineResumePack`, `offlineSuspendPack`, `offlineDeletePack`, `offlineInvalidatePack`; events `offlineProgress`, `offlineError` | ✅ | 🔨 |
| Ambient cache | `setMaximumAmbientCacheSize:`, `clearAmbientCache…`, `invalidateAmbientCache…`, `resetDatabase…` | the same names | commands `offlineSetAmbientCacheSize`, `offlineClearAmbientCache`, `offlineInvalidateAmbientCache`, `offlineResetDatabase` | ✅ | 🔨 |
| Side-loading a database | `addContentsOfFile:` | `mergeOfflineRegions` | command `offlineMergeDatabase { path }` | ✅ | 🔨 |
| Preloading single resources | `preloadData:forURL:…`, `putResourceWithUrl:` | `putResourceWithUrl` | ❌ tile pyramids and database merges cover offline use | ❌ | ❌ |
| Tile count limit | `setMaximumAllowedMapboxTiles:` | `setOfflineMapboxTileCountLimit` | ❌ applies to Mapbox-hosted tiles only | ❌ | ❌ |
| Connectivity | no API | `MapLibre.setConnected` | command `setConnected` | ❌ no iOS API | 🔨 |
| HTTP headers | `MLNNetworkConfiguration.sessionConfiguration` | `HttpRequestUtil.setOkHttpClient` | `maplibre.httpHeaders` | ✅ | 🔨 |
| Logging | `MLNLoggingConfiguration` | `Logger.setVerbosity` | `maplibre.logLevel` | ✅ | 🔨 |

### Events

| SDK callback | munim-maps | iOS | Android |
| --- | --- | --- | --- |
| Map loaded, style loaded, load failed | `onMapReady`; `onProviderEvent` `styleLoaded`, `mapLoadFailed` | ✅ | 🔨 |
| Region will change (with reason), is changing, did change | `onCameraMove`, `onCameraChange`; `onProviderEvent` `cameraMoveStarted { reason }` | ✅ | 🔨 |
| Idle, map fully rendered | `onProviderEvent` `idle`, `renderedMap { fullyRendered }` | ✅ | 🔨 |
| Source changed | `onProviderEvent` `sourceChanged` | ✅ | 🔨 |
| Render errors | `onProviderEvent` `renderError` | ✅ | 🔨 |
| Sprite, glyph, tile and shader events | ❌ MapLibre's own diagnostics | ❌ | ❌ |
| Taps, long presses | `onPress`, `onLongPress` | ✅ | 🔨 |
| Annotation select / drag / callout | the marker events above | ✅ | 🔨 |
| User location, tracking mode | `onUserLocationChange`, `onUserTrackingModeChange` | ✅ | 🔨 |
| Camera change veto (`shouldChangeFromCamera:toCamera:`) | ❌ a synchronous native veto; `cameraBoundary` and the limits cover it | ❌ | ❌ |

### Services (OpenStreetMap, no key)

`addressForCoordinate` and `openMapsServices` (exported by `munim-maps`) use [Nominatim](https://nominatim.org) (reverse and forward geocoding), [Photon](https://photon.komoot.io) (search as you type) and [OSRM](https://project-osrm.org) or [Valhalla](https://valhalla.github.io/valhalla/) (routing), each with a configurable endpoint. The public servers are for light use only: Nominatim allows one request a second with an identifying User-Agent and no bulk geocoding; the OSRM demo server is for testing. Point the endpoints at your own server or a hosted one in production.

| Service | munim-maps API | iOS | Android |
| --- | --- | --- | --- |
| Reverse geocoding | `addressForCoordinate`, `openMapsServices.reverseGeocode` | ✅ | 🔨 |
| Forward geocoding / search | `openMapsServices.geocode`, `openMapsServices.search` (Photon) | ✅ | 🔨 |
| Routing | `openMapsServices.route` (OSRM or Valhalla) | ✅ | 🔨 |

### Left out on purpose

- Coordinate, distance, clock and compass direction formatters (`MLNCoordinateFormatter`…): Foundation formatters, not map features; JavaScript has `Intl`.
- Android plugins (annotation, offline, localization, scale bar, building, markerview): separate artifacts whose features munim-maps implements itself (markers, offline, label language, scale bar, buildings, `MarkerView`).

## Cesium engine

There is no native Cesium SDK for mobile (Cesium Native is a C++ library for game engines, not a map view), so `provider="cesium"` runs **CesiumJS** in a WebView the engine owns: `WKWebView` on iOS, `android.webkit.WebView` on Android. No `react-native-webview` dependency.

- **CesiumJS from a pinned CDN, or bundled**: the engine's page (`packages/munim-maps/cesium/page/munim-cesium/`: `index.html`, `js/`, CSS, 200 KB) is always in the app. CesiumJS **1.146.0** itself (Apache-2.0; the minified `Cesium.js`, its `Workers`, `ThirdParty` (Draco, Basis), `Assets` and `Widgets`, 13 MB) comes by default from `https://cdn.jsdelivr.net/npm/cesium@1.146.0/Build/Cesium/`: the page asks for `Cesium/…` on its own origin and the engine's handler fetches the file, writes it to the cache folder (`munim-maps-cesium/1.146.0/`) and serves it, so the page stays same-origin (Web Workers, no CSP or CORS changes) and works offline after the first load. Self-host with Info.plist `MunimMapsCesiumBaseURL` / manifest meta-data `munimmaps.cesium_base_url` (a `Build/Cesium/` folder of the same version). To ship it in the app instead (offline from the first launch): add `cesium` **1.146.0** to the app's dependencies and turn on the config plugin's `cesium: { bundled: true }`, `MUNIM_MAPS_CESIUM_BUNDLED=1` / `"munimMaps.cesiumBundled": "true"` for CocoaPods, `munimMaps.cesiumBundled=true` for Gradle. munim-maps does not ship CesiumJS: `scripts/cesium/copy-cesium.js` copies the minified build (`Cesium.js`, `Workers`, `ThirdParty`, `Assets`, `Widgets`) with CesiumJS's `LICENSE.md` (Apache-2.0) and `ThirdParty.json` (third-party notices) from the app's `cesium` package, at `pod install` into `cesium/build/Cesium` of the installed package (the `MunimMapsCesium` resource bundle; run `pod install` again after changing the `cesium` version) and in the Gradle task `munimMapsCopyCesium` (generated assets, `munim-cesium/Cesium/`). Another version than 1.146.0 builds with a warning (prebuild, `pod install`, Gradle); a missing `cesium` package stops the build. `MUNIM_MAPS_CESIUM_DIR` / `munimMaps.cesiumDir` point at a `cesium` package folder elsewhere (monorepos). In this repository, `scripts/cesium/vendor-cesium.sh [version]` (development only) fetches a version from npm into `packages/munim-maps/cesium/build/Cesium` to try it, and `npm run check:cesium` checks the three pins (copy-cesium.js, CesiumSupport.swift, CesiumMapEngine.kt) agree. iOS serves the page from the `MunimMapsCesium` resource bundle of the `NitroMunimMaps/Cesium` subspec through a `munim-cesium://` URL scheme handler; Android from the APK's assets at `https://appassets.androidplatform.net/` (`munimMaps.cesium=true` adds them).
- **The two halves**: `cesium/page/munim-cesium/js/*.js` (the same on both platforms) draws everything with CesiumJS; `ios/Engines/Cesium/` and `android/src/cesium/` host the WebView, send props as JSON messages (`{ t: 'set' }`), receive events and the camera, and answer methods (`{ t: 'call' }` / `{ t: 'result' }`). App files (`require()`d images and models, `file://`, Android resources, Metro's `http://` in development) reach the page through `…/resource?uri=`; on iOS, https tiles go through `…/tile/<host>/<path>` with an identifying User-Agent (OpenStreetMap's tile policy; WebKit sends no Referer from a custom scheme).
- **No key needed**: OpenStreetMap imagery and a smooth ellipsoid (no terrain). With `configureMunimMaps({ cesiumIonToken })` (or the config plugin's `cesiumIonToken`): Cesium World Terrain by default (unless `elevation="flat"`), Bing imagery through ion for `mapStyle` `imagery` / `hybrid` (Esri World Imagery without a token), Cesium OSM Buildings while `showsBuildings`, and every ion asset. `Cesium.Ion.defaultAccessToken` is set to your token or to nothing: CesiumJS's built-in evaluation token is never used.
- **3D layer, `cesium.modelRendering`**: `auto` (default) and `native` draw the munim 3D layer **natively in Cesium**, so terrain and 3D Tiles hide it: GLB / glTF models (munim-maps-vehicles' `VEHICLES` resolve to GLB on Cesium) as Cesium `Model` primitives with heading, altitude, `altitudeReference`, scale, `screenSize`, `tint` (recolours `paint…` materials in the GLB), spin, embedded animations and `motion`; built-in shapes (box, sphere, cylinder, cone, pyramid; capsule and gem approximated) as entities; pictures (avatars with border and badge) as billboards; labels as label entities; stems as polylines; `lift` per frame; ground shadows as ground ellipses; effects (exhaust, smoke as particle systems, contrail as a glowing trail); zones as fading walls with a ground outline; paths as 3D polylines. `auto` sends the only things Cesium cannot draw (USDZ, SCN, OBJ files on iOS, and occluders, which Cesium's real depth makes unnecessary) to munim-maps' overlay 3D layer; `native` skips them. `overlay` draws everything on munim-maps' native 3D layer (SceneKit / Filament) over the WebView, fed with Cesium's camera every frame, exactly as on MapKit: it works (`measureAlignment` within a point of Cesium's own projection on the iPad), but it is not hidden by terrain or 3D Tiles and trails the camera by a frame while it moves, because the WebView reports its camera asynchronously. (`modelRenderer` is the older name: `cesium` = `native`, `native` = `overlay`.)
- **Extras**: `cesium={{ … }}` (`CesiumMapOptions`, `src/providers/cesium.ts`) reaches CesiumJS declaratively, `cesiumCommands(ref.current)` imperatively (through the engine-neutral `providerCommand(name, argsJson)` method), and `onProviderEvent` + `parseCesiumEvent` deliver Cesium-only events. `cesiumCommands(ref).evaluate({ script })` (with `cesium={{ allowEvaluate: true }}`) runs any CesiumJS code in the page, so nothing in the library is out of reach.
- **Limits**: WebGL in a WebView is slower than a native SDK and uses more memory; Cesium renders on demand (`requestRenderMode`) and continuously only while something moves. Synchronous getters (`point(for:)`, `coordinate(for:)`, `camera`, `visibleRegion` in Swift; the same on Android) use the camera Cesium last reported, at the ground height of the map's centre; `cesiumCommands(ref).pick` / `pickPosition` / `toScreen` ask Cesium itself (terrain, 3D Tiles). The native 3D layer follows Cesium's camera one message behind (a frame or two while moving). If the WebView's content process is killed for memory, iOS reloads the page and every prop; Android reports `onError` (remount the map). `MapModelLayer` over another library's map does not apply.

### Cesium checklist

Walked from the CesiumJS 1.146 reference (`Cesium.d.ts`: 541 exported classes, functions and enums), grouped by capability. **API** is where it is in munim-maps: a shared prop or method, `cesium.<option>` (`CesiumMapOptions`), or `commands.<name>` (`cesiumCommands`). `evaluate` reaches anything else.

| Capability (CesiumJS classes) | munim-maps API | iOS | Android | Notes |
| --- | --- | --- | --- | --- |
| Viewer / CesiumWidget, Scene, render loop | `provider="cesium"` | ✅ | ✅ | Renders on demand; continuously while flights, the clock, models in motion, particles or orbits run. `cesium.targetFrameRate`, `resolutionScale`, `useBrowserRecommendedResolution`, `msaaSamples`, `orderIndependentTranslucency`, `contextOptions` |
| SceneMode 3D / 2D / Columbus view, morphs, MapMode2D, map projection | `cesium.sceneMode`, `morphDuration`, `scene3DOnly`, `mapMode2D`, `mapProjection`; `commands.setSceneMode`; `morphComplete` event | ✅ | ✅ | The munim camera is kept across morphs (2D drops the pitch) |
| Imagery: OpenStreetMap, UrlTemplate (XYZ), WMS, WMTS, TMS, SingleTile, Bing, ion, ArcGIS (MapServer, basemaps), Mapbox, MapboxStyle, Google 2D, Azure 2D, Google Earth Enterprise, Grid, TileCoordinates; layer alpha / brightness / contrast / hue / saturation / gamma / split / colorToAlpha / cutout / day-night alpha; ordering | `mapStyle`, `colorScheme`, `tileOverlays`, `cesium.imagery`, `cesium.imageryLayers`; `commands.addImageryLayer` / `removeImageryLayer` / `setImageryLayer` (raise, lower) / `imageryLayers` / `pickImageryFeatures` | ✅ | ✅ | Presets: `openStreetMap` (default), `aerial`, `aerialWithLabels`, `road`, `muted`, `naturalEarth` (bundled, offline), `none`. Dark mode tones the imagery down |
| Terrain: Ellipsoid, Cesium World Terrain, World Bathymetry, ion, quantized-mesh URLs, ArcGIS elevation, VR-TheWorld, 3D Tiles terrain, Google Earth Enterprise; vertex normals, water mask; vertical exaggeration | `elevation`, `cesium.terrain`, `verticalExaggeration`, `verticalExaggerationRelativeHeight`; `commands.setTerrain`, `sampleHeights`, `clampToHeight` | ✅ | ✅ | ion terrain needs the token |
| 3D Tiles: Cesium3DTileset (URL, ion), Cesium OSM Buildings, Google Photorealistic 3D Tiles (ion asset 2275207 or a Map Tiles API key), styles (Cesium3DTileStyle), custom shaders, clipping planes / polygons, point cloud shading, image-based lighting, classification, Gaussian splats, I3S scene layers, voxels (Cesium3DTilesVoxelProvider + VoxelPrimitive), Mapbox Vector Tiles as 3D Tiles (MVTDataProvider), iTwin (ITwinData) | `showsBuildings`, `occlusion="buildings"`, `cesium.osmBuildings`, `cesium.photorealistic`, `cesium.tilesets`; `commands.addTileset` / `removeTileset` / `setTilesetStyle` / `setTilesetProperties` / `tilesetInfo`; `tilesetLoaded`, `tilesetAllTilesLoaded` events | ✅ | ✅ | Splats load through `Cesium3DTileset` (`KHR_gaussian_splatting`). OSM Buildings and photorealistic need an ion token or a Google key with the Map Tiles API |
| Entities: point, billboard, label, polyline (glow, arrow, dash, outline materials), polygon (extrusion, holes), ellipse, rectangle, wall, corridor, box, cylinder, ellipsoid, plane, polylineVolume, model (glTF, animations, node transforms), path, tileset; properties, availability, descriptions | `cesium.entities` (CZML packets, updated in place); `commands.addEntities` / `removeEntities` / `getEntity` / `listEntities` / `selectEntity` / `trackEntity`; `cesium.trackedEntityId`, `selectedEntityId` | ✅ | ✅ | CZML is Cesium's own JSON for entities and covers every graphics type and material |
| Data sources: CzmlDataSource, GeoJsonDataSource (and TopoJSON), KmlDataSource (KML / KMZ, tours), GpxDataSource, CustomDataSource; EntityCluster; exportKml | `cesium.dataSources` (URL or inline data, loader options, clustering, `flyTo`); `commands.loadDataSource` / `removeDataSource` / `exportKml`; `dataSourceLoaded` event | ✅ | ✅ | KML tours play through `evaluate` (`KmlTour.play`) |
| Time: Clock, ClockRange, ClockStep, JulianDate, SampledProperty / SampledPositionProperty interpolation (Lagrange, Hermite, linear), TimeIntervalCollection, VelocityOrientationProperty | `cesium.clock`; `commands.setClock` / `play` / `pause` / `setTime` / `getClock`; CZML `position.epoch` + samples | ✅ | ✅ | munim `motion` keyframes use the wall clock, as on MapKit |
| Camera: setView, flyTo (maximum height, pitch adjust, fly over longitude, easing), lookAt, flyHome, viewBoundingSphere, zoomTo / flyTo targets, move / look / rotate / twist / zoom, frustum (perspective, orthographic, fov, near, far), ScreenSpaceCameraController | `initialCamera`, `setCamera`, `animateCamera`, `flyCamera`, `stopFlight`, `getCamera`, `setRegion`, `getVisibleRegion`, `fitToCoordinates`, `fitToMarkers`, `cameraDistanceRange`, `cameraBoundary`, `mapPadding`, gesture props; `cesium.camera`, `cesium.controller`; `commands.flyTo` / `setView` / `lookAt` / `flyHome` / `zoomTo` / `flyToTarget` / `orbit` / `stopOrbit` / `cameraMove` / `cameraLook` / `cameraRotate` / `getCameraView` | ✅ | ✅ | The munim camera (centre, distance, pitch from straight down, heading) is measured where the centre ray meets the ground; `mapPadding` moves that point |
| Lighting and atmosphere: SunLight, DirectionalLight, Sun, Moon, SkyBox, SkyAtmosphere, Atmosphere (scene), globe lighting / ground atmosphere / dynamic lighting, Fog, ShadowMap, terrain shadows, HDR, tonemappers, exposure, ImageBasedLighting, CloudCollection (cumulus clouds) | `lighting`, `colorScheme`; `cesium.light`, `sun`, `moon`, `skyBox`, `skyAtmosphere`, `atmosphere`, `globe`, `fog`, `shadows`, `terrainShadows`, `highDynamicRange`, `tonemapper`, `exposure`, `backgroundColor`, `clouds`, `cloudOptions`, `sceneOptions` | ✅ | ✅ | `lighting="day"` / `"night"` light models from over the viewer's shoulder whatever the time |
| Globe: show, base colour, translucency, underground colour, depth test, water effect, skirts, cartographic limit, clipping, materials (elevation contour / ramp, slope, aspect, elevation bands), tile cache, screen-space error | `cesium.globe` | ✅ | ✅ | |
| Post-processing: FXAA, bloom, ambient occlusion, PostProcessStageLibrary (black and white, brightness, night vision, depth of field, edge detection, silhouette, lens flare, blur), custom stages | `cesium.postProcess` | ✅ | ✅ | Ambient occlusion and depth of field only where the WebGL context supports them |
| Picking: pick, drillPick, pickPosition, Cesium3DTileFeature properties, imagery features, SceneTransforms | `onPress`, `onMarkerPress`, `onModelPress`, `onOverlayPress`, `onMapFeaturePress` (3D Tiles features, with `selectableMapFeatures`), `pick` event; `commands.pick` / `drillPick` / `pickPosition` / `pickImageryFeatures` / `toScreen`; `pointForCoordinate`, `coordinateForPoint` | ✅ | ✅ | Double-tap entity tracking is off (the app decides) |
| Measurement: EllipsoidGeodesic, EllipsoidRhumbLine, distances, areas (EllipsoidTangentPlane + PolygonPipeline), headings, sampleTerrain(MostDetailed), sampleHeightMostDetailed, clampToHeightMostDetailed | `commands.measureDistance` (geodesic, rhumb, straight) / `measureArea` / `measureHeading` / `sampleHeights` / `clampToHeight` | ✅ | ✅ | |
| Screenshots | `takeSnapshot` (PNG file); `commands.screenshot` (PNG / JPEG data URL, any size) | ✅ | ✅ | Markers and models are in the picture (unlike MapKit's snapshot) |
| Particle systems (ParticleSystem, box / circle / cone / sphere emitters, bursts) | munim `effect` (exhaust, smoke, contrail); `commands.addParticleSystem` / `removeParticleSystem` | ✅ | ✅ | |
| Panoramas (EquirectangularPanorama, CubeMapPanorama, GoogleStreetViewCubeMapPanoramaProvider) | `commands.loadPanorama` / `removePanorama` | ✅ | ✅ | Street View needs a Street View Static API key |
| Models (Model, ModelAnimationCollection, ModelNode, CustomShader, silhouettes, colour blend) | munim `models` (the GLB catalogue and your glTF / GLB: heading, altitude, `altitudeReference`, scale, `screenSize`, `tint`, spin, `playAnimations`, `motion`, labels, stems, `lift`, ground shadows); `commands.modelInfo` / `playModelAnimation` / `stopModelAnimations` / `setModelNode` / `setModelStyle` | ✅ | ✅ | `tint` recolours `paint…` materials in the GLB itself. Shapes: box, sphere, cylinder, cone, pyramid; capsule and gem approximated |
| Widgets: Animation, Timeline, BaseLayerPicker, Geocoder (ion, Google, Bing), HomeButton, SceneModePicker, ProjectionPicker, NavigationHelpButton, FullscreenButton, VRButton, InfoBox, SelectionIndicator; inspector mixins (Cesium, 3D Tiles, voxel), PerformanceWatchdog, drag and drop | `cesium.widgets` | ✅ | ✅ | Base layer picker and geocoder need an ion token. VR and fullscreen depend on the WebView |
| Credits (CreditDisplay) | Always shown; `cesium.showCredits: false` only where the data's terms allow it | ✅ | ✅ | |
| Keys: Ion, IonResource, ArcGisMapService, GoogleMaps, BingMaps, ITwinPlatform | `configureMunimMaps({ cesiumIonToken, googleMapsApiKey })`; `cesium.ionServer`, `arcGisAccessToken`, `googleMapsApiKey`, `googleStreetViewApiKey`, `bingMapsKey`, `iTwinAccessToken`, `iTwinShareKey` | ✅ | ✅ | |
| munim markers on Cesium: pin (PinBuilder, Maki icons), balloon, image, avatar, label, dot; badges; callouts with accessories; dragging; clustering (EntityCluster) with `clusterStyles`; `MarkerView` | `markers`, `clusterStyles`, `selectMarker`, `deselectMarker`, `fitToMarkers`, marker events, `MarkerView` | ✅ | ✅ (`MarkerView` 🔨) | `glyphSymbol` takes Maki icon names (SF Symbols are Apple's); `displayPriority` / `collisionMode` have no Cesium equivalent (clustering instead) |
| munim shapes: polylines (geodesic / rhumb, dashes, gradients, `strokeStart` / `strokeEnd`), polygons with holes, circles, z-index, overlay taps | `polylines`, `polygons`, `circles`, `onOverlayPress` | ✅ | ✅ | Clamped to terrain. `lineCap` / `lineJoin` / `level` do not exist in Cesium. `overlayAtPoint` is not synchronous on Cesium: use `onOverlayPress` or `commands.drillPick` |
| munim zones and paths | `zones`, `paths` | ✅ | ✅ | Walls on the terrain; paths above the terrain (or the ellipsoid with `altitudeReference: 'sea'`) |
| User location and tracking | `showsUserLocation`, `userTrackingMode`, `showsUserTrackingButton`, `onUserLocationChange`, `onUserTrackingModeChange` | ✅ | ✅ | iOS asks for when-in-use access; Android needs the app to hold the location permission |
| Controls | `compassVisibility`, `scaleVisibility`, `pitchButtonVisibility` (2D/3D), `showsUserTrackingButton` | ✅ | ✅ | Drawn in the page (Cesium has none of its own) |
| Reverse geocoding | `addressForCoordinate` | ✅ | ✅ | The platform geocoder (CLGeocoder, android.location.Geocoder): Cesium only geocodes forwards (its Geocoder widget) |

Left out, with reasons:

- **Points of interest filter, traffic, place cards, Look Around, `mapItemForFeature`**: Apple Maps data; Cesium has none (tapped 3D Tiles features come through `onMapFeaturePress` instead).
- **`styleUrl`**: MapLibre / Mapbox style JSON; Cesium has no vector style. Use `cesium.imagery`, `tileOverlays` or an `mvt` tileset.
- **`globe`**: Cesium is always a globe in 3D; use `cesium.sceneMode` for flat maps.
- **Occluder models**: a MapKit workaround for its missing depth buffer; Cesium hides models behind terrain and 3D Tiles itself, so occluders only affect models on the native layer.
- **Low-level rendering classes** (Primitive, GeometryInstance, Appearance, Material, the geometry classes, BufferPrimitiveCollection, Matrix / Cartesian maths, Resource, TaskProcessor, RequestScheduler…): reachable with `evaluate`; the typed API wraps them through entities, CZML and options.
- **VR, fullscreen**: what the WebView allows.
