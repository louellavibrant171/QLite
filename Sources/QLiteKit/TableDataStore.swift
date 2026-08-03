import Foundation

/// A row read from a table, carrying the handle needed to update or delete it.
public struct TableRowData: Identifiable, Hashable {
    /// Offset within the current page; stable enough for SwiftUI list identity.
    public let id: Int
    /// `rowid` when the table has one, otherwise `nil` and edits fall back to primary keys.
    public let rowID: Int64?
    public var values: [SQLValue]
}

/// A page of rows plus the sort/filter that produced it.
public struct TablePage {
    public var columns: [ColumnInfo]
    public var rows: [TableRowData]
    public var totalRows: Int64
    public var offset: Int
    public var limit: Int
}

/// Sort description applied server-side so paging stays correct for large tables.
public struct ColumnSort: Equatable {
    public var column: String
    public var ascending: Bool

    public init(column: String, ascending: Bool = true) {
        self.column = column
        self.ascending = ascending
    }
}

/// Reads and mutates the contents of a single table or view.
public struct TableDataStore {
    private let db: Database
    public let details: TableDetails

    public init(database: Database, details: TableDetails) {
        self.db = database
        self.details = details
    }

    public var table: String { details.object.name }

    /// True when rows can be updated or deleted: we need either a rowid or a primary key.
    public var isEditable: Bool {
        guard details.object.kind == .table else { return false }
        return details.hasRowID || !details.primaryKeyColumns.isEmpty
    }

    public var editabilityReason: String? {
        if details.object.kind == .view { return "Views are read-only." }
        if isEditable { return nil }
        return "This table has neither a rowid nor a primary key, so rows cannot be addressed for editing."
    }

    // MARK: - Reading

    /// Fetches one page of rows.
    /// - Parameter filter: raw SQL boolean expression appended as a `WHERE` clause.
    public func page(limit: Int, offset: Int, sort: ColumnSort? = nil, filter: String? = nil) throws -> TablePage {
        let whereClause = Self.whereClause(filter)
        let countSQL = "SELECT COUNT(*) FROM \(quoteIdentifier(table))\(whereClause)"
        let total = try db.scalar(countSQL).intValue ?? 0

        var selection = details.columns.map { quoteIdentifier($0.name) }.joined(separator: ", ")
        if selection.isEmpty { selection = "*" }
        let prefix = details.hasRowID ? "rowid AS \"_qlite_rowid\", " : ""

        var sql = "SELECT \(prefix)\(selection) FROM \(quoteIdentifier(table))\(whereClause)"
        if let sort, details.columns.contains(where: { $0.name == sort.column }) {
            sql += " ORDER BY \(quoteIdentifier(sort.column)) \(sort.ascending ? "ASC" : "DESC")"
        }
        sql += " LIMIT \(max(0, limit)) OFFSET \(max(0, offset))"

        let result = try db.query(sql)
        let rows = result.rows.enumerated().map { index, values -> TableRowData in
            if details.hasRowID {
                return TableRowData(id: offset + index, rowID: values.first?.intValue, values: Array(values.dropFirst()))
            }
            return TableRowData(id: offset + index, rowID: nil, values: values)
        }
        return TablePage(columns: details.columns, rows: rows, totalRows: total, offset: offset, limit: limit)
    }

    private static func whereClause(_ filter: String?) -> String {
        guard let filter, !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return " WHERE \(filter)"
    }

    // MARK: - Writing

    /// Builds the `WHERE` clause identifying a single row, plus its bound parameters.
    private func rowPredicate(for row: TableRowData) throws -> (String, [SQLValue]) {
        if let rowID = row.rowID {
            return ("rowid = ?", [.integer(rowID)])
        }
        let keys = details.primaryKeyColumns
        guard !keys.isEmpty else {
            throw QLiteError.notEditable(editabilityReason ?? "Row cannot be addressed.")
        }
        var clauses: [String] = []
        var parameters: [SQLValue] = []
        for key in keys {
            guard let index = details.columns.firstIndex(where: { $0.name == key.name }) else { continue }
            let value = row.values[index]
            if value.isNull {
                clauses.append("\(quoteIdentifier(key.name)) IS NULL")
            } else {
                clauses.append("\(quoteIdentifier(key.name)) = ?")
                parameters.append(value)
            }
        }
        return (clauses.joined(separator: " AND "), parameters)
    }

    /// Updates a single cell of a row.
    @discardableResult
    public func update(row: TableRowData, column: String, to value: SQLValue) throws -> Int {
        let (predicate, keyParameters) = try rowPredicate(for: row)
        let sql = "UPDATE \(quoteIdentifier(table)) SET \(quoteIdentifier(column)) = ? WHERE \(predicate)"
        return try db.run(sql, [value] + keyParameters)
    }

    /// Replaces every column of a row in one statement.
    @discardableResult
    public func update(row: TableRowData, values: [String: SQLValue]) throws -> Int {
        guard !values.isEmpty else { return 0 }
        let (predicate, keyParameters) = try rowPredicate(for: row)
        let assignments = values.keys.map { "\(quoteIdentifier($0)) = ?" }.joined(separator: ", ")
        let parameters = values.keys.map { values[$0]! } + keyParameters
        let sql = "UPDATE \(quoteIdentifier(table)) SET \(assignments) WHERE \(predicate)"
        return try db.run(sql, parameters)
    }

    @discardableResult
    public func delete(rows: [TableRowData]) throws -> Int {
        try db.transaction {
            var deleted = 0
            for row in rows {
                let (predicate, parameters) = try rowPredicate(for: row)
                deleted += try db.run("DELETE FROM \(quoteIdentifier(table)) WHERE \(predicate)", parameters)
            }
            return deleted
        }
    }

    /// Inserts a row. Columns absent from `values` fall back to their defaults.
    @discardableResult
    public func insert(values: [String: SQLValue]) throws -> Int64 {
        if values.isEmpty {
            try db.run("INSERT INTO \(quoteIdentifier(table)) DEFAULT VALUES")
            return db.lastInsertRowID
        }
        let columns = Array(values.keys)
        let columnList = columns.map { quoteIdentifier($0) }.joined(separator: ", ")
        let placeholders = columns.map { _ in "?" }.joined(separator: ", ")
        let sql = "INSERT INTO \(quoteIdentifier(table)) (\(columnList)) VALUES (\(placeholders))"
        try db.run(sql, columns.map { values[$0]! })
        return db.lastInsertRowID
    }

    /// Deletes every row of the table.
    @discardableResult
    public func deleteAllRows() throws -> Int {
        try db.run("DELETE FROM \(quoteIdentifier(table))")
    }
}
