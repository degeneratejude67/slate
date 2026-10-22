import SwiftUI
import PhotosUI
import PencilKit
import UniformTypeIdentifiers

/// The editor with GoodNotes-style tabs for every open notebook.
struct EditorContainer: View {
    @EnvironmentObject private var lib: LibraryModel

    var body: some View {
        VStack(spacing: 0) {
            if lib.tabs.count > 1 { TabStrip() }
            if let url = lib.activeTab {
                NotebookEditorView(url: url)
                    .id(url)
            } else {
                Color.clear.onAppear { lib.editorShown = false }
            }
        }
    }
}

struct TabStrip: View {
    @EnvironmentObject private var lib: LibraryModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(lib.tabs, id: \.self) { url in
                    let active = url == lib.activeTab
                    HStack(spacing: 6) {
                        Text(url.deletingPathExtension().lastPathComponent)
                            .font(.footnote.weight(active ? .semibold : .regular))
                            .lineLimit(1)
                        Button { lib.closeTab(url) } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .frame(maxWidth: 220)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(active ? Color(uiColor: .systemBackground) : Color.primary.opacity(0.05)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(active ? 0.12 : 0)))
                    .onTapGesture { lib.activeTab = url }
                    .accessibilityIdentifier("tab-" + url.deletingPathExtension().lastPathComponent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .background(.bar)
    }
}

struct NotebookEditorView: View {
    let url: URL

    @EnvironmentObject private var lib: LibraryModel
    @StateObject private var state = EditorState()
    @ObservedObject private var settings = AppSettings.shared
    @State private var document: NotebookDocument?
    @State private var loadError: String?
    @State private var photoItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            EditorNavBar(state: state, title: document?.meta.title ?? "", onClose: close)
            Divider().opacity(0.6)
            if settings.prefs.toolbar == .top {
                EditorToolRow(state: state)
                Divider()
            }
            HStack(spacing: 0) {
                canvasArea
                if let reference = state.referenceURL {
                    Divider()
                    ReferencePane(url: reference) { state.referenceURL = nil }
                        .containerRelativeFrame(.horizontal) { width, _ in width * 0.45 }
                        .id(reference)
                }
            }
            if settings.prefs.toolbar == .bottom {
                Divider()
                EditorToolRow(state: state)
                    .background(.bar)
            }
        }
        .background(.bar)
        .sheet(isPresented: $state.showPages) {
            if let document { PageGridView(document: document, state: state) }
        }
        .sheet(isPresented: $state.showStickers) {
            StickerPickerView(state: state)
        }
        .sheet(isPresented: $state.showReferencePicker) {
            ReferencePicker(current: url, state: state)
                .environmentObject(lib)
        }
        .sheet(item: $state.shareItem) { item in
            ActivityView(items: [item.url])
        }
        .photosPicker(isPresented: $state.showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    state.controller?.insertImage(image)
                }
                photoItem = nil
            }
        }
        .fileImporter(isPresented: $state.showImageImporter, allowedContentTypes: [.image]) { result in
            guard case .success(let file) = result else { return }
            let scoped = file.startAccessingSecurityScopedResource()
            defer { if scoped { file.stopAccessingSecurityScopedResource() } }
            if let image = UIImage(contentsOfFile: file.path) {
                state.controller?.insertImage(image)
            } else {
                state.errorMessage = "That file isn't a picture Slate can read."
            }
        }
        .alert("Slate", isPresented: Binding(get: { state.errorMessage != nil },
                                             set: { if !$0 { state.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.errorMessage ?? "")
        }
        .onReceive(state.audio.$errorMessage) { message in
            if let message { state.errorMessage = message }
        }
        .onAppear(perform: load)
    }

    private var canvasArea: some View {
        ZStack(alignment: .bottom) {
            if let document {
                CanvasHost(document: document, state: state)
                    .ignoresSafeArea(.container, edges: settings.prefs.toolbar == .top ? .bottom : [])
            } else if let loadError {
                ContentUnavailableView("Can't open this notebook", systemImage: "exclamationmark.triangle",
                                       description: Text(loadError))
            } else {
                ProgressView()
            }
            PlayerBar(audio: state.audio)
            if settings.prefs.showPageNumber && !state.pageLabel.isEmpty {
                Text(state.pageLabel)
                    .font(.footnote.monospacedDigit().weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 18)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("page-label")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func load() {
        guard document == nil else { return }
        do {
            let doc = try NotebookDocument(url: url)
            if let page = lib.pendingPage.removeValue(forKey: url) {
                doc.meta.lastPage = min(max(page, 0), max(doc.pageCount - 1, 0))
            }
            document = doc
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func close() {
        state.controller?.saveNow()
        lib.editorShown = false
    }
}

struct CanvasHost: UIViewControllerRepresentable {
    let document: NotebookDocument
    let state: EditorState

    func makeUIViewController(context: Context) -> NotebookCanvasController {
        NotebookCanvasController(document: document, state: state)
    }

    func updateUIViewController(_ controller: NotebookCanvasController, context: Context) {}
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Pick a notebook to show beside this one (a past paper next to your working, say).
struct ReferencePicker: View {
    let current: URL
    @ObservedObject var state: EditorState
    @EnvironmentObject private var lib: LibraryModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if state.referenceURL != nil {
                    Button(role: .destructive) {
                        state.referenceURL = nil
                        dismiss()
                    } label: { Label("Close Side View", systemImage: "xmark.rectangle") }
                }
                let others = lib.store.allNotebooks().filter { $0.url != current }
                Section("Open beside this notebook") {
                    ForEach(others) { entry in
                        Button {
                            state.referenceURL = entry.url
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "book.closed")
                                VStack(alignment: .leading) {
                                    Text(entry.name)
                                    Text(lib.store.displayPath(entry.url.deletingLastPathComponent()))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("reference-" + entry.name)
                    }
                }
            }
            .navigationTitle("Side View")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

/// A read-only view of another notebook, with its ink and items, beside the editor.
struct ReferencePane: View {
    let url: URL
    let onClose: () -> Void
    @State private var document: NotebookDocument?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "book.closed")
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("close-reference")
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(.bar)
            Divider()
            GeometryReader { geo in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if let document {
                            ForEach(0..<document.pageCount, id: \.self) { index in
                                ReferencePage(document: document, index: index, width: max(geo.size.width - 28, 100))
                            }
                        }
                    }
                    .padding(14)
                }
            }
        }
        .background(Color(uiColor: Theme.desk))
        .onAppear { document = try? NotebookDocument(url: url) }
    }
}

private struct ReferencePage: View {
    let document: NotebookDocument
    let index: Int
    let width: CGFloat
    @State private var image: UIImage?

    var body: some View {
        let size = document.pageSize(at: index)
        ZStack {
            if let image {
                Image(uiImage: image).resizable()
            } else {
                Color.white
            }
        }
        .frame(width: width, height: width * size.height / max(size.width, 1))
        .shadow(color: .black.opacity(0.14), radius: 3, y: 1)
        .task(id: Int(width)) {
            let page = document.pdf.page(at: index)
            let id = document.meta.pages[safe: index]?.id
            let ink = id.map { document.drawing(for: $0) } ?? PKDrawing()
            let items = document.items(onPage: index)
            var pictures: [String: UIImage] = [:]
            for item in items where item.kind == .image {
                if let name = item.image { pictures[name] = document.image(named: name) }
            }
            let loaded = pictures
            let renderWidth = width * 1.5
            image = await Task.detached(priority: .userInitiated) {
                Thumbnailer.image(page: page, pageSize: size, drawing: ink, width: renderWidth,
                                  items: items, imageLoader: { loaded[$0] })
            }.value
        }
    }
}

struct StickerPickerView: View {
    @ObservedObject var state: EditorState
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    private var packs: [StickerPack] {
        StickerCatalog.packs.filter { settings.prefs.stickerPacks.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if packs.isEmpty {
                        Text("No sticker packs yet. Add some in Marketplace.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    }
                    ForEach(Array(packs.enumerated()), id: \.element.id) { packIndex, pack in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(pack.name).font(.headline)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 14)], spacing: 14) {
                                ForEach(Array(pack.stickers.enumerated()), id: \.element.id) { i, sticker in
                                    Button {
                                        dismiss()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            state.controller?.insertSticker(sticker)
                                        }
                                    } label: {
                                        Image(uiImage: StickerCatalog.image(for: sticker, width: 160))
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 70, height: 60)
                                            .padding(6)
                                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("sticker-\(packIndex)-\(i)")
                                }
                            }
                        }
                    }
                    Text("More packs are free in Marketplace, in the library sidebar.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .navigationTitle("Stickers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
