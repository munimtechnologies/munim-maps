# Map providers

munim-maps draws the same React Native API (`MunimMapView`, models, markers, shapes, camera, events) on five map engines, on iOS and Android:

| Provider | `provider=` | iOS | Android | Key |
| --- | --- | --- | --- | --- |
| Apple MapKit | `'mapkit'` | Built in, the default | — (Apple only) | None |
| Google Maps | `'google'` | `NitroMunimMaps/Google` subspec | `munimMaps.google=true` (the default when on) | Google Maps SDK key |
| Mapbox | `'mapbox'` | `NitroMunimMaps/Mapbox` subspec | `munimMaps.mapbox=true` | Mapbox public token (`pk.…`) |
| MapLibre (open maps) | `'maplibre'` | `NitroMunimMaps/MapLibre` subspec | Built in (`munimMaps.maplibre=false` to drop it); the default without Google | None: OpenStreetMap data from [OpenFreeMap](https://openfreemap.org) |
| Cesium | `'cesium'` | `NitroMunimMaps/Cesium` subspec | `munimMaps.cesium=true` | Cesium ion token for ion terrain, imagery and 3D Tiles |

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
| Map on screen | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ |
| `styleUrl` / built-in styles (`mapStyle`) | ✅ styles | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ `styleUrl` | ⏳ | ⏳ |
| Dark mode (`colorScheme`) | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| 3D buildings, terrain (`elevation`, `showsBuildings`) | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Globe (`globe`) | ✅ | — | — | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ always a globe | ⏳ |
| `initialCamera`, `setCamera`, `animateCamera`, `getCamera` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ |
| `flyCamera` / `stopFlight` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| `setRegion`, `getVisibleRegion`, `fitToCoordinates` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ |
| `pointForCoordinate`, `coordinateForPoint` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ |
| Gestures on/off | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ |
| Camera limits, boundary, `mapPadding` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| `onMapReady`, `onPress`, `onLongPress`, `onCameraMove`, `onCameraChange` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ |
| Markers (pin, balloon, image, avatar, label, dot), callouts, dragging | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Clustering (`clusteringId`, `clusterStyles`) | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| `MarkerView` (React Native views as markers) | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Polylines, polygons, circles | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Gradient / animated polylines, overlay taps | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Tile overlays | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| User location, tracking modes | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Compass, scale, tracking button | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Points of interest filter, traffic | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Tappable places (`onMapFeaturePress`) | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Place cards (`selectionAccessory`), Look Around | ✅ | — | — | — | — | — | — | — | — |
| `takeSnapshot`, `addressForCoordinate` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| 3D models: GLB / glTF | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ |
| 3D models: USDZ, USD, SCN, OBJ… | ✅ | ⏳ | — | ⏳ | — | ⏳ | — | ⏳ | — |
| Model heading, altitude, scale, `screenSize`, `tint`, spin, `motion` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ |
| Built-in shapes, pictures (avatars), labels, stems, `lift` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Effects (exhaust, smoke, contrail), occluders | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Zones, paths | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| `occlusion="buildings"` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Terrain (`altitudeReference: 'sea'`, `followTerrain`, `groundElevation`) | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| `onModelPress` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ |
| `measureAlignment` (3D layer vs the engine's own projection) | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ |
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

## Engine-only methods and events

Every engine can add methods and events without changing the shared spec:

- `ref.current.providerCommand(command, argsJson)` → JSON text, and `onProviderEvent({ provider, name, data })` on `MunimMapView` (the same channel the Google, MapLibre and Cesium engines use). JavaScript: `providerCommand(ref.current, command, args)`; each engine adds typed wrappers next to its options (`mapboxMap(ref.current)`).
- `callProvider(provider, command, args)` and `addProviderEventListener(provider, listener)` for engine-level commands that need no map (Mapbox's offline downloads), through `MunimMapsConfig`.
- Native: iOS `MunimMapEngine.providerCommand(_:arguments:completion:)` / `setProviderEventHandler(_:)` and `MunimMapEngineFactory.providerCommand(_:arguments:emit:completion:)`; Android `MunimMapEngine.providerCommand(command, args, completion)` (JSON text) / `MunimMapEngineListener.onProviderEvent(name, json)` and `MunimMapEngineFactory.providerCommand(context, …)`. All have defaults (reject / drop), so engines opt in.
- `onMarkerDrag` (shared): a dragged marker's position while it moves, between `onMarkerDragStart` and `onMarkerDragEnd` (iOS `MunimMapEngine.onMarkerDrag`, Android `MunimMapEngineListener.onMarkerDrag`, defaulted).
- `MarkerView` on Android: `MunimMapView` keeps its children off screen next to the map (Android's Nitro views cannot hold React children); each `MarkerView` draws its children into a bitmap and calls `MunimMapEngine.setViewMarker` / `setViewMarkerImage` / `removeViewMarker` (defaulted), like iOS.

## Mapbox engine

Mapbox Maps SDK **11.32** on both platforms (`MapboxMaps ~> 11.32` pod; `com.mapbox.maps:android-ndk27:11.32.0`, 16 KB page aligned; both download without a secret token). Needs a public token (`pk.…`): `configureMunimMaps({ mapboxAccessToken })`, the config plugin's `mapboxAccessToken` (Info.plist `MBXAccessToken`, Android `mapbox_access_token` string), never a secret `sk.` token in an app.

- Shared API: everything in the matrix above maps onto Mapbox (details in the checklist).
- `mapbox={{ … }}` (`MapboxMapOptions`, src/providers/mapbox.ts): declarative style objects written exactly as the [Mapbox Style Specification](https://docs.mapbox.com/style-spec/) and handed to the SDK unchanged (`addLayer(with:)` / `addStyleLayer(Value)`), diffed between renders; map options (gestures, ornaments, puck, camera bounds, rendering, debug); `events` and `interactions`.
- `mapboxMap(ref.current).<method>(args)` (`MapboxMapMethods`): queries, feature state, cluster expansion, partial GeoJSON updates, runtime style edits, style imports, featuresets, Mapbox's camera in zoom levels, free camera, viewport, snapshots, elevation, location override, statistics.
- `MapboxOffline`: style packs and tile regions, with progress through `addListener`; `MapboxServices`: Geocoding v6, Search Box, Directions, Matrix, Isochrone over HTTPS with the public token (billed per request by Mapbox beyond the free tier; temporary geocoding results may not be stored, per Mapbox's terms).
- 3D: munim-maps' layer (SceneKit / Filament) is aligned to Mapbox's camera: 36.87° vertical field of view, 512-point tiles, an off-centre projection when the camera has padding (iOS), globe below zoom 5.5, `drawsTerrain` with terrain on. Mapbox's own glTF `model` layer works too (`models` + a `model` layer); munim-maps' models stay in front of Mapbox's 3D buildings (no shared depth buffer) unless `occlusion="buildings"`.

### Mapbox checklist

Every capability of the SDKs' public surface (iOS `MapboxMaps` and Android `com.mapbox.maps` + plugins + `extension-style`), with its munim-maps API. ✅ done · 🟡 partly (note) · — not offered (reason).

| Capability | munim-maps API | iOS | Android | Note |
| --- | --- | --- | --- | --- |
| Map view, token, lifecycle | `provider="mapbox"`, `configureMunimMaps({ mapboxAccessToken })` | ✅ | ⏳ | Missing token → `onError`. |
| Styles: Standard, Standard Satellite, Streets, Outdoors, Light, Dark, Satellite, Satellite Streets, Navigation | `styleUrl` + `MAPBOX_STYLES`; `mapStyle` (`standard`/`muted` → Standard, `hybrid`/`imagery` → Standard Satellite) | ✅ | ⏳ | |
| Custom style URL / JSON | `styleUrl`, `mapbox.styleJson` | ✅ | ⏳ | |
| Standard config (light presets day/dawn/dusk/night, theme default/faded/monochrome/custom, 3D objects/buildings/trees/landmarks/facades, POI/transit/place/road labels, pedestrian roads, landmark icons, admin boundaries, fonts, density…) | `mapbox.standard`, `mapbox.lightPreset`; `colorScheme` → preset, `showsBuildings` → `show3dObjects`, `pointsOfInterest: 'none'` → labels off | ✅ | ⏳ | Unknown keys pass through. |
| Style imports (add/update/move/remove, config, schema) | `mapbox.imports`, `mapbox.importConfig`; `getStyleImports`, `getStyleImportSchema`, `getStyleImportConfig`, `setStyleImportConfig` | ✅ | ⏳ | |
| Colour themes (LUT) | `mapbox.colorTheme` | ✅ | ⏳ | Experimental in the SDK. |
| Globe / Mercator projection | `globe`, `mapbox.projection` | ✅ | ⏳ | |
| Atmosphere / fog | `mapbox.atmosphere` | ✅ | ⏳ | |
| Terrain (raster-dem, exaggeration) | `mapbox.terrain`, `terrainExaggeration`; on for `hybrid`/`imagery` + `elevation="realistic"`; `getElevation` | ✅ | ⏳ | |
| Lights (flat, ambient + directional) | `mapbox.lights` | ✅ | ⏳ | |
| Snow, rain | `mapbox.snow`, `mapbox.rain` | ✅ | ⏳ | Experimental in the SDK. |
| Sources: vector, raster, raster-dem, raster-array, GeoJSON (clustering, cluster properties, line metrics), image, model, batched-model | `mapbox.sources` (style-spec JSON) | ✅ | ⏳ | |
| GeoJSON partial updates | `updateGeoJSONSource`, `add/update/removeGeoJSONSourceFeatures` | ✅ | ⏳ | |
| Video source | — | — | — | Not in the mobile SDKs (GL JS only). |
| Custom geometry / custom raster sources (tiles produced in code) | — | — | — | Need native per-tile callbacks; use a GeoJSON source or a `{z}/{x}/{y}` URL instead. |
| Layers: fill, line (dash, gradient, trim, pattern), symbol, circle, heatmap, fill-extrusion, raster, raster-particle, hillshade, background, sky, model, location-indicator, slot, clip, building | `mapbox.layers` (style-spec JSON incl. `slot`, positions `beforeId`/`aboveId`/`index`) | ✅ | ⏳ | |
| Expressions, feature state in paint | style-spec JSON; `setFeatureState`, `getFeatureState`, `removeFeatureState`, `resetFeatureStates` (by source or featureset) | ✅ | ⏳ | |
| Runtime styling | `setLayerProperties`, `getLayerProperties`, `setSourceProperties`, `getSourceProperties`, `moveLayer`, `getLayers`, `getSources`, `getSlots`, `getStyleJson` | ✅ | ⏳ | |
| Persistent layers | — | — | — | munim-maps re-adds its layers after every style load, which covers it. |
| Custom (Metal / OpenGL) layers | — | — | — | munim-maps' own 3D layer is the native drawing hook. |
| Images (SDF, stretch, content, scale) | `mapbox.images` | ✅ | ⏳ | `http(s)`, `file`, `data:` and bundled URIs. |
| glTF models for `model` layers | `mapbox.models` | ✅ | ⏳ | `munim-maps/vehicles-glb` works. |
| Queries | `queryRenderedFeatures` (point, box, viewport; layers, filter, featureset), `querySourceFeatures` | ✅ | ⏳ | |
| Cluster expansion | `getClusterExpansionZoom`, `getClusterLeaves`, `getClusterChildren` | ✅ | ⏳ | |
| Featuresets and interactions (Standard POIs, buildings, place labels, landmarks; layers) with feature state | `mapbox.interactions` → `onProviderEvent('interaction')`; `selectableMapFeatures` → `onMapFeaturePress`; `getFeaturesets` | ✅ | ⏳ | Hover is not a mobile gesture. |
| Point annotations (images, text, drag, clustering) | `markers` (all six styles), `clusteringId`, `clusterStyles`, `onClusterPress`, `draggable`, `onMarkerDrag*` | ✅ | ⏳ | One manager per clustering id. |
| Polyline / polygon / circle annotations | `polylines`, `polygons`, `circles` (as GeoJSON layers in Standard's slots) | ✅ | ⏳ | Layers rather than annotation managers, so gradients, trims and dashes per shape work. |
| View annotations (anchors, overlap, priority, dragging) | `MarkerView`; callouts (`callout`, accessories) | ✅ | ⏳ | Draggable `MarkerView` uses Mapbox's view annotation drag. |
| Camera (set, ease, fly, cancel, bounds, padding, anchors) | shared camera API; `getCameraState`, `setCamera`, `easeTo`, `flyTo`, `cancelCameraAnimations`, `cameraForCoordinates`, `getBounds`, `getCameraBounds`, `getStyleDefaultCamera`; `mapbox.cameraBounds`; `cameraDistanceRange`, `cameraBoundary`, `mapPadding` | ✅ | ⏳ | |
| Free camera | `getFreeCamera`, `setFreeCamera` | ✅ | ⏳ | |
| Gestures (pan, pinch, rotate, pitch, double tap / touch, quick zoom, pan mode, deceleration, focal point) | `zoomEnabled`… + `mapbox.gestures` | ✅ | ⏳ | |
| Ornaments: compass, scale bar, logo, attribution | `compassVisibility`, `scaleVisibility` + `mapbox.ornaments` | ✅ | ⏳ | Logo and attribution stay visible (Mapbox's terms). |
| Indoor selector | — | — | — | Restricted Mapbox indoor data. |
| Location puck 2D / 3D, bearing heading / course, pulsing, accuracy ring | `showsUserLocation` + `mapbox.puck`; `onUserLocationChange` | ✅ | ⏳ | |
| Custom location data | `setLocationOverride`, `clearLocationOverride` | ✅ | ⏳ | |
| Viewport: follow puck, overview, idle, transitions, status | `userTrackingMode` (`follow`, `followWithHeading`), `showsUserTrackingButton`, `setViewport`; `onProviderEvent('viewportStatus')` | ✅ | ⏳ | Panning away drops to `none` + `onUserTrackingModeChange`. |
| Map events | `mapbox.events`: `mapLoaded`, `mapIdle`, `mapLoadingError`, `styleLoaded`, `styleDataLoaded`, `styleImageMissing`, `styleImageRemoveUnused`, `sourceDataLoaded`, `sourceAdded`, `sourceRemoved`, `cameraChanged`, `renderFrameStarted`, `renderFrameFinished`, `resourceRequest` | ✅ | ⏳ | Plus the shared `onMapReady`, `onCameraMove`, `onCameraChange`, `onPress`, `onLongPress`. |
| Snapshots | `takeSnapshot` (the view), `snapshot` (Mapbox `Snapshotter`, any style / camera / size) | ✅ | ⏳ | |
| Offline: style packs, tile regions, estimates, metadata, quota, offline switch, clear data | `MapboxOffline` | ✅ | ⏳ | |
| Map options (constrain mode, viewport mode, north orientation, prefetch, tile cache, frame rate, style transition) | `mapbox.rendering` | ✅ | ⏳ | |
| Debug overlays | `mapbox.debug` | 🟡 | ⏳ | iOS has no wireframe options. |
| Performance statistics | `collectPerformanceStatistics` | ✅ | ⏳ | |
| Tile cover | `tileCover` | ✅ | ⏳ | |
| Map recorder / player | — | — | — | Experimental SDK debugging tool. |
| SwiftUI `Map`, Jetpack Compose `MapboxMap` | — | — | — | munim-maps wraps the UIKit / Android View API. |
| Search SDK, Navigation SDK | `MapboxServices` (web APIs) | ✅ JS | ✅ JS | Separate SDKs with their own licences; the web APIs cover search and routes. |
| Reverse geocoding | `addressForCoordinate` (Geocoding v6) | ✅ | ⏳ | |
| munim 3D layer (models, avatars, paths, zones, effects) | `models`, `zones`, `paths`, `measureAlignment` | ✅ | ⏳ | |

Testing: `munimmapsexample://mapbox` (example/MapboxScreen.tsx) shows every group; **Run checks** or `munimmapsexample://mapbox/checks` runs the checks (`MUNIM_MAPS_MAPBOX check …` in the log). Fast iOS compile loop: build the `MapboxMaps` pod scheme once (`xcodebuild -scheme MapboxMaps -configuration Release -destination generic/platform=iOS`) and typecheck `ios/Core`, `ios/Engines/*.swift`, `ios/Engines/MapKit` and `ios/Engines/Mapbox` against it with `swiftc -typecheck -I <products>/MapboxMaps -Xcc -fmodule-map-file=<products>/MapboxMaps/MapboxMaps.modulemap -F <products>/XCFrameworkIntermediates/{MapboxCoreMaps,MapboxCommon,Turf}`.
