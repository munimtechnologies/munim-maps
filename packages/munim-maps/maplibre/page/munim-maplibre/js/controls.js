// Map controls drawn over GL JS, as on the other engines: compass, scale
// bar, user tracking button, 2D/3D (pitch) button; and the user's location
// (from the device, sent by the native engine) with follow modes.
/* global maplibregl */
;(function () {
  'use strict'
  const M = window.munimMapLibre

  const ui = () => document.getElementById('munim-ui')
  let compass, scale, trackingButton, pitchButton

  function visibility(key, fallback) {
    return M.norm(M.state[key] || fallback)
  }

  function padding() {
    const p = M.state.mapPadding || {}
    return { top: p.top || 0, left: p.left || 0, bottom: p.bottom || 0, right: p.right || 0 }
  }

  function ornament(name) {
    const o = (M.options().ornaments || {})[name] || {}
    return o
  }

  /** Puts a control in a corner (`topRight` by default), `stack` points from it. */
  function place(el, corner, margin, stack) {
    const p = padding()
    const mx = margin && margin.x != null ? margin.x : 12
    const my = margin && margin.y != null ? margin.y : 12
    el.style.left = el.style.right = el.style.top = el.style.bottom = ''
    const c = corner || 'topRight'
    if (c === 'topLeft' || c === 'bottomLeft') el.style.left = `${p.left + mx}px`
    else el.style.right = `${p.right + mx}px`
    if (c === 'bottomLeft' || c === 'bottomRight') el.style.bottom = `${p.bottom + my + stack}px`
    else el.style.top = `${p.top + my + stack}px`
  }

  function makeCompass() {
    const el = document.createElement('button')
    el.className = 'munim-control munim-compass'
    el.setAttribute('aria-label', 'Compass')
    el.innerHTML = '<svg viewBox="0 0 30 30"><g><polygon points="15,3 19,15 11,15" fill="#ff3b30"/><polygon points="15,27 19,15 11,15" fill="#8e8e93"/></g></svg>'
    el.addEventListener('click', (ev) => {
      ev.stopPropagation()
      M.map.easeTo({ bearing: 0, duration: 400 })
    })
    ui().appendChild(el)
    return el
  }

  function makeButton(label, onClick) {
    const el = document.createElement('button')
    el.className = 'munim-control'
    el.textContent = label
    el.addEventListener('click', (ev) => {
      ev.stopPropagation()
      onClick()
    })
    ui().appendChild(el)
    return el
  }

  let moving = false
  let moveTimer

  function updateControls() {
    const map = M.map
    if (!map) return
    const heading = map.getBearing()
    let stack = 0
    const compassOrnament = ornament('compass')
    const cv = compassOrnament.visible === false ? 'hidden' : visibility('compassVisibility', 'adaptive')
    const turned = Math.abs(((((heading % 360) + 540) % 360) - 180)) > 1
    const showCompass = cv === 'visible' || (cv === 'adaptive' && turned)
    if (showCompass) {
      compass = compass || makeCompass()
      compass.style.display = 'flex'
      place(compass, compassOrnament.position, compassOrnament.margin, 0)
      compass.querySelector('g').setAttribute('transform', `rotate(${-heading} 15 15)`)
      stack += 48
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
      place(trackingButton, compassOrnament.position, compassOrnament.margin, stack)
      const mode = M.norm(M.state.userTrackingMode || 'none')
      trackingButton.style.color = mode === 'none' ? '' : '#0A84FF'
      trackingButton.style.transform = mode === 'followwithheading' ? 'rotate(-45deg)' : ''
      stack += 48
    } else if (trackingButton) trackingButton.style.display = 'none'
    const pv = visibility('pitchButtonVisibility', 'hidden')
    if (pv !== 'hidden') {
      pitchButton =
        pitchButton ||
        makeButton('3D', () => {
          const pitch = M.map.getPitch()
          M.map.easeTo({ pitch: pitch > 5 ? 0 : 55, duration: 500 })
        })
      pitchButton.style.display = 'flex'
      place(pitchButton, compassOrnament.position, compassOrnament.margin, stack)
      pitchButton.textContent = map.getPitch() > 5 ? '2D' : '3D'
    } else if (pitchButton) pitchButton.style.display = 'none'
    // Scale: adaptive shows it while the camera moves.
    const scaleOrnament = ornament('scaleBar')
    const sv = scaleOrnament.visible === false ? 'hidden' : scaleOrnament.visible === true ? 'visible' : visibility('scaleVisibility', 'hidden')
    const showScale = sv === 'visible' || (sv === 'adaptive' && moving)
    if (showScale) {
      scale = scale || makeScale()
      scale.style.display = 'block'
      place(scale, scaleOrnament.position || 'topLeft', scaleOrnament.margin, 0)
      updateScale(scaleOrnament.metric !== false)
    } else if (scale) scale.style.display = 'none'
  }

  function makeScale() {
    const el = document.createElement('div')
    el.className = 'munim-scale'
    el.innerHTML = '<div class="munim-scale-text"></div><div class="munim-scale-bar"></div>'
    ui().appendChild(el)
    return el
  }

  function updateScale(metric) {
    const map = M.map
    const c = map.getContainer()
    const y = c.clientHeight / 2
    const a = map.unproject([c.clientWidth / 2 - 50, y])
    const b = map.unproject([c.clientWidth / 2 + 50, y])
    const metersPerPixel = a.distanceTo(b) / 100
    if (!(metersPerPixel > 0)) return
    const unit = metric ? 1 : 0.3048
    const perPixel = metersPerPixel / unit
    let nice = 1
    for (let exp = 0; exp < 9; exp++) {
      for (const s of [1, 2, 5]) {
        const v = s * Math.pow(10, exp)
        if (v / perPixel <= 120) nice = v
      }
    }
    const width = nice / perPixel
    const text = metric ? (nice >= 1000 ? `${nice / 1000} km` : `${nice} m`) : nice >= 5280 ? `${Math.round(nice / 5280)} mi` : `${nice} ft`
    scale.querySelector('.munim-scale-text').textContent = text
    scale.querySelector('.munim-scale-bar').style.width = `${Math.round(width)}px`
  }

  M.mapHooks.push((map) => {
    map.on('move', () => {
      moving = true
      clearTimeout(moveTimer)
      moveTimer = setTimeout(() => {
        moving = false
        updateControls()
      }, 800)
      updateControls()
    })
    map.on('load', updateControls)
  })
  for (const key of ['compassVisibility', 'scaleVisibility', 'showsUserTrackingButton', 'pitchButtonVisibility']) M.on(key, updateControls)

  // MARK: User location

  let userMarker
  let location

  function accuracyRing(lat, lon, radius) {
    const ring = []
    const d = radius / 6371008.8
    const f = M.toRad(lat)
    const l = M.toRad(lon)
    for (let i = 0; i <= 48; i++) {
      const b = ((i % 48) / 48) * Math.PI * 2
      const la = Math.asin(Math.sin(f) * Math.cos(d) + Math.cos(f) * Math.sin(d) * Math.cos(b))
      const lo = l + Math.atan2(Math.sin(b) * Math.sin(d) * Math.cos(f), Math.cos(d) - Math.sin(f) * Math.sin(la))
      ring.push([M.toDeg(lo), M.toDeg(la)])
    }
    return { type: 'Feature', properties: {}, geometry: { type: 'Polygon', coordinates: [ring] } }
  }

  function updateUser() {
    const map = M.map
    if (!map) return
    const show = !!M.state.showsUserLocation && !!location
    if (!show) {
      if (userMarker) userMarker.getElement().style.display = 'none'
      if (map.getLayer('munim-user-accuracy')) map.setLayoutProperty('munim-user-accuracy', 'visibility', 'none')
      return
    }
    if (!userMarker) {
      const el = document.createElement('div')
      el.className = 'munim-user-dot'
      el.innerHTML = '<div class="munim-user-heading"></div>'
      userMarker = new maplibregl.Marker({ element: el, anchor: 'center', rotationAlignment: 'map' })
      userMarker.setLngLat([location.longitude, location.latitude]).addTo(map)
    }
    const el = userMarker.getElement()
    el.style.display = 'block'
    userMarker.setLngLat([location.longitude, location.latitude])
    const heading = M.num(location.heading, -1)
    el.querySelector('.munim-user-heading').style.display = heading >= 0 ? 'block' : 'none'
    if (heading >= 0) userMarker.setRotation(heading)
    if (M.styleLoaded(map)) {
      const data = accuracyRing(location.latitude, location.longitude, Math.max(5, M.num(location.horizontalAccuracy, 10)))
      const source = map.getSource('munim-user-accuracy')
      if (source) source.setData(data)
      else {
        map.addSource('munim-user-accuracy', { type: 'geojson', data })
        map.addLayer({ id: 'munim-user-accuracy', type: 'fill', source: 'munim-user-accuracy', paint: { 'fill-color': '#0A84FF', 'fill-opacity': 0.15 } }, map.getLayer('munim-3d') ? 'munim-3d' : undefined)
      }
      map.setLayoutProperty('munim-user-accuracy', 'visibility', 'visible')
    }
    follow()
  }

  function follow() {
    const mode = M.norm(M.state.userTrackingMode || 'none')
    if (mode === 'none' || !location || M.isFlying()) return
    const options = { center: [location.longitude, location.latitude], duration: 500 }
    if (mode === 'followwithheading' && M.num(location.heading, -1) >= 0) options.bearing = location.heading
    M.map.easeTo(options)
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
  M.styleHooks.push(() => location && updateUser())

  // Panning away ends following, as on MapKit.
  M.mapHooks.push((map) => {
    map.on('dragstart', () => {
      const mode = M.norm(M.state.userTrackingMode || 'none')
      if (mode !== 'none') M.setTrackingMode('none', true)
    })
  })

  M.destroyHooks.push(() => {
    for (const el of [compass, scale, trackingButton, pitchButton]) if (el) el.remove()
    compass = scale = trackingButton = pitchButton = undefined
    if (userMarker) userMarker.remove()
    userMarker = undefined
  })
})()
