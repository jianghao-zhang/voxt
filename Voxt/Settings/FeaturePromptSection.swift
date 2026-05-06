import SwiftUI

struct FeaturePromptSection: View {
    let title: String
    @Binding var text: String
    let defaultText: String
    let variables: [PromptTemplateVariableDescriptor]
    let persistChanges: () -> Void
    @State private var coordinator: FeaturePromptDraftCoordinator
    @State private var pendingSaveTask: Task<Void, Never>?

    init(
        title: String,
        text: Binding<String>,
        defaultText: String,
        variables: [PromptTemplateVariableDescriptor],
        persistChanges: @escaping () -> Void
    ) {
        self.title = title
        _text = text
        self.defaultText = defaultText
        self.variables = variables
        self.persistChanges = persistChanges
        _coordinator = State(initialValue: FeaturePromptDraftCoordinator(text: text.wrappedValue))
    }

    var body: some View {
        ResettablePromptSection(
            title: featureSettingsLocalizedKey(title),
            text: Binding(
                get: { coordinator.draft },
                set: { coordinator.updateDraft($0) }
            ),
            defaultText: defaultText,
            variables: variables,
            promptHeight: 196,
            onTextChange: schedulePersist,
            onFocusChange: handleFocusChange
        )
        .onChange(of: text) { _, newValue in
            coordinator.syncExternalText(newValue)
        }
        .onDisappear {
            flushPendingChanges()
        }
    }

    private func schedulePersist(_ newValue: String) {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                flushPendingChanges(expectedText: newValue)
            }
        }
    }

    private func handleFocusChange(_ isFocused: Bool) {
        guard !isFocused else { return }
        flushPendingChanges()
    }

    private func flushPendingChanges(expectedText: String? = nil) {
        pendingSaveTask?.cancel()
        pendingSaveTask = nil

        if let persistedText = coordinator.takePendingPersist(expectedText: expectedText) {
            text = persistedText
            persistChanges()
        }
    }
}
