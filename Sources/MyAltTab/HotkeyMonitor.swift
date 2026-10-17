import CoreGraphics
import Foundation

/// Watches the keyboard through a CGEventTap and turns Option+Tab presses into switcher events.
/// While a switch session is active, all key presses are swallowed so they don't reach the frontmost app.
///
/// The tap runs on its own thread and only posts events to the main queue, so slow work there
/// (e.g. querying unresponsive apps) never stalls keyboard input system-wide.
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
    private var runLoop: CFRunLoop?

    // Only touched on the tap thread.
    private var isActive = false
    /// Keys whose keyDown was swallowed; their keyUp is swallowed too so apps never see a lone release.
    private var swallowedKeys: Set<Int64> = []

    init(handler: @escaping (Event) -> Void) {
        self.handler = handler
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
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
        self.tap = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "MyAltTab.HotkeyMonitor"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return true
    }

    /// Ends the current session without emitting an event (e.g. after a mouse click picked a window,
    /// or when there was nothing to switch to).
    func endSession() {
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [self] in isActive = false }
        CFRunLoopWakeUp(runLoop)
    }

    private func emit(_ event: Event) {
        DispatchQueue.main.async { [handler] in handler(event) }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Events (possibly the Option release) were missed while disabled, so don't trust the session state.
            if isActive {
                isActive = false
                emit(.cancel)
            }
            swallowedKeys.removeAll()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return passThrough
        }

        let flags = event.flags
        let option = flags.contains(.maskAlternate)

        if type == .flagsChanged {
            if isActive && !option {
                isActive = false
                emit(.commit)
            }
            return passThrough
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .keyUp {
            return swallowedKeys.remove(keyCode) != nil ? nil : passThrough
        }
        guard type == .keyDown else { return passThrough }

        // The Option release was missed (e.g. Secure Input was on): end the session and let typing through.
        if isActive && !option {
            isActive = false
            emit(.cancel)
            return passThrough
        }

        let shift = flags.contains(.maskShift)

        if keyCode == KeyCode.tab && option && !flags.contains(.maskCommand) && !flags.contains(.maskControl) {
            if isActive {
                emit(shift ? .previous : .next)
            } else {
                isActive = true
                emit(.start(reverse: shift))
            }
            swallowedKeys.insert(keyCode)
            return nil
        }

        guard isActive else { return passThrough }
        switch keyCode {
        case KeyCode.escape:
            isActive = false
            emit(.cancel)
        case KeyCode.returnKey:
            isActive = false
            emit(.commit)
        case KeyCode.left:
            emit(.previous)
        case KeyCode.right:
            emit(.next)
        case KeyCode.up:
            emit(.up)
        case KeyCode.down:
            emit(.down)
        default:
            break
        }
        swallowedKeys.insert(keyCode)
        return nil
    }
}
