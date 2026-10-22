import SwiftUI

struct NewNotebookSheet: View {
    @EnvironmentObject private var lib: LibraryModel
    @Environment(\.dismiss) private var dismiss
    let folder: URL
    var initialPaper: Paper? = nil

    @State private var title = "Untitled"
    @State private var paper = AppSettings.shared.prefs.defaultPaper
    @State private var size = AppSettings.shared.prefs.defaultSize
    @State private var cover = AppSettings.shared.prefs.defaultCover
    @State private var category: TemplateCategory = .essentials

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                        .accessibilityIdentifier("notebook-title")
                }
                Section("Paper") {
                    Picker("Category", selection: $category) {
                        ForEach(TemplateCategory.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(PaperKind.allCases.filter { $0.category == category }) { kind in
                                paperOption(Paper(kind: kind, tone: paper.tone))
                            }
                            if category == .creative {
                                ForEach(TemplateStore.names(), id: \.self) { name in
                                    paperOption(Paper(kind: .blank, tone: .white, custom: name))
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    if paper.custom == nil {
                        Picker("Colour", selection: $paper.tone) {
                            ForEach(PaperTone.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Picker("Size", selection: $size) {
                            ForEach(PageSizePreset.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                Section("Cover") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(CoverStyle.allCases) { style in
                                NotebookCover(style: style)
                                    .frame(height: 70)
                                    .padding(4)
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(cover == style ? Theme.accent : .clear, lineWidth: 2.5))
                                    .onTapGesture { cover = style }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle("New Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                        .accessibilityIdentifier("create-notebook")
                }
            }
            .onAppear {
                if let initialPaper {
                    paper = initialPaper
                    category = initialPaper.custom == nil ? initialPaper.kind.category : .creative
                } else {
                    category = paper.custom == nil ? paper.kind.category : .creative
                }
            }
        }
    }

    private func paperOption(_ option: Paper) -> some View {
        let selected = option.kind == paper.kind && option.custom == paper.custom
        return VStack(spacing: 6) {
            Image(uiImage: TemplateRenderer.previewImage(option, size: size.size, width: 84))
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 112)
                .overlay(RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(selected ? Theme.accent : Color.black.opacity(0.12), lineWidth: selected ? 2.5 : 1))
            Text(option.label)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 90)
                .foregroundStyle(selected ? Theme.accent : Color.secondary)
        }
        .onTapGesture { paper = option }
        .accessibilityIdentifier("paper-\(option.custom ?? option.kind.rawValue)")
    }

    private func create() {
        let chosen = paper
        lib.perform {
            lib.pendingOpen = try lib.store.createNotebook(title: title, paper: chosen, size: size.size,
                                                           pages: 1, cover: cover, in: folder)
        }
        dismiss()
    }
}
