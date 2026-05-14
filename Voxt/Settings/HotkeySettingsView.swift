import SwiftUI
import AppKit
import Carbon

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

enum HotkeyShortcutKind: String, CaseIterable {
    case transcription
    case translation
    case rewrite

    var titleKey: LocalizedStringKey {
        switch self {
        case .transcription:
            return "Transcription"
        case .translation:
            return "Translation"
        case .rewrite:
            return "Content Rewrite"
        }
    }
}

enum HotkeyShortcutVisibility {
    static func visibleKinds() -> [HotkeyShortcutKind] {
        [.transcription, .translation, .rewrite]
    }
}

struct HotkeySettingsView: View {
    private enum RecordingField {
        case transcription
        case translation
        case rewrite
        case customPaste
    }

    @AppStorage(AppPreferenceKey.hotkeyKeyCode) private var hotkeyKeyCode = Int(HotkeyPreference.defaultKeyCode)
    @AppStorage(AppPreferenceKey.hotkeyModifiers) private var hotkeyModifiers = Int(HotkeyPreference.defaultModifiers.rawValue)
    @AppStorage(AppPreferenceKey.hotkeySidedModifiers) private var hotkeySidedModifiers = 0
    @AppStorage(AppPreferenceKey.translationHotkeyKeyCode) private var translationHotkeyKeyCode = Int(HotkeyPreference.defaultTranslationKeyCode)
    @AppStorage(AppPreferenceKey.translationHotkeyModifiers) private var translationHotkeyModifiers = Int(HotkeyPreference.defaultTranslationModifiers.rawValue)
    @AppStorage(AppPreferenceKey.translationHotkeySidedModifiers) private var translationHotkeySidedModifiers = 0
    @AppStorage(AppPreferenceKey.rewriteHotkeyKeyCode) private var rewriteHotkeyKeyCode = Int(HotkeyPreference.defaultRewriteKeyCode)
    @AppStorage(AppPreferenceKey.rewriteHotkeyModifiers) private var rewriteHotkeyModifiers = Int(HotkeyPreference.defaultRewriteModifiers.rawValue)
    @AppStorage(AppPreferenceKey.rewriteHotkeySidedModifiers) private var rewriteHotkeySidedModifiers = 0
    @AppStorage(AppPreferenceKey.rewriteHotkeyActivationMode) private var rewriteHotkeyActivationMode = HotkeyPreference.defaultRewriteActivationMode.rawValue
    @AppStorage(AppPreferenceKey.customPasteHotkeyEnabled) private var customPasteHotkeyEnabled = false
    @AppStorage(AppPreferenceKey.customPasteHotkeyKeyCode) private var customPasteHotkeyKeyCode = Int(HotkeyPreference.defaultCustomPasteKeyCode)
    @AppStorage(AppPreferenceKey.customPasteHotkeyModifiers) private var customPasteHotkeyModifiers = Int(HotkeyPreference.defaultCustomPasteModifiers.rawValue)
    @AppStorage(AppPreferenceKey.customPasteHotkeySidedModifiers) private var customPasteHotkeySidedModifiers = 0
    @AppStorage(AppPreferenceKey.hotkeyTriggerMode) private var hotkeyTriggerMode = HotkeyPreference.defaultTriggerMode.rawValue
    @AppStorage(AppPreferenceKey.hotkeyDistinguishModifierSides) private var distinguishModifierSides = HotkeyPreference.defaultDistinguishModifierSides
    @AppStorage(AppPreferenceKey.hotkeyPreset) private var hotkeyPreset = HotkeyPreference.defaultPreset.rawValue
    @AppStorage(AppPreferenceKey.escapeKeyCancelsOverlaySession) private var escapeKeyCancelsOverlaySession = true
    @AppStorage(AppPreferenceKey.mouseTriggersEnabled) private var mouseTriggersEnabled = false
    @AppStorage(AppPreferenceKey.mouseTriggerMode) private var mouseTriggerMode = MouseTriggerPreference.defaultTriggerMode.rawValue
    @AppStorage(AppPreferenceKey.interfaceLanguage) private var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue
    @State private var recordingField: RecordingField?
    @State private var pendingCapturedField: RecordingField?
    @State private var pendingCapturedHotkey: HotkeyPreference.Hotkey?
    @State private var recorderMessageKey: String?
    @State private var isMouseShortcutSectionExpanded = false

    private var hotkeyBinding: Binding<UInt16> {
        Binding(
            get: { UInt16(hotkeyKeyCode) },
            set: {
                hotkeyKeyCode = Int($0)
                hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
            }
        )
    }

    private var modifierBinding: Binding<NSEvent.ModifierFlags> {
        Binding(
            get: { NSEvent.ModifierFlags(rawValue: UInt(hotkeyModifiers)).intersection(.hotkeyRelevant) },
            set: {
                hotkeyModifiers = Int($0.rawValue)
                hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
            }
        )
    }

    private var currentHotkey: HotkeyPreference.Hotkey {
        HotkeyPreference.Hotkey(
            keyCode: hotkeyBinding.wrappedValue,
            modifiers: modifierBinding.wrappedValue,
            sidedModifiers: sidedModifierBinding.wrappedValue
        )
    }

    private var sidedModifierBinding: Binding<SidedModifierFlags> {
        Binding(
            get: { SidedModifierFlags(rawValue: hotkeySidedModifiers).filtered(by: modifierBinding.wrappedValue) },
            set: { hotkeySidedModifiers = $0.filtered(by: modifierBinding.wrappedValue).rawValue }
        )
    }

    private var translationHotkeyBinding: Binding<UInt16> {
        Binding(
            get: { UInt16(translationHotkeyKeyCode) },
            set: {
                translationHotkeyKeyCode = Int($0)
                hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
            }
        )
    }

    private var translationModifierBinding: Binding<NSEvent.ModifierFlags> {
        Binding(
            get: { NSEvent.ModifierFlags(rawValue: UInt(translationHotkeyModifiers)).intersection(.hotkeyRelevant) },
            set: {
                translationHotkeyModifiers = Int($0.rawValue)
                hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
            }
        )
    }

    private var currentTranslationHotkey: HotkeyPreference.Hotkey {
        HotkeyPreference.Hotkey(
            keyCode: translationHotkeyBinding.wrappedValue,
            modifiers: translationModifierBinding.wrappedValue,
            sidedModifiers: translationSidedModifierBinding.wrappedValue
        )
    }

    private var translationSidedModifierBinding: Binding<SidedModifierFlags> {
        Binding(
            get: { SidedModifierFlags(rawValue: translationHotkeySidedModifiers).filtered(by: translationModifierBinding.wrappedValue) },
            set: { translationHotkeySidedModifiers = $0.filtered(by: translationModifierBinding.wrappedValue).rawValue }
        )
    }

    private var rewriteHotkeyBinding: Binding<UInt16> {
        Binding(
            get: { UInt16(rewriteHotkeyKeyCode) },
            set: {
                rewriteHotkeyKeyCode = Int($0)
                hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
            }
        )
    }

    private var rewriteModifierBinding: Binding<NSEvent.ModifierFlags> {
        Binding(
            get: { NSEvent.ModifierFlags(rawValue: UInt(rewriteHotkeyModifiers)).intersection(.hotkeyRelevant) },
            set: {
                rewriteHotkeyModifiers = Int($0.rawValue)
                hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
            }
        )
    }

    private var currentRewriteHotkey: HotkeyPreference.Hotkey {
        HotkeyPreference.Hotkey(
            keyCode: rewriteHotkeyBinding.wrappedValue,
            modifiers: rewriteModifierBinding.wrappedValue,
            sidedModifiers: rewriteSidedModifierBinding.wrappedValue
        )
    }

    private var rewriteSidedModifierBinding: Binding<SidedModifierFlags> {
        Binding(
            get: { SidedModifierFlags(rawValue: rewriteHotkeySidedModifiers).filtered(by: rewriteModifierBinding.wrappedValue) },
            set: { rewriteHotkeySidedModifiers = $0.filtered(by: rewriteModifierBinding.wrappedValue).rawValue }
        )
    }

    private var customPasteHotkeyBinding: Binding<UInt16> {
        Binding(
            get: { UInt16(customPasteHotkeyKeyCode) },
            set: { customPasteHotkeyKeyCode = Int($0) }
        )
    }

    private var customPasteModifierBinding: Binding<NSEvent.ModifierFlags> {
        Binding(
            get: { NSEvent.ModifierFlags(rawValue: UInt(customPasteHotkeyModifiers)).intersection(.hotkeyRelevant) },
            set: { customPasteHotkeyModifiers = Int($0.rawValue) }
        )
    }

    private var currentCustomPasteHotkey: HotkeyPreference.Hotkey {
        HotkeyPreference.Hotkey(
            keyCode: customPasteHotkeyBinding.wrappedValue,
            modifiers: customPasteModifierBinding.wrappedValue,
            sidedModifiers: customPasteSidedModifierBinding.wrappedValue
        )
    }

    private var customPasteSidedModifierBinding: Binding<SidedModifierFlags> {
        Binding(
            get: { SidedModifierFlags(rawValue: customPasteHotkeySidedModifiers).filtered(by: customPasteModifierBinding.wrappedValue) },
            set: { customPasteHotkeySidedModifiers = $0.filtered(by: customPasteModifierBinding.wrappedValue).rawValue }
        )
    }

    private var isRecordingBinding: Binding<Bool> {
        Binding(
            get: { recordingField != nil },
            set: { isRecording in
                if !isRecording {
                    recordingField = nil
                }
            }
        )
    }

    private var triggerModeBinding: Binding<HotkeyPreference.TriggerMode> {
        Binding(
            get: {
                rewriteActivationState.enforcedTriggerMode(
                    from: HotkeyPreference.TriggerMode(rawValue: hotkeyTriggerMode) ?? HotkeyPreference.defaultTriggerMode
                )
            },
            set: {
                hotkeyTriggerMode = rewriteActivationState.enforcedTriggerMode(from: $0).rawValue
            }
        )
    }

    private var mouseTriggerModeBinding: Binding<HotkeyPreference.TriggerMode> {
        Binding(
            get: {
                HotkeyPreference.TriggerMode(rawValue: mouseTriggerMode)
                    ?? MouseTriggerPreference.defaultTriggerMode
            },
            set: {
                mouseTriggerMode = $0.rawValue
            }
        )
    }

    private var rewriteActivationState: HotkeyRewriteActivationState {
        HotkeyRewriteActivationState(rawValue: rewriteHotkeyActivationMode)
    }

    private var isRewriteDoubleTapWakeEnabled: Bool {
        rewriteActivationState.isDoubleTapWakeEnabled
    }

    private var rewriteDoubleTapDisplayText: String {
        rewriteActivationState.displayText(
            for: currentHotkey,
            distinguishModifierSides: distinguishModifierSides
        )
    }

    private var validationMessages: [HotkeySettingsValidation.Message] {
        HotkeySettingsValidation.messages(
            for: .init(
                transcriptionHotkey: currentHotkey,
                translationHotkey: currentTranslationHotkey,
                rewriteHotkey: currentRewriteHotkey,
                shouldValidateRewriteHotkey: !isRewriteDoubleTapWakeEnabled,
                customPasteHotkey: customPasteHotkeyEnabled ? currentCustomPasteHotkey : nil
            )
        )
    }

    private var presetBinding: Binding<HotkeyPreference.Preset> {
        Binding(
            get: { HotkeyPreference.Preset(rawValue: hotkeyPreset) ?? .custom },
            set: { applyPreset($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text(localized("Shortcut"))
                        .font(.headline)

                    HStack(alignment: .center, spacing: 12) {
                        Text(localized("Preset"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        SettingsMenuPicker(
                            selection: presetBinding,
                            options: HotkeyPreference.Preset.allCases.map { preset in
                                SettingsMenuOption(value: preset, title: preset.title)
                            },
                            selectedTitle: presetBinding.wrappedValue.title,
                            width: 220
                        )
                    }

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localized("Distinguish Left/Right Modifiers"))
                                .foregroundStyle(.secondary)
                            Text(localized("When enabled, Left Shift and Right Shift are treated as different shortcuts."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { distinguishModifierSides },
                                set: { newValue in
                                    distinguishModifierSides = newValue
                                    hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
                                }
                            )
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    SettingsShortcutCaptureField(
                        title: "Transcription",
                        hotkey: displayedHotkey(for: .transcription, current: currentHotkey),
                        isRecording: recordingField == .transcription,
                        isPendingConfirmation: isPendingConfirmation(for: .transcription),
                        distinguishModifierSides: distinguishModifierSides,
                        onFocus: { beginRecording(.transcription) },
                        onReset: {
                            hotkeyBinding.wrappedValue = HotkeyPreference.defaultKeyCode
                            modifierBinding.wrappedValue = HotkeyPreference.defaultModifiers
                            sidedModifierBinding.wrappedValue = []
                            hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
                        },
                        onCancelPending: discardPendingCapture,
                        onConfirmPending: confirmPendingCapture
                    )

                    SettingsShortcutCaptureField(
                        title: "Translation",
                        hotkey: displayedHotkey(for: .translation, current: currentTranslationHotkey),
                        isRecording: recordingField == .translation,
                        isPendingConfirmation: isPendingConfirmation(for: .translation),
                        distinguishModifierSides: distinguishModifierSides,
                        onFocus: { beginRecording(.translation) },
                        onReset: {
                            translationHotkeyBinding.wrappedValue = HotkeyPreference.defaultTranslationKeyCode
                            translationModifierBinding.wrappedValue = HotkeyPreference.defaultTranslationModifiers
                            translationSidedModifierBinding.wrappedValue = []
                            hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
                        },
                        onCancelPending: discardPendingCapture,
                        onConfirmPending: confirmPendingCapture
                    )

                    SettingsShortcutCaptureField(
                        title: "Content Rewrite",
                        hotkey: displayedHotkey(for: .rewrite, current: currentRewriteHotkey),
                        isRecording: recordingField == .rewrite,
                        isPendingConfirmation: isPendingConfirmation(for: .rewrite),
                        distinguishModifierSides: distinguishModifierSides,
                        displayTextOverride: isRewriteDoubleTapWakeEnabled ? rewriteDoubleTapDisplayText : nil,
                        isReadOnly: isRewriteDoubleTapWakeEnabled,
                        modeButtonTitle: "Double-tap Wake",
                        isModeButtonSelected: isRewriteDoubleTapWakeEnabled,
                        onModeButtonToggle: toggleRewriteDoubleTapWake,
                        onFocus: { beginRecording(.rewrite) },
                        onReset: {
                            rewriteHotkeyBinding.wrappedValue = HotkeyPreference.defaultRewriteKeyCode
                            rewriteModifierBinding.wrappedValue = HotkeyPreference.defaultRewriteModifiers
                            rewriteSidedModifierBinding.wrappedValue = []
                            hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
                        },
                        onCancelPending: discardPendingCapture,
                        onConfirmPending: confirmPendingCapture
                    )

                    if customPasteHotkeyEnabled {
                        SettingsShortcutCaptureField(
                            title: "Custom Paste",
                            hotkey: displayedHotkey(for: .customPaste, current: currentCustomPasteHotkey),
                            isRecording: recordingField == .customPaste,
                            isPendingConfirmation: isPendingConfirmation(for: .customPaste),
                            distinguishModifierSides: distinguishModifierSides,
                            onFocus: { beginRecording(.customPaste) },
                            onReset: {
                                customPasteHotkeyBinding.wrappedValue = HotkeyPreference.defaultCustomPasteKeyCode
                                customPasteModifierBinding.wrappedValue = HotkeyPreference.defaultCustomPasteModifiers
                                customPasteSidedModifierBinding.wrappedValue = []
                            },
                            onCancelPending: discardPendingCapture,
                            onConfirmPending: confirmPendingCapture
                        )
                    }

                    if recordingField != nil, pendingCapturedField != recordingField {
                        Text(localized("Type your shortcut now. Press Esc to cancel recording."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if pendingCapturedField != nil {
                        Text(localized("Shortcut captured. Press another shortcut to replace it, or choose Confirm / Cancel."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let recorderMessageKey {
                        Text(LocalizedStringKey(recorderMessageKey))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(validationMessages) { message in
                        Text(message.text)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    HotkeyRecorderView(
                        isRecording: isRecordingBinding,
                        onCapture: { capturedHotkey in
                            guard let field = recordingField else { return }
                            pendingCapturedField = field
                            pendingCapturedHotkey = capturedHotkey
                        },
                        onCancelCapture: {
                            discardPendingCapture()
                            recordingField = nil
                        },
                        onRecorderMessageChange: { messageKey in
                            guard recorderMessageKey != messageKey else { return }
                            DispatchQueue.main.async {
                                recorderMessageKey = messageKey
                            }
                        }
                    )
                    .frame(width: 0, height: 0)

                    HStack(alignment: .center, spacing: 12) {
                        Text(localized("Trigger"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        SettingsMenuPicker(
                            selection: triggerModeBinding,
                            options: HotkeyPreference.TriggerMode.allCases.map { mode in
                                SettingsMenuOption(value: mode, title: mode.title)
                            },
                            selectedTitle: triggerModeBinding.wrappedValue.title,
                            width: 220
                        )
                        .disabled(isRewriteDoubleTapWakeEnabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            mouseShortcutSection

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text(localized("Cancel Shortcut"))
                        .font(.headline)

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localized("Use Esc to Cancel"))
                                .foregroundStyle(.secondary)
                            Text(localized("When enabled, pressing Esc cancels the active overlay session. Turn this off to disable Esc cancellation."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $escapeKeyCancelsOverlaySession)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            VoiceEndCommandSettingsSection()

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localized("Hotkey Tips"))
                        .font(.headline)
                    Text(localized("Use a single key such as fn, or combine it with modifier keys."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(localized("Long Press runs while held. Tap starts and stops with a tap."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(localized("If text is selected, the translation shortcut translates and replaces the selection directly."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(localized("On macOS, fn shortcuts may conflict with Globe or input source switching. If needed, change that shortcut in System Settings > Keyboard > Keyboard Shortcuts > Input Sources."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
        }
        .id(interfaceLanguageRaw)
        .onChange(of: customPasteHotkeyEnabled) { _, enabled in
            guard !enabled else { return }
            if recordingField == .customPaste || pendingCapturedField == .customPaste {
                discardPendingCapture()
            }
        }
        .onChange(of: rewriteHotkeyActivationMode) { _, _ in
            if isRewriteDoubleTapWakeEnabled {
                hotkeyTriggerMode = HotkeyPreference.TriggerMode.tap.rawValue
                if recordingField == .rewrite || pendingCapturedField == .rewrite {
                    discardPendingCapture()
                }
            }
        }
    }

    private var mouseShortcutSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isMouseShortcutSectionExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(isMouseShortcutSectionExpanded ? 90 : 0))
                            .foregroundStyle(.secondary)
                        Text(localized("Middle-Click Transcription"))
                            .font(.headline)
                        Spacer()
                        Text(mouseShortcutSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isMouseShortcutSectionExpanded {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(localized("Enable Middle Click"))
                                    .foregroundStyle(.secondary)
                                Text(localized("Use the middle mouse button to start transcription."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $mouseTriggersEnabled)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }

                        HStack(alignment: .center, spacing: 12) {
                            Text(localized("Trigger"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            SettingsMenuPicker(
                                selection: mouseTriggerModeBinding,
                                options: HotkeyPreference.TriggerMode.allCases.map { mode in
                                    SettingsMenuOption(value: mode, title: mode.title)
                                },
                                selectedTitle: mouseTriggerModeBinding.wrappedValue.title,
                                width: 220
                            )
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    private var mouseShortcutSummary: String {
        mouseTriggersEnabled ? localized("On") : localized("Off")
    }

    private func applyPreset(_ preset: HotkeyPreference.Preset) {
        discardPendingCapture()
        hotkeyPreset = preset.rawValue
        guard let values = HotkeyPreference.applyPreset(preset) else { return }
        distinguishModifierSides = values.distinguishSides
    }

    private func beginRecording(_ field: RecordingField) {
        pendingCapturedField = nil
        pendingCapturedHotkey = nil
        recordingField = field
    }

    private func toggleRewriteDoubleTapWake() {
        discardPendingCapture()
        let nextState = HotkeyRewriteActivationState(
            rawValue: rewriteActivationState.toggledMode.rawValue
        )
        rewriteHotkeyActivationMode = nextState.mode.rawValue
        hotkeyTriggerMode = nextState.enforcedTriggerMode(
            from: HotkeyPreference.TriggerMode(rawValue: hotkeyTriggerMode)
                ?? HotkeyPreference.defaultTriggerMode
        ).rawValue
    }

    private func isPendingConfirmation(for field: RecordingField) -> Bool {
        pendingCapturedField == field && pendingCapturedHotkey != nil
    }

    private func displayedHotkey(for field: RecordingField, current: HotkeyPreference.Hotkey) -> HotkeyPreference.Hotkey {
        guard pendingCapturedField == field, let pendingCapturedHotkey else {
            return current
        }
        return pendingCapturedHotkey
    }

    private func discardPendingCapture() {
        recorderMessageKey = nil
        pendingCapturedField = nil
        pendingCapturedHotkey = nil
        recordingField = nil
    }

    private func confirmPendingCapture() {
        guard let field = pendingCapturedField, let hotkey = pendingCapturedHotkey else { return }

        switch field {
        case .transcription:
            hotkeyBinding.wrappedValue = hotkey.keyCode
            modifierBinding.wrappedValue = hotkey.modifiers
            sidedModifierBinding.wrappedValue = hotkey.sidedModifiers
        case .translation:
            translationHotkeyBinding.wrappedValue = hotkey.keyCode
            translationModifierBinding.wrappedValue = hotkey.modifiers
            translationSidedModifierBinding.wrappedValue = hotkey.sidedModifiers
        case .rewrite:
            rewriteHotkeyBinding.wrappedValue = hotkey.keyCode
            rewriteModifierBinding.wrappedValue = hotkey.modifiers
            rewriteSidedModifierBinding.wrappedValue = hotkey.sidedModifiers
        case .customPaste:
            customPasteHotkeyBinding.wrappedValue = hotkey.keyCode
            customPasteModifierBinding.wrappedValue = hotkey.modifiers
            customPasteSidedModifierBinding.wrappedValue =
                hotkey.keyCode == HotkeyPreference.modifierOnlyKeyCode ? hotkey.sidedModifiers : []
        }

        hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
        pendingCapturedField = nil
        pendingCapturedHotkey = nil
        recordingField = nil
    }
}
