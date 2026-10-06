import type {
  HybridView,
  HybridViewMethods,
  HybridViewProps,
} from 'react-native-nitro-modules'

/**
 * Built-in shapes, for drawing a model without an asset file. `none` means
 * the model is loaded from `uri`.
 */
export type MapModelShape =
  | 'none'
  | 'box'
  | 'sphere'
  | 'cylinder'
  | 'cone'
  | 'capsule'
  | 'pyramid'
  | 'gem'

/**
 * A particle effect drawn with a model: `exhaust` is an engine plume from
 * the model's base, `smoke` a billowing cloud on the ground.
 */
export type MapModelEffect = 'none' | 'exhaust' | 'smoke' | 'contrail'

/** What hides models: nothing, or buildings. */
export type MapOcclusion = 'none' | 'buildings'

/** `day` and `night` fix the lighting; `auto` follows the map's appearance. */
export type MapModelLighting = 'auto' | 'day' | 'night'

/** Where a moving model is `t` seconds into its motion. */
export interface MotionKeyframe {
  t: number
  latitude: number
  longitude: number
  /** Metres above the ground. */
  altitude: number
  /** Degrees clockwise from north; negative faces the direction of travel. */
  heading: number
}

/**
 * One model as the native side receives it. Every field is required here so
 * no optional struct or enum crosses the bridge (margelo/nitro#1319); the
 * JavaScript wrapper fills the defaults.
 */
export interface NativeMapModel {
  id: string
  latitude: number
  longitude: number
  /** Metres above the ground. */
  altitude: number
  /** Degrees clockwise from north. */
  heading: number
  /** Multiplier applied to the model, after any `screenSize` sizing. */
  scale: number
  /** `file://`, absolute path or `http(s)://` URL of a USDZ, USD, SCN or OBJ file. Empty for shapes. */
  uri: string
  shape: MapModelShape
  /** Shape size in metres (x, east-west at heading 0). */
  width: number
  /** Shape size in metres (y, up). */
  height: number
  /** Shape size in metres (z, north-south at heading 0). */
  length: number
  /** Shape colour as `#RRGGBB` or `#RRGGBBAA`. Ignored for asset models. */
  color: string
  /**
   * Recolours an asset's paint: every material whose name starts with
   * `paint`. Empty keeps the file's colours.
   */
  tintColor: string
  /** Makes the shape glow, so it stays bright on the dark map. */
  emissive: boolean
  spinDegreesPerSecond: number
  /** Loops the animations embedded in a USDZ file. */
  playAnimations: boolean
  /** When above 0, the model is resized every frame to this height in points. */
  screenSize: number
  /** Draws a soft round shadow on the ground under the model. */
  groundShadow: boolean
  /**
   * `file://`, absolute path or `http(s)://` URL of a PNG or JPEG. When set,
   * the model is a round picture that always faces the camera (an avatar),
   * `screenSize` points across, instead of `uri` or `shape`.
   */
  imageUri: string
  /** Ring around the picture, `#RRGGBB(AA)`. Empty for none. */
  imageBorderColor: string
  /** Ring width in points. */
  imageBorderWidth: number
  /** Short text in a pill under the picture, such as `4F`. Empty for none. */
  imageBadge: string
  /** Raises the model this many points above `altitude`, at any zoom. */
  liftPoints: number
  /** Text in a pill floating above the model. Empty for none. */
  label: string
  /** Draws a thin line from the ground up to the model, for floating models. */
  stem: boolean
  /** Stem colour, `#RRGGBB(AA)`. */
  stemColor: string
  effect: MapModelEffect
  /** 0...1, to throttle the effect up or let it die away. */
  effectIntensity: number
  /** Keyframes interpolated natively every frame. Empty for none. */
  motion: MotionKeyframe[]
  /** When `t = 0` is, in seconds since 1970. */
  motionStart: number
  motionLoop: boolean
  /** Draw nothing, but hide other models behind it. */
  occluder: boolean
  /** "x,y,z;x,y,z": where the effect starts, in the model's metres. Empty for the default. */
  effectOrigins: string
  visible: boolean
}

export interface MapCoordinate {
  latitude: number
  longitude: number
}

/** A see-through wall standing on a zone's outline, fading out at the top. */
export interface NativeMapZone {
  id: string
  /** Outline, in order. Closed automatically. */
  points: MapCoordinate[]
  /** Wall height in metres. */
  height: number
  /**
   * `#RRGGBB` or `#RRGGBBAA`. The alpha sets how see-through the wall is;
   * the edges at the top and bottom are drawn solid, like a map outline.
   */
  color: string
  visible: boolean
}

export interface MapPathPoint {
  latitude: number
  longitude: number
  /** Metres above the ground. */
  altitude: number
}

/**
 * A line drawn in 3D: it can sit above the ground and follows the globe,
 * where MapKit's own overlays stay flat.
 */
export interface NativeMapPath {
  id: string
  points: MapPathPoint[]
  /** `#RRGGBB` or `#RRGGBBAA`. */
  color: string
  /** Points on screen. */
  width: number
  /** Join the last point back to the first. */
  closed: boolean
  visible: boolean
}

/** How far the drawn models are from where MapKit draws the same points. */
export interface MapAlignmentReport {
  attached: boolean
  modelsMeasured: number
  /** Largest gap in points between a model's ground point and MapKit's. */
  maxErrorPoints: number
  meanErrorPoints: number
  /** Models whose rendered pixels were found where they were projected. */
  modelsVisibleInRender: number
  cameraDistance: number
  cameraPitch: number
  cameraHeading: number
  /** The vertical field of view matched to MapKit, in degrees. */
  fieldOfViewDegrees: number
}

export interface MapModelLayerProps extends HybridViewProps {
  models: NativeMapModel[]
  zones: NativeMapZone[]
  paths: NativeMapPath[]
  /**
   * `buildings` hides models behind buildings (MapKit does not share its
   * depth buffer). Footprints and heights come from vector tiles around the
   * camera, OpenStreetMap data from OpenFreeMap unless `buildingTilesUrl`
   * is set. Avatars, labels and stems stay visible.
   */
  occlusion: MapOcclusion
  /** `{z}/{x}/{y}` vector tiles with an OpenMapTiles `building` layer. Empty uses OpenFreeMap. */
  buildingTilesUrl: string
  /**
   * `testID` of the map to draw over. Empty means the nearest MapKit map on
   * screen, which is right when there is only one.
   */
  mapTestID: string
  lighting: MapModelLighting
  /** Hide every model while the camera is farther away than this, in metres. */
  maxCameraDistance: number
  /**
   * Keep the map on realistic elevation (3D terrain and landmarks, like
   * Apple Maps), even when the map library sets a flat style. iOS 16+.
   */
  realisticElevation: boolean
  /**
   * Show the standard style as a globe when zoomed far out, like Apple
   * Maps (MapKit only does this for satellite imagery). Uses a MapKit switch
   * that is not public API: it may stop working in an iOS update (the map
   * stays flat) and App Review may reject an app for it. Default false.
   */
  globe: boolean
  onModelPress?: (id: string) => void
  /** Fires with `true` when a map is found and `false` when it goes away. */
  onAttachChange?: (attached: boolean) => void
  onError?: (message: string) => void
}

export interface MapModelLayerMethods extends HybridViewMethods {
  isAttached(): boolean
  /** Measures the drawn models against MapKit's own projection. */
  measureAlignment(): Promise<MapAlignmentReport>
}

export type MapModelLayer = HybridView<
  MapModelLayerProps,
  MapModelLayerMethods,
  { ios: 'swift' }
>
