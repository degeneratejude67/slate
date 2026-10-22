import SwiftUI

/// GoodNotes-style two-row bar: navigation and page actions on top, tools in the middle of
/// the second row with the favourite colours and widths of the selected tool beside them.
struct EditorToolbar: View {
    @ObservedObject var state: EditorState
    let title: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topRow
            Divider().opacity(0.6)
            toolRow
            Divider()
        }
        .background(.bar)
    }

    // MARK: Rows

    private var topRow: some View {
        HStack(spacing: 20) {
            Button(action: onClose) {
                Label("Library", systemImage: "chevron.left")
            }
            .accessibilityIdentifier("close-notebook")

            Button { state.showPages = true } label: {
                Image(systemName: "square.grid.2x2")
            }
            .accessibilityIdentifier("pages-button")

            Spacer(minLength: 12)
            Text(title)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 12)

            if AppEnv.isUITest {
                Text("\(state.strokeCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("stroke-count")
            }
            addPageMenu
            moreMenu
        }
        .font(.system(size: 17))
        .padding(.horizontal, 18)
        .frame(height: 46)
    }

    private var toolRow: some View {
        HStack(spacing: 4) {
            Button { state.controller?.undo() } label: { plainIcon("arrow.uturn.backward") }
                .buttonStyle(.plain)
                .accessibilityIdentifier("undo")
            Button { state.controller?.redo() } label: { plainIcon("arrow.uturn.forward") }
                .buttonStyle(.plain)
                .accessibilityIdentifier("redo")

            Spacer(minLength: 8)

            penButton
            toolButton(.pencil)
            toolButton(.highlighter)
            toolButton(.eraser)
            toolButton(.lasso)

            Divider().frame(height: 26).padding(.horizontal, 10)

            styleControls

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
    }

    // MARK: Tools

    private func toolIcon(_ kind: ToolKind) -> some View {
        let selected = state.settings.tool == kind
        return Image(systemName: kind.symbol)
            .font(.system(size: 19))
            .frame(width: 42, height: 36)
            .foregroundStyle(selected ? Theme.accent : Color.primary)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Theme.accent.opacity(0.15) : Color.clear))
            .contentShape(Rectangle())
    }

    private func plainIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18))
            .frame(width: 40, height: 36)
            .contentShape(Rectangle())
    }

    private func toolButton(_ kind: ToolKind) -> some View {
        Button { state.settings.tool = kind } label: { toolIcon(kind) }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tool-\(kind.rawValue)")
    }

    /// Tap picks the pen; press and hold picks the pen type.
    private var penButton: some View {
        Menu {
            Picker("Pen", selection: $state.settings.penStyle) {
                ForEach(PenStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
        } label: {
            toolIcon(.pen)
        } primaryAction: {
            state.settings.tool = .pen
        }
        .accessibilityIdentifier("tool-pen")
    }

    @ViewBuilder private var styleControls: some View {
        let settings = state.settings
        let enabled = settings.tool.usesColor
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Button { state.settings.selectColor(i) } label: {
                    Circle()
                        .fill(settings.palette[safe: i]?.color ?? .black)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                        .padding(3)
                        .overlay(Circle().strokeBorder(settings.colorIndex == i && enabled ? Theme.accent : .clear,
                                                       lineWidth: 2))
                        .frame(width: 32, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("color-\(i)")
            }
            ColorPicker("Colour", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 32)

            Divider().frame(height: 22).padding(.horizontal, 6)

            ForEach(0..<3, id: \.self) { i in
                Button { state.settings.selectWidth(i) } label: {
                    Circle()
                        .fill(settings.widthIndex == i && enabled ? Theme.accent : Color.primary.opacity(0.55))
                        .frame(width: CGFloat(5 + i * 4), height: CGFloat(5 + i * 4))
                        .frame(width: 28, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("width-\(i)")
            }
        }
        .opacity(enabled ? 1 : 0.3)
        .disabled(!enabled)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { state.settings.currentColor.color },
            set: { state.settings.setCurrentColor(RGBA(UIColor($0))) }
        )
    }

    // MARK: Menus

    private var addPageMenu: some View {
        Menu {
            Button { state.controller?.insertPage(paper: nil) } label: {
                Label("Same as This Page", systemImage: "doc.on.doc")
            }
            Section("New Page After This One") {
                ForEach(PaperKind.allCases) { kind in
                    Button(kind.label) {
                        state.controller?.insertPage(paper: Paper(kind: kind, tone: .white))
                    }
                }
            }
        } label: {
            Image(systemName: "doc.badge.plus")
        }
        .accessibilityIdentifier("add-page-menu")
    }

    private var moreMenu: some View {
        Menu {
            Toggle(isOn: $state.settings.fingerDraws) {
                Label("Draw with Finger", systemImage: "hand.draw")
            }
            Picker("Eraser", selection: $state.settings.eraserMode) {
                Text("Eraser: Whole Strokes").tag(EraserMode.stroke)
                Text("Eraser: Precise").tag(EraserMode.pixel)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityIdentifier("more-menu")
    }
}
