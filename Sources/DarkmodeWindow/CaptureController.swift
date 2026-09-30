import AppKit
import ScreenCaptureKit

/// Captures the screen area underneath the overlay (own app excluded).
final class CaptureController: NSObject, SCStreamOutput, SCStreamDelegate {
    /// Delivers a frame plus the part of the requested region it covers (normalized, top-left
    /// origin). Less than the full region when the window extends beyond the display.
    var onFrame: ((CVPixelBuffer, CGRect) -> Void)?
    var onError: ((Error) -> Void)?

    private var stream: SCStream?
    private var displayID: CGDirectDisplayID?
    private let sampleQueue = DispatchQueue(label: "de.fey-it.DarkmodeWindow.capture")
    private var active = false
    private var busy = false
    private var pending: (rect: CGRect, screen: NSScreen)?
    private var coveredRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// `rect` in Cocoa screen coordinates (points). Call on the main thread.
    func setRegion(_ rect: CGRect, on screen: NSScreen) {
        active = true
        pending = (rect, screen)
        processPending()
    }

    func stop() {
        active = false
        pending = nil
        guard !busy else { return }  // finished in processPending
        stopStream()
    }

    private func stopStream() {
        let old = stream
        stream = nil
        displayID = nil
        Task { try? await old?.stopCapture() }
    }

    private func processPending() {
        guard !busy else { return }
        guard active else { stopStream(); return }
        guard let next = pending else { return }
        pending = nil
        busy = true
        Task { @MainActor in
            do {
                try await apply(next.rect, on: next.screen)
            } catch {
                stopStream()
                active = false
                pending = nil
                onError?(error)
            }
            busy = false
            processPending()
        }
    }

    @MainActor
    private func apply(_ rect: CGRect, on screen: NSScreen) async throws {
        guard let id = screen.displayID else { return }
        let displayBounds = CGDisplayBounds(id)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let globalRect = CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
        let visible = globalRect.intersection(displayBounds)
        guard !visible.isNull, visible.width >= 1, visible.height >= 1 else { return }
        let local = visible.offsetBy(dx: -displayBounds.minX, dy: -displayBounds.minY)
        let covered = CGRect(x: (visible.minX - globalRect.minX) / globalRect.width,
                             y: (visible.minY - globalRect.minY) / globalRect.height,
                             width: visible.width / globalRect.width,
                             height: visible.height / globalRect.height)

        let scale = screen.backingScaleFactor
        let config = SCStreamConfiguration()
        config.sourceRect = local
        config.width = Int((local.width * scale).rounded())
        config.height = Int((local.height * scale).rounded())
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.showsCursor = false
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 4

        if let stream, displayID == id {
            try await stream.updateConfiguration(config)
            coveredRect = covered
            return
        }

        if let old = stream {
            stream = nil
            try? await old.stopCapture()
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == id }) else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let own = content.applications.filter { $0.processID == ownPID }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try await newStream.startCapture()
        stream = newStream
        displayID = id
        coveredRect = covered
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.onFrame?(buffer, self.coveredRect)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.stream = nil
            self.displayID = nil
            self.active = false
            self.onError?(error)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
