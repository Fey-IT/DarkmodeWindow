import Metal
import AppKit
import CoreText

// Usage: shader-preview [input.png] [output.png] [scale]
// Without input a synthetic slide is rendered. Output shows original (top) and converted (bottom).
let args = CommandLine.arguments
let inputImage: CGImage? = args.count > 1 ? NSImage(contentsOfFile: args[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil) : nil
let outputPath = args.count > 2 ? args[2] : "preview.png"
let scale: Float = args.count > 3 ? Float(args[3]) ?? 2 : (inputImage == nil ? 1 : 2)
let W = inputImage?.width ?? 1200, H = inputImage?.height ?? 700
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W*4, space: cs,
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
// Left: dark Teams-like UI; right: white slide
ctx.setFillColor(NSColor(srgbRed: 0.12, green: 0.12, blue: 0.14, alpha: 1).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 220, height: H))
ctx.setFillColor(.white); ctx.fill(CGRect(x: 220, y: 0, width: W-220, height: H))
func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ c: NSColor, bold: Bool = false) {
    let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: c]))
    ctx.textPosition = CGPoint(x: x, y: y); CTLineDraw(line, ctx)
}
text("Teams Chat", 20, 640, 16, .white, bold: true)
text("Hi everyone", 20, 600, 13, NSColor(white: 0.85, alpha: 1))
text("Quarterly Results 2026", 260, 610, 44, .black, bold: true)
text("Revenue up 12 % – costs stable", 260, 550, 24, NSColor(white: 0.25, alpha: 1))
text("Important: deadline 30 Sep", 260, 500, 24, NSColor(srgbRed: 0.8, green: 0.1, blue: 0.1, alpha: 1), bold: true)
text("Link: intranet.example.com", 260, 460, 22, NSColor(srgbRed: 0.1, green: 0.3, blue: 0.85, alpha: 1))
let bars: [(CGFloat, NSColor)] = [(180, .systemBlue), (240, .systemOrange), (120, .systemGreen), (300, NSColor(srgbRed: 0.5, green: 0.2, blue: 0.7, alpha: 1))]
for (i, b) in bars.enumerated() { ctx.setFillColor(b.1.cgColor); ctx.fill(CGRect(x: 280 + CGFloat(i)*90, y: 80, width: 60, height: b.0)) }
// "Photo": gradient block
let grad = CGGradient(colorsSpace: cs, colors: [NSColor(srgbRed: 0.9, green: 0.7, blue: 0.5, alpha: 1).cgColor, NSColor(srgbRed: 0.2, green: 0.35, blue: 0.2, alpha: 1).cgColor] as CFArray, locations: nil)!
ctx.saveGState(); ctx.clip(to: CGRect(x: 780, y: 80, width: 340, height: 300))
ctx.drawLinearGradient(grad, start: CGPoint(x: 780, y: 380), end: CGPoint(x: 1120, y: 80), options: []); ctx.restoreGState()
ctx.setFillColor(NSColor(srgbRed: 0.93, green: 0.95, blue: 1.0, alpha: 1).cgColor); ctx.fill(CGRect(x: 780, y: 420, width: 340, height: 60))
text("Light blue info box", 800, 440, 20, NSColor(srgbRed: 0.1, green: 0.2, blue: 0.5, alpha: 1))
if let inputImage { ctx.draw(inputImage, in: CGRect(x: 0, y: 0, width: W, height: H)) }
if inputImage == nil {
    ctx.setFillColor(NSColor(srgbRed: 0.93, green: 0.55, blue: 0.2, alpha: 1).cgColor)
    let button = CGPath(roundedRect: CGRect(x: 780, y: 520, width: 340, height: 44), cornerWidth: 8, cornerHeight: 8, transform: nil)
    ctx.addPath(button); ctx.fillPath()
    text("Sign in", 800, 534, 18, .white, bold: true)
    ctx.setFillColor(NSColor(srgbRed: 0.2, green: 0.45, blue: 0.85, alpha: 1).cgColor); ctx.fill(CGRect(x: 780, y: 590, width: 340, height: 40))
    text("Header", 800, 602, 16, .white)
}
let input = ctx.makeImage()!

let dev = MTLCreateSystemDefaultDevice()!
let filter = try! DarkFilter(device: dev)
let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
let tex = dev.makeTexture(descriptor: td)!
tex.replace(region: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0, withBytes: ctx.data!, bytesPerRow: ctx.bytesPerRow)
let od = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
od.usage = [.renderTarget]; od.storageMode = .managed
let out = dev.makeTexture(descriptor: od)!
let cb = dev.makeCommandQueue()!.makeCommandBuffer()!
var p = ShaderParams(); p.lodSmall = log2(16 * scale); p.lodLarge = log2(24 * scale); p.lodErode = log2(2 * scale); p.lodColor = log2(8 * scale); p.inkOffset = 5 * scale
filter.ingest(tex, commandBuffer: cb, params: p)
let rp = MTLRenderPassDescriptor(); rp.colorAttachments[0].texture = out; rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .store
let en = cb.makeRenderCommandEncoder(descriptor: rp)!
filter.draw(with: en, params: p); en.endEncoding()
let b2 = cb.makeBlitCommandEncoder()!; b2.synchronize(resource: out); b2.endEncoding()
cb.commit(); cb.waitUntilCompleted()
var bytes = [UInt8](repeating: 0, count: W*H*4)
out.getBytes(&bytes, bytesPerRow: W*4, from: MTLRegionMake2D(0, 0, W, H), mipmapLevel: 0)
let octx = CGContext(data: &bytes, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W*4, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
// side by side
let combo = CGContext(data: nil, width: W, height: H*2, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
combo.draw(input, in: CGRect(x: 0, y: H, width: W, height: H)); combo.draw(octx.makeImage()!, in: CGRect(x: 0, y: 0, width: W, height: H))
let rep = NSBitmapImageRep(cgImage: combo.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outputPath))
print("Preview: \(outputPath)")
