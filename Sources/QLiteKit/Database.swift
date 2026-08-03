import Foundation
import SQLite3

/// The result of a query: an ordered set of column names plus the rows that were read.
public struct ResultSet {
    public var columnNames: [String]
    public var rows: [[SQLValue]]

    public init(columnNames: [String] = [], rows: [[SQLValue]] = []) {
        self.columnNames = columnNames
        self.rows = rows
    }

    public var isEmpty: Bool { rows.isEmpty }
}

/// How a database file is opened.
public enum OpenMode {
    /// Read and write. Required to replay a `-wal` file, so this is the default.
    case readWrite
    /// Read-only, but still consults `-wal`/`-shm`, which needs those files to be writable.
    case readOnly
    /// Read-only and self-contained: SQLite ignores any WAL or journal and never touches the
    /// file system beside the main file. The last checkpointed state is what you see.
    case immutable
}

/// A connection to a SQLite database file.
///
/// `Database` is *not* thread safe; confine a connection to a single queue. The app uses one
/// connection per open window, driven from the main queue.
public final class Database {
    private var handle: OpaquePointer?
    public let url: URL
    public let mode: OpenMode

    public var isReadOnly: Bool { mode != .readWrite }

    /// Opens `url` in `mode`. `createIfMissing` is only honoured for `.readWrite`.
    public init(url: URL, mode: OpenMode = .readWrite, createIfMissing: Bool = true) throws {
        self.url = url
        self.mode = mode

        var flags: Int32
        var path = url.path
        switch mode {
        case .readWrite:
            flags = SQLITE_OPEN_READWRITE | (createIfMissing ? SQLITE_OPEN_CREATE : 0)
        case .readOnly:
            flags = SQLITE_OPEN_READONLY
        case .immutable:
            // `immutable=1` is only understood through the URI form of the filename.
            flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
            path = "file:" + Self.percentEncodedPath(url.path) + "?immutable=1"
        }

        var db: OpaquePointer?
        let status = sqlite3_open_v2(path, &db, flags | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, db != nil else {
            let error = SQLiteError(handle: db, code: status)
            if db != nil { sqlite3_close_v2(db) }
            throw error
        }
        self.handle = db
        sqlite3_busy_timeout(db, 3_000)
        if mode == .readWrite {
            try? execute("PRAGMA foreign_keys = ON")
        }
        // Fail early on a file that exists but is not a database, rather than at the first query.
        try execute("SELECT count(*) FROM sqlite_master")
    }

    /// Percent-encodes a path for use in a `file:` URI, per SQLite's URI filename rules.
    private static func percentEncodedPath(_ path: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "/-._~")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }

    /// Opens a database for reading, degrading gracefully when the file cannot be written.
    ///
    /// A database with a non-empty `-wal` can only be read completely when SQLite may write to
    /// the `-shm` file. When that is impossible — a read-only volume, or a sandboxed extension
    /// that was only handed the main file — this falls back to a temporary copy of the whole
    /// file set, and finally to an `immutable` open that shows the last checkpointed state.
    /// - Returns: the connection, the snapshot keeping temporary files alive (if one was made),
    ///   and whether WAL content is missing from the result.
    public static func openForReading(url: URL) -> (database: Database, snapshot: DatabaseSnapshot?, walIsStale: Bool)? {
        let sidecars = DatabaseSidecars.detect(for: url)

        if let db = try? Database(url: url, mode: .readWrite, createIfMissing: false) {
            return (db, nil, false)
        }
        if let db = try? Database(url: url, mode: .readOnly) {
            return (db, nil, false)
        }
        if sidecars.hasPendingWAL || sidecars.hasJournal,
           let snapshot = try? DatabaseSnapshot.make(of: url),
           let db = try? Database(url: snapshot.url, mode: .readWrite, createIfMissing: false) {
            return (db, snapshot, false)
        }
        if let db = try? Database(url: url, mode: .immutable) {
            return (db, nil, sidecars.hasPendingWAL)
        }
        return nil
    }

    deinit { close() }

    public func close() {
        if let handle {
            sqlite3_close_v2(handle)
            self.handle = nil
        }
    }

    /// The SQLite library version the app is linked against.
    public static var libraryVersion: String { String(cString: sqlite3_libversion()) }

    public var lastInsertRowID: Int64 { handle.map { sqlite3_last_insert_rowid($0) } ?? 0 }
    public var changes: Int { handle.map { Int(sqlite3_changes($0)) } ?? 0 }

    public func prepare(_ sql: String) throws -> Statement {
        try Statement(db: handle, sql: sql)
    }

    /// Runs one or more statements, discarding any rows they produce.
    public func execute(_ sql: String) throws {
        var status = SQLITE_OK
        var errorPointer: UnsafeMutablePointer<CChar>?
        status = sqlite3_exec(handle, sql, nil, nil, &errorPointer)
        if status != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errorPointer)
            throw SQLiteError(code: status, message: message, sql: sql)
        }
    }

    /// Runs a single statement with bound parameters and returns the number of affected rows.
    @discardableResult
    public func run(_ sql: String, _ parameters: [SQLValue] = []) throws -> Int {
        let statement = try prepare(sql)
        try statement.bind(parameters)
        while try statement.step() {}
        return changes
    }

    /// Runs a single statement and collects every row it produces.
    public func query(_ sql: String, _ parameters: [SQLValue] = []) throws -> ResultSet {
        let statement = try prepare(sql)
        try statement.bind(parameters)
        var result = ResultSet(columnNames: statement.columnNames)
        while try statement.step() {
            result.rows.append(statement.currentRow())
        }
        return result
    }

    /// Convenience for single-value queries such as `SELECT COUNT(*)`.
    public func scalar(_ sql: String, _ parameters: [SQLValue] = []) throws -> SQLValue {
        try query(sql, parameters).rows.first?.first ?? .null
    }

    /// Executes `body` inside a transaction, rolling back if it throws.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// Runs `PRAGMA integrity_check` and returns the engine's messages.
    public func integrityCheck() throws -> [String] {
        try query("PRAGMA integrity_check").rows.compactMap { $0.first?.stringValue }
    }

    /// Reclaims unused space.
    public func vacuum() throws { try execute("VACUUM") }

    /// The current journal mode (`delete`, `wal`, …).
    public var journalMode: String {
        (try? scalar("PRAGMA journal_mode"))?.stringValue ?? "unknown"
    }

    /// Merges the write-ahead log into the main database file.
    ///
    /// A `TRUNCATE` checkpoint reports zero pages once it succeeds, so the work is done in two
    /// steps: `FULL` moves the pages and reports how many, then `TRUNCATE` shrinks the file.
    /// - Returns: the number of pages moved into the database.
    @discardableResult
    public func checkpointWAL(truncate: Bool = true) throws -> Int64 {
        // Columns are (busy, pages in the WAL, pages checkpointed).
        let result = try query("PRAGMA wal_checkpoint(FULL)")
        let pages = result.rows.first?.dropFirst().first?.intValue ?? 0
        if truncate {
            _ = try? query("PRAGMA wal_checkpoint(TRUNCATE)")
        }
        return pages
    }

    /// The sidecar files sitting next to this database right now.
    public var sidecars: DatabaseSidecars { DatabaseSidecars.detect(for: url) }

    /// File size on disk, in bytes.
    public var fileSize: Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Returns `true` when the file at `url` starts with the SQLite 3 magic header.
    public static func isSQLiteFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 16), data.count == 16 else { return false }
        return data == Data("SQLite format 3\0".utf8)
    }
}
