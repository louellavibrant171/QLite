import Foundation
import SQLite3

/// An error reported by the SQLite engine, carrying the failing statement when known.
public struct SQLiteError: LocalizedError, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public let sql: String?

    public init(code: Int32, message: String, sql: String? = nil) {
        self.code = code
        self.message = message
        self.sql = sql
    }

    init(handle: OpaquePointer?, code: Int32, sql: String? = nil) {
        self.code = code
        self.message = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
        self.sql = sql
    }

    public var errorDescription: String? { description }

    public var description: String {
        if let sql, !sql.isEmpty {
            return "\(message) (code \(code))\n\(sql)"
        }
        return "\(message) (code \(code))"
    }
}

/// Errors raised by QLiteKit itself rather than by SQLite.
public enum QLiteError: LocalizedError {
    case notEditable(String)
    case invalidIdentifier(String)
    case noSuchObject(String)

    public var errorDescription: String? {
        switch self {
        case .notEditable(let reason): return reason
        case .invalidIdentifier(let name): return "Invalid identifier: “\(name)”"
        case .noSuchObject(let name): return "No such object: “\(name)”"
        }
    }
}

/// Quotes an identifier for safe interpolation into SQL (`my"table` -> `"my""table"`).
public func quoteIdentifier(_ identifier: String) -> String {
    "\"" + identifier.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

/// Quotes a string literal for safe interpolation into SQL.
public func quoteLiteral(_ literal: String) -> String {
    "'" + literal.replacingOccurrences(of: "'", with: "''") + "'"
}
