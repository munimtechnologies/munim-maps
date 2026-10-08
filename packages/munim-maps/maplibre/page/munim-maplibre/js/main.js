// Starts the engine: tells the app the page is up and makes the map when
// the app sends `init` (after every prop, so the first style, camera and
// projection are the right ones).
/* global maplibregl */
;(function () {
  'use strict'
  const M = window.munimMapLibre

  let started = false
  M.start = function () {
    document.body.classList.toggle('munim-dark', M.isDark())
    if (started) {
      // A new `init` (keys or the default style changed): the style again.
      if (M.map) M.loadStyle(true)
      return
    }
    started = true
    if (!window.maplibregl) {
      M.error('MapLibre GL JS did not load (offline on the first launch, or blocked)')
      return
    }
    try {
      M.createMap()
    } catch (e) {
      M.error('could not start (WebGL unavailable?)', e)
      return
    }
    // Apply every prop that arrived before the map, in registration order
    // (except what making the map and loading its style already applied).
    const applied = new Set(['options', 'initialCamera', 'styleUrl', 'mapStyle', 'colorScheme', 'globe', 'elevation', 'showsBuildings', 'pointsOfInterest', 'gestures', 'distanceRange', 'boundary', 'mapPadding'])
    for (const key of M.order) {
      if (applied.has(key) || !(key in M.state)) continue
      const handler = M.handlers[key]
      try {
        handler(M.state[key])
      } catch (e) {
        M.error(`could not apply ${key}`, e)
      }
    }
  }

  window.addEventListener('error', (e) => M.error('script error', e.error || e.message))
  window.addEventListener('unhandledrejection', (e) => M.error('unhandled', e.reason))

  M.post({ t: 'ready', maplibre: window.maplibregl ? maplibregl.getVersion() : '' })
})()
