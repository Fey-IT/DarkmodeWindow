import AppKit

/// Borderless floating panel that never takes focus away from Teams/Meet.
final class OverlayWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        sharingType = .none
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovable = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Dark frame with title bar (move) and edges (resize); the inner content area is click-through.
final class FrameView: NSView {
    static let border: CGFloat = 5
    static let titleHeight: CGFloat = 22
    static let minSize = NSSize(width: 200, height: 140)

    struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1)
        static let right = Edges(rawValue: 2)
        static let bottom = Edges(rawValue: 4)
        static let top = Edges(rawValue: 8)
    }

    let contentContainer = NSView()
    var onUserInteraction: (() -> Void)?
    var onClose: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "DarkmodeWindow")
    private let closeButton = NSButton()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor(white: 0.086, alpha: 1).cgColor
        addSubview(contentContainer)

        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = NSColor(white: 0.6, alpha: 1)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Ausblenden")
        closeButton.isBordered = false
        closeButton.contentTintColor = NSColor(white: 0.6, alpha: 1)
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.toolTip = "Ausblenden (⌃⌥⌘D)"
        addSubview(closeButton)

        addTrackingArea(NSTrackingArea(rect: .zero,
                                       options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    var title: String {
        get { titleLabel.stringValue }
        set { titleLabel.stringValue = newValue }
    }

    var contentRect: NSRect {
        NSRect(x: Self.border, y: Self.border,
               width: bounds.width - 2 * Self.border,
               height: bounds.height - Self.border - Self.titleHeight)
    }

    override func layout() {
        super.layout()
        contentContainer.frame = contentRect
        let barY = bounds.height - Self.titleHeight
        closeButton.frame = NSRect(x: bounds.width - 26, y: barY + 3, width: 18, height: 16)
        titleLabel.frame = NSRect(x: 10, y: barY + 4, width: bounds.width - 44, height: 14)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    @objc private func closeClicked() { onClose?() }

    private func edges(at p: NSPoint) -> Edges {
        let grip: CGFloat = 6, corner: CGFloat = 14
        var e: Edges = []
        let nearLeft = p.x < grip, nearRight = p.x > bounds.width - grip
        let nearBottom = p.y < grip, nearTop = p.y > bounds.height - 4
        if nearLeft { e.insert(.left) }
        if nearRight { e.insert(.right) }
        if nearBottom { e.insert(.bottom) }
        if nearTop { e.insert(.top) }
        // Generous corner zones
        if nearLeft || nearRight {
            if p.y < corner { e.insert(.bottom) } else if p.y > bounds.height - corner { e.insert(.top) }
        }
        if nearBottom || nearTop {
            if p.x < corner { e.insert(.left) } else if p.x > bounds.width - corner { e.insert(.right) }
        }
        return e
    }

    private func cursor(for e: Edges) -> NSCursor {
        switch e {
        case [.left], [.right]: return .resizeLeftRight
        case [.top], [.bottom]: return .resizeUpDown
        case [.left, .top], [.right, .bottom]:
            return NSCursor.frameResize(position: .topLeft, directions: .all)
        case [.right, .top], [.left, .bottom]:
            return NSCursor.frameResize(position: .topRight, directions: .all)
        default: return .arrow
        }
    }

    override func mouseMoved(with event: NSEvent) {
        cursor(for: edges(at: convert(event.locationInWindow, from: nil))).set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        // The panel never activates by itself (so it doesn't steal focus from Teams); a click on the
        // frame does, so the menu bar shows DarkmodeWindow and ⌘Q quits this app.
        NSApp.activate()
        let p = convert(event.locationInWindow, from: nil)
        let e = edges(at: p)
        let move = e.isEmpty
        if move && p.y <= bounds.height - Self.titleHeight { return }

        // Track the drag ourselves; only an actual move/resize counts as the user taking over
        // (ends docking and auto-position) – a plain click does not.
        let startFrame = window.frame
        let startMouse = NSEvent.mouseLocation
        var tookOver = false
        while let ev = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), ev.type != .leftMouseUp {
            let m = NSEvent.mouseLocation
            let dx = m.x - startMouse.x, dy = m.y - startMouse.y
            if !tookOver {
                guard abs(dx) > 2 || abs(dy) > 2 else { continue }
                tookOver = true
                onUserInteraction?()
            }
            var f = startFrame
            if move {
                f.origin.x += dx
                f.origin.y += dy
            }
            if e.contains(.left) {
                f.size.width = max(Self.minSize.width, startFrame.width - dx)
                f.origin.x = startFrame.maxX - f.width
            }
            if e.contains(.right) { f.size.width = max(Self.minSize.width, startFrame.width + dx) }
            if e.contains(.bottom) {
                f.size.height = max(Self.minSize.height, startFrame.height - dy)
                f.origin.y = startFrame.maxY - f.height
            }
            if e.contains(.top) { f.size.height = max(Self.minSize.height, startFrame.height + dy) }
            window.setFrame(f, display: true)
        }
    }
}
