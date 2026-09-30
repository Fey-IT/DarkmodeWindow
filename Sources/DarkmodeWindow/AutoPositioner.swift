import AppKit
import ScreenCaptureKit

/// Periodically looks for the largest bright area on screen (e.g. a shared slide in Meet/Teams)
/// using a tiny low-resolution screenshot without our own window.
final class AutoPositioner {
    /// Called on the main thread with the found area in Cocoa screen coordinates.
    var onFound: ((NSRect) -> Void)?
    /// Returns the screen to search and optionally a sub-area (Cocoa coordinates), e.g. a docked window.
    var searchArea: (() -> (screen: NSScreen, area: NSRect?)?)?

    private let interval: TimeInterval = 2
    private var timer: Timer?
    private var inFlight = false

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard !inFlight, let target = searchArea?() else { return }
        inFlight = true
        Task { @MainActor in
            let rect = try? await Self.findBrightArea(on: target.screen, within: target.area)
            inFlight = false
            if let rect, timer != nil { onFound?(rect) }
        }
    }

    /// Grid cell size in points; the result is accurate to about one cell.
    static let cell: CGFloat = 4
    private static let minSize = NSSize(width: 160, height: 100)

    @MainActor
    static func findBrightArea(on screen: NSScreen, within area: NSRect?) async throws -> NSRect? {
        guard let id = screen.displayID else { return nil }
        let displayBounds = CGDisplayBounds(id)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        func toGlobalCG(_ r: NSRect) -> CGRect {
            CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
        }

        var searchRect = displayBounds
        if let area {
            searchRect = toGlobalCG(area).intersection(displayBounds)
            guard !searchRect.isNull, searchRect.width >= minSize.width, searchRect.height >= minSize.height else { return nil }
        }
        let local = searchRect.offsetBy(dx: -displayBounds.minX, dy: -displayBounds.minY)

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == id }) else { return nil }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let filter = SCContentFilter(display: display,
                                     excludingApplications: content.applications.filter { $0.processID == ownPID },
                                     exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.sourceRect = local
        let w = max(1, Int(local.width / cell)), h = max(1, Int(local.height / cell))
        config.width = w
        config.height = h
        config.showsCursor = false
        config.colorSpaceName = CGColorSpace.sRGB
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

        guard let found = largestBrightComponent(in: image, width: w, height: h) else { return nil }
        // Pad by one cell so no bright sliver stays uncovered (dark surroundings stay dark anyway).
        let cg = CGRect(x: searchRect.minX + CGFloat(found.minX - 1) * cell,
                        y: searchRect.minY + CGFloat(found.minY - 1) * cell,
                        width: CGFloat(found.width + 2) * cell,
                        height: CGFloat(found.height + 2) * cell)
            .intersection(searchRect)
        return NSRect(x: cg.minX, y: primaryHeight - cg.maxY, width: cg.width, height: cg.height)
    }

    /// Bounding box (grid cells, top-left origin) of the largest 4-connected bright region.
    static func largestBrightComponent(in image: CGImage, width w: Int, height h: Int)
        -> (minX: Int, minY: Int, width: Int, height: Int)? {
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Row 0 of the buffer is the top of the image.
        var bright = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) {
            let r = Double(pixels[i * 4]), g = Double(pixels[i * 4 + 1]), b = Double(pixels[i * 4 + 2])
            bright[i] = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 > 0.72
        }

        var visited = [Bool](repeating: false, count: w * h)
        var best: (count: Int, minX: Int, minY: Int, maxX: Int, maxY: Int)?
        var stack: [Int] = []
        for start in 0..<(w * h) where bright[start] && !visited[start] {
            var count = 0, minX = w, minY = h, maxX = 0, maxY = 0
            visited[start] = true
            stack.append(start)
            while let i = stack.popLast() {
                count += 1
                let x = i % w, y = i / w
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
                for n in [x > 0 ? i - 1 : -1, x < w - 1 ? i + 1 : -1, y > 0 ? i - w : -1, y < h - 1 ? i + w : -1]
                where n >= 0 && bright[n] && !visited[n] {
                    visited[n] = true
                    stack.append(n)
                }
            }
            if count > (best?.count ?? 0) { best = (count, minX, minY, maxX, maxY) }
        }

        guard let best else { return nil }
        let bw = best.maxX - best.minX + 1, bh = best.maxY - best.minY + 1
        let fill = Double(best.count) / Double(bw * bh)
        guard CGFloat(bw) * cell >= minSize.width, CGFloat(bh) * cell >= minSize.height, fill >= 0.5 else { return nil }
        return (best.minX, best.minY, bw, bh)
    }
}
