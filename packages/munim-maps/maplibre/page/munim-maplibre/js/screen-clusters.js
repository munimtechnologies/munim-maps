// Screen-space clustering for the GL JS page's DOM markers, like MapKit's:
// markers closer than `radius` points merge. Greedy, in list order: each
// marker not yet taken gathers every marker not yet taken within `radius` of
// it. A grid of `radius`-sized cells finds the neighbours, so a map with
// thousands of markers clusters in about linear time (the plain double loop
// it replaces compared every pair). The result is the same as the double
// loop's (test/screen-clusters.test.js).
;(function (root) {
  'use strict'

  /**
   * `points`: `{ x, y }[]` in screen points. Returns the groups of two or
   * more, each a list of indexes into `points` in list order.
   */
  function cluster(points, radius) {
    const size = radius > 0 ? radius : 44
    const cells = new Map()
    const key = (cx, cy) => cx * 73856093 + cy * 19349663
    const cellOf = new Array(points.length)
    for (let i = 0; i < points.length; i++) {
      const p = points[i]
      const cx = Math.floor(p.x / size)
      const cy = Math.floor(p.y / size)
      cellOf[i] = [cx, cy]
      const k = key(cx, cy)
      let list = cells.get(k)
      if (!list) cells.set(k, (list = []))
      list.push(i)
    }
    const used = new Uint8Array(points.length)
    const groups = []
    for (let a = 0; a < points.length; a++) {
      if (used[a]) continue
      used[a] = 1
      const pa = points[a]
      const [cx, cy] = cellOf[a]
      const near = []
      for (let dx = -1; dx <= 1; dx++) {
        for (let dy = -1; dy <= 1; dy++) {
          const list = cells.get(key(cx + dx, cy + dy))
          if (!list) continue
          for (const b of list) {
            if (used[b] || b === a) continue
            const pb = points[b]
            // Another cell with the same hash key.
            if (cellOf[b][0] !== cx + dx || cellOf[b][1] !== cy + dy) continue
            if (Math.hypot(pa.x - pb.x, pa.y - pb.y) < size) near.push(b)
          }
        }
      }
      if (!near.length) continue
      near.sort((m, n) => m - n)
      for (const b of near) used[b] = 1
      groups.push([a, ...near])
    }
    return groups
  }

  root.munimScreenClusters = { cluster }
  if (typeof module !== 'undefined' && module.exports) module.exports = root.munimScreenClusters
})(typeof window !== 'undefined' ? window : globalThis)
