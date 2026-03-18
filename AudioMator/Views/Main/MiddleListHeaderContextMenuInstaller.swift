import AppKit
import SwiftUI

struct MiddleListHeaderContextMenuInstaller: NSViewRepresentable {
    @Binding var visibleColumns: Set<MiddleListColumn>

    func makeCoordinator() -> Coordinator {
        Coordinator(visibleColumns: $visibleColumns)
    }

    func makeNSView(context: Context) -> NSView {
        let view = IntrospectionView()
        view.coordinator = context.coordinator
        DispatchQueue.main.async {
            context.coordinator.installMenuIfPossible(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.visibleColumns = $visibleColumns

        guard let view = nsView as? IntrospectionView else { return }
        view.coordinator = context.coordinator

        DispatchQueue.main.async {
            context.coordinator.installMenuIfPossible(from: view)
        }
    }
}

private final class IntrospectionView: NSView {
    weak var coordinator: MiddleListHeaderContextMenuInstaller.Coordinator?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            coordinator?.installMenuIfPossible(from: self)
        }
    }
}

extension MiddleListHeaderContextMenuInstaller {
    final class Coordinator: NSObject {
        var visibleColumns: Binding<Set<MiddleListColumn>>

        private weak var headerView: NSTableHeaderView?

        init(visibleColumns: Binding<Set<MiddleListColumn>>) {
            self.visibleColumns = visibleColumns
        }

        func installMenuIfPossible(from view: NSView) {
            guard let tableView = findTableView(from: view) else { return }
            guard let headerView = tableView.headerView else { return }

            self.headerView = headerView
            headerView.menu = makeMenu()
        }

        @objc
        private func toggleColumn(_ sender: NSMenuItem) {
            guard
                let rawValue = sender.representedObject as? String,
                let column = MiddleListColumn(rawValue: rawValue)
            else {
                return
            }

            var updated = visibleColumns.wrappedValue
            if updated.contains(column) {
                guard updated.count > 1 else { return }
                updated.remove(column)
            } else {
                updated.insert(column)
            }

            visibleColumns.wrappedValue = updated
            headerView?.menu = makeMenu()
        }

        private func makeMenu() -> NSMenu {
            let menu = NSMenu(title: "Columns")
            menu.autoenablesItems = false

            let visible = visibleColumns.wrappedValue

            for column in MiddleListColumn.allCases {
                let item = NSMenuItem(
                    title: column.displayName,
                    action: #selector(toggleColumn(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = column.rawValue
                item.state = visible.contains(column) ? .on : .off
                item.isEnabled = visible.count > 1 || !visible.contains(column)
                menu.addItem(item)
            }

            return menu
        }

        private func findTableView(from view: NSView) -> NSTableView? {
            var candidate: NSView? = view

            while let current = candidate {
                if let tableView = current as? NSTableView {
                    return tableView
                }

                if let scrollView = current as? NSScrollView,
                   let tableView = scrollView.documentView as? NSTableView {
                    return tableView
                }

                if let tableView = findTableViewInDescendants(of: current) {
                    return tableView
                }

                candidate = current.superview
            }

            return nil
        }

        private func findTableViewInDescendants(of view: NSView) -> NSTableView? {
            for subview in view.subviews {
                if let tableView = subview as? NSTableView {
                    return tableView
                }

                if let scrollView = subview as? NSScrollView,
                   let tableView = scrollView.documentView as? NSTableView {
                    return tableView
                }

                if let tableView = findTableViewInDescendants(of: subview) {
                    return tableView
                }
            }

            return nil
        }
    }
}
