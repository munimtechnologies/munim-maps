# Changelog

All notable changes to this project are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

munim-maps is becoming one API over five map engines (MapKit, Google Maps, Mapbox, MapLibre and Cesium) on iOS and Android. This is the foundation; the engines other than MapKit (iOS) and MapLibre (Android) are coming in this release. See [docs/providers.md](docs/providers.md).

### Added

- `provider` on `MunimMapView`: `'mapkit'` (default on iOS), `'google'`, `'mapbox'`, `'maplibre'` (default on Android without Google) or `'cesium'`, with `styleUrl` and per-engine options in `google`, `mapbox`, `maplibre`, `cesium` and `mapkit` props. Engines that are not built in show a placeholder and report `onError`.
- `configureMunimMaps({ googleMapsApiKey, mapboxAccessToken, cesiumIonToken, maplibreStyleUrl, mapboxStyleUrl, defaultProvider })`, `availableProviders()`, `installedProviders()`, `isProviderAvailable()` and `MAP_PROVIDERS`.
- Expo config plugin (`"plugins": [["munim-maps", { "providers": [...], ...keys }]]`): turns engines on (CocoaPods subspecs through `Podfile.properties.json`, Gradle properties) and writes their keys into Info.plist, the manifest and strings.xml.
- Opt-in engines: `NitroMunimMaps/Google`, `/Mapbox`, `/MapLibre` and `/Cesium` subspecs on iOS (the default install is still MapKit only), `munimMaps.google`, `mapbox`, `maplibre` and `cesium` Gradle properties on Android.
- **Android**: `MunimMapView` and `MapModelLayer` are Kotlin Nitro views. `MunimMapView` draws MapLibre Native with OpenFreeMap (no key) and GLB / glTF models through a Filament 3D layer driven by the same camera model as iOS (position, altitude, heading, scale, `screenSize`, `tint`, spin, `motion`, `onModelPress`, `measureAlignment`), with the camera API, regions, conversions, gestures and map events.
- **Android 3D layer at parity with iOS**, on every engine (it reads only `MapCameraState`): built-in shapes, pictures (avatars with rings and badges), labels, stems, `lift`, ground shadows, embedded glTF animations, effects (`exhaust`, `smoke`, `contrail`), `occluder` models, zones, 3D paths, `occlusion="buildings"` (vector tiles), the Earth hiding the globe's far side, `altitudeReference: 'sea'` and `followTerrain` (Terrarium terrain tiles), and `flyCamera` / `stopFlight` stepped on the layer's frame clock for any engine that can set its camera.
- `groundElevation()` on Android.
- Example: `munimmapsexample://layer3d[/<provider>][/check]`, every 3D layer group on one engine, with alignment checks at several cameras and mid-flight.
- The vehicle catalogue as GLB (`packages/munim-maps/vehicles/glb`, 20 MB): `munim-maps/vehicles` gives USDZ on iOS and GLB on Android, and `munim-maps/vehicles-glb` gives GLB everywhere. `make-vehicles.swift` writes both.
- Swift: the `MunimMapEngine` protocol, `MunimMapContainerView`, `MunimMapEngines`, `MunimMapsConfiguration`, and `MapCameraSource` / `MapCameraState`, so `MunimModelLayer.attach(to:)` can draw over any engine's map.
- Example: an engine picker (`munimmapsexample://providers/<provider>`, the start screen on Android) showing the same models on each engine with the 3D layer's measured alignment; development keys are read at build time from `example/.env.local` or `~/.config/munim-maps/keys.env`.

### Changed

- The MapKit map and its features moved to `ios/Engines/MapKit/` behind `MunimMapEngine`; the 3D renderer now reads only the camera state, not `MKMapView`. Behaviour is unchanged (the on-device self-test still passes 47 of 47).

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
