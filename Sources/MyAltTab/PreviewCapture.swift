import AppKit
import ScreenCaptureKit

/// Captures window thumbnails with ScreenCaptureKit (needs Screen Recording access).
/// Thumbnails are cached by window ID so the switcher can show the last one instantly.
final class PreviewCapture {
    static let shared = PreviewCapture()

    /// Largest thumbnail size in pixels (2x the on-screen preview area).
    private static let maxPixels = CGSize(width: 440, height: 280)

    /// Only read and written on the main thread.
    private(set) var cache: [CGWindowID: NSImage] = [:]

    func capture(_ windowIDs: [CGWindowID], onImage: @escaping (CGWindowID, NSImage) -> Void) {
        guard !windowIDs.isEmpty, CGPreflightScreenCaptureAccess() else { return }
        Task {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) else { return }
            let windows = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })

            for id in windowIDs {
                guard let window = windows[id], window.frame.width > 0, window.frame.height > 0 else { continue }
                // One task per window so captures run concurrently.
                Task {
                    guard let image = try? await Self.snapshot(window) else { return }
                    await MainActor.run {
                        self.cache[id] = image
                        onImage(id, image)
                    }
                }
            }
        }
    }

    /// Forgets thumbnails of windows that no longer exist, so closed windows' contents don't linger in memory.
    func prune(keeping windowIDs: Set<CGWindowID>) {
        cache = cache.filter { windowIDs.contains($0.key) }
    }

    private static func snapshot(_ window: SCWindow) async throws -> NSImage {
        let scale = min(maxPixels.width / window.frame.width, maxPixels.height / window.frame.height, 2)
        let config = SCStreamConfiguration()
        config.width = max(1, Int(window.frame.width * scale))
        config.height = max(1, Int(window.frame.height * scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window),
                                                               configuration: config)
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
