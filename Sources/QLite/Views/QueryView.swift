import SwiftUI
import QLiteKit

/// The Query tab: a SQL editor above the result grid.
struct QueryView: View {
    @ObservedObject var model: DatabaseModel
    @State private var resultSelection: Set<Int> = []

    var body: some View {
        // VSplitView hands its children their ideal size, so both panes have to ask for the
        // full width explicitly or they end up centred at the text view's intrinsic width.
        VSplitView {
            editor
                .frame(maxWidth: .infinity, minHeight: 140, idealHeight: 220, maxHeight: .infinity)
            results
                .frame(maxWidth: .infinity, minHeight: 160, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editor: some View {
        VStack(spacing: 0) {
            SQLTextView(text: $model.queryText, onRun: { model.runQuery() })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            Divider()
            HStack(spacing: 8) {
                Button {
                    model.runQuery()
                } label: {
                    Label(L("query.run"), systemImage: "play.fill")
                }
                .keyboardShortcut("r", modifiers: .command)

                Button(L("query.explain")) { model.explainQuery() }

                Menu(L("query.templates")) {
                    ForEach(Self.templates, id: \.0) { key, sql in
                        Button(L(key)) { model.queryText = sql }
                    }
                }
                .fixedSize()

                Spacer()

                if let execution = model.execution {
                    Text(execution.summary)
                        .font(.caption)
                        .foregroundStyle(execution.error == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var results: some View {
        if let statement = model.execution?.displayedResult, let set = statement.resultSet, !set.columnNames.isEmpty {
            DataGrid(columns: set.columnNames,
                     rows: set.rows.enumerated().map { DataGridRow(id: $0.offset, values: $0.element) },
                     selection: $resultSelection,
                     contextActions: { ids in
                         AnyView(Button(L("data.copyCSV")) {
                             let rows = ids.sorted().compactMap { $0 < set.rows.count ? set.rows[$0] : nil }
                             let copy = ResultSet(columnNames: set.columnNames, rows: rows)
                             NSPasteboard.general.clearContents()
                             NSPasteboard.general.setString(Exporter.string(from: copy, format: .csv), forType: .string)
                         })
                     })
        } else if let error = model.execution?.error {
            ScrollView {
                Text(error.localizedDescription)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        } else {
            ContentUnavailableView(L("query.noResults"),
                                   systemImage: "terminal",
                                   description: Text(L("query.noResultsHint")))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    static let templates: [(String, String)] = [
        ("query.template.select", "SELECT * FROM table_name LIMIT 100;"),
        ("query.template.count", "SELECT COUNT(*) AS row_count FROM table_name;"),
        ("query.template.tables", "SELECT name, type FROM sqlite_master ORDER BY type, name;"),
        ("query.template.sizes", """
        SELECT m.name AS table_name,
               (SELECT COUNT(*) FROM pragma_table_info(m.name)) AS columns
        FROM sqlite_master m
        WHERE m.type = 'table'
        ORDER BY table_name;
        """),
        ("query.template.create", """
        CREATE TABLE new_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );
        """)
    ]
}

/// An `NSTextView` wrapper: SwiftUI's `TextEditor` lacks monospaced tab handling and a
/// keyboard shortcut hook for running the query.
struct SQLTextView: NSViewRepresentable {
    @Binding var text: String
    var onRun: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.string = text
        textView.allowsUndo = true
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onRun: onRun)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        private let onRun: () -> Void

        init(text: Binding<String>, onRun: @escaping () -> Void) {
            self.text = text
            self.onRun = onRun
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        /// ⌘↩ / the Enter key on the numeric keypad runs the query.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSTextView.insertNewlineIgnoringFieldEditor(_:)) {
                onRun()
                return true
            }
            return false
        }
    }
}
