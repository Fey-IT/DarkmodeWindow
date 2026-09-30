import MetalKit
import CoreVideo

/// Feeds captured frames into the DarkFilter and presents the result in an MTKView.
final class Renderer: NSObject, MTKViewDelegate {
    static let backgroundColor = MTLClearColor(red: 0.086, green: 0.086, blue: 0.086, alpha: 1)

    private let queue: MTLCommandQueue
    private let filter: DarkFilter
    private var textureCache: CVMetalTextureCache?
    private var pendingBuffer: CVPixelBuffer?
    /// Part of the view the frame belongs to (normalized, top-left origin).
    private var coveredRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    var params = ShaderParams()

    init?(view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        do {
            filter = try DarkFilter(device: device)
        } catch {
            NSLog("DarkmodeWindow: shader error \(error)")
            return nil
        }
        self.queue = queue
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        super.init()

        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.clearColor = Renderer.backgroundColor
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.framebufferOnly = true
        view.delegate = self
    }

    func submit(_ buffer: CVPixelBuffer, covering rect: CGRect) {
        pendingBuffer = buffer
        coveredRect = rect
    }

    func reset() {
        pendingBuffer = nil
        filter.reset()
    }

    func draw(in view: MTKView) {
        guard let cmd = queue.makeCommandBuffer() else { return }
        var heldTexture: CVMetalTexture?

        if let buffer = pendingBuffer, let cache = textureCache {
            pendingBuffer = nil
            var cvTexture: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, .bgra8Unorm,
                                                      CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer),
                                                      0, &cvTexture)
            if let cvTexture, let source = CVMetalTextureGetTexture(cvTexture) {
                heldTexture = cvTexture
                filter.ingest(source, commandBuffer: cmd, params: params)
            }
        }

        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let encoder = cmd.makeRenderCommandEncoder(descriptor: pass) else {
            cmd.commit()
            return
        }
        let size = view.drawableSize
        encoder.setViewport(MTLViewport(originX: coveredRect.minX * size.width,
                                        originY: coveredRect.minY * size.height,
                                        width: coveredRect.width * size.width,
                                        height: coveredRect.height * size.height,
                                        znear: 0, zfar: 1))
        filter.draw(with: encoder, params: params)
        encoder.endEncoding()
        cmd.present(drawable)
        cmd.addCompletedHandler { _ in _ = heldTexture }
        cmd.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
}
