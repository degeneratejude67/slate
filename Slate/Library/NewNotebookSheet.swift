import SwiftUI

struct NewNotebookSheet: View {
    @EnvironmentObject private var lib: LibraryModel
    @Environment(\.dismiss) private var dismiss
    let folder: URL

    @State private var title = "Untitled"
    @State private var kind: PaperKind = .ruled
    @State private var tone: PaperTone = .white
    @State private var size: PageSizePreset = .a4
    @State private var cover: CoverStyle = .slate

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Title", text: $title)
                        .accessibilityIdentifier("notebook-title")
                }
                Section("Paper") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(PaperKind.allCases) { option in
                                VStack(spacing: 6) {
                                    Image(uiImage: TemplateRenderer.previewImage(Paper(kind: option, tone: tone),
                                                                                 size: size.size, width: 84))
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 84, height: 112)
                                        .overlay(RoundedRectangle(cornerRadius: 3)
                                            .strokeBorder(kind == option ? Theme.accent : Color.black.opacity(0.12),
                                                          lineWidth: kind == option ? 2.5 : 1))
                                    Text(option.label)
                                        .font(.caption)
                                        .foregroundStyle(kind == option ? Theme.accent : Color.secondary)
                                }
                                .onTapGesture { kind = option }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    Picker("Colour", selection: $tone) {
                        ForEach(PaperTone.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Size", selection: $size) {
                        ForEach(PageSizePreset.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Cover") {
                    HStack(spacing: 14) {
                        ForEach(CoverStyle.allCases) { style in
                            Circle()
                                .fill(style.color)
                                .frame(width: 30, height: 30)
                                .padding(3)
                                .overlay(Circle().strokeBorder(cover == style ? Theme.accent : .clear, lineWidth: 2))
                                .onTapGesture { cover = style }
                        }
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
        }
    }

    private func create() {
        let paper = Paper(kind: kind, tone: tone)
        lib.perform {
            lib.pendingOpen = try lib.store.createNotebook(title: title, paper: paper, size: size.size,
                                                           pages: 1, cover: cover, in: folder)
        }
        dismiss()
    }
}
