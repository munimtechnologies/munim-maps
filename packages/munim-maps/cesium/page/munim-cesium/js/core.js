// munim-maps Cesium engine, the web half: the bridge to the native engine
// (CesiumMapEngine.swift / CesiumMapEngine.kt), shared state and helpers.
//
// Native -> web: window.munimCesium.receive(json), messages
//   { t: 'init', ... }               keys, platform, resource base
//   { t: 'set', k: key, v: value }   a prop changed
//   { t: 'call', id, m: name, a: args } a method; answered with 'result'
// Web -> native: postMessage(json), messages
//   { t: 'ready' }                   the page is up, send 'init' and props
//   { t: 'event', n: name, d: data } map events (press, markerPress…)
//   { t: 'cam', s: state }           the camera, when it changed (for the
//                                    native 3D layer and synchronous getters)
//   { t: 'result', id, ok, v | e }   a method's answer
/* global Cesium */
;(function () {
  'use strict'

  const M = (window.munimCesium = window.munimCesium || {})
  M.state = {}
  M.handlers = {} // set handlers: key -> fn(value)
  M.methods = {} // call handlers: name -> fn(args) -> value | Promise
  M.order = [] // keys in the order they are re-applied on a new viewer
  M.viewer = undefined
  M.env = {
    platform: 'web',
    ionToken: '',
    googleKey: '',
    resourceBase: '',
    tileProxy: '',
    density: window.devicePixelRatio || 1,
    appId: 'munim-maps',
  }

  // MARK: Transport

  function post(message) {
    const json = JSON.stringify(message)
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.munim) {
        window.webkit.messageHandlers.munim.postMessage(json)
      } else if (window.MunimAndroid && window.MunimAndroid.postMessage) {
        window.MunimAndroid.postMessage(json)
      } else if (typeof window.munimTestHost === 'function') {
        window.munimTestHost(message)
      }
    } catch (e) {
      // Nothing to tell: the host is gone.
    }
  }
  M.post = post

  M.emit = function (name, data) {
    post({ t: 'event', n: name, d: data === undefined ? {} : data })
  }

  /** Reports an error through the map's `onError`. */
  M.error = function (message, error) {
    const detail = error && error.message ? `: ${error.message}` : error && error.statusCode !== undefined ? `: ${error.toString()} (${error.statusCode})` : error ? `: ${error}` : ''
    M.emit('error', { message: `Cesium: ${message}${detail}` })
  }

  M.receive = function (input) {
    let message = input
    if (typeof input === 'string') {
      try {
        message = JSON.parse(input)
      } catch (e) {
        M.error('bad message from the app', e)
        return
      }
    }
    if (!message || typeof message !== 'object') return
    switch (message.t) {
      case 'init':
        Object.assign(M.env, message.env || {})
        M.start()
        break
      case 'set':
        M.set(message.k, message.v)
        break
      case 'batch':
        for (const m of message.m || []) M.receive(m)
        break
      case 'call':
        M.call(message.id, message.m, message.a || {})
        break
    }
  }

  /** Stores a prop and applies it once there is a viewer. */
  M.set = function (key, value) {
    M.state[key] = value
    if (!M.viewer) return
    const handler = M.handlers[key]
    if (!handler) return
    try {
      handler(value)
    } catch (e) {
      M.error(`could not apply ${key}`, e)
    }
    M.requestRender()
  }

  /** Registers what a prop does; `order` decides re-application order. */
  M.on = function (key, handler) {
    M.handlers[key] = handler
    if (!M.order.includes(key)) M.order.push(key)
  }

  M.method = function (name, fn) {
    M.methods[name] = fn
  }

  M.call = function (id, name, args) {
    const fn = M.methods[name]
    const reply = (ok, value) => post(ok ? { t: 'result', id, ok: true, v: value === undefined ? null : value } : { t: 'result', id, ok: false, e: String(value && value.message ? value.message : value) })
    if (!fn) {
      reply(false, `unknown command "${name}"`)
      return
    }
    if (!M.viewer && name !== 'version') {
      reply(false, 'the map is not ready yet')
      return
    }
    try {
      Promise.resolve(fn(args)).then(
        (value) => {
          M.requestRender()
          reply(true, value)
        },
        (error) => reply(false, error)
      )
    } catch (e) {
      reply(false, e)
    }
  }

  M.requestRender = function () {
    if (M.viewer && !M.viewer.isDestroyed()) M.viewer.scene.requestRender()
  }

  // MARK: Helpers

  const C = Cesium
  M.C = C

  M.toRad = (d) => (d * Math.PI) / 180
  M.toDeg = (r) => (r * 180) / Math.PI

  /** Enum values from Swift (`followWithHeading`, `top-left`) or Kotlin (`FOLLOWWITHHEADING`, `TOP_LEFT`). */
  M.norm = (v) => String(v == null ? '' : v).toLowerCase().replace(/[-_\s]/g, '')

  M.num = (v, fallback) => (typeof v === 'number' && isFinite(v) ? v : fallback)

  /** `#RGB`, `#RRGGBB`, `#RRGGBBAA` or any CSS colour; `fallback` when empty. */
  M.color = function (value, fallback) {
    if (value == null || value === '') return fallback === undefined ? undefined : M.color(fallback)
    if (value instanceof C.Color) return value
    if (Array.isArray(value)) {
      const [r, g, b, a] = value
      const scale = value.some((x) => x > 1) ? 255 : 1
      return new C.Color(r / scale, g / scale, b / scale, a == null ? 1 : a / scale)
    }
    if (typeof value === 'object') {
      if (value.css) return M.color(value.css, fallback)
      if (value.rgba) return M.color(value.rgba, fallback)
      if (value.red != null) return new C.Color(value.red, value.green, value.blue, value.alpha == null ? 1 : value.alpha)
    }
    const s = String(value).trim()
    const hex = /^#([0-9a-f]{3,8})$/i.exec(s)
    if (hex) {
      let h = hex[1]
      if (h.length === 3 || h.length === 4) h = h.split('').map((c) => c + c).join('')
      const n = (i) => parseInt(h.slice(i, i + 2), 16) / 255
      return new C.Color(n(0), n(2), n(4), h.length === 8 ? n(6) : 1)
    }
    const parsed = C.Color.fromCssColorString(s)
    return parsed || (fallback === undefined ? undefined : M.color(fallback))
  }

  M.css = function (value, fallback) {
    const c = M.color(value, fallback)
    return c ? c.toCssColorString() : 'transparent'
  }

  /** A position from `{ latitude, longitude, height | altitude }`, `[lon, lat, h]` or a Cartesian. */
  M.cartesian = function (p, defaultHeight) {
    if (!p) return undefined
    if (p instanceof C.Cartesian3) return p
    if (Array.isArray(p)) return C.Cartesian3.fromDegrees(p[0], p[1], p[2] == null ? defaultHeight || 0 : p[2])
    if (p.x != null && p.y != null && p.z != null) return new C.Cartesian3(p.x, p.y, p.z)
    const height = p.height != null ? p.height : p.altitude != null ? p.altitude : defaultHeight || 0
    return C.Cartesian3.fromDegrees(p.longitude, p.latitude, height)
  }

  M.cartographic = function (p) {
    const c = M.cartesian(p)
    return c ? C.Cartographic.fromCartesian(c) : undefined
  }

  M.fromCartesian = function (cartesian) {
    if (!cartesian) return null
    const c = C.Cartographic.fromCartesian(cartesian)
    if (!c) return null
    return { latitude: M.toDeg(c.latitude), longitude: M.toDeg(c.longitude), height: c.height }
  }

  /** A rectangle from `{ west, south, east, north }` in degrees, or a region. */
  M.rectangle = function (r) {
    if (!r) return undefined
    if (r instanceof C.Rectangle) return r
    if (r.west != null) return C.Rectangle.fromDegrees(r.west, r.south, r.east, r.north)
    if (r.latitudeDelta != null) {
      return C.Rectangle.fromDegrees(r.longitude - r.longitudeDelta / 2, r.latitude - r.latitudeDelta / 2, r.longitude + r.longitudeDelta / 2, r.latitude + r.latitudeDelta / 2)
    }
    return undefined
  }

  M.julian = function (v) {
    if (v == null || v === '') return undefined
    if (v instanceof C.JulianDate) return v
    if (typeof v === 'number') return C.JulianDate.fromDate(new Date(v > 1e11 ? v : v * 1000))
    return C.JulianDate.fromIso8601(String(v))
  }

  M.iso = (julian) => (julian ? C.JulianDate.toIso8601(julian) : null)

  /** Cesium enum value by (case-insensitive, camel or snake) name. */
  M.enumValue = function (Enum, name, fallback) {
    if (name == null || name === '') return fallback
    if (typeof name === 'number') return name
    const wanted = M.norm(name)
    for (const key of Object.keys(Enum)) {
      if (M.norm(key) === wanted) return Enum[key]
    }
    return fallback
  }

  /**
   * Copies plain option values onto a Cesium object, converting colours
   * (keys ending in `color`), positions and nested objects. Unknown keys are
   * set as is, so every public property of the object can be reached.
   */
  M.assign = function (target, options, skip) {
    if (!target || !options) return
    for (const key of Object.keys(options)) {
      if (skip && skip.includes(key)) continue
      const value = options[key]
      if (value === undefined) continue
      try {
        if (/color$/i.test(key) && value != null && typeof value !== 'boolean') {
          target[key] = M.color(value)
        } else if (value && typeof value === 'object' && !Array.isArray(value) && target[key] && typeof target[key] === 'object' && !(target[key] instanceof C.Color)) {
          if (value.x != null && target[key] instanceof C.Cartesian3) target[key] = new C.Cartesian3(value.x, value.y, value.z)
          else if (value.x != null && target[key] instanceof C.Cartesian2) target[key] = new C.Cartesian2(value.x, value.y)
          else M.assign(target[key], value)
        } else {
          target[key] = value
        }
      } catch (e) {
        M.error(`could not set ${key}`, e)
      }
    }
  }

  /** Converts known value shapes in Cesium constructor options. */
  M.convertOptions = function (options) {
    if (!options || typeof options !== 'object') return options
    const out = Array.isArray(options) ? [] : {}
    for (const key of Object.keys(options)) {
      const value = options[key]
      if (value == null) {
        out[key] = value
      } else if (/color$/i.test(key) && typeof value !== 'boolean') {
        out[key] = M.color(value)
      } else if (/rectangle$/i.test(key) && typeof value === 'object') {
        out[key] = M.rectangle(value)
      } else if (key === 'heightReference') {
        out[key] = M.enumValue(C.HeightReference, value, C.HeightReference.NONE)
      } else if (key === 'classificationType') {
        out[key] = M.enumValue(C.ClassificationType, value, C.ClassificationType.BOTH)
      } else if (key === 'shadows') {
        out[key] = typeof value === 'boolean' ? (value ? C.ShadowMode.ENABLED : C.ShadowMode.DISABLED) : M.enumValue(C.ShadowMode, value, C.ShadowMode.ENABLED)
      } else if (key === 'splitDirection') {
        out[key] = M.enumValue(C.SplitDirection, value, C.SplitDirection.NONE)
      } else if (key === 'colorBlendMode') {
        out[key] = M.enumValue(C.Cesium3DTileColorBlendMode || C.ColorBlendMode, value)
      } else if (key === 'tilingScheme') {
        out[key] = M.norm(value) === 'geographic' ? new C.GeographicTilingScheme() : new C.WebMercatorTilingScheme()
      } else if (key === 'distanceDisplayCondition' && typeof value === 'object') {
        out[key] = new C.DistanceDisplayCondition(value.near || 0, value.far == null ? Number.POSITIVE_INFINITY : value.far)
      } else if (key === 'scaleByDistance' || key === 'translucencyByDistance' || key === 'pixelOffsetScaleByDistance') {
        out[key] = new C.NearFarScalar(value.near, value.nearValue, value.far, value.farValue)
      } else if (key === 'credit' && typeof value === 'string') {
        out[key] = value
      } else if (key === 'modelMatrix' && typeof value === 'object' && !Array.isArray(value)) {
        out[key] = C.Transforms.eastNorthUpToFixedFrame(M.cartesian(value))
      } else if (typeof value === 'object' && !Array.isArray(value) && value.latitude != null && value.longitude != null && /position|center|origin|destination/i.test(key)) {
        out[key] = M.cartesian(value)
      } else {
        out[key] = value
      }
    }
    return out
  }

  /**
   * A URL Cesium can load: data and blob as is; https as is, except GLB
   * models, which go through the app (kept on the device after the first
   * load, and same-origin); anything else (file paths, Android resources,
   * Metro's http) through the app.
   */
  M.resource = function (uri) {
    if (!uri) return uri
    const s = String(uri)
    if (/^https:/i.test(s)) {
      if (M.env.resourceBase && /\.glb([?#]|$)/i.test(s)) return M.env.resourceBase + encodeURIComponent(s)
      return s
    }
    if (/^(data:|blob:)/i.test(s)) return s
    if (/^(Cesium\/|js\/|\.\/)/.test(s)) return s
    if (!M.env.resourceBase) return s
    return M.env.resourceBase + encodeURIComponent(s)
  }

  /** An https tile template, through the app's tile proxy when it has one (iOS: identifies the app to tile servers). */
  M.tileUrl = function (template) {
    if (!M.env.tileProxy || !/^https:\/\//i.test(template)) return template
    return M.env.tileProxy + template.replace(/^https:\/\//i, '')
  }

  M.later = (fn) => setTimeout(fn, 0)

  M.debounce = function (fn, ms) {
    let timer
    return function () {
      clearTimeout(timer)
      const args = arguments
      timer = setTimeout(() => fn.apply(null, args), ms)
    }
  }

  /** Points (CSS pixels) to a Cartesian2 window position. */
  M.windowPosition = (p) => new C.Cartesian2(p.x, p.y)

  M.isDark = function () {
    const scheme = M.norm(M.state.colorScheme)
    if (scheme === 'dark') return true
    if (scheme === 'light') return false
    return !!(window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches)
  }
})()
