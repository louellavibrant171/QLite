import SwiftUI
import QLiteKit

/// The Data tab: filter bar, paged grid and row editing controls.
struct TableDataView: View {
    @ObservedObject var model: DatabaseModel
    @FocusState private var filterFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            content
            Divider()
            pager
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.filterFieldFocused) { _, focused in
            if focused {
                filterFocused = true
                model.filterFieldFocused = false
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let object = model.selectedObject, !model.selectedObjectIsBrowsable {
            ContentUnavailableView(object.name,
                                   systemImage: object.kind.symbolName,
                                   description: Text(L("data.notATable")))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let page = model.page, let details = model.details {
            DataGrid(columns: details.columns.map(\.name),
                     rows: page.rows.map { DataGridRow(id: $0.id, values: $0.values) },
                     selection: $model.selectedRowIDs,
                     sort: model.sort,
                     onSort: { model.toggleSort(column: $0) },
                     onOpenRow: { id in
                         if let row = page.rows.first(where: { $0.id == id }) {
                             model.activeSheet = .editRow(row)
                         }
                     },
                     contextActions: { ids in
                         AnyView(rowContextMenu(ids: ids, page: page))
                     })
        } else {
            ContentUnavailableView(L("data.noTable"),
                                   systemImage: "tablecells",
                                   description: Text(L("data.noTableHint")))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var isEditable: Bool { model.canEditRows }

    private var controls: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(.secondary)
                TextField(L("data.filterPlaceholder"), text: $model.filterText)
                    .textFieldStyle(.plain)
                    .focused($filterFocused)
                    .onSubmit { model.applyFilter() }
                if !model.filterText.isEmpty {
                    Button {
                        model.filterText = ""
                        model.applyFilter()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            .frame(maxWidth: 380)

            Menu {
                Button(L("data.noSorting")) { model.sort = nil; model.reloadPage() }
                Divider()
                ForEach(model.details?.columns ?? []) { column in
                    Button(column.name) { model.toggleSort(column: column.name) }
                }
            } label: {
                Label(sortLabel, systemImage: "arrow.up.arrow.down")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Spacer()

            Button {
                model.activeSheet = .editRow(nil)
            } label: {
                Label(L("data.insert"), systemImage: "plus")
            }
            .disabled(!isEditable)
            .help(model.dataStore?.editabilityReason ?? L("data.insertHelp"))

            Button {
                model.activeSheet = .editRow(model.selectedRows.first)
            } label: {
                Label(L("data.edit"), systemImage: "square.and.pencil")
            }
            .disabled(!isEditable || model.selectedRows.isEmpty)

            Button(role: .destructive) {
                confirmDeleteRows()
            } label: {
                Label(L("data.delete"), systemImage: "trash")
            }
            .disabled(!isEditable || model.selectedRows.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var sortLabel: String {
        guard let sort = model.sort else { return L("data.sort") }
        return "\(sort.column) \(sort.ascending ? "↑" : "↓")"
    }

    private var pager: some View {
        HStack(spacing: 10) {
            Button {
                model.previousPage()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(model.currentPageNumber <= 1)

            Text(L("data.page", model.currentPageNumber, model.pageCount))
                .font(.caption)
                .monospacedDigit()

            Button {
                model.nextPage()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(model.currentPageNumber >= model.pageCount)

            Spacer()

            Picker("Rows per page", selection: $model.pageSize) {
                ForEach([50, 100, 200, 500, 1000], id: \.self) { size in
                    Text(L("data.rowsPerPage", size)).tag(size)
                }
            }
            .labelsHidden()
            .fixedSize()
            .onChange(of: model.pageSize) { _, _ in model.goToPage(0) }
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func rowContextMenu(ids: Set<Int>, page: TablePage) -> some View {
        let rows = page.rows.filter { ids.contains($0.id) }
        Button(L("data.editRow")) {
            if let row = rows.first { model.activeSheet = .editRow(row) }
        }
        .disabled(rows.count != 1 || !isEditable)

        Button(L("data.copyCSV")) {
            let details = model.details
            let set = ResultSet(columnNames: details?.columns.map(\.name) ?? [],
                                rows: rows.map(\.values))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Exporter.string(from: set, format: .csv), forType: .string)
        }

        Divider()

        Button(L("data.deleteCount", rows.count), role: .destructive) {
            model.selectedRowIDs = ids
            confirmDeleteRows()
        }
        .disabled(!isEditable)
    }

    private func confirmDeleteRows() {
        let count = model.selectedRows.count
        guard count > 0 else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("data.confirmDelete.title", count)
        alert.informativeText = L("sidebar.confirmDrop.message")
        alert.addButton(withTitle: L("common.delete"))
        alert.addButton(withTitle: L("common.cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            model.deleteSelectedRows()
        }
    }
}
