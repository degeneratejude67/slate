import SwiftUI
import PencilKit

/// All pages as thumbnails. Tap to jump; press and hold to add, move or delete a page.
struct PageGridView: View {
    let document: NotebookDocument
    @ObservedObject var state: EditorState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let _ = state.pagesRevision
        let drawings = state.controller?.pageDrawings() ?? []
        let count = document.pageCount
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 22)], spacing: 26) {
                    ForEach(Array(document.meta.pages.enumerated()), id: \.element.id) { index, _ in
                        VStack(spacing: 6) {
                            PageThumbnail(document: document, index: index,
                                          drawing: drawings[safe: index] ?? PKDrawing())
                            Text("\(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismiss()
                            DispatchQueue.main.async { state.controller?.scrollToPage(index, animated: false) }
                        }
                        .contextMenu {
                            Button { state.controller?.insertPage(paper: nil, after: index) } label: {
                                Label("Add Page After", systemImage: "plus.square.on.square")
                            }
                            Button { state.controller?.movePage(from: index, to: index - 1) } label: {
                                Label("Move Up", systemImage: "arrow.up")
                            }
                            .disabled(index == 0)
                            Button { state.controller?.movePage(from: index, to: index + 1) } label: {
                                Label("Move Down", systemImage: "arrow.down")
                            }
                            .disabled(index == count - 1)
                            Button(role: .destructive) { state.controller?.deletePage(at: index) } label: {
                                Label("Delete Page", systemImage: "trash")
                            }
                            .disabled(count <= 1)
                        }
                        .accessibilityIdentifier("page-thumb-\(index)")
                    }
                }
                .padding(24)
            }
            .background(Color(uiColor: Theme.desk))
            .navigationTitle("Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct PageThumbnail: View {
    let document: NotebookDocument
    let index: Int
    let drawing: PKDrawing
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
        .aspectRatio(size.width / max(size.height, 1), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .shadow(color: .black.opacity(0.16), radius: 3, y: 1)
        .task(id: "\(index)-\(drawing.strokes.count)-\(document.meta.pages[safe: index]?.id.uuidString ?? "")") {
            let page = document.pdf.page(at: index)
            let ink = drawing
            let items = document.items(onPage: index)
            var pictures: [String: UIImage] = [:]
            for item in items where item.kind == .image {
                if let name = item.image { pictures[name] = document.image(named: name) }
            }
            let loaded = pictures
            let rendered = await Task.detached(priority: .userInitiated) {
                Thumbnailer.image(page: page, pageSize: size, drawing: ink, width: 220,
                                  items: items, imageLoader: { loaded[$0] })
            }.value
            image = rendered
        }
    }
}
