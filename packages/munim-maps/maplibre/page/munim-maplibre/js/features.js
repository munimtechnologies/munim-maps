// munim-maps' 2D features on GL JS: markers (pin, balloon, image, avatar,
// label, dot; badges, title, callouts, dragging, clustering) as GL JS
// markers (DOM, so they follow terrain and the globe and can be dragged),
// polylines (dashes, gradients, caps, joins, geodesic, trimming), polygons
// with holes and circles as GeoJSON sources with style layers, raster tile
// overlays, and what a tap or long press hits.
/* global maplibregl */
;(function () {
  'use strict'
  const M = window.munimMapLibre

  const FONT = '-apple-system, system-ui, "Segoe UI", Roboto, sans-serif'
  const dpr = () => Math.min(3, window.devicePixelRatio || 1)

  // MARK: Images

  const imageCache = new Map()
  /** Loads an image (through the app for local files) once. */
  M.loadImage = function (uri) {
    const url = M.resource(uri)
    if (!imageCache.has(url)) {
      imageCache.set(
        url,
        new Promise((resolve, reject) => {
          const img = new Image()
          img.crossOrigin = 'anonymous'
          img.onload = () => resolve(img)
          img.onerror = () => {
            imageCache.delete(url)
            reject(new Error(`could not load image ${uri}`))
          }
          img.src = url
        })
      )
    }
    return imageCache.get(url)
  }

  function canvas(width, height) {
    const c = document.createElement('canvas')
    const scale = dpr()
    c.width = Math.ceil(width * scale)
    c.height = Math.ceil(height * scale)
    const ctx = c.getContext('2d')
    ctx.scale(scale, scale)
    return { canvas: c, ctx, width, height }
  }
  M.canvas = canvas

  function roundRect(ctx, x, y, w, h, r) {
    ctx.beginPath()
    ctx.moveTo(x + r, y)
    ctx.arcTo(x + w, y, x + w, y + h, r)
    ctx.arcTo(x + w, y + h, x, y + h, r)
    ctx.arcTo(x, y + h, x, y, r)
    ctx.arcTo(x, y, x + w, y, r)
    ctx.closePath()
  }
  M.roundRect = roundRect

  function drawBadges(ctx, badges, box) {
    for (const b of badges || []) {
      if (!b.text) continue
      ctx.font = `700 10px ${FONT}`
      const w = Math.max(16, ctx.measureText(b.text).width + 8)
      const h = 16
      const pos = M.norm(b.position || 'topright')
      let x = box.x + box.w - w / 2
      let y = box.y - 2
      if (pos === 'topleft') x = box.x - w / 2 + 4
      if (pos === 'bottomleft') {
        x = box.x - w / 2 + 4
        y = box.y + box.h - h + 2
      }
      if (pos === 'bottomright') y = box.y + box.h - h + 2
      if (pos === 'bottom') {
        x = box.x + box.w / 2 - w / 2
        y = box.y + box.h - h / 2
      }
      x = Math.max(0, x)
      ctx.fillStyle = M.css(b.color, '#FF3B30')
      roundRect(ctx, x, y, w, h, h / 2)
      ctx.fill()
      ctx.lineWidth = 1.5
      ctx.strokeStyle = '#ffffff'
      ctx.stroke()
      ctx.fillStyle = M.css(b.textColor, '#ffffff')
      ctx.textAlign = 'center'
      ctx.textBaseline = 'middle'
      ctx.fillText(b.text, x + w / 2, y + h / 2 + 0.5)
    }
  }

  function drawCover(ctx, img, x, y, w, h) {
    const ratio = Math.max(w / img.width, h / img.height)
    const sw = w / ratio
    const sh = h / ratio
    ctx.drawImage(img, (img.width - sw) / 2, (img.height - sh) / 2, sw, sh, x, y, w, h)
  }

  /** The marker's picture, its size in CSS pixels and where its anchor is (0…1). */
  async function markerImage(m, selected) {
    const style = M.norm(m.style || 'pin')
    const color = M.css(m.color, '#FF3B30')
    // The badges' room around the picture: they may overhang it.
    const badgePad = (m.badges || []).some((b) => b && b.text) ? 8 : 0
    switch (style) {
      case 'dot': {
        const size = M.num(m.imageSize, 0) > 0 ? m.imageSize : 14
        const { canvas: c, ctx } = canvas(size + 6, size + 6)
        ctx.beginPath()
        ctx.arc((size + 6) / 2, (size + 6) / 2, size / 2, 0, Math.PI * 2)
        ctx.fillStyle = color
        ctx.shadowColor = 'rgba(0,0,0,0.35)'
        ctx.shadowBlur = 3
        ctx.fill()
        ctx.shadowBlur = 0
        ctx.lineWidth = 2.5
        ctx.strokeStyle = M.css(m.borderColor, '#ffffff')
        ctx.stroke()
        return { image: c, width: size + 6, height: size + 6, anchor: [0.5, 0.5] }
      }
      case 'label': {
        const text = m.title || m.glyph || ''
        const probe = canvas(1, 1).ctx
        probe.font = `600 13px ${FONT}`
        const w = Math.ceil(probe.measureText(text).width) + 20
        const h = 26
        const pad = 2 + badgePad
        const { canvas: c, ctx } = canvas(w + pad * 2, h + pad * 2)
        ctx.shadowColor = 'rgba(0,0,0,0.3)'
        ctx.shadowBlur = 3
        ctx.fillStyle = color
        roundRect(ctx, pad, pad, w, h, h / 2)
        ctx.fill()
        ctx.shadowBlur = 0
        if (M.num(m.borderWidth, 0) > 0) {
          ctx.lineWidth = m.borderWidth
          ctx.strokeStyle = M.css(m.borderColor, '#ffffff')
          ctx.stroke()
        }
        ctx.fillStyle = M.css(m.glyphColor, '#ffffff')
        ctx.font = `600 13px ${FONT}`
        ctx.textAlign = 'center'
        ctx.textBaseline = 'middle'
        ctx.fillText(text, pad + w / 2, pad + h / 2 + 0.5)
        drawBadges(ctx, m.badges, { x: pad, y: pad, w, h })
        return { image: c, width: w + pad * 2, height: h + pad * 2, anchor: [0.5, 0.5] }
      }
      case 'image':
      case 'avatar': {
        const size = M.num(m.imageSize, 0) > 0 ? m.imageSize : style === 'avatar' ? 44 : 32
        const border = M.num(m.borderWidth, style === 'avatar' ? 3 : 0)
        const pad = 6 + badgePad
        const { canvas: c, ctx } = canvas(size + pad * 2, size + pad * 2)
        let img
        try {
          img = m.imageUri ? await M.loadImage(m.imageUri) : undefined
        } catch (e) {
          M.error(`marker ${m.id}`, e)
        }
        const x = pad
        const y = pad
        ctx.save()
        if (style === 'avatar') {
          ctx.shadowColor = 'rgba(0,0,0,0.35)'
          ctx.shadowBlur = 4
          ctx.beginPath()
          ctx.arc(x + size / 2, y + size / 2, size / 2, 0, Math.PI * 2)
          ctx.fillStyle = M.css(m.borderColor, '#ffffff')
          ctx.fill()
          ctx.shadowBlur = 0
          ctx.beginPath()
          ctx.arc(x + size / 2, y + size / 2, size / 2 - border, 0, Math.PI * 2)
          ctx.clip()
          if (img) drawCover(ctx, img, x + border, y + border, size - border * 2, size - border * 2)
          else {
            ctx.fillStyle = color
            ctx.fill()
          }
        } else if (img) {
          const ratio = img.width / Math.max(1, img.height)
          const w = ratio >= 1 ? size : size * ratio
          const h = ratio >= 1 ? size / ratio : size
          ctx.drawImage(img, x + (size - w) / 2, y + (size - h) / 2, w, h)
          if (border > 0) {
            ctx.lineWidth = border
            ctx.strokeStyle = M.css(m.borderColor, '#ffffff')
            ctx.strokeRect(x + (size - w) / 2, y + (size - h) / 2, w, h)
          }
        }
        ctx.restore()
        drawBadges(ctx, m.badges, { x, y, w: size, h: size })
        return { image: c, width: size + pad * 2, height: size + pad * 2, anchor: [0.5, 0.5] }
      }
      case 'marker': {
        // A round balloon with a glyph and a point, like MapKit's marker.
        const d = selected ? 40 : 28
        const w = d + 6
        const h = d + 12
        const { canvas: c, ctx } = canvas(w, h)
        ctx.shadowColor = 'rgba(0,0,0,0.3)'
        ctx.shadowBlur = 3
        ctx.fillStyle = color
        ctx.beginPath()
        ctx.arc(w / 2, d / 2 + 2, d / 2, Math.PI * 0.8, Math.PI * 2.2)
        ctx.lineTo(w / 2, d + 10)
        ctx.closePath()
        ctx.fill()
        ctx.shadowBlur = 0
        const glyph = m.glyph || ''
        ctx.fillStyle = M.css(m.glyphColor, '#ffffff')
        if (glyph) {
          ctx.font = `600 ${Math.round(d * 0.45)}px ${FONT}`
          ctx.textAlign = 'center'
          ctx.textBaseline = 'middle'
          ctx.fillText(glyph, w / 2, d / 2 + 2.5)
        } else {
          ctx.beginPath()
          ctx.arc(w / 2, d / 2 + 2, d * 0.14, 0, Math.PI * 2)
          ctx.fill()
        }
        drawBadges(ctx, m.badges, { x: 3, y: 2, w: d, h: d })
        return { image: c, width: w, height: h, anchor: [0.5, 1] }
      }
      case 'pin':
      default: {
        // A classic map pin: a round head on a point.
        const size = selected ? 56 : 48
        const w = size * 0.62
        const { canvas: c, ctx } = canvas(w, size)
        const r = w / 2 - 2
        const cx = w / 2
        const cy = r + 2
        ctx.shadowColor = 'rgba(0,0,0,0.35)'
        ctx.shadowBlur = 3
        ctx.fillStyle = color
        ctx.beginPath()
        const a = Math.asin(Math.min(1, r / (size - cy - 1)))
        ctx.arc(cx, cy, r, Math.PI / 2 + a, Math.PI / 2 - a + Math.PI * 2)
        ctx.lineTo(cx, size - 1)
        ctx.closePath()
        ctx.fill()
        ctx.shadowBlur = 0
        ctx.lineWidth = 1.5
        ctx.strokeStyle = 'rgba(0,0,0,0.15)'
        ctx.stroke()
        ctx.fillStyle = M.css(m.glyphColor, '#ffffff')
        if (m.glyph) {
          ctx.font = `600 ${Math.round(r)}px ${FONT}`
          ctx.textAlign = 'center'
          ctx.textBaseline = 'middle'
          ctx.fillText(m.glyph, cx, cy + 0.5)
        } else {
          ctx.beginPath()
          ctx.arc(cx, cy, r * 0.38, 0, Math.PI * 2)
          ctx.fill()
        }
        drawBadges(ctx, m.badges, { x: 2, y: 2, w: w - 4, h: r * 2 })
        return { image: c, width: w, height: size, anchor: [0.5, 1] }
      }
    }
  }

  // MARK: Markers

  let markers = new Map() // id -> entry
  let selectedId = ''
  let callout

  function markerKey(m, selected) {
    return JSON.stringify([m.style, m.color, m.glyph, m.glyphColor, m.imageUri, m.imageSize, m.borderColor, m.borderWidth, m.badges, m.title, selected])
  }

  function titleVisible(m) {
    const style = M.norm(m.style || 'pin')
    return !!m.title && style !== 'label' && M.norm(m.titleVisibility) !== 'hidden'
  }

  function makeEntry(m) {
    const el = document.createElement('div')
    el.className = 'munim-marker'
    const img = document.createElement('div')
    img.className = 'munim-marker-image'
    el.appendChild(img)
    const title = document.createElement('div')
    title.className = 'munim-marker-title'
    el.appendChild(title)
    const entry = { spec: m, el, img, title, imageKey: '', size: { width: 1, height: 1 }, anchor: [0.5, 1] }
    const marker = new maplibregl.Marker({ element: el, anchor: 'top-left', draggable: !!m.draggable, subpixelPositioning: true })
    marker.setLngLat(M.lngLat(m))
    entry.marker = marker
    el.addEventListener('click', (ev) => {
      ev.stopPropagation()
      if (entry.justDragged) return
      M.selectMarker(m.id, true)
    })
    marker.on('dragstart', () => {
      entry.dragging = true
      const p = marker.getLngLat()
      M.emit('markerDragStart', { id: entry.spec.id, latitude: p.lat, longitude: p.lng })
    })
    marker.on('drag', () => {
      const p = marker.getLngLat()
      M.emit('markerDrag', { id: entry.spec.id, latitude: p.lat, longitude: p.lng })
      if (selectedId === entry.spec.id) updateCallout()
    })
    marker.on('dragend', () => {
      entry.dragging = false
      entry.justDragged = true
      setTimeout(() => (entry.justDragged = false), 300)
      const p = marker.getLngLat()
      M.emit('markerDragEnd', { id: entry.spec.id, latitude: p.lat, longitude: p.lng })
    })
    return entry
  }

  async function updateImage(entry) {
    const m = entry.spec
    const selected = selectedId === m.id
    const key = markerKey(m, selected)
    if (key === entry.imageKey) return
    entry.imageKey = key
    const result = await markerImage(m, selected)
    if (entry.imageKey !== key) return
    result.image.style.width = `${result.width}px`
    result.image.style.height = `${result.height}px`
    entry.img.replaceChildren(result.image)
    entry.img.style.width = `${result.width}px`
    entry.img.style.height = `${result.height}px`
    entry.size = result
    applyAnchor(entry, result.anchor)
  }

  function applyAnchor(entry, fallback) {
    const m = entry.spec
    const ax = M.num(m.anchorX, -1) >= 0 ? m.anchorX : fallback[0]
    const ay = M.num(m.anchorY, -1) >= 0 ? m.anchorY : fallback[1]
    entry.anchor = [ax, ay]
    entry.marker.setOffset([-ax * entry.size.width, -ay * entry.size.height])
    entry.title.style.top = `${entry.size.height + (M.norm(m.style) === 'dot' ? 2 : 0)}px`
    entry.title.style.left = `${entry.size.width / 2}px`
    if (selectedId === m.id) updateCallout()
  }

  function applySpec(entry, m) {
    const previous = entry.spec
    entry.spec = m
    const marker = entry.marker
    if (!entry.dragging) marker.setLngLat(M.lngLat(m))
    marker.setDraggable(!!m.draggable)
    entry.el.style.zIndex = String(Math.round(M.num(m.zIndex, 0)) + 10)
    entry.el.dataset.markerId = m.id
    // Hidden behind the globe or terrain.
    marker.setOpacity(String(M.num(m.opacity, 1)), '0')
    entry.hidden = m.visible === false
    entry.el.style.visibility = entry.hidden || entry.clustered ? 'hidden' : 'visible'
    const subtitle = m.subtitle && M.norm(m.subtitleVisibility) === 'visible' ? m.subtitle : ''
    if (titleVisible(m)) {
      entry.title.textContent = m.title
      if (subtitle) {
        const s = document.createElement('div')
        s.className = 'munim-marker-subtitle'
        s.textContent = subtitle
        entry.title.appendChild(s)
      }
      entry.title.style.display = 'block'
    } else {
      entry.title.style.display = 'none'
    }
    if (previous && (previous.anchorX !== m.anchorX || previous.anchorY !== m.anchorY)) applyAnchor(entry, entry.size.anchor || [0.5, 1])
    updateImage(entry).catch((e) => M.error(`marker ${m.id}`, e))
  }

  function setMarkers(list) {
    const map = M.map
    const next = new Map()
    for (const m of list || []) next.set(m.id, m)
    for (const [id, entry] of markers) {
      if (!next.has(id)) {
        entry.marker.remove()
        markers.delete(id)
        if (selectedId === id) {
          selectedId = ''
          hideCallout()
        }
      }
    }
    for (const [id, m] of next) {
      let entry = markers.get(id)
      if (!entry) {
        entry = makeEntry(m)
        markers.set(id, entry)
        entry.marker.addTo(map)
      }
      applySpec(entry, m)
    }
    updateClusters()
  }

  M.markerEntry = (id) => markers.get(id)
  M.markerIds = () => [...markers.keys()]

  M.selectMarker = function (id, fromTap) {
    if (selectedId === id) {
      if (fromTap) M.emit('markerPress', { id })
      return
    }
    if (selectedId) M.deselectMarker(true)
    const entry = markers.get(id)
    if (!entry) return
    selectedId = id
    entry.el.classList.add('munim-selected')
    updateImage(entry)
    if (entry.spec.calloutEnabled !== false && (entry.spec.title || entry.spec.subtitle)) showCallout(entry)
    M.emit('markerPress', { id })
  }

  M.deselectMarker = function (notify) {
    if (!selectedId) return
    const id = selectedId
    selectedId = ''
    const entry = markers.get(id)
    if (entry) {
      entry.el.classList.remove('munim-selected')
      updateImage(entry)
    }
    hideCallout()
    if (notify !== false) M.emit('markerDeselect', { id })
  }

  M.selectedMarker = () => selectedId

  // MARK: Callouts

  function accessoryElement(accessory, side, id) {
    if (!accessory) return undefined
    const kind = M.norm(accessory.kind)
    if (!kind || kind === 'none') return undefined
    const button = document.createElement('button')
    button.className = 'munim-callout-accessory'
    if (accessory.color) button.style.color = M.css(accessory.color)
    if (kind === 'image' && accessory.imageUri) {
      const img = document.createElement('img')
      img.src = M.resource(accessory.imageUri)
      button.appendChild(img)
    } else if (kind === 'button') {
      button.textContent = accessory.text || 'Go'
    } else if (kind === 'info') {
      button.textContent = 'ⓘ'
    } else {
      button.textContent = '›'
    }
    button.addEventListener('click', (ev) => {
      ev.stopPropagation()
      M.emit('calloutAccessoryPress', { id, side })
    })
    return button
  }

  function showCallout(entry) {
    hideCallout()
    const m = entry.spec
    const el = document.createElement('div')
    el.className = 'munim-callout'
    const left = accessoryElement(m.leftCalloutAccessory, 'left', m.id)
    if (left) el.appendChild(left)
    const text = document.createElement('div')
    text.className = 'munim-callout-text'
    const title = document.createElement('div')
    title.className = 'munim-callout-title'
    title.textContent = m.title || ''
    text.appendChild(title)
    if (m.subtitle) {
      const sub = document.createElement('div')
      sub.className = 'munim-callout-subtitle'
      sub.textContent = m.subtitle
      text.appendChild(sub)
    }
    if (m.calloutDetail) {
      const detail = document.createElement('div')
      detail.className = 'munim-callout-detail'
      detail.textContent = m.calloutDetail
      text.appendChild(detail)
    }
    el.appendChild(text)
    const right = accessoryElement(m.rightCalloutAccessory, 'right', m.id)
    if (right) el.appendChild(right)
    el.addEventListener('click', (ev) => {
      ev.stopPropagation()
      M.emit('calloutPress', { id: m.id })
    })
    const marker = new maplibregl.Marker({ element: el, anchor: 'bottom' }).setLngLat(entry.marker.getLngLat()).addTo(M.map)
    el.style.zIndex = '1000'
    callout = { el, marker, id: m.id }
    updateCallout()
  }

  function hideCallout() {
    if (callout) callout.marker.remove()
    callout = undefined
  }

  function updateCallout() {
    if (!callout) return
    const entry = markers.get(callout.id)
    if (!entry) return hideCallout()
    callout.marker.setLngLat(entry.marker.getLngLat())
    const ay = entry.anchor ? entry.anchor[1] : 1
    callout.marker.setOffset([0, -(entry.size.height * ay) - 6])
  }

  // MARK: Clustering (screen space, like MapKit's: markers closer than 44 points merge)

  let clusterMarkers = [] // maplibregl.Marker[]
  let clusterTimer

  function clusterStyle(id) {
    return (M.state.clusterStyles || []).find((s) => s.clusteringId === id) || {}
  }

  function clusterElement(clusteringId, members) {
    const style = clusterStyle(clusteringId)
    const count = members.length
    const glyph = style.glyph ? String(style.glyph).replace('{count}', String(count)) : String(count)
    const size = count < 10 ? 34 : count < 100 ? 40 : 46
    const el = document.createElement('div')
    el.className = 'munim-cluster'
    el.style.width = el.style.height = `${size}px`
    el.style.background = M.css(style.color, '#0A84FF')
    el.style.color = M.css(style.glyphColor, '#ffffff')
    el.style.fontSize = `${Math.round(size * 0.4)}px`
    el.textContent = glyph
    return el
  }

  function updateClusters() {
    const map = M.map
    if (!map) return
    for (const c of clusterMarkers) c.remove()
    clusterMarkers = []
    const groups = new Map()
    for (const entry of markers.values()) {
      entry.clustered = false
      const id = entry.spec.clusteringId
      if (!id || entry.hidden || entry.dragging) continue
      if (!groups.has(id)) groups.set(id, [])
      groups.get(id).push(entry)
    }
    for (const [clusteringId, list] of groups) {
      const points = list.map((e) => ({ e, p: map.project(e.marker.getLngLat()), used: false }))
      for (const a of points) {
        if (a.used) continue
        const members = [a]
        a.used = true
        for (const b of points) {
          if (b.used) continue
          if (Math.hypot(a.p.x - b.p.x, a.p.y - b.p.y) < 44) {
            b.used = true
            members.push(b)
          }
        }
        if (members.length < 2) continue
        let lat = 0
        let lng = 0
        for (const m of members) {
          m.e.clustered = true
          const ll = m.e.marker.getLngLat()
          lat += ll.lat
          lng += ll.lng
        }
        lat /= members.length
        lng /= members.length
        const el = clusterElement(
          clusteringId,
          members.map((m) => m.e)
        )
        const ids = members.map((m) => m.e.spec.id)
        el.addEventListener('click', (ev) => {
          ev.stopPropagation()
          M.emit('clusterPress', { clusteringId, markerIds: ids.join(','), latitude: lat, longitude: lng })
        })
        const marker = new maplibregl.Marker({ element: el, anchor: 'center' }).setLngLat([lng, lat]).addTo(map)
        clusterMarkers.push(marker)
      }
    }
    for (const entry of markers.values()) entry.el.style.visibility = entry.hidden || entry.clustered ? 'hidden' : 'visible'
  }
  M.updateClusters = updateClusters

  M.mapHooks.push((map) => {
    // Reclustering while the camera moves would flicker: do it when it settles.
    map.on('moveend', updateClusters)
    map.on('zoom', () => {
      clearTimeout(clusterTimer)
      clusterTimer = setTimeout(updateClusters, 120)
    })
  })

  // MARK: Shapes (GeoJSON sources and style layers)

  const R = 6371008.8
  let shapes = { polyline: [], polygon: [], circle: [] }

  function dashArray(pattern, width) {
    const parts = String(pattern || '')
      .split(/[ ,]+/)
      .map(Number)
      .filter((n) => n > 0)
    if (parts.length < 2) return undefined
    const w = Math.max(0.5, width || 1)
    return parts.map((p) => p / w)
  }

  function listOf(value) {
    if (Array.isArray(value)) return value.map(String)
    return String(value || '')
      .split(',')
      .map((x) => x.trim())
      .filter(Boolean)
  }

  /** Great-circle points between two coordinates, every ~ 50 km. */
  function geodesic(a, b) {
    const f1 = M.toRad(a.latitude)
    const l1 = M.toRad(a.longitude)
    const f2 = M.toRad(b.latitude)
    const l2 = M.toRad(b.longitude)
    const d = 2 * Math.asin(Math.sqrt(Math.sin((f2 - f1) / 2) ** 2 + Math.cos(f1) * Math.cos(f2) * Math.sin((l2 - l1) / 2) ** 2))
    const n = Math.min(256, Math.ceil((d * R) / 50000))
    if (n <= 1 || d === 0) return [a, b]
    const out = []
    for (let i = 0; i <= n; i++) {
      const f = i / n
      const A = Math.sin((1 - f) * d) / Math.sin(d)
      const B = Math.sin(f * d) / Math.sin(d)
      const x = A * Math.cos(f1) * Math.cos(l1) + B * Math.cos(f2) * Math.cos(l2)
      const y = A * Math.cos(f1) * Math.sin(l1) + B * Math.cos(f2) * Math.sin(l2)
      const z = A * Math.sin(f1) + B * Math.sin(f2)
      out.push({ latitude: M.toDeg(Math.atan2(z, Math.sqrt(x * x + y * y))), longitude: M.toDeg(Math.atan2(y, x)) })
    }
    return out
  }

  function distance(a, b) {
    const f1 = M.toRad(a.latitude)
    const f2 = M.toRad(b.latitude)
    const dl = M.toRad(b.longitude - a.longitude)
    return R * 2 * Math.asin(Math.sqrt(Math.sin((f2 - f1) / 2) ** 2 + Math.cos(f1) * Math.cos(f2) * Math.sin(dl / 2) ** 2))
  }

  /** The part of a line between two fractions of its length. */
  function trim(coords, start, end) {
    if ((start <= 0 && end >= 1) || coords.length < 2) return coords
    const lengths = [0]
    for (let i = 1; i < coords.length; i++) lengths.push(lengths[i - 1] + distance(coords[i - 1], coords[i]))
    const total = lengths[lengths.length - 1]
    const at = (d) => {
      let i = 1
      while (i < lengths.length - 1 && lengths[i] < d) i++
      const a = coords[i - 1]
      const b = coords[i]
      const f = (d - lengths[i - 1]) / Math.max(1e-9, lengths[i] - lengths[i - 1])
      return { latitude: a.latitude + (b.latitude - a.latitude) * f, longitude: a.longitude + (b.longitude - a.longitude) * f }
    }
    const s = Math.max(0, start) * total
    const e = Math.min(1, end) * total
    if (e <= s) return []
    const out = [at(s)]
    for (let i = 1; i < coords.length - 1; i++) if (lengths[i] > s && lengths[i] < e) out.push(coords[i])
    out.push(at(e))
    return out
  }

  function circleRing(lat, lon, radius) {
    const ring = []
    const d = radius / R
    const f = M.toRad(lat)
    const l = M.toRad(lon)
    for (let i = 0; i <= 72; i++) {
      const b = ((i % 72) / 72) * Math.PI * 2
      const la = Math.asin(Math.sin(f) * Math.cos(d) + Math.cos(f) * Math.sin(d) * Math.cos(b))
      const lo = l + Math.atan2(Math.sin(b) * Math.sin(d) * Math.cos(f), Math.cos(d) - Math.sin(f) * Math.sin(la))
      ring.push([M.toDeg(lo), M.toDeg(la)])
    }
    return ring
  }

  function ring(coords) {
    const r = coords.map((c) => [c.longitude, c.latitude])
    if (r.length && (r[0][0] !== r[r.length - 1][0] || r[0][1] !== r[r.length - 1][1])) r.push(r[0])
    return r
  }

  /** Layers for one shape: `[{ layer, source }]`, in drawing order. */
  function shapeLayers(kind, s) {
    const base = `munim-shape-${kind}-${s.id}`
    const props = { id: s.id, kind }
    const out = []
    const strokeWidth = M.num(s.strokeWidth, kind === 'polyline' ? 3 : 1)
    const dash = dashArray(s.dashPattern, strokeWidth)
    const stroke = (source, extra) => {
      if (!(strokeWidth > 0)) return
      const paint = { 'line-color': M.css(s.strokeColor, '#0A84FF'), 'line-width': strokeWidth }
      if (dash) paint['line-dasharray'] = dash
      const layout = { 'line-cap': M.norm(s.lineCap) === 'square' ? 'square' : M.norm(s.lineCap) === 'butt' ? 'butt' : 'round', 'line-join': ['bevel', 'miter'].includes(M.norm(s.lineJoin)) ? M.norm(s.lineJoin) : 'round' }
      out.push({ layer: Object.assign({ id: `${base}-line`, type: 'line', source, layout, paint }, extra || {}) })
    }
    if (kind === 'polyline') {
      let coords = s.coordinates || []
      if (s.geodesic && coords.length > 1) {
        const dense = [coords[0]]
        for (let i = 1; i < coords.length; i++) dense.push(...geodesic(coords[i - 1], coords[i]).slice(1))
        coords = dense
      }
      coords = trim(coords, M.num(s.strokeStart, 0), M.num(s.strokeEnd, 1))
      if (coords.length < 2) return { sources: {}, layers: [] }
      const colors = listOf(s.strokeColors)
      const locations = listOf(s.strokeColorLocations).map(Number)
      const source = { type: 'geojson', lineMetrics: colors.length > 1, data: { type: 'Feature', properties: props, geometry: { type: 'LineString', coordinates: coords.map(M.lngLat) } } }
      stroke(base)
      if (colors.length > 1 && out.length) {
        const stops = []
        colors.forEach((c, i) => {
          const at = locations.length === colors.length ? locations[i] : i / (colors.length - 1)
          stops.push(Math.max(0, Math.min(1, at)), M.css(c))
        })
        // Stops must increase.
        for (let i = 2; i < stops.length; i += 2) if (stops[i] <= stops[i - 2]) stops[i] = Math.min(1, stops[i - 2] + 1e-6)
        out[0].layer.paint['line-gradient'] = ['interpolate', ['linear'], ['line-progress'], ...stops]
        delete out[0].layer.paint['line-color']
        delete out[0].layer.paint['line-dasharray']
      }
      return { sources: { [base]: source }, layers: out }
    }
    let polygon
    if (kind === 'polygon') {
      const coords = s.coordinates || []
      if (coords.length < 3) return { sources: {}, layers: [] }
      polygon = [ring(coords), ...(s.holes || []).filter((h) => h.length > 2).map(ring)]
    } else {
      polygon = [circleRing(s.latitude, s.longitude, Math.max(0.1, M.num(s.radius, 100)))]
    }
    const source = { type: 'geojson', data: { type: 'Feature', properties: props, geometry: { type: 'Polygon', coordinates: polygon } } }
    out.push({ layer: { id: `${base}-fill`, type: 'fill', source: base, paint: { 'fill-color': M.css(s.fillColor, '#0A84FF33') } } })
    stroke(base)
    return { sources: { [base]: source }, layers: out }
  }

  let shapeLayerIds = []
  let shapeSourceIds = []
  /** Tappable shape layers: layer id -> { id, kind }. */
  let tappable = new Map()

  /** The layer munim things above labels go under: the 3D layer, the user dot. */
  function topSlot(map) {
    for (const id of ['munim-3d', 'munim-user-accuracy']) if (map.getLayer(id)) return id
    return undefined
  }

  function labelSlot(map) {
    const layer = (map.getStyle().layers || []).find((l) => l.type === 'symbol' && !l.id.startsWith('munim-'))
    return layer ? layer.id : topSlot(map)
  }

  /** Draws every shape again (in zIndex order within its level). */
  function drawShapes() {
    const map = M.map
    if (!map || !M.styleLoaded(map)) return
    for (const id of shapeLayerIds) if (map.getLayer(id)) map.removeLayer(id)
    for (const id of shapeSourceIds) if (map.getSource(id)) map.removeSource(id)
    shapeLayerIds = []
    shapeSourceIds = []
    tappable = new Map()
    const all = []
    for (const kind of ['polygon', 'circle', 'polyline']) for (const s of shapes[kind] || []) all.push({ kind, s })
    all.sort((a, b) => M.num(a.s.zIndex, 0) - M.num(b.s.zIndex, 0))
    for (const { kind, s } of all) {
      let built
      try {
        built = shapeLayers(kind, s)
      } catch (e) {
        M.error(`${kind} ${s.id}`, e)
        continue
      }
      for (const [id, source] of Object.entries(built.sources)) {
        map.addSource(id, source)
        shapeSourceIds.push(id)
      }
      const before = M.norm(s.level) === 'aboveroads' ? labelSlot(map) : topSlot(map)
      for (const { layer } of built.layers) {
        map.addLayer(layer, before)
        shapeLayerIds.push(layer.id)
        if (s.tappable !== false) tappable.set(layer.id, { id: s.id, kind })
      }
    }
  }
  M.drawShapes = drawShapes

  /** The tappable overlay at a point (CSS pixels), or undefined. */
  M.overlayAt = function (point) {
    const map = M.map
    const layers = [...tappable.keys()].filter((id) => map.getLayer(id))
    if (!layers.length) return undefined
    const box = [
      [point.x - 8, point.y - 8],
      [point.x + 8, point.y + 8],
    ]
    const hits = map.queryRenderedFeatures(box, { layers })
    for (const f of hits) {
      const t = tappable.get(f.layer.id)
      if (t) return t
    }
    return undefined
  }

  // MARK: Tile overlays

  let tileIds = []
  function drawTiles() {
    const map = M.map
    if (!map || !M.styleLoaded(map)) return
    for (const id of tileIds) {
      if (map.getLayer(id)) map.removeLayer(id)
      if (map.getSource(id)) map.removeSource(id)
    }
    tileIds = []
    const list = (M.state.tileOverlays || []).slice().sort((a, b) => M.num(a.zIndex, 0) - M.num(b.zIndex, 0))
    let replaces = false
    for (const t of list) {
      if (!t.urlTemplate) continue
      const id = `munim-tiles-${t.id}`
      const source = { type: 'raster', tiles: [M.tileUrl(t.urlTemplate)], tileSize: 256 }
      if (M.num(t.minimumZoom, 0) > 0) source.minzoom = t.minimumZoom
      if (M.num(t.maximumZoom, 0) > 0) source.maxzoom = t.maximumZoom
      map.addSource(id, source)
      const before = M.norm(t.level) === 'abovelabels' ? topSlot(map) : labelSlot(map)
      map.addLayer({ id, type: 'raster', source: id, paint: { 'raster-opacity': M.num(t.opacity, 1) } }, before)
      tileIds.push(id)
      if (t.replacesMap) replaces = true
    }
    if (replaces) {
      for (const l of map.getStyle().layers || []) if (!l.id.startsWith('munim-')) map.setLayoutProperty(l.id, 'visibility', 'none')
    }
  }

  M.styleHooks.push(() => {
    tileIds = []
    shapeLayerIds = []
    shapeSourceIds = []
    drawTiles()
    drawShapes()
  })

  M.on('markers', setMarkers)
  M.on('clusterStyles', updateClusters)
  M.on('polylines', (list) => {
    shapes.polyline = list || []
    drawShapes()
  })
  M.on('polygons', (list) => {
    shapes.polygon = list || []
    drawShapes()
  })
  M.on('circles', (list) => {
    shapes.circle = list || []
    drawShapes()
  })
  M.on('tileOverlays', () => drawTiles())
  M.on('overlayPress', () => {})
  M.mapHooks.push(() => {
    shapes = { polyline: M.state.polylines || [], polygon: M.state.polygons || [], circle: M.state.circles || [] }
  })

  M.method('selectMarker', (a) => M.selectMarker(a.id, false))
  M.method('deselectMarker', () => M.deselectMarker(true))
  M.method('fitToMarkers', (a) => {
    const ids = a.ids && a.ids.length ? new Set(a.ids) : undefined
    const coords = [...markers.values()]
      .filter((e) => !ids || ids.has(e.spec.id))
      .map((e) => {
        const p = e.marker.getLngLat()
        return { latitude: p.lat, longitude: p.lng }
      })
    M.fitCoordinates(coords, a.padding, a.animated)
  })
  M.method('overlayAtPoint', (a) => {
    const hit = M.overlayAt(a.point || a)
    return hit ? hit.id : ''
  })
  M.method('markerScreenPoints', () => {
    const out = {}
    for (const [id, e] of markers) {
      const p = M.map.project(e.marker.getLngLat())
      out[id] = { x: p.x, y: p.y, clustered: !!e.clustered }
    }
    return out
  })

  // MARK: Taps, long presses, places

  const PLACE_KINDS = { poi: 'pointOfInterest', place: 'territory', water_name: 'physicalFeature', mountain_peak: 'physicalFeature', park: 'physicalFeature' }

  function mapFeatureTap(point) {
    const wanted = new Set(M.state.selectableFeatures || [])
    if (!wanted.size) return false
    const map = M.map
    const kindWanted = (kind) => (kind === 'pointOfInterest' && wanted.has('pointsOfInterest')) || (kind === 'territory' && wanted.has('territories')) || (kind === 'physicalFeature' && wanted.has('physicalFeatures'))
    const layers = (map.getStyle().layers || []).filter((l) => l.type === 'symbol' && PLACE_KINDS[l['source-layer']] && kindWanted(PLACE_KINDS[l['source-layer']])).map((l) => l.id)
    if (!layers.length) return false
    const hits = map.queryRenderedFeatures(
      [
        [point.x - 10, point.y - 10],
        [point.x + 10, point.y + 10],
      ],
      { layers }
    )
    const hit = hits[0]
    if (!hit) return false
    const p = hit.properties || {}
    const name = p.name || p['name:en'] || p.name_en || ''
    const tapped = map.unproject([point.x, point.y])
    const coords = hit.geometry && hit.geometry.type === 'Point' ? hit.geometry.coordinates : [tapped.lng, tapped.lat]
    M.emit('mapFeaturePress', {
      title: String(name),
      latitude: coords[1],
      longitude: coords[0],
      kind: PLACE_KINDS[hit.layer['source-layer']],
      category: String(p.class || p.subclass || ''),
      id: hit.id != null ? String(hit.id) : `${hit.layer.id}:${name}`,
    })
    return true
  }

  function payload(point, lngLat) {
    return { latitude: lngLat.lat, longitude: lngLat.lng, x: point.x, y: point.y }
  }

  let suppressClickUntil = 0

  function handleTap(e) {
    if (Date.now() < suppressClickUntil) return
    const target = e.originalEvent && e.originalEvent.target
    if (target && target.closest && target.closest('.munim-marker, .munim-callout, .munim-cluster, .munim-control, .maplibregl-ctrl')) return
    const point = e.point
    const model = M.modelHit && M.modelHit(point)
    if (model) {
      M.emit('modelPress', { id: model })
      return
    }
    if (selectedId) M.deselectMarker(true)
    if (M.state.overlayPress) {
      const hit = M.overlayAt(point)
      if (hit) {
        M.emit('overlayPress', { id: hit.id, kind: hit.kind, latitude: e.lngLat.lat, longitude: e.lngLat.lng })
        return
      }
    }
    if (mapFeatureTap(point)) return
    M.emit('press', payload(point, e.lngLat))
  }

  M.mapHooks.push((map) => {
    map.on('click', handleTap)
    // Long press: half a second without moving (touch); the context menu (mouse).
    let timer
    let start
    let fingers = 0
    const container = map.getCanvasContainer()
    container.addEventListener(
      'touchstart',
      (ev) => {
        fingers = ev.touches.length
        clearTimeout(timer)
        if (fingers !== 1) return
        const target = ev.target
        if (target && target.closest && target.closest('.munim-marker, .munim-callout, .munim-cluster')) return
        const rect = container.getBoundingClientRect()
        start = { x: ev.touches[0].clientX - rect.left, y: ev.touches[0].clientY - rect.top }
        timer = setTimeout(() => {
          suppressClickUntil = Date.now() + 700
          const lngLat = map.unproject([start.x, start.y])
          M.emit('longPress', payload(start, lngLat))
        }, 500)
      },
      { passive: true }
    )
    container.addEventListener(
      'touchmove',
      (ev) => {
        if (!start || ev.touches.length !== 1) return clearTimeout(timer)
        const rect = container.getBoundingClientRect()
        const x = ev.touches[0].clientX - rect.left
        const y = ev.touches[0].clientY - rect.top
        if (Math.hypot(x - start.x, y - start.y) > 8) clearTimeout(timer)
      },
      { passive: true }
    )
    container.addEventListener('touchend', () => clearTimeout(timer), { passive: true })
    container.addEventListener('touchcancel', () => clearTimeout(timer), { passive: true })
    map.on('contextmenu', (e) => M.emit('longPress', payload(e.point, e.lngLat)))
    map.on('move', () => {
      if (callout) updateCallout()
    })
  })

  M.destroyHooks.push(() => {
    for (const e of markers.values()) e.marker.remove()
    markers = new Map()
    selectedId = ''
    hideCallout()
  })
})()
