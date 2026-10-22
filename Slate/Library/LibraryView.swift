import SwiftUI

enum SidebarItem: Hashable {
    case documents
    case folder(URL)
    case marketplace
    case settings
}

/// GoodNotes-style home: sidebar with Documents, folders (Notability-style subjects),
/// Marketplace and Settings; the cover grid or the chosen screen on the right.
struct LibraryView: View {
    @EnvironmentObject private var lib: LibraryModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: SidebarItem? = LibraryView.initialSelection

    private static var initialSelection: SidebarItem {
        if AppEnv.arguments.contains("-uitest-marketplace") { return .marketplace }
        if AppEnv.arguments.contains("-uitest-settings") { return .settings }
        return .documents
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            NavigationStack {
                detail
            }
        }
        .fullScreenCover(item: $lib.openNotebook, onDismiss: { lib.refresh() }) { item in
            NotebookEditorView(url: item.url)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && lib.openNotebook == nil { lib.rescan() }
        }
        .alert("Slate", isPresented: Binding(get: { lib.errorMessage != nil },
                                             set: { if !$0 { lib.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(lib.errorMessage ?? "")
        }
    }

    @ViewBuilder private var detail: some View {
        switch selection ?? .documents {
        case .documents:
            FolderView(folder: lib.store.root, selection: $selection)
                .id(lib.store.root)
        case .folder(let url):
            FolderView(folder: url, selection: $selection)
                .id(url)
        case .marketplace:
            MarketplaceView()
        case .settings:
            SettingsView()
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var lib: LibraryModel
    @Binding var selection: SidebarItem?

    var body: some View {
        let _ = lib.revision
        List(selection: $selection) {
            Label("Documents", systemImage: "doc.on.doc")
                .tag(SidebarItem.documents)
            Section("Subjects") {
                OutlineGroup(lib.store.folderTree(), children: \.children) { node in
                    Label(node.name, systemImage: "folder")
                        .tag(SidebarItem.folder(node.url))
                }
            }
            Section {
                Label("Marketplace", systemImage: "storefront")
                    .tag(SidebarItem.marketplace)
                Label("Settings", systemImage: "gearshape")
                    .tag(SidebarItem.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Slate")
    }
}

/// Shown above the library when the free Apple ID signature is about to run out.
struct ExpiryBanner: View {
    var body: some View {
        if let days = Provisioning.daysLeft, let expiry = Provisioning.expiry, days <= 2 {
            HStack(spacing: 12) {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(days <= 0 ? "Re-sign Slate today" : "Re-sign Slate within \(days) day\(days == 1 ? "" : "s")")
                        .font(.subheadline.weight(.semibold))
                    Text("The signature ends \(expiry.formatted(date: .abbreviated, time: .shortened)). Plug into the PC and use iloader; your notebooks stay.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
            .padding(.horizontal, 32)
            .padding(.top, 12)
        }
    }
}
