import Cocoa
import SwiftUI
import QuickLookUI
import QLiteKit

/// Localized string for the preview. Extensions follow the system language rather than the
/// app's language preference, which lives in the app's own defaults domain.
private func L(_ key: String, _ arguments: CVarArg...) -> String {
    let bundle = Bundle(for: PreviewViewController.self)
    let format = bundle.localizedString(forKey: key, value: key, table: nil)
    return arguments.isEmpty ? format : String(format: format, arguments: arguments)
}

/// QuickLook preview: renders a database's schema and sample rows without launching QLite.
final class PreviewViewController: NSViewController, QLPreviewingController {
    private var hostingView: NSView?

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    func preparePreviewOfFile(at url: URL) async throws {
        // The summary is capped so previewing a multi-gigabyte database stays instant.
        let summary = try DatabaseSummary.load(url: url, maxTables: 10, sampleRowCount: 5)
        await MainActor.run { self.install(PreviewContentView(summary: summary)) }
    }

    @MainActor
    private func install<Content: View>(_ content: Content) {
        hostingView?.removeFromSuperview()
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingView = hosting
    }
}

/// The preview layout: a header, then one card per table with its columns and sample rows.
struct PreviewContentView: View {
    let summary: DatabaseSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                ForEach(summary.tables) { table in
                    TableCard(table: table)
                }
                ForEach(summary.views) { view in
                    TableCard(table: view)
                }
                if summary.tableCount > summary.tables.count {
                    Text(L("preview.moreTables", summary.tableCount - summary.tables.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if summary.tables.isEmpty && summary.views.isEmpty {
                    Text(L("preview.noTables"))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "cylinder.split.1x2.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                Text(summary.fileName).font(.title3.bold()).lineLimit(1)
            }
            Text(summary.headline)
                .font(.callout)
                .foregroundStyle(.secondary)

            // Tell the user when the preview could not include write-ahead log content.
            if summary.walIsStale {
                Label(L("preview.walStale"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if summary.pendingWALBytes > 0 {
                Label(L("preview.walIncluded",
                        ByteCountFormatter.string(fromByteCount: summary.pendingWALBytes, countStyle: .file)),
                      systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One table: name, row count, column list and a few sample rows.
struct TableCard: View {
    let table: DatabaseSummary.TableSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: table.kind.symbolName).foregroundStyle(.secondary)
                Text(table.name).font(.headline)
                Spacer()
                Text(L("preview.rows", table.rowCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text(table.columns.map { "\($0.name) \($0.type)" }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if !table.sampleRows.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        row(table.columns.map(\.name), isHeader: true)
                        ForEach(Array(table.sampleRows.enumerated()), id: \.offset) { _, values in
                            row(values.map { $0.isNull ? "NULL" : $0.displayString }, isHeader: false)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private func row(_ cells: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell)
                    .font(.system(size: 11, design: .monospaced))
                    .fontWeight(isHeader ? .semibold : .regular)
                    .foregroundStyle(isHeader ? .secondary : .primary)
                    .lineLimit(1)
                    .frame(width: 130, alignment: .leading)
                    .padding(.trailing, 6)
            }
        }
    }
}
