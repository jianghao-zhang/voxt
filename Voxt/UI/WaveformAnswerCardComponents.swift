import SwiftUI
import AppKit

struct RewriteConversationBottomVisibilityPreferenceKey: PreferenceKey {
    static var defaultValue = true

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

struct RewriteConversationBubble: View {
    let title: String
    let content: String
    let alignment: Alignment
    let isUser: Bool
    let isStreaming: Bool

    @State private var isHovered = false
    @State private var didCopy = false
    @State private var copyFeedbackToken = UUID()

    private var resolvedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "AI Answer") : trimmed
    }

    private var copyText: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else { return "" }
        guard !isUser, !trimmedTitle.isEmpty else { return trimmedContent }
        return "\(trimmedTitle)\n\n\(trimmedContent)"
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 7) {
            if isUser || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(resolvedTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(isUser ? 0.7 : (isStreaming ? 0.54 : 0.64)))
            }

            Group {
                if isStreaming {
                    Text(content)
                } else {
                    Text(content)
                        .textSelection(.enabled)
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(isStreaming ? 0.84 : 0.92))
            .frame(maxWidth: .infinity, alignment: alignment)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 340, alignment: alignment)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isUser ? .white.opacity(0.1) : .white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isUser ? .white.opacity(0.12) : .white.opacity(0.08), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if !isUser && isHovered {
                Button(action: copyToPasteboard) {
                    HStack(spacing: 4) {
                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9, weight: .semibold))
                        Text(didCopy ? String(localized: "Copied") : String(localized: "Copy"))
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.94))
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.black.opacity(0.74))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.trailing, 8)
                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .topTrailing)))
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    private func copyToPasteboard() {
        guard !copyText.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(copyText, forType: .string)
        copyFeedbackToken = UUID()
        let token = copyFeedbackToken
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard token == copyFeedbackToken else { return }
            didCopy = false
        }
    }
}

struct AnswerContinueButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(String(localized: "Continue"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(
                    Capsule()
                        .fill(isHovered ? .white.opacity(0.16) : .white.opacity(0.08))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(isHovered ? 0.18 : 0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(localized: "Continue")))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

struct AnswerConversationWaveView: View {
    let isRecording: Bool
    let isProcessing: Bool
    let audioLevel: Float
    let shouldAnimate: Bool

    @StateObject private var waveformState = RecentAudioWaveformState(
        barCount: 16,
        historyDuration: 0.9,
        framesPerSecond: 20,
        silenceFloor: 0.01,
        peakHoldFrames: 1,
        peakDecayFactor: 0.74,
        riseSmoothing: 0.82,
        fallSmoothing: 0.24
    )

    var body: some View {
        MeetingMiniWaveform(
            waveformState: waveformState,
            isSubdued: !isRecording || isProcessing
        )
        .scaleEffect(x: 0.84, y: 0.82, anchor: .leading)
        .onAppear {
            waveformState.setActive(shouldAnimate && isRecording && !isProcessing)
        }
        .onChange(of: shouldAnimate) {
            waveformState.setActive(shouldAnimate && isRecording && !isProcessing)
        }
        .onChange(of: isRecording) {
            waveformState.setActive(shouldAnimate && isRecording && !isProcessing)
        }
        .onChange(of: isProcessing) {
            waveformState.setActive(shouldAnimate && isRecording && !isProcessing)
        }
        .onChange(of: audioLevel) {
            waveformState.ingest(level: emphasizedWaveformInputLevel(audioLevel))
        }
        .onDisappear {
            waveformState.setActive(false)
        }
    }

    private func emphasizedWaveformInputLevel(_ level: Float) -> Float {
        let clamped = max(0, min(level, 1))
        let expanded = min(1.0, pow(Double(clamped), 0.72) * 1.24)
        return Float(expanded)
    }
}
