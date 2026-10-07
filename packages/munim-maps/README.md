<!-- Banner Image -->

<p align="center">
  <a href="https://github.com/munimtechnologies/munim-maps">
    <img alt="Munim Technologies Maps" height="128" src="https://raw.githubusercontent.com/munimtechnologies/munim-maps/main/.github/resources/banner.png">
    <h1 align="center">munim-maps</h1>
  </a>
</p>

<p align="center">
   <a aria-label="Package version" href="https://www.npmjs.com/package/munim-maps" target="_blank">
    <img alt="Package version" src="https://img.shields.io/npm/v/munim-maps.svg?style=flat-square&label=Version&labelColor=000000&color=0066CC" />
  </a>
  <a aria-label="Package is free to use" href="https://github.com/munimtechnologies/munim-maps/blob/main/LICENSE" target="_blank">
    <img alt="License: Apache-2.0" src="https://img.shields.io/badge/License-Apache%202.0-success.svg?style=flat-square&color=33CC12" target="_blank" />
  </a>
  <a aria-label="package downloads" href="https://www.npmtrends.com/munim-maps" target="_blank">
    <img alt="Downloads" src="https://img.shields.io/npm/dm/munim-maps.svg?style=flat-square&labelColor=gray&color=33CC12&label=Downloads" />
  </a>
  <a aria-label="total package downloads" href="https://www.npmjs.com/package/munim-maps" target="_blank">
    <img alt="Total Downloads" src="https://img.shields.io/npm/dt/munim-maps.svg?style=flat-square&labelColor=gray&color=0066CC&label=Total%20Downloads" />
  </a>
</p>

<p align="center">
  <a aria-label="try with expo" href="https://docs.expo.dev/"><b>Works with Expo</b></a>
&ensp;•&ensp;
  <a aria-label="documentation" href="https://github.com/munimtechnologies/munim-maps#readme">Read the Documentation</a>
&ensp;•&ensp;
  <a aria-label="report issues" href="https://github.com/munimtechnologies/munim-maps/issues">Report Issues</a>
</p>

<h6 align="center">Follow Munim Technologies</h6>
<p align="center">
  <a aria-label="Follow Munim Technologies on GitHub" href="https://github.com/munimtechnologies" target="_blank">
    <img alt="Munim Technologies on GitHub" src="https://img.shields.io/badge/GitHub-222222?style=for-the-badge&logo=github&logoColor=white" target="_blank" />
  </a>&nbsp;
  <a aria-label="Follow Munim Technologies on LinkedIn" href="https://linkedin.com/in/sheehanmunim" target="_blank">
    <img alt="Munim Technologies on LinkedIn" src="https://img.shields.io/badge/LinkedIn-0077B5?style=for-the-badge&logo=linkedin&logoColor=white" target="_blank" />
  </a>&nbsp;
  <a aria-label="Visit Munim Technologies Website" href="https://munimtech.com" target="_blank">
    <img alt="Munim Technologies Website" src="https://img.shields.io/badge/Website-0066CC?style=for-the-badge&logo=globe&logoColor=white" target="_blank" />
  </a>
</p>

<p align="center">
  <img alt="A Starship launch, city traffic, friends on their floor and satellites on the globe, drawn by munim-maps on Apple Maps" src="https://raw.githubusercontent.com/munimtechnologies/munim-maps/main/.github/resources/hero.jpg" width="100%">
</p>


<table align="center">
  <tr>
    <td align="center"><img alt="Starship ignition and liftoff" src="https://raw.githubusercontent.com/munimtechnologies/munim-maps/main/.github/resources/clip-launch.gif" width="180"><br><sub>Starship launch</sub></td>
    <td align="center"><img alt="Cars, buses and bikes moving through Chicago" src="https://raw.githubusercontent.com/munimtechnologies/munim-maps/main/.github/resources/clip-traffic.gif" width="180"><br><sub>Traffic</sub></td>
    <td align="center"><img alt="Fighter jets, airliners with contrails, boats and bridge traffic at the Golden Gate" src="https://raw.githubusercontent.com/munimtechnologies/munim-maps/main/.github/resources/clip-jets.gif" width="180"><br><sub>Jets over the Golden Gate</sub></td>
    <td align="center"><img alt="Satellites orbiting the globe on the standard map" src="https://raw.githubusercontent.com/munimtechnologies/munim-maps/main/.github/resources/clip-orbit.gif" width="180"><br><sub>Satellites on the globe</sub></td>
    <td align="center"><img alt="Friends floating at their floor on Chicago skyscrapers" src="https://raw.githubusercontent.com/munimtechnologies/munim-maps/main/.github/resources/clip-friends.gif" width="180"><br><sub>Friends on their floor</sub></td>
  </tr>
</table>

<p align="center"><sub>Recorded on an iPhone 17 Pro. Open any shot in the example app with <code>munimmapsexample://demo/launch</code>, <code>traffic</code>, <code>friends</code>, <code>orbit</code> or <code>jets</code>.</sub></p>

## Introduction

**munim-maps** puts animated 3D models on Apple Maps in React Native: vehicles, people on the floor of a building they are really on, power-ups, zone walls and your own USDZ files, anchored to real coordinates and moving in the same frame as the map.

Use it with the map you already have, or its own: **`MunimMapView`** is a MapKit map with models built in, and **`MapModelLayer`** draws over any MapKit map on screen, such as `react-native-maps` on iOS. See [Use Your Own Map](#️-use-your-own-map).

**Fully compatible with Expo!** Works with Expo managed (prebuild) and bare workflows.

**Built with React Native's Nitro modules architecture** for high performance and reliability.

**Comes with a catalogue of 57 detailed models**: cars, trucks, buses, bikes, motorcycles, trains, boats, airliners, fighter jets (F-16, F-22, F-35, YF-23), a helicopter, a hot air balloon, rockets (Starship, Falcon 9, Saturn V, Space Shuttle), Starbase's launch tower and mount, and spacecraft (ISS, Starlink, Hubble, GPS, CubeSat, Crew Dragon, James Webb), all recolourable at runtime.

**Or bring your own**: any USDZ, USD, glTF / GLB, SceneKit, OBJ, PLY, STL or Alembic file, bundled, downloaded or from disk. See [Bring Your Own Model](#-bring-your-own-model).

**Hidden behind buildings**: with `occlusion="buildings"`, a car driving behind a tower disappears behind it, the way it would in real life.

**Terrain height**: give a friend's GPS altitude with `altitudeReference: 'sea'` and munim-maps takes off the ground height there, and `followTerrain` keeps models on MapKit's 3D satellite terrain. See [Terrain](#terrain).

**The globe on the standard map**: zoomed far out, the normal map becomes a globe like it does in Apple Maps, and models, satellites and 3D paths follow it.

**Not using React Native?** The same map and 3D layer are a Swift package for UIKit and SwiftUI apps; see [Swift Package Manager](#swift-package-manager).

**Note**: iOS only for now. On Android both components render nothing; see [Platform Support Matrix](#platform-support-matrix).

## 📦 Installation

### Expo

```bash
npx expo install munim-maps react-native-nitro-modules
```

### React Native CLI

```bash
npm install munim-maps react-native-nitro-modules
```

munim-maps is native code, so it ships in a new app build, not an over-the-air update.

### Metro

To `require()` model files (including the vehicle catalogue), add their extensions to Metro:

```js
// metro.config.js
config.resolver.assetExts.push('usdz', 'glb', 'gltf', 'obj', 'scn')
```

### Swift Package Manager

For native iOS apps without React Native. In Xcode, **File → Add Package Dependencies…** and enter `https://github.com/munimtechnologies/munim-maps`, or in `Package.swift`:

```swift
.package(url: "https://github.com/munimtechnologies/munim-maps", from: "0.3.0")
```

Add the `MunimMaps` product, and `MunimMapsVehicles` for the vehicle catalogue (it bundles the USDZ files, so it is a separate product). iOS 16 or later.

```swift
import MunimMaps
import MunimMapsVehicles

// SwiftUI
MunimMap(
  initialCamera: MunimCamera(latitude: 41.8838, longitude: -87.6305, distance: 2600, pitch: 60),
  models: [
    MunimModel(id: "car", coordinate: .init(latitude: 41.8841, longitude: -87.6244),
               uri: MunimVehicles.url("car-ev")!.absoluteString, tintColor: "#E5484D", screenSize: 15),
  ],
  globe: true
)

// UIKit: a full map...
let map = MunimMapKitView(frame: view.bounds)
map.models = models
map.markers = [MunimMarker(id: "cafe", coordinate: cafe, title: "Cafe")]

// ...or 3D over an MKMapView you already have
let layer = MunimModelLayer()
layer.install(over: mapView)
layer.models = models
layer.onModelPress = { id in print(id) }
```

`MunimMapKitView` has the same props, events and methods as `MunimMapView` (`setCamera`, `fit(coordinates:)`, `point(for:)`, `snapshot`, `address(for:)`, `openLookAround(at:)`…). Ground heights are `try await MunimTerrain.shared.groundElevations(for: coordinates)`.

## Table of contents

- [📦 Installation](#-installation)
- [📚 Documentation](#-documentation)
- [🚀 Features](#-features)
- [🗺️ Use Your Own Map](#️-use-your-own-map)
- [🧊 Bring Your Own Model](#-bring-your-own-model)
- [🚗 Vehicle Catalogue](#-vehicle-catalogue)
- [Platform Support Matrix](#platform-support-matrix)
- [⚡ Quick Start](#-quick-start)
- [🔧 API Reference](#-api-reference)
- [📖 Usage Examples](#-usage-examples)
- [⚙️ How It Works](#️-how-it-works)
- [🔍 Troubleshooting](#-troubleshooting)
- [🛣️ Roadmap](#️-roadmap)
- [👏 Contributing](#-contributing)
- [📄 License](#-license)

## 📚 Documentation

<p>Learn about putting 3D on maps <a aria-label="documentation" href="https://github.com/munimtechnologies/munim-maps#readme">in our documentation!</a></p>

- [Getting Started](#-installation)
- [API Reference](#-api-reference)
- [Usage Examples](#-usage-examples)
- [Troubleshooting](#-troubleshooting)

## 🚀 Features

### Models on the map

- 🧊 **3D models at real coordinates**: USDZ, USD, glTF / GLB, SCN, OBJ, PLY, STL or Alembic files, bundled with `require()`, from `file://` or downloaded and cached from `http(s)://` ([details](#-bring-your-own-model))
- 🏙️ **Hidden behind buildings**: `occlusion="buildings"` hides models behind real building footprints and heights, which MapKit cannot do on its own
- 🔥 **Exhaust and smoke**: particle effects for rocket launches and fires, stopping at the ground
- 🔷 **Built-in shapes**: box, sphere, cylinder, cone, capsule, pyramid and gem, with colour and glow
- 🎨 **Runtime paint**: `tint` recolours a model's paint, so one file comes in any colour
- 🧭 **Heading, altitude and scale**, plus `spinDegreesPerSecond` and looping USDZ animations
- ⛰️ **Terrain height**: altitudes above the ground or above sea level (`altitudeReference: 'sea'`, such as a phone's GPS altitude), models that stay on MapKit's 3D terrain (`followTerrain`), and `groundElevation()` for the height of the ground anywhere, which MapKit does not expose ([details](#terrain))
- 📏 **Screen-size models**: `screenSize` keeps a model the same height on screen at any zoom, like a marker
- 🌑 **Ground shadows** and **day/night lighting** that follows the map's appearance

### People, vehicles and labels

- 🏢 **People in buildings**: round avatars that always face the camera float at their real height, with a stem down to the spot below and a floor badge such as `5F`
- 🚴 **Riders**: `lift` floats an avatar over a vehicle model at any zoom
- 🏷️ **Labels**: text pills that float above any model, for power-ups or names
- 👆 **Taps**: `onModelPress` with the model's id; the map keeps every gesture

### Globe, satellites and paths

- 🌍 **Globe on the standard map**: `globe` turns the normal map into a globe when zoomed far out, as Apple Maps does (MapKit only does this for satellite imagery). See the [note on how](#the-globe-uses-a-private-mapkit-switch)
- 🛰️ **Models on the globe**: when MapKit draws a globe (the standard map with `globe`, or `hybrid`/`imagery` with realistic elevation), models are placed on the sphere and hidden behind the Earth when they go round the far side
- 🪐 **Orbits and flight paths**: `paths` are lines drawn in 3D, a fixed number of points wide, that can sit at any height and follow the globe; MapKit's own polylines stay flat even on the globe

### Zones

- 🧱 **Zone walls**: circles or polygons stand up as see-through walls with solid top and bottom edges, like a map outline turned into a fence
- 🔄 **Live updates**: change a zone's radius or points and the wall rebuilds (shrinking zones)

### A full MapKit map

- 🗺️ **`MunimMapView`**: everything react-native-maps does on iOS, without a second library: markers, polylines, polygons, circles, tile overlays, every map event and the camera API
- 📍 **Markers**: MapKit pins and balloons (with emoji or text), images, round avatars with a ring and corner badges, label pills and dots; clustering, dragging, callouts, z-order
- ✏️ **Shapes**: polylines (dashed, geodesic), polygons with holes, circles, and tile overlays (your own tiles, over or instead of Apple's map)
- 🍎 **New MapKit**: `standard`, `muted`, `hybrid` and `imagery` styles, realistic elevation, point-of-interest filters, traffic, tappable map features (`onMapFeaturePress`), Look Around, camera distance limits and boundaries
- 🧭 **Camera and conversions**: `setCamera`, `setRegion`, `fitToCoordinates`, `fitToMarkers`, `pointForCoordinate`, `coordinateForPoint`, snapshots and reverse geocoding
- 🔦 **Follow with heading**: `userTrackingMode="followWithHeading"` is MapKit's own tracking with the heading beam; MapKit owns the following and `onUserTrackingModeChange` tells you when the user pans away ([details](#follow-the-user-with-heading))
- 🎛️ **Controls**: compass and scale that are always visible or adaptive, MapKit's tracking and 2D/3D buttons, and standalone `MapCompass`, `MapScale` and `MapUserTrackingButton` you can place anywhere
- 🪪 **Place cards**: tap a place on Apple's map and get Apple's own place card (`selectionAccessory`, iOS 18+)
- 🧷 **React Native views as markers**: `<MarkerView>` turns any React Native view into a real MapKit marker that clusters, collides and selects
- 🌈 **Routes and overlays**: gradient polylines, `strokeStart` / `strokeEnd` to animate a route being drawn, line joins, overlays under or over labels, and `onOverlayPress` for taps on lines and shapes
- 🔎 **MapKit services**: search and autocomplete, points of interest, directions and travel times, geocoding, places by id, Apple Maps hand-off and map images, without a map on screen ([details](#-mapkit-services))
- 👀 **Look Around**: `<LookAroundView>` embeds Apple's street-level imagery, and `lookAroundSnapshot()` makes a picture of it
- 🧩 **`MapModelLayer`**: or keep your map and draw the 3D over it, including `react-native-maps` and `expo-maps` on iOS

### Accuracy

- 🎯 **Matched to MapKit's own camera** to under a point, measured on device against `MKMapView.convert` (on the globe, checked against MapKit's city labels)
- ⏱️ **Same-frame motion**: models stay within 0.2 px of MapKit's own overlays while MapKit animates the camera
- ⚡ **High performance**: Nitro modules, Metal rendering, redraws only when the camera moves or something animates

## 🗺️ Use Your Own Map

munim-maps does not need its own map. Pick whichever fits your app; models, vehicles, avatars, labels and zones work the same on all of them.

| Map | How | Status |
| --- | --- | --- |
| **Apple MapKit, built in** | `<MunimMapView>` | ✅ Tested on device |
| **[react-native-maps](https://github.com/react-native-maps/react-native-maps)** (iOS, Apple Maps provider) | `<MapView testID="map">` then `<MapModelLayer mapTestID="map">` | ✅ Tested on device (self-test) |
| **[expo-maps](https://docs.expo.dev/versions/latest/sdk/maps/)** `AppleMaps.View` (iOS 17+) | Wrap it in `<View testID="map" collapsable={false}>`, then `<MapModelLayer mapTestID="map">` | ✅ Tested on device (self-test); see [Over expo-maps](#over-expo-maps) |
| **Any other React Native map built on MapKit** (`MKMapView`, including SwiftUI's `Map`) | `<MapModelLayer>` after it; give the map (or a view around it) a `testID`, or let the layer find the nearest MapKit map | Supported: the layer looks for the `MKMapView` inside the tagged view, so it works with any library that uses one |
| **UIKit or SwiftUI, no React Native** | `MunimMapKitView`, `MunimMap` or `MunimModelLayer` from the Swift package | ✅ Builds with Swift Package Manager |
| **Google Maps, Mapbox, MapLibre** | Not supported: they are not MapKit. On Android, Mapbox's `ModelLayer` draws glTF models natively. | ❌ |

### Over react-native-maps

```tsx
<View style={{ flex: 1 }}>
  <MapView style={StyleSheet.absoluteFill} testID="map" pitchEnabled />
  <MapModelLayer mapTestID="map" models={models} zones={zones} />
</View>
```

The layer sits on top of the map, never takes touches (the map keeps every gesture, and `onModelPress` still fires for taps on models), and draws with MapKit's own camera, so you keep all of react-native-maps' markers, polylines and callouts alongside the 3D.

### Over expo-maps

```tsx
import { AppleMaps } from 'expo-maps'

<View style={{ flex: 1 }}>
  <View testID="map" collapsable={false} style={StyleSheet.absoluteFill}>
    <AppleMaps.View style={StyleSheet.absoluteFill} cameraPosition={{ coordinates, zoom: 16 }} />
  </View>
  <MapModelLayer mapTestID="map" models={models} />
</View>
```

`AppleMaps.View` is SwiftUI's `Map`, which draws with an `MKMapView` inside, so the layer finds it and reads its camera the same way. Its props have no `testID`, so put the `testID` on a `View` around it (`collapsable={false}` keeps React Native from flattening that view away), or leave out `mapTestID` and the layer takes the nearest map. On an iPad Air, models stayed within 1.6 points of MapKit at zoom 15, 16 and 17. expo-maps' own camera API only sets a centre and a zoom level, so pitched and rotated views (with gestures) were checked by eye, not measured.

### On its own

```tsx
<MunimMapView style={{ flex: 1 }} initialCamera={camera} models={models} zones={zones} />
```

## 🧊 Bring Your Own Model

Any 3D file works as a model's `source`, not just the catalogue. Files are read in metres, and munim-maps puts the model's lowest point on the ground at its `coordinate`.

| Format | Extensions | Loaded with | Notes |
| --- | --- | --- | --- |
| **USDZ** | `.usdz` | SceneKit | Recommended. Materials, textures and embedded animations. Export from Reality Composer, Blender or Reality Converter. |
| **USD** | `.usd`, `.usda`, `.usdc` | SceneKit | |
| **glTF 2.0** | `.glb`, `.gltf` | munim-maps' own loader | PBR materials and textures, skins and the first animation. Prefer `.glb` (one file). Not supported: Draco or meshopt compression, KTX2 textures, morph targets. |
| **SceneKit** | `.scn` | SceneKit | |
| **OBJ** | `.obj` (+ `.mtl`) | Model I/O | The `.mtl` and textures must sit next to the `.obj`, so load it from a URL or a folder on disk; a bundled `.obj` comes without materials. |
| **PLY, STL, Alembic** | `.ply`, `.stl`, `.abc` | Model I/O | Meshes and vertex colours. |

```tsx
// Bundled with the app (add the extension to Metro's assetExts, see Installation)
{ id: 'fox', coordinate, source: require('./assets/Fox.glb'), screenSize: 60 }

// Downloaded once and cached
{ id: 'balloon', coordinate, source: 'https://example.com/models/balloon.usdz', altitude: 40 }
{ id: 'statue', coordinate, source: { uri: 'https://example.com/statue.gltf' } } // its .bin and textures are fetched too

// A file on the device, such as a download or a LiDAR scan
{ id: 'scan', coordinate, source: `file://${documentsPath}/room.usdz` }
```

```swift
// Swift
MunimModel(id: "fox", coordinate: c, uri: Bundle.main.url(forResource: "Fox", withExtension: "glb")!.absoluteString, screenSize: 60)
```

<p align="center">
  <img alt="A walking fox from a GLB file, a USDZ car and a downloaded USDZ balloon" src="https://raw.githubusercontent.com/munimtechnologies/munim-maps/main/.github/resources/clip-models.gif" width="240">
</p>

**How models are placed**

- **Size**: metres; `scale` multiplies it, or `screenSize` keeps the model a number of points tall at any zoom, like a marker.
- **Facing**: at `heading: 0` the model's front faces north. USD and SceneKit files face -Z; glTF files face +Z and are turned for you.
- **Colour**: `tint` recolours every material whose name starts with `paint`, so name the body material `paint` in your 3D tool to make a model recolourable.
- **Animation**: animations embedded in USDZ and glTF play on a loop; turn them off with `playAnimations: false`.
- **Tips**: apply transforms and set the origin before exporting, keep files to a few MB, and bake textures. Sketchfab and the [Khronos glTF samples](https://github.com/KhronosGroup/glTF-Sample-Assets) are good sources of GLB files; Apple's [Reality Converter](https://developer.apple.com/augmented-reality/tools/) turns glTF, OBJ and FBX into USDZ.

## 🚗 Vehicle Catalogue

Import the catalogue from `munim-maps/vehicles` (a separate entry point, so apps that never use it do not bundle it). Each model's paint can be recoloured with `tint`; models face north at heading 0, are sized in real metres and sit on the ground.

```tsx
import { VEHICLES } from 'munim-maps/vehicles'

{ id: 'ride', coordinate, source: VEHICLES['car-ev'], tint: '#E5484D', heading: 90, screenSize: 15 }
```

### Cars

<img alt="Cars" src="https://raw.githubusercontent.com/munimtechnologies/munim-maps/main/.github/resources/vehicles-cars.jpg" width="100%">

| Name | Vehicle | Modelled on |
| --- | --- | --- |
| `car-sedan` | Four-door sedan: beltline crease, glass, door seams and lamps on the body | Mid-size sedan proportions |
| `car-ev` | Electric fastback, closed nose with light bar | Model 3-style EV |
| `car-hatchback` | Five-door hatchback | Compact hatchback |
| `car-wagon` | Estate / station wagon | Mid-size wagon |
| `car-suv` | Mid-size SUV | Two-row SUV |
| `car-offroader` | Boxy off-roader with spare wheel and roof rack | Wrangler-style 4x4 |
| `car-sports` | Sports coupe with spoiler and twin exhausts | Front-engine coupe |
| `car-supercar` | Low wide supercar with wing | Mid-engine supercar |
| `car-convertible` | Roadster with an open cabin, shaped seats and a framed windscreen | Two-seat convertible |
| `car-pickup` | Full-size pickup with open bed | F-150-style pickup |
| `car-minivan` | Minivan | Three-row minivan |
| `car-taxi` | Taxi with roof sign and stripe | Yellow cab |
| `car-police` | Police car with light bar | Patrol sedan |

### Vans, trucks and buses

<img alt="Commercial vehicles" src="https://raw.githubusercontent.com/munimtechnologies/munim-maps/main/.github/resources/vehicles-commercial.jpg" width="100%">

| Name | Vehicle |
| --- | --- |
| `van-delivery` | High-roof delivery van: raked windscreen, sliding door, twin rear doors, wrap-round bumpers and arch flares |
| `van-ambulance` | Type II ambulance: roof light bar, corner flashers, red stripe and stars of life |
| `truck-box` | Cab-over box truck: 20 ft box with aluminium rails, roll-up door, DOT tape and dual rear wheels |
| `truck-semi` | Long-hood tractor (chrome grille, swept fenders, air cleaners, stacks, sleeper) with a 53 ft dry van, side skirts and swing doors |
| `truck-fire` | Custom-cab pumper: crew cab, white roof cap, roll-up compartments, pump panel, ladders, hose bed and chevrons |
| `bus-city` | 40 ft low-floor bus: wraparound windscreen, LED sign, glazed doors, flush window band and roof fairing |
| `bus-school` | Conventional school bus: split-sash windows, rub rails, warning lamps, stop and crossing arms, crossover mirrors |

### Bikes, scooters and motorcycles

<img alt="Two-wheelers" src="https://raw.githubusercontent.com/munimtechnologies/munim-maps/main/.github/resources/vehicles-two-wheelers.jpg" width="100%">

| Name | Vehicle |
| --- | --- |
| `bike-road` | Road bike with drop bars, wire-spoked wheels and drivetrain |
| `bike-mountain` | Mountain bike with suspension fork and wide tyres |
| `bike-city` | City bike with basket, rack and fenders |
| `scooter-kick` | Electric kick scooter |
| `scooter-moped` | Step-through scooter: leg shield, bulbous side cowls, round headlamp, two-tone seat and rack |
| `motorcycle-sport` | Superbike: twin-spar frame, gold fork, inline-four, full fairing and screen, split five-spoke wheels, twin discs |
| `motorcycle-cruiser` | Cruiser: finned 45-degree V-twin, chrome nacelle and headlamp, teardrop tank, deep fenders, shotgun pipes, laced wheels |
| `motorcycle-dirt` | MX bike: long-travel fork, knobbly tyres on laced wheels, shrouds, flat seat, number plates and a high pipe |

### Rail and water

<img alt="Rail and water" src="https://raw.githubusercontent.com/munimtechnologies/munim-maps/main/.github/resources/vehicles-rail-and-water.jpg" width="100%">

| Name | Vehicle |
| --- | --- |
| `rail-tram` | Two-section low-floor tram: raked cabs, flush glazing, glazed double doors, bellows, pantograph and bogies |
| `rail-highspeed` | High-speed train: sculpted power-car nose, trailer car, livery sweep, window band, pantograph and bogies |
| `boat-speed` | Bowrider: deep-V hull, open bow seating, walk-through windscreen, consoles, bow rails and an outboard |
| `boat-sail` | 33 ft sloop: coachroof with ports, teak decks, mainsail and jib, shrouds, lifelines and wheel |
| `boat-yacht` | 35 m superyacht: dark hull, three decks with swept window bands, hardtop, radar mast, rails and a tender |
| `boat-jetski` | Personal watercraft: deep-V hull with chines, footwells, stepped seat, steering pod and jet nozzle |

### Aircraft

<img alt="Aircraft" src="https://raw.githubusercontent.com/munimtechnologies/munim-maps/main/.github/resources/vehicles-aircraft.jpg" width="100%">

| Name | Aircraft | Modelled on |
| --- | --- | --- |
| `plane-airliner` | Narrow-body twinjet with winglets, window rows and landing gear | A320/737-class |
| `plane-widebody` | Wide-body twinjet with six-wheel bogies | 777/787-class |
| `plane-jet` | Business jet with big oval windows, rear engines and a T-tail | Long-range business jet |
| `plane-prop` | High-wing single: strut-braced wing, wheel fairings, windows and control surfaces | Cessna 172-style |
| `jet-f16` | Single-engine fighter with chin intake | F-16 |
| `jet-f22` | Stealth fighter, diamond wing, twin canted tails | F-22 |
| `jet-f35` | Stealth fighter, single engine | F-35 |
| `jet-yf23` | Stealth prototype, diamond wing, V-tails | YF-23 |
| `heli-light` | Light helicopter: bubble windscreen, four-blade rotor, endplate stabiliser, tail rotor and skids | Bell 407-style |
| `balloon` | Hot air balloon with basket | |

### Rockets

<img alt="Rockets" src="https://raw.githubusercontent.com/munimtechnologies/munim-maps/main/.github/resources/vehicles-rockets.jpg" width="100%">

| Name | Rocket |
| --- | --- |
| `rocket-starship` | Starship on Super Heavy: stainless steel rings and welds, four grid fins, chines, the vented hot-staging ring, 33 Raptors, the ship's black hexagonal heat shield and flaps (123 m) |
| `rocket-falcon9` | Falcon 9: octaweb and nine Merlins, folded legs, black interstage with grid fins, fairing with its seam (70 m) |
| `rocket-saturnv` | Saturn V: roll pattern, fins and engine fairings, five F-1s, S-IVB stripes, service module and escape tower (111 m) |
| `rocket-shuttle` | Space Shuttle stack: double-delta orbiter with black tiles, OMS pods and three main engines; ribbed intertank, feedline and the two boosters (56 m) |
| `starbase-tower` | Starbase's launch tower: steel lattice, the "chopsticks" catch arms and the ship quick-disconnect arm (146 m) |
| `starbase-mount` | Starbase's orbital launch mount: six legs, the ring with hold-down clamps, the booster quick-disconnect and the deluge plate on a concrete pad |

Rockets stand upright; animate a launch by raising `altitude` and add `effect: 'exhaust'`. To stand a Starship on its pad, give the tower, mount and ship the same `heading` (the bearing from the tower to the mount), put the ship at the mount's coordinate with `altitude: 20`, and the tower 22 m behind the mount.

### Spacecraft

<img alt="Spacecraft" src="https://raw.githubusercontent.com/munimtechnologies/munim-maps/main/.github/resources/vehicles-space.jpg" width="100%">

| Name | Spacecraft |
| --- | --- |
| `satellite-iss` | International Space Station: truss, eight solar array wings with roll-out arrays, radiators, the modules, Canadarm2 and docked visitors (109 m) |
| `satellite-starlink` | Starlink satellite: flat bus with two long solar wings |
| `satellite-hubble` | Hubble Space Telescope with its aperture door open, solar arrays and antennas |
| `satellite-gps` | GPS III satellite in gold foil with two solar wings |
| `satellite-cubesat` | 3U CubeSat with folding panels and antenna whips |
| `satellite-dragon` | Crew Dragon capsule and trunk, nose cone open |
| `satellite-jwst` | James Webb Space Telescope: 18 gold mirror segments and the five-layer sunshield |

Spacecraft lie flat, facing their direction of travel. `screenSize` sets a model's *height* on screen, so for flat craft use a small value: Starlink is about 1 m tall and 31 m wide, so `screenSize: 1.3` draws it about 40 points wide. Put them in orbit with `altitude` (the ISS flies at about 420 km) and a `globe` map; see [Satellites in orbit](#satellites-in-orbit).

The models are generated from code (`scripts/vehicles/make-vehicles.swift`) and have no logos or brand names. Bodies are skinned through measured cross-sections, wings and tails are airfoil sections, and windows, seams, lights and stripes are laid onto the skin so they follow its curves.

## Platform Support Matrix

| Capability | iOS | Android | Notes |
| --- | --- | --- | --- |
| `MunimMapView` | ✅ | ❌ | MapKit. Android renders nothing for now. |
| `MapModelLayer` over `react-native-maps` | ✅ | ❌ | iOS `react-native-maps` uses MapKit. On Android, Mapbox's own `ModelLayer` draws glTF models natively. |
| `MapModelLayer` over `expo-maps` | ✅ | ❌ | `AppleMaps.View` (SwiftUI `Map`, iOS 17+). |
| USDZ / USD / SCN models | ✅ | ❌ | OBJ through Model I/O. |
| Avatars, labels, stems, zones | ✅ | ❌ | |
| Vehicle catalogue | ✅ | ❌ | `munim-maps/vehicles` (57 models). |
| Globe on the standard map | ✅ | ❌ | Uses a private MapKit switch; see [Troubleshooting](#the-globe-uses-a-private-mapkit-switch). |
| Models and paths on the globe | ✅ | ❌ | Also on `hybrid` / `imagery` with realistic elevation, which are globes by default. |
| Hidden behind buildings | ✅ | ❌ | `occlusion="buildings"`: OpenStreetMap footprints and heights. MapKit's own 3D landmarks are not shared, so heights can differ slightly from what you see. |
| glTF / GLB, OBJ, PLY, STL models | ✅ | ❌ | See [Bring Your Own Model](#-bring-your-own-model). |
| Terrain height | ✅ | ❌ | MapKit does not expose it, so heights come from public elevation tiles: `altitudeReference: 'sea'`, `followTerrain`, `groundElevation()`. See [Terrain](#terrain). |
| User tracking (follow, follow with heading) | ✅ | ❌ | MapKit's own `MKUserTrackingMode`, reported back with `onUserTrackingModeChange`. |
| Compass, scale, tracking and 2D/3D buttons | ✅ | ❌ | Built in or standalone (`MapCompass`, `MapScale`, `MapUserTrackingButton`). Tracking button built in from iOS 17 (a standalone `MKUserTrackingButton` before), 2D/3D button iOS 17+. |
| Place cards for tapped places | ✅ iOS 18+ | ❌ | `selectionAccessory`. |
| React Native views as markers | ✅ | ❌ | `MarkerView`: drawn into a native marker. |
| Gradient polylines, overlay taps, overlay levels | ✅ | ❌ | |
| Search, autocomplete, points of interest | ✅ | ❌ | `MKLocalSearch`, `MKLocalSearchCompleter`, `MKLocalPointsOfInterestRequest`. Physical features and `regionRequired` need iOS 18. |
| Directions and travel times | ✅ | ❌ | `MKDirections`. MapKit gives transit only as travel times (`eta`). |
| Geocoding | ✅ | ❌ | iOS 26 `MKGeocodingRequest` / `MKReverseGeocodingRequest`, `CLGeocoder` before. |
| Places by id, place card sheet | ✅ iOS 18+ | ❌ | `mapItem(id)`, `presentPlaceCard(id)`. |
| Look Around view and snapshots | ✅ iOS 16+ | ❌ | `LookAroundView`, `lookAroundSnapshot()`. |
| Map images without a view | ✅ | ❌ | `mapSnapshot()` (`MKMapSnapshotter`). |

### MapKit coverage

Everything in MapKit's iOS 26 and 27 SDK that a React Native app can use is available. Left out on purpose:

- **macOS-only controls**: `MKZoomControl`, `MKPitchControl`, `showsZoomControls` and `showsPitchControl` are not on iOS. There is no standalone 2D/3D button on iOS either (SwiftUI's `MapPitchToggle` has no UIKit version), so the 2D/3D button is the map's own (`pitchButtonVisibility`).
- **`MKUserTrackingBarButtonItem`**: a navigation-bar item for UIKit; use `MapUserTrackingButton` anywhere in your layout instead.
- **Place cards on your own markers**: MapKit only shows place cards (`MKSelectionAccessory`) for Apple's own places (`selectableMapFeatures`). For a place you found, use `presentPlaceCard(id)`.
- **`MKGeoJSONDecoder`**: turns GeoJSON into the same polylines and polygons any GeoJSON library gives you in JavaScript; pass the coordinates to `polylines` and `polygons`.
- **`MKMultiPolyline` / `MKMultiPolygon`**: a drawing optimisation only; use several entries.
- **`MKOverlayRenderer.blendMode`**, **`MKAnnotationView.accessoryOffset`**, **drag and drop of `MKMapItem`**, **`NSUserActivity` map items** and **`MKDirections.Request(contentsOf:)`** (handling Apple Maps' directions URLs, which needs app-level URL routing): rarely needed from React Native.
- **Glyph images on cluster balloons**: MapKit draws the member count or text, never an image, so `clusterStyles` take text and emoji.
- **Background location**: CoreLocation, not MapKit.

## ⚡ Quick Start

### Draw over react-native-maps

Render `MapModelLayer` right after the map, in the same parent. It covers the map, lets every touch through, and finds the map by `testID`.

```tsx
import MapView from 'react-native-maps'
import { MapModelLayer, type MapModel } from 'munim-maps'
import { VEHICLES } from 'munim-maps/vehicles'

const models: MapModel[] = [
  {
    id: 'friend',
    coordinate: { latitude: 41.8853, longitude: -87.6318 },
    altitude: 15, // metres above the ground
    image: { uri: 'https://example.com/avatar.jpg' },
    imageBorder: { color: '#0A84FF', width: 3 },
    badge: '5F',
    stem: '#0A84FF',
  },
  {
    id: 'car',
    coordinate: { latitude: 41.8841, longitude: -87.6244 },
    source: VEHICLES['car-sedan'],
    tint: '#2E6FD8',
    heading: 0,
    screenSize: 15,
  },
]

export function Map() {
  return (
    <View style={{ flex: 1 }}>
      <MapView style={StyleSheet.absoluteFill} testID="map" pitchEnabled />
      <MapModelLayer
        mapTestID="map"
        models={models}
        onModelPress={(id) => console.log('tapped', id)}
      />
    </View>
  )
}
```

### A map with models built in

```tsx
import { MunimMapView } from 'munim-maps'

<MunimMapView
  style={{ flex: 1 }}
  initialCamera={{ latitude: 41.8838, longitude: -87.6305, distance: 2600, pitch: 62, heading: 20 }}
  mapStyle="muted"
  models={models}
  zones={[{ id: 'park', circle: { center: { latitude: 41.8826, longitude: -87.6226 }, radius: 260 }, color: '#FF3B3040' }]}
/>
```

## 🔧 API Reference

### `MapModelLayer`

| Prop | Type | Default | |
| --- | --- | --- | --- |
| `models` | `MapModel[]` | required | |
| `zones` | `MapZone[]` | `[]` | |
| `mapTestID` | `string` | nearest map | `testID` of the map to draw over. |
| `lighting` | `'auto' \| 'day' \| 'night'` | `auto` | `auto` follows the map's light or dark appearance. |
| `paths` | `MapPath[]` | `[]` | Lines in 3D: at any height, and on the globe. |
| `maxCameraDistance` | `number` | `50000` | Hide everything when the camera is farther away, in metres. Raise it for the globe. |
| `realisticElevation` | `boolean` | `false` | Keep the map on realistic elevation even when the map library sets a flat style. |
| `globe` | `boolean` | `false` | The standard map as a globe when zoomed out. [Private MapKit switch](#the-globe-uses-a-private-mapkit-switch). |
| `occlusion` | `'none' \| 'buildings'` | `none` | Hide models behind buildings. See [Hidden behind buildings](#hidden-behind-buildings). |
| `buildingTilesUrl` | `string` | OpenFreeMap | `{z}/{x}/{y}` vector tiles with an OpenMapTiles `building` layer. |
| `followTerrain` | `boolean` | `false` | Keep models, paths and zones on MapKit's 3D terrain (satellite imagery with realistic elevation). See [Terrain](#terrain). |
| `onModelPress` | `(id: string) => void` | | |
| `onAttachChange` | `(attached: boolean) => void` | | Fires when the map is found or lost. |
| `onError` | `(message: string) => void` | | Load failures and other problems. |
| `style` | `ViewStyle` | fills the parent | |

Ref (`MapModelLayerRef`): `isAttached()`, `measureAlignment()`.

### `MunimMapView`

| Prop | Type | Default |
| --- | --- | --- |
| `initialCamera` | `MapCamera` | required |
| `models` | `MapModel[]` | `[]` |
| `zones` | `MapZone[]` | `[]` |
| `paths` | `MapPath[]` | `[]` |
| `globe` | `boolean` | `false` |
| `occlusion` / `buildingTilesUrl` / `followTerrain` | | as above |
| `mapStyle` | `'standard' \| 'muted' \| 'hybrid' \| 'imagery'` | `standard` |
| `elevation` | `'flat' \| 'realistic'` | `realistic` |
| `colorScheme` | `'system' \| 'light' \| 'dark'` | `system` |
| `showsBuildings` | `boolean` | `true` |
| `showsUserLocation` | `boolean` | `false` |
| `lighting`, `maxCameraDistance`, `onModelPress`, `onError` | | as above |
| `onCameraChange` | `(camera: MapCamera) => void` | fires when the camera stops |

**Map features**

| Prop | Type | Default |
| --- | --- | --- |
| `markers` | `MapMarker[]` | `[]` |
| `polylines` | `MapPolyline[]` | `[]` |
| `polygons` | `MapPolygon[]` | `[]` |
| `circles` | `MapCircle[]` | `[]` |
| `tileOverlays` | `MapTileOverlay[]` | `[]` |
| `clusterStyles` | `MapClusterStyle[]` | MapKit's |
| `showsCompass` / `showsScale` / `showsTraffic` | `boolean` | `true` / `false` / `false` |
| `compassVisibility` / `scaleVisibility` | `'adaptive' \| 'visible' \| 'hidden'` | `adaptive` / `hidden` (override `showsCompass` / `showsScale`) |
| `showsUserTrackingButton` | `boolean` | `false` |
| `pitchButtonVisibility` | `'adaptive' \| 'visible' \| 'hidden'` | `hidden` (iOS 17+) |
| `mapScope` | `string` | | name for standalone controls |
| `pointsOfInterest` | `'all' \| 'none' \| string[]` | `all` (`MKPOICategory…` values or short names such as `'cafe'`) |
| `userTrackingMode` | `'none' \| 'follow' \| 'followWithHeading'` | `none` ([details](#follow-the-user-with-heading)) |
| `zoomEnabled` / `scrollEnabled` / `rotateEnabled` / `pitchEnabled` | `boolean` | `true` |
| `cameraDistanceRange` | `{ min?, max? }` (metres) | MapKit's |
| `cameraBoundary` | `MapRegion` | none |
| `mapPadding` | `{ top, left, bottom, right }` | `0` |
| `selectableMapFeatures` | `('pointsOfInterest' \| 'territories' \| 'physicalFeatures')[]` | `[]` |
| `selectionAccessory` | `'none' \| 'automatic' \| 'callout' \| 'calloutCompact' \| 'calloutFull' \| 'sheet' \| 'openInMaps'` | `none`: Apple's place card for a tapped place (iOS 18+); see [Place cards](#place-cards) |
| `children` | `MarkerView` elements | |

**Events**: `onMapReady`, `onPress`, `onLongPress`, `onCameraMove` (every frame), `onCameraChange` (when it stops), `onMarkerPress`, `onMarkerDeselect`, `onCalloutPress`, `onCalloutAccessoryPress` (`{ id, side: 'left' | 'right' }`), `onClusterPress` (`{ clusteringId, markerIds, latitude, longitude }`, `markerIds` comma-separated), `onOverlayPress` (`{ id, kind, latitude, longitude }` for tappable polylines, polygons and circles; taken instead of `onPress`), `onMarkerDragStart`, `onMarkerDragEnd`, `onUserLocationChange`, `onUserTrackingModeChange` (`'none' | 'follow' | 'followWithHeading'`), `onMapFeaturePress` (with an `id` for `mapItemForFeature`), `onModelPress`, `onError`.

**Ref (`MunimMapViewRef`)**: `setCamera(camera, animated)`, `animateCamera(camera, durationMs, easing)`, `flyCamera(keyframes, start, loop)` (camera keyframes `{ t, camera }` on the same clock as `motion`, stepped natively every frame), `stopFlight()`, `getCamera()`, `setRegion(region, durationMs)`, `getVisibleRegion()`, `fitToCoordinates(coordinates, padding, animated)`, `fitToMarkers(ids, padding, animated)` (comma-separated ids, empty for all), `pointForCoordinate(coordinate)`, `coordinateForPoint(point)`, `selectMarker(id)`, `deselectMarker(id)`, `takeSnapshot(width, height)` (PNG path), `addressForCoordinate(coordinate)`, `hasLookAround(coordinate)`, `openLookAround(coordinate)`, `mapItemForFeature(id)` (the full `MapItem` behind a tapped map feature: phone, website, address), `overlayAtPoint(point)` (id of the tappable overlay a tap there would hit), `measureAlignment()`.

Camera moves from code (`setCamera`, `animateCamera`, `flyCamera`, `setRegion`, `fitTo…`) end user tracking, as a pan does, and report `'none'` through `onUserTrackingModeChange`.

### `MapMarker`

| Field | Default | |
| --- | --- | --- |
| `id`, `coordinate` | required | |
| `title`, `subtitle` | | Shown in the callout, and as the text of a `label`. |
| `style` | `marker` | `pin`, `marker` (balloon), `image`, `avatar`, `label`, `dot`. |
| `color` | | Pin, balloon, dot or label colour. |
| `glyph` | | Text or emoji inside a `marker` balloon. |
| `image` | | `require()`, URL or `{ uri }` for `image` and `avatar`. |
| `size` | | Width (`image`) or diameter (`avatar`, `dot`) in points. |
| `border` | ring 2 for avatars | `{ color, width }`. |
| `badges` | | `{ text, position, color, textColor }[]`: pills at `top-left`, `top-right`, `bottom-left`, `bottom-right` or `bottom`. |
| `anchor` | centre (bottom for images) | `{ x, y }` in 0...1. |
| `zIndex`, `draggable`, `clusteringId`, `callout`, `opacity`, `visible` | | |
| `displayPriority` | `'required'` | `'required'` (1000, never hidden), `'high'` (750), `'low'` (250) or 0...1000: what MapKit hides first where markers overlap. |
| `collisionMode` | `'rectangle'` | `'rectangle'`, `'circle'` or `'none'`. |
| `titleVisibility`, `subtitleVisibility` | `'adaptive'` | `marker` style: when the title and subtitle show under the balloon. |
| `glyphSymbol`, `selectedGlyphSymbol` | | `marker` style: an SF Symbol in the balloon, and while selected (`'cup.and.saucer.fill'`). |
| `glyphColor` | white | `marker` style. |
| `animatesWhenAdded` | `false` | `marker` style: MapKit's drop-in animation. |
| `calloutLeft`, `calloutRight` | none, `'detail'` | `'detail'`, `'info'`, `{ text }` or `{ symbol }` (a button), `{ image }` or `{ symbol, button: false }` (a picture); `null` for none. Taps fire `onCalloutAccessoryPress`. |
| `calloutDetail` | | Several lines of text in the callout, in place of the subtitle. |

On iOS 26 and 27 MapKit shows no callout bubble for the balloon (`marker`) style: selecting one enlarges it and shows its title and subtitle under it. Pins, images, avatars, labels and dots show their callout.

**`MapClusterStyle`** (`clusterStyles`): `{ clusteringId, color?, glyphColor?, glyph? ('{count}' is the number of markers, emoji welcome), title? ('{count} cafés'), subtitle?, displayPriority? }`. Tapping a cluster fires `onClusterPress`; `ref.fitToMarkers(event.markerIds, padding, true)` zooms in on it.

### `MapPolyline`, `MapPolygon`, `MapCircle`, `MapTileOverlay`

- `MapPolyline`: `coordinates`, `strokeColor`, `strokeColors` (a gradient along the line, `MKGradientPolylineRenderer`) with `strokeColorLocations` (0...1, default evenly spaced), `strokeWidth`, `dashPattern` (`[4, 10]`), `geodesic`, `lineCap`, `lineJoin` (`'round'`, `'bevel'`, `'miter'`), `strokeStart` / `strokeEnd` (draw part of the line, 0...1; change `strokeEnd` over time to animate a route, it updates in place), `level`, `tappable`, `zIndex`.
- `MapPolygon`: `coordinates`, `holes`, `strokeColor`, `fillColor`, `strokeWidth`, `dashPattern`, `lineJoin`, `level`, `tappable`, `zIndex`.
- `MapCircle`: `center`, `radius` (metres), `strokeColor`, `fillColor`, `strokeWidth`, `dashPattern`, `level`, `tappable`, `zIndex`.
- `MapTileOverlay`: `urlTemplate` (`{z}/{x}/{y}`), `replacesMap`, `minimumZoom`, `maximumZoom`, `opacity`, `level`, `zIndex`.
- `level`: `'aboveLabels'` (default for shapes) draws over MapKit's labels; `'aboveRoads'` (default for tiles) draws under labels and buildings, like Apple Maps' routes.
- `tappable` (default `true`): taps on the shape fire `onOverlayPress` while that prop is set (the topmost shape wins: lines within a few points, polygons inside with holes cut out, circles inside the radius).

### `MarkerView`

React Native views as a marker, like SwiftUI's `Annotation { … }`. Put it inside `MunimMapView`:

```tsx
<MunimMapView initialCamera={camera} onMarkerPress={(id) => console.log(id)}>
  <MarkerView id="bean" coordinate={{ latitude: 41.8827, longitude: -87.6233 }} anchor={{ x: 0.5, y: 1 }}>
    <View style={styles.bubble}>
      <Text>🫘 Cloud Gate</Text>
    </View>
  </MarkerView>
</MunimMapView>
```

It takes the `MapMarker` fields that are not about the marker's look (`id`, `coordinate`, `anchor` (default the centre), `title`, `subtitle`, `callout…`, `zIndex`, `draggable`, `clusteringId`, `displayPriority`, `collisionMode`, `opacity`, `visible`), plus `tracksViewChanges`.

How it works, and the trade-off: Nitro views can hold React Native children, but MapKit positions markers itself, so the children are laid out off screen and drawn into the picture of a real `MKAnnotationView`. That marker moves with the map in the same frame, clusters, collides, selects, drags and shows callouts like any other, and its events are the map's marker events. But it is a picture, not live views: buttons inside it do not get taps (the whole marker does), and changes show when the `MarkerView` re-renders (and for a second after, so images can load), or continuously with `tracksViewChanges` (15 redraws a second, so turn it off once the content is stable, as with react-native-maps).

### `MapCompass`, `MapScale`, `MapUserTrackingButton`

MapKit's own controls placed anywhere in your layout, like SwiftUI's `MapCompass(scope:)`. Give the map a `mapScope` and the controls the same name; hide the map's own (`compassVisibility="hidden"`) so there is only one.

```tsx
<MunimMapView mapScope="main" compassVisibility="hidden" … />
<View style={styles.toolbar}>
  <MapUserTrackingButton mapScope="main" />
  <MapCompass mapScope="main" visibility="visible" />
  <MapScale mapScope="main" visibility="visible" alignment="leading" style={{ width: 160 }} />
</View>
```

| Prop | | |
| --- | --- | --- |
| `mapScope` | required | The map's `mapScope`. |
| `visibility` | `'adaptive'` | `MapCompass`, `MapScale`: `'adaptive'` (while rotated, while zooming), `'visible'`, `'hidden'`. |
| `alignment` | `'leading'` | `MapScale`: `'leading'`, `'trailing'`, `'center'` (iOS 26). |
| `style` | 44 × 44 (scale 150 × 24) | |

### `LookAroundView`

Apple's Look Around (`MKLookAroundViewController`) inside your layout, like SwiftUI's `LookAroundPreview`. Tap it to go full screen. iOS 16+.

| Prop | Default | |
| --- | --- | --- |
| `coordinate` | | Where to look, or |
| `mapItemId` | | a place id (`MapItem.identifier`, iOS 18+), which wins. |
| `showsRoadLabels` | `true` | |
| `pointsOfInterest` | `'all'` | `'all'`, `'none'` or categories. |
| `navigationEnabled` | `true` | Let the user move along the street. |
| `badgePosition` | `'topLeading'` | `'topLeading'`, `'topTrailing'`, `'bottomTrailing'`. |
| `onSceneChange` | | `(available: boolean)`: whether Apple has imagery there. |
| `onFullScreenChange` | | `(fullScreen: boolean)` |
| `onError`, `style` | | |

### 🔎 MapKit services

Functions, no map needed. All return promises and reject on Android.

| Function | MapKit | Returns |
| --- | --- | --- |
| `searchPlaces({ query, region?, regionRequired?, resultTypes?, pointsOfInterest? })` | `MKLocalSearch` | `MapItem[]` |
| `createSearchCompleter({ region?, resultTypes?, pointsOfInterest?, onResults, onError? })` | `MKLocalSearchCompleter` | `{ setQuery, setRegion, setResultTypes, setPointsOfInterest, resolve(completion), cancel }` |
| `pointsOfInterest({ center, radius? \| region, categories? })` | `MKLocalPointsOfInterestRequest` | `MapItem[]` (radius up to 2 km) |
| `directions({ from, to, transportType?, alternates?, departureDate?, arrivalDate?, avoidTolls?, avoidHighways? })` | `MKDirections` | `Route[]` |
| `eta(sameOptions)` | `MKDirections.calculateETA` | `{ expectedTravelTime, distance, expectedArrivalDate, expectedDepartureDate, transportType }` |
| `geocode(address, region?)` | `MKGeocodingRequest` (iOS 26), `CLGeocoder` | `MapItem[]` |
| `reverseGeocode(coordinate)` | `MKReverseGeocodingRequest` (iOS 26), `CLGeocoder` | `MapItem[]` |
| `mapItem(identifier)` | `MKMapItemRequest` (iOS 18) | `MapItem` |
| `openInMaps(items, { directionsMode?, camera?, region?, mapStyle?, showsTraffic? })` | `MKMapItem.openMaps` | `boolean` |
| `presentPlaceCard(identifier)` | `MKMapItemDetailViewController` (iOS 18) | `boolean` |
| `mapSnapshot({ region \| camera, width, height, mapStyle?, elevation?, colorScheme?, pointsOfInterest?, showsBuildings?, showsTraffic? })` | `MKMapSnapshotter` | PNG path |
| `hasLookAround(coordinate)` | `MKLookAroundSceneRequest` | `boolean` |
| `lookAroundSnapshot({ coordinate \| mapItemId, width, height, pointsOfInterest?, colorScheme? })` | `MKLookAroundSnapshotter` | PNG path |
| `formatDistance(meters, { units?, style? })` | `MKDistanceFormatter` | `"1.2 mi"` |
| `routePolyline(route, { id, strokeColor?, strokeColors?, strokeWidth? })` | | a `polylines` entry drawn like Apple Maps (under labels, round caps) |

- **`MapItem`**: `identifier` (`MKMapItem.Identifier`, iOS 18+, stable between launches), `name`, `phoneNumber`, `url`, `category` (`MKPOICategory…`), `timeZone`, `latitude`, `longitude`, `isCurrentLocation`, and `address` (`name`, `street`, `city`, `region`, `postalCode`, `country`, `countryCode`, `formatted`, `shortAddress`).
- **`Route`**: `name`, `distance` (m), `expectedTravelTime` (s), `transportType`, `advisoryNotices`, `hasTolls`, `hasHighways`, `coordinates` (the full line) and `steps` (`instructions`, `notice`, `distance`, `transportType`, `coordinates`).
- **Waypoints** (`from`, `to`): a coordinate, a `MapItem`, `{ mapItemId }` or `'currentLocation'`.
- **`transportType`**: `'automobile'` (default), `'walking'`, `'cycling'`, `'transit'` (travel times only: MapKit gives no transit routes) or `'any'`.
- **`directionsMode`** (`openInMaps`): `'none'` (show the places), `'automatic'` (the person's preferred mode), `'driving'`, `'walking'`, `'transit'`, `'cycling'`.
- **Categories** (`pointsOfInterest`, `categories`): `MKPOICategory…` raw values or their short names, such as `'cafe'`, `'evCharger'`, `'nationalPark'` (`pointOfInterestCategory(name)` converts).

### Coming from react-native-maps

| react-native-maps | munim-maps |
| --- | --- |
| `<MapView provider={PROVIDER_DEFAULT}>` (iOS) | `<MunimMapView>` |
| `<Marker coordinate title description pinColor>` | `markers={[{ id, coordinate, title, subtitle, style: 'pin', color }]}` |
| `<Marker>` with a custom child view | `<MarkerView>` with children (drawn into a native marker; `tracksViewChanges` works the same), or `style: 'avatar'` / `'image'` / `'label'` with `badges` |
| `<Marker>` `<Callout>` with buttons | `callout`, `calloutLeft` / `calloutRight` (`onCalloutAccessoryPress`), `calloutDetail` |
| `followsUserLocation` (and patching it to follow with heading) | `userTrackingMode="followWithHeading"` + `onUserTrackingModeChange`: MapKit owns the following, nothing recentres from JavaScript |
| `showsMyLocationButton` / `showsCompass` / `showsScale` | `showsUserTrackingButton` / `compassVisibility` / `scaleVisibility`, or `MapUserTrackingButton` / `MapCompass` / `MapScale` anywhere |
| `<Polyline strokeColors>` | `strokeColors` (+ `strokeColorLocations`), a real MapKit gradient |
| `<Polyline tappable onPress>` | `tappable` + `onOverlayPress` on the map |
| `react-native-map-clustering` | `clusteringId` + `clusterStyles` + `onClusterPress` (MapKit's own clustering) |
| `<Geojson>` | parse the GeoJSON in JavaScript and pass `polylines` / `polygons` / `markers` |
| `onPoiClick` | `selectableMapFeatures` + `onMapFeaturePress`, or Apple's place card with `selectionAccessory` |
| Google Places / Directions APIs | `searchPlaces`, `createSearchCompleter`, `directions`, `geocode` (MapKit, no API key) |
| `<Polyline>` / `<Polygon>` / `<Circle>` | `polylines` / `polygons` / `circles` |
| `<UrlTile urlTemplate>` | `tileOverlays` |
| `mapType="mutedStandard"` / `"hybridFlyover"` | `mapStyle="muted"` / `mapStyle="hybrid" elevation="realistic"` |
| `onRegionChange` / `onRegionChangeComplete` | `onCameraMove` / `onCameraChange` |
| `animateCamera` / `animateToRegion` / `fitToCoordinates` | `setCamera` / `setRegion` / `fitToCoordinates` |
| `pointForCoordinate` / `coordinateForPoint` / `addressForCoordinate` / `takeSnapshot` | same names |

`MapCamera`: `{ latitude, longitude, distance, pitch, heading }` (metres from the camera to the centre, degrees).

### `MapModel`

| Field | Default | |
| --- | --- | --- |
| `id` | required | Unique per layer. |
| `coordinate` | required | `{ latitude, longitude }` of the model's base. |
| `altitude` | `0` | Metres above the ground, or above sea level with `altitudeReference: 'sea'`. |
| `altitudeReference` | `'ground'` | `'sea'`: `altitude` (and `motion` altitudes) are metres above sea level, such as a phone's GPS altitude; the ground height there is looked up and taken off, and the model shows once it has loaded. See [Terrain](#terrain). |
| `heading` | `0` | Degrees clockwise from north. |
| `scale` | `1` | Multiplier. Files are read in metres. |
| `source` | | `require()`d asset, `file://` path or `http(s)://` URL of a USDZ, USD, glTF / GLB, SCN, OBJ, PLY, STL or Alembic file. Remote files are cached. |
| `shape` | `box` | Used without `source` or `image`: `box`, `sphere`, `cylinder`, `cone`, `capsule`, `pyramid`, `gem`. |
| `size` | `10 × 10 × 10` | Shape size in metres: `{ width, height, length }`. |
| `color` | `#0A84FF` | Shape colour, `#RRGGBB` or `#RRGGBBAA`. |
| `tint` | | Recolours an asset's paint (materials named `paint…`). |
| `emissive` | `false` | Makes a shape glow. |
| `image` | | PNG or JPEG drawn as a round picture that always faces the camera. Replaces `source` and `shape`. |
| `imageBorder` | | `{ color, width }` ring around the picture. |
| `badge` | | Short text in a pill under the picture, such as `5F`. |
| `label` | | Text in a pill floating above any model. |
| `stem` | `false` | A line from the ground up to the model. `true` or a colour. |
| `lift` | `0` | Raises the model this many points above `altitude`, at any zoom. |
| `screenSize` | `0` (44 for images) | Keeps the model this many points tall at any zoom. |
| `spinDegreesPerSecond` | `0` | |
| `playAnimations` | `true` | Loops animations embedded in a USDZ. |
| `groundShadow` | `true` (false for images) | |
| `effect` | | `'exhaust'`: an engine plume pointing down from the model's base, sized to the model, stopping at the ground. `'smoke'`: a billowing cloud `size.width` metres across, for use without `source`. `'contrail'`: two white trails left in the sky behind a model moving with `motion`. |
| `effectIntensity` | `1` | 0...1, to throttle up or let the smoke clear. |
| `effectOrigins` | | `[x, y, z][]` in the model's metres (x right, y up, z back): where the effect starts, such as one contrail per engine. |
| `occluder` | `false` | Draws nothing but hides other models behind it, like buildings do: stand-ins for things on the map, such as a bridge's railings. |
| `motion` | | `{ keyframes: [{ t, coordinate, altitude?, heading? }], start, loop? }`: moves the model along keyframes natively every frame, so motion stays smooth whatever JavaScript is doing. `start` is seconds since 1970 (`Date.now() / 1000`); without `heading` the model faces where it is going. |
| `visible` | `true` | |

### `MapZone`

| Field | Default | |
| --- | --- | --- |
| `id` | required | |
| `circle` | | `{ center, radius }` in metres, or |
| `polygon` | | `{ latitude, longitude }[]`, closed automatically. |
| `height` | `40` | Wall height in metres. |
| `color` | `#0A84FF40` | The alpha sets how see-through the wall is; the top and bottom edges are solid. |
| `visible` | `true` | |

### `MapPath`

| Field | Default | |
| --- | --- | --- |
| `id` | required | |
| `coordinates` | required | `{ latitude, longitude, altitude? }[]`, altitude in metres above the ground (or sea level). |
| `altitudeReference` | `'ground'` | `'sea'`: the altitudes are above sea level, as on `MapModel`. |
| `color` | `#FFFFFF` | `#RRGGBB` or `#RRGGBBAA`. |
| `width` | `2` | Points on screen, at any zoom. |
| `closed` | `false` | Join the last point back to the first (an orbit). |
| `visible` | `true` | |

Unlike `MapPolyline` (a MapKit overlay, flat on the ground), a path is drawn by the 3D layer, so it also works over `react-native-maps`.

### Helpers

- `isSupported`: `true` on iOS.
- `groundElevation(coordinates)`: `Promise<number[]>`, the height of the ground above sea level in metres at each coordinate, from the same terrain tiles munim-maps uses for `altitudeReference: 'sea'`. Negative under the sea (the sea floor) and in places below sea level. Rejects if a tile cannot be downloaded.
- `circleToPolygon(center, radiusMeters, segments?)`: the outline of a circle on the ground.
- `toNativeModel(model)`, `toNativeZone(zone)`, `toNativePath(path)`: the native shapes, for testing.
- `munim-maps/vehicles`: `VEHICLES` (name → asset), `VEHICLE_NAMES`, `VehicleName`.

## 📖 Usage Examples

### Follow the user with heading

MapKit's own tracking: the map follows the user and turns with the device, with the heading beam on the blue dot. MapKit drops it when the user pans or zooms away (and a camera move from code does the same), and says so through `onUserTrackingModeChange`, so keep the mode in state:

```tsx
const [tracking, setTracking] = useState<UserTrackingMode>('followWithHeading')

<MunimMapView
  initialCamera={camera}
  showsUserLocation
  userTrackingMode={tracking}
  onUserTrackingModeChange={setTracking}
  showsUserTrackingButton
/>
<Button title="Follow" onPress={() => setTracking('followWithHeading')} />
```

Nothing recentres the map from JavaScript, so it never fights the user's pan (react-native-maps' `followsUserLocation` did). munim-maps asks for when-in-use location access the first time it needs it; add `NSLocationWhenInUseUsageDescription` to your Info.plist (`expo.ios.infoPlist` in app.json).

### Search with autocomplete

```tsx
const [suggestions, setSuggestions] = useState<SearchCompletion[]>([])
const completer = useMemo(
  () => createSearchCompleter({ region, onResults: setSuggestions }),
  [region]
)
useEffect(() => () => completer.cancel(), [completer])

<TextInput onChangeText={(text) => completer.setQuery(text)} />
{suggestions.map((s) => (
  <Pressable key={s.index} onPress={async () => {
    const [place] = await completer.resolve(s)
    if (place) mapRef.current?.setCamera({ ...place, distance: 1500, pitch: 45, heading: 0 }, true)
  }}>
    <Text>{s.title}</Text>
    <Text>{s.subtitle}</Text>
  </Pressable>
))}

// Or a one-off search:
const cafes = await searchPlaces({ query: 'coffee', region, resultTypes: ['pointOfInterest'] })
```

### Directions, drawn as a gradient

```tsx
const [route] = await directions({ from: 'currentLocation', to: place, transportType: 'automobile' })
// route.distance, route.expectedTravelTime, route.steps[0].instructions …

<MunimMapView
  polylines={[routePolyline(route, { id: 'route', strokeColors: ['#30D158', '#0A84FF'] })]}
  onOverlayPress={(e) => console.log('tapped', e.id)}
/>
```

Animate it being drawn by stepping `strokeEnd` from 0 to 1; the line updates in place.

### Place cards

Let people tap Apple's own places and see Apple's place card (hours, photos, ratings, call and directions), iOS 18+:

```tsx
<MunimMapView
  selectableMapFeatures={['pointsOfInterest']}
  selectionAccessory="automatic"
  onMapFeaturePress={async (feature) => {
    const place = await mapRef.current?.mapItemForFeature(feature.id)
    console.log(place?.phoneNumber, place?.url)
  }}
/>
```

`'callout'` shows the card in a callout over the map, `'sheet'` in a sheet, `'openInMaps'` as a button. While a selection accessory is set MapKit shows no classic callouts on your markers, so leave it `'none'` if you rely on them. For a place you found yourself, `presentPlaceCard(place.identifier)` opens the card as a sheet.

### Look Around

```tsx
<LookAroundView
  style={{ height: 180, borderRadius: 12, overflow: 'hidden' }}
  coordinate={place}
  onSceneChange={(available) => setHasImagery(available)}
/>
const path = await lookAroundSnapshot({ coordinate: place, width: 320, height: 200 })
```

### People in buildings

Phones report altitude above sea level, so pass it as it is with `altitudeReference: 'sea'` and munim-maps takes off the height of the ground there:

```tsx
{
  id: friend.id,
  coordinate: friend.coordinate,
  altitude: friend.altitude, // metres above sea level, from the phone
  altitudeReference: 'sea',
  image: { uri: friend.avatarUrl },
  imageBorder: { color: '#0A84FF', width: 3 },
  badge: `${floor}F`,
  stem: '#0A84FF',
}
```

iOS's `CLLocation.altitude` is already above sea level. Android's `Location.getAltitude()` is above the GPS ellipsoid, tens of metres different; use `getMslAltitudeMeters()` (Android 14+) on the sending phone. For a floor badge, `groundElevation([coordinate])` gives the ground height to measure from.

### Terrain

MapKit does not expose terrain height, so munim-maps reads it from the free, public [Terrarium elevation tiles](https://registry.opendata.aws/terrain-tiles/) on AWS (zoom 14, about 7-10 m per sample, interpolated), cached in memory and in the app's Caches folder.

```tsx
// A hiker on Half Dome, 2,694 m above sea level, and a balloon over the valley
{ id: 'hiker', coordinate: halfDome, altitude: 2696, altitudeReference: 'sea', image: avatar, stem: true }
{ id: 'balloon', coordinate: valley, altitude: 1800, altitudeReference: 'sea', source: VEHICLES.balloon }

// On satellite imagery in 3D, keep models given above the ground on the mountain too
<MunimMapView mapStyle="hybrid" elevation="realistic" followTerrain models={models} />

// Or just the numbers
const [halfDome] = await groundElevation([{ latitude: 37.74602, longitude: -119.53313 }]) // 2693
```

- **Above sea level** (`altitudeReference: 'sea'`): the ground height under the model is taken off its altitude. The model is hidden until its tile has loaded (usually a fraction of a second, then cached), and moving models load the tiles along their `motion` ahead of time.
- **On 3D terrain** (`followTerrain`): MapKit draws real 3D terrain for satellite imagery (`hybrid`, `imagery`) with realistic elevation, around a camera centred on the ground at the middle of the map. Models then need lifting by the difference between the ground under them and the ground at the centre, or a car on a mountainside floats or sinks. `followTerrain` does this for models, paths and zones given above the ground; models above sea level always do it. The `standard` and `muted` styles stay flat (realistic elevation only shades them), so nothing changes there.
- **Accuracy**: within a few metres of surveyed heights in most places (Denver's State Capitol 1608.7 m vs 1609 m, Half Dome 2692.5 m vs 2694 m), but sharp peaks are smoothed (Everest reads about 8,730 m) and MapKit's own terrain mesh can differ a little.
- **Water**: the tiles carry the sea floor under bays and oceans, so for placing models, ground below sea level counts as sea level (the map draws water there). This puts models in the few places on land below sea level (the Dead Sea, Death Valley, Dutch polders) a little high. `groundElevation()` returns the raw values.
- **Privacy**: the tiles for the area of each model, path point and (with 3D terrain) the map's centre are requested from AWS. Nothing is requested unless a model or path uses `'sea'`, `followTerrain` is on, or `groundElevation()` is called. Swift apps can point `MunimTerrain.shared.tileURLTemplate` at their own Terrarium-format tiles.

### A friend riding a vehicle

Two models at the same coordinate: the vehicle on the ground and the avatar lifted above it.

```tsx
const at = { latitude: 41.8841, longitude: -87.6244 }
const models: MapModel[] = [
  { id: 'car', coordinate: at, source: VEHICLES['car-pickup'], tint: '#8E5A2E', heading: 45, screenSize: 16 },
  { id: 'rider', coordinate: at, image: avatar, imageBorder: { color: '#FFFFFF', width: 3 }, screenSize: 40, lift: 20 },
]
```

### Power-ups

```tsx
{
  id: 'revive',
  coordinate,
  shape: 'gem',
  color: '#FF2D55',
  emissive: true,
  screenSize: 28,
  spinDegreesPerSecond: 90,
  label: '❤️ Revive',
}
```

### Zones

```tsx
<MapModelLayer
  mapTestID="map"
  models={[]}
  zones={[
    { id: 'safe', circle: { center, radius: 250 }, height: 40, color: '#30D15833' },
    { id: 'arena', polygon: corners, height: 60, color: '#FF3B3040' },
  ]}
/>
```

### Satellites in orbit

```tsx
import { VEHICLES } from 'munim-maps/vehicles'

<MunimMapView
  style={{ flex: 1 }}
  initialCamera={{ latitude: 22, longitude: -55, distance: 24_000_000, pitch: 0, heading: 0 }}
  globe
  maxCameraDistance={100_000_000}
  models={[{ id: 'iss', coordinate: issGround, altitude: 420_000, heading: issHeading, source: VEHICLES['satellite-iss'], screenSize: 26 }]}
  paths={[{ id: 'iss-orbit', coordinates: orbit.map((c) => ({ ...c, altitude: 420_000 })), color: '#FFD60AAA', width: 1.5, closed: true }]}
/>
```

`example/orbits.ts` moves the ISS, a Starlink train, Hubble, a CubeSat and GPS satellites along circular orbits.

### Moving models and camera moves

For smooth motion, describe it once as keyframes and let munim-maps move it natively every frame, instead of updating `coordinate` from JavaScript. Models and the camera share one clock, so a camera can follow a moving model exactly:

```tsx
const start = Date.now() / 1000 + 1

const plane: MapModel = {
  id: 'jet',
  coordinate: from,
  source: VEHICLES['jet-f22'],
  effect: 'contrail',
  effectOrigins: [[-0.95, 1.5, 9.1], [0.95, 1.5, 9.1]], // the two nozzles
  motion: {
    start,
    keyframes: [
      { t: 0, coordinate: from, altitude: 300 },
      { t: 20, coordinate: to, altitude: 300 },
    ],
  },
}

mapRef.current?.flyCamera(
  [
    { t: 0, camera: { ...from, distance: 2000, pitch: 70, heading: 120 } },
    { t: 20, camera: { ...to, distance: 2000, pitch: 70, heading: 100 } },
  ],
  start,
  false
)
```

### Animation

Update a model from state, for example its `altitude` or `coordinate`; only models whose fields changed are touched natively. Use `spinDegreesPerSecond` or USDZ animations for motion that should not go through JavaScript.

## ⚙️ How It Works

MapKit has no public API for custom 3D content, so munim-maps draws the models itself, in a transparent Metal layer laid exactly over the map.

1. **Camera.** Every frame it reads the map's camera (centre, altitude, pitch, heading). MapKit's camera, fitted against `MKMapView.convert` on device, is a pinhole camera centred on the view with a 30° vertical field of view; the centre coordinate is drawn at the centre of the map's *safe area*, so the camera is moved until the ray through that point lands on it. The field of view is measured from the map each frame rather than hard-coded.
2. **Positions.** Models are placed in metres around the centre of the map using Web Mercator map points, the projection MapKit draws in at street and city zoom. When MapKit draws a globe, they are placed on a sphere instead, still in metres around the centre, with the camera `distance` metres back along the ray through the centre point, and an invisible Earth hides whatever is on the far side.
3. **Timing.** Rendering happens in a run-loop observer at the end of each pass, after the map has moved. SceneKit's transaction is flushed first (otherwise SceneKit draws the previous frame's positions), and the drawable is presented straight from the GPU, the way MapKit presents the map.
4. **Buildings.** With `occlusion="buildings"`, building footprints and heights are loaded from vector tiles around the camera and their walls are drawn into the depth buffer only: nothing shows, but models behind them are hidden. Avatars, labels and stems are drawn on top, so a person inside a building still shows.
5. **Terrain.** Heights come from Terrarium elevation tiles (see [Terrain](#terrain)). When MapKit draws 3D terrain, the camera's ground plane is at the height of the ground at the centre of the map, so models are lifted by the difference between the ground under them and that height.
6. **Touches.** The layer never takes touches. Taps are watched by a recognizer on the map that runs alongside the map's own, and hit-tested against each model.

The example app checks all of this on device: a self-test compares every model's ground point with `MKMapView.convert` at five camera angles on both `MunimMapView` and `react-native-maps` (under a point on iPhone 17 Pro), the same close in with the globe switched on, and a lag test (`munimmapsexample://lagtest`) puts a MapKit `MKCircle` and a model on the same spot and screenshots MapKit's own camera animation (within 0.2 px mid-animation).

## 🔍 Troubleshooting

### Common Issues

1. **Nothing draws**: check `onAttachChange` (is the map found?) and `onError`. Give `react-native-maps` a `testID` and pass it as `mapTestID`.
2. **`require('./x.usdz')` fails to bundle**: add the extension (`usdz`, `glb`…) to Metro's `assetExts`.
3. **A model is huge or tiny**: files are read in metres; use `scale`, or `screenSize` for marker-style models.
4. **Models disappear when zoomed out**: raise `maxCameraDistance` (default 50 km).
5. **Models float or sink on mountains with satellite imagery in 3D**: turn on `followTerrain` (see [Terrain](#terrain)). A model with `altitudeReference: 'sea'` that never appears is waiting for its terrain tile; check `onError`.
6. **Over-the-air update crashes on an old build**: munim-maps is native; ship it in a new build.

### Markers and callouts

- A balloon (`marker`) shows no callout bubble on iOS 26 and 27: MapKit enlarges it and shows the title under it. Use `pin`, `image` or another style for callouts with buttons.
- No callouts at all: a `selectionAccessory` other than `'none'` makes MapKit skip classic callouts.
- `MarkerView` content looks stale: it is a picture. Re-render the `MarkerView` or set `tracksViewChanges` while it changes.

### User tracking stops

MapKit stops following when the user pans or zooms, and munim-maps stops it when you move the camera from code. Both report `'none'` through `onUserTrackingModeChange`; store it in state so setting `'followWithHeading'` again turns it back on. Without location access (or without `NSLocationWhenInUseUsageDescription`) MapKit cannot follow at all.

### Hidden behind buildings

MapKit does not share its depth buffer, so by default models draw over buildings. `occlusion="buildings"` fixes that with OpenStreetMap building footprints and heights, loaded as vector tiles around the camera (z14, cached on the device):

- By default the tiles come from [OpenFreeMap](https://openfreemap.org), a free service with no API key, so the area being viewed is requested from it. Point `buildingTilesUrl` at your own tiles (any OpenMapTiles-schema vector tiles) to keep requests in-house.
- Heights come from OpenStreetMap and can differ a little from Apple's 3D buildings, and buildings without a height are treated as about 10 m tall.
- Avatars, labels and stems are never hidden, so people inside buildings still show; vehicles, shapes and effects are.

### The globe uses a private MapKit switch

MapKit's public API shows the globe only for satellite imagery with realistic elevation. Apple Maps shows it for the standard map through a switch on VectorKit, the engine that draws `MKMapView`; `globe` turns that switch on. It is not public API, so:

- it can stop working in an iOS update (munim-maps checks that the switch exists before using it, so the map then just stays flat);
- App Review may reject an app that uses it.

Leave `globe` off (the default) if that matters to you; `mapStyle="hybrid"` or `"imagery"` with realistic elevation are globes through public API.

MapKit's `convert` methods keep answering as if the map were flat even while it draws the globe, so far-out positions from `pointForCoordinate` / `coordinateForPoint` are off on the globe. munim-maps' own models and paths are placed on the sphere and are not affected.

### Xcode 27

Apps built with Xcode 27 must adopt the scene lifecycle or they crash at launch on iOS 27. With Expo, set `enableSceneSupport` in `expo-build-properties`; the example app does.

### Example

`example/` is an Expo app: Starbase launch pads whose Starships launch on a loop, friends on Chicago skyscrapers, vehicles, power-ups, zone walls, satellites orbiting the globe (`munimmapsexample://orbit`), cities on the globe (`munimmapsexample://cities`), Yosemite in 3D with heights above sea level (`munimmapsexample://terrain`), models over expo-maps (`munimmapsexample://expomaps`), the self-test and the lag test.

```bash
npm install
cd example && npx expo run:ios --device
```

## 🛣️ Roadmap

- **Android on MapLibre**: the open-source map engine (OpenStreetMap data, no API key), with the same 3D layer.

## 👏 Contributing

We welcome contributions! Please open an issue or a pull request on [GitHub](https://github.com/munimtechnologies/munim-maps).

## 📄 License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

---

<img alt="Star the Munim Technologies repo on GitHub to support the project" src="https://user-images.githubusercontent.com/9664363/185428788-d762fd5d-97b3-4f59-8db7-f72405be9677.gif" width="50%">
