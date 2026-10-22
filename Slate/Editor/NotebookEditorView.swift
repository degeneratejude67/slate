import SwiftUI

struct NotebookEditorView: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @StateObject private var state = EditorState()
    @State private var document: NotebookDocument?
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            EditorToolbar(state: state, title: document?.meta.title ?? "", onClose: close)
            ZStack(alignment: .bottom) {
                if let document {
                    CanvasHost(document: document, state: state)
                        .ignoresSafeArea(.container, edges: .bottom)
                } else if let loadError {
                    ContentUnavailableView("Can't open this notebook", systemImage: "exclamationmark.triangle",
                                           description: Text(loadError))
                } else {
                    ProgressView()
                }
                if !state.pageLabel.isEmpty {
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
        }
        .background(Color(uiColor: Theme.desk))
        .sheet(isPresented: $state.showPages) {
            if let document { PageGridView(document: document, state: state) }
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
