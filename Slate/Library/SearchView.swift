import SwiftUI

/// Finds words in notebook titles, typed text boxes, PDF text and handwriting.
struct SearchView: View {
    @EnvironmentObject private var lib: LibraryModel
    @State private var query = AppEnv.arguments.contains("-uitest-search") ? "Pelton" : ""
    @State private var hits: [SearchHit] = []
    @State private var searching = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search handwriting, text and PDFs", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(run)
                    .accessibilityIdentifier("search-field")
                if !query.isEmpty {
                    Button { query = ""; hits = [] } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemGroupedBackground)))
            .padding(.horizontal, 32)
            .padding(.vertical, 16)

            if searching {
                ProgressView().padding(.top, 40)
                Spacer()
            } else if hits.isEmpty {
                ContentUnavailableView {
                    Label(query.count < 2 ? "Search your notes" : "No results", systemImage: "magnifyingglass")
                } description: {
                    Text("Handwriting is read on this iPad a few seconds after you write.")
                }
            } else {
                List {
                    let groups = Dictionary(grouping: hits, by: \.notebook)
                    ForEach(groups.keys.sorted { $0.lastPathComponent < $1.lastPathComponent }, id: \.self) { notebook in
                        Section(notebook.deletingPathExtension().lastPathComponent) {
                            ForEach(groups[notebook] ?? []) { hit in
                                Button {
                                    lib.open(hit.notebook, page: hit.page)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(hit.page.map { "Page \($0 + 1)" } ?? "Notebook")
                                                .font(.subheadline.weight(.semibold))
                                            Text(hit.source.rawValue)
                                                .font(.caption)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Capsule().fill(Theme.accent.opacity(0.12)))
                                        }
                                        Text(hit.snippet)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .accessibilityIdentifier("search-hit")
                            }
                        }
                    }
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Search")
        .onChange(of: query) { _, _ in run() }
        .task {
            await SearchIndexer.shared.indexMissing(lib.store.allNotebooks().map(\.url))
            run()
        }
    }

    private func run() {
        let text = query
        let store = lib.store
        guard text.trimmingCharacters(in: .whitespaces).count >= 2 else {
            hits = []
            return
        }
        searching = hits.isEmpty
        Task.detached(priority: .userInitiated) {
            let found = SearchIndex.search(text, in: store)
            await MainActor.run {
                if text == query {
                    hits = found
                    searching = false
                }
            }
        }
    }
}
