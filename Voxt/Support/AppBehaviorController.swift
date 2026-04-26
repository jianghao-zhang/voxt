import AppKit
import ServiceManagement

enum AppBehaviorController {
    static func resolvedActivationPolicy(
        showInDock: Bool,
        mainWindowVisible: Bool
    ) -> NSApplication.ActivationPolicy {
        if showInDock {
            return .regular
        }
        return mainWindowVisible ? .regular : .accessory
    }

    @MainActor
    static func applyDockVisibility(
        showInDock: Bool,
        mainWindowVisible: Bool
    ) {
        let targetPolicy = resolvedActivationPolicy(
            showInDock: showInDock,
            mainWindowVisible: mainWindowVisible
        )
        guard NSApp.activationPolicy() != targetPolicy else { return }

        NSApp.setActivationPolicy(targetPolicy)
        VoxtLog.info(
            "Dock visibility changed: showInDock=\(showInDock), mainWindowVisible=\(mainWindowVisible), policy=\(targetPolicy.rawValue)"
        )
    }

    @MainActor
    static func setLaunchAtLogin(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            VoxtLog.warning("Launch at login is unavailable on macOS versions below 13.0.")
            return
        }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        VoxtLog.info("Launch at login updated: enabled=\(enabled)")
    }

    static func launchAtLoginIsEnabled() -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }
}
