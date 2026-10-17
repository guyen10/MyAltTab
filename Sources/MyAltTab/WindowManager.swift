import AppKit
import ApplicationServices

// Private but stable API (used by most window switchers) that maps an AX window to its CGWindowID.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

struct WindowInfo {
    let windowID: CGWindowID
    let element: AXUIElement
    let app: NSRunningApplication
    let title: String
    let isMinimized: Bool

    var appName: String { app.localizedName ?? "" }
    var icon: NSImage { app.icon ?? NSWorkspace.shared.icon(for: .application) }
}

enum WindowManager {
    /// Standard windows of regular apps on the current Space, front-to-back (most recently used first).
    /// Minimized windows and windows of hidden apps are appended at the end when `includeMinimized` is true.
    static func windows(includeMinimized: Bool) -> [WindowInfo] {
        var zOrder: [CGWindowID: Int] = [:]
        if let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            for (index, info) in list.enumerated() where (info[kCGWindowLayer as String] as? Int) == 0 {
                if let number = info[kCGWindowNumber as String] as? Int {
                    zOrder[CGWindowID(number)] = index
                }
            }
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var ranked: [(window: WindowInfo, rank: Int)] = []

        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != ownPID {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, 0.25) // don't hang on unresponsive apps
            guard let axWindows: [AXUIElement] = attribute(axApp, kAXWindowsAttribute) else { continue }

            for element in axWindows {
                AXUIElementSetMessagingTimeout(element, 0.25) // elements don't inherit the app's timeout
                guard (attribute(element, kAXSubroleAttribute) as String?) == kAXStandardWindowSubrole else { continue }
                let minimized = (attribute(element, kAXMinimizedAttribute) as Bool?) ?? false

                var windowID: CGWindowID = 0
                _ = _AXUIElementGetWindow(element, &windowID)

                let rank: Int
                if minimized || app.isHidden {
                    guard includeMinimized else { continue }
                    rank = Int.max
                } else if let z = zOrder[windowID] {
                    rank = z
                } else {
                    continue // on another Space
                }

                let title = (attribute(element, kAXTitleAttribute) as String?) ?? ""
                ranked.append((WindowInfo(windowID: windowID, element: element, app: app,
                                          title: title.isEmpty ? (app.localizedName ?? "") : title,
                                          isMinimized: minimized), rank))
            }
        }

        return ranked.enumerated()
            .sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }
            .map { $0.element.window }
    }

    static func focus(_ window: WindowInfo) {
        if window.app.isHidden { window.app.unhide() }
        if window.isMinimized {
            AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementSetAttributeValue(window.element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)

        // Making the app frontmost through AX works even when macOS' cooperative activation would refuse.
        let axApp = AXUIElementCreateApplication(window.app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.25)
        AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        window.app.activate(options: [])
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }
}
