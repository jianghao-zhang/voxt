import SwiftUI
import AppKit
import Carbon

private struct HotkeyConflictRule {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    let messageKey: String
}

private let hotkeyConflictRules: [HotkeyConflictRule] = [
    HotkeyConflictRule(keyCode: UInt16(kVK_Space), modifiers: [.command], messageKey: "Conflicts with Spotlight (⌘Space)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_Space), modifiers: [.command, .option], messageKey: "Conflicts with Finder search (⌥⌘Space)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_Tab), modifiers: [.command], messageKey: "Conflicts with App Switcher (⌘Tab)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_ANSI_Grave), modifiers: [.command], messageKey: "Conflicts with window switcher (⌘`)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_ANSI_Q), modifiers: [.command], messageKey: "Conflicts with Quit (⌘Q)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_ANSI_H), modifiers: [.command], messageKey: "Conflicts with Hide (⌘H)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_ANSI_M), modifiers: [.command], messageKey: "Conflicts with Minimise (⌘M)."),
    HotkeyConflictRule(keyCode: UInt16(kVK_ANSI_W), modifiers: [.command], messageKey: "Conflicts with Close (⌘W).")
]

struct HotkeySettingsView: View {
    private enum RecordingField {
        case transcription
        case translation
        case rewrite
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
    @AppStorage(AppPreferenceKey.hotkeyTriggerMode) private var hotkeyTriggerMode = HotkeyPreference.defaultTriggerMode.rawValue
    @AppStorage(AppPreferenceKey.hotkeyDistinguishModifierSides) private var distinguishModifierSides = HotkeyPreference.defaultDistinguishModifierSides
    @AppStorage(AppPreferenceKey.hotkeyPreset) private var hotkeyPreset = HotkeyPreference.defaultPreset.rawValue
    @AppStorage(AppPreferenceKey.interfaceLanguage) private var interfaceLanguageRaw = AppInterfaceLanguage.system.rawValue

    @State private var recordingField: RecordingField?

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

    private var activeKeyCodeBinding: Binding<UInt16> {
        Binding(
            get: {
                switch recordingField {
                case .translation:
                    return UInt16(translationHotkeyKeyCode)
                case .rewrite:
                    return UInt16(rewriteHotkeyKeyCode)
                default:
                    return UInt16(hotkeyKeyCode)
                }
            },
            set: { newValue in
                switch recordingField {
                case .translation:
                    translationHotkeyKeyCode = Int(newValue)
                case .rewrite:
                    rewriteHotkeyKeyCode = Int(newValue)
                default:
                    hotkeyKeyCode = Int(newValue)
                }
                hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
            }
        )
    }

    private var activeModifierBinding: Binding<NSEvent.ModifierFlags> {
        Binding(
            get: {
                switch recordingField {
                case .translation:
                    return NSEvent.ModifierFlags(rawValue: UInt(translationHotkeyModifiers)).intersection(.hotkeyRelevant)
                case .rewrite:
                    return NSEvent.ModifierFlags(rawValue: UInt(rewriteHotkeyModifiers)).intersection(.hotkeyRelevant)
                default:
                    return NSEvent.ModifierFlags(rawValue: UInt(hotkeyModifiers)).intersection(.hotkeyRelevant)
                }
            },
            set: { newValue in
                switch recordingField {
                case .translation:
                    translationHotkeyModifiers = Int(newValue.rawValue)
                case .rewrite:
                    rewriteHotkeyModifiers = Int(newValue.rawValue)
                default:
                    hotkeyModifiers = Int(newValue.rawValue)
                }
                hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
            }
        )
    }

    private var activeSidedModifierBinding: Binding<SidedModifierFlags> {
        Binding(
            get: {
                switch recordingField {
                case .translation:
                    return SidedModifierFlags(rawValue: translationHotkeySidedModifiers).filtered(by: translationModifierBinding.wrappedValue)
                case .rewrite:
                    return SidedModifierFlags(rawValue: rewriteHotkeySidedModifiers).filtered(by: rewriteModifierBinding.wrappedValue)
                default:
                    return SidedModifierFlags(rawValue: hotkeySidedModifiers).filtered(by: modifierBinding.wrappedValue)
                }
            },
            set: { newValue in
                switch recordingField {
                case .translation:
                    translationHotkeySidedModifiers = newValue.filtered(by: translationModifierBinding.wrappedValue).rawValue
                case .rewrite:
                    rewriteHotkeySidedModifiers = newValue.filtered(by: rewriteModifierBinding.wrappedValue).rawValue
                default:
                    hotkeySidedModifiers = newValue.filtered(by: modifierBinding.wrappedValue).rawValue
                }
                hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
            }
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
            get: { HotkeyPreference.TriggerMode(rawValue: hotkeyTriggerMode) ?? HotkeyPreference.defaultTriggerMode },
            set: { hotkeyTriggerMode = $0.rawValue }
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
                    Text("Shortcut")
                        .font(.headline)

                    HStack(alignment: .center, spacing: 12) {
                        Text("Preset")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Preset", selection: presetBinding) {
                            ForEach(HotkeyPreference.Preset.allCases) { preset in
                                Text(preset.title).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 220, alignment: .trailing)
                    }

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Distinguish Left/Right Modifiers")
                                .foregroundStyle(.secondary)
                            Text("When enabled, Left Shift and Right Shift are treated as different shortcuts.")
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

                    shortcutInput(
                        titleKey: "Transcription",
                        hotkey: currentHotkey,
                        isRecording: recordingField == .transcription,
                        onFocus: { recordingField = .transcription },
                        onReset: {
                            hotkeyBinding.wrappedValue = HotkeyPreference.defaultKeyCode
                            modifierBinding.wrappedValue = HotkeyPreference.defaultModifiers
                            sidedModifierBinding.wrappedValue = []
                            hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
                        }
                    )

                    shortcutInput(
                        titleKey: "Translation",
                        hotkey: currentTranslationHotkey,
                        isRecording: recordingField == .translation,
                        onFocus: { recordingField = .translation },
                        onReset: {
                            translationHotkeyBinding.wrappedValue = HotkeyPreference.defaultTranslationKeyCode
                            translationModifierBinding.wrappedValue = HotkeyPreference.defaultTranslationModifiers
                            translationSidedModifierBinding.wrappedValue = []
                            hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
                        }
                    )

                    shortcutInput(
                        titleKey: "Content Rewrite",
                        hotkey: currentRewriteHotkey,
                        isRecording: recordingField == .rewrite,
                        onFocus: { recordingField = .rewrite },
                        onReset: {
                            rewriteHotkeyBinding.wrappedValue = HotkeyPreference.defaultRewriteKeyCode
                            rewriteModifierBinding.wrappedValue = HotkeyPreference.defaultRewriteModifiers
                            rewriteSidedModifierBinding.wrappedValue = []
                            hotkeyPreset = HotkeyPreference.Preset.custom.rawValue
                        }
                    )

                    if recordingField != nil {
                        Text("Type your shortcut now. Press Esc to cancel recording.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let conflict = hotkeyConflictMessage(for: currentHotkey) {
                        Text(localizedString("Transcription shortcut: %@", conflict))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if let conflict = hotkeyConflictMessage(for: currentTranslationHotkey) {
                        Text(localizedString("Translation shortcut: %@", conflict))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if let conflict = hotkeyConflictMessage(for: currentRewriteHotkey) {
                        Text(localizedString("Content rewrite shortcut: %@", conflict))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if currentHotkey == currentTranslationHotkey {
                        Text("Transcription and translation shortcuts should be different.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if currentHotkey == currentRewriteHotkey {
                        Text("Transcription and content rewrite shortcuts should be different.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if currentTranslationHotkey == currentRewriteHotkey {
                        Text("Translation and content rewrite shortcuts should be different.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    HotkeyRecorderView(
                        keyCode: activeKeyCodeBinding,
                        modifiers: activeModifierBinding,
                        sidedModifiers: activeSidedModifierBinding,
                        isRecording: isRecordingBinding
                    )
                    .frame(width: 0, height: 0)

                    HStack(alignment: .center, spacing: 12) {
                        Text("Trigger")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("Trigger", selection: triggerModeBinding) {
                            ForEach(HotkeyPreference.TriggerMode.allCases) { mode in
                                Text(mode.titleKey).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 220, alignment: .trailing)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tips")
                        .font(.headline)
                    Text("Both actions support custom shortcuts. You can use a single key (such as fn) or a key combination.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Enable left/right modifier distinction only if you want shortcuts such as Right Command and Right Shift to behave differently from their left-side counterparts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Long Press: Hold a hotkey to start its session and release it to stop. This works for transcription, translation, and content rewrite.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Tap: Tap transcription hotkey to start and tap transcription hotkey again to stop. Translation and content rewrite hotkeys start their own sessions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Selected text shortcut behavior: If text is selected in a focused input, pressing the translation shortcut translates and replaces the selection directly. Tap and long press behave the same.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
        }
        .id(interfaceLanguageRaw)
    }

    private func hotkeyConflictMessage(for hotkey: HotkeyPreference.Hotkey) -> String? {
        return hotkeyConflictRules.first {
            hotkey.keyCode == $0.keyCode && hotkey.modifiers == $0.modifiers
        }.map { NSLocalizedString($0.messageKey, comment: "") }
    }

    private func localizedString(_ formatKey: String, _ argument: String) -> String {
        String(format: NSLocalizedString(formatKey, comment: ""), argument)
    }

    private func applyPreset(_ preset: HotkeyPreference.Preset) {
        hotkeyPreset = preset.rawValue
        guard let values = HotkeyPreference.presetHotkeys(for: preset) else { return }

        distinguishModifierSides = values.distinguishSides

        hotkeyKeyCode = Int(values.transcription.keyCode)
        hotkeyModifiers = Int(values.transcription.modifiers.rawValue)
        hotkeySidedModifiers = values.transcription.sidedModifiers.rawValue

        translationHotkeyKeyCode = Int(values.translation.keyCode)
        translationHotkeyModifiers = Int(values.translation.modifiers.rawValue)
        translationHotkeySidedModifiers = values.translation.sidedModifiers.rawValue

        rewriteHotkeyKeyCode = Int(values.rewrite.keyCode)
        rewriteHotkeyModifiers = Int(values.rewrite.modifiers.rawValue)
        rewriteHotkeySidedModifiers = values.rewrite.sidedModifiers.rawValue
    }

    @ViewBuilder
    private func shortcutInput(
        titleKey: LocalizedStringKey,
        hotkey: HotkeyPreference.Hotkey,
        isRecording: Bool,
        onFocus: @escaping () -> Void,
        onReset: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(titleKey)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()

            HStack(spacing: 8) {
                Text(isRecording ? String(localized: "Listening...") : HotkeyPreference.displayString(for: hotkey, distinguishModifierSides: distinguishModifierSides))
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(isRecording ? .primary : .primary)
                Spacer()
                Button(action: onReset) {
                    Image(systemName: "arrow.counterclockwise")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(Text("Reset shortcut"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isRecording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isRecording ? 2 : 1)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onFocus)
            .frame(width: 320, alignment: .trailing)
        }
    }
}
