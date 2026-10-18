/**
 * Colours for the native side. Every engine's parser reads `#RRGGBB` and
 * `#RRGGBBAA` (CSS order, alpha last), but not all of them read `rgba()`,
 * `hsl()`, `transparent` or CSS names (MapKit's reads hex only), so
 * JavaScript turns any CSS colour into hex first and every engine gets the
 * same input.
 *
 * No React Native import: this module is pure, so it runs in unit tests.
 */

/** CSS named colours (CSS Color Module Level 4), as `RRGGBB`. */
const NAMED: Record<string, string> = {
  aliceblue: 'F0F8FF',
  antiquewhite: 'FAEBD7',
  aqua: '00FFFF',
  aquamarine: '7FFFD4',
  azure: 'F0FFFF',
  beige: 'F5F5DC',
  bisque: 'FFE4C4',
  black: '000000',
  blanchedalmond: 'FFEBCD',
  blue: '0000FF',
  blueviolet: '8A2BE2',
  brown: 'A52A2A',
  burlywood: 'DEB887',
  cadetblue: '5F9EA0',
  chartreuse: '7FFF00',
  chocolate: 'D2691E',
  coral: 'FF7F50',
  cornflowerblue: '6495ED',
  cornsilk: 'FFF8DC',
  crimson: 'DC143C',
  cyan: '00FFFF',
  darkblue: '00008B',
  darkcyan: '008B8B',
  darkgoldenrod: 'B8860B',
  darkgray: 'A9A9A9',
  darkgreen: '006400',
  darkgrey: 'A9A9A9',
  darkkhaki: 'BDB76B',
  darkmagenta: '8B008B',
  darkolivegreen: '556B2F',
  darkorange: 'FF8C00',
  darkorchid: '9932CC',
  darkred: '8B0000',
  darksalmon: 'E9967A',
  darkseagreen: '8FBC8F',
  darkslateblue: '483D8B',
  darkslategray: '2F4F4F',
  darkslategrey: '2F4F4F',
  darkturquoise: '00CED1',
  darkviolet: '9400D3',
  deeppink: 'FF1493',
  deepskyblue: '00BFFF',
  dimgray: '696969',
  dimgrey: '696969',
  dodgerblue: '1E90FF',
  firebrick: 'B22222',
  floralwhite: 'FFFAF0',
  forestgreen: '228B22',
  fuchsia: 'FF00FF',
  gainsboro: 'DCDCDC',
  ghostwhite: 'F8F8FF',
  gold: 'FFD700',
  goldenrod: 'DAA520',
  gray: '808080',
  green: '008000',
  greenyellow: 'ADFF2F',
  grey: '808080',
  honeydew: 'F0FFF0',
  hotpink: 'FF69B4',
  indianred: 'CD5C5C',
  indigo: '4B0082',
  ivory: 'FFFFF0',
  khaki: 'F0E68C',
  lavender: 'E6E6FA',
  lavenderblush: 'FFF0F5',
  lawngreen: '7CFC00',
  lemonchiffon: 'FFFACD',
  lightblue: 'ADD8E6',
  lightcoral: 'F08080',
  lightcyan: 'E0FFFF',
  lightgoldenrodyellow: 'FAFAD2',
  lightgray: 'D3D3D3',
  lightgreen: '90EE90',
  lightgrey: 'D3D3D3',
  lightpink: 'FFB6C1',
  lightsalmon: 'FFA07A',
  lightseagreen: '20B2AA',
  lightskyblue: '87CEFA',
  lightslategray: '778899',
  lightslategrey: '778899',
  lightsteelblue: 'B0C4DE',
  lightyellow: 'FFFFE0',
  lime: '00FF00',
  limegreen: '32CD32',
  linen: 'FAF0E6',
  magenta: 'FF00FF',
  maroon: '800000',
  mediumaquamarine: '66CDAA',
  mediumblue: '0000CD',
  mediumorchid: 'BA55D3',
  mediumpurple: '9370DB',
  mediumseagreen: '3CB371',
  mediumslateblue: '7B68EE',
  mediumspringgreen: '00FA9A',
  mediumturquoise: '48D1CC',
  mediumvioletred: 'C71585',
  midnightblue: '191970',
  mintcream: 'F5FFFA',
  mistyrose: 'FFE4E1',
  moccasin: 'FFE4B5',
  navajowhite: 'FFDEAD',
  navy: '000080',
  oldlace: 'FDF5E6',
  olive: '808000',
  olivedrab: '6B8E23',
  orange: 'FFA500',
  orangered: 'FF4500',
  orchid: 'DA70D6',
  palegoldenrod: 'EEE8AA',
  palegreen: '98FB98',
  paleturquoise: 'AFEEEE',
  palevioletred: 'DB7093',
  papayawhip: 'FFEFD5',
  peachpuff: 'FFDAB9',
  peru: 'CD853F',
  pink: 'FFC0CB',
  plum: 'DDA0DD',
  powderblue: 'B0E0E6',
  purple: '800080',
  rebeccapurple: '663399',
  red: 'FF0000',
  rosybrown: 'BC8F8F',
  royalblue: '4169E1',
  saddlebrown: '8B4513',
  salmon: 'FA8072',
  sandybrown: 'F4A460',
  seagreen: '2E8B57',
  seashell: 'FFF5EE',
  sienna: 'A0522D',
  silver: 'C0C0C0',
  skyblue: '87CEEB',
  slateblue: '6A5ACD',
  slategray: '708090',
  slategrey: '708090',
  snow: 'FFFAFA',
  springgreen: '00FF7F',
  steelblue: '4682B4',
  tan: 'D2B48C',
  teal: '008080',
  thistle: 'D8BFD8',
  tomato: 'FF6347',
  turquoise: '40E0D0',
  violet: 'EE82EE',
  wheat: 'F5DEB3',
  white: 'FFFFFF',
  whitesmoke: 'F5F5F5',
  yellow: 'FFFF00',
  yellowgreen: '9ACD32',
}

type Rgba = [number, number, number, number]

const clamp = (value: number, min: number, max: number) =>
  Math.min(max, Math.max(min, value))

function number(text: string): number | undefined {
  if (!/^[+-]?(\d+\.?\d*|\.\d+)(e[+-]?\d+)?$/i.test(text)) return undefined
  return Number(text)
}

/** `255`, `100%` → 0...255. */
function channel(text: string): number | undefined {
  if (text.endsWith('%')) {
    const percent = number(text.slice(0, -1))
    return percent == null ? undefined : clamp((percent / 100) * 255, 0, 255)
  }
  const value = number(text)
  return value == null ? undefined : clamp(value, 0, 255)
}

/** `0.5`, `50%` → 0...1. */
function alpha(text: string | undefined): number | undefined {
  if (text == null) return 1
  if (text.endsWith('%')) {
    const percent = number(text.slice(0, -1))
    return percent == null ? undefined : clamp(percent / 100, 0, 1)
  }
  const value = number(text)
  return value == null ? undefined : clamp(value, 0, 1)
}

/** `120`, `120deg`, `0.5turn`, `2rad`, `100grad` → degrees. */
function hue(text: string): number | undefined {
  const match = /^(.*?)(deg|turn|rad|grad)?$/.exec(text)
  const value = match ? number(match[1] ?? '') : undefined
  if (value == null) return undefined
  switch (match?.[2]) {
    case 'turn':
      return value * 360
    case 'rad':
      return (value * 180) / Math.PI
    case 'grad':
      return value * 0.9
    default:
      return value
  }
}

/** `rgb(…)` / `hsl(…)` arguments, comma or space separated, `/ alpha`. */
function args(inside: string): string[] {
  return inside
    .trim()
    .split(/\s*[,/]\s*|\s+/)
    .filter((part) => part.length > 0)
}

function hslToRgb(h: number, s: number, l: number): [number, number, number] {
  const hh = (((h % 360) + 360) % 360) / 360
  const f = (n: number) => {
    const k = (n + hh * 12) % 12
    const a = s * Math.min(l, 1 - l)
    return l - a * Math.max(-1, Math.min(k - 3, 9 - k, 1))
  }
  return [f(0) * 255, f(8) * 255, f(4) * 255]
}

function parse(text: string): Rgba | undefined {
  const value = text.trim().toLowerCase()
  if (value === 'transparent') return [0, 0, 0, 0]
  const named = NAMED[value]
  if (named) return parse(`#${named}`)
  if (value.startsWith('#')) {
    let hex = value.slice(1)
    if (!/^[0-9a-f]+$/.test(hex)) return undefined
    if (hex.length === 3 || hex.length === 4) {
      hex = [...hex].map((digit) => digit + digit).join('')
    }
    if (hex.length !== 6 && hex.length !== 8) return undefined
    const byte = (at: number) => parseInt(hex.slice(at, at + 2), 16)
    return [byte(0), byte(2), byte(4), hex.length === 8 ? byte(6) / 255 : 1]
  }
  const fn = /^(rgba?|hsla?)\((.*)\)$/.exec(value)
  if (!fn) return undefined
  const parts = args(fn[2] ?? '')
  if (parts.length !== 3 && parts.length !== 4) return undefined
  const a = alpha(parts[3])
  if (a == null) return undefined
  if (fn[1]?.startsWith('rgb')) {
    const [r, g, b] = parts.slice(0, 3).map(channel)
    if (r == null || g == null || b == null) return undefined
    return [r, g, b, a]
  }
  const h = hue(parts[0] ?? '')
  const s = parts[1]?.endsWith('%') ? alpha(parts[1]) : undefined
  const l = parts[2]?.endsWith('%') ? alpha(parts[2]) : undefined
  if (h == null || s == null || l == null) return undefined
  const [r, g, b] = hslToRgb(h, s, l)
  return [r, g, b, a]
}

const hex2 = (value: number) =>
  Math.round(clamp(value, 0, 255))
    .toString(16)
    .padStart(2, '0')
    .toUpperCase()

/**
 * Any CSS colour (`#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`, `rgb()`,
 * `rgba()`, `hsl()`, `hsla()`, `transparent`, a CSS name) as `#RRGGBB`, or
 * `#RRGGBBAA` when it is not opaque. `undefined` and `''` give `''` (the
 * engine's default); text that is not a colour is passed on as it is.
 */
export function normalizeColor(color: string | null | undefined): string {
  if (color == null) return ''
  const text = String(color).trim()
  if (text === '') return ''
  const rgba = parse(text)
  if (!rgba) return text
  const [r, g, b, a] = rgba
  const alphaByte = Math.round(a * 255)
  return `#${hex2(r)}${hex2(g)}${hex2(b)}${alphaByte === 255 ? '' : hex2(alphaByte)}`
}

/**
 * `normalizeColor`, or `fallback` when the colour is left out (`undefined`
 * or `null`; `''` stays `''`, the engine's own default).
 */
export function colorOr(
  color: string | null | undefined,
  fallback: string
): string {
  return color == null ? fallback : normalizeColor(color)
}
