import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// A prepared statement. Instances are created by `Database.prepare(_:)` and are not thread safe.
public final class Statement {
    private let db: OpaquePointer?
    private var handle: OpaquePointer?
    public let sql: String

    /// Remaining SQL after this statement, used to iterate multi-statement scripts.
    public let tail: String

    init(db: OpaquePointer?, sql: String) throws {
        self.db = db
        self.sql = sql

        var stmt: OpaquePointer?
        var status = SQLITE_OK
        var remainder = ""
        let bytes = Array(sql.utf8)

        bytes.withUnsafeBufferPointer { buffer in
            let base = UnsafeRawPointer(buffer.baseAddress)?.assumingMemoryBound(to: CChar.self)
            var tailPointer: UnsafePointer<CChar>?
            status = sqlite3_prepare_v2(db, base, Int32(bytes.count), &stmt, &tailPointer)
            // The tail pointer indexes into `bytes`, so translate it back to an offset while
            // the buffer is still alive.
            if let tailPointer, let base {
                let offset = tailPointer - base
                if offset > 0 && offset < bytes.count {
                    remainder = String(decoding: bytes[offset...], as: UTF8.self)
                }
            }
        }

        guard status == SQLITE_OK else { throw SQLiteError(handle: db, code: status, sql: sql) }
        self.handle = stmt
        self.tail = remainder
    }

    deinit {
        if let handle { sqlite3_finalize(handle) }
    }

    /// True when `sqlite3_prepare` produced no statement (e.g. a comment-only fragment).
    public var isEmpty: Bool { handle == nil }

    public var columnCount: Int { handle.map { Int(sqlite3_column_count($0)) } ?? 0 }

    public var columnNames: [String] {
        guard let handle else { return [] }
        return (0..<Int32(columnCount)).map { String(cString: sqlite3_column_name(handle, $0)) }
    }

    /// The table each result column originates from, when SQLite can determine it.
    public var columnTableNames: [String?] {
        guard let handle else { return [] }
        return (0..<Int32(columnCount)).map { index in
            sqlite3_column_table_name(handle, index).map { String(cString: $0) }
        }
    }

    public var isReadOnly: Bool { handle.map { sqlite3_stmt_readonly($0) != 0 } ?? true }

    public func bind(_ values: [SQLValue]) throws {
        guard let handle else { return }
        sqlite3_reset(handle)
        sqlite3_clear_bindings(handle)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch value {
            case .null:
                status = sqlite3_bind_null(handle, index)
            case .integer(let v):
                status = sqlite3_bind_int64(handle, index, v)
            case .real(let v):
                status = sqlite3_bind_double(handle, index, v)
            case .text(let v):
                status = sqlite3_bind_text(handle, index, v, -1, SQLITE_TRANSIENT)
            case .blob(let data):
                status = data.isEmpty
                    ? sqlite3_bind_zeroblob(handle, index, 0)
                    : data.withUnsafeBytes { sqlite3_bind_blob(handle, index, $0.baseAddress, Int32(data.count), SQLITE_TRANSIENT) }
            }
            guard status == SQLITE_OK else { throw SQLiteError(handle: db, code: status, sql: sql) }
        }
    }

    /// Advances the cursor. Returns `true` while rows are available.
    @discardableResult
    public func step() throws -> Bool {
        guard let handle else { return false }
        let status = sqlite3_step(handle)
        switch status {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw SQLiteError(handle: db, code: status, sql: sql)
        }
    }

    public func value(at index: Int) -> SQLValue {
        guard let handle else { return .null }
        let i = Int32(index)
        switch sqlite3_column_type(handle, i) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(handle, i))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(handle, i))
        case SQLITE_TEXT:
            return .text(String(cString: sqlite3_column_text(handle, i)))
        case SQLITE_BLOB:
            let count = Int(sqlite3_column_bytes(handle, i))
            guard count > 0, let pointer = sqlite3_column_blob(handle, i) else { return .blob(Data()) }
            return .blob(Data(bytes: pointer, count: count))
        default:
            return .null
        }
    }

    public func currentRow() -> [SQLValue] {
        (0..<columnCount).map { value(at: $0) }
    }
}
