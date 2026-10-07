// Starts the engine: tells the app the page is up, makes the viewer when the
// app sends `init`, and keeps rendering while anything moves.
/* global Cesium */
;(function () {
  'use strict'
  const M = window.munimCesium
  const C = Cesium

  /** Reasons to render every frame (orbiting, particle systems added by commands). */
  M.continuous = {}

  let started = false
  M.start = function () {
    if (started) {
      // A new `init` (keys changed): make the viewer again.
      M.createViewer()
      return
    }
    started = true
    try {
      M.createViewer()
    } catch (e) {
      M.error('could not start (WebGL unavailable?)', e)
      return
    }
    let readyEmitted = false
    const emitReady = () => {
      if (readyEmitted || !M.viewer) return
      readyEmitted = true
      M.emit('mapReady', { cesium: C.VERSION })
    }
    // Ready once the first globe tiles are drawn (or after 3 s, whatever happens).
    M.viewerHooks.push((viewer) => viewer.scene.globe.tileLoadProgressEvent.addEventListener((n) => n === 0 && emitReady()))
    M.viewer.scene.globe.tileLoadProgressEvent.addEventListener((n) => n === 0 && emitReady())
    setTimeout(emitReady, 3000)

    const tick = () => {
      const viewer = M.viewer
      if (viewer && !viewer.isDestroyed()) {
        const animating = M.isFlying() || viewer.scene.mode === C.SceneMode.MORPHING || viewer.clock.shouldAnimate || (M.modelsAnimating && M.modelsAnimating()) || Object.keys(M.continuous).length > 0 || viewer.trackedEntity
        if (animating) viewer.scene.requestRender()
      }
      requestAnimationFrame(tick)
    }
    requestAnimationFrame(tick)
  }

  window.addEventListener('error', (e) => M.error('script error', e.error || e.message))
  window.addEventListener('unhandledrejection', (e) => M.error('unhandled', e.reason))

  M.post({ t: 'ready', cesium: C.VERSION })
})()
