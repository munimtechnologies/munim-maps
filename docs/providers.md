# Map providers

munim-maps draws the same React Native API (`MunimMapView`, models, markers, shapes, camera, events) on five map engines, on iOS and Android:

| Provider | `provider=` | iOS | Android | Key |
| --- | --- | --- | --- | --- |
| Apple MapKit | `'mapkit'` | Built in, the default | — (Apple only) | None |
| Google Maps | `'google'` | ✅ `NitroMunimMaps/Google` subspec | ✅ `munimMaps.google=true` (the default when on); photorealistic 3D with `munimMaps.googleMaps3d=true` | Google Maps SDK key |
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
| Map on screen | ✅ | ✅ | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ |
| `styleUrl` / built-in styles (`mapStyle`) | ✅ styles | ✅ map types, JSON styles, `styleUrl` = JSON style | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ✅ `styleUrl` | ⏳ | ⏳ |
| Dark mode (`colorScheme`) | ✅ | ✅ | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| 3D buildings, terrain (`elevation`, `showsBuildings`) | ✅ | ✅ buildings; no terrain | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Globe (`globe`) | ✅ | — | — | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ always a globe | ⏳ |
| `initialCamera`, `setCamera`, `animateCamera`, `getCamera` | ✅ | ✅ | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ |
| `flyCamera` / `stopFlight` | ✅ | ✅ | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| `setRegion`, `getVisibleRegion`, `fitToCoordinates` | ✅ | ✅ | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ |
| `pointForCoordinate`, `coordinateForPoint` | ✅ | ✅ | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ |
| Gestures on/off | ✅ | ✅ | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ |
| Camera limits, boundary, `mapPadding` | ✅ | ✅ | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| `onMapReady`, `onPress`, `onLongPress`, `onCameraMove`, `onCameraChange` | ✅ | ✅ | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ |
| Markers (pin, balloon, image, avatar, label, dot), callouts, dragging | ✅ | ✅ | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Clustering (`clusteringId`, `clusterStyles`) | ✅ | ✅ Utils | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| `MarkerView` (React Native views as markers) | ✅ | ✅ | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Polylines, polygons, circles | ✅ | ✅ | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Gradient / animated polylines, overlay taps | ✅ | ✅ | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Tile overlays | ✅ | ✅ | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| User location, tracking modes | ✅ | 🟡 tracking by munim-maps | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Compass, scale, tracking button | ✅ | 🟡 compass, my-location button; no scale | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Points of interest filter, traffic | ✅ | ✅ | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Tappable places (`onMapFeaturePress`) | ✅ | ✅ POIs (place IDs) | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Place cards (`selectionAccessory`), Look Around | ✅ | 🟡 Street View for Look Around | 🟡 Street View for Look Around; phone test pending | — | — | — | — | — | — |
| `takeSnapshot`, `addressForCoordinate` | ✅ | ✅ | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| 3D models: GLB / glTF | ✅ | ✅ | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ |
| 3D models: USDZ, USD, SCN, OBJ… | ✅ | ✅ | — | ⏳ | — | ⏳ | — | ⏳ | — |
| Model heading, altitude, scale, `screenSize`, `tint`, spin, `motion` | ✅ | ✅ | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ |
| Built-in shapes, pictures (avatars), labels, stems, `lift` | ✅ | ✅ | ⏳ Android 3D layer | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Effects (exhaust, smoke, contrail), occluders | ✅ | ✅ | ⏳ Android 3D layer | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Zones, paths | ✅ | ✅ | ⏳ Android 3D layer | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| `occlusion="buildings"` | ✅ | ✅ | ⏳ Android 3D layer | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| Terrain (`altitudeReference: 'sea'`, `followTerrain`, `groundElevation`) | ✅ | ✅ sea level (Google 2D has no terrain) | ⏳ Android 3D layer | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ | ⏳ |
| `onModelPress` | ✅ | ✅ | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ |
| `measureAlignment` (3D layer vs the engine's own projection) | ✅ | ✅ ≤ 1.7 pt (iPad) | 🟡 built; phone test pending | ⏳ | ⏳ | ⏳ | ✅ | ⏳ | ⏳ |
| `MapModelLayer` over another library's map | ✅ react-native-maps, expo-maps | — | 🟡 react-native-maps (Google `MapView` adapter); phone test pending | ⏳ | ⏳ @rnmapbox/maps | ⏳ | ⏳ | — | — |
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

## Google Maps engine checklist

Every public capability of the Maps SDK for iOS (`GoogleMaps` 10.x, CocoaPods) and the Maps SDK for Android (`play-services-maps` 20.x), plus Google Maps Utils (iOS `Google-Maps-iOS-Utils` 7.x, Android `android-maps-utils` 3.20 by default), mapped to munim-maps. Shared props and methods work as on every engine; Google-only options go in `google={{ … }}` (`GoogleMapOptions`, `src/providers/google.ts`), Google-only events arrive in `onProviderEvent` (`provider: 'google'`, typed as `GoogleMapEvent`) and Google-only methods go through `providerCommand` (typed wrapper: `googleMap(ref)`). Status: ✅ done · 🟡 partly (see note) · — not offered, with the reason · ⏳ not done yet. iOS was checked on an iPad (the Google screen's 30 checks: 30 passed, 3D layer within 1.7 pt of Google's projection at five cameras). Android ✅ means built into a release APK that compiles and runs the same code paths; the on-phone run is still pending (the test phone was disconnected).

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
| Photorealistic 3D maps (Maps 3D SDK): camera, fly-to / fly-around, glTF models, polylines, polygons, markers, map mode, clicks | `google.mode: '3d'` (+ `modelRendering`, `map3dMode`, `modelScale`), `googleMap(ref).flyTo` / `flyAround` / `stopCameraAnimation` / `getCamera3d` / `setCamera3d`, events `map3dReady`, `map3dSteady`, `cameraAnimationEnd`, `modeChange` | — `GoogleMaps3D` is a SwiftUI-only Swift package (no CocoaPods) | 🟡 built on `play-services-maps3d` 0.2.0 (`munimMaps.googleMaps3d=true`), compiles; not runnable with the dev key (needs the Map Tiles API + Maps 3D SDK for Android) |

Notes:

- **3D layer alignment.** Google publishes a zoom, not a camera distance or field of view. `GoogleCameraSource` (iOS) and `GoogleCamera` (Android) measure both from Google's own projection every frame: the ground scale along the screen row through the target gives points per metre at the target's depth, and the foreshortening of a point further up the screen gives the camera distance while the map is tilted; their product is the focal length (kept as a field of view for flat views). `googleMap(ref).cameraDiagnostics()` shows the numbers.
- **iOS SDK versions.** GoogleMaps 9.4 or later with Google Maps Utils 6.1 or later (10.x with Utils 7 when nothing else pins them; react-native-maps' Google subspec pins 9.4.0 / 6.1.0, and must be added when react-native-maps is in the app, because it registers its Google component whenever the GoogleMaps pod exists). `transitEnabled` needs 10.x. The pod's iOS minimum becomes 16.0 with the Google engine on.
- **Model rendering.** The 2D Maps SDKs have no 3D models, so on the 2D map `models` are always drawn by munim-maps' overlay (`modelRendering: 'native'` reports that). `google={{ mode: '3d' }}` (Android) switches the engine to Google's photorealistic 3D map (Maps 3D SDK, `Map3DView`): `modelRendering: 'auto'` (default) or `'native'` draws every glTF model (`uri`) as a Google `Model` (position, altitude mode from `altitudeReference`, heading, `scale` × `google.modelScale`, `motion` keyframes stepped natively, taps to `onModelPress`), and polylines, polygons and markers natively; the overlay cannot follow Google 3D's camera (no projection API), so `'overlay'` falls back to native with an error. Built-in shapes, pictures, labels, effects, zones and paths need the 2D map. Local GLBs are copied to the cache and passed as `file://` URLs.
- **What the 3D mode needs:** `munimMaps.googleMaps3d=true` (Expo plugin `googleMaps3d: true`), and a key with the **Map Tiles API** and the **Maps 3D SDK for Android** enabled (with 3D billing). The development key has neither, so the mode compiles but could not be run. `play-services-maps3d` 0.2.0 is used because 0.2.2 is built with Kotlin 2.3, which React Native's Kotlin 2.1 compiler cannot read (`munimMaps.googleMaps3dVersion` overrides it). **iOS:** the Maps 3D SDK is `GoogleMaps3D`, a SwiftUI-only Swift package; CocoaPods (which React Native uses) cannot install it, so `mode: '3d'` reports an error on iOS and stays on the 2D map.
- **Not in the SDKs**, so not offered: a scale bar, a globe, a 2D/3D button, Apple's place cards and MapKit's search (use `googleMapsServices` or MapKit's services, which work with any engine on iOS), tracking modes (munim-maps follows the user itself).
- **Engine-only events and methods** go through the shared `onProviderEvent` / `providerCommand` (added for every engine, with defaults, so no other engine changes). Google's continuous marker drag is the `markerDrag` event (iOS `mapView(_:didDrag:)`, Android `OnMarkerDragListener.onMarkerDrag` in `setUpMarkerCollection`), ready to also feed a shared `onMarkerDrag` event.
