import SwiftUI
import QLiteKit

/// The Structure tab: columns, foreign keys and indexes of the selected table.
struct StructureView: View {
    @ObservedObject var model: DatabaseModel

    var body: some View {
        if let object = model.selectedObject, !model.selectedObjectIsBrowsable {
            ContentUnavailableView(object.name,
                                   systemImage: object.kind.symbolName,
                                   description: Text(L("data.notATable")))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let details = model.details {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    columnsSection(details)
                    if !details.foreignKeys.isEmpty { foreignKeysSection(details) }
                    indexesSection(details)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(L("structure.noObject"),
                                   systemImage: "list.bullet.rectangle",
                                   description: Text(L("structure.noObjectHint")))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Columns

    private func columnsSection(_ details: TableDetails) -> some View {
        Section {
            VStack(spacing: 0) {
                header([L("structure.name"), L("structure.type"), L("structure.notNull"), L("structure.default"), L("structure.key")])
                ForEach(details.columns) { column in
                    HStack(spacing: 0) {
                        cell(column.name, weight: .medium)
                        cell(column.type.isEmpty ? L("common.none") : column.type)
                        cell(column.isNotNull ? L("common.yes") : L("common.none"))
                        cell(column.defaultValue ?? L("common.none"))
                        cell(column.isPrimaryKey ? "PK \(column.primaryKeyPosition)" : L("common.none"))
                        Menu {
                            Button(L("sidebar.rename")) { renameColumn(column, in: details) }
                            Button(L("structure.dropColumn"), role: .destructive) { dropColumn(column, in: details) }
                                .disabled(details.object.kind != .table)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 34)
                        .disabled(details.object.kind != .table)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        } header: {
            HStack {
                Text(L("structure.columns")).font(.headline)
                Spacer()
                if details.object.kind == .table {
                    Button {
                        model.activeSheet = .addColumn(details.object.name)
                    } label: {
                        Label(L("structure.addColumn"), systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: - Foreign keys

    private func foreignKeysSection(_ details: TableDetails) -> some View {
        Section {
            VStack(spacing: 0) {
                header([L("structure.column"), L("structure.references"), L("structure.onUpdate"), L("structure.onDelete")])
                ForEach(details.foreignKeys) { key in
                    HStack(spacing: 0) {
                        cell(key.column, weight: .medium)
                        cell("\(key.referencedTable).\(key.referencedColumn)")
                        cell(key.onUpdate)
                        cell(key.onDelete)
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        } header: {
            Text(L("structure.foreignKeys")).font(.headline)
        }
    }

    // MARK: - Indexes

    private func indexesSection(_ details: TableDetails) -> some View {
        Section {
            if details.indexes.isEmpty {
                Text(L("structure.noIndexes"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    header([L("structure.name"), L("structure.columnsHeader"), L("structure.unique"), L("structure.origin")])
                    ForEach(details.indexes) { index in
                        HStack(spacing: 0) {
                            cell(index.name, weight: .medium)
                            cell(index.columns.joined(separator: ", "))
                            cell(index.isUnique ? L("common.yes") : L("common.none"))
                            cell(index.originDescription)
                            Button {
                                dropIndex(index)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .frame(width: 34)
                            .disabled(index.origin != "c")
                            .help(index.origin == "c" ? L("structure.dropIndexHelp") : L("structure.constraintIndexHelp"))
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            }
        } header: {
            HStack {
                Text(L("structure.indexes")).font(.headline)
                Spacer()
                if details.object.kind == .table {
                    Button {
                        model.activeSheet = .createIndex(details.object.name)
                    } label: {
                        Label(L("structure.createIndex"), systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    // MARK: - Building blocks

    private func header(_ titles: [String]) -> some View {
        HStack(spacing: 0) {
            ForEach(titles, id: \.self) { title in
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
    }

    private func cell(_ text: String, weight: Font.Weight = .regular) -> some View {
        Text(text)
            .fontWeight(weight)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
            .textSelection(.enabled)
    }

    // MARK: - Actions

    private func renameColumn(_ column: ColumnInfo, in details: TableDetails) {
        guard let newName = prompt(title: L("structure.renameColumn"),
                                   message: L("structure.renameColumn.message", column.name),
                                   value: column.name) else { return }
        model.renameColumn(in: details.object.name, from: column.name, to: newName)
    }

    private func dropColumn(_ column: ColumnInfo, in details: TableDetails) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("structure.confirmDropColumn.title", column.name)
        alert.informativeText = L("structure.confirmDropColumn.message")
        alert.addButton(withTitle: L("common.drop"))
        alert.addButton(withTitle: L("common.cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            model.dropColumn(in: details.object.name, name: column.name)
        }
    }

    private func dropIndex(_ index: IndexInfo) {
        let alert = NSAlert()
        alert.messageText = L("structure.confirmDropIndex.title", index.name)
        alert.addButton(withTitle: L("common.drop"))
        alert.addButton(withTitle: L("common.cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            model.drop(SchemaObject(kind: .index, name: index.name, tableName: "", sql: ""))
        }
    }

    /// A one-field text prompt, which AppKit provides more cheaply than a SwiftUI sheet.
    private func prompt(title: String, message: String, value: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L("common.ok"))
        alert.addButton(withTitle: L("common.cancel"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
