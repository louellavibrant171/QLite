import Foundation
import SQLite3

/// A compact, read-only description of a database used by the QuickLook preview and thumbnail.
public struct DatabaseSummary {
    public struct TableSummary: Identifiable, Hashable {
        public let name: String
        public let kind: SchemaObjectKind
        public let columns: [ColumnInfo]
        public let rowCount: Int64
        /// A handful of rows shown as a preview.
        public let sampleRows: [[SQLValue]]

        public var id: String { "\(kind.rawValue):\(name)" }
    }

    public let fileName: String
    public let fileSize: Int64
    public let sqliteVersion: String
    /// Detailed summaries, capped by `maxTables`.
    public let tables: [TableSummary]
    public let views: [TableSummary]
    /// Total counts in the file, even when more objects exist than were summarised.
    public let tableCount: Int
    public let viewCount: Int
    public let indexCount: Int
    public let triggerCount: Int
    public let properties: [(String, String)]

    public var totalRowCount: Int64 { tables.reduce(0) { $0 + $1.rowCount } }

    public var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    /// Bytes waiting in the write-ahead log that are not in the main file yet.
    public let pendingWALBytes: Int64
    /// True when the WAL could not be read, so the summary shows the last checkpointed state.
    public let walIsStale: Bool

    /// Reads a summary from `url` without modifying the user's file.
    ///
    /// Uncommitted `-wal` content is included whenever the file set can be opened or copied;
    /// see `Database.openForReading(url:)`.
    /// - Parameters:
    ///   - maxTables: how many tables to describe in detail.
    ///   - sampleRowCount: rows sampled per table (0 disables sampling).
    public static func load(url: URL, maxTables: Int = 12, sampleRowCount: Int = 5) throws -> DatabaseSummary {
        let sidecars = DatabaseSidecars.detect(for: url)
        guard let opened = Database.openForReading(url: url) else {
            throw SQLiteError(code: SQLITE_CANTOPEN, message: "Cannot open \(url.lastPathComponent)")
        }
        let db = opened.database
        // Hold the snapshot until the summary has been read; it deletes its files when released.
        let snapshot = opened.snapshot
        defer {
            db.close()
            withExtendedLifetime(snapshot) {}
        }
        let reader = SchemaReader(database: db)
        let objects = try reader.objects()

        func summarize(_ object: SchemaObject) -> TableSummary {
            let columns = (try? reader.columns(of: object.name)) ?? []
            let count = (try? reader.rowCount(of: object.name)) ?? 0
            var samples: [[SQLValue]] = []
            if sampleRowCount > 0 && !columns.isEmpty {
                let selection = columns.map { quoteIdentifier($0.name) }.joined(separator: ", ")
                let sql = "SELECT \(selection) FROM \(quoteIdentifier(object.name)) LIMIT \(sampleRowCount)"
                samples = (try? db.query(sql).rows) ?? []
            }
            return TableSummary(name: object.name, kind: object.kind, columns: columns, rowCount: count, sampleRows: samples)
        }

        let tableObjects = objects.filter { $0.kind == .table }
        let viewObjects = objects.filter { $0.kind == .view }

        return DatabaseSummary(
            fileName: url.lastPathComponent,
            fileSize: (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)??.int64Value ?? 0,
            sqliteVersion: Database.libraryVersion,
            tables: tableObjects.prefix(maxTables).map(summarize),
            views: viewObjects.prefix(max(0, maxTables - tableObjects.count)).map(summarize),
            tableCount: tableObjects.count,
            viewCount: viewObjects.count,
            indexCount: objects.filter { $0.kind == .index }.count,
            triggerCount: objects.filter { $0.kind == .trigger }.count,
            properties: reader.databaseProperties(),
            pendingWALBytes: sidecars.wal?.size ?? 0,
            walIsStale: opened.walIsStale
        )
    }

    /// One-line description used as the thumbnail caption and preview subtitle.
    public var headline: String {
        var parts = ["\(tableCount) table\(tableCount == 1 ? "" : "s")"]
        if viewCount > 0 { parts.append("\(viewCount) view\(viewCount == 1 ? "" : "s")") }
        if indexCount > 0 { parts.append("\(indexCount) index\(indexCount == 1 ? "" : "es")") }
        parts.append(formattedFileSize)
        return parts.joined(separator: " · ")
    }
}
