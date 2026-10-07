import { useMemo } from 'react'
import { Platform, type StyleProp, type ViewStyle } from 'react-native'
import { callback, getHostComponent } from 'react-native-nitro-modules'
import LookAroundViewConfig from '../nitrogen/generated/shared/json/LookAroundViewConfig.json'
import type {
  LookAroundBadgePosition,
  LookAroundViewMethods,
  LookAroundViewProps,
} from './specs/LookAroundView.nitro'
import {
  pointsOfInterestFilter,
  type PointOfInterestCategory,
} from './services'

const NativeLookAroundView = getHostComponent<
  LookAroundViewProps,
  LookAroundViewMethods
>('LookAroundView', () => LookAroundViewConfig)

export type { LookAroundBadgePosition }

export interface LookAroundViewProperties {
  /** Where to look, or `mapItemId`. */
  coordinate?: { latitude: number; longitude: number }
  /** A place id (`MapItem.identifier`, iOS 18+). Wins over `coordinate`. */
  mapItemId?: string
  /** Default true. */
  showsRoadLabels?: boolean
  /** Default `'all'`. */
  pointsOfInterest?: 'all' | 'none' | PointOfInterestCategory[]
  /** Let the user move along the street. Default true. */
  navigationEnabled?: boolean
  /** Where the Apple Maps badge sits. Default `'topLeading'`. */
  badgePosition?: LookAroundBadgePosition
  /** Whether Apple has imagery here; the view stays empty when not. */
  onSceneChange?: (available: boolean) => void
  /** The user opened or closed the full-screen view. */
  onFullScreenChange?: (fullScreen: boolean) => void
  onError?: (message: string) => void
  style?: StyleProp<ViewStyle>
}

function useCallbackProp<A extends unknown[]>(
  fn: ((...args: A) => void) | undefined
) {
  return useMemo(() => (fn ? callback(fn) : undefined), [fn])
}

/**
 * Apple's Look Around (`MKLookAroundViewController`) inside your layout,
 * like SwiftUI's `LookAroundPreview`: street-level imagery the user can
 * pan, and tap to open full screen. iOS 16+; renders nothing elsewhere.
 */
export function LookAroundView(props: LookAroundViewProperties) {
  const onSceneChange = useCallbackProp(props.onSceneChange)
  const onFullScreenChange = useCallbackProp(props.onFullScreenChange)
  const onError = useCallbackProp(props.onError)
  if (Platform.OS !== 'ios') return null
  return (
    <NativeLookAroundView
      style={props.style}
      latitude={props.coordinate?.latitude ?? 0}
      longitude={props.coordinate?.longitude ?? 0}
      mapItemId={props.mapItemId ?? ''}
      showsRoadLabels={props.showsRoadLabels ?? true}
      pointsOfInterest={pointsOfInterestFilter(props.pointsOfInterest)}
      navigationEnabled={props.navigationEnabled ?? true}
      badgePosition={props.badgePosition ?? 'topLeading'}
      onSceneChange={onSceneChange}
      onFullScreenChange={onFullScreenChange}
      onError={onError}
    />
  )
}
