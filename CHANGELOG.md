# Changelog

All notable changes to this project are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-10-05

### Added

- `MapModelLayer`: draws 3D models over an existing MapKit map, such as `react-native-maps`' `MapView` on iOS, found by `testID` or as the nearest map on screen.
- `MunimMapView`: a MapKit map with models built in, with `standard`, `muted`, `hybrid` and `imagery` styles, flat or realistic elevation, and `setCamera` / `getCamera`.
- Models from USDZ, USD, SCN or OBJ files (bundled, `file://` or cached `http(s)://`) or built-in shapes, with altitude, heading, scale, spin, embedded animations, screen-constant sizing, ground shadows and day/night lighting.
- Camera matching that measures MapKit's focal length from the map itself, and same-frame rendering through a pre-commit run-loop observer.
- `onModelPress` taps and `measureAlignment()` for checking the drawing against MapKit.
