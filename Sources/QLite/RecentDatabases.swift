import Foundation

/// Tracks recently opened databases as file bookmarks, so they survive renames and moves.
///
/// Security-scoped bookmarks only exist for sandboxed apps. QLite is not sandboxed (see
/// `QLite.entitlements`), so plain bookmarks are used, with the security-scoped variants kept
/// as a fallback for anyone running a sandboxed build.
final class RecentDatabases {
    static let shared = RecentDatabases()

    private let defaultsKey = "recentDatabaseBookmarks"
    private let limit = 15
    private var accessedURLs: Set<URL> = []

    /// True when the process runs inside an App Sandbox container.
    private let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    private init() {}

    /// Recently opened files, most recent first. Missing files are filtered out.
    var urls: [URL] {
        bookmarks.compactMap { resolve($0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private var bookmarks: [Data] {
        get { UserDefaults.standard.array(forKey: defaultsKey) as? [Data] ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    func remember(url: URL) {
        let options: URL.BookmarkCreationOptions = isSandboxed ? [.withSecurityScope] : []
        guard let data = try? url.bookmarkData(options: options,
                                               includingResourceValuesForKeys: nil,
                                               relativeTo: nil) else { return }
        var stored = bookmarks.filter { resolve($0) != url }
        stored.insert(data, at: 0)
        bookmarks = Array(stored.prefix(limit))
    }

    func clear() {
        bookmarks = []
    }

    /// Resolves a bookmark, starting security-scoped access when the data carries a scope.
    /// Any access opened here stays open for the lifetime of the process.
    private func resolve(_ data: Data) -> URL? {
        var isStale = false
        let options: URL.BookmarkResolutionOptions = isSandboxed ? [.withSecurityScope] : []
        var resolved = try? URL(resolvingBookmarkData: data,
                                options: options,
                                relativeTo: nil,
                                bookmarkDataIsStale: &isStale)
        if resolved == nil && !isSandboxed {
            // Bookmarks written by an older sandboxed build still resolve with the scope flag.
            resolved = try? URL(resolvingBookmarkData: data,
                                options: [.withSecurityScope],
                                relativeTo: nil,
                                bookmarkDataIsStale: &isStale)
        }
        guard let url = resolved else { return nil }
        if isSandboxed, !accessedURLs.contains(url), url.startAccessingSecurityScopedResource() {
            accessedURLs.insert(url)
        }
        return url
    }
}
