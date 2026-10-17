import ServiceManagement

/// Thin wrapper over SMAppService so the "Launch at Login" setting always reflects the system state.
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    /// Registered, even if the user still has to approve it in System Settings → Login Items.
    static var isRegistered: Bool { status == .enabled || status == .requiresApproval }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
