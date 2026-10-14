import CoreGraphics
import Foundation

/// Watches the keyboard through a CGEventTap and turns Option+Tab presses into switcher events.
/// While a switch session is active, all key presses are swallowed so they don't reach the frontmost app.
final class HotkeyMonitor {
    enum Event {
        case start(reverse: Bool)
        case next
        case previous
        case up
        case down
        case cancel
        case commit
    }

    private enum KeyCode {
        static let tab: Int64 = 48
        static let escape: Int64 = 53
        static let returnKey: Int64 = 36
        static let left: Int64 = 123
        static let right: Int64 = 124
        static let down: Int64 = 125
        static let up: Int64 = 126
    }

    private let handler: (Event) -> Void
    private var tap: CFMachPort?
    private(set) var isActive = false

    init(handler: @escaping (Event) -> Void) {
        self.handler = handler
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    /// Ends the current session without emitting an event (e.g. after a mouse click picked a window).
    func endSession() {
        isActive = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return passThrough
        }

        let flags = event.flags
        let option = flags.contains(.maskAlternate)

        if type == .flagsChanged {
            if isActive && !option {
                isActive = false
                handler(.commit)
            }
            return passThrough
        }

        guard type == .keyDown else { return passThrough }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let shift = flags.contains(.maskShift)

        if keyCode == KeyCode.tab && option && !flags.contains(.maskCommand) && !flags.contains(.maskControl) {
            if isActive {
                handler(shift ? .previous : .next)
            } else {
                isActive = true
                handler(.start(reverse: shift))
            }
            return nil
        }

        guard isActive else { return passThrough }
        switch keyCode {
        case KeyCode.escape:
            isActive = false
            handler(.cancel)
        case KeyCode.returnKey:
            isActive = false
            handler(.commit)
        case KeyCode.left:
            handler(.previous)
        case KeyCode.right:
            handler(.next)
        case KeyCode.up:
            handler(.up)
        case KeyCode.down:
            handler(.down)
        default:
            break
        }
        return nil
    }
}
