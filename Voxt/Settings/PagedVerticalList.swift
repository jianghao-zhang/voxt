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

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
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
        context.coordinator.update(parent: self)
        guard let tableView = context.coordinator.tableView else { return }
        tableView.rowHeight = rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: rowSpacing)
        tableView.tableColumns.first?.width = scrollView.contentSize.width
        tableView.reloadData()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: PagedVerticalList
        weak var tableView: NSTableView?
        weak var scrollView: NSScrollView?
        private var lastLoadMoreItemCount = -1
        private var lastKnownTotalCount = -1

        init(parent: PagedVerticalList) {
            self.parent = parent
            lastKnownTotalCount = parent.totalCount
        }

        func update(parent newParent: PagedVerticalList) {
            if newParent.items.count < parent.items.count || newParent.totalCount != lastKnownTotalCount {
                lastLoadMoreItemCount = -1
            }
            parent = newParent
            lastKnownTotalCount = newParent.totalCount
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            parent.items.count + (showsFooter ? 1 : 0)
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            isFooterRow(row) ? 40 : parent.rowHeight
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row rowIndex: Int) -> NSView? {
            if isFooterRow(rowIndex) {
                return hostedCell(
                    in: tableView,
                    rootView: AnyView(footerView)
                )
            }

            guard parent.items.indices.contains(rowIndex) else { return nil }
            requestNextPageIfNeeded(displaying: rowIndex)
            let item = parent.items[rowIndex]
            return hostedCell(
                in: tableView,
                rootView: AnyView(
                    parent.row(item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: parent.rowHeight)
                )
            )
        }

        private var showsFooter: Bool {
            parent.isLoading || parent.items.count < parent.totalCount
        }

        private func isFooterRow(_ rowIndex: Int) -> Bool {
            showsFooter && rowIndex == parent.items.count
        }

        @ViewBuilder
        private var footerView: some View {
            if parent.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 36)
            } else {
                Button(AppLocalization.localizedString("Load More")) {
                    self.parent.onLoadMore()
                }
                .buttonStyle(SettingsPillButtonStyle())
                .frame(maxWidth: .infinity, minHeight: 36)
            }
        }

        private func requestNextPageIfNeeded(displaying rowIndex: Int) {
            guard !parent.isLoading, parent.items.count < parent.totalCount else { return }
            guard rowIndex >= max(0, parent.items.count - 12) else { return }
            guard lastLoadMoreItemCount != parent.items.count else { return }
            lastLoadMoreItemCount = parent.items.count
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.parent.onLoadMore()
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
}
