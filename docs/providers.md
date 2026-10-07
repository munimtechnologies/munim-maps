# Map providers

munim-maps draws the same React Native API (`MunimMapView`, models, markers, shapes, camera, events) on five map engines, on iOS and Android:

| Provider | `provider=` | iOS | Android | Key |
| --- | --- | --- | --- | --- |
| Apple MapKit | `'mapkit'` | Built in, the default | — (Apple only) | None |
| Google Maps | `'google'` | `NitroMunimMaps/Google` subspec | `munimMaps.google=true` (the default when on) | Google Maps SDK key |
| Mapbox | `'mapbox'` | `NitroMunimMaps/Mapbox` subspec | `munimMaps.mapbox=true` | Mapbox public token (`pk.…`) |
| MapLibre (open maps) | `'maplibre'` | `NitroMunimMaps/MapLibre` subspec | Built in (`munimMaps.maplibre=false` to drop it); the default without Google | None: OpenStreetMap data from [OpenFreeMap](https://openfreemap.org) |
| Cesium | `'cesium'` | `NitroMunimMaps/Cesium` subspec (CesiumJS 1.146 bundled, in a WKWebView) | `munimMaps.cesium=true` (in a WebView) | None: OpenStreetMap imagery, ellipsoid. A Cesium ion token adds terrain, Bing imagery, OSM Buildings and ion assets |

Engines other than MapKit (iOS) and MapLibre (Android) are opt-in at build time, so an app only ships the SDKs it uses. An engine that is not built in, or not implemented yet, shows a placeholder saying so and reports it through `onError`.

## Using it

```tsx
import { MunimMapView, configureMunimMaps } from 'munim-maps'
import { VEHICLES } from 'munim-maps/vehicles' // USDZ on iOS, GLB on Android

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
  "cesiumIonToken": "…"
}]
```

- **iOS**: writes `munimMaps.providers` to `ios/Podfile.properties.json`; the podspec turns those subspecs on (`NitroMunimMaps/Google`…). Keys go to Info.plist: `MunimMapsGoogleMapsApiKey`, `MBXAccessToken`, `MunimMapsCesiumIonToken`.
- **Android**: writes `munimMaps.<provider>=true` to `android/gradle.properties`; `android/build.gradle` adds that engine's source set and SDK. Keys go to the manifest (`com.google.android.geo.API_KEY`, `munimmaps.cesium_ion_token` meta-data) and `mapbox_access_token` in strings.xml.

### Without Expo

- **iOS**: `pod 'NitroMunimMaps/Google', :path => '../node_modules/munim-maps'` (and `/Mapbox`, `/MapLibre`, `/Cesium`) in the Podfile, or `MUNIM_MAPS_PROVIDERS=google,maplibre pod install`.
- **Android**: `munimMaps.google=true` (and `mapbox`, `cesium`; `maplibre=false` to drop MapLibre) in `android/gradle.properties`. SDK versions can be pinned with `munimMaps.maplibreVersion`, `munimMaps.googleMapsVersion`, `munimMaps.mapboxVersion`, `munimMaps.filamentVersion`.

## Feature matrix

✅ works · 🟡 partly (see note) · ⏳ coming in this release · — does not apply. MapKit is iOS only; Android's 3D layer is Filament, iOS's is SceneKit, and both read the same camera state from every engine.

| Feature | MapKit iOS | Google iOS | Google Android | Mapbox iOS | Mapbox Android | MapLibre iOS | MapLibre Android | Cesium iOS | Cesium Android |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Map on screen | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ | ✅ |
| `styleUrl` / built-in styles (`mapStyle`) | ✅ styles | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ `styleUrl` | ✅ `mapStyle`, `cesium.imagery` | ✅ `mapStyle`, `cesium.imagery` |
| Dark mode (`colorScheme`) | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ |
| 3D buildings, terrain (`elevation`, `showsBuildings`) | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ ion token | ✅ ion token |
| Globe (`globe`) | ✅ | — | — | ⏳ | ⏳ | ⏳ | ⏳ | ✅ always | ✅ always |
| `initialCamera`, `setCamera`, `animateCamera`, `getCamera` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ | ✅ |
| `flyCamera` / `stopFlight` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ |
| `setRegion`, `getVisibleRegion`, `fitToCoordinates` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ | ✅ |
| `pointForCoordinate`, `coordinateForPoint` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ | ✅ |
| Gestures on/off | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ | ✅ |
| Camera limits, boundary, `mapPadding` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ |
| `onMapReady`, `onPress`, `onLongPress`, `onCameraMove`, `onCameraChange` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ | ✅ |
| Markers (pin, balloon, image, avatar, label, dot), callouts, dragging | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ |
| Clustering (`clusteringId`, `clusterStyles`) | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ |
| `MarkerView` (React Native views as markers) | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | — |
| Polylines, polygons, circles | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ |
| Gradient / animated polylines, overlay taps | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ |
| Tile overlays | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ |
| User location, tracking modes | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ |
| Compass, scale, tracking button | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ |
| Points of interest filter, traffic | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | — | — |
| Tappable places (`onMapFeaturePress`) | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | 🟡 3D Tiles features | 🟡 3D Tiles features |
| Place cards (`selectionAccessory`), Look Around | ✅ | — | — | — | — | — | — | — | — |
| `takeSnapshot`, `addressForCoordinate` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ |
| 3D models: GLB / glTF | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ Cesium | ✅ Cesium |
| 3D models: USDZ, USD, SCN, OBJ… | ✅ | ⏳ | — | ⏳ | — | ⏳ | — | ✅ native layer | — |
| Model heading, altitude, scale, `screenSize`, `tint`, spin, `motion` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ | ✅ |
| Built-in shapes, pictures (avatars), labels, stems, `lift` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ |
| Effects (exhaust, smoke, contrail), occluders | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ (occluders: native layer) | ✅ (occluders: native layer) |
| Zones, paths | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ |
| `occlusion="buildings"` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ real depth | ✅ real depth |
| Terrain (`altitudeReference: 'sea'`, `followTerrain`, `groundElevation`) | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ Cesium terrain | ✅ Cesium terrain |
| `onModelPress` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ | ✅ |
| `measureAlignment` (3D layer vs the engine's own projection) | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ | ✅ |
| `MapModelLayer` over another library's map | ✅ react-native-maps, expo-maps | ⏳ | ⏳ react-native-maps | ⏳ | ⏳ @rnmapbox/maps | ⏳ | ⏳ | — | — |
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

### Android (`packages/munim-maps/android/`)

| File | What |
| --- | --- |
| `src/main/java/com/munimmaps/engine/MunimMapEngine.kt` | `MunimMapEngine` interface (setters, camera, methods, all with defaults), `MunimMapEngineListener` (events), `MunimMapEngineFactory` |
| `…/engine/MunimMapEngines.kt` | Registry; finds `com.munimmaps.engines.<provider>.<Name>MapEngineFactory` by name (kept by `proguard-rules.pro`) |
| `…/engine/MunimMapContainerView.kt`, `UnavailableMapEngine.kt`, `MunimMapsConfiguration.kt` | Host, placeholder, keys |
| `…/engine/MapCameraState.kt`, `MapCameraSource.kt` | The same camera model as iOS, in pixels |
| `…/engine/MapViewAdapters.kt` | Adapters that let `MapModelLayer` draw over other libraries' map views |
| `…/models/MunimModelLayer.kt`, `ModelRenderer.kt`, `ModelAssets.kt` | The Filament 3D layer (transparent TextureView, gltfio), asset loading (Metro URLs, raw resources, files, assets) |
| `…/com/margelo/nitro/munimmaps/Hybrid*.kt` | The Nitro views and `MunimMapsConfig` |
| `src/<provider>/java/com/munimmaps/engines/<provider>/` | One source set per engine, compiled only when `munimMaps.<provider>=true` (MapLibre: on by default) |

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

- **iOS**: plain launch of the example runs the MapKit self-test (`Documents/munim-maps-selftest.json`); `munimmapsexample://providers/<provider>` opens the engine picker. A fast compile check of the engine code without the SDKs: typecheck `ios/Core` and `ios/Engines` with `swiftc -typecheck -sdk iphonesimulator`, adding empty stand-in modules named `GoogleMaps`, `MapboxMaps`, `MapLibre` (`-I`) and `-D MUNIM_MAPS_CESIUM` to compile every engine's stub.
- **Android**: the example starts on the engine picker (MapLibre by default) and logs `MUNIM_MAPS_PROVIDERS … alignment {…}` every 3 s (`adb logcat | grep MUNIM_MAPS`). Build with `./gradlew :app:assembleRelease -PreactNativeArchitectures=arm64-v8a` (from `example/android`, after `npx expo prebuild --platform android`) for an arm64 phone or emulator. Phase 1 was checked on an Android 15 phone: MapLibre with the GLB vehicles, 3D layer within 0.41 pt of MapLibre's own projection.

## Cesium engine

There is no native Cesium SDK for mobile (Cesium Native is a C++ library for game engines, not a map view), so `provider="cesium"` runs **CesiumJS** in a WebView the engine owns: `WKWebView` on iOS, `android.webkit.WebView` on Android. No `react-native-webview` dependency.

- **Bundled, offline, pinned**: CesiumJS **1.146.0** (Apache-2.0; licence and third-party notices in `cesium/munim-cesium/Cesium/LICENSE.md` and `ThirdParty.json`) ships inside munim-maps under `packages/munim-maps/cesium/munim-cesium/`: the minified `Cesium.js`, its `Workers`, `ThirdParty` (Draco, Basis), `Assets` and `Widgets`, nothing else (13 MB on disk, about 4 MB compressed in an app). `scripts/cesium/vendor-cesium.sh <version>` replaces it from npm. iOS serves it from the `MunimMapsCesium` resource bundle of the `NitroMunimMaps/Cesium` subspec through a `munim-cesium://` URL scheme handler; Android serves it from the APK's assets at `https://appassets.androidplatform.net/` (`munimMaps.cesium=true` adds them).
- **The two halves**: `cesium/munim-cesium/js/*.js` (the same on both platforms) draws everything with CesiumJS; `ios/Engines/Cesium/` and `android/src/cesium/` host the WebView, send props as JSON messages (`{ t: 'set' }`), receive events and the camera, and answer methods (`{ t: 'call' }` / `{ t: 'result' }`). App files (`require()`d images and models, `file://`, Android resources, Metro's `http://` in development) reach the page through `…/resource?uri=`; on iOS, https tiles go through `…/tile/<host>/<path>` with an identifying User-Agent (OpenStreetMap's tile policy; WebKit sends no Referer from a custom scheme).
- **No key needed**: OpenStreetMap imagery and a smooth ellipsoid (no terrain). With `configureMunimMaps({ cesiumIonToken })` (or the config plugin's `cesiumIonToken`): Cesium World Terrain by default (unless `elevation="flat"`), Bing imagery through ion for `mapStyle` `imagery` / `hybrid` (Esri World Imagery without a token), Cesium OSM Buildings while `showsBuildings`, and every ion asset. `Cesium.Ion.defaultAccessToken` is set to your token or to nothing: CesiumJS's built-in evaluation token is never used.
- **3D layer, `cesium.modelRendering`**: `auto` (default) and `native` draw the munim 3D layer **natively in Cesium**, so terrain and 3D Tiles hide it: GLB / glTF models (the vehicle catalogue: `munim-maps/vehicles-glb` on iOS, `munim-maps/vehicles` is already GLB on Android) as Cesium `Model` primitives with heading, altitude, `altitudeReference`, scale, `screenSize`, `tint` (recolours `paint…` materials in the GLB), spin, embedded animations and `motion`; built-in shapes (box, sphere, cylinder, cone, pyramid; capsule and gem approximated) as entities; pictures (avatars with border and badge) as billboards; labels as label entities; stems as polylines; `lift` per frame; ground shadows as ground ellipses; effects (exhaust, smoke as particle systems, contrail as a glowing trail); zones as fading walls with a ground outline; paths as 3D polylines. `auto` sends the only things Cesium cannot draw (USDZ, SCN, OBJ files on iOS, and occluders, which Cesium's real depth makes unnecessary) to munim-maps' overlay 3D layer; `native` skips them. `overlay` draws everything on munim-maps' native 3D layer (SceneKit / Filament) over the WebView, fed with Cesium's camera every frame, exactly as on MapKit: it works (`measureAlignment` within a point of Cesium's own projection on the iPad), but it is not hidden by terrain or 3D Tiles and trails the camera by a frame while it moves, because the WebView reports its camera asynchronously. (`modelRenderer` is the older name: `cesium` = `native`, `native` = `overlay`.)
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
| munim markers on Cesium: pin (PinBuilder, Maki icons), balloon, image, avatar, label, dot; badges; callouts with accessories; dragging; clustering (EntityCluster) with `clusterStyles`; `MarkerView` | `markers`, `clusterStyles`, `selectMarker`, `deselectMarker`, `fitToMarkers`, marker events, `MarkerView` | ✅ | ✅ (`MarkerView` is iOS only, as in phase 1) | `glyphSymbol` takes Maki icon names (SF Symbols are Apple's); `displayPriority` / `collisionMode` have no Cesium equivalent (clustering instead) |
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
