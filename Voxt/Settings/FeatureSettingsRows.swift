import SwiftUI
import AppKit

struct FeatureToggleRow: View {
    let title: String
    var badgeText: String? = nil
    let detail: String
    @Binding var isOn: Bool
    var isEmbedded = false

    var body: some View {
        FeatureRowScaffold(
            title: title,
            badgeText: badgeText,
            detail: detail,
            isEmbedded: isEmbedded
        ) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

struct FeatureInlinePickerRow<PickerContent: View>: View {
    let title: String
    let detail: String
    var isEmbedded = false
    @ViewBuilder let picker: PickerContent

    init(title: String, detail: String, isEmbedded: Bool = false, @ViewBuilder picker: () -> PickerContent) {
        self.title = title
        self.detail = detail
        self.isEmbedded = isEmbedded
        self.picker = picker()
    }

    var body: some View {
        FeatureRowScaffold(
            title: title,
            detail: detail,
            isEmbedded: isEmbedded
        ) {
            picker
        }
    }
}

struct FeatureInlineTextFieldRow: View {
    let title: String
    let detail: String
    @Binding var text: String
    let placeholder: String
    let width: CGFloat
    var isEmbedded = false

    var body: some View {
        FeatureRowScaffold(
            title: title,
            detail: detail,
            isEmbedded: isEmbedded
        ) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .settingsFieldSurface(width: width)
                .multilineTextAlignment(.leading)
        }
    }
}

struct FeatureDirectorySelectionRow: View {
    private let pathFieldWidth: CGFloat = 200
    private let actionButtonWidth: CGFloat = 26

    let title: String
    let detail: String
    let path: String
    let buttonTitle: String
    let action: () -> Void
    var isEmbedded = false

    var body: some View {
        FeatureRowScaffold(
            title: title,
            detail: detail,
            spacerMinLength: 12,
            isEmbedded: isEmbedded
        ) {
            HStack(alignment: .center, spacing: 8) {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(width: pathFieldWidth, alignment: .leading)
                    .settingsFieldSurface(width: pathFieldWidth, minHeight: 32)

                Button(action: action) {
                    Text(buttonTitle)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: actionButtonWidth)
                }
                .buttonStyle(SettingsPillButtonStyle())
            }
        }
    }
}

struct FeatureEmbeddedFieldGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(
        spacing: CGFloat = 18,
        @ViewBuilder content: () -> Content
    ) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
    }
}

struct FeatureNoteSoundPresetRow<PickerContent: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let picker: PickerContent
    let onTrySound: () -> Void

    init(
        title: String,
        detail: String,
        @ViewBuilder picker: () -> PickerContent,
        onTrySound: @escaping () -> Void
    ) {
        self.title = title
        self.detail = detail
        self.picker = picker()
        self.onTrySound = onTrySound
    }

    var body: some View {
        FeatureRowScaffold(
            title: title,
            detail: detail,
            spacerMinLength: 12,
            isEmbedded: false
        ) {
            HStack(alignment: .center, spacing: 8) {
                picker

                Button(featureSettingsLocalized("Try Sound"), action: onTrySound)
                    .buttonStyle(SettingsPillButtonStyle())
                    .fixedSize(horizontal: true, vertical: false)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct FeatureHintBanner: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
        )
    }
}

struct FeatureSelectorRow: View {
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            SettingsSelectionButton(width: 280, action: action) {
                Text(value)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

struct SettingsShortcutCaptureField: View {
    let title: LocalizedStringKey
    let hotkey: HotkeyPreference.Hotkey
    let isRecording: Bool
    let isPendingConfirmation: Bool
    let distinguishModifierSides: Bool
    let onFocus: () -> Void
    let onReset: () -> Void
    let onCancelPending: () -> Void
    let onConfirmPending: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.body)
                .foregroundStyle(.secondary)
            Spacer()

            HStack(spacing: 8) {
                Text(
                    isRecording && !isPendingConfirmation
                        ? featureSettingsLocalized("Listening...")
                        : HotkeyPreference.displayString(for: hotkey, distinguishModifierSides: distinguishModifierSides)
                )
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.9)
                .layoutPriority(1)
                .frame(maxWidth: .infinity, alignment: .leading)

                if isPendingConfirmation {
                    Button(featureSettingsLocalized("Cancel"), action: onCancelPending)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .frame(height: 16)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color(nsColor: .controlAccentColor).opacity(0.12))
                        )
                    Button(featureSettingsLocalized("Confirm"), action: onConfirmPending)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .frame(height: 16)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.accentColor.opacity(0.18))
                        )
                } else if isRecording {
                    Button(featureSettingsLocalized("Cancel"), action: onCancelPending)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .frame(height: 16)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color(nsColor: .controlAccentColor).opacity(0.12))
                        )
                } else {
                    Button(action: onReset) {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(Text(featureSettingsLocalized("Reset shortcut")))
                }
            }
            .frame(height: 16)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(SettingsUIStyle.controlFillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onFocus)
            .frame(width: 320, alignment: .trailing)
        }
    }
}

private struct FeatureRowChromeModifier: ViewModifier {
    let isEmbedded: Bool

    func body(content: Content) -> some View {
        if isEmbedded {
            content
        } else {
            content
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                        .fill(SettingsUIStyle.groupedFillColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                        .stroke(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
                )
        }
    }
}

private struct FeatureRowScaffold<TrailingContent: View>: View {
    let title: String
    let badgeText: String?
    let detail: String
    var spacerMinLength: CGFloat = 0
    let isEmbedded: Bool
    @ViewBuilder let trailingContent: TrailingContent

    init(
        title: String,
        badgeText: String? = nil,
        detail: String,
        spacerMinLength: CGFloat = 0,
        isEmbedded: Bool,
        @ViewBuilder trailingContent: () -> TrailingContent
    ) {
        self.title = title
        self.badgeText = badgeText
        self.detail = detail
        self.spacerMinLength = spacerMinLength
        self.isEmbedded = isEmbedded
        self.trailingContent = trailingContent()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FeatureRowLabelStack(title: title, badgeText: badgeText, detail: detail)
            Spacer(minLength: spacerMinLength)
            trailingContent
        }
        .modifier(FeatureRowChromeModifier(isEmbedded: isEmbedded))
    }
}

private struct FeatureRowLabelStack: View {
    let title: String
    let badgeText: String?
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                if let badgeText, !badgeText.isEmpty {
                    Text(badgeText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.orange.opacity(0.12))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.orange.opacity(0.24), lineWidth: 1)
                        )
                }

                Spacer(minLength: 0)
            }
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
