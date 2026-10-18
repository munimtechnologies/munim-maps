import assert from 'node:assert/strict'
import { test } from 'node:test'
import { markerContentKey, sameValue } from '../src/markerContent.ts'

// React elements as React makes them, without importing React.
const element = (
  type: unknown,
  props: Record<string, unknown>,
  key: string | null = null
) => ({
  $$typeof: Symbol.for('react.transitional.element'),
  type,
  key,
  props,
})

function Avatar() {}
function Badge() {}

test('the same children give the same key, render after render', () => {
  const make = () =>
    element(Avatar, {
      source: { uri: 'https://example.com/a.png' },
      style: { width: 40, height: 40 },
      onLoad: () => {},
      children: [element('Text', { children: '3' }), null, false],
    })
  assert.equal(markerContentKey(make()), markerContentKey(make()))
})

test('a changed prop, text, image source, type or key changes it', () => {
  const base = markerContentKey(element(Avatar, { uri: 'a', children: 'x' }))
  assert.notEqual(
    base,
    markerContentKey(element(Avatar, { uri: 'b', children: 'x' }))
  )
  assert.notEqual(
    base,
    markerContentKey(element(Avatar, { uri: 'a', children: 'y' }))
  )
  assert.notEqual(
    base,
    markerContentKey(element(Badge, { uri: 'a', children: 'x' }))
  )
  assert.notEqual(
    base,
    markerContentKey(element(Avatar, { uri: 'a', children: 'x' }, 'k'))
  )
  assert.notEqual(
    markerContentKey(element('Image', { source: { uri: 'a' } })),
    markerContentKey(element('Image', { source: { uri: 'b' } }))
  )
  assert.notEqual(
    markerContentKey(element('View', { style: [{ opacity: 1 }] })),
    markerContentKey(element('View', { style: [{ opacity: 0.5 }] }))
  )
})

test('callbacks do not change it', () => {
  assert.equal(
    markerContentKey(element('View', { onPress: () => 1 })),
    markerContentKey(element('View', { onPress: () => 2 }))
  )
})

test('cycles and huge trees do not hang', () => {
  const cyclic: Record<string, unknown> = { a: 1 }
  cyclic.self = cyclic
  assert.equal(
    typeof markerContentKey(element('View', { data: cyclic })),
    'number'
  )
  const huge = Array.from({ length: 10_000 }, (_, i) =>
    element('Text', { children: String(i) })
  )
  assert.equal(markerContentKey(huge), undefined)
  let deep: unknown = 'leaf'
  for (let i = 0; i < 100; i++) deep = element('View', { children: deep })
  assert.equal(markerContentKey(deep), undefined)
})

test('class instances count by identity of their class, not their contents', () => {
  class Value {
    v: number
    constructor(v: number) {
      this.v = v
    }
  }
  assert.equal(
    markerContentKey(element('View', { value: new Value(1) })),
    markerContentKey(element('View', { value: new Value(2) }))
  )
})

test('sameValue compares JSON-like values deeply', () => {
  const marker = { id: 'a', badges: [{ text: '1' }], left: { kind: 'none' } }
  assert.ok(
    sameValue(marker, {
      id: 'a',
      badges: [{ text: '1' }],
      left: { kind: 'none' },
    })
  )
  assert.ok(
    !sameValue(marker, {
      id: 'a',
      badges: [{ text: '2' }],
      left: { kind: 'none' },
    })
  )
  assert.ok(!sameValue(marker, { id: 'a', badges: [], left: { kind: 'none' } }))
  assert.ok(!sameValue({ a: 1 }, { a: 1, b: 2 }))
  assert.ok(sameValue(Number.NaN, Number.NaN))
})
