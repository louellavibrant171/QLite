import Foundation

/// Reads schema metadata out of a database using `sqlite_master` and the `PRAGMA` functions.
public struct SchemaReader {
    private let db: Database

    public init(database: Database) {
        self.db = database
    }

    /// All user objects, ordered by kind then name. Internal `sqlite_*` objects are skipped.
    public func objects() throws -> [SchemaObject] {
        let sql = """
        SELECT type, name, tbl_name, COALESCE(sql, '')
        FROM sqlite_master
        WHERE name NOT LIKE 'sqlite\\_%' ESCAPE '\\'
        ORDER BY type, name COLLATE NOCASE
        """
        return try db.query(sql).rows.compactMap { row in
            guard row.count >= 4,
                  let type = row[0].stringValue,
                  let kind = SchemaObjectKind(rawValue: type),
                  let name = row[1].stringValue else { return nil }
            return SchemaObject(kind: kind,
                                name: name,
                                tableName: row[2].stringValue ?? name,
                                sql: row[3].stringValue ?? "")
        }
    }

    public func columns(of table: String) throws -> [ColumnInfo] {
        let sql = "PRAGMA table_info(\(quoteIdentifier(table)))"
        return try db.query(sql).rows.compactMap { row in
            guard row.count >= 6, let name = row[1].stringValue else { return nil }
            return ColumnInfo(cid: Int(row[0].intValue ?? 0),
                              name: name,
                              type: row[2].stringValue ?? "",
                              isNotNull: (row[3].intValue ?? 0) != 0,
                              defaultValue: row[4].isNull ? nil : row[4].stringValue,
                              primaryKeyPosition: Int(row[5].intValue ?? 0))
        }
    }

    public func foreignKeys(of table: String) throws -> [ForeignKeyInfo] {
        let sql = "PRAGMA foreign_key_list(\(quoteIdentifier(table)))"
        return try db.query(sql).rows.compactMap { row in
            guard row.count >= 8 else { return nil }
            return ForeignKeyInfo(id: Int(row[0].intValue ?? 0),
                                  column: row[3].stringValue ?? "",
                                  referencedTable: row[2].stringValue ?? "",
                                  referencedColumn: row[4].stringValue ?? "",
                                  onUpdate: row[5].stringValue ?? "NO ACTION",
                                  onDelete: row[6].stringValue ?? "NO ACTION")
        }
    }

    public func indexes(of table: String) throws -> [IndexInfo] {
        let listSQL = "PRAGMA index_list(\(quoteIdentifier(table)))"
        let rows = (try? db.query(listSQL).rows) ?? []
        return rows.compactMap { row in
            guard row.count >= 5, let name = row[1].stringValue else { return nil }
            let columns = (try? db.query("PRAGMA index_info(\(quoteIdentifier(name)))").rows
                .compactMap { $0.count >= 3 ? $0[2].stringValue : nil }) ?? []
            return IndexInfo(name: name,
                             isUnique: (row[2].intValue ?? 0) != 0,
                             origin: row[3].stringValue ?? "c",
                             isPartial: (row[4].intValue ?? 0) != 0,
                             columns: columns)
        }
    }

    public func rowCount(of table: String) throws -> Int64 {
        try db.scalar("SELECT COUNT(*) FROM \(quoteIdentifier(table))").intValue ?? 0
    }

    /// Detects whether `rowid` can be used as a stable row handle for editing.
    public func hasRowID(_ table: String) -> Bool {
        (try? db.query("SELECT rowid FROM \(quoteIdentifier(table)) LIMIT 1")) != nil
    }

    /// Gathers columns, keys, indexes and the row count for one table or view.
    public func details(for object: SchemaObject) throws -> TableDetails {
        let columns = try columns(of: object.name)
        let foreignKeys = object.kind == .table ? ((try? foreignKeys(of: object.name)) ?? []) : []
        let indexes = object.kind == .table ? indexes(ofIgnoringErrors: object.name) : []
        let count = (try? rowCount(of: object.name)) ?? 0
        return TableDetails(object: object,
                            columns: columns,
                            foreignKeys: foreignKeys,
                            indexes: indexes,
                            rowCount: count,
                            hasRowID: object.kind == .table && hasRowID(object.name))
    }

    private func indexes(ofIgnoringErrors table: String) -> [IndexInfo] {
        (try? indexes(of: table)) ?? []
    }

    /// Key/value pairs shown in the database info panel and QuickLook preview.
    public func databaseProperties() -> [(String, String)] {
        var properties: [(String, String)] = []
        let pragmas = ["page_size", "page_count", "encoding", "journal_mode", "user_version", "application_id"]
        for pragma in pragmas {
            if let value = try? db.scalar("PRAGMA \(pragma)"), !value.isNull {
                properties.append((pragma, value.displayString))
            }
        }
        properties.append(("sqlite_version", Database.libraryVersion))
        return properties
    }
}
