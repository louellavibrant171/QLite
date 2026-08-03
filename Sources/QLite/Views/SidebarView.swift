import SwiftUI
import QLiteKit

/// Lists every schema object, grouped by kind, with the object-level actions.
struct SidebarView: View {
    @ObservedObject var model: DatabaseModel
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { model.selectedObjectID },
                set: { id in
                    if let id, let object = model.objects.first(where: { $0.id == id }) {
                        model.selectObject(object)
                    }
                })
            ) {
                ForEach(filteredGroups, id: \.0) { kind, objects in
                    Section(sectionTitle(kind)) {
                        ForEach(objects) { object in
                            Label {
                                Text(object.name).lineLimit(1)
                            } icon: {
                                Image(systemName: kind.symbolName)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(object.id)
                            .contextMenu { contextMenu(for: object) }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack(spacing: 6) {
                Button {
                    model.activeSheet = .newTable
                } label: {
                    Image(systemName: "plus")
                }
                .help(L("sidebar.newTable"))

                Button {
                    if let object = model.selectedObject { confirmDrop(object) }
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(model.selectedObject == nil)
                .help(L("sidebar.dropSelected"))

                Spacer()
                Text(L("sidebar.objectCount", model.objects.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: L("sidebar.filter"))
    }

    /// Plural section titles need their own keys; English plurals are not "name + s".
    private func sectionTitle(_ kind: SchemaObjectKind) -> String {
        switch kind {
        case .table: return L("kind.tables")
        case .view: return L("kind.views")
        case .index: return L("kind.indexes")
        case .trigger: return L("kind.triggers")
        }
    }

    private var filteredGroups: [(SchemaObjectKind, [SchemaObject])] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return model.objectsByKind.compactMap { kind, objects in
            let matching = query.isEmpty ? objects : objects.filter { $0.name.lowercased().contains(query) }
            return matching.isEmpty ? nil : (kind, matching)
        }
    }

    @ViewBuilder
    private func contextMenu(for object: SchemaObject) -> some View {
        if object.kind == .table {
            Button(L("sidebar.addColumn")) { model.activeSheet = .addColumn(object.name) }
            Button(L("sidebar.createIndex")) { model.activeSheet = .createIndex(object.name) }
            Button(L("sidebar.rename")) { model.activeSheet = .renameTable(object.name) }
            Divider()
            Button(L("sidebar.emptyTable")) { confirmEmpty(object) }
        }
        Button(L("sidebar.copyCreate")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(object.sql, forType: .string)
        }
        Button(L("sidebar.queryThis")) {
            model.queryText = "SELECT * FROM \(quoteIdentifier(object.name)) LIMIT 100;"
            model.runQuery()
        }
        Divider()
        Button(L("sidebar.drop"), role: .destructive) { confirmDrop(object) }
    }

    private func confirmDrop(_ object: SchemaObject) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("sidebar.confirmDrop.title", object.name)
        alert.informativeText = L("sidebar.confirmDrop.message")
        alert.addButton(withTitle: L("common.drop"))
        alert.addButton(withTitle: L("common.cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            model.drop(object)
        }
    }

    private func confirmEmpty(_ object: SchemaObject) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("sidebar.confirmEmpty.title", object.name)
        alert.informativeText = L("sidebar.confirmEmpty.message")
        alert.addButton(withTitle: L("sidebar.confirmEmpty.confirm"))
        alert.addButton(withTitle: L("common.cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            model.selectObject(object)
            model.emptyTable(object)
        }
    }
}
