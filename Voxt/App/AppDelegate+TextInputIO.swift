import Foundation
import AppKit
import ApplicationServices

extension AppDelegate {
    private static let axMessagingTimeout: Float = 0.05

    func selectedTextFromSystemSelection() -> String? {
        if let axSelected = selectedTextFromAXFocusedElement(),
           !axSelected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return axSelected
        }
        return selectedTextBySimulatedCopy()
    }

    private func selectedTextFromAXFocusedElement() -> String? {
        guard AccessibilityPermissionManager.isTrusted() else { return nil }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        guard focusedStatus == .success,
              let focusedElementRef,
              CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID()
        else {
            return nil
        }

        let focusedElement = unsafeBitCast(focusedElementRef, to: AXUIElement.self)
        var selectedTextRef: CFTypeRef?
        let selectedStatus = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &selectedTextRef
        )
        guard selectedStatus == .success, let selectedTextRef else {
            return nil
        }

        if let selectedText = selectedTextRef as? String, !selectedText.isEmpty {
            return selectedText
        }
        if let selectedText = selectedTextRef as? NSAttributedString, !selectedText.string.isEmpty {
            return selectedText.string
        }
        return nil
    }

    private func selectedTextBySimulatedCopy() -> String? {
        guard AccessibilityPermissionManager.isTrusted() else { return nil }
        guard let source = CGEventSource(stateID: .hidSystemState) else { return nil }

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        let originalChangeCount = pasteboard.changeCount

        let cKeyCode: CGKeyCode = 0x08
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true)
        cmdDown?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false)
        cmdUp?.flags = .maskCommand
        guard cmdDown != nil, cmdUp != nil else { return nil }

        cmdDown?.post(tap: .cgAnnotatedSessionEventTap)
        cmdUp?.post(tap: .cgAnnotatedSessionEventTap)

        let deadline = Date().addingTimeInterval(0.06)
        while pasteboard.changeCount == originalChangeCount, Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        let copiedChangeCount = pasteboard.changeCount
        guard copiedChangeCount != originalChangeCount else {
            return nil
        }

        let copied = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        pasteboard.clearContents()
        if let previous, !previous.isEmpty {
            pasteboard.setString(previous, forType: .string)
        }

        guard let copied, !copied.isEmpty else { return nil }
        return copied
    }

    func hasWritableFocusedTextInput() -> Bool {
        guard let focusedElement = focusedAXElement() else {
            VoxtLog.info("Focused input check: no focused AX element.")
            return false
        }

        if let writableElement = writableTextInputElement(from: focusedElement) {
            let role = axStringAttribute(kAXRoleAttribute as CFString, for: writableElement) ?? "unknown"
            let editable = axBoolAttribute("AXEditable" as CFString, for: writableElement) == true
            var isSettable = DarwinBoolean(false)
            let settableStatus = AXUIElementIsAttributeSettable(
                writableElement,
                kAXValueAttribute as CFString,
                &isSettable
            )
            let valueSettable = settableStatus == .success && isSettable.boolValue
            VoxtLog.info(
                "Focused input check: writable descendant detected. role=\(role), editable=\(editable), valueSettable=\(valueSettable)"
            )
            return true
        }

        let editable = axBoolAttribute("AXEditable" as CFString, for: focusedElement)
        if editable == true {
            let role = axStringAttribute(kAXRoleAttribute as CFString, for: focusedElement) ?? "unknown"
            VoxtLog.info("Focused input check: editable AX element detected. role=\(role)")
            return true
        }

        var isSettable = DarwinBoolean(false)
        let settableStatus = AXUIElementIsAttributeSettable(
            focusedElement,
            kAXValueAttribute as CFString,
            &isSettable
        )
        if settableStatus == .success, isSettable.boolValue {
            let role = axStringAttribute(kAXRoleAttribute as CFString, for: focusedElement) ?? "unknown"
            VoxtLog.info("Focused input check: settable AX value detected. role=\(role)")
            return true
        }

        guard let role = axStringAttribute(kAXRoleAttribute as CFString, for: focusedElement) else {
            VoxtLog.info(
                "Focused input check: role unavailable. editable=\(editable == true), valueSettable=\(isSettable.boolValue)"
            )
            return false
        }

        let writableRoles: Set<String> = [
            kAXTextAreaRole as String,
            kAXTextFieldRole as String,
            "AXSearchField",
            kAXComboBoxRole as String
        ]
        let isWritable = writableRoles.contains(role)
        VoxtLog.info(
            "Focused input check: role=\(role), editable=\(editable == true), valueSettable=\(isSettable.boolValue), result=\(isWritable)"
        )
        return isWritable
    }

    private func focusedAXElement() -> AXUIElement? {
        guard AccessibilityPermissionManager.isTrusted() else {
            VoxtLog.info("Focused input check: accessibility not trusted.")
            return nil
        }

        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, Self.axMessagingTimeout)
        var focusedElementRef: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )
        if focusedStatus == .success,
           let focusedElementRef,
           CFGetTypeID(focusedElementRef) == AXUIElementGetTypeID() {
            return unsafeBitCast(focusedElementRef, to: AXUIElement.self)
        }

        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
        VoxtLog.info(
            "Focused input check: system-wide focused element unavailable. status=\(focusedStatus.rawValue), bundleID=\(bundleID)"
        )

        guard let appPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            VoxtLog.info("Focused input check: no frontmost application PID.")
            return nil
        }

        let appElement = AXUIElementCreateApplication(appPID)
        AXUIElementSetMessagingTimeout(appElement, Self.axMessagingTimeout)
        if let focusedAppElement = axElementAttribute(kAXFocusedUIElementAttribute as CFString, for: appElement) {
            VoxtLog.info("Focused input check: using frontmost app focused element. bundleID=\(bundleID)")
            return focusedAppElement
        }

        guard let focusedWindow = axElementAttribute(kAXFocusedWindowAttribute as CFString, for: appElement) else {
            VoxtLog.info("Focused input check: no focused window on frontmost app. bundleID=\(bundleID)")
            return nil
        }

        if let focusedWindowElement = axElementAttribute(kAXFocusedUIElementAttribute as CFString, for: focusedWindow) {
            VoxtLog.info("Focused input check: using focused window focused element. bundleID=\(bundleID)")
            return focusedWindowElement
        }

        VoxtLog.info("Focused input check: falling back to focused window element. bundleID=\(bundleID)")
        return focusedWindow
    }

    private func axBoolAttribute(_ attribute: CFString, for element: AXUIElement) -> Bool? {
        AXUIElementSetMessagingTimeout(element, Self.axMessagingTimeout)
        var valueRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard status == .success, let valueRef else { return nil }
        if let boolValue = valueRef as? Bool {
            return boolValue
        }
        if let numberValue = valueRef as? NSNumber {
            return numberValue.boolValue
        }
        return nil
    }

    private func axStringAttribute(_ attribute: CFString, for element: AXUIElement) -> String? {
        AXUIElementSetMessagingTimeout(element, Self.axMessagingTimeout)
        var valueRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard status == .success else { return nil }
        return valueRef as? String
    }

    private func axElementAttribute(_ attribute: CFString, for element: AXUIElement) -> AXUIElement? {
        AXUIElementSetMessagingTimeout(element, Self.axMessagingTimeout)
        var valueRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard status == .success,
              let valueRef,
              CFGetTypeID(valueRef) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeBitCast(valueRef, to: AXUIElement.self)
    }

    private func axElementArrayAttribute(_ attribute: CFString, for element: AXUIElement) -> [AXUIElement] {
        AXUIElementSetMessagingTimeout(element, Self.axMessagingTimeout)
        var valueRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &valueRef)
        guard status == .success,
              let valueRef,
              let array = valueRef as? [Any]
        else {
            return []
        }

        return array.compactMap { item in
            let cfItem = item as AnyObject
            guard CFGetTypeID(cfItem) == AXUIElementGetTypeID() else { return nil }
            return unsafeBitCast(cfItem, to: AXUIElement.self)
        }
    }

    private func writableTextInputElement(from element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth <= 5 else { return nil }

        if isWritableTextInputElement(element) {
            return element
        }

        if let focusedChild = axElementAttribute(kAXFocusedUIElementAttribute as CFString, for: element),
           let writableFocusedChild = writableTextInputElement(from: focusedChild, depth: depth + 1) {
            return writableFocusedChild
        }

        for child in axElementArrayAttribute(kAXChildrenAttribute as CFString, for: element) {
            if let writableChild = writableTextInputElement(from: child, depth: depth + 1) {
                return writableChild
            }
        }

        return nil
    }

    private func isWritableTextInputElement(_ element: AXUIElement) -> Bool {
        if axBoolAttribute("AXEditable" as CFString, for: element) == true {
            return true
        }

        var isSettable = DarwinBoolean(false)
        let settableStatus = AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &isSettable
        )
        if settableStatus == .success, isSettable.boolValue {
            return true
        }

        guard let role = axStringAttribute(kAXRoleAttribute as CFString, for: element) else {
            return false
        }

        let writableRoles: Set<String> = [
            kAXTextAreaRole as String,
            kAXTextFieldRole as String,
            "AXSearchField",
            kAXComboBoxRole as String
        ]
        return writableRoles.contains(role)
    }

    @discardableResult
    private func restoreSessionTargetApplicationIfNeeded() -> Bool {
        guard let ownBundleID = Bundle.main.bundleIdentifier else { return false }
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let frontmostBundleID = frontmostApplication?.bundleIdentifier
        let frontmostPID = frontmostApplication?.processIdentifier
        let ownPID = ProcessInfo.processInfo.processIdentifier

        guard frontmostPID == ownPID || frontmostBundleID == ownBundleID else {
            return false
        }

        if let targetPID = sessionTargetApplicationPID,
           let targetApplication = NSRunningApplication(processIdentifier: targetPID),
           !targetApplication.isTerminated {
            VoxtLog.info(
                "Restoring focus to session target app before text injection. bundleID=\(targetApplication.bundleIdentifier ?? "unknown"), pid=\(targetPID)"
            )
            return targetApplication.activate(options: [])
        }

        if let targetBundleID = sessionTargetApplicationBundleID,
           let targetApplication = NSRunningApplication.runningApplications(withBundleIdentifier: targetBundleID)
            .first(where: { !$0.isTerminated }) {
            VoxtLog.info(
                "Restoring focus to session target app by bundle ID before text injection. bundleID=\(targetBundleID), pid=\(targetApplication.processIdentifier)"
            )
            return targetApplication.activate(options: [])
        }

        VoxtLog.info(
            "Session target app restoration skipped: target app unavailable. targetBundleID=\(sessionTargetApplicationBundleID ?? "nil"), targetPID=\(sessionTargetApplicationPID.map(String.init) ?? "nil")"
        )
        return false
    }

    func typeText(_ text: String, completion: ((Bool) -> Void)? = nil) {
        guard !text.isEmpty else {
            completion?(false)
            return
        }

        let injectionStartedAt = Date()
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string) ?? ""
        let accessibilityTrusted = AccessibilityPermissionManager.isTrusted()
        let keepResultInClipboard = autoCopyWhenNoFocusedInput

        guard accessibilityTrusted else {
            writeTextToPasteboard(text)
            promptForAccessibilityPermission()
            VoxtLog.warning("Accessibility permission missing. Transcription copied; paste manually after granting permission.")
            completion?(false)
            return
        }

        let activationRestored = restoreSessionTargetApplicationIfNeeded()
        let activationDelay: TimeInterval = activationRestored ? 0.04 : 0
        VoxtLog.info(
            "Text injection prepared. characters=\(text.count), activationRestored=\(activationRestored), activationDelayMs=\(Int(activationDelay * 1000))"
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay) { [weak self] in
            guard let self else {
                completion?(false)
                return
            }

            self.pasteTextByShortcut(
                text,
                previousClipboardValue: previous,
                keepResultInClipboard: keepResultInClipboard,
                completion: { didInject in
                    let elapsedMs = Int(Date().timeIntervalSince(injectionStartedAt) * 1000)
                    VoxtLog.info(
                        "Text injection completed via paste fallback. characters=\(text.count), elapsedMs=\(elapsedMs), didInject=\(didInject)"
                    )
                    completion?(didInject)
                }
            )
        }
    }

    func beginOverlayOutputDelivery() {
        overlayState.isRequesting = true
        overlayState.isCompleting = false
        if overlayState.displayMode != .answer {
            overlayState.displayMode = .processing
        }
    }

    func endOverlayOutputDelivery() {
        overlayState.isRequesting = false
    }

    func writeTextToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func cacheLatestInjectableOutputText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        latestInjectableOutputText = trimmed
    }

    private func resolvedLatestInjectableOutputText() -> String? {
        let cached = latestInjectableOutputText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !cached.isEmpty {
            return cached
        }

        let historyText = historyStore.allHistoryEntries.first?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return historyText.isEmpty ? nil : historyText
    }

    func injectLatestResultByCustomPasteHotkey() {
        guard let latestText = resolvedLatestInjectableOutputText() else {
            showOverlayStatus(String(localized: "No recent result available to paste yet."), clearAfter: 2.0)
            return
        }

        typeText(latestText)
    }

    private func pasteTextByShortcut(
        _ text: String,
        previousClipboardValue: String,
        keepResultInClipboard: Bool,
        completion: ((Bool) -> Void)?
    ) {
        writeTextToPasteboard(text)

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            VoxtLog.error("typeText fallback failed: unable to create CGEventSource")
            completion?(false)
            return
        }

        let vKeyCode: CGKeyCode = 0x09
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        cmdDown?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        cmdUp?.flags = .maskCommand

        guard cmdDown != nil, cmdUp != nil else {
            VoxtLog.error("typeText fallback failed: unable to create key events")
            completion?(false)
            return
        }

        cmdDown?.post(tap: .cgAnnotatedSessionEventTap)
        cmdUp?.post(tap: .cgAnnotatedSessionEventTap)
        completion?(true)

        guard !keepResultInClipboard else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            if !previousClipboardValue.isEmpty {
                pasteboard.setString(previousClipboardValue, forType: .string)
            }
        }
    }

    private func promptForAccessibilityPermission() {
        _ = AccessibilityPermissionManager.request(prompt: true)
    }
}
