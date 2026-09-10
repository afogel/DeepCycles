
import AppKit

// Renders the DeepCycles icon: paper square, "dc" in the system serif, ring as full stop.
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let rect = CGRect(x: 0, y: 0, width: size, height: size)
let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0, dy: 0), xRadius: size * 0.22, yRadius: size * 0.22)
NSColor(srgbRed: 246/255, green: 244/255, blue: 239/255, alpha: 1).setFill()
path.fill()
let ink = NSColor(srgbRed: 31/255, green: 42/255, blue: 61/255, alpha: 1)
let blue = NSColor(srgbRed: 36/255, green: 66/255, blue: 118/255, alpha: 1)
func serif(_ weight: NSFont.Weight, _ pt: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: pt, weight: weight)
    let desc = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
    return NSFont(descriptor: desc, size: pt) ?? base
}
let d = NSAttributedString(string: "d", attributes: [.font: serif(.bold, size * 0.62), .foregroundColor: ink])
let c = NSAttributedString(string: "c", attributes: [.font: serif(.light, size * 0.62), .foregroundColor: ink])
let dSize = d.size(), cSize = c.size()
let ringR = size * 0.045
let gap = size * 0.04
let total = dSize.width + cSize.width + gap + ringR * 2
var x = (size - total) / 2
let baseline = size * 0.36
d.draw(at: NSPoint(x: x, y: baseline - dSize.height * 0.22)); x += dSize.width
c.draw(at: NSPoint(x: x, y: baseline - cSize.height * 0.22)); x += cSize.width + gap
ctx.setStrokeColor(blue.cgColor)
ctx.setLineWidth(ringR * 0.55)
ctx.setLineCap(.round)
ctx.addArc(center: CGPoint(x: x + ringR, y: baseline + ringR * 0.9), radius: ringR, startAngle: .pi / 2, endAngle: .pi / 2 + .pi * 1.7, clockwise: false)
ctx.strokePath()
img.unlockFocus()
let out = CommandLine.arguments.dropFirst().first ?? "icon_1024.png"
let tiff = img.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
