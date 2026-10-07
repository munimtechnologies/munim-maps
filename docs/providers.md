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
| `…/models/MunimModelLayer.kt`, `ModelRenderer.kt`, `ModelAssets.kt` | The Filament 3D layer (transparent TextureView, gltfio), asset loading (Metro URLs, raw and drawable resources, files, assets) |
| `…/models/ModelMeshes.kt`, `ModelMaterials.kt`, `ModelBitmaps.kt` | Geometry built on the CPU (shapes, quads, stems, walls, ribbons), materials from gltfio's ubershader (no extra compiled materials), the Canvas-drawn pictures (avatars, labels, shadow, puffs) |
| `…/models/ModelEffects.kt`, `BuildingOccluder.kt`, `TerrainElevation.kt`, `CameraFlight.kt` | Particle effects, building occlusion (vector tiles), `MunimTerrain` (Terrarium tiles), `flyCamera` on the layer's frame clock |
| `…/com/margelo/nitro/munimmaps/Hybrid*.kt` | The Nitro views and `MunimMapsConfig` |
| `src/<provider>/java/com/munimmaps/engines/<provider>/` | One source set per engine, compiled only when `munimMaps.<provider>=true` (MapLibre: on by default) |

## The Android 3D layer

`MunimModelLayer` on Android (Filament 1.75.1) matches iOS's SceneKit layer feature for feature, and only reads `MapCameraState`, so every Android engine that provides a `MapCameraSource` gets all of it. The reference is iOS's `MapModelRenderer.swift`, `MapModelNodes.swift`, `MunimModelLayer.swift`, `BuildingOccluder.swift` and `TerrainElevation.swift`.

| iOS 3D layer feature | Android | How |
| --- | --- | --- |
| GLB / glTF models, heading, altitude, scale, spin, `motion` | ✅ | gltfio assets; glTF models turned half a turn as iOS's `GLTFLoader` does; the same keyframe maths (`pose`) |
| Embedded animations (`playAnimations`) | ✅ | gltfio `Animator`, looped on the frame clock |
| `screenSize`, `lift`, `tint` (materials named `paint…`), `groundShadow` | ✅ | Scaled by depth / focal length each frame; tint on `baseColorFactor`; a soft shadow quad under the model |
| USDZ, USD, SCN, OBJ… | — | Apple formats; `munim-maps/vehicles` hands Android the GLB catalogue |
| Built-in shapes (`box`, `sphere`, `cylinder`, `cone`, `capsule`, `pyramid`, `gem`), `color`, `emissive`, see-through colours | ✅ | Meshes built on the CPU, lit with gltfio's ubershader (as iOS: `capsule` is SceneKit's 1 × 1 capsule, a sphere stretched to `size`; the box has no chamfer) |
| Pictures (`image`, `imageBorder`, `badge`), always facing the camera, drawn over buildings | ✅ | The avatar bitmap drawn with Canvas exactly as iOS draws it, on a camera-facing quad in Filament channel 3 with depth testing off |
| Labels (22 pt pill, 4 pt above the model), stems (2 pt line, 8 pt dot) | ✅ | Same sizes, drawn on top |
| Effects: `exhaust`, `smoke`, `contrail`, `effectIntensity`, `effectOrigins` | ✅ | iOS's SceneKit particle systems simulated on the CPU (same birth rates, lives, sizes, growth, speeds, spreads, colour ramps, damping, plumes stopping at the ground, contrails thrown back at the model's speed) and drawn as sorted camera-facing puffs; shock diamonds as glowing spheres |
| `occluder` models | ✅ | Depth only, drawn first (channel 1) |
| Zones (walls with solid bands, fading up) | ✅ | Same geometry and colours |
| Paths (3D ribbons, fixed width in points, `closed`, on the globe) | ✅ | Rebuilt every frame to face the camera, as iOS |
| `occlusion="buildings"`, `buildingTilesUrl` | ✅ | Kotlin port of the vector-tile decoder; z14 OpenMapTiles `building` walls (OpenFreeMap by default) in depth only, within 9 km, nine tiles nearest first, cached in the app's cache folder |
| Globe: the Earth hides the far side | ✅ | A depth-only sphere when `MapCameraState.globe` |
| Terrain: `altitudeReference: 'sea'`, `followTerrain`, `groundElevation()` | ✅ | `MunimTerrain` in Kotlin (Terrarium PNG tiles, zoom 14, bilinear, memory + disk cache, read without colour management); lifting onto drawn terrain needs an engine that sets `drawsTerrain` |
| `lighting` (`auto` follows the map's dark mode) | ✅ | Sun + ambient light, as phase 1 |
| `maxCameraDistance` | ✅ | |
| `onModelPress` / `modelHit` | ✅ | iOS's hit test (bounding radius, 22 pt slop, nearest wins) |
| `measureAlignment` | ✅ | `modelsVisibleInRender` counts models whose bounds are on screen (iOS reads the rendered pixels) |
| `flyCamera` / `stopFlight` | ✅ every engine | `MunimMapEngine`'s default steps the keyframes on the layer's frame clock with `setCamera`, before the layer reads the camera, so the map and the models move together; other camera calls stop it |
| `realisticElevation`, `globe` on `MapModelLayer` | — | MapKit switches |

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

- **iOS**: plain launch of the example runs the MapKit self-test (`Documents/munim-maps-selftest.json`); `munimmapsexample://providers/<provider>` opens the engine picker. A fast compile check of the engine code without the SDKs: typecheck `ios/Core` and `ios/Engines` with `swiftc -typecheck -sdk iphonesimulator`, adding empty stand-in modules named `GoogleMaps`, `MapboxMaps`, `MapLibre` (`-I`) and `-D MUNIM_MAPS_CESIUM` to compile every engine's stub.
- **Android**: the example starts on the engine picker (MapLibre by default) and logs `MUNIM_MAPS_PROVIDERS … alignment {…}` every 3 s (`adb logcat | grep MUNIM_MAPS`). Build with `./gradlew :app:assembleRelease -PreactNativeArchitectures=arm64-v8a` (from `example/android`, after `npx expo prebuild --platform android`) for an arm64 phone or emulator. Phase 1 was checked on an Android 15 phone: MapLibre with the GLB vehicles, 3D layer within 0.41 pt of MapLibre's own projection.
