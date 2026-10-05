# munim-maps

Animated 3D models on Apple Maps for Expo and React Native.

munim-maps draws USDZ models (or built-in shapes) at real coordinates on a MapKit map, and keeps them on the ground as the map pans, zooms, tilts and rotates. It works two ways:

- **`MapModelLayer`** draws over a map you already have, such as `react-native-maps`' `MapView` on iOS.
- **`MunimMapView`** is a MapKit map with models built in, for apps that do not have a map yet.

It is built with [Nitro Modules](https://nitro.margelo.com). iOS only for now; on Android both components render nothing. Android apps on Mapbox can use Mapbox's own `ModelLayer`.

## Install

```sh
npx expo install munim-maps react-native-nitro-modules
```

Then rebuild the native app (`npx expo prebuild` / `pod install`). munim-maps is native code, so it cannot be added with an over-the-air update.

To bundle `.usdz` files with `require()`, add the extension to Metro:

```js
// metro.config.js
config.resolver.assetExts.push('usdz')
```

## Draw over react-native-maps

Render `MapModelLayer` right after the map, in the same parent. It covers the map, lets every touch through, and finds the map by `testID`.

```tsx
import MapView from 'react-native-maps'
import { MapModelLayer, type MapModel } from 'munim-maps'

const models: MapModel[] = [
  {
    id: 'rocket',
    coordinate: { latitude: 25.99717, longitude: -97.15696 },
    source: require('./assets/starship.usdz'),
    altitude: 20,
  },
  {
    id: 'drop',
    coordinate: { latitude: 25.9952, longitude: -97.1575 },
    shape: 'pyramid',
    color: '#30D158',
    emissive: true,
    screenSize: 36, // stays 36 points tall at any zoom, like a marker
    spinDegreesPerSecond: 90,
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

To animate, update the model (for example its `altitude`) from state. Only models whose fields changed are touched natively.

## A map with models built in

```tsx
import { MunimMapView } from 'munim-maps'

<MunimMapView
  style={{ flex: 1 }}
  initialCamera={{ latitude: 25.9965, longitude: -97.1559, distance: 1100, pitch: 55, heading: 35 }}
  mapStyle="muted"
  models={models}
/>
```

`ref` methods: `setCamera(camera, animated)`, `getCamera()`, `measureAlignment()`.

## Models

| Field | Default | |
| --- | --- | --- |
| `id` | required | Unique per layer. |
| `coordinate` | required | `{ latitude, longitude }` of the model's base. |
| `altitude` | `0` | Metres above the ground. |
| `heading` | `0` | Degrees clockwise from north. |
| `scale` | `1` | Multiplier. Model files are read in metres. |
| `source` | | `require()`d asset, `file://` path or `http(s)://` URL of a USDZ, USD, SCN or OBJ file. Remote files are cached. |
| `shape` | `box` | Used when there is no `source`: `box`, `sphere`, `cylinder`, `cone`, `capsule`, `pyramid`. |
| `size` | `10 × 10 × 10` | Shape size in metres: `{ width, height, length }`. |
| `color` | `#0A84FF` | Shape colour, `#RRGGBB` or `#RRGGBBAA`. |
| `emissive` | `false` | Makes the shape glow, for night maps. |
| `spinDegreesPerSecond` | `0` | Turns the model around its vertical axis. |
| `playAnimations` | `true` | Loops animations embedded in a USDZ. |
| `screenSize` | `0` | When set, keeps the model this many points tall at any zoom. |
| `groundShadow` | `true` | Soft round shadow under the model. |
| `visible` | `true` | |

Each model is moved so the centre of its base sits on the coordinate.

Layer props: `models`, `mapTestID`, `lighting` (`auto` follows the map's light or dark appearance, or force `day` / `night`), `maxCameraDistance` (hide models when zoomed out past this many metres, default 50 km), `onModelPress`, `onAttachChange`, `onError`.

## How it works

MapKit has no public API for custom 3D content, so munim-maps draws the models itself, in a transparent Metal layer laid exactly over the map:

1. **Camera.** Every frame it reads the map's camera (centre, altitude, pitch, heading). MapKit's camera, fitted against `MKMapView.convert` on device, is a pinhole camera centred on the view with a 30° vertical field of view. One detail matters: MapKit draws the centre coordinate at the centre of the map's *safe area*, not of the view, so the camera is moved until the ray through that point lands on it. The field of view is not published, so it is measured from the map each frame rather than hard-coded.
2. **Positions.** Models are placed in metres around the centre of the map using Web Mercator map points, the same flat projection MapKit draws in at street and city zoom.
3. **Timing.** Rendering happens in a run-loop observer that runs just before Core Animation commits the frame, after the map has moved, and the Metal drawable is presented inside that same transaction. The models move in the same frame as the map instead of trailing it.
4. **Touches.** The layer never takes touches. Taps are watched with a recognizer on the map that runs alongside the map's own, and hit-tested against each model's bounds.

`measureAlignment()` compares where each model's ground point is drawn with where MapKit draws the same coordinate (`MKMapView.convert(_:toPointTo:)`), and checks the rendered pixels. The example app runs it on launch for several camera angles, on both `MunimMapView` and `react-native-maps`.

## Limits

- The map's own 3D buildings and terrain never hide a model; models always draw on top of them.
- MapKit does not expose terrain height. With `elevation: 'realistic'` in hilly places a model can float above or sink into the ground; use `altitude` to correct it.
- Zoomed far out (the globe), the flat placement no longer matches, so models hide past `maxCameraDistance`.
- iOS only.

## Example

`example/` is an Expo app with two Starbase launch pads whose Starships launch on a loop, on both `MunimMapView` and `react-native-maps`. It runs a self-test on launch and writes `Documents/munim-maps-selftest.json`.

```sh
npm install
cd example && npx expo run:ios --device
```

## License

Apache-2.0
