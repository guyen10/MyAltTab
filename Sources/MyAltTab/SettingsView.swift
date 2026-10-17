import ApplicationServices
import Combine
import ServiceManagement
import SwiftUI

enum Settings {
    static let includeMinimized = "includeMinimized"
    static let showPreviews = "showPreviews"
    static let previewIconSize = "previewIconSize"
}

// Plain ObservableObject instead of @State: the Command Line Tools SDK lacks the SwiftUI macro plugin @State needs.
final class SettingsModel: ObservableObject {
    @Published var launchAtLogin = LoginItem.isRegistered
    @Published var loginStatus = LoginItem.status
    @Published var loginError: String?
    @Published var isTrusted = AXIsProcessTrusted()
    @Published var canCaptureScreen = CGPreflightScreenCaptureAccess()

    func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != LoginItem.isRegistered else { return }
        do {
            try LoginItem.setEnabled(enabled)
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        refresh()
    }

    func refresh() {
        isTrusted = AXIsProcessTrusted()
        canCaptureScreen = CGPreflightScreenCaptureAccess()
        loginStatus = LoginItem.status
        let enabled = LoginItem.isRegistered
        if launchAtLogin != enabled { launchAtLogin = enabled }
    }
}

struct SettingsView: View {
    @AppStorage(Settings.includeMinimized) private var includeMinimized = true
    @AppStorage(Settings.showPreviews) private var showPreviews = true
    @AppStorage(Settings.previewIconSize) private var previewIconSize = SwitcherLayout.badgeRange.upperBound
    @ObservedObject var model: SettingsModel

    private let refresh = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MyAltTab").font(.title2.weight(.semibold))
                        Text("Version \(Self.version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("General") {
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin },
                                                        set: { model.setLaunchAtLogin($0) }))
                if model.loginStatus == .requiresApproval {
                    HStack {
                        Text("Approve MyAltTab in Login Items to finish enabling.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let loginError = model.loginError {
                    Text(loginError).foregroundStyle(.red).font(.caption)
                }
                Toggle("Include minimized and hidden windows", isOn: $includeMinimized)
                Picker("Show windows as", selection: $showPreviews) {
                    Text("Previews").tag(true)
                    Text("Icons only").tag(false)
                }
                .pickerStyle(.segmented)
                if showPreviews {
                    LabeledContent("App icon size") {
                        HStack {
                            Slider(value: $previewIconSize, in: SwitcherLayout.badgeRange, step: 4)
                            Text("\(Int(previewIconSize)) pt")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }
            }

            Section("Permissions") {
                HStack {
                    Image(systemName: model.isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.isTrusted ? .green : .orange)
                    Text(model.isTrusted ? "Accessibility access granted" : "Accessibility access required")
                    Spacer()
                    if !model.isTrusted {
                        Button("Open Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
                if showPreviews {
                    HStack {
                        Image(systemName: model.canCaptureScreen ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(model.canCaptureScreen ? .green : .orange)
                        Text(model.canCaptureScreen ? "Screen Recording access granted" : "Screen Recording needed for previews")
                        Spacer()
                        if !model.canCaptureScreen {
                            Button("Open Settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                            }
                            Button("Relaunch") { relaunch() }
                        }
                    }
                }
            }

            Section {
                Text("Hold ⌥ Option and press Tab to cycle windows. Shift+Tab or ←/→ to move, Esc to cancel, release ⌥ to switch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.refresh() }
        .onReceive(refresh) { _ in model.refresh() }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    /// Screen Recording access only takes effect after the app restarts.
    private func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}
