import SceneKit
import AppKit
// Renders every .usdz in a folder from the side and from 3/4 above, in a grid.
let dir = URL(fileURLWithPath: CommandLine.arguments[1])
let files = try! FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "usdz" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
let cell = CGSize(width: 360, height: 240)
let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
var tiles: [(String, NSImage, NSImage)] = []
for f in files {
  let scene = try! SCNScene(url: f, options: nil)
  let (lo, hi) = scene.rootNode.boundingBox
  let size = Float(max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z))
  let center = SCNVector3((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2)
  scene.background.contents = NSColor(white: 0.93, alpha: 1)
  let floor = SCNNode(geometry: SCNFloor()); floor.geometry?.firstMaterial?.diffuse.contents = NSColor(white: 0.85, alpha: 1)
  scene.rootNode.addChildNode(floor)
  scene.lightingEnvironment.contents = NSColor(white: 0.8, alpha: 1); scene.lightingEnvironment.intensity = 1.2
  let sun = SCNNode(); sun.light = SCNLight(); sun.light!.type = .directional; sun.light!.intensity = 1600
  sun.light!.castsShadow = true; sun.eulerAngles = SCNVector3(-1.0, 0.6, 0); scene.rootNode.addChildNode(sun)
  let fill = SCNNode(); fill.light = SCNLight(); fill.light!.type = .directional; fill.light!.intensity = 900
  fill.eulerAngles = SCNVector3(-0.5, 2.3, 0); scene.rootNode.addChildNode(fill)
  func shot(_ dir: SCNVector3) -> NSImage {
    let cam = SCNNode(); cam.camera = SCNCamera(); cam.camera!.zFar = Double(size * 20); cam.camera!.fieldOfView = 30
    let d = size * 1.9
    cam.position = SCNVector3(center.x + dir.x * CGFloat(d), center.y + dir.y * CGFloat(d), center.z + dir.z * CGFloat(d))
    cam.look(at: center); scene.rootNode.addChildNode(cam)
    renderer.scene = scene; renderer.pointOfView = cam
    let img = renderer.snapshot(atTime: 0, with: cell, antialiasingMode: .multisampling4X)
    cam.removeFromParentNode(); return img
  }
  tiles.append((f.deletingPathExtension().lastPathComponent, shot(SCNVector3(0.75, 0.6, -0.7)), shot(SCNVector3(0.75, 0.6, -0.7))))
}
let cols = 4
let rows = (tiles.count + cols - 1) / cols
let single = CommandLine.arguments.count > 3
let rowHeight = single ? cell.height : cell.height * 2
let out = NSImage(size: NSSize(width: CGFloat(cols) * cell.width, height: CGFloat(rows) * rowHeight))
out.lockFocus()
for (i, t) in tiles.enumerated() {
  let x = CGFloat(i % cols) * cell.width, y = out.size.height - CGFloat(i / cols + 1) * rowHeight
  if single {
    t.1.draw(in: NSRect(x: x, y: y, width: cell.width, height: cell.height))
  } else {
    t.2.draw(in: NSRect(x: x, y: y, width: cell.width, height: cell.height))
    t.1.draw(in: NSRect(x: x, y: y + cell.height, width: cell.width, height: cell.height))
  }
  (t.0 as NSString).draw(at: NSPoint(x: x + 10, y: y + rowHeight - 26), withAttributes: [.font: NSFont.boldSystemFont(ofSize: 16)])
}
out.unlockFocus()
let rep = NSBitmapImageRep(data: out.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print("sheet", tiles.count)
