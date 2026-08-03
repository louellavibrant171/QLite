import SwiftUI
import QLiteKit

/// A row rendered by `DataGrid`, decoupled from where the values came from.
struct DataGridRow: Identifiable, Hashable {
    let id: Int
    var values: [SQLValue]
}

/// A spreadsheet-style grid used for both table contents and query results.
struct DataGrid: View {
    let columns: [String]
    let rows: [DataGridRow]
    @Binding var selection: Set<Int>
    var sort: ColumnSort?
    var onSort: ((String) -> Void)?
    var onOpenRow: ((Int) -> Void)?
    var contextActions: ((Set<Int>) -> AnyView)?

    var body: some View {
        if columns.isEmpty {
            ContentUnavailableView(L("data.noColumns"), systemImage: "tablecells")
        } else {
            Table(rows, selection: $selection) {
                TableColumnForEach(Array(columns.indices), id: \.self) { index in
                    TableColumn(header(for: index)) { row in
                        CellView(value: index < row.values.count ? row.values[index] : .null)
                    }
                    .width(min: 64, ideal: 150)
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .monospacedDigit()
            .contextMenu(forSelectionType: Int.self) { ids in
                if let contextActions {
                    contextActions(ids)
                }
            } primaryAction: { ids in
                if let id = ids.first { onOpenRow?(id) }
            }
        }
    }

    /// Column titles carry the sort indicator, since `TableColumn` headers are plain text.
    private func header(for index: Int) -> String {
        let name = columns[index]
        guard let sort, sort.column == name else { return name }
        return "\(name) \(sort.ascending ? "▲" : "▼")"
    }
}

/// Renders one value, distinguishing NULLs and blobs from ordinary content.
struct CellView: View {
    let value: SQLValue

    var body: some View {
        switch value {
        case .null:
            Text("NULL")
                .foregroundStyle(.tertiary)
                .italic()
        case .blob:
            Text(value.displayString)
                .foregroundStyle(.secondary)
                .font(.system(.body, design: .monospaced))
        case .integer, .real:
            Text(value.displayString)
                .font(.system(.body, design: .monospaced))
        case .text(let text):
            Text(text.replacingOccurrences(of: "\n", with: "⏎"))
                .lineLimit(1)
                .help(text.count > 60 ? text : "")
        }
    }
}
