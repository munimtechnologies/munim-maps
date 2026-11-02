const assert = require('node:assert/strict')
const fs = require('node:fs')
const path = require('node:path')
const { test } = require('node:test')

const pages = [
  path.join(__dirname, '../maplibre/page/munim-maplibre/js/shape-tween.js'),
  path.join(__dirname, '../cesium/page/munim-cesium/js/shape-tween.js'),
]
const tween = require(pages[0])

/** A tween on a fake clock: `advance(ms)` runs the frames due. */
function harness() {
  let time = 0
  let pending
  const frames = []
  const t = tween.create((kind, shapes) => frames.push({ kind, shapes }), {
    now: () => time,
    schedule: (fn) => {
      pending = fn
    },
  })
  return {
    t,
    frames,
    advance(ms) {
      time += ms
      const fn = pending
      pending = undefined
      if (fn) fn()
    },
    get scheduled() {
      return pending !== undefined
    },
  }
}

const circle = (radius, extra) =>
  Object.assign(
    {
      id: 'zone',
      latitude: 40,
      longitude: -86,
      radius,
      animationDuration: 1000,
    },
    extra
  )

test('both pages ship the same tween', () => {
  assert.equal(
    fs.readFileSync(pages[0], 'utf8'),
    fs.readFileSync(pages[1], 'utf8')
  )
})

test('a circle glides to a new radius over animationDuration', () => {
  const h = harness()
  assert.equal(h.t.set('circle', [circle(1000)])[0].radius, 1000)
  assert.equal(h.scheduled, false)
  // The new radius starts from the drawn one.
  assert.equal(h.t.set('circle', [circle(500)])[0].radius, 1000)
  h.advance(250)
  assert.equal(h.frames.at(-1).shapes[0].radius, 875)
  h.advance(250)
  assert.equal(h.frames.at(-1).shapes[0].radius, 750)
  h.advance(600)
  assert.equal(h.frames.at(-1).shapes[0].radius, 500)
  assert.equal(h.scheduled, false, 'no frames once it arrives')
})

test('a new target mid-glide starts from where the shape is drawn', () => {
  const h = harness()
  h.t.set('circle', [circle(1000)])
  h.t.set('circle', [circle(0)])
  h.advance(500)
  assert.equal(h.frames.at(-1).shapes[0].radius, 500)
  assert.equal(h.t.set('circle', [circle(1000)])[0].radius, 500)
  h.advance(500)
  assert.equal(h.frames.at(-1).shapes[0].radius, 750)
})

test('the same props again do not restart the glide', () => {
  const h = harness()
  h.t.set('circle', [circle(1000)])
  h.t.set('circle', [circle(0)])
  h.advance(500)
  h.t.set('circle', [circle(0, { fillColor: '#ff000033' })])
  h.advance(250)
  const drawn = h.frames.at(-1).shapes[0]
  assert.equal(drawn.radius, 250)
  assert.equal(drawn.fillColor, '#ff000033', 'style applies at once')
})

test('animationDuration 0 jumps', () => {
  const h = harness()
  h.t.set('circle', [circle(1000, { animationDuration: 0 })])
  assert.equal(
    h.t.set('circle', [circle(10, { animationDuration: 0 })])[0].radius,
    10
  )
  assert.equal(h.scheduled, false)
})

test('a centre glides the short way across the antimeridian', () => {
  assert.equal(tween.lerpLongitude(179, -179, 0.5), 180)
  assert.equal(tween.lerpLongitude(170, -170, 0.75), -175)
  assert.equal(tween.lerpLongitude(-10, 10, 0.5), 0)
})

test('polygons glide pairwise when the vertex counts match, else jump', () => {
  const h = harness()
  const square = (size, count = 4) => ({
    id: 'p',
    animationDuration: 1000,
    coordinates: [
      { latitude: 0, longitude: 0 },
      { latitude: size, longitude: 0 },
      { latitude: size, longitude: size },
      { latitude: 0, longitude: size },
      { latitude: 0, longitude: size / 2 },
    ].slice(0, count),
    holes: [],
  })
  h.t.set('polygon', [square(2)])
  h.t.set('polygon', [square(4)])
  h.advance(500)
  assert.deepEqual(h.frames.at(-1).shapes[0].coordinates[2], {
    latitude: 3,
    longitude: 3,
  })
  h.advance(500)
  // A different vertex count: straight to the new polygon.
  const jumped = h.t.set('polygon', [square(8, 5)])
  assert.equal(jumped[0].coordinates.length, 5)
  assert.equal(jumped[0].coordinates[2].latitude, 8)
})

test('circles and polygons glide independently', () => {
  const h = harness()
  h.t.set('circle', [circle(1000)])
  h.t.set('circle', [circle(0)])
  h.t.set('polygon', [])
  h.advance(500)
  assert.deepEqual(
    h.frames.map((f) => f.kind),
    ['circle']
  )
})
