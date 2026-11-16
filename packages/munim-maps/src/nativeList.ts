/**
 * Turns a list prop (`markers`, `polylines`, `models`…) into the native
 * structs the map gets, without sending what did not change.
 *
 * Each converted item equal to the one at the same index last time is
 * replaced by that one, and when every item is, the previous array itself
 * comes back. Nitro only sends a prop when it is a different value, so a
 * re-render that rebuilds the same markers (`data.map(…)` in render, a new
 * array from a store) sends nothing to the map: no conversion of thousands
 * of items to native structs and no native diff. When some items changed,
 * the unchanged ones keep their previous objects.
 *
 * Items are converted on every call (an app may change an item in place and
 * pass a new array), so `convert` must be cheap and depend only on the item;
 * make a new list (`deps` in the hook) when what else it reads changes.
 */
export function createNativeList<T, N>(
  convert: (item: T) => N
): (items: readonly T[] | undefined) => N[] {
  let lastItems: readonly T[] | undefined
  let last: N[] = []
  return (items) => {
    // The same array as last time (a re-render with the same prop).
    if (items === lastItems && items !== undefined) return last
    lastItems = items
    const list = items ?? []
    let same = list.length === last.length
    const next: N[] = new Array(list.length)
    for (let i = 0; i < list.length; i++) {
      let value = convert(list[i] as T)
      const previous = last[i]
      if (previous !== undefined && sameNative(previous, value)) {
        value = previous
      } else {
        same = false
      }
      next[i] = value
    }
    if (same) return last
    last = next
    return next
  }
}

/**
 * Deep equality for native structs (plain objects, arrays, strings,
 * numbers, booleans): a tight loop, since it runs over every item of every
 * list on every render.
 */
export function sameNative(a: unknown, b: unknown): boolean {
  if (a === b) return true
  if (
    typeof a !== 'object' ||
    typeof b !== 'object' ||
    a === null ||
    b === null
  ) {
    // NaN equals NaN here: the same value for the map.
    return Number.isNaN(a) && Number.isNaN(b)
  }
  if (Array.isArray(a)) {
    if (!Array.isArray(b) || a.length !== b.length) return false
    for (let i = 0; i < a.length; i++) if (!sameNative(a[i], b[i])) return false
    return true
  }
  if (Array.isArray(b)) return false
  const x = a as Record<string, unknown>
  const y = b as Record<string, unknown>
  let keys = 0
  for (const key in x) {
    if (!sameNative(x[key], y[key])) return false
    keys++
  }
  for (const key in y) {
    if (!(key in x)) return false
    keys--
  }
  return keys === 0
}
