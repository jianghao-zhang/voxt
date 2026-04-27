import AppKit
import SwiftUI
import Combine
import QuartzCore

@MainActor
final class VoxtNoteWindowManager {
    private let store: VoxtNoteStore
    private var controller: VoxtNoteWindowController?
    private var itemsCancellable: AnyCancellable?

    init(store: VoxtNoteStore) {
        self.store = store
        itemsCancellable = store.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                guard let self else { return }
                if items.allSatisfy(\.isCompleted) {
                    self.hide()
                }
            }
    }

    func show() {
        guard !store.incompleteItems.isEmpty else { return }
        let controller = resolvedController()
        controller.showWindow(nil)
        controller.window?.orderFrontRegardless()
        controller.updateFrame(animated: false)
    }

    func hide() {
        controller?.window?.orderOut(nil)
    }

    private func resolvedController() -> VoxtNoteWindowController {
        if let controller {
            return controller
        }

        let controller = VoxtNoteWindowController(
            store: store,
            onRequestClose: { [weak self] in
                self?.hide()
            }
        )
        self.controller = controller
        return controller
    }
}

@MainActor
private final class VoxtNoteWindowController: NSWindowController {
    private static let collapsedSize = NSSize(width: 304, height: 72)
    private static let expandedSize = NSSize(width: 304, height: 346)
    private static let leftInset: CGFloat = 20

    private var hostingView: NSHostingView<VoxtNoteWindowView>?
    private var isExpanded = false
    private let store: VoxtNoteStore
    private let onRequestClose: () -> Void

    init(store: VoxtNoteStore, onRequestClose: @escaping () -> Void) {
        self.store = store
        self.onRequestClose = onRequestClose

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.collapsedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        super.init(window: panel)

        let rootView = VoxtNoteWindowView(
            store: store,
            onComplete: { [weak self] noteID in
                _ = self?.store.updateCompletion(true, for: noteID)
            },
            onDelete: { [weak self] noteID in
                self?.store.delete(id: noteID)
            },
            onRequestClose: onRequestClose,
            onExpansionChanged: { [weak self] expanded in
                self?.setExpanded(expanded)
            }
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hostingView
        self.hostingView = hostingView
        updateFrame(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        updateFrame(animated: true)
    }

    func updateFrame(animated: Bool) {
        guard let window else { return }
        let size = isExpanded ? Self.expandedSize : Self.collapsedSize
        let frame = resolvedFrame(for: size)
        guard !frame.isEmpty else { return }

        if animated, window.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            }
        } else {
            window.setFrame(frame, display: true)
        }
    }

    private func resolvedFrame(for size: NSSize) -> CGRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? .zero
        guard !visibleFrame.isEmpty else {
            return CGRect(origin: .zero, size: size)
        }

        return CGRect(
            x: visibleFrame.minX + Self.leftInset,
            y: visibleFrame.minY + overlayScreenEdgeInset,
            width: size.width,
            height: size.height
        )
    }

    private var overlayScreenEdgeInset: CGFloat {
        let storedValue = UserDefaults.standard.object(forKey: AppPreferenceKey.overlayScreenEdgeInset) as? Int ?? 30
        return CGFloat(min(max(storedValue, 0), 120))
    }
}

private struct VoxtNoteWindowView: View {
    @ObservedObject var store: VoxtNoteStore
    let onComplete: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onRequestClose: () -> Void
    let onExpansionChanged: (Bool) -> Void

    @State private var isExpanded = false
    @State private var pendingCollapseTask: Task<Void, Never>?

    var body: some View {
        VStack {
            Spacer(minLength: 0)

            noteCard
                .frame(width: 304)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background(Color.clear)
        .onDisappear {
            pendingCollapseTask?.cancel()
            pendingCollapseTask = nil
        }
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isExpanded {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(store.incompleteItems) { item in
                            noteRow(item)
                        }
                    }
                    .padding(.bottom, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: 228, alignment: .topLeading)
                .padding(.bottom, 12)
            }

            barRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onHover(perform: handleHover)
    }

    private var barRow: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "note.text")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor.opacity(0.92))

            Text("\(store.incompleteItems.count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))

            Text(store.latestIncompleteItem?.title ?? "Notes")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onRequestClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 22, height: 22)
                    .background(
                        Circle()
                            .fill(.white.opacity(0.08))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func noteRow(_ item: VoxtNoteItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .lineLimit(1)

                        Spacer(minLength: 2)

                        if let createdAtText = RelativeNoteTimestampFormatter.noteCardTimestamp(for: item.createdAt) {
                            Text(createdAtText)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.44))
                                .lineLimit(1)
                        }
                    }

                    Text(item.text)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    copyToPasteboard(item.text)
                }

                Spacer(minLength: 2)

                NoteRowActionButton(systemName: "checkmark.circle", action: {
                    onComplete(item.id)
                })

                NoteRowActionButton(systemName: "trash", action: {
                    onDelete(item.id)
                })
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func handleHover(_ hovering: Bool) {
        guard !store.items.isEmpty else { return }
        pendingCollapseTask?.cancel()
        pendingCollapseTask = nil

        if hovering {
            withAnimation(.easeOut(duration: 0.16)) {
                isExpanded = true
            }
            onExpansionChanged(true)
            return
        }

        pendingCollapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
                isExpanded = false
            }
            onExpansionChanged(false)
        }
    }

    private func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

private struct NoteRowActionButton: View {
    let systemName: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(.white.opacity(isHovering ? 0.14 : 0.001))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.14)) {
                isHovering = hovering
            }
        }
    }
}
