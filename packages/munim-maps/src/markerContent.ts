/**
 * Change detection for `MarkerView`: it re-draws its picture when its
 * content changed, not on every React render. Pure (no React Native
 * import), so it runs in unit tests.
 */

const MAX_DEPTH = 24
const MAX_TOKENS = 5000

/** Stable ids for component types (functions and classes), by identity. */
const typeIds = new WeakMap<object, number>()
let nextTypeId = 1

function typeId(type: unknown): string {
  if (typeof type === 'string') return type
  if ((typeof type === 'function' || typeof type === 'object') && type) {
    let id = typeIds.get(type)
    if (id == null) {
      id = nextTypeId++
      typeIds.set(type, id)
    }
    return `#${id}`
  }
  return String(type)
}

function isElement(value: object): value is {
  type: unknown
  key: unknown
  props: Record<string, unknown>
} {
  return (
    '$$typeof' in value &&
    'type' in value &&
    'props' in value &&
    typeof (value as { props: unknown }).props === 'object'
  )
}

function isPlain(value: object): boolean {
  const proto = Object.getPrototypeOf(value)
  return proto === Object.prototype || proto === null
}

// FNV-1a: bit operations are the point.
/* eslint-disable no-bitwise */
class Hasher {
  private hash = 0x811c9dc5
  private tokens = 0
  private path = new Set<object>()
  overflow = false

  private feed(text: string) {
    this.tokens += 1
    if (this.tokens > MAX_TOKENS) {
      this.overflow = true
      return
    }
    let h = this.hash
    for (let i = 0; i < text.length; i++) {
      h ^= text.charCodeAt(i)
      h = Math.imul(h, 0x01000193)
    }
    // A separator, so ['ab', 'c'] and ['a', 'bc'] differ.
    h ^= 0x1f
    this.hash = Math.imul(h, 0x01000193)
  }

  walk(value: unknown, depth: number) {
    if (this.overflow) return
    if (depth > MAX_DEPTH) {
      // Too deep to follow: assume it changed.
      this.overflow = true
      return
    }
    switch (typeof value) {
      case 'undefined':
        return this.feed('u')
      case 'boolean':
        return this.feed(value ? 't' : 'F')
      case 'number':
        return this.feed(`n${value}`)
      case 'bigint':
        return this.feed(`b${value}`)
      case 'string':
        return this.feed(`s${value}`)
      case 'symbol':
        return this.feed('y')
      // Callbacks are new on every render and do not change the picture.
      case 'function':
        return this.feed('f')
    }
    if (value === null) return this.feed('0')
    const object = value as object
    if (this.path.has(object)) return this.feed('cycle')
    this.path.add(object)
    if (Array.isArray(object)) {
      this.feed(`[${object.length}`)
      for (const item of object) this.walk(item, depth + 1)
      this.feed(']')
    } else if (isElement(object)) {
      this.feed(`<${typeId(object.type)}`)
      this.walk(object.key, depth + 1)
      this.walkObject(object.props, depth + 1)
      this.feed('>')
    } else if (object instanceof Date) {
      this.feed(`d${object.getTime()}`)
    } else if (isPlain(object)) {
      this.walkObject(object as Record<string, unknown>, depth)
    } else {
      // A class instance (an Animated value, a store…): what it holds is
      // not part of the render. Its identity is.
      this.feed(`o${typeId(object.constructor)}`)
    }
    this.path.delete(object)
  }

  private walkObject(object: Record<string, unknown>, depth: number) {
    const keys = Object.keys(object).sort()
    this.feed(`{${keys.length}`)
    for (const key of keys) {
      this.feed(key)
      this.walk(object[key], depth + 1)
    }
    this.feed('}')
  }

  result(): number | undefined {
    return this.overflow ? undefined : this.hash >>> 0
  }
}

/* eslint-enable no-bitwise */

/**
 * A number that changes when what a `MarkerView` draws may have changed:
 * a hash of its children as given (element types, keys and props, through
 * nested elements, arrays and plain objects such as `style` and image
 * sources). Callbacks are ignored. `undefined` when the children are too
 * large or deep to hash: treat them as changed.
 *
 * Content that changes without its props changing (state inside a child
 * component, context) is not seen here: `tracksViewChanges` or the
 * `MarkerView` ref's `redraw()` covers it.
 */
export function markerContentKey(children: unknown): number | undefined {
  const hasher = new Hasher()
  hasher.walk(children, 0)
  return hasher.result()
}

/** Deep equality for JSON-like values (the native marker struct). */
export function sameValue(a: unknown, b: unknown): boolean {
  if (Object.is(a, b)) return true
  if (typeof a !== 'object' || typeof b !== 'object' || !a || !b) return false
  if (Array.isArray(a) !== Array.isArray(b)) return false
  if (Array.isArray(a)) {
    const other = b as unknown[]
    return (
      a.length === other.length && a.every((v, i) => sameValue(v, other[i]))
    )
  }
  const ka = Object.keys(a)
  const kb = Object.keys(b)
  if (ka.length !== kb.length) return false
  return ka.every(
    (key) =>
      Object.prototype.hasOwnProperty.call(b, key) &&
      sameValue(
        (a as Record<string, unknown>)[key],
        (b as Record<string, unknown>)[key]
      )
  )
}
