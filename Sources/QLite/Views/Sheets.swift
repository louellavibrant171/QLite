import SwiftUI
import UniformTypeIdentifiers
import QLiteKit

// MARK: - Create table

/// Builds a `CREATE TABLE` statement from a list of column definitions.
struct NewTableView: View {
    @ObservedObject var model: DatabaseModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var withoutRowID = false
    @State private var columns: [ColumnDefinition] = [
        ColumnDefinition(name: "id", type: "INTEGER", isPrimaryKey: true, isAutoIncrement: true)
    ]

    var body: some View {
        SheetLayout(title: L("sheet.newTable"),
                    confirmTitle: L("sheet.create"),
                    isConfirmEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty && !columns.isEmpty,
                    onCancel: { dismiss() },
                    onConfirm: {
                        model.createTable(name: name, columns: columns, withoutRowID: withoutRowID)
                        dismiss()
                    }) {
            Form {
                TextField(L("sheet.tableName"), text: $name)
                Toggle(L("sheet.withoutRowID"), isOn: $withoutRowID)
            }
            .formStyle(.grouped)
            .frame(height: 90)

            ColumnListEditor(columns: $columns)
        }
        .frame(width: 640, height: 480)
    }
}

/// Editable list of column definitions shared by the create-table sheet.
struct ColumnListEditor: View {
    @Binding var columns: [ColumnDefinition]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("sheet.columns")).font(.headline)
                Spacer()
                Button {
                    columns.append(ColumnDefinition(name: "column_\(columns.count + 1)"))
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            List {
                ForEach($columns) { $column in
                    HStack(spacing: 6) {
                        TextField(L("sheet.name"), text: $column.name)
                            .frame(minWidth: 110)
                        Picker("", selection: $column.type) {
                            ForEach(ColumnDefinition.commonTypes, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                        Toggle("PK", isOn: $column.isPrimaryKey)
                        Toggle("NN", isOn: $column.isNotNull)
                        Toggle("UQ", isOn: $column.isUnique)
                        Toggle("AI", isOn: $column.isAutoIncrement)
                            .disabled(!column.isPrimaryKey || column.type != "INTEGER")
                        Button {
                            columns.removeAll { $0.id == column.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                    .toggleStyle(.checkbox)
                    .font(.callout)
                }
                .onMove { columns.move(fromOffsets: $0, toOffset: $1) }
            }
        }
    }
}

// MARK: - Add column

struct AddColumnView: View {
    @ObservedObject var model: DatabaseModel
    let table: String
    @Environment(\.dismiss) private var dismiss
    @State private var column = ColumnDefinition(name: "new_column")

    var body: some View {
        SheetLayout(title: L("sheet.addColumnTo", table),
                    confirmTitle: L("sheet.add"),
                    isConfirmEnabled: !column.name.trimmingCharacters(in: .whitespaces).isEmpty,
                    onCancel: { dismiss() },
                    onConfirm: {
                        model.addColumn(column, to: table)
                        dismiss()
                    }) {
            Form {
                TextField(L("sheet.name"), text: $column.name)
                Picker(L("sheet.type"), selection: $column.type) {
                    ForEach(ColumnDefinition.commonTypes, id: \.self) { Text($0).tag($0) }
                }
                Toggle(L("sheet.notNull"), isOn: $column.isNotNull)
                Toggle(L("sheet.unique"), isOn: $column.isUnique)
                TextField(L("sheet.defaultValue"), text: $column.defaultValue)
                Text(L("sheet.notNullHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
        }
        .frame(width: 460, height: 340)
    }
}

// MARK: - Create index

struct CreateIndexView: View {
    @ObservedObject var model: DatabaseModel
    let table: String
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var unique = false
    @State private var selected: Set<String> = []

    private var availableColumns: [ColumnInfo] { model.details?.columns ?? [] }

    var body: some View {
        SheetLayout(title: L("sheet.createIndexOn", table),
                    confirmTitle: L("sheet.create"),
                    isConfirmEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty && !selected.isEmpty,
                    onCancel: { dismiss() },
                    onConfirm: {
                        let ordered = availableColumns.map(\.name).filter { selected.contains($0) }
                        model.createIndex(name: name, table: table, columns: ordered, unique: unique)
                        dismiss()
                    }) {
            Form {
                TextField(L("sheet.indexName"), text: $name)
                Toggle(L("sheet.unique"), isOn: $unique)
            }
            .formStyle(.grouped)
            .frame(height: 90)

            List(availableColumns, selection: $selected) { column in
                Toggle(isOn: Binding(
                    get: { selected.contains(column.name) },
                    set: { isOn in
                        if isOn { selected.insert(column.name) } else { selected.remove(column.name) }
                    })
                ) {
                    Text(column.name) + Text("  \(column.type)").foregroundColor(.secondary)
                }
                .toggleStyle(.checkbox)
            }
        }
        .frame(width: 460, height: 420)
        .onAppear {
            if name.isEmpty { name = "idx_\(table)" }
        }
    }
}

// MARK: - Rename

struct RenameView: View {
    let title: String
    let currentName: String
    let onRename: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var newName: String = ""

    var body: some View {
        SheetLayout(title: title,
                    confirmTitle: L("sheet.rename"),
                    isConfirmEnabled: !newName.trimmingCharacters(in: .whitespaces).isEmpty,
                    onCancel: { dismiss() },
                    onConfirm: {
                        onRename(newName)
                        dismiss()
                    }) {
            Form {
                TextField(L("sheet.newName"), text: $newName)
            }
            .formStyle(.grouped)
        }
        .frame(width: 420, height: 170)
        .onAppear { newName = currentName }
    }
}

// MARK: - Row editor

/// Inserts a new row or edits every column of an existing one.
struct RowEditorView: View {
    @ObservedObject var model: DatabaseModel
    let row: TableRowData?
    @Environment(\.dismiss) private var dismiss

    @State private var fields: [String: String] = [:]
    @State private var nulls: Set<String> = []

    private var columns: [ColumnInfo] { model.details?.columns ?? [] }

    var body: some View {
        SheetLayout(title: row == nil ? L("sheet.insertRow") : L("sheet.editRow"),
                    confirmTitle: row == nil ? L("sheet.insert") : L("sheet.save"),
                    isConfirmEnabled: true,
                    onCancel: { dismiss() },
                    onConfirm: { save() }) {
            List(columns) { column in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(column.name).fontWeight(.medium)
                        Text(column.type.isEmpty ? "ANY" : column.type)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if column.isPrimaryKey {
                            Text("PK").font(.caption2).padding(.horizontal, 4)
                                .background(.tint.opacity(0.2), in: Capsule())
                        }
                        Spacer()
                        Toggle("NULL", isOn: Binding(
                            get: { nulls.contains(column.name) },
                            set: { isNull in
                                if isNull { nulls.insert(column.name) } else { nulls.remove(column.name) }
                            })
                        )
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .disabled(column.isNotNull)
                    }
                    TextField("", text: Binding(
                        get: { fields[column.name] ?? "" },
                        set: { fields[column.name] = $0 })
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(nulls.contains(column.name))
                }
                .padding(.vertical, 3)
            }
        }
        .frame(width: 520, height: 480)
        .onAppear(perform: load)
    }

    private func load() {
        guard let row else {
            for column in columns where !column.isNotNull {
                nulls.insert(column.name)
            }
            return
        }
        for (index, column) in columns.enumerated() where index < row.values.count {
            let value = row.values[index]
            if value.isNull {
                nulls.insert(column.name)
            } else {
                fields[column.name] = value.editableString
            }
        }
    }

    private func save() {
        var values: [String: SQLValue] = [:]
        for column in columns {
            if nulls.contains(column.name) {
                values[column.name] = .null
            } else if let text = fields[column.name] {
                values[column.name] = SQLValue.coerce(text, declaredType: column.type)
            }
        }
        if let row {
            model.updateRow(row, values: values)
        } else {
            model.insertRow(values: values)
        }
        dismiss()
    }
}

// MARK: - Export

struct ExportView: View {
    let result: ResultSet
    let suggestedName: String
    @Environment(\.dismiss) private var dismiss
    @State private var format: Exporter.Format = .csv

    var body: some View {
        SheetLayout(title: L("sheet.exportRows", result.rows.count),
                    confirmTitle: L("sheet.saveAs"),
                    isConfirmEnabled: true,
                    onCancel: { dismiss() },
                    onConfirm: { save() }) {
            Form {
                Picker(L("sheet.format"), selection: $format) {
                    ForEach(Exporter.Format.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.radioGroup)
            }
            .formStyle(.grouped)
        }
        .frame(width: 400, height: 260)
    }

    private func save() {
        let panel = NSSavePanel()
        panel.prompt = L("panel.export")
        panel.nameFieldLabel = L("panel.saveAsLabel")
        panel.nameFieldStringValue = "\(suggestedName).\(format.fileExtension)"
        if let type = UTType(filenameExtension: format.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = Exporter.string(from: result, format: format, tableName: suggestedName)
        try? text.data(using: .utf8)?.write(to: url)
        dismiss()
    }
}

// MARK: - Shared chrome

/// Title bar plus Cancel/Confirm footer shared by every sheet.
struct SheetLayout<Content: View>: View {
    let title: String
    let confirmTitle: String
    let isConfirmEnabled: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                Spacer()
                Button(L("common.cancel"), role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isConfirmEnabled)
            }
            .padding(12)
        }
    }
}
