import SwiftUI
import UniformTypeIdentifiers

struct FolderView: View {
    @EnvironmentObject private var lib: LibraryModel
    let folder: URL
    @Binding var selection: URL?

    @State private var showNewNotebook = false
    @State private var showImporter = false
    @State private var askNewFolder = false
    @State private var newFolderName = ""
    @State private var renameTarget: LibraryEntry?
    @State private var renameText = ""
    @State private var deleteTarget: LibraryEntry?

    var body: some View {
        let _ = lib.revision
        let entries = lib.entries(in: folder)
        ScrollView {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("Nothing here yet", systemImage: "books.vertical")
                } description: {
                    Text("Tap + to make a notebook or import a lecture PDF.")
                }
                .padding(.top, 120)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 30, alignment: .top)],
                      spacing: 34) {
                ForEach(entries) { entry in
                    Button { open(entry) } label: {
                        EntryTile(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier((entry.isNotebook ? "notebook-" : "folder-") + entry.name)
                    .contextMenu { menu(for: entry) }
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(folder == lib.store.root ? "Documents" : folder.lastPathComponent)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker("Sort By", selection: $lib.sort) {
                        ForEach(LibrarySort.allCases) { sort in
                            Text(sort.label).tag(sort)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                Menu {
                    Button { showNewNotebook = true } label: {
                        Label("New Notebook", systemImage: "book.closed")
                    }
                    Button { showImporter = true } label: {
                        Label("Import PDF", systemImage: "square.and.arrow.down")
                    }
                    Button { askNewFolder = true } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("add-menu")
            }
        }
        .sheet(isPresented: $showNewNotebook, onDismiss: { lib.openPending() }) {
            NewNotebookSheet(folder: folder)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): lib.importPDFs(urls, into: folder)
            case .failure(let error): lib.errorMessage = error.localizedDescription
            }
        }
        .alert("New Folder", isPresented: $askNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Create") {
                let name = newFolderName
                lib.perform { try lib.store.createFolder(named: name, in: folder) }
                newFolderName = ""
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        }
        .alert("Rename", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let target = renameTarget {
                    let name = renameText
                    lib.perform { try lib.store.rename(target.url, to: name) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(deleteTarget?.name ?? "")”?",
                            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let target = deleteTarget {
                    if selection == target.url { selection = nil }
                    lib.perform { try lib.store.delete(target.url) }
                }
            }
        } message: {
            Text("This deletes it and all its ink. It can't be undone.")
        }
    }

    private func open(_ entry: LibraryEntry) {
        if entry.isNotebook {
            lib.openNotebook = OpenNotebook(url: entry.url)
        } else {
            selection = entry.url
        }
    }

    @ViewBuilder
    private func menu(for entry: LibraryEntry) -> some View {
        Button {
            renameText = entry.name
            renameTarget = entry
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Menu {
            if folder != lib.store.root {
                Button("Documents") { lib.perform { try lib.store.move(entry.url, to: lib.store.root) } }
            }
            ForEach(moveTargets(for: entry), id: \.self) { target in
                Button(lib.store.displayPath(target)) {
                    lib.perform { try lib.store.move(entry.url, to: target) }
                }
            }
        } label: {
            Label("Move To", systemImage: "folder")
        }
        Button(role: .destructive) { deleteTarget = entry } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func moveTargets(for entry: LibraryEntry) -> [URL] {
        let own = entry.url.standardizedFileURL.path
        return lib.store.allFolders().filter { target in
            let path = target.standardizedFileURL.path
            return path != own && !path.hasPrefix(own + "/") && target.standardizedFileURL != folder.standardizedFileURL
        }
    }
}
