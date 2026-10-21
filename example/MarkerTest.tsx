// Manual check for the 0.7.0 fixes (fix/lackin-gaps): an initialRegion that
// arrives after the map is ready (a second one is ignored), CSS colours on
// shapes, and MarkerView pictures that finish loading late. Not linked from
// the example app; render it in place of App to try it.
import { useEffect, useState } from 'react'
import { Image, Text, View } from 'react-native'
import { MarkerView, MunimMapView, type MapRegion } from 'munim-maps'

const CHICAGO: MapRegion = {
  latitude: 41.8826,
  longitude: -87.6226,
  latitudeDelta: 0.02,
  longitudeDelta: 0.02,
}

export default function MarkerTest() {
  const [tick, setTick] = useState(0)
  const [initialRegion, setInitialRegion] = useState<MapRegion | undefined>()
  useEffect(() => {
    const timer = setInterval(() => setTick((t) => t + 1), 1000)
    // Arrives after the map is ready.
    const late = setTimeout(() => setInitialRegion(CHICAGO), 3000)
    // A second value must be ignored.
    const later = setTimeout(
      () => setInitialRegion({ ...CHICAGO, latitude: 40.7128, longitude: -74.006 }),
      6000
    )
    return () => {
      clearInterval(timer)
      clearTimeout(late)
      clearTimeout(later)
    }
  }, [])
  return (
    <View style={{ flex: 1 }}>
      <MunimMapView
        style={{ flex: 1 }}
        testID="test-map"
        initialRegion={initialRegion}
        onMapReady={() => console.log('MARKERTEST ready')}
        polygons={[
          {
            id: 'rgba',
            coordinates: [
              { latitude: 41.886, longitude: -87.63 },
              { latitude: 41.886, longitude: -87.615 },
              { latitude: 41.879, longitude: -87.615 },
              { latitude: 41.879, longitude: -87.63 },
            ],
            fillColor: 'rgba(255, 0, 0, 0.35)',
            strokeColor: 'rebeccapurple',
            strokeWidth: 4,
          },
        ]}
        circles={[
          {
            id: 'hsl',
            center: { latitude: 41.876, longitude: -87.632 },
            radius: 300,
            fillColor: 'hsla(120, 100%, 40%, 0.4)',
            strokeColor: 'transparent',
          },
        ]}
      >
        <MarkerView id="late" coordinate={{ latitude: 41.8826, longitude: -87.6226 }}>
          <View
            style={{
              width: 80,
              height: 80,
              borderRadius: 40,
              overflow: 'hidden',
              backgroundColor: 'orange',
              borderWidth: 3,
              borderColor: 'white',
            }}
          >
            <Image
              source={{ uri: 'http://localhost:8799/late.png' }}
              style={{ width: 80, height: 80 }}
            />
          </View>
        </MarkerView>
        <MarkerView id="label" coordinate={{ latitude: 41.889, longitude: -87.6226 }}>
          <View style={{ backgroundColor: 'white', padding: 6, borderRadius: 8 }}>
            <Text>static label</Text>
          </View>
        </MarkerView>
      </MunimMapView>
      <Text style={{ position: 'absolute', top: 60, left: 20, fontSize: 20 }}>
        tick {tick}
      </Text>
    </View>
  )
}
