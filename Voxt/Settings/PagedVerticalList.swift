import AppKit
import SwiftUI

private let pagedVerticalListColumnIdentifier = NSUserInterfaceItemIdentifier("PagedVerticalListColumn")
private let pagedVerticalListRowIdentifier = NSUserInterfaceItemIdentifier("PagedVerticalListRow")

private final class HostedTableCell: NSTableCellView {
    let hostingView: NSHostingView<AnyView>

    override init(frame frameRect: NSRect) {
        hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hostingView.setContentHuggingPriority(.defaultLow, for: .vertical)
        addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct PagedVerticalList<Item: Identifiable, Row: View>: NSViewRepresentable {
    let items: [Item]
    let totalCount: Int
    let rowHeight: CGFloat
    let rowSpacing: CGFloat
    let isLoading: Bool
    let onLoadMore: () -> Void
    @ViewBuilder let row: (Item) -> Row

    private var state: PagedVerticalListState<Item> {
        PagedVerticalListState(
            items: items,
            totalCount: totalCount,
            rowHeight: rowHeight,
            rowSpacing: rowSpacing,
            isLoading: isLoading,
            onLoadMore: onLoadMore,
            row: { item in AnyView(row(item)) }
        )
    }

    func makeCoordinator() -> PagedVerticalListCoordinator<Item> {
        PagedVerticalListCoordinator(state: state)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.gridStyleMask = []
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.rowHeight = rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: rowSpacing)
        tableView.usesAutomaticRowHeights = false
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        if #available(macOS 11.0, *) {
            tableView.style = .plain
        }

        let column = NSTableColumn(identifier: pagedVerticalListColumnIdentifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(state: state)
        guard let tableView = context.coordinator.tableView else { return }
        tableView.rowHeight = rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: rowSpacing)
        tableView.tableColumns.first?.width = scrollView.contentSize.width
        tableView.reloadData()
    }

}

final class PagedVerticalListCoordinator<Item: Identifiable>: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var state: PagedVerticalListState<Item>
    weak var tableView: NSTableView?
    weak var scrollView: NSScrollView?
    private var lastLoadMoreItemCount = -1
    private var lastKnownTotalCount = -1

    init(state: PagedVerticalListState<Item>) {
        self.state = state
        lastKnownTotalCount = state.totalCount
    }

    func update(state newState: PagedVerticalListState<Item>) {
        if newState.items.count < state.items.count || newState.totalCount != lastKnownTotalCount {
            lastLoadMoreItemCount = -1
        }
        state = newState
        lastKnownTotalCount = newState.totalCount
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        state.items.count + (showsFooter ? 1 : 0)
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        isFooterRow(row) ? 40 : state.rowHeight
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row rowIndex: Int) -> NSView? {
        if isFooterRow(rowIndex) {
            return hostedCell(
                in: tableView,
                rootView: AnyView(footerView)
            )
        }

        guard state.items.indices.contains(rowIndex) else { return nil }
        requestNextPageIfNeeded(displaying: rowIndex)
        let item = state.items[rowIndex]
        return hostedCell(
            in: tableView,
            rootView: AnyView(
                state.row(item)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: state.rowHeight)
            )
        )
    }

    private var showsFooter: Bool {
        state.isLoading || state.items.count < state.totalCount
    }

    private func isFooterRow(_ rowIndex: Int) -> Bool {
        showsFooter && rowIndex == state.items.count
    }

    @ViewBuilder
    private var footerView: some View {
        if state.isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 36)
        } else {
            Button(AppLocalization.localizedString("Load More")) {
                self.state.onLoadMore()
            }
            .buttonStyle(SettingsPillButtonStyle())
            .frame(maxWidth: .infinity, minHeight: 36)
        }
    }

    private func requestNextPageIfNeeded(displaying rowIndex: Int) {
        guard !state.isLoading, state.items.count < state.totalCount else { return }
        guard rowIndex >= max(0, state.items.count - 12) else { return }
        guard lastLoadMoreItemCount != state.items.count else { return }
        lastLoadMoreItemCount = state.items.count
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.state.onLoadMore()
        }
    }

    private func hostedCell(in tableView: NSTableView, rootView: AnyView) -> HostedTableCell {
        let cell = tableView.makeView(
            withIdentifier: pagedVerticalListRowIdentifier,
            owner: self
        ) as? HostedTableCell ?? HostedTableCell()
        cell.identifier = pagedVerticalListRowIdentifier
        cell.hostingView.rootView = rootView
        return cell
    }
}

struct PagedVerticalListState<Item: Identifiable> {
    let items: [Item]
    let totalCount: Int
    let rowHeight: CGFloat
    let rowSpacing: CGFloat
    let isLoading: Bool
    let onLoadMore: () -> Void
    let row: (Item) -> AnyView
}
