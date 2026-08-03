import Foundation

/// The kinds of objects stored in `sqlite_master`.
public enum SchemaObjectKind: String, CaseIterable, Hashable {
    case table
    case view
    case index
    case trigger

    public var pluralTitle: String {
        switch self {
        case .table: return "Tables"
        case .view: return "Views"
        case .index: return "Indexes"
        case .trigger: return "Triggers"
        }
    }

    public var symbolName: String {
        switch self {
        case .table: return "tablecells"
        case .view: return "eye"
        case .index: return "list.bullet.indent"
        case .trigger: return "bolt"
        }
    }
}

/// One entry of `sqlite_master`.
public struct SchemaObject: Identifiable, Hashable {
    public let kind: SchemaObjectKind
    public let name: String
    /// The table an index or trigger belongs to; equal to `name` for tables and views.
    public let tableName: String
    public let sql: String

    public var id: String { "\(kind.rawValue):\(name)" }

    public init(kind: SchemaObjectKind, name: String, tableName: String, sql: String) {
        self.kind = kind
        self.name = name
        self.tableName = tableName
        self.sql = sql
    }
}

/// A column of a table or view, as reported by `PRAGMA table_info`.
public struct ColumnInfo: Identifiable, Hashable {
    public let cid: Int
    public let name: String
    public let type: String
    public let isNotNull: Bool
    public let defaultValue: String?
    /// 1-based position within the primary key, or 0 when the column is not part of it.
    public let primaryKeyPosition: Int

    public var id: Int { cid }
    public var isPrimaryKey: Bool { primaryKeyPosition > 0 }
    public var affinity: TypeAffinity { TypeAffinity.of(type) }

    public init(cid: Int, name: String, type: String, isNotNull: Bool, defaultValue: String?, primaryKeyPosition: Int) {
        self.cid = cid
        self.name = name
        self.type = type
        self.isNotNull = isNotNull
        self.defaultValue = defaultValue
        self.primaryKeyPosition = primaryKeyPosition
    }
}

/// One row of `PRAGMA foreign_key_list`.
public struct ForeignKeyInfo: Identifiable, Hashable {
    public let id: Int
    public let column: String
    public let referencedTable: String
    public let referencedColumn: String
    public let onUpdate: String
    public let onDelete: String
}

/// One row of `PRAGMA index_list`, enriched with the indexed columns.
public struct IndexInfo: Identifiable, Hashable {
    public let name: String
    public let isUnique: Bool
    public let origin: String
    public let isPartial: Bool
    public let columns: [String]

    public var id: String { name }

    /// `c` = created by CREATE INDEX, `u` = UNIQUE constraint, `pk` = PRIMARY KEY.
    public var originDescription: String {
        switch origin {
        case "c": return "CREATE INDEX"
        case "u": return "UNIQUE constraint"
        case "pk": return "PRIMARY KEY"
        default: return origin
        }
    }
}

/// Everything the UI needs to describe a single table or view.
public struct TableDetails: Hashable {
    public var object: SchemaObject
    public var columns: [ColumnInfo]
    public var foreignKeys: [ForeignKeyInfo]
    public var indexes: [IndexInfo]
    public var rowCount: Int64
    /// False for `WITHOUT ROWID` tables and views, where `rowid` cannot be used as a row handle.
    public var hasRowID: Bool

    public var primaryKeyColumns: [ColumnInfo] {
        columns.filter { $0.isPrimaryKey }.sorted { $0.primaryKeyPosition < $1.primaryKeyPosition }
    }
}

/// A column definition used when creating tables or adding columns.
public struct ColumnDefinition: Identifiable, Hashable {
    public var id = UUID()
    public var name: String
    public var type: String
    public var isPrimaryKey: Bool
    public var isNotNull: Bool
    public var isUnique: Bool
    public var isAutoIncrement: Bool
    public var defaultValue: String

    public init(name: String = "",
                type: String = "TEXT",
                isPrimaryKey: Bool = false,
                isNotNull: Bool = false,
                isUnique: Bool = false,
                isAutoIncrement: Bool = false,
                defaultValue: String = "") {
        self.name = name
        self.type = type
        self.isPrimaryKey = isPrimaryKey
        self.isNotNull = isNotNull
        self.isUnique = isUnique
        self.isAutoIncrement = isAutoIncrement
        self.defaultValue = defaultValue
    }

    /// Renders the column as it appears inside `CREATE TABLE`.
    public func sqlFragment(includePrimaryKey: Bool) -> String {
        var parts = [quoteIdentifier(name)]
        if !type.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(type) }
        if includePrimaryKey && isPrimaryKey {
            parts.append("PRIMARY KEY")
            if isAutoIncrement { parts.append("AUTOINCREMENT") }
        }
        if isNotNull { parts.append("NOT NULL") }
        if isUnique && !isPrimaryKey { parts.append("UNIQUE") }
        let trimmedDefault = defaultValue.trimmingCharacters(in: .whitespaces)
        if !trimmedDefault.isEmpty { parts.append("DEFAULT \(trimmedDefault)") }
        return parts.joined(separator: " ")
    }

    /// Common declared types offered by the UI.
    public static let commonTypes = ["INTEGER", "TEXT", "REAL", "BLOB", "NUMERIC", "BOOLEAN", "DATETIME"]
}

public let sqliteTypeKeywords = ColumnDefinition.commonTypes
