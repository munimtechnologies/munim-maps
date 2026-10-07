// Map controls drawn over Cesium (it has none of its own): compass, scale
// bar, user tracking button, 2D/3D (pitch) button; and the user's location
// (from the device, sent by the native engine) with follow modes.
/* global Cesium */
;(function () {
  'use strict'
  const M = window.munimCesium
  const C = Cesium

  const ui = () => document.getElementById('munim-ui')
  let compass, scale, trackingButton, pitchButton

  function visibility(key, fallback) {
    return M.norm(M.state[key] || fallback)
  }

  function topInset() {
    return (M.state.mapPadding && M.state.mapPadding.top) || 0
  }

  function makeCompass() {
    const el = document.createElement('button')
    el.className = 'munim-control munim-compass'
    el.setAttribute('aria-label', 'Compass')
    el.innerHTML =
      '<svg viewBox="0 0 30 30"><g><polygon points="15,3 19,15 11,15" fill="#ff3b30"/><polygon points="15,27 19,15 11,15" fill="#8e8e93"/><text x="15" y="12" font-size="0" fill="#fff">N</text></g></svg>'
    el.addEventListener('click', () => {
      const cam = M.munimCamera()
      M.animateTo(Object.assign(cam, { heading: 0 }), 0.4, 'easeinout')
    })
    ui().appendChild(el)
    return el
  }

  function makeButton(label, onClick) {
    const el = document.createElement('button')
    el.className = 'munim-control'
    el.textContent = label
    el.addEventListener('click', onClick)
    ui().appendChild(el)
    return el
  }

  function updateControls() {
    if (!M.viewer) return
    const cam = M.munimCamera()
    const right = ((M.state.mapPadding && M.state.mapPadding.right) || 0) + 12
    let top = topInset() + 12
    // Compass: adaptive shows it while the map is turned.
    const cv = visibility('compassVisibility', 'adaptive')
    const turned = Math.abs(((cam.heading + 180) % 360) - 180) > 1
    const showCompass = cv === 'visible' || (cv === 'adaptive' && turned)
    if (showCompass) {
      compass = compass || makeCompass()
      compass.style.display = 'flex'
      compass.style.right = `${right}px`
      compass.style.top = `${top}px`
      compass.querySelector('g').setAttribute('transform', `rotate(${-cam.heading} 15 15)`)
      top += 48
    } else if (compass) compass.style.display = 'none'
    if (M.state.showsUserTrackingButton) {
      trackingButton =
        trackingButton ||
        makeButton('➤', () => {
          const mode = M.norm(M.state.userTrackingMode || 'none')
          const next = mode === 'none' ? 'follow' : mode === 'follow' ? 'followWithHeading' : 'none'
          M.setTrackingMode(next, true)
        })
      trackingButton.style.display = 'flex'
      trackingButton.style.right = `${right}px`
      trackingButton.style.top = `${top}px`
      const mode = M.norm(M.state.userTrackingMode || 'none')
      trackingButton.style.color = mode === 'none' ? '' : '#0A84FF'
      trackingButton.style.transform = mode === 'followwithheading' ? 'rotate(-45deg)' : ''
      top += 48
    } else if (trackingButton) trackingButton.style.display = 'none'
    const pv = visibility('pitchButtonVisibility', 'hidden')
    if (pv !== 'hidden') {
      pitchButton =
        pitchButton ||
        makeButton('3D', () => {
          const c = M.munimCamera()
          M.animateTo(Object.assign(c, { pitch: c.pitch > 5 ? 0 : 55 }), 0.5, 'easeinout')
        })
      pitchButton.style.display = 'flex'
      pitchButton.style.right = `${right}px`
      pitchButton.style.top = `${top}px`
      pitchButton.textContent = cam.pitch > 5 ? '2D' : '3D'
    } else if (pitchButton) pitchButton.style.display = 'none'
    // Scale: adaptive shows it while the camera moves.
    const sv = visibility('scaleVisibility', 'hidden')
    const showScale = sv === 'visible' || (sv === 'adaptive' && M.isMoving && M.isMoving())
    if (showScale) {
      scale = scale || makeScale()
      scale.style.display = 'block'
      scale.style.left = `${((M.state.mapPadding && M.state.mapPadding.left) || 0) + 12}px`
      scale.style.top = `${topInset() + 12}px`
      updateScale()
    } else if (scale) scale.style.display = 'none'
  }

  function makeScale() {
    const el = document.createElement('div')
    el.className = 'munim-scale'
    el.innerHTML = '<div class="munim-scale-text"></div><div class="munim-scale-bar"></div>'
    ui().appendChild(el)
    return el
  }

  function updateScale() {
    const scene = M.viewer.scene
    const canvas = scene.canvas
    const y = canvas.clientHeight - 40
    const a = M.pickGround(new C.Cartesian2(canvas.clientWidth / 2 - 50, y))
    const b = M.pickGround(new C.Cartesian2(canvas.clientWidth / 2 + 50, y))
    if (!a || !b) return
    const metersPer100 = C.Cartesian3.distance(a, b)
    const metersPerPixel = metersPer100 / 100
    const steps = [1, 2, 5]
    let nice = 1
    for (let exp = 0; exp < 8; exp++) {
      for (const s of steps) {
        const v = s * Math.pow(10, exp)
        if (v / metersPerPixel <= 120) nice = v
      }
    }
    const width = nice / metersPerPixel
    const text = nice >= 1000 ? `${nice / 1000} km` : `${nice} m`
    scale.querySelector('.munim-scale-text').textContent = text
    scale.querySelector('.munim-scale-bar').style.width = `${Math.round(width)}px`
  }

  M.viewerHooks.push((viewer) => viewer.scene.postRender.addEventListener(updateControls))
  M.destroyHooks.push(() => {
    for (const el of [compass, scale, trackingButton, pitchButton]) if (el) el.remove()
    compass = scale = trackingButton = pitchButton = undefined
    userEntity = undefined
  })
  for (const key of ['compassVisibility', 'scaleVisibility', 'showsUserTrackingButton', 'pitchButtonVisibility']) M.on(key, updateControls)

  // MARK: User location

  let userEntity
  let location

  function userDot() {
    const c = document.createElement('canvas')
    const s = Math.min(3, window.devicePixelRatio || 1)
    c.width = c.height = 28 * s
    const ctx = c.getContext('2d')
    ctx.scale(s, s)
    ctx.shadowColor = 'rgba(0,0,0,0.3)'
    ctx.shadowBlur = 3
    ctx.beginPath()
    ctx.arc(14, 14, 10, 0, Math.PI * 2)
    ctx.fillStyle = '#ffffff'
    ctx.fill()
    ctx.shadowBlur = 0
    ctx.beginPath()
    ctx.arc(14, 14, 7, 0, Math.PI * 2)
    ctx.fillStyle = '#0A84FF'
    ctx.fill()
    return c
  }

  function updateUser() {
    if (!M.viewer) return
    const ds = M.viewer.entities
    if (!M.state.showsUserLocation || !location) {
      if (userEntity) userEntity.show = false
      return
    }
    const position = C.Cartesian3.fromDegrees(location.longitude, location.latitude)
    if (!userEntity) {
      userEntity = ds.add({
        id: 'munim-user-location',
        position,
        billboard: { image: userDot(), width: 28, height: 28, heightReference: C.HeightReference.CLAMP_TO_GROUND, disableDepthTestDistance: Number.POSITIVE_INFINITY },
        ellipse: { semiMajorAxis: 10, semiMinorAxis: 10, material: C.Color.fromCssColorString('#0A84FF').withAlpha(0.15) },
      })
      userEntity._munim = { kind: 'user', id: 'user' }
    }
    userEntity.show = true
    userEntity.position = position
    const accuracy = Math.max(5, M.num(location.horizontalAccuracy, 10))
    userEntity.ellipse.semiMajorAxis = accuracy
    userEntity.ellipse.semiMinorAxis = accuracy
    follow()
  }

  function follow() {
    const mode = M.norm(M.state.userTrackingMode || 'none')
    if (mode === 'none' || !location || M.isFlying()) return
    const cam = M.munimCamera()
    const next = Object.assign(cam, { latitude: location.latitude, longitude: location.longitude })
    if (mode === 'followwithheading' && M.num(location.heading, -1) >= 0) next.heading = location.heading
    M.animateTo(next, 0.5, 'easeinout')
  }

  M.setTrackingMode = function (mode, notify) {
    M.state.userTrackingMode = mode
    if (notify) M.emit('userTrackingModeChange', { mode })
    follow()
    updateControls()
  }

  M.on('showsUserLocation', updateUser)
  M.on('userLocation', (l) => {
    location = l
    updateUser()
  })
  M.on('userTrackingMode', () => {
    follow()
    updateControls()
  })

  // Panning away ends following, as on MapKit.
  M.viewerHooks.push((viewer) => {
    const canvas = viewer.scene.canvas
    canvas.addEventListener('pointerdown', () => {
      const mode = M.norm(M.state.userTrackingMode || 'none')
      if (mode !== 'none') {
        const startCam = M.munimCamera()
        const stop = () => {
          canvas.removeEventListener('pointerup', stop)
          const now = M.munimCamera()
          if (Math.abs(now.latitude - startCam.latitude) > 1e-6 || Math.abs(now.longitude - startCam.longitude) > 1e-6) M.setTrackingMode('none', true)
        }
        canvas.addEventListener('pointerup', stop)
      }
    })
  })
})()
