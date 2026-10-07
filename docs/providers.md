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

✅ works · 🧪 built, on-device check pending · 🟡 partly (see note) · ⏳ coming in this release · — does not apply. MapKit is iOS only; Android's 3D layer is Filament, iOS's is SceneKit, and both read the same camera state from every engine.

| Feature | MapKit iOS | Google iOS | Google Android | Mapbox iOS | Mapbox Android | MapLibre iOS | MapLibre Android | Cesium iOS | Cesium Android |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Map on screen | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ | ⏳ | ⏳ |
| `styleUrl` / built-in styles (`mapStyle`) | ✅ styles | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ `styleUrl` | ⏳ | ⏳ |
| Dark mode (`colorScheme`) | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | 🧪 | ⏳ | ⏳ |
| 3D buildings, terrain (`elevation`, `showsBuildings`) | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | 🟡 buildings, no 3D terrain | 🟡 buildings, no 3D terrain | ⏳ | ⏳ |
| Globe (`globe`) | ✅ | — | — | ⏳ | ⏳ | — (not in MapLibre Native) | — | ⏳ always a globe | ⏳ |
| `initialCamera`, `setCamera`, `animateCamera`, `getCamera` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ | ⏳ | ⏳ |
| `flyCamera` / `stopFlight` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | 🧪 | ⏳ | ⏳ |
| `setRegion`, `getVisibleRegion`, `fitToCoordinates` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ | ⏳ | ⏳ |
| `pointForCoordinate`, `coordinateForPoint` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ | ⏳ | ⏳ |
| Gestures on/off | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ | ⏳ | ⏳ |
| Camera limits, boundary, `mapPadding` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | 🧪 | ⏳ | ⏳ |
| `onMapReady`, `onPress`, `onLongPress`, `onCameraMove`, `onCameraChange` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ | ⏳ | ⏳ |
| Markers (pin, balloon, image, avatar, label, dot), callouts, dragging | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | 🧪 | ⏳ | ⏳ |
| Clustering (`clusteringId`, `clusterStyles`) | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | 🧪 | ⏳ | ⏳ |
| `MarkerView` (React Native views as markers) | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | — no Android `MarkerView` yet | ⏳ | ⏳ |
| Polylines, polygons, circles | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | 🧪 | ⏳ | ⏳ |
| Gradient / animated polylines, overlay taps | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | 🧪 | ⏳ | ⏳ |
| Tile overlays | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | 🧪 | ⏳ | ⏳ |
| User location, tracking modes | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | 🧪 | ⏳ | ⏳ |
| Compass, scale, tracking button | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | 🧪 | ⏳ | ⏳ |
| Points of interest filter, traffic | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | 🟡 POIs, no traffic data | 🟡 POIs, no traffic data | ⏳ | ⏳ |
| Tappable places (`onMapFeaturePress`) | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | 🧪 | ⏳ | ⏳ |
| Place cards (`selectionAccessory`), Look Around | ✅ | — | — | — | — | — | — | — | — |
| `takeSnapshot`, `addressForCoordinate` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | 🧪 | ⏳ | ⏳ |
| 3D models: GLB / glTF | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ | ⏳ | ⏳ |
| 3D models: USDZ, USD, SCN, OBJ… | ✅ | ⏳ | — | ⏳ | — | ✅ | — | ⏳ | — |
| Model heading, altitude, scale, `screenSize`, `tint`, spin, `motion` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ | ⏳ | ⏳ |
| Built-in shapes, pictures (avatars), labels, stems, `lift` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ | ⏳ |
| Effects (exhaust, smoke, contrail), occluders | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ | ⏳ |
| Zones, paths | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ | ⏳ |
| `occlusion="buildings"` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ | ⏳ |
| Terrain (`altitudeReference: 'sea'`, `followTerrain`, `groundElevation`) | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ | ⏳ |
| `onModelPress` | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ | ⏳ | ⏳ |
| `measureAlignment` (3D layer vs the engine's own projection) | ✅ | ⏳ | ⏳ | ⏳ | ⏳ | ✅ | ✅ | ⏳ | ⏳ |
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

## MapLibre engine checklist (open maps)

Every capability in the public surface of MapLibre Native for iOS (6.30, the newest on CocoaPods: the `MLN…` headers) and Android (13.6.1: `org.maplibre.android…`), mapped to the munim-maps API. Status per platform: ✅ done · 🧪 built (compiles, in the example), on-device check pending · 🟡 partly (note) · ❌ left out (reason given). iOS was checked on an iPad Air (M3) with the example's 27 MapLibre checks (27/27); the Android phone was disconnected for this round, so Android rows are 🧪. Shared rows are the props, events and methods every engine has; MapLibre-only ones are `maplibre={{…}}` options (`MapLibreMapOptions`), commands (`maplibreCommands(ref)`, which call `ref.providerCommand(name, json)`) and events (`onProviderEvent`).

### Map and style

| SDK capability | iOS | Android | munim-maps API | iOS | Android |
| --- | --- | --- | --- | --- | --- |
| Map view, lifecycle | `MLNMapView` | `MapView` + `onStart…onDestroy` | `provider="maplibre"` | ✅ | 🧪 |
| Style from URL | `styleURL` | `setStyle(String)` | `styleUrl` | ✅ | 🧪 |
| Style from JSON | `styleJSON` | `Style.Builder().fromJson` | `maplibre.styleJson` (string or object) | ✅ | 🧪 |
| OpenFreeMap styles, no key | — | — | `maplibre.style`: `liberty` (default), `bright`, `positron`, `dark`, `fiord` | ✅ | 🧪 |
| Keyed providers | `MLNSettings.apiKey`, `MLNTileServerOptions`, `useWellKnownTileServer` | `MapLibre.getInstance(ctx, key, WellKnownTileServer)`, `TileServerOptions` | `maplibre.style`: `maptiler-*`, `stadia-*` with `maplibre.apiKey` (the style URL carries the key) | ✅ | 🧪 |
| Predefined styles | `MLNStyle.predefinedStyles`, `MLNDefaultStyle` | `Style.getPredefinedStyles`, `DefaultStyle` | `maplibre.style: 'demotiles'` (the SDKs' own list is MapLibre's demo tiles) | ✅ | 🧪 |
| `mapStyle` standard / muted | — | — | `standard` → Liberty, `muted` → Positron | ✅ | 🧪 |
| `mapStyle` hybrid / imagery | raster source | raster source | needs `maplibre.satelliteTilesUrl` (there is no keyless satellite imagery); `hybrid` keeps roads and labels over it | ✅ | 🧪 |
| Dark mode | — | — | `colorScheme="dark"` → `maplibre.darkStyle` (default OpenFreeMap Dark) | ✅ | 🧪 |
| Reload style | `reloadStyle:` | `setStyle` again | command `reloadStyle` | ✅ | 🧪 |
| Style switching at runtime | `styleURL =` | `setStyle` | change `styleUrl` / `maplibre.style`; markers, shapes and runtime layers come back on the new style | ✅ | 🧪 |
| Style transition | `MLNStyle.transition` | `Style.setTransition` | `maplibre.transition { duration, delay }` (ms) | ✅ | 🧪 |
| Placement transitions | `performsPlacementTransitions` | no API | `maplibre.placementTransitions` | ✅ | ❌ no Android API |
| Light | `MLNLight` | `Style.getLight()` | `maplibre.light` (style-spec `light`) | ✅ | 🧪 |
| Label language | `localizeLabelsIntoLocale:` | no API | `maplibre.labelLanguage` (rewrites `text-field` to `name:<lang>` with a fallback, on both) | ✅ | 🧪 |
| Local CJK glyphs | `MLNIdeographicFontFamilyName` (Info.plist) | `MapLibreMapOptions.localIdeographFontFamily` | Android: `maplibre.localIdeographFontFamily`; iOS: the Info.plist key | ❌ Info.plist only | 🧪 |
| Globe projection | not in MapLibre Native (GL JS only) | not in MapLibre Native | `globe` / `maplibre.projection: 'globe'` report "not supported" | ❌ SDK has none | ❌ SDK has none |
| 3D terrain | not in MapLibre Native | not in MapLibre Native | `elevation="realistic"` stays flat; hillshade and color relief instead | ❌ SDK has none | ❌ SDK has none |
| 3D buildings | `fill-extrusion` layers | same | `showsBuildings` toggles the style's building layers | ✅ | 🧪 |
| Points of interest | style `poi` layers | same | `pointsOfInterest` (`all`, `none`, OpenMapTiles `class` names) | ✅ | 🧪 |
| Traffic | no traffic data in OpenStreetMap | same | `showsTraffic` reports unsupported | ❌ no data | ❌ no data |

### Runtime styling (the whole style spec)

| SDK capability | iOS | Android | munim-maps API | iOS | Android |
| --- | --- | --- | --- | --- | --- |
| Sources: vector, raster, raster-dem, geojson, image | `MLNVectorTileSource`, `MLNRasterTileSource`, `MLNRasterDEMSource`, `MLNShapeSource`, `MLNImageSource` | `VectorSource`, `RasterSource`, `RasterDemSource`, `GeoJsonSource`, `ImageSource` | `maplibre.sources` (style-spec source objects); commands `addSource`, `removeSource` | ✅ | 🧪 |
| Tile templates, TileJSON, scheme, bounds, zoom range, attribution, tile size, DEM encoding | `MLNTileSourceOption…` | `TileSet` | the style-spec keys (`tiles`, `url`, `scheme`, `bounds`, `minzoom`, `maxzoom`, `tileSize`, `encoding`, `attribution`) | ✅ | 🧪 |
| PMTiles | `pmtiles://` URLs | same | `url: 'pmtiles://https://…'` | ✅ | 🧪 |
| MapLibre Tiles (MLT) | `encoding: 'mlt'` | same | the source's `encoding` | ✅ | 🧪 |
| GeoJSON: cluster, clusterRadius, clusterMaxZoom, lineMetrics, tolerance, buffer, maxzoom | `MLNShapeSourceOption…` | `GeoJsonOptions` | geojson source keys | ✅ | 🧪 |
| GeoJSON `clusterProperties` | `MLNShapeSourceOptionClusterProperties` | no API | ❌ Android has no API; left out on both so a map means the same everywhere | ❌ | ❌ |
| Update GeoJSON | `MLNShapeSource.shape`, `URL` | `setGeoJson`, `setUri` | command `setGeoJson`, or new `maplibre.sources` | ✅ | 🧪 |
| Computed / custom geometry sources | `MLNComputedShapeSource` | `CustomGeometrySource`, `CustomVectorSource` | ❌ they call native code for every tile; GeoJSON or a tile server covers the same ground | ❌ | ❌ |
| Source tuning (prefetch delta, volatile, overscale, update interval) | no API | `Source.setPrefetchZoomDelta`… | ❌ Android only and rarely needed; `maplibre.rendering.prefetchZoomDelta` covers the map | ❌ | ❌ |
| Layers: fill, line, symbol, circle, heatmap, fill-extrusion, raster, hillshade, color-relief, background | `MLN…StyleLayer` | `…Layer` | `maplibre.layers` (style-spec layers + `beforeId`); commands `addLayer`, `removeLayer`, `moveLayer` | ✅ | 🧪 |
| Paint and layout properties, expressions | KVC with `NSExpression(mlnJSONObject:)` | `PaintPropertyValue`, `LayoutPropertyValue` | style-spec JSON as is; commands `setPaintProperty`, `setLayoutProperty` | ✅ | 🧪 |
| Filters | `predicate` (`NSPredicate(mlnJSONObject:)`) | `setFilter(Expression)` | the layer's `filter`; command `setFilter` | ✅ | 🧪 |
| Layer zoom range, visibility, source layer | `minimumZoomLevel`, `isVisible`, `sourceLayerIdentifier` | `setMinZoom`, `visibility` | `minzoom`, `maxzoom`, `layout.visibility`, `source-layer`; command `setLayerZoomRange` | ✅ | 🧪 |
| Style images (icons, patterns, SDF) | `setImage:forName:` (template images for SDF) | `addImage(id, bitmap, sdf)` | `maplibre.images { name: uri \| { uri, sdf } }`; commands `addImage`, `removeImage` | ✅ | 🧪 |
| Missing images | `didFailToLoadImage:` | `OnStyleImageMissingListener` | event `styleImageMissing` | ✅ | 🧪 |
| Feature state | `MLNShapeSource` / `MLNVectorTileSource` `setFeatureState…` | `setFeatureState`, `getFeatureState`, `removeFeatureState` | commands `setFeatureState`, `getFeatureState`, `removeFeatureState` | ✅ | 🧪 |
| Hillshade from public elevation data | `MLNRasterDEMSource` + `MLNHillshadeStyleLayer` | `RasterDemSource` + `HillshadeLayer` | `maplibre.hillshade` (`true` or options; AWS Terrain Tiles, keyless) | ✅ | 🧪 |
| Color relief | `MLNColorReliefStyleLayer` | `ColorReliefLayer` | `maplibre.colorRelief` | ✅ | 🧪 |
| Custom native layers | `MLNCustomStyleLayer`, `MLNPluginLayer` | `CustomLayer` | ❌ native drawing code, not data; munim-maps' 3D layer covers models | ❌ | ❌ |
| Style out | `MLNStyle.styleJSON` | `Style.getJson` | command `getStyle` (layer ids, source ids, style JSON) | ✅ | 🧪 |

### Camera, gestures, ornaments

| SDK capability | iOS | Android | munim-maps API | iOS | Android |
| --- | --- | --- | --- | --- | --- |
| Camera get / set / animate | `camera`, `setCamera:withDuration:animationTimingFunction:` | `cameraPosition`, `moveCamera`, `easeCamera` | `initialCamera`, `setCamera`, `animateCamera`, `getCamera` | ✅ | 🧪 |
| Fly-to (zoom-out arc) | `flyToCamera:withDuration:…` | `animateCamera` | command `flyTo { camera, durationMs }` | ✅ | 🧪 |
| Keyframed flights | — | — | `flyCamera`, `stopFlight` (munim-maps' frame clock) | ✅ | 🧪 |
| Regions and fitting | `setVisibleCoordinateBounds:edgePadding:`, `cameraThatFitsCoordinateBounds:` | `newLatLngBounds`, `getCameraForLatLngBounds` | `setRegion`, `getVisibleRegion`, `fitToCoordinates`, `fitToMarkers` | ✅ | 🧪 |
| Projection | `convertPoint:…`, `convertCoordinate:…`, `metersPerPointAtLatitude:` | `Projection` | `pointForCoordinate`, `coordinateForPoint`; command `metersPerPoint` | ✅ | 🧪 |
| Padding | `contentInset` | `setPadding` | `mapPadding` | ✅ | 🧪 |
| Zoom and pitch limits | `minimumZoomLevel`, `maximumZoomLevel`, `minimumPitch`, `maximumPitch` | `setMin/MaxZoomPreference`, `setMin/MaxPitchPreference` | `cameraDistanceRange`; `maplibre.camera { minZoom, maxZoom, minPitch, maxPitch }` | ✅ | 🧪 |
| Camera bounds | `maximumScreenBounds` | `setLatLngBoundsForCameraTarget` | `cameraBoundary` | ✅ | 🧪 |
| Camera roll | `MLNMapCamera.roll` | `CameraPosition.roll` | `maplibre.camera.roll` | ✅ | 🧪 |
| Field of view | fixed 36.87° | `CameraPosition.fov` | read for the 3D layer | ✅ | 🧪 |
| Reset north / position | `resetNorth`, `resetPosition` | `resetNorth` | commands `resetNorth`, `resetPosition` | ✅ | 🧪 |
| Gestures on/off | `zoomEnabled`, `scrollEnabled`, `rotateEnabled`, `pitchEnabled` | `UiSettings` | `zoomEnabled`, `scrollEnabled`, `rotateEnabled`, `pitchEnabled` | ✅ | 🧪 |
| Gesture tuning | `quickZoomReversed`, `panScrollingMode`, `toleranceForSnappingToNorth`, `decelerationRate`, `anchorRotateOrZoomGesturesToCenterCoordinate`, `hapticFeedbackEnabled` | `UiSettings`: double tap, quick zoom, fling / scale / rotate velocity, horizontal scroll, `disableRotateWhenScaling`, `increaseRotateThresholdWhenScaling` | `maplibre.gestures { … }` (each key on the platforms that have it) | ✅ | 🧪 |
| Compass | `showsCompassView`, `compassView.compassVisibility`, position, margins | `UiSettings.compass…` (gravity, margins, fade when facing north) | `compassVisibility`; `maplibre.ornaments.compass { position, margin }` | ✅ | 🧪 |
| Scale bar | `showsScale`, `scaleBarPosition`, margins, `scaleBarUsesMetricSystem` | none in the SDK | `scaleVisibility` (Android: munim-maps draws one); `maplibre.ornaments.scaleBar { position, margin, metric }` | ✅ | 🧪 |
| Logo, attribution | `showsLogoView`, `showsAttributionButton`, positions, margins | `UiSettings.logo…`, `attribution…` | `maplibre.ornaments.logo`, `.attribution` (attribution stays on by default, as OpenStreetMap's licence asks) | ✅ | 🧪 |
| Rendering | `preferredFramesPerSecond`, `prefetchesTiles`, `tileCacheEnabled`, `tileLod…`, `frustumOffset`, `debugMask`, `enableRenderingStatsView:` | `setMaximumFps`, `setPrefetchZoomDelta`, `setTileCacheEnabled`, `setTileLod…`, `setFrustumOffset`, `setDebugActive`, `enableRenderingStatsView` | `maplibre.rendering { maxFps, prefetchTiles, prefetchZoomDelta, tileCache, tileLodScale, tileLodMinRadius, tileLodPitchThreshold, tileLodZoomShift, frustumOffset, debug, renderingStats }` | ✅ | 🧪 |
| Surface options | — | `MapLibreMapOptions` texture mode, translucency, `pixelRatio`, `foregroundLoadColor`; Vulkan / OpenGL AAR flavours | `maplibre.pixelRatio`, `maplibre.foregroundLoadColor`; texture mode stays off (the 3D layer is its own view); the backend is the AAR flavour | — | 🧪 |
| Action journal | `MLNActionJournalOptions` | `MapLibreMapOptions.actionJournal…` | ❌ diagnostics for MapLibre's own developers | ❌ | ❌ |

### Markers and shapes

munim-maps draws markers and shapes on MapLibre as GeoJSON sources with style layers, not the SDKs' annotation views, so clustering, collision and ordering work the same on both platforms. They stand in for the SDKs' annotation classes (`MLNPointAnnotation`, `MLNAnnotationView`, `MLNAnnotationImage`, `MLNCalloutView`, `MLNPolyline`, `MLNPolygon`; Android's deprecated `Marker`, `Polyline`, `Polygon`, `InfoWindow`).

| Capability | munim-maps API | iOS | Android |
| --- | --- | --- | --- |
| Point markers: pin, balloon with glyph, image, avatar with badges, label, dot | `markers` (`style`) | ✅ | 🧪 |
| Anchor, z order, opacity, visibility, collision, display priority | `anchorX/Y`, `zIndex`, `opacity`, `visible`, `collisionMode`, `displayPriority` (symbol sort key, allow-overlap) | ✅ | 🧪 |
| Callouts with title, subtitle, accessories | `calloutEnabled`, `onCalloutPress`, `onCalloutAccessoryPress` (munim-maps' callout view) | ✅ | 🧪 |
| Select / deselect | `selectMarker`, `deselectMarker`, `onMarkerPress`, `onMarkerDeselect` | ✅ | 🧪 |
| Dragging | `draggable`, `onMarkerDragStart`, `onMarkerDragEnd` (long press, then drag) | ✅ | 🧪 |
| Clustering | `clusteringId`, `clusterStyles`, `onClusterPress` (GeoJSON clustering per `clusteringId`) | ✅ | 🧪 |
| React Native views as markers | `MarkerView` (drawn as an image marker) | ✅ | ❌ `MarkerView` has no Android view yet (shared code) |
| Polylines: colour, width, dashes, caps, joins, geodesic, gradient, partial stroke | `polylines` (`line-gradient`; geodesic lines densified; `strokeStart` / `strokeEnd` cut the line) | ✅ | 🧪 |
| Polygons with holes, circles | `polygons`, `circles` (geodesic rings) | ✅ | 🧪 |
| Overlay level | `level`: `aboveRoads` (below the first label layer) or `aboveLabels` | ✅ | 🧪 |
| Overlay taps | `onOverlayPress`, `overlayAtPoint` | ✅ | 🧪 |
| Tile overlays | `tileOverlays` (raster source and layer; `replacesMap` hides the style's layers) | ✅ | 🧪 |

### User location

| SDK capability | iOS | Android | munim-maps API | iOS | Android |
| --- | --- | --- | --- | --- | --- |
| Show location | `showsUserLocation` | `LocationComponent` | `showsUserLocation` | ✅ | 🧪 |
| Tracking modes | `MLNUserTrackingMode` none, follow, followWithHeading, followWithCourse | `CameraMode` NONE, TRACKING, TRACKING_COMPASS, TRACKING_GPS; `RenderMode` NORMAL, COMPASS, GPS | `userTrackingMode`, `onUserTrackingModeChange`; `maplibre.location.course` follows the course instead of the heading | ✅ | 🧪 |
| Location updates | `didUpdateUserLocation:` | `LocationEngine` callbacks | `onUserLocationChange` | ✅ | 🧪 |
| Puck look | `MLNUserLocationAnnotationViewStyle`, `showsUserHeadingIndicator`, `userLocationVerticalAlignment` | `LocationComponentOptions` (colours, accuracy ring, pulse, bearing) | `maplibre.location { puckColor, accuracyColor, pulse, pulseColor, showsHeading, verticalAlignment, renderMode }` | ✅ | 🧪 |
| Tracking button | — | — | `showsUserTrackingButton` (munim-maps' button) | ✅ | 🧪 |
| Custom location sources | `MLNLocationManager` | `LocationEngine` | ❌ app code; munim-maps uses the platform's location services | ❌ | ❌ |

### Queries, snapshots, offline, network

| SDK capability | iOS | Android | munim-maps API | iOS | Android |
| --- | --- | --- | --- | --- | --- |
| Rendered features at a point or in a box, by layer and filter | `visibleFeaturesAtPoint:inStyleLayersWithIdentifiers:predicate:` | `queryRenderedFeatures` | command `queryRenderedFeatures { point \| box, layers, filter }` → GeoJSON | ✅ | 🧪 |
| Source features | `MLNVectorTileSource.featuresInSourceLayersWithIdentifiers:predicate:`, `MLNShapeSource.featuresMatchingPredicate:` | `querySourceFeatures` | command `querySourceFeatures { source, sourceLayers, filter }` | ✅ | 🧪 |
| Cluster leaves, children, expansion zoom | `MLNShapeSource.leavesOfCluster:…`, `childrenOfCluster:`, `zoomLevelForExpandingCluster:` | `getClusterLeaves`, `getClusterChildren`, `getClusterExpansionZoom` | commands of the same names | ✅ | 🧪 |
| Tapping base-map places | `visibleFeaturesAtPoint:` | `queryRenderedFeatures` | `onMapFeaturePress`, `selectableMapFeatures` (OpenMapTiles `poi`, `place`, `water_name`, `mountain_peak`) | ✅ | 🧪 |
| Snapshot of the view | — | `MapLibreMap.snapshot` | `takeSnapshot` | ✅ | 🧪 |
| Snapshotter (offscreen; any style, camera, size) | `MLNMapSnapshotter` | `MapSnapshotter` | command `snapshot { width, height, styleUrl, camera, showsLogo }` | ✅ | 🧪 |
| Offline packs: create (tile pyramid or shape), list, resume, suspend, delete, invalidate, progress, metadata | `MLNOfflineStorage`, `MLNOfflinePack`, `MLNTilePyramidOfflineRegion`, `MLNShapeOfflineRegion` | `OfflineManager`, `OfflineRegion`, `OfflineTilePyramidRegionDefinition`, `OfflineGeometryRegionDefinition` | commands `offlineCreatePack`, `offlineListPacks`, `offlineResumePack`, `offlineSuspendPack`, `offlineDeletePack`, `offlineInvalidatePack`; events `offlineProgress`, `offlineError` | ✅ | 🧪 |
| Ambient cache | `setMaximumAmbientCacheSize:`, `clearAmbientCache…`, `invalidateAmbientCache…`, `resetDatabase…` | the same names | commands `offlineSetAmbientCacheSize`, `offlineClearAmbientCache`, `offlineInvalidateAmbientCache`, `offlineResetDatabase` | ✅ | 🧪 |
| Side-loading a database | `addContentsOfFile:` | `mergeOfflineRegions` | command `offlineMergeDatabase { path }` | ✅ | 🧪 |
| Preloading single resources | `preloadData:forURL:…`, `putResourceWithUrl:` | `putResourceWithUrl` | ❌ tile pyramids and database merges cover offline use | ❌ | ❌ |
| Tile count limit | `setMaximumAllowedMapboxTiles:` | `setOfflineMapboxTileCountLimit` | ❌ applies to Mapbox-hosted tiles only | ❌ | ❌ |
| Connectivity | no API | `MapLibre.setConnected` | command `setConnected` | ❌ no iOS API | 🧪 |
| HTTP headers | `MLNNetworkConfiguration.sessionConfiguration` | `HttpRequestUtil.setOkHttpClient` | `maplibre.httpHeaders` | ✅ | 🧪 |
| Logging | `MLNLoggingConfiguration` | `Logger.setVerbosity` | `maplibre.logLevel` | ✅ | 🧪 |

### Events

| SDK callback | munim-maps | iOS | Android |
| --- | --- | --- | --- |
| Map loaded, style loaded, load failed | `onMapReady`; `onProviderEvent` `styleLoaded`, `mapLoadFailed` | ✅ | 🧪 |
| Region will change (with reason), is changing, did change | `onCameraMove`, `onCameraChange`; `onProviderEvent` `cameraMoveStarted { reason }` | ✅ | 🧪 |
| Idle, map fully rendered | `onProviderEvent` `idle`, `renderedMap { fullyRendered }` | ✅ | 🧪 |
| Source changed | `onProviderEvent` `sourceChanged` | ✅ | 🧪 |
| Render errors | `onProviderEvent` `renderError` | ✅ | 🧪 |
| Sprite, glyph, tile and shader events | ❌ MapLibre's own diagnostics | ❌ | ❌ |
| Taps, long presses | `onPress`, `onLongPress` | ✅ | 🧪 |
| Annotation select / drag / callout | the marker events above | ✅ | 🧪 |
| User location, tracking mode | `onUserLocationChange`, `onUserTrackingModeChange` | ✅ | 🧪 |
| Camera change veto (`shouldChangeFromCamera:toCamera:`) | ❌ a synchronous native veto; `cameraBoundary` and the limits cover it | ❌ | ❌ |

### Services (OpenStreetMap, no key)

`addressForCoordinate` and `openMapsServices` (exported by `munim-maps`) use [Nominatim](https://nominatim.org) (reverse and forward geocoding), [Photon](https://photon.komoot.io) (search as you type) and [OSRM](https://project-osrm.org) or [Valhalla](https://valhalla.github.io/valhalla/) (routing), each with a configurable endpoint. The public servers are for light use only: Nominatim allows one request a second with an identifying User-Agent and no bulk geocoding; the OSRM demo server is for testing. Point the endpoints at your own server or a hosted one in production.

| Service | munim-maps API | iOS | Android |
| --- | --- | --- | --- |
| Reverse geocoding | `addressForCoordinate`, `openMapsServices.reverseGeocode` | ✅ | 🧪 |
| Forward geocoding / search | `openMapsServices.geocode`, `openMapsServices.search` (Photon) | ✅ | 🧪 |
| Routing | `openMapsServices.route` (OSRM or Valhalla) | ✅ | 🧪 |

### Left out on purpose

- Coordinate, distance, clock and compass direction formatters (`MLNCoordinateFormatter`…): Foundation formatters, not map features; JavaScript has `Intl`.
- Android plugins (annotation, offline, localization, scale bar, building, markerview): separate artifacts whose features munim-maps implements itself (markers, offline, label language, scale bar, buildings, `MarkerView`).
