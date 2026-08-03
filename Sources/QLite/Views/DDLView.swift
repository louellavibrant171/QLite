import SwiftUI
import QLiteKit

/// The DDL tab: the `CREATE` statement of the selected object.
struct DDLView: View {
    @ObservedObject var model: DatabaseModel

    var body: some View {
        if let object = model.selectedObject {
            VStack(spacing: 0) {
                // A two-axis ScrollView centres content smaller than its viewport and ignores
                // `.infinity` frames, so the statement is padded out to the measured size.
                GeometryReader { proxy in
                    ScrollView([.vertical, .horizontal]) {
                        Text(object.sql.isEmpty ? L("ddl.noSQL") : object.sql + ";")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(16)
                            .frame(minWidth: proxy.size.width,
                                   minHeight: proxy.size.height,
                                   alignment: .topLeading)
                    }
                }
                Divider()
                HStack {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(object.sql, forType: .string)
                        model.status = L("ddl.copied")
                    } label: {
                        Label(L("ddl.copy"), systemImage: "doc.on.doc")
                    }
                    Button {
                        model.queryText = object.sql + ";"
                        model.tab = .query
                    } label: {
                        Label(L("ddl.openInQuery"), systemImage: "terminal")
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        } else {
            ContentUnavailableView(L("structure.noObject"), systemImage: "curlybraces")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The Info tab: file and PRAGMA properties plus maintenance actions.
struct DatabaseInfoView: View {
    @ObservedObject var model: DatabaseModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(model.databaseName).font(.title2.bold())

                VStack(spacing: 0) {
                    ForEach(model.databaseProperties, id: \.0) { key, value in
                        HStack(alignment: .top) {
                            Text(key)
                                .foregroundStyle(.secondary)
                                .frame(width: 150, alignment: .leading)
                            Text(value)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 5)
                        Divider()
                    }
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))

                sidecarSection

                HStack {
                    Button(L("info.integrityCheck")) { model.integrityCheck() }
                    Button(L("info.vacuum")) { model.vacuum() }
                    Button(L("info.reveal")) {
                        NSWorkspace.shared.activateFileViewerSelecting([model.url])
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The `-wal` / `-shm` / `-journal` files sitting next to the database, plus a checkpoint
    /// action when the write-ahead log holds data the main file does not have yet.
    @ViewBuilder
    private var sidecarSection: some View {
        let sidecars = model.sidecars
        VStack(alignment: .leading, spacing: 8) {
            Text(L("info.sidecars")).font(.headline)

            if sidecars.all.isEmpty {
                Text(L("info.noSidecars"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(sidecars.all, id: \.name) { sidecar in
                        HStack {
                            Text(sidecar.name)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(ByteCountFormatter.string(fromByteCount: sidecar.size, countStyle: .file))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 5)
                        Divider()
                    }
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))

                if sidecars.hasPendingWAL {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(.orange)
                        Text(L("info.walPending",
                               ByteCountFormatter.string(fromByteCount: sidecars.wal?.size ?? 0, countStyle: .file)))
                            .font(.callout)
                        Spacer()
                        Button(L("info.checkpoint")) { model.checkpointWAL() }
                    }
                }
            }
        }
    }
}

/// The launch window: recent databases plus the primary open actions.
struct WelcomeView: View {
    private var recents: [URL] { RecentDatabases.shared.urls }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "cylinder.split.1x2")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("QLite").font(.largeTitle.bold())
                Text(L("welcome.subtitle"))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    (NSApp.delegate as? AppDelegate)?.openDocument(nil)
                } label: {
                    Label(L("welcome.open"), systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)

                Button {
                    (NSApp.delegate as? AppDelegate)?.newDocument(nil)
                } label: {
                    Label(L("welcome.new"), systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
            .padding(24)
            .frame(width: 280)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(L("welcome.recent")).font(.headline).padding(.horizontal, 16).padding(.top, 20)
                if recents.isEmpty {
                    Spacer()
                    Text(L("welcome.noRecent"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    List(recents, id: \.self) { url in
                        Button {
                            (NSApp.delegate as? AppDelegate)?.open(url: url)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(url.lastPathComponent).fontWeight(.medium)
                                Text(url.deletingLastPathComponent().path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.head)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.inset)
                }
            }
        }
        .frame(width: 620, height: 380)
    }
}
