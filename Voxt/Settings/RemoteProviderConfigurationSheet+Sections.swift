import SwiftUI

extension RemoteProviderConfigurationSheet {
    var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.localizedString("Model"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            SettingsMenuPicker(
                selection: providerModelSelectionBinding,
                options: providerModelMenuOptions,
                selectedTitle: providerModelSelectedTitle,
                width: 240
            )

            if shouldShowCustomProviderModelField {
                Text(AppLocalization.localizedString("Custom Model ID (Optional)"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(customProviderModelPlaceholder, text: $customModelID)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
            }
        }
    }

    var endpointAndKeySection: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.localizedString("Endpoint (Optional)"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(AppLocalization.localizedString("https://..."), text: $endpoint)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
                if !endpointPresets.isEmpty {
                    HStack(spacing: 10) {
                        Menu {
                            ForEach(endpointPresets, id: \.id) { preset in
                                Button(preset.title) {
                                    endpoint = preset.url
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(AppLocalization.localizedString("Apply Preset"))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .buttonStyle(SettingsPillButtonStyle(horizontalPadding: 10, height: 30))

                        if !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Button(AppLocalization.localizedString("Clear")) {
                                endpoint = ""
                            }
                            .buttonStyle(SettingsPillButtonStyle(horizontalPadding: 10, height: 30))
                        }

                        Spacer()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.localizedString("API Key"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SecureField(AppLocalization.localizedString("Paste API key"), text: $apiKey)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
            }

            if let endpointPresetHintText {
                Text(endpointPresetHintText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var meetingModelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.localizedString("Meeting ASR"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            SettingsMenuPicker(
                selection: meetingModelSelectionBinding,
                options: meetingModelMenuOptions,
                selectedTitle: meetingModelSelectedTitle,
                width: 240
            )

            if resolvedMeetingSelectionForPicker == customModelOptionID {
                Text(AppLocalization.localizedString("Custom Meeting Model ID"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(AppLocalization.localizedString("e.g. qwen3-asr-flash-filetrans"), text: $customMeetingModelID)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
            }

            Text(AppLocalization.localizedString("Used only for Meeting Notes transcription."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var doubaoCredentialsSection: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.localizedString("App ID"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(AppLocalization.localizedString("App ID"), text: $appID)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalization.localizedString("Access Token"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                SecureField(AppLocalization.localizedString("Paste access token"), text: $accessToken)
                    .textFieldStyle(.plain)
                    .settingsFieldSurface(minHeight: 34)
            }
        }
    }

    var doubaoDictionarySection: some View {
        RemoteProviderDoubaoDictionarySection(
            mode: $doubaoDictionaryMode,
            enableRequestHotwords: $doubaoEnableRequestHotwords,
            enableRequestCorrections: $doubaoEnableRequestCorrections
        )
    }

    var openAIChunkSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(AppLocalization.localizedString("Chunk Pseudo Realtime Preview"), isOn: $openAIChunkPseudoRealtimeEnabled)
                .toggleStyle(.switch)
            Text(AppLocalization.localizedString("Enable segmented OpenAI ASR preview during recording. This roughly doubles usage."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var searchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(AppLocalization.localizedString("Search"), isOn: $searchEnabled)
                .toggleStyle(.switch)

            if let provider = llmProviderForPicker {
                Text(provider.searchToggleDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    var actionSection: some View {
        SettingsDialogActionRow {
            if isTestingConnection {
                ProgressView()
                    .controlSize(.small)
            }
            Button(AppLocalization.localizedString("Test")) {
                testConnection()
            }
            .buttonStyle(SettingsPillButtonStyle())
            .disabled(isTestingConnection)

            if showsMeetingASRSection {
                Button(AppLocalization.localizedString("Test Meeting ASR")) {
                    testMeetingConnection()
                }
                .buttonStyle(SettingsPillButtonStyle())
                .disabled(isTestingConnection)
            }
        } trailing: {
            Button(AppLocalization.localizedString("Cancel")) {
                dismiss()
            }
            .buttonStyle(SettingsPillButtonStyle())
            .keyboardShortcut(.cancelAction)

            Button(AppLocalization.localizedString("Save")) {
                onSave(currentConfigurationSnapshot)
                dismiss()
            }
            .buttonStyle(SettingsPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
    }
}
