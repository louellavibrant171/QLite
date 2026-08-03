import AppKit
import UniformTypeIdentifiers

/// Enables, disables and refreshes QLite's QuickLook extensions, and binds file extensions
/// to QLite as their default application.
///
/// Extension state lives in PlugInKit, which has no public API, so these operations shell out
/// to the same tools a user would run in Terminal. That is also why QLite is not sandboxed.
enum QuickLookRegistration {
    enum Kind {
        case preview
        case thumbnail

        var bundleIdentifier: String {
            switch self {
            case .preview: return "com.qlite.QLite.Preview"
            case .thumbnail: return "com.qlite.QLite.Thumbnail"
            }
        }
    }

    /// Marks an extension as used or ignored for the current user.
    @discardableResult
    static func setEnabled(_ enabled: Bool, for kind: Kind) -> Bool {
        run("/usr/bin/pluginkit", ["-e", enabled ? "use" : "ignore", "-i", kind.bundleIdentifier]) != nil
    }

    /// Re-registers the app bundle and flushes the QuickLook caches, which is the standard
    /// remedy when Finder keeps showing a stale preview.
    /// - Returns: `nil` on success, otherwise a message describing what failed.
    static func refresh() -> String? {
        let appURL = Bundle.main.bundleURL
        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/"
            + "LaunchServices.framework/Versions/A/Support/lsregister"

        if run(lsregister, ["-f", "-R", appURL.path]) == nil {
            return "lsregister"
        }
        for appex in pluginURLs() {
            _ = run("/usr/bin/pluginkit", ["-a", appex.path])
        }
        _ = run("/usr/bin/qlmanage", ["-r"])
        _ = run("/usr/bin/qlmanage", ["-r", "cache"])
        return nil
    }

    private static func pluginURLs() -> [URL] {
        let plugins = Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns")
        let contents = try? FileManager.default.contentsOfDirectory(at: plugins,
                                                                   includingPropertiesForKeys: nil)
        return (contents ?? []).filter { $0.pathExtension == "appex" }
    }

    /// Makes QLite the default application for every extension in `extensions` that the app
    /// actually declares. Undeclared types are returned so the UI can explain the omission.
    @discardableResult
    static func bindDefaultApplication(for extensions: [String]) -> (bound: Int, skipped: [String]) {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.qlite.QLite"
        var bound = 0
        var skipped: [String] = []

        for ext in extensions {
            guard DatabaseFileExtensions.declared.contains(ext),
                  let type = UTType(filenameExtension: ext) else {
                skipped.append(ext)
                continue
            }
            let status = LSSetDefaultRoleHandlerForContentType(type.identifier as CFString,
                                                              .all,
                                                              bundleID as CFString)
            if status == noErr { bound += 1 } else { skipped.append(ext) }
        }
        return (bound, skipped)
    }

    /// Runs a tool and returns its standard output, or `nil` when it could not run or exited
    /// with a failure status.
    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: launchPath) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return nil
        }
    }
}

/// The extensions declared in QLite's Info.plist, read at runtime so the list cannot drift
/// away from what the bundle actually claims.
enum DatabaseFileExtensions {
    static let declared: [String] = {
        guard let types = Bundle.main.object(forInfoDictionaryKey: "UTImportedTypeDeclarations") as? [[String: Any]] else {
            return []
        }
        return types.flatMap { declaration -> [String] in
            let tags = declaration["UTTypeTagSpecification"] as? [String: Any]
            return (tags?["public.filename-extension"] as? [String]) ?? []
        }
    }()
}
