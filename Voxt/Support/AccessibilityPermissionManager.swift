import Foundation
import AppKit
import ApplicationServices

enum AccessibilityPermissionManager {
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func request(prompt: Bool) -> Bool {
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        } else {
            _ = AXIsProcessTrusted()
        }

        // Perform a benign AX query so macOS registers the app against the
        // accessibility service immediately instead of waiting for a later AX read.
        primeAccessibilityRegistration()
        return AXIsProcessTrusted()
    }

    private static func primeAccessibilityRegistration() {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        let focusedAppStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )

        guard
            focusedAppStatus == .success,
            let runningApp = NSWorkspace.shared.frontmostApplication
        else {
            return
        }

        let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)
        var focusedWindow: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )
    }
}
