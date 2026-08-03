import Foundation

/// Data definition operations: creating, altering and dropping schema objects.
///
/// Every method returns the SQL it executed so the UI can show it in a log.
public struct SchemaEditor {
    private let db: Database

    public init(database: Database) {
        self.db = database
    }

    // MARK: - Tables

    @discardableResult
    public func createTable(name: String,
                            columns: [ColumnDefinition],
                            withoutRowID: Bool = false,
                            ifNotExists: Bool = false) throws -> String {
        try validate(identifier: name)
        let usable = columns.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !usable.isEmpty else { throw QLiteError.notEditable("A table needs at least one column.") }

        let primaryKeys = usable.filter { $0.isPrimaryKey }
        // A single INTEGER PRIMARY KEY has to be declared inline to alias the rowid; composite
        // keys become a table-level constraint instead.
        let inlinePrimaryKey = primaryKeys.count == 1
        var body = usable.map { $0.sqlFragment(includePrimaryKey: inlinePrimaryKey) }
        if !inlinePrimaryKey && !primaryKeys.isEmpty {
            let keyList = primaryKeys.map { quoteIdentifier($0.name) }.joined(separator: ", ")
            body.append("PRIMARY KEY (\(keyList))")
        }

        var sql = "CREATE TABLE \(ifNotExists ? "IF NOT EXISTS " : "")\(quoteIdentifier(name)) (\n    "
        sql += body.joined(separator: ",\n    ")
        sql += "\n)"
        if withoutRowID { sql += " WITHOUT ROWID" }
        try db.execute(sql)
        return sql
    }

    @discardableResult
    public func renameTable(from oldName: String, to newName: String) throws -> String {
        try validate(identifier: newName)
        let sql = "ALTER TABLE \(quoteIdentifier(oldName)) RENAME TO \(quoteIdentifier(newName))"
        try db.execute(sql)
        return sql
    }

    @discardableResult
    public func dropTable(_ name: String) throws -> String {
        let sql = "DROP TABLE \(quoteIdentifier(name))"
        try db.execute(sql)
        return sql
    }

    @discardableResult
    public func dropView(_ name: String) throws -> String {
        let sql = "DROP VIEW \(quoteIdentifier(name))"
        try db.execute(sql)
        return sql
    }

    @discardableResult
    public func dropTrigger(_ name: String) throws -> String {
        let sql = "DROP TRIGGER \(quoteIdentifier(name))"
        try db.execute(sql)
        return sql
    }

    // MARK: - Columns

    @discardableResult
    public func addColumn(_ column: ColumnDefinition, to table: String) throws -> String {
        try validate(identifier: column.name)
        let sql = "ALTER TABLE \(quoteIdentifier(table)) ADD COLUMN \(column.sqlFragment(includePrimaryKey: false))"
        try db.execute(sql)
        return sql
    }

    /// Requires SQLite 3.25 or newer (shipped with macOS 10.15+).
    @discardableResult
    public func renameColumn(in table: String, from oldName: String, to newName: String) throws -> String {
        try validate(identifier: newName)
        let sql = "ALTER TABLE \(quoteIdentifier(table)) RENAME COLUMN \(quoteIdentifier(oldName)) TO \(quoteIdentifier(newName))"
        try db.execute(sql)
        return sql
    }

    /// Requires SQLite 3.35 or newer; SQLite refuses to drop indexed or key columns.
    @discardableResult
    public func dropColumn(in table: String, name: String) throws -> String {
        let sql = "ALTER TABLE \(quoteIdentifier(table)) DROP COLUMN \(quoteIdentifier(name))"
        try db.execute(sql)
        return sql
    }

    // MARK: - Indexes

    @discardableResult
    public func createIndex(name: String,
                            table: String,
                            columns: [String],
                            unique: Bool = false,
                            whereClause: String? = nil) throws -> String {
        try validate(identifier: name)
        guard !columns.isEmpty else { throw QLiteError.notEditable("An index needs at least one column.") }
        let columnList = columns.map { quoteIdentifier($0) }.joined(separator: ", ")
        var sql = "CREATE \(unique ? "UNIQUE " : "")INDEX \(quoteIdentifier(name)) ON \(quoteIdentifier(table)) (\(columnList))"
        if let whereClause, !whereClause.trimmingCharacters(in: .whitespaces).isEmpty {
            sql += " WHERE \(whereClause)"
        }
        try db.execute(sql)
        return sql
    }

    @discardableResult
    public func dropIndex(_ name: String) throws -> String {
        let sql = "DROP INDEX \(quoteIdentifier(name))"
        try db.execute(sql)
        return sql
    }

    // MARK: - Helpers

    /// Drops any object, dispatching on its kind.
    @discardableResult
    public func drop(_ object: SchemaObject) throws -> String {
        switch object.kind {
        case .table: return try dropTable(object.name)
        case .view: return try dropView(object.name)
        case .index: return try dropIndex(object.name)
        case .trigger: return try dropTrigger(object.name)
        }
    }

    private func validate(identifier: String) throws {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.lowercased().hasPrefix("sqlite_") else {
            throw QLiteError.invalidIdentifier(identifier)
        }
    }
}
