import { useEffect, useMemo, useRef } from 'react'
import { StyleSheet } from 'react-native'
import Constants from 'expo-constants'
import Mapbox, { Camera, CircleLayer, MapView, ShapeSource } from '@rnmapbox/maps'
import type { HostMapProps } from './LayerOver'

/**
 * The host map for `LayerOverScreen`: an `@rnmapbox/maps` MapView (Android
 * only in this example; its token comes from the build, never committed).
 */
const token = (Constants.expoConfig?.extra as { mapboxAccessToken?: string } | undefined)?.mapboxAccessToken
if (token) void Mapbox.setAccessToken(token)

export function RnMapboxHost(props: HostMapProps) {
  const camera = useRef<Camera | null>(null)
  const { handle } = props
  useEffect(() => {
    handle({
      setCamera: (pose) =>
        camera.current?.setCamera({
          centerCoordinate: [pose.longitude, pose.latitude],
          zoomLevel: pose.zoom,
          pitch: pose.pitch,
          heading: pose.heading,
          padding: { paddingTop: pose.paddingTop ?? 0, paddingBottom: 0, paddingLeft: 0, paddingRight: 0 },
          animationMode: 'none',
          animationDuration: 0,
        }),
      animateCamera: (pose, ms) =>
        camera.current?.setCamera({
          centerCoordinate: [pose.longitude, pose.latitude],
          zoomLevel: pose.zoom,
          pitch: pose.pitch,
          heading: pose.heading,
          padding: { paddingTop: pose.paddingTop ?? 0, paddingBottom: 0, paddingLeft: 0, paddingRight: 0 },
          animationMode: 'easeTo',
          animationDuration: ms,
        }),
    })
    return () => handle(null)
  }, [handle])
  const probe = useMemo(
    () => ({
      type: 'Feature' as const,
      properties: {},
      geometry: { type: 'Point' as const, coordinates: [props.probe.longitude, props.probe.latitude] },
    }),
    [props.probe]
  )
  // Circle radius in pixels for `probeRadius` metres: Mapbox circles are sized in points, so scale with zoom.
  const metersPerPointZ22 =
    (Math.cos((props.probe.latitude * Math.PI) / 180) * 2 * Math.PI * 6_378_137) / (512 * 2 ** 22)
  return (
    <MapView
      testID={props.testID}
      style={StyleSheet.absoluteFill}
      styleURL={Mapbox.StyleURL.Street}
      pitchEnabled
      rotateEnabled
      scaleBarEnabled={false}
      surfaceView={!props.textureView}
      onDidFinishLoadingMap={props.onReady}
    >
      <Camera
        ref={camera}
        defaultSettings={{
          centerCoordinate: [props.initial.longitude, props.initial.latitude],
          zoomLevel: props.initial.zoom,
          pitch: props.initial.pitch,
          heading: props.initial.heading,
          padding: { paddingTop: props.initial.paddingTop ?? 0, paddingBottom: 0, paddingLeft: 0, paddingRight: 0 },
        }}
      />
      <ShapeSource id="probe" shape={probe}>
        <CircleLayer
          id="probe-circle"
          style={{
            circleColor: '#FF00FF',
            circlePitchAlignment: 'map',
            circlePitchScale: 'map',
            // Exponential base 2: the radius doubles with each zoom level, as the ground does.
            circleRadius: [
              'interpolate',
              ['exponential', 2],
              ['zoom'],
              0,
              props.probeRadius / metersPerPointZ22 / 2 ** 22,
              22,
              props.probeRadius / metersPerPointZ22,
            ],
          }}
        />
      </ShapeSource>
    </MapView>
  )
}
