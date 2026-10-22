import SwiftUI
import PDFKit
import PencilKit

/// All pages as thumbnails, bookmarked pages, or the PDF's own outline. Tap to jump;
/// press and hold a page to add, move or delete it.
struct PageGridView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case pages = "Pages", bookmarks = "Bookmarks", outline = "Outline"
        var id: String { rawValue }
    }

    let document: NotebookDocument
    @ObservedObject var state: EditorState
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .pages

    private struct OutlineRow: Identifiable {
        let id = UUID()
        let title: String
        let page: Int
        let depth: Int
    }

    private var outline: [OutlineRow] {
        guard let root = document.pdf.outlineRoot else { return [] }
        var rows: [OutlineRow] = []
        func walk(_ node: PDFOutline, depth: Int) {
            for i in 0..<node.numberOfChildren {
                guard let child = node.child(at: i) else { continue }
                if let page = child.destination?.page {
                    rows.append(OutlineRow(title: child.label ?? "Untitled", page: document.pdf.index(for: page), depth: depth))
                }
                walk(child, depth: depth + 1)
            }
        }
        walk(root, depth: 0)
        return rows
    }

    var body: some View {
        let _ = state.pagesRevision
        NavigationStack {
            Group {
                switch mode {
                case .pages:
                    grid(Array(document.meta.pages.indices))
                case .bookmarks:
                    let marked = document.meta.pages.indices.filter { document.meta.bookmarks.contains(document.meta.pages[$0].id) }
                    if marked.isEmpty {
                        ContentUnavailableView("No bookmarks", systemImage: "bookmark",
                                               description: Text("Tap the bookmark button on a page to add it here."))
                    } else {
                        grid(marked)
                    }
                case .outline:
                    let rows = outline
                    if rows.isEmpty {
                        ContentUnavailableView("No outline", systemImage: "list.bullet.indent",
                                               description: Text("This PDF has no table of contents."))
                    } else {
                        List(rows) { row in
                            Button {
                                jump(to: row.page)
                            } label: {
                                HStack {
                                    Text(row.title).padding(.leading, CGFloat(row.depth) * 16)
                                    Spacer()
                                    Text("\(row.page + 1)").foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .background(Color(uiColor: Theme.desk))
            .navigationTitle("Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Show", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func jump(to index: Int) {
        dismiss()
        DispatchQueue.main.async { state.controller?.scrollToPage(index, animated: false) }
    }

    private func grid(_ indices: [Int]) -> some View {
        let drawings = state.controller?.pageDrawings() ?? []
        let count = document.pageCount
        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 22)], spacing: 26) {
                ForEach(indices, id: \.self) { index in
                    VStack(spacing: 6) {
                        PageThumbnail(document: document, index: index,
                                      drawing: drawings[safe: index] ?? PKDrawing())
                            .overlay(alignment: .topTrailing) {
                                if let id = document.meta.pages[safe: index]?.id, document.meta.bookmarks.contains(id) {
                                    Image(systemName: "bookmark.fill")
                                        .foregroundStyle(.red)
                                        .padding(6)
                                }
                            }
                        Text("\(index + 1)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { jump(to: index) }
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
    }
}

private struct PageThumbnail: View {
    let document: NotebookDocument
    let index: Int
    let drawing: PKDrawing
    @State private var image: UIImage?

    var body: some View {
        let size = document.pageSize(at: index)
        let items = document.items(onPage: index)
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
        .task(id: "\(index)-\(drawing.strokes.count)-\(items.count)-\(document.meta.pages[safe: index]?.id.uuidString ?? "")") {
            let page = document.pdf.page(at: index)
            let ink = drawing
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
