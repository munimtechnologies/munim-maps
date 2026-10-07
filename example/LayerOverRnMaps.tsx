import { useEffect, useRef, useState } from 'react'
import { StyleSheet } from 'react-native'
import MapView, { Circle, PROVIDER_GOOGLE } from 'react-native-maps'
import type { HostMapProps, HostPose } from './LayerOver'

/**
 * The host map for `LayerOverScreen`: react-native-maps with
 * `provider="google"` (Google Maps on Android). Padding is react-native-maps'
 * `mapPadding` prop, which Google does not report back, so the layer finds
 * the camera's centre with Google's own projection.
 */
export function RnMapsGoogleHost(props: HostMapProps) {
  const map = useRef<MapView | null>(null)
  const [paddingTop, setPaddingTop] = useState(props.initial.paddingTop ?? 0)
  const { handle } = props
  useEffect(() => {
    const camera = (pose: HostPose) => ({
      center: { latitude: pose.latitude, longitude: pose.longitude },
      zoom: pose.zoom,
      pitch: pose.pitch,
      heading: pose.heading,
    })
    handle({
      setCamera: (pose) => {
        setPaddingTop(pose.paddingTop ?? 0)
        // After the padding has reached the map.
        setTimeout(() => map.current?.setCamera(camera(pose)), 100)
      },
      animateCamera: (pose, ms) => {
        setPaddingTop(pose.paddingTop ?? 0)
        map.current?.animateCamera(camera(pose), { duration: ms })
      },
    })
    return () => handle(null)
  }, [handle])
  return (
    <MapView
      ref={map}
      testID={props.testID}
      provider={PROVIDER_GOOGLE}
      style={StyleSheet.absoluteFill}
      initialCamera={{
        center: { latitude: props.initial.latitude, longitude: props.initial.longitude },
        zoom: props.initial.zoom,
        pitch: props.initial.pitch,
        heading: props.initial.heading,
        altitude: 0,
      }}
      mapPadding={{ top: paddingTop, left: 0, right: 0, bottom: 0 }}
      pitchEnabled
      rotateEnabled
      onMapReady={props.onReady}
    >
      <Circle
        center={props.probe}
        radius={props.probeRadius}
        fillColor="#FF00FF"
        strokeColor="#FF00FF"
        strokeWidth={1}
      />
    </MapView>
  )
}
