import SwiftUI
import QLiteKit

/// Root view of a database window: sidebar, detail pane, status bar and sheets.
struct DatabaseView: View {
    @ObservedObject var model: DatabaseModel
    @ObservedObject private var preferences = Preferences.shared
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
        } detail: {
            VStack(spacing: 0) {
                DetailHeader(model: model)
                Divider()
                detailContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                StatusBar(model: model)
            }
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $model.activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        // Rebuild the whole tree when the language changes so every L(...) is re-evaluated.
        .id(preferences.language)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch model.tab {
        case .data:
            TableDataView(model: model)
        case .structure:
            StructureView(model: model)
        case .ddl:
            DDLView(model: model)
        case .query:
            QueryView(model: model)
        case .info:
            DatabaseInfoView(model: model)
        }
    }

    @ViewBuilder
    private func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .newTable:
            NewTableView(model: model)
        case .addColumn(let table):
            AddColumnView(model: model, table: table)
        case .renameTable(let table):
            RenameView(title: L("sheet.renameTable"), currentName: table) { newName in
                model.renameTable(from: table, to: newName)
            }
        case .createIndex(let table):
            CreateIndexView(model: model, table: table)
        case .editRow(let row):
            RowEditorView(model: model, row: row)
        case .export(let result, let name):
            ExportView(result: result, suggestedName: name)
        }
    }
}

/// Object title, tab picker and the primary actions for the current object.
struct DetailHeader: View {
    @ObservedObject var model: DatabaseModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(model.details?.object.name ?? model.databaseName)
                    .font(.headline)
                    .lineLimit(1)
                if let details = model.details, model.selectedObjectIsBrowsable {
                    Text(L("header.summary", L("kind.\(details.object.kind.rawValue)"), details.columns.count, details.rowCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let object = model.selectedObject {
                    Text(L("kind.\(object.kind.rawValue)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(model.url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 8)

            Picker("", selection: $model.tab) {
                ForEach(DetailTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.symbolName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Button {
                model.reloadSchema()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help(L("header.refresh"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Status text plus the inline error banner.
struct StatusBar: View {
    @ObservedObject var model: DatabaseModel

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.callout)
                        .textSelection(.enabled)
                        .lineLimit(3)
                    Spacer()
                    Button(L("common.dismiss")) { model.errorMessage = nil }
                        .buttonStyle(.link)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.12))
            }
            HStack {
                Text(model.status.isEmpty ? model.databaseName : model.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Spacer()
                Text("SQLite \(Database.libraryVersion)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
    }
}
