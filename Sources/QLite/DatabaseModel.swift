import Foundation
import Combine
import QLiteKit

/// Detail panes shown next to the sidebar.
enum DetailTab: String, CaseIterable, Identifiable {
    case data
    case structure
    case ddl
    case query
    case info

    var id: String { rawValue }

    /// Localized title shown in the tab picker and the View menu.
    var title: String { L("tab.\(rawValue)") }

    var symbolName: String {
        switch self {
        case .data: return "tablecells"
        case .structure: return "list.bullet.rectangle"
        case .ddl: return "curlybraces"
        case .query: return "terminal"
        case .info: return "info.circle"
        }
    }
}

/// Modal editors presented over the main window.
enum ActiveSheet: Identifiable {
    case newTable
    case addColumn(String)
    case renameTable(String)
    case createIndex(String)
    case editRow(TableRowData?)
    case export(ResultSet, String)

    var id: String {
        switch self {
        case .newTable: return "newTable"
        case .addColumn(let table): return "addColumn:\(table)"
        case .renameTable(let table): return "renameTable:\(table)"
        case .createIndex(let table): return "createIndex:\(table)"
        case .editRow(let row): return "editRow:\(row?.id.description ?? "new")"
        case .export(_, let name): return "export:\(name)"
        }
    }
}

/// View model backing one database window: owns the connection and every user action.
@MainActor
final class DatabaseModel: ObservableObject {
    let url: URL
    private let database: Database
    private let reader: SchemaReader
    private let schemaEditor: SchemaEditor
    private let queryRunner: QueryRunner

    // Schema
    @Published private(set) var objects: [SchemaObject] = []
    @Published var selectedObjectID: SchemaObject.ID?
    @Published private(set) var details: TableDetails?

    // Data browsing
    @Published private(set) var page: TablePage?
    @Published var pageSize = 200
    @Published private(set) var pageIndex = 0
    @Published var sort: ColumnSort?
    @Published var filterText = ""
    @Published var selectedRowIDs: Set<Int> = []

    // Query editor
    @Published var queryText = "SELECT 1;"
    @Published private(set) var execution: QueryExecution?

    // UI state
    @Published var tab: DetailTab = .data
    @Published var activeSheet: ActiveSheet?
    @Published var status = ""
    @Published var errorMessage: String?
    @Published var filterFieldFocused = false

    init(url: URL) throws {
        self.url = url
        // With sidecar reading turned off the file is opened `immutable`: SQLite then ignores
        // any -wal/-journal and never writes, which also makes the database read-only here.
        let readSidecars = Preferences.shared.readSidecars
        self.database = try Database(url: url,
                                     mode: readSidecars ? .readWrite : .immutable,
                                     createIfMissing: readSidecars)
        self.reader = SchemaReader(database: database)
        self.schemaEditor = SchemaEditor(database: database)
        self.queryRunner = QueryRunner(database: database)
        reloadSchema(selectFirst: true)
    }

    deinit { database.close() }

    var databaseName: String { url.lastPathComponent }

    /// Indexes and triggers have neither columns nor rows, so the Data and Structure tabs
    /// show an explanation rather than empty tables.
    var selectedObjectIsBrowsable: Bool {
        guard let kind = selectedObject?.kind else { return false }
        return kind == .table || kind == .view
    }

    var selectedObject: SchemaObject? {
        objects.first { $0.id == selectedObjectID }
    }

    /// False when the connection itself cannot write, regardless of the selected object.
    var isReadOnlyDatabase: Bool { database.isReadOnly }

    /// Whether the rows currently on screen can be inserted, edited or deleted.
    var canEditRows: Bool { !database.isReadOnly && (dataStore?.isEditable ?? false) }

    var dataStore: TableDataStore? {
        details.map { TableDataStore(database: database, details: $0) }
    }

    var objectsByKind: [(SchemaObjectKind, [SchemaObject])] {
        SchemaObjectKind.allCases.compactMap { kind in
            let matching = objects.filter { $0.kind == kind }
            return matching.isEmpty ? nil : (kind, matching)
        }
    }

    // MARK: - Schema

    func reloadSchema(selectFirst: Bool = false) {
        perform(L("op.reloadSchema")) {
            objects = try reader.objects()
            if selectFirst || selectedObject == nil {
                selectedObjectID = objects.first { $0.kind == .table }?.id ?? objects.first?.id
            }
            reloadDetails()
        }
    }

    func reloadDetails() {
        guard let object = selectedObject else {
            details = nil
            page = nil
            return
        }
        perform(L("op.loadObject", object.name)) {
            details = try reader.details(for: object)
            if let sort, details?.columns.contains(where: { $0.name == sort.column }) != true {
                self.sort = nil
            }
            pageIndex = 0
            selectedRowIDs = []
            reloadPage()
        }
    }

    func selectObject(_ object: SchemaObject) {
        selectedObjectID = object.id
        if object.kind == .index || object.kind == .trigger {
            tab = .ddl
        }
        reloadDetails()
    }

    // MARK: - Data browsing

    func reloadPage() {
        guard let store = dataStore, details?.object.kind != .index, details?.object.kind != .trigger else {
            page = nil
            status = ""
            return
        }
        perform(L("op.loadRows")) {
            page = try store.page(limit: pageSize,
                                  offset: pageIndex * pageSize,
                                  sort: sort,
                                  filter: filterText.isEmpty ? nil : filterText)
            if let page {
                let shown = min(Int(page.totalRows), page.offset + page.rows.count)
                status = page.totalRows == 0
                    ? L("data.noRows")
                    : L("data.rowsRange", page.offset + 1, shown, page.totalRows)
            }
        }
    }

    var pageCount: Int {
        guard let page, pageSize > 0 else { return 1 }
        return max(1, Int((page.totalRows + Int64(pageSize) - 1) / Int64(pageSize)))
    }

    var currentPageNumber: Int { pageIndex + 1 }

    func goToPage(_ index: Int) {
        pageIndex = min(max(0, index), pageCount - 1)
        reloadPage()
    }

    func nextPage() { goToPage(pageIndex + 1) }
    func previousPage() { goToPage(pageIndex - 1) }

    func applyFilter() {
        pageIndex = 0
        reloadPage()
    }

    func toggleSort(column: String) {
        if sort?.column == column {
            sort = ColumnSort(column: column, ascending: !(sort?.ascending ?? true))
        } else {
            sort = ColumnSort(column: column, ascending: true)
        }
        pageIndex = 0
        reloadPage()
    }

    // MARK: - Row editing

    var selectedRows: [TableRowData] {
        (page?.rows ?? []).filter { selectedRowIDs.contains($0.id) }
    }

    func insertRow(values: [String: SQLValue]) {
        guard let store = dataStore else { return }
        perform(L("op.insertRow")) {
            _ = try store.insert(values: values)
            status = L("status.rowInserted")
            reloadCounts()
        }
    }

    func updateRow(_ row: TableRowData, values: [String: SQLValue]) {
        guard let store = dataStore else { return }
        perform(L("op.updateRow")) {
            let changed = try store.update(row: row, values: values)
            status = L("status.rowsUpdated", changed)
            reloadPage()
        }
    }

    func updateCell(row: TableRowData, column: String, value: SQLValue) {
        guard let store = dataStore else { return }
        perform(L("op.updateCell")) {
            _ = try store.update(row: row, column: column, to: value)
            reloadPage()
        }
    }

    func deleteSelectedRows() {
        guard let store = dataStore, !selectedRows.isEmpty else { return }
        perform(L("op.deleteRows")) {
            let deleted = try store.delete(rows: selectedRows)
            status = L("status.rowsDeleted", deleted)
            selectedRowIDs = []
            reloadCounts()
        }
    }

    private func reloadCounts() {
        if let object = selectedObject {
            details = try? reader.details(for: object)
        }
        reloadPage()
    }

    // MARK: - Schema editing

    func createTable(name: String, columns: [ColumnDefinition], withoutRowID: Bool) {
        perform(L("op.createTable")) {
            let sql = try schemaEditor.createTable(name: name, columns: columns, withoutRowID: withoutRowID)
            status = sql
            reloadSchema()
            selectedObjectID = SchemaObject(kind: .table, name: name, tableName: name, sql: sql).id
            reloadDetails()
        }
    }

    func addColumn(_ column: ColumnDefinition, to table: String) {
        perform(L("op.addColumn")) {
            status = try schemaEditor.addColumn(column, to: table)
            reloadSchema()
        }
    }

    func renameColumn(in table: String, from oldName: String, to newName: String) {
        perform(L("op.renameColumn")) {
            status = try schemaEditor.renameColumn(in: table, from: oldName, to: newName)
            reloadSchema()
        }
    }

    func dropColumn(in table: String, name: String) {
        perform(L("op.dropColumn")) {
            status = try schemaEditor.dropColumn(in: table, name: name)
            reloadSchema()
        }
    }

    func renameTable(from oldName: String, to newName: String) {
        perform(L("op.renameTable")) {
            status = try schemaEditor.renameTable(from: oldName, to: newName)
            reloadSchema()
            selectedObjectID = "table:\(newName)"
            reloadDetails()
        }
    }

    func createIndex(name: String, table: String, columns: [String], unique: Bool) {
        perform(L("op.createIndex")) {
            status = try schemaEditor.createIndex(name: name, table: table, columns: columns, unique: unique)
            reloadSchema()
        }
    }

    func drop(_ object: SchemaObject) {
        perform(L("op.drop")) {
            status = try schemaEditor.drop(object)
            if selectedObjectID == object.id { selectedObjectID = nil }
            reloadSchema()
        }
    }

    func emptyTable(_ object: SchemaObject) {
        guard let store = dataStore else { return }
        perform(L("op.emptyTable")) {
            let deleted = try store.deleteAllRows()
            status = L("status.rowsDeletedFrom", deleted, object.name)
            reloadCounts()
        }
    }

    // MARK: - Query editor

    func runQuery() {
        tab = .query
        let result = queryRunner.run(queryText)
        execution = result
        status = result.summary
        errorMessage = result.error?.localizedDescription
        if result.statements.contains(where: { !$0.isReadOnly }) {
            reloadSchema()
        }
    }

    func explainQuery() {
        tab = .query
        perform(L("op.explain")) {
            let plan = try queryRunner.explain(queryText)
            var execution = QueryExecution()
            execution.statements = [.init(sql: "EXPLAIN QUERY PLAN",
                                          resultSet: plan,
                                          affectedRows: 0,
                                          duration: 0,
                                          isReadOnly: true)]
            self.execution = execution
            status = L("query.plan")
        }
    }

    /// The result set currently on screen, used by Export.
    var exportableResult: (ResultSet, String)? {
        switch tab {
        case .query:
            if let set = execution?.displayedResult?.resultSet {
                return (set, selectedObject?.name ?? "query_result")
            }
            return nil
        default:
            guard let page, let details else { return nil }
            let set = ResultSet(columnNames: details.columns.map(\.name), rows: page.rows.map(\.values))
            return (set, details.object.name)
        }
    }

    // MARK: - Maintenance

    func vacuum() {
        perform(L("op.vacuum")) {
            try database.vacuum()
            status = L("status.vacuumed")
        }
    }

    /// Merges the write-ahead log into the main database file.
    func checkpointWAL() {
        perform(L("op.checkpoint")) {
            let pages = try database.checkpointWAL()
            status = L("status.checkpointed", pages)
            reloadDetails()
        }
    }

    /// The `-wal` / `-shm` / `-journal` files currently next to this database.
    var sidecars: DatabaseSidecars { database.sidecars }

    func integrityCheck() {
        perform(L("op.integrityCheck")) {
            let messages = try database.integrityCheck()
            status = messages.joined(separator: "; ")
        }
    }

    var databaseProperties: [(String, String)] {
        var properties: [(String, String)] = [
            (L("info.file"), url.path),
            (L("info.size"), ByteCountFormatter.string(fromByteCount: database.fileSize, countStyle: .file))
        ]
        properties.append(contentsOf: reader.databaseProperties())
        return properties
    }

    // MARK: - Error handling

    /// Runs a database action, surfacing any failure in the error banner.
    private func perform(_ label: String, _ body: () throws -> Void) {
        do {
            errorMessage = nil
            try body()
        } catch {
            errorMessage = L("status.failed", label, error.localizedDescription)
        }
    }
}
