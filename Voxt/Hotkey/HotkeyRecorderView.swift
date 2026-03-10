import SwiftUI
import AppKit
import Carbon

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var keyCode: UInt16
    @Binding var modifiers: NSEvent.ModifierFlags
    @Binding var sidedModifiers: SidedModifierFlags
    @Binding var isRecording: Bool

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onKeyCaptured = { keyCode, modifiers, sidedModifiers in
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.sidedModifiers = sidedModifiers
            self.isRecording = false
        }
        view.onCancel = {
            self.isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.isRecording = isRecording
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

final class KeyCaptureView: NSView {
    var onKeyCaptured: ((UInt16, NSEvent.ModifierFlags, SidedModifierFlags) -> Void)?
    var onCancel: (() -> Void)?
    var isRecording: Bool = false
    private var currentSidedModifiers: SidedModifierFlags = []
    private var pendingModifierCaptureTask: Task<Void, Never>?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }
        if event.keyCode == UInt16(kVK_Escape) {
            pendingModifierCaptureTask?.cancel()
            onCancel?()
            return
        }
        pendingModifierCaptureTask?.cancel()
        let mods = event.modifierFlags.intersection(.hotkeyRelevant)
        onKeyCaptured?(event.keyCode, mods, currentSidedModifiers.filtered(by: mods))
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return }

        currentSidedModifiers = SidedModifierFlags.toggled(from: currentSidedModifiers, keyCode: event.keyCode)
        let mods = event.modifierFlags.intersection(.hotkeyRelevant)
        guard !mods.isEmpty else { return }

        let modifierOnlyKeyCodes: Set<UInt16> = [
            UInt16(kVK_Shift), UInt16(kVK_RightShift),
            UInt16(kVK_Control), UInt16(kVK_RightControl),
            UInt16(kVK_Option), UInt16(kVK_RightOption),
            UInt16(kVK_Command), UInt16(kVK_RightCommand),
            UInt16(kVK_Function), UInt16(kVK_CapsLock)
        ]

        guard modifierOnlyKeyCodes.contains(event.keyCode) else { return }
        let capturedModifiers = mods
        let capturedSidedModifiers = currentSidedModifiers.filtered(by: mods)
        pendingModifierCaptureTask?.cancel()
        pendingModifierCaptureTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard let self, !Task.isCancelled, self.isRecording else { return }
            self.onKeyCaptured?(HotkeyPreference.modifierOnlyKeyCode, capturedModifiers, capturedSidedModifiers)
        }
    }
}
