const assert = require('node:assert/strict')
const path = require('node:path')
const { test } = require('node:test')

const { cluster } = require(
  path.join(__dirname, '../maplibre/page/munim-maplibre/js/screen-clusters.js')
)

/** The double loop the GL JS page used before: every pair compared. */
function naive(list, radius) {
  const used = new Array(list.length).fill(false)
  const groups = []
  for (let a = 0; a < list.length; a++) {
    if (used[a]) continue
    used[a] = true
    const members = [a]
    for (let b = 0; b < list.length; b++) {
      if (used[b]) continue
      if (Math.hypot(list[a].x - list[b].x, list[a].y - list[b].y) < radius) {
        used[b] = true
        members.push(b)
      }
    }
    if (members.length > 1) groups.push(members)
  }
  return groups
}

/** Deterministic pseudo-random points on a screen. */
function points(count, width, height, seed) {
  let s = seed
  const next = () => (s = (s * 1664525 + 1013904223) % 4294967296) / 4294967296
  return Array.from({ length: count }, () => ({
    x: next() * width,
    y: next() * height,
  }))
}

test('the grid gives the same clusters as comparing every pair', () => {
  for (const [count, seed] of [
    [0, 1],
    [1, 2],
    [50, 3],
    [500, 4],
    [2000, 5],
  ]) {
    const p = points(count, 400, 800, seed)
    assert.deepEqual(cluster(p, 44), naive(p, 44), `${count} points`)
  }
  // Points exactly on cell edges and off screen, and NaN (behind the globe).
  const edges = [
    { x: 0, y: 0 },
    { x: 44, y: 0 },
    { x: 43.9, y: 0 },
    { x: -44, y: -44 },
    { x: -0.1, y: 0 },
    { x: NaN, y: NaN },
    { x: 88, y: 88 },
  ]
  assert.deepEqual(cluster(edges, 44), naive(edges, 44))
})

test('clustering 5000 markers is fast (grid vs every pair)', () => {
  const p = points(5000, 1200, 2400, 7)
  const time = (fn) => {
    const start = process.hrtime.bigint()
    fn()
    return Number(process.hrtime.bigint() - start) / 1e6
  }
  time(() => cluster(p, 44))
  time(() => naive(p, 44))
  const grid = Math.min(...[0, 1, 2].map(() => time(() => cluster(p, 44))))
  const pairs = Math.min(...[0, 1, 2].map(() => time(() => naive(p, 44))))
  console.log(
    `# 5000 markers: grid ${grid.toFixed(1)} ms, every pair ${pairs.toFixed(1)} ms`
  )
  assert.ok(grid < pairs, `grid ${grid} ms should beat every pair ${pairs} ms`)
})
