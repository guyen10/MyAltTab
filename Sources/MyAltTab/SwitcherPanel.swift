import AppKit
import SwiftUI

final class SwitcherModel: ObservableObject {
    @Published var windows: [WindowInfo] = []
    @Published var selected = 0
    @Published var layout = SwitcherLayout(showPreviews: true)
    @Published var previews: [CGWindowID: NSImage] = [:]
}

/// Owns the floating switcher panel and the current selection.
final class SwitcherController {
    let model = SwitcherModel()
    /// Called when the user clicks a tile with the mouse.
    var onClick: ((Int) -> Void)?

    private let panel: NSPanel
    private let hostingView: NSHostingView<SwitcherView>
    private var pendingShow: DispatchWorkItem?
    /// The screen the layout was sized for; the panel is shown on the same one.
    private var screen: NSScreen?

    init() {
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        hostingView = NSHostingView(rootView: SwitcherView(model: model, onClick: { _ in }))
        panel.contentView = hostingView
        hostingView.rootView = SwitcherView(model: model, onClick: { [weak self] index in self?.onClick?(index) })
    }

    /// Returns false when there are no windows to switch to.
    @discardableResult
    func start(reverse: Bool) -> Bool {
        let includeMinimized = UserDefaults.standard.bool(forKey: Settings.includeMinimized)
        let windows = WindowManager.windows(includeMinimized: includeMinimized)
        model.windows = windows
        PreviewCapture.shared.prune(keeping: Set(windows.map(\.windowID)))
        guard !windows.isEmpty else { return false }

        let screen = activeScreen()
        self.screen = screen
        let showPreviews = UserDefaults.standard.bool(forKey: Settings.showPreviews)
        let badgeRange = SwitcherLayout.badgeRange
        let badgeSize = min(max(UserDefaults.standard.double(forKey: Settings.previewIconSize), badgeRange.lowerBound), badgeRange.upperBound)
        model.layout = SwitcherLayout.fitting(count: windows.count, in: screen.visibleFrame.size,
                                              showPreviews: showPreviews, badgeSize: CGFloat(badgeSize))

        if showPreviews {
            // Show cached thumbnails right away, then fill in fresh ones as they arrive.
            model.previews = PreviewCapture.shared.cache
            PreviewCapture.shared.capture(windows.filter { !$0.isMinimized && !$0.app.isHidden }.map(\.windowID)) { [weak self] id, image in
                self?.model.previews[id] = image
            }
        } else {
            model.previews = [:]
        }
        if windows.count == 1 {
            model.selected = 0
        } else {
            model.selected = reverse ? windows.count - 1 : 1
        }

        // Delay showing so a quick Option+Tab tap switches without flashing the panel.
        let work = DispatchWorkItem { [weak self] in self?.showPanel() }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        return true
    }

    func move(by delta: Int) {
        let count = model.windows.count
        guard count > 0 else { return }
        model.selected = ((model.selected + delta) % count + count) % count
    }

    /// Moves up/down a row in the grid; stays put when there's no tile in that direction.
    func moveRow(by delta: Int) {
        let count = model.windows.count
        let columns = model.layout.columns
        let target = model.selected + delta * columns
        if target >= 0 && target < count {
            model.selected = target
        } else if delta > 0 && model.selected / columns < (count - 1) / columns {
            model.selected = count - 1 // partial last row
        }
    }

    func select(_ index: Int) {
        guard model.windows.indices.contains(index) else { return }
        model.selected = index
    }

    func commit() {
        let windows = model.windows
        let selected = model.selected
        hide()
        if windows.indices.contains(selected) {
            WindowManager.focus(windows[selected])
        }
    }

    func cancel() {
        hide()
    }

    private func hide() {
        pendingShow?.cancel()
        pendingShow = nil
        panel.orderOut(nil)
        model.windows = []
    }

    /// The screen under the mouse pointer.
    private func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func showPanel() {
        let frame = (screen ?? activeScreen()).visibleFrame
        // Size comes from the layout math rather than SwiftUI's fittingSize, which can lag behind model changes.
        let size = model.layout.panelSize
        panel.setFrame(NSRect(x: frame.midX - size.width / 2,
                              y: frame.midY - size.height / 2,
                              width: size.width,
                              height: size.height),
                       display: true)
        panel.orderFrontRegardless()
    }
}
