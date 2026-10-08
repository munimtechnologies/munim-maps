// munim-maps MapLibre GL JS renderer, the web half: the bridge to the native
// engine (MapLibreWebEngine.swift / MapLibreWebEngine.kt), shared state and
// helpers. The protocol is the Cesium engine's:
//
// Native -> web: window.munimMapLibre.receive(json), messages
//   { t: 'init', env }               platform, resource base, default style
//   { t: 'set', k: key, v: value }   a prop changed
//   { t: 'call', id, m: name, a: args } a method; answered with 'result'
//   { t: 'batch', m: [messages] }
// Web -> native: postMessage(json), messages
//   { t: 'ready' }                   the page is up: send props, then 'init'
//   { t: 'event', n: name, d: data } map events (press, markerPress…)
//   { t: 'cam', s: state }           the camera when it changed (synchronous
//                                    getters and the native 3D layer)
//   { t: 'result', id, ok, v | e }   a method's answer
/* global maplibregl */
;(function () {
  'use strict'

  const M = (window.munimMapLibre = window.munimMapLibre || {})
  M.state = {}
  M.handlers = {} // set handlers: key -> fn(value)
  M.methods = {} // call handlers: name -> fn(args) -> value | Promise
  M.order = [] // keys in the order they are re-applied on a new map
  M.map = undefined
  M.mapHooks = [] // fn(map) when a map is made
  M.styleHooks = [] // fn(map) after every style load (sources and layers are gone)
  M.destroyHooks = [] // fn() before a map is removed
  M.env = {
    platform: 'web',
    resourceBase: '',
    tileProxy: '',
    density: window.devicePixelRatio || 1,
    appId: 'munim-maps',
    defaultStyleUrl: '',
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
      // The host is gone.
    }
  }
  M.post = post

  M.emit = function (name, data) {
    post({ t: 'event', n: name, d: data === undefined ? {} : data })
  }

  /** A MapLibre-only event (`onProviderEvent`). */
  M.providerEvent = function (name, data) {
    M.emit('provider', { name, data: data === undefined ? {} : data })
  }

  /** Reports an error through the map's `onError`. */
  M.error = function (message, error) {
    const detail = error && error.message ? `: ${error.message}` : error ? `: ${error}` : ''
    M.emit('error', { message: `MapLibre GL JS: ${message}${detail}` })
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

  /** Stores a prop and applies it once there is a map. */
  M.set = function (key, value) {
    M.state[key] = value
    if (!M.map) return
    const handler = M.handlers[key]
    if (!handler) return
    try {
      handler(value)
    } catch (e) {
      M.error(`could not apply ${key}`, e)
    }
    M.repaint()
  }

  /** Registers what a prop does. */
  M.on = function (key, handler) {
    M.handlers[key] = handler
    if (!M.order.includes(key)) M.order.push(key)
  }

  M.method = function (name, fn) {
    M.methods[name] = fn
  }

  M.call = function (id, name, args) {
    const fn = M.methods[name]
    const reply = (ok, value) => {
      if (!ok) return post({ t: 'result', id, ok: false, e: String(value && value.message ? value.message : value) })
      // GL JS setters return the map (not JSON): answer null for anything that is not data.
      let v = value === undefined ? null : value
      try {
        JSON.stringify(v)
      } catch (e) {
        v = null
      }
      post({ t: 'result', id, ok: true, v })
    }
    if (!fn) {
      reply(false, `MapLibre GL JS has no command "${name}"`)
      return
    }
    if (!M.map && name !== 'version') {
      reply(false, 'the map is not ready yet')
      return
    }
    try {
      Promise.resolve(fn(args)).then(
        (value) => {
          M.repaint()
          reply(true, value)
        },
        (error) => reply(false, error)
      )
    } catch (e) {
      reply(false, e)
    }
  }

  M.repaint = function () {
    if (M.map) M.map.triggerRepaint()
  }

  // MARK: Helpers

  M.toRad = (d) => (d * Math.PI) / 180
  M.toDeg = (r) => (r * 180) / Math.PI

  /** Enum values from Swift (`followWithHeading`, `top-left`) or Kotlin (`FOLLOWWITHHEADING`, `TOP_LEFT`). */
  M.norm = (v) => String(v == null ? '' : v).toLowerCase().replace(/[-_\s]/g, '')

  M.num = (v, fallback) => (typeof v === 'number' && isFinite(v) ? v : fallback)

  M.options = () => M.state.options || {}

  /** `{ r, g, b, a }` (0…1) from `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA` or a CSS colour. */
  M.rgba = function (value, fallback) {
    if (value == null || value === '') return fallback === undefined ? undefined : M.rgba(fallback)
    if (typeof value === 'object' && value.r != null) return value
    const s = String(value).trim()
    const hex = /^#([0-9a-f]{3,8})$/i.exec(s)
    if (hex) {
      let h = hex[1]
      if (h.length === 3 || h.length === 4) h = h.split('').map((c) => c + c).join('')
      const n = (i) => parseInt(h.slice(i, i + 2), 16) / 255
      return { r: n(0), g: n(2), b: n(4), a: h.length === 8 ? n(6) : 1 }
    }
    const ctx = M.rgba.ctx || (M.rgba.ctx = document.createElement('canvas').getContext('2d'))
    ctx.fillStyle = '#000'
    ctx.fillStyle = s
    const parsed = ctx.fillStyle
    const m = /^#([0-9a-f]{6})$/i.exec(parsed)
    if (m) return M.rgba(parsed)
    const rgba = /rgba?\(([^)]+)\)/.exec(parsed)
    if (rgba) {
      const p = rgba[1].split(',').map((x) => parseFloat(x))
      return { r: p[0] / 255, g: p[1] / 255, b: p[2] / 255, a: p[3] == null ? 1 : p[3] }
    }
    return fallback === undefined ? undefined : M.rgba(fallback)
  }

  /** A CSS colour (`rgba(…)`) for any colour munim accepts; `fallback` when empty. */
  M.css = function (value, fallback) {
    const c = M.rgba(value, fallback)
    if (!c) return 'transparent'
    return `rgba(${Math.round(c.r * 255)},${Math.round(c.g * 255)},${Math.round(c.b * 255)},${+c.a.toFixed(3)})`
  }

  /** Opacity of a colour (0…1). */
  M.alpha = (value, fallback) => {
    const c = M.rgba(value, fallback)
    return c ? c.a : 1
  }

  /** The colour without its alpha, as `rgb(…)`. */
  M.opaque = function (value, fallback) {
    const c = M.rgba(value, fallback)
    if (!c) return 'rgb(0,0,0)'
    return `rgb(${Math.round(c.r * 255)},${Math.round(c.g * 255)},${Math.round(c.b * 255)})`
  }

  /**
   * A URL the page can load: data and blob as is; https as is, except glTF
   * models (kept on the device after the first load, through the app);
   * anything else (file paths, Android resources, Metro's http) through the app.
   */
  M.resource = function (uri) {
    if (!uri) return uri
    const s = String(uri)
    if (/^https:/i.test(s)) {
      if (M.env.resourceBase && /\.(glb|gltf)([?#]|$)/i.test(s)) return M.env.resourceBase + encodeURIComponent(s)
      return s
    }
    if (/^(data:|blob:)/i.test(s)) return s
    if (/^(maplibre-gl\/|three\/|js\/|\.\/)/.test(s)) return s
    if (!M.env.resourceBase) return s
    return M.env.resourceBase + encodeURIComponent(s)
  }

  /** An https tile URL through the app's tile proxy when it has one (iOS: identifies the app to tile servers). */
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

  M.isDark = function () {
    const scheme = M.norm(M.state.colorScheme)
    if (scheme === 'dark') return true
    if (scheme === 'light') return false
    return !!(window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches)
  }

  /** `[lng, lat]` from a munim coordinate. */
  M.lngLat = (c) => [c.longitude, c.latitude]

  M.wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

  /**
   * Whether the style is parsed (sources and layers can be added). GL JS's
   * `isStyleLoaded()` also waits for every tile, so it is false right after
   * `style.load`.
   */
  M.styleLoaded = (map = M.map) => !!(map && map.style && map.style._loaded)

  /** Resolves when the map has finished loading its style. */
  M.styleReady = function () {
    const map = M.map
    if (!map) return Promise.reject(new Error('no map'))
    if (M.styleLoaded(map)) return Promise.resolve()
    return new Promise((resolve) => {
      const check = () => {
        if (!M.map || M.map !== map) return resolve()
        if (M.styleLoaded(map)) {
          map.off('styledata', check)
          resolve()
        }
      }
      map.on('styledata', check)
      setTimeout(check, 50)
    })
  }

  M.version = () => (window.maplibregl ? maplibregl.getVersion() : '')
})()
