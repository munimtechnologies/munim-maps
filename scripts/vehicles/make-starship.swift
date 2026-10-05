import SceneKit
import Foundation

func pbr(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, metal: CGFloat, rough: CGFloat, emit: NSColor? = nil) -> SCNMaterial {
  let m = SCNMaterial(); m.lightingModel = .physicallyBased
  m.diffuse.contents = NSColor(red: r, green: g, blue: b, alpha: 1)
  m.metalness.contents = metal; m.roughness.contents = rough
  if let emit { m.emission.contents = emit }
  return m
}
func node(_ g: SCNGeometry, _ m: SCNMaterial, y: CGFloat, x: CGFloat = 0, z: CGFloat = 0) -> SCNNode {
  g.materials = Array(repeating: m, count: max(1, g.elements.count)); let n = SCNNode(geometry: g); n.position = SCNVector3(x, y, z); return n
}
let steel = pbr(0.78, 0.79, 0.8, metal: 0.9, rough: 0.32)
let dark = pbr(0.12, 0.12, 0.13, metal: 0.4, rough: 0.6)
let flame = pbr(1, 0.55, 0.15, metal: 0, rough: 1, emit: NSColor(red: 1, green: 0.6, blue: 0.2, alpha: 1))

// Starship stack: 71 m booster + 50 m ship, 9 m wide.
let ship = SCNScene()
let r: CGFloat = 4.5
ship.rootNode.addChildNode(node(SCNCylinder(radius: r, height: 71), steel, y: 35.5))
ship.rootNode.addChildNode(node(SCNCylinder(radius: r, height: 1.2), dark, y: 1.5)) // engine skirt band
ship.rootNode.addChildNode(node(SCNCylinder(radius: r, height: 38), steel, y: 71 + 19))
ship.rootNode.addChildNode(node(SCNCone(topRadius: 0.6, bottomRadius: r, height: 12), steel, y: 71 + 38 + 6))
for i in 0..<4 { // grid fins near the top of the booster
  let a = CGFloat(i) * .pi / 2 + .pi / 4
  let fin = node(SCNBox(width: 3.5, height: 2.5, length: 0.5, chamferRadius: 0), dark, y: 67, x: cos(a) * (r + 1.6), z: sin(a) * (r + 1.6))
  fin.eulerAngles.y = -a + .pi / 2
  ship.rootNode.addChildNode(fin)
}
for (i, y) in [(0, 76.0), (1, 76.0), (2, 103.0), (3, 103.0)] { // ship flaps
  let side: CGFloat = i % 2 == 0 ? 1 : -1
  let flap = node(SCNBox(width: 3, height: y < 90 ? 9 : 6, length: 0.4, chamferRadius: 0), dark, y: y, x: side * (r + 1.2))
  ship.rootNode.addChildNode(flap)
}
if !ship.write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "/starship.usdz"), options: nil, delegate: nil, progressHandler: nil) { fatalError("ship") }

// Launch tower: 146 m with two chopstick arms.
let tower = SCNScene()
tower.rootNode.addChildNode(node(SCNBox(width: 10, height: 146, length: 10, chamferRadius: 0), dark, y: 73))
for side in [-1.0, 1.0] {
  tower.rootNode.addChildNode(node(SCNBox(width: 2, height: 3, length: 30, chamferRadius: 0), dark, y: 118, x: CGFloat(side) * 6, z: 18))
}
let beacon = pbr(1, 0.1, 0.1, metal: 0, rough: 1, emit: NSColor(red: 1, green: 0.15, blue: 0.1, alpha: 1))
tower.rootNode.addChildNode(node(SCNSphere(radius: 1.6), beacon, y: 147.5))
if !tower.write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "/tower.usdz"), options: nil, delegate: nil, progressHandler: nil) { fatalError("tower") }
print("ok")
