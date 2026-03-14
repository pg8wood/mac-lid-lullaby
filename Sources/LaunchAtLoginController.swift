import AppKit
import Foundation
import ServiceManagement

final class LaunchAtLoginController {
    private let service = SMAppService.mainApp
    private let defaults: UserDefaults
    private let preferenceKey = "launchAtLoginPreferred"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var canManage: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    var preferenceEnabled: Bool {
        if defaults.object(forKey: preferenceKey) == nil {
            return true
        }

        return defaults.bool(forKey: preferenceKey)
    }

    var menuState: NSControl.StateValue {
        guard canManage else { return .off }

        switch service.status {
        case .enabled:
            return .on
        case .requiresApproval:
            return .mixed
        case .notRegistered, .notFound:
            return .off
        @unknown default:
            return .off
        }
    }

    func configureOnLaunch() {
        apply(preferenceEnabled)
    }

    func toggle() {
        apply(menuState == .off)
    }

    private func apply(_ enabled: Bool) {
        defaults.set(enabled, forKey: preferenceKey)
        guard canManage else { return }

        switch (enabled, service.status) {
        case (true, .enabled), (true, .requiresApproval):
            return
        case (false, .notRegistered), (false, .notFound):
            return
        case (true, _):
            try? service.register()
        case (false, _):
            try? service.unregister()
        }
    }
}
