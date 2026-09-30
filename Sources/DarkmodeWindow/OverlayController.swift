import AppKit
import MetalKit

/// Owns the overlay window and ties capture, rendering and docking together.
final class OverlayController: NSObject, NSWindowDelegate {
    private let settings = Settings.shared
    private let window: OverlayWindow
    private let frameView: FrameView
    private let metalView = MTKView()
    private let renderer: Renderer?
    private let capture = CaptureController()
    private let autoPositioner = AutoPositioner()

    private var mouseTimer: Timer?
    private var dockTimer: Timer?
    private var hiddenBecauseTargetInvisible = false

    private(set) var isShown = false
    private(set) var dockedWindow: TargetWindow?
    /// Set when capturing failed (usually missing screen recording permission); falls back to dimming.
    private(set) var captureFailed = false

    override init() {
        let frame = Settings.shared.windowFrame ?? Self.defaultFrame()
        window = OverlayWindow(contentRect: frame)
        frameView = FrameView(frame: NSRect(origin: .zero, size: frame.size))
        renderer = Renderer(view: metalView)
        super.init()

        window.contentView = frameView
        window.delegate = self
        metalView.autoresizingMask = [.width, .height]
        metalView.frame = frameView.contentContainer.bounds
        frameView.contentContainer.addSubview(metalView)
        frameView.onUserInteraction = { [weak self] in self?.userDidManipulate() }
        frameView.onClose = { [weak self] in self?.hide() }

        capture.onFrame = { [weak self] buffer, covered in
            guard let self else { return }
            self.renderer?.submit(buffer, covering: covered)
            self.metalView.draw()
        }
        capture.onError = { [weak self] error in
            NSLog("DarkmodeWindow: capture failed: \(error)")
            self?.captureFailed = true
            self?.applyMode()
        }
        if renderer == nil { captureFailed = true }

        autoPositioner.searchArea = { [weak self] in
            guard let self, let screen = self.window.screen ?? NSScreen.main else { return nil }
            if let docked = self.dockedWindow {
                guard let state = WindowDocking.state(of: docked.id), state.onScreen else { return nil }
                let dockScreen = NSScreen.screens.max {
                    $0.frame.intersection(state.frame).area < $1.frame.intersection(state.frame).area
                } ?? screen
                return (dockScreen, state.frame)
            }
            return (screen, nil)
        }
        autoPositioner.onFound = { [weak self] rect in self?.moveContent(to: rect) }

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    private static func defaultFrame() -> NSRect {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: 900, height: 560)
        return NSRect(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    // MARK: Visibility

    func show() {
        isShown = true
        hiddenBecauseTargetInvisible = false
        applyMode()  // dark content is in place before the window appears
        window.orderFrontRegardless()
        startMouseTimer()
        applyMode()
        if dockedWindow != nil { followDockedWindow() }
        if settings.autoPosition { autoPositioner.start() }
    }

    func hide() {
        isShown = false
        window.orderOut(nil)
        mouseTimer?.invalidate()
        mouseTimer = nil
        autoPositioner.stop()
        stopCapture()
    }

    func toggle() {
        isShown ? hide() : show()
    }

    // MARK: Mode

    /// Re-evaluates mode/brightness and (re)starts or stops capturing accordingly.
    func applyMode() {
        let smart = settings.mode == .smartDark && !captureFailed
        let brightness = settings.brightness
        metalView.isHidden = !smart
        frameView.contentContainer.layer?.backgroundColor = smart
            ? NSColor(white: 0.086, alpha: 1).cgColor
            : NSColor.black.withAlphaComponent(1 - 0.6 * brightness).cgColor

        var params = ShaderParams()
        params.brightness = Float(brightness)
        params.adaptive = settings.adaptive ? 1 : 0
        let scale = Float(window.backingScaleFactor)
        params.lodSmall = log2(16 * scale)
        params.lodLarge = log2(24 * scale)
        params.lodErode = log2(2 * scale)
        params.lodColor = log2(8 * scale)
        params.inkOffset = 5 * scale
        renderer?.params = params

        if smart && window.isVisible {
            updateCaptureRegion()
            metalView.draw()
        } else {
            stopCapture()
        }
        updateTitle()
    }

    /// Clears a previous capture failure and tries again (e.g. after granting permission).
    func retryCapture() {
        captureFailed = renderer == nil
        applyMode()
    }

    private func stopCapture() {
        capture.stop()
        renderer?.reset()
    }

    private func updateCaptureRegion() {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let rect = window.convertToScreen(frameView.convert(frameView.contentRect, to: nil))
        capture.setRegion(rect, on: screen)
    }

    private func updateTitle() {
        var parts = ["DarkmodeWindow"]
        if captureFailed {
            parts.append(L10n.t("Abdunkeln (keine Aufnahme-Berechtigung)", "Dim (no screen recording permission)"))
        } else {
            parts.append(settings.mode == .smartDark ? "Smart Dark" : L10n.t("Abdunkeln", "Dim"))
        }
        if let dockedWindow { parts.append(L10n.t("angedockt: ", "attached: ") + dockedWindow.owner) }
        if settings.autoPosition { parts.append("Auto-Position") }
        frameView.title = parts.joined(separator: " · ")
    }

    // MARK: Click-through

    private func startMouseTimer() {
        guard mouseTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.updateMousePassThrough()
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer
    }

    /// Only the frame accepts clicks; everything inside goes to the window underneath.
    private func updateMousePassThrough() {
        if NSEvent.pressedMouseButtons != 0 && !window.ignoresMouseEvents { return }  // keep an ongoing drag
        let p = NSEvent.mouseLocation
        let content = window.convertToScreen(frameView.convert(frameView.contentRect, to: nil))
        let overFrame = window.frame.contains(p) && !content.contains(p)
        if window.ignoresMouseEvents == overFrame {
            window.ignoresMouseEvents = !overFrame
        }
    }

    // MARK: Auto position

    var autoPositionEnabled: Bool { settings.autoPosition }

    func setAutoPosition(_ enabled: Bool) {
        settings.autoPosition = enabled
        if enabled && isShown {
            autoPositioner.start()
        } else {
            autoPositioner.stop()
        }
        updateTitle()
    }

    /// Places the window so its content area covers `rect`; ignores tiny changes to avoid jitter.
    private func moveContent(to rect: NSRect) {
        let current = window.convertToScreen(frameView.convert(frameView.contentRect, to: nil))
        let tolerance: CGFloat = 6
        if abs(current.minX - rect.minX) < tolerance, abs(current.maxX - rect.maxX) < tolerance,
           abs(current.minY - rect.minY) < tolerance, abs(current.maxY - rect.maxY) < tolerance {
            return
        }
        let b = FrameView.border
        window.setFrame(NSRect(x: rect.minX - b, y: rect.minY - b,
                               width: rect.width + 2 * b,
                               height: rect.height + b + FrameView.titleHeight), display: true)
    }

    /// Manual move/resize ends docking. Auto-position stays on (it only goes off via the menu),
    /// so the window jumps back onto the bright area with the next search.
    private func userDidManipulate() {
        undock()
    }

    // MARK: Docking

    func dock(to target: TargetWindow) {
        dockedWindow = target
        dockTimer?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.followDockedWindow() }
        RunLoop.main.add(timer, forMode: .common)
        dockTimer = timer
        if !isShown { show() }
        followDockedWindow()
        updateTitle()
    }

    func undock() {
        guard dockedWindow != nil else { return }
        dockedWindow = nil
        dockTimer?.invalidate()
        dockTimer = nil
        if hiddenBecauseTargetInvisible && isShown {
            hiddenBecauseTargetInvisible = false
            window.orderFrontRegardless()
            applyMode()
        }
        updateTitle()
    }

    private func followDockedWindow() {
        guard let target = dockedWindow, isShown else { return }
        guard let state = WindowDocking.state(of: target.id) else {
            undock()  // target window was closed
            return
        }
        if !state.onScreen {
            if !hiddenBecauseTargetInvisible {
                hiddenBecauseTargetInvisible = true
                window.orderOut(nil)
                stopCapture()
            }
            return
        }
        if !settings.autoPosition {
            let b = FrameView.border
            let frame = NSRect(x: state.frame.minX - b, y: state.frame.minY - b,
                               width: state.frame.width + 2 * b,
                               height: state.frame.height + b + FrameView.titleHeight)
            if frame != window.frame {
                window.setFrame(frame, display: true)
            }
        }
        if hiddenBecauseTargetInvisible {
            hiddenBecauseTargetInvisible = false
            applyMode()
            window.orderFrontRegardless()
        }
    }

    // MARK: NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        geometryChanged()
    }

    func windowDidResize(_ notification: Notification) {
        geometryChanged()
    }

    func windowDidChangeBackingProperties(_ notification: Notification) {
        applyMode()
    }

    private func geometryChanged() {
        if dockedWindow == nil { settings.windowFrame = window.frame }
        if settings.mode == .smartDark && !captureFailed && window.isVisible {
            updateCaptureRegion()
        }
    }

    @objc private func screensChanged() {
        guard window.isVisible else { return }
        applyMode()
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
