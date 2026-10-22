import SwiftUI
import UniformTypeIdentifiers

/// Built-in, free "Marketplace": paper templates, covers and sticker packs, plus the
/// user's own imported templates.
struct MarketplaceView: View {
    @EnvironmentObject private var lib: LibraryModel
    @ObservedObject private var settings = AppSettings.shared
    @State private var detail: Paper?
    @State private var showImporter = false
    @State private var templatesRevision = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Templates, covers and stickers for your notebooks. Everything here is free and works offline.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ForEach(TemplateCategory.allCases) { category in
                    section(category.rawValue) {
                        ForEach(PaperKind.allCases.filter { $0.category == category }) { kind in
                            templateCard(Paper(kind: kind, tone: .white), title: kind.label, blurb: kind.blurb)
                        }
                    }
                }

                section("Your Templates") {
                    Button { showImporter = true } label: {
                        VStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 120, height: 160)
                                .overlay(Image(systemName: "plus").font(.title2).foregroundStyle(Theme.accent))
                            Text("Import PDF or Picture")
                                .font(.footnote.weight(.medium))
                                .frame(width: 130)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("import-template")
                    let _ = templatesRevision
                    ForEach(TemplateStore.names(), id: \.self) { name in
                        templateCard(Paper(kind: .blank, tone: .white, custom: name), title: name, blurb: "Imported")
                            .contextMenu {
                                Button(role: .destructive) {
                                    TemplateStore.delete(name)
                                    templatesRevision += 1
                                } label: { Label("Delete Template", systemImage: "trash") }
                            }
                    }
                }

                section("Covers") {
                    ForEach(CoverStyle.allCases) { style in
                        VStack(spacing: 8) {
                            NotebookCover(style: style)
                                .frame(height: 150)
                            HStack(spacing: 4) {
                                Text(style.label).font(.footnote.weight(.medium))
                                if settings.prefs.defaultCover == style {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                        .onTapGesture { settings.prefs.defaultCover = style }
                        .accessibilityIdentifier("cover-\(style.rawValue)")
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Sticker Packs").font(.title3.weight(.semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 18)], spacing: 18) {
                        ForEach(StickerCatalog.packs) { pack in
                            packCard(pack)
                        }
                    }
                }
            }
            .padding(32)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Marketplace")
        .sheet(item: Binding(get: { detail.map(DetailItem.init) }, set: { detail = $0?.paper }),
               onDismiss: { lib.openPending() }) { item in
            TemplateDetailSheet(paper: item.paper)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.pdf, .image]) { result in
            guard case .success(let url) = result else { return }
            do {
                try TemplateStore.importFile(url)
                templatesRevision += 1
            } catch {
                lib.errorMessage = error.localizedDescription
            }
        }
    }

    private struct DetailItem: Identifiable {
        let paper: Paper
        var id: String { (paper.custom ?? paper.kind.rawValue) + paper.tone.rawValue }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title3.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 18) { content() }
                    .padding(.vertical, 4)
            }
        }
    }

    private func templateCard(_ paper: Paper, title: String, blurb: String) -> some View {
        Button { detail = paper } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(uiImage: TemplateRenderer.previewImage(paper, size: PageSizePreset.a4.size, width: 120))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 160)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                Text(blurb)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(width: 130, alignment: .leading)
            }
            .frame(width: 130, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("template-\(paper.custom ?? paper.kind.rawValue)")
    }

    private func packCard(_ pack: StickerPack) -> some View {
        let added = settings.prefs.stickerPacks.contains(pack.id)
        return HStack(alignment: .top, spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: 3), spacing: 6) {
                ForEach(pack.stickers.prefix(6)) { sticker in
                    Image(uiImage: StickerCatalog.image(for: sticker, width: 120))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                }
            }
            .frame(width: 114)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            VStack(alignment: .leading, spacing: 4) {
                Text(pack.name).font(.headline)
                Text(pack.blurb).font(.footnote).foregroundStyle(.secondary)
                Text("\(pack.stickers.count) stickers · Free").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Button {
                    if added {
                        settings.prefs.stickerPacks.removeAll { $0 == pack.id }
                    } else {
                        settings.prefs.stickerPacks.append(pack.id)
                    }
                } label: {
                    Text(added ? "Added" : "Get")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(added ? Color.primary.opacity(0.08) : Theme.accent))
                        .foregroundStyle(added ? Color.primary : Color.white)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pack-\(pack.id)")
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }
}

struct TemplateDetailSheet: View {
    @EnvironmentObject private var lib: LibraryModel
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss
    let paper: Paper
    @State private var tone: PaperTone = .white

    private var chosen: Paper { Paper(kind: paper.kind, tone: tone, custom: paper.custom) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(uiImage: TemplateRenderer.previewImage(chosen, size: PageSizePreset.a4.size, width: 340))
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 460)
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                    Text(paper.custom == nil ? paper.kind.blurb : "Your imported template.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if paper.custom == nil {
                        Picker("Colour", selection: $tone) {
                            ForEach(PaperTone.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 320)
                    }
                    Button {
                        let paper = chosen
                        lib.perform {
                            lib.pendingOpen = try lib.store.createNotebook(
                                title: paper.label, paper: paper, size: settings.prefs.defaultSize.size,
                                pages: 1, cover: settings.prefs.defaultCover, in: lib.store.root)
                        }
                        dismiss()
                    } label: {
                        Label("New Notebook with This Paper", systemImage: "book.closed")
                            .frame(maxWidth: 320)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("use-template")
                    Button {
                        settings.prefs.defaultPaper = chosen
                        dismiss()
                    } label: {
                        Label(settings.prefs.defaultPaper == chosen ? "Default Paper" : "Make Default Paper",
                              systemImage: "star")
                            .frame(maxWidth: 320)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("default-template")
                }
                .padding(28)
            }
            .navigationTitle(paper.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .onAppear { tone = paper.tone }
    }
}
