// munim-maps' 2D features on Cesium: markers (pin, balloon, image, avatar,
// label, dot; badges, callouts, dragging, clustering), polylines (dashes,
// gradients, trimming), polygons with holes, circles, and what a tap hits.
/* global Cesium */
;(function () {
  'use strict'
  const M = window.munimCesium
  const C = Cesium

  const FONT = '-apple-system, system-ui, "Segoe UI", Roboto, sans-serif'
  const ALWAYS = Number.POSITIVE_INFINITY
  const pinBuilder = new C.PinBuilder()
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

  function roundRect(ctx, x, y, w, h, r) {
    ctx.beginPath()
    ctx.moveTo(x + r, y)
    ctx.arcTo(x + w, y, x + w, y + h, r)
    ctx.arcTo(x + w, y + h, x, y + h, r)
    ctx.arcTo(x, y + h, x, y, r)
    ctx.arcTo(x, y, x + w, y, r)
    ctx.closePath()
  }

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

  /** The marker's picture, its size in CSS pixels and where its anchor is (0…1). */
  async function markerImage(m, selected) {
    const style = M.norm(m.style || 'pin')
    const color = M.color(m.color, '#FF3B30')
    switch (style) {
      case 'dot': {
        const size = M.num(m.imageSize, 0) > 0 ? m.imageSize : 14
        const { canvas: c, ctx } = canvas(size + 6, size + 6)
        ctx.beginPath()
        ctx.arc((size + 6) / 2, (size + 6) / 2, size / 2, 0, Math.PI * 2)
        ctx.fillStyle = color.toCssColorString()
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
        const { canvas: c, ctx } = canvas(w + 4, h + 4)
        ctx.shadowColor = 'rgba(0,0,0,0.3)'
        ctx.shadowBlur = 3
        ctx.fillStyle = color.toCssColorString()
        roundRect(ctx, 2, 2, w, h, h / 2)
        ctx.fill()
        ctx.shadowBlur = 0
        if (m.borderWidth > 0) {
          ctx.lineWidth = m.borderWidth
          ctx.strokeStyle = M.css(m.borderColor, '#ffffff')
          ctx.stroke()
        }
        ctx.fillStyle = M.css(m.glyphColor, '#ffffff')
        ctx.font = `600 13px ${FONT}`
        ctx.textAlign = 'center'
        ctx.textBaseline = 'middle'
        ctx.fillText(text, 2 + w / 2, 2 + h / 2 + 0.5)
        drawBadges(ctx, m.badges, { x: 2, y: 2, w, h })
        return { image: c, width: w + 4, height: h + 4, anchor: [0.5, 0.5] }
      }
      case 'image':
      case 'avatar': {
        const size = M.num(m.imageSize, 0) > 0 ? m.imageSize : style === 'avatar' ? 44 : 32
        const border = M.num(m.borderWidth, style === 'avatar' ? 3 : 0)
        const pad = 6
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
            ctx.fillStyle = color.toCssColorString()
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
        return { image: c, width: size + pad * 2, height: size + pad * 2, anchor: [0.5, style === 'avatar' ? 0.5 : 0.5] }
      }
      case 'marker': {
        // A round balloon with a glyph and a point, like MapKit's marker.
        const d = selected ? 40 : 28
        const w = d + 6
        const h = d + 12
        const { canvas: c, ctx } = canvas(w, h)
        ctx.shadowColor = 'rgba(0,0,0,0.3)'
        ctx.shadowBlur = 3
        ctx.fillStyle = color.toCssColorString()
        ctx.beginPath()
        ctx.arc(w / 2, d / 2 + 2, d / 2, Math.PI * 0.8, Math.PI * 2.2)
        ctx.lineTo(w / 2, d + 10)
        ctx.closePath()
        ctx.fill()
        ctx.shadowBlur = 0
        const glyph = m.glyph || ''
        if (glyph) {
          ctx.fillStyle = M.css(m.glyphColor, '#ffffff')
          ctx.font = `600 ${Math.round(d * 0.45)}px ${FONT}`
          ctx.textAlign = 'center'
          ctx.textBaseline = 'middle'
          ctx.fillText(glyph, w / 2, d / 2 + 2.5)
        } else {
          ctx.fillStyle = M.css(m.glyphColor, '#ffffff')
          ctx.beginPath()
          ctx.arc(w / 2, d / 2 + 2, d * 0.14, 0, Math.PI * 2)
          ctx.fill()
        }
        drawBadges(ctx, m.badges, { x: 3, y: 2, w: d, h: d })
        return { image: c, width: w, height: h, anchor: [0.5, 1] }
      }
      case 'pin':
      default: {
        const size = selected ? 56 : 48
        let pin
        const symbol = m.glyphSymbol || ''
        try {
          if (symbol && /^[a-z0-9-]+$/.test(symbol)) pin = await Promise.resolve(pinBuilder.fromMakiIconId(symbol, color, size))
        } catch (e) {
          pin = undefined
        }
        if (!pin) pin = m.glyph ? pinBuilder.fromText(m.glyph, color, size) : pinBuilder.fromColor(color, size)
        return { image: pin, width: size, height: size, anchor: [0.5, 1] }
      }
    }
  }

  function drawCover(ctx, img, x, y, w, h) {
    const ratio = Math.max(w / img.width, h / img.height)
    const sw = w / ratio
    const sh = h / ratio
    ctx.drawImage(img, (img.width - sw) / 2, (img.height - sh) / 2, sw, sh, x, y, w, h)
  }

  // MARK: Markers

  const markerSources = new Map() // clusteringId ('' for none) -> CustomDataSource
  let markers = new Map() // id -> { spec, entity, key }
  let selectedId = ''
  let callout

  function markerSource(clusteringId) {
    const key = clusteringId || ''
    let source = markerSources.get(key)
    if (source) return source
    source = new C.CustomDataSource(`munim-markers${key ? ':' + key : ''}`)
    if (key) {
      const c = source.clustering
      c.enabled = true
      c.pixelRange = 44
      c.minimumClusterSize = 2
      c.clusterEvent.addEventListener((entities, cluster) => styleCluster(key, entities, cluster))
    }
    M.viewer.dataSources.add(source)
    markerSources.set(key, source)
    return source
  }

  function styleCluster(clusteringId, entities, cluster) {
    const style = (M.state.clusterStyles || []).find((s) => s.clusteringId === clusteringId) || {}
    const count = entities.length
    const text = style.glyph || String(count)
    const size = count < 10 ? 34 : count < 100 ? 40 : 46
    const { canvas: c, ctx } = canvas(size + 4, size + 4)
    ctx.shadowColor = 'rgba(0,0,0,0.3)'
    ctx.shadowBlur = 3
    ctx.beginPath()
    ctx.arc((size + 4) / 2, (size + 4) / 2, size / 2, 0, Math.PI * 2)
    ctx.fillStyle = M.css(style.color, '#0A84FF')
    ctx.fill()
    ctx.shadowBlur = 0
    ctx.lineWidth = 2
    ctx.strokeStyle = '#ffffff'
    ctx.stroke()
    ctx.fillStyle = M.css(style.glyphColor, '#ffffff')
    ctx.font = `700 ${Math.round(size * 0.4)}px ${FONT}`
    ctx.textAlign = 'center'
    ctx.textBaseline = 'middle'
    ctx.fillText(text, (size + 4) / 2, (size + 4) / 2 + 0.5)
    cluster.label.show = false
    cluster.billboard.show = true
    cluster.billboard.image = c
    cluster.billboard.width = size + 4
    cluster.billboard.height = size + 4
    cluster.billboard.verticalOrigin = C.VerticalOrigin.CENTER
    cluster.billboard.disableDepthTestDistance = ALWAYS
    cluster.billboard.heightReference = C.HeightReference.CLAMP_TO_GROUND
    cluster.billboard.id = { munimCluster: clusteringId, ids: entities.map((e) => (e._munim ? e._munim.id : e.id)), position: cluster.billboard.position }
  }

  function markerKey(m, selected) {
    return JSON.stringify([m.style, m.color, m.glyph, m.glyphSymbol, m.glyphColor, m.imageUri, m.imageSize, m.borderColor, m.borderWidth, m.badges, m.title, selected])
  }

  async function updateMarkerImage(entry) {
    const m = entry.spec
    const selected = selectedId === m.id
    const key = markerKey(m, selected)
    if (key === entry.imageKey) return
    entry.imageKey = key
    const result = await markerImage(m, selected)
    if (entry.imageKey !== key || !entry.entity) return
    const billboard = entry.entity.billboard
    billboard.image = result.image
    billboard.width = result.width
    billboard.height = result.height
    const ax = M.num(m.anchorX, -1) >= 0 ? m.anchorX : result.anchor[0]
    const ay = M.num(m.anchorY, -1) >= 0 ? m.anchorY : result.anchor[1]
    billboard.horizontalOrigin = C.HorizontalOrigin.CENTER
    billboard.verticalOrigin = C.VerticalOrigin.CENTER
    billboard.pixelOffset = new C.Cartesian2((0.5 - ax) * result.width, (0.5 - ay) * result.height)
    entry.size = result
    entry.anchor = [ax, ay]
    M.requestRender()
  }

  function titleLabel(m) {
    const style = M.norm(m.style || 'pin')
    if (!m.title || style === 'label' || M.norm(m.titleVisibility) === 'hidden') return undefined
    const subtitle = m.subtitle && M.norm(m.subtitleVisibility) === 'visible' ? `\n${m.subtitle}` : ''
    return {
      text: m.title + subtitle,
      font: `600 12px ${FONT}`,
      fillColor: C.Color.fromCssColorString('#1c1c1e'),
      outlineColor: C.Color.WHITE,
      outlineWidth: 3,
      style: C.LabelStyle.FILL_AND_OUTLINE,
      verticalOrigin: C.VerticalOrigin.TOP,
      horizontalOrigin: C.HorizontalOrigin.CENTER,
      pixelOffset: new C.Cartesian2(0, style === 'dot' ? 10 : 4),
      heightReference: C.HeightReference.CLAMP_TO_GROUND,
      disableDepthTestDistance: ALWAYS,
      showBackground: false,
    }
  }

  function setMarkers(list) {
    const viewer = M.viewer
    const next = new Map()
    for (const m of list || []) next.set(m.id, m)
    for (const [id, entry] of markers) {
      const m = next.get(id)
      if (!m || (m.clusteringId || '') !== (entry.spec.clusteringId || '')) {
        entry.source.entities.remove(entry.entity)
        markers.delete(id)
        if (selectedId === id) hideCallout()
      }
    }
    for (const [id, m] of next) {
      let entry = markers.get(id)
      const position = C.Cartesian3.fromDegrees(m.longitude, m.latitude)
      if (!entry) {
        const source = markerSource(m.clusteringId)
        const entity = source.entities.add({
          id: `munim-marker:${id}`,
          position,
          billboard: { heightReference: C.HeightReference.CLAMP_TO_GROUND, disableDepthTestDistance: ALWAYS, image: pinBuilder.fromColor(C.Color.TRANSPARENT, 1) },
        })
        entity._munim = { kind: 'marker', id }
        entry = { spec: m, entity, source, imageKey: '' }
        markers.set(id, entry)
      } else if (!entry.dragging) {
        entry.entity.position = position
      }
      entry.spec = m
      const e = entry.entity
      e.show = m.visible !== false
      e.billboard.color = new C.Color(1, 1, 1, M.num(m.opacity, 1))
      e.billboard.eyeOffset = new C.Cartesian3(0, 0, -M.num(m.zIndex, 0))
      e.label = titleLabel(m)
      e.name = m.title || id
      e.description = m.subtitle || ''
      updateMarkerImage(entry).catch((err) => M.error(`marker ${id}`, err))
    }
    // Drop empty cluster sources.
    for (const [key, source] of markerSources) {
      if (source.entities.values.length === 0 && key) {
        viewer.dataSources.remove(source, true)
        markerSources.delete(key)
      }
    }
    if (selectedId) updateCallout()
  }

  M.markerEntry = (id) => markers.get(id)

  M.selectMarker = function (id, fromTap) {
    if (selectedId === id) return
    if (selectedId) M.deselectMarker(true)
    const entry = markers.get(id)
    if (!entry) return
    selectedId = id
    updateMarkerImage(entry)
    if (entry.spec.calloutEnabled !== false && (entry.spec.title || entry.spec.subtitle)) showCallout(entry)
    if (fromTap) M.emit('markerPress', { id })
  }

  M.deselectMarker = function (notify) {
    if (!selectedId) return
    const id = selectedId
    selectedId = ''
    const entry = markers.get(id)
    if (entry) updateMarkerImage(entry)
    hideCallout()
    if (notify) M.emit('markerDeselect', { id })
  }

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
    el.addEventListener('click', () => M.emit('calloutPress', { id: m.id }))
    document.getElementById('munim-ui').appendChild(el)
    callout = { el, id: m.id }
    updateCallout()
  }

  function hideCallout() {
    if (callout) callout.el.remove()
    callout = undefined
  }

  function updateCallout() {
    if (!callout || !M.viewer) return
    const entry = markers.get(callout.id)
    if (!entry) return hideCallout()
    const scene = M.viewer.scene
    const position = entry.entity.position.getValue(M.viewer.clock.currentTime)
    const carto = C.Cartographic.fromCartesian(position)
    const ground = M.groundHeight(M.toDeg(carto.latitude), M.toDeg(carto.longitude))
    const p = C.SceneTransforms.worldToWindowCoordinates(scene, C.Cartesian3.fromRadians(carto.longitude, carto.latitude, ground))
    if (!p) {
      callout.el.style.display = 'none'
      return
    }
    const size = entry.size || { height: 40 }
    const ay = entry.anchor ? entry.anchor[1] : 1
    callout.el.style.display = 'flex'
    callout.el.style.left = `${p.x}px`
    callout.el.style.top = `${p.y - size.height * ay - 8}px`
  }

  M.viewerHooks.push((viewer) => viewer.scene.postRender.addEventListener(updateCallout))
  M.destroyHooks.push(() => {
    markerSources.clear()
    markers = new Map()
    selectedId = ''
    hideCallout()
    shapes = undefined
    shapeEntities = new Map()
  })

  // MARK: Shapes

  let shapes
  let shapeEntities = new Map() // `${kind}:${id}` -> [entities]

  function shapeSource() {
    if (!shapes) {
      shapes = new C.CustomDataSource('munim-shapes')
      M.viewer.dataSources.add(shapes)
    }
    return shapes
  }

  /** A dash pattern `"10,5"` (points on, off, …) as Cesium's 16-bit pattern and length. */
  function dash(pattern) {
    const parts = String(pattern || '')
      .split(/[ ,]+/)
      .map(Number)
      .filter((n) => n > 0)
    if (parts.length < 2) return undefined
    const total = parts.reduce((a, b) => a + b, 0)
    let bits = 0
    for (let i = 0; i < 16; i++) {
      let at = ((i + 0.5) / 16) * total
      let on = true
      for (const len of parts) {
        if (at < len) break
        at -= len
        on = !on
      }
      if (on) bits |= 1 << (15 - i)
    }
    return { dashLength: total, dashPattern: bits }
  }

  function gradientImage(colors, locations) {
    const c = document.createElement('canvas')
    c.width = 256
    c.height = 4
    const ctx = c.getContext('2d')
    const g = ctx.createLinearGradient(0, 0, 256, 0)
    colors.forEach((color, i) => {
      const at = locations && locations[i] != null ? locations[i] : i / Math.max(1, colors.length - 1)
      g.addColorStop(Math.max(0, Math.min(1, at)), M.css(color))
    })
    ctx.fillStyle = g
    ctx.fillRect(0, 0, 256, 4)
    return c
  }

  function lineMaterial(color, width, pattern, gradient) {
    if (gradient) return new C.ImageMaterialProperty({ image: gradient, transparent: true })
    const d = dash(pattern)
    if (d) return new C.PolylineDashMaterialProperty({ color, dashLength: d.dashLength, dashPattern: d.dashPattern })
    return new C.ColorMaterialProperty(color)
  }

  /** The part of a line between two fractions of its length. */
  function trim(coords, start, end) {
    if ((start <= 0 && end >= 1) || coords.length < 2) return coords
    const geodesic = new C.EllipsoidGeodesic()
    const lengths = [0]
    for (let i = 1; i < coords.length; i++) {
      geodesic.setEndPoints(C.Cartographic.fromDegrees(coords[i - 1].longitude, coords[i - 1].latitude), C.Cartographic.fromDegrees(coords[i].longitude, coords[i].latitude))
      lengths.push(lengths[i - 1] + geodesic.surfaceDistance)
    }
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

  function positions(coords) {
    return coords.map((c) => C.Cartesian3.fromDegrees(c.longitude, c.latitude))
  }

  function strokeEntity(id, kind, coords, color, width, pattern, zIndex, closed) {
    const list = closed && coords.length > 2 ? [...coords, coords[0]] : coords
    if (list.length < 2 || !(width > 0)) return undefined
    return {
      id: `munim-${kind}-stroke:${id}:${Math.random().toString(36).slice(2, 7)}`,
      polyline: {
        positions: positions(list),
        width,
        material: lineMaterial(color, width, pattern),
        clampToGround: true,
        zIndex: zIndex || 0,
        arcType: C.ArcType.GEODESIC,
      },
    }
  }

  function setShapes(kind, list) {
    const source = shapeSource()
    for (const [key, entities] of shapeEntities) {
      if (key.startsWith(kind + ':')) {
        for (const e of entities) source.entities.remove(e)
        shapeEntities.delete(key)
      }
    }
    for (const s of list || []) {
      const specs = []
      const zIndex = Math.round(M.num(s.zIndex, 0))
      if (kind === 'polyline') {
        const coords = trim(s.coordinates || [], M.num(s.strokeStart, 0), M.num(s.strokeEnd, 1))
        if (coords.length < 2) continue
        const colors = String(s.strokeColors || '')
          .split(',')
          .map((x) => x.trim())
          .filter(Boolean)
        const locations = String(s.strokeColorLocations || '')
          .split(',')
          .map((x) => x.trim())
          .filter(Boolean)
          .map(Number)
        const gradient = colors.length > 1 ? gradientImage(colors, locations.length === colors.length ? locations : undefined) : undefined
        specs.push({
          id: `munim-polyline:${s.id}`,
          polyline: {
            positions: positions(coords),
            width: M.num(s.strokeWidth, 3),
            material: lineMaterial(M.color(s.strokeColor, '#0A84FF'), s.strokeWidth, s.dashPattern, gradient),
            clampToGround: true,
            zIndex,
            arcType: s.geodesic ? C.ArcType.GEODESIC : C.ArcType.RHUMB,
          },
        })
      } else if (kind === 'polygon') {
        const coords = s.coordinates || []
        if (coords.length < 3) continue
        const holes = (s.holes || []).filter((h) => h.length > 2)
        specs.push({
          id: `munim-polygon:${s.id}`,
          polygon: {
            hierarchy: new C.PolygonHierarchy(positions(coords), holes.map((h) => new C.PolygonHierarchy(positions(h)))),
            material: M.color(s.fillColor, '#0A84FF33'),
            zIndex,
            arcType: C.ArcType.GEODESIC,
          },
        })
        const stroke = M.color(s.strokeColor, '#0A84FF')
        const width = M.num(s.strokeWidth, 1)
        for (const ring of [coords, ...holes]) {
          const e = strokeEntity(s.id, 'polygon', ring, stroke, width, s.dashPattern, zIndex, true)
          if (e) specs.push(e)
        }
      } else if (kind === 'circle') {
        const center = C.Cartesian3.fromDegrees(s.longitude, s.latitude)
        const radius = Math.max(0.1, M.num(s.radius, 100))
        specs.push({
          id: `munim-circle:${s.id}`,
          position: center,
          ellipse: { semiMajorAxis: radius, semiMinorAxis: radius, material: M.color(s.fillColor, '#0A84FF33'), zIndex },
        })
        const ring = []
        for (let i = 0; i < 72; i++) {
          const b = (i / 72) * Math.PI * 2
          const d = radius / 6371008.8
          const lat = M.toRad(s.latitude)
          const lon = M.toRad(s.longitude)
          const la = Math.asin(Math.sin(lat) * Math.cos(d) + Math.cos(lat) * Math.sin(d) * Math.cos(b))
          const lo = lon + Math.atan2(Math.sin(b) * Math.sin(d) * Math.cos(lat), Math.cos(d) - Math.sin(lat) * Math.sin(la))
          ring.push({ latitude: M.toDeg(la), longitude: M.toDeg(lo) })
        }
        const e = strokeEntity(s.id, 'circle', ring, M.color(s.strokeColor, '#0A84FF'), M.num(s.strokeWidth, 1), s.dashPattern, zIndex, true)
        if (e) specs.push(e)
      }
      const entities = specs.map((spec) => {
        const entity = source.entities.add(spec)
        entity._munim = { kind: 'overlay', overlayKind: kind, id: s.id, tappable: s.tappable !== false }
        return entity
      })
      shapeEntities.set(`${kind}:${s.id}`, entities)
    }
  }

  M.on('markers', setMarkers)
  M.on('clusterStyles', () => {
    for (const source of markerSources.values()) source.clustering.pixelRange = source.clustering.pixelRange + 0
  })
  M.on('polylines', (list) => setShapes('polyline', list))
  M.on('polygons', (list) => setShapes('polygon', list))
  M.on('circles', (list) => setShapes('circle', list))

  M.method('selectMarker', (a) => M.selectMarker(a.id, false))
  M.method('deselectMarker', () => M.deselectMarker(false))
  M.method('fitToMarkers', (a) => {
    const ids = a.ids && a.ids.length ? new Set(a.ids) : undefined
    const coords = [...markers.values()].filter((e) => !ids || ids.has(e.spec.id)).map((e) => ({ latitude: e.spec.latitude, longitude: e.spec.longitude }))
    M.fitCoordinates(coords, a.padding, a.animated)
  })

  // MARK: Taps, long presses, dragging

  /** What a tap at a window position hits: munim things first, then anything Cesium drew. */
  M.describePick = function (picked) {
    if (!picked) return undefined
    const id = picked.id
    if (id && id.munimModel !== undefined) return { kind: 'model', id: id.munimModel }
    if (id && id.munimCluster !== undefined) return { kind: 'cluster', clusteringId: id.munimCluster, ids: id.ids, position: id.position }
    if (id instanceof C.Entity) {
      if (id._munim) return Object.assign({ entity: id }, id._munim)
      return { kind: 'entity', entity: id, id: id.id }
    }
    if (picked instanceof C.Cesium3DTileFeature || (picked.getProperty && picked.getPropertyIds)) {
      const properties = {}
      try {
        for (const name of picked.getPropertyIds()) properties[name] = picked.getProperty(name)
      } catch (e) {
        // no properties
      }
      return { kind: 'feature', feature: picked, properties }
    }
    return { kind: 'primitive', primitive: picked.primitive }
  }

  function tapPayload(position) {
    const ground = M.pickGround(position, true)
    const coord = ground ? M.fromCartesian(ground) : null
    return { latitude: coord ? coord.latitude : 0, longitude: coord ? coord.longitude : 0, height: coord ? coord.height : 0, x: position.x, y: position.y }
  }

  function pickEvent(position, what) {
    if (M.options().pickEvents === false) return
    const data = tapPayload(position)
    if (what) {
      data.kind = what.kind
      if (what.id !== undefined) data.id = typeof what.id === 'string' ? what.id : String(what.id)
      if (what.properties) data.properties = what.properties
      if (what.entity && what.entity.properties) {
        try {
          data.properties = what.entity.properties.getValue(M.viewer.clock.currentTime)
        } catch (e) {
          // not plain values
        }
      }
      if (what.entity && what.entity.name) data.name = what.entity.name
    }
    M.emit('provider', { name: 'pick', data })
  }

  function featureTitle(properties) {
    for (const key of ['name', 'name:en', 'Name', 'NAME', 'title', 'elementId', 'id']) {
      if (properties[key] != null && properties[key] !== '') return String(properties[key])
    }
    return ''
  }

  function handleTap(position) {
    const scene = M.viewer.scene
    const what = M.describePick(scene.pick(position))
    pickEvent(position, what)
    if (what && what.kind === 'marker') {
      M.selectMarker(what.id, true)
      return
    }
    if (selectedId) M.deselectMarker(true)
    if (what && what.kind === 'cluster') {
      const p = what.position ? M.fromCartesian(what.position) : tapPayload(position)
      M.emit('clusterPress', { clusteringId: what.clusteringId, markerIds: what.ids.join(','), latitude: p.latitude, longitude: p.longitude })
      return
    }
    if (what && what.kind === 'model') {
      M.emit('modelPress', { id: what.id })
      return
    }
    if (what && what.kind === 'overlay' && what.tappable && M.state.overlayPress) {
      const p = tapPayload(position)
      M.emit('overlayPress', { id: what.id, kind: what.overlayKind, latitude: p.latitude, longitude: p.longitude })
      return
    }
    if (what && what.kind === 'feature' && (M.state.selectableFeatures || []).length) {
      const p = tapPayload(position)
      M.emit('mapFeaturePress', { title: featureTitle(what.properties), latitude: p.latitude, longitude: p.longitude, kind: 'pointOfInterest', category: String(what.properties.building || what.properties.amenity || ''), id: String(what.properties.elementId || what.properties.id || '') })
      return
    }
    if (what && what.kind === 'entity' && M.options().selectEntitiesOnTap !== false) {
      M.viewer.selectedEntity = what.entity
    }
    M.emit('press', tapPayload(position))
  }

  /** The tappable overlay at a point (for `overlayAtPoint`). */
  M.method('overlayAtPoint', (a) => {
    for (const picked of M.viewer.scene.drillPick(M.windowPosition(a.point), 8)) {
      const what = M.describePick(picked)
      if (what && what.kind === 'overlay' && what.tappable) return what.id
    }
    return ''
  })

  M.viewerHooks.push((viewer) => {
    const scene = viewer.scene
    const canvas = scene.canvas
    const handler = new C.ScreenSpaceEventHandler(canvas)
    let suppressUntil = 0
    handler.setInputAction((e) => {
      if (Date.now() < suppressUntil) return
      handleTap(e.position)
    }, C.ScreenSpaceEventType.LEFT_CLICK)

    // Long press: half a second without moving.
    let pressTimer
    let start
    let pointers = 0
    canvas.addEventListener('pointerdown', (ev) => {
      pointers++
      clearTimeout(pressTimer)
      if (pointers > 1) return
      start = { x: ev.offsetX, y: ev.offsetY }
      pressTimer = setTimeout(() => {
        suppressUntil = Date.now() + 700
        M.emit('longPress', tapPayload(new C.Cartesian2(start.x, start.y)))
      }, 500)
    })
    const cancel = (ev) => {
      if (ev.type !== 'pointermove') pointers = Math.max(0, pointers - 1)
      if (ev.type === 'pointermove' && start && Math.hypot(ev.offsetX - start.x, ev.offsetY - start.y) < 8) return
      clearTimeout(pressTimer)
    }
    canvas.addEventListener('pointermove', cancel)
    canvas.addEventListener('pointerup', cancel)
    canvas.addEventListener('pointercancel', cancel)

    // Dragging draggable markers.
    let drag
    handler.setInputAction((e) => {
      const what = M.describePick(scene.pick(e.position))
      if (!what || what.kind !== 'marker') return
      const entry = markers.get(what.id)
      if (!entry || !entry.spec.draggable) return
      drag = { entry, start: e.position, active: false }
      scene.screenSpaceCameraController.enableInputs = false
    }, C.ScreenSpaceEventType.LEFT_DOWN)
    handler.setInputAction((e) => {
      if (!drag) return
      if (!drag.active && C.Cartesian2.distance(e.endPosition, drag.start) < 5) return
      if (!drag.active) {
        drag.active = true
        drag.entry.dragging = true
        clearTimeout(pressTimer)
        const p = M.fromCartesian(drag.entry.entity.position.getValue(viewer.clock.currentTime))
        M.emit('markerDragStart', { id: drag.entry.spec.id, latitude: p.latitude, longitude: p.longitude })
      }
      const ground = M.pickGround(e.endPosition)
      if (ground) {
        drag.entry.entity.position = ground
        M.requestRender()
        const p = M.fromCartesian(ground)
        M.emit('markerDrag', { id: drag.entry.spec.id, latitude: p.latitude, longitude: p.longitude })
      }
    }, C.ScreenSpaceEventType.MOUSE_MOVE)
    handler.setInputAction(() => {
      if (!drag) return
      scene.screenSpaceCameraController.enableInputs = M.options().controller ? M.options().controller.enableInputs !== false : true
      if (drag.active) {
        suppressUntil = Date.now() + 400
        drag.entry.dragging = false
        const p = M.fromCartesian(drag.entry.entity.position.getValue(viewer.clock.currentTime))
        M.emit('markerDragEnd', { id: drag.entry.spec.id, latitude: p.latitude, longitude: p.longitude })
      }
      drag = undefined
    }, C.ScreenSpaceEventType.LEFT_UP)
    M.inputHandler = handler
  })
})()
