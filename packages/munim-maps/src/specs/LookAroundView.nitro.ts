import type {
  HybridView,
  HybridViewMethods,
  HybridViewProps,
} from 'react-native-nitro-modules'

/** Where the Apple Maps badge sits. */
export type LookAroundBadgePosition =
  'topLeading' | 'topTrailing' | 'bottomTrailing'

/**
 * Apple's Look Around (`MKLookAroundViewController`) embedded in a view:
 * street-level imagery the user can pan, and tap to open full screen.
 */
export interface LookAroundViewProps extends HybridViewProps {
  latitude: number
  longitude: number
  /** An `MKMapItem.Identifier` (iOS 18+); wins over the coordinate. */
  mapItemId: string
  showsRoadLabels: boolean
  /** `all`, `none`, or comma-separated `MKPOICategory…` values. */
  pointsOfInterest: string
  /** Let the user move along the street. */
  navigationEnabled: boolean
  badgePosition: LookAroundBadgePosition
  /** Whether imagery was found for the place (false shows nothing). */
  onSceneChange?: (available: boolean) => void
  onFullScreenChange?: (fullScreen: boolean) => void
  onError?: (message: string) => void
}

export interface LookAroundViewMethods extends HybridViewMethods {}

export type LookAroundView = HybridView<
  LookAroundViewProps,
  LookAroundViewMethods,
  { ios: 'swift' }
>
