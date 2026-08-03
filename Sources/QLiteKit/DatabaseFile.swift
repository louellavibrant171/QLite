import Foundation

/// File-system facts about a database: which extensions count as databases, and which
/// sidecar files (`-wal`, `-shm`, `-journal`) sit next to the main file.
public enum DatabaseFile {
    /// Extensions QLite recognises out of the box. The Settings window lets users narrow
    /// this list down or add their own.
    public static let defaultExtensions = [
        "db", "db3", "sqlite", "sqlite3", "sqlitedb", "s3db", "sl3", "data", "dat"
    ]

    /// Every extension declared in the app's Info.plist. Types outside this set can still be
    /// opened from the Open panel, they just cannot be bound as a default handler.
    public static let declaredExtensions = [
        "db", "db3", "sqlite", "sqlite3", "sqlitedb", "s3db", "sl3"
    ]

    /// Suffixes SQLite appends to the main database file name.
    public static let sidecarSuffixes = ["-wal", "-shm", "-journal"]

    /// Maps a sidecar path back to the database it belongs to; other URLs are returned as-is.
    /// Opening `foo.db-wal` should open `foo.db`.
    public static func primaryURL(for url: URL) -> URL {
        let path = url.path
        for suffix in sidecarSuffixes where path.hasSuffix(suffix) {
            return URL(fileURLWithPath: String(path.dropLast(suffix.count)))
        }
        return url
    }

    /// True when the extension looks like a database, ignoring case.
    public static func hasDatabaseExtension(_ url: URL, allowed: [String] = defaultExtensions) -> Bool {
        allowed.contains(url.pathExtension.lowercased())
    }
}

/// The write-ahead log and rollback journal accompanying a database.
public struct DatabaseSidecars {
    public struct Sidecar {
        public let url: URL
        public let size: Int64
        public var name: String { url.lastPathComponent }
    }

    public let wal: Sidecar?
    public let shm: Sidecar?
    public let journal: Sidecar?

    /// Data lives in the WAL that has not been checkpointed into the main file yet.
    public var hasPendingWAL: Bool { (wal?.size ?? 0) > 0 }

    /// A rollback journal is present, so the main file may be mid-transaction.
    public var hasJournal: Bool { (journal?.size ?? 0) > 0 }

    public var all: [Sidecar] { [wal, shm, journal].compactMap { $0 } }

    public var urls: [URL] { all.map(\.url) }

    public static func detect(for url: URL) -> DatabaseSidecars {
        func sidecar(_ suffix: String) -> Sidecar? {
            let candidate = URL(fileURLWithPath: url.path + suffix)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: candidate.path) else { return nil }
            return Sidecar(url: candidate, size: (attributes[.size] as? NSNumber)?.int64Value ?? 0)
        }
        return DatabaseSidecars(wal: sidecar("-wal"), shm: sidecar("-shm"), journal: sidecar("-journal"))
    }
}

/// A throwaway copy of a database and its sidecars.
///
/// Read-only consumers (the QuickLook preview) cannot open a WAL database in place: SQLite
/// needs write access to the `-shm` file to replay the log. Copying the whole set to a
/// temporary directory and opening *that* read-write shows uncommitted WAL content without
/// touching the user's file.
public final class DatabaseSnapshot {
    public let url: URL
    private let directory: URL

    private init(url: URL, directory: URL) {
        self.url = url
        self.directory = directory
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    /// Copies `original` plus any `-wal`/`-shm`/`-journal` files into a temporary directory.
    /// Throws if the main file cannot be copied; missing or unreadable sidecars are skipped.
    public static func make(of original: URL) throws -> DatabaseSnapshot {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("qlite-snapshot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let copy = directory.appendingPathComponent(original.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: original, to: copy)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }

        for sidecar in DatabaseSidecars.detect(for: original).all {
            let destination = directory.appendingPathComponent(sidecar.name)
            try? FileManager.default.copyItem(at: sidecar.url, to: destination)
        }
        return DatabaseSnapshot(url: copy, directory: directory)
    }
}
