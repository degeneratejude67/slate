import SwiftUI

/// Notability-style subject sidebar on the left, GoodNotes-style cover grid on the right.
struct LibraryView: View {
    @EnvironmentObject private var lib: LibraryModel
    @State private var selection: URL?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            NavigationStack {
                FolderView(folder: selection ?? lib.store.root, selection: $selection)
                    .id(selection ?? lib.store.root)
            }
        }
        .fullScreenCover(item: $lib.openNotebook, onDismiss: { lib.refresh() }) { item in
            NotebookEditorView(url: item.url)
        }
        .alert("Slate", isPresented: Binding(get: { lib.errorMessage != nil },
                                             set: { if !$0 { lib.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(lib.errorMessage ?? "")
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var lib: LibraryModel
    @Binding var selection: URL?

    var body: some View {
        let _ = lib.revision
        List(selection: $selection) {
            Label("Documents", systemImage: "doc.on.doc")
                .tag(lib.store.root)
            Section("Folders") {
                OutlineGroup(lib.store.folderTree(), children: \.children) { node in
                    Label(node.name, systemImage: "folder")
                        .tag(node.url)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Slate")
    }
}
