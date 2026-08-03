import Cocoa
import QuickLookThumbnailing
import QLiteKit

/// Draws Finder thumbnails: a document card listing the first few table names.
final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        // Row counts are skipped here: thumbnails must be cheap even for huge files.
        let summary = try? DatabaseSummary.load(url: request.fileURL, maxTables: 6, sampleRowCount: 0)
        let size = request.maximumSize

        let reply = QLThumbnailReply(contextSize: size) { context -> Bool in
            Self.draw(summary: summary, size: size, in: context)
            return true
        }
        handler(reply, nil)
    }

    private static func draw(summary: DatabaseSummary?, size: CGSize, in context: CGContext) {
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext

        let rect = CGRect(origin: .zero, size: size)
        let cornerRadius = min(size.width, size.height) * 0.08
        let card = NSBezierPath(roundedRect: rect.insetBy(dx: size.width * 0.04, dy: size.height * 0.04),
                                xRadius: cornerRadius,
                                yRadius: cornerRadius)
        NSColor.white.setFill()
        card.fill()
        NSColor.systemBlue.withAlphaComponent(0.9).setStroke()
        card.lineWidth = max(1, size.width * 0.012)
        card.stroke()

        // Header band.
        let headerHeight = size.height * 0.22
        let headerRect = CGRect(x: rect.minX + size.width * 0.04,
                                y: rect.maxY - size.height * 0.04 - headerHeight,
                                width: size.width * 0.92,
                                height: headerHeight)
        let header = NSBezierPath(roundedRect: headerRect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.systemBlue.setFill()
        header.fill()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(6, size.height * 0.11), weight: .bold),
            .foregroundColor: NSColor.white
        ]
        NSString(string: "SQLite").draw(at: CGPoint(x: headerRect.minX + size.width * 0.06,
                                                    y: headerRect.midY - size.height * 0.06),
                                        withAttributes: titleAttributes)

        guard size.height > 48 else {
            NSGraphicsContext.restoreGraphicsState()
            return
        }

        let lineAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: max(5, size.height * 0.062), weight: .regular),
            .foregroundColor: NSColor.black.withAlphaComponent(0.75)
        ]
        var y = headerRect.minY - size.height * 0.10
        let lines = summary.map { summary -> [String] in
            var lines = summary.tables.map { "▸ \($0.name)" }
            if summary.tableCount > summary.tables.count {
                lines.append("… +\(summary.tableCount - summary.tables.count)")
            }
            return lines.isEmpty ? ["(no tables)"] : lines
        } ?? ["(unreadable)"]

        for line in lines {
            guard y > rect.minY + size.height * 0.06 else { break }
            NSString(string: line).draw(at: CGPoint(x: rect.minX + size.width * 0.10, y: y),
                                        withAttributes: lineAttributes)
            y -= size.height * 0.095
        }

        NSGraphicsContext.restoreGraphicsState()
    }
}
