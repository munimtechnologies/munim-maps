import assert from 'node:assert/strict'
import { registerHooks } from 'node:module'
import { test } from 'node:test'
import type { MapMarker } from '../src/features.ts'

// The sources import each other without extensions (Metro and TypeScript
// resolve them); Node needs `.ts`.
registerHooks({
  resolve(specifier, context, next) {
    try {
      return next(specifier, context)
    } catch (error) {
      if (specifier.startsWith('.')) return next(`${specifier}.ts`, context)
      throw error
    }
  },
})
const { createNativeList } = await import('../src/nativeList.ts')
const { toNativeMarker } = await import('../src/features.ts')

const markers = (count: number, moved = -1): MapMarker[] =>
  Array.from({ length: count }, (_, i) => ({
    id: `m${i}`,
    coordinate: { latitude: 41 + i * 1e-4 + (i === moved ? 0.01 : 0), longitude: -87 },
    title: `Marker ${i}`,
    color: 'tomato',
    badges: [{ text: String(i % 9) }],
    clusteringId: 'all',
  }))

test('a rebuilt list with the same markers is the same array (nothing is sent)', () => {
  const list = createNativeList(toNativeMarker)
  const first = list(markers(100))
  assert.equal(list(markers(100)), first)
  // The same array object again short-circuits.
  const input = markers(100)
  const second = list(input)
  assert.equal(list(input), second)
})

test('one moved marker gives a new array that keeps every other item', () => {
  const list = createNativeList(toNativeMarker)
  const first = list(markers(100))
  const next = list(markers(100, 42))
  assert.notEqual(next, first)
  for (let i = 0; i < 100; i++) {
    if (i === 42) {
      assert.notEqual(next[i], first[i])
      assert.ok(Math.abs(next[i]!.latitude - first[i]!.latitude - 0.01) < 1e-9)
    } else {
      assert.equal(next[i], first[i])
    }
  }
  // Fewer markers: a new array.
  assert.equal(list(markers(99)).length, 99)
  assert.equal(list(undefined).length, 0)
})

test('a marker changed in place in a new array is converted again', () => {
  const list = createNativeList(toNativeMarker)
  const input = markers(3)
  list(input)
  input[1]!.coordinate = { latitude: 1, longitude: 2 }
  const next = list([...input])
  assert.equal(next[1]!.latitude, 1)
})

test('5000 markers re-rendered unchanged send nothing', () => {
  const runs = 20
  let sentBefore = 0
  let sentAfter = 0
  const list = createNativeList(toNativeMarker)
  let previousBefore: unknown
  let previousAfter: unknown
  const inputs = Array.from({ length: runs }, () => markers(5000))
  const t0 = process.hrtime.bigint()
  for (const input of inputs) {
    // Before: useMemo([markers]) mapped every render's new array, and Nitro
    // sent each new array to the map.
    const out = input.map(toNativeMarker)
    if (out !== previousBefore) sentBefore++
    previousBefore = out
  }
  const t1 = process.hrtime.bigint()
  for (const input of inputs) {
    const out = list(input)
    if (out !== previousAfter) sentAfter++
    previousAfter = out
  }
  const t2 = process.hrtime.bigint()
  const ms = (a: bigint, b: bigint) => (Number(b - a) / 1e6 / runs).toFixed(2)
  console.log(
    `# 5000 markers x ${runs} renders: before ${ms(t0, t1)} ms/render in JS, ${sentBefore} arrays sent; ` +
      `after ${ms(t1, t2)} ms/render in JS, ${sentAfter} array sent`
  )
  assert.equal(sentBefore, runs)
  assert.equal(sentAfter, 1)
})
