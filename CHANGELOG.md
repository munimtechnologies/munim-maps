# Changelog

All notable changes to this project are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `MapModelLayer` over `@rnmapbox/maps` on Android: the layer finds the Mapbox `MapView` (by `mapTestID`, or the nearest one) and draws with Mapbox's own camera (centre, zoom on 512-point tiles, pitch, bearing, padding, Mapbox's 36.87° field of view), every frame. No flag: the adapter compiles whenever `@rnmapbox/maps` (or munim-maps' Mapbox engine) is in the app, against the Mapbox SDK version `@rnmapbox/maps` builds with (`compileOnly`, nothing added to the APK). Taps on models fire `onModelPress` through Mapbox's gestures plugin, next to `@rnmapbox/maps`' own `onPress`. On a Galaxy A14: within 0.09 pt of Mapbox's `pixelForCoordinate` at seven cameras (one padded) and during an animation, within 2 pt on screenshots while dragging.
- `MapModelLayer` over react-native-maps on Android (Google Maps) without munim-maps' Google engine: the Google adapter compiles whenever react-native-maps is in the app. It finds the camera's centre with Google's projection, so react-native-maps' `mapPadding` is followed. On a Galaxy A14: within 0.35 pt of Google's projection, within 2 pt on screenshots while dragging. No `onModelPress` here: Google's map has a single click listener, react-native-maps'.
- Example: `munimmapsexample://layer/rnmapbox` and `layer/rnmaps-google` (Android): vehicles, avatars, shapes, effects, zones and paths over each library's map; `/check` measures them against the host's own projection at seven cameras (one with map padding) and during a host-driven animation (`MUNIM_MAPS_LAYER_OVER` log lines), `/pan`, `/pan45` and `/pan45pad` (`/tex`: the Mapbox map in a TextureView) show a probe (the host's magenta circle under munim-maps' green tile) for screenshots while dragging: `example/scripts/layer-pan.sh` drags and saves frames, `layer-probe.py` measures them, `run-check.sh` runs a deep link and keeps its log. `@rnmapbox/maps` is in the example for Android only (`example/react-native.config.js`), its token from the same keys file as the others.

### Fixed

- Android: the 3D layer stayed one frame behind once the map stopped moving whenever Filament skipped the last frame (the GPU busy during a fast drag); a skipped frame is now drawn on the next one.
- Android, Mapbox engine: models were off with camera padding on a pitched map (38 pt with 160 points of top padding at 50°, measured over `@rnmapbox/maps` with the same camera code): Mapbox moves its centre of perspective to the padded centre, which `MapCameraState` now models (`principalX` / `principalY`, drawn with Filament's camera shift).
- Android, Google: with map padding the camera's field of view was measured as if the target were straight ahead (17.6° instead of 30°, 11 pt off). Padded cameras now use the field of view measured without padding, and Google's starting field of view is the 30° measured on Android.

### Changed

- Android: `MapModelLayer` keeps its 3D view exactly over the map's view (position and size, before every draw), so it lines up even when the layer and the map are not the same size, and finds the map again after it is remounted.
- Android: `MapViewAdapters` finds its built-in adapters by class name (like the engines); `MapCameraSource.setTapListener` (default: none) lets an adapter pass map taps to the layer.

## [0.5.0] - 2026-10-07

munim-maps is one API over five map engines (MapKit, Google Maps, Mapbox, MapLibre and Cesium) on iOS and Android, and ships no 3D models any more: the vehicle catalogue is the separate `munim-maps-vehicles` package. See [docs/providers.md](docs/providers.md).

### Breaking

- `munim-maps/vehicles` and `munim-maps/vehicles-glb` throw an error that points to `munim-maps-vehicles`. The npm package no longer carries the 34 MB of models, and apps no longer bundle all 57: install `munim-maps-vehicles` and `import { VEHICLES } from 'munim-maps-vehicles'` (remote, cached on the device) or `import car from 'munim-maps-vehicles/bundled/car-ev'` (one model in the app). The Swift Package's `MunimMapsVehicles` has the names and remote URLs (`MunimVehicles.url(_:)`, `glbURL(_:)`, `baseURL`) and no resources.
- The Cesium engine loads CesiumJS from jsDelivr by default, and the npm package no longer carries CesiumJS (13 MB). To bundle it, add `cesium` to the app (`npm install cesium@1.146.0`, the version the engine is written for; other versions build with a warning) and turn on `cesium: { bundled: true }` (Expo), `munimMaps.cesiumBundled=true` (Gradle) or `MUNIM_MAPS_CESIUM_BUNDLED=1` (CocoaPods): the minified build, its `LICENSE.md` and `ThirdParty.json` are copied from the app's `cesium` package at `pod install` (into the `MunimMapsCesium` resource bundle) and by a Gradle task (`munimMapsCopyCesium`, generated assets). `MUNIM_MAPS_CESIUM_DIR` / `munimMaps.cesiumDir` point at another `cesium` folder.
- Android with Mapbox: Mapbox's Maven repository comes from the Expo config plugin (or your `android/build.gradle`), no longer from a `rootProject.allprojects` hook in munim-maps' build file.

### Added

**Engines and setup**

- `provider` on `MunimMapView`: `'mapkit'` (default on iOS), `'google'`, `'mapbox'`, `'maplibre'` (default on Android without Google) or `'cesium'`, with `styleUrl` and per-engine options in `google`, `mapbox`, `maplibre`, `cesium` and `mapkit` props. Engines that are not built in show a placeholder and report `onError`.
- `configureMunimMaps({ googleMapsApiKey, mapboxAccessToken, cesiumIonToken, maplibreStyleUrl, mapboxStyleUrl, defaultProvider })`, `availableProviders()`, `installedProviders()`, `isProviderAvailable()` and `MAP_PROVIDERS`.
- Expo config plugin (`"plugins": [["munim-maps", { "providers": [...], ...keys }]]`): turns engines on (CocoaPods subspecs through `Podfile.properties.json`, Gradle properties) and writes their keys into Info.plist, the manifest and strings.xml. It also adds Mapbox's Maven repository on Android, `googleMaps3d` and `cesium: { bundled }`.
- Opt-in engines: `NitroMunimMaps/Google`, `/Mapbox`, `/MapLibre` and `/Cesium` subspecs on iOS (the default install is still MapKit only), `munimMaps.google`, `mapbox`, `maplibre` and `cesium` Gradle properties on Android.
- Swift: the `MunimMapEngine` protocol, `MunimMapContainerView`, `MunimMapEngines`, `MunimMapsConfiguration`, and `MapCameraSource` / `MapCameraState`, so `MunimModelLayer.attach(to:)` can draw over any engine's map.

**Shared API on every engine**

- `modelRendering: 'auto' | 'native' | 'overlay'` on `MunimMapView`: who draws `models`. `auto` lets Mapbox (its model layer), Cesium (entities) and Google's photorealistic 3D map (Android) draw them, and uses munim-maps' 3D layer on MapKit, MapLibre and the Google 2D map; whatever an engine cannot draw stays on the 3D layer, except on Cesium. `google.modelRendering`, `mapbox.modelRendering` and `cesium.modelRendering` are aliases.
- Engine-only methods and events through one channel: `ref.current.providerCommand(command, argsJson)` and `onProviderEvent({ provider, name, data })`, with `providerCommand(ref, name, args)`, `parseProviderEvent`, `callProvider` / `addProviderEventListener` for engine-level commands that need no map, and typed wrappers per engine (`googleMap`, `googleEvent`, `mapboxMap`, `maplibreCommands`, `cesiumCommands`, `parseCesiumEvent`).
- `onMarkerDrag`: a marker's position while it is dragged, between `onMarkerDragStart` and `onMarkerDragEnd`, on every engine (MapKit reads the dragged view on a display link).
- react-native-maps' region API: `initialRegion`, a controlled `region`, `onRegionChangeStart`, `onRegionChangeComplete(region)` and `ref.animateToRegion(region, ms)`; `initialCamera` is optional when a region is given.
- `MarkerView` on Android, on every engine: the views are drawn into a bitmap (again on change with `tracksViewChanges`); Mapbox shows them as view annotations, Google, MapLibre and Cesium as image markers.
- `selectableMapFeatures` reaches every Android engine (Mapbox: Standard's POI, landmark and place-label featuresets).
- Remote models (`http(s)://`, such as munim-maps-vehicles') are cached on disk on Android too, and Mapbox's model layer and Cesium read the cached files, so maps work offline after the first load. Two-format sources (`{ uri, usdz, glb }`) let munim-maps pick USDZ or GLB per engine and platform.

**Vehicle catalogue package**

- `munim-maps-vehicles`: the 57 models as USDZ and GLB; `VEHICLES[name]` (jsDelivr URLs at the package's version), `VEHICLE_NAMES`, `VehicleName`, `vehicleSource(name)`, `configureMunimMapsVehicles({ baseUrl })` for self-hosting, and `munim-maps-vehicles/bundled/<name>` / `bundled/glb/<name>` (one file per model). `scripts/vehicles/write-catalogue.mjs` generates its files from the models `make-vehicles.swift` writes.

**Android**

- **Android**: `MunimMapView` and `MapModelLayer` are Kotlin Nitro views. `MunimMapView` draws MapLibre Native with OpenFreeMap (no key) and GLB / glTF models through a Filament 3D layer driven by the same camera model as iOS (position, altitude, heading, scale, `screenSize`, `tint`, spin, `motion`, `onModelPress`, `measureAlignment`), with the camera API, regions, conversions, gestures and map events.
- **Android 3D layer at parity with iOS**, on every engine (it reads only `MapCameraState`): built-in shapes, pictures (avatars with rings and badges), labels, stems, `lift`, ground shadows, embedded glTF animations, effects (`exhaust`, `smoke`, `contrail`), `occluder` models, zones, 3D paths, `occlusion="buildings"` (vector tiles), the Earth hiding the globe's far side, `altitudeReference: 'sea'` and `followTerrain` (Terrarium terrain tiles), and `flyCamera` / `stopFlight` stepped on the layer's frame clock for any engine that can set its camera.
- `groundElevation()` on Android.
- Android: `hasLookAround` / `openLookAround` go to the engine (Google's Street View); `MapModelLayer` can draw over react-native-maps' Google `MapView` when the Google engine is built in.

**Google Maps**

- **Google Maps engine** (`provider="google"`) on iOS (Maps SDK for iOS 10 + Google Maps Utils 7, `NitroMunimMaps/Google`) and Android (Maps SDK 20 + android-maps-utils 3.20, `munimMaps.google=true`): map types, cloud styling (`google.mapId`) and JSON styles, dark mode, buildings, traffic, transit, indoor maps with level events and `setIndoorLevel`, lite mode (Android), every gesture and UI control (compass, my-location button, zoom controls and map toolbar on Android), padding, zoom limits and camera target bounds; markers of every style with info windows, dragging, flat / rotated markers, advanced markers with pins and collision behaviour, `MarkerView`, clustering with `clusterStyles`; polylines with gradients, spans, patterns, caps, joints and texture / sprite stamps, polygons with holes, circles, overlay taps, tile overlays (`{x}{y}{z}`, `{-y}`, `{quadkey}`, `file://`), ground overlays, heatmaps, KML and GeoJSON layers, data-driven styling of boundaries and datasets; Street View (`openLookAround`, `hasLookAround`, `googleMap(ref).streetView`); snapshots, reverse geocoding, POI taps, camera-move reasons; and the 3D layer on Google's camera, with Google's field of view measured from its projection.
- Google photorealistic 3D mode on Android (`google={{ mode: '3d' }}`, Maps 3D SDK `play-services-maps3d` 0.2.0 behind `munimMaps.googleMaps3d=true` / the Expo plugin's `googleMaps3d`): models as native Google glTF models (`modelRendering: 'auto' | 'native' | 'overlay'`), native polylines, polygons and markers, `flyTo` / `flyAround`. Needs the Map Tiles API and the Maps 3D SDK for Android on the key.
- `googleMapsServices({ apiKey })`: Places API (New) autocomplete, details, text and nearby search and photos, the Geocoding API and the Routes API (routes with decoded lines, route matrices), for keys with those APIs on; `googleGeometry` and `encodePolyline` / `decodePolyline` in JavaScript.

**Mapbox**

- **Mapbox engine** (`provider="mapbox"`, Mapbox Maps SDK 11.32 on iOS and Android): Mapbox Standard and Standard Satellite with light presets, themes and the rest of their config, globe, terrain, atmosphere, lights, snow and rain, style imports and colour themes; every style-spec source and layer type, images and glTF models from the declarative `mapbox={{ … }}` options (`MapboxMapOptions`); markers as point annotations with clustering and dragging, shapes and tile overlays as layers in Standard's slots, `MarkerView`s as view annotations; the location puck (2D / 3D, heading, pulsing), follow and follow-with-heading through Mapbox's viewport; featureset taps; Mapbox map events; munim-maps' 3D layer aligned to Mapbox's camera. `mapboxMap(ref)` methods (queries, feature state, clusters, runtime styling, Mapbox's camera, free camera, viewport, `Snapshotter`, elevation, location override, tile cover, statistics), `MapboxOffline` (style packs, tile regions) and `MapboxServices` (Geocoding, Search Box, Directions, Matrix, Isochrone). See the checklist in docs/providers.md.
- Mapbox draws glTF / GLB `models` natively in its model layer (`mapbox={{ modelRendering: 'auto' | 'native' | 'overlay' }}`, `auto` by default): lit, shadowed and hidden by Mapbox's buildings and terrain, with motion, spin, `screenSize` and `tint`; avatars, labels, stems, effects, zones and paths stay on munim-maps' 3D layer.

**MapLibre (open maps)**

- **MapLibre engine** (`provider="maplibre"`, open maps: OpenStreetMap data from OpenFreeMap, no key) on iOS (`NitroMunimMaps/MapLibre`, MapLibre Native 6.30+) and Android (built in, MapLibre Native 13.6): the shared API (camera, flights, regions, conversions, gestures, limits, padding, markers of every style with callouts, dragging and clustering, polylines with gradients and dashes, polygons, circles, tile overlays, overlay taps, tappable base-map places, user location and tracking, compass, scale bar, tracking button, snapshots, `addressForCoordinate`) and the munim 3D layer on MapLibre's camera.
- `maplibre={{ … }}` (`MapLibreMapOptions`): style presets (OpenFreeMap Liberty, Bright, Positron, Dark, Fiord; MapLibre demo tiles; MapTiler and Stadia with `apiKey`), `styleJson`, dark style, satellite tiles for `mapStyle` imagery/hybrid, style-spec `sources` (vector, raster, raster-dem, GeoJSON with clustering, image, PMTiles, MLT) and `layers` (all ten layer types, expressions, filters), `images`, `light`, `transition`, `hillshade` and `colorRelief` from keyless AWS Terrain Tiles, `labelLanguage`, ornaments, gesture tuning, zoom/pitch limits and roll, rendering options (fps, prefetch, tile cache and LOD, frustum offset, debug overlays), location puck options, HTTP headers, log level.
- `maplibreCommands(ref)`: typed MapLibre commands: rendered and source feature queries, cluster leaves / children / expansion zoom, runtime styling (add / remove / move sources and layers, paint and layout properties, filters, zoom ranges, images, light), feature state, `flyTo`, `resetNorth`, an offscreen snapshotter, offline packs (create, list, resume, suspend, delete, invalidate, progress events, ambient cache, database merge) and connectivity. Events: `styleLoaded`, `mapLoadFailed`, `cameraMoveStarted`, `idle`, `renderedMap`, `sourceChanged`, `styleImageMissing`, `renderError`, `offlineProgress`, `offlineError`.
- `openMapsServices` and `configureOpenMapsServices`: Nominatim geocoding, Photon search and OSRM / Valhalla routing with configurable endpoints (the public servers are for light use only), and `decodePolyline`.

**Cesium**

- **Cesium engine** (`provider="cesium"`, iOS and Android): CesiumJS 1.146.0 (Apache-2.0), loaded from jsDelivr at that version and kept on the device (or bundled in the app from its own `cesium` package with `cesium: { bundled: true }`; 13 MB, minified build only) and run in a WebView the engine owns (`WKWebView` with a `munim-cesium://` scheme handler, `android.webkit.WebView` serving `https://appassets.androidplatform.net/`), no `react-native-webview`. OpenStreetMap imagery and an ellipsoid without a key; `cesiumIonToken` adds Cesium World Terrain, Bing imagery, OSM Buildings and ion assets. The shared API works on it: camera (set, animate, fly through keyframes, regions, fit, conversions, limits, boundary, padding, gestures), events, markers (pin, balloon, image, avatar, label, dot, badges, callouts with accessories, dragging, clustering, `MarkerView` on iOS), polylines (dashes, gradients, trimming), polygons with holes, circles, tile overlays, user location and tracking, compass / scale / tracking / 2D-3D controls, snapshots, reverse geocoding, and the 3D layer: GLB / glTF models (the vehicle catalogue) drawn by Cesium with heading, altitude, `screenSize`, `tint`, spin, animations, `motion`, labels, stems, `lift`, ground shadows, effects (exhaust, smoke, contrail), zones and paths, hidden by terrain and 3D Tiles; other files (USDZ on iOS) on the native layer over Cesium's camera (`measureAlignment`); `cesium.modelRendering`: `auto` / `native` (Cesium entities and primitives) or `overlay` (munim-maps' native 3D layer over the WebView). `cesium={{ … }}` (`CesiumMapOptions`) reaches the rest of CesiumJS: scene modes, every imagery and terrain provider, 3D Tiles (OSM Buildings, Google Photorealistic, I3S, voxels, vector tiles, iTwin), CZML entities, CZML / GeoJSON / KML / GPX data sources, the clock, lighting, atmosphere, shadows, fog, clouds, post-processing and Viewer widgets.
- `cesiumCommands(ref)`: Cesium's own methods (flights, `lookAt`, orbit, picking, `pickPosition`, measuring, terrain heights, screenshots, entities, data sources, tilesets and styles, imagery layers, terrain, clock, particle systems, panoramas, model animations and styles, `evaluate`), and `onProviderEvent` with `parseCesiumEvent` (`pick`, `tilesetLoaded`, `dataSourceLoaded`, `morphComplete`…).

**Example**

- One engine picker (`munimmapsexample://providers[/<provider>]`, the start screen on Android) shows the same models on each engine with the 3D layer's measured alignment and opens every other screen: each engine's own screen, the 3D layer on the picked engine, and on iOS the MapKit, react-native-maps and expo-maps examples. Development keys are read at build time from `example/.env.local` or `~/.config/munim-maps/keys.env`.
- Each engine's screen with every feature group and on-device checks behind a button or a deep link: `munimmapsexample://google[/checks]`, `mapbox[/checks]`, `maplibre[/check]`, `cesium[/checks]`, `layer3d[/<provider>][/check]`. Checks never run on their own, except the MapKit self-test on a plain iOS launch.
- Models come from munim-maps-vehicles (`EXPO_PUBLIC_MUNIM_MAPS_VEHICLES_BASE_URL` points it at a local server before publishing); the engine picker's balloon is a bundled model.

### Changed

- The MapKit map and its features moved to `ios/Engines/MapKit/` behind `MunimMapEngine`; the 3D renderer now reads only the camera state, not `MKMapView`. Behaviour is unchanged (the on-device self-test still passes 47 of 47).
- `decodePolyline` is one implementation (Google's services and the OpenStreetMap services share it).
- Cesium draws at most 2 device pixels per CSS pixel (it drew 2 x the device resolution: 5.25 pixels per CSS pixel on a 420 dpi phone, 4 x the pixels on an iPad).

### Fixed

Found running every engine's checks on Android:

- Google: apps no longer stop when a Google map is created on devices with older Google Play services (`org.apache.http.legacy`, not required, in the library manifest); `hasLookAround` / `streetView.hasCoverage` work (the probe panorama was never started).
- Mapbox: clustered markers, `MarkerView` (added twice before its first layout; plain layout params in Mapbox's FrameLayout) and callouts no longer crash; `setViewport({ state: 'overview' })` no longer throws `IllegalAccessError`; `getNativeModels` exists on Android; overlay taps ignore off-screen projections; a location override set before following starts moves the follow camera.
- MapLibre: `getFeatureState`, `setFeatureState`, `removeFeatureState` and the offscreen `snapshot` command answer JSON.

Found running Google's photorealistic 3D map on a phone (Maps 3D SDK 0.2.0):

- Google 3D (Android): the initial camera, models, markers, polylines and polygons were given to the SDK before its map was ready and were lost (the map stayed on the whole Earth, with no models); they are applied once the map is ready, including an `initialCamera` that arrives after `google.mode: '3d'`. `getCamera`, `getCamera3d` and relative `flyTo` / `setCamera3d` read the camera set in code (the SDK reports only gestures), camera changes made in code reach `onCameraChange`, and `map3dReady` fires once instead of on every loading-progress update.
- Cesium: without terrain, the camera centre and distance (`getCamera`, `getVisibleRegion`, `pointForCoordinate`, `cameraChange`) are measured on the ellipsoid, not on the globe's loading tiles, which sag up to tens of kilometres below it until finer tiles arrive (on a slow phone, `getCamera` read 3 to 30 km for a 1.1 km camera for several seconds after the map was ready).

## [0.4.0] - 2026-10-06

### Added

- Terrain height. MapKit does not expose it, so munim-maps reads the free public Terrarium elevation tiles on AWS (zoom 14, bilinear, cached in memory and on disk, one request per tile at a time):
  - `altitudeReference: 'sea'` on models and paths: `altitude` is metres above sea level, such as a phone's GPS altitude, and the ground height there is taken off natively. The model shows once its tile has loaded; moving models load the tiles along their keyframes ahead of time.
  - `followTerrain` on `MapModelLayer` and `MunimMapView` (`followsTerrain` in Swift): on satellite imagery with realistic elevation, where MapKit draws real 3D terrain, models, paths and zones stay on the mountains instead of at the height of the ground at the map's centre. Models above sea level always follow the terrain.
  - `groundElevation(coordinates)`: the height of the ground above sea level, from JavaScript, and `MunimTerrain.shared.groundElevations(for:)` in Swift.
- `MapModelLayer` is tested over expo-maps' `AppleMaps.View` (SwiftUI `Map`) on device: it finds the `MKMapView` inside, and the self-test measures it within 1.6 points at three zoom levels.
- Example: Yosemite in 3D with heights above sea level (`munimmapsexample://terrain`), models over expo-maps (`munimmapsexample://expomaps`), and terrain and expo-maps checks in the self-test.
- MapKit parity on `MunimMapView`:
  - `userTrackingMode="followWithHeading"` is handed to MapKit, which owns the following (heading beam included, nothing recentres from JavaScript); `onUserTrackingModeChange` reports when MapKit drops it after a pan or zoom, or the tracking button changes it. Camera moves from code end tracking the same way. Location access is requested when needed. The old `'follow-with-heading'` spelling still works.
  - Controls: `compassVisibility` and `scaleVisibility` (`adaptive`, `visible`, `hidden`), `showsUserTrackingButton`, `pitchButtonVisibility` (iOS 17+), and standalone `MapCompass`, `MapScale` and `MapUserTrackingButton` that drive the map with the same `mapScope`.
  - `selectionAccessory`: Apple's place card for tapped places (`MKSelectionAccessory`, iOS 18+), and `mapItemForFeature(id)` for the full place behind `onMapFeaturePress`.
  - Markers: `displayPriority`, `collisionMode`, `titleVisibility` / `subtitleVisibility`, SF Symbol glyphs (`glyphSymbol`, `selectedGlyphSymbol`), `glyphColor`, `animatesWhenAdded`, callout buttons and pictures (`calloutLeft`, `calloutRight`, `onCalloutAccessoryPress`) and `calloutDetail`.
  - `clusterStyles` (balloon colour, `{count}` glyph and title) and `onClusterPress` with the member ids.
  - `<MarkerView>`: React Native views as markers, drawn into a real MapKit marker (`tracksViewChanges` for live content).
  - Overlays: gradient polylines (`strokeColors`, `strokeColorLocations`), `lineJoin`, `strokeStart` / `strokeEnd` (updated in place, to animate a route), `level` (`aboveRoads`, `aboveLabels`) on every overlay, and `onOverlayPress` with `tappable` hit-testing for polylines, polygons and circles (`overlayAtPoint(point)` on the ref).
  - `pointsOfInterest` accepts short category names such as `'cafe'`.
- `<LookAroundView>`: Apple's Look Around embedded in your layout (`coordinate` or `mapItemId`, `showsRoadLabels`, `pointsOfInterest`, `navigationEnabled`, `badgePosition`, `onSceneChange`, `onFullScreenChange`).
- MapKit services, no map needed: `searchPlaces`, `createSearchCompleter` (autocomplete, resolved to places), `pointsOfInterest`, `directions` and `eta` (transport types, alternates, dates, avoiding tolls and highways, steps), `geocode` and `reverseGeocode` (iOS 26 `MKGeocodingRequest` / `MKReverseGeocodingRequest`, `CLGeocoder` before), `mapItem(id)`, `openInMaps`, `mapSnapshot`, `hasLookAround`, `lookAroundSnapshot`, `formatDistance`, and `routePolyline` to draw a route.
- Example: a MapKit screen with all of it (`munimmapsexample://parity`, `/follow`, `/callout`) and 16 more self-test checks (services, overlay hit-testing, `MarkerView`, user tracking).

### Fixed

- The self-test's render check looked at one pixel in the middle of each model, which fell between the beams of the lattice Starbase tower at "close, pitched 70, heading 315" (on both `MunimMapView` and react-native-maps). It now looks for the model's pixels anywhere in its projected bounding box; alignment there was always within 1.7 points.
- Updating markers no longer re-configures unchanged ones, which closed an open callout.

### Changed

- The vehicle catalogue is rebuilt to the jets' level of detail. Bodies are skinned through measured cross-sections, wings and tails are airfoil sections, and windows, seams, lights, stripes and markings are laid onto the skin, so they follow its curves instead of sitting on it as flat boxes:
  - Cars: beltline creases, flush glass split by the pillars, door seams and handles, lamps, grilles and bumpers on the body, arch-cut wheel openings and dished alloy wheels; the convertible has an open cabin.
  - Vans, trucks and buses: fitted windscreens and windows, sliding and swing doors, arch flares, DOT tape and roll-up doors; a long-hood semi tractor with a chrome grille and air cleaners, a crew-cab pumper, a 40 ft city bus and a conventional school bus.
  - Motorcycles: twin-spar, cradle and perimeter frames, swingarms, forks through triple clamps, round-profile tyres on cast or laced wheels with discs, an inline-four, a finned V-twin and a single, exhausts and lofted bodywork; a step-through scooter.
  - Boats: deep-V hulls with chines; a bowrider with an outboard, a 33 ft sloop, a 35 m superyacht and a personal watercraft.
  - Aircraft: airliners with winglets, nacelles, window rows and gear (`plane-widebody` is now its own twin-aisle, not a scaled narrow-body), a business jet with a T-tail, a Cessna 172-style high wing and a Bell 407-style helicopter.
  - Rail: a two-section tram and a high-speed train with a sculpted nose, bogies and pantographs.
  - Rockets: the Space Shuttle orbiter (double delta, tiles, OMS pods, main engines) now faces the front of the stack; Falcon 9 and Saturn V gain engines, legs, grid fins, fins and paint patterns.
- Vehicle models share vertices across their markings and drop body sections that add no shape, so the jets are about 40% lighter; the whole catalogue is 15 MB.

## [0.3.0] - 2026-10-06

### Added

- `MunimMapView` is now a full MapKit map, so apps no longer need react-native-maps on iOS: markers (pins, balloons with glyphs, images, round avatars with ring and corner badges, label pills, dots) with clustering, dragging, callouts and z-order; polylines (dashed, geodesic), polygons with holes, circles and tile overlays; point-of-interest filters, traffic, compass, scale, user location and tracking modes, gesture switches, camera distance limits and boundaries, map padding and tappable map features.
- `MunimMapView` events and methods: `onMapReady`, `onPress`, `onLongPress`, `onCameraMove`, `onCameraChange`, marker and callout events, `onUserLocationChange`, `onMapFeaturePress`; `setCamera`, `animateCamera`, `getCamera`, `setRegion`, `getVisibleRegion`, `fitToCoordinates`, `fitToMarkers`, `pointForCoordinate`, `coordinateForPoint`, `selectMarker`, `deselectMarker`, `takeSnapshot`, `addressForCoordinate`, `hasLookAround`, `openLookAround`.
- `globe`: the standard map becomes a globe when zoomed far out, like Apple Maps. It uses a MapKit switch that is not public API; see the README.
- Models, labels, stems and zones are placed on the sphere whenever MapKit draws a globe (the standard map with `globe`, or `hybrid` / `imagery` with realistic elevation), and hidden when they go round the far side.
- `paths`: lines drawn in 3D, a fixed number of points wide, at any height and on the globe (orbits, flight paths). They also work over react-native-maps.
- `occlusion="buildings"`: models are hidden behind buildings, using OpenStreetMap footprints and heights from vector tiles around the camera (OpenFreeMap by default, or `buildingTilesUrl`). Avatars, labels and stems stay visible.
- glTF 2.0 models (`.glb`, `.gltf`): PBR materials and textures, skins and the first animation, from bundles, URLs (with their buffers and images) or files. PLY, STL and Alembic files load through Model I/O alongside OBJ.
- `effect`: particle effects, `exhaust` (a methane engine plume with shock diamonds, sized to the model and stopping at the ground), `smoke` (a launch-pad cloud) and `contrail` (trails left in the sky), with `effectIntensity` to throttle them.
- `occluder`: a model that draws nothing but hides other models behind it, for stand-ins such as a bridge's railings and towers.
- `effectOrigins`: where an effect starts on a model, such as one contrail per engine.
- `motion` on models and `flyCamera` on `MunimMapView`: keyframes interpolated natively every frame on one shared clock, so moving models and camera moves stay smooth and locked to the map whatever JavaScript is doing. `animateCamera` now steps the camera the same way instead of a UIKit animation, during which MapKit reported the destination camera and models slid.
- The four fighter jets are rebuilt from measured three-view drawings, with intakes, control surfaces, nozzles, canopies, camouflage and markings.
- Seven spacecraft in the vehicle catalogue: the ISS, a Starlink satellite, Hubble, a GPS III satellite, a 3U CubeSat, Crew Dragon and the James Webb Space Telescope.
- Starbase: `starbase-tower` (the launch tower with its chopsticks and quick-disconnect arm) and `starbase-mount` (the orbital launch mount), and a rebuilt `rocket-starship` with grid fins, chines, the hot-staging ring, 33 Raptors and the ship's heat shield and flaps (57 models).
- `realisticElevation` on `MapModelLayer`: keeps a map library's flat style on realistic elevation.
- Swift Package Manager: the `MunimMaps` and `MunimMapsVehicles` products bring `MunimMapKitView`, the SwiftUI `MunimMap` and `MunimModelLayer` to native apps without React Native.
- Example: satellites orbiting the globe (`munimmapsexample://orbit`), cities on the globe, scripted demo shots (`munimmapsexample://demo/<shot>`, with traffic on real Chicago streets from OpenStreetMap and a GLB sample), and globe checks in the self-test.

### Fixed

- Badges longer than the picture (`Floor 103`) were cut off; the badge now widens to fit.
- Geodesic polylines crashed: `MKGeodesicPolyline`'s initialiser never returns a subclass, so the overlay's own properties were written past the end of the object.

## [0.2.0] - 2026-10-05

### Added

- Vehicle catalogue in `munim-maps/vehicles`: 48 detailed models (13 cars including EV, off-roader, supercar, pickup, taxi and police; vans, trucks, fire engine and buses; bikes, scooters and motorcycles; tram and high-speed train; boats; airliners, business jet, prop plane, F-16, F-22, F-35, YF-23, helicopter, hot air balloon; Starship, Falcon 9, Saturn V and the Space Shuttle), generated by `scripts/vehicles/make-vehicles.swift`.
- `tint`: recolours a model's paint (materials named `paint…`) at runtime.
- Avatar models: `image` draws a round picture that always faces the camera, with `imageBorder` and a `badge` pill (such as `5F`), sized in points by `screenSize`.
- `stem`: a line from the ground up to a floating model, with a dot on the ground, for people on upper floors.
- `lift`: raises a model by a number of points at any zoom, to float an avatar over a vehicle.
- `label`: a text pill floating above any model.
- `gem` shape, for power-ups.
- `zones`: circles or polygons drawn as see-through walls with solid top and bottom edges.
- Example: friends on Chicago skyscrapers, the vehicle catalogue with tints, power-ups and zones, an Orbit toggle, and a lag test (`munimmapsexample://lagtest`).

### Fixed

- Models trailed the map by a frame or more while it moved, and stayed slightly off once it stopped. SceneKit's transaction is now flushed before each frame, and frames are presented straight from the GPU. Mid-animation the models now stay within 0.2 px of MapKit's own overlays.
- Screen-size models no longer redraw every frame while the map is still.
- Badge pills stay readable on light rings.

## [0.1.0] - 2026-10-05

### Added

- `MapModelLayer`: draws 3D models over an existing MapKit map, such as `react-native-maps`' `MapView` on iOS, found by `testID` or as the nearest map on screen.
- `MunimMapView`: a MapKit map with models built in, with `standard`, `muted`, `hybrid` and `imagery` styles, flat or realistic elevation, and `setCamera` / `getCamera`.
- Models from USDZ, USD, SCN or OBJ files (bundled, `file://` or cached `http(s)://`) or built-in shapes, with altitude, heading, scale, spin, embedded animations, screen-constant sizing, ground shadows and day/night lighting.
- Camera matching that measures MapKit's focal length from the map itself, and same-frame rendering through a pre-commit run-loop observer.
- `onModelPress` taps and `measureAlignment()` for checking the drawing against MapKit.
