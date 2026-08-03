import AppKit

// QLite drives its own AppKit lifecycle: SwiftUI's DocumentGroup would read whole database
// files into memory, and QLite needs a long-lived SQLite connection per window instead.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    // Keep the delegate alive for the process lifetime.
    objc_setAssociatedObject(application, "QLiteAppDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
    application.run()
}
