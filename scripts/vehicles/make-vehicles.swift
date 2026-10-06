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

/// Stealth fighter fuselage: a faceted loft (low superellipse exponent gives
/// chined, diamond-ish sections).
func fighterBody(_ root: SCNNode, length L: Float, width W: Float, height H: Float, cy: Float, _ m: SCNMaterial, faceted: Bool) {
  let n: Float = faceted ? 1.45 : 2.2
  root.addChildNode(loft([
    Station(z: -L / 2, width: 0.05, bottom: cy - 0.03, top: cy + 0.03, n: n),
    Station(z: -L / 2 + L * 0.12, width: W * 0.32, bottom: cy - H * 0.25, top: cy + H * 0.2, n: n),
    Station(z: -L / 2 + L * 0.3, width: W * 0.62, bottom: cy - H * 0.38, top: cy + H * 0.3, n: n),
    Station(z: -L / 2 + L * 0.55, width: W, bottom: cy - H * 0.42, top: cy + H * 0.28, n: n),
    Station(z: L / 2 - L * 0.1, width: W * 0.92, bottom: cy - H * 0.4, top: cy + H * 0.25, n: n),
    Station(z: L / 2, width: W * 0.7, bottom: cy - H * 0.32, top: cy + H * 0.2, n: n),
  ], segments: 24, m))
}

func canopy(_ root: SCNNode, z0: Float, z1: Float, width: Float, base: Float, height: Float) {
  root.addChildNode(loft([
    Station(z: z0, width: width * 0.3, bottom: base, top: base + height * 0.3, n: 2),
    Station(z: z0 + (z1 - z0) * 0.45, width: width, bottom: base, top: base + height, n: 2.2),
    Station(z: z1, width: width * 0.5, bottom: base, top: base + height * 0.45, n: 2),
  ], segments: 20, material("canopy", 0xB8860B, metal: 0.9, rough: 0.1)))
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

func f16(livery: UInt32) -> SCNNode {
  let root = SCNNode()
  let grey = paint(livery), cy: Float = 1.6
  fighterBody(root, length: 15, width: 1.5, height: 1.5, cy: cy, grey, faceted: false)
  canopy(root, z0: -5.4, z1: -2.6, width: 0.75, base: cy + 0.25, height: 0.62)
  box(root, 0.9, 0.7, 1.6, grey, 0, cy - 0.75, -2.4) // chin intake
  box(root, 0.8, 0.6, 0.04, black, 0, cy - 0.75, -3.2)
  for side in [-1, 1] as [Float] {
    // Cropped delta wing: leading edge swept 40 degrees.
    plate(root, [SIMD2(0, -2.2), SIMD2(0, 2.2), SIMD2(side * 4.7, 2.0), SIMD2(side * 4.7, 0.9)], thickness: 0.1, grey, at: V3(side * 0.6, cy - 0.1, 0.9), rx: .pi / 2)
    plate(root, [SIMD2(0, -0.6), SIMD2(0, 1.6), SIMD2(side * 2.6, 1.4), SIMD2(side * 2.6, 0.8)], thickness: 0.08, grey, at: V3(side * 0.4, cy - 0.1, 5.6), rx: .pi / 2)
    tube(root, V3(side * 5.3, cy - 0.1, 1.2), V3(side * 5.3, cy - 0.1, 3.4), 0.08, white) // wingtip missile
  }
  plate(root, [SIMD2(0, 0), SIMD2(3.2, 0), SIMD2(1.0, 3.3), SIMD2(0.2, 3.3)], thickness: 0.1, grey, at: V3(0, cy + 0.4, 4.4), ry: -.pi / 2)
  put(root, TubeMesh(innerRadius: 0.4, outerRadius: 0.55, height: 0.7), black, 0, cy, 7.7, rx: .pi / 2)
  return root
}

func f22(livery: UInt32) -> SCNNode {
  let root = SCNNode()
  let g = paint(livery), cy: Float = 1.7
  fighterBody(root, length: 18.9, width: 2.9, height: 1.6, cy: cy, g, faceted: true)
  canopy(root, z0: -6.8, z1: -3.4, width: 0.8, base: cy + 0.32, height: 0.7)
  for side in [-1, 1] as [Float] {
    // Caret intakes.
    plate(root, [SIMD2(0, 0), SIMD2(0, 1.0), SIMD2(side * 0.9, 0.5)], thickness: 0, black, at: V3(side * 1.0, cy - 0.5, -3.4), ry: 0)
    // Diamond wing: 42 degree leading edge, swept-forward trailing edge.
    plate(root, [SIMD2(0, -3.6), SIMD2(0, 3.0), SIMD2(side * 6.8, 1.9), SIMD2(side * 6.8, 0.6)], thickness: 0.1, g, at: V3(side * 1.2, cy - 0.05, 2.0), rx: .pi / 2)
    // Horizontal stabilisers.
    plate(root, [SIMD2(0, -1.2), SIMD2(0, 1.2), SIMD2(side * 2.8, 1.0), SIMD2(side * 2.8, 0.1)], thickness: 0.08, g, at: V3(side * 1.1, cy - 0.1, 8.4), rx: .pi / 2)
    // Twin canted vertical tails (28 degrees out).
    plate(root, [SIMD2(0, 0), SIMD2(3.4, 0), SIMD2(2.6, 2.9), SIMD2(0.8, 2.9)], thickness: 0.1, g, at: V3(side * 1.05, cy + 0.35, 5.6), ry: -.pi / 2, rz: 0)
    root.childNodes.last?.simdOrientation = simd_quatf(angle: side * -0.49, axis: V3(0, 0, 1)) * simd_quatf(angle: -.pi / 2, axis: V3(0, 1, 0))
    // Thrust-vectoring nozzles.
    box(root, 0.9, 0.7, 0.9, black, side * 0.6, cy - 0.15, 9.6)
  }
  return root
}

func f35(livery: UInt32) -> SCNNode {
  let root = SCNNode()
  let g = paint(livery), cy: Float = 1.75
  fighterBody(root, length: 15.7, width: 2.7, height: 1.9, cy: cy, g, faceted: true)
  canopy(root, z0: -5.2, z1: -2.2, width: 0.85, base: cy + 0.4, height: 0.72)
  for side in [-1, 1] as [Float] {
    plate(root, [SIMD2(0, 0), SIMD2(0, 1.1), SIMD2(side * 0.75, 0.55)], thickness: 0, black, at: V3(side * 1.05, cy - 0.4, -2.0))
    // Trapezoidal wing.
    plate(root, [SIMD2(0, -2.7), SIMD2(0, 2.4), SIMD2(side * 4.6, 1.7), SIMD2(side * 4.6, 0.1)], thickness: 0.1, g, at: V3(side * 1.1, cy - 0.1, 1.6), rx: .pi / 2)
    plate(root, [SIMD2(0, -1.1), SIMD2(0, 1.2), SIMD2(side * 2.4, 1.0), SIMD2(side * 2.4, 0.2)], thickness: 0.08, g, at: V3(side * 0.9, cy - 0.05, 6.7), rx: .pi / 2)
    plate(root, [SIMD2(0, 0), SIMD2(2.6, 0), SIMD2(2.2, 2.3), SIMD2(0.9, 2.3)], thickness: 0.1, g, at: V3(side * 0.85, cy + 0.45, 4.6), ry: -.pi / 2)
    root.childNodes.last?.simdOrientation = simd_quatf(angle: side * -0.44, axis: V3(0, 0, 1)) * simd_quatf(angle: -.pi / 2, axis: V3(0, 1, 0))
  }
  // Single big engine nozzle.
  put(root, TubeMesh(innerRadius: 0.45, outerRadius: 0.62, height: 0.8), black, 0, cy - 0.1, 8.1, rx: .pi / 2)
  return root
}

func yf23(livery: UInt32) -> SCNNode {
  let root = SCNNode()
  let g = paint(livery), cy: Float = 1.6
  fighterBody(root, length: 20.6, width: 2.2, height: 1.4, cy: cy, g, faceted: true)
  canopy(root, z0: -7.6, z1: -4.4, width: 0.75, base: cy + 0.25, height: 0.62)
  for side in [-1, 1] as [Float] {
    // Pure diamond wing: 40 degree leading edge, 40 degree forward-swept trailing edge.
    plate(root, [SIMD2(0, -4.6), SIMD2(0, 4.6), SIMD2(side * 6.5, 0.6), SIMD2(side * 6.5, -0.2)], thickness: 0.1, g, at: V3(side * 1.0, cy - 0.05, 2.6), rx: .pi / 2)
    // Engine nacelles under the wing, with trough exhausts.
    let nacelle = loft([
      Station(z: -1.6, width: 1.1, bottom: cy - 0.75, top: cy + 0.05, n: 1.6),
      Station(z: 6.0, width: 1.3, bottom: cy - 0.7, top: cy + 0.15, n: 1.6),
      Station(z: 8.6, width: 1.0, bottom: cy - 0.45, top: cy + 0.15, n: 1.6),
    ], segments: 18, g)
    nacelle.simdPosition = V3(side * 1.75, 0, 0)
    root.addChildNode(nacelle)
    // Big all-moving V-tails (ruddervators), canted 50 degrees.
    plate(root, [SIMD2(0, 0), SIMD2(4.0, 0), SIMD2(3.4, 3.4), SIMD2(1.4, 3.4)], thickness: 0.1, g, at: V3(side * 1.75, cy + 0.15, 6.0), ry: -.pi / 2)
    root.childNodes.last?.simdOrientation = simd_quatf(angle: side * -0.87, axis: V3(0, 0, 1)) * simd_quatf(angle: -.pi / 2, axis: V3(0, 1, 0))
  }
  return root
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

func starshipStack() -> SCNNode {
  let r = SCNNode()
  let R: Float = 4.5
  // Super Heavy booster: 71 m, with engine skirt, chines and grid fins.
  stage(r, 0, 71, R, R, steel)
  for i in 0..<20 {
    let a = Float(i) / 20 * 2 * .pi
    put(r, CylinderMesh(radius: 0.45, height: 1.2, sides: 14), engineBell, cos(a) * 3.2, sin(a) * 3.2, -0.4, rx: .pi / 2)
  }
  for a in [Float.pi / 4, 3 * Float.pi / 4, 5 * Float.pi / 4, 7 * Float.pi / 4] {
    let c = SCNNode(); c.simdOrientation = simd_quatf(angle: a, axis: V3(0, 0, 1)); r.addChildNode(c)
    side(c, 3.4, 0.25, 2.6, tile, x: R + 1.7, y: 0, z: 67.5)                     // grid fin
    side(c, 0.25, 0.5, 40, steel, x: R + 0.15, y: 0, z: 35)                       // chine
  }
  stage(r, 71, 72.5, R, R, tile) // hot-staging ring
  // Ship: 50 m, heat shield on one side, flaps fore and aft.
  stage(r, 72.5, 110, R, R, steel)
  nose(r, 110, 122.5, R, steel, tip: 0.6)
  side(r, R * 1.6, 0.4, 44, tile, x: 0, y: -R + 0.1, z: 97) // windward heat shield
  for s in [-1, 1] as [Float] {
    side(r, 3.2, 0.35, 9, tile, x: s * (R + 1.4), y: -0.3, z: 78)    // aft flaps
    side(r, 2.4, 0.35, 6, tile, x: s * (R + 0.9), y: -0.3, z: 113)   // forward flaps
  }
  return standUp(r)
}

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
save(f16(livery: 0x8A949E), "jet-f16")
save(f22(livery: 0x7D8790), "jet-f22")
save(f35(livery: 0x6B7580), "jet-f35")
save(yf23(livery: 0x5C6670), "jet-yf23")
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
