import Foundation
import SceneKit

// Detailed vehicles for map markers, built from lofted cross-sections.
// Conventions: metres, base on y = 0, front faces -Z (north at heading 0),
// x to the right. Materials named "paint" are recoloured at runtime by
// munim-maps' `tint`.

typealias V3 = SIMD3<Float>

// MARK: Materials

func color(_ hex: UInt32) -> NSColor {
  NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
          blue: CGFloat(hex & 255) / 255, alpha: 1)
}

func material(_ name: String, _ hex: UInt32, metal: CGFloat = 0, rough: CGFloat = 0.5,
              emit: Bool = false) -> SCNMaterial {
  let m = SCNMaterial()
  m.name = name
  m.lightingModel = .physicallyBased
  m.diffuse.contents = color(hex)
  m.metalness.contents = metal
  m.roughness.contents = rough
  if emit { m.emission.contents = color(hex) }
  m.isDoubleSided = false
  return m
}

func paint(_ hex: UInt32) -> SCNMaterial { material("paint", hex, metal: 0.35, rough: 0.28) }
let glass = material("glass", 0x1B2633, metal: 0.6, rough: 0.08)
let tyre = material("tyre", 0x18181A, rough: 0.92)
let rim = material("rim", 0xC9CDD2, metal: 0.95, rough: 0.22)
let chrome = material("chrome", 0xE6E8EB, metal: 1, rough: 0.12)
let black = material("trim", 0x202124, rough: 0.6)
let plastic = material("plastic", 0x3A3B3E, rough: 0.55)
let headlight = material("headlight", 0xFFF6D8, rough: 0.2, emit: true)
let taillight = material("taillight", 0xE0182D, rough: 0.3, emit: true)
let amber = material("indicator", 0xFFA21F, rough: 0.3, emit: true)
let plate = material("plate", 0xF4F4F0, rough: 0.5)
let white = material("white", 0xF4F5F7, metal: 0.2, rough: 0.35)
let rubber = material("rubber", 0x2A2A2C, rough: 0.85)
let leather = material("leather", 0x2B211C, rough: 0.7)
let wood = material("wood", 0xA9744F, rough: 0.6)
let sailcloth: SCNMaterial = {
  let m = material("sail", 0xF7F5EE, rough: 0.8)
  m.isDoubleSided = true
  m.emission.contents = color(0x55544F) // sails stay bright when lit from behind
  return m
}()


// MARK: Mesh primitives
// SceneKit's parametric shapes do not survive USD export reliably, so every
// part is built as a plain mesh.

func meshGeometry(_ positions: [V3], _ normals: [V3], _ indices: [UInt32]) -> SCNGeometry {
  let mesh = Mesh()
  mesh.positions = positions; mesh.normals = normals; mesh.indices = indices
  return mesh.geometry(black)
}

func BoxMesh(width: CGFloat, height: CGFloat, length: CGFloat, chamferRadius: CGFloat = 0) -> SCNGeometry {
  let hx = Float(width) / 2, hy = Float(height) / 2, hz = Float(length) / 2
  var p: [V3] = [], n: [V3] = [], idx: [UInt32] = []
  let faces: [(V3, V3, V3)] = [ // normal, u, v
    (V3(1, 0, 0), V3(0, 0, -1), V3(0, 1, 0)), (V3(-1, 0, 0), V3(0, 0, 1), V3(0, 1, 0)),
    (V3(0, 1, 0), V3(1, 0, 0), V3(0, 0, -1)), (V3(0, -1, 0), V3(1, 0, 0), V3(0, 0, 1)),
    (V3(0, 0, 1), V3(1, 0, 0), V3(0, 1, 0)), (V3(0, 0, -1), V3(-1, 0, 0), V3(0, 1, 0)),
  ]
  let half = V3(hx, hy, hz)
  for (normal, u, v) in faces {
    let base = UInt32(p.count)
    let c = normal * half
    let du = u * half, dv = v * half
    for (a, b) in [(-1, -1), (1, -1), (1, 1), (-1, 1)] as [(Float, Float)] {
      p.append(c + du * a + dv * b); n.append(normal)
    }
    idx += [base, base + 1, base + 2, base, base + 2, base + 3]
  }
  return meshGeometry(p, n, idx)
}

/// Cylinder along Y, centred, capped.
func CylinderMesh(radius: CGFloat, height: CGFloat, sides: Int = 20) -> SCNGeometry {
  TubeMesh(innerRadius: 0, outerRadius: radius, height: height, sides: sides)
}

/// Thick ring along Y (inner radius 0 makes a cylinder).
func TubeMesh(innerRadius: CGFloat, outerRadius: CGFloat, height: CGFloat, sides: Int = 28) -> SCNGeometry {
  let ri = Float(innerRadius), ro = Float(outerRadius), hh = Float(height) / 2
  var p: [V3] = [], n: [V3] = [], idx: [UInt32] = []
  func ring(_ r: Float, _ y: Float, _ normal: (V3) -> V3) -> UInt32 {
    let base = UInt32(p.count)
    for i in 0...sides {
      let a = Float(i) / Float(sides) * 2 * .pi
      let d = V3(cos(a), 0, sin(a))
      p.append(V3(d.x * r, y, d.z * r)); n.append(normal(d))
    }
    return base
  }
  // Outer wall.
  let o0 = ring(ro, -hh) { $0 }, o1 = ring(ro, hh) { $0 }
  for i in 0..<UInt32(sides) { idx += [o0 + i, o1 + i, o0 + i + 1, o0 + i + 1, o1 + i, o1 + i + 1] }
  if ri > 0 {
    let i0 = ring(ri, -hh) { -$0 }, i1 = ring(ri, hh) { -$0 }
    for i in 0..<UInt32(sides) { idx += [i0 + i, i0 + i + 1, i1 + i, i0 + i + 1, i1 + i + 1, i1 + i] }
  }
  // Caps (annulus or disc).
  for (y, up) in [(hh, Float(1)), (-hh, Float(-1))] {
    let outer = ring(ro, y) { _ in V3(0, up, 0) }
    let inner = ring(max(ri, 0.0001), y) { _ in V3(0, up, 0) }
    for i in 0..<UInt32(sides) {
      if up > 0 { idx += [inner + i, inner + i + 1, outer + i, inner + i + 1, outer + i + 1, outer + i] }
      else { idx += [inner + i, outer + i, inner + i + 1, inner + i + 1, outer + i, outer + i + 1] }
    }
  }
  return meshGeometry(p, n, idx)
}

/// Torus around Y.
func TorusMesh(ringRadius: CGFloat, pipeRadius: CGFloat, ringSides: Int = 40, pipeSides: Int = 10) -> SCNGeometry {
  let R = Float(ringRadius), r = Float(pipeRadius)
  var p: [V3] = [], n: [V3] = [], idx: [UInt32] = []
  for i in 0...ringSides {
    let a = Float(i) / Float(ringSides) * 2 * .pi
    let d = V3(cos(a), 0, sin(a))
    for j in 0...pipeSides {
      let b = Float(j) / Float(pipeSides) * 2 * .pi
      let normal = d * cos(b) + V3(0, sin(b), 0)
      p.append(d * R + normal * r); n.append(normal)
    }
  }
  let stride = UInt32(pipeSides + 1)
  for i in 0..<UInt32(ringSides) {
    for j in 0..<UInt32(pipeSides) {
      let a = i * stride + j, b = (i + 1) * stride + j
      idx += [a, a + 1, b, b, a + 1, b + 1]
    }
  }
  return meshGeometry(p, n, idx)
}

/// A flat triangle panel in the XY plane, visible from both sides.
func PanelMesh(_ points: [SIMD2<Float>]) -> SCNGeometry {
  var p: [V3] = [], n: [V3] = []
  for normal in [V3(0, 0, 1), V3(0, 0, -1)] {
    for q in points { p.append(V3(q.x, q.y, 0)); n.append(normal) }
  }
  let k = UInt32(points.count)
  var idx: [UInt32] = []
  for i in 1..<(k - 1) { idx += [0, i, i + 1] }
  for i in 1..<(k - 1) { idx += [k, k + i + 1, k + i] }
  return meshGeometry(p, n, idx)
}

// MARK: Mesh helpers

final class Mesh {
  var positions: [V3] = []
  var normals: [V3] = []
  var indices: [UInt32] = []

  func geometry(_ m: SCNMaterial) -> SCNGeometry {
    let p = SCNGeometrySource(vertices: positions.map { SCNVector3($0.x, $0.y, $0.z) })
    let n = SCNGeometrySource(normals: normals.map { SCNVector3($0.x, $0.y, $0.z) })
    let e = SCNGeometryElement(indices: indices, primitiveType: .triangles)
    let g = SCNGeometry(sources: [p, n], elements: [e])
    g.materials = [m]
    return g
  }
}

/// A point on a superellipse |x/a|^n + |y/b|^n = 1 (n = 2 is an ellipse,
/// larger is boxier).
func superellipse(_ t: Float, _ a: Float, _ b: Float, _ n: Float) -> SIMD2<Float> {
  let c = cos(t), s = sin(t)
  let x = a * (c >= 0 ? 1 : -1) * pow(abs(c), 2 / n)
  let y = b * (s >= 0 ? 1 : -1) * pow(abs(s), 2 / n)
  return SIMD2(x, y)
}

struct Station {
  var z: Float        // position along the length
  var width: Float    // full width
  var bottom: Float   // y of the lowest point
  var top: Float      // y of the highest point
  var n: Float = 3    // roundness (superellipse exponent)
  var bulge: Float = 0 // extra width at the bottom (0) vs top (negative = tumblehome)
}

/// Sweeps closed superellipse sections along Z, capping both ends. Smooth
/// normals around, so a body reads as one curved surface.
func loft(_ stations: [Station], segments: Int = 28, _ m: SCNMaterial) -> SCNNode {
  let mesh = Mesh()
  var rings: [[V3]] = []
  for s in stations {
    let a = max(0.001, s.width / 2)
    let b = max(0.001, (s.top - s.bottom) / 2)
    let cy = (s.top + s.bottom) / 2
    var ring: [V3] = []
    for i in 0..<segments {
      let t = Float(i) / Float(segments) * 2 * .pi
      var p = superellipse(t, a, b, s.n)
      // Narrow the top (tumblehome) or flare the bottom.
      let k = (p.y / b) // -1 bottom ... 1 top
      p.x *= 1 + s.bulge * k
      ring.append(V3(p.x, cy + p.y, s.z))
    }
    rings.append(ring)
  }
  // Side surface with smooth normals from neighbours.
  let rows = rings.count
  for r in 0..<rows {
    for i in 0..<segments {
      let p = rings[r][i]
      let prev = rings[r][(i + segments - 1) % segments]
      let next = rings[r][(i + 1) % segments]
      let back = rings[max(0, r - 1)][i]
      let fwd = rings[min(rows - 1, r + 1)][i]
      let tangent = next - prev
      let along = fwd - back
      var normal = simd_normalize(simd_cross(tangent, along))
      if !normal.x.isFinite { normal = V3(0, 1, 0) }
      mesh.positions.append(p)
      mesh.normals.append(normal)
    }
  }
  for r in 0..<(rows - 1) {
    for i in 0..<segments {
      let a = UInt32(r * segments + i)
      let b = UInt32(r * segments + (i + 1) % segments)
      let c = UInt32((r + 1) * segments + i)
      let d = UInt32((r + 1) * segments + (i + 1) % segments)
      mesh.indices += [a, b, c, b, d, c]
    }
  }
  // Caps.
  for (r, facing) in [(0, Float(-1)), (rows - 1, Float(1))] {
    let center = rings[r].reduce(V3(0, 0, 0), +) / Float(segments)
    let base = UInt32(mesh.positions.count)
    mesh.positions.append(center)
    mesh.normals.append(V3(0, 0, facing))
    for p in rings[r] { mesh.positions.append(p); mesh.normals.append(V3(0, 0, facing)) }
    for i in 0..<segments {
      let a = base + 1 + UInt32(i)
      let b = base + 1 + UInt32((i + 1) % segments)
      mesh.indices += facing < 0 ? [base, b, a] : [base, a, b]
    }
  }
  let node = SCNNode(geometry: mesh.geometry(m))
  return node
}

@discardableResult
func put(_ parent: SCNNode, _ g: SCNGeometry, _ m: SCNMaterial, _ x: Float, _ y: Float, _ z: Float,
         rx: Float = 0, ry: Float = 0, rz: Float = 0) -> SCNNode {
  g.materials = Array(repeating: m, count: max(1, g.elements.count))
  let n = SCNNode(geometry: g)
  n.simdPosition = V3(x, y, z)
  n.simdEulerAngles = V3(rx, ry, rz)
  parent.addChildNode(n)
  return n
}

/// A cylinder from `a` to `b`.
@discardableResult
func tube(_ parent: SCNNode, _ a: V3, _ b: V3, _ r: Float, _ m: SCNMaterial, sides: Int = 10) -> SCNNode {
  let length = simd_length(b - a)
  let c = CylinderMesh(radius: CGFloat(r), height: CGFloat(length), sides: sides)
  c.materials = [m]
  let n = SCNNode(geometry: c)
  n.simdPosition = (a + b) / 2
  let up = V3(0, 1, 0)
  let dir = simd_normalize(b - a)
  let axis = simd_cross(up, dir)
  let angle = acos(max(-1, min(1, simd_dot(up, dir))))
  if simd_length(axis) > 1e-5 { n.simdOrientation = simd_quatf(angle: angle, axis: simd_normalize(axis)) }
  else if simd_dot(up, dir) < 0 { n.simdOrientation = simd_quatf(angle: .pi, axis: V3(1, 0, 0)) }
  parent.addChildNode(n)
  return n
}

func box(_ parent: SCNNode, _ w: Float, _ h: Float, _ l: Float, _ m: SCNMaterial,
         _ x: Float, _ y: Float, _ z: Float, rx: Float = 0, ry: Float = 0, rz: Float = 0) {
  put(parent, BoxMesh(width: CGFloat(w), height: CGFloat(h), length: CGFloat(l), chamferRadius: 0), m, x, y, z, rx: rx, ry: ry, rz: rz)
}

/// A road wheel: tyre, rim and spokes, axle along X.
func carWheel(_ parent: SCNNode, x: Float, y: Float, z: Float, radius: Float, width: Float, spokes: Int = 5, outward: Float) {
  let w = SCNNode()
  w.simdPosition = V3(x, y, z)
  let tyreG = TubeMesh(innerRadius: CGFloat(radius * 0.66), outerRadius: CGFloat(radius), height: CGFloat(width))
  put(w, tyreG, tyre, 0, 0, 0, rz: .pi / 2)
  let face = CylinderMesh(radius: CGFloat(radius * 0.66), height: CGFloat(width * 0.6))
  put(w, face, rim, 0, 0, 0, rz: .pi / 2)
  let hub = CylinderMesh(radius: CGFloat(radius * 0.16), height: CGFloat(width * 0.75))
  put(w, hub, chrome, outward * 0.02, 0, 0, rz: .pi / 2)
  for i in 0..<spokes {
    let a = Float(i) / Float(spokes) * 2 * .pi
    box(w, width * 0.12, radius * 0.5, radius * 0.11, black, outward * width * 0.31,
        sin(a) * radius * 0.36, cos(a) * radius * 0.36, rx: .pi / 2 - a)
  }
  parent.addChildNode(w)
}

/// A bicycle wheel: tyre, rim, hub and wire spokes, in the YZ plane.
func bikeWheel(_ parent: SCNNode, y: Float, z: Float, radius: Float, tyreWidth: Float, spokes: Int = 24) {
  let w = SCNNode()
  w.simdPosition = V3(0, y, z)
  let t = TorusMesh(ringRadius: CGFloat(radius - tyreWidth / 2), pipeRadius: CGFloat(tyreWidth / 2))
  put(w, t, tyre, 0, 0, 0, rz: .pi / 2)
  let r = TorusMesh(ringRadius: CGFloat(radius - tyreWidth * 1.1), pipeRadius: 0.012)
  put(w, r, rim, 0, 0, 0, rz: .pi / 2)
  put(w, CylinderMesh(radius: 0.025, height: 0.1), chrome, 0, 0, 0, rz: .pi / 2)
  for i in 0..<spokes {
    let a = Float(i) / Float(spokes) * 2 * .pi
    let side: Float = i % 2 == 0 ? 0.03 : -0.03
    tube(w, V3(side, 0, 0), V3(0, sin(a) * (radius - tyreWidth * 1.1), cos(a) * (radius - tyreWidth * 1.1)), 0.0025, chrome, sides: 4)
  }
  parent.addChildNode(w)
}

// MARK: Cars

struct CarSpec {
  var length: Float, width: Float, height: Float
  var wheelRadius: Float, wheelbase: Float, frontOverhangBias: Float = 0
  var hoodHeight: Float      // top of the bonnet
  var cabinStart: Float      // z where the windscreen starts (from front, 0..1)
  var cabinEnd: Float        // z where the rear screen ends (0..1)
  var roofStart: Float, roofEnd: Float
  var bed: Bool = false      // pickup
  var boxy: Float = 3.2
  var roofless: Bool = false // convertible: windscreen only, seats showing
  var grille: Bool = true    // EVs have a closed nose
}

func car(_ spec: CarSpec, body: UInt32, extras: (SCNNode, CarSpec) -> Void = { _, _ in }) -> SCNNode {
  let L = spec.length, W = spec.width, H = spec.height, wr = spec.wheelRadius
  let belt = spec.hoodHeight
  let p = paint(body)
  let cs = spec.cabinStart, ce = spec.cabinEnd, rs = spec.roofStart, re = spec.roofEnd
  let axles = [L / 2 - spec.wheelbase / 2 + spec.frontOverhangBias, L / 2 + spec.wheelbase / 2 + spec.frontOverhangBias]
  let clear = wr * 0.42
  return roadVehicle(length: L) { v in
    // Side profile: bumper, bonnet, windscreen, roof, rear screen, deck, tail.
    var topKeys: [(Float, Float)] = [(0, belt * 0.7), (0.025, belt * 0.86), (0.08, belt * 0.95), (cs - 0.03, belt + 0.01), (cs, belt + 0.03)]
    if spec.roofless {
      topKeys += [(rs, belt + 0.05), (ce, belt + 0.06)]
    } else {
      topKeys += [(cs + (rs - cs) * 0.5, belt + (H - belt) * 0.66), (rs, H - 0.01), ((rs + re) / 2, H), (re, H - 0.015)]
      topKeys += [(ce, belt + (ce > 0.95 ? (H - belt) * 0.35 : 0.06))]
    }
    if ce < 0.95 { topKeys += [(ce + (1 - ce) * 0.55, belt + 0.04)] }
    topKeys += [(1.0, belt * (ce > 0.95 ? 0.95 : 0.86))]
    let top = curve(topKeys.map { ($0.0 * L, $0.1) })
    let hw = curve([(0, W * 0.37), (0.02 * L, W * 0.44), (0.07 * L, W * 0.49), (0.2 * L, W / 2), (0.92 * L, W / 2), (0.98 * L, W * 0.47), (L, W * 0.41)])
    let bot = archBottom(clear, axles: axles, wheel: wr, gap: 0.05)
    let botEnds = curve([(0, clear + 0.12), (0.04 * L, clear + 0.02), (0.96 * L, clear + 0.02), (L, clear + 0.14)])
    let zs = samples(0, L, step: 0.04, dense: [(0, 0.3, 0.015), (L - 0.3, L, 0.015), (axles[0] - 0.55, axles[0] + 0.55, 0.02),
                                               (axles[1] - 0.55, axles[1] + 0.55, 0.02), (cs * L - 0.2, rs * L + 0.2, 0.02)])
    shell(v, zs, sharp: [8], capStart: p, capEnd: p, { z in
      let w = hw(z), t = top(z), b = max(bot(z), botEnds(z))
      let shoulder = min(belt - 0.02, t - 0.05)
      let rb: Float = 0.08, rt = min(0.12 * (spec.boxy > 4 ? 0.6 : 1), (t - shoulder) * 0.45 + 0.01)
      let tumble = max(0, t - shoulder) * (spec.boxy > 4 ? 0.12 : 0.26)
      var pts: [SIMD2<Float>] = [SIMD2(0, b), SIMD2((w - rb) * 0.5, b)]
      for i in 0...3 { let a = -Float.pi / 2 + Float.pi / 2 * Float(i) / 3; pts.append(SIMD2(w - rb + rb * cos(a), b + rb + rb * sin(a))) }
      let lo = b + rb
      for i in 1...3 { let f = Float(i) / 3; pts.append(SIMD2(w + 0.012 * sin(.pi * f), lo + (shoulder - lo) * f)) }
      for i in 1...2 { let f = Float(i) / 3; pts.append(SIMD2(w - tumble * f, shoulder + (t - rt - shoulder) * f)) }
      for i in 0...4 { let a = Float.pi / 2 * Float(i) / 4; pts.append(SIMD2(w - tumble - rt + rt * cos(a), t - rt + rt * sin(a))) }
      pts.append(SIMD2((w - tumble - rt) * 0.5, t)); pts.append(SIMD2(0, t))
      return pts
    }, skin: { f in f.n.y < -0.75 ? trimPlastic : p })
    let fd = Drape(v, axis: 2), sd = Drape(v, axis: 0)
    let yB = belt + 0.05, yR = H - 0.07
    if !spec.roofless {
      // Glass: windscreen, side windows (split by the B pillar), rear screen.
      decalPatches(v, fd, [rounded([SIMD2(-W * 0.4, yB), SIMD2(W * 0.4, yB), SIMD2(W * 0.31, yR), SIMD2(-W * 0.31, yR)], r: 0.06)], glass,
                   below: true, lift: 0.008, k: 8)
      let zA = cs * L + 0.12, zRoof0 = rs * L + 0.05, zRoof1 = re * L - 0.05, zC = ce * L - (ce > 0.95 ? 0.12 : 0.18)
      let zB = (zRoof0 + zRoof1) / 2 - (ce > 0.95 ? (zRoof1 - zRoof0) * 0.18 : 0)
      let yC: Float = ce > 0.95 ? yR - 0.04 : yB
      let front = [SIMD2(zA, yB), SIMD2(zB - 0.05, yB), SIMD2(zB - 0.05, yR), SIMD2(zRoof0, yR)]
      let rear = ce > 0.95 ? [SIMD2(zB + 0.05, yB), SIMD2(zC, yB), SIMD2(zC, yC), SIMD2(zB + 0.05, yR)]
                           : [SIMD2(zB + 0.05, yB), SIMD2(zC, yB), SIMD2(zRoof1, yR), SIMD2(zB + 0.05, yR)]
      sidePatches(v, sd, [rounded(front, r: 0.05), rounded(rear, r: 0.05)], glass, lift: 0.008, k: 4)
      if ce > 0.95 {
        sidePatches(v, sd, [rounded([SIMD2(zC + 0.08, yB), SIMD2(L * 0.985 - 0.06, yB), SIMD2(L * 0.985 - 0.08, yR - 0.06), SIMD2(zC + 0.08, yR - 0.04)], r: 0.04)],
                    glass, lift: 0.008)
      }
      decalPatches(v, fd, [rounded([SIMD2(-W * 0.37, yB + (ce > 0.95 ? 0.05 : 0.02)), SIMD2(W * 0.37, yB + (ce > 0.95 ? 0.05 : 0.02)),
                                    SIMD2(W * 0.3, yR - 0.02), SIMD2(-W * 0.3, yR - 0.02)], r: 0.06)], glass, below: false, lift: 0.008, k: 8)
    }
    // Door seams, handles, sills.
    let d0 = cs * L + 0.05, d2 = min(ce * L, axles[1] - wr - 0.1)
    let dB = (d0 + d2) / 2 + 0.05
    sideLines(v, sd, [[SIMD2(d0, clear + 0.12), SIMD2(d0, belt - 0.02)], [SIMD2(dB, clear + 0.08), SIMD2(dB, belt + 0.02)],
                      [SIMD2(d2, clear + 0.14), SIMD2(d2, belt - 0.02)]], width: 0.01, black)
    sidePatches(v, sd, [rounded([SIMD2(dB - 0.2, belt - 0.12), SIMD2(dB - 0.08, belt - 0.12), SIMD2(dB - 0.08, belt - 0.1), SIMD2(dB - 0.2, belt - 0.1)], r: 0.008),
                        rounded([SIMD2(d2 - 0.2, belt - 0.12), SIMD2(d2 - 0.08, belt - 0.12), SIMD2(d2 - 0.08, belt - 0.1), SIMD2(d2 - 0.2, belt - 0.1)], r: 0.008)],
                chrome, lift: 0.014)
    let R = wr + 0.05
    sidePatches(v, sd, [rounded([SIMD2(axles[0] + R + 0.02, clear + 0.03), SIMD2(axles[1] - R - 0.02, clear + 0.03), SIMD2(axles[1] - R - 0.02, clear + 0.1),
                                 SIMD2(axles[0] + R + 0.02, clear + 0.1)], r: 0.02)], trimPlastic, lift: 0.01)
    // Front: lamps, grille or light bar, lower intake, plate. Rear: lamps, plate, diffuser.
    let ly = belt * 0.8
    decalPatches(v, fd, [rounded([SIMD2(W * 0.24, ly - 0.03), SIMD2(W * 0.44, ly - 0.02), SIMD2(W * 0.45, ly + 0.07), SIMD2(W * 0.27, ly + 0.05)], r: 0.03)],
                 lens, below: true, mirror: true, lift: 0.01)
    decalPatches(v, fd, [rounded([SIMD2(W * 0.29, ly), SIMD2(W * 0.4, ly + 0.005), SIMD2(W * 0.41, ly + 0.045), SIMD2(W * 0.3, ly + 0.035)], r: 0.015)],
                 headlight, below: true, mirror: true, lift: 0.016)
    if spec.grille {
      decalPatches(v, fd, [rounded([SIMD2(-W * 0.2, ly - 0.16), SIMD2(W * 0.2, ly - 0.16), SIMD2(W * 0.22, ly + 0.02), SIMD2(-W * 0.22, ly + 0.02)], r: 0.04)],
                   black, below: true, lift: 0.01)
      decalLines(v, fd, [[SIMD2(-W * 0.19, ly - 0.07), SIMD2(W * 0.19, ly - 0.07)]], width: 0.015, chrome, below: true, mirror: false, lift: 0.016)
    } else {
      decalLines(v, fd, [[SIMD2(-W * 0.3, ly + 0.05), SIMD2(W * 0.3, ly + 0.05)]], width: 0.018, headlight, below: true, mirror: false, lift: 0.014)
    }
    decalPatches(v, fd, [rounded([SIMD2(-W * 0.36, clear + 0.06), SIMD2(W * 0.36, clear + 0.06), SIMD2(W * 0.3, clear + 0.2), SIMD2(-W * 0.3, clear + 0.2)], r: 0.04)],
                 trimPlastic, below: true, lift: 0.01)
    decalPatches(v, fd, [rounded([SIMD2(-0.26, clear + 0.22), SIMD2(0.26, clear + 0.22), SIMD2(0.26, clear + 0.33), SIMD2(-0.26, clear + 0.33)], r: 0.01)],
                 plate, below: true, lift: 0.016)
    let ty = belt * 0.86
    decalPatches(v, fd, [rounded([SIMD2(W * 0.18, ty - 0.03), SIMD2(W * 0.45, ty - 0.03), SIMD2(W * 0.44, ty + 0.06), SIMD2(W * 0.2, ty + 0.05)], r: 0.03)],
                 taillight, below: false, mirror: true, lift: 0.012)
    decalPatches(v, fd, [rounded([SIMD2(-0.26, ty - 0.24), SIMD2(0.26, ty - 0.24), SIMD2(0.26, ty - 0.13), SIMD2(-0.26, ty - 0.13)], r: 0.01)],
                 plate, below: false, lift: 0.016)
    decalPatches(v, fd, [rounded([SIMD2(-W * 0.4, clear + 0.06), SIMD2(W * 0.4, clear + 0.06), SIMD2(W * 0.38, clear + 0.18), SIMD2(-W * 0.38, clear + 0.18)], r: 0.03)],
                 trimPlastic, below: false, lift: 0.01)
    if spec.roofless {
      // Windscreen frame and glass, cabin tub, seats with headrests, roll hoops.
      let zW = cs * L
      let plan = (0...8).map { i -> SIMD2<Float> in let t = Float(i) / 8 * 2 - 1; return SIMD2(t * W * 0.42, zW + 0.12 + t * t * 0.12) }
      screenStrip(v, plan, y0: belt + 0.02, y1: belt + 0.36, rake: 0.32, glass)
      tube(v, V3(plan[0].x, belt + 0.36, plan[0].y + 0.32), V3(plan[8].x, belt + 0.36, plan[8].y + 0.32), 0.02, black, sides: 6)
      let up = Drape(v, axis: 1)
      let c0 = cs * L + 0.4, c1 = ce * L - 0.15
      decalPatches(v, up, [rounded([SIMD2(-W * 0.4, c0), SIMD2(W * 0.4, c0), SIMD2(W * 0.4, c1), SIMD2(-W * 0.4, c1)], r: 0.18)],
                   material("interior", 0x2A2522, rough: 0.8), lift: 0.006, k: 6)
      for side in [-1, 1] as [Float] {
        let sz = c0 + (c1 - c0) * 0.55
        motoBody(v, [(sz - 0.28, W * 0.12, belt - 0.02, belt + 0.06), (sz + 0.1, W * 0.13, belt - 0.02, belt + 0.08), (sz + 0.16, W * 0.13, belt - 0.02, belt + 0.5),
                     (sz + 0.26, W * 0.12, belt - 0.02, belt + 0.48)], x: side * W * 0.2, step: 0.03, rb: 0.3, rt: 0.6, cap: leather) { _ in leather }
        motoBody(v, [(sz + 0.16, 0.1, belt + 0.5, belt + 0.66), (sz + 0.26, 0.1, belt + 0.5, belt + 0.66)], x: side * W * 0.2, step: 0.03, rb: 0.5, rt: 0.6,
                 cap: leather) { _ in leather }
      }
      put(v, TorusMesh(ringRadius: 0.17, pipeRadius: 0.018, ringSides: 24, pipeSides: 6), black, -W * 0.2, belt + 0.25, c0 + 0.25, rx: -1.2)
    }
    for side in [-1, 1] as [Float] {
      sideMirror(v, at: V3(side * (W / 2 - 0.08), belt + 0.08, cs * L + 0.22), side: side, reach: 0.08, w: 0.16, h: 0.11, p)
      for z in axles {
        roadWheel(v, x: side * (W / 2 - wr * 0.4), y: wr, z: z, radius: wr, width: 0.23, outward: side, rimRatio: 0.66, rimMaterial: rim, holes: 5, lugs: 5)
      }
    }
    extras(holder(v, V3(0, 0, L / 2)), spec)
  }
}

let sedan = CarSpec(length: 4.7, width: 1.83, height: 1.45, wheelRadius: 0.33, wheelbase: 2.8,
                    hoodHeight: 0.92, cabinStart: 0.30, cabinEnd: 0.84, roofStart: 0.43, roofEnd: 0.70)
let hatchback = CarSpec(length: 4.1, width: 1.78, height: 1.48, wheelRadius: 0.32, wheelbase: 2.6,
                        hoodHeight: 0.92, cabinStart: 0.28, cabinEnd: 0.97, roofStart: 0.42, roofEnd: 0.88)
let suv = CarSpec(length: 4.8, width: 1.95, height: 1.75, wheelRadius: 0.38, wheelbase: 2.9,
                  hoodHeight: 1.12, cabinStart: 0.28, cabinEnd: 0.97, roofStart: 0.40, roofEnd: 0.93, boxy: 4)
let sports = CarSpec(length: 4.5, width: 1.92, height: 1.22, wheelRadius: 0.34, wheelbase: 2.6,
                     hoodHeight: 0.80, cabinStart: 0.36, cabinEnd: 0.80, roofStart: 0.50, roofEnd: 0.64)
let pickup = CarSpec(length: 5.6, width: 2.0, height: 1.9, wheelRadius: 0.42, wheelbase: 3.6,
                     hoodHeight: 1.2, cabinStart: 0.26, cabinEnd: 0.55, roofStart: 0.35, roofEnd: 0.53, bed: true, boxy: 4.5)

// MARK: Bikes and scooters

func bicycle(kind: String, frame: UInt32) -> SCNNode {
  let root = SCNNode()
  let mountain = kind == "mountain", road = kind == "road", city = kind == "city"
  let wheelR: Float = mountain ? 0.37 : 0.35
  let tyreW: Float = mountain ? 0.06 : road ? 0.026 : 0.04
  let wb: Float = mountain ? 1.12 : 1.02
  let rearZ = wb / 2, frontZ = -wb / 2
  bikeWheel(root, y: wheelR, z: rearZ, radius: wheelR, tyreWidth: tyreW)
  bikeWheel(root, y: wheelR, z: frontZ, radius: wheelR, tyreWidth: tyreW)
  let f = paint(frame)
  let bb = V3(0, 0.30, 0.05)                 // bottom bracket
  let seatTop = V3(0, city ? 0.82 : 0.86, 0.22)
  let headTop = V3(0, city ? 0.84 : (road ? 0.80 : 0.82), -0.40)
  let headBottom = V3(0, 0.64, -0.36)
  let rearAxle = V3(0, wheelR, rearZ), frontAxle = V3(0, wheelR, frontZ)
  let r: Float = mountain ? 0.024 : 0.018
  tube(root, bb, seatTop, r, f)                                   // seat tube
  tube(root, city ? V3(0, 0.38, 0.0) : seatTop - V3(0, 0.06, 0.01), headTop - V3(0, 0.05, 0), r, f) // top tube
  tube(root, bb, headBottom, r * 1.15, f)                         // down tube
  tube(root, headBottom, headTop, r * 1.2, f)                     // head tube
  for x in [-0.05, 0.05] as [Float] {
    tube(root, bb + V3(x, 0, 0), rearAxle + V3(x, 0, 0), r * 0.6, f)            // chainstays
    tube(root, seatTop - V3(-x, 0.08, 0), rearAxle + V3(x, 0, 0), r * 0.55, f)  // seatstays
    tube(root, headBottom + V3(x * 0.8, 0, 0), frontAxle + V3(x, 0, 0), mountain ? 0.02 : 0.013, mountain ? chrome : f) // fork
  }
  // Saddle and post.
  tube(root, seatTop, seatTop + V3(0, 0.12, 0.03), 0.013, chrome)
  box(root, 0.14, 0.05, 0.26, leather, 0, seatTop.y + 0.14, seatTop.z + 0.05)
  // Stem and bars.
  let barCenter = headTop + V3(0, 0.07, -0.06)
  tube(root, headTop, barCenter, 0.014, chrome)
  if road {
    tube(root, barCenter + V3(-0.21, 0, 0), barCenter + V3(0.21, 0, 0), 0.012, black)
    for x in [-0.21, 0.21] as [Float] {
      tube(root, barCenter + V3(x, 0, 0), barCenter + V3(x, -0.13, -0.08), 0.012, black)
      tube(root, barCenter + V3(x, -0.13, -0.08), barCenter + V3(x, -0.15, 0.02), 0.012, black)
    }
  } else {
    let span: Float = mountain ? 0.36 : 0.30
    tube(root, barCenter + V3(-span, city ? 0.04 : 0, city ? 0.08 : 0), barCenter + V3(span, city ? 0.04 : 0, city ? 0.08 : 0), 0.013, black)
    for x in [-span, span] { tube(root, barCenter + V3(x, 0, 0), barCenter + V3(x * 0.75, 0, 0), 0.018, rubber) }
  }
  // Crank, chainring, pedals, chain.
  let ring = TorusMesh(ringRadius: 0.1, pipeRadius: 0.008)
  put(root, ring, chrome, 0.06, bb.y, bb.z, rz: .pi / 2)
  for s in [-1, 1] as [Float] {
    let pedal = bb + V3(s * 0.09, s * -0.15, 0)
    tube(root, bb + V3(s * 0.07, 0, 0), pedal, 0.01, chrome)
    box(root, 0.09, 0.02, 0.06, black, pedal.x + s * 0.04, pedal.y, pedal.z)
  }
  tube(root, bb + V3(0.06, 0.1, 0), rearAxle + V3(0.06, 0.05, 0), 0.006, black, sides: 4)
  tube(root, bb + V3(0.06, -0.1, 0), rearAxle + V3(0.06, -0.05, 0), 0.006, black, sides: 4)
  if city {
    // Basket, rack and fenders.
    let basket = barCenter + V3(0, -0.05, -0.2)
    box(root, 0.36, 0.22, 0.28, wood, 0, basket.y, basket.z)
    box(root, 0.3, 0.02, 0.36, chrome, 0, wheelR + 0.38, rearZ - 0.02)
    let fender = TubeMesh(innerRadius: CGFloat(wheelR + 0.02), outerRadius: CGFloat(wheelR + 0.035), height: 0.07)
    put(root, fender, f, 0, wheelR, rearZ, rz: .pi / 2)
    box(root, 0.07, 0.04, 0.04, headlight, 0, headTop.y - 0.1, headTop.z - 0.05)
  }
  if mountain {
    // Suspension stanchions.
    for x in [-0.05, 0.05] as [Float] { tube(root, headBottom + V3(x, -0.02, 0), headBottom + V3(x, -0.2, 0.02), 0.022, black) }
  }
  return root
}

func kickScooter(deck: UInt32) -> SCNNode {
  let root = SCNNode()
  let d = paint(deck)
  root.addChildNode(loft([
    Station(z: -0.42, width: 0.16, bottom: 0.08, top: 0.16, n: 4),
    Station(z: 0.36, width: 0.18, bottom: 0.08, top: 0.15, n: 4),
    Station(z: 0.42, width: 0.12, bottom: 0.1, top: 0.15, n: 3),
  ], segments: 20, d))
  box(root, 0.15, 0.01, 0.62, rubber, 0, 0.162, -0.02)
  for z in [-0.5, 0.48] as [Float] {
    let t = TorusMesh(ringRadius: 0.085, pipeRadius: 0.03)
    put(root, t, tyre, 0, 0.115, z, rz: .pi / 2)
    put(root, CylinderMesh(radius: 0.06, height: 0.05), rim, 0, 0.115, z, rz: .pi / 2)
  }
  // Rear fender and front fork.
  let fender = TubeMesh(innerRadius: 0.12, outerRadius: 0.135, height: 0.08)
  put(root, fender, d, 0, 0.12, 0.48, rz: .pi / 2)
  tube(root, V3(0, 0.12, -0.5), V3(0, 1.08, -0.56), 0.022, d)
  tube(root, V3(-0.24, 1.1, -0.56), V3(0.24, 1.1, -0.56), 0.016, black)
  for x in [-0.24, 0.24] as [Float] { tube(root, V3(x, 1.1, -0.56), V3(x * 0.78, 1.1, -0.56), 0.022, rubber) }
  box(root, 0.08, 0.06, 0.05, plastic, 0, 1.06, -0.6)
  box(root, 0.06, 0.03, 0.02, headlight, 0, 0.95, -0.59)
  box(root, 0.08, 0.02, 0.02, taillight, 0, 0.17, 0.5)
  return root
}

// Classic step-through scooter (Vespa class): 1.85 m, 12-inch wheels.
// Pressed-steel leg shield and floorboard, bulbous side cowls over the
// engine, round headlamp in the headset, front fender on the fork link,
// two-tone seat, rear rack.
func moped(body: UInt32) -> SCNNode {
  let L: Float = 1.85, r: Float = 0.235
  let fz: Float = 0.24, rz: Float = 1.56
  let p = paint(body)
  return roadVehicle(length: L) { v in
    motoWheel(v, z: fz, r: r, w: 0.1, rimRatio: 0.6, rimMat: rim)
    motoWheel(v, z: rz, r: r, w: 0.1, rimRatio: 0.6, rimMat: rim)
    for (z, x) in [(fz, Float(0.06)), (rz, Float(-0.06))] {
      put(v, CylinderMesh(radius: CGFloat(r * 0.56), height: 0.02, sides: 24), rim, x, r, z, rz: .pi / 2)
      put(v, CylinderMesh(radius: CGFloat(r * 0.2), height: 0.04, sides: 14), chrome, x * 1.3, r, z, rz: .pi / 2)
    }
    // Front fender, single-sided fork link, steering column.
    motoBody(v, [(fz - 0.24, 0.06, 0.4, 0.44), (fz - 0.14, 0.085, 0.47, 0.56), (fz + 0.06, 0.085, 0.49, 0.59), (fz + 0.18, 0.07, 0.42, 0.5),
                 (fz + 0.22, 0.05, 0.3, 0.38)], step: 0.015, rb: 0.6, rt: 0.6, cap: p) { _ in p }
    tube(v, V3(-0.07, r, fz), V3(-0.07, 0.55, fz + 0.12), 0.025, engineDark, sides: 8)
    tube(v, V3(0, 0.55, fz + 0.14), V3(0, 1.0, fz + 0.26), 0.03, engineDark, sides: 8)
    // Leg shield, floorboard and the step-through frame.
    motoBody(v, [(0.36, 0.2, 0.32, 0.88), (0.42, 0.25, 0.3, 0.98), (0.5, 0.24, 0.3, 0.97), (0.54, 0.17, 0.32, 0.9)], step: 0.02, rb: 0.3, rt: 0.6, cap: p) { _ in p }
    motoBody(v, [(0.5, 0.17, 0.27, 0.33), (1.0, 0.17, 0.27, 0.33), (1.08, 0.12, 0.28, 0.4)], step: 0.04, rb: 0.3, rt: 0.2, cap: p) { _ in p }
    // Side cowls over the engine and the tail.
    motoBody(v, [(0.98, 0.12, 0.34, 0.52), (1.12, 0.26, 0.3, 0.66), (1.42, 0.31, 0.28, 0.72), (1.66, 0.25, 0.34, 0.7), (1.8, 0.14, 0.46, 0.64),
                 (1.85, 0.06, 0.52, 0.6)], step: 0.02, rb: 0.6, rt: 0.6, cap: p) { _ in p }
    // Seat (two-tone) and rear rack.
    motoBody(v, [(1.0, 0.12, 0.7, 0.78), (1.1, 0.16, 0.7, 0.82), (1.62, 0.16, 0.7, 0.83), (1.7, 0.12, 0.7, 0.8)], step: 0.02, rb: 0.4, rt: 0.6, cap: leather) { f in
      f.n.y > 0.85 ? leather : material("seat-base", 0x6E5A48, rough: 0.6)
    }
    for x in [-0.12, 0.12] as [Float] { tube(v, V3(x, 0.78, 1.68), V3(x, 0.8, 1.9), 0.01, chrome, sides: 6) }
    tube(v, V3(-0.12, 0.8, 1.9), V3(0.12, 0.8, 1.9), 0.01, chrome, sides: 6)
    // Headset with round headlamp, speedo, bars and mirrors.
    motoBody(v, [(0.22, 0.08, 0.98, 1.06), (0.3, 0.17, 0.96, 1.12), (0.44, 0.17, 0.97, 1.12), (0.52, 0.1, 1.0, 1.08)], step: 0.015, rb: 0.6, rt: 0.6, cap: p) { _ in p }
    put(v, LatheMesh([SIMD2(0, 0.07), SIMD2(0.02, 0.07), SIMD2(0.03, 0.001)], sides: 20), chrome, 0, 1.04, 0.225, rx: -.pi / 2)
    put(v, CylinderMesh(radius: 0.06, height: 0.01, sides: 20), headlight, 0, 1.04, 0.19, rx: .pi / 2)
    put(v, CylinderMesh(radius: 0.04, height: 0.01, sides: 16), glass, 0, 1.125, 0.38)
    for side in [-1, 1] as [Float] {
      tube(v, V3(side * 0.15, 1.06, 0.38), V3(side * 0.34, 1.06, 0.4), 0.016, rubber, sides: 8)
      tube(v, V3(side * 0.16, 1.1, 0.38), V3(side * 0.24, 1.32, 0.38), 0.007, chrome, sides: 4)
      put(v, CylinderMesh(radius: 0.045, height: 0.015, sides: 14), chrome, side * 0.24, 1.34, 0.38, rx: .pi / 2)
    }
    let fd = Drape(v, axis: 2), up = Drape(v, axis: 1)
    decalPatches(v, fd, [[SIMD2(-0.04, 0.7), SIMD2(0.04, 0.7), SIMD2(0.07, 0.86), SIMD2(-0.07, 0.86)]], chrome, below: true, lift: 0.004)
    decalLines(v, up, (0..<4).map { i in let x = -0.12 + Float(i) * 0.08; return [SIMD2(x, 0.55), SIMD2(x, 0.98)] }, width: 0.015, rubber, mirror: false, lift: 0.004)
    box(v, 0.1, 0.05, 0.02, taillight, 0, 0.62, L + 0.005)
    tube(v, V3(0.1, 0.25, 1.25), V3(0.14, 0.24, 1.75), 0.03, chrome, sides: 8)
  }
}

// MARK: Boats

/// A strip of glass (or any panel) standing on a plan-view polyline from y0
/// to y1, its top leaning back by `rake`; double-sided.
func screenStrip(_ p: SCNNode, _ plan: [SIMD2<Float>], y0: Float, y1: Float, rake: Float, _ m: SCNMaterial) {
  let mesh = Mesh()
  for i in 0..<(plan.count - 1) {
    let a = plan[i], b = plan[i + 1]
    let a0 = V3(a.x, y0, a.y), b0 = V3(b.x, y0, b.y), a1 = V3(a.x, y1, a.y + rake), b1 = V3(b.x, y1, b.y + rake)
    let n = simd_normalize(simd_cross(b0 - a0, a1 - a0))
    emitTri(mesh, a0, b0, b1, n, n, n); emitTri(mesh, a0, b1, a1, n, n, n)
    emitTri(mesh, a0, b1, b0, -n, -n, -n); emitTri(mesh, a0, a1, b1, -n, -n, -n)
  }
  p.addChildNode(SCNNode(geometry: mesh.geometry(m)))
}

/// An open-boat hull (keel, chine, topsides, gunwale cap, inner wall and a
/// recessed floor) through profiles along z. Returns nothing; the skin
/// closure paints bottom, topsides, cap and floor.
func openHull(_ v: SCNNode, length L: Float, keel: (Float) -> Float, hw: (Float) -> Float, gunwale: (Float) -> Float, floor: (Float) -> Float,
              deadrise: Float, step: Float, skin: (Facet) -> SCNMaterial) {
  shell(v, samples(0, L, step: step, dense: [(0, L * 0.15, step * 0.4)]), sharp: [4, 8, 9, 10], capStart: hullWhite, capEnd: hullWhite, { z in
    let w = hw(z), k = keel(z), g = gunwale(z), f = min(floor(z), g - 0.01)
    let chine = SIMD2<Float>(w * 0.78, k + w * 0.78 * deadrise)
    var half = resample([SIMD2(0, k), chine], 5)
    half += resample([chine, SIMD2(w, g)], 5).dropFirst()
    let inner = max(0.01, w - 0.13)
    half += [SIMD2(w - 0.03, g + 0.04), SIMD2(inner, g + 0.02), SIMD2(inner * 0.98, (g + f) / 2), SIMD2(inner * 0.95, f), SIMD2(0, f)]
    return half
  }, skin: skin)
}

// Bowrider (21 ft class): 6.6 m, 2.5 m beam, 20-degree deep V with chines,
// painted topsides over a white bottom, open bow with wrap-round seating,
// a wraparound windscreen with a walk-through, twin consoles (wheel and
// dash on the right), helm buckets, rear bench and sun pad, bow rails,
// and a 200 hp outboard on the transom.
func speedboat(hull: UInt32) -> SCNNode {
  let L: Float = 6.6
  let p = paint(hull)
  let cushion = material("cushion", 0xEDE7DA, rough: 0.75)
  let mat = material("deck-mat", 0x9AA0A6, rough: 0.85)
  return roadVehicle(length: L) { v in
    let keel = curve([(0, 0.85), (0.6, 0.4), (1.6, 0.1), (3.0, 0.0), (L, 0.02)])
    let hw = curve([(0, 0.04), (0.4, 0.55), (1.2, 0.98), (2.5, 1.2), (5.5, 1.25), (L, 1.2)])
    let g = curve([(0, 1.16), (1.0, 1.1), (3.0, 1.03), (L, 0.98)])
    let f = curve([(0, 1.2), (0.55, 1.2), (0.8, 0.62), (5.2, 0.6), (5.45, 0.95), (L, 0.95)])
    openHull(v, length: L, keel: keel, hw: hw, gunwale: g, floor: f, deadrise: 0.36, step: 0.06) { fc in
      let y = fc.p.y
      if fc.n.y > 0.75 && y < 0.7 { return mat }
      if fc.n.y > 0.75 { return hullWhite }
      let outward = fc.n.x * (fc.p.x >= 0 ? 1 : -1) > 0.25 || fc.p.z + L / 2 < 0.5
      return outward && y > 0.5 && fc.n.y < 0.6 ? p : hullWhite
    }
    // Windscreen with a walk-through gap.
    for side in [-1, 1] as [Float] {
      let plan = (0...8).map { i -> SIMD2<Float> in
        let t = Float(i) / 8
        let x = side * (0.28 + t * 0.88)
        return SIMD2(x, 2.32 + pow(t, 2.2) * 0.55)
      }
      screenStrip(v, plan, y0: 1.04, y1: 1.46, rake: 0.18, tint)
      tube(v, V3(plan[8].x, 1.04, plan[8].y), V3(plan[8].x, 1.46, plan[8].y + 0.18), 0.012, chrome, sides: 4)
      tube(v, V3(plan[0].x, 1.46, plan[0].y + 0.18), V3(plan[8].x, 1.46, plan[8].y + 0.18), 0.01, chrome, sides: 4)
      // Console.
      motoBody(v, [(2.4, 0.3, 0.6, 1.0), (2.6, 0.34, 0.6, 1.08), (3.15, 0.32, 0.6, 1.0)], x: side * 0.6, step: 0.05, rb: 0.2, rt: 0.5, cap: hullWhite) { fc in
        fc.n.y > 0.55 && fc.n.z < -0.2 ? black : hullWhite
      }
      // Bucket seats and bow cushions.
      motoBody(v, [(3.45, 0.24, 0.62, 0.95), (3.8, 0.26, 0.62, 0.97), (3.9, 0.24, 0.62, 1.45), (4.0, 0.22, 0.65, 1.42)], x: side * 0.6, step: 0.04,
               rb: 0.4, rt: 0.6, cap: cushion) { _ in cushion }
      motoBody(v, [(0.85, 0.12, 0.62, 0.86), (1.4, 0.2, 0.62, 0.86), (2.15, 0.22, 0.62, 0.86)], x: side * 0.72, step: 0.05, rb: 0.4, rt: 0.6, cap: cushion) { _ in cushion }
      // Bow rails.
      let rail = (0...6).map { i -> V3 in
        let z = 0.25 + Float(i) * 0.28
        return V3(side * (hw(z) - 0.06), g(z) + 0.32, z)
      }
      for k in 0..<(rail.count - 1) { rod(v, rail[k], rail[k + 1], 0.014, chrome, sides: 6) }
      for q in rail where q.z > 0.4 { rod(v, q, V3(q.x, g(q.z), q.z), 0.012, chrome, sides: 6) }
    }
    put(v, TorusMesh(ringRadius: 0.17, pipeRadius: 0.018, ringSides: 24, pipeSides: 6), black, 0.6, 1.2, 3.02, rx: -1.1)
    motoBody(v, [(4.6, 1.05, 0.62, 0.95), (5.0, 1.08, 0.62, 0.98), (5.35, 1.06, 0.62, 1.4), (5.45, 1.0, 0.65, 1.38)], step: 0.04, rb: 0.2, rt: 0.5, cap: cushion) { _ in cushion }
    motoBody(v, [(5.5, 1.0, 0.95, 1.04), (6.3, 1.05, 0.95, 1.06)], step: 0.05, rb: 0.2, rt: 0.6, cap: cushion) { _ in cushion }
    // Outboard.
    let ob = holder(v, V3(0, 0, L + 0.1))
    motoBody(ob, [(-0.05, 0.16, 1.05, 1.5), (0.15, 0.24, 0.98, 1.72), (0.55, 0.22, 1.02, 1.7), (0.7, 0.12, 1.15, 1.55)], step: 0.03, rb: 0.6, rt: 0.6, cap: black) { fc in
      fc.p.y > 1.6 ? hullWhite : black
    }
    motoBody(ob, [(0.05, 0.07, 0.15, 1.0), (0.3, 0.09, 0.15, 1.0), (0.42, 0.04, 0.25, 0.95)], step: 0.04, rb: 0.5, rt: 0.5, cap: black) { _ in black }
    motoBody(ob, [(0.0, 0.12, 0.42, 0.45), (0.55, 0.14, 0.42, 0.45)], step: 0.05, rb: 0.3, rt: 0.3, cap: engineDark) { _ in engineDark }
    for k in 0..<3 {
      let a = Float(k) / 3 * 2 * .pi
      put(ob, BoxMesh(width: 0.22, height: 0.02, length: 0.12), alu, sin(a) * 0.12, 0.18 + cos(a) * 0.12, 0.42, rx: 0.3, rz: a)
    }
    let sd = Drape(v, axis: 0)
    sideLines(v, sd, [[SIMD2(0.35, 0.98), SIMD2(L - 0.02, 0.85)]], width: 0.05, hullWhite, lift: 0.01)
    box(v, 0.06, 0.05, 0.05, navRed, -0.06, 1.2, 0.12)
    box(v, 0.06, 0.05, 0.05, navGreen, 0.06, 1.2, 0.12)
  }
}

// 33 ft cruising sloop: painted hull with a white boot top, coachroof
// with long dark ports, a recessed cockpit with wheel, teak side decks,
// masthead rig with mainsail and jib, lifelines and pulpits.
func sailboat(hull: UInt32) -> SCNNode {
  let L: Float = 10.0
  let p = paint(hull)
  return roadVehicle(length: L) { v in
    let keel = curve([(0, 1.1), (0.8, 0.5), (2.5, 0.1), (5.0, 0.0), (8.5, 0.15), (L, 0.55)])
    let hw = curve([(0, 0.04), (1.0, 0.85), (3.0, 1.5), (5.5, 1.65), (8.0, 1.5), (L, 1.25)])
    let g = curve([(0, 1.45), (2.0, 1.3), (6.0, 1.18), (L, 1.2)])
    let f = curve([(0, 2.0), (6.6, 2.0), (6.8, 0.75), (9.4, 0.75), (9.6, 2.0), (L, 2.0)])
    openHull(v, length: L, keel: keel, hw: hw, gunwale: g, floor: f, deadrise: 0.22, step: 0.08) { fc in
      if fc.n.y > 0.75 && fc.p.y < 1.0 { return teak }
      if fc.n.y > 0.75 { return teak }
      if fc.p.y < 0.35 { return antifoul }
      return p
    }
    // Coachroof.
    motoBody(v, [(2.6, 0.5, 1.15, 1.5), (3.2, 1.0, 1.15, 1.72), (6.0, 1.05, 1.15, 1.76), (6.7, 1.0, 1.15, 1.72)], step: 0.06, rb: 0.1, rt: 0.3, cap: hullWhite) { _ in hullWhite }
    let sd = Drape(v, axis: 0)
    sideLines(v, sd, [[SIMD2(0.9, 0.45), SIMD2(L - 0.05, 0.62)]], width: 0.08, hullWhite, lift: 0.01)
    sidePatches(v, sd, [rounded([SIMD2(3.4, 1.42), SIMD2(5.9, 1.42), SIMD2(5.7, 1.58), SIMD2(3.6, 1.6)], r: 0.08)], tint, lift: 0.01)
    // Mast, boom, sails, rigging, wheel, lifelines.
    let mz: Float = 3.4
    tube(v, V3(0, 1.75, mz), V3(0, 14.6, mz), 0.09, chrome, sides: 10)
    tube(v, V3(0, 2.6, mz), V3(0, 2.7, mz + 4.3), 0.06, chrome, sides: 8)
    put(v, PanelMesh([SIMD2(0, 0), SIMD2(0, 11.8), SIMD2(4.2, 0)]), sailcloth, 0.02, 2.75, mz + 0.05, ry: -.pi / 2)
    put(v, PanelMesh([SIMD2(0, 0), SIMD2(-3.2, 0), SIMD2(0, 12.0)]), sailcloth, 0, 1.55, mz - 0.1, ry: -.pi / 2)
    rod(v, V3(0, 14.5, mz), V3(0, 1.45, 0.05), 0.012, chrome, sides: 4)
    rod(v, V3(0, 14.5, mz), V3(0, 1.2, L - 0.05), 0.012, chrome, sides: 4)
    for side in [-1, 1] as [Float] {
      rod(v, V3(0, 9.0, mz), V3(side * 0.9, 9.0, mz), 0.03, chrome, sides: 4)
      rod(v, V3(side * 0.9, 9.0, mz), V3(side * 1.5, 1.25, mz + 0.4), 0.01, chrome, sides: 4)
      rod(v, V3(0, 14.4, mz), V3(side * 0.9, 9.0, mz), 0.01, chrome, sides: 4)
      var stan: [V3] = []
      for z in stride(from: Float(1.0), through: L - 0.3, by: 1.2) { stan.append(V3(side * (hw(z) - 0.08), g(z), z)) }
      for q in stan { rod(v, q, q + V3(0, 0.6, 0), 0.015, chrome, sides: 4) }
      for k in 0..<(stan.count - 1) { rod(v, stan[k] + V3(0, 0.6, 0), stan[k + 1] + V3(0, 0.6, 0), 0.008, chrome, sides: 4) }
    }
    put(v, TorusMesh(ringRadius: 0.38, pipeRadius: 0.02, ringSides: 28, pipeSides: 6), chrome, 0, 1.25, 8.9)
    box(v, 0.12, 0.5, 0.1, engineDark, 0, 0.95, 8.95)
  }
}

// MARK: Planes
// Airliners and the business jet use the fighter toolkit: fuselages lofted
// through oval sections, NACA-section wings and tails, lathe-turned
// nacelles, and windows, doors and stripes draped onto the skin. They sit
// on their landing gear.

let fanDark = material("intake", 0x1A1C1F, metal: 0.6, rough: 0.4)
let fanBlades = material("fan", 0x8B9096, metal: 0.9, rough: 0.3)
let bellyGrey = material("belly", 0xC9CED4, metal: 0.25, rough: 0.4)
let wingPanel = material("wing", 0xCDD2D8, metal: 0.3, rough: 0.4)

struct AirlinerSpec {
  var length: Float, radius: Float, span: Float
  var wingZ: Float          // wing root leading edge from the nose
  var rootChord: Float, tipChord: Float, sweep: Float
  var engineD: Float, engineL: Float, engineS: Float
  var finHeight: Float, finRoot: Float, stabSpan: Float
  var windows: Int
}

let narrowbody = AirlinerSpec(length: 37.6, radius: 1.98, span: 35.8, wingZ: 13.6, rootChord: 6.2, tipChord: 1.5, sweep: 0.47,
                              engineD: 2.05, engineL: 4.4, engineS: 5.75, finHeight: 6.2, finRoot: 5.6, stabSpan: 12.45, windows: 30)
let twinAisle = AirlinerSpec(length: 63.7, radius: 3.1, span: 64.8, wingZ: 23.5, rootChord: 11.5, tipChord: 2.4, sweep: 0.55,
                             engineD: 3.45, engineL: 7.3, engineS: 9.9, finHeight: 9.6, finRoot: 9.5, stabSpan: 21.5, windows: 50)

func airliner(livery: UInt32, spec: AirlinerSpec = narrowbody) -> SCNNode {
  let s = spec, L = s.length, R = s.radius
  let p = paint(livery)
  let body = material("white", 0xF4F5F7, metal: 0.25, rough: 0.3)
  let cy: Float = R + R * 0.75
  return fighter(length: L) { a in
    let shape: [(Float, Float, Float)] = [(0.012, 0.32, -0.2), (0.03, 0.58, -0.12), (0.06, 0.82, -0.05), (0.1, 0.96, -0.01), (0.15, 1, 0),
                                          (0.68, 1, 0), (0.78, 0.88, 0.12), (0.88, 0.6, 0.34), (0.96, 0.3, 0.52), (1.0, 0.1, 0.6)]
    var keys = [Ring(z: 0, half: noseTip(cy - 0.2 * R, 13))]
    for (f, k, dy) in shape {
      let c = cy + dy * R
      keys.append(Ring(z: f * L, half: ovalHalf(R * k, c - R * k * 0.98, c + R * k, n: 2, count: 13)))
    }
    jetBody(a, keys, step: L / 160, capEnd: body) { f in f.n.y < -0.85 && f.p.z + L / 2 > L * 0.3 && f.p.z + L / 2 < L * 0.62 ? bellyGrey : body }
    // Windows, cockpit glass, doors, cheat line.
    let sd = Drape(a, axis: 0), fd = Drape(a, axis: 2)
    let wy = cy + R * 0.18, wh = R * 0.17, ww = R * 0.11
    let z0 = L * 0.15, z1 = L * 0.74
    var panes: [[SIMD2<Float>]] = []
    for i in 0..<s.windows {
      let z = z0 + (z1 - z0) * Float(i) / Float(s.windows - 1)
      if abs(z - (s.wingZ + s.rootChord * 0.5)) < R * 0.3 { continue }
      panes.append(rounded([SIMD2(z - ww, wy - wh), SIMD2(z + ww, wy - wh), SIMD2(z + ww, wy + wh), SIMD2(z - ww, wy + wh)], r: ww * 0.9, steps: 2))
    }
    sidePatches(a, sd, panes, glass, lift: 0.01, k: 2)
    sidePatches(a, sd, [[SIMD2(L * 0.03, cy - R * 0.14), SIMD2(L * 0.97, cy + R * 0.3), SIMD2(L * 0.97, cy + R * 0.36), SIMD2(L * 0.03, cy - R * 0.06)]], p, lift: 0.008, k: 6)
    for dz in [L * 0.1, L * 0.82] {
      sideLines(a, sd, [closed(rounded([SIMD2(dz, cy - R * 0.55), SIMD2(dz + R * 0.42, cy - R * 0.55), SIMD2(dz + R * 0.42, cy + R * 0.48),
                                         SIMD2(dz, cy + R * 0.48)], r: R * 0.1))], width: L * 0.0008, slat)
    }
    decalPatches(a, fd, [[SIMD2(0.05, cy + R * 0.12), SIMD2(R * 0.32, cy + R * 0.1), SIMD2(R * 0.3, cy + R * 0.3), SIMD2(0.05, cy + R * 0.36)],
                         [SIMD2(R * 0.36, cy + R * 0.09), SIMD2(R * 0.62, cy + R * 0.02), SIMD2(R * 0.56, cy + R * 0.22), SIMD2(R * 0.34, cy + R * 0.29)]],
                 glass, below: true, mirror: true, lift: 0.01, k: 3)
    // Belly fairing.
    motoBody(a, [(s.wingZ - 1.5, R * 0.3, cy - R * 1.02, cy - R * 0.7), (s.wingZ + 1, R * 0.86, cy - R * 1.1, cy - R * 0.4),
                 (s.wingZ + s.rootChord, R * 0.86, cy - R * 1.08, cy - R * 0.4), (s.wingZ + s.rootChord + 2.5, R * 0.3, cy - R * 0.98, cy - R * 0.7)],
             step: L / 120, rb: 0.6, rt: 0.3, cap: bellyGrey) { _ in bellyGrey }
    // Wings with winglets and engines.
    let half = s.span / 2
    let kinkS = half * 0.36
    var wings: [WingSurface] = []
    for side in [-1, 1] as [Float] {
      let y0 = cy - R * 0.62
      let dih: Float = 0.09
      let st = [WS(s: R * 0.4, le: s.wingZ, te: s.wingZ + s.rootChord, t: s.rootChord * 0.14, y: y0),
                WS(s: kinkS, le: s.wingZ + kinkS * s.sweep, te: s.wingZ + s.rootChord * 0.92 + kinkS * 0.12, t: s.rootChord * 0.1, y: y0 + kinkS * dih),
                WS(s: half - 0.3, le: s.wingZ + (half - 0.3) * s.sweep * 1.02, te: s.wingZ + (half - 0.3) * s.sweep * 1.02 + s.tipChord, t: s.tipChord * 0.1,
                   y: y0 + half * dih)]
      wings.append(wingSkin(a, st, side: side, chord: 9, sub: 4) { _ in wingPanel })
      let tip = st[2]
      let wl = finFrame(a, x: tip.s, y: tip.y, cant: 0.3, side: side)
      wingSkin(wl, [WS(s: 0, le: tip.le, te: tip.te, t: s.tipChord * 0.1, y: 0), WS(s: s.span * 0.07, le: tip.te - s.tipChord * 0.45, te: tip.te + 0.1,
                                                                                 t: 0.06, y: 0)], side: side, chord: 6, sub: 1) { _ in p }
      // Engine under the wing, ahead of the leading edge, on a pylon.
      let ex = side * s.engineS, ez0 = s.wingZ + s.engineS * s.sweep - s.engineL * 0.62
      let ey = y0 + s.engineS * dih - s.engineD * 0.55
      let D = s.engineD, EL = s.engineL
      put(a, LatheMesh([SIMD2(0, D * 0.44), SIMD2(EL * 0.03, D * 0.5), SIMD2(EL * 0.2, D * 0.52), SIMD2(EL * 0.55, D * 0.5), SIMD2(EL * 0.82, D * 0.4),
                        SIMD2(EL, D * 0.33)], sides: 32, caps: false), p, ex, ey, ez0, rx: .pi / 2)
      put(a, LatheMesh([SIMD2(-0.001, D * 0.44), SIMD2(EL * 0.12, D * 0.44)], sides: 32, caps: false, twoSided: true), fanDark, ex, ey, ez0, rx: .pi / 2)
      put(a, CylinderMesh(radius: CGFloat(D * 0.43), height: 0.05, sides: 32), fanBlades, ex, ey, ez0 + EL * 0.14, rx: .pi / 2)
      put(a, LatheMesh([SIMD2(0, D * 0.13), SIMD2(D * 0.2, 0.001)], sides: 16), chrome, ex, ey, ez0 + EL * 0.14, rx: -.pi / 2)
      put(a, LatheMesh([SIMD2(EL, D * 0.3), SIMD2(EL + D * 0.4, D * 0.22), SIMD2(EL + D * 0.75, 0.001)], sides: 20), engineSilver, ex, ey, ez0, rx: .pi / 2)
      strut(a, V3(ex, ey + D * 0.42, ez0 + EL * 0.3), V3(ex, y0 + s.engineS * dih - 0.05, s.wingZ + s.engineS * s.sweep + s.rootChord * 0.45),
            D * 0.14, 0.4, body, up: V3(1, 0, 0))
    }
    for w in wings {
      wingLines(w, [[SIMD2(kinkS + 0.5, w.z(kinkS + 0.5, 0.78)), SIMD2(half * 0.82, w.z(half * 0.82, 0.76)), SIMD2(half * 0.82, w.z(half * 0.82, 1))],
                    [SIMD2(R * 0.6, w.z(R * 0.6, 0.78)), SIMD2(kinkS, w.z(kinkS, 0.8)), SIMD2(kinkS, w.z(kinkS, 1))]], width: L * 0.0012, slat)
    }
    // Tailplane and fin.
    let tz = L * 0.83, ty = cy + R * 0.25
    for side in [-1, 1] as [Float] {
      wingSkin(a, [WS(s: R * 0.2, le: tz, te: tz + s.finRoot * 0.75, t: 0.5, y: ty), WS(s: s.stabSpan / 2, le: tz + s.stabSpan / 2 * 0.6, te: tz + s.stabSpan / 2 * 0.6 + s.finRoot * 0.28,
                                                                                    t: 0.15, y: ty + s.stabSpan * 0.04)], side: side, chord: 7, sub: 2) { _ in wingPanel }
    }
    let fin = finFrame(a, x: 0, y: cy + R * 0.55, cant: 0, side: 1)
    wingSkin(fin, [WS(s: -R * 0.3, le: L * 0.76, te: L * 0.76 + s.finRoot * 1.15, t: 0.6, y: 0), WS(s: 0.4, le: L * 0.8, te: L * 0.8 + s.finRoot, t: 0.55, y: 0),
                   WS(s: s.finHeight, le: L * 0.8 + s.finHeight * 0.8, te: L * 0.8 + s.finHeight * 0.8 + s.finRoot * 0.36, t: 0.18, y: 0)],
             side: 1, chord: 8, sub: 2) { _ in p }
    // Gear: nose and two main bogies.
    let gw = R * 0.32
    tube(a, V3(0, cy - R * 0.9, L * 0.11), V3(0, gw, L * 0.11), R * 0.05, chrome, sides: 10)
    for x in [-0.12, 0.12] as [Float] { put(a, TubeMesh(innerRadius: CGFloat(gw * 0.45), outerRadius: CGFloat(gw), height: CGFloat(gw * 0.6), sides: 20), tyre, x * R * 1.6, gw, L * 0.11, rz: .pi / 2) }
    for side in [-1, 1] as [Float] {
      let x = side * R * 1.3, z = s.wingZ + s.rootChord * 0.85
      tube(a, V3(x, cy - R * 0.7, z), V3(x, gw * 1.1, z), R * 0.07, chrome, sides: 10)
      for dz in (s.length > 50 ? [-0.75, 0, 0.75] : [0]) as [Float] {
        for dx in [-0.3, 0.3] as [Float] {
          put(a, TubeMesh(innerRadius: CGFloat(gw * 0.5), outerRadius: CGFloat(gw * 1.25), height: CGFloat(gw * 0.7), sides: 22), tyre, x + dx * R * 0.6, gw * 1.25, z + dz * R * 0.6, rz: .pi / 2)
        }
      }
    }
    navLights(a, x: half, y: cy - R * 0.62 + half * 0.09 + 0.05, z: s.wingZ + (half - 0.3) * s.sweep + s.tipChord * 0.3)
  }
}

func widebody(livery: UInt32) -> SCNNode { airliner(livery: livery, spec: twinAisle) }

// Long-range business jet (G650 class): 30.4 m, 30.4 m span, big oval
// windows, swept wing with blended winglets, rear-mounted engines on
// stub pylons, T-tail.
func privateJet(livery: UInt32) -> SCNNode {
  let L: Float = 30.4, R: Float = 1.3
  let p = paint(livery)
  let body = material("white", 0xF4F5F7, metal: 0.25, rough: 0.3)
  let cy: Float = R + 1.0
  return fighter(length: L) { a in
    let shape: [(Float, Float, Float)] = [(0.015, 0.35, -0.25), (0.04, 0.62, -0.15), (0.08, 0.86, -0.05), (0.13, 0.98, 0), (0.18, 1, 0),
                                          (0.62, 1, 0), (0.75, 0.84, 0.12), (0.88, 0.55, 0.32), (0.97, 0.26, 0.48), (1.0, 0.1, 0.52)]
    var keys = [Ring(z: 0, half: noseTip(cy - 0.25 * R, 13))]
    for (f, k, dy) in shape {
      let c = cy + dy * R
      keys.append(Ring(z: f * L, half: ovalHalf(R * k, c - R * k * 0.98, c + R * k, n: 2, count: 13)))
    }
    jetBody(a, keys, step: L / 140, capEnd: body) { _ in body }
    // Big oval windows, cockpit glass, cheat lines, door.
    let sd = Drape(a, axis: 0), fd = Drape(a, axis: 2)
    sidePatches(a, sd, (0..<9).map { i in
      let z = 6.6 + Float(i) * 1.4
      return (0..<14).map { k in let t = Float(k) / 14 * 2 * .pi; return SIMD2(z + cos(t) * 0.33, cy + 0.25 + sin(t) * 0.26) }
    }, glass, lift: 0.01, k: 2)
    sidePatches(a, sd, [[SIMD2(1.0, cy - 0.55), SIMD2(29.0, cy + 0.2), SIMD2(29.0, cy + 0.3), SIMD2(1.0, cy - 0.43)],
                        [SIMD2(1.5, cy - 0.75), SIMD2(29.0, cy - 0.05), SIMD2(29.0, cy + 0.0), SIMD2(1.5, cy - 0.68)]], p, lift: 0.008, k: 6)
    sideLines(a, sd, [closed(rounded([SIMD2(4.4, cy - 0.85), SIMD2(5.3, cy - 0.85), SIMD2(5.3, cy + 0.85), SIMD2(4.4, cy + 0.85)], r: 0.15))], width: 0.03, slat, right: false)
    decalPatches(a, fd, [[SIMD2(0.05, cy + 0.12), SIMD2(0.42, cy + 0.08), SIMD2(0.4, cy + 0.42), SIMD2(0.05, cy + 0.48)],
                         [SIMD2(0.46, cy + 0.07), SIMD2(0.82, cy - 0.04), SIMD2(0.74, cy + 0.26), SIMD2(0.44, cy + 0.4)]], glass, below: true, mirror: true, lift: 0.01, k: 3)
    let half: Float = 15.2, wz: Float = 11.4
    for side in [-1, 1] as [Float] {
      let y0 = cy - R * 0.72
      let st = [WS(s: R * 0.3, le: wz, te: wz + 5.4, t: 0.7, y: y0), WS(s: 4.0, le: wz + 2.6, te: wz + 6.0, t: 0.42, y: y0 + 0.3),
                WS(s: half - 0.4, le: wz + 9.0, te: wz + 10.4, t: 0.15, y: y0 + 1.0)]
      wingSkin(a, st, side: side, chord: 9, sub: 4) { _ in wingPanel }
      let wl = finFrame(a, x: half - 0.4, y: y0 + 1.0, cant: 0.25, side: side)
      wingSkin(wl, [WS(s: 0, le: wz + 9.0, te: wz + 10.4, t: 0.15, y: 0), WS(s: 1.4, le: wz + 10.2, te: wz + 10.8, t: 0.05, y: 0)], side: side, chord: 5, sub: 1) { _ in p }
      // Rear engine on a stub pylon.
      let ex = side * (R + 0.95), ey = cy + R * 0.35, ez0: Float = 19.6, D: Float = 1.45, EL: Float = 4.4
      put(a, LatheMesh([SIMD2(0, D * 0.44), SIMD2(EL * 0.04, D * 0.5), SIMD2(EL * 0.3, D * 0.52), SIMD2(EL * 0.7, D * 0.47), SIMD2(EL, D * 0.34)],
                       sides: 28, caps: false), p, ex, ey, ez0, rx: .pi / 2)
      put(a, CylinderMesh(radius: CGFloat(D * 0.43), height: 0.05, sides: 28), fanBlades, ex, ey, ez0 + 0.4, rx: .pi / 2)
      put(a, LatheMesh([SIMD2(-0.001, D * 0.44), SIMD2(0.38, D * 0.44)], sides: 28, caps: false, twoSided: true), fanDark, ex, ey, ez0, rx: .pi / 2)
      put(a, LatheMesh([SIMD2(EL, D * 0.32), SIMD2(EL + 0.5, D * 0.2), SIMD2(EL + 0.8, 0.001)], sides: 20), engineSilver, ex, ey, ez0, rx: .pi / 2)
      wingSkin(a, [WS(s: R * 0.6, le: ez0 + 1.4, te: ez0 + 3.6, t: 0.3, y: ey), WS(s: R + 0.4, le: ez0 + 1.6, te: ez0 + 3.4, t: 0.25, y: ey)],
               side: side, chord: 5, sub: 1) { _ in body }
    }
    // T-tail.
    let finF = finFrame(a, x: 0, y: cy + R * 0.55, cant: 0, side: 1)
    wingSkin(finF, [WS(s: -0.3, le: 22.5, te: 28.6, t: 0.4, y: 0), WS(s: 4.3, le: 26.6, te: 29.6, t: 0.22, y: 0)], side: 1, chord: 7, sub: 2) { _ in p }
    for side in [-1, 1] as [Float] {
      wingSkin(a, [WS(s: 0.1, le: 26.5, te: 29.5, t: 0.24, y: cy + R * 0.55 + 4.3), WS(s: 5.0, le: 29.0, te: 30.4, t: 0.1, y: cy + R * 0.55 + 4.5)],
               side: side, chord: 6, sub: 2) { _ in wingPanel }
    }
    // Gear.
    tube(a, V3(0, cy - R * 0.9, 3.4), V3(0, 0.3, 3.4), 0.08, chrome, sides: 8)
    for x in [-0.15, 0.15] as [Float] { put(a, TubeMesh(innerRadius: 0.12, outerRadius: 0.3, height: 0.2, sides: 18), tyre, x, 0.3, 3.4, rz: .pi / 2) }
    for side in [-1, 1] as [Float] {
      tube(a, V3(side * 1.9, cy - R * 0.7, wz + 4.8), V3(side * 1.9, 0.42, wz + 4.8), 0.1, chrome, sides: 8)
      for dx in [-0.18, 0.18] as [Float] { put(a, TubeMesh(innerRadius: 0.18, outerRadius: 0.42, height: 0.24, sides: 18), tyre, side * 1.9 + dx, 0.42, wz + 4.8, rz: .pi / 2) }
    }
    navLights(a, x: half - 0.4, y: cy - R * 0.72 + 1.05, z: wz + 9.6)
  }
}

// MARK: Police and taxi extras

func lightbar(_ root: SCNNode, _ spec: CarSpec) {
  let y = spec.height + 0.06
  let zc = -spec.length / 2 + (spec.roofStart + spec.roofEnd) / 2 * spec.length
  box(root, 1.1, 0.1, 0.28, black, 0, y, zc)
  box(root, 0.5, 0.11, 0.26, material("light-red", 0xFF2D2D, emit: true), -0.27, y + 0.02, zc)
  box(root, 0.5, 0.11, 0.26, material("light-blue", 0x2D6BFF, emit: true), 0.27, y + 0.02, zc)
}

func spoiler(_ root: SCNNode, _ spec: CarSpec) {
  let z = spec.length / 2 - 0.25
  let y = spec.hoodHeight + 0.22
  box(root, spec.width * 0.82, 0.04, 0.32, paintMaterialOf(root), 0, y, z)
  for side in [-1, 1] as [Float] {
    box(root, 0.04, 0.2, 0.14, black, side * spec.width * 0.3, y - 0.11, z)
  }
  for side in [-1, 1] as [Float] { // twin exhausts
    tube(root, V3(side * 0.35, spec.wheelRadius * 0.6, spec.length / 2 - 0.1), V3(side * 0.35, spec.wheelRadius * 0.6, spec.length / 2 + 0.04), 0.045, chrome)
  }
}

func taxiSign(_ root: SCNNode, _ spec: CarSpec) {
  let zc = -spec.length / 2 + (spec.roofStart + spec.roofEnd) / 2 * spec.length
  box(root, 0.7, 0.2, 0.3, material("taxi-sign", 0xFFF9C4, emit: true), 0, spec.height + 0.1, zc)
  for side in [-1, 1] as [Float] {
    box(root, 0.02, 0.05, spec.length * 0.6, black, side * (spec.width / 2 + 0.005), spec.hoodHeight - 0.25, 0)
  }
}

func pickupBed(_ root: SCNNode, _ spec: CarSpec) {
  // Open load bed behind the cab: floor, sides and tailgate in body paint,
  // painted over the rear of the lower body.
  let bedStart = -spec.length / 2 + spec.cabinEnd * spec.length + 0.05
  let bedEnd = spec.length / 2 - 0.08
  let top = spec.hoodHeight + 0.18
  let len = bedEnd - bedStart
  let zc = (bedStart + bedEnd) / 2
  box(root, spec.width * 0.86, 0.04, len, black, 0, spec.hoodHeight + 0.02, zc)
  for side in [-1, 1] as [Float] {
    box(root, 0.08, top - spec.hoodHeight + 0.04, len, paintMaterialOf(root), side * (spec.width / 2 - 0.05), (top + spec.hoodHeight) / 2, zc)
  }
  box(root, spec.width * 0.92, top - spec.hoodHeight + 0.04, 0.08, paintMaterialOf(root), 0, (top + spec.hoodHeight) / 2, bedEnd)
  box(root, spec.width * 0.86, 0.04, 0.06, chrome, 0, top, bedStart)
}

func paintMaterialOf(_ root: SCNNode) -> SCNMaterial {
  var found: SCNMaterial?
  var top = root
  while let up = top.parent { top = up }
  top.enumerateHierarchy { n, stop in
    if let m = n.geometry?.firstMaterial, m.name == "paint" { found = m; stop.pointee = true }
  }
  return found ?? paint(0xC0C0C0)
}


// MARK: More cars

let evSedan = CarSpec(length: 4.7, width: 1.85, height: 1.44, wheelRadius: 0.34, wheelbase: 2.88,
                      hoodHeight: 0.86, cabinStart: 0.27, cabinEnd: 0.92, roofStart: 0.40, roofEnd: 0.64, grille: false)
let wagon = CarSpec(length: 4.85, width: 1.85, height: 1.5, wheelRadius: 0.33, wheelbase: 2.85,
                    hoodHeight: 0.92, cabinStart: 0.29, cabinEnd: 0.98, roofStart: 0.42, roofEnd: 0.93)
let minivan = CarSpec(length: 5.1, width: 1.99, height: 1.78, wheelRadius: 0.35, wheelbase: 3.05,
                      hoodHeight: 1.02, cabinStart: 0.17, cabinEnd: 0.99, roofStart: 0.30, roofEnd: 0.95, boxy: 4)
let supercar = CarSpec(length: 4.6, width: 2.03, height: 1.12, wheelRadius: 0.35, wheelbase: 2.7,
                       hoodHeight: 0.74, cabinStart: 0.30, cabinEnd: 0.78, roofStart: 0.45, roofEnd: 0.58)
let convertible = CarSpec(length: 4.4, width: 1.85, height: 1.3, wheelRadius: 0.33, wheelbase: 2.6,
                          hoodHeight: 0.86, cabinStart: 0.38, cabinEnd: 0.75, roofStart: 0.48, roofEnd: 0.62, roofless: true)
let offroader = CarSpec(length: 4.3, width: 1.9, height: 1.86, wheelRadius: 0.42, wheelbase: 2.45,
                        hoodHeight: 1.18, cabinStart: 0.33, cabinEnd: 0.97, roofStart: 0.38, roofEnd: 0.95, boxy: 7)

func offroadGear(_ root: SCNNode, _ spec: CarSpec) {
  // Spare wheel on the tailgate, roof rack, chunky bumpers.
  carWheel(root, x: 0, y: spec.hoodHeight * 0.85, z: spec.length / 2 + 0.16, radius: spec.wheelRadius, width: 0.24, outward: 1)
  root.childNodes.last?.simdOrientation = simd_quatf(angle: .pi / 2, axis: V3(0, 1, 0))
  let roofZ = -spec.length / 2 + (spec.roofStart + spec.roofEnd) / 2 * spec.length
  for x in [-0.7, 0.7] as [Float] { box(root, 0.05, 0.05, spec.length * 0.5, black, x, spec.height + 0.06, roofZ) }
  for z in [-0.6, 0, 0.6] as [Float] { box(root, 1.45, 0.04, 0.05, black, 0, spec.height + 0.09, roofZ + z) }
  box(root, spec.width + 0.05, 0.2, 0.22, black, 0, spec.wheelRadius * 0.9, -spec.length / 2 - 0.05)
  box(root, spec.width + 0.05, 0.2, 0.22, black, 0, spec.wheelRadius * 0.9, spec.length / 2 + 0.02)
}

// MARK: Road vehicle tools
// Vans, trucks and buses are built like the jets: nose-first along +Z from
// z = 0 (a holder moves the nose to -L/2), bodies skinned through
// rounded-box half-sections sampled every few centimetres, then windows,
// seams, lights and stripes draped onto the skin from the side, the front,
// the back or above, so they follow its curves exactly. Parts that stick
// out (mirrors, wheels, bumpers) are added after the drapes are taken.

/// Builds a ground vehicle nose-first along +Z (nose at z = 0) and collapses
/// it into one mesh per material, wheels on y = 0.
func roadVehicle(length L: Float, _ build: (SCNNode) -> Void) -> SCNNode {
  spacecraft { r in build(holder(r, V3(0, 0, -L / 2))) }
}

/// A smooth curve through (x, y) keys (monotone, so it never overshoots).
func curve(_ keys: [(Float, Float)]) -> (Float) -> Float {
  let xs = keys.map { $0.0 }, ys = keys.map { $0.1 }
  return { monotoneCubic(xs, ys, $0) }
}

/// A rounded-box half-section from bottom centre round the side to top
/// centre: `hw` half width, bottom `b`, top `t`, corner radii `rb` and `rt`,
/// the side leaning in by `lean` at the top and bowing out by `bow` midway.
func boxHalf(_ hw: Float, _ b: Float, _ t: Float, rb: Float, rt: Float, lean: Float = 0, bow: Float = 0,
             sides: Int = 6, arc: Int = 5) -> [SIMD2<Float>] {
  let h = max(0.002, t - b)
  let rb = max(0.001, min(rb, hw * 0.98, h * 0.49)), rt = max(0.001, min(rt, (hw - lean) * 0.98, h * 0.49))
  var pts: [SIMD2<Float>] = [SIMD2(0, b), SIMD2(max(0.0005, hw - rb) * 0.5, b)]
  for i in 0...arc {
    let a = -Float.pi / 2 + Float.pi / 2 * Float(i) / Float(arc)
    pts.append(SIMD2(hw - rb + rb * cos(a), b + rb + rb * sin(a)))
  }
  let s0 = SIMD2<Float>(hw, b + rb), s1 = SIMD2<Float>(hw - lean, t - rt)
  for i in 1..<sides {
    let f = Float(i) / Float(sides)
    pts.append(s0 + (s1 - s0) * f + SIMD2(bow * sin(.pi * f), 0))
  }
  for i in 0...arc {
    let a = Float.pi / 2 * Float(i) / Float(arc)
    pts.append(SIMD2(hw - lean - rt + rt * cos(a), t - rt + rt * sin(a)))
  }
  pts.append(SIMD2(max(0.0005, hw - lean - rt) * 0.5, t))
  pts.append(SIMD2(0, t))
  return pts
}

/// A body skinned through half-sections given as a function of z, sampled
/// at `zs`, mirrored about x = `x`.
func shell(_ p: SCNNode, _ zs: [Float], x: Float = 0, sharp: Set<Int> = [], capStart: SCNMaterial? = nil, capEnd: SCNMaterial? = nil,
           tolerance: Float = 0.003, _ section: (Float) -> [SIMD2<Float>], skin: (Facet) -> SCNMaterial) {
  var rows: [[V3]] = []
  var k = 0
  for z in zs {
    let half = section(z)
    k = half.count
    var ring = half.map { V3(x + $0.x, $0.y, z) }
    for i in stride(from: k - 2, through: 1, by: -1) { ring.append(V3(x - half[i].x, half[i].y, z)) }
    rows.append(ring)
  }
  var crease = (0..<k).map { sharp.contains($0) }
  for i in stride(from: k - 2, through: 1, by: -1) { crease.append(sharp.contains(i)) }
  gridSkin(p, rows: simplifyRows(rows, zs: zs, tolerance: tolerance), crease: crease, capStart: capStart, capEnd: capEnd, skin: skin)
}

/// Drops rows that lie within `tolerance` of the straight blend between the
/// rows kept either side (Douglas-Peucker over whole sections), so flat
/// sides cost two rows however finely they were sampled.
func simplifyRows(_ rows: [[V3]], zs: [Float], tolerance: Float) -> [[V3]] {
  guard rows.count > 2, tolerance > 0 else { return rows }
  var keep = [Bool](repeating: false, count: rows.count)
  keep[0] = true; keep[rows.count - 1] = true
  func split(_ lo: Int, _ hi: Int) {
    guard hi - lo > 1 else { return }
    var worst: Float = 0, at = -1
    for i in (lo + 1)..<hi {
      let t = (zs[i] - zs[lo]) / max(1e-6, zs[hi] - zs[lo])
      var dev: Float = 0
      for j in 0..<rows[i].count {
        dev = max(dev, simd_length(rows[i][j] - (rows[lo][j] + (rows[hi][j] - rows[lo][j]) * t)))
      }
      if dev > worst { worst = dev; at = i }
    }
    if worst > tolerance { keep[at] = true; split(lo, at); split(at, hi) }
  }
  split(0, rows.count - 1)
  return rows.indices.filter { keep[$0] }.map { rows[$0] }
}

/// A polyline resampled to `n` points evenly along its length (so hull
/// sections with different shapes keep the same point count).
func resample(_ pts: [SIMD2<Float>], _ n: Int) -> [SIMD2<Float>] {
  var lens: [Float] = [0]
  for i in 1..<pts.count { lens.append(lens[i - 1] + simd_length(pts[i] - pts[i - 1])) }
  let total = max(1e-6, lens[lens.count - 1])
  return (0..<n).map { j in
    let d = total * Float(j) / Float(n - 1)
    var i = 1
    while i < pts.count - 1 && lens[i] < d { i += 1 }
    let f = (d - lens[i - 1]) / max(1e-6, lens[i] - lens[i - 1])
    return pts[i - 1] + (pts[i] - pts[i - 1]) * max(0, min(1, f))
  }
}

/// Sample positions from a to b about every `step`, plus extra cuts, sorted.
func samples(_ a: Float, _ b: Float, step: Float, dense: [(Float, Float, Float)] = []) -> [Float] {
  var zs: [Float] = []
  var z = a
  while z < b - step * 0.3 { zs.append(z); z += step }
  zs.append(b)
  for (z0, z1, s) in dense {
    var q = z0
    while q < z1 { zs.append(q); q += s }
  }
  zs = zs.filter { $0 >= a && $0 <= b }.sorted()
  var out: [Float] = []
  for q in zs where out.last.map({ q - $0 > 0.004 }) ?? true { out.append(q) }
  return out
}

/// The underside lifted into round wheel arches over each axle.
func archBottom(_ base: Float, axles: [Float], wheel r: Float, gap: Float = 0.06) -> (Float) -> Float {
  { z in
    var b = base
    let R = r + gap
    for a in axles where abs(z - a) < R * 1.25 {
      let u = min(1, abs(z - a) / R)
      b = max(b, r + R * (1 - u * u).squareRoot() * 0.97)
    }
    return b
  }
}

/// A road wheel with a rounded tyre, a dished rim, a hub and lug nuts, axle
/// along X, its outer face towards `outward`. `holes` dark vents ring the
/// hub (steel and alloy wheels); `dual` adds an inner twin (trucks).
func roadWheel(_ p: SCNNode, x: Float, y: Float, z: Float, radius r: Float, width w: Float, outward: Float,
               rimRatio: Float = 0.62, rimMaterial: SCNMaterial = rim, holes: Int = 0, lugs: Int = 6,
               hub: SCNMaterial = chrome, dual: Bool = false) {
  let wh = holder(p, V3(x, y, z), ry: outward > 0 ? 0 : .pi)
  let rr = r * rimRatio, hw = w / 2
  let mid = (r + rr) / 2, ext = (r - rr) / 2
  // Tyre: a rounded cross-section swept round the axle (outer face at +X).
  var prof: [SIMD2<Float>] = [SIMD2(-hw * 0.86, rr * 0.97)]
  for i in 0...6 {
    let t = -Float.pi / 2 + Float.pi * Float(i) / 6
    let s = sin(t), c = cos(t)
    prof.append(SIMD2(hw * (s < 0 ? -1 : 1) * pow(abs(s), 2 / 3.2), mid + ext * 1.0 * pow(abs(c), 2 / 3.2)))
  }
  prof.append(SIMD2(hw * 0.86, rr * 0.97))
  let tyreG = LatheMesh(prof, sides: 24, caps: false)
  put(wh, tyreG, tyre, 0, 0, 0, rz: -.pi / 2)
  if dual { put(wh, LatheMesh(prof, sides: 24, caps: false), tyre, -(w + 0.04), 0, 0, rz: -.pi / 2) }
  // Rim: barrel, lip, then a dished face down to the hub.
  let dish: [SIMD2<Float>] = [SIMD2(-hw * 0.85, rr * 0.98), SIMD2(hw * 0.7, rr * 0.98), SIMD2(hw * 0.76, rr * 0.92),
                              SIMD2(hw * 0.6, rr * 0.82), SIMD2(hw * 0.46, rr * 0.5), SIMD2(hw * 0.44, rr * 0.3),
                              SIMD2(hw * 0.58, rr * 0.26), SIMD2(hw * 0.62, 0.001)]
  put(wh, LatheMesh(dish, sides: 20, caps: false, twoSided: true), rimMaterial, 0, 0, 0, rz: -.pi / 2)
  for i in 0..<lugs {
    let a = Float(i) / Float(lugs) * 2 * .pi
    put(wh, CylinderMesh(radius: CGFloat(rr * 0.045), height: CGFloat(w * 0.1), sides: 6), hub,
        hw * 0.52, sin(a) * rr * 0.36, cos(a) * rr * 0.36, rz: .pi / 2)
  }
  for i in 0..<holes {
    let a = (Float(i) + 0.5) / Float(holes) * 2 * .pi
    put(wh, CylinderMesh(radius: CGFloat(rr * 0.11), height: 0.01, sides: 8), black,
        hw * 0.53 + 0.004, sin(a) * rr * 0.64, cos(a) * rr * 0.64, rz: .pi / 2)
  }
}

/// A closed outline with rounded corners (radius r), from corner points.
func rounded(_ pts: [SIMD2<Float>], r: Float, steps: Int = 3) -> [SIMD2<Float>] {
  var out: [SIMD2<Float>] = []
  let n = pts.count
  for i in 0..<n {
    let p = pts[i], a = pts[(i + n - 1) % n], b = pts[(i + 1) % n]
    let da = simd_normalize(a - p), db = simd_normalize(b - p)
    let rr = min(r, simd_length(a - p) * 0.45, simd_length(b - p) * 0.45)
    let s = p + da * rr, e = p + db * rr
    for k in 0...steps {
      let t = Float(k) / Float(steps)
      // Quadratic Bezier with the corner as control point.
      out.append(s * (1 - t) * (1 - t) + p * 2 * (1 - t) * t + e * t * t)
    }
  }
  return out
}

/// An outline's boundary as a closed polyline.
func closed(_ pts: [SIMD2<Float>]) -> [SIMD2<Float>] { pts + [pts[0]] }

/// Draped onto both sides at once: (z, y) shapes on the right side and
/// their mirror images on the left.
func sidePatches(_ p: SCNNode, _ d: Drape, _ polys: [[SIMD2<Float>]], _ m: SCNMaterial, right: Bool = true, left: Bool = true,
                 lift: Float = 0.012, k: Int = 4) {
  if right { decalPatches(p, d, polys, m, below: false, lift: lift, k: k) }
  if left { decalPatches(p, d, polys, m, below: true, lift: lift, k: k) }
}

func sideLines(_ p: SCNNode, _ d: Drape, _ lines: [[SIMD2<Float>]], width: Float = 0.02, _ m: SCNMaterial, right: Bool = true,
               left: Bool = true, lift: Float = 0.014) {
  if right { decalLines(p, d, lines, width: width, m, below: false, mirror: false, lift: lift, maxSteps: 14) }
  if left { decalLines(p, d, lines, width: width, m, below: true, mirror: false, lift: lift, maxSteps: 14) }
}

/// A star-of-life style six-armed cross centred at (u, v).
func starOfLife(_ u: Float, _ v: Float, _ s: Float) -> [[SIMD2<Float>]] {
  (0..<3).map { k in
    let a = Float(k) * .pi / 3
    let d = SIMD2(cos(a), sin(a)), n = SIMD2(-sin(a), cos(a))
    let c = SIMD2(u, v)
    return [c - d * s - n * s * 0.2, c + d * s - n * s * 0.2, c + d * s + n * s * 0.2, c - d * s + n * s * 0.2]
  }
}

/// A side mirror: an arm from the door to a housing with glass facing back.
func sideMirror(_ p: SCNNode, at a: V3, side: Float, reach: Float, w: Float, h: Float, _ body: SCNMaterial) {
  let tip = a + V3(side * reach, 0.02, 0.02)
  tube(p, a, tip, 0.018, black, sides: 8)
  let housing = holder(p, tip + V3(side * w * 0.35, 0, 0))
  shell(housing, samples(-0.05, 0.07, step: 0.03), { z in
    let f = (z + 0.05) / 0.12
    return boxHalf(w / 2 * (0.75 + 0.25 * f), -h / 2 * (0.8 + 0.2 * f), h / 2 * (0.8 + 0.2 * f), rb: 0.03, rt: 0.03, sides: 3, arc: 3)
  }, skin: { _ in body })
  put(housing, BoxMesh(width: CGFloat(w * 0.88), height: CGFloat(h * 0.86), length: 0.004), glass, 0, 0, 0.072)
}

// MARK: Vans, trucks and buses

let trimPlastic = material("plastic", 0x2C2D30, rough: 0.7)
let lens = material("lens", 0xBFC6CF, metal: 0.6, rough: 0.15)
let reflectorRed = material("reflector", 0xB0121F, rough: 0.35)
let stripeRed = material("stripe-red", 0xD7192C, rough: 0.4)
let lifeBlue = material("star-blue", 0x0B4DA2, rough: 0.4)
let lightRed = material("light-red", 0xFF2D2D, rough: 0.3, emit: true)
let lightWhite = material("light-white", 0xF4F6FF, rough: 0.3, emit: true)

// High-roof delivery van, Sprinter/Transit class: 5.93 m long, 2.02 m wide,
// 2.72 m tall, 3.67 m wheelbase. Short sloping bonnet, raked windscreen
// into a roof fairing, flat sides with a sliding door on the right, twin
// rear doors, wrap-round plastic bumpers and arch flares. The ambulance
// (Type II) adds a roof light bar, corner flashers, a red stripe and
// stars of life.
func deliveryVan(body: UInt32, ambulance: Bool = false) -> SCNNode {
  let L: Float = 5.93, hwMax: Float = 1.01, H: Float = ambulance ? 2.78 : 2.72
  let axles: [Float] = [1.0, 4.67], wr: Float = 0.355
  let p = paint(body)
  let top = curve([(0, 0.84), (0.1, 0.98), (0.32, 1.08), (0.75, 1.17), (0.97, 1.23), (1.35, 1.72), (1.76, 2.28),
                   (2.0, H - 0.12), (2.35, H - 0.01), (5.82, H), (L, H - 0.08)])
  let hw = curve([(0, 0.8), (0.07, 0.91), (0.25, 0.975), (0.6, 0.995), (1.2, hwMax), (5.86, hwMax), (L, 0.97)])
  let rt = curve([(0, 0.12), (0.9, 0.16), (1.3, 0.24), (2.0, 0.2), (2.4, 0.15), (L, 0.15)])
  let lean = curve([(0, 0.13), (0.9, 0.12), (1.5, 0.08), (2.4, 0.06), (L, 0.06)])
  let baseBottom = curve([(0, 0.42), (0.12, 0.36), (5.7, 0.36), (L, 0.46)])
  let bottom = archBottom(0.36, axles: axles, wheel: wr, gap: 0.07)
  let zs = samples(0, L, step: 0.07, dense: [(0, 0.35, 0.025), (0.5, 1.5, 0.025), (4.17, 5.17, 0.025), (5.75, L, 0.02)])
  return roadVehicle(length: L) { v in
    shell(v, zs, capStart: p, capEnd: p, { z in
      boxHalf(hw(z), max(baseBottom(z), bottom(z)), top(z), rb: 0.07, rt: rt(z), lean: lean(z), bow: 0.012, sides: 8, arc: 6)
    }, skin: { f in f.n.y < -0.75 ? trimPlastic : p })
    // Roof ribs.
    for x in [-0.55, -0.2, 0.2, 0.55] as [Float] {
      shell(v, samples(2.5, 5.6, step: 0.5), x: x, { _ in boxHalf(0.035, H - 0.02, H + 0.025, rb: 0.001, rt: 0.02, sides: 1, arc: 2) },
            skin: { _ in p })
    }
    let front = Drape(v, axis: 2), sides = Drape(v, axis: 0), above = Drape(v, axis: 1)
    // Front: windscreen, wipers, grille, headlights, bumper, plate.
    decalPatches(v, front, [rounded([SIMD2(-0.86, 1.31), SIMD2(0.86, 1.31), SIMD2(0.8, 2.22), SIMD2(-0.8, 2.22)], r: 0.09)],
                 glass, below: true, lift: 0.01, k: 8)
    decalLines(v, front, [[SIMD2(0.06, 1.36), SIMD2(0.62, 1.44)], [SIMD2(-0.72, 1.36), SIMD2(-0.16, 1.44)]], width: 0.025, black,
               below: true, mirror: false, lift: 0.02)
    decalPatches(v, front, [rounded([SIMD2(-0.44, 0.64), SIMD2(0.44, 0.64), SIMD2(0.48, 0.93), SIMD2(-0.48, 0.93)], r: 0.06)],
                 black, below: true, lift: 0.012, k: 5)
    decalLines(v, front, [[SIMD2(-0.42, 0.72), SIMD2(0.42, 0.72)], [SIMD2(-0.44, 0.8), SIMD2(0.44, 0.8)], [SIMD2(-0.46, 0.88), SIMD2(0.46, 0.88)]],
               width: 0.022, chrome, below: true, mirror: false, lift: 0.02)
    decalPatches(v, front, [rounded([SIMD2(0.52, 0.86), SIMD2(0.8, 0.88), SIMD2(0.84, 1.05), SIMD2(0.56, 1.0)], r: 0.04)],
                 lens, below: true, mirror: true, lift: 0.014)
    decalPatches(v, front, [rounded([SIMD2(0.58, 0.9), SIMD2(0.72, 0.91), SIMD2(0.74, 0.99), SIMD2(0.6, 0.97)], r: 0.03)],
                 headlight, below: true, mirror: true, lift: 0.02)
    decalPatches(v, front, [rounded([SIMD2(-0.82, 0.36), SIMD2(0.82, 0.36), SIMD2(0.82, 0.62), SIMD2(-0.82, 0.62)], r: 0.05)],
                 trimPlastic, below: true, lift: 0.012)
    decalPatches(v, front, [rounded([SIMD2(-0.26, 0.44), SIMD2(0.26, 0.44), SIMD2(0.26, 0.56), SIMD2(-0.26, 0.56)], r: 0.015)],
                 plate, below: true, lift: 0.02)
    decalPatches(v, front, [ring2(0.64, 0.49, 0.045, 12)], lens, below: true, mirror: true, lift: 0.02)
    decalPatches(v, front, [rounded([SIMD2(0.12, 2.5), SIMD2(0.26, 2.5), SIMD2(0.26, 2.56), SIMD2(0.12, 2.56)], r: 0.01),
                            rounded([SIMD2(-0.06, 2.5), SIMD2(0.06, 2.5), SIMD2(0.06, 2.56), SIMD2(-0.06, 2.56)], r: 0.01)],
                 amber, below: true, mirror: true, lift: 0.015)
    // Sides: cab door window, door seams, bumper wraps, cladding, arch flares.
    sidePatches(v, sides, [rounded([SIMD2(1.22, 1.38), SIMD2(2.0, 1.38), SIMD2(2.0, 2.14), SIMD2(1.84, 2.18)], r: 0.06)], glass, lift: 0.01, k: 6)
    sideLines(v, sides, [[SIMD2(1.46, 0.43), SIMD2(1.46, 0.96), SIMD2(1.14, 1.3)], [SIMD2(2.06, 0.43), SIMD2(2.06, 2.22)]], width: 0.012, black)
    sidePatches(v, sides, [rounded([SIMD2(1.86, 1.2), SIMD2(1.98, 1.2), SIMD2(1.98, 1.24), SIMD2(1.86, 1.24)], r: 0.01)], trimPlastic, lift: 0.02)
    sideLines(v, sides, [closed(rounded([SIMD2(2.14, 0.43), SIMD2(3.44, 0.43), SIMD2(3.44, 2.4), SIMD2(2.14, 2.4)], r: 0.07))], width: 0.012,
              black, left: false)
    sideLines(v, sides, [[SIMD2(3.44, 1.96), SIMD2(5.78, 1.96)]], width: 0.03, trimPlastic, left: false)
    sidePatches(v, sides, [rounded([SIMD2(2.26, 1.2), SIMD2(2.38, 1.2), SIMD2(2.38, 1.24), SIMD2(2.26, 1.24)], r: 0.01)], trimPlastic,
                left: false, lift: 0.02)
    sideLines(v, sides, [[SIMD2(5.8, 0.48), SIMD2(5.8, H - 0.1)]], width: 0.012, black)
    let R = wr + 0.07
    sidePatches(v, sides, [rounded([SIMD2(0.0, 0.36), SIMD2(axles[0] - R - 0.02, 0.36), SIMD2(axles[0] - R - 0.02, 0.62), SIMD2(0.0, 0.62)], r: 0.03),
                           rounded([SIMD2(axles[0] + R + 0.02, 0.37), SIMD2(axles[1] - R - 0.02, 0.37), SIMD2(axles[1] - R - 0.02, 0.5),
                                    SIMD2(axles[0] + R + 0.02, 0.5)], r: 0.02),
                           rounded([SIMD2(axles[1] + R + 0.02, 0.37), SIMD2(L, 0.37), SIMD2(L, 0.6), SIMD2(axles[1] + R + 0.02, 0.6)], r: 0.03)],
                trimPlastic, lift: 0.012)
    for a in axles {
      let arc = (0...16).map { i -> SIMD2<Float> in
        let t = Float.pi * Float(i) / 16
        return SIMD2(a - cos(t) * (R + 0.03), wr + sin(t) * (R + 0.03) * 0.97)
      }
      sideLines(v, sides, [arc], width: 0.075, trimPlastic, lift: 0.016)
    }
    sidePatches(v, sides, [rounded([SIMD2(0.3, 0.72), SIMD2(0.42, 0.72), SIMD2(0.42, 0.76), SIMD2(0.3, 0.76)], r: 0.01)], amber, lift: 0.02)
    // Rear: twin doors, windows, tail lights, bumper, plate.
    decalPatches(v, front, [rounded([SIMD2(0.8, 0.66), SIMD2(0.95, 0.66), SIMD2(0.95, 1.6), SIMD2(0.8, 1.6)], r: 0.03)],
                 taillight, below: false, mirror: true, lift: 0.014)
    sidePatches(v, sides, [rounded([SIMD2(5.86, 0.66), SIMD2(L, 0.66), SIMD2(L, 1.6), SIMD2(5.86, 1.6)], r: 0.01)], taillight, lift: 0.014)
    decalLines(v, front, [[SIMD2(0, 0.62), SIMD2(0, H - 0.12)], closed(rounded([SIMD2(-0.76, 0.62), SIMD2(0.76, 0.62), SIMD2(0.76, H - 0.12),
                                                                              SIMD2(-0.76, H - 0.12)], r: 0.06))],
               width: 0.014, black, below: false, mirror: false, lift: 0.012)
    decalPatches(v, front, [rounded([SIMD2(0.08, 1.72), SIMD2(0.66, 1.72), SIMD2(0.66, 2.38), SIMD2(0.08, 2.38)], r: 0.05)],
                 glass, below: false, mirror: true, lift: 0.01, k: 5)
    decalPatches(v, front, [rounded([SIMD2(-0.88, 0.36), SIMD2(0.88, 0.36), SIMD2(0.88, 0.6), SIMD2(-0.88, 0.6)], r: 0.04)],
                 trimPlastic, below: false, lift: 0.012)
    decalPatches(v, front, [rounded([SIMD2(-0.26, 0.66), SIMD2(0.26, 0.66), SIMD2(0.26, 0.78), SIMD2(-0.26, 0.78)], r: 0.015)],
                 plate, below: false, lift: 0.016)
    decalPatches(v, front, [rounded([SIMD2(0.12, H - 0.08), SIMD2(0.3, H - 0.08), SIMD2(0.3, H - 0.04), SIMD2(0.12, H - 0.04)], r: 0.01)],
                 taillight, below: false, mirror: true, lift: 0.014)
    if ambulance {
      sidePatches(v, sides, [rounded([SIMD2(0.08, 1.02), SIMD2(5.86, 1.02), SIMD2(5.86, 1.22), SIMD2(0.08, 1.22)], r: 0.02)], stripeRed, lift: 0.011)
      sidePatches(v, sides, [rounded([SIMD2(2.6, 1.42), SIMD2(3.3, 1.42), SIMD2(3.3, 2.2), SIMD2(2.6, 2.2)], r: 0.05)], glass, lift: 0.01)
      sidePatches(v, sides, starOfLife(4.4, 1.75, 0.34), lifeBlue, lift: 0.012)
      decalPatches(v, front, starOfLife(0, 1.1, 0.22), lifeBlue, below: false, lift: 0.014)
      decalPatches(v, front, [rounded([SIMD2(-0.82, 1.0), SIMD2(0.82, 1.0), SIMD2(0.82, 0.86), SIMD2(-0.82, 0.86)], r: 0.01)],
                   stripeRed, below: false, lift: 0.012)
      decalPatches(v, above, starOfLife(0, 4.0, 0.6), lifeBlue, lift: 0.04)
      // Light bar across the roof front, flashers at the rear corners and scene lights.
      let bar = holder(v, V3(0, H + 0.03, 2.45))
      shell(bar, samples(-0.14, 0.14, step: 0.035), { z in
        let f = 1 - pow(abs(z) / 0.14, 4)
        return boxHalf(0.78 * (0.9 + 0.1 * f), 0, 0.13 * (0.7 + 0.3 * f), rb: 0.02, rt: 0.05, sides: 2, arc: 3)
      }, skin: { f in
        if f.n.y < -0.5 { return black }
        let seg = Int(((f.p.x + 0.78) / 0.26).rounded(.down))
        return seg % 2 == 0 ? lightRed : lightWhite
      })
      for x in [-0.86, 0.86] as [Float] {
        box(v, 0.14, 0.12, 0.08, lightRed, x, H - 0.12, L + 0.02)
        box(v, 0.04, 0.12, 0.22, lightRed, x * 1.16, H - 0.12, 0.0 + L - 0.25)
        box(v, 0.04, 0.12, 0.22, lightWhite, x * 1.16, H - 0.12, 3.9)
      }
      box(v, 0.24, 0.07, 0.03, lightRed, 0.0, 0.98, -0.01)
    }
    // Mirrors, step, exhaust and wheels.
    for side in [-1, 1] as [Float] {
      sideMirror(v, at: V3(side * 0.96, 1.5, 1.32), side: side, reach: 0.12, w: 0.2, h: 0.34, trimPlastic)
    }
    box(v, 1.4, 0.07, 0.22, trimPlastic, 0, 0.45, L + 0.08)
    tube(v, V3(-0.6, 0.32, L - 0.6), V3(-0.6, 0.3, L + 0.02), 0.035, chrome)
    for z in axles {
      for side in [-1, 1] as [Float] {
        roadWheel(v, x: side * 0.86, y: wr, z: z, radius: wr, width: 0.235, outward: side, rimRatio: 0.6,
                  rimMaterial: rim, holes: 6, lugs: 6)
      }
    }
  }
}


let frpWhite = material("box", 0xF2F3F1, metal: 0.05, rough: 0.45)
let alu = material("aluminium", 0xBCC2C8, metal: 0.85, rough: 0.3)
let doorGrey = material("door", 0xD6D9DC, metal: 0.4, rough: 0.4)
let slat = material("slat", 0x9EA4AA, metal: 0.4, rough: 0.5)
let reflectorWhite = material("reflector-white", 0xF7F7F2, rough: 0.3)

/// Rear reflective tape: alternating red and white segments along a line.
func dotTape(_ p: SCNNode, _ d: Drape, from a: SIMD2<Float>, to b: SIMD2<Float>, segment: Float = 0.3, width: Float = 0.05,
             below: Bool, mirror: Bool = false) {
  let n = max(2, Int(simd_length(b - a) / segment))
  var reds: [[SIMD2<Float>]] = [], whites: [[SIMD2<Float>]] = []
  for i in 0..<n {
    let s = a + (b - a) * (Float(i) / Float(n)), e = a + (b - a) * (Float(i + 1) / Float(n))
    if i % 2 == 0 { reds.append([s, e]) } else { whites.append([s, e]) }
  }
  decalLines(p, d, reds, width: width, reflectorRed, below: below, mirror: mirror, lift: 0.016)
  decalLines(p, d, whites, width: width, reflectorWhite, below: below, mirror: mirror, lift: 0.016)
}

/// A low cab-forward cab (box truck, fire engine): bowed flat front,
/// near-vertical windscreen, door windows. Returns the drapes taken.
func cabForward(_ v: SCNNode, length cl: Float, hw hwMax: Float, bottom: Float, top H: Float, axle: Float, wheel wr: Float,
                _ p: SCNMaterial, roofStep: (Float, Float)? = nil) {
  let top = curve([(0, H - 0.2), (0.12, H - 0.08), (0.4, H - 0.01), (cl, H)])
  let hw = curve([(0, hwMax - 0.16), (0.05, hwMax - 0.06), (0.14, hwMax - 0.01), (0.3, hwMax), (cl, hwMax)])
  let bot = archBottom(bottom, axles: [axle], wheel: wr, gap: 0.08)
  let zs = samples(0, cl, step: 0.06, dense: [(0, 0.2, 0.02), (axle - 0.6, axle + 0.6, 0.025)])
  shell(v, zs, capStart: p, capEnd: p, { z in
    var t = top(z)
    if let (z0, h) = roofStep, z > z0 { t += h * min(1, (z - z0) / 0.25) }
    return boxHalf(hw(z), bot(z), t, rb: 0.08, rt: 0.12, lean: 0.03, bow: 0.008, sides: 8, arc: 5)
  }, skin: { f in f.n.y < -0.75 ? trimPlastic : p })
}

// Medium-duty box truck, Isuzu N/Hino class: cab-over with a 2.0 m cab,
// 6.1 m (20 ft) fibreglass box with aluminium rails and corner posts,
// roll-up rear door, 4.4 m wheelbase, dual rear wheels.
func boxTruck(body: UInt32) -> SCNNode {
  let L: Float = 8.75, wr: Float = 0.41
  let axles: [Float] = [1.15, 5.6]
  let p = paint(body)
  return roadVehicle(length: L) { v in
    cabForward(v, length: 2.05, hw: 1.0, bottom: 0.92, top: 2.42, axle: axles[0], wheel: wr, p)
    // Box: 6.1 x 2.45 x 2.55 on a floor at 1.08.
    let bz0: Float = 2.2
    shell(v, samples(bz0, L, step: 0.25, dense: [(bz0, bz0 + 0.1, 0.02), (L - 0.1, L, 0.02)]), capStart: frpWhite, capEnd: frpWhite, { _ in
      boxHalf(1.225, 1.08, 3.63, rb: 0.03, rt: 0.05, sides: 4, arc: 3)
    }, skin: { f in f.n.y < -0.75 ? alu : frpWhite })
    // Chassis rails, cab back, fuel tank, battery box.
    for x in [-0.45, 0.45] as [Float] { box(v, 0.1, 0.24, 7.1, black, x, 0.8, 4.9) }
    let front = Drape(v, axis: 2), sides = Drape(v, axis: 0)
    // Cab front: big windscreen, grille band, headlights, plate.
    decalPatches(v, front, [rounded([SIMD2(-0.9, 1.5), SIMD2(0.9, 1.5), SIMD2(0.86, 2.24), SIMD2(-0.86, 2.24)], r: 0.08)], glass,
                 below: true, lift: 0.01, k: 8)
    decalLines(v, front, [[SIMD2(0.04, 1.54), SIMD2(0.7, 1.58)], [SIMD2(-0.8, 1.54), SIMD2(-0.14, 1.58)]], width: 0.025, black,
               below: true, mirror: false, lift: 0.02)
    decalPatches(v, front, [rounded([SIMD2(-0.62, 1.08), SIMD2(0.62, 1.08), SIMD2(0.62, 1.36), SIMD2(-0.62, 1.36)], r: 0.04)], black,
                 below: true, lift: 0.012)
    decalLines(v, front, [[SIMD2(-0.58, 1.17), SIMD2(0.58, 1.17)], [SIMD2(-0.58, 1.27), SIMD2(0.58, 1.27)]], width: 0.02, chrome,
               below: true, mirror: false, lift: 0.02)
    decalPatches(v, front, [rounded([SIMD2(0.66, 1.06), SIMD2(0.92, 1.06), SIMD2(0.9, 1.3), SIMD2(0.66, 1.3)], r: 0.03)], lens,
                 below: true, mirror: true, lift: 0.014)
    decalPatches(v, front, [ring2(0.79, 1.18, 0.07, 12)], headlight, below: true, mirror: true, lift: 0.02)
    decalPatches(v, front, [rounded([SIMD2(0.86, 1.36), SIMD2(0.94, 1.36), SIMD2(0.94, 1.42), SIMD2(0.86, 1.42)], r: 0.01)], amber,
                 below: true, mirror: true, lift: 0.02)
    // Cab sides: door window with vent, door seam, step well.
    sidePatches(v, sides, [rounded([SIMD2(0.32, 1.56), SIMD2(1.5, 1.56), SIMD2(1.5, 2.24), SIMD2(0.42, 2.24)], r: 0.06)], glass, lift: 0.01, k: 5)
    sideLines(v, sides, [[SIMD2(0.62, 1.56), SIMD2(0.62, 2.24)]], width: 0.03, black)
    sideLines(v, sides, [closed(rounded([SIMD2(0.26, 0.96), SIMD2(1.62, 0.96), SIMD2(1.62, 2.32), SIMD2(0.26, 2.32)], r: 0.05))], width: 0.012, black)
    sidePatches(v, sides, [rounded([SIMD2(1.45, 1.36), SIMD2(1.56, 1.36), SIMD2(1.56, 1.4), SIMD2(1.45, 1.4)], r: 0.01)], trimPlastic, lift: 0.02)
    sidePatches(v, sides, [rounded([SIMD2(0.1, 1.5), SIMD2(0.2, 1.5), SIMD2(0.2, 1.56), SIMD2(0.1, 1.56)], r: 0.01)], amber, lift: 0.02)
    // Box: aluminium top and bottom rails, corner posts, rub rail, logistics post seams.
    sideLines(v, sides, [[SIMD2(bz0 + 0.02, 3.56), SIMD2(L - 0.02, 3.56)]], width: 0.12, alu, lift: 0.01)
    sideLines(v, sides, [[SIMD2(bz0 + 0.02, 1.16), SIMD2(L - 0.02, 1.16)]], width: 0.16, alu, lift: 0.01)
    sideLines(v, sides, [[SIMD2(bz0 + 0.04, 1.08), SIMD2(bz0 + 0.04, 3.62)], [SIMD2(L - 0.04, 1.08), SIMD2(L - 0.04, 3.62)]], width: 0.08, alu, lift: 0.012)
    var seams: [[SIMD2<Float>]] = []
    var z = bz0 + 1.22
    while z < L - 0.5 { seams.append([SIMD2(z, 1.24), SIMD2(z, 3.5)]); z += 1.22 }
    sideLines(v, sides, seams, width: 0.012, slat, lift: 0.011)
    sidePatches(v, sides, [rounded([SIMD2(bz0 + 0.15, 3.42), SIMD2(bz0 + 0.25, 3.42), SIMD2(bz0 + 0.25, 3.48), SIMD2(bz0 + 0.15, 3.48)], r: 0.01),
                           rounded([SIMD2(L - 0.25, 3.42), SIMD2(L - 0.15, 3.42), SIMD2(L - 0.15, 3.48), SIMD2(L - 0.25, 3.48)], r: 0.01)],
                amber, lift: 0.016)
    dotTape(v, sides, from: SIMD2(bz0 + 0.3, 1.27), to: SIMD2(L - 0.3, 1.27), below: false)
    dotTape(v, sides, from: SIMD2(bz0 + 0.3, 1.27), to: SIMD2(L - 0.3, 1.27), below: true)
    // Box front cap above the cab: marker lights.
    // Rear: roll-up door in a frame, slats, handle, lights, plate.
    decalPatches(v, front, [rounded([SIMD2(-1.08, 1.2), SIMD2(1.08, 1.2), SIMD2(1.08, 3.44), SIMD2(-1.08, 3.44)], r: 0.02)], doorGrey,
                 below: false, lift: 0.01, k: 3)
    decalLines(v, front, (1...10).map { i in let y = 1.2 + Float(i) * 0.2; return [SIMD2(-1.07, y), SIMD2(1.07, y)] }, width: 0.014, slat,
               below: false, mirror: false, lift: 0.014)
    decalLines(v, front, [closed([SIMD2(-1.16, 1.12), SIMD2(1.16, 1.12), SIMD2(1.16, 3.56), SIMD2(-1.16, 3.56)])], width: 0.1, alu,
               below: false, mirror: false, lift: 0.012)
    decalPatches(v, front, [rounded([SIMD2(-0.14, 1.28), SIMD2(0.14, 1.28), SIMD2(0.14, 1.36), SIMD2(-0.14, 1.36)], r: 0.01)], black,
                 below: false, lift: 0.018)
    decalPatches(v, front, [rounded([SIMD2(0.3, 3.5), SIMD2(0.42, 3.5), SIMD2(0.42, 3.54), SIMD2(0.3, 3.54)], r: 0.01),
                            rounded([SIMD2(-0.06, 3.5), SIMD2(0.06, 3.5), SIMD2(0.06, 3.54), SIMD2(-0.06, 3.54)], r: 0.01)],
                 taillight, below: false, mirror: true, lift: 0.018)
    dotTape(v, front, from: SIMD2(-1.1, 3.6), to: SIMD2(1.1, 3.6), segment: 0.18, width: 0.04, below: false)
    // Rear bumper/under-ride guard with lights and plate.
    box(v, 2.3, 0.14, 0.12, black, 0, 0.62, L - 0.25)
    for x in [-0.95, 0.95] as [Float] {
      box(v, 0.1, 0.5, 0.1, black, x * 0.55, 0.85, L - 0.25)
      box(v, 0.22, 0.12, 0.04, taillight, x, 0.98, L + 0.005)
      box(v, 0.1, 0.12, 0.04, amber, x * 0.82, 0.98, L + 0.005)
    }
    box(v, 0.32, 0.16, 0.02, plate, 0, 0.85, L - 0.18)
    // Front bumper, steps, mirrors, fuel tank, mud flaps, wheels.
    let bumper = holder(v, V3(0, 0, -0.06))
    shell(bumper, samples(0, 0.24, step: 0.04), { z in boxHalf(1.03 - 0.1 * pow(1 - z / 0.24, 3), 0.62, 0.92, rb: 0.03, rt: 0.04, sides: 3, arc: 3) },
          skin: { _ in trimPlastic })
    for side in [-1, 1] as [Float] {
      box(v, 0.12, 0.05, 0.42, alu, side * 0.98, 0.64, 1.95)
      sideMirror(v, at: V3(side * 1.0, 2.0, 0.35), side: side, reach: 0.2, w: 0.2, h: 0.42, black)
      put(v, CylinderMesh(radius: 0.06, height: 0.08, sides: 10), lens, side * 1.06, 1.62, 0.42, rz: .pi / 2)
      box(v, 0.5, 0.48, 0.02, rubber, side * 0.85, 0.48, axles[1] + 0.62)
    }
    put(v, CylinderMesh(radius: 0.26, height: 1.1, sides: 20), alu, -0.82, 0.74, 3.2, rx: .pi / 2)
    box(v, 0.5, 0.42, 0.6, black, 0.8, 0.72, 3.3)
    for side in [-1, 1] as [Float] {
      roadWheel(v, x: side * 0.86, y: wr, z: axles[0], radius: wr, width: 0.245, outward: side, rimRatio: 0.58, rimMaterial: rim, holes: 6, lugs: 8)
      roadWheel(v, x: side * 0.92, y: wr, z: axles[1], radius: wr, width: 0.245, outward: side, rimRatio: 0.58, rimMaterial: rim, holes: 6,
                lugs: 8, dual: true)
    }
  }
}

// Class 8 conventional tractor (long-hood, Peterbilt 389 class) with a
// 72-inch sleeper, pulling a 53 ft (16.15 m) dry van: tall chrome grille,
// separate swept fenders, external air cleaners, twin stacks, chrome tanks,
// tandem drive axles; the trailer has aluminium rails, side skirts, landing
// gear, a sliding tandem, swing doors with lock rods and DOT tape.
func semiTruck(cab: UInt32) -> SCNNode {
  let tL: Float = 22.4, wr: Float = 0.52
  let p = paint(cab)
  let front: [Float] = [1.3], drive: [Float] = [6.55, 7.9], trailerAxles: [Float] = [19.4, 20.65]
  return roadVehicle(length: tL) { v in
    // Hood: narrow, rising gently to the cowl.
    let hoodTop = curve([(0.3, 1.86), (0.5, 1.95), (1.6, 2.0), (2.7, 2.08)])
    let hoodHw = curve([(0.3, 0.6), (0.5, 0.64), (1.5, 0.7), (2.7, 0.78)])
    shell(v, samples(0.3, 2.7, step: 0.08, dense: [(0.3, 0.6, 0.02)]), capStart: chrome, { z in
      boxHalf(hoodHw(z), 1.05, hoodTop(z), rb: 0.04, rt: 0.12, lean: 0.06, sides: 6, arc: 5)
    }, skin: { _ in p })
    // Fenders sweeping over the front wheels down to the steps.
    for side in [-1, 1] as [Float] {
      let fx = side * 0.98
      let fTop = curve([(0.4, 1.32), (0.8, 1.42), (1.3, 1.44), (1.9, 1.36), (2.5, 1.1), (2.75, 0.95)])
      shell(v, samples(0.4, 2.75, step: 0.05), x: fx, capStart: p, capEnd: p, { z in
        let u = (z - front[0]) / (wr + 0.12)
        let arch = abs(u) < 1 ? wr + (wr + 0.12) * (1 - u * u).squareRoot() : 0.75
        return boxHalf(0.3, max(0.75, min(arch, fTop(z) - 0.08)), fTop(z), rb: 0.02, rt: 0.12, sides: 4, arc: 4)
      }, skin: { f in f.n.y < -0.6 ? black : p })
    }
    // Cab and sleeper.
    let cabTop = curve([(2.55, 2.12), (2.7, 2.2), (3.05, 2.86), (3.35, 2.98), (4.05, 3.0), (4.4, 3.55), (4.8, 3.86), (6.0, 3.88)])
    let zs = samples(2.55, 6.0, step: 0.06, dense: [(2.55, 3.4, 0.025)])
    shell(v, zs, capStart: p, capEnd: p, { z in
      let hw: Float = z < 4.05 ? 1.03 : 1.2
      let blend = z < 3.95 ? 0 : min(1, (z - 3.95) / 0.3)
      return boxHalf(1.03 + (1.2 - 1.03) * blend * blend * (3 - 2 * blend) + 0 * hw, 1.0, cabTop(z), rb: 0.05, rt: 0.14, lean: 0.07,
                     bow: 0.01, sides: 8, arc: 5)
    }, skin: { f in f.n.y < -0.75 ? black : p })
    // Frame rails, fifth wheel, deck plate.
    for x in [-0.45, 0.45] as [Float] { box(v, 0.1, 0.28, 8.3, black, x, 0.95, 4.2) }
    box(v, 1.6, 0.12, 1.2, black, 0, 1.22, 7.1)
    box(v, 1.9, 0.04, 0.5, alu, 0, 1.12, 6.2)
    // Trailer.
    let tz0: Float = 6.25, tz1: Float = tL, tb: Float = 1.3, tt: Float = 4.11
    shell(v, samples(tz0, tz1, step: 0.4, dense: [(tz0, tz0 + 0.1, 0.02), (tz1 - 0.1, tz1, 0.02)]), capStart: frpWhite, capEnd: frpWhite, { _ in
      boxHalf(1.3, tb, tt, rb: 0.03, rt: 0.06, sides: 4, arc: 3)
    }, skin: { f in f.n.y < -0.75 ? alu : frpWhite })
    let fd = Drape(v, axis: 2), sd = Drape(v, axis: 0)
    // Grille, headlights, windscreen, cab windows, sleeper windows.
    decalPatches(v, fd, [rounded([SIMD2(-0.5, 1.0), SIMD2(0.5, 1.0), SIMD2(0.5, 1.82), SIMD2(-0.5, 1.82)], r: 0.04)], black, below: true, lift: 0.012)
    decalLines(v, fd, (0..<9).map { i in let y = 1.05 + Float(i) * 0.09; return [SIMD2(-0.48, y), SIMD2(0.48, y)] }, width: 0.03, chrome,
               below: true, mirror: false, lift: 0.02)
    decalLines(v, fd, [closed([SIMD2(-0.54, 0.98), SIMD2(0.54, 0.98), SIMD2(0.54, 1.86), SIMD2(-0.54, 1.86)])], width: 0.06, chrome,
               below: true, mirror: false, lift: 0.022)
    decalPatches(v, fd, [rounded([SIMD2(-0.92, 2.28), SIMD2(-0.03, 2.28), SIMD2(-0.03, 2.84), SIMD2(-0.86, 2.84)], r: 0.06),
                         rounded([SIMD2(0.03, 2.28), SIMD2(0.92, 2.28), SIMD2(0.86, 2.84), SIMD2(0.03, 2.84)], r: 0.06)], glass,
                 below: true, lift: 0.01, k: 6)
    decalPatches(v, fd, (0..<5).map { i in ring2(-0.6 + Float(i) * 0.3, 2.94, 0.035, 8) }, amber, below: true, lift: 0.016)
    sidePatches(v, sd, [rounded([SIMD2(2.98, 2.2), SIMD2(3.9, 2.2), SIMD2(3.9, 2.82), SIMD2(3.2, 2.9)], r: 0.07)], glass, lift: 0.01, k: 5)
    sidePatches(v, sd, [rounded([SIMD2(4.9, 2.4), SIMD2(5.5, 2.4), SIMD2(5.5, 2.75), SIMD2(4.9, 2.75)], r: 0.06)], glass, lift: 0.01)
    sideLines(v, sd, [closed(rounded([SIMD2(2.8, 1.05), SIMD2(4.0, 1.05), SIMD2(4.0, 2.96), SIMD2(2.8, 2.96)], r: 0.06))], width: 0.012, black)
    sideLines(v, sd, [closed(rounded([SIMD2(4.6, 1.1), SIMD2(5.3, 1.1), SIMD2(5.3, 1.8), SIMD2(4.6, 1.8)], r: 0.04))], width: 0.012, black)
    // Trailer: rails, posts, skirts, tape, rear doors.
    sideLines(v, sd, [[SIMD2(tz0 + 0.02, tt - 0.07), SIMD2(tz1 - 0.02, tt - 0.07)], [SIMD2(tz0 + 0.02, tb + 0.1), SIMD2(tz1 - 0.02, tb + 0.1)]],
              width: 0.13, alu, lift: 0.01)
    var posts: [[SIMD2<Float>]] = []
    var z = tz0 + 0.6
    while z < tz1 - 0.3 { posts.append([SIMD2(z, tb + 0.18), SIMD2(z, tt - 0.14)]); z += 0.61 }
    sideLines(v, sd, posts, width: 0.035, slat, lift: 0.011)
    dotTape(v, sd, from: SIMD2(tz0 + 0.3, tb + 0.24), to: SIMD2(tz1 - 0.3, tb + 0.24), below: false)
    dotTape(v, sd, from: SIMD2(tz0 + 0.3, tb + 0.24), to: SIMD2(tz1 - 0.3, tb + 0.24), below: true)
    decalLines(v, fd, [[SIMD2(0, tb + 0.08), SIMD2(0, tt - 0.12)]], width: 0.03, black, below: false, mirror: false, lift: 0.012)
    decalLines(v, fd, [closed([SIMD2(-1.26, tb + 0.06), SIMD2(1.26, tb + 0.06), SIMD2(1.26, tt - 0.06), SIMD2(-1.26, tt - 0.06)])], width: 0.08, alu,
               below: false, mirror: false, lift: 0.012)
    decalLines(v, fd, [-0.85, -0.25, 0.25, 0.85].map { x in [SIMD2(Float(x), tb + 0.15), SIMD2(Float(x), tt - 0.15)] }, width: 0.035, chrome,
               below: false, mirror: false, lift: 0.02)
    decalLines(v, fd, [-1.2, -0.65, 0.65, 1.2].flatMap { x in [Float(0.5), 1.4, 2.3].map { y in [SIMD2(Float(x) - 0.07, tb + y), SIMD2(Float(x) + 0.07, tb + y)] } },
               width: 0.08, alu, below: false, mirror: false, lift: 0.02)
    dotTape(v, fd, from: SIMD2(-1.25, tb + 0.02), to: SIMD2(1.25, tb + 0.02), segment: 0.2, width: 0.05, below: false)
    decalPatches(v, fd, [-0.2, 0, 0.2].map { x in ring2(Float(x), tt - 0.03, 0.025, 8) }, taillight, below: false, lift: 0.016)
    // Trailer gear: skirts, landing legs, slider, under-ride guard, lights.
    for side in [-1, 1] as [Float] {
      box(v, 0.02, 0.85, 8.6, plastic, side * 1.25, 0.82, 13.85)
      box(v, 0.12, 0.95, 0.12, alu, side * 0.75, 0.82, 9.6)
      box(v, 0.26, 0.04, 0.3, black, side * 0.75, 0.33, 9.6)
      for z in trailerAxles { box(v, 0.12, 0.08, 0.6, black, side * 0.55, 0.9, z) }
      box(v, 0.24, 0.14, 0.04, taillight, side * 1.05, 0.95, tL + 0.005)
      box(v, 0.55, 0.55, 0.02, rubber, side * 0.9, 0.5, trailerAxles[1] + 0.75)
      box(v, 0.55, 0.55, 0.02, rubber, side * 0.9, 0.5, drive[1] + 0.75)
    }
    box(v, 1.4, 0.24, 2.2, black, 0, 1.15, 20.0)
    box(v, 2.4, 0.12, 0.1, alu, 0, 0.55, tL - 0.22)
    for x in [-0.8, 0.8] as [Float] { box(v, 0.08, 0.7, 0.08, alu, x, 0.85, tL - 0.25) }
    // Bumper, headlights, air cleaners, stacks, tanks, steps, mirrors.
    let bumper = holder(v, V3(0, 0, 0))
    shell(bumper, samples(0, 0.32, step: 0.04), { z in boxHalf(1.24 - 0.12 * pow(1 - z / 0.32, 2), 0.52, 0.92, rb: 0.06, rt: 0.06, sides: 3, arc: 3) },
          skin: { _ in chrome })
    for side in [-1, 1] as [Float] {
      box(v, 0.24, 0.17, 0.12, chrome, side * 1.0, 1.24, 0.62)
      box(v, 0.2, 0.13, 0.03, headlight, side * 1.0, 1.24, 0.555)
      put(v, LatheMesh([SIMD2(0, 0.2), SIMD2(0.7, 0.2), SIMD2(0.82, 0.12), SIMD2(0.84, 0.001)], sides: 20), chrome, side * 1.08, 1.4, 2.35)
      tube(v, V3(side * 1.16, 1.1, 4.12), V3(side * 1.16, 4.35, 4.12), 0.09, chrome, sides: 14)
      put(v, CylinderMesh(radius: 0.33, height: 1.3, sides: 22), chrome, side * 0.92, 0.82, 4.95, rx: .pi / 2)
      for z in [4.4, 5.5] as [Float] { box(v, 0.7, 0.04, 0.06, black, side * 0.92, 1.15, z) }
      box(v, 0.32, 0.04, 0.55, alu, side * 1.05, 0.62, 3.45)
      box(v, 0.32, 0.04, 0.55, alu, side * 1.05, 0.95, 3.45)
      tube(v, V3(side * 1.03, 1.9, 2.95), V3(side * 1.35, 2.0, 3.0), 0.02, chrome)
      tube(v, V3(side * 1.03, 2.7, 2.95), V3(side * 1.35, 2.6, 3.0), 0.02, chrome)
      box(v, 0.05, 0.62, 0.22, chrome, side * 1.38, 2.3, 3.0)
      box(v, 0.01, 0.56, 0.18, glass, side * 1.38, 2.3, 3.115)
    }
    for side in [-1, 1] as [Float] {
      roadWheel(v, x: side * 0.98, y: wr, z: front[0], radius: wr, width: 0.28, outward: side, rimRatio: 0.55, rimMaterial: chrome, holes: 10, lugs: 10)
      for z in drive {
        roadWheel(v, x: side * 0.95, y: wr, z: z, radius: wr, width: 0.28, outward: side, rimRatio: 0.55, rimMaterial: chrome, holes: 10, lugs: 10, dual: true)
      }
      for z in trailerAxles {
        roadWheel(v, x: side * 0.95, y: wr, z: z, radius: wr, width: 0.28, outward: side, rimRatio: 0.55, rimMaterial: alu, holes: 10, lugs: 10, dual: true)
      }
    }
  }
}

// Low-floor 40 ft city bus (New Flyer Xcelsior class): 12.5 m long,
// 2.59 m wide, 3.3 m to the roof fairing, 7.2 m wheelbase. Flush wraparound
// windscreen under an LED destination sign, glazed bi-fold doors on the
// right, a continuous flush window band with slim dark pillars, roof
// fairing over the CNG/battery pack and HVAC, rear engine louvres.
// Livery (paint) runs along the skirt and the roof fairing.
func cityBus(livery: UInt32) -> SCNNode {
  let L: Float = 12.5, hwMax: Float = 1.295, H: Float = 3.08, wr: Float = 0.5
  let axles: [Float] = [2.55, 9.75]
  let p = paint(livery)
  let busWhite = material("white", 0xF4F5F7, metal: 0.2, rough: 0.35)
  return roadVehicle(length: L) { v in
    let hw = curve([(0, hwMax - 0.12), (0.06, hwMax - 0.05), (0.2, hwMax - 0.01), (0.5, hwMax), (L - 0.3, hwMax), (L, hwMax - 0.08)])
    let top = curve([(0, H - 0.22), (0.12, H - 0.08), (0.35, H), (L - 0.2, H), (L, H - 0.1)])
    let bot = archBottom(0.36, axles: axles, wheel: wr, gap: 0.09)
    let zs = samples(0, L, step: 0.08, dense: [(0, 0.3, 0.02), (axles[0] - 0.7, axles[0] + 0.7, 0.03), (axles[1] - 0.7, axles[1] + 0.7, 0.03),
                                               (L - 0.3, L, 0.02)])
    shell(v, zs, capStart: busWhite, capEnd: busWhite, { z in
      boxHalf(hw(z), bot(z), top(z), rb: 0.08, rt: 0.2, lean: 0.06, bow: 0.006, sides: 8, arc: 5)
    }, skin: { f in f.n.y < -0.75 ? trimPlastic : busWhite })
    // Roof fairing.
    shell(v, samples(2.3, 11.6, step: 0.12, dense: [(2.3, 2.9, 0.03), (11.0, 11.6, 0.03)]), capStart: p, capEnd: p, { z in
      let f = min(1, (z - 2.3) / 0.6, (11.6 - z) / 0.6)
      let s = f * f * (3 - 2 * f)
      return boxHalf(1.05, H - 0.05, H + 0.02 + 0.3 * s, rb: 0.02, rt: 0.18, lean: 0.05, sides: 3, arc: 4)
    }, skin: { _ in p })
    let fd = Drape(v, axis: 2), sd = Drape(v, axis: 0), up = Drape(v, axis: 1)
    // Livery: a skirt between the wheel arches, a stripe under the windows
    // and a sweep up the front corners.
    let R = wr + 0.09
    sidePatches(v, sd, [rounded([SIMD2(0.02, 0.37), SIMD2(axles[0] - R - 0.03, 0.37), SIMD2(axles[0] - R - 0.03, 0.95), SIMD2(0.02, 0.95)], r: 0.04),
                        rounded([SIMD2(axles[0] + R + 0.03, 0.37), SIMD2(axles[1] - R - 0.03, 0.37), SIMD2(axles[1] - R - 0.03, 0.95),
                                 SIMD2(axles[0] + R + 0.03, 0.95)], r: 0.04),
                        rounded([SIMD2(axles[1] + R + 0.03, 0.37), SIMD2(L - 0.02, 0.37), SIMD2(L - 0.02, 0.95), SIMD2(axles[1] + R + 0.03, 0.95)], r: 0.04),
                        rounded([SIMD2(0.02, 1.13), SIMD2(L - 0.02, 1.13), SIMD2(L - 0.02, 1.3), SIMD2(0.02, 1.3)], r: 0.03)], p, lift: 0.008, k: 6)
    decalPatches(v, fd, [rounded([SIMD2(-1.22, 0.56), SIMD2(1.22, 0.56), SIMD2(1.22, 0.95), SIMD2(-1.22, 0.95)], r: 0.04)], p, below: true, lift: 0.008)
    // Front: windscreen, sign, lamps, bumper, plate, bike rack.
    decalPatches(v, fd, [rounded([SIMD2(-1.18, 1.0), SIMD2(1.18, 1.0), SIMD2(1.14, 2.62), SIMD2(-1.14, 2.62)], r: 0.12)], glass,
                 below: true, lift: 0.01, k: 10)
    decalPatches(v, fd, [rounded([SIMD2(-0.95, 2.68), SIMD2(0.95, 2.68), SIMD2(0.95, 2.92), SIMD2(-0.95, 2.92)], r: 0.03)], black,
                 below: true, lift: 0.012)
    decalLines(v, fd, [[SIMD2(-0.8, 2.8), SIMD2(0.6, 2.8)]], width: 0.08, amber, below: true, mirror: false, lift: 0.02)
    decalPatches(v, fd, [rounded([SIMD2(0.82, 0.58), SIMD2(1.16, 0.58), SIMD2(1.16, 0.84), SIMD2(0.82, 0.84)], r: 0.06)], lens,
                 below: true, mirror: true, lift: 0.014)
    decalPatches(v, fd, [ring2(0.92, 0.71, 0.06, 12), ring2(1.07, 0.71, 0.05, 12)], headlight, below: true, mirror: true, lift: 0.02)
    decalPatches(v, fd, [rounded([SIMD2(-1.2, 0.36), SIMD2(1.2, 0.36), SIMD2(1.2, 0.55), SIMD2(-1.2, 0.55)], r: 0.05)], trimPlastic,
                 below: true, lift: 0.012)
    decalPatches(v, fd, [rounded([SIMD2(-0.26, 0.6), SIMD2(0.26, 0.6), SIMD2(0.26, 0.72), SIMD2(-0.26, 0.72)], r: 0.015)], plate,
                 below: true, lift: 0.016)
    // Right side: front and rear doors (glazed bi-folds); both sides: window band.
    for (z0, z1) in [(0.45, 1.65), (5.6, 6.85)] as [(Float, Float)] {
      let mid = (z0 + z1) / 2
      decalPatches(v, sd, [rounded([SIMD2(z0, 0.42), SIMD2(z1, 0.42), SIMD2(z1, 2.78), SIMD2(z0, 2.78)], r: 0.06)], black, lift: 0.01)
      decalPatches(v, sd, [rounded([SIMD2(z0 + 0.06, 0.55), SIMD2(mid - 0.03, 0.55), SIMD2(mid - 0.03, 2.7), SIMD2(z0 + 0.06, 2.7)], r: 0.04),
                           rounded([SIMD2(mid + 0.03, 0.55), SIMD2(z1 - 0.06, 0.55), SIMD2(z1 - 0.06, 2.7), SIMD2(mid + 0.03, 2.7)], r: 0.04)],
                   glass, lift: 0.016)
    }
    let band: (Float, Float) = (1.38, 2.62)
    func windows(_ z0: Float, _ z1: Float, panes: Int, right: Bool, left: Bool) {
      sidePatches(v, sd, [rounded([SIMD2(z0, band.0), SIMD2(z1, band.0), SIMD2(z1, band.1), SIMD2(z0, band.1)], r: 0.1)], glass,
                  right: right, left: left, lift: 0.01)
      let pane = (z1 - z0) / Float(panes)
      sideLines(v, sd, (1..<panes).map { i in let z = z0 + pane * Float(i); return [SIMD2(z, band.0), SIMD2(z, band.1)] }, width: 0.07, black,
                right: right, left: left, lift: 0.015)
    }
    windows(1.8, 5.45, panes: 3, right: true, left: false)
    windows(7.0, 11.4, panes: 4, right: true, left: false)
    windows(0.25, 11.4, panes: 9, right: false, left: true)
    sidePatches(v, sd, [rounded([SIMD2(0.25, 1.1), SIMD2(1.55, 1.1), SIMD2(1.55, 1.36), SIMD2(0.25, 1.36)], r: 0.04)], glass, right: false, lift: 0.01)
    // Engine louvres and access doors at the back of the left side; side markers.
    sideLines(v, sd, (0..<8).map { i in let y = 1.0 + Float(i) * 0.05; return [SIMD2(10.55, y), SIMD2(11.6, y)] }, width: 0.022, black,
              right: false, lift: 0.014)
    sidePatches(v, sd, [3.6, 8.2, 12.2].map { z in rounded([SIMD2(Float(z), 0.6), SIMD2(Float(z) + 0.1, 0.6), SIMD2(Float(z) + 0.1, 0.65),
                                                               SIMD2(Float(z), 0.65)], r: 0.01) }, amber, lift: 0.02)
    // Rear: window, engine grille, lamps, bumper.
    decalPatches(v, fd, [rounded([SIMD2(-0.95, 2.2), SIMD2(0.95, 2.2), SIMD2(0.95, 2.82), SIMD2(-0.95, 2.82)], r: 0.08)], glass, below: false, lift: 0.01)
    decalPatches(v, fd, [rounded([SIMD2(-0.9, 0.95), SIMD2(0.9, 0.95), SIMD2(0.9, 1.75), SIMD2(-0.9, 1.75)], r: 0.05)], trimPlastic,
                 below: false, lift: 0.012)
    decalLines(v, fd, (0..<7).map { i in let y = 1.03 + Float(i) * 0.1; return [SIMD2(-0.85, y), SIMD2(0.85, y)] }, width: 0.03, slat,
               below: false, mirror: false, lift: 0.016)
    decalPatches(v, fd, [ring2(1.08, 1.5, 0.08, 14), ring2(1.08, 1.25, 0.08, 14)], taillight, below: false, mirror: true, lift: 0.016)
    decalPatches(v, fd, [ring2(1.08, 1.0, 0.07, 14)], amber, below: false, mirror: true, lift: 0.016)
    decalPatches(v, fd, [rounded([SIMD2(-1.2, 0.36), SIMD2(1.2, 0.36), SIMD2(1.2, 0.6), SIMD2(-1.2, 0.6)], r: 0.04)], trimPlastic, below: false, lift: 0.012)
    // Roof: HVAC grilles and hatches.
    decalPatches(v, up, [rounded([SIMD2(-0.7, 9.4), SIMD2(0.7, 9.4), SIMD2(0.7, 10.9), SIMD2(-0.7, 10.9)], r: 0.1)], trimPlastic, lift: 0.01)
    decalPatches(v, up, [ring2(0.45, 9.8, 0.22, 16), ring2(-0.45, 9.8, 0.22, 16), ring2(0.45, 10.5, 0.22, 16), ring2(-0.45, 10.5, 0.22, 16)], black, lift: 0.02)
    // Mirrors on stalks, bike rack, wheels.
    for side in [-1, 1] as [Float] {
      tube(v, V3(side * 1.22, 2.55, 0.25), V3(side * 1.42, 2.6, -0.2), 0.025, black, sides: 8)
      box(v, 0.08, 0.36, 0.22, black, side * 1.44, 2.38, -0.22)
    }
    for x in [-0.55, 0.55] as [Float] {
      tube(v, V3(x, 0.55, 0.0), V3(x, 0.62, -0.42), 0.025, alu, sides: 8)
      tube(v, V3(x, 0.62, -0.42), V3(x, 0.98, -0.45), 0.025, alu, sides: 8)
    }
    tube(v, V3(-0.62, 0.62, -0.42), V3(0.62, 0.62, -0.42), 0.025, alu, sides: 8)
    for side in [-1, 1] as [Float] {
      roadWheel(v, x: side * 1.08, y: wr, z: axles[0], radius: wr, width: 0.3, outward: side, rimRatio: 0.56, rimMaterial: alu, holes: 10, lugs: 10)
      roadWheel(v, x: side * 0.98, y: wr, z: axles[1], radius: wr, width: 0.3, outward: side, rimRatio: 0.56, rimMaterial: alu, holes: 10, lugs: 10, dual: true)
    }
  }
}

// Conventional school bus (Thomas C2 / IC CE class): 11.2 m, 2.44 m wide,
// short sloping hood, two-piece windscreen, drop-sash windows with split
// sashes, three black rub rails, red and amber warning lamps front and
// rear, stop arm, crossing arm, crossover mirrors, rear emergency door.
func schoolBus() -> SCNNode {
  let L: Float = 11.2, hwMax: Float = 1.22, H: Float = 3.12, wr: Float = 0.5
  let axles: [Float] = [1.05, 7.95]
  let yellow = paint(0xFFB300)
  return roadVehicle(length: L) { v in
    let top = curve([(0, 1.18), (0.1, 1.36), (0.4, 1.44), (1.25, 1.56), (1.45, 1.62), (1.75, 2.62), (1.95, H - 0.06), (2.3, H), (L - 0.2, H),
                     (L, H - 0.12)])
    let hw = curve([(0, 0.82), (0.1, 0.9), (0.6, 0.94), (1.3, 1.0), (1.55, hwMax - 0.02), (2.2, hwMax), (L - 0.15, hwMax), (L, hwMax - 0.06)])
    let rt = curve([(0, 0.14), (1.3, 0.2), (1.8, 0.4), (2.4, 0.42), (L, 0.42)])
    let bot = archBottom(0.5, axles: axles, wheel: wr, gap: 0.08)
    let zs = samples(0, L, step: 0.08, dense: [(0, 0.3, 0.02), (1.2, 2.4, 0.025), (axles[0] - 0.7, axles[0] + 0.7, 0.03),
                                               (axles[1] - 0.7, axles[1] + 0.7, 0.03), (L - 0.3, L, 0.02)])
    shell(v, zs, capStart: yellow, capEnd: yellow, { z in
      boxHalf(hw(z), bot(z), top(z), rb: 0.06, rt: rt(z), lean: z < 1.4 ? 0.12 : 0.05, bow: 0.005, sides: 8, arc: 6)
    }, skin: { f in f.n.y < -0.75 ? black : yellow })
    let fd = Drape(v, axis: 2), sd = Drape(v, axis: 0), up = Drape(v, axis: 1)
    // Front: grille, headlamps, windscreen, sign board, warning lamps.
    decalPatches(v, fd, [rounded([SIMD2(-0.5, 0.62), SIMD2(0.5, 0.62), SIMD2(0.5, 1.12), SIMD2(-0.5, 1.12)], r: 0.06)], black, below: true, lift: 0.012)
    decalLines(v, fd, (0..<5).map { i in let y = 0.7 + Float(i) * 0.09; return [SIMD2(-0.46, y), SIMD2(0.46, y)] }, width: 0.025, slat,
               below: true, mirror: false, lift: 0.02)
    decalPatches(v, fd, [ring2(0.66, 0.92, 0.1, 14)], chrome, below: true, mirror: true, lift: 0.014)
    decalPatches(v, fd, [ring2(0.66, 0.92, 0.075, 14)], headlight, below: true, mirror: true, lift: 0.02)
    decalPatches(v, fd, [rounded([SIMD2(-1.08, 1.68), SIMD2(-0.03, 1.68), SIMD2(-0.03, 2.55), SIMD2(-1.04, 2.55)], r: 0.06),
                         rounded([SIMD2(0.03, 1.68), SIMD2(1.08, 1.68), SIMD2(1.04, 2.55), SIMD2(0.03, 2.55)], r: 0.06)], glass,
                 below: true, lift: 0.01, k: 7)
    decalPatches(v, fd, [rounded([SIMD2(-0.55, 2.7), SIMD2(0.55, 2.7), SIMD2(0.55, 2.94), SIMD2(-0.55, 2.94)], r: 0.02)], black, below: true, lift: 0.012)
    decalPatches(v, fd, [rounded([SIMD2(-0.52, 2.73), SIMD2(0.52, 2.73), SIMD2(0.52, 2.91), SIMD2(-0.52, 2.91)], r: 0.02)], yellow, below: true, lift: 0.016)
    decalLines(v, fd, [[SIMD2(-0.45, 2.82), SIMD2(0.45, 2.82)]], width: 0.06, black, below: true, mirror: false, lift: 0.02)
    decalPatches(v, fd, [ring2(0.95, 2.82, 0.09, 14)], lightRed, below: true, mirror: true, lift: 0.016)
    decalPatches(v, fd, [ring2(0.73, 2.82, 0.09, 14)], amber, below: true, mirror: true, lift: 0.016)
    // Sides: rub rails, windows with split sashes, entry door, emergency exit.
    sideLines(v, sd, [0.95, 1.3, 1.62].map { y in [SIMD2(1.5, Float(y)), SIMD2(L - 0.05, Float(y))] }, width: 0.06, black, lift: 0.012)
    let w0: Float = 2.45, pane: Float = 0.82
    for side in [true, false] {
      for i in 0..<10 {
        let z0 = w0 + Float(i) * pane
        if !side && i == 9 { continue }
        decalPatches(v, sd, [rounded([SIMD2(z0 + 0.04, 1.78), SIMD2(z0 + pane - 0.04, 1.78), SIMD2(z0 + pane - 0.04, 2.55),
                                      SIMD2(z0 + 0.04, 2.55)], r: 0.05)], glass, below: !side, lift: 0.01)
        decalLines(v, sd, [[SIMD2(z0 + 0.04, 2.2), SIMD2(z0 + pane - 0.04, 2.2)]], width: 0.035, alu, below: !side, mirror: false, lift: 0.016)
      }
      decalPatches(v, sd, [rounded([SIMD2(1.55, 1.75), SIMD2(2.3, 1.75), SIMD2(2.3, 2.55), SIMD2(1.85, 2.55)], r: 0.05)], glass, below: !side, lift: 0.01)
    }
    decalPatches(v, sd, [rounded([SIMD2(1.62, 0.62), SIMD2(1.96, 0.62), SIMD2(1.96, 2.62), SIMD2(1.62, 2.62)], r: 0.03),
                         rounded([SIMD2(2.0, 0.62), SIMD2(2.34, 0.62), SIMD2(2.34, 2.62), SIMD2(2.0, 2.62)], r: 0.03)], glass, below: false, lift: 0.014)
    decalLines(v, sd, [closed(rounded([SIMD2(9.95, 0.6), SIMD2(10.6, 0.6), SIMD2(10.6, 2.62), SIMD2(9.95, 2.62)], r: 0.04))], width: 0.02, black,
               below: true, mirror: false, lift: 0.014)
    // Stop arm folded on the left side.
    decalPatches(v, sd, [ring2(2.55, 2.0, 0.24, 8, phase: .pi / 8)], material("stop", 0xD0021B, rough: 0.4), below: true, lift: 0.08)
    // Rear: emergency door with windows, lamps, bumper.
    decalPatches(v, fd, [rounded([SIMD2(-0.5, 1.78), SIMD2(0.5, 1.78), SIMD2(0.5, 2.55), SIMD2(-0.5, 2.55)], r: 0.05),
                         rounded([SIMD2(0.62, 1.78), SIMD2(1.1, 1.78), SIMD2(1.1, 2.55), SIMD2(0.62, 2.55)], r: 0.05),
                         rounded([SIMD2(-1.1, 1.78), SIMD2(-0.62, 1.78), SIMD2(-0.62, 2.55), SIMD2(-1.1, 2.55)], r: 0.05),
                         rounded([SIMD2(-0.5, 0.95), SIMD2(0.5, 0.95), SIMD2(0.5, 1.6), SIMD2(-0.5, 1.6)], r: 0.05)], glass, below: false, lift: 0.01)
    decalLines(v, fd, [closed(rounded([SIMD2(-0.56, 0.62), SIMD2(0.56, 0.62), SIMD2(0.56, 2.62), SIMD2(-0.56, 2.62)], r: 0.04))], width: 0.02, black,
               below: false, mirror: false, lift: 0.014)
    decalPatches(v, fd, [ring2(0.95, 2.82, 0.09, 14)], lightRed, below: false, mirror: true, lift: 0.016)
    decalPatches(v, fd, [ring2(0.73, 2.82, 0.09, 14)], amber, below: false, mirror: true, lift: 0.016)
    decalPatches(v, fd, [ring2(0.95, 1.2, 0.09, 14)], taillight, below: false, mirror: true, lift: 0.016)
    decalPatches(v, fd, [ring2(0.95, 0.95, 0.08, 14)], amber, below: false, mirror: true, lift: 0.016)
    // Roof hatches.
    decalPatches(v, up, [rounded([SIMD2(-0.4, 4.0), SIMD2(0.4, 4.0), SIMD2(0.4, 4.7), SIMD2(-0.4, 4.7)], r: 0.06),
                         rounded([SIMD2(-0.4, 8.0), SIMD2(0.4, 8.0), SIMD2(0.4, 8.7), SIMD2(-0.4, 8.7)], r: 0.06)], alu, lift: 0.02)
    // Bumpers, crossing arm, crossover mirrors, side mirrors, wheels.
    box(v, 2.3, 0.26, 0.14, black, 0, 0.62, -0.06)
    box(v, 2.4, 0.26, 0.14, black, 0, 0.62, L + 0.06)
    tube(v, V3(0.85, 0.62, -0.14), V3(0.85, 0.62, -0.75), 0.03, material("stop", 0xD0021B, rough: 0.4), sides: 8)
    for side in [-1, 1] as [Float] {
      tube(v, V3(side * 0.85, 1.25, 0.2), V3(side * 1.05, 1.75, -0.12), 0.015, black, sides: 6)
      put(v, LatheMesh([SIMD2(-0.03, 0.001), SIMD2(-0.03, 0.12), SIMD2(0.03, 0.12), SIMD2(0.05, 0.001)], sides: 14), black, side * 1.05, 1.82, -0.12,
          rx: .pi / 2)
      tube(v, V3(side * 1.2, 2.3, 1.55), V3(side * 1.45, 2.4, 1.3), 0.02, black, sides: 6)
      box(v, 0.08, 0.42, 0.24, black, side * 1.47, 2.2, 1.28)
      roadWheel(v, x: side * 1.0, y: wr, z: axles[0], radius: wr, width: 0.28, outward: side, rimRatio: 0.56, rimMaterial: rim, holes: 6, lugs: 10)
      roadWheel(v, x: side * 0.92, y: wr, z: axles[1], radius: wr, width: 0.28, outward: side, rimRatio: 0.56, rimMaterial: rim, holes: 6, lugs: 10, dual: true)
    }
  }
}

// Custom-cab pumper (Pierce Enforcer class): 10.4 m, 2.5 m wide; tilt
// cab with a raised-roof crew section, white roof cap, chrome bumper
// extension with siren, light bars, pump panel, roll-up compartment
// doors, ladders on the right, hose bed, rear chevrons.
func fireTruck() -> SCNNode {
  let L: Float = 10.4, wr: Float = 0.55
  let axles: [Float] = [1.4, 7.0]
  let red = paint(0xC8102E)
  let capWhite = material("white", 0xF4F5F7, metal: 0.2, rough: 0.35)
  let yellowChevron = material("chevron", 0xF5D20B, rough: 0.4)
  return roadVehicle(length: L) { v in
    cabForward(v, length: 3.55, hw: 1.25, bottom: 0.95, top: 2.95, axle: axles[0], wheel: wr, red, roofStep: (1.9, 0.18))
    // Body: pump house and compartments.
    shell(v, samples(3.6, L, step: 0.25, dense: [(3.6, 3.7, 0.02), (L - 0.1, L, 0.02), (axles[1] - 0.8, axles[1] + 0.8, 0.04)]),
          capStart: red, capEnd: red, { z in
      let b = archBottom(0.62, axles: [axles[1]], wheel: wr, gap: 0.1)(z)
      return boxHalf(1.25, b, z < 4.6 ? 2.9 : 2.55, rb: 0.03, rt: 0.05, sides: 6, arc: 3)
    }, skin: { f in f.n.y < -0.75 ? black : red })
    let fd = Drape(v, axis: 2), sd = Drape(v, axis: 0), up = Drape(v, axis: 1)
    // Cab: white roof cap, windscreen, grille, lamps.
    decalPatches(v, up, [rounded([SIMD2(-1.18, 0.12), SIMD2(1.18, 0.12), SIMD2(1.18, 1.86), SIMD2(-1.18, 1.86)], r: 0.1),
                         rounded([SIMD2(-1.18, 2.2), SIMD2(1.18, 2.2), SIMD2(1.18, 3.5), SIMD2(-1.18, 3.5)], r: 0.1)], capWhite, lift: 0.006, k: 10)
    decalPatches(v, fd, [rounded([SIMD2(-1.08, 1.85), SIMD2(-0.03, 1.85), SIMD2(-0.03, 2.65), SIMD2(-1.04, 2.65)], r: 0.08),
                         rounded([SIMD2(0.03, 1.85), SIMD2(1.08, 1.85), SIMD2(1.04, 2.65), SIMD2(0.03, 2.65)], r: 0.08)], glass,
                 below: true, lift: 0.01, k: 7)
    decalPatches(v, fd, [rounded([SIMD2(-0.6, 1.08), SIMD2(0.6, 1.08), SIMD2(0.6, 1.62), SIMD2(-0.6, 1.62)], r: 0.04)], chrome, below: true, lift: 0.012)
    decalLines(v, fd, (0..<6).map { i in let y = 1.14 + Float(i) * 0.085; return [SIMD2(-0.56, y), SIMD2(0.56, y)] }, width: 0.035, black,
               below: true, mirror: false, lift: 0.018)
    decalPatches(v, fd, [rounded([SIMD2(0.72, 1.12), SIMD2(1.1, 1.12), SIMD2(1.1, 1.36), SIMD2(0.72, 1.36)], r: 0.04)], lens, below: true, mirror: true, lift: 0.014)
    decalPatches(v, fd, [ring2(0.82, 1.24, 0.07, 12), ring2(1.0, 1.24, 0.07, 12)], headlight, below: true, mirror: true, lift: 0.02)
    decalPatches(v, fd, [rounded([SIMD2(0.72, 1.45), SIMD2(1.1, 1.45), SIMD2(1.1, 1.58), SIMD2(0.72, 1.58)], r: 0.03)], lightRed, below: true, mirror: true, lift: 0.016)
    // Cab doors: front and crew, windows.
    for (z0, z1, top) in [(0.35, 1.45, Float(2.62)), (2.05, 3.2, Float(2.82))] as [(Float, Float, Float)] {
      sidePatches(v, sd, [rounded([SIMD2(z0 + 0.1, 1.95), SIMD2(z1 - 0.1, 1.95), SIMD2(z1 - 0.1, top), SIMD2(z0 + 0.1, top)], r: 0.06)], glass, lift: 0.01)
      sideLines(v, sd, [closed(rounded([SIMD2(z0, 1.0), SIMD2(z1, 1.0), SIMD2(z1, top + 0.08), SIMD2(z0, top + 0.08)], r: 0.05))], width: 0.014, black)
    }
    sidePatches(v, sd, [rounded([SIMD2(1.55, 1.95), SIMD2(1.95, 1.95), SIMD2(1.95, 2.62), SIMD2(1.55, 2.62)], r: 0.05)], glass, lift: 0.01)
    // Pump panel and compartments with roll-up doors.
    sidePatches(v, sd, [rounded([SIMD2(3.7, 1.0), SIMD2(4.5, 1.0), SIMD2(4.5, 2.6), SIMD2(3.7, 2.6)], r: 0.03)], alu, lift: 0.01)
    sidePatches(v, sd, [ring2(3.9, 2.3, 0.07, 12), ring2(4.1, 2.3, 0.07, 12), ring2(4.3, 2.3, 0.07, 12), ring2(4.1, 2.05, 0.09, 12)], black, lift: 0.016)
    sidePatches(v, sd, [ring2(3.95, 1.4, 0.1, 12), ring2(4.3, 1.4, 0.1, 12)], chrome, lift: 0.03)
    let doors: [(Float, Float)] = [(4.65, 5.85), (5.95, 6.25), (7.75, 9.0), (9.1, 10.25)]
    for (z0, z1) in doors {
      let yb: Float = (z0 > 5.9 && z1 < 7.8) ? 1.85 : 0.95
      sidePatches(v, sd, [rounded([SIMD2(z0, yb), SIMD2(z1, yb), SIMD2(z1, 2.42), SIMD2(z0, 2.42)], r: 0.02)], doorGrey, lift: 0.01)
      sideLines(v, sd, stride(from: yb + 0.08, to: 2.4, by: 0.08).map { y in [SIMD2(z0 + 0.02, Float(y)), SIMD2(z1 - 0.02, Float(y))] },
                width: 0.012, slat, lift: 0.014)
    }
    sidePatches(v, sd, [rounded([SIMD2(5.95, 1.88), SIMD2(8.1, 1.88), SIMD2(8.1, 2.42), SIMD2(5.95, 2.42)], r: 0.02)], doorGrey, lift: 0.01)
    sideLines(v, sd, stride(from: Float(1.96), to: 2.4, by: 0.08).map { y in [SIMD2(5.97, Float(y)), SIMD2(8.08, Float(y))] }, width: 0.012, slat, lift: 0.014)
    sideLines(v, sd, [[SIMD2(0.1, 0.98), SIMD2(L - 0.1, 0.98)]], width: 0.06, material("stripe-gold", 0xD8B04A, metal: 0.7, rough: 0.3), lift: 0.016)
    // Rear: chevrons, lamps, tailboard.
    var chev: [[SIMD2<Float>]] = [], chevY: [[SIMD2<Float>]] = []
    for i in -8...8 {
      let x0 = Float(i) * 0.3
      let poly = [SIMD2(x0, 0.7), SIMD2(x0 + 0.15, 0.7), SIMD2(x0 + 0.85, 1.4), SIMD2(x0 + 0.7, 1.4)]
      let clipped = poly.map { SIMD2(max(-1.2, min(1.2, $0.x)), $0.y) }
      if i % 2 == 0 { chev.append(clipped) } else { chevY.append(clipped) }
    }
    decalPatches(v, fd, chev, lightRed.copy() as! SCNMaterial, below: false, lift: 0.012)
    decalPatches(v, fd, chevY, yellowChevron, below: false, lift: 0.012)
    decalPatches(v, fd, [rounded([SIMD2(-1.1, 1.55), SIMD2(1.1, 1.55), SIMD2(1.1, 2.45), SIMD2(-1.1, 2.45)], r: 0.02)], doorGrey, below: false, lift: 0.01)
    decalPatches(v, fd, [ring2(1.05, 0.55, 0.07, 12), ring2(0.85, 0.55, 0.07, 12)], taillight, below: false, mirror: true, lift: 0.016)
    box(v, 2.4, 0.08, 0.5, alu, 0, 0.62, L + 0.22)
    // Hose bed: hose loads on top of the rear body.
    let hoseColours = [material("hose-yellow", 0xE8C31B, rough: 0.8), material("hose-red", 0xB01325, rough: 0.8), material("hose-white", 0xEDEDE8, rough: 0.8)]
    for i in 0..<9 {
      let x = -0.9 + Float(i) * 0.225
      box(v, 0.2, 0.18, 4.6, hoseColours[i / 3], x, 2.5, 7.6)
    }
    // Ladders on the right, rails, lights, bumper with siren, mirrors, wheels.
    for y in [2.72, 2.92] as [Float] {
      tube(v, V3(1.32, y, 4.6), V3(1.32, y, 10.0), 0.025, alu, sides: 8)
      tube(v, V3(1.32, y + 0.42, 4.6), V3(1.32, y + 0.42, 10.0), 0.025, alu, sides: 8)
    }
    for k in 0..<18 {
      let z = 4.75 + Float(k) * 0.3
      tube(v, V3(1.32, 2.72, z), V3(1.32, 3.14, z), 0.015, alu, sides: 6)
    }
    for side in [-1, 1] as [Float] {
      tube(v, V3(side * 1.28, 1.2, 3.62), V3(side * 1.28, 2.6, 3.62), 0.025, chrome, sides: 8)
    }
    let bar = holder(v, V3(0, 2.95, 0.7))
    shell(bar, samples(-0.16, 0.16, step: 0.04), { z in
      let f = 1 - pow(abs(z) / 0.16, 4)
      return boxHalf(1.1 * (0.92 + 0.08 * f), 0, 0.14 * (0.7 + 0.3 * f), rb: 0.02, rt: 0.05, sides: 2, arc: 3)
    }, skin: { f in f.n.y < -0.5 ? black : (Int(((f.p.x + 1.1) / 0.275).rounded(.down)) % 2 == 0 ? lightRed : lightWhite) })
    for x in [-1.2, 1.2] as [Float] {
      box(v, 0.16, 0.14, 0.12, lightRed, x, 2.42, L + 0.02)
      box(v, 0.05, 0.14, 0.3, lightRed, x * 1.03, 2.46, 9.9)
      box(v, 0.05, 0.12, 0.3, lightWhite, x * 1.03, 2.62, 5.5)
    }
    let bumper = holder(v, V3(0, 0, -0.55))
    shell(bumper, samples(0, 0.58, step: 0.05), capStart: alu, { z in
      boxHalf(1.24 - 0.12 * pow(1 - z / 0.58, 3), 0.62, 0.95, rb: 0.03, rt: 0.04, sides: 3, arc: 3)
    }, skin: { _ in alu })
    put(v, LatheMesh([SIMD2(0, 0.14), SIMD2(0.2, 0.15), SIMD2(0.24, 0.001)], sides: 18), chrome, 0.55, 1.12, -0.42, rx: -.pi / 2)
    for side in [-1, 1] as [Float] {
      sideMirror(v, at: V3(side * 1.24, 2.25, 0.3), side: side, reach: 0.22, w: 0.2, h: 0.44, chrome)
      roadWheel(v, x: side * 1.05, y: wr, z: axles[0], radius: wr, width: 0.3, outward: side, rimRatio: 0.56, rimMaterial: chrome, holes: 10, lugs: 10)
      roadWheel(v, x: side * 0.97, y: wr, z: axles[1], radius: wr, width: 0.3, outward: side, rimRatio: 0.56, rimMaterial: chrome, holes: 10, lugs: 10, dual: true)
    }
  }
}

// MARK: Motorcycles
// Built nose-first along +Z from the front tyre (z = 0), like the cars:
// tubular or twin-spar frames, a swingarm, forks through triple clamps,
// round-profile tyres on cast or laced wheels with discs and calipers,
// engines built from their real masses (crankcase, cylinders, heads, fins)
// and bodywork skinned through sections so the paint wraps.

let frameBlack = material("frame", 0x1E1F22, metal: 0.4, rough: 0.35)
let alloy = material("alloy", 0xA7ADB4, metal: 0.9, rough: 0.28)
let forkGold = material("fork-gold", 0xC9A13B, metal: 0.95, rough: 0.2)
let engineSilver = material("engine", 0x8E949B, metal: 0.8, rough: 0.35)
let engineDark = material("engine-dark", 0x2F3236, metal: 0.6, rough: 0.4)
let discSteel = material("disc", 0xB9BDC2, metal: 1, rough: 0.35)
let caliperRed = material("caliper", 0xB81D24, metal: 0.4, rough: 0.35)
let spring = material("spring", 0xE2B714, metal: 0.4, rough: 0.35)

/// A motorcycle wheel at (0, r, z): round-profile tyre, rim, hub and either
/// cast spokes (`cast` > 0, split in pairs) or laced wire spokes.
func motoWheel(_ p: SCNNode, z: Float, r: Float, w: Float, rimRatio: Float = 0.72, cast: Int = 0, wires: Int = 0,
               knobs: Bool = false, rimMat: SCNMaterial = alloy, discs: [Float] = [], discR: Float = 0.15) {
  let wh = holder(p, V3(0, r, z))
  let rr = r * rimRatio
  let tr = (r - rr) * 0.62
  let c = r - (r - rr) * 0.55
  var prof: [SIMD2<Float>] = [SIMD2(-w * 0.32, rr * 1.01)]
  for i in 0...12 {
    let a = -Float.pi * 0.62 + Float.pi * 1.24 * Float(i) / 12
    prof.append(SIMD2(sin(a) * w / 2, c + cos(a) * tr * 0.98 + (r - c - tr * 0.98) * cos(a) * cos(a)))
  }
  prof.append(SIMD2(w * 0.32, rr * 1.01))
  put(wh, LatheMesh(prof, sides: 40, caps: false), tyre, 0, 0, 0, rz: -.pi / 2)
  if knobs {
    for i in 0..<36 {
      let a = Float(i) / 36 * 2 * .pi
      for side in [-1, 1] as [Float] {
        let x = side * w * (i % 2 == 0 ? 0.22 : 0.36)
        let n = holder(wh, V3(x, cos(a) * (r - 0.004), sin(a) * (r - 0.004)), rx: -a)
        put(n, BoxMesh(width: CGFloat(w * 0.26), height: 0.018, length: 0.032), tyre, 0, 0, 0)
      }
    }
  }
  // Rim band.
  put(wh, LatheMesh([SIMD2(-w * 0.36, rr * 0.93), SIMD2(-w * 0.36, rr * 1.01), SIMD2(w * 0.36, rr * 1.01), SIMD2(w * 0.36, rr * 0.93)],
                    sides: 36, caps: false, twoSided: true), rimMat, 0, 0, 0, rz: -.pi / 2)
  put(wh, CylinderMesh(radius: CGFloat(r * 0.13), height: CGFloat(w * 0.9), sides: 16), rimMat, 0, 0, 0, rz: .pi / 2)
  for i in 0..<cast {
    let a = Float(i) / Float(cast) * 2 * .pi
    for da in [-0.09, 0.09] as [Float] {
      let hub = V3(0, cos(a) * r * 0.12, sin(a) * r * 0.12)
      let out = V3(0, cos(a + da) * rr * 0.94, sin(a + da) * rr * 0.94)
      strut(wh, hub, out, 0.022, 0.03, rimMat, up: V3(1, 0, 0))
    }
  }
  for i in 0..<wires {
    let a = Float(i) / Float(wires) * 2 * .pi
    let side: Float = i % 2 == 0 ? 1 : -1
    let a0 = a + side * 0.35
    rod(wh, V3(side * w * 0.3, cos(a0) * r * 0.1, sin(a0) * r * 0.1), V3(side * w * 0.05, cos(a) * rr * 0.93, sin(a) * rr * 0.93), 0.003, chrome, sides: 3)
  }
  for x in discs {
    put(wh, TubeMesh(innerRadius: CGFloat(discR * 0.62), outerRadius: CGFloat(discR), height: 0.006, sides: 28), discSteel, x, 0, 0, rz: .pi / 2)
    put(wh, TubeMesh(innerRadius: CGFloat(r * 0.13), outerRadius: CGFloat(discR * 0.64), height: 0.004, sides: 20), engineDark, x, 0, 0, rz: .pi / 2)
  }
}

/// A smooth body or tank through (z, half width, bottom, top) keys with
/// rounded-box sections of roundness `n` (higher = boxier).
func motoBody(_ p: SCNNode, _ keys: [(Float, Float, Float, Float)], x: Float = 0, step: Float = 0.02, rb: Float = 0.5, rt: Float = 0.5,
              lean: Float = 0, cap: SCNMaterial? = nil, skin: (Facet) -> SCNMaterial) {
  let hw = curve(keys.map { ($0.0, $0.1) }), b = curve(keys.map { ($0.0, $0.2) }), t = curve(keys.map { ($0.0, $0.3) })
  shell(p, samples(keys[0].0, keys[keys.count - 1].0, step: step), x: x, capStart: cap, capEnd: cap, { z in
    let h = max(0.004, t(z) - b(z)), w = max(0.003, hw(z))
    return boxHalf(w, b(z), b(z) + h, rb: min(w, h) * rb, rt: min(w, h) * rt, lean: w * lean, sides: 4, arc: 5)
  }, skin: skin)
}

func coilSpring(_ p: SCNNode, _ a: V3, _ b: V3, r: Float, turns: Int, _ m: SCNMaterial) {
  let (h, L) = axisHolder(p, a, b)
  let n = turns * 10
  for i in 0..<n {
    let t0 = Float(i) / Float(n), t1 = Float(i + 1) / Float(n)
    let a0 = t0 * Float(turns) * 2 * .pi, a1 = t1 * Float(turns) * 2 * .pi
    rod(h, V3(cos(a0) * r, t0 * L, sin(a0) * r), V3(cos(a1) * r, t1 * L, sin(a1) * r), r * 0.14, m, sides: 4)
  }
}

/// A finned cylinder from `a` to `b` (air-cooled engines).
func finnedBarrel(_ p: SCNNode, _ a: V3, _ b: V3, r: Float, fins: Int, finR: Float, _ m: SCNMaterial) {
  let (h, L) = axisHolder(p, a, b)
  put(h, LatheMesh([SIMD2(0, r), SIMD2(L, r)], sides: 18, caps: true), m, 0, 0, 0)
  for i in 0..<fins {
    let y = L * (Float(i) + 0.5) / Float(fins)
    put(h, LatheMesh([SIMD2(y - 0.004, finR), SIMD2(y + 0.004, finR)], sides: 18, caps: true), m, 0, 0, 0)
  }
}

// Sport bike (litre superbike class): 2.07 m, 1.405 m wheelbase, 24-degree
// rake. Aluminium twin-spar frame and banana swingarm, gold upside-down
// fork, full fairing with twin LED eyes and a smoked screen, tank, seat
// and a pointed tail, inline-four with radiator, underslung silencer,
// split five-spoke wheels, twin front discs with radial calipers.
// Cruiser (Softail class): 2.37 m, 1.665 m wheelbase, 30-degree rake,
// black tubular frame, chrome fork shrouds and nacelle with a round
// headlamp, pulled-back bars, teardrop tank with a console, stepped seat,
// deep valanced fenders, 45-degree V-twin with finned barrels, round air
// cleaner, staggered shotgun pipes, laced wheels and floorboards.
// Dirt bike (MX class): 2.18 m, 1.48 m wheelbase, long-travel fork, 21/19
// inch laced wheels with knobbly tyres, high fenders, radiator shrouds, a
// long flat seat, number plates, single-cylinder engine and a high pipe.
func motorcycle(kind: String, body: UInt32) -> SCNNode {
  let p = paint(body)
  switch kind {
  case "sport": return sportBike(p)
  case "cruiser": return cruiser(p)
  default: return dirtBike(p)
  }
}

func sportBike(_ p: SCNMaterial) -> SCNNode {
  let L: Float = 2.07
  let fz: Float = 0.3, rz: Float = 1.705, fr: Float = 0.3, rr: Float = 0.31
  let rake: Float = 24 * .pi / 180
  let head = V3(0, fr + cos(rake) * 0.6, fz + sin(rake) * 0.6)
  let pivot = V3(0, 0.47, 1.14)
  return roadVehicle(length: L) { v in
    motoWheel(v, z: fz, r: fr, w: 0.12, cast: 5, rimMat: engineDark, discs: [-0.075, 0.075], discR: 0.16)
    motoWheel(v, z: rz, r: rr, w: 0.19, cast: 5, rimMat: engineDark, discs: [-0.07], discR: 0.11)
    // Fork: gold upper tubes, black lower legs, radial calipers, triple clamps.
    for x in [-0.085, 0.085] as [Float] {
      let low = V3(x, fr, fz), up = V3(x, head.y + 0.06, head.z + 0.03)
      let mid = low + (up - low) * 0.42
      tube(v, low, mid, 0.03, engineDark, sides: 12)
      tube(v, mid, up, 0.025, forkGold, sides: 12)
      box(v, 0.03, 0.1, 0.05, forkGold, x * 1.05, fr + 0.1, fz + 0.08, rx: rake)
    }
    for y in [head.y - 0.04, head.y + 0.05] {
      box(v, 0.24, 0.025, 0.07, alloy, 0, y, head.z - 0.01, rx: rake)
    }
    // Clip-on bars, levers, mirrors (on the fairing later).
    for side in [-1, 1] as [Float] {
      tube(v, V3(side * 0.1, head.y + 0.03, head.z + 0.02), V3(side * 0.33, head.y - 0.0, head.z + 0.1), 0.012, frameBlack, sides: 8)
      tube(v, V3(side * 0.24, head.y - 0.04, head.z + 0.04), V3(side * 0.34, head.y - 0.03, head.z + 0.0), 0.006, alloy, sides: 4)
    }
    // Twin-spar frame and swingarm.
    for side in [-1, 1] as [Float] {
      strut(v, V3(side * 0.12, head.y - 0.02, head.z + 0.04), V3(side * 0.17, 0.66, 0.98), 0.1, 0.04, alloy, up: V3(1, 0, 0))
      strut(v, V3(side * 0.17, 0.66, 0.98), V3(side * 0.15, pivot.y, pivot.z), 0.1, 0.04, alloy, up: V3(1, 0, 0))
      strut(v, V3(side * 0.13, pivot.y, pivot.z), V3(side * 0.13, rr + 0.04, rz), 0.07, 0.035, alloy, up: V3(1, 0, 0))
      put(v, CylinderMesh(radius: 0.03, height: 0.02, sides: 12), alloy, side * 0.15, rr, rz, rz: .pi / 2)
    }
    // Inline-four: crankcase, tilted block and head, radiator, sprocket, chain.
    motoBody(v, [(0.72, 0.15, 0.24, 0.5), (0.85, 0.2, 0.2, 0.52), (1.1, 0.19, 0.22, 0.5), (1.2, 0.12, 0.3, 0.46)], rb: 0.3, rt: 0.3, cap: engineDark) { _ in engineDark }
    strut(v, V3(0, 0.48, 0.86), V3(0, 0.72, 0.78), 0.12, 0.36, engineSilver, up: V3(1, 0, 0))
    strut(v, V3(0, 0.72, 0.78), V3(0, 0.8, 0.75), 0.13, 0.34, engineDark, up: V3(1, 0, 0))
    box(v, 0.42, 0.34, 0.04, frameBlack, 0, 0.62, 0.66, rx: -0.15)
    put(v, CylinderMesh(radius: 0.05, height: 0.012, sides: 14), engineDark, 0.1, 0.4, 1.12, rz: .pi / 2)
    tube(v, V3(0.1, 0.45, 1.12), V3(0.1, rr + 0.09, rz), 0.008, frameBlack, sides: 4)
    tube(v, V3(0.1, 0.35, 1.12), V3(0.1, rr - 0.07, rz), 0.008, frameBlack, sides: 4)
    put(v, CylinderMesh(radius: 0.09, height: 0.01, sides: 18), engineDark, 0.1, rr, rz, rz: .pi / 2)
    // Rear shock with spring, under the seat.
    tube(v, V3(0, 0.42, 1.25), V3(0, 0.72, 1.18), 0.022, alloy, sides: 8)
    coilSpring(v, V3(0, 0.46, 1.24), V3(0, 0.66, 1.2), r: 0.04, turns: 6, spring)
    // Exhaust: headers under the engine to a short silencer under the right.
    for x in [-0.09, -0.03, 0.03, 0.09] as [Float] {
      tube(v, V3(x, 0.66, 0.66), V3(x * 0.8, 0.3, 0.72), 0.016, alloy, sides: 6)
      tube(v, V3(x * 0.8, 0.3, 0.72), V3(x * 0.5, 0.21, 0.95), 0.016, alloy, sides: 6)
    }
    motoBody(v, [(0.95, 0.07, 0.17, 0.27), (1.2, 0.12, 0.16, 0.36), (1.45, 0.1, 0.22, 0.38)], x: 0.1, rb: 0.6, rt: 0.6, cap: frameBlack) { _ in engineDark }
    // Fairing, tank, seat and tail: one skin.
    let seat0: Float = 1.2, seat1: Float = 1.58
    motoBody(v, [(0.32, 0.03, 0.75, 0.8), (0.38, 0.1, 0.66, 0.88), (0.48, 0.15, 0.56, 0.95), (0.6, 0.17, 0.46, 1.0), (0.76, 0.17, 0.42, 0.98),
                 (0.95, 0.165, 0.42, 0.99), (1.1, 0.15, 0.46, 0.96), (1.22, 0.12, 0.66, 0.88), (1.5, 0.11, 0.73, 0.89), (1.62, 0.1, 0.77, 0.95),
                 (1.85, 0.065, 0.84, 1.0), (2.02, 0.02, 0.92, 0.99)], rb: 0.3, rt: 0.5, lean: 0.3, cap: p) { f in
      let z = f.p.z + L / 2
      if f.n.y > 0.55 && z > seat0 && z < seat1 { return leather }
      if f.n.y > 0.2 && z > 0.47 && z < 0.66 && abs(f.p.x) < 0.17 { return glass }
      return p
    }
    motoBody(v, [(0.66, 0.06, 0.24, 0.3), (0.8, 0.15, 0.2, 0.42), (1.05, 0.14, 0.2, 0.42), (1.12, 0.05, 0.26, 0.38)], rb: 0.4, rt: 0.2, cap: p) { _ in p }
    let fd = Drape(v, axis: 2), sd = Drape(v, axis: 0)
    decalPatches(v, fd, [rounded([SIMD2(0.03, 0.78), SIMD2(0.12, 0.8), SIMD2(0.14, 0.83), SIMD2(0.04, 0.82)], r: 0.008)], headlight,
                 below: true, mirror: true, lift: 0.006)
    decalPatches(v, fd, [rounded([SIMD2(-0.045, 0.69), SIMD2(0.045, 0.69), SIMD2(0.035, 0.77), SIMD2(-0.035, 0.77)], r: 0.01)], black,
                 below: true, lift: 0.006)
    decalPatches(v, fd, [rounded([SIMD2(-0.06, 0.95), SIMD2(0.06, 0.95), SIMD2(0.05, 0.98), SIMD2(-0.05, 0.98)], r: 0.008)], taillight,
                 below: false, lift: 0.006)
    sidePatches(v, sd, [rounded([SIMD2(0.62, 0.45), SIMD2(0.78, 0.4), SIMD2(0.78, 0.48), SIMD2(0.64, 0.52)], r: 0.01),
                        rounded([SIMD2(0.84, 0.36), SIMD2(1.0, 0.33), SIMD2(1.0, 0.4), SIMD2(0.86, 0.43)], r: 0.01)], black, lift: 0.006)
    sideLines(v, sd, [[SIMD2(0.5, 0.82), SIMD2(0.9, 0.72), SIMD2(1.15, 0.6)], [SIMD2(1.62, 0.84), SIMD2(1.95, 0.93)]], width: 0.022, white, lift: 0.006)
    // Front fender, mirrors, rear hugger, plate hanger, pegs.
    let fender = holder(v, V3(0, fr, fz))
    put(fender, LatheMesh([SIMD2(-0.065, fr + 0.03), SIMD2(0.065, fr + 0.03)], sides: 24, caps: false, twoSided: true, from: 0.72 * .pi, to: 1.3 * .pi),
        p, 0, 0, 0, rz: -.pi / 2)
    for side in [-1, 1] as [Float] {
      tube(v, V3(side * 0.2, 0.92, 0.55), V3(side * 0.3, 0.98, 0.53), 0.008, frameBlack, sides: 4)
      box(v, 0.1, 0.05, 0.04, frameBlack, side * 0.32, 0.99, 0.53)
      tube(v, V3(side * 0.12, 0.5, 1.2), V3(side * 0.22, 0.52, 1.24), 0.012, alloy, sides: 6)
    }
    strut(v, V3(0, 0.88, 1.9), V3(0, 0.62, 2.0), 0.08, 0.012, frameBlack, up: V3(1, 0, 0))
    box(v, 0.17, 0.11, 0.01, plate, 0, 0.6, 2.01)
  }
}

func cruiser(_ p: SCNMaterial) -> SCNNode {
  let L: Float = 2.37
  let fz: Float = 0.33, rz: Float = 1.995, r: Float = 0.33
  let rake: Float = 30 * .pi / 180
  let head = V3(0, r + cos(rake) * 0.72, fz + sin(rake) * 0.72)
  return roadVehicle(length: L) { v in
    motoWheel(v, z: fz, r: r, w: 0.16, rimRatio: 0.7, wires: 40, rimMat: chrome, discs: [0.07], discR: 0.15)
    motoWheel(v, z: rz, r: r, w: 0.24, rimRatio: 0.7, wires: 40, rimMat: chrome, discs: [-0.09], discR: 0.14)
    // Fork with chrome shrouds, nacelle, headlamp, wide bars.
    for x in [-0.11, 0.11] as [Float] {
      let low = V3(x, r, fz), up = V3(x, head.y + 0.05, head.z + 0.03)
      tube(v, low, low + (up - low) * 0.5, 0.032, chrome, sides: 14)
      tube(v, low + (up - low) * 0.5, up, 0.04, chrome, sides: 14)
    }
    motoBody(v, [(head.z - 0.2, 0.06, head.y - 0.12, head.y + 0.0), (head.z - 0.1, 0.15, head.y - 0.14, head.y + 0.04),
                 (head.z + 0.06, 0.14, head.y - 0.12, head.y + 0.05)], rb: 0.5, rt: 0.5, cap: chrome) { _ in chrome }
    let lamp = holder(v, V3(0, head.y - 0.06, head.z - 0.2))
    put(lamp, LatheMesh([SIMD2(-0.1, 0.11), SIMD2(0.02, 0.115), SIMD2(0.035, 0.001)], sides: 24), chrome, 0, 0, 0, rx: -.pi / 2)
    put(lamp, CylinderMesh(radius: 0.1, height: 0.01, sides: 24), headlight, 0, 0, -0.037, rx: .pi / 2)
    for side in [-1, 1] as [Float] {
      tube(v, V3(side * 0.08, head.y + 0.08, head.z + 0.02), V3(side * 0.3, head.y + 0.14, head.z - 0.02), 0.014, chrome, sides: 8)
      tube(v, V3(side * 0.3, head.y + 0.14, head.z - 0.02), V3(side * 0.4, head.y + 0.12, head.z + 0.18), 0.014, chrome, sides: 8)
      put(v, CylinderMesh(radius: 0.022, height: 0.1, sides: 10), black, side * 0.4, head.y + 0.12, head.z + 0.2, rx: .pi / 2)
      put(v, LatheMesh([SIMD2(0, 0.03), SIMD2(0.04, 0.03), SIMD2(0.06, 0.001)], sides: 12), chrome, side * 0.2, head.y - 0.1, head.z - 0.16, rx: -.pi / 2)
    }
    // Frame: backbone, down tubes, cradle, rear stays.
    let seatNode = V3(0, 0.68, 1.35)
    for side in [-1, 1] as [Float] {
      tube(v, V3(side * 0.03, head.y - 0.05, head.z + 0.03), V3(side * 0.09, 0.3, head.z + 0.18), 0.022, frameBlack, sides: 10)
      tube(v, V3(side * 0.09, 0.3, head.z + 0.18), V3(side * 0.1, 0.17, 0.9), 0.022, frameBlack, sides: 10)
      tube(v, V3(side * 0.1, 0.17, 0.9), V3(side * 0.12, 0.2, 1.35), 0.022, frameBlack, sides: 10)
      tube(v, V3(side * 0.12, 0.2, 1.35), V3(side * 0.12, seatNode.y, seatNode.z), 0.022, frameBlack, sides: 10)
      tube(v, V3(side * 0.13, 0.3, 1.38), V3(side * 0.15, r, rz), 0.024, frameBlack, sides: 10)
      tube(v, V3(side * 0.13, seatNode.y, seatNode.z), V3(side * 0.15, r + 0.05, rz - 0.05), 0.02, frameBlack, sides: 10)
    }
    tube(v, V3(0, head.y - 0.04, head.z + 0.03), V3(0, seatNode.y + 0.02, seatNode.z), 0.028, frameBlack, sides: 10)
    // V-twin: crankcase, two finned barrels at 45 degrees, heads, rocker
    // boxes, pushrod tubes, air cleaner, primary cover, transmission.
    motoBody(v, [(0.9, 0.1, 0.18, 0.42), (1.05, 0.15, 0.16, 0.44), (1.25, 0.15, 0.18, 0.42), (1.38, 0.1, 0.22, 0.38)], rb: 0.4, rt: 0.4, cap: engineSilver) { _ in engineSilver }
    let crank = V3(0, 0.36, 1.12)
    for (k, a) in [(-1, -22.5), (1, 22.5)] as [(Float, Float)] {
      let d = V3(0, cos(Float(a) * .pi / 180), sin(Float(a) * .pi / 180))
      let base = crank + d * 0.08, top = crank + d * 0.33
      finnedBarrel(v, base, top, r: 0.06, fins: 9, finR: 0.085, engineSilver)
      finnedBarrel(v, top, top + d * 0.08, r: 0.06, fins: 3, finR: 0.08, engineSilver)
      motoBody(v, [(top.z - 0.07, 0.07, top.y + 0.06, top.y + 0.11), (top.z + 0.07, 0.07, top.y + 0.06, top.y + 0.11)], rb: 0.6, rt: 0.6, cap: chrome) { _ in chrome }
      tube(v, crank + V3(0.05, -0.05, k * 0.02), top + V3(0.05, 0.0, k * 0.0), 0.012, chrome, sides: 6)
    }
    put(v, LatheMesh([SIMD2(0, 0.13), SIMD2(0.05, 0.13), SIMD2(0.07, 0.09), SIMD2(0.075, 0.001)], sides: 28), chrome, 0.14, 0.62, 1.12, rz: -.pi / 2)
    motoBody(v, [(0.88, 0.04, 0.17, 0.34), (1.05, 0.05, 0.14, 0.38), (1.5, 0.05, 0.18, 0.36), (1.6, 0.04, 0.22, 0.32)], x: -0.17, rb: 0.6, rt: 0.6,
             cap: chrome) { _ in chrome }
    // Teardrop tank with console, stepped seat, fenders.
    motoBody(v, [(head.z + 0.0, 0.05, head.y - 0.08, head.y + 0.0), (head.z + 0.1, 0.17, head.y - 0.18, head.y + 0.06),
                 (head.z + 0.35, 0.2, 0.66, head.y + 0.06), (1.32, 0.12, 0.68, 0.84)], rb: 0.6, rt: 0.6, cap: p) { _ in p }
    motoBody(v, [(head.z + 0.12, 0.035, head.y + 0.06, head.y + 0.08), (head.z + 0.34, 0.035, head.y + 0.03, head.y + 0.07)], rb: 0.5, rt: 0.5,
             cap: chrome) { _ in chrome }
    motoBody(v, [(1.28, 0.15, 0.6, 0.72), (1.4, 0.2, 0.58, 0.7), (1.62, 0.17, 0.62, 0.76), (1.78, 0.12, 0.72, 0.85), (1.86, 0.1, 0.8, 0.87)],
             rb: 0.5, rt: 0.6, cap: leather) { _ in leather }
    for (cz, cr, w, a0, a1) in [(fz, r, Float(0.2), Float(0.62), Float(1.42)), (rz, r, Float(0.27), Float(0.3), Float(1.08))] {
      let fender = holder(v, V3(0, cr, cz))
      let prof: [SIMD2<Float>] = (0...6).map { i in
        let t = -Float.pi / 2 + Float.pi * Float(i) / 6
        return SIMD2(sin(t) * w / 2, cr + 0.04 + cos(t) * 0.05)
      }
      put(fender, LatheMesh(prof, sides: 28, caps: false, twoSided: true, from: a0 * .pi, to: a1 * .pi), p, 0, 0, 0, rz: -.pi / 2)
    }
    // Shotgun pipes on the right, floorboards, tail lamp, signals.
    tube(v, V3(0.08, 0.56, 1.0), V3(0.2, 0.33, 1.0), 0.03, chrome, sides: 10)
    tube(v, V3(0.08, 0.6, 1.25), V3(0.2, 0.4, 1.2), 0.03, chrome, sides: 10)
    tube(v, V3(0.2, 0.33, 1.0), V3(0.21, 0.3, 2.25), 0.042, chrome, sides: 14)
    tube(v, V3(0.2, 0.4, 1.2), V3(0.21, 0.42, 2.25), 0.042, chrome, sides: 14)
    for side in [-1, 1] as [Float] {
      box(v, 0.11, 0.015, 0.28, rubber, side * 0.3, 0.3, 0.86)
      tube(v, V3(side * 0.11, 0.3, 0.86), V3(side * 0.25, 0.3, 0.86), 0.012, chrome, sides: 6)
      tube(v, V3(side * 0.1, 0.62, 2.18), V3(side * 0.17, 0.62, 2.2), 0.008, chrome, sides: 4)
      put(v, LatheMesh([SIMD2(0, 0.022), SIMD2(0.04, 0.022), SIMD2(0.055, 0.001)], sides: 10), amber, side * 0.18, 0.62, 2.2, rx: .pi / 2)
    }
    put(v, LatheMesh([SIMD2(0, 0.035), SIMD2(0.025, 0.035), SIMD2(0.035, 0.001)], sides: 14), taillight, 0, 0.66, 2.26, rx: .pi / 2)
  }
}

func dirtBike(_ p: SCNMaterial) -> SCNNode {
  let L: Float = 2.18
  let fz: Float = 0.36, rz: Float = 1.84, fr: Float = 0.355, rr: Float = 0.34
  let rake: Float = 27 * .pi / 180
  let head = V3(0, fr + cos(rake) * 0.85, fz + sin(rake) * 0.85)
  return roadVehicle(length: L) { v in
    motoWheel(v, z: fz, r: fr, w: 0.085, rimRatio: 0.76, wires: 36, knobs: true, rimMat: engineDark, discs: [0.06], discR: 0.13)
    motoWheel(v, z: rz, r: rr, w: 0.115, rimRatio: 0.72, wires: 36, knobs: true, rimMat: engineDark, discs: [-0.07], discR: 0.11)
    for x in [-0.09, 0.09] as [Float] {
      let low = V3(x, fr, fz), up = V3(x, head.y + 0.06, head.z + 0.03)
      tube(v, low, low + (up - low) * 0.55, 0.03, engineDark, sides: 12)
      tube(v, low + (up - low) * 0.55, up, 0.027, forkGold, sides: 12)
    }
    for y in [head.y - 0.06, head.y + 0.05] { box(v, 0.24, 0.03, 0.08, alloy, 0, y, head.z, rx: rake) }
    tube(v, V3(-0.4, head.y + 0.13, head.z + 0.07), V3(0.4, head.y + 0.13, head.z + 0.07), 0.013, alloy, sides: 8)
    tube(v, V3(-0.16, head.y + 0.19, head.z + 0.06), V3(0.16, head.y + 0.19, head.z + 0.06), 0.012, alloy, sides: 8)
    for side in [-1, 1] as [Float] {
      tube(v, V3(side * 0.04, head.y + 0.06, head.z + 0.05), V3(side * 0.16, head.y + 0.19, head.z + 0.06), 0.012, alloy, sides: 8)
      put(v, CylinderMesh(radius: 0.02, height: 0.11, sides: 10), black, side * 0.42, head.y + 0.13, head.z + 0.07, rz: .pi / 2)
    }
    // Perimeter frame (painted tubes), swingarm, shock.
    let frame = material("frame", 0x2A2C30, metal: 0.4, rough: 0.35)
    for side in [-1, 1] as [Float] {
      tube(v, V3(side * 0.04, head.y - 0.03, head.z + 0.03), V3(side * 0.13, 0.82, 0.98), 0.02, frame, sides: 10)
      tube(v, V3(side * 0.13, 0.82, 0.98), V3(side * 0.12, 0.42, 1.15), 0.02, frame, sides: 10)
      tube(v, V3(side * 0.12, 0.42, 1.15), V3(side * 0.07, 0.3, 0.95), 0.018, frame, sides: 10)
      tube(v, V3(side * 0.13, 0.82, 0.98), V3(side * 0.1, 0.93, 1.75), 0.014, alloy, sides: 8)
      strut(v, V3(side * 0.11, 0.45, 1.16), V3(side * 0.1, rr, rz), 0.06, 0.03, alloy, up: V3(1, 0, 0))
    }
    tube(v, V3(0, head.y - 0.06, head.z + 0.05), V3(0, 0.3, 0.95), 0.022, frame, sides: 10)
    tube(v, V3(0, 0.82, 1.1), V3(0, 0.5, 1.32), 0.022, alloy, sides: 8)
    coilSpring(v, V3(0, 0.78, 1.12), V3(0, 0.55, 1.29), r: 0.045, turns: 7, spring)
    // Single: crankcase, upright finned... (liquid cooled) block, head, radiator.
    motoBody(v, [(0.85, 0.08, 0.27, 0.52), (1.0, 0.12, 0.25, 0.56), (1.15, 0.1, 0.3, 0.52)], rb: 0.4, rt: 0.4, cap: engineDark) { _ in engineDark }
    strut(v, V3(0, 0.52, 0.95), V3(0, 0.74, 0.9), 0.14, 0.15, engineSilver, up: V3(1, 0, 0))
    strut(v, V3(0, 0.74, 0.9), V3(0, 0.8, 0.88), 0.16, 0.17, engineDark, up: V3(1, 0, 0))
    for side in [-1, 1] as [Float] { box(v, 0.03, 0.28, 0.2, frameBlack, side * 0.13, 0.7, 0.85, rx: -0.2) }
    // Header and high silencer on the right.
    tube(v, V3(0.02, 0.7, 0.83), V3(0.12, 0.42, 0.8), 0.022, alloy, sides: 8)
    tube(v, V3(0.12, 0.42, 0.8), V3(0.16, 0.48, 1.25), 0.022, alloy, sides: 8)
    tube(v, V3(0.16, 0.48, 1.25), V3(0.16, 0.74, 1.55), 0.024, alloy, sides: 8)
    motoBody(v, [(1.5, 0.042, 0.69, 0.78), (1.95, 0.045, 0.8, 0.89)], x: 0.16, rb: 0.6, rt: 0.6, cap: engineDark) { _ in alloy }
    // Tank and shrouds, long seat, side plates, fenders, number plate.
    motoBody(v, [(head.z + 0.02, 0.06, head.y - 0.1, head.y - 0.02), (head.z + 0.1, 0.14, 0.72, head.y + 0.0), (1.0, 0.13, 0.78, 0.98),
                 (1.12, 0.06, 0.88, 0.97)], rb: 0.5, rt: 0.5, cap: p) { _ in p }
    for side in [-1, 1] as [Float] {
      motoBody(v, [(head.z + 0.0, 0.01, 0.74, head.y - 0.04), (head.z + 0.18, 0.025, 0.66, 0.98), (0.98, 0.012, 0.72, 0.9)], x: side * 0.16,
               rb: 0.5, rt: 0.5, cap: p) { _ in p }
    }
    motoBody(v, [(0.92, 0.06, 0.92, 0.99), (1.1, 0.12, 0.92, 1.0), (1.6, 0.1, 0.92, 0.99), (1.78, 0.05, 0.93, 0.98)], rb: 0.4, rt: 0.6, cap: black) { _ in black }
    for side in [-1, 1] as [Float] {
      motoBody(v, [(1.3, 0.008, 0.66, 0.9), (1.65, 0.008, 0.78, 0.93)], x: side * 0.13, rb: 0.5, rt: 0.5, cap: white) { _ in white }
    }
    motoBody(v, [(1.55, 0.09, 0.95, 0.97), (1.95, 0.12, 0.97, 0.99), (2.17, 0.06, 1.0, 1.02)], rb: 0.4, rt: 0.6, cap: p) { _ in p }
    motoBody(v, [(fz - 0.36, 0.03, fr * 2 + 0.12, fr * 2 + 0.14), (fz - 0.1, 0.08, fr * 2 + 0.06, fr * 2 + 0.1), (fz + 0.2, 0.08, fr * 2 + 0.06, fr * 2 + 0.1),
                 (fz + 0.36, 0.05, fr * 2 + 0.0, fr * 2 + 0.03)], rb: 0.5, rt: 0.5, cap: p) { _ in p }
    let numberPlate = holder(v, V3(0, head.y - 0.02, head.z - 0.1), rx: -rake)
    motoBody(numberPlate, [(-0.02, 0.12, -0.14, 0.12), (0.02, 0.12, -0.14, 0.12)], rb: 0.3, rt: 0.3, cap: white) { _ in white }
    for side in [-1, 1] as [Float] { tube(v, V3(side * 0.12, 0.5, 1.15), V3(side * 0.22, 0.5, 1.18), 0.012, alloy, sides: 6) }
  }
}

// MARK: Rail

let bellows = material("bellows", 0x2A2B2D, rough: 0.9)
let roofGrey = material("roof", 0xA9AEB4, metal: 0.4, rough: 0.45)

/// A bogie: frame, two wheelsets with visible wheels, springs.
func bogie(_ p: SCNNode, z: Float, gauge: Float = 1.435, wheel r: Float = 0.42, base: Float = 2.4) {
  box(p, gauge + 0.3, 0.32, base + 0.6, engineDark, 0, r + 0.08, z)
  for dz in [-base / 2, base / 2] {
    for side in [-1, 1] as [Float] {
      put(p, CylinderMesh(radius: CGFloat(r), height: 0.12, sides: 20), alu, side * gauge / 2, r, z + dz, rz: .pi / 2)
      put(p, CylinderMesh(radius: CGFloat(r * 0.5), height: 0.14, sides: 14), engineDark, side * gauge / 2 + side * 0.01, r, z + dz, rz: .pi / 2)
    }
    tube(p, V3(-gauge / 2, r, z + dz), V3(gauge / 2, r, z + dz), 0.07, engineDark, sides: 8)
  }
  for side in [-1, 1] as [Float] { coilSpring(p, V3(side * (gauge / 2 + 0.05), r + 0.25, z), V3(side * (gauge / 2 + 0.05), r + 0.55, z), r: 0.1, turns: 4, engineDark) }
}

/// A pantograph folded half-up on the roof at z.
func pantograph(_ p: SCNNode, y: Float, z: Float) {
  box(p, 0.9, 0.1, 1.2, roofGrey, 0, y + 0.05, z)
  for x in [-0.25, 0.25] as [Float] {
    tube(p, V3(x, y + 0.12, z - 0.4), V3(x * 0.4, y + 0.8, z + 0.6), 0.03, alu, sides: 6)
    tube(p, V3(x * 0.4, y + 0.8, z + 0.6), V3(x, y + 1.25, z - 0.5), 0.025, alu, sides: 6)
  }
  box(p, 1.7, 0.05, 0.1, alu, 0, y + 1.27, z - 0.5)
}

// Low-floor articulated tram (Citadis/Avenio class), two 15 m sections:
// raked cab with a wraparound windscreen and a sign, flush glazing with
// slim pillars, glazed double sliding doors on both sides, livery skirt,
// roof equipment pods, a pantograph, bellows at the joint, bogie skirts.
func tram(livery: UInt32) -> SCNNode {
  let L: Float = 30.6, W: Float = 2.65, H: Float = 3.45
  let p = paint(livery)
  let body = material("white", 0xF4F5F7, metal: 0.2, rough: 0.35)
  return roadVehicle(length: L) { v in
    let secL: Float = 15.0
    for (k, z0) in [Float(0), secL + 0.6].enumerated() {
      let cabFront = k == 0, cabBack = k == 1
      let top = curve([(0, cabFront ? H - 0.45 : H), (0.6, cabFront ? H - 0.12 : H), (1.4, H), (secL - 1.4, H), (secL - 0.6, cabBack ? H - 0.12 : H),
                       (secL, cabBack ? H - 0.45 : H)])
      let hw = curve([(0, cabFront ? W / 2 - 0.3 : W / 2 - 0.02), (0.5, cabFront ? W / 2 - 0.08 : W / 2), (1.2, W / 2), (secL - 1.2, W / 2),
                      (secL - 0.5, cabBack ? W / 2 - 0.08 : W / 2), (secL, cabBack ? W / 2 - 0.3 : W / 2 - 0.02)])
      let bot = curve([(0, cabFront ? 0.45 : 0.32), (0.4, 0.32), (secL - 0.4, 0.32), (secL, cabBack ? 0.45 : 0.32)])
      let sec = holder(v, V3(0, 0, z0))
      shell(sec, samples(0, secL, step: 0.15, dense: [(0, 1.6, 0.04), (secL - 1.6, secL, 0.04)]), capStart: body, capEnd: body, { z in
        boxHalf(hw(z), bot(z), top(z), rb: 0.1, rt: 0.28, lean: 0.06, bow: 0.01, sides: 8, arc: 5)
      }, skin: { f in f.n.y < -0.75 ? bellows : body })
      // Roof pods.
      shell(sec, samples(3.0, 11.5, step: 0.25, dense: [(3.0, 3.6, 0.05), (10.9, 11.5, 0.05)]), capStart: roofGrey, capEnd: roofGrey, { z in
        let f = min(1, (z - 3.0) / 0.6, (11.5 - z) / 0.6)
        return boxHalf(0.95, H - 0.05, H + 0.32 * f * f * (3 - 2 * f) + 0.01, rb: 0.02, rt: 0.12, lean: 0.06, sides: 3, arc: 3)
      }, skin: { _ in roofGrey })
    }
    // Bellows between sections.
    shell(v, samples(secL - 0.05, secL + 0.65, step: 0.1), { z in
      let ripple = 0.04 * sin((z - secL) * 40)
      return boxHalf(W / 2 - 0.12 + ripple, 0.4, H - 0.15, rb: 0.1, rt: 0.2, sides: 6, arc: 4)
    }, skin: { _ in bellows })
    pantograph(v, y: H + 0.32, z: secL + 0.6 + 6.0)
    let sd = Drape(v, axis: 0), fd = Drape(v, axis: 2)
    // Livery skirt and band, doors, windows.
    for (z0, z1) in [(Float(0.05), secL - 0.05), (secL + 0.65, L - 0.05)] {
      sidePatches(v, sd, [rounded([SIMD2(z0, 0.34), SIMD2(z1, 0.34), SIMD2(z1, 0.95), SIMD2(z0, 0.95)], r: 0.1)], p, lift: 0.008, k: 6)
      sideLines(v, sd, [[SIMD2(z0 + 0.1, H - 0.4), SIMD2(z1 - 0.1, H - 0.4)]], width: 0.12, p, lift: 0.01)
    }
    let doors: [Float] = [2.6, 8.4, 13.0, 18.0, 23.6, 28.0]
    for z in doors {
      sidePatches(v, sd, [rounded([SIMD2(z - 0.68, 0.36), SIMD2(z + 0.68, 0.36), SIMD2(z + 0.68, 2.6), SIMD2(z - 0.68, 2.6)], r: 0.06)], black, lift: 0.012)
      sidePatches(v, sd, [rounded([SIMD2(z - 0.62, 0.45), SIMD2(z - 0.03, 0.45), SIMD2(z - 0.03, 2.52), SIMD2(z - 0.62, 2.52)], r: 0.05),
                          rounded([SIMD2(z + 0.03, 0.45), SIMD2(z + 0.62, 0.45), SIMD2(z + 0.62, 2.52), SIMD2(z + 0.03, 2.52)], r: 0.05)], glass, lift: 0.018)
    }
    var spans: [(Float, Float)] = []
    var last: Float = 1.6
    for z in doors + [L - 1.6] {
      let a = last, b = z - (z == L - 1.6 ? 0 : 0.8)
      if b - a > 0.6 && !(a < secL + 0.7 && b > secL - 0.1) { spans.append((a, b)) }
      else if b - a > 0.6 { spans.append((a, secL - 0.25)); spans.append((secL + 0.85, b)) }
      last = z + 0.8
    }
    for (a, b) in spans where b - a > 0.5 {
      sidePatches(v, sd, [rounded([SIMD2(a, 1.15), SIMD2(b, 1.15), SIMD2(b, 2.65), SIMD2(a, 2.65)], r: 0.12)], glass, lift: 0.01)
      let n = max(1, Int((b - a) / 1.6))
      sideLines(v, sd, (1..<max(2, n)).compactMap { i in n > 1 ? [SIMD2(a + (b - a) * Float(i) / Float(n), 1.15), SIMD2(a + (b - a) * Float(i) / Float(n), 2.65)] : nil },
                width: 0.06, body, lift: 0.016)
    }
    // Cab ends: windscreens, signs, lamps.
    for (below, sign) in [(true, Float(1)), (false, Float(-1))] {
      decalPatches(v, fd, [rounded([SIMD2(-1.12, 1.25), SIMD2(1.12, 1.25), SIMD2(1.0, 2.75), SIMD2(-1.0, 2.75)], r: 0.2)], glass, below: below, lift: 0.01, k: 10)
      decalPatches(v, fd, [rounded([SIMD2(-0.7, 2.82), SIMD2(0.7, 2.82), SIMD2(0.7, 3.08), SIMD2(-0.7, 3.08)], r: 0.04)], black, below: below, lift: 0.012)
      decalLines(v, fd, [[SIMD2(-0.6, 2.95), SIMD2(0.4, 2.95)]], width: 0.08, amber, below: below, mirror: false, lift: 0.018)
      decalPatches(v, fd, [rounded([SIMD2(0.72, 0.72), SIMD2(1.05, 0.72), SIMD2(1.05, 0.9), SIMD2(0.72, 0.9)], r: 0.05)], below ? headlight : taillight,
                   below: below, mirror: true, lift: 0.014)
      decalPatches(v, fd, [rounded([SIMD2(-1.2, 0.4), SIMD2(1.2, 0.4), SIMD2(1.2, 0.68), SIMD2(-1.2, 0.68)], r: 0.06)], p, below: below, lift: 0.01)
      _ = sign
    }
    for z in [3.2, 12.0, secL + 3.6, L - 3.2] as [Float] { bogie(v, z: z, wheel: 0.33, base: 1.8) }
  }
}

// High-speed train (TGV/ICE class): 22 m power car with a long sculpted
// nose and wraparound cab glass, followed by a 26 m trailer car; livery
// stripes, flush window band, plug doors, roof fairings, pantograph,
// skirted bogies and a gangway bellows.
func highSpeedTrain(livery: UInt32) -> SCNNode {
  let L: Float = 49.0, W: Float = 2.9, H: Float = 3.85
  let p = paint(livery)
  let body = material("white", 0xF4F5F7, metal: 0.2, rough: 0.3)
  return roadVehicle(length: L) { v in
    // Power car: nose keys (top, half width, bottom) along z.
    let nTop = curve([(0, 0.95), (0.6, 1.25), (2.0, 1.75), (4.5, 2.6), (6.6, 3.45), (8.0, H), (22.0, H)])
    let nHw = curve([(0, 0.22), (0.5, 0.6), (1.5, 0.95), (3.5, 1.3), (6.0, W / 2 - 0.02), (7.5, W / 2), (22.0, W / 2)])
    let nBot = curve([(0, 0.62), (0.8, 0.45), (2.0, 0.38), (22, 0.38)])
    shell(v, samples(0, 22.0, step: 0.15, dense: [(0, 9, 0.05)]), capStart: body, capEnd: body, { z in
      let w = nHw(z), t = nTop(z), b = nBot(z)
      return boxHalf(w, b, t, rb: min(0.35, w * 0.5), rt: min(0.6, w * 0.6, (t - b) * 0.45), lean: 0.12 * min(1, z / 6), bow: 0.02, sides: 8, arc: 6)
    }, skin: { f in
      let z = f.p.z + L / 2
      if z > 3.6 && z < 6.4 && f.p.y > 2.15 && f.n.y > 0.25 { return glass }
      return f.n.y < -0.75 ? bellows : body
    })
    // Trailer car.
    let t0: Float = 22.9
    shell(v, samples(t0, L, step: 0.25, dense: [(t0, t0 + 0.6, 0.05), (L - 0.6, L, 0.05)]), capStart: body, capEnd: body, { z in
      let f = min(1, (z - t0) / 0.5, (L - z) / 0.5)
      return boxHalf(W / 2 - 0.05 * (1 - f), 0.38, H - 0.05 * (1 - f), rb: 0.3, rt: 0.55, lean: 0.12, bow: 0.02, sides: 8, arc: 6)
    }, skin: { f in f.n.y < -0.75 ? bellows : body })
    shell(v, samples(21.95, t0 + 0.05, step: 0.1), { z in
      boxHalf(W / 2 - 0.2 + 0.03 * sin((z - 22) * 30), 0.6, H - 0.2, rb: 0.2, rt: 0.4, sides: 6, arc: 4)
    }, skin: { _ in bellows })
    // Roof fairings and pantograph.
    shell(v, samples(9.0, 20.0, step: 0.3, dense: [(9, 10, 0.08)]), capStart: roofGrey, capEnd: roofGrey, { z in
      let f = min(1, (z - 9.0) / 1.0, (20 - z) / 0.6)
      return boxHalf(1.0, H - 0.05, H + 0.25 * f * f * (3 - 2 * f) + 0.01, rb: 0.02, rt: 0.12, lean: 0.05, sides: 3, arc: 3)
    }, skin: { _ in roofGrey })
    pantograph(v, y: H + 0.25, z: 17.5)
    let sd = Drape(v, axis: 0), up = Drape(v, axis: 1), fd = Drape(v, axis: 2)
    // Livery: a stripe sweeping up the nose and along both cars, and a skirt.
    sidePatches(v, sd, [[SIMD2(0.6, 0.85), SIMD2(5.0, 1.05), SIMD2(21.9, 1.05), SIMD2(21.9, 1.45), SIMD2(6.0, 1.45), SIMD2(1.5, 1.2)],
                        [SIMD2(t0 + 0.05, 1.05), SIMD2(L - 0.05, 1.05), SIMD2(L - 0.05, 1.45), SIMD2(t0 + 0.05, 1.45)]], p, lift: 0.01, k: 6)
    sidePatches(v, sd, [[SIMD2(2.0, 0.42), SIMD2(21.9, 0.42), SIMD2(21.9, 0.72), SIMD2(3.0, 0.72)], [SIMD2(t0, 0.42), SIMD2(L, 0.42), SIMD2(L, 0.72), SIMD2(t0, 0.72)]],
                material("skirt", 0x3A3D42, rough: 0.6), lift: 0.008, k: 4)
    decalPatches(v, up, [[SIMD2(-0.2, 0.3), SIMD2(0.2, 0.3), SIMD2(0.5, 3.6), SIMD2(-0.5, 3.6)]], p, lift: 0.01, k: 6)
    // Cab side windows, doors, passenger windows.
    sidePatches(v, sd, [rounded([SIMD2(6.4, 2.35), SIMD2(7.5, 2.4), SIMD2(7.5, 3.0), SIMD2(6.6, 2.95)], r: 0.12)], glass, lift: 0.01)
    sideLines(v, sd, [closed(rounded([SIMD2(8.2, 0.75), SIMD2(9.0, 0.75), SIMD2(9.0, 2.95), SIMD2(8.2, 2.95)], r: 0.06))], width: 0.02, black)
    for (a, b) in [(t0 + 2.6, L - 2.6)] as [(Float, Float)] {
      sidePatches(v, sd, [rounded([SIMD2(a, 2.0), SIMD2(b, 2.0), SIMD2(b, 2.85), SIMD2(a, 2.85)], r: 0.2)], glass, lift: 0.01)
      let n = 11
      sideLines(v, sd, (1..<n).map { i in let z = a + (b - a) * Float(i) / Float(n); return [SIMD2(z, 2.0), SIMD2(z, 2.85)] }, width: 0.12, body, lift: 0.016)
      for z in [t0 + 1.2, L - 1.2] {
        sidePatches(v, sd, [rounded([SIMD2(z - 0.45, 0.8), SIMD2(z + 0.45, 0.8), SIMD2(z + 0.45, 2.95), SIMD2(z - 0.45, 2.95)], r: 0.08)], black, lift: 0.012)
        sidePatches(v, sd, [rounded([SIMD2(z - 0.2, 2.1), SIMD2(z + 0.2, 2.1), SIMD2(z + 0.2, 2.75), SIMD2(z - 0.2, 2.75)], r: 0.06)], glass, lift: 0.018)
      }
    }
    // Nose lamps.
    decalPatches(v, fd, [rounded([SIMD2(0.32, 1.05), SIMD2(0.7, 1.15), SIMD2(0.68, 1.3), SIMD2(0.32, 1.22)], r: 0.04)], headlight, below: true, mirror: true, lift: 0.01)
    decalPatches(v, fd, [rounded([SIMD2(-0.9, 2.2), SIMD2(0.9, 2.2), SIMD2(0.9, 2.95), SIMD2(-0.9, 2.95)], r: 0.08)], glass, below: false, lift: 0.01)
    for z in [5.0, 18.5, t0 + 3.0, L - 3.0] as [Float] { bogie(v, z: z, wheel: 0.46, base: 2.8) }
  }
}


// MARK: More boats

let hullWhite = material("white", 0xF4F5F7, metal: 0.15, rough: 0.3)
let deckMat = material("deck-mat", 0x2A2C2E, rough: 0.85)
let seatGrey = material("seat", 0x3B3E42, rough: 0.7)
let teak = material("teak", 0xB58556, rough: 0.6)
let antifoul = material("antifouling", 0x2B3138, rough: 0.7)
let tint = material("glass", 0x16202B, metal: 0.7, rough: 0.06)

/// Smoothstep from 0 at a to 1 at b.
func ramp(_ x: Float, _ a: Float, _ b: Float) -> Float {
  let t = max(0, min(1, (x - a) / (b - a)))
  return t * t * (3 - 2 * t)
}

// Personal watercraft (three-seat runabout class): 3.35 m, 1.24 m beam.
// 22-degree deep-V hull with chines and a rub rail, a bow hood rising to
// the steering pod, footwells either side of a stepped seat, a boarding
// platform, the jet pump nozzle and sponsons at the stern. White hull,
// painted deck.
func jetSki(body: UInt32) -> SCNNode {
  let L: Float = 3.35
  let p = paint(body)
  return roadVehicle(length: L) { v in
    let keel = curve([(0, 0.44), (0.3, 0.2), (0.8, 0.06), (1.4, 0.0), (L, 0.0)])
    let hw = curve([(0, 0.03), (0.15, 0.24), (0.5, 0.47), (1.1, 0.6), (2.4, 0.62), (3.0, 0.6), (L, 0.56)])
    let gy = curve([(0, 0.63), (0.4, 0.62), (1.0, 0.58), (L, 0.55)])
    let hood = curve([(0, 0.66), (0.3, 0.84), (0.8, 0.98), (1.15, 1.03), (1.3, 0.95), (1.45, 0.8)])
    func deck(_ z: Float) -> [SIMD2<Float>] {
      let w = hw(z), g = gy(z), t = hood(min(z, 1.45))
      let a: [SIMD2<Float>] = [SIMD2(w * 0.93, g + 0.07), SIMD2(w * 0.85, t - 0.14), SIMD2(w * 0.65, t - 0.05), SIMD2(w * 0.35, t - 0.01), SIMD2(0, t)]
      let b: [SIMD2<Float>] = [SIMD2(w * 0.93, g + 0.07), SIMD2(w * 0.84, g - 0.05), SIMD2(0.31, g - 0.05), SIMD2(0.27, 0.74), SIMD2(0, 0.75)]
      let c: [SIMD2<Float>] = [SIMD2(w * 0.93, g + 0.05), SIMD2(w * 0.85, g - 0.02), SIMD2(0.4, g - 0.03), SIMD2(0.2, g - 0.03), SIMD2(0, g - 0.03)]
      let f1 = ramp(z, 1.2, 1.45), f2 = ramp(z, 2.7, 2.9)
      return (0..<5).map { i in a[i] + (b[i] - a[i]) * f1 + (c[i] - b[i]) * f2 }
    }
    let zs = samples(0, L, step: 0.03)
    shell(v, zs, sharp: [4, 8, 9, 10], capStart: hullWhite, capEnd: hullWhite, { z in
      let w = hw(z), k = keel(z), g = gy(z)
      let chine = SIMD2<Float>(w * 0.8, k + w * 0.8 * 0.42)
      var half = resample([SIMD2(0, k), chine], 5)
      half += resample([chine, SIMD2(w, g)], 5).dropFirst()
      return half + deck(z)
    }, skin: { f in
      let z = f.p.z + L / 2
      if f.p.y < 0.55 && f.n.y < 0.5 { return hullWhite }
      if f.n.y > 0.8 && f.p.y < 0.6 && (z > 2.85 || abs(f.p.x) > 0.3) { return deckMat }
      return p
    })
    // Seat, pod, bars, visor, mirrors.
    motoBody(v, [(1.32, 0.15, 0.73, 0.9), (1.5, 0.22, 0.73, 0.96), (2.05, 0.22, 0.73, 0.95), (2.25, 0.22, 0.73, 1.0), (2.68, 0.2, 0.73, 0.98),
                 (2.78, 0.1, 0.73, 0.92)], rb: 0.3, rt: 0.5, cap: seatGrey) { f in f.n.y > 0.7 ? black : seatGrey }
    motoBody(v, [(1.05, 0.12, 0.96, 1.05), (1.2, 0.15, 0.98, 1.13), (1.32, 0.1, 0.96, 1.08)], rb: 0.4, rt: 0.5, cap: p) { _ in p }
    put(v, BoxMesh(width: 0.22, height: 0.12, length: 0.01), tint, 0, 1.16, 1.08, rx: -0.6)
    tube(v, V3(-0.38, 1.12, 1.24), V3(0.38, 1.12, 1.24), 0.016, black, sides: 8)
    for side in [-1, 1] as [Float] {
      put(v, CylinderMesh(radius: 0.022, height: 0.12, sides: 10), rubber, side * 0.36, 1.12, 1.24, rz: .pi / 2)
      tube(v, V3(side * 0.28, 0.98, 0.95), V3(side * 0.34, 1.06, 0.95), 0.01, black, sides: 4)
      box(v, 0.1, 0.05, 0.02, black, side * 0.36, 1.08, 0.95)
    }
    let side = Drape(v, axis: 0), up = Drape(v, axis: 1)
    // Graphics, rub rail, intake grate, platform grip.
    sideLines(v, side, [[SIMD2(0.12, 0.6), SIMD2(L - 0.02, 0.53)]], width: 0.05, black, lift: 0.012)
    sidePatches(v, side, [[SIMD2(0.35, 0.38), SIMD2(1.3, 0.5), SIMD2(2.2, 0.5), SIMD2(1.2, 0.42)], [SIMD2(0.7, 0.28), SIMD2(1.6, 0.42), SIMD2(1.8, 0.42), SIMD2(1.0, 0.3)]],
                p, lift: 0.01, k: 5)
    decalPatches(v, up, [rounded([SIMD2(-0.35, 2.1), SIMD2(0.35, 2.1), SIMD2(0.35, 2.5), SIMD2(-0.35, 2.5)], r: 0.08)], deckMat, below: true, lift: 0.01)
    // Jet nozzle, ride plate, sponsons, tow eye.
    put(v, LatheMesh([SIMD2(0, 0.12), SIMD2(0.22, 0.1), SIMD2(0.26, 0.001)], sides: 18), engineDark, 0, 0.2, L - 0.05, rx: .pi / 2)
    box(v, 0.5, 0.02, 0.4, alu, 0, 0.02, L - 0.2)
    for s in [-1, 1] as [Float] {
      box(v, 0.02, 0.1, 0.35, black, s * 0.57, 0.18, L - 0.4, rz: s * 0.5)
    }
    put(v, TorusMesh(ringRadius: 0.04, pipeRadius: 0.01), chrome, 0, 0.58, L - 0.02, rx: .pi / 2)
  }
}

// Motor superyacht (35 m class): 35 m, 7.6 m beam. Sharp raked bow,
// rising sheer, dark hull over a white boot stripe and antifouling, three
// white decks with swept dark window bands and overhangs, wraparound
// bridge glass, sun deck with a hardtop and radar arch, mast with radomes,
// teak decks, stainless rails, a tender, hull portholes, swim platform.
func yacht(hull: UInt32) -> SCNNode {
  let L: Float = 35
  let p = paint(hull)
  let superWhite = material("white", 0xF6F6F4, metal: 0.15, rough: 0.3)
  return roadVehicle(length: L) { v in
    let keel = curve([(0, 1.9), (1.5, 0.9), (4, 0.25), (8, 0.0), (L, 0.15)])
    let hw = curve([(0, 0.05), (1.0, 1.1), (3.5, 2.6), (8, 3.55), (14, 3.8), (L - 2, 3.75), (L, 3.6)])
    let sheer = curve([(0, 4.6), (4, 4.25), (10, 3.95), (20, 3.7), (L, 3.6)])
    let zs = samples(0, L, step: 0.3, dense: [(0, 4, 0.1), (L - 0.6, L, 0.05)])
    shell(v, zs, sharp: [5, 10], capStart: p, capEnd: p, { z in
      let w = hw(z), k = keel(z), s = sheer(z)
      let chine = SIMD2<Float>(w * 0.72, k + w * 0.72 * 0.3 + 0.3)
      var half = resample([SIMD2(0, k), chine], 6)
      half += resample([chine, SIMD2(w * 0.98, (chine.y + s) / 2), SIMD2(w, s)], 6).dropFirst()
      half += [SIMD2(w * 0.97, s + 0.02), SIMD2(w * 0.6, s + 0.05), SIMD2(0, s + 0.06)]
      return half
    }, skin: { f in
      if f.n.y > 0.7 { return teak }
      if f.p.y < 0.7 { return antifoul }
      return p
    })
    // Decks: main deckhouse, upper deck, bridge, sun deck.
    struct Deck { var z0: Float; var z1: Float; var y0: Float; var h: Float; var hw: Float; var rake: Float }
    let decks = [Deck(z0: 9.5, z1: 30.0, y0: 3.75, h: 2.4, hw: 3.35, rake: 3.0), Deck(z0: 12.5, z1: 28.5, y0: 6.15, h: 2.3, hw: 3.1, rake: 2.6),
                 Deck(z0: 15.0, z1: 24.5, y0: 8.45, h: 1.9, hw: 2.6, rake: 2.2)]
    for (i, d) in decks.enumerated() {
      let front = curve([(d.z0, d.y0 + 0.4), (d.z0 + d.rake * 0.5, d.y0 + d.h * 0.7), (d.z0 + d.rake, d.y0 + d.h), (d.z1, d.y0 + d.h)])
      let width = curve([(d.z0, d.hw * 0.35), (d.z0 + d.rake, d.hw * 0.86), (d.z0 + d.rake * 2.2, d.hw), (d.z1, d.hw)])
      shell(v, samples(d.z0, d.z1, step: 0.2, dense: [(d.z0, d.z0 + d.rake + 0.5, 0.06)]), capStart: superWhite, capEnd: superWhite, { z in
        boxHalf(width(z), d.y0, max(d.y0 + 0.3, front(z)), rb: 0.05, rt: 0.25, lean: 0.25, bow: 0.02, sides: 6, arc: 4)
      }, skin: { f in f.n.y > 0.9 && i < 2 && f.p.z + L / 2 > d.z1 - 4 ? teak : superWhite })
      // Overhanging deck edge above each level.
      shell(v, samples(d.z0 + d.rake * 0.6, d.z1 + 1.2, step: 0.3), capStart: superWhite, capEnd: superWhite, { z in
        boxHalf(width(min(z, d.z1)) + 0.25, d.y0 + d.h - 0.12, d.y0 + d.h + 0.05, rb: 0.03, rt: 0.06, sides: 2, arc: 2)
      }, skin: { _ in superWhite })
    }
    // Hardtop on posts over the sun deck, radar arch and mast with domes.
    shell(v, samples(17.5, 24.0, step: 0.3), capStart: superWhite, capEnd: superWhite, { z in
      let f = ramp(z, 17.5, 18.8)
      return boxHalf(2.4 * (0.6 + 0.4 * f), 12.6, 12.75 + 0.08 * f, rb: 0.03, rt: 0.06, sides: 2, arc: 3)
    }, skin: { _ in superWhite })
    for x in [-2.0, 2.0] as [Float] { for z in [19.0, 23.4] as [Float] { tube(v, V3(x, 10.35, z), V3(x * 0.95, 12.62, z), 0.08, superWhite, sides: 10) } }
    tube(v, V3(0, 12.75, 21.0), V3(0, 14.6, 21.6), 0.1, superWhite, sides: 10)
    for (x, r) in [(-0.8, 0.45), (0.8, 0.35)] as [(Float, Float)] {
      put(v, LatheMesh((0...8).map { i in let a = Float(i) / 8 * .pi; return SIMD2(-cos(a) * r, sin(a) * r + 0.001) }, sides: 18), superWhite, x, 14.0, 21.4)
    }
    box(v, 2.2, 0.08, 0.12, superWhite, 0, 13.9, 21.4)
    rod(v, V3(0, 14.6, 21.6), V3(0, 16.5, 21.9), 0.025, chrome)
    let sd = Drape(v, axis: 0), up = Drape(v, axis: 1), fd = Drape(v, axis: 2)
    // Hull: boot stripe, portholes, anchor pocket, sheer line.
    sideLines(v, sd, [[SIMD2(1.6, 0.85), SIMD2(L - 0.1, 0.85)]], width: 0.18, superWhite, lift: 0.02)
    sidePatches(v, sd, (0..<7).map { i in ring2(13 + Float(i) * 1.8, 2.2, 0.2, 14) } + (0..<3).map { i in ring2(5.5 + Float(i) * 1.6, 2.6, 0.18, 14) },
                tint, lift: 0.02)
    sidePatches(v, sd, [rounded([SIMD2(1.9, 3.3), SIMD2(2.9, 3.3), SIMD2(2.9, 3.9), SIMD2(1.9, 3.9)], r: 0.2)], black, lift: 0.02)
    sideLines(v, sd, [[SIMD2(0.6, 4.4), SIMD2(10, 3.92), SIMD2(L - 0.1, 3.56)]], width: 0.12, chrome, lift: 0.02)
    // Window bands, swept at the front.
    for (i, d) in decks.enumerated() {
      let y0 = d.y0 + d.h * 0.28, y1 = d.y0 + d.h * 0.82
      let zA = d.z0 + d.rake * 0.7
      let band = [SIMD2(zA, y0 + 0.2), SIMD2(d.z1 - 1.0, y0), SIMD2(d.z1 - 0.4, y1 - 0.15), SIMD2(zA + d.rake * 0.6, y1)]
      sidePatches(v, sd, [rounded(band, r: 0.4)], tint, lift: 0.02, k: 8)
      if i == 0 { sidePatches(v, sd, [rounded([SIMD2(d.z1 - 7, y0 - 0.2), SIMD2(d.z1 - 4.5, y0 - 0.2), SIMD2(d.z1 - 4.5, y1 + 0.1), SIMD2(d.z1 - 7, y1 + 0.1)], r: 0.2)],
                              black, lift: 0.03) }
      decalPatches(v, fd, [rounded([SIMD2(-d.hw * 0.8, d.y0 + d.h * 0.42), SIMD2(d.hw * 0.8, d.y0 + d.h * 0.42), SIMD2(d.hw * 0.7, d.y0 + d.h * 0.9),
                                    SIMD2(-d.hw * 0.7, d.y0 + d.h * 0.9)], r: 0.3)], tint, below: true, lift: 0.02, k: 8)
    }
    // Aft deck teak and sun deck pads.
    decalPatches(v, up, [rounded([SIMD2(-2.5, 20.2), SIMD2(2.5, 20.2), SIMD2(2.5, 23.8), SIMD2(-2.5, 23.8)], r: 0.4)], material("cushion", 0xE9E4DA, rough: 0.8),
                 lift: 0.12)
    decalPatches(v, up, [rounded([SIMD2(-2.2, 3.5), SIMD2(2.2, 3.5), SIMD2(2.8, 8.5), SIMD2(-2.8, 8.5)], r: 0.6)], material("cushion", 0xE9E4DA, rough: 0.8),
                 lift: 0.1)
    // Rails: stanchions and top rail along the main deck edge and the upper deck.
    for side in [-1, 1] as [Float] {
      var pts: [V3] = []
      var z: Float = 2.0
      while z < L - 0.4 {
        let x = side * (hw(z) - 0.15), y = sheer(z) + 0.05
        pts.append(V3(x, y, z)); z += 1.5
      }
      for q in pts { rod(v, q, q + V3(0, 0.95, 0), 0.025, chrome) }
      for k in 0..<(pts.count - 1) { rod(v, pts[k] + V3(0, 0.95, 0), pts[k + 1] + V3(0, 0.95, 0), 0.03, chrome) }
    }
    // Tender on the foredeck of the upper level, swim platform, ladder.
    let tender = holder(v, V3(0, 6.2, 10.4))
    motoBody(tender, [(-2.0, 0.15, 0.2, 0.55), (-1.4, 0.72, 0.0, 0.62), (1.2, 0.82, 0.0, 0.6), (2.0, 0.7, 0.05, 0.58)], rb: 0.5, rt: 0.6,
             cap: material("tube-grey", 0x5C6167, rough: 0.6)) { f in f.n.y > 0.6 ? superWhite : material("tube-grey", 0x5C6167, rough: 0.6) }
    box(v, 6.6, 0.25, 2.0, teak, 0, 1.2, L + 0.9)
    for x in [-0.4, 0.4] as [Float] { rod(v, V3(x, 1.3, L + 0.1), V3(x, 3.5, L - 0.2), 0.03, chrome) }
  }
}

// MARK: More aircraft


let navWhite = material("nav-white", 0xFFFFFF, rough: 0.3, emit: true)
let bladeBlack = material("blade", 0x26282B, rough: 0.5)
let bladeTip = material("blade-tip", 0xF2C318, rough: 0.5)
let wingGrey = material("white", 0xE3E6EA, metal: 0.25, rough: 0.4)

// Light single-engine helicopter (Bell 407 class): 10.6 m fuselage,
// 10.7 m four-blade rotor. Rounded cabin with a big bubble windscreen and
// chin windows, doors with windows, engine cowling with exhaust stacks,
// tapering tail boom, horizontal stabiliser with endplates, swept fin,
// two-blade tail rotor on the left, skids on curved cross tubes.
func helicopter(livery: UInt32) -> SCNNode {
  let L: Float = 10.6
  let p = paint(livery)
  return fighter(length: L) { h in
    let c = 11
    func skin(_ f: Facet) -> SCNMaterial {
      let z = f.p.z + L / 2
      if z < 1.5 && f.p.y > 1.22 - z * 0.1 && abs(f.p.x) > 0.035 { return glass }
      if z < 0.95 && f.p.y > 0.72 && f.p.y < 1.08 && abs(f.p.x) > 0.12 && f.n.z < -0.2 { return glass }
      if f.n.y < -0.7 { return hullWhite }
      return p
    }
    jetBody(h, [
      Ring(z: 0, half: noseTip(1.25, c)),
      Ring(z: 0.25, half: ovalHalf(0.46, 0.76, 1.66, n: 2.2, count: c, widest: 0.45)),
      Ring(z: 0.8, half: ovalHalf(0.72, 0.56, 2.04, n: 2.4, count: c, widest: 0.42)),
      Ring(z: 1.6, half: ovalHalf(0.8, 0.5, 2.25, n: 2.7, count: c, widest: 0.42)),
      Ring(z: 2.6, half: ovalHalf(0.81, 0.5, 2.3, n: 2.9, count: c, widest: 0.42)),
      Ring(z: 3.5, half: ovalHalf(0.74, 0.62, 2.42, n: 2.7, count: c, widest: 0.45)),
      Ring(z: 4.4, half: ovalHalf(0.5, 0.98, 2.4, n: 2.4, count: c, widest: 0.5)),
      Ring(z: 5.3, half: ovalHalf(0.3, 1.5, 2.2, count: c)),
      Ring(z: 9.6, half: ovalHalf(0.13, 1.88, 2.15, count: c)),
      Ring(z: 9.95, half: ovalHalf(0.08, 1.92, 2.1, count: c)),
    ], step: 0.1, capEnd: p, skin: skin)
    // Engine cowling and exhaust.
    motoBody(h, [(2.0, 0.2, 2.2, 2.4), (2.4, 0.45, 2.22, 2.62), (3.6, 0.48, 2.25, 2.7), (4.5, 0.32, 2.2, 2.5), (5.0, 0.1, 2.15, 2.3)],
             step: 0.05, rb: 0.3, rt: 0.6, cap: p) { _ in p }
    for side in [-1, 1] as [Float] {
      tube(h, V3(side * 0.18, 2.6, 4.2), V3(side * 0.24, 2.85, 4.55), 0.09, engineDark, sides: 12)
    }
    // Rotor: mast, hub, four blades with tip caps.
    tube(h, V3(0, 2.65, 2.25), V3(0, 3.15, 2.25), 0.09, engineDark, sides: 12)
    put(h, CylinderMesh(radius: 0.3, height: 0.14, sides: 16), engineDark, 0, 3.18, 2.25)
    for k in 0..<4 {
      let blade = holder(h, V3(0, 3.2, 2.25), ry: Float(k) * .pi / 2 + 0.4)
      wingSkin(blade, [WS(s: 0.25, le: -0.12, te: 0.12, t: 0.05, y: 0), WS(s: 0.6, le: -0.14, te: 0.14, t: 0.04, y: 0),
                       WS(s: 5.33, le: -0.1, te: 0.12, t: 0.03, y: -0.08)], side: 1, chord: 5, sub: 1) { f in
        f.p.y > -10 && simd_length(SIMD2(f.p.x, f.p.z - (2.25 - L / 2))) > 4.95 ? bladeTip : bladeBlack
      }
    }
    // Horizontal stabiliser with endplates, swept fin, tail rotor.
    for side in [-1, 1] as [Float] {
      wingSkin(h, [WS(s: 0.1, le: 7.6, te: 8.25, t: 0.1, y: 1.98), WS(s: 1.35, le: 7.75, te: 8.25, t: 0.07, y: 1.98)], side: side, chord: 6, sub: 1) { _ in p }
      let ep = finFrame(h, x: 1.35, y: 1.98, cant: 0, side: 1)
      wingSkin(ep, [WS(s: -0.3, le: 7.72, te: 8.25, t: 0.05, y: side * 0.0), WS(s: 0.35, le: 7.85, te: 8.25, t: 0.05, y: 0)], side: side, chord: 4, sub: 1) { _ in p }
    }
    let fin = finFrame(h, x: 0, y: 2.08, cant: 0, side: 1)
    wingSkin(fin, [WS(s: 0, le: 8.85, te: 9.95, t: 0.12, y: 0), WS(s: 1.05, le: 9.6, te: 10.1, t: 0.07, y: 0)], side: 1, chord: 6, sub: 1) { _ in p }
    wingSkin(fin, [WS(s: 0, le: 9.2, te: 9.95, t: 0.1, y: 0), WS(s: 0.5, le: 9.6, te: 9.95, t: 0.06, y: 0)], side: -1, chord: 5, sub: 1) { _ in p }
    tube(h, V3(0, 1.55, 9.75), V3(0, 1.4, 10.25), 0.02, chrome, sides: 6)
    let tr = holder(h, V3(-0.22, 2.55, 9.75), rz: .pi / 2 + 0.3)
    put(tr, CylinderMesh(radius: 0.08, height: 0.12, sides: 12), engineDark, 0, 0, 0, rz: .pi / 2)
    for side in [-1, 1] as [Float] {
      wingSkin(tr, [WS(s: 0.06, le: -0.07, te: 0.07, t: 0.025, y: -0.05), WS(s: 0.85, le: -0.06, te: 0.06, t: 0.015, y: -0.05)], side: side, chord: 4, sub: 1) { _ in bladeBlack }
    }
    // Skids on curved cross tubes, with steps.
    for side in [-1, 1] as [Float] {
      let x = side * 1.12
      tube(h, V3(x, 0.08, 0.6), V3(x, 0.08, 3.9), 0.05, alu, sides: 10)
      tube(h, V3(x, 0.08, 0.6), V3(x, 0.2, 0.3), 0.05, alu, sides: 10)
      tube(h, V3(x, 0.2, 0.3), V3(x, 0.38, 0.22), 0.05, alu, sides: 10)
      for z in [1.25, 3.2] as [Float] {
        tube(h, V3(side * 0.45, 0.55, z), V3(side * 0.85, 0.45, z), 0.05, alu, sides: 10)
        tube(h, V3(side * 0.85, 0.45, z), V3(x, 0.1, z), 0.05, alu, sides: 10)
      }
      box(h, 0.3, 0.03, 0.2, alu, side * 0.85, 0.42, 1.9)
    }
    let sd = Drape(h, axis: 0, skip: ["glass"])
    sidePatches(h, sd, [rounded([SIMD2(1.62, 1.3), SIMD2(2.45, 1.3), SIMD2(2.45, 2.05), SIMD2(1.62, 2.12)], r: 0.12),
                        rounded([SIMD2(2.55, 1.3), SIMD2(3.35, 1.3), SIMD2(3.3, 2.02), SIMD2(2.55, 2.05)], r: 0.12)], glass, lift: 0.01, k: 6)
    sideLines(h, sd, [closed(rounded([SIMD2(1.55, 0.72), SIMD2(2.5, 0.72), SIMD2(2.5, 2.18), SIMD2(1.55, 2.2)], r: 0.1)),
                      closed(rounded([SIMD2(2.5, 0.72), SIMD2(3.42, 0.72), SIMD2(3.38, 2.12), SIMD2(2.5, 2.18)], r: 0.1))], width: 0.015, black)
    sideLines(h, sd, [[SIMD2(0.4, 0.95), SIMD2(4.5, 1.05), SIMD2(9.6, 1.95)]], width: 0.08, hullWhite, lift: 0.016)
    navLights(h, x: 1.4, y: 1.98, z: 8.0)
    box(h, 0.1, 0.06, 0.1, navRed, 0, 2.08, 4.0)
  }
}

// Cessna 172 class four-seat high-wing single: 8.28 m long, 11.0 m span,
// 2.72 m tall. Cowled flat-four with spinner and two-blade prop, raked
// windscreen, door and rear side windows, rear "omni-vision" window,
// strut-braced wing (constant-chord inboard, tapered outboard, 1.7 degrees
// dihedral) with flaps and ailerons, swept fin with a dorsal fillet,
// stabiliser with elevators, spring-steel mains and a nose oleo with
// wheel fairings, nav and beacon lights.
func propPlane(livery: UInt32) -> SCNNode {
  let L: Float = 8.28
  let p = paint(livery)
  return fighter(length: L) { a in
    let c = 13
    func skin(_ f: Facet) -> SCNMaterial {
      let z = f.p.z + L / 2
      if z > 1.55 && z < 2.25 && f.n.z < -0.25 && f.n.y > 0.15 && f.p.y > 1.9 { return glass }
      if z > 3.65 && z < 4.45 && f.n.y > 0.55 && abs(f.p.x) < 0.32 { return glass }
      return hullWhite
    }
    jetBody(a, [
      Ring(z: 0.2, half: ovalHalf(0.32, 1.2, 1.72, n: 2.4, count: c)),
      Ring(z: 0.5, half: ovalHalf(0.47, 1.0, 1.85, n: 2.6, count: c)),
      Ring(z: 1.4, half: ovalHalf(0.53, 0.92, 1.93, n: 3, count: c, widest: 0.45)),
      Ring(z: 1.6, half: ovalHalf(0.55, 0.9, 2.02, n: 3, count: c, widest: 0.42)),
      Ring(z: 2.25, half: ovalHalf(0.56, 0.88, 2.5, n: 3.2, count: c, widest: 0.4)),
      Ring(z: 3.5, half: ovalHalf(0.55, 0.92, 2.5, n: 3.2, count: c, widest: 0.4)),
      Ring(z: 4.3, half: ovalHalf(0.42, 1.08, 2.28, n: 2.8, count: c, widest: 0.42)),
      Ring(z: 5.5, half: ovalHalf(0.27, 1.3, 2.04, n: 2.4, count: c)),
      Ring(z: 7.0, half: ovalHalf(0.13, 1.52, 1.95, n: 2.2, count: c)),
      Ring(z: 8.0, half: ovalHalf(0.05, 1.64, 1.9, count: c)),
    ], step: 0.1, capStart: engineDark, capEnd: hullWhite, skin: skin)
    // Spinner and two-blade prop.
    put(a, LatheMesh((0...8).map { i in let t = Float(i) / 8; return SIMD2(t * 0.32, 0.17 * (1 - pow(1 - t, 0.5) * 0) * sqrt(max(0.0001, t))) }, sides: 20),
        white, 0, 1.46, 0.2, rx: -.pi / 2)
    let prop = holder(a, V3(0, 1.46, 0.08), rz: .pi / 2 + 0.5)
    for side in [-1, 1] as [Float] {
      wingSkin(prop, [WS(s: 0.1, le: -0.08, te: 0.06, t: 0.04, y: 0), WS(s: 0.5, le: -0.09, te: 0.08, t: 0.025, y: 0),
                      WS(s: 0.95, le: -0.05, te: 0.04, t: 0.012, y: 0)], side: side, chord: 4, sub: 2) { f in
        simd_length(SIMD2(f.p.x, f.p.y - 1.46)) > 0.85 ? bladeTip : bladeBlack
      }
    }
    // Wing, struts, tail.
    var wings: [WingSurface] = []
    for side in [-1, 1] as [Float] {
      wings.append(wingSkin(a, [WS(s: 0, le: 1.62, te: 3.28, t: 0.2, y: 2.48), WS(s: 2.6, le: 1.62, te: 3.28, t: 0.19, y: 2.56),
                                WS(s: 5.3, le: 1.98, te: 3.1, t: 0.12, y: 2.64), WS(s: 5.5, le: 2.06, te: 3.04, t: 0.08, y: 2.64)],
                            side: side, chord: 9, sub: 3) { f in
        abs(f.p.x) > 5.0 ? p : wingGrey
      })
      strut(a, V3(side * 0.52, 1.0, 2.35), V3(side * 2.65, 2.42, 2.4), 0.11, 0.03, hullWhite, up: V3(0, 0, 1))
      wingSkin(a, [WS(s: 0.12, le: 6.95, te: 8.0, t: 0.1, y: 1.78), WS(s: 1.72, le: 7.3, te: 7.98, t: 0.06, y: 1.78)], side: side, chord: 6, sub: 2) { f in
        abs(f.p.x) > 1.45 ? p : wingGrey
      }
    }
    let fin = finFrame(a, x: 0, y: 1.9, cant: 0, side: 1)
    let finS = wingSkin(fin, [WS(s: 0, le: 5.5, te: 8.15, t: 0.14, y: 0), WS(s: 0.28, le: 6.7, te: 8.2, t: 0.12, y: 0),
                              WS(s: 1.5, le: 7.65, te: 8.3, t: 0.08, y: 0)], side: 1, chord: 7, sub: 2) { f in f.p.y > 2.9 ? p : hullWhite }
    // Control surface lines.
    for w in wings {
      wingLines(w, [[SIMD2(0.6, w.z(0.6, 0.74)), SIMD2(2.9, w.z(2.9, 0.74)), SIMD2(2.9, w.z(2.9, 1))],
                    [SIMD2(3.0, w.z(3.0, 1)), SIMD2(3.0, w.z(3.0, 0.72)), SIMD2(5.2, w.z(5.2, 0.7)), SIMD2(5.2, w.z(5.2, 1))]], width: 0.02, slat, lower: true)
    }
    wingLines(finS, [[SIMD2(0.1, 7.75), SIMD2(1.45, 7.95)]], width: 0.02, slat, upper: true, lower: true)
    // Gear: spring-steel mains with fairings, nose oleo.
    for side in [-1, 1] as [Float] {
      strut(a, V3(side * 0.42, 0.98, 2.65), V3(side * 1.25, 0.32, 2.75), 0.1, 0.025, hullWhite, up: V3(0, 0, 1))
      put(a, TubeMesh(innerRadius: 0.12, outerRadius: 0.22, height: 0.13, sides: 20), tyre, side * 1.25, 0.22, 2.75, rz: .pi / 2)
      motoBody(a, [(2.3, 0.04, 0.16, 0.3), (2.55, 0.12, 0.06, 0.48), (2.95, 0.12, 0.06, 0.48), (3.35, 0.02, 0.26, 0.36)], x: side * 1.25,
               step: 0.03, rb: 0.6, rt: 0.6, cap: p) { _ in p }
    }
    tube(a, V3(0, 1.0, 0.75), V3(0, 0.22, 0.6), 0.04, chrome, sides: 10)
    put(a, TubeMesh(innerRadius: 0.1, outerRadius: 0.19, height: 0.11, sides: 18), tyre, 0, 0.19, 0.6, rz: .pi / 2)
    motoBody(a, [(0.3, 0.03, 0.14, 0.26), (0.5, 0.1, 0.05, 0.42), (0.78, 0.1, 0.05, 0.42), (0.98, 0.02, 0.22, 0.32)], step: 0.03, rb: 0.6, rt: 0.6,
             cap: p) { _ in p }
    tube(a, V3(0.2, 0.95, 1.3), V3(0.22, 0.82, 1.7), 0.035, engineDark, sides: 8)
    // Windows, livery stripes, cowl intakes, lights.
    let sd = Drape(a, axis: 0), fd = Drape(a, axis: 2)
    sidePatches(a, sd, [rounded([SIMD2(1.75, 1.72), SIMD2(2.78, 1.72), SIMD2(2.78, 2.4), SIMD2(2.0, 2.4)], r: 0.08),
                        rounded([SIMD2(2.88, 1.75), SIMD2(3.75, 1.78), SIMD2(3.62, 2.3), SIMD2(2.88, 2.38)], r: 0.08)], glass, lift: 0.01, k: 6)
    sideLines(a, sd, [closed(rounded([SIMD2(1.68, 0.98), SIMD2(2.84, 0.98), SIMD2(2.84, 2.46), SIMD2(1.9, 2.46)], r: 0.06))], width: 0.012, slat)
    sidePatches(a, sd, [[SIMD2(0.5, 1.42), SIMD2(5.0, 1.42), SIMD2(7.6, 1.66), SIMD2(7.6, 1.74), SIMD2(5.0, 1.56), SIMD2(0.5, 1.56)],
                        [SIMD2(1.4, 1.3), SIMD2(5.2, 1.36), SIMD2(7.6, 1.6), SIMD2(5.2, 1.4), SIMD2(1.4, 1.36)]], p, lift: 0.01, k: 6)
    decalPatches(a, fd, [ring2(0.2, 1.62, 0.07, 12)], black, below: true, mirror: true, lift: 0.01)
    let wl = wings.first { $0.side < 0 }!, wr = wings.first { $0.side > 0 }!
    box(a, 0.06, 0.05, 0.12, navRed, -5.52, wl.at(5.5).y, 2.2)
    box(a, 0.06, 0.05, 0.12, navGreen, 5.52, wr.at(5.5).y, 2.2)
    box(a, 0.06, 0.08, 0.06, navRed, 0, 3.42, 7.95)
    box(a, 0.05, 0.05, 0.08, navWhite, 0, 1.78, 8.3)
  }
}

// MARK: Fighter jets
// Each jet is drawn nose-first along +Z in metres from the nose (a holder
// moves the nose to -L/2), then collapsed into one mesh per material like the
// spacecraft, so it sits on y = 0 with the landing gear up. Fuselages are
// lofted from half cross-sections (bottom centre, round the right side, to
// top centre) mirrored to the left, with chosen keypoints kept as sharp
// chines; wings and tails are lofted airfoils. A skin closure picks each
// quad's material, which is how the camouflage, the RAM edge strips, the
// intake mouths and the exhaust troughs are painted on. Colours are authored
// darker than the real paint because the map's lighting is bright.

/// One quad of a lofted skin, in the jet's frame: centre, outward normal and,
/// on wings and tails, the chordwise position (0 leading edge, 1 trailing
/// edge; -1 elsewhere).
struct Facet { var p: V3; var n: V3; var u: Float }

/// Fritsch-Carlson monotone cubic through (xs, ys), evaluated at x: smooth
/// like a spline, but never overshoots between keys.
func monotoneCubic(_ xs: [Float], _ ys: [Float], _ x: Float) -> Float {
  let n = xs.count
  if n == 1 || x <= xs[0] { return ys[0] }
  if x >= xs[n - 1] { return ys[n - 1] }
  var d = [Float](repeating: 0, count: n - 1)
  for i in 0..<(n - 1) { d[i] = (ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]) }
  var m = [Float](repeating: 0, count: n)
  m[0] = d[0]; m[n - 1] = d[n - 2]
  for i in 1..<(n - 1) { m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2 }
  for i in 0..<(n - 1) {
    if d[i] == 0 { m[i] = 0; m[i + 1] = 0; continue }
    let a = m[i] / d[i], b = m[i + 1] / d[i], s = a * a + b * b
    if s > 9 { let t = 3 / s.squareRoot(); m[i] = t * a * d[i]; m[i + 1] = t * b * d[i] }
  }
  var k = 0
  while k < n - 2 && x > xs[k + 1] { k += 1 }
  let h = xs[k + 1] - xs[k], t = (x - xs[k]) / h, t2 = t * t, t3 = t2 * t
  return (2 * t3 - 3 * t2 + 1) * ys[k] + (t3 - 2 * t2 + t) * h * m[k]
    + (-2 * t3 + 3 * t2) * ys[k + 1] + (t3 - t2) * h * m[k + 1]
}

/// A skin through `rows` of points (each a closed loop of the same count).
/// Normals are smooth except across points flagged in `crease`; the skin
/// closure picks each quad's material. Ends get flat caps when given one.
func gridSkin(_ parent: SCNNode, rows: [[V3]], crease: [Bool], us: [Float]? = nil, inward: Bool = false,
              capStart: SCNMaterial? = nil, capEnd: SCNMaterial? = nil, skin: (Facet) -> SCNMaterial) {
  let R = rows.count, K = rows[0].count
  guard R >= 2, K >= 3 else { return }
  var F = [[V3]](repeating: [V3](repeating: V3(0, 0, 0), count: K), count: R - 1)
  var score: Float = 0
  for r in 0..<(R - 1) {
    let c0 = rows[r].reduce(V3(0, 0, 0), +) / Float(K)
    for s in 0..<K {
      let a = rows[r][s], b = rows[r][(s + 1) % K], c = rows[r + 1][(s + 1) % K], d = rows[r + 1][s]
      let n = simd_cross(c - a, d - b) * 0.5
      F[r][s] = n
      score += simd_dot(n, (a + b + c + d) / 4 - c0)
    }
  }
  let flip = (score < 0) != inward
  if flip { for r in 0..<(R - 1) { for s in 0..<K { F[r][s] = -F[r][s] } } }
  func vertexNormal(_ r: Int, _ i: Int, _ s: Int) -> V3 {
    var n = V3(0, 0, 0)
    for st in crease[i] ? [s] : [(i + K - 1) % K, i] {
      for rr in [r - 1, r] where rr >= 0 && rr < R - 1 { n += F[rr][st] }
    }
    let l = simd_length(n)
    return l > 1e-12 ? n / l : V3(0, 1, 0)
  }
  final class Bucket {
    let m: SCNMaterial; let mesh = Mesh(); var map: [Int: UInt32] = [:]
    init(_ m: SCNMaterial) { self.m = m }
  }
  var buckets: [ObjectIdentifier: Bucket] = [:], order: [ObjectIdentifier] = []
  func bucket(_ m: SCNMaterial) -> Bucket {
    let k = ObjectIdentifier(m)
    if let b = buckets[k] { return b }
    let b = Bucket(m); buckets[k] = b; order.append(k); return b
  }
  func vid(_ b: Bucket, _ r: Int, _ i: Int, _ s: Int) -> UInt32 {
    let key = ((r * K + i) << 1) | (crease[i] && s != i ? 1 : 0)
    if let v = b.map[key] { return v }
    let v = UInt32(b.mesh.positions.count)
    b.mesh.positions.append(rows[r][i]); b.mesh.normals.append(vertexNormal(r, i, s))
    b.map[key] = v
    return v
  }
  for r in 0..<(R - 1) {
    for s in 0..<K {
      let s1 = (s + 1) % K
      let l = simd_length(F[r][s])
      if l < 1e-12 { continue }
      let centre = (rows[r][s] + rows[r][s1] + rows[r + 1][s1] + rows[r + 1][s]) / 4
      let u = us.map { ($0[s] + $0[s1]) / 2 } ?? -1
      let m = skin(Facet(p: parent.simdConvertPosition(centre, to: nil),
                         n: simd_normalize(parent.simdConvertVector(F[r][s] / l, to: nil)), u: u))
      let b = bucket(m)
      let a = vid(b, r, s, s), bb = vid(b, r, s1, s), c = vid(b, r + 1, s1, s), d = vid(b, r + 1, s, s)
      b.mesh.indices += flip ? [a, c, bb, a, d, c] : [a, bb, c, a, c, d]
    }
  }
  for (r, cap, other) in [(0, capStart, 1), (R - 1, capEnd, R - 2)] {
    guard let cap else { continue }
    let ring = rows[r]
    let c = ring.reduce(V3(0, 0, 0), +) / Float(K)
    var n = V3(0, 0, 0)
    for i in 0..<K { n += simd_cross(ring[i] - c, ring[(i + 1) % K] - c) }
    if simd_length(n) < 1e-12 { continue }
    n = simd_normalize(n)
    if simd_dot(n, c - rows[other].reduce(V3(0, 0, 0), +) / Float(K)) < 0 { n = -n }
    if inward { n = -n }
    let b = bucket(cap)
    let base = UInt32(b.mesh.positions.count)
    b.mesh.positions.append(c); b.mesh.normals.append(n)
    for q in ring { b.mesh.positions.append(q); b.mesh.normals.append(n) }
    for i in 0..<K {
      let i0 = base + 1 + UInt32(i), i1 = base + 1 + UInt32((i + 1) % K)
      let along = simd_dot(simd_cross(ring[i] - c, ring[(i + 1) % K] - c), n) >= 0
      b.mesh.indices += along ? [base, i0, i1] : [base, i1, i0]
    }
  }
  for k in order { let b = buckets[k]!; parent.addChildNode(SCNNode(geometry: b.mesh.geometry(b.m))) }
}

/// A key cross-section: the right half from bottom centre (x = 0) round the
/// side to top centre (x = 0), at distance `z` from the nose.
struct Ring { var z: Float; var half: [SIMD2<Float>] }

/// A body lofted through key half-sections (interpolated smoothly along Z,
/// sampled every `step`) and mirrored about x = `x`. Half-section keypoints
/// listed in `sharp` stay creased (chines).
func jetBody(_ p: SCNNode, _ keys: [Ring], sharp: Set<Int> = [], step: Float = 0.25, x: Float = 0, sub: Int = 1,
             capStart: SCNMaterial? = nil, capEnd: SCNMaterial? = nil, skin: (Facet) -> SCNMaterial) {
  if sub > 1 {
    // Split every segment of the half-sections into `sub` pieces.
    let split = keys.map { key in
      Ring(z: key.z, half: (0..<((key.half.count - 1) * sub + 1)).map { j in
        let i = j / sub, f = Float(j % sub) / Float(sub)
        return i + 1 < key.half.count ? key.half[i] + (key.half[i + 1] - key.half[i]) * f : key.half[i]
      })
    }
    jetBody(p, split, sharp: Set(sharp.map { $0 * sub }), step: step, x: x, capStart: capStart, capEnd: capEnd, skin: skin)
    return
  }
  let k = keys[0].half.count
  let zs = keys.map { $0.z }
  var zList = zs
  var z = zs[0] + step
  while z < zs[zs.count - 1] {
    if !zs.contains(where: { abs($0 - z) < step * 0.35 }) { zList.append(z) }
    z += step
  }
  zList.sort()
  let xs = (0..<k).map { i in keys.map { $0.half[i].x } }, ys = (0..<k).map { i in keys.map { $0.half[i].y } }
  var rows: [[V3]] = []
  for zz in zList {
    let half = (0..<k).map { SIMD2(monotoneCubic(zs, xs[$0], zz), monotoneCubic(zs, ys[$0], zz)) }
    var ring = half.map { V3(x + $0.x, $0.y, zz) }
    for i in stride(from: k - 2, through: 1, by: -1) { ring.append(V3(x - half[i].x, half[i].y, zz)) }
    rows.append(ring)
  }
  var crease = (0..<k).map { sharp.contains($0) }
  for i in stride(from: k - 2, through: 1, by: -1) { crease.append(sharp.contains(i)) }
  gridSkin(p, rows: rows, crease: crease, capStart: capStart, capEnd: capEnd, skin: skin)
}

/// A superellipse half-section `a` wide either side, from `bottom` to `top`,
/// widest at the fraction `widest` of the height.
func ovalHalf(_ a: Float, _ bottom: Float, _ top: Float, n: Float = 2, count: Int = 9, widest: Float = 0.5) -> [SIMD2<Float>] {
  let yc = bottom + (top - bottom) * widest
  return (0..<count).map { i in
    if i == 0 { return SIMD2(0, bottom) }
    if i == count - 1 { return SIMD2(0, top) }
    let t = -Float.pi / 2 + Float.pi * Float(i) / Float(count - 1)
    let s = sin(t)
    let y = s < 0 ? yc - (yc - bottom) * pow(-s, 2 / n) : yc + (top - yc) * pow(s, 2 / n)
    return SIMD2(a * pow(cos(t), 2 / n), y)
  }
}

/// A tiny section to close a pointed nose at height y.
func noseTip(_ y: Float, _ k: Int) -> [SIMD2<Float>] {
  (0..<k).map { i in
    let t = Float(i) / Float(k - 1)
    return SIMD2(i == 0 || i == k - 1 ? 0 : 0.012 * sin(t * .pi), y - 0.012 + 0.024 * t)
  }
}

/// A spanwise wing or tail station: `s` out from the root line, leading and
/// trailing edge positions along Z, thickness `t` and height `y`.
struct WS { var s: Float; var le: Float; var te: Float; var t: Float; var y: Float }

/// NACA 00xx half-thickness for unit thickness at chord fraction u.
func nacaHalf(_ u: Float) -> Float {
  let u = max(0, min(1, u))
  return 5 * (0.2969 * u.squareRoot() - 0.1260 * u - 0.3516 * u * u + 0.2843 * u * u * u - 0.1036 * u * u * u * u)
}

/// A lofted lifting surface, kept so markings can be drawn on its skin.
struct WingSurface {
  let frame: SCNNode
  let st: [WS]
  let side: Float
  /// The station at span `s` (linear between the defining stations).
  func at(_ s: Float) -> WS {
    if s <= st[0].s { return st[0] }
    for i in 1..<st.count where s <= st[i].s {
      let a = st[i - 1], b = st[i], f = (s - a.s) / max(1e-6, b.s - a.s)
      return WS(s: s, le: a.le + (b.le - a.le) * f, te: a.te + (b.te - a.te) * f, t: a.t + (b.t - a.t) * f, y: a.y + (b.y - a.y) * f)
    }
    return st[st.count - 1]
  }
  /// Z of chord fraction u at span s.
  func z(_ s: Float, _ u: Float) -> Float { let w = at(s); return w.le + u * (w.te - w.le) }
  /// A point on the upper (or lower) skin at span s and position z along the
  /// chord, lifted off the skin, in the frame's coordinates.
  func point(_ s: Float, _ z: Float, upper: Bool, lift: Float) -> V3 {
    let w = at(s)
    let u = (z - w.le) / max(1e-6, w.te - w.le)
    let h = nacaHalf(u) * w.t + lift
    return V3(side * s, w.y + (upper ? h : -h), z)
  }
}

/// A lifting surface lofted through spanwise stations, spanning towards
/// `side` (+1 right, -1 left) along X in `p`'s frame, NACA 00xx sections.
@discardableResult
func wingSkin(_ p: SCNNode, _ st: [WS], side: Float, chord n: Int = 7, sub: Int = 3,
              skin: (Facet) -> SCNMaterial) -> WingSurface {
  let us = (0...n).map { (1 - cos(Float.pi * Float($0) / Float(n))) / 2 }
  var stations: [WS] = []
  for i in 0..<(st.count - 1) {
    let a = st[i], b = st[i + 1]
    for j in 0..<sub {
      let f = Float(j) / Float(sub)
      stations.append(WS(s: a.s + (b.s - a.s) * f, le: a.le + (b.le - a.le) * f, te: a.te + (b.te - a.te) * f,
                         t: a.t + (b.t - a.t) * f, y: a.y + (b.y - a.y) * f))
    }
  }
  stations.append(st[st.count - 1])
  var ringU: [Float] = us
  for j in stride(from: n - 1, through: 1, by: -1) { ringU.append(us[j]) }
  let rows: [[V3]] = stations.map { w in
    var ring: [V3] = us.map { u in V3(side * w.s, w.y + nacaHalf(u) * w.t, w.le + u * (w.te - w.le)) }
    for j in stride(from: n - 1, through: 1, by: -1) {
      ring.append(V3(side * w.s, w.y - nacaHalf(us[j]) * w.t, w.le + us[j] * (w.te - w.le)))
    }
    return ring
  }
  var crease = [Bool](repeating: false, count: ringU.count)
  crease[0] = true; crease[n] = true
  let capMaterial = skin(Facet(p: V3(0, 0, 0), n: V3(0, 1, 0), u: 0.5))
  gridSkin(p, rows: rows, crease: crease, us: ringU, capStart: capMaterial, capEnd: capMaterial, skin: skin)
  return WingSurface(frame: p, st: st, side: side)
}

/// Adds a triangle whose winding faces `n`.
func emitTri(_ m: Mesh, _ a: V3, _ b: V3, _ c: V3, _ na: V3, _ nb: V3, _ nc: V3) {
  let base = UInt32(m.positions.count)
  m.positions += [a, b, c]; m.normals += [na, nb, nc]
  m.indices += simd_dot(simd_cross(b - a, c - a), na + nb + nc) >= 0 ? [base, base + 1, base + 2] : [base, base + 2, base + 1]
}

/// Adds a triangle over existing vertices, wound to face their normals.
func indexedTri(_ m: Mesh, _ a: UInt32, _ b: UInt32, _ c: UInt32) {
  let pa = m.positions[Int(a)], pb = m.positions[Int(b)], pc = m.positions[Int(c)]
  let n = m.normals[Int(a)] + m.normals[Int(b)] + m.normals[Int(c)]
  m.indices += simd_dot(simd_cross(pb - pa, pc - pa), n) >= 0 ? [a, b, c] : [a, c, b]
}

/// Builds a ribbon `width` wide through surface points with their normals
/// (two shared vertices per point).
func ribbon(_ m: Mesh, _ pts: [(V3, V3)], width: Float) {
  guard pts.count >= 2 else { return }
  let base = UInt32(m.positions.count)
  for i in 0..<pts.count {
    let (p, n) = pts[i]
    let d = pts[min(pts.count - 1, i + 1)].0 - pts[max(0, i - 1)].0
    var side = simd_cross(n, d)
    if simd_length(side) < 1e-6 { side = V3(1, 0, 0) }
    side = simd_normalize(side) * (width / 2)
    m.positions += [p - side, p + side]; m.normals += [n, n]
  }
  for i in 0..<UInt32(pts.count - 1) {
    let l0 = base + 2 * i, r0 = l0 + 1, l1 = l0 + 2, r1 = l0 + 3
    indexedTri(m, l0, r0, r1)
    indexedTri(m, l0, r1, l1)
  }
}

/// Lines drawn on a wing or tail skin: polylines of (span, z) points.
func wingLines(_ w: WingSurface, _ lines: [[SIMD2<Float>]], width: Float = 0.035, _ m: SCNMaterial,
               upper: Bool = true, lower: Bool = false, lift: Float = 0.012) {
  let mesh = Mesh()
  for faceUp in [true, false] where (faceUp && upper) || (!faceUp && lower) {
    let n = V3(0, faceUp ? 1 : -1, 0)
    for line in lines {
      var pts: [(V3, V3)] = []
      for k in 0..<(line.count - 1) {
        let a = line[k], b = line[k + 1]
        let steps = max(1, Int(simd_length(b - a) / 0.15))
        for j in 0...steps where !(j == 0 && k > 0) {
          let q = a + (b - a) * (Float(j) / Float(steps))
          pts.append((w.point(q.x, q.y, upper: faceUp, lift: lift), n))
        }
      }
      ribbon(mesh, pts, width: width)
    }
  }
  if !mesh.indices.isEmpty { w.frame.addChildNode(SCNNode(geometry: mesh.geometry(m))) }
}

/// A filled convex patch on a wing or tail skin, given as (span, z) points.
func wingPatch(_ w: WingSurface, _ poly: [SIMD2<Float>], _ m: SCNMaterial, upper: Bool = true, lift: Float = 0.014) {
  let mesh = Mesh()
  let c = poly.reduce(SIMD2<Float>(0, 0), +) / Float(poly.count)
  let n = V3(0, upper ? 1 : -1, 0)
  let k = 3
  for i in 0..<poly.count {
    let a = poly[i], b = poly[(i + 1) % poly.count]
    // Subdivide each fan triangle so the patch follows the airfoil's curve.
    func q(_ i: Int, _ j: Int) -> V3 {
      let s = c + (a - c) * (Float(i) / Float(k)) + (b - c) * (Float(j) / Float(k))
      return w.point(s.x, s.y, upper: upper, lift: lift)
    }
    for i in 0..<k {
      for j in 0..<(k - i) {
        emitTri(mesh, q(i, j), q(i + 1, j), q(i, j + 1), n, n, n)
        if i + j < k - 1 { emitTri(mesh, q(i + 1, j), q(i + 1, j + 1), q(i, j + 1), n, n, n) }
      }
    }
  }
  w.frame.addChildNode(SCNNode(geometry: mesh.geometry(m)))
}

/// Stroke letters for tail codes on a unit cell (x across, y up).
let tailFont: [Character: [[SIMD2<Float>]]] = [
  "A": [[SIMD2(0, 0), SIMD2(0.3, 1), SIMD2(0.6, 0)], [SIMD2(0.13, 0.42), SIMD2(0.47, 0.42)]],
  "F": [[SIMD2(0, 0), SIMD2(0, 1), SIMD2(0.6, 1)], [SIMD2(0, 0.52), SIMD2(0.45, 0.52)]],
  "H": [[SIMD2(0, 0), SIMD2(0, 1)], [SIMD2(0.6, 0), SIMD2(0.6, 1)], [SIMD2(0, 0.5), SIMD2(0.6, 0.5)]],
  "L": [[SIMD2(0, 1), SIMD2(0, 0), SIMD2(0.6, 0)]],
  "V": [[SIMD2(0, 1), SIMD2(0.3, 0), SIMD2(0.6, 1)]],
]

/// A tail code on one face of a fin: letters `height` tall with their
/// baseline at span `s`, the block starting at z. `upperFace` picks the
/// frame's +Y face; `readAft` is true for faces seen from the left, where
/// text runs nose to tail.
func tailCode(_ fin: WingSurface, _ text: String, s: Float, z: Float, height: Float, _ m: SCNMaterial,
              upperFace: Bool, readAft: Bool) {
  var lines: [[SIMD2<Float>]] = []
  let advance = height * 0.85
  let width = advance * Float(text.count - 1) + height * 0.6
  for (k, ch) in text.enumerated() {
    for stroke in tailFont[ch] ?? [] {
      lines.append(stroke.map { p in
        let along = Float(k) * advance + p.x * height
        return SIMD2(s + p.y * height, readAft ? z + along : z + width - along)
      })
    }
  }
  wingLines(fin, lines, width: height * 0.16, m, upper: upperFace, lower: !upperFace)
}

/// Downward (or upward) ray casts onto everything built so far, for draping
/// panel lines and markings over the fuselage.
final class Drape {
  struct Tri { let a: V3; let b: V3; let c: V3 }
  var tris: [Tri] = []
  var bins: [Int: [Int32]] = [:]
  let cell: Float = 0.5
  func key(_ i: Int, _ j: Int) -> Int { (i + 2000) * 8192 + (j + 2000) }
  /// Which axis the rays travel along: 1 (Y, the default) casts down onto
  /// the top or up onto the belly with (x, z) positions; 0 (X) casts onto
  /// the sides with (z, y) positions; 2 (Z) casts onto the front or back
  /// with (x, y) positions. `below` picks the lowest hit along the axis.
  let axis: Int
  var order: (Int, Int, Int) { axis == 0 ? (2, 0, 1) : axis == 2 ? (0, 2, 1) : (0, 1, 2) }
  func swizzle(_ p: V3) -> V3 { let o = order; return V3(p[o.0], p[o.1], p[o.2]) }
  func unswizzle(_ s: V3) -> V3 { let o = order; var p = V3(0, 0, 0); p[o.0] = s.x; p[o.1] = s.y; p[o.2] = s.z; return p }
  init(_ root: SCNNode, axis: Int = 1, skip: Set<String> = ["canopy"]) {
    self.axis = axis
    root.enumerateHierarchy { node, _ in
      guard let g = node.geometry, let vs = g.sources(for: .vertex).first else { return }
      if let name = g.firstMaterial?.name, skip.contains(name) { return }
      let t = node.simdConvertTransform(matrix_identity_float4x4, to: root)
      let pts = vectors(vs).map { v -> V3 in let w = t * SIMD4<Float>(v.x, v.y, v.z, 1); return swizzle(V3(w.x, w.y, w.z)) }
      for e in 0..<g.elementCount {
        let idx = triangleIndices(g.element(at: e))
        for k in stride(from: 0, to: idx.count - 2, by: 3) {
          let tri = Tri(a: pts[Int(idx[k])], b: pts[Int(idx[k + 1])], c: pts[Int(idx[k + 2])])
          let id = Int32(tris.count)
          tris.append(tri)
          let x0 = Int((min(tri.a.x, tri.b.x, tri.c.x) / cell).rounded(.down)), x1 = Int((max(tri.a.x, tri.b.x, tri.c.x) / cell).rounded(.down))
          let z0 = Int((min(tri.a.z, tri.b.z, tri.c.z) / cell).rounded(.down)), z1 = Int((max(tri.a.z, tri.b.z, tri.c.z) / cell).rounded(.down))
          if x1 - x0 > 40 || z1 - z0 > 40 { continue }
          for i in x0...x1 { for j in z0...z1 { bins[key(i, j), default: []].append(id) } }
        }
      }
    }
  }
  /// The highest (or lowest) surface point above (x, z), with its normal.
  func hit(_ x: Float, _ z: Float, below: Bool) -> (V3, V3)? {
    var best: (V3, V3)?
    for id in bins[key(Int((x / cell).rounded(.down)), Int((z / cell).rounded(.down)))] ?? [] {
      let t = tris[Int(id)]
      let v0 = SIMD2(t.b.x - t.a.x, t.b.z - t.a.z), v1 = SIMD2(t.c.x - t.a.x, t.c.z - t.a.z), v2 = SIMD2(x - t.a.x, z - t.a.z)
      let den = v0.x * v1.y - v1.x * v0.y
      if abs(den) < 1e-9 { continue }
      let b1 = (v2.x * v1.y - v1.x * v2.y) / den, b2 = (v0.x * v2.y - v2.x * v0.y) / den
      if b1 < -1e-4 || b2 < -1e-4 || b1 + b2 > 1 + 1e-4 { continue }
      let y = t.a.y + b1 * (t.b.y - t.a.y) + b2 * (t.c.y - t.a.y)
      if let b = best, below ? y >= b.0.y : y <= b.0.y { continue }
      var n = simd_normalize(simd_cross(t.b - t.a, t.c - t.a))
      if (n.y < 0) != below { n = -n }
      best = (V3(x, y, z), n)
    }
    return best.map { (unswizzle($0.0), unswizzle($0.1)) }
  }
}

/// Panel lines draped over the top (or the belly) along (x, z) polylines,
/// optionally mirrored to the left side.
func decalLines(_ p: SCNNode, _ d: Drape, _ lines: [[SIMD2<Float>]], width: Float = 0.03, _ m: SCNMaterial,
                below: Bool = false, mirror: Bool = true, lift: Float = 0.012, maxSteps: Int = 1000) {
  let mesh = Mesh()
  for flip in mirror ? [Float(1), -1] : [1] {
    for line in lines {
      var run: [(V3, V3)] = []
      for k in 0..<(line.count - 1) {
        let a = line[k] * SIMD2(flip, 1), b = line[k + 1] * SIMD2(flip, 1)
        let steps = max(1, min(maxSteps, Int(simd_length(b - a) / 0.08)))
        for j in 0...steps where !(j == 0 && k > 0) {
          let q = a + (b - a) * (Float(j) / Float(steps))
          if let (pt, n) = d.hit(q.x, q.y, below: below) { run.append((pt + n * lift, n)) }
          else { ribbon(mesh, run, width: width); run = [] }
        }
      }
      ribbon(mesh, run, width: width)
    }
  }
  if !mesh.indices.isEmpty { p.addChildNode(SCNNode(geometry: mesh.geometry(m))) }
}

/// Filled markings draped over the top (or belly): star-shaped (x, z)
/// polygons, optionally mirrored.
func decalPatches(_ p: SCNNode, _ d: Drape, _ polys: [[SIMD2<Float>]], _ m: SCNMaterial, below: Bool = false,
                  mirror: Bool = false, lift: Float = 0.014, k: Int = 4) {
  let mesh = Mesh()
  for flip in mirror ? [Float(1), -1] : [1] {
    for poly0 in polys {
      let poly = poly0.map { $0 * SIMD2(flip, 1) }
      let c = poly.reduce(SIMD2<Float>(0, 0), +) / Float(poly.count)
      // Vertices shared between the fan's triangles, keyed by position.
      var ids: [SIMD2<Int32>: UInt32] = [:]
      func vertex(_ s: SIMD2<Float>) -> UInt32? {
        let key = SIMD2<Int32>(Int32((s.x * 10000).rounded()), Int32((s.y * 10000).rounded()))
        if let v = ids[key] { return v == UInt32.max ? nil : v }
        guard let (pt, n) = d.hit(s.x, s.y, below: below) else { ids[key] = UInt32.max; return nil }
        let v = UInt32(mesh.positions.count)
        mesh.positions.append(pt + n * lift); mesh.normals.append(n); ids[key] = v
        return v
      }
      for e in 0..<poly.count {
        let a = poly[e], b = poly[(e + 1) % poly.count]
        // Subdivide only as finely as the triangle's size needs.
        let kk = max(1, min(k, Int((max(simd_length(a - c), simd_length(b - c)) / 0.12).rounded(.up))))
        func q(_ i: Int, _ j: Int) -> UInt32? {
          vertex(c + (a - c) * (Float(i) / Float(kk)) + (b - c) * (Float(j) / Float(kk)))
        }
        for i in 0..<kk {
          for j in 0..<(kk - i) {
            if let x = q(i, j), let y = q(i + 1, j), let z = q(i, j + 1) { indexedTri(mesh, x, y, z) }
            if i + j < kk - 1, let x = q(i + 1, j), let y = q(i + 1, j + 1), let z = q(i, j + 1) { indexedTri(mesh, x, y, z) }
          }
        }
      }
    }
  }
  if !mesh.indices.isEmpty { p.addChildNode(SCNNode(geometry: mesh.geometry(m))) }
}

/// A smooth-edged marking draped over the top: the region where f(x, z) > 0,
/// traced with marching squares on a `cell` grid (used for camouflage).
func decalField(_ p: SCNNode, _ d: Drape, x0: Float, x1: Float, z0: Float, z1: Float, cell: Float,
                _ f: (Float, Float) -> Float, _ m: SCNMaterial, lift: Float = 0.01) {
  let mesh = Mesh()
  var ids: [SIMD2<Int32>: UInt32] = [:]
  func vertex(_ q: SIMD2<Float>) -> UInt32? {
    let key = SIMD2<Int32>(Int32((q.x * 1000).rounded()), Int32((q.y * 1000).rounded()))
    if let v = ids[key] { return v == UInt32.max ? nil : v }
    guard let (pt, n) = d.hit(q.x, q.y, below: false) else { ids[key] = UInt32.max; return nil }
    let v = UInt32(mesh.positions.count)
    mesh.positions.append(pt + n * lift); mesh.normals.append(n); ids[key] = v
    return v
  }
  let nx = Int(((x1 - x0) / cell).rounded(.up)), nz = Int(((z1 - z0) / cell).rounded(.up))
  var values = [[Float]](repeating: [Float](repeating: 0, count: nz + 1), count: nx + 1)
  for i in 0...nx { for j in 0...nz { values[i][j] = f(x0 + Float(i) * cell, z0 + Float(j) * cell) } }
  for i in 0..<nx {
    for j in 0..<nz {
      let corners = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
      var poly: [SIMD2<Float>] = []
      for k in 0..<4 {
        let (ai, aj) = corners[k], (bi, bj) = corners[(k + 1) % 4]
        let va = values[ai][aj], vb = values[bi][bj]
        let pa = SIMD2(x0 + Float(ai) * cell, z0 + Float(aj) * cell), pb = SIMD2(x0 + Float(bi) * cell, z0 + Float(bj) * cell)
        if va > 0 { poly.append(pa) }
        if (va > 0) != (vb > 0) { poly.append(pa + (pb - pa) * (va / (va - vb))) }
      }
      guard poly.count >= 3 else { continue }
      let vs = poly.map(vertex)
      for k in 1..<(poly.count - 1) {
        guard let a = vs[0], let b = vs[k], let c = vs[k + 1] else { continue }
        let n = mesh.normals[Int(a)] + mesh.normals[Int(b)] + mesh.normals[Int(c)]
        let pa = mesh.positions[Int(a)], pb = mesh.positions[Int(b)], pc = mesh.positions[Int(c)]
        mesh.indices += simd_dot(simd_cross(pb - pa, pc - pa), n) >= 0 ? [a, b, c] : [a, c, b]
      }
    }
  }
  if !mesh.indices.isEmpty { p.addChildNode(SCNNode(geometry: mesh.geometry(m))) }
}

/// Outline points of a regular polygon (or a star when `inner` is set).
func ring2(_ cx: Float, _ cz: Float, _ r: Float, _ n: Int, inner: Float? = nil, phase: Float = 0) -> [SIMD2<Float>] {
  let count = inner == nil ? n : n * 2
  return (0..<count).map { i in
    let a = phase + Float(i) / Float(count) * 2 * .pi
    let rr = inner != nil && i % 2 == 1 ? inner! : r
    return SIMD2(cx + sin(a) * rr, cz - cos(a) * rr)
  }
}

/// A rectangle outline (x0...x1, z0...z1) as a closed polyline.
func rectLine(_ x0: Float, _ z0: Float, _ x1: Float, _ z1: Float) -> [SIMD2<Float>] {
  [SIMD2(x0, z0), SIMD2(x1, z0), SIMD2(x1, z1), SIMD2(x0, z1), SIMD2(x0, z0)]
}

/// A sawtooth edge from a to b with `teeth` teeth of depth `depth` (to the
/// left of the direction of travel).
func sawLine(_ a: SIMD2<Float>, _ b: SIMD2<Float>, teeth: Int, depth: Float) -> [SIMD2<Float>] {
  let d = b - a, n = simd_normalize(SIMD2(-d.y, d.x)) * depth
  var pts: [SIMD2<Float>] = []
  for i in 0...(teeth * 2) {
    let p = a + d * (Float(i) / Float(teeth * 2))
    pts.append(i % 2 == 1 ? p + n : p)
  }
  return pts
}

/// US national insignia (star, disc and bars) for low-visibility markings,
/// centred at (x, z), radius r, bars along X.
func insignia(_ p: SCNNode, _ d: Drape, x: Float, z: Float, r: Float, _ m: SCNMaterial, star: SCNMaterial, below: Bool = false) {
  let disc = ring2(x, z, r, 20)
  let bars = [[SIMD2(x - 2 * r, z - r * 0.33), SIMD2(x - r * 0.7, z - r * 0.33), SIMD2(x - r * 0.7, z + r * 0.33), SIMD2(x - 2 * r, z + r * 0.33)],
              [SIMD2(x + r * 0.7, z - r * 0.33), SIMD2(x + 2 * r, z - r * 0.33), SIMD2(x + 2 * r, z + r * 0.33), SIMD2(x + r * 0.7, z + r * 0.33)]]
  decalPatches(p, d, [disc] + bars, m, below: below)
  decalPatches(p, d, [ring2(x, z, r * 0.9, 5, inner: r * 0.36)], star, below: below, lift: 0.02)
}

/// A round nozzle along +Z from z0 (radius r0) to z1 (radius r1) whose rim
/// is cut into `teeth` saw teeth, with a dark throat inside.
func roundNozzle(_ p: SCNNode, x: Float, y: Float, z0: Float, z1: Float, r0: Float, r1: Float,
                 teeth: Int, depth: Float, _ outer: SCNMaterial, inner: SCNMaterial, petals: SCNMaterial? = nil) {
  let K = teeth * 2
  func ring(_ z: Float, _ r: Float, saw: Bool) -> [V3] {
    (0..<K).map { i in
      let a = Float(i) / Float(K) * 2 * .pi
      return V3(x + cos(a) * r, y + sin(a) * r, saw && i % 2 == 1 ? z - depth : z)
    }
  }
  let rm = r1 + (r0 - r1) * depth / (z1 - z0)
  gridSkin(p, rows: [ring(z0, r0, saw: false), ring(z0 + (z1 - z0) * 0.35, r0 - (r0 - r1) * 0.3, saw: false),
                     ring(z1 - depth, rm, saw: false), ring(z1, r1, saw: true)],
           crease: (0..<K).map { _ in false }) { f in
    // Alternate petals catch the light differently.
    guard let petals else { return outer }
    let a = atan2(f.p.y - y, f.p.x - x) + .pi
    return Int((a / (2 * .pi) * Float(teeth)).rounded(.down)) % 2 == 0 ? outer : petals
  }
  gridSkin(p, rows: [ring(z1, r1 * 0.95, saw: true), ring(z1 - 0.8, r1 * 0.78, saw: false)],
           crease: (0..<K).map { _ in false }, inward: true, capEnd: inner) { _ in inner }
}

/// A rectangular (two-dimensional) nozzle: four flat flaps through
/// (z, width, height) stations centred on (x, y), with a dark exit.
func flatNozzle(_ p: SCNNode, x: Float, y: Float, _ st: [(Float, Float, Float)], _ m: SCNMaterial, inner: SCNMaterial) {
  let rows: [[V3]] = st.map { z, w, h in
    [V3(x - w / 2, y - h / 2, z), V3(x + w / 2, y - h / 2, z), V3(x + w / 2, y + h / 2, z), V3(x - w / 2, y + h / 2, z)]
  }
  gridSkin(p, rows: rows, crease: [true, true, true, true]) { _ in m }
  let (z, w, h) = st[st.count - 1]
  gridSkin(p, rows: [rows[rows.count - 1], [V3(x - w * 0.42, y - h * 0.3, z - 0.6), V3(x + w * 0.42, y - h * 0.3, z - 0.6),
                                           V3(x + w * 0.42, y + h * 0.3, z - 0.6), V3(x - w * 0.42, y + h * 0.3, z - 0.6)]],
           crease: [true, true, true, true], inward: true, capEnd: inner) { _ in inner }
}

/// Splits each edge of a closed polygon ring into `n` pieces (keeping the
/// corners as creases).
func subdivideRing(_ ring: [V3], _ n: Int) -> (pts: [V3], crease: [Bool]) {
  var pts: [V3] = [], crease: [Bool] = []
  for i in 0..<ring.count {
    let a = ring[i], b = ring[(i + 1) % ring.count]
    for j in 0..<n { pts.append(a + (b - a) * (Float(j) / Float(n))); crease.append(j == 0) }
  }
  return (pts, crease)
}

/// An intake trunk: a polygon lip (its corners may be swept to different
/// Z) lofted back through planar polygon sections, with a dark duct
/// receding `depth` behind the lip. Corner lists run the same way round.
func intakeTrunk(_ p: SCNNode, lip: [V3], sections: [(Float, [SIMD2<Float>])], depth: Float, sub: Int = 3,
                 smooth: Bool = false, duct: SCNMaterial, skin: (Facet) -> SCNMaterial) {
  var rows = [subdivideRing(lip, sub).pts]
  let crease = smooth ? subdivideRing(lip, sub).crease.map { _ in false } : subdivideRing(lip, sub).crease
  for (z, poly) in sections { rows.append(subdivideRing(poly.map { V3($0.x, $0.y, z) }, sub).pts) }
  gridSkin(p, rows: rows, crease: crease, skin: skin)
  let c = lip.reduce(V3(0, 0, 0), +) / Float(lip.count)
  let back = lip.map { c + ($0 - c) * 0.72 + V3(0, 0, depth) }
  gridSkin(p, rows: [subdivideRing(lip, sub).pts, subdivideRing(back, sub).pts], crease: crease, inward: true,
           capEnd: duct) { _ in duct }
}

/// Smooth value noise in about 0...1, for camouflage blotches.
func camoNoise(_ x: Float, _ z: Float, scale: Float, seed: UInt32) -> Float {
  func hash(_ i: Int32, _ j: Int32) -> Float {
    var h = UInt32(bitPattern: i) &* 0x8DA6_B343 ^ UInt32(bitPattern: j) &* 0xD816_3841 ^ seed &* 0xCB1A_B31F
    h ^= h >> 13; h = h &* 0x5BD1_E995; h ^= h >> 15
    return Float(h & 0xFFFFFF) / Float(0xFFFFFF)
  }
  func value(_ x: Float, _ y: Float) -> Float {
    let xi = x.rounded(.down), yi = y.rounded(.down)
    let fx = x - xi, fy = y - yi
    let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
    let i = Int32(xi), j = Int32(yi)
    let a = hash(i, j), b = hash(i + 1, j), c = hash(i, j + 1), d = hash(i + 1, j + 1)
    return (a + (b - a) * sx) * (1 - sy) + (c + (d - c) * sx) * sy
  }
  return 0.65 * value(x / scale, z / scale) + 0.35 * value(x / scale * 2.3 + 7.1, z / scale * 2.3 + 3.7)
}

let jetIntake = material("intake", 0x050506, rough: 0.95)
let jetExhaust = material("exhaust", 0x070708, rough: 0.9)
let canopyGold = material("canopy", 0x130E03, metal: 0.7, rough: 0.06)
let canopySmoke = material("canopy", 0x0E1318, metal: 0.75, rough: 0.08)
let navRed = material("nav-red", 0xFF2A1A, rough: 0.4, emit: true)
let navGreen = material("nav-green", 0x16D870, rough: 0.4, emit: true)
let missileGrey = material("missile", 0x8A8D90, metal: 0.1, rough: 0.5)
func jetPaint(_ name: String, _ hex: UInt32) -> SCNMaterial { material(name, hex, metal: 0.18, rough: 0.55) }

/// Builds a jet nose-first along +Z (nose at z = 0, belly at y = 0) and
/// collapses it into one mesh per material.
func fighter(length L: Float, _ build: (SCNNode) -> Void) -> SCNNode {
  spacecraft { r in build(holder(r, V3(0, 0, -L / 2))) }
}

/// A canopy through (z, half width, bottom, top) stations; its lower part
/// sinks into the fuselage.
func jetCanopy(_ p: SCNNode, _ st: [(Float, Float, Float, Float)], _ m: SCNMaterial) {
  jetBody(p, st.map { Ring(z: $0.0, half: ovalHalf($0.1, $0.2, $0.3, n: 2.1, count: 11, widest: 0.22)) },
          step: 0.1, capStart: m, capEnd: m) { _ in m }
}

/// Port (red) and starboard (green) navigation lights.
func navLights(_ p: SCNNode, x: Float, y: Float, z: Float) {
  box(p, 0.06, 0.05, 0.16, navRed, -x, y, z)
  box(p, 0.06, 0.05, 0.16, navGreen, x, y, z)
}

/// A frame for a fin rooted at (x, y), canted outward by `cant` from the
/// vertical (its span runs along the frame's X).
func finFrame(_ p: SCNNode, x: Float, y: Float, cant: Float, side: Float) -> SCNNode {
  holder(p, V3(side * x, y, 0), rz: side * (.pi / 2 - cant))
}

// F-22A Raptor: 18.9 m long, 13.6 m span. Planform, side and front
// profiles measured from the USAF 3-view: chined nose, swept caret
// intakes with deep ducts, 42-degree diamond wing with 3 degrees of
// anhedral, flaperons and ailerons, big fins canted 27 degrees with
// rudders, stabilisers reaching 2 m past the 2D nozzles, engine humps
// either side of the tail stinger, dark radome, two-tone haze grey with
// lighter edge tape, sawtooth panels and low-vis markings.
func f22() -> SCNNode {
  let L: Float = 18.92
  let light = jetPaint("paint", 0x24292E), dark = jetPaint("camo", 0x1C2024), edge = jetPaint("edge", 0x2B3035)
  let radome = jetPaint("radome", 0x1A1D20), tape = jetPaint("panel-light", 0x3A4046)
  let line = material("panel", 0x15171A, rough: 0.7), marking = material("marking", 0x16181B, rough: 0.6)
  let nozzle = material("nozzle", 0x1B1C1D, metal: 0.4, rough: 0.6)
  return fighter(length: L) { p in
    func skin(_ f: Facet) -> SCNMaterial { f.u >= 0 && (f.u < 0.045 || f.u > 0.955) ? edge : light }
    func bodySkin(_ f: Facet) -> SCNMaterial { f.p.z + L / 2 < 2.1 ? radome : skin(f) }
    // Fuselage: half-sections (bottom centre, lower chine, chine, shoulder, flank, top).
    jetBody(p, [
      Ring(z: 0, half: noseTip(0.78, 6)),
      Ring(z: 0.95, half: [SIMD2(0, 0.56), SIMD2(0.32, 0.66), SIMD2(0.48, 0.84), SIMD2(0.34, 1.0), SIMD2(0.17, 1.07), SIMD2(0, 1.09)]),
      Ring(z: 1.9, half: [SIMD2(0, 0.42), SIMD2(0.47, 0.55), SIMD2(0.7, 0.88), SIMD2(0.48, 1.17), SIMD2(0.24, 1.34), SIMD2(0, 1.38)]),
      Ring(z: 2.84, half: [SIMD2(0, 0.32), SIMD2(0.56, 0.45), SIMD2(0.82, 0.92), SIMD2(0.58, 1.28), SIMD2(0.28, 1.5), SIMD2(0, 1.55)]),
      Ring(z: 3.8, half: [SIMD2(0, 0.24), SIMD2(0.62, 0.36), SIMD2(0.9, 0.95), SIMD2(0.64, 1.34), SIMD2(0.31, 1.58), SIMD2(0, 1.62)]),
      Ring(z: 4.75, half: [SIMD2(0, 0.17), SIMD2(0.66, 0.28), SIMD2(0.97, 0.98), SIMD2(0.68, 1.4), SIMD2(0.33, 1.64), SIMD2(0, 1.68)]),
      Ring(z: 6.0, half: [SIMD2(0, 0.08), SIMD2(0.7, 0.14), SIMD2(1.0, 1.0), SIMD2(0.76, 1.5), SIMD2(0.36, 1.74), SIMD2(0, 1.78)]),
      Ring(z: 7.2, half: [SIMD2(0, 0.02), SIMD2(0.8, 0.06), SIMD2(1.2, 1.05), SIMD2(0.95, 1.64), SIMD2(0.42, 1.95), SIMD2(0, 2.0)]),
      Ring(z: 8.6, half: [SIMD2(0, 0), SIMD2(1.5, 0.04), SIMD2(2.0, 1.1), SIMD2(1.5, 1.55), SIMD2(0.6, 1.86), SIMD2(0, 1.9)]),
      Ring(z: 10.5, half: [SIMD2(0, 0), SIMD2(1.55, 0.05), SIMD2(2.15, 1.1), SIMD2(1.55, 1.45), SIMD2(0.6, 1.72), SIMD2(0, 1.75)]),
      Ring(z: 12.5, half: [SIMD2(0, 0.08), SIMD2(1.5, 0.12), SIMD2(2.1, 1.1), SIMD2(1.55, 1.38), SIMD2(0.7, 1.52), SIMD2(0, 1.5)]),
      Ring(z: 14.2, half: [SIMD2(0, 0.25), SIMD2(1.4, 0.3), SIMD2(2.0, 1.08), SIMD2(1.5, 1.3), SIMD2(0.7, 1.32), SIMD2(0, 1.26)]),
      Ring(z: 15.6, half: [SIMD2(0, 0.48), SIMD2(1.3, 0.5), SIMD2(1.85, 1.06), SIMD2(1.4, 1.22), SIMD2(0.6, 1.18), SIMD2(0, 1.12)]),
      Ring(z: 16.3, half: [SIMD2(0, 0.6), SIMD2(1.2, 0.62), SIMD2(1.7, 1.05), SIMD2(1.3, 1.18), SIMD2(0.5, 1.12), SIMD2(0, 1.08)]),
    ], sharp: [1, 2, 3], step: 0.2, sub: 2, capStart: radome, capEnd: light, skin: bodySkin)
    jetCanopy(p, [(2.45, 0.05, 1.45, 1.5), (3.0, 0.38, 1.4, 1.86), (3.8, 0.52, 1.42, 2.18), (4.5, 0.55, 1.46, 2.3),
                  (5.3, 0.5, 1.52, 2.24), (6.0, 0.36, 1.6, 2.08), (6.6, 0.1, 1.75, 1.95)], canopyGold)
    var fins: [WingSurface] = [], wings: [WingSurface] = [], stabs: [WingSurface] = []
    for side in [-1, 1] as [Float] {
      func m(_ pts: [SIMD2<Float>]) -> [SIMD2<Float>] { side > 0 ? pts : pts.reversed().map { SIMD2(-$0.x, $0.y) } }
      // Caret intake: the lip is swept back in plan (top edge) and in profile (outer edge).
      let lip = [V3(0.72, 0.1, 5.7), V3(1.4, 0.06, 6.25), V3(1.85, 1.04, 5.6), V3(0.97, 1.0, 4.75)]
      let sections: [(Float, [SIMD2<Float>])] = [
        (6.6, [SIMD2(0.7, 0.04), SIMD2(1.5, 0.04), SIMD2(1.98, 1.06), SIMD2(1.0, 1.12)]),
        (8.2, [SIMD2(0.75, 0.0), SIMD2(1.6, 0.02), SIMD2(2.15, 1.1), SIMD2(1.1, 1.3)]),
        (9.8, [SIMD2(0.8, 0.0), SIMD2(1.55, 0.04), SIMD2(2.12, 1.1), SIMD2(1.15, 1.42)]),
      ]
      let lipS = side > 0 ? lip : lip.reversed().map { V3(-$0.x, $0.y, $0.z) }
      intakeTrunk(p, lip: lipS, sections: sections.map { ($0.0, m($0.1)) }, depth: 1.6, duct: jetIntake, skin: skin)
      // Engine bays bulge either side of the tail stinger.
      jetBody(p, [Ring(z: 11.0, half: ovalHalf(0.3, 0.9, 1.5, count: 9)), Ring(z: 12.6, half: ovalHalf(0.56, 0.6, 1.62, count: 9)),
                  Ring(z: 14.6, half: ovalHalf(0.57, 0.55, 1.52, count: 9)), Ring(z: 16.2, half: ovalHalf(0.55, 0.62, 1.4, count: 9))],
              step: 0.2, x: side * 0.68, skin: skin)
      // Booms carrying the stabiliser pivots.
      jetBody(p, [Ring(z: 14.4, half: ovalHalf(0.36, 0.78, 1.32, n: 1.6, count: 7)), Ring(z: 16.6, half: ovalHalf(0.3, 0.84, 1.26, n: 1.6, count: 7)),
                  Ring(z: 17.7, half: ovalHalf(0.04, 1.0, 1.06, n: 1.6, count: 7))], step: 0.2, x: side * 1.62, skin: skin)
      // Diamond wing: 42-degree leading edge, trailing edge swept forward 17 degrees, cropped tip.
      wings.append(wingSkin(p, [WS(s: 1.6, le: 7.89, te: 16.07, t: 0.44, y: 1.12), WS(s: 6.55, le: 12.37, te: 14.3, t: 0.08, y: 0.84),
                                WS(s: 6.85, le: 12.65, te: 13.78, t: 0.07, y: 0.82)], side: side, chord: 10, sub: 4, skin: skin))
      // All-moving stabilisers with clipped corners.
      stabs.append(wingSkin(p, [WS(s: 1.3, le: 14.15, te: 17.5, t: 0.24, y: 1.04), WS(s: 2.8, le: 15.55, te: 18.9, t: 0.16, y: 1.04),
                                WS(s: 4.15, le: 16.8, te: 18.5, t: 0.07, y: 1.04),
                                WS(s: 4.51, le: 17.3, te: 18.2, t: 0.05, y: 1.04)], side: side, chord: 8, sub: 3, skin: skin))
      // Fins canted 27 degrees outward.
      let fin = finFrame(p, x: 1.66, y: 1.33, cant: 0.47, side: side)
      fins.append(wingSkin(fin, [WS(s: -0.3, le: 12.9, te: 17.35, t: 0.26, y: 0), WS(s: 0, le: 13.07, te: 17.2, t: 0.26, y: 0),
                                 WS(s: 2.7, le: 14.28, te: 15.82, t: 0.07, y: 0), WS(s: 2.96, le: 14.5, te: 15.7, t: 0.06, y: 0)],
                           side: side, chord: 8, sub: 3, skin: skin))
      // Two-dimensional thrust-vectoring nozzles with converged flaps.
      flatNozzle(p, x: side * 0.68, y: 1.0, [(16.1, 1.1, 0.84), (16.45, 1.08, 0.66), (16.78, 1.02, 0.34)], nozzle, inner: jetExhaust)
      // Sawtooth fairings outboard of the nozzles.
      for k in 0..<3 {
        let z0 = 15.9 + Float(k) * 0.32
        wingSkin(p, [WS(s: 1.2, le: z0, te: z0 + 0.32, t: 0.05, y: 1.02), WS(s: 1.45, le: z0 + 0.16, te: z0 + 0.17, t: 0.02, y: 1.02)],
                 side: side, chord: 3, sub: 1) { _ in light }
      }
    }
    box(p, 0.24, 0.12, 1.5, light, 0, 1.0, 16.95) // tail stinger
    navLights(p, x: 6.8, y: 0.84, z: 13.2)
    // Control surfaces, edge tape and markings on the flying surfaces.
    for w in wings {
      wingLines(w, [[SIMD2(2.3, w.z(2.3, 0.1)), SIMD2(6.5, w.z(6.5, 0.12))],
                    [SIMD2(2.2, w.z(2.2, 0.8)), SIMD2(4.75, w.z(4.75, 0.78)), SIMD2(4.75, w.z(4.75, 1))],
                    [SIMD2(4.85, w.z(4.85, 1)), SIMD2(4.85, w.z(4.85, 0.76)), SIMD2(6.45, w.z(6.45, 0.74)), SIMD2(6.45, w.z(6.45, 1))],
                    [SIMD2(2.2, w.z(2.2, 0.8)), SIMD2(2.2, w.z(2.2, 1))]], width: 0.035, line, lower: true)
    }
    for s in stabs { wingLines(s, [[SIMD2(1.8, s.z(1.8, 0.2)), SIMD2(4.0, s.z(4.0, 0.2))]], width: 0.03, tape) }
    for f in fins {
      wingLines(f, [[SIMD2(0.15, f.z(0.15, 0.72)), SIMD2(1.75, f.z(1.75, 0.68)), SIMD2(1.75, f.z(1.75, 1))]], width: 0.035, line,
                upper: true, lower: true)
      tailCode(f, "FF", s: 1.95, z: 14.15, height: 0.5, marking, upperFace: false, readAft: f.side < 0)
      wingLines(f, [[SIMD2(2.62, f.z(2.62, 0.08)), SIMD2(2.62, f.z(2.62, 0.92))]], width: 0.12, tape, upper: false, lower: true)
    }
    let d = Drape(p)
    // Two-tone camouflage: soft-edged darker blotches over the haze grey.
    decalField(p, d, x0: -7, x1: 7, z0: 1.8, z1: 19, cell: 0.17, { x, z in
      if abs(x) < 0.62 && z > 2.3 && z < 6.8 { return -1 }
      return camoNoise(x, z - L / 2, scale: 4.6, seed: 22) - 0.56
    }, dark)
    // Sawtooth edge tape, vents and doors on the upper fuselage.
    var tapes: [[SIMD2<Float>]] = []
    for row in 0..<4 { let z0 = 9.0 + Float(row) * 0.36; tapes.append(sawLine(SIMD2(0.22, z0), SIMD2(0.78, z0), teeth: 3, depth: -0.18)) }
    tapes.append(sawLine(SIMD2(1.05, 6.7), SIMD2(1.05, 9.2), teeth: 6, depth: 0.12))
    tapes.append(rectLine(0.3, 11.6, 0.75, 12.4))
    decalLines(p, d, tapes, width: 0.035, tape)
    decalLines(p, d, [[SIMD2(1.0, 6.4), SIMD2(1.12, 9.6)], [SIMD2(0.42, 7.6), SIMD2(0.42, 8.7)], [SIMD2(0.9, 10.6), SIMD2(0.9, 13.4)],
                      rectLine(0.12, 13.6, 0.5, 14.6), [SIMD2(0, 2.1), SIMD2(0.7, 2.1)]], width: 0.025, line)
    decalPatches(p, d, [[SIMD2(0.52, 6.25), SIMD2(0.66, 6.45), SIMD2(0.58, 6.75), SIMD2(0.44, 6.55)],
                        [SIMD2(0.76, 6.6), SIMD2(0.9, 6.8), SIMD2(0.82, 7.1), SIMD2(0.68, 6.9)],
                        [SIMD2(0.33, 6.95), SIMD2(0.66, 6.95), SIMD2(0.66, 7.25), SIMD2(0.33, 7.25)],
                        [SIMD2(0.33, 7.5), SIMD2(0.66, 7.5), SIMD2(0.66, 7.8), SIMD2(0.33, 7.8)]], line, mirror: true)
    decalPatches(p, d, [ring2(0.72, 10.6, 0.17, 6), ring2(-0.3, 11.0, 0.1, 4)], line)
    insignia(p, d, x: -4.3, z: 13.3, r: 0.42, marking, star: light)
    // Main weapons bay doors on the belly.
    decalLines(p, d, [sawLine(SIMD2(-0.7, 7.4), SIMD2(0.7, 7.4), teeth: 3, depth: -0.22), [SIMD2(0.7, 7.4), SIMD2(0.7, 11.2)],
                      sawLine(SIMD2(0.7, 11.2), SIMD2(-0.7, 11.2), teeth: 3, depth: -0.22), [SIMD2(-0.7, 11.2), SIMD2(-0.7, 7.4)],
                      [SIMD2(0, 7.6), SIMD2(0, 11.0)]], width: 0.03, line, below: true, mirror: false)
  }
}

// F-35A Lightning II: 15.7 m long, 10.7 m span, measured from the 3-view.
// Narrow chined forebody, forward-swept DSI inlets with bumps, broad
// bulged mid-body, trapezoid wing with flaperons, fins canted 23 degrees
// with rudders, stabilisers 1.6 m past the serrated nozzle, tail booms,
// single dark grey with lighter edge coatings, grilles, refuelling door,
// gun bump, bay doors and low-vis markings.
func f35() -> SCNNode {
  let L: Float = 15.67
  let base = jetPaint("paint", 0x0F1012), edge = jetPaint("edge", 0x1B1D20), tape = jetPaint("panel-light", 0x17191C)
  let line = material("panel", 0x08090A, rough: 0.7), marking = material("marking", 0x222528, rough: 0.6)
  let nozzle = material("nozzle", 0x15181D, metal: 0.45, rough: 0.5), nozzle2 = material("nozzle-petal", 0x1D2127, metal: 0.45, rough: 0.45)
  return fighter(length: L) { p in
    func skin(_ f: Facet) -> SCNMaterial { f.u >= 0 && (f.u < 0.05 || f.u > 0.95) ? edge : base }
    jetBody(p, [
      Ring(z: 0, half: noseTip(0.98, 6)),
      Ring(z: 0.8, half: [SIMD2(0, 0.76), SIMD2(0.26, 0.84), SIMD2(0.4, 1.0), SIMD2(0.3, 1.16), SIMD2(0.15, 1.24), SIMD2(0, 1.26)]),
      Ring(z: 1.8, half: [SIMD2(0, 0.52), SIMD2(0.4, 0.6), SIMD2(0.58, 1.03), SIMD2(0.42, 1.42), SIMD2(0.2, 1.6), SIMD2(0, 1.64)]),
      Ring(z: 3.0, half: [SIMD2(0, 0.47), SIMD2(0.5, 0.55), SIMD2(0.72, 1.06), SIMD2(0.52, 1.62), SIMD2(0.26, 1.86), SIMD2(0, 1.9)]),
      Ring(z: 4.0, half: [SIMD2(0, 0.43), SIMD2(0.58, 0.5), SIMD2(0.84, 1.08), SIMD2(0.62, 1.75), SIMD2(0.3, 1.98), SIMD2(0, 2.02)]),
      Ring(z: 5.2, half: [SIMD2(0, 0.32), SIMD2(0.62, 0.38), SIMD2(0.95, 1.1), SIMD2(0.78, 1.88), SIMD2(0.36, 2.2), SIMD2(0, 2.25)]),
      Ring(z: 6.6, half: [SIMD2(0, 0.16), SIMD2(0.8, 0.2), SIMD2(1.3, 1.15), SIMD2(1.0, 1.9), SIMD2(0.45, 2.17), SIMD2(0, 2.2)]),
      Ring(z: 8.0, half: [SIMD2(0, 0.05), SIMD2(1.1, 0.1), SIMD2(1.85, 1.2), SIMD2(1.25, 1.85), SIMD2(0.55, 2.1), SIMD2(0, 2.13)]),
      Ring(z: 10.0, half: [SIMD2(0, 0), SIMD2(1.2, 0.08), SIMD2(1.85, 1.2), SIMD2(1.3, 1.75), SIMD2(0.6, 2.02), SIMD2(0, 2.06)]),
      Ring(z: 12.0, half: [SIMD2(0, 0.1), SIMD2(1.15, 0.16), SIMD2(1.7, 1.2), SIMD2(1.25, 1.65), SIMD2(0.6, 1.95), SIMD2(0, 1.99)]),
      Ring(z: 13.2, half: [SIMD2(0, 0.25), SIMD2(1.0, 0.3), SIMD2(1.5, 1.18), SIMD2(1.1, 1.5), SIMD2(0.55, 1.75), SIMD2(0, 1.79)]),
      Ring(z: 13.9, half: [SIMD2(0, 0.3), SIMD2(0.8, 0.34), SIMD2(1.2, 1.12), SIMD2(0.9, 1.4), SIMD2(0.5, 1.56), SIMD2(0, 1.6)]),
    ], sharp: [1, 2], step: 0.16, sub: 3, capStart: base, capEnd: base, skin: skin)
    jetCanopy(p, [(1.95, 0.05, 1.58, 1.62), (2.5, 0.38, 1.52, 2.0), (3.3, 0.52, 1.58, 2.32), (4.1, 0.54, 1.68, 2.37),
                  (4.8, 0.45, 1.8, 2.3), (5.4, 0.2, 1.95, 2.25)], canopyGold)
    // Gun fairing over the left wing root.
    jetBody(p, [Ring(z: 7.2, half: ovalHalf(0.03, 1.9, 1.95, count: 7)), Ring(z: 7.9, half: ovalHalf(0.17, 1.76, 2.14, count: 7)),
                Ring(z: 9.4, half: ovalHalf(0.15, 1.76, 2.1, count: 7))], step: 0.25, x: -1.05, capEnd: base) { _ in base }
    var wings: [WingSurface] = [], fins: [WingSurface] = [], stabs: [WingSurface] = []
    for side in [-1, 1] as [Float] {
      func m(_ pts: [SIMD2<Float>]) -> [SIMD2<Float>] { side > 0 ? pts : pts.reversed().map { SIMD2(-$0.x, $0.y) } }
      // Diverterless supersonic inlet: forward-swept cowl lip, bump on the inner wall.
      let lip = [V3(0.7, 0.48, 4.95), V3(1.42, 0.52, 4.75), V3(1.5, 1.3, 4.25), V3(0.75, 1.32, 4.55)]
      let sections: [(Float, [SIMD2<Float>])] = [
        (5.4, [SIMD2(0.72, 0.36), SIMD2(1.5, 0.44), SIMD2(1.7, 1.24), SIMD2(0.85, 1.58)]),
        (7.0, [SIMD2(0.8, 0.18), SIMD2(1.6, 0.28), SIMD2(1.86, 1.2), SIMD2(1.0, 1.78)]),
        (8.6, [SIMD2(0.9, 0.08), SIMD2(1.55, 0.18), SIMD2(1.86, 1.2), SIMD2(1.05, 1.88)]),
      ]
      intakeTrunk(p, lip: side > 0 ? lip : lip.reversed().map { V3(-$0.x, $0.y, $0.z) },
                  sections: sections.map { ($0.0, m($0.1)) }, depth: 1.4, sub: 4, smooth: true, duct: jetIntake, skin: skin)
      jetBody(p, [Ring(z: 3.7, half: ovalHalf(0.02, 0.86, 0.92, count: 7)), Ring(z: 4.55, half: ovalHalf(0.24, 0.55, 1.28, count: 7)),
                  Ring(z: 5.3, half: ovalHalf(0.1, 0.62, 1.2, count: 7))], step: 0.12, x: side * 0.66) { _ in base }
      // Tail booms carrying the fins and stabilisers.
      jetBody(p, [Ring(z: 11.6, half: ovalHalf(0.34, 0.92, 1.5, n: 1.8, count: 7)), Ring(z: 14.0, half: ovalHalf(0.28, 1.0, 1.42, n: 1.8, count: 7)),
                  Ring(z: 15.1, half: ovalHalf(0.04, 1.16, 1.22, n: 1.8, count: 7))], step: 0.2, x: side * 1.3, skin: skin)
      wings.append(wingSkin(p, [WS(s: 1.6, le: 6.8, te: 12.53, t: 0.36, y: 1.21), WS(s: 2.17, le: 7.83, te: 12.38, t: 0.3, y: 1.21),
                                WS(s: 5.37, le: 10.0, te: 11.58, t: 0.07, y: 1.21)], side: side, chord: 10, sub: 5, skin: skin))
      stabs.append(wingSkin(p, [WS(s: 1.0, le: 12.27, te: 15.67, t: 0.2, y: 1.2), WS(s: 3.62, le: 14.12, te: 15.02, t: 0.05, y: 1.2)],
                            side: side, chord: 8, sub: 4, skin: skin))
      let fin = finFrame(p, x: 1.33, y: 1.43, cant: 0.4, side: side)
      fins.append(wingSkin(fin, [WS(s: -0.3, le: 11.45, te: 14.15, t: 0.22, y: 0), WS(s: 0, le: 11.6, te: 14.06, t: 0.22, y: 0),
                                 WS(s: 2.42, le: 13.56, te: 14.98, t: 0.05, y: 0)], side: side, chord: 8, sub: 4, skin: skin))
    }
    roundNozzle(p, x: 0, y: 0.92, z0: 13.3, z1: 14.08, r0: 0.66, r1: 0.56, teeth: 15, depth: 0.15, nozzle, inner: jetExhaust, petals: nozzle2)
    navLights(p, x: 5.35, y: 1.22, z: 10.6)
    for w in wings {
      wingLines(w, [[SIMD2(2.3, w.z(2.3, 0.13)), SIMD2(5.2, w.z(5.2, 0.15))],
                    [SIMD2(2.25, w.z(2.25, 1)), SIMD2(2.25, w.z(2.25, 0.76)), SIMD2(5.0, w.z(5.0, 0.72)), SIMD2(5.0, w.z(5.0, 1))]],
                width: 0.03, line, lower: true)
    }
    for s in stabs { wingLines(s, [[SIMD2(1.3, s.z(1.3, 0.3)), SIMD2(3.4, s.z(3.4, 0.3))]], width: 0.025, tape) }
    for f in fins {
      wingLines(f, [[SIMD2(0.15, f.z(0.15, 1)), SIMD2(0.15, f.z(0.15, 0.7)), SIMD2(2.25, f.z(2.25, 0.68)), SIMD2(2.25, f.z(2.25, 1))]],
                width: 0.03, line, upper: true, lower: true)
      tailCode(f, "HL", s: 1.1, z: 12.75, height: 0.5, marking, upperFace: false, readAft: f.side < 0)
    }
    let d = Drape(p)
    // Refuelling door with its sawtooth front, the IPP door, grilles and seams.
    decalLines(p, d, [sawLine(SIMD2(-0.3, 6.1), SIMD2(0.3, 6.1), teeth: 2, depth: -0.16), [SIMD2(0.3, 6.1), SIMD2(0.3, 7.2), SIMD2(-0.3, 7.2), SIMD2(-0.3, 6.1)],
                      rectLine(-0.22, 7.45, 0.22, 8.5), [SIMD2(0, 7.45), SIMD2(0, 8.5)]], width: 0.03, tape, mirror: false)
    decalLines(p, d, [[SIMD2(0.95, 5.4), SIMD2(1.05, 8.0), SIMD2(1.1, 11.2)], sawLine(SIMD2(1.1, 9.0), SIMD2(1.6, 9.0), teeth: 2, depth: 0.14),
                      [SIMD2(0.45, 9.2), SIMD2(0.45, 12.2)], rectLine(0.3, 12.4, 0.75, 13.1)], width: 0.025, line)
    decalPatches(p, d, [[SIMD2(1.12, 7.5), SIMD2(1.3, 7.5), SIMD2(1.3, 8.4), SIMD2(1.12, 8.4)],
                        [SIMD2(-1.1, 6.2), SIMD2(-1.32, 6.0), SIMD2(-1.38, 6.45), SIMD2(-1.16, 6.65)],
                        [SIMD2(-1.18, 6.8), SIMD2(-1.4, 6.6), SIMD2(-1.46, 7.05), SIMD2(-1.24, 7.25)]], line)
    insignia(p, d, x: 4.2, z: 11.1, r: 0.32, marking, star: base)
    // Weapons bay doors on the belly.
    var bays: [[SIMD2<Float>]] = []
    for x0 in [Float(0.12), -0.86] {
      bays.append(sawLine(SIMD2(x0, 6.4), SIMD2(x0 + 0.74, 6.4), teeth: 2, depth: -0.2))
      bays.append([SIMD2(x0 + 0.74, 6.4), SIMD2(x0 + 0.74, 10.8)])
      bays.append(sawLine(SIMD2(x0 + 0.74, 10.8), SIMD2(x0, 10.8), teeth: 2, depth: -0.2))
      bays.append([SIMD2(x0, 10.8), SIMD2(x0, 6.4)])
    }
    decalLines(p, d, bays, width: 0.03, line, below: true, mirror: false)
  }
}

// YF-23 Black Widow II: 20.6 m long, 13.3 m span. Planform from the YF-22/
// YF-23 comparison drawing, details from NASA photos: flat chined forebody
// with the canopy far forward, 40-degree diamond wing, big engine nacelles
// separated by a low spine, S-duct intakes under the wing, exhaust troughs
// lined with tiles on the aft deck, sawtooth trailing edge, ruddervators
// splayed 50 degrees; charcoal with light low-vis markings.
func yf23() -> SCNNode {
  let L: Float = 20.6
  let base = jetPaint("paint", 0x0B0C0D), edge = jetPaint("edge", 0x0F1012)
  let tile = material("tile", 0x3E3B37, metal: 0.4, rough: 0.5), trough = material("trough", 0x0A0908, rough: 0.9)
  let tileLine = material("tile-line", 0x3A3732, rough: 0.7)
  let line = material("panel", 0x060607, rough: 0.7), marking = material("marking", 0x34373B, rough: 0.6)
  return fighter(length: L) { p in
    func skin(_ f: Facet) -> SCNMaterial { f.u >= 0 && (f.u < 0.05 || f.u > 0.95) ? edge : base }
    func inTrough(_ f: Facet) -> Bool {
      let z = f.p.z + L / 2
      return z > 16.9 && abs(abs(f.p.x) - 1.05) < 0.56 && f.n.y > 0.35
    }
    jetBody(p, [
      Ring(z: 0, half: noseTip(0.95, 6)),
      Ring(z: 1.3, half: [SIMD2(0, 0.74), SIMD2(0.36, 0.8), SIMD2(0.54, 0.96), SIMD2(0.38, 1.12), SIMD2(0.18, 1.2), SIMD2(0, 1.22)]),
      Ring(z: 3.0, half: [SIMD2(0, 0.55), SIMD2(0.6, 0.62), SIMD2(0.89, 0.98), SIMD2(0.6, 1.28), SIMD2(0.3, 1.42), SIMD2(0, 1.46)]),
      Ring(z: 5.0, half: [SIMD2(0, 0.42), SIMD2(0.76, 0.5), SIMD2(1.13, 1.0), SIMD2(0.76, 1.38), SIMD2(0.36, 1.55), SIMD2(0, 1.6)]),
      Ring(z: 7.1, half: [SIMD2(0, 0.36), SIMD2(0.86, 0.42), SIMD2(1.33, 1.02), SIMD2(0.8, 1.42), SIMD2(0.38, 1.6), SIMD2(0, 1.64)]),
      Ring(z: 9.0, half: [SIMD2(0, 0.3), SIMD2(0.9, 0.36), SIMD2(1.4, 1.02), SIMD2(0.7, 1.4), SIMD2(0.34, 1.55), SIMD2(0, 1.58)]),
      Ring(z: 12.0, half: [SIMD2(0, 0.32), SIMD2(0.8, 0.38), SIMD2(1.2, 1.0), SIMD2(0.6, 1.32), SIMD2(0.3, 1.45), SIMD2(0, 1.48)]),
      Ring(z: 16.0, half: [SIMD2(0, 0.45), SIMD2(0.7, 0.5), SIMD2(1.0, 1.0), SIMD2(0.55, 1.25), SIMD2(0.28, 1.35), SIMD2(0, 1.38)]),
      Ring(z: 19.0, half: [SIMD2(0, 0.75), SIMD2(0.5, 0.78), SIMD2(0.75, 1.0), SIMD2(0.45, 1.15), SIMD2(0.22, 1.2), SIMD2(0, 1.22)]),
      Ring(z: 20.3, half: noseTip(1.04, 6)),
    ], sharp: [2], step: 0.18, sub: 2, capStart: base, capEnd: base, skin: skin)
    jetCanopy(p, [(2.0, 0.05, 1.36, 1.4), (2.6, 0.4, 1.3, 1.78), (3.4, 0.52, 1.35, 2.02), (4.2, 0.52, 1.42, 2.06),
                  (5.0, 0.42, 1.5, 1.96), (5.6, 0.12, 1.58, 1.7)], canopySmoke)
    func nacelle(_ hw: Float, _ b: Float, _ t: Float) -> [SIMD2<Float>] {
      [SIMD2(0, b), SIMD2(hw * 0.86, b + 0.03), SIMD2(hw * 1.18, min(1.0, b + (t - b) * 0.5)), SIMD2(hw * 0.8, t - (t - b) * 0.24),
       SIMD2(hw * 0.42, t - 0.03), SIMD2(0, t)]
    }
    var wings: [WingSurface] = [], tails: [WingSurface] = []
    for side in [-1, 1] as [Float] {
      let xc = side * 1.5
      jetBody(p, [Ring(z: 8.2, half: nacelle(0.5, 0.52, 0.98)), Ring(z: 10.4, half: nacelle(0.8, 0.3, 1.46)),
                  Ring(z: 12.0, half: nacelle(0.86, 0.25, 1.74)), Ring(z: 15.0, half: nacelle(0.86, 0.28, 1.74)),
                  Ring(z: 17.2, half: nacelle(0.85, 0.4, 1.62)), Ring(z: 19.4, half: nacelle(0.8, 0.66, 1.22))],
              sharp: [2, 3], step: 0.2, x: xc, sub: 2, capStart: jetIntake, capEnd: jetExhaust) { f in inTrough(f) ? trough : skin(f) }
      // S-duct intake mouth under the wing.
      let lip = [V3(0.95, 0.42, 9.2), V3(2.05, 0.42, 9.45), V3(2.15, 0.92, 9.0), V3(0.85, 0.92, 8.75)]
      intakeTrunk(p, lip: side > 0 ? lip : lip.reversed().map { V3(-$0.x, $0.y, $0.z) },
                  sections: [(10.2, side > 0 ? [SIMD2(0.9, 0.32), SIMD2(2.1, 0.32), SIMD2(2.2, 0.95), SIMD2(0.8, 0.95)]
                                             : [SIMD2(-0.8, 0.95), SIMD2(-2.2, 0.95), SIMD2(-2.1, 0.32), SIMD2(-0.9, 0.32)])],
                  depth: 1.2, sub: 2, duct: jetIntake, skin: skin)
      wings.append(wingSkin(p, [WS(s: 1.2, le: 6.99, te: 17.26, t: 0.44, y: 1.0), WS(s: 6.78, le: 11.58, te: 12.62, t: 0.07, y: 1.0)],
                            side: side, chord: 12, sub: 8, skin: skin))
      // Aft deck with the sawtooth trailing edge; the troughs run along it.
      wingSkin(p, [WS(s: 0, le: 15.0, te: 20.43, t: 0.12, y: 1.06), WS(s: 1.15, le: 15.0, te: 19.5, t: 0.12, y: 1.06),
                   WS(s: 2.06, le: 15.0, te: 20.22, t: 0.12, y: 1.06), WS(s: 2.4, le: 15.0, te: 19.8, t: 0.12, y: 1.06),
                   WS(s: 3.31, le: 15.0, te: 20.59, t: 0.1, y: 1.06)], side: side, chord: 10, sub: 3) { f in inTrough(f) ? trough : skin(f) }
      let tail = finFrame(p, x: 2.42, y: 1.45, cant: 0.873, side: side)
      tails.append(wingSkin(tail, [WS(s: -0.3, le: 16.05, te: 20.65, t: 0.26, y: 0), WS(s: 0, le: 16.2, te: 20.6, t: 0.26, y: 0),
                                   WS(s: 3.55, le: 18.36, te: 19.1, t: 0.06, y: 0)], side: side, chord: 9, sub: 5, skin: skin))
    }
    navLights(p, x: 6.75, y: 1.0, z: 12.1)
    for w in wings {
      wingLines(w, [[SIMD2(2.4, w.z(2.4, 0.1)), SIMD2(6.5, w.z(6.5, 0.12))],
                    [SIMD2(2.6, w.z(2.6, 1)), SIMD2(2.6, w.z(2.6, 0.82)), SIMD2(4.6, w.z(4.6, 0.8)), SIMD2(4.6, w.z(4.6, 1))],
                    [SIMD2(4.7, w.z(4.7, 1)), SIMD2(4.7, w.z(4.7, 0.78)), SIMD2(6.4, w.z(6.4, 0.74)), SIMD2(6.4, w.z(6.4, 1))]],
                width: 0.035, line, lower: true)
    }
    for t in tails {
      wingLines(t, [[SIMD2(3.15, t.z(3.15, 0.05)), SIMD2(3.15, t.z(3.15, 0.95))]], width: 0.2, marking, upper: true, lower: true)
      wingLines(t, [[SIMD2(0.2, t.z(0.2, 1)), SIMD2(0.2, t.z(0.2, 0.7)), SIMD2(2.9, t.z(2.9, 0.62)), SIMD2(2.9, t.z(2.9, 1))]],
                width: 0.03, line, upper: true, lower: true)
    }
    let d = Drape(p)
    // Tiled trough walls and floor, and the nozzle exit edge.
    var tiles: [[SIMD2<Float>]] = [[SIMD2(0.49, 16.9), SIMD2(0.49, 20.3)], [SIMD2(1.61, 16.9), SIMD2(1.61, 20.2)]]
    decalLines(p, d, tiles, width: 0.06, tile)
    tiles = []
    for k in 0..<10 { let z = 17.5 + Float(k) * 0.3; tiles.append([SIMD2(0.55, z), SIMD2(1.55, z)]) }
    tiles.append([SIMD2(1.05, 17.5), SIMD2(1.05, 20.2)])
    decalLines(p, d, tiles, width: 0.025, tileLine)
    decalLines(p, d, [[SIMD2(0.55, 17.45), SIMD2(1.05, 16.95), SIMD2(1.55, 17.45)]], width: 0.07, tile)
    decalLines(p, d, [[SIMD2(0.75, 8.8), SIMD2(0.7, 15.5)], [SIMD2(0.3, 6.2), SIMD2(0.3, 7.4), SIMD2(-0.3, 7.4), SIMD2(-0.3, 6.2)],
                      [SIMD2(0, 2.9), SIMD2(0.5, 2.9)], rectLine(0.25, 11.0, 0.55, 12.6)], width: 0.03, line)
    insignia(p, d, x: -4.4, z: 11.3, r: 0.42, marking, star: base)
    insignia(p, d, x: 0.0, z: 9.6, r: 0.22, marking, star: base)
  }
}

// F-16C Fighting Falcon: 15.1 m long, 9.96 m span over the wingtip
// missiles, measured from the 3-view. Ogive radome with pitot, frameless
// bubble canopy, curved LERX into a 40-degree cropped delta with
// flaperons, chin intake with a deep duct, tall fin with dorsal fillet and
// rudder, anhedral stabilisers, ventral fins, speed brakes, AIM-9s on the
// tip rails; two-tone grey with a darker radome and spine.
func f16() -> SCNNode {
  let L: Float = 15.06
  let medium = jetPaint("paint", 0x2A3035), dark = jetPaint("camo", 0x1A1D20), radome = jetPaint("radome", 0x131517)
  let line = material("panel", 0x111315, rough: 0.7), marking = material("marking", 0x14171A, rough: 0.6)
  let nozzle = material("nozzle", 0x3A3632, metal: 0.6, rough: 0.45), nozzle2 = material("nozzle-petal", 0x2C2926, metal: 0.6, rough: 0.5)
  let frame = material("frame", 0x1A1D20, rough: 0.6)
  return fighter(length: L) { p in
    func skin(_ f: Facet) -> SCNMaterial {
      let z = f.p.z + L / 2
      return f.u < 0 && z < 2.55 ? radome : medium
    }
    let body: [(Float, Float, Float, Float, Float)] = [ // z, half width, bottom, top, widest
      (0.4, 0.03, 0.5, 0.56, 0.5), (1.13, 0.3, 0.38, 0.95, 0.5), (1.88, 0.48, 0.32, 1.12, 0.5), (2.64, 0.56, 0.3, 1.3, 0.48),
      (3.4, 0.6, 0.32, 1.42, 0.45), (4.6, 0.6, 0.45, 1.5, 0.42), (6.5, 0.62, 0.55, 1.78, 0.42), (8.0, 0.62, 0.55, 1.66, 0.45),
      (10.0, 0.62, 0.45, 1.62, 0.45), (12.0, 0.66, 0.22, 1.7, 0.5), (13.3, 0.64, 0.3, 1.58, 0.5), (13.85, 0.62, 0.32, 1.52, 0.5),
    ]
    jetBody(p, body.map { Ring(z: $0.0, half: ovalHalf($0.1, $0.2, $0.3, n: 2.3, count: 13, widest: $0.4)) },
            step: 0.16, capStart: radome, capEnd: medium, skin: skin)
    // Chin intake: the lower lip juts forward, a deep duct behind it.
    let mouth = ovalHalf(0.78, 0.0, 0.86, n: 2.8, count: 9, widest: 0.62)
    var lipRing: [V3] = mouth.map { V3($0.x, $0.y, 4.5 + 0.38 * ($0.y / 0.86)) }
    for i in stride(from: mouth.count - 2, through: 1, by: -1) { lipRing.append(V3(-mouth[i].x, mouth[i].y, 4.5 + 0.38 * (mouth[i].y / 0.86))) }
    let trunk: [(Float, Float, Float, Float)] = [(5.2, 0.76, 0.0, 0.88), (7.0, 0.72, 0.0, 0.88), (9.5, 0.66, 0.05, 0.92), (11.5, 0.6, 0.2, 0.92), (12.8, 0.5, 0.35, 0.92)]
    var rows: [[V3]] = [lipRing]
    for t in trunk {
      let h = ovalHalf(t.1, t.2, t.3, n: 2.8, count: 9, widest: 0.62)
      var ring = h.map { V3($0.x, $0.y, t.0) }
      for i in stride(from: h.count - 2, through: 1, by: -1) { ring.append(V3(-h[i].x, h[i].y, t.0)) }
      rows.append(ring)
    }
    let flags = [Bool](repeating: false, count: lipRing.count)
    gridSkin(p, rows: rows, crease: flags, skin: skin)
    let c = lipRing.reduce(V3(0, 0, 0), +) / Float(lipRing.count)
    gridSkin(p, rows: [lipRing, lipRing.map { c + ($0 - c) * 0.78 + V3(0, 0, 1.5) }], crease: flags, inward: true, capEnd: jetIntake) { _ in jetIntake }
    jetCanopy(p, [(2.9, 0.05, 1.32, 1.36), (3.4, 0.38, 1.28, 1.8), (4.2, 0.48, 1.3, 2.12), (4.9, 0.48, 1.36, 2.19),
                  (5.7, 0.4, 1.45, 2.08), (6.5, 0.12, 1.65, 1.82)], canopyGold)
    // The canopy's only frame: the bow at its rear.
    jetBody(p, [Ring(z: 5.95, half: ovalHalf(0.43, 1.42, 2.06, n: 2.1, count: 11, widest: 0.22)),
                Ring(z: 6.12, half: ovalHalf(0.41, 1.45, 2.04, n: 2.1, count: 11, widest: 0.22))], step: 0.1) { _ in frame }
    tube(p, V3(0, 0.53, 0), V3(0, 0.53, 0.45), 0.022, line)   // pitot
    for side in [-1, 1] as [Float] {
      tube(p, V3(side * 0.36, 0.72, 1.55), V3(side * 0.52, 0.72, 1.62), 0.015, line)   // AoA probes
      box(p, 0.02, 0.12, 0.2, line, side * 0.12, 1.24, 2.45)                          // IFF blades
      // Leading-edge root extension curving into the wing (outline from the 3-view).
      wingSkin(p, [WS(s: 0.55, le: 2.8, te: 9.5, t: 0.36, y: 0.98), WS(s: 0.72, le: 3.39, te: 9.5, t: 0.3, y: 0.98),
                   WS(s: 0.8, le: 4.14, te: 9.5, t: 0.24, y: 0.98), WS(s: 0.87, le: 4.89, te: 9.5, t: 0.2, y: 0.98),
                   WS(s: 0.94, le: 5.27, te: 9.5, t: 0.17, y: 0.98), WS(s: 1.03, le: 5.65, te: 9.5, t: 0.14, y: 0.98),
                   WS(s: 1.13, le: 6.02, te: 9.5, t: 0.12, y: 0.98), WS(s: 1.25, le: 6.4, te: 9.5, t: 0.1, y: 0.98),
                   WS(s: 1.35, le: 6.8, te: 9.5, t: 0.08, y: 0.98), WS(s: 1.5, le: 7.57, te: 9.5, t: 0.07, y: 0.98)],
               side: side, chord: 6, sub: 1, skin: skin)
      // Cropped delta: 40-degree leading edge, straight trailing edge.
      let w = wingSkin(p, [WS(s: 0.6, le: 6.7, te: 11.59, t: 0.24, y: 0.98), WS(s: 1.5, le: 7.57, te: 11.59, t: 0.2, y: 0.98),
                           WS(s: 4.4, le: 9.9, te: 11.59, t: 0.05, y: 0.98)], side: side, chord: 9, sub: 5, skin: skin)
      wingLines(w, [[SIMD2(1.55, w.z(1.55, 0.14)), SIMD2(4.35, w.z(4.35, 0.16))],
                    [SIMD2(1.55, 11.59), SIMD2(1.55, 10.75), SIMD2(3.65, 10.95), SIMD2(3.65, 11.59)]], width: 0.03, line, lower: true)
      // Aft strakes and the stabilisers, 10 degrees of anhedral.
      wingSkin(p, [WS(s: 0.55, le: 11.3, te: 13.3, t: 0.12, y: 0.98), WS(s: 1.13, le: 11.9, te: 13.0, t: 0.04, y: 0.98)],
               side: side, chord: 5, sub: 1, skin: skin)
      wingSkin(p, [WS(s: 0.7, le: 12.5, te: 15.06, t: 0.16, y: 0.96), WS(s: 1.45, le: 13.18, te: 15.06, t: 0.14, y: 0.83),
                   WS(s: 2.85, le: 14.45, te: 15.06, t: 0.05, y: 0.58), WS(s: 3.02, le: 14.65, te: 14.95, t: 0.04, y: 0.55)],
               side: side, chord: 7, sub: 3, skin: skin)
      // Speed brake housings either side of the nozzle.
      wingSkin(p, [WS(s: 0.55, le: 13.2, te: 14.95, t: 0.16, y: 0.96), WS(s: 1.05, le: 13.3, te: 14.9, t: 0.12, y: 0.96)],
               side: side, chord: 4, sub: 1, skin: skin)
      // Ventral fins, canted 15 degrees out.
      let ventral = holder(p, V3(side * 0.62, 0.3, 0), rz: -side * (.pi / 2 - 0.26))
      wingSkin(ventral, [WS(s: -0.15, le: 11.9, te: 13.3, t: 0.06, y: 0), WS(s: 0, le: 12.0, te: 13.25, t: 0.06, y: 0),
                         WS(s: 0.68, le: 12.55, te: 13.2, t: 0.03, y: 0)], side: side, chord: 4, sub: 1, skin: skin)
      // Wingtip launch rail and AIM-9X.
      box(p, 0.1, 0.1, 2.3, medium, side * 4.47, 0.98, 10.45)
      box(p, 0.06, 0.08, 1.6, medium, side * 4.6, 0.93, 10.45)
      let mx = side * 4.72, my: Float = 0.88
      tube(p, V3(mx, my, 8.9), V3(mx, my, 11.55), 0.064, missileGrey)
      let noseCone = holder(p, V3(mx, my, 8.9), rx: -.pi / 2)
      put(noseCone, LatheMesh([SIMD2(0, 0.064), SIMD2(0.22, 0.04), SIMD2(0.36, 0.0)], sides: 10, caps: false), missileGrey, 0, 0, 0)
      for a in [Float.pi / 4, -Float.pi / 4] {
        box(p, 0.34, 0.012, 0.3, missileGrey, mx, my, 11.35, rz: a)
        box(p, 0.2, 0.012, 0.12, missileGrey, mx, my, 9.3, rz: a)
      }
    }
    // Fin with its dorsal fillet, base fairing and rudder.
    let fin = holder(p, V3(0, 1.6, 0), rz: .pi / 2)
    let f = wingSkin(fin, [WS(s: -0.2, le: 9.4, te: 15.2, t: 0.3, y: 0), WS(s: 0, le: 9.6, te: 15.15, t: 0.3, y: 0),
                           WS(s: 0.58, le: 11.8, te: 15.15, t: 0.26, y: 0), WS(s: 0.62, le: 11.85, te: 14.5, t: 0.24, y: 0),
                           WS(s: 2.78, le: 14.0, te: 15.2, t: 0.06, y: 0)], side: 1, chord: 8, sub: 3, skin: skin)
    wingLines(f, [[SIMD2(0.66, 14.5), SIMD2(0.66, 13.75), SIMD2(2.55, 14.6), SIMD2(2.55, 15.18)]], width: 0.03, line, upper: true, lower: true)
    tailCode(f, "HL", s: 1.5, z: 13.0, height: 0.42, marking, upperFace: false, readAft: false)
    tailCode(f, "HL", s: 1.5, z: 13.0, height: 0.42, marking, upperFace: true, readAft: true)
    roundNozzle(p, x: 0, y: 0.96, z0: 13.8, z1: 15.06, r0: 0.68, r1: 0.46, teeth: 15, depth: 0.04, nozzle, inner: jetExhaust, petals: nozzle2)
    tube(p, V3(0, 0.3, 12.4), V3(0, 0.22, 13.5), 0.035, line) // tail hook
    let d = Drape(p)
    // Darker grey over the spine and the strakes, softly demarcated.
    decalField(p, d, x0: -1.6, x1: 1.6, z0: 2.4, z1: 14.0, cell: 0.1, { x, z in
      if abs(x) < 0.52 && z > 2.8 && z < 6.6 { return -1 }
      return min(1.0 + 0.12 * sin(z * 1.7) - abs(x), (z - 2.6) * 2, (13.6 - z) * 2)
    }, dark)
    decalLines(p, d, [[SIMD2(0.35, 6.8), SIMD2(0.35, 12.0)], [SIMD2(0.62, 7.2), SIMD2(0.66, 12.6)], rectLine(0.0, 8.4, 0.28, 9.4),
                      [SIMD2(0.0, 2.55), SIMD2(0.6, 2.55)], [SIMD2(1.0, 7.8), SIMD2(1.3, 9.4)]], width: 0.025, line)
    decalPatches(p, d, [[SIMD2(-0.09, 7.25), SIMD2(0.09, 7.25), SIMD2(0.09, 7.6), SIMD2(-0.09, 7.6)],
                        [SIMD2(-0.66, 4.55), SIMD2(-0.56, 4.55), SIMD2(-0.56, 4.8), SIMD2(-0.66, 4.8)]], line)
    insignia(p, d, x: -3.0, z: 10.5, r: 0.36, marking, star: medium)
  }
}

func hotAirBalloon(envelope: UInt32) -> SCNNode {
  let root = SCNNode()
  // Envelope: a vertical loft (built along Z, turned upright).
  let profile: [(Float, Float)] = [(0, 1.1), (2.5, 2.6), (5.5, 5.2), (9, 7.6), (12.5, 8.7), (15.5, 8.4), (18, 6.6), (19.8, 3.6), (20.6, 0.6)]
  let env = loft(profile.map { Station(z: $0.0, width: $0.1 * 2, bottom: -$0.1, top: $0.1, n: 2) }, segments: 32, paint(envelope))
  env.simdOrientation = simd_quatf(angle: -.pi / 2, axis: V3(1, 0, 0))
  env.simdPosition = V3(0, 3.8, 0)
  root.addChildNode(env)
  // Coloured gores (vertical stripes).
  let stripe = material("gore", 0xFFFFFF, rough: 0.6)
  for i in 0..<8 {
    let a = Float(i) / 8 * 2 * .pi
    for k in 0..<(profile.count - 1) {
      let (h0, r0) = profile[k], (h1, r1) = profile[k + 1]
      tube(root, V3(cos(a) * r0 * 1.004, 3.8 + h0, sin(a) * r0 * 1.004), V3(cos(a) * r1 * 1.004, 3.8 + h1, sin(a) * r1 * 1.004), 0.14, stripe, sides: 6)
    }
  }
  // Burner frame, ropes, wicker basket.
  box(root, 1.4, 1.1, 1.4, wood, 0, 0.55, 0)
  for (x, z) in [(-0.65, -0.65), (0.65, -0.65), (-0.65, 0.65), (0.65, 0.65)] as [(Float, Float)] {
    tube(root, V3(x, 1.1, z), V3(x * 2.0, 3.85, z * 2.0), 0.02, black, sides: 4)
  }
  put(root, CylinderMesh(radius: 0.3, height: 0.35), chrome, 0, 2.6, 0)
  return root
}


// MARK: Rockets
// Built lying along +Z (z = height above the pad), then stood up.

func standUp(_ node: SCNNode) -> SCNNode {
  let holder = SCNNode()
  node.simdOrientation = simd_quatf(angle: -.pi / 2, axis: V3(1, 0, 0))
  holder.addChildNode(node)
  return holder
}

let steel = material("steel", 0xDCDFE2, metal: 0.65, rough: 0.32)
let tile = material("heat-shield", 0x17181A, rough: 0.8)
let rocketWhite = material("white", 0xF4F4F2, metal: 0.1, rough: 0.5)
let foam = material("tank-foam", 0xC8692B, rough: 0.85)
let engineBell = material("engine", 0x3B3D40, metal: 0.8, rough: 0.35)

// starshipStack() is built with the Starbase pad models further down.

let carbon = material("interstage", 0x1D1E20, metal: 0.2, rough: 0.6)
let gridTi = material("grid-fin", 0x6E7175, metal: 0.8, rough: 0.4)
let f9Soot = material("f9-soot", 0x3A3836, rough: 0.9)
let merlin = material("engine", 0x2E2C2A, metal: 0.7, rough: 0.45)

/// A band of a lying rocket body from z0 to z1 at radius r, optionally only
/// part of the way round (a0...a1 radians) — paint patterns and seams.
func bodyBand(_ p: SCNNode, _ z0: Float, _ z1: Float, r: Float, _ m: SCNMaterial, from a0: Float = 0, to a1: Float = 2 * .pi, sides: Int = 40) {
  put(p, LatheMesh([SIMD2(z0, r), SIMD2(z1, r)], sides: sides, caps: false, from: a0, to: a1), m, 0, 0, 0, rx: .pi / 2)
}

/// A rocket engine bell pointing down (-Z) from z, throat radius rt, exit
/// radius re, length l.
func bell(_ p: SCNNode, x: Float, y: Float, z: Float, rt: Float, re: Float, l: Float, _ m: SCNMaterial) {
  let prof: [SIMD2<Float>] = (0...8).map { i in
    let t = Float(i) / 8
    return SIMD2(-l * t, rt + (re - rt) * pow(t, 0.7))
  }
  put(p, LatheMesh(prof.reversed(), sides: 20, caps: false, twoSided: true), m, x, y, z, rx: .pi / 2)
}

// Falcon 9 Block 5 (70 m, 3.66 m): first stage with the octaweb and nine
// Merlins, four folded carbon landing legs, soot staining, the raceway;
// black carbon interstage with four titanium grid fins; second stage;
// 5.2 m fairing with its seam.
func falcon9() -> SCNNode {
  let r = SCNNode()
  let R: Float = 1.83
  bodyBand(r, 0, 41.2, r: R, rocketWhite)
  bodyBand(r, 0, 6.0, r: R + 0.005, f9Soot, from: 0.3, to: 2.6)
  bodyBand(r, 41.2, 47.7, r: R + 0.01, carbon)
  bodyBand(r, 47.7, 60.6, r: R, rocketWhite)
  put(r, LatheMesh([SIMD2(60.1, R), SIMD2(61.2, 2.6), SIMD2(66.6, 2.6), SIMD2(68.5, 2.4), SIMD2(70.5, 1.7), SIMD2(72.0, 0.85), SIMD2(72.6, 0.3), SIMD2(72.7, 0.001)],
                   sides: 40), rocketWhite, 0, 0, 0, rx: .pi / 2)
  rod(r, V3(0, 2.61, 61.2), V3(0, 2.61, 72.0), 0.03, slat, sides: 4)
  rod(r, V3(0, -2.61, 61.2), V3(0, -2.61, 72.0), 0.03, slat, sides: 4)
  box(r, 0.25, 0.18, 39.5, rocketWhite, R + 0.07, 0, 21.0)
  // Octaweb base and nine Merlins.
  put(r, CylinderMesh(radius: CGFloat(R), height: 0.2, sides: 32), merlin, 0, 0, 0.0, rx: .pi / 2)
  for i in 0..<9 {
    let a = Float(i) / 8 * 2 * .pi
    let rr: Float = i == 8 ? 0 : 1.25
    bell(r, x: cos(a) * rr, y: sin(a) * rr, z: 0, rt: 0.18, re: 0.46, l: 1.1, merlin)
  }
  // Landing legs (folded) and grid fins.
  for k in 0..<4 {
    let a = Float(k) * .pi / 2 + .pi / 4
    let c = holder(r, V3(0, 0, 0), rz: a)
    motoBody(c, [(0.4, 0.3, R - 0.02, R + 0.22), (1.5, 0.4, R - 0.02, R + 0.3), (9.0, 0.32, R - 0.02, R + 0.18), (10.0, 0.18, R - 0.02, R + 0.08)],
             step: 0.3, rb: 0.3, rt: 0.5, cap: carbon) { _ in carbon }
    let g = holder(r, V3(0, 0, 0), rz: a - .pi / 4)
    box(g, 0.25, 0.3, 0.6, carbon, R + 0.12, 0, 45.8)
    for i in 0..<6 { box(g, 0.04, 1.6, 0.14, gridTi, R + 0.35 + Float(i) * 0.24, 0, 46.2, rz: .pi / 2) }
    box(g, 1.4, 0.06, 0.12, gridTi, R + 0.95, 0, 45.6)
    box(g, 1.4, 0.06, 0.12, gridTi, R + 0.95, 0, 46.8)
  }
  return spacecraft { root in root.addChildNode(standUp(r)) }
}

// Saturn V (110.6 m, 10.1 m): S-IC with its black-and-white roll pattern,
// four fins and engine fairings over five F-1s; S-II with the interstage;
// S-IVB with the black aft skirt and the "ullage" stripes; instrument
// unit, spacecraft adapter, service module, command module and the launch
// escape tower.
func saturnV() -> SCNNode {
  let r = SCNNode()
  let R: Float = 5.05
  bodyBand(r, 0, 42, r: R, rocketWhite)
  // Roll pattern: black quarters at the base, alternating with the top.
  for k in 0..<4 {
    let a0 = Float(k) * .pi / 2
    if k % 2 == 0 { bodyBand(r, 0, 8, r: R + 0.01, tile, from: a0, to: a0 + .pi / 2) }
    if k % 2 == 1 { bodyBand(r, 33, 42, r: R + 0.01, tile, from: a0, to: a0 + .pi / 2) }
    bodyBand(r, 18.5, 19.5, r: R + 0.01, tile, from: a0 + .pi / 8, to: a0 + .pi / 8 + 0.3)
  }
  // Fins and engine fairings.
  for k in 0..<4 {
    let a = Float(k) * .pi / 2 + .pi / 4
    let c = holder(r, V3(0, 0, 0), rz: a)
    motoBody(c, [(-3.0, 1.0, R - 1.0, R + 0.6), (0.5, 1.1, R - 0.8, R + 0.9), (5.0, 0.7, R - 0.5, R + 0.4), (7.5, 0.1, R - 0.1, R + 0.02)],
             step: 0.3, rb: 0.6, rt: 0.6, cap: rocketWhite) { _ in rocketWhite }
    strut(c, V3(R + 0.6, 0, -2.5), V3(R + 3.6, 0, -1.8), 0.25, 0.25, rocketWhite, up: V3(0, 1, 0))
    wingSkin(c, [WS(s: R + 0.8, le: -2.6, te: 3.0, t: 0.3, y: 0), WS(s: R + 3.6, le: -2.4, te: -0.6, t: 0.15, y: 0)], side: 1, chord: 5, sub: 1) { _ in rocketWhite }
    bell(r, x: cos(a) * 3.3, y: sin(a) * 3.3, z: 0, rt: 0.6, re: 1.85, l: 5.6, engineBell)
  }
  bell(r, x: 0, y: 0, z: 0, rt: 0.6, re: 1.85, l: 5.6, engineBell)
  // S-II and interstage, S-IVB, IU, SLA, CSM, LES.
  bodyBand(r, 42, 47.5, r: R + 0.02, rocketWhite)
  bodyBand(r, 44.6, 45.2, r: R + 0.04, tile)
  bodyBand(r, 47.5, 66.7, r: R, rocketWhite)
  put(r, LatheMesh([SIMD2(66.7, R), SIMD2(72.2, 3.3)], sides: 40, caps: false), rocketWhite, 0, 0, 0, rx: .pi / 2)
  bodyBand(r, 72.2, 74.8, r: 3.31, tile)
  bodyBand(r, 74.8, 90.0, r: 3.3, rocketWhite)
  for k in 0..<4 { let a0 = Float(k) * .pi / 2; bodyBand(r, 82.0, 88.0, r: 3.31, tile, from: a0 + 0.2, to: a0 + 0.45) }
  bodyBand(r, 90.0, 91.0, r: 3.31, slat)
  put(r, LatheMesh([SIMD2(91.0, 3.3), SIMD2(99.4, 1.96)], sides: 40, caps: false), rocketWhite, 0, 0, 0, rx: .pi / 2)
  bodyBand(r, 99.4, 103.3, r: 1.96, foilSilver)
  put(r, LatheMesh([SIMD2(103.3, 1.96), SIMD2(106.5, 0.45), SIMD2(106.9, 0.001)], sides: 32), rocketWhite, 0, 0, 0, rx: .pi / 2)
  for k in 0..<4 {
    let a = Float(k) * .pi / 2 + .pi / 4
    rod(r, V3(cos(a) * 0.5, sin(a) * 0.5, 106.4), V3(cos(a) * 0.25, sin(a) * 0.25, 108.6), 0.04, lightRed, sides: 4)
  }
  put(r, LatheMesh([SIMD2(108.6, 0.32), SIMD2(110.0, 0.3), SIMD2(110.6, 0.001)], sides: 16), lightRed, 0, 0, 0, rx: .pi / 2)
  return spacecraft { root in root.addChildNode(standUp(r)) }
}

let rcc = material("rcc", 0x4A4C4F, rough: 0.6)
let tileWhite = material("white", 0xF1F1EE, metal: 0.05, rough: 0.6)
let intertankFoam = material("intertank", 0xB65E25, rough: 0.9)
let srbJoint = material("srb-joint", 0x9EA2A6, metal: 0.3, rough: 0.5)

/// The Space Shuttle orbiter, built in its own frame: nose at z = 0 running
/// aft along +Z to the engine bells at 35.5 m, belly on y = 0, 23.8 m
/// span. Lofted fuselage with the crew cabin hump, payload bay doors, OMS
/// pods, double-delta wing (81-degree strakes, 45-degree main panels) and
/// the swept fin with its split rudder; black tiles below, grey RCC on the
/// nose cap and leading edges, three main engines and the body flap.
func orbiter() -> SCNNode {
  let o = SCNNode()
  let c = 15
  jetBody(o, [
    Ring(z: 0, half: noseTip(1.55, c)),
    Ring(z: 0.6, half: ovalHalf(0.78, 0.55, 2.45, n: 2.2, count: c, widest: 0.3)),
    Ring(z: 2.0, half: ovalHalf(1.6, 0.15, 3.75, n: 2.4, count: c, widest: 0.28)),
    Ring(z: 4.0, half: ovalHalf(2.2, 0.03, 4.95, n: 2.6, count: c, widest: 0.28)),
    Ring(z: 6.0, half: ovalHalf(2.5, 0.0, 5.8, n: 2.8, count: c, widest: 0.28)),
    Ring(z: 7.6, half: ovalHalf(2.6, 0.0, 5.55, n: 3.2, count: c, widest: 0.3)),
    Ring(z: 9.0, half: ovalHalf(2.62, 0.0, 5.3, n: 3.5, count: c, widest: 0.3)),
    Ring(z: 25.0, half: ovalHalf(2.62, 0.0, 5.3, n: 3.5, count: c, widest: 0.3)),
    Ring(z: 28.5, half: ovalHalf(2.58, 0.05, 5.2, n: 3.5, count: c, widest: 0.3)),
    Ring(z: 32.3, half: ovalHalf(2.42, 0.18, 4.95, n: 3.5, count: c, widest: 0.3)),
  ], step: 0.3, capEnd: engineDark) { f in
    if f.p.z < 1.05 { return rcc }
    if f.n.y < -0.3 { return tile }
    if f.p.y < 0.6 && f.n.y < 0.25 { return tile }
    if f.p.z < 6.2 && f.p.y > 3.6 && f.p.y < 5.2 && f.n.z < -0.15 && f.n.y > 0.1 { return tile }
    return tileWhite
  }
  // Wings: strake, main panel, cropped tip.
  var wings: [WingSurface] = []
  for side in [-1, 1] as [Float] {
    wings.append(wingSkin(o, [WS(s: 2.2, le: 12.0, te: 32.3, t: 1.5, y: 0.78), WS(s: 4.6, le: 21.5, te: 32.3, t: 1.2, y: 0.72),
                              WS(s: 11.6, le: 28.6, te: 32.0, t: 0.45, y: 0.66), WS(s: 11.9, le: 29.4, te: 31.9, t: 0.3, y: 0.66)],
                          side: side, chord: 10, sub: 4) { f in
      if f.u >= 0 && f.u < 0.05 { return rcc }
      return f.n.y < 0 ? tile : tileWhite
    })
  }
  for w in wings {
    wingLines(w, [[SIMD2(3.0, w.z(3.0, 0.86)), SIMD2(7.3, w.z(7.3, 0.86)), SIMD2(7.3, w.z(7.3, 1))],
                  [SIMD2(7.45, w.z(7.45, 1)), SIMD2(7.45, w.z(7.45, 0.85)), SIMD2(11.4, w.z(11.4, 0.8)), SIMD2(11.4, w.z(11.4, 1))]],
              width: 0.06, tile)
  }
  // Fin with the rudder/speed brake.
  let finF = finFrame(o, x: 0, y: 5.15, cant: 0, side: 1)
  let fin = wingSkin(finF, [WS(s: -0.2, le: 25.0, te: 33.8, t: 0.65, y: 0), WS(s: 7.9, le: 32.7, te: 36.9, t: 0.25, y: 0)], side: 1, chord: 9, sub: 3) { f in
    f.u >= 0 && f.u < 0.04 ? rcc : tileWhite
  }
  wingLines(fin, [[SIMD2(0.6, 33.0), SIMD2(7.6, 34.9)]], width: 0.06, tile, upper: true, lower: true)
  // OMS pods with their engines.
  for side in [-1, 1] as [Float] {
    motoBody(o, [(25.0, 0.05, 4.5, 4.7), (26.6, 0.78, 3.95, 5.75), (31.0, 0.88, 3.85, 5.95), (32.9, 0.72, 3.95, 5.6)], x: side * 1.72,
             step: 0.2, rb: 0.6, rt: 0.6, cap: engineDark) { f in f.p.z < 26.8 && f.n.z < -0.3 ? tile : tileWhite }
    put(o, LatheMesh([SIMD2(0, 0.28), SIMD2(0.25, 0.22), SIMD2(1.1, 0.5)], sides: 18, caps: false, twoSided: true), engineBell,
        side * 1.72, 4.85, 32.85, rx: .pi / 2)
  }
  // Main engines and body flap.
  for (x, y) in [(Float(0), Float(3.8)), (-1.35, 1.95), (1.35, 1.95)] {
    put(o, LatheMesh([SIMD2(0, 0.62), SIMD2(0.35, 0.36), SIMD2(1.0, 0.72), SIMD2(2.0, 1.02), SIMD2(3.1, 1.18)], sides: 24, caps: false, twoSided: true),
        engineBell, x, y, 32.3, rx: .pi / 2)
    put(o, CylinderMesh(radius: 0.5, height: 0.6, sides: 16), engineDark, x, y, 32.4, rx: .pi / 2)
  }
  motoBody(o, [(32.2, 2.1, 0.12, 0.62), (34.2, 2.1, 0.2, 0.42)], step: 0.2, rb: 0.1, rt: 0.1, cap: tile) { f in f.n.y < 0 ? tile : tileWhite }
  // Windows, payload bay door seams, RCS ports.
  let up = Drape(o, axis: 1)
  var panes: [[SIMD2<Float>]] = []
  for side in [-1, 1] as [Float] {
    for (x0, x1) in [(0.18, 0.75), (0.85, 1.4), (1.5, 1.95)] as [(Float, Float)] {
      let z0: Float = 3.95 + x0 * 0.12, z1: Float = 4.75 + x1 * 0.02
      panes.append(side > 0 ? [SIMD2(x0, z0), SIMD2(x1, z0 + 0.1), SIMD2(x1, z1), SIMD2(x0, z1)] : [SIMD2(-x1, z0 + 0.1), SIMD2(-x0, z0), SIMD2(-x0, z1), SIMD2(-x1, z1)])
    }
    panes.append(side > 0 ? [SIMD2(0.25, 5.35), SIMD2(0.75, 5.35), SIMD2(0.75, 5.75), SIMD2(0.25, 5.75)] :
                   [SIMD2(-0.75, 5.35), SIMD2(-0.25, 5.35), SIMD2(-0.25, 5.75), SIMD2(-0.75, 5.75)])
  }
  decalPatches(o, up, panes.map { rounded($0, r: 0.06) }, glass, lift: 0.02, k: 4)
  decalLines(o, up, [[SIMD2(0, 7.6), SIMD2(0, 25.2)]] + (0..<5).map { i in let z = 7.6 + Float(i + 1) * 3.5; return [SIMD2(-2.2, z), SIMD2(2.2, z)] },
             width: 0.04, slat, mirror: false, lift: 0.015)
  decalLines(o, up, [[SIMD2(2.2, 7.6), SIMD2(2.2, 25.2)]], width: 0.05, slat, mirror: true, lift: 0.015)
  decalPatches(o, up, [rounded([SIMD2(0.3, 8.0), SIMD2(2.0, 8.0), SIMD2(2.0, 16.0), SIMD2(0.3, 16.0)], r: 0.1)], material("radiator", 0xDDE3E8, metal: 0.4, rough: 0.3),
               mirror: true, lift: 0.01)
  return o
}

// Space Shuttle stack at launch: orbiter (above), 46.9 m external tank
// (LH2 tank, ribbed intertank, ogive LO2 tank with its spike, LO2 feedline
// and cable tray, bipod and aft attach struts) and two 45.5 m solid
// rocket boosters (nose caps, frustums, forward skirts, segment joints,
// ET attach rings, flared aft skirts, nozzles).
func shuttleStack() -> SCNNode {
  let r = SCNNode()
  let R: Float = 4.2
  // External tank: aft dome, LH2 tank, intertank, LO2 tank ogive and spike.
  put(r, LatheMesh((0...6).map { i in let a = Float(i) / 6 * .pi / 2; return SIMD2(-1.6 * cos(a), R * sin(a) + 0.001) }, sides: 40), foam, 0, 0, 0, rx: .pi / 2)
  put(r, LatheMesh([SIMD2(0, R), SIMD2(29.0, R)], sides: 40, caps: false), foam, 0, 0, 0, rx: .pi / 2)
  put(r, LatheMesh([SIMD2(29.0, R + 0.02), SIMD2(35.6, R + 0.02)], sides: 40, caps: false), intertankFoam, 0, 0, 0, rx: .pi / 2)
  for i in 0..<36 {
    let a = Float(i) / 36 * 2 * .pi
    box(r, 0.12, 0.08, 6.6, intertankFoam, cos(a) * (R + 0.04), sin(a) * (R + 0.04), 32.3, rz: a)
  }
  let ogive: [SIMD2<Float>] = (0...14).map { i in
    let t = Float(i) / 14
    return SIMD2(35.6 + t * 11.0, max(0.25, R * pow(1 - t, 0.62) * (1 - 0.08 * t)))
  }
  put(r, LatheMesh(ogive, sides: 40), foam, 0, 0, 0, rx: .pi / 2)
  tube(r, V3(0, 0, 46.5), V3(0, 0, 48.2), 0.12, rcc, sides: 10)
  // LO2 feedline and cable tray down the side facing +x.
  tube(r, V3(R * 0.72, -R * 0.69, 2.0), V3(R * 0.72, -R * 0.69, 35.6), 0.22, foam, sides: 12)
  tube(r, V3(-R * 0.98, -R * 0.2, 1.0), V3(-R * 0.98, -R * 0.2, 44.0), 0.12, foam, sides: 8)
  // Boosters.
  for s in [-1, 1] as [Float] {
    let b = SCNNode(); b.simdPosition = V3(s * 6.08, 0, 0); r.addChildNode(b)
    let br: Float = 1.855
    put(b, LatheMesh([SIMD2(-3.4, 2.6), SIMD2(-2.2, 2.3), SIMD2(-0.2, br), SIMD2(39.7, br)], sides: 32, caps: false), rocketWhite, 0, 0, 0, rx: .pi / 2)
    put(b, LatheMesh([SIMD2(39.7, br), SIMD2(41.6, br * 0.62), SIMD2(43.6, br * 0.55), SIMD2(44.8, 0.6), SIMD2(45.5, 0.001)], sides: 32), rocketWhite, 0, 0, 0,
        rx: .pi / 2)
    for z in [5.0, 13.5, 21.5, 29.5, 37.0] as [Float] {
      put(b, LatheMesh([SIMD2(z - 0.18, br + 0.04), SIMD2(z + 0.18, br + 0.04)], sides: 32, caps: true), srbJoint, 0, 0, 0, rx: .pi / 2)
    }
    put(b, LatheMesh([SIMD2(1.6, br + 0.06), SIMD2(2.3, br + 0.06)], sides: 32, caps: true), srbJoint, 0, 0, 0, rx: .pi / 2)
    put(b, LatheMesh([SIMD2(0, 1.1), SIMD2(-1.2, 1.25), SIMD2(-3.9, 1.9)], sides: 24, caps: false, twoSided: true), engineBell, 0, 0, 0, rx: .pi / 2)
    for k in 0..<4 {
      let a = Float(k) / 4 * 2 * .pi + .pi / 4
      box(b, 0.5, 0.5, 0.9, srbJoint, cos(a) * 2.45, sin(a) * 2.45, -3.0)
    }
    // Attach struts to the tank.
    for z in [3.0, 3.6, 39.0] as [Float] { rod(r, V3(s * (6.08 - br), 0, z), V3(s * R, 0, z + (z > 30 ? 0 : 0.3)), 0.14, srbJoint, sides: 6) }
  }
  // Orbiter belly-to-tank, nose up.
  let o = orbiter()
  let yOff = R + 0.95, zNose: Float = 35.6
  // Belly towards the tank, facing the front of the model (-Z once stood up).
  o.simdOrientation = simd_quatf(angle: .pi, axis: V3(0, 1, 0))
  o.simdPosition = V3(0, yOff, zNose)
  r.addChildNode(o)
  // Forward bipod and aft attach structure between belly and tank.
  for s in [-1, 1] as [Float] {
    rod(r, V3(0, yOff, zNose - 6.5), V3(s * 0.9, R, zNose - 4.5), 0.12, srbJoint, sides: 6)
    rod(r, V3(s * 1.4, yOff, zNose - 30.5), V3(s * 1.6, R * 0.96, zNose - 30.5), 0.3, srbJoint, sides: 8)
  }
  return spacecraft { root in root.addChildNode(standUp(r)) }
}

// MARK: Spacecraft
// Satellites float, so each one is built around its own centre, collapsed
// into one mesh per material (hundreds of small parts would otherwise each
// become a USD prim) and lifted so its lowest point sits on y = 0. Front
// (-Z) is the direction of travel; big flat parts (solar arrays, radiators,
// sunshields) lie in the XZ plane so they read from above.

let foilGold = material("mli-gold", 0xC8962F, metal: 0.9, rough: 0.34)
let foilAmber = material("mli-amber", 0xA8701E, metal: 0.85, rough: 0.42)
let foilSilver = material("mli-silver", 0xCDD1D6, metal: 0.95, rough: 0.24)
let cells = material("solar-cell", 0x0B1430, metal: 0.25, rough: 0.32)
let cellGrid = material("solar-grid", 0x9AA6B6, metal: 0.8, rough: 0.3)
let issCells = material("solar-iss", 0xB57C34, metal: 0.6, rough: 0.33)
let issGrid = material("solar-iss-grid", 0x4A3218, rough: 0.5)
let rosaCells = material("solar-rosa", 0x1A2236, metal: 0.3, rough: 0.3)
let panelBack = material("panel-back", 0xE4E5E3, rough: 0.55)
let radiatorWhite = material("radiator", 0xF3F4F1, metal: 0.05, rough: 0.4)
let radiatorLine = material("radiator-line", 0xA3A8AE, rough: 0.5)
let trussSilver = material("truss", 0xB9BEC4, metal: 0.85, rough: 0.3)
let dishWhite = material("dish", 0xF0F0EC, metal: 0.1, rough: 0.45)
let mirrorGold = material("mirror-gold", 0xF8C232, metal: 0.55, rough: 0.28) // fully metallic renders black without an environment map
let composite = material("composite", 0x2B2D31, metal: 0.3, rough: 0.55)
let handrail = material("handrail", 0xE3B81C, rough: 0.5)
let moduleBand = material("module-band", 0xB4B6B3, metal: 0.3, rough: 0.5)
let soyuzGreen = material("soyuz-mli", 0x7F8B72, metal: 0.2, rough: 0.7)

var rngState: UInt32 = 0x5EED
/// Deterministic noise in 0..<1, so regenerating gives the same models.
func rnd() -> Float {
  rngState = rngState &* 1664525 &+ 1013904223
  return Float(rngState >> 8) / Float(1 << 24)
}

/// A flat rectangle facing +Y (single-sided), for cell grids and decals.
func QuadMesh(width: Float, length: Float) -> SCNGeometry {
  let hx = width / 2, hz = length / 2
  return meshGeometry([V3(-hx, 0, -hz), V3(hx, 0, -hz), V3(hx, 0, hz), V3(-hx, 0, hz)],
                      Array(repeating: V3(0, 1, 0), count: 4), [0, 2, 1, 0, 3, 2])
}

/// A surface of revolution about Y. `profile` holds (height, radius) points
/// running from the bottom up the outside to the top (run it top-down for an
/// inward-facing lining). Ends with radius > 0 get flat caps when `caps` is
/// set; `from`/`to` sweep part of the way round; `twoSided` adds back faces.
func LatheMesh(_ profile: [SIMD2<Float>], sides: Int = 28, caps: Bool = true, twoSided: Bool = false,
               from a0: Float = 0, to a1: Float = 2 * .pi) -> SCNGeometry {
  var p: [V3] = [], n: [V3] = [], idx: [UInt32] = []
  let count = profile.count
  for j in 0..<count {
    let d = profile[min(count - 1, j + 1)] - profile[max(0, j - 1)]
    var nr = d.x, ny = -d.y
    let len = max(1e-6, (nr * nr + ny * ny).squareRoot())
    nr /= len; ny /= len
    for i in 0...sides {
      let a = a0 + (a1 - a0) * Float(i) / Float(sides)
      p.append(V3(cos(a) * profile[j].y, profile[j].x, sin(a) * profile[j].y))
      n.append(V3(cos(a) * nr, ny, sin(a) * nr))
    }
  }
  let row = UInt32(sides + 1)
  for j in 0..<UInt32(count - 1) {
    for i in 0..<UInt32(sides) {
      let a = j * row + i, b = (j + 1) * row + i
      idx += [a, b, a + 1, a + 1, b, b + 1]
    }
  }
  if twoSided {
    let base = UInt32(p.count)
    p += p; n += n.map { -$0 }
    let back = stride(from: 0, to: idx.count, by: 3).flatMap { [idx[$0] + base, idx[$0 + 2] + base, idx[$0 + 1] + base] }
    idx += back
  }
  if caps {
    for (k, down) in [(0, true), (count - 1, false)] where profile[k].y > 0.0001 {
      let c = UInt32(p.count)
      let y = profile[k].x, r = profile[k].y
      let normal = V3(0, down ? -1 : 1, 0)
      p.append(V3(0, y, 0)); n.append(normal)
      for i in 0...sides {
        let a = a0 + (a1 - a0) * Float(i) / Float(sides)
        p.append(V3(cos(a) * r, y, sin(a) * r)); n.append(normal)
      }
      for i in 0..<UInt32(sides) { idx += down ? [c, c + 1 + i, c + 2 + i] : [c, c + 2 + i, c + 1 + i] }
    }
  }
  return meshGeometry(p, n, idx)
}

/// A parabolic dish opening towards +Y, visible from both sides.
func DishMesh(radius: Float, depth: Float, sides: Int = 24, rings: Int = 6) -> SCNGeometry {
  let profile = (0...rings).map { k -> SIMD2<Float> in
    let t = Float(k) / Float(rings)
    return SIMD2(depth * t * t, radius * max(t, 0.001))
  }
  return LatheMesh(profile, sides: sides, caps: false, twoSided: true)
}

/// An empty node placed and rotated inside `parent`, to build parts in.
@discardableResult
func holder(_ parent: SCNNode, _ p: V3, rx: Float = 0, ry: Float = 0, rz: Float = 0) -> SCNNode {
  let n = SCNNode()
  n.simdPosition = p
  n.simdEulerAngles = V3(rx, ry, rz)
  parent.addChildNode(n)
  return n
}

/// A node at `a` whose local +Y points at `b`, and the distance between them.
func axisHolder(_ parent: SCNNode, _ a: V3, _ b: V3) -> (SCNNode, Float) {
  let n = SCNNode()
  n.simdPosition = a
  n.simdOrientation = simd_quatf(from: V3(0, 1, 0), to: simd_normalize(b - a))
  parent.addChildNode(n)
  return (n, simd_length(b - a))
}

/// A thin uncapped rod from `a` to `b`, for lattice members and booms (a
/// third of the vertices of a capped tube).
@discardableResult
func rod(_ parent: SCNNode, _ a: V3, _ b: V3, _ r: Float, _ m: SCNMaterial, sides: Int = 4) -> SCNNode {
  let (h, L) = axisHolder(parent, a, b)
  return put(h, LatheMesh([SIMD2(0, r), SIMD2(L, r)], sides: sides, caps: false), m, 0, 0, 0)
}

/// A rigid solar panel lying flat with its cells up, centred on (x, y, z):
/// `w` across X, `l` along Z, a backing sheet `t` thick, a cols x rows cell
/// grid and an edge frame.
func solarPanel(_ p: SCNNode, x: Float, y: Float, z: Float, w: Float, l: Float, cols: Int, rows: Int, t: Float,
                cell: SCNMaterial = cells, grid: SCNMaterial = cellGrid, back: SCNMaterial = panelBack,
                frame: SCNMaterial? = trussSilver) {
  box(p, w, t, l, back, x, y, z)
  let top = y + t / 2 + t * 0.2
  put(p, QuadMesh(width: w * 0.99, length: l * 0.99), cell, x, top, z)
  let lw = min(w / Float(max(1, cols)), l / Float(max(1, rows))) * 0.06
  for i in stride(from: 1, to: cols, by: 1) {
    put(p, QuadMesh(width: lw, length: l * 0.99), grid, x - w / 2 + w * Float(i) / Float(cols), top + t * 0.2, z)
  }
  for j in stride(from: 1, to: rows, by: 1) {
    put(p, QuadMesh(width: w * 0.99, length: lw), grid, x, top + t * 0.2, z - l / 2 + l * Float(j) / Float(rows))
  }
  if let f = frame {
    let e = lw * 1.6
    box(p, w + e, t * 1.6, e, f, x, y, z - l / 2)
    box(p, w + e, t * 1.6, e, f, x, y, z + l / 2)
    box(p, e, t * 1.6, l, f, x - w / 2, y, z)
    box(p, e, t * 1.6, l, f, x + w / 2, y, z)
  }
}

/// Reads an SCNGeometrySource of 3-vectors (float or double components).
func vectors(_ s: SCNGeometrySource) -> [V3] {
  var out: [V3] = []
  out.reserveCapacity(s.vectorCount)
  s.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
    for i in 0..<s.vectorCount {
      let o = s.dataOffset + i * s.dataStride
      if s.bytesPerComponent == 8 {
        out.append(V3(Float(raw.loadUnaligned(fromByteOffset: o, as: Double.self)),
                      Float(raw.loadUnaligned(fromByteOffset: o + 8, as: Double.self)),
                      Float(raw.loadUnaligned(fromByteOffset: o + 16, as: Double.self))))
      } else {
        out.append(V3(raw.loadUnaligned(fromByteOffset: o, as: Float.self),
                      raw.loadUnaligned(fromByteOffset: o + 4, as: Float.self),
                      raw.loadUnaligned(fromByteOffset: o + 8, as: Float.self)))
      }
    }
  }
  return out
}

/// Reads a triangle element's indices.
func triangleIndices(_ e: SCNGeometryElement) -> [UInt32] {
  let count = e.primitiveCount * 3
  var out: [UInt32] = []
  out.reserveCapacity(count)
  e.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
    for i in 0..<count {
      switch e.bytesPerIndex {
      case 1: out.append(UInt32(raw.load(fromByteOffset: i, as: UInt8.self)))
      case 2: out.append(UInt32(raw.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self)))
      default: out.append(raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self))
      }
    }
  }
  return out
}

/// Builds a spacecraft's parts, collapses them into one mesh per material and
/// lifts the result so its lowest point is on y = 0.
func spacecraft(_ build: (SCNNode) -> Void) -> SCNNode {
  let parts = SCNNode()
  build(parts)
  var groups: [(SCNMaterial, Mesh)] = []
  var slot: [ObjectIdentifier: Int] = [:]
  parts.enumerateHierarchy { node, _ in
    guard let g = node.geometry,
          let vs = g.sources(for: .vertex).first, let ns = g.sources(for: .normal).first else { return }
    let m = g.firstMaterial ?? black
    let t = node.simdConvertTransform(matrix_identity_float4x4, to: parts)
    let rot = simd_float3x3(V3(t.columns.0.x, t.columns.0.y, t.columns.0.z),
                            V3(t.columns.1.x, t.columns.1.y, t.columns.1.z),
                            V3(t.columns.2.x, t.columns.2.y, t.columns.2.z))
    let normalMatrix = rot.inverse.transpose
    let key = ObjectIdentifier(m)
    if slot[key] == nil { slot[key] = groups.count; groups.append((m, Mesh())) }
    let mesh = groups[slot[key]!].1
    let base = UInt32(mesh.positions.count)
    for v in vectors(vs) {
      let w = t * SIMD4<Float>(v.x, v.y, v.z, 1)
      mesh.positions.append(V3(w.x, w.y, w.z))
    }
    for v in vectors(ns) {
      let w = normalMatrix * v
      mesh.normals.append(simd_length(w) > 1e-6 ? simd_normalize(w) : V3(0, 1, 0))
    }
    for e in 0..<g.elementCount { mesh.indices += triangleIndices(g.element(at: e)).map { base + $0 } }
  }
  let minY = groups.map { $0.1.positions.map { $0.y }.min() ?? 0 }.min() ?? 0
  let root = SCNNode()
  for (m, mesh) in groups {
    mesh.positions = mesh.positions.map { V3($0.x, $0.y - minY, $0.z) }
    root.addChildNode(SCNNode(geometry: mesh.geometry(m)))
  }
  return root
}

/// A pressurised module from `a` to `b`: hull, debris-shield seams and
/// berthing rings at both ends.
func module(_ p: SCNNode, _ a: V3, _ b: V3, r: Float, _ m: SCNMaterial, bands: Int = 3) {
  let (h, L) = axisHolder(p, a, b)
  put(h, CylinderMesh(radius: CGFloat(r), height: CGFloat(L), sides: 28), m, 0, L / 2, 0)
  for i in 0..<bands {
    let y = L * (Float(i) + 0.5) / Float(bands)
    put(h, LatheMesh([SIMD2(y - 0.07, r + 0.04), SIMD2(y + 0.07, r + 0.04)], sides: 28, caps: false), moduleBand, 0, 0, 0)
  }
  for y in [Float(0), L] {
    put(h, TubeMesh(innerRadius: CGFloat(r * 0.42), outerRadius: CGFloat(r * 0.62), height: 0.3, sides: 20), trussSilver, 0, y, 0)
  }
}

/// A square box truss from x0 to x1: four longerons, a frame at every bay
/// and alternating diagonals on each face.
func lattice(_ p: SCNNode, from x0: Float, to x1: Float, y: Float, z: Float, size s: Float, bays: Int, r: Float, _ m: SCNMaterial) {
  let h = s / 2
  let corners: [SIMD2<Float>] = [SIMD2(-h, -h), SIMD2(h, -h), SIMD2(h, h), SIMD2(-h, h)] // (y, z) offsets
  for c in corners { rod(p, V3(x0, y + c.x, z + c.y), V3(x1, y + c.x, z + c.y), r, m, sides: 6) }
  for b in 0...bays {
    let x = x0 + (x1 - x0) * Float(b) / Float(bays)
    let xn = x0 + (x1 - x0) * Float(b + 1) / Float(bays)
    for k in 0..<4 {
      let a = corners[k], c = corners[(k + 1) % 4]
      rod(p, V3(x, y + a.x, z + a.y), V3(x, y + c.x, z + c.y), r * 0.7, m)
      if b < bays {
        let flip = (b + k) % 2 == 0
        rod(p, V3(flip ? x : xn, y + a.x, z + a.y), V3(flip ? xn : x, y + c.x, z + c.y), r * 0.6, m)
      }
    }
  }
}

/// Wrinkled foil: small, slightly tilted patches over a face of size w x l
/// (the face's normal is the holder's +Y).
func crinkle(_ p: SCNNode, w: Float, l: Float, count: Int, size: Float, _ m: SCNMaterial) {
  for _ in 0..<count {
    let x = (rnd() - 0.5) * (w - size), z = (rnd() - 0.5) * (l - size)
    put(p, QuadMesh(width: size * (0.5 + rnd()), length: size * (0.5 + rnd())), m, x, 0.004 + rnd() * 0.004, z,
        rx: (rnd() - 0.5) * 0.25, ry: rnd() * 3, rz: (rnd() - 0.5) * 0.25)
  }
}

// Starlink V2 mini: a flat 2.7 m x 4.1 m bus and two 13 m solar wings,
// about 30 m tip to tip.
func starlink() -> SCNNode {
  spacecraft { r in
    let bus = material("paint", 0x5F646B, metal: 0.75, rough: 0.32)
    let W: Float = 2.7, L: Float = 4.1, H: Float = 0.34
    box(r, W, H, L, bus, 0, 0, 0)
    // Zenith deck: dark radiator panels in a silver frame.
    for z in [-1.32, 0, 1.32] as [Float] {
      put(r, QuadMesh(width: W * 0.86, length: 1.2), composite, 0, H / 2 + 0.006, z)
    }
    for x in [-W / 2, W / 2] {
      box(r, 0.05, 0.05, L, foilSilver, x * 0.98, H / 2, 0)
    }
    // Three laser terminals with mirror heads, two star trackers, stacking posts.
    for (x, z) in [(-0.85, -1.62), (0.85, -1.62), (0, 1.7)] as [(Float, Float)] {
      put(r, CylinderMesh(radius: 0.17, height: 0.18, sides: 18), bus, x, H / 2 + 0.09, z)
      put(r, LatheMesh([SIMD2(0, 0.15), SIMD2(0.07, 0.14), SIMD2(0.13, 0.09), SIMD2(0.16, 0)], sides: 18), chrome, x, H / 2 + 0.18, z)
    }
    for x in [-0.6, 0.6] as [Float] {
      let st = holder(r, V3(x, H / 2 + 0.1, 0.75), rx: 0.4, rz: x > 0 ? -0.4 : 0.4)
      put(st, CylinderMesh(radius: 0.07, height: 0.18, sides: 12), black, 0, 0, 0)
      put(st, CylinderMesh(radius: 0.05, height: 0.02, sides: 12), glass, 0, 0.095, 0)
    }
    for (x, z) in [(-1.2, -1.9), (1.2, -1.9), (-1.2, 1.9), (1.2, 1.9)] as [(Float, Float)] {
      put(r, CylinderMesh(radius: 0.06, height: 0.14, sides: 10), trussSilver, x, H / 2 + 0.07, z)
    }
    // Nadir: four phased-array antennas and two gimballed gateway dishes.
    for (x, z) in [(-0.66, -0.95), (0.66, -0.95), (-0.66, 0.95), (0.66, 0.95)] as [(Float, Float)] {
      box(r, 1.2, 0.06, 1.12, dishWhite, x, -H / 2 - 0.03, z)
      for k in 1..<4 { box(r, 1.2, 0.065, 0.012, moduleBand, x, -H / 2 - 0.03, z - 0.56 + 1.12 * Float(k) / 4) }
    }
    for z in [-1.82, 1.82] as [Float] {
      tube(r, V3(0, -H / 2, z), V3(0, -H / 2 - 0.22, z), 0.04, trussSilver)
      put(r, DishMesh(radius: 0.21, depth: 0.08), dishWhite, 0, -H / 2 - 0.22, z, rx: .pi)
    }
    // Argon Hall thruster on the aft edge.
    put(r, CylinderMesh(radius: 0.1, height: 0.12, sides: 16), trussSilver, 0, 0, L / 2 + 0.06, rx: .pi / 2)
    put(r, CylinderMesh(radius: 0.07, height: 0.02, sides: 16), black, 0, 0, L / 2 + 0.125, rx: .pi / 2)
    // Solar wings: a yoke, a hinge drum and six hinged panels each side.
    for s in [-1, 1] as [Float] {
      let root = s * (W / 2 + 0.9)
      tube(r, V3(s * W / 2, 0, -1.3), V3(root, 0, 0), 0.04, trussSilver)
      tube(r, V3(s * W / 2, 0, 1.3), V3(root, 0, 0), 0.04, trussSilver)
      put(r, CylinderMesh(radius: 0.09, height: 0.6, sides: 12), trussSilver, root, 0, 0, rx: .pi / 2)
      let pw: Float = 2.12, gap: Float = 0.06
      for i in 0..<6 {
        let cx = s * (W / 2 + 1.0 + pw / 2 + Float(i) * (pw + gap))
        solarPanel(r, x: cx, y: 0, z: 0, w: pw, l: L, cols: 4, rows: 10, t: 0.035)
        if i > 0 { box(r, gap, 0.04, 0.3, black, cx - s * (pw + gap) / 2, 0, L * 0.3); box(r, gap, 0.04, 0.3, black, cx - s * (pw + gap) / 2, 0, -L * 0.3) }
      }
      tube(r, V3(root, -0.05, 0), V3(s * (W / 2 + 1.0 + 6 * (pw + gap)), -0.05, 0), 0.035, trussSilver)
    }
  }
}

// Hubble Space Telescope: 13.2 m long, 4.2 m across the aft shroud, rigid
// solar wings either side, high-gain antennas above and below, aperture door
// open at the front.
func hubble() -> SCNNode {
  spacecraft { r in
    let skin = material("paint", 0xC9CDD2, metal: 0.92, rough: 0.27)
    // Body frame: local +Y runs forward (-Z) from the aft bulkhead; local +Z is up.
    let b = holder(r, V3(0, 0, 6.6), rx: -.pi / 2)
    put(b, LatheMesh([SIMD2(-0.12, 0.001), SIMD2(-0.09, 1.0), SIMD2(-0.02, 1.9), SIMD2(0.06, 2.13), SIMD2(3.6, 2.13)], sides: 36), skin, 0, 0, 0)
    put(b, CylinderMesh(radius: 2.0, height: 1.5, sides: 30), foilSilver, 0, 4.35, 0)
    put(b, LatheMesh([SIMD2(5.1, 2.13), SIMD2(5.5, 1.56)], sides: 36), skin, 0, 0, 0)
    put(b, LatheMesh([SIMD2(5.5, 1.55), SIMD2(13.2, 1.55)], sides: 36, caps: false), skin, 0, 0, 0)
    put(b, LatheMesh([SIMD2(13.18, 1.5), SIMD2(10.5, 1.5)], sides: 30, caps: false), black, 0, 0, 0) // baffle lining
    put(b, CylinderMesh(radius: 1.5, height: 0.04, sides: 30), black, 0, 10.6, 0)
    for y in [5.5, 7.4, 9.3, 11.2] as [Float] {
      put(b, LatheMesh([SIMD2(y - 0.04, 1.585), SIMD2(y + 0.04, 1.585)], sides: 36, caps: false), moduleBand, 0, 0, 0)
    }
    put(b, TubeMesh(innerRadius: 1.44, outerRadius: 1.63, height: 0.12, sides: 36), skin, 0, 13.2, 0)
    for y in [1.2, 2.4, 3.6] as [Float] {
      put(b, LatheMesh([SIMD2(y - 0.03, 2.155), SIMD2(y + 0.03, 2.155)], sides: 36, caps: false), moduleBand, 0, 0, 0)
    }
    // Ten equipment bays with yellow handrails.
    for k in 0..<10 {
      let bay = holder(b, V3(0, 0, 0), ry: -(Float(k) + 0.5) * .pi / 5)
      box(bay, 0.1, 1.44, 1.34, k % 3 == 0 ? foilSilver : skin, 2.08, 4.35, 0)
      box(bay, 0.03, 1.2, 0.03, moduleBand, 2.14, 4.35, 0)
      for z in [-0.42, 0.42] as [Float] { tube(bay, V3(2.2, 3.85, z), V3(2.2, 4.85, z), 0.025, handrail, sides: 6) }
    }
    // White blanket patches on the forward shell and light shield.
    for _ in 0..<9 {
      let a = rnd() * 2 * .pi, y = 6.0 + rnd() * 6.6
      let patch = holder(b, V3(0, 0, 0), ry: -a)
      box(patch, 0.02, 0.5 + rnd() * 0.9, 0.4 + rnd() * 0.6, radiatorWhite, 1.56, y, 0)
    }
    // Soft-capture ring and grapple fixtures at the back, magnetometers at the front.
    put(b, TubeMesh(innerRadius: 0.55, outerRadius: 0.78, height: 0.22, sides: 24), trussSilver, 0, -0.2, 0)
    for k in 0..<3 {
      let a = Float(k) * 2 * .pi / 3
      box(b, 0.2, 0.3, 0.2, black, cos(a) * 0.68, -0.4, sin(a) * 0.68)
    }
    for x in [-1.3, 1.3] as [Float] {
      put(b, CylinderMesh(radius: 0.1, height: 0.3, sides: 10), radiatorWhite, x, 2.2, 2.25, rx: .pi / 2)
      box(b, 0.25, 0.3, 0.25, foilSilver, x * 0.5, 13.0, 1.62)
    }
    // Aperture door, hinged at the top of the opening and swung up 105 degrees.
    let door = holder(b, V3(0, 13.25, 1.6), rx: 1.83)
    put(door, CylinderMesh(radius: 1.62, height: 0.1, sides: 30), skin, 0, 0.05, -1.6)
    put(door, CylinderMesh(radius: 1.45, height: 0.02, sides: 30), black, 0, -0.01, -1.6)
    tube(door, V3(-0.4, 0.05, 0), V3(0.4, 0.05, 0), 0.08, trussSilver)
    // Low-gain antennas fore and aft.
    put(b, LatheMesh([SIMD2(0, 0.18), SIMD2(0.5, 0.05)], sides: 12), radiatorWhite, 0, 13.0, -1.62, rx: -.pi / 2)
    // Solar wings: two rigid panels either side of a mast, parallel to the tube.
    for s in [-1, 1] as [Float] {
      tube(r, V3(s * 1.5, 0, 0.8), V3(s * 4.6, 0, 0.8), 0.07, trussSilver)
      put(r, CylinderMesh(radius: 0.18, height: 0.3, sides: 14), foilSilver, s * 1.7, 0, 0.8, rz: .pi / 2)
      tube(r, V3(s * 4.6, -0.06, -2.85), V3(s * 4.6, -0.06, 4.45), 0.05, trussSilver)
      for dz in [-1.85, 1.85] as [Float] {
        solarPanel(r, x: s * 4.6, y: 0, z: 0.8 + dz, w: 2.6, l: 3.5, cols: 5, rows: 12, t: 0.05, frame: foilGold)
      }
    }
    // High-gain antennas on booms above and below.
    for s in [-1, 1] as [Float] {
      tube(r, V3(0, s * 1.55, -2.0), V3(0, s * 4.3, -2.0), 0.06, trussSilver)
      box(r, 0.3, 0.3, 0.3, foilSilver, 0, s * 4.3, -2.0)
      put(r, DishMesh(radius: 0.66, depth: 0.2), dishWhite, 0, s * 4.45, -2.0, rx: s > 0 ? -0.35 : .pi + 0.35)
      tube(r, V3(0, s * 4.45, -2.0), V3(0, s * 4.95, -2.0 - 0.2), 0.03, trussSilver)
    }
  }
}

// GPS III: an A2100-class bus (1.8 x 3.4 x 2.5 m) in gold foil with mirror
// radiators on the array faces, two three-panel wings (about 17 m span) and
// the L-band helix array on the Earth-facing (bottom) face.
func gps3() -> SCNNode {
  spacecraft { r in
    let foil = material("paint", 0xC8962F, metal: 0.9, rough: 0.34)
    let X: Float = 1.8, Y: Float = 3.4, Z: Float = 2.46
    box(r, X, Y, Z, foil, 0, 0, 0)
    // Crinkled foil on the fore/aft faces and the top.
    crinkle(holder(r, V3(0, Y / 2, 0)), w: X, l: Z, count: 14, size: 0.45, foilAmber)
    for s in [-1, 1] as [Float] {
      crinkle(holder(r, V3(0, 0, s * Z / 2), rx: s * .pi / 2), w: X, l: Y, count: 16, size: 0.5, foilAmber)
    }
    // Mirror radiators (OSR tiles) on the array faces.
    for s in [-1, 1] as [Float] {
      let face = holder(r, V3(s * X / 2, 0, 0), rz: -s * .pi / 2)
      // Local X runs up the face, local Z along it.
      box(face, Y * 0.86, 0.03, Z * 0.9, foilSilver, 0, 0.015, 0)
      for i in 1..<10 { put(face, QuadMesh(width: 0.02, length: Z * 0.9), radiatorLine, -Y * 0.43 + Y * 0.86 * Float(i) / 10, 0.035, 0) }
      for j in 1..<8 { put(face, QuadMesh(width: Y * 0.86, length: 0.02), radiatorLine, 0, 0.035, -Z * 0.45 + Z * 0.9 * Float(j) / 8) }
    }
    // Zenith: apogee engine, thruster pods, a laser reflector array.
    put(r, CylinderMesh(radius: 0.14, height: 0.14, sides: 14), engineBell, 0, Y / 2 + 0.07, 0.4)
    put(r, LatheMesh([SIMD2(0, 0.1), SIMD2(0.2, 0.2), SIMD2(0.42, 0.32)], sides: 18, caps: false, twoSided: true), engineBell, 0, Y / 2 + 0.12, 0.4)
    for (x, z) in [(-0.75, -1.08), (0.75, -1.08), (-0.75, 1.08), (0.75, 1.08)] as [(Float, Float)] {
      box(r, 0.16, 0.12, 0.16, trussSilver, x, Y / 2 + 0.06, z)
      put(r, CylinderMesh(radius: 0.03, height: 0.08, sides: 8), engineBell, x, Y / 2 + 0.15, z)
    }
    box(r, 0.5, 0.06, 0.4, composite, -0.4, Y / 2 + 0.03, -0.55)
    for i in 0..<3 { for j in 0..<3 { put(r, CylinderMesh(radius: 0.04, height: 0.02, sides: 10), glass, -0.55 + Float(i) * 0.15, Y / 2 + 0.065, -0.68 + Float(j) * 0.13) } }
    // Earth face: ground plane with twelve helix radomes, a UHF crosslink helix and an S-band dish.
    box(r, X * 0.98, 0.06, Z * 0.98, radiatorWhite, 0, -Y / 2 - 0.03, 0)
    put(r, CylinderMesh(radius: 0.9, height: 0.06, sides: 30), composite, 0, -Y / 2 - 0.08, -0.15)
    var spots: [SIMD2<Float>] = (0..<4).map { k in let a = Float(k) * .pi / 2 + .pi / 4; return SIMD2(cos(a) * 0.28, sin(a) * 0.28) }
    spots += (0..<8).map { k in let a = Float(k) * .pi / 4; return SIMD2(cos(a) * 0.68, sin(a) * 0.68) }
    for c in spots {
      put(r, CylinderMesh(radius: 0.1, height: 0.7, sides: 14), radiatorWhite, c.x, -Y / 2 - 0.46, -0.15 + c.y)
      put(r, LatheMesh([SIMD2(0, 0.1), SIMD2(0.06, 0.07), SIMD2(0.1, 0.001)], sides: 14), radiatorWhite, c.x, -Y / 2 - 0.81, -0.15 + c.y, rx: .pi)
    }
    let uhf = holder(r, V3(0.55, -Y / 2 - 0.06, 1.0))
    tube(uhf, V3(0, 0, 0), V3(0, -1.1, 0), 0.03, trussSilver)
    for k in 0..<24 {
      let a0 = Float(k) * 0.7, a1 = Float(k + 1) * 0.7
      tube(uhf, V3(cos(a0) * 0.2, -0.1 - Float(k) * 0.04, sin(a0) * 0.2), V3(cos(a1) * 0.2, -0.1 - Float(k + 1) * 0.04, sin(a1) * 0.2), 0.015, foilGold, sides: 4)
    }
    put(r, DishMesh(radius: 0.22, depth: 0.07), dishWhite, -0.55, -Y / 2 - 0.2, 1.0, rx: .pi)
    tube(r, V3(-0.55, -Y / 2, 1.0), V3(-0.55, -Y / 2 - 0.2, 1.0), 0.03, trussSilver)
    // Solar wings: drive, yoke and three panels each side.
    for s in [-1, 1] as [Float] {
      put(r, CylinderMesh(radius: 0.2, height: 0.25, sides: 16), trussSilver, s * (X / 2 + 0.12), 0.2, 0, rz: .pi / 2)
      let root = s * (X / 2 + 1.6)
      tube(r, V3(s * (X / 2 + 0.2), 0.2, 0), V3(root, 0.2, -1.2), 0.045, trussSilver)
      tube(r, V3(s * (X / 2 + 0.2), 0.2, 0), V3(root, 0.2, 1.2), 0.045, trussSilver)
      for i in 0..<3 {
        let cx = s * (X / 2 + 1.6 + 1.0 + Float(i) * 2.05)
        solarPanel(r, x: cx, y: 0.2, z: 0, w: 2.0, l: 2.6, cols: 6, rows: 8, t: 0.04)
        box(r, 0.05, 0.05, 2.5, black, cx - s * 1.025, 0.2, 0)
      }
    }
  }
}

// 3U CubeSat: 10 x 10 x 34 cm, two double-deployed panels each side
// (about 0.5 m span) and four tape-spring antennas at the front end.
func cubesat() -> SCNNode {
  spacecraft { r in
    let frame = material("paint", 0xB3B8BF, metal: 0.85, rough: 0.3)
    let pcb = material("pcb", 0x1A1C22, rough: 0.6)
    let s: Float = 0.1, L: Float = 0.3405, h = s / 2
    box(r, s * 0.95, s * 0.95, L - 0.014, pcb, 0, 0, 0)
    // Corner rails, standing proud at both ends, with separation springs.
    for (x, y) in [(-1, -1), (1, -1), (1, 1), (-1, 1)] as [(Float, Float)] {
      box(r, 0.0085, 0.0085, L, frame, x * (h - 0.00425), y * (h - 0.00425), 0)
      put(r, CylinderMesh(radius: 0.0025, height: 0.006, sides: 8), chrome, x * (h - 0.00425), y * (h - 0.00425), L / 2 + 0.003, rx: .pi / 2)
    }
    // Frame ribs between the three units and round the end plates.
    for z in [-L / 2 + 0.004, -0.0567, 0.0567, L / 2 - 0.004] as [Float] {
      for (w, hh, x, y) in [(s, 0.004, 0, h - 0.002), (s, 0.004, 0, -h + 0.002), (0.004, s, h - 0.002, 0), (0.004, s, -h + 0.002, 0)] as [(Float, Float, Float, Float)] {
        box(r, w, hh, 0.006, frame, x, y, z)
      }
    }
    // Body-mounted cells on top and bottom (two per unit), GPS patch and sun sensor.
    for face in [Float(1), -1] {
      let f = holder(r, V3(0, face * (h * 0.95 + 0.0005), 0), rx: face > 0 ? 0 : .pi)
      for z in [-0.1135, 0, 0.1135] as [Float] where !(face > 0 && z > 0.1) {
        for x in [-0.021, 0.021] as [Float] {
          put(f, QuadMesh(width: 0.038, length: 0.075), cells, x, 0.0003, z)
          put(f, QuadMesh(width: 0.038, length: 0.002), cellGrid, x, 0.0006, z - 0.03)
          put(f, QuadMesh(width: 0.038, length: 0.002), cellGrid, x, 0.0006, z + 0.03)
        }
      }
    }
    box(r, 0.03, 0.004, 0.03, dishWhite, 0.015, h + 0.002, 0.11)
    box(r, 0.012, 0.004, 0.012, glass, -0.025, h + 0.002, 0.12)
    // Nadir camera.
    put(r, CylinderMesh(radius: 0.017, height: 0.012, sides: 16), black, 0, -h - 0.006, 0.11)
    put(r, CylinderMesh(radius: 0.011, height: 0.002, sides: 16), glass, 0, -h - 0.012, 0.11)
    // Deployed panels, hinged at the top edges of the side faces.
    for side in [-1, 1] as [Float] {
      for k in 0..<2 {
        let cx = side * (h + 0.05 + Float(k) * 0.1015)
        solarPanel(r, x: cx, y: h + 0.002, z: 0, w: 0.097, l: 0.32, cols: 2, rows: 4, t: 0.0025, frame: frame)
        put(r, CylinderMesh(radius: 0.002, height: 0.3, sides: 8), frame, cx - side * 0.0505, h + 0.002, 0, rx: .pi / 2)
      }
    }
    // Antenna deployer and four tape whips in an X (two long VHF, two short UHF).
    box(r, s * 0.92, s * 0.92, 0.008, composite, 0, 0, -L / 2 - 0.002)
    for k in 0..<4 {
      let a = Float(k) * .pi / 2 + .pi / 4
      let len: Float = k % 2 == 0 ? 0.5 : 0.17
      let whip = holder(r, V3(0, 0, -L / 2 - 0.006), rz: a)
      box(whip, len, 0.0008, 0.006, chrome, 0.04 + len / 2, 0, 0)
    }
  }
}

/// Crew Dragon (capsule and trunk) built along +Z: docking ring at z = 0,
/// trunk end at z = 7.1, nose cone open and hinged up.
func buildDragon(_ p: SCNNode, capsule: SCNMaterial) {
  // Lathe frame: local +Y runs forward from the trunk end; local +Z is up.
  let d = holder(p, V3(0, 0, 7.1), rx: -.pi / 2)
  let shell = rocketWhite
  // Trunk: radiators round the bottom half, solar cells round the top half, four fins.
  put(d, LatheMesh([SIMD2(0, 1.83), SIMD2(3.4, 1.83)], sides: 40), shell, 0, 0, 0)
  put(d, TubeMesh(innerRadius: 1.8, outerRadius: 1.88, height: 0.2, sides: 40), black, 0, 0.1, 0)
  put(d, LatheMesh([SIMD2(0.35, 1.845), SIMD2(3.25, 1.845)], sides: 24, caps: false, from: 0.02, to: .pi - 0.02), cells, 0, 0, 0)
  for k in 1..<12 {
    let a = Float(k) / 12 * .pi
    let line = holder(d, V3(0, 0, 0), ry: -a)
    box(line, 0.012, 2.9, 0.025, cellGrid, 1.85, 1.8, 0)
  }
  for y in [0.93, 1.51, 2.09, 2.67] as [Float] {
    put(d, LatheMesh([SIMD2(y - 0.012, 1.852), SIMD2(y + 0.012, 1.852)], sides: 24, caps: false, from: 0.02, to: .pi - 0.02), cellGrid, 0, 0, 0)
  }
  for k in 0..<4 {
    let a = Float(k) * .pi / 2 + .pi / 4
    put(d, PanelMesh([SIMD2(1.8, 0), SIMD2(2.45, 0), SIMD2(2.45, 0.45), SIMD2(1.8, 1.5)]), shell, 0, 0, 0, ry: -a)
  }
  put(d, LatheMesh([SIMD2(3.4, 1.83), SIMD2(3.62, 1.9)], sides: 40), black, 0, 0, 0)
  // Capsule: black heat-shield rim, sloped side wall, forward bulkhead.
  put(d, LatheMesh([SIMD2(3.62, 1.82), SIMD2(3.7, 2.0), SIMD2(3.84, 2.0)], sides: 40, caps: false), black, 0, 0, 0)
  put(d, LatheMesh([SIMD2(3.84, 2.0), SIMD2(3.92, 1.99), SIMD2(6.45, 1.27), SIMD2(6.62, 1.14), SIMD2(6.72, 0.95), SIMD2(6.78, 0.7)], sides: 40), capsule, 0, 0, 0)
  let wall = atan2(Float(0.72), Float(2.53))
  func wallRadius(_ y: Float) -> Float { 1.99 - (y - 3.92) * 0.72 / 2.53 }
  // SuperDraco pods (two nozzles each) at the four corners.
  for k in 0..<4 {
    let pod = holder(d, V3(0, 0, 0), ry: -(Float(k) * .pi / 2 + .pi / 4))
    box(pod, 0.16, 1.1, 0.72, capsule, wallRadius(4.75) + 0.04, 4.75, 0, rz: wall)
    for z in [-0.18, 0.18] as [Float] {
      put(pod, CylinderMesh(radius: 0.09, height: 0.18, sides: 12), black, wallRadius(4.2) + 0.1, 4.2, z, rz: wall)
    }
    box(pod, 0.08, 0.14, 0.22, black, wallRadius(6.2) + 0.03, 6.2, 0.25, rz: wall) // Draco cluster
    box(pod, 0.08, 0.14, 0.22, black, wallRadius(6.2) + 0.03, 6.2, -0.25, rz: wall)
  }
  // Side hatch with its window on top, two more windows.
  let hatch = holder(d, V3(0, 0, 0), ry: -.pi / 2)
  box(hatch, 0.03, 1.0, 0.9, moduleBand, wallRadius(5.0) + 0.005, 5.0, 0, rz: wall)
  box(hatch, 0.05, 0.3, 0.3, glass, wallRadius(5.15) + 0.02, 5.15, 0, rz: wall)
  for a in [Float(0.45), Float.pi - 0.45] {
    let w = holder(d, V3(0, 0, 0), ry: -a)
    box(w, 0.05, 0.32, 0.3, glass, wallRadius(5.3) + 0.01, 5.3, 0, rz: wall)
  }
  // Docking adapter with guide petals.
  put(d, TubeMesh(innerRadius: 0.48, outerRadius: 0.66, height: 0.3, sides: 28), trussSilver, 0, 6.93, 0)
  for k in 0..<3 {
    let a = Float(k) * 2 * .pi / 3
    let petal = holder(d, V3(0, 0, 0), ry: -a)
    box(petal, 0.08, 0.25, 0.3, trussSilver, 0.55, 7.15, 0, rz: 0.4)
  }
  // Nose cone, hinged at the top of the bulkhead and swung up over 100 degrees.
  let cone = holder(d, V3(0, 6.8, 1.02), rx: 1.85)
  put(cone, LatheMesh([SIMD2(0, 1.06), SIMD2(0.25, 0.99), SIMD2(0.55, 0.78), SIMD2(0.8, 0.42), SIMD2(0.92, 0.1), SIMD2(0.94, 0.001)], sides: 36), capsule, 0, 0, -1.02)
  put(cone, CylinderMesh(radius: 0.98, height: 0.02, sides: 36), black, 0, -0.012, -1.02)
  tube(cone, V3(-0.3, 0, 0), V3(0.3, 0, 0), 0.07, trussSilver)
}

func crewDragon() -> SCNNode {
  spacecraft { r in buildDragon(holder(r, V3(0, 0, -3.55)), capsule: material("paint", 0xF3F3F1, metal: 0.1, rough: 0.45)) }
}

/// Soyuz (orbital, descent and service modules) or Progress (cargo,
/// refuelling and service modules) built along +Z from the docking probe at
/// z = 0, with solar wings flat in the XZ plane.
func buildSoyuz(_ p: SCNNode, cargo: Bool) {
  let s = holder(p, V3(0, 0, 0), rx: .pi / 2) // local +Y runs aft along +Z
  tube(p, V3(0, 0, -0.35), V3(0, 0, 0.1), 0.08, trussSilver)
  if cargo {
    put(s, LatheMesh([SIMD2(0, 0.3), SIMD2(0.3, 0.9), SIMD2(0.9, 1.13), SIMD2(2.6, 1.13), SIMD2(3.0, 0.9)], sides: 28), soyuzGreen, 0, 0, 0)
    put(s, LatheMesh([SIMD2(3.0, 1.1), SIMD2(4.4, 1.1)], sides: 28), soyuzGreen, 0, 0, 0)
  } else {
    put(s, LatheMesh([SIMD2(0, 0.3), SIMD2(0.3, 0.8), SIMD2(0.9, 1.12), SIMD2(1.8, 1.12), SIMD2(2.4, 0.8), SIMD2(2.6, 0.5)], sides: 28), soyuzGreen, 0, 0, 0)
    put(s, LatheMesh([SIMD2(2.6, 0.9), SIMD2(3.0, 1.2), SIMD2(4.2, 2.05), SIMD2(4.4, 2.1)], sides: 28), soyuzGreen, 0, 0, 0)
  }
  put(s, LatheMesh([SIMD2(4.4, 1.36), SIMD2(7.0, 1.36), SIMD2(7.2, 1.05)], sides: 28), radiatorWhite, 0, 0, 0)
  put(s, TubeMesh(innerRadius: 1.36, outerRadius: 1.42, height: 0.2, sides: 28), moduleBand, 0, 5.2, 0)
  for side in [-1, 1] as [Float] {
    tube(p, V3(side * 1.36, 0, 5.8), V3(side * 1.9, 0, 5.8), 0.05, trussSilver)
    for i in 0..<4 {
      solarPanel(p, x: side * (1.95 + 0.5 + Float(i) * 1.02), y: 0, z: 5.8, w: 1.0, l: 1.9, cols: 2, rows: 4, t: 0.03)
    }
  }
  tube(p, V3(0.6, 0.6, 0.6), V3(1.4, 1.4, -0.4), 0.02, trussSilver) // Kurs antenna
}

// James Webb Space Telescope: 18 gold hexagonal segments (6.6 m across)
// tipped 45 degrees up towards the front, secondary mirror on a tripod, a
// five-layer kite-shaped sunshield (21.2 x 14.2 m) and the bus beneath.
func jwst() -> SCNNode {
  spacecraft { r in
    let shield = material("paint", 0xC4B2E2, metal: 0.55, rough: 0.25) // aluminised Kapton, purple-silver
    let seam = material("seam", 0x9A8FB8, metal: 0.5, rough: 0.35)
    shield.isDoubleSided = true
    let tipZ: Float = 10.6, halfW: Float = 7.08, shoulder: Float = 1.8
    func outline(_ k: Float) -> [SIMD2<Float>] {
      [SIMD2(0, -tipZ * k), SIMD2(halfW * k, -shoulder * k), SIMD2(halfW * k, shoulder * k),
       SIMD2(0, tipZ * k), SIMD2(-halfW * k, shoulder * k), SIMD2(-halfW * k, -shoulder * k)]
    }
    // Five membranes, spaced apart, the sun-facing one largest.
    let layerY: [Float] = [0, 0.16, 0.3, 0.42, 0.52]
    for (i, y) in layerY.enumerated() {
      put(r, PanelMesh(outline(1 - Float(i) * 0.018)), shield, 0, y, 0, rx: -.pi / 2)
    }
    // Seams on the top layer and a cable round its edge.
    let topY = layerY.last! + 0.012, k5: Float = 1 - 4 * 0.018
    func half(_ z: Float) -> Float { abs(z) < shoulder * k5 ? halfW * k5 : halfW * k5 * (tipZ * k5 - abs(z)) / ((tipZ - shoulder) * k5) }
    for z in stride(from: Float(-8), through: 8, by: 2) {
      put(r, QuadMesh(width: 2 * half(z) * 0.98, length: 0.05), seam, 0, topY, z)
    }
    for x in [-4.5, -2.25, 2.25, 4.5] as [Float] {
      let zr = shoulder * k5 + (halfW * k5 - abs(x)) / (halfW * k5) * (tipZ - shoulder) * k5
      put(r, QuadMesh(width: 0.05, length: 2 * zr * 0.97), seam, x, topY, 0)
    }
    let edge = outline(k5)
    for i in 0..<edge.count {
      let a = edge[i], b = edge[(i + 1) % edge.count]
      rod(r, V3(a.x, topY, a.y), V3(b.x, topY, b.y), 0.04, trussSilver)
    }
    // Mid booms out to the sides, pallets and spreader bars at the tips.
    for s in [-1, 1] as [Float] {
      rod(r, V3(0, 0.6, 0), V3(s * halfW * 0.97, 0.6, 0), 0.07, trussSilver, sides: 8)
      box(r, 2.8, 0.5, 1.0, composite, 0, -0.3, s * (tipZ - 0.9))
      box(r, 2.6, 0.08, 0.9, foilSilver, 0, -0.03, s * (tipZ - 0.9))
      tube(r, V3(0, -0.3, s * 1.6), V3(0, -0.3, s * (tipZ - 1.4)), 0.12, composite)
      tube(r, V3(-1.6, 0.58, s * (tipZ - 1.0)), V3(1.6, 0.58, s * (tipZ - 1.0)), 0.05, trussSilver)
    }
    // Momentum trim flap at the aft tip.
    put(r, PanelMesh([SIMD2(-1.0, 0), SIMD2(1.0, 0), SIMD2(0.75, 1.4), SIMD2(-0.75, 1.4)]), shield, 0, 0.3, tipZ - 0.2, rx: 0.75)
    tube(r, V3(0, 0.3, tipZ - 0.2), V3(0, 1.3, tipZ + 0.7), 0.04, trussSilver)
    // Spacecraft bus under the shield: solar array, high-gain dish, star trackers.
    box(r, 3.2, 1.4, 3.2, composite, 0, -1.25, 0.4)
    for s in [-1, 1] as [Float] {
      box(r, 0.03, 1.0, 2.4, foilGold, s * 1.62, -1.25, 0.4)
      put(r, CylinderMesh(radius: 0.12, height: 0.3, sides: 12), black, s * 1.0, -0.6, -1.25, rx: -0.6)
    }
    let array = holder(r, V3(0, -1.75, 4.9), rz: .pi)
    solarPanel(array, x: 0, y: 0, z: 0, w: 2.1, l: 5.6, cols: 3, rows: 10, t: 0.05)
    tube(r, V3(0, -1.7, 2.0), V3(0, -1.75, 2.2), 0.06, trussSilver)
    tube(r, V3(0.8, -1.95, 0.4), V3(0.8, -2.5, 0.4), 0.05, trussSilver)
    put(r, DishMesh(radius: 0.32, depth: 0.1), dishWhite, 0.8, -2.5, 0.4, rx: .pi)
    // Optical telescope: deployable tower, instrument module, backplane, mirror.
    tube(r, V3(0, -0.55, 0.6), V3(0, 1.6, 1.15), 0.3, composite)
    let C = V3(0, 4.2, 1.4)
    let up = V3(0, 0.7071, 0.7071), normal = V3(0, 0.7071, -0.7071)
    let isim = C - normal * 1.3 - up * 1.6
    box(r, 2.2, 2.0, 2.0, composite, isim.x, isim.y, isim.z, rx: -.pi / 4)
    box(r, 2.24, 1.6, 1.6, foilSilver, isim.x, isim.y - 0.1, isim.z + 0.15, rx: -.pi / 4)
    let m = holder(r, C, rx: -.pi / 4) // mirror frame: +Y is the boresight, +Z is up the mirror
    put(m, CylinderMesh(radius: 3.05, height: 0.35, sides: 6), composite, 0, -0.35, 0)
    box(m, 1.4, 0.8, 5.6, composite, 0, -0.85, 0)
    let Rc: Float = 0.762, wFlat: Float = 1.32 + 0.012, focal: Float = 7.95
    let hexTurn = simd_quatf(angle: .pi / 6, axis: V3(0, 1, 0))
    for q in -2...2 {
      for rr in -2...2 where max(abs(q), abs(rr), abs(q + rr)) >= 1 && max(abs(q), abs(rr), abs(q + rr)) <= 2 {
        let u = wFlat * (Float(q) + Float(rr) / 2)
        let v = (wFlat / Float(3).squareRoot()) * 1.5 * Float(rr)
        let seg = SCNNode(geometry: CylinderMesh(radius: CGFloat(Rc), height: 0.06, sides: 6))
        seg.geometry!.materials = [mirrorGold]
        seg.simdPosition = V3(u, (u * u + v * v) / (4 * focal), v)
        let n = simd_normalize(V3(-u / (2 * focal), 1, -v / (2 * focal)))
        seg.simdOrientation = simd_quatf(from: V3(0, 1, 0), to: n) * hexTurn
        m.addChildNode(seg)
      }
    }
    // Aft optics baffle poking out of the centre.
    put(m, CylinderMesh(radius: 0.32, height: 0.9, sides: 16), black, 0, 0.45, 0)
    put(m, TubeMesh(innerRadius: 0.32, outerRadius: 0.38, height: 0.06, sides: 16), foilSilver, 0, 0.9, 0)
    // Secondary mirror on three struts.
    let S = C + normal * 7.0
    for a in [C + up * 3.25, C + V3(2.3, 0, 0) - up * 2.4, C + V3(-2.3, 0, 0) - up * 2.4] {
      tube(r, a, S - normal * 0.25, 0.07, composite, sides: 8)
    }
    let (sm, _) = axisHolder(r, S, S - normal)
    put(sm, CylinderMesh(radius: 0.42, height: 0.06, sides: 6), mirrorGold, 0, 0, 0)
    put(sm, CylinderMesh(radius: 0.48, height: 0.4, sides: 6), composite, 0, -0.23, 0)
  }
}

/// One ISS solar array wing: two 34 m blankets either side of a lattice mast,
/// with blanket boxes at the root and tip; `rosa` adds a roll-out array
/// (iROSA) mounted over it.
func issWing(_ p: SCNNode, x: Float, y: Float, zRoot: Float, dir: Float, rosa: Bool) {
  let len: Float = 33.5, start: Float = 1.3
  box(p, 11.4, 0.45, 0.8, foilSilver, x, y, zRoot + dir * 0.7)
  box(p, 11.4, 0.4, 0.7, foilSilver, x, y, zRoot + dir * (start + len + 0.35))
  // Mast: three longerons with battens.
  let tri: [SIMD2<Float>] = [SIMD2(-0.3, -0.25), SIMD2(0.3, -0.25), SIMD2(0, 0.28)]
  for c in tri { rod(p, V3(x + c.x, y + c.y, zRoot + dir * start), V3(x + c.x, y + c.y, zRoot + dir * (start + len)), 0.04, trussSilver) }
  for k in 0...14 {
    let z = zRoot + dir * (start + len * Float(k) / 14)
    for i in 0..<3 { rod(p, V3(x + tri[i].x, y + tri[i].y, z), V3(x + tri[(i + 1) % 3].x, y + tri[(i + 1) % 3].y, z), 0.03, trussSilver) }
  }
  for s in [-1, 1] as [Float] {
    let cx = x + s * 2.95, cz = zRoot + dir * (start + len / 2)
    box(p, 4.6, 0.06, len, panelBack, cx, y, cz)
    put(p, QuadMesh(width: 4.55, length: len * 0.995), issCells, cx, y + 0.045, cz)
    for k in 1..<20 { put(p, QuadMesh(width: 4.55, length: 0.07), issGrid, cx, y + 0.06, cz - len / 2 + len * Float(k) / 20) }
    put(p, QuadMesh(width: 0.06, length: len * 0.995), issGrid, cx, y + 0.06, cz)
  }
  if rosa {
    let h = holder(p, V3(x, y + 0.7, zRoot + dir * 3.0), rx: -dir * 0.07)
    let rl: Float = 18.3
    box(h, 6.0, 0.05, rl, panelBack, 0, 0, dir * rl / 2)
    put(h, QuadMesh(width: 5.95, length: rl * 0.995), rosaCells, 0, 0.04, dir * rl / 2)
    for k in 1..<14 { put(h, QuadMesh(width: 5.95, length: 0.05), cellGrid, 0, 0.05, dir * rl * Float(k) / 14) }
    put(h, QuadMesh(width: 0.05, length: rl * 0.995), cellGrid, 0, 0.05, dir * rl / 2)
    for s in [-1, 1] as [Float] { rod(h, V3(s * 3.05, 0, 0), V3(s * 3.05, 0, dir * rl), 0.08, trussSilver, sides: 6) }
    box(h, 6.4, 0.3, 0.5, foilSilver, 0, 0, 0)
    box(h, 6.2, 0.25, 0.4, foilSilver, 0, 0, dir * rl)
    tube(p, V3(x - 2, y, zRoot + dir * 1.3), V3(x - 2, y + 0.7, zRoot + dir * 3.0), 0.06, trussSilver)
    tube(p, V3(x + 2, y, zRoot + dir * 1.3), V3(x + 2, y + 0.7, zRoot + dir * 3.0), 0.06, trussSilver)
  }
}

/// A deployed radiator: `w` wide, `l` long, swung down `pitch` from the
/// anchor towards +Z (dir 1) or -Z (dir -1), with panel seams and edge beams.
func radiatorWing(_ p: SCNNode, at a: V3, w: Float, l: Float, panels: Int, pitch: Float, dir: Float) {
  let h = holder(p, a, rx: dir * pitch)
  box(h, w, 0.08, l, radiatorWhite, 0, 0, dir * l / 2)
  for k in 1..<panels { put(h, QuadMesh(width: w, length: 0.06), radiatorLine, 0, 0.045, dir * l * Float(k) / Float(panels)) }
  for s in [-1, 1] as [Float] { rod(h, V3(s * w / 2, 0, 0), V3(s * w / 2, 0, dir * l), 0.06, trussSilver) }
}

// International Space Station: 109 m integrated truss with eight solar
// array wings (six with iROSA overlays), heat-rejection and photovoltaic
// radiators, and the pressurised modules from Harmony (front) to Zvezda,
// with a Crew Dragon, a Soyuz and a Progress docked.
func iss() -> SCNNode {
  spacecraft { r in
    let hull = material("paint", 0xE8E7E0, metal: 0.12, rough: 0.62)
    let ty: Float = 4.6, tz: Float = -10 // truss axis
    // Integrated truss: S0 in the middle, S1/P1, S3/P3, the alpha joints, then
    // the two array segments either side.
    lattice(r, from: -6.7, to: 6.7, y: ty, z: tz, size: 4.4, bays: 3, r: 0.12, trussSilver)
    box(r, 12.6, 2.6, 2.6, foilSilver, 0, ty, tz)
    for s in [-1, 1] as [Float] {
      lattice(r, from: s * 6.7, to: s * 20.4, y: ty, z: tz, size: 4.0, bays: 3, r: 0.11, trussSilver)
      box(r, 12.6, 1.6, 1.8, radiatorWhite, s * 13.5, ty - 0.4, tz)
      box(r, 3.0, 1.2, 1.2, foilGold, s * 10.5, ty + 1.0, tz + 0.6)
      lattice(r, from: s * 20.4, to: s * 24.5, y: ty, z: tz, size: 3.6, bays: 1, r: 0.1, trussSilver)
      box(r, 3.6, 2.2, 2.2, foilSilver, s * 22.4, ty, tz)
      put(r, CylinderMesh(radius: 2.1, height: 2.0, sides: 28), foilSilver, s * 25.5, ty, tz, rz: .pi / 2)
      put(r, TubeMesh(innerRadius: 2.1, outerRadius: 2.25, height: 0.3, sides: 28), trussSilver, s * 24.7, ty, tz, rz: .pi / 2)
      put(r, TubeMesh(innerRadius: 2.1, outerRadius: 2.25, height: 0.3, sides: 28), trussSilver, s * 26.3, ty, tz, rz: .pi / 2)
      lattice(r, from: s * 26.5, to: s * 54.0, y: ty, z: tz, size: 3.0, bays: 9, r: 0.09, trussSilver)
      for xc in [33.0, 48.0] as [Float] {
        box(r, 11.0, 1.3, 1.3, radiatorWhite, s * xc, ty, tz)
        for dz in [-1, 1] as [Float] {
          put(r, CylinderMesh(radius: 0.7, height: 1.0, sides: 18), foilSilver, s * xc, ty, tz + dz * 2.0, rx: .pi / 2)
        }
      }
      // Main heat-rejection radiators off S1/P1 and photovoltaic radiators.
      for xc in [11.4, 15.2, 19.0] as [Float] {
        radiatorWing(r, at: V3(s * xc, ty - 1.8, tz + 1.8), w: 3.4, l: 22.5, panels: 8, pitch: 0.52, dir: 1)
      }
      radiatorWing(r, at: V3(s * 40.5, ty - 1.4, tz - 1.4), w: 3.1, l: 13.2, panels: 7, pitch: 0.55, dir: -1)
      // Express logistics carriers on S3/P3.
      for (dy, top) in [(Float(-2.3), false), (Float(2.3), true)] where !(s > 0 && top) {
        box(r, 4.2, 0.3, 4.6, trussSilver, s * 22.4, ty + dy, tz)
        for (i, m) in [radiatorWhite, foilGold, composite, foilSilver].enumerated() {
          let px = s * 22.4 + (Float(i % 2) - 0.5) * 2.0, pz = tz + (Float(i / 2) - 0.5) * 2.2
          box(r, 1.6, 1.0, 1.8, m, px, ty + dy + (top ? 0.65 : -0.65), pz)
        }
      }
      // Wings: P4/S4 and P6/S6, each with one wing forward and one aft.
      for (xc, rosaFwd, rosaAft) in [(Float(33), true, true), (Float(48), s < 0, s < 0)] {
        issWing(r, x: s * xc, y: ty, zRoot: tz - 1.6, dir: -1, rosa: rosaFwd)
        issWing(r, x: s * xc, y: ty, zRoot: tz + 1.6, dir: 1, rosa: rosaAft)
      }
    }
    // AMS-02 on top of S3.
    put(r, TubeMesh(innerRadius: 0.8, outerRadius: 1.6, height: 1.5, sides: 28), foilSilver, 22.4, ty + 3.1, tz)
    box(r, 3.4, 0.12, 2.4, radiatorWhite, 22.4, ty + 4.0, tz - 1.9, rx: 0.4)
    box(r, 3.4, 0.12, 2.4, radiatorWhite, 22.4, ty + 4.0, tz + 1.9, rx: -0.4)
    box(r, 2.2, 1.0, 2.2, foilGold, 22.4, ty + 2.1, tz)
    // S0 struts down to Destiny.
    for (x, z) in [(-1.6, -12.5), (1.6, -12.5), (-1.6, -7.5), (1.6, -7.5)] as [(Float, Float)] {
      tube(r, V3(x, ty - 2.2, z), V3(x * 0.6, 1.6, z), 0.14, trussSilver)
    }
    // Mobile base and Canadarm2 reaching forward over Harmony.
    box(r, 5.6, 2.4, 1.4, foilGold, 5.0, ty, tz - 2.9)
    let shoulder = V3(5.0, ty + 1.6, tz - 3.8), elbow = V3(5.0, ty + 7.6, tz - 9.5), wrist = V3(5.0, ty + 3.6, tz - 15.5)
    tube(r, V3(5.0, ty, tz - 3.6), shoulder, 0.3, composite)
    tube(r, shoulder, elbow, 0.2, radiatorWhite)
    tube(r, elbow, wrist, 0.2, radiatorWhite)
    for j in [shoulder, elbow, wrist] { put(r, CylinderMesh(radius: 0.36, height: 0.9, sides: 14), composite, j.x, j.y, j.z, rz: .pi / 2) }
    tube(r, wrist, wrist + V3(0, -1.4, -0.6), 0.25, composite)
    // US segment: Harmony with Columbus and Kibo, Destiny, Unity with Quest,
    // Tranquility, the Cupola, Leonardo and BEAM.
    module(r, V3(0, 0, -22.2), V3(0, 0, -15.0), r: 2.2, hull)
    put(r, LatheMesh([SIMD2(0, 1.4), SIMD2(1.7, 0.95)], sides: 24), hull, 0, 0, -22.2, rx: -.pi / 2)
    put(r, TubeMesh(innerRadius: 0.6, outerRadius: 0.95, height: 0.4, sides: 24), trussSilver, 0, 0, -24.1, rx: .pi / 2)
    module(r, V3(2.2, 0, -18.6), V3(9.1, 0, -18.6), r: 2.25, hull)
    box(r, 0.8, 1.6, 2.2, foilGold, 9.4, 1.0, -18.6)
    box(r, 0.6, 1.2, 1.6, radiatorWhite, 9.3, -1.2, -18.0)
    module(r, V3(-2.2, 0, -18.6), V3(-13.4, 0, -18.6), r: 2.2, hull, bands: 4)
    module(r, V3(-6.6, 2.0, -18.6), V3(-6.6, 6.2, -18.6), r: 2.1, hull, bands: 2)
    box(r, 6.0, 0.8, 5.0, trussSilver, -16.6, -0.6, -18.6)
    for (i, m) in [foilGold, radiatorWhite, foilSilver, composite, radiatorWhite, foilGold].enumerated() {
      box(r, 1.6, 1.0, 1.4, m, -14.6 - Float(i % 3) * 1.9, 0.3, -20.0 + Float(i / 3) * 2.8)
    }
    tube(r, V3(-13.4, 1.6, -18.6), V3(-15.0, 4.6, -16.8), 0.14, radiatorWhite)
    tube(r, V3(-15.0, 4.6, -16.8), V3(-18.0, 3.4, -17.6), 0.12, radiatorWhite)
    module(r, V3(0, 0, -15.0), V3(0, 0, -6.5), r: 2.15, hull)
    module(r, V3(0, 0, -6.5), V3(0, 0, -1.0), r: 2.3, hull, bands: 2)
    module(r, V3(2.3, 0, -3.75), V3(5.5, 0, -3.75), r: 2.0, hull, bands: 2)
    module(r, V3(5.5, 0, -3.75), V3(7.8, 0, -3.75), r: 1.0, hull, bands: 1)
    for (y, z) in [(Float(2.0), Float(-5.2)), (2.0, -2.3), (-2.0, -5.2), (-2.0, -2.3)] {
      put(r, LatheMesh([SIMD2(-0.6, 0.001), SIMD2(-0.42, 0.42), SIMD2(0, 0.6), SIMD2(0.42, 0.42), SIMD2(0.6, 0.001)], sides: 14), foilSilver, 4.2, y, z)
    }
    module(r, V3(-2.3, 0, -3.75), V3(-9.0, 0, -3.75), r: 2.25, hull)
    module(r, V3(-6.2, 0, -6.0), V3(-6.2, 0, -12.4), r: 2.2, hull)
    put(r, LatheMesh([SIMD2(0, 1.5), SIMD2(0.5, 1.5), SIMD2(0.9, 1.25), SIMD2(1.2, 0.75), SIMD2(1.3, 0.001)], sides: 6), hull, -5.4, -2.2, -3.75, rx: .pi)
    put(r, CylinderMesh(radius: 0.62, height: 0.04, sides: 20), glass, -5.4, -3.52, -3.75)
    for k in 0..<6 {
      let a = Float(k) * .pi / 3 + .pi / 6
      box(r, 0.7, 0.06, 0.5, glass, -5.4 + cos(a) * 1.1, -3.25, -3.75 + sin(a) * 1.1, rx: sin(a) * 0.55, rz: -cos(a) * 0.55)
    }
    put(r, LatheMesh([SIMD2(0, 1.0), SIMD2(0.4, 1.5), SIMD2(1.6, 1.5), SIMD2(2.0, 0.9)], sides: 24), hull, -6.2, 0, -1.5, rx: .pi / 2)
    // Russian segment: PMA-1, Zarya (with Rassvet below), Zvezda (with Poisk
    // above and Nauka with Prichal below) and Zvezda's solar wings.
    put(r, LatheMesh([SIMD2(0, 1.5), SIMD2(1.8, 1.05)], sides: 24), hull, 0, 0, -1.0, rx: .pi / 2)
    put(r, LatheMesh([SIMD2(0, 0.95), SIMD2(0.4, 1.35), SIMD2(1.5, 1.4), SIMD2(2.2, 2.05), SIMD2(12.6, 2.05)], sides: 28), hull, 0, 0, 0.8, rx: .pi / 2)
    for z in [5.0, 8.4, 11.6] as [Float] {
      put(r, TubeMesh(innerRadius: 2.05, outerRadius: 2.1, height: 0.14, sides: 28), moduleBand, 0, 0, z, rx: .pi / 2)
    }
    for s in [-1, 1] as [Float] { box(r, 0.08, 1.6, 6.0, radiatorWhite, s * 2.08, 0.6, 8.0) }
    module(r, V3(0, -1.3, 2.3), V3(0, -7.3, 2.3), r: 1.17, hull, bands: 2)
    put(r, LatheMesh([SIMD2(0, 0.6), SIMD2(0.2, 1.05), SIMD2(0.7, 1.15), SIMD2(1.3, 1.05), SIMD2(1.9, 1.45),
                      SIMD2(5.9, 1.45), SIMD2(6.9, 2.07), SIMD2(11.6, 2.07), SIMD2(12.0, 1.4), SIMD2(13.1, 1.0)], sides: 28), hull, 0, 0, 13.4, rx: .pi / 2)
    for z in [21.6, 23.4] as [Float] {
      put(r, TubeMesh(innerRadius: 2.07, outerRadius: 2.12, height: 0.14, sides: 28), moduleBand, 0, 0, z, rx: .pi / 2)
    }
    module(r, V3(0, 1.0, 14.1), V3(0, 5.1, 14.1), r: 1.27, hull, bands: 1)
    module(r, V3(0, -1.0, 14.1), V3(0, -14.1, 14.1), r: 2.1, hull, bands: 4)
    put(r, LatheMesh([SIMD2(-1.65, 0.001), SIMD2(-1.2, 1.12), SIMD2(0, 1.65), SIMD2(1.2, 1.12), SIMD2(1.65, 0.001)], sides: 24), hull, 0, -15.7, 14.1)
    for s in [-1, 1] as [Float] {
      tube(r, V3(s * 2.1, -12.0, 14.1), V3(s * 3.0, -12.0, 14.1), 0.08, trussSilver)
      for i in 0..<2 { solarPanel(r, x: s * (3.0 + 1.0 + Float(i) * 2.05), y: -12.0, z: 14.1, w: 2.0, l: 2.6, cols: 3, rows: 4, t: 0.05) }
      tube(r, V3(s * 2.07, 0, 23.0), V3(s * 2.7, 0, 23.0), 0.08, trussSilver)
      for i in 0..<4 { solarPanel(r, x: s * (2.75 + 1.55 + Float(i) * 3.15), y: 0, z: 23.0, w: 3.1, l: 3.3, cols: 3, rows: 4, t: 0.05) }
    }
    // Visiting vehicles: Crew Dragon on Harmony's front port, Soyuz under
    // Rassvet, Progress on Zvezda's aft port.
    buildDragon(holder(r, V3(0, 0, -24.4), ry: .pi), capsule: rocketWhite)
    buildSoyuz(holder(r, V3(0, -7.6, 2.3), rx: .pi / 2), cargo: false)
    buildSoyuz(holder(r, V3(0, 0, 26.9)), cargo: true)
  }
}

// MARK: Starbase
// Super Heavy + Starship and the Pad A launch tower ("Mechazilla") and
// launch mount. Built upright (y up) and collapsed into one mesh per
// material like the spacecraft. All three share one heading at a pad: the
// tower's chopsticks and the ship's heat shield face -Z, the mount's booster
// quick-disconnect faces +Z, so the tower goes 22 m behind the mount (+Z
// before heading is applied).

let stainless = material("paint", 0x71757A, metal: 0.9, rough: 0.35)
let stainlessDark = material("paint", 0x6A6E73, metal: 0.9, rough: 0.38)
let stainlessLight = material("paint", 0x787C80, metal: 0.9, rough: 0.32)
let weldSeam = material("weld", 0x45484C, metal: 0.85, rough: 0.5)
let blackTile = material("heat-shield", 0x060607, rough: 0.9)
let tileGap = material("tile-gap", 0x1A1B1D, rough: 0.8)
let gridFinSteel = material("grid-fin", 0x1E2022, metal: 0.35, rough: 0.5)
let soot = material("soot", 0x3A3B3D, metal: 0.4, rough: 0.75)
let raptorBell = material("raptor", 0x141516, metal: 0.35, rough: 0.55)
let raptorBay = material("engine-bay", 0x1C1D20, metal: 0.4, rough: 0.7)
let ventDark = material("vent", 0x111214, rough: 0.9)
let towerSteel = material("tower-steel", 0x111214, metal: 0.3, rough: 0.65)
let braceSteel = material("brace-steel", 0x191B1E, metal: 0.3, rough: 0.65)
let railSteel = material("rail", 0x4A4E52, metal: 0.45, rough: 0.45)
let grating = material("grating", 0x2A2C2F, metal: 0.4, rough: 0.75)
let concrete = material("concrete", 0x3E3C38, rough: 0.92)
let scorch = material("scorch", 0x252421, rough: 0.95)
let mountSteel = material("mount-steel", 0x5C5F62, metal: 0.3, rough: 0.55)
let mountShade = material("mount-steel-shade", 0x45484C, metal: 0.35, rough: 0.6)
let clampDark = material("clamp", 0x2C2E31, metal: 0.6, rough: 0.5)
let pipeWhite = material("pipe", 0x6E7071, metal: 0.25, rough: 0.45)
let towerPipe = material("tower-pipe", 0x4A4E52, metal: 0.25, rough: 0.5)
let cableBlack = material("cable", 0x18191B, metal: 0.6, rough: 0.5)
let beaconRed = material("beacon", 0xFF2A1A, rough: 0.4, emit: true)

/// A convex polygon in the XY plane extruded `t` along Z (centred), closed,
/// with flat normals.
func SlabMesh(_ outline: [SIMD2<Float>], thickness t: Float) -> SCNGeometry {
  var pts = outline
  var area: Float = 0
  for i in 0..<pts.count {
    let a = pts[i], b = pts[(i + 1) % pts.count]
    area += a.x * b.y - b.x * a.y
  }
  if area < 0 { pts.reverse() }
  let h = t / 2, k = pts.count
  var p: [V3] = [], n: [V3] = [], idx: [UInt32] = []
  for (z, nz) in [(h, Float(1)), (-h, Float(-1))] {
    let base = UInt32(p.count)
    for q in pts { p.append(V3(q.x, q.y, z)); n.append(V3(0, 0, nz)) }
    for i in 1..<UInt32(k - 1) {
      idx += nz > 0 ? [base, base + i, base + i + 1] : [base, base + i + 1, base + i]
    }
  }
  for i in 0..<k {
    let a = pts[i], b = pts[(i + 1) % k]
    let e = simd_normalize(b - a)
    let normal = V3(e.y, -e.x, 0)
    let base = UInt32(p.count)
    p += [V3(a.x, a.y, -h), V3(b.x, b.y, -h), V3(b.x, b.y, h), V3(a.x, a.y, h)]
    n += Array(repeating: normal, count: 4)
    idx += [base, base + 1, base + 2, base, base + 2, base + 3]
  }
  return meshGeometry(p, n, idx)
}

/// A box beam from `a` to `b`, `w` wide and `d` deep; the depth runs along
/// `up` (made perpendicular to the beam), the width across both.
@discardableResult
func strut(_ p: SCNNode, _ a: V3, _ b: V3, _ w: Float, _ d: Float, _ m: SCNMaterial, up: V3 = V3(0, 0, 1)) -> SCNNode {
  let L = simd_length(b - a)
  let y = (b - a) / L
  var z = up - simd_dot(up, y) * y
  if simd_length(z) < 1e-4 { z = simd_cross(y, V3(1, 0, 0)) }
  if simd_length(z) < 1e-4 { z = simd_cross(y, V3(0, 1, 0)) }
  z = simd_normalize(z)
  let x = simd_cross(y, z)
  let n = SCNNode()
  n.simdPosition = (a + b) / 2
  n.simdOrientation = simd_quatf(simd_float3x3(x, y, z))
  p.addChildNode(n)
  put(n, BoxMesh(width: CGFloat(w), height: CGFloat(L), length: CGFloat(d)), m, 0, 0, 0)
  return n
}

/// An open band of radius `r` around Y from y0 to y1 (part of the way round
/// with `from`/`to`).
func band(_ p: SCNNode, _ y0: Float, _ y1: Float, _ r: Float, _ m: SCNMaterial, sides: Int = 56,
          from a0: Float = 0, to a1: Float = 2 * .pi) {
  put(p, LatheMesh([SIMD2(y0, r), SIMD2(y1, r)], sides: sides, caps: false, from: a0, to: a1), m, 0, 0, 0)
}

/// A flat ring facing up at height y, from radius r0 to r1.
func annulus(_ p: SCNNode, y: Float, _ r0: Float, _ r1: Float, _ m: SCNMaterial, sides: Int = 48) {
  put(p, LatheMesh([SIMD2(y, r1), SIMD2(y, r0)], sides: sides, caps: false), m, 0, 0, 0)
}

/// A frame turned so its local +X points out from the Y axis at angle `a`
/// (world (cos a, 0, sin a)) and +Z runs round the circle.
func around(_ p: SCNNode, _ a: Float) -> SCNNode { holder(p, V3(0, 0, 0), ry: -a) }

/// A tapering box truss along local -Z from z = -z0 to -z1: four chords, a
/// frame every bay and alternating diagonals on the sides and bottom. The top
/// stays flat at y = 0; the section shrinks from w0 x h0 to w1 x h1.
func boxTruss(_ p: SCNNode, z0: Float, z1: Float, w0: Float, h0: Float, w1: Float, h1: Float, bays: Int,
              chord: Float, web: Float, _ m: SCNMaterial, webMaterial: SCNMaterial) {
  func at(_ t: Float, _ sx: Float, _ bottom: Bool) -> V3 {
    let w = w0 + (w1 - w0) * t, h = h0 + (h1 - h0) * t
    return V3(sx * w / 2, bottom ? -h : 0, -(z0 + (z1 - z0) * t))
  }
  for sx: Float in [-1, 1] {
    for bottom in [false, true] {
      strut(p, at(0, sx, bottom), at(1, sx, bottom), chord, chord, m, up: V3(0, 1, 0))
    }
  }
  for i in 0...bays {
    let t = Float(i) / Float(bays), tn = Float(i + 1) / Float(bays)
    for sx: Float in [-1, 1] {
      strut(p, at(t, sx, false), at(t, sx, true), web, web, webMaterial, up: V3(1, 0, 0))
      if i < bays {
        let up = i % 2 == 0
        strut(p, at(t, sx, up), at(tn, sx, !up), web, web, webMaterial, up: V3(1, 0, 0))
      }
    }
    strut(p, at(t, -1, true), at(t, 1, true), web, web, webMaterial, up: V3(0, 1, 0))
    strut(p, at(t, -1, false), at(t, 1, false), web, web, webMaterial, up: V3(0, 1, 0))
    if i < bays {
      let flip: Float = i % 2 == 0 ? 1 : -1
      strut(p, at(t, -flip, true), at(tn, flip, true), web * 0.8, web * 0.8, webMaterial, up: V3(0, 1, 0))
    }
  }
}

/// Super Heavy's waffle grid fin, lying flat, from radius x0 to x1 and
/// `halfWidth` either side, at height y (in an `around` frame).
func gridFin(_ p: SCNNode, x0: Float, x1: Float, halfWidth hw: Float, y: Float, depth: Float) {
  let Lx = x1 - x0, Lz = 2 * hw
  box(p, 0.24, depth, Lz + 0.24, gridFinSteel, x0, y, 0)
  box(p, 0.24, depth, Lz + 0.24, gridFinSteel, x1, y, 0)
  box(p, Lx, depth, 0.24, gridFinSteel, x0 + Lx / 2, y, -hw)
  box(p, Lx, depth, 0.24, gridFinSteel, x0 + Lx / 2, y, hw)
  let step: Float = 0.42 * 1.4142
  func point(_ u: Float, _ v: Float) -> V3 { V3(x0 + u, y, v - hw) }
  var c = -Lz + step / 2
  while c < Lx {
    let u0 = max(0, c), u1 = min(Lx, Lz + c)
    if u1 - u0 > 0.15 { strut(p, point(u0, u0 - c), point(u1, u1 - c), 0.07, depth * 0.94, gridFinSteel, up: V3(0, 1, 0)) }
    c += step
  }
  c = step / 2
  while c < Lx + Lz {
    let u0 = max(0, c - Lz), u1 = min(Lx, c)
    if u1 - u0 > 0.15 { strut(p, point(u0, c - u0), point(u1, c - u1), 0.07, depth * 0.94, gridFinSteel, up: V3(0, 1, 0)) }
    c += step
  }
}

/// Hexagonal tile gaps over a body of revolution: thin lines a little above
/// the surface between angles a0 and a1, from y0 up to where the radius
/// drops below `minRadius`. `cell` is the hexagon's circumradius.
func hexTileLines(_ p: SCNNode, radius: (Float) -> Float, y0: Float, y1: Float, a0: Float, a1: Float,
                  cell rho: Float, lift: Float, width: Float, minRadius: Float, _ m: SCNMaterial) {
  let mesh = Mesh()
  let r0 = radius(y0)
  let cols = max(1, Int(((a1 - a0) * r0 / (rho * 1.7320508)).rounded()))
  let dTheta = (a1 - a0) / Float(cols)
  let dy = rho * 1.5
  func surface(_ theta: Float, _ y: Float) -> (V3, V3) {
    let r = radius(y)
    let slope = (radius(min(y1, y + 0.05)) - radius(max(y0, y - 0.05))) / 0.1
    let normal = simd_normalize(V3(cos(theta), -slope, sin(theta)))
    return (V3(cos(theta) * r, y, sin(theta) * r) + normal * lift, normal)
  }
  func edge(_ t0: Float, _ ya: Float, _ t1: Float, _ yb: Float) {
    guard ya >= y0, yb >= y0, ya <= y1, yb <= y1, min(t0, t1) >= a0 - 1e-4, max(t0, t1) <= a1 + 1e-4 else { return }
    guard radius(ya) > minRadius, radius(yb) > minRadius else { return }
    let (pa, na) = surface(t0, ya), (pb, nb) = surface(t1, yb)
    let normal = simd_normalize(na + nb)
    let side = simd_normalize(simd_cross(normal, pb - pa)) * (width / 2)
    let base = UInt32(mesh.positions.count)
    mesh.positions += [pa - side, pb - side, pb + side, pa + side]
    mesh.normals += Array(repeating: normal, count: 4)
    mesh.indices += [base, base + 1, base + 2, base, base + 2, base + 3]
  }
  var row = 0
  var yc = y0 + rho * 0.5
  while yc < y1 + rho {
    let shift: Float = row % 2 == 0 ? 0 : 0.5
    for col in -1...cols {
      let tc = a0 + (Float(col) + 0.5 + shift) * dTheta
      let hx = dTheta / 2
      edge(tc + hx, yc + rho / 2, tc, yc + rho)        // upper right
      edge(tc, yc + rho, tc - hx, yc + rho / 2)        // upper left
      edge(tc - hx, yc + rho / 2, tc - hx, yc - rho / 2) // left side
    }
    yc += dy; row += 1
  }
  if !mesh.indices.isEmpty { p.addChildNode(SCNNode(geometry: mesh.geometry(m))) }
}

/// A square column tapering from `bottom` wide at y = 0 to `top` wide at
/// y = height, with flat faces and caps.
func TaperedBoxMesh(bottom: Float, top: Float, height h: Float) -> SCNGeometry {
  let hb = bottom / 2, ht = top / 2
  let corners: [SIMD2<Float>] = [SIMD2(1, 1), SIMD2(1, -1), SIMD2(-1, -1), SIMD2(-1, 1)] // (x, z)
  var p: [V3] = [], n: [V3] = [], idx: [UInt32] = []
  for i in 0..<4 {
    let c0 = corners[i], c1 = corners[(i + 1) % 4]
    let mid = (c0 + c1) / 2
    let normal = simd_normalize(V3(mid.x * h, hb - ht, mid.y * h))
    let base = UInt32(p.count)
    p += [V3(c0.x * hb, 0, c0.y * hb), V3(c1.x * hb, 0, c1.y * hb), V3(c1.x * ht, h, c1.y * ht), V3(c0.x * ht, h, c0.y * ht)]
    n += Array(repeating: normal, count: 4)
    idx += [base, base + 1, base + 2, base, base + 2, base + 3]
  }
  for (y, half, up) in [(h, ht, true), (Float(0), hb, false)] {
    let base = UInt32(p.count)
    for c in corners { p.append(V3(c.x * half, y, c.y * half)); n.append(V3(0, up ? 1 : -1, 0)) }
    idx += up ? [base, base + 1, base + 2, base, base + 2, base + 3] : [base, base + 2, base + 1, base, base + 3, base + 2]
  }
  return meshGeometry(p, n, idx)
}

/// Starship's ogive nose radius, t = 0 at the base to 1 at the tip.
func starshipNose(_ t: Float, _ R: Float) -> Float { R * sqrt(max(0, 1 - pow(max(0, t), 1.25))) }

// Super Heavy (71 m with the hot-staging ring) and Starship (52 m), 9 m
// across, 123 m tall. Base (the booster's aft skirt) on y = 0; the ship's
// heat shield faces -Z. Stainless steel is `paint`.
func starshipStack() -> SCNNode {
  spacecraft { r in
    let R: Float = 4.5
    let hsr0: Float = 69.2, ship0: Float = 71.0, nose0: Float = 107.0, tipY: Float = 123.0
    let shades = [stainless, stainlessDark, stainless, stainlessLight, stainless, stainlessDark, stainlessLight]
    // Hull: 1.8 m rings, each a slightly different shade, with weld seams.
    func rings(_ y0: Float, _ y1: Float, seed: Int) {
      var y = y0, i = seed
      while y < y1 - 0.01 {
        let top = min(y1, y + 1.8)
        band(r, y, top, R, shades[(i * 3 + i / 2) % shades.count])
        if top < y1 - 0.01 { band(r, top - 0.035, top + 0.035, R + 0.012, weldSeam) }
        y = top; i += 1
      }
    }

    // --- Super Heavy ---
    rings(0, hsr0, seed: 0)
    band(r, 0, 0.55, R + 0.01, soot)                                   // scorched aft skirt edge
    put(r, LatheMesh([SIMD2(2.2, R - 0.03), SIMD2(0, R - 0.03)], sides: 56, caps: false), raptorBay, 0, 0, 0)
    put(r, CylinderMesh(radius: CGFloat(R - 0.03), height: 0.2, sides: 56), raptorBay, 0, 2.1, 0) // aft heat shield
    put(r, CylinderMesh(radius: CGFloat(R), height: 0.2, sides: 56), stainlessDark, 0, hsr0 - 0.1, 0)
    // 33 Raptors: 3 centre, 10 inner ring, 20 outer ring.
    let bell: [SIMD2<Float>] = [SIMD2(0.1, 0.56), SIMD2(0.45, 0.49), SIMD2(0.9, 0.39), SIMD2(1.4, 0.29), SIMD2(2.0, 0.22)]
    var spots: [SIMD2<Float>] = []
    for i in 0..<3 { let a = Float(i) / 3 * 2 * .pi + .pi / 2; spots.append(SIMD2(cos(a), sin(a)) * 0.8) }
    for i in 0..<10 { let a = Float(i) / 10 * 2 * .pi; spots.append(SIMD2(cos(a), sin(a)) * 2.35) }
    for i in 0..<20 { let a = (Float(i) + 0.5) / 20 * 2 * .pi; spots.append(SIMD2(cos(a), sin(a)) * 3.82) }
    for s in spots {
      put(r, LatheMesh(bell, sides: 16, caps: false, twoSided: true), raptorBell, s.x, 0, s.y)
    }
    // Four grid fins near the top, a quarter-turn apart, with actuator housings.
    let finY: Float = 65.4
    for k in 0..<4 {
      let h = around(r, Float(k) * .pi / 2 + .pi / 4)
      box(h, 0.8, 2.6, 2.8, gridFinSteel, R + 0.3, finY + 0.2, 0)
      gridFin(holder(h, V3(0, finY, 0), rx: 0.21), x0: R + 0.6, x1: R + 4.8, halfWidth: 2.6, y: 0, depth: 1.2)
    }
    // Chopstick catch points on the two sides between the fins.
    for a: Float in [0, .pi] {
      let h = around(r, a)
      box(h, 0.9, 1.1, 1.6, gridFinSteel, R + 0.4, 62.6, 0)
    }
    // Two chines down the sides and a raceway down the front-left.
    for a: Float in [0, .pi] {
      let h = around(r, a)
      put(h, SlabMesh([SIMD2(R - 0.05, 5), SIMD2(R + 0.5, 8.5), SIMD2(R + 0.5, 56), SIMD2(R - 0.05, 59.5)], thickness: 0.32),
          stainlessDark, 0, 0, 0)
    }
    let raceway = around(r, 1.5 * .pi - 0.55)
    box(raceway, 0.34, 64, 0.8, stainlessDark, R + 0.17, 35, 0)
    put(raceway, CylinderMesh(radius: 0.13, height: 62, sides: 8), stainlessDark, R + 0.14, 35, 0.62)
    // Vented hot-staging ring: dark interior behind 30 steel posts.
    put(r, CylinderMesh(radius: CGFloat(R - 0.16), height: CGFloat(ship0 - hsr0), sides: 56), ventDark, 0, (hsr0 + ship0) / 2, 0)
    for y in [hsr0 + 0.15, ship0 - 0.15] {
      put(r, TubeMesh(innerRadius: CGFloat(R - 0.4), outerRadius: CGFloat(R + 0.02), height: 0.3, sides: 56), stainlessDark, 0, y, 0)
    }
    for i in 0..<30 {
      let h = around(r, Float(i) / 30 * 2 * .pi)
      box(h, 0.24, ship0 - hsr0 - 0.5, 0.42, stainlessDark, R - 0.1, (hsr0 + ship0) / 2, 0)
    }

    // --- Starship ---
    rings(ship0, nose0, seed: 5)
    put(r, CylinderMesh(radius: CGFloat(R), height: 0.1, sides: 56), stainlessDark, 0, ship0 + 0.05, 0)
    var noseProfile: [SIMD2<Float>] = []
    for t in stride(from: Float(0), to: 0.9, by: 0.05) + [0.9, 0.93, 0.96, 0.98, 0.993, 1.0] {
      noseProfile.append(SIMD2(nose0 + (tipY - nose0) * t, starshipNose(t, R)))
    }
    put(r, LatheMesh(noseProfile, sides: 56, caps: false), stainless, 0, 0, 0)
    for t: Float in [0.22, 0.45, 0.66] {
      let y = nose0 + (tipY - nose0) * t, rr = starshipNose(t, R)
      band(r, y - 0.035, y + 0.035, rr + 0.012, weldSeam)
    }
    // Heat shield: black hexagonal tiles over the windward half, base to tip.
    func shipRadius(_ y: Float) -> Float { y <= nose0 ? R : starshipNose((y - nose0) / (tipY - nose0), R) }
    let tileFrom: Float = .pi - 0.07, tileTo: Float = 2 * .pi + 0.07
    var shield: [SIMD2<Float>] = [SIMD2(ship0 + 0.02, R + 0.05)]
    for q in noseProfile { shield.append(SIMD2(q.x, q.y + 0.05)) }
    shield[shield.count - 1] = SIMD2(tipY + 0.05, 0.001)
    put(r, LatheMesh(shield, sides: 44, caps: false, from: tileFrom, to: tileTo), blackTile, 0, 0, 0)
    hexTileLines(r, radius: shipRadius, y0: ship0 + 0.02, y1: tipY, a0: tileFrom, a1: tileTo,
                 cell: 0.55, lift: 0.065, width: 0.04, minRadius: 1.0, tileGap)
    // Aft flaps on the tile edges at the base, with root fairings.
    for a: Float in [0, .pi] {
      let h = around(r, a)
      put(h, SlabMesh([SIMD2(R - 0.2, ship0 + 0.6), SIMD2(R + 0.8, ship0 + 1.6), SIMD2(R + 0.8, ship0 + 12.8),
                       SIMD2(R - 0.2, ship0 + 14.0)], thickness: 1.3), blackTile, 0, 0, 0)
      put(h, SlabMesh([SIMD2(R + 0.5, ship0 + 1.0), SIMD2(R + 4.3, ship0 + 2.4), SIMD2(R + 4.3, ship0 + 9.6),
                       SIMD2(R + 0.5, ship0 + 13.0)], thickness: 0.42), blackTile, 0, 0, 0)
    }
    // Forward flaps on the nose, set back towards the leeward side.
    let fy0 = nose0 + 1.2, fy1 = nose0 + 8.2
    let fr0 = shipRadius(fy0), fr1 = shipRadius(fy1)
    for a: Float in [0.3, .pi - 0.3] {
      let h = around(r, a)
      put(h, SlabMesh([SIMD2(fr0 - 0.25, fy0 - 0.6), SIMD2(fr0 + 0.5, fy0), SIMD2(fr1 + 0.5, fy1),
                       SIMD2(fr1 - 0.25, fy1 + 0.7)], thickness: 1.0), blackTile, 0, 0, 0)
      put(h, SlabMesh([SIMD2(fr0 + 0.3, fy0 + 0.2), SIMD2(fr0 + 2.9, fy0 + 1.1), SIMD2(fr1 + 2.2, fy1 - 0.7),
                       SIMD2(fr1 + 0.3, fy1)], thickness: 0.36), blackTile, 0, 0, 0)
    }
    // Leeward details: raceway and the payload (PEZ) door slot.
    let shipRaceway = around(r, 0.62)
    box(shipRaceway, 0.3, nose0 - ship0, 0.7, stainlessDark, R + 0.15, (ship0 + nose0) / 2 + 1, 0)
    band(r, ship0 + 27, ship0 + 27.8, R + 0.02, ventDark, sides: 20, from: .pi / 2 - 0.5, to: .pi / 2 + 0.5)
  }
}

/// Pad A's Orbital Launch Tower: a 10 m square, 145 m steel lattice in nine
/// modules, lightning rod on top, the chopsticks carriage riding the front
/// face with both arms open towards -Z (parked astride the booster's top when
/// the rocket stands 22 m in front), and the ship quick-disconnect arm swung
/// out to the ship. Base on y = 0, centred on the origin.
func starbaseTower() -> SCNNode {
  spacecraft { r in
    let c: Float = 4.5               // column centre lines (outer faces at ±5 m)
    let base: Float = 1.2, top: Float = 145
    let modules = 9
    let mh = (top - base) / Float(modules)
    let rocketZ: Float = -22         // where the rocket stands
    // Foundation and the drawworks house behind the tower.
    box(r, 15, base, 15, concrete, 0, base / 2, 0)
    box(r, 8, 5, 6, mountShade, 0, base + 2.5, 9.5)
    box(r, 8.4, 0.4, 6.4, towerSteel, 0, base + 5.2, 9.5)
    // Corner columns, spliced at every module joint.
    for sx in [-c, c] {
      for sz in [-c, c] {
        box(r, 1.0, top - base, 1.0, towerSteel, sx, (base + top) / 2, sz)
        for k in 0...modules { box(r, 1.4, 0.6, 1.4, towerSteel, sx, base + Float(k) * mh, sz) }
      }
    }
    // Each face: a girder at every half module and an X brace in each bay.
    let faces: [(SIMD2<Float>, SIMD2<Float>, V3)] = [
      (SIMD2(-c, -c), SIMD2(c, -c), V3(0, 0, -1)), (SIMD2(c, c), SIMD2(-c, c), V3(0, 0, 1)),
      (SIMD2(-c, c), SIMD2(-c, -c), V3(-1, 0, 0)), (SIMD2(c, -c), SIMD2(c, c), V3(1, 0, 0)),
    ]
    let bays = modules * 2
    let bh = (top - base) / Float(bays)
    for (a, b, normal) in faces {
      for j in 0...bays {
        let y = base + Float(j) * bh
        let joint = j % 2 == 0
        strut(r, V3(a.x, y, a.y), V3(b.x, y, b.y), joint ? 0.9 : 0.6, 0.6, towerSteel, up: normal)
        if j < bays {
          let yn = y + bh
          strut(r, V3(a.x, y, a.y), V3(b.x, yn, b.y), 0.42, 0.4, braceSteel, up: normal)
          strut(r, V3(b.x, y, b.y), V3(a.x, yn, a.y), 0.42, 0.4, braceSteel, up: normal)
        }
      }
    }
    // Grating decks at the module joints.
    for k in 1..<modules { box(r, 8.4, 0.2, 8.4, grating, 0, base + Float(k) * mh, 0) }
    // Elevator shaft on the back face, with the car part way up.
    let ez: Float = c + 2.2
    for sx: Float in [-1.2, 1.2] {
      for sz in [ez - 1.2, ez + 1.2] { box(r, 0.3, top - base - 4, 0.3, braceSteel, sx, (base + top - 4) / 2, sz) }
    }
    var ey = base + 4
    while ey < top - 4 {
      box(r, 2.7, 0.25, 0.25, braceSteel, 0, ey, ez + 1.2)
      box(r, 0.25, 0.25, 2.7, braceSteel, -1.2, ey, ez)
      box(r, 0.25, 0.25, 2.7, braceSteel, 1.2, ey, ez)
      ey += 4.5
    }
    box(r, 2.0, 3.0, 2.0, mountSteel, 0, 46, ez)
    // Propellant and gas lines up the left face to the ship QD arm.
    let qdY: Float = 97.5
    for (i, rr) in [Float(0.42), 0.36, 0.3, 0.22].enumerated() {
      let z = -2.8 + Float(i) * 1.0
      put(r, CylinderMesh(radius: CGFloat(rr), height: CGFloat(qdY - base), sides: 10), towerPipe, -c - 1.2, (base + qdY) / 2, z)
    }
    var py = base + 6
    while py < qdY { box(r, 1.0, 0.3, 4.4, braceSteel, -c - 0.9, py, -1.3); py += 8 }
    // Carriage rails on the front corners.
    for sx in [-c + 0.2, c - 0.2] { box(r, 0.4, top - 10, 0.6, railSteel, sx, (top + 10) / 2, -c - 0.85) }
    // Crown: deck, sheave housings, beacons and the lightning rod.
    box(r, 12.4, 0.8, 12.4, towerSteel, 0, top + 0.4, 0)
    for sx: Float in [-3.2, 3.2] {
      box(r, 2.4, 2.6, 3.0, mountShade, sx, top + 2.1, -4.2)
      box(r, 2.4, 2.6, 3.0, mountShade, sx, top + 2.1, 4.2)
    }
    for sx: Float in [-5.9, 5.9] {
      for sz: Float in [-5.9, 5.9] { put(r, CylinderMesh(radius: 0.25, height: 0.5, sides: 8), beaconRed, sx, top + 1.05, sz) }
    }
    box(r, 1.4, 1.2, 1.4, towerSteel, 0, top + 1.4, 0)
    put(r, LatheMesh([SIMD2(top + 2, 0.32), SIMD2(top + 10, 0.07)], sides: 8, caps: true), towerSteel, 0, 0, 0)
    put(r, CylinderMesh(radius: 0.22, height: 0.45, sides: 8), beaconRed, 0, top + 10.2, 0)

    // Chopsticks carriage wrapped round the tower, arms hinged at its front corners.
    let hc: Float = 86, ch: Float = 10, co: Float = 6.4
    for y in [hc - 1, hc + 4, hc + ch - 1] {
      for (a, b, normal) in [(SIMD2<Float>(-co, -co), SIMD2<Float>(co, -co), V3(0, 0, -1)), (SIMD2(co, co), SIMD2(-co, co), V3(0, 0, 1)),
                             (SIMD2(-co, co), SIMD2(-co, -co), V3(-1, 0, 0)), (SIMD2(co, -co), SIMD2(co, co), V3(1, 0, 0))] {
        strut(r, V3(a.x, y, a.y), V3(b.x, y, b.y), 1.0, 0.9, towerSteel, up: normal)
      }
    }
    for (a, b, normal) in [(SIMD2<Float>(-co, co), SIMD2<Float>(-co, -co), V3(-1, 0, 0)), (SIMD2(co, -co), SIMD2(co, co), V3(1, 0, 0)),
                           (SIMD2(co, co), SIMD2(-co, co), V3(0, 0, 1))] {
      strut(r, V3(a.x, hc - 1, a.y), V3(b.x, hc + ch - 1, b.y), 0.55, 0.5, braceSteel, up: normal)
      strut(r, V3(b.x, hc - 1, b.y), V3(a.x, hc + ch - 1, a.y), 0.55, 0.5, braceSteel, up: normal)
    }
    for sx in [-co, co] {
      for sz in [-co, co] { box(r, 1.2, ch, 1.2, towerSteel, sx, hc - 1 + ch / 2, sz) }
      put(r, CylinderMesh(radius: 0.95, height: CGFloat(ch + 1), sides: 14), railSteel, sx, hc - 1.5 + ch / 2, -co) // hinge
      box(r, 1.2, 2.4, 1.0, railSteel, sx * 0.66, hc + 1, -c - 1.4)   // rollers on the rails
      box(r, 1.2, 2.4, 1.0, railSteel, sx * 0.66, hc + ch - 3, -c - 1.4)
    }
    // Hoist cables from the crown sheaves to the carriage, and down the back to the drawworks.
    for sx: Float in [-3.6, -2.8, 2.8, 3.6] {
      box(r, 0.12, top - (hc + ch - 1), 0.12, cableBlack, sx, (top + hc + ch - 1) / 2, -5.9)
      box(r, 0.12, top - base - 5, 0.12, cableBlack, sx, (top + base + 5) / 2, 5.9)
    }
    // The arms: 36 m tapering trusses, open 14° each side, flat tops with the
    // catch rails and shock-absorbing carriages on the inner edges.
    let armTop = hc + 4.4
    let open: Float = 14 * .pi / 180
    for side: Float in [-1, 1] {
      let arm = holder(r, V3(side * co, armTop, -co), ry: -side * open)
      boxTruss(arm, z0: 0.6, z1: 36, w0: 2.8, h0: 4.4, w1: 1.8, h1: 2.2, bays: 12, chord: 0.55, web: 0.32,
               towerSteel, webMaterial: braceSteel)
      put(arm, SlabMesh([SIMD2(-1.6, -0.6), SIMD2(1.6, -0.6), SIMD2(1.1, -36), SIMD2(-1.1, -36)], thickness: 0.22),
          towerSteel, 0, 0.15, 0, rx: .pi / 2)
      box(arm, 3.4, 4.8, 2.2, towerSteel, 0, -2.3, -0.8)                     // hinge block
      box(arm, 1.9, 2.4, 0.4, towerSteel, 0, -1.1, -36)                      // tip plate
      let inner = -side
      strut(arm, V3(inner * 1.25, 0.55, -1.5), V3(inner * 0.8, 0.55, -35.5), 0.55, 0.5, railSteel, up: V3(0, 1, 0))
      let cz: Float = -17.5
      let cx = inner * (1.4 - 0.5 * (17.5 / 36))
      box(arm, 1.4, 1.0, 3.2, railSteel, cx, 1.2, cz)
      // Hydraulic actuator from the carriage face to the arm.
      strut(arm, V3(-side * 4.0, -2.4, 1.0), V3(inner * 1.0, -2.0, -7.0), 0.45, 0.45, railSteel, up: V3(0, 1, 0))
    }

    // Ship quick-disconnect arm: from the front-left corner to the ship's aft skin.
    let hinge = V3(-c - 0.7, qdY, -c - 0.7)
    let target = V3(-1.2, qdY, rocketZ + 4.34 + 0.4)
    let d = target - hinge
    let qd = holder(r, hinge, ry: atan2(-d.x, -d.z))
    let qdLength = simd_length(d)
    boxTruss(qd, z0: 0.5, z1: qdLength - 1.0, w0: 2.4, h0: 2.8, w1: 2.0, h1: 2.4, bays: 5, chord: 0.4, web: 0.26,
             towerSteel, webMaterial: braceSteel)
    put(qd, CylinderMesh(radius: 0.7, height: 4.4, sides: 12), railSteel, 0, -1.3, 0)
    box(qd, 2.8, 3.2, 1.8, mountSteel, 0, -1.3, -(qdLength - 0.8))           // QD hood
    box(qd, 2.0, 2.2, 0.2, clampDark, 0, -1.3, -(qdLength + 0.15))           // umbilical plate
    for x: Float in [-0.5, 0.5] {
      strut(qd, V3(x, 0.4, -0.5), V3(x, 0.4, -(qdLength - 1.7)), 0.4, 0.4, towerPipe, up: V3(0, 1, 0))
    }
  }
}

/// Pad A's Orbital Launch Mount: a 40 m concrete pad, the water-cooled steel
/// deluge plate, six tapered legs and the table whose ring (18.2 m across,
/// 9.5 m opening) carries the booster at y = 20, with 20 hold-down clamps and
/// the booster quick-disconnect hood facing +Z (towards the tower). Base on
/// y = 0, centred on the origin.
func starbaseMount() -> SCNNode {
  spacecraft { r in
    let pad: Float = 1.0, top: Float = 20
    let legR: Float = 10.6
    box(r, 40, pad, 40, concrete, 0, pad / 2, 0)
    annulus(r, y: pad + 0.01, 7.4, 15.5, scorch)
    // Water-cooled steel deluge plate, burnt in the middle, with water lines.
    put(r, CylinderMesh(radius: 7.6, height: 0.9, sides: 48), mountShade, 0, pad + 0.45, 0)
    annulus(r, y: pad + 0.91, 0, 5.4, soot, sides: 40)
    for rr: Float in [2.2, 3.8, 6.4] { annulus(r, y: pad + 0.92, rr - 0.07, rr + 0.07, scorch, sides: 40) }
    for a: Float in [0.25, .pi - 0.25, .pi + 0.25, -0.25] {
      let h = around(r, a)
      put(h, CylinderMesh(radius: 0.45, height: 10, sides: 12), pipeWhite, 12.6, pad + 0.35, 0, rz: .pi / 2)
    }
    // Six tapered legs on footings, between them the table girders.
    var tops: [V3] = []
    for k in 0..<6 {
      let a = Float(k) / 6 * 2 * .pi
      let x = cos(a) * legR, z = sin(a) * legR
      box(r, 4.4, 1.2, 4.4, concrete, x, pad + 0.6, z)
      put(r, TaperedBoxMesh(bottom: 2.9, top: 2.0, height: 14.8 - pad - 1.2), mountSteel, x, pad + 1.2, z, ry: -a)
      box(r, 2.6, 0.7, 2.6, mountShade, x, 14.9, z)
      tops.append(V3(x, 0, z))
    }
    for k in 0..<6 {
      let a = tops[k], b = tops[(k + 1) % 6]
      let mid = (a + b) / 2
      let out = simd_normalize(mid)
      strut(r, V3(a.x, 17.2, a.z), V3(b.x, 17.2, b.z), 4.4, 1.3, mountSteel, up: out)
      for t: Float in [0.2, 0.35, 0.5, 0.65, 0.8] {      // stiffeners on the girder face
        let q = a + (b - a) * t + out * 0.68
        strut(r, V3(q.x, 15.1, q.z), V3(q.x, 19.3, q.z), 0.22, 0.12, mountShade, up: out)
      }
      let ang = Float(k) / 6 * 2 * .pi
      let radial = V3(cos(ang), 0, sin(ang))
      strut(r, V3(a.x, 17.6, a.z), radial * 5.2 + V3(0, 17.6, 0), 2.8, 1.0, mountShade, up: V3(-sin(ang), 0, cos(ang)))
    }
    // The ring top, its throat and the hold-down clamps.
    put(r, TubeMesh(innerRadius: 4.75, outerRadius: 9.1, height: 1.0, sides: 56), mountSteel, 0, top - 0.5, 0)
    put(r, TubeMesh(innerRadius: 4.75, outerRadius: 5.4, height: 4.8, sides: 56), mountShade, 0, top - 3.4, 0)
    annulus(r, y: top + 0.005, 6.9, 7.1, mountShade, sides: 56)
    for i in 0..<20 {
      let h = around(r, (Float(i) + 0.5) / 20 * 2 * .pi)
      box(h, 0.9, 1.3, 0.75, clampDark, 5.05, top + 0.65, 0)
      box(h, 1.5, 0.5, 1.0, clampDark, 5.5, top + 0.25, 0)
    }
    // Handrail round the ring edge.
    put(r, TorusMesh(ringRadius: 8.95, pipeRadius: 0.06, ringSides: 56, pipeSides: 6), railSteel, 0, top + 1.1, 0)
    for i in 0..<28 {
      let a = Float(i) / 28 * 2 * .pi
      put(r, CylinderMesh(radius: 0.05, height: 1.1, sides: 6), railSteel, cos(a) * 8.95, top + 0.55, sin(a) * 8.95)
    }
    // Deluge supply ring under the table.
    put(r, TorusMesh(ringRadius: 7.6, pipeRadius: 0.3, ringSides: 48, pipeSides: 8), mountShade, 0, 13.6, 0)
    // Booster quick-disconnect hood on the +Z side, its lines running down to the pad.
    let q = around(r, .pi / 2)
    put(q, SlabMesh([SIMD2(4.75, top), SIMD2(8.8, top), SIMD2(8.8, top + 2.6), SIMD2(6.9, top + 4.4), SIMD2(4.75, top + 4.4)],
                    thickness: 5.0), mountSteel, 0, 0, 0)
    box(q, 0.12, 3.0, 3.6, clampDark, 4.72, top + 2.0, 0)
    for z: Float in [-1.6, 1.6] { box(q, 0.1, 1.6, 0.5, clampDark, 8.82, top + 1.4, z) }
    for z: Float in [-1.3, 0, 1.3] {
      put(q, CylinderMesh(radius: 0.42, height: CGFloat(top + 1.5 - pad), sides: 10), pipeWhite, 9.6, (pad + top + 1.5) / 2, z)
      strut(q, V3(9.6, top + 1.5, z), V3(8.6, top + 1.5, z), 0.8, 0.8, pipeWhite, up: V3(0, 1, 0))
    }
    box(q, 1.4, 6, 4.4, mountShade, 9.9, pad + 3, 0)
  }
}

// MARK: Export

/// The USD exporter needs one material per geometry element.
func fixMaterialCounts(_ node: SCNNode) {
  node.enumerateHierarchy { n, _ in
    guard let g = n.geometry else { return }
    let materials = g.materials.isEmpty ? [black] : g.materials
    g.materials = (0..<max(1, g.elements.count)).map { materials[$0 % materials.count] }
  }
}

// MARK: glTF export
// The same node tree as the USDZ, written as a binary glTF (.glb) for
// Android (Filament), Mapbox and Cesium. World transforms are baked into one
// mesh with one primitive per material; material names are kept, so `tint`
// still finds `paint…`. glTF models face +Z (munim-maps' glTF loader turns
// them 180° to face north), so the model is turned 180° about Y on the way out.

/// Things the glTF export could not carry over, printed once at the end.
var glbNotes: [String: Set<String>] = [:]
func glbNote(_ what: String, _ model: String) { glbNotes[what, default: []].insert(model) }

/// glTF colour factors are linear sRGB. They are matched to how the USDZ
/// looks on iOS rather than to the hex values: SceneKit's USD export writes
/// the sRGB components unconverted into UsdPreviewSurface (whose colours are
/// linear), and SceneKit reads them back as linear Display P3. So the same
/// numbers are taken as linear Display P3 and converted to linear sRGB.
let usdLinearP3 = CGColorSpace(name: CGColorSpace.linearDisplayP3)!
let gltfLinearSRGB = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!

func asShownOnIOS(_ r: Double, _ g: Double, _ b: Double) -> [Double] {
  let p3 = CGColor(colorSpace: usdLinearP3, components: [CGFloat(r), CGFloat(g), CGFloat(b), 1])!
  let c = p3.converted(to: gltfLinearSRGB, intent: .defaultIntent, options: nil)!.components!
  return (0..<3).map { Double(c[$0]) }
}

/// A material property's colour as linear RGBA (see `asShownOnIOS`).
func linearRGBA(_ p: SCNMaterialProperty, _ model: String) -> [Double]? {
  guard let contents = p.contents else { return nil }
  var color: NSColor?
  if let c = contents as? NSColor {
    color = c
  } else if CFGetTypeID(contents as CFTypeRef) == CGColor.typeID {
    color = NSColor(cgColor: contents as! CGColor)
  } else if let n = contents as? NSNumber {
    color = NSColor(srgbRed: CGFloat(n.doubleValue), green: CGFloat(n.doubleValue), blue: CGFloat(n.doubleValue), alpha: 1)
  }
  guard let s = color?.usingColorSpace(.sRGB) else {
    glbNote("material property with \(type(of: contents)) contents (texture?) dropped", model)
    return nil
  }
  let k = Double(p.intensity)
  return asShownOnIOS(Double(s.redComponent), Double(s.greenComponent), Double(s.blueComponent)).map { $0 * k }
    + [Double(s.alphaComponent)]
}

/// A scalar material property (metalness, roughness).
func scalar(_ p: SCNMaterialProperty, _ fallback: Double, _ model: String) -> Double {
  guard let contents = p.contents else { return fallback }
  if let n = contents as? NSNumber { return n.doubleValue * Double(p.intensity) }
  if let c = (contents as? NSColor)?.usingColorSpace(.genericGray) { return Double(c.whiteComponent) * Double(p.intensity) }
  glbNote("scalar property with \(type(of: contents)) contents (texture?) dropped", model)
  return fallback
}

func rounded6(_ v: Double) -> Double { (min(1, max(0, v)) * 1e6).rounded() / 1e6 }

func gltfMaterial(_ m: SCNMaterial, _ model: String) -> [String: Any] {
  var base = linearRGBA(m.diffuse, model) ?? [1, 1, 1, 1]
  base[3] *= Double(m.transparency)
  // Display P3 colours outside sRGB are clamped to its gamut.
  if let worst = base[0..<3].map({ max($0 - 1, -$0) }).max(), worst > 0.02 {
    glbNote("base colour outside sRGB clamped (\(m.name ?? "?"))", model)
  }
  let pbr = m.lightingModel == .physicallyBased
  if !pbr { glbNote("non-PBR lighting model \(m.lightingModel.rawValue) mapped to metallic 0 / roughness 0.5", model) }
  var out: [String: Any] = [
    "pbrMetallicRoughness": [
      "baseColorFactor": base.map(rounded6),
      "metallicFactor": rounded6(pbr ? scalar(m.metalness, 0, model) : 0),
      "roughnessFactor": rounded6(pbr ? scalar(m.roughness, 0.5, model) : 0.5),
    ] as [String: Any],
  ]
  if let name = m.name { out["name"] = name }
  if let e = linearRGBA(m.emission, model), e[0] + e[1] + e[2] > 0 {
    // Saturated lamps leave sRGB's range; the excess goes in the strength.
    let peak = max(1, e[0], e[1], e[2])
    out["emissiveFactor"] = e[0..<3].map { rounded6($0 / peak) }
    if peak > 1 {
      out["extensions"] = ["KHR_materials_emissive_strength": ["emissiveStrength": (peak * 1e4).rounded() / 1e4]]
    }
  }
  if base[3] < 1 { out["alphaMode"] = "BLEND" }
  if m.isDoubleSided { out["doubleSided"] = true }
  for (label, p) in [("normal", m.normal), ("ambientOcclusion", m.ambientOcclusion), ("selfIllumination", m.selfIllumination),
                     ("transparent", m.transparent), ("displacement", m.displacement)] {
    // Plain colours here are SceneKit's defaults; only images would matter.
    if let c = p.contents, !(c is NSColor), !(c is NSNumber), CFGetTypeID(c as CFTypeRef) != CGColor.typeID {
      glbNote("material \(label) map (\(type(of: c))) dropped", model)
    }
  }
  return out
}

/// Bit-exact vertex identity, for welding duplicates.
struct GLBVertex: Hashable { var p: SIMD3<UInt32>; var n: SIMD3<UInt32> }

final class GLBPrimitive {
  var positions: [V3] = []
  var normals: [V3] = []
  var indices: [UInt32] = []
  var lookup: [GLBVertex: UInt32] = [:]

  func vertex(_ p: V3, _ n: V3) -> UInt32 {
    let key = GLBVertex(p: p.bitPattern, n: n.bitPattern)
    if let i = lookup[key] { return i }
    let i = UInt32(positions.count)
    positions.append(p); normals.append(n); lookup[key] = i
    return i
  }
}

extension SIMD3 where Scalar == Float {
  var bitPattern: SIMD3<UInt32> { SIMD3<UInt32>(x.bitPattern, y.bitPattern, z.bitPattern) }
}

/// An element's triangles as index triples, whatever its primitive type.
func elementTriangles(_ e: SCNGeometryElement, _ model: String) -> [(UInt32, UInt32, UInt32)] {
  func index(_ raw: UnsafeRawBufferPointer, _ i: Int) -> UInt32 {
    switch e.bytesPerIndex {
    case 1: return UInt32(raw.load(fromByteOffset: i, as: UInt8.self))
    case 2: return UInt32(raw.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self))
    default: return raw.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self)
    }
  }
  var out: [(UInt32, UInt32, UInt32)] = []
  e.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
    switch e.primitiveType {
    case .triangles:
      for t in 0..<e.primitiveCount { out.append((index(raw, t * 3), index(raw, t * 3 + 1), index(raw, t * 3 + 2))) }
    case .triangleStrip:
      for t in 0..<e.primitiveCount {
        let a = index(raw, t), b = index(raw, t + 1), c = index(raw, t + 2)
        out.append(t % 2 == 0 ? (a, b, c) : (b, a, c))
      }
    case .polygon:
      // Vertex counts per polygon first, then the indices; fan-triangulated.
      var cursor = e.primitiveCount
      for f in 0..<e.primitiveCount {
        let n = Int(index(raw, f))
        for k in 1..<max(1, n - 1) { out.append((index(raw, cursor), index(raw, cursor + k), index(raw, cursor + k + 1))) }
        cursor += n
      }
    default:
      glbNote("line/point elements skipped", model)
    }
  }
  return out
}

/// Every float component of an SCNGeometrySource as 3-vectors.
func sourceVectors(_ s: SCNGeometrySource) -> [V3] {
  var out: [V3] = []
  out.reserveCapacity(s.vectorCount)
  s.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
    for i in 0..<s.vectorCount {
      let o = s.dataOffset + i * s.dataStride
      var v = V3(0, 0, 0)
      for c in 0..<min(3, s.componentsPerVector) {
        let at = o + c * s.bytesPerComponent
        v[c] = s.bytesPerComponent == 8 ? Float(raw.loadUnaligned(fromByteOffset: at, as: Double.self))
                                        : raw.loadUnaligned(fromByteOffset: at, as: Float.self)
      }
      out.append(v)
    }
  }
  return out
}

func writeGLB(_ root: SCNNode, _ name: String, to url: URL) {
  // glTF's front is +Z; munim-maps models face -Z. A 180° turn about Y keeps
  // the handedness (and so the winding).
  let turn = V3(-1, 1, -1)
  var materials: [[String: Any]] = []
  var materialSlot: [String: Int] = [:]
  var primitives: [Int: GLBPrimitive] = [:]
  var order: [Int] = []

  root.enumerateHierarchy { node, _ in
    if !node.animationKeys.isEmpty || node.hasActions { glbNote("animations/actions skipped", name) }
    var hidden = false
    var up: SCNNode? = node
    while let n = up {
      if n.isHidden { hidden = true }
      if n.opacity < 1 { glbNote("node opacity ignored", name) }
      up = n.parent
    }
    guard !hidden, let g = node.geometry, let vs = g.sources(for: .vertex).first else { return }
    let positions = sourceVectors(vs)
    var normals: [V3]
    if let ns = g.sources(for: .normal).first { normals = sourceVectors(ns) } else {
      glbNote("geometry without normals (computed)", name)
      normals = []
    }
    let t = node.simdWorldTransform
    let rot = simd_float3x3(V3(t.columns.0.x, t.columns.0.y, t.columns.0.z),
                            V3(t.columns.1.x, t.columns.1.y, t.columns.1.z),
                            V3(t.columns.2.x, t.columns.2.y, t.columns.2.z))
    let normalMatrix = rot.inverse.transpose
    let mirrored = rot.determinant < 0
    let world = positions.map { p -> V3 in
      let w = t * SIMD4<Float>(p.x, p.y, p.z, 1)
      return V3(w.x, w.y, w.z) * turn
    }
    var worldNormals = normals.map { n -> V3 in
      let w = normalMatrix * n
      return simd_length(w) > 1e-6 ? simd_normalize(w) * turn : V3(0, 1, 0)
    }
    let materialsOfGeometry = g.materials.isEmpty ? [black] : g.materials
    for e in 0..<g.elementCount {
      let m = materialsOfGeometry[e % materialsOfGeometry.count]
      let info = gltfMaterial(m, name)
      let key = String(data: try! JSONSerialization.data(withJSONObject: info, options: .sortedKeys), encoding: .utf8)!
      let slot: Int
      if let s = materialSlot[key] { slot = s } else {
        slot = materials.count; materialSlot[key] = slot; materials.append(info)
      }
      if primitives[slot] == nil { primitives[slot] = GLBPrimitive(); order.append(slot) }
      let prim = primitives[slot]!
      var triangles = elementTriangles(g.element(at: e), name)
      if mirrored { triangles = triangles.map { ($0.0, $0.2, $0.1) } }
      if worldNormals.count != world.count {
        // No usable normals: area-weighted vertex normals from these faces.
        worldNormals = Array(repeating: V3(0, 0, 0), count: world.count)
        for (a, b, c) in triangles {
          let n = simd_cross(world[Int(b)] - world[Int(a)], world[Int(c)] - world[Int(a)])
          for i in [a, b, c] { worldNormals[Int(i)] += n }
        }
        worldNormals = worldNormals.map { simd_length($0) > 1e-12 ? simd_normalize($0) : V3(0, 1, 0) }
      }
      for (a, b, c) in triangles {
        let ia = prim.vertex(world[Int(a)], worldNormals[Int(a)])
        let ib = prim.vertex(world[Int(b)], worldNormals[Int(b)])
        let ic = prim.vertex(world[Int(c)], worldNormals[Int(c)])
        if ia == ib || ib == ic || ia == ic { continue }
        prim.indices += [ia, ib, ic]
      }
    }
  }

  // One buffer: positions, normals, then indices (each view 4-byte aligned).
  var positionBytes = Data(), normalBytes = Data(), indexBytes = Data()
  var accessors: [[String: Any]] = []
  var meshPrimitives: [[String: Any]] = []
  func append<T>(_ values: [T], to data: inout Data) {
    values.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
  }
  for slot in order {
    let prim = primitives[slot]!
    guard !prim.indices.isEmpty else { continue }
    var lo = V3(repeating: .infinity), hi = V3(repeating: -.infinity)
    for p in prim.positions { lo = simd_min(lo, p); hi = simd_max(hi, p) }
    let count = prim.positions.count
    accessors.append(["bufferView": 0, "byteOffset": positionBytes.count, "componentType": 5126, "count": count, "type": "VEC3",
                      "min": [lo.x, lo.y, lo.z].map(Double.init), "max": [hi.x, hi.y, hi.z].map(Double.init)])
    append(prim.positions.flatMap { [$0.x, $0.y, $0.z] }, to: &positionBytes)
    accessors.append(["bufferView": 1, "byteOffset": normalBytes.count, "componentType": 5126, "count": count, "type": "VEC3"])
    append(prim.normals.flatMap { [$0.x, $0.y, $0.z] }, to: &normalBytes)
    // uint16 when every index fits below the primitive-restart value.
    let small = count <= 65535
    accessors.append(["bufferView": 2, "byteOffset": indexBytes.count, "componentType": small ? 5123 : 5125,
                      "count": prim.indices.count, "type": "SCALAR"])
    if small { append(prim.indices.map { UInt16($0) }, to: &indexBytes) } else { append(prim.indices, to: &indexBytes) }
    while indexBytes.count % 4 != 0 { indexBytes.append(0) }
    let base = accessors.count - 3
    meshPrimitives.append(["attributes": ["POSITION": base, "NORMAL": base + 1], "indices": base + 2, "material": slot, "mode": 4])
  }
  let views: [[String: Any]] = [
    ["buffer": 0, "byteOffset": 0, "byteLength": positionBytes.count, "byteStride": 12, "target": 34962],
    ["buffer": 0, "byteOffset": positionBytes.count, "byteLength": normalBytes.count, "byteStride": 12, "target": 34962],
    ["buffer": 0, "byteOffset": positionBytes.count + normalBytes.count, "byteLength": indexBytes.count, "target": 34963],
  ]
  let bin = positionBytes + normalBytes + indexBytes
  var json: [String: Any] = [
    "asset": ["version": "2.0", "generator": "munim-maps scripts/vehicles/make-vehicles.swift"],
    "scene": 0,
    "scenes": [["name": name, "nodes": [0]]],
    "nodes": [["name": name, "mesh": 0]],
    "meshes": [["name": name, "primitives": meshPrimitives]],
    "materials": materials,
    "accessors": accessors,
    "bufferViews": views,
    "buffers": [["byteLength": bin.count]],
  ]
  if materials.contains(where: { $0["extensions"] != nil }) { json["extensionsUsed"] = ["KHR_materials_emissive_strength"] }
  var jsonBytes = try! JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes])
  while jsonBytes.count % 4 != 0 { jsonBytes.append(0x20) }
  var binBytes = bin
  while binBytes.count % 4 != 0 { binBytes.append(0) }
  var glb = Data()
  func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { glb.append(contentsOf: $0) } }
  u32(0x4654_6C67); u32(2); u32(12 + 8 + jsonBytes.count + 8 + binBytes.count)
  u32(jsonBytes.count); u32(0x4E4F_534A); glb.append(jsonBytes)
  u32(binBytes.count); u32(0x004E_4942); glb.append(binBytes)
  do { try glb.write(to: url) } catch { fatalError("\(name).glb: \(error)") }
}

/// Optional second argument: where to write the .glb copies.
let glbDirectory: String? = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil

func save(_ node: SCNNode, _ name: String) {
  fixMaterialCounts(node)
  let scene = SCNScene()
  scene.rootNode.addChildNode(node)
  let url = URL(fileURLWithPath: CommandLine.arguments[1] + "/\(name).usdz")
  if !scene.write(to: url, options: nil, delegate: nil, progressHandler: nil) { fatalError(name) }
  if let glbDirectory { writeGLB(node, name, to: URL(fileURLWithPath: glbDirectory + "/\(name).glb")) }
}

save(car(sedan, body: 0x2E6FD8), "car-sedan")
save(car(hatchback, body: 0xE5484D), "car-hatchback")
save(car(suv, body: 0x2F3437), "car-suv")
save(car(sports, body: 0xFF6A00, extras: spoiler), "car-sports")
save(car(pickup, body: 0x8A9AA9, extras: pickupBed), "car-pickup")
save(car(sedan, body: 0xF7C600, extras: taxiSign), "car-taxi")
save(car(sedan, body: 0x15171A, extras: lightbar), "car-police")
save(bicycle(kind: "road", frame: 0xD7263D), "bike-road")
save(bicycle(kind: "mountain", frame: 0x1F9D55), "bike-mountain")
save(bicycle(kind: "city", frame: 0x4A90D9), "bike-city")
save(kickScooter(deck: 0x30D158), "scooter-kick")
save(moped(body: 0x7FC8C0), "scooter-moped")
save(speedboat(hull: 0x1E3A5F), "boat-speed")
save(sailboat(hull: 0xF2F2F2), "boat-sail")
save(airliner(livery: 0x0A4DA2), "plane-airliner")
save(privateJet(livery: 0x8E1B1B), "plane-jet")
save(propPlane(livery: 0xD62828), "plane-prop")
print("ok")
save(car(evSedan, body: 0xE8E8EA), "car-ev")
save(car(wagon, body: 0x5B6B48), "car-wagon")
save(car(minivan, body: 0x9AA4AE), "car-minivan")
save(car(supercar, body: 0xC1121F, extras: spoiler), "car-supercar")
save(car(convertible, body: 0x1D4E89), "car-convertible")
save(car(offroader, body: 0x4B5320, extras: offroadGear), "car-offroader")
save(deliveryVan(body: 0xF4F5F7), "van-delivery")
save(deliveryVan(body: 0xF4F5F7, ambulance: true), "van-ambulance")
save(boxTruck(body: 0x2E6FD8), "truck-box")
save(semiTruck(cab: 0xB22222), "truck-semi")
save(fireTruck(), "truck-fire")
save(cityBus(livery: 0x0A84FF), "bus-city")
save(schoolBus(), "bus-school")
save(motorcycle(kind: "sport", body: 0x1F6FEB), "motorcycle-sport")
save(motorcycle(kind: "cruiser", body: 0x111111), "motorcycle-cruiser")
save(motorcycle(kind: "dirt", body: 0xFF6A00), "motorcycle-dirt")
save(tram(livery: 0xD7263D), "rail-tram")
save(highSpeedTrain(livery: 0x0A4DA2), "rail-highspeed")
save(yacht(hull: 0x1C2836), "boat-yacht")
save(jetSki(body: 0xFFD60A), "boat-jetski")
save(widebody(livery: 0x6E1E8F), "plane-widebody")
save(f16(), "jet-f16")
save(f22(), "jet-f22")
save(f35(), "jet-f35")
save(yf23(), "jet-yf23")
save(helicopter(livery: 0xD62828), "heli-light")
save(hotAirBalloon(envelope: 0xFF3B30), "balloon")
save(starshipStack(), "rocket-starship")
save(falcon9(), "rocket-falcon9")
save(saturnV(), "rocket-saturnv")
save(shuttleStack(), "rocket-shuttle")
print("more ok")
save(iss(), "satellite-iss")
save(starlink(), "satellite-starlink")
save(hubble(), "satellite-hubble")
save(gps3(), "satellite-gps")
save(cubesat(), "satellite-cubesat")
save(crewDragon(), "satellite-dragon")
save(jwst(), "satellite-jwst")
print("satellites ok")
save(starbaseTower(), "starbase-tower")
save(starbaseMount(), "starbase-mount")
print("starbase ok")
for (what, models) in glbNotes.sorted(by: { $0.key < $1.key }) {
  print("glb note: \(what): \(models.sorted().joined(separator: ", "))")
}
