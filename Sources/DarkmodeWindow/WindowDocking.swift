import AppKit

struct TargetWindow {
    let id: CGWindowID
    let owner: String
    let title: String

    var menuTitle: String {
        title.isEmpty ? owner : "\(owner) – \(title)"
    }
}

/// Finds meeting windows of other apps and reads their current position.
enum WindowDocking {
    private static let meetingApps = ["Teams", "zoom.us", "Webex", "Slack", "Webex Meetings"]
    private static let browsers = ["Google Chrome", "Safari", "Microsoft Edge", "Firefox", "Arc",
                                   "Brave Browser", "Vivaldi", "Opera", "Chromium"]

    static func allWindows() -> [TargetWindow] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let owner = info[kCGWindowOwnerName as String] as? String,
                  let bounds = bounds(from: info), bounds.width > 150, bounds.height > 100 else { return nil }
            return TargetWindow(id: id, owner: owner, title: info[kCGWindowName as String] as? String ?? "")
        }
    }

    static func meetingWindows(in windows: [TargetWindow]) -> [TargetWindow] {
        windows.filter { w in
            meetingApps.contains { w.owner.localizedCaseInsensitiveContains($0) }
                || (browsers.contains(w.owner) && w.title.localizedCaseInsensitiveContains("Meet"))
        }
    }

    /// Bounds in Cocoa screen coordinates, or nil if the window no longer exists.
    static func state(of id: CGWindowID) -> (frame: NSRect, onScreen: Bool)? {
        guard let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
              let info = list.first, let cg = bounds(from: info) else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let frame = NSRect(x: cg.minX, y: primaryHeight - cg.maxY, width: cg.width, height: cg.height)
        return (frame, info[kCGWindowIsOnscreen as String] as? Bool ?? false)
    }

    private static func bounds(from info: [String: Any]) -> CGRect? {
        guard let dict = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dict as CFDictionary)
    }
}
