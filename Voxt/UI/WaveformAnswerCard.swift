import SwiftUI

struct WaveformAnswerCard: View {
    let title: String
    let content: String
    let answerInteractionMode: AnswerInteractionMode
    let conversationTurns: [RewriteConversationTurn]
    let streamingUserPromptText: String?
    let canInjectAnswer: Bool
    let canCopyAnswer: Bool
    let canContinueAnswer: Bool
    let canShowHistoryDetail: Bool
    let didCopyAnswer: Bool
    let isRecording: Bool
    let isProcessing: Bool
    let audioLevel: Float
    let shouldAnimateWave: Bool
    let streamingDraftPayload: RewriteAnswerPayload?
    let onInject: () -> Void
    let onContinue: () -> Void
    let onToggleConversationRecording: () -> Void
    let onShowDetail: () -> Void
    let onCopy: () -> Void
    let onClose: () -> Void

    @State private var isScrolledToConversationBottom = true
    @State private var wasScrolledToConversationBottom = true
    @State private var hasUnreadConversationMessages = false
    @State private var pendingScrollRequestToken = UUID()

    private let conversationBottomAnchorID = "rewrite-conversation-bottom-anchor"

    private var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "AI Answer") : trimmed
    }

    private var isConversationMode: Bool {
        answerInteractionMode == .conversation
    }

    private var continueAction: () -> Void {
        isConversationMode ? onToggleConversationRecording : onContinue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 8)

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)
                .padding(.bottom, 10)

            bodyContent
        }
    }

    @ViewBuilder
    private var header: some View {
        if isConversationMode {
            HStack(alignment: .center, spacing: 12) {
                TranscriptionModeIconView()
                    .frame(width: 20, height: 20)
                    .opacity(0.92)

                AnswerConversationWaveView(
                    isRecording: isRecording,
                    isProcessing: isProcessing,
                    audioLevel: audioLevel,
                    shouldAnimate: shouldAnimateWave
                )
                .frame(width: 96, height: 20, alignment: .leading)

                Spacer(minLength: 12)

                headerActions(showsContinue: canContinueAnswer)
            }
            .frame(minHeight: 24, alignment: .center)
        } else {
            HStack(alignment: .center, spacing: 12) {
                AnswerIconView()
                    .frame(width: 20, height: 20)

                Text(displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 12)

                headerActions(showsContinue: canContinueAnswer)
            }
            .frame(minHeight: 24, alignment: .center)
        }
    }

    @ViewBuilder
    private func headerActions(showsContinue: Bool) -> some View {
        if showsContinue {
            AnswerContinueButton(action: continueAction)
        }

        if canInjectAnswer {
            AnswerHeaderActionButton(
                accessibilityLabel: String(localized: "Inject into Current Input"),
                action: onInject,
                isEnabled: true
            ) {
                Image(systemName: "arrow.down.to.line.compact")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }

        if canShowHistoryDetail {
            AnswerHeaderActionButton(
                accessibilityLabel: String(localized: "Detail"),
                action: onShowDetail,
                isEnabled: true
            ) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }

        AnswerHeaderActionButton(
            accessibilityLabel: String(localized: "Copy Answer"),
            action: onCopy,
            isEnabled: canCopyAnswer
        ) {
            if didCopyAnswer {
                CopySuccessIconView()
                    .frame(width: 15, height: 15)
            } else {
                CopyIconView()
                    .frame(width: 15, height: 15)
            }
        }

        AnswerHeaderActionButton(
            accessibilityLabel: String(localized: "Close"),
            action: onClose,
            isEnabled: true
        ) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        if isConversationMode {
            conversationBody
        } else {
            singleResultBody
        }
    }

    private var singleResultBody: some View {
        ScrollView(.vertical, showsIndicators: true) {
            Text(content)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(.trailing, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: 220, alignment: .topLeading)
    }

    private var conversationBody: some View {
        GeometryReader { outerProxy in
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(conversationTurns) { turn in
                                if !turn.userPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    HStack {
                                        Spacer(minLength: 48)
                                        conversationBubble(
                                            title: String(localized: "You"),
                                            content: turn.userPromptText,
                                            alignment: .trailing,
                                            isUser: true
                                        )
                                    }
                                }

                                HStack {
                                    conversationBubble(
                                        title: assistantPayload(for: turn).title,
                                        content: assistantPayload(for: turn).content,
                                        alignment: .leading,
                                        isUser: false
                                    )
                                    Spacer(minLength: 48)
                                }
                                .id(turn.id)
                            }

                            if let streamingUserPromptText,
                               !streamingUserPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                HStack {
                                    Spacer(minLength: 48)
                                    conversationBubble(
                                        title: String(localized: "You"),
                                        content: streamingUserPromptText,
                                        alignment: .trailing,
                                        isUser: true,
                                        isStreaming: true
                                    )
                                }
                                .id("streaming-user-draft")
                            }

                            if let streamingDraftPayload,
                               !streamingDraftPayload.trimmedTitle.isEmpty || !streamingDraftPayload.trimmedContent.isEmpty || isProcessing {
                                HStack {
                                    conversationBubble(
                                        title: streamingDraftPayload.title,
                                        content: streamingDraftPayload.trimmedContent.isEmpty ? "…" : streamingDraftPayload.content,
                                        alignment: .leading,
                                        isUser: false,
                                        isStreaming: true
                                    )
                                    Spacer(minLength: 48)
                                }
                                .id("streaming-draft")
                            } else if isProcessing {
                                HStack {
                                    conversationBubble(
                                        title: "",
                                        content: "…",
                                        alignment: .leading,
                                        isUser: false,
                                        isStreaming: true
                                    )
                                    Spacer(minLength: 48)
                                }
                                .id("streaming-placeholder")
                            }

                            GeometryReader { geo in
                                Color.clear
                                    .preference(
                                        key: RewriteConversationBottomVisibilityPreferenceKey.self,
                                        value: abs(geo.frame(in: .named("RewriteConversationScroll")).maxY - outerProxy.size.height) < 36
                                    )
                            }
                            .frame(height: 1)
                            .id(conversationBottomAnchorID)
                        }
                        .padding(.trailing, 10)
                    }
                    .coordinateSpace(name: "RewriteConversationScroll")
                    .frame(maxWidth: .infinity, maxHeight: 220, alignment: .topLeading)
                    .onPreferenceChange(RewriteConversationBottomVisibilityPreferenceKey.self) { isVisible in
                        wasScrolledToConversationBottom = isScrolledToConversationBottom
                        isScrolledToConversationBottom = isVisible
                        if isVisible {
                            hasUnreadConversationMessages = false
                        }
                    }
                    .onAppear {
                        scrollConversationToBottom(using: proxy)
                    }
                    .onChange(of: conversationTurns.count) { oldValue, newValue in
                        guard newValue > oldValue else { return }
                        handleConversationMessagesUpdate(using: proxy, animated: true)
                    }
                    .onChange(of: isProcessing) { oldValue, newValue in
                        guard newValue, newValue != oldValue else { return }
                        handleConversationMessagesUpdate(using: proxy, forceScroll: true, animated: true)
                    }
                    .onChange(of: streamingDraftPayload?.content ?? "") { _, _ in
                        handleConversationMessagesUpdate(using: proxy, animated: false)
                    }
                    .onChange(of: streamingDraftPayload?.trimmedTitle ?? "") { oldValue, newValue in
                        guard oldValue != newValue else { return }
                        handleConversationMessagesUpdate(
                            using: proxy,
                            forceScroll: !newValue.isEmpty && oldValue.isEmpty,
                            animated: oldValue.isEmpty && !newValue.isEmpty
                        )
                    }
                    .onChange(of: streamingUserPromptText ?? "") { oldValue, newValue in
                        guard oldValue != newValue else { return }
                        handleConversationMessagesUpdate(
                            using: proxy,
                            forceScroll: !newValue.isEmpty && oldValue.isEmpty,
                            animated: oldValue.isEmpty && !newValue.isEmpty
                        )
                    }

                    if hasUnreadConversationMessages {
                        Button {
                            hasUnreadConversationMessages = false
                            scrollConversationToBottom(using: proxy)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 10, weight: .semibold))
                                Text(String(localized: "Latest"))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(.white.opacity(0.92))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(.black.opacity(0.78))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                        .padding(.bottom, 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 220, alignment: .topLeading)
    }

    private func handleConversationMessagesUpdate(
        using proxy: ScrollViewProxy,
        forceScroll: Bool = false,
        animated: Bool = false
    ) {
        if forceScroll || isScrolledToConversationBottom || wasScrolledToConversationBottom {
            hasUnreadConversationMessages = false
            scrollConversationToBottom(using: proxy, animated: animated)
        } else {
            hasUnreadConversationMessages = true
        }
    }

    private func scrollConversationToBottom(using proxy: ScrollViewProxy, animated: Bool = true) {
        let token = UUID()
        pendingScrollRequestToken = token
        DispatchQueue.main.async {
            guard token == pendingScrollRequestToken else { return }
            if animated {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(conversationBottomAnchorID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(conversationBottomAnchorID, anchor: .bottom)
            }
        }
    }

    private func assistantPayload(for turn: RewriteConversationTurn) -> RewriteAnswerPayload {
        let rawPayload = RewriteAnswerPayload(
            title: turn.resultTitle,
            content: turn.resultContent
        )
        if rawPayload.trimmedTitle.isEmpty { return rawPayload }
        return RewriteAnswerPayloadParser.normalize(rawPayload)
    }

    private func conversationBubble(
        title: String,
        content: String,
        alignment: Alignment,
        isUser: Bool,
        isStreaming: Bool = false
    ) -> some View {
        RewriteConversationBubble(
            title: title,
            content: content,
            alignment: alignment,
            isUser: isUser,
            isStreaming: isStreaming
        )
    }
}
struct AnswerHeaderActionButton<Label: View>: View {
    let accessibilityLabel: String
    let action: () -> Void
    let isEnabled: Bool
    @ViewBuilder let label: () -> Label

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: 24, height: 24)
                .opacity(isEnabled ? 1 : 0.42)
                .background(
                    Circle()
                        .fill(isEnabled ? (isHovered ? .white.opacity(0.16) : .white.opacity(0.08)) : .white.opacity(0.04))
                )
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(isEnabled && isHovered ? 0.18 : 0), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(accessibilityLabel))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}
