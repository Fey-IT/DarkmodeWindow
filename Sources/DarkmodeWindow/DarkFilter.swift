import Metal

/// GPU part of the dark-mode conversion, independent of any view (also used by the shader test).
final class DarkFilter {
    let device: MTLDevice
    private let outputPipeline: MTLRenderPipelineState
    private let brightPipeline: MTLRenderPipelineState
    private let paperPipeline: MTLRenderPipelineState
    /// Mipmapped copy of the latest frame (the capture buffer is recycled by ScreenCaptureKit).
    private(set) var frameTexture: MTLTexture?
    /// Mipmapped mask of bright pixels (input for the paper erosion).
    private var brightTexture: MTLTexture?
    /// Mipmapped "paper" mask; coarse levels drive the adaptive mode.
    private var paperTexture: MTLTexture?

    init(device: MTLDevice, outputFormat: MTLPixelFormat = .bgra8Unorm) throws {
        self.device = device
        let library = try device.makeLibrary(source: shaderSource, options: nil)

        func pipeline(_ fragment: String, _ format: MTLPixelFormat) throws -> MTLRenderPipelineState {
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "vmain")
            desc.fragmentFunction = library.makeFunction(name: fragment)
            desc.colorAttachments[0].pixelFormat = format
            return try device.makeRenderPipelineState(descriptor: desc)
        }
        outputPipeline = try pipeline("fmain", outputFormat)
        brightPipeline = try pipeline("fbright", .r8Unorm)
        paperPipeline = try pipeline("fpaper", .r8Unorm)
    }

    var hasFrame: Bool { frameTexture != nil }

    func reset() {
        frameTexture = nil
        brightTexture = nil
        paperTexture = nil
    }

    /// Copies a new frame and rebuilds the masks.
    func ingest(_ source: MTLTexture, commandBuffer cmd: MTLCommandBuffer, params: ShaderParams) {
        let w = source.width, h = source.height
        if frameTexture?.width != w || frameTexture?.height != h {
            let frameDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: true)
            frameDesc.usage = [.shaderRead]
            frameDesc.storageMode = .private
            frameTexture = device.makeTexture(descriptor: frameDesc)

            let maskDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: w, height: h, mipmapped: true)
            maskDesc.usage = [.shaderRead, .renderTarget]
            maskDesc.storageMode = .private
            brightTexture = device.makeTexture(descriptor: maskDesc)
            paperTexture = device.makeTexture(descriptor: maskDesc)
        }
        guard let frame = frameTexture, let bright = brightTexture, let paper = paperTexture else { return }

        if let blit = cmd.makeBlitCommandEncoder() {
            blit.copy(from: source, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
                      sourceSize: MTLSize(width: w, height: h, depth: 1),
                      to: frame, destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin())
            blit.generateMipmaps(for: frame)
            blit.endEncoding()
        }
        maskPass(cmd, pipeline: brightPipeline, input: frame, output: bright, params: params)
        maskPass(cmd, pipeline: paperPipeline, input: bright, output: paper, params: params)
    }

    private func maskPass(_ cmd: MTLCommandBuffer, pipeline: MTLRenderPipelineState,
                          input: MTLTexture, output: MTLTexture, params: ShaderParams) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = output
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        if let encoder = cmd.makeRenderCommandEncoder(descriptor: pass) {
            var p = params
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(input, index: 0)
            encoder.setFragmentBytes(&p, length: MemoryLayout<ShaderParams>.stride, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
        }
        if let blit = cmd.makeBlitCommandEncoder() {
            blit.generateMipmaps(for: output)
            blit.endEncoding()
        }
    }

    /// Draws the converted frame into the current render pass.
    func draw(with encoder: MTLRenderCommandEncoder, params: ShaderParams) {
        guard let frame = frameTexture, let paper = paperTexture, let bright = brightTexture else { return }
        var p = params
        encoder.setRenderPipelineState(outputPipeline)
        encoder.setFragmentTexture(frame, index: 0)
        encoder.setFragmentTexture(paper, index: 1)
        encoder.setFragmentTexture(bright, index: 2)
        encoder.setFragmentBytes(&p, length: MemoryLayout<ShaderParams>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}
