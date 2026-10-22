import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct NotebookEditorView: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
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
        .onAppear(perform: load)
    }

    private func load() {
        guard document == nil else { return }
        do {
            document = try NotebookDocument(url: url)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func close() {
        state.controller?.saveNow()
        dismiss()
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
