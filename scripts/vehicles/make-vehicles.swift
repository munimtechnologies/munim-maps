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
  let root = SCNNode()
  let L = spec.length, W = spec.width, H = spec.height
  let front = -L / 2
  let groundClear: Float = spec.wheelRadius * 0.45
  let beltline = spec.hoodHeight
  func z(_ f: Float) -> Float { front + f * L }

  // Lower body: nose to tail, rounded at both ends, with half-round wheel
  // arches cut into the bottom edge so the wheels show.
  let keys: [(Float, Float, Float, Float)] = [ // (fraction, width scale, bottom, top)
    (0.0, 0.70, groundClear + 0.12, beltline * 0.78),
    (0.02, 0.88, groundClear + 0.04, beltline * 0.90),
    (0.07, 0.97, groundClear, beltline * 0.97),
    (0.20, 1.0, groundClear, beltline),
    (0.80, 1.0, groundClear, beltline + 0.02),
    (0.94, 0.98, groundClear, beltline + 0.02),
    (0.985, 0.90, groundClear + 0.05, beltline * 0.97),
    (1.0, 0.74, groundClear + 0.14, beltline * 0.88),
  ]
  func base(_ f: Float) -> (Float, Float, Float) {
    for k in 1..<keys.count where f <= keys[k].0 {
      let a = keys[k - 1], b = keys[k]
      let t = (f - a.0) / max(0.0001, b.0 - a.0)
      return (a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t, a.3 + (b.3 - a.3) * t)
    }
    return (keys.last!.1, keys.last!.2, keys.last!.3)
  }
  let axles = [-spec.wheelbase / 2 + spec.frontOverhangBias, spec.wheelbase / 2 + spec.frontOverhangBias]
  let archRadius = spec.wheelRadius * 1.12
  var fractions = keys.map { $0.0 }
  for axle in axles {
    for k in -8...8 {
      let zz = axle + Float(k) / 8 * archRadius
      fractions.append((zz - front) / L)
    }
  }
  fractions = Array(Set(fractions.map { ($0 * 10000).rounded() / 10000 })).filter { $0 >= 0 && $0 <= 1 }.sorted()
  var lower: [Station] = []
  for f in fractions {
    let (ws, b0, t) = base(f)
    let zz = front + f * L
    var bottom = b0
    for axle in axles where abs(zz - axle) < archRadius {
      let u = (zz - axle) / archRadius
      bottom = max(bottom, spec.wheelRadius + archRadius * sqrt(max(0, 1 - u * u)) * 0.98)
    }
    lower.append(Station(z: zz, width: W * ws, bottom: min(bottom, t - 0.08), top: t, n: spec.boxy, bulge: -0.04))
  }
  root.addChildNode(loft(lower, segments: 32, paint(body)))

  // Greenhouse: windscreen, roof and rear screen as a glass loft, with a
  // painted roof panel over it.
  if spec.roofless {
    let cs = spec.cabinStart, rs = spec.roofStart
    root.addChildNode(loft([
      Station(z: z(cs), width: W * 0.86, bottom: beltline - 0.05, top: beltline + 0.02, n: 3),
      Station(z: z(rs), width: W * 0.84, bottom: beltline - 0.05, top: beltline + 0.36, n: 3, bulge: -0.05),
      Station(z: z(rs) + 0.06, width: W * 0.84, bottom: beltline - 0.05, top: beltline + 0.36, n: 3, bulge: -0.05),
    ], segments: 28, glass))
    // Cabin tub, seats with headrests, and roll hoops.
    box(root, W * 0.78, 0.06, L * 0.3, black, 0, beltline - 0.02, z(rs + 0.18))
    for side in [-1, 1] as [Float] {
      box(root, W * 0.28, 0.12, 0.5, leather, side * W * 0.2, beltline + 0.02, z(rs + 0.14))
      box(root, W * 0.28, 0.55, 0.12, leather, side * W * 0.2, beltline + 0.25, z(rs + 0.25))
      tube(root, V3(side * W * 0.2 - 0.12, beltline + 0.5, z(rs + 0.3)), V3(side * W * 0.2 + 0.12, beltline + 0.5, z(rs + 0.3)), 0.03, chrome)
      box(root, 0.06, 0.12, 0.2, paint(body), side * (W / 2 + 0.06), beltline + 0.06, z(cs) + 0.18)
    }
  } else {
    let cs = spec.cabinStart, ce = spec.cabinEnd, rs = spec.roofStart, re = spec.roofEnd
    let cabin: [Station] = [
      Station(z: z(cs), width: W * 0.86, bottom: beltline - 0.05, top: beltline + 0.02, n: 3),
      Station(z: z(rs), width: W * 0.80, bottom: beltline - 0.05, top: H - 0.02, n: 3.4, bulge: -0.08),
      Station(z: z(re), width: W * 0.80, bottom: beltline - 0.05, top: H - 0.02, n: 3.4, bulge: -0.08),
      Station(z: z(ce), width: W * 0.86, bottom: beltline - 0.05, top: beltline + 0.04, n: 3),
    ]
    root.addChildNode(loft(cabin, segments: 32, glass))
    // Roof panel and pillars in body colour.
    let roof: [Station] = [
      Station(z: z(rs) + 0.04, width: W * 0.80, bottom: H - 0.07, top: H, n: 4),
      Station(z: z(re) - 0.04, width: W * 0.80, bottom: H - 0.07, top: H, n: 4),
    ]
    root.addChildNode(loft(roof, segments: 24, paint(body)))
    // A, B and C pillars.
    for side in [-1, 1] as [Float] {
      let x = side * W * 0.405
      tube(root, V3(x * 0.98, beltline, z(cs) + 0.05), V3(x * 0.93, H - 0.04, z(rs) + 0.05), 0.045, paint(body))
      tube(root, V3(x * 0.99, beltline, z((rs + re) / 2)), V3(x * 0.93, H - 0.04, z((rs + re) / 2)), 0.05, paint(body))
      tube(root, V3(x * 0.98, beltline, z(ce) - 0.05), V3(x * 0.93, H - 0.04, z(re) - 0.05), 0.06, paint(body))
      // Mirrors.
      box(root, 0.06, 0.12, 0.2, paint(body), side * (W / 2 + 0.06), beltline + 0.06, z(cs) + 0.18)
      box(root, 0.02, 0.1, 0.16, glass, side * (W / 2 + 0.095), beltline + 0.06, z(cs) + 0.2)
      // Door handles and sill.
      box(root, 0.02, 0.025, 0.14, chrome, side * (W / 2 + 0.005), beltline - 0.12, z(0.45))
      box(root, 0.02, 0.025, 0.14, chrome, side * (W / 2 + 0.005), beltline - 0.12, z(0.62))
      box(root, 0.03, 0.06, L * 0.5, black, side * (W / 2 - 0.01), groundClear + 0.06, z(0.5))
    }
  }

  // Wheels with arches.
  let axleF = -spec.wheelbase / 2 + spec.frontOverhangBias, axleR = spec.wheelbase / 2 + spec.frontOverhangBias
  for zAxle in [axleF, axleR] {
    for side in [-1, 1] as [Float] {
      let x = side * (W / 2 - spec.wheelRadius * 0.42)
      carWheel(root, x: x, y: spec.wheelRadius, z: zAxle, radius: spec.wheelRadius, width: 0.24, outward: side)
      // Dark arch liner just above the tyre.
      let arch = TubeMesh(innerRadius: CGFloat(spec.wheelRadius * 1.02), outerRadius: CGFloat(spec.wheelRadius * 1.12), height: 0.26)
      put(root, arch, black, x * 1.01, spec.wheelRadius, zAxle, rz: .pi / 2)
    }
  }

  // Lights, grille, bumpers, plates.
  for side in [-1, 1] as [Float] {
    box(root, W * 0.2, 0.09, 0.05, headlight, side * W * 0.33, beltline * 0.82, front + 0.03)
    box(root, W * 0.05, 0.05, 0.05, amber, side * W * 0.45, beltline * 0.76, front + 0.05)
    box(root, W * 0.2, 0.08, 0.05, taillight, side * W * 0.34, beltline * 0.86, -front - 0.04)
  }
  if spec.grille { box(root, W * 0.38, 0.14, 0.04, black, 0, beltline * 0.64, front + 0.02) }
  else { box(root, W * 0.8, 0.03, 0.04, headlight, 0, beltline * 0.86, front + 0.035) } // light bar
  box(root, W * 0.92, 0.1, 0.12, plastic, 0, groundClear + 0.14, front + 0.06)
  box(root, W * 0.92, 0.1, 0.12, plastic, 0, groundClear + 0.16, -front - 0.06)
  box(root, 0.32, 0.1, 0.02, plate, 0, groundClear + 0.3, front - 0.005)
  box(root, 0.32, 0.1, 0.02, plate, 0, beltline * 0.62, -front + 0.005)
  extras(root, spec)
  return root
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

func moped(body: UInt32) -> SCNNode {
  let root = SCNNode()
  let p = paint(body)
  // Rear bodywork shell over the engine.
  root.addChildNode(loft([
    Station(z: 0.05, width: 0.34, bottom: 0.32, top: 0.62, n: 2.4),
    Station(z: 0.35, width: 0.52, bottom: 0.3, top: 0.72, n: 2.6),
    Station(z: 0.65, width: 0.46, bottom: 0.36, top: 0.70, n: 2.6),
    Station(z: 0.82, width: 0.26, bottom: 0.48, top: 0.62, n: 2.2),
  ], segments: 24, p))
  // Floorboard and leg shield.
  box(root, 0.3, 0.06, 0.5, rubber, 0, 0.3, -0.2)
  root.addChildNode(loft([
    Station(z: -0.52, width: 0.40, bottom: 0.3, top: 0.95, n: 3),
    Station(z: -0.44, width: 0.44, bottom: 0.3, top: 1.0, n: 3),
  ], segments: 20, p))
  // Seat, front fender, fork, headset, mirrors.
  root.addChildNode(loft([
    Station(z: 0.05, width: 0.26, bottom: 0.7, top: 0.79, n: 3),
    Station(z: 0.6, width: 0.3, bottom: 0.7, top: 0.8, n: 3),
  ], segments: 18, leather))
  for (z, r) in [(Float(-0.62), Float(0.24)), (Float(0.62), Float(0.24))] {
    let t = TubeMesh(innerRadius: CGFloat(r * 0.6), outerRadius: CGFloat(r), height: 0.11)
    put(root, t, tyre, 0, r, z, rz: .pi / 2)
    put(root, CylinderMesh(radius: CGFloat(r * 0.6), height: 0.07), rim, 0, r, z, rz: .pi / 2)
  }
  root.addChildNode(loft([
    Station(z: -0.86, width: 0.16, bottom: 0.42, top: 0.5, n: 2.5),
    Station(z: -0.62, width: 0.2, bottom: 0.47, top: 0.56, n: 2.5),
    Station(z: -0.42, width: 0.16, bottom: 0.38, top: 0.46, n: 2.5),
  ], segments: 18, p))
  tube(root, V3(0, 0.24, -0.62), V3(0, 1.0, -0.48), 0.03, chrome)
  root.addChildNode(loft([
    Station(z: -0.56, width: 0.3, bottom: 0.98, top: 1.1, n: 2.4),
    Station(z: -0.40, width: 0.34, bottom: 0.98, top: 1.12, n: 2.4),
  ], segments: 18, p))
  tube(root, V3(-0.36, 1.08, -0.44), V3(0.36, 1.08, -0.44), 0.014, chrome)
  for x in [-0.36, 0.36] as [Float] { tube(root, V3(x, 1.08, -0.44), V3(x * 0.8, 1.08, -0.44), 0.022, rubber) }
  for x in [-0.22, 0.22] as [Float] {
    tube(root, V3(x, 1.1, -0.46), V3(x * 1.3, 1.32, -0.48), 0.008, chrome)
    put(root, CylinderMesh(radius: 0.045, height: 0.015), chrome, x * 1.3, 1.34, -0.48, rx: .pi / 2)
  }
  put(root, CylinderMesh(radius: 0.065, height: 0.04), headlight, 0, 1.03, -0.585, rx: .pi / 2)
  box(root, 0.1, 0.05, 0.03, taillight, 0, 0.66, 0.84)
  return root
}

// MARK: Boats

func speedboat(hull: UInt32) -> SCNNode {
  let root = SCNNode()
  let h = paint(hull)
  root.addChildNode(loft([
    Station(z: -2.6, width: 0.1, bottom: 0.55, top: 0.95, n: 2),
    Station(z: -2.0, width: 1.3, bottom: 0.15, top: 1.0, n: 2.2, bulge: 0.15),
    Station(z: -0.8, width: 2.2, bottom: 0.02, top: 1.0, n: 2.6, bulge: 0.2),
    Station(z: 1.6, width: 2.3, bottom: 0.0, top: 0.95, n: 3.2, bulge: 0.15),
    Station(z: 2.3, width: 2.2, bottom: 0.05, top: 0.92, n: 3.6),
  ], segments: 32, h))
  // White deck stripe and boot.
  root.addChildNode(loft([
    Station(z: -1.9, width: 1.24, bottom: 0.96, top: 1.02, n: 2.2),
    Station(z: 2.25, width: 2.18, bottom: 0.9, top: 0.96, n: 3.6),
  ], segments: 28, white))
  // Windscreen, seats, console, outboard engine, rails.
  root.addChildNode(loft([
    Station(z: -0.55, width: 1.8, bottom: 1.0, top: 1.05, n: 3),
    Station(z: -0.35, width: 1.7, bottom: 1.0, top: 1.42, n: 3, bulge: -0.1),
  ], segments: 24, glass))
  for x in [-0.45, 0.45] as [Float] {
    box(root, 0.55, 0.12, 0.55, white, x, 1.08, 0.3)
    box(root, 0.55, 0.45, 0.1, white, x, 1.3, 0.55)
  }
  box(root, 1.9, 0.12, 0.6, white, 0, 1.08, 1.6)
  box(root, 0.36, 0.28, 0.3, black, 0, 1.2, 2.3)
  box(root, 0.24, 0.9, 0.2, plastic, 0, 0.62, 2.45)
  box(root, 0.18, 0.06, 0.3, chrome, 0, 0.1, 2.48)
  for x in [-1.0, 1.0] as [Float] { tube(root, V3(x * 0.55, 1.08, -1.6), V3(x * 1.0, 1.06, -0.6), 0.015, chrome) }
  return root
}

func sailboat(hull: UInt32) -> SCNNode {
  let root = SCNNode()
  let h = paint(hull)
  root.addChildNode(loft([
    Station(z: -4.2, width: 0.1, bottom: 0.7, top: 1.15, n: 2),
    Station(z: -3.2, width: 1.9, bottom: 0.2, top: 1.2, n: 2.2, bulge: 0.15),
    Station(z: -0.5, width: 3.0, bottom: 0.0, top: 1.15, n: 2.6, bulge: 0.15),
    Station(z: 3.2, width: 2.5, bottom: 0.2, top: 1.05, n: 3),
    Station(z: 3.7, width: 2.2, bottom: 0.45, top: 1.0, n: 3),
  ], segments: 32, h))
  root.addChildNode(loft([
    Station(z: -3.6, width: 1.0, bottom: 1.14, top: 1.2, n: 2.2),
    Station(z: 3.6, width: 2.1, bottom: 1.0, top: 1.06, n: 3),
  ], segments: 28, wood))
  root.addChildNode(loft([
    Station(z: -1.4, width: 1.6, bottom: 1.15, top: 1.5, n: 3),
    Station(z: 1.0, width: 1.8, bottom: 1.1, top: 1.55, n: 3),
  ], segments: 24, white))
  for z in [-1.2, -0.6, 0.0, 0.6] as [Float] {
    box(root, 1.82, 0.12, 0.25, glass, 0, 1.4, z)
  }
  // Mast, boom, mainsail and jib (thin double-sided panels).
  tube(root, V3(0, 1.2, -1.6), V3(0, 13.5, -1.6), 0.08, chrome)
  tube(root, V3(0, 2.4, -1.6), V3(0, 2.4, 2.4), 0.06, chrome)
  // Mainsail behind the mast, jib ahead of it (panels in the YZ plane).
  put(root, PanelMesh([SIMD2(0, 0), SIMD2(0, 10.8), SIMD2(3.9, 0)]), sailcloth, 0.02, 2.5, -1.55, ry: -.pi / 2)
  put(root, PanelMesh([SIMD2(0, 0), SIMD2(-2.5, 0), SIMD2(0, 10.6)]), sailcloth, 0, 1.3, -1.7, ry: -.pi / 2)
  tube(root, V3(0, 13.4, -1.6), V3(0, 1.2, -4.15), 0.012, chrome, sides: 4)
  tube(root, V3(0, 13.4, -1.6), V3(0, 1.2, 3.6), 0.012, chrome, sides: 4)
  return root
}

// MARK: Planes

/// A tapered, swept wing panel from `x, y, z` outwards to the `side`
/// (+1 right, -1 left). The loft runs along +Z (span) with the chord along X,
/// then is turned so the span points sideways, swept back and tilted up.
func wing(_ parent: SCNNode, root rootChord: Float, tip tipChord: Float, span: Float, sweep: Float,
          thickness: Float, dihedral: Float, x: Float, y: Float, z: Float, side: Float, _ m: SCNMaterial) {
  let panel = loft([
    Station(z: 0, width: rootChord, bottom: -thickness / 2, top: thickness / 2, n: 2.2),
    Station(z: span, width: tipChord, bottom: -thickness * 0.3, top: thickness * 0.3, n: 2.2),
  ], segments: 16, m)
  panel.simdOrientation = simd_quatf(angle: side * .pi / 2, axis: V3(0, 1, 0))
  let holder = SCNNode()
  holder.addChildNode(panel)
  holder.simdPosition = V3(x, y, z)
  holder.simdOrientation = simd_quatf(angle: -side * atan2(sweep, span), axis: V3(0, 1, 0))
    * simd_quatf(angle: side * dihedral, axis: V3(0, 0, 1))
  parent.addChildNode(holder)
}

func airliner(livery: UInt32) -> SCNNode {
  let root = SCNNode()
  let L: Float = 38, R: Float = 2.0
  var fuselage: [Station] = []
  let shape: [(Float, Float, Float)] = [ // fraction, radius scale, centre y offset
    (0.0, 0.05, -0.2), (0.02, 0.45, -0.15), (0.06, 0.78, -0.05), (0.12, 0.96, 0), (0.2, 1, 0),
    (0.7, 1, 0), (0.8, 0.9, 0.15), (0.9, 0.6, 0.45), (0.98, 0.28, 0.75), (1.0, 0.12, 0.8),
  ]
  let cy: Float = 3.2
  for (f, s, dy) in shape {
    fuselage.append(Station(z: -L / 2 + f * L, width: 2 * R * s, bottom: cy + dy - R * s, top: cy + dy + R * s, n: 2))
  }
  root.addChildNode(loft(fuselage, segments: 36, white))
  // Coloured belly stripe and tail.
  let stripe = paint(livery)
  for side in [-1, 1] as [Float] {
    box(root, 0.05, 0.22, L * 0.62, stripe, side * R * 0.99, cy - 0.3, -1)
    box(root, 0.05, 0.16, L * 0.6, glass, side * R * 0.985, cy + 0.55, -1.5) // window band
  }
  put(root, BoxMesh(width: 1.1, height: 0.5, length: 0.05, chamferRadius: 0), glass, 0, cy + 0.85, -L / 2 + 1.2, rx: -0.9)
  // Wings with engines.
  for side in [-1, 1] as [Float] {
    wing(root, root: 6.2, tip: 1.6, span: 15.5, sweep: 6.0, thickness: 0.7, dihedral: 0.09,
         x: side * R * 0.7, y: cy - 1.0, z: -1.5, side: side, white)
    let ex = side * 5.6
    let engine = loft([
      Station(z: -4.6, width: 1.9, bottom: cy - 2.95, top: cy - 1.05, n: 2),
      Station(z: -3.2, width: 2.1, bottom: cy - 3.05, top: cy - 0.95, n: 2),
      Station(z: -1.6, width: 1.5, bottom: cy - 2.75, top: cy - 1.25, n: 2),
    ], segments: 24, stripe)
    engine.simdPosition = V3(ex, 0, 0)
    root.addChildNode(engine)
    put(root, CylinderMesh(radius: 0.85, height: 0.05), chrome, ex, cy - 2.0, -4.62, rx: .pi / 2)
    box(root, 0.3, 0.9, 1.6, white, ex, cy - 1.0, -2.6)
    box(root, 0.15, 0.08, 0.12, taillight, side * 17.0, cy - 0.3, 1.8)
  }
  // Tailplane and fin.
  for side in [-1, 1] as [Float] {
    wing(root, root: 3.2, tip: 1.2, span: 6.2, sweep: 2.8, thickness: 0.3, dihedral: 0.12,
         x: side * 0.5, y: cy + 0.4, z: L / 2 - 4.6, side: side, white)
  }
  let fin = loft([
    Station(z: 0, width: 5.0, bottom: -0.15, top: 0.15, n: 2.2),
    Station(z: 6.2, width: 2.0, bottom: -0.1, top: 0.1, n: 2.2),
  ], segments: 16, stripe)
  fin.simdOrientation = simd_quatf(angle: -.pi / 2, axis: V3(1, 0, 0)) * simd_quatf(angle: .pi / 2, axis: V3(0, 0, 1))
  let finHolder = SCNNode()
  finHolder.addChildNode(fin)
  finHolder.simdPosition = V3(0, cy + 1.3, L / 2 - 4.2)
  finHolder.simdOrientation = simd_quatf(angle: 0.55, axis: V3(1, 0, 0))
  root.addChildNode(finHolder)
  // Landing gear.
  for (x, z) in [(Float(0), Float(-L / 2 + 4)), (-2.2, 1.0), (2.2, 1.0)] {
    tube(root, V3(x, cy - 1.6, z), V3(x, 0.55, z), 0.12, chrome)
    put(root, TubeMesh(innerRadius: 0.2, outerRadius: 0.55, height: 0.4), tyre, x, 0.55, z, rz: .pi / 2)
  }
  return root
}

func privateJet(livery: UInt32) -> SCNNode {
  let root = SCNNode()
  let L: Float = 20, R: Float = 1.1, cy: Float = 2.0
  let shape: [(Float, Float, Float)] = [
    (0.0, 0.05, -0.1), (0.03, 0.45, -0.08), (0.1, 0.85, 0), (0.18, 1, 0), (0.62, 1, 0),
    (0.78, 0.85, 0.1), (0.92, 0.5, 0.3), (1.0, 0.12, 0.45),
  ]
  root.addChildNode(loft(shape.map { Station(z: -L / 2 + $0.0 * L, width: 2 * R * $0.1, bottom: cy + $0.2 - R * $0.1, top: cy + $0.2 + R * $0.1, n: 2) }, segments: 32, white))
  let stripe = paint(livery)
  for side in [-1, 1] as [Float] {
    box(root, 0.04, 0.14, L * 0.6, stripe, side * R * 0.99, cy - 0.15, -0.5)
    for i in 0..<6 { box(root, 0.05, 0.26, 0.32, glass, side * R * 0.98, cy + 0.25, -4.5 + Float(i) * 0.9) }
    wing(root, root: 3.2, tip: 1.0, span: 7.2, sweep: 2.6, thickness: 0.35, dihedral: 0.08,
         x: side * R * 0.6, y: cy - 0.6, z: -0.3, side: side, white)
    // Rear-mounted engines.
    let e = loft([
      Station(z: 3.4, width: 0.95, bottom: cy - 0.05, top: cy + 0.9, n: 2),
      Station(z: 5.6, width: 0.8, bottom: cy + 0.05, top: cy + 0.8, n: 2),
    ], segments: 20, stripe)
    e.simdPosition = V3(side * 1.65, 0, 0)
    root.addChildNode(e)
    tube(root, V3(side * 0.9, cy + 0.4, 4.4), V3(side * 1.3, cy + 0.4, 4.4), 0.12, white)
  }
  put(root, BoxMesh(width: 0.9, height: 0.35, length: 0.05, chamferRadius: 0), glass, 0, cy + 0.55, -L / 2 + 1.6, rx: -0.9)
  // T-tail.
  let fin = loft([
    Station(z: 0, width: 2.6, bottom: -0.1, top: 0.1, n: 2.2),
    Station(z: 3.0, width: 1.4, bottom: -0.07, top: 0.07, n: 2.2),
  ], segments: 14, stripe)
  fin.simdOrientation = simd_quatf(angle: -.pi / 2, axis: V3(1, 0, 0)) * simd_quatf(angle: .pi / 2, axis: V3(0, 0, 1))
  let finHolder = SCNNode(); finHolder.addChildNode(fin)
  finHolder.simdPosition = V3(0, cy + 0.8, L / 2 - 2.2)
  finHolder.simdOrientation = simd_quatf(angle: 0.6, axis: V3(1, 0, 0))
  root.addChildNode(finHolder)
  for side in [-1, 1] as [Float] {
    wing(root, root: 1.5, tip: 0.8, span: 2.8, sweep: 0.9, thickness: 0.16, dihedral: 0,
         x: side * 0.1, y: cy + 3.6, z: L / 2 - 0.9, side: side, white)
  }
  for (x, z) in [(Float(0), Float(-L / 2 + 2.5)), (-1.6, 0.8), (1.6, 0.8)] {
    tube(root, V3(x, cy - 0.9, z), V3(x, 0.32, z), 0.07, chrome)
    put(root, TubeMesh(innerRadius: 0.1, outerRadius: 0.32, height: 0.22), tyre, x, 0.32, z, rz: .pi / 2)
  }
  return root
}

func propPlane(livery: UInt32) -> SCNNode {
  let root = SCNNode()
  let cy: Float = 1.45
  let p = paint(livery)
  root.addChildNode(loft([
    Station(z: -3.9, width: 0.7, bottom: cy - 0.35, top: cy + 0.3, n: 2.2),
    Station(z: -3.0, width: 1.1, bottom: cy - 0.55, top: cy + 0.55, n: 2.6),
    Station(z: -1.2, width: 1.2, bottom: cy - 0.6, top: cy + 0.75, n: 3),
    Station(z: 0.6, width: 1.1, bottom: cy - 0.55, top: cy + 0.7, n: 3),
    Station(z: 3.2, width: 0.35, bottom: cy - 0.1, top: cy + 0.35, n: 2.4),
    Station(z: 4.2, width: 0.18, bottom: cy, top: cy + 0.3, n: 2.2),
  ], segments: 28, white))
  for side in [-1, 1] as [Float] {
    box(root, 0.04, 0.12, 5.5, p, side * 0.58, cy - 0.15, 0.3)
    box(root, 0.04, 0.42, 1.3, glass, side * 0.585, cy + 0.42, -1.1)
    // High wing with struts.
    box(root, 5.3, 0.16, 1.5, white, side * 2.75, cy + 0.82, -1.0)
    box(root, 0.6, 0.165, 1.51, p, side * 5.1, cy + 0.82, -1.0)
    tube(root, V3(side * 0.55, cy - 0.4, -0.9), V3(side * 2.6, cy + 0.74, -0.9), 0.04, white)
    // Tailplane.
    box(root, 1.6, 0.08, 0.8, white, side * 0.85, cy + 0.2, 3.8)
    // Main gear with fairings.
    tube(root, V3(side * 0.5, cy - 0.5, -0.4), V3(side * 1.1, 0.27, -0.4), 0.04, chrome)
    put(root, TubeMesh(innerRadius: 0.1, outerRadius: 0.27, height: 0.14), tyre, side * 1.1, 0.27, -0.4, rz: .pi / 2)
  }
  put(root, BoxMesh(width: 1.0, height: 0.5, length: 0.05, chamferRadius: 0), glass, 0, cy + 0.6, -2.0, rx: -0.75)
  box(root, 0.08, 1.4, 1.1, p, 0, cy + 0.95, 3.85)
  // Spinner and two-blade propeller.
  let spinner = loft([
    Station(z: -4.35, width: 0.06, bottom: cy - 0.05, top: cy + 0.01, n: 2),
    Station(z: -3.92, width: 0.36, bottom: cy - 0.2, top: cy + 0.16, n: 2),
  ], segments: 16, chrome)
  root.addChildNode(spinner)
  box(root, 0.14, 1.9, 0.04, black, 0, cy - 0.02, -4.0, rz: 0.4)
  tube(root, V3(0, cy - 0.5, -3.3), V3(0, 0.22, -3.3), 0.04, chrome)
  put(root, TubeMesh(innerRadius: 0.08, outerRadius: 0.22, height: 0.12), tyre, 0, 0.22, -3.3, rz: .pi / 2)
  return root
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
  root.enumerateHierarchy { n, stop in
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

// MARK: Vans, trucks and buses

/// A tall box body (van, bus) lofted with a rounded nose. `noseLength` is
/// how far back the windscreen top is; `hood` adds a bonnet in front.
func boxBody(_ root: SCNNode, length L: Float, width W: Float, height H: Float, bottom: Float,
             noseLength: Float, hoodLength: Float = 0, hoodHeight: Float = 0, _ m: SCNMaterial) {
  let f = -L / 2
  var st: [Station] = []
  if hoodLength > 0 {
    st.append(Station(z: f, width: W * 0.86, bottom: bottom + 0.1, top: hoodHeight * 0.9, n: 4))
    st.append(Station(z: f + 0.15, width: W * 0.94, bottom: bottom, top: hoodHeight, n: 4.5))
    st.append(Station(z: f + hoodLength, width: W * 0.96, bottom: bottom, top: hoodHeight + 0.05, n: 4.5))
  } else {
    st.append(Station(z: f, width: W * 0.9, bottom: bottom + 0.08, top: H * 0.5, n: 4))
    st.append(Station(z: f + 0.12, width: W * 0.98, bottom: bottom, top: H * 0.62, n: 5))
  }
  st.append(Station(z: f + hoodLength + noseLength, width: W, bottom: bottom, top: H, n: 6))
  st.append(Station(z: L / 2 - 0.1, width: W, bottom: bottom, top: H, n: 6))
  st.append(Station(z: L / 2, width: W * 0.96, bottom: bottom + 0.05, top: H - 0.05, n: 6))
  root.addChildNode(loft(st, segments: 32, m))
}

func wheelsAt(_ root: SCNNode, axles: [Float], track: Float, radius: Float, dual: Bool = false) {
  for z in axles {
    for side in [-1, 1] as [Float] {
      carWheel(root, x: side * track / 2, y: radius, z: z, radius: radius, width: 0.3, spokes: 8, outward: side)
      if dual { carWheel(root, x: side * (track / 2 - 0.32), y: radius, z: z, radius: radius, width: 0.3, spokes: 8, outward: side) }
    }
  }
}

func windowBand(_ root: SCNNode, width W: Float, y: Float, height: Float, from z0: Float, to z1: Float, panes: Int) {
  let paneLength = (z1 - z0) / Float(panes)
  for side in [-1, 1] as [Float] {
    for i in 0..<panes {
      box(root, 0.03, height, paneLength * 0.86, glass, side * (W / 2 + 0.005), y, z0 + paneLength * (Float(i) + 0.5))
    }
  }
}

func deliveryVan(body: UInt32, ambulance: Bool = false) -> SCNNode {
  let root = SCNNode()
  let L: Float = 5.9, W: Float = 2.05, H: Float = ambulance ? 2.75 : 2.6, b: Float = 0.38
  boxBody(root, length: L, width: W, height: H, bottom: b, noseLength: 1.2, hoodLength: 0.75, hoodHeight: 1.15, paint(body))
  // Windscreen and cab side windows.
  put(root, BoxMesh(width: CGFloat(W * 0.9), height: 0.85, length: 0.04), glass, 0, 1.75, -L / 2 + 1.35, rx: -0.42)
  for side in [-1, 1] as [Float] {
    box(root, 0.03, 0.62, 0.8, glass, side * (W / 2 + 0.005), 1.72, -L / 2 + 1.75)
    box(root, 0.06, 0.14, 0.22, black, side * (W / 2 + 0.08), 1.5, -L / 2 + 1.25)
    box(root, 0.02, 1.7, 0.02, black, side * (W / 2 + 0.005), 1.3, -0.2) // sliding door seam
  }
  wheelsAt(root, axles: [-L / 2 + 1.05, L / 2 - 1.2], track: W - 0.2, radius: 0.38)
  for side in [-1, 1] as [Float] {
    box(root, 0.36, 0.14, 0.04, headlight, side * 0.68, 0.95, -L / 2 + 0.02)
    box(root, 0.12, 0.6, 0.04, taillight, side * 0.9, 1.3, L / 2 + 0.01)
  }
  box(root, W * 0.5, 0.2, 0.04, black, 0, 0.82, -L / 2 + 0.02)
  if ambulance {
    let red = material("stripe-red", 0xD7192C, rough: 0.4)
    for side in [-1, 1] as [Float] { box(root, 0.03, 0.22, L * 0.72, red, side * (W / 2 + 0.008), 1.15, 0.5) }
    box(root, 0.6, 0.22, 0.03, red, 0, 1.9, L / 2 + 0.005)
    box(root, 0.22, 0.6, 0.03, red, 0, 1.9, L / 2 + 0.006)
    box(root, 1.3, 0.12, 0.3, material("light-red", 0xFF2D2D, emit: true), 0, H + 0.06, -L / 2 + 1.9)
  }
  return root
}

func boxTruck(body: UInt32) -> SCNNode {
  let root = SCNNode()
  let p = paint(body)
  // Cab.
  boxBody(root, length: 2.4, width: 2.3, height: 2.7, bottom: 0.55, noseLength: 0.7, p)
  root.childNodes.last?.simdPosition = V3(0, 0, -2.6)
  put(root, BoxMesh(width: 2.0, height: 0.9, length: 0.04), glass, 0, 2.05, -3.62, rx: -0.2)
  for side in [-1, 1] as [Float] { box(root, 0.03, 0.7, 0.9, glass, side * 1.155, 2.0, -3.0) }
  // Cargo box, chassis, wheels.
  box(root, 2.45, 3.0, 6.0, white, 0, 2.15, 1.25)
  box(root, 1.2, 0.3, 7.6, black, 0, 0.62, 0.3)
  wheelsAt(root, axles: [-3.0], track: 2.0, radius: 0.5)
  wheelsAt(root, axles: [2.6], track: 2.0, radius: 0.5, dual: true)
  for side in [-1, 1] as [Float] {
    box(root, 0.4, 0.16, 0.04, headlight, side * 0.75, 1.05, -3.82)
    box(root, 0.18, 0.3, 0.04, taillight, side * 1.05, 0.9, 4.26)
  }
  return root
}

func semiTruck(cab: UInt32) -> SCNNode {
  let root = SCNNode()
  let p = paint(cab)
  // Conventional-nose tractor with a sleeper.
  boxBody(root, length: 6.6, width: 2.5, height: 3.6, bottom: 0.7, noseLength: 0.55, hoodLength: 1.9, hoodHeight: 1.95, p)
  root.childNodes.last?.simdPosition = V3(0, 0, -6.2)
  put(root, BoxMesh(width: 2.2, height: 0.95, length: 0.04), glass, 0, 2.65, -7.05, rx: -0.3)
  box(root, 1.2, 1.1, 0.06, chrome, 0, 1.4, -9.52) // grille
  for side in [-1, 1] as [Float] {
    box(root, 0.03, 0.75, 0.9, glass, side * 1.255, 2.6, -6.4)
    tube(root, V3(side * 1.3, 1.2, -5.6), V3(side * 1.3, 4.3, -5.6), 0.08, chrome)       // stacks
    put(root, CylinderMesh(radius: 0.32, height: 1.3), chrome, side * 1.15, 0.85, -4.6, rx: .pi / 2) // fuel tanks
    box(root, 0.4, 0.18, 0.04, headlight, side * 0.95, 1.35, -9.5)
  }
  wheelsAt(root, axles: [-8.3], track: 2.15, radius: 0.52)
  wheelsAt(root, axles: [-4.2, -2.9], track: 2.15, radius: 0.52, dual: true)
  // 53-foot trailer.
  box(root, 2.6, 2.9, 14.6, white, 0, 2.75, 5.3)
  box(root, 2.62, 0.25, 14.6, paint(cab), 0, 1.25, 5.3)
  wheelsAt(root, axles: [10.4, 11.7], track: 2.15, radius: 0.52, dual: true)
  for x in [-0.9, 0.9] as [Float] { tube(root, V3(x, 1.2, 0.5), V3(x, 0.1, 0.5), 0.05, chrome) }
  for side in [-1, 1] as [Float] { box(root, 0.18, 0.12, 0.04, taillight, side * 1.15, 1.25, 12.61) }
  return root
}

func cityBus(livery: UInt32) -> SCNNode {
  let root = SCNNode()
  let L: Float = 12.2, W: Float = 2.55, H: Float = 3.15
  boxBody(root, length: L, width: W, height: H, bottom: 0.32, noseLength: 0.35, white)
  put(root, BoxMesh(width: CGFloat(W * 0.92), height: 1.5, length: 0.04), glass, 0, 1.95, -L / 2 + 0.04, rx: -0.06)
  box(root, 1.6, 0.25, 0.04, material("sign", 0xFFB800, emit: true), 0, 2.95, -L / 2 + 0.02)
  windowBand(root, width: W, y: 2.05, height: 1.0, from: -L / 2 + 1.2, to: L / 2 - 0.6, panes: 8)
  let p = paint(livery)
  for side in [-1, 1] as [Float] {
    box(root, 0.03, 0.55, L - 0.4, p, side * (W / 2 + 0.006), 0.95, 0)
    box(root, 0.035, 2.1, 1.1, glass, W / 2 * 1.003, 1.4, -L / 2 + 1.5) // front door
    box(root, 0.035, 2.1, 1.1, glass, W / 2 * 1.003, 1.4, 0.6)          // rear door
    box(root, 0.3, 0.14, 0.04, headlight, side * 0.95, 0.75, -L / 2 + 0.02)
    box(root, 0.16, 0.4, 0.04, taillight, side * 1.1, 1.0, L / 2 + 0.01)
  }
  box(root, W * 0.98, 0.08, L * 0.94, p, 0, H + 0.02, 0) // roof pods
  wheelsAt(root, axles: [-L / 2 + 2.6, L / 2 - 3.0], track: W - 0.35, radius: 0.5)
  return root
}

func schoolBus() -> SCNNode {
  let root = SCNNode()
  let L: Float = 11.5, W: Float = 2.45, H: Float = 3.0
  let yellow = paint(0xFFB300)
  boxBody(root, length: L, width: W, height: H, bottom: 0.45, noseLength: 0.4, hoodLength: 1.6, hoodHeight: 1.5, yellow)
  put(root, BoxMesh(width: CGFloat(W * 0.9), height: 0.85, length: 0.04), glass, 0, 2.1, -L / 2 + 1.85, rx: -0.12)
  windowBand(root, width: W, y: 2.2, height: 0.72, from: -L / 2 + 2.3, to: L / 2 - 0.5, panes: 9)
  for side in [-1, 1] as [Float] {
    for y in [1.2, 1.55] as [Float] { box(root, 0.025, 0.06, L - 1.8, black, side * (W / 2 + 0.006), y, 0.7) }
    box(root, 0.3, 0.16, 0.04, headlight, side * 0.75, 1.0, -L / 2 + 0.02)
    box(root, 0.14, 0.14, 0.04, taillight, side * 1.0, 1.1, L / 2 + 0.01)
    box(root, 0.16, 0.16, 0.04, amber, side * 0.9, 2.85, -L / 2 + 1.58)
  }
  box(root, 0.03, 0.4, 0.4, material("stop", 0xD0021B, rough: 0.4), -W / 2 - 0.25, 1.6, -L / 2 + 2.4) // stop arm
  box(root, W * 0.5, 0.35, 0.05, black, 0, 1.0, -L / 2 + 0.02)
  wheelsAt(root, axles: [-L / 2 + 1.3, L / 2 - 2.6], track: W - 0.3, radius: 0.5)
  return root
}

func fireTruck() -> SCNNode {
  let root = SCNNode()
  let red = paint(0xC8102E)
  boxBody(root, length: 3.0, width: 2.5, height: 3.0, bottom: 0.6, noseLength: 0.5, red)
  root.childNodes.last?.simdPosition = V3(0, 0, -3.6)
  put(root, BoxMesh(width: 2.2, height: 1.1, length: 0.04), glass, 0, 2.3, -5.08, rx: -0.12)
  for side in [-1, 1] as [Float] { box(root, 0.03, 0.8, 1.2, glass, side * 1.255, 2.3, -4.0) }
  box(root, 2.5, 2.4, 6.0, red, 0, 1.85, 1.2)
  for side in [-1, 1] as [Float] {
    for i in 0..<4 { box(root, 0.03, 1.6, 1.3, material("locker", 0xD5D9DE, metal: 0.3, rough: 0.35), side * 1.256, 1.75, -1.2 + Float(i) * 1.5) } // roller-door lockers
    box(root, 0.4, 0.16, 0.04, headlight, side * 0.8, 1.2, -5.12)
    tube(root, V3(side * 0.45, 3.2, -1.5), V3(side * 0.45, 3.3, 4.3), 0.06, chrome) // ladder rails
  }
  for i in 0..<12 { tube(root, V3(-0.45, 3.25, -1.4 + Float(i) * 0.5), V3(0.45, 3.25, -1.4 + Float(i) * 0.5), 0.03, chrome) }
  box(root, 1.6, 0.14, 0.3, material("light-red", 0xFF2D2D, emit: true), 0, 3.08, -4.0)
  wheelsAt(root, axles: [-3.9], track: 2.15, radius: 0.55)
  wheelsAt(root, axles: [2.6], track: 2.15, radius: 0.55, dual: true)
  return root
}

// MARK: Motorcycles

func motorcycle(kind: String, body: UInt32) -> SCNNode {
  let root = SCNNode()
  let p = paint(body)
  let sport = kind == "sport", cruiser = kind == "cruiser", dirt = kind == "dirt"
  let wb: Float = cruiser ? 1.7 : (dirt ? 1.48 : 1.42)
  let rF: Float = dirt ? 0.4 : 0.31, rR: Float = dirt ? 0.37 : 0.31
  for (z, r, w) in [(-wb / 2, rF, Float(dirt ? 0.09 : 0.12)), (wb / 2, rR, Float(cruiser ? 0.2 : (dirt ? 0.11 : 0.19)))] {
    put(root, TubeMesh(innerRadius: CGFloat(r * 0.62), outerRadius: CGFloat(r), height: CGFloat(w)), tyre, 0, r, z, rz: .pi / 2)
    put(root, CylinderMesh(radius: CGFloat(r * 0.62), height: CGFloat(w * 0.5)), rim, 0, r, z, rz: .pi / 2)
    put(root, CylinderMesh(radius: CGFloat(r * 0.4), height: CGFloat(w * 0.7)), chrome, 0, r, z, rz: .pi / 2) // disc
  }
  // Engine block and exhaust.
  box(root, 0.36, 0.4, 0.5, plastic, 0, 0.5, 0.05)
  if cruiser {
    for a in [-0.45, 0.45] as [Float] { tube(root, V3(0, 0.45, 0.05), V3(0, 0.45 + 0.4 * cos(a), 0.05 + 0.4 * sin(a)), 0.1, chrome) }
  }
  tube(root, V3(0.18, 0.35, 0.1), V3(0.2, cruiser ? 0.32 : 0.55, wb / 2 + 0.25), 0.05, chrome)
  // Forks.
  let rake: Float = cruiser ? 0.5 : 0.42
  let headY: Float = dirt ? 1.15 : (cruiser ? 0.95 : 0.9)
  let headZ = -wb / 2 + sin(rake) * (headY - rF) * 0.9
  for x in [-0.09, 0.09] as [Float] { tube(root, V3(x, rF, -wb / 2), V3(x, headY, headZ), 0.025, chrome) }
  if sport {
    // Fairing, tank, tail, windscreen.
    root.addChildNode(loft([
      Station(z: headZ - 0.32, width: 0.18, bottom: 0.62, top: 0.85, n: 2.2),
      Station(z: headZ - 0.05, width: 0.46, bottom: 0.38, top: 1.0, n: 2.4),
      Station(z: headZ + 0.45, width: 0.44, bottom: 0.32, top: 0.95, n: 2.4),
      Station(z: 0.25, width: 0.38, bottom: 0.55, top: 0.93, n: 2.5),
      Station(z: 0.55, width: 0.28, bottom: 0.72, top: 0.86, n: 2.5),
      Station(z: wb / 2 + 0.15, width: 0.14, bottom: 0.82, top: 0.95, n: 2.2),
    ], segments: 24, p))
    put(root, BoxMesh(width: 0.28, height: 0.22, length: 0.02), glass, 0, 1.06, headZ - 0.02, rx: -0.6)
    box(root, 0.24, 0.05, 0.42, leather, 0, 0.9, 0.45)
    box(root, 0.16, 0.06, 0.03, headlight, 0, 0.82, headZ - 0.34)
  } else if cruiser {
    root.addChildNode(loft([
      Station(z: headZ + 0.05, width: 0.2, bottom: 0.8, top: 0.92, n: 2.2),
      Station(z: headZ + 0.35, width: 0.38, bottom: 0.72, top: 0.98, n: 2.2),
      Station(z: 0.15, width: 0.3, bottom: 0.74, top: 0.92, n: 2.2),
    ], segments: 22, p))
    root.addChildNode(loft([
      Station(z: 0.15, width: 0.34, bottom: 0.62, top: 0.72, n: 3),
      Station(z: 0.6, width: 0.38, bottom: 0.64, top: 0.78, n: 3),
    ], segments: 18, leather))
    let fender = TubeMesh(innerRadius: CGFloat(rR + 0.04), outerRadius: CGFloat(rR + 0.07), height: 0.24)
    put(root, fender, p, 0, rR, wb / 2, rz: .pi / 2)
    tube(root, V3(-0.42, headY + 0.12, headZ + 0.18), V3(0.42, headY + 0.12, headZ + 0.18), 0.02, chrome)
    put(root, CylinderMesh(radius: 0.1, height: 0.08), headlight, 0, headY - 0.08, headZ - 0.12, rx: .pi / 2)
  } else {
    // Dirt bike: high fenders, slim tank, flat seat, number plate.
    root.addChildNode(loft([
      Station(z: headZ + 0.05, width: 0.3, bottom: 0.82, top: 1.02, n: 2.4),
      Station(z: 0.1, width: 0.26, bottom: 0.84, top: 0.98, n: 2.4),
      Station(z: wb / 2 + 0.3, width: 0.14, bottom: 0.92, top: 1.0, n: 2.4),
    ], segments: 20, p))
    box(root, 0.22, 0.05, 0.7, leather, 0, 1.0, 0.25)
    box(root, 0.16, 0.02, 0.45, p, 0, rF * 2 + 0.06, -wb / 2 + 0.02)
    box(root, 0.24, 0.22, 0.03, white, 0, headY - 0.05, headZ - 0.06)
  }
  // Bars and mirrors.
  if !cruiser { tube(root, V3(-0.36, headY + 0.06, headZ + 0.08), V3(0.36, headY + 0.06, headZ + 0.08), 0.016, black) }
  box(root, 0.1, 0.05, 0.03, taillight, 0, 0.88, wb / 2 + 0.2)
  return root
}

// MARK: Rail

func tram(livery: UInt32) -> SCNNode {
  let root = SCNNode()
  let p = paint(livery)
  for (offset, cab) in [(Float(-7.6), true), (Float(7.6), false)] {
    let L: Float = 14.8, W: Float = 2.65, H: Float = 3.4
    let s = SCNNode()
    s.simdPosition = V3(0, 0, offset)
    s.addChildNode(loft([
      Station(z: -L / 2, width: W * (cab ? 0.85 : 0.98), bottom: 0.35, top: H * (cab ? 0.85 : 0.98), n: cab ? 3 : 6),
      Station(z: -L / 2 + (cab ? 0.9 : 0.05), width: W, bottom: 0.3, top: H, n: 6),
      Station(z: L / 2 - (cab ? 0.05 : 0.9), width: W, bottom: 0.3, top: H, n: 6),
      Station(z: L / 2, width: W * (cab ? 0.98 : 0.85), bottom: 0.35, top: H * (cab ? 0.98 : 0.85), n: cab ? 6 : 3),
    ], segments: 32, white))
    windowBand(s, width: W, y: 2.15, height: 1.3, from: -L / 2 + 1.2, to: L / 2 - 1.2, panes: 6)
    for side in [-1, 1] as [Float] { box(s, 0.03, 0.45, L - 0.6, p, side * (W / 2 + 0.006), 0.9, 0) }
    for z in [-L / 2 + 2.5, L / 2 - 2.5] {
      box(s, 2.2, 0.5, 2.0, black, 0, 0.35, z) // bogie
    }
    root.addChildNode(s)
  }
  put(root, BoxMesh(width: 2.3, height: 1.7, length: 0.04), glass, 0, 2.2, -15.1, rx: -0.15)
  // Pantograph.
  tube(root, V3(0, 3.45, -9), V3(0, 4.4, -8.2), 0.03, chrome)
  tube(root, V3(0, 4.4, -8.2), V3(0, 4.6, -9.3), 0.03, chrome)
  box(root, 1.6, 0.04, 0.1, chrome, 0, 4.62, -9.3)
  box(root, 0.3, 0.14, 0.04, headlight, -0.7, 0.9, -15.0); box(root, 0.3, 0.14, 0.04, headlight, 0.7, 0.9, -15.0)
  return root
}

func highSpeedTrain(livery: UInt32) -> SCNNode {
  let root = SCNNode()
  let p = paint(livery)
  let W: Float = 2.95, H: Float = 3.7
  // Long aerodynamic power car nose.
  root.addChildNode(loft([
    Station(z: -12.5, width: 0.4, bottom: 0.7, top: 1.0, n: 2),
    Station(z: -11.0, width: 1.9, bottom: 0.45, top: 1.9, n: 2.3),
    Station(z: -9.0, width: 2.7, bottom: 0.4, top: 3.0, n: 3),
    Station(z: -7.0, width: W, bottom: 0.4, top: H, n: 4),
    Station(z: 12.5, width: W, bottom: 0.4, top: H, n: 4),
  ], segments: 32, white))
  root.addChildNode(loft([
    Station(z: -10.6, width: 1.7, bottom: 1.75, top: 2.0, n: 2.3),
    Station(z: -8.8, width: 2.6, bottom: 2.2, top: 2.95, n: 2.6),
    Station(z: -8.2, width: 2.75, bottom: 2.3, top: 3.2, n: 3),
  ], segments: 24, glass))
  for side in [-1, 1] as [Float] {
    box(root, 0.03, 0.35, 21.5, p, side * (W / 2 + 0.006), 1.3, 1.6)
    box(root, 0.025, 0.08, 23, p, side * (W / 2 + 0.006), 0.85, 0.8)
  }
  windowBand(root, width: W, y: 2.35, height: 0.75, from: -5.5, to: 12, panes: 10)
  // Second car.
  box(root, W, H - 0.4, 25, white, 0, (H + 0.4) / 2 + 0.0, 25.4)
  windowBand(root, width: W, y: 2.35, height: 0.75, from: 13.5, to: 37, panes: 14)
  for side in [-1, 1] as [Float] { box(root, 0.03, 0.35, 25, p, side * (W / 2 + 0.006), 1.3, 25.4) }
  for z in [-5.0, 9.5, 16.0, 34.0] as [Float] { box(root, 2.4, 0.55, 2.6, black, 0, 0.32, z) }
  box(root, 0.5, 0.12, 0.05, headlight, 0, 1.0, -12.45)
  return root
}

// MARK: More boats

func yacht(hull: UInt32) -> SCNNode {
  let root = SCNNode()
  root.addChildNode(loft([
    Station(z: -9.0, width: 0.2, bottom: 1.6, top: 2.6, n: 2),
    Station(z: -7.0, width: 3.6, bottom: 0.4, top: 2.7, n: 2.2, bulge: 0.15),
    Station(z: -2.0, width: 5.4, bottom: 0.0, top: 2.6, n: 2.8, bulge: 0.12),
    Station(z: 7.6, width: 5.2, bottom: 0.2, top: 2.4, n: 3.4),
    Station(z: 8.4, width: 4.8, bottom: 0.6, top: 2.35, n: 3.4),
  ], segments: 32, paint(hull)))
  root.addChildNode(loft([
    Station(z: -8.2, width: 2.0, bottom: 2.55, top: 2.75, n: 2.2),
    Station(z: 8.3, width: 4.7, bottom: 2.3, top: 2.5, n: 3.4),
  ], segments: 28, wood))
  for (z0, z1, w, y0, h) in [(Float(-4.5), Float(5.5), Float(4.2), Float(2.6), Float(1.6)), (-2.5, 3.5, 3.4, 4.2, 1.3), (-1.0, 2.0, 2.4, 5.5, 0.9)] {
    root.addChildNode(loft([
      Station(z: z0, width: w * 0.8, bottom: y0, top: y0 + h * 0.8, n: 3),
      Station(z: z0 + 1.2, width: w, bottom: y0, top: y0 + h, n: 4),
      Station(z: z1, width: w, bottom: y0, top: y0 + h, n: 4),
    ], segments: 28, white))
    for side in [-1, 1] as [Float] { box(root, 0.04, h * 0.45, (z1 - z0) * 0.8, glass, side * (w / 2 + 0.01), y0 + h * 0.55, (z0 + z1) / 2 + 0.3) }
  }
  tube(root, V3(0, 6.4, 0.5), V3(0, 8.4, 0.8), 0.06, chrome)
  box(root, 1.2, 0.08, 0.08, chrome, 0, 8.0, 0.75)
  return root
}

func jetSki(body: UInt32) -> SCNNode {
  let root = SCNNode()
  root.addChildNode(loft([
    Station(z: -1.6, width: 0.2, bottom: 0.25, top: 0.55, n: 2),
    Station(z: -1.0, width: 1.0, bottom: 0.05, top: 0.7, n: 2.4, bulge: 0.15),
    Station(z: 0.6, width: 1.15, bottom: 0.0, top: 0.62, n: 3),
    Station(z: 1.5, width: 1.05, bottom: 0.05, top: 0.5, n: 3.4),
  ], segments: 24, paint(body)))
  root.addChildNode(loft([
    Station(z: -0.4, width: 0.42, bottom: 0.62, top: 0.85, n: 3),
    Station(z: 0.9, width: 0.45, bottom: 0.58, top: 0.82, n: 3),
  ], segments: 18, leather))
  tube(root, V3(0, 0.75, -0.75), V3(0, 1.0, -0.55), 0.04, black)
  tube(root, V3(-0.35, 1.02, -0.55), V3(0.35, 1.02, -0.55), 0.02, black)
  put(root, BoxMesh(width: 0.5, height: 0.2, length: 0.02), glass, 0, 0.88, -0.95, rx: -0.9)
  return root
}

// MARK: More aircraft

func widebody(livery: UInt32) -> SCNNode {
  let holder = SCNNode()
  let plane = airliner(livery: livery)
  plane.simdScale = V3(1.55, 1.55, 1.65) // ~63 m long, ~60 m span
  holder.addChildNode(plane)
  return holder
}

/// A flat surface (fin or tail) from a polygon in its own plane, given
/// thickness, placed and rotated.
func plate(_ root: SCNNode, _ outline: [SIMD2<Float>], thickness: Float, _ m: SCNMaterial,
           at p: V3, ry: Float = 0, rz: Float = 0, rx: Float = 0) {
  let g = PanelMesh(outline)
  let node = put(root, g, m, p.x, p.y, p.z, rx: rx, ry: ry, rz: rz)
  node.geometry?.firstMaterial?.isDoubleSided = true
  _ = thickness
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

/// Builds a ribbon `width` wide through surface points with their normals.
func ribbon(_ m: Mesh, _ pts: [(V3, V3)], width: Float) {
  guard pts.count >= 2 else { return }
  var left: [V3] = [], right: [V3] = []
  for i in 0..<pts.count {
    let (p, n) = pts[i]
    let d = pts[min(pts.count - 1, i + 1)].0 - pts[max(0, i - 1)].0
    var side = simd_cross(n, d)
    if simd_length(side) < 1e-6 { side = V3(1, 0, 0) }
    side = simd_normalize(side) * (width / 2)
    left.append(p - side); right.append(p + side)
  }
  for i in 0..<(pts.count - 1) {
    let n0 = pts[i].1, n1 = pts[i + 1].1
    emitTri(m, left[i], right[i], right[i + 1], n0, n0, n1)
    emitTri(m, left[i], right[i + 1], left[i + 1], n0, n1, n1)
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
  init(_ root: SCNNode, skip: Set<String> = ["canopy"]) {
    root.enumerateHierarchy { node, _ in
      guard let g = node.geometry, let vs = g.sources(for: .vertex).first else { return }
      if let name = g.firstMaterial?.name, skip.contains(name) { return }
      let t = node.simdConvertTransform(matrix_identity_float4x4, to: root)
      let pts = vectors(vs).map { v -> V3 in let w = t * SIMD4<Float>(v.x, v.y, v.z, 1); return V3(w.x, w.y, w.z) }
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
    return best
  }
}

/// Panel lines draped over the top (or the belly) along (x, z) polylines,
/// optionally mirrored to the left side.
func decalLines(_ p: SCNNode, _ d: Drape, _ lines: [[SIMD2<Float>]], width: Float = 0.03, _ m: SCNMaterial,
                below: Bool = false, mirror: Bool = true, lift: Float = 0.012) {
  let mesh = Mesh()
  for flip in mirror ? [Float(1), -1] : [1] {
    for line in lines {
      var run: [(V3, V3)] = []
      for k in 0..<(line.count - 1) {
        let a = line[k] * SIMD2(flip, 1), b = line[k + 1] * SIMD2(flip, 1)
        let steps = max(1, Int(simd_length(b - a) / 0.08))
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
                  mirror: Bool = false, lift: Float = 0.014) {
  let mesh = Mesh()
  let k = 4
  for flip in mirror ? [Float(1), -1] : [1] {
    for poly0 in polys {
      let poly = poly0.map { $0 * SIMD2(flip, 1) }
      let c = poly.reduce(SIMD2<Float>(0, 0), +) / Float(poly.count)
      for e in 0..<poly.count {
        let a = poly[e], b = poly[(e + 1) % poly.count]
        func q(_ i: Int, _ j: Int) -> (V3, V3)? {
          let s = c + (a - c) * (Float(i) / Float(k)) + (b - c) * (Float(j) / Float(k))
          guard let (pt, n) = d.hit(s.x, s.y, below: below) else { return nil }
          return (pt + n * lift, n)
        }
        for i in 0..<k {
          for j in 0..<(k - i) {
            if let x = q(i, j), let y = q(i + 1, j), let z = q(i, j + 1) { emitTri(mesh, x.0, y.0, z.0, x.1, y.1, z.1) }
            if i + j < k - 1, let x = q(i + 1, j), let y = q(i + 1, j + 1), let z = q(i, j + 1) {
              emitTri(mesh, x.0, y.0, z.0, x.1, y.1, z.1)
            }
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

func helicopter(livery: UInt32) -> SCNNode {
  let root = SCNNode()
  let p = paint(livery), cy: Float = 1.6
  root.addChildNode(loft([
    Station(z: -2.6, width: 0.6, bottom: cy - 0.35, top: cy + 0.35, n: 2),
    Station(z: -1.8, width: 1.6, bottom: cy - 0.85, top: cy + 0.8, n: 2.4),
    Station(z: 0.4, width: 1.7, bottom: cy - 0.8, top: cy + 0.9, n: 2.6),
    Station(z: 1.6, width: 1.0, bottom: cy - 0.2, top: cy + 0.75, n: 2.4),
  ], segments: 28, p))
  root.addChildNode(loft([
    Station(z: -2.62, width: 0.5, bottom: cy - 0.25, top: cy + 0.3, n: 2),
    Station(z: -1.6, width: 1.62, bottom: cy - 0.5, top: cy + 0.82, n: 2.4),
    Station(z: -0.9, width: 1.66, bottom: cy - 0.2, top: cy + 0.86, n: 2.5),
  ], segments: 24, glass))
  root.addChildNode(loft([
    Station(z: 1.5, width: 0.5, bottom: cy + 0.25, top: cy + 0.7, n: 2.2),
    Station(z: 6.4, width: 0.18, bottom: cy + 0.4, top: cy + 0.62, n: 2.2),
  ], segments: 16, p))
  plate(root, [SIMD2(0, 0), SIMD2(0.9, 0), SIMD2(0.9, 1.2), SIMD2(0.4, 1.2)], thickness: 0, p, at: V3(0, cy + 0.5, 6.0), ry: -.pi / 2)
  box(root, 1.4, 0.06, 0.4, p, 0, cy + 0.5, 5.4)
  // Rotor mast, four main blades, tail rotor.
  tube(root, V3(0, cy + 0.9, -0.2), V3(0, cy + 1.35, -0.2), 0.1, black)
  put(root, CylinderMesh(radius: 0.22, height: 0.15), black, 0, cy + 1.38, -0.2)
  for i in 0..<4 {
    let a = Float(i) * .pi / 2 + 0.3
    box(root, 0.32, 0.05, 5.4, black, sin(a) * 2.8, cy + 1.4, -0.2 + cos(a) * 2.8, ry: a)
  }
  for i in 0..<2 { box(root, 0.04, 1.3, 0.16, black, 0.18, cy + 0.9, 6.3, rx: Float(i) * .pi / 2) }
  // Skids.
  for x in [-0.8, 0.8] as [Float] {
    tube(root, V3(x, 0.08, -1.6), V3(x, 0.08, 1.4), 0.05, chrome)
    tube(root, V3(x * 0.6, cy - 0.7, -0.8), V3(x, 0.08, -0.9), 0.04, chrome)
    tube(root, V3(x * 0.6, cy - 0.7, 0.8), V3(x, 0.08, 0.7), 0.04, chrome)
  }
  return root
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

/// A round section from z0 to z1 with radius r0 at the bottom and r1 at the top.
func stage(_ parent: SCNNode, _ z0: Float, _ z1: Float, _ r0: Float, _ r1: Float, _ m: SCNMaterial, segments: Int = 32) {
  parent.addChildNode(loft([
    Station(z: z0, width: r0 * 2, bottom: -r0, top: r0, n: 2),
    Station(z: z1, width: r1 * 2, bottom: -r1, top: r1, n: 2),
  ], segments: segments, m))
}

/// An ogive nose from z0 (radius r) to a point at z1.
func nose(_ parent: SCNNode, _ z0: Float, _ z1: Float, _ r: Float, _ m: SCNMaterial, tip: Float = 0.04) {
  var st: [Station] = []
  for i in 0...8 {
    let t = Float(i) / 8
    let rr = max(tip, r * sqrt(max(0, 1 - t * t)))
    st.append(Station(z: z0 + (z1 - z0) * t, width: rr * 2, bottom: -rr, top: rr, n: 2))
  }
  parent.addChildNode(loft(st, segments: 32, m))
}

/// A part on the side of a lying rocket: x across, y "up" before standing
/// (becomes -z, front/back), z height.
func side(_ parent: SCNNode, _ w: Float, _ h: Float, _ l: Float, _ m: SCNMaterial, x: Float, y: Float, z: Float, rz: Float = 0) {
  box(parent, w, h, l, m, x, y, z, rz: rz)
}

let steel = material("steel", 0xDCDFE2, metal: 0.65, rough: 0.32)
let tile = material("heat-shield", 0x17181A, rough: 0.8)
let rocketWhite = material("white", 0xF4F4F2, metal: 0.1, rough: 0.5)
let foam = material("tank-foam", 0xC8692B, rough: 0.85)
let engineBell = material("engine", 0x3B3D40, metal: 0.8, rough: 0.35)

// starshipStack() is built with the Starbase pad models further down.

func falcon9() -> SCNNode {
  let r = SCNNode()
  let R: Float = 1.83
  stage(r, 0, 41, R, R, rocketWhite)          // first stage
  stage(r, 41, 47, R, R, tile)                // interstage
  stage(r, 47, 59, R, R, rocketWhite)         // second stage
  stage(r, 59, 61, R, 2.6, rocketWhite)       // fairing base
  stage(r, 61, 67, 2.6, 2.6, rocketWhite)
  nose(r, 67, 70, 2.6, rocketWhite, tip: 0.2)
  side(r, 0.12, 0.6, 37, tile, x: 0, y: R, z: 21) // flag stripe area
  for a in [Float(0), .pi / 2, .pi, 3 * .pi / 2] {
    let c = SCNNode(); c.simdOrientation = simd_quatf(angle: a, axis: V3(0, 0, 1)); r.addChildNode(c)
    side(c, 0.2, 1.0, 9.5, tile, x: R + 0.1, y: 0, z: 4.8)       // folded landing leg
    side(c, 1.6, 0.15, 1.5, tile, x: R + 0.8, y: 0, z: 46)       // grid fin
  }
  for i in 0..<9 {
    let a = Float(i) / 8 * 2 * .pi
    let rr: Float = i == 8 ? 0 : 1.2
    put(r, CylinderMesh(radius: 0.32, height: 0.9, sides: 12), engineBell, cos(a) * rr, sin(a) * rr, -0.3, rx: .pi / 2)
  }
  return standUp(r)
}

func saturnV() -> SCNNode {
  let r = SCNNode()
  let R: Float = 5.05
  stage(r, 0, 42, R, R, rocketWhite)                 // S-IC
  for k in 0..<4 {                                   // roll pattern bands
    let a = Float(k) * .pi / 2
    let c = SCNNode(); c.simdOrientation = simd_quatf(angle: a, axis: V3(0, 0, 1)); r.addChildNode(c)
    side(c, R * 0.75, 0.2, 8, tile, x: R * 0.35, y: R * 0.93, z: 34)
    side(c, R * 0.75, 0.2, 7, tile, x: R * 0.35, y: R * 0.93, z: 4)
    side(c, 0.5, 4.5, 7, rocketWhite, x: R + 0.3, y: 0, z: 3.5)       // fin
  }
  stage(r, 42, 47, R, R, tile)                       // S-II interstage
  stage(r, 47, 66, R, R, rocketWhite)                // S-II
  stage(r, 66, 72, R, 3.3, rocketWhite)              // taper
  stage(r, 72, 90, 3.3, 3.3, rocketWhite)            // S-IVB
  stage(r, 90, 97, 3.3, 1.95, rocketWhite)           // instrument unit, SLA
  nose(r, 97, 103, 1.95, rocketWhite, tip: 0.4)      // command module
  tube(r, V3(0, 0, 103), V3(0, 0, 110.6), 0.15, tile) // launch escape tower
  for i in 0..<5 {
    let a = Float(i) / 4 * 2 * .pi
    let rr: Float = i == 4 ? 0 : 2.8
    put(r, TubeMesh(innerRadius: 1.2, outerRadius: 1.75, height: 5.8, sides: 20), engineBell, cos(a) * rr, sin(a) * rr, -2.9, rx: .pi / 2)
  }
  return standUp(r)
}

func shuttleStack() -> SCNNode {
  let r = SCNNode()
  // External tank, 47 m, 8.4 m wide, with ogive nose.
  stage(r, 0, 38, 4.2, 4.2, foam)
  nose(r, 38, 47, 4.2, foam, tip: 0.3)
  // Two solid rocket boosters either side.
  for s in [-1, 1] as [Float] {
    let b = SCNNode(); b.simdPosition = V3(s * 6.1, 0, 0); r.addChildNode(b)
    stage(b, 0, 40, 1.85, 1.85, rocketWhite)
    nose(b, 40, 45.5, 1.85, rocketWhite, tip: 0.15)
    stage(b, -3, 0, 2.4, 1.85, rocketWhite)              // aft skirt
  }
  // Orbiter, belly (black tiles) against the tank: fuselage, delta wing,
  // fin on the far side, three main engines at the tail.
  let o = SCNNode(); o.simdPosition = V3(0, -6.3, 0); r.addChildNode(o)
  o.addChildNode(loft([
    Station(z: -1, width: 4.6, bottom: -2.0, top: 2.4, n: 3),
    Station(z: 26, width: 5.2, bottom: -2.3, top: 2.5, n: 3),
    Station(z: 32, width: 4.2, bottom: -1.9, top: 2.2, n: 2.6),
    Station(z: 36.5, width: 0.8, bottom: -0.3, top: 0.6, n: 2),
  ], segments: 28, rocketWhite))
  let wingOutline = [SIMD2<Float>(-12, 0), SIMD2(12, 0), SIMD2(2.3, 20), SIMD2(-2.3, 20)]
  plate(o, wingOutline, thickness: 0.3, rocketWhite, at: V3(0, 1.9, 1), rx: .pi / 2)
  plate(o, wingOutline, thickness: 0.3, tile, at: V3(0, 1.98, 1), rx: .pi / 2)
  plate(o, [SIMD2(0, 0), SIMD2(7.5, 0), SIMD2(3.5, 8), SIMD2(0.8, 8)], thickness: 0.3, rocketWhite, at: V3(0, -2.0, -1))
  o.childNodes.last?.simdOrientation = simd_quatf(angle: .pi, axis: V3(0, 0, 1)) * simd_quatf(angle: -.pi / 2, axis: V3(0, 1, 0))
  side(o, 4.0, 0.3, 30, tile, x: 0, y: 2.45, z: 16)
  for i in 0..<3 {
    let a = Float(i) / 3 * 2 * .pi
    put(o, CylinderMesh(radius: 0.65, height: 1.6, sides: 14), engineBell, cos(a) * 1.0, -0.6 + sin(a) * 0.9, -1.6, rx: .pi / 2)
  }
  return standUp(r)
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

func save(_ node: SCNNode, _ name: String) {
  fixMaterialCounts(node)
  let scene = SCNScene()
  scene.rootNode.addChildNode(node)
  let url = URL(fileURLWithPath: CommandLine.arguments[1] + "/\(name).usdz")
  if !scene.write(to: url, options: nil, delegate: nil, progressHandler: nil) { fatalError(name) }
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
save(yacht(hull: 0xF8F8F8), "boat-yacht")
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
