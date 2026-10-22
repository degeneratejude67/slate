import SwiftUI

/// GoodNotes-style bars: navigation and page actions in one row, tools in the other with
/// the options of the selected tool beside them.
struct EditorNavBar: View {
    @ObservedObject var state: EditorState
    let title: String
    let onClose: () -> Void

    var body: some View {
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
                Text("\(state.itemCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("item-count")
            }
            insertMenu
            addPageMenu
            moreMenu
        }
        .font(.system(size: 17))
        .padding(.horizontal, 18)
        .frame(height: 46)
    }

    private var insertMenu: some View {
        Menu {
            Button { state.settings.tool = .text } label: { Label("Text Box", systemImage: "textformat") }
            Button { state.showPhotoPicker = true } label: { Label("Photo", systemImage: "photo") }
            Button { state.showImageImporter = true } label: { Label("Image from Files", systemImage: "folder") }
            Button { state.showStickers = true } label: { Label("Sticker", systemImage: "face.smiling") }
        } label: {
            Image(systemName: "plus.circle")
        }
        .accessibilityIdentifier("insert-menu")
    }

    private var addPageMenu: some View {
        Menu {
            Button { state.controller?.insertPage(paper: nil) } label: {
                Label("Same as This Page", systemImage: "doc.on.doc")
            }
            Section("New Page After This One") {
                ForEach(PaperKind.quick) { kind in
                    Button(kind.label) {
                        state.controller?.insertPage(paper: Paper(kind: kind, tone: AppSettings.shared.prefs.defaultPaper.tone))
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
            Toggle(isOn: Binding(get: { AppSettings.shared.prefs.fingerDraws },
                                 set: { AppSettings.shared.prefs.fingerDraws = $0 })) {
                Label("Draw with Finger", systemImage: "hand.draw")
            }
            Picker("Scrolling", selection: Binding(get: { AppSettings.shared.prefs.scroll },
                                                   set: { AppSettings.shared.prefs.scroll = $0 })) {
                ForEach(ScrollAxis.allCases) { Text("Scroll " + $0.label).tag($0) }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityIdentifier("more-menu")
    }
}

struct EditorToolRow: View {
    @ObservedObject var state: EditorState

    var body: some View {
        HStack(spacing: 2) {
            Button { state.controller?.undo() } label: { plainIcon("arrow.uturn.backward") }
                .buttonStyle(.plain)
                .accessibilityIdentifier("undo")
            Button { state.controller?.redo() } label: { plainIcon("arrow.uturn.forward") }
                .buttonStyle(.plain)
                .accessibilityIdentifier("redo")

            Spacer(minLength: 6)

            penButton
            ForEach([ToolKind.pencil, .highlighter, .shape, .eraser, .lasso, .text, .select]) { kind in
                toolButton(kind)
            }

            Divider().frame(height: 26).padding(.horizontal, 8)

            options
                .frame(minWidth: 230, alignment: .leading)

            Spacer(minLength: 6)
        }
        .padding(.horizontal, 10)
        .frame(height: 50)
    }

    // MARK: Tool buttons

    private func toolIcon(_ kind: ToolKind) -> some View {
        let selected = state.settings.tool == kind
        return Image(systemName: kind.symbol)
            .font(.system(size: 18))
            .frame(width: 40, height: 36)
            .foregroundStyle(selected ? Theme.accent : Color.primary)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Theme.accent.opacity(0.15) : Color.clear))
            .contentShape(Rectangle())
    }

    private func plainIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17))
            .frame(width: 38, height: 36)
            .contentShape(Rectangle())
    }

    private func toolButton(_ kind: ToolKind) -> some View {
        Button { state.settings.tool = kind } label: { toolIcon(kind) }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tool-\(kind.rawValue)")
            .accessibilityLabel(kind.label)
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

    // MARK: Options of the current tool

    @ViewBuilder private var options: some View {
        switch state.settings.tool {
        case .eraser:
            Picker("Eraser", selection: $state.settings.eraserMode) {
                Text("Whole Strokes").tag(EraserMode.stroke)
                Text("Precise").tag(EraserMode.pixel)
            }
            .pickerStyle(.segmented)
            .frame(width: 230)
        case .lasso:
            Text("Circle ink to move, resize or recolour it.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .select:
            if state.selectedKind != nil {
                HStack(spacing: 14) {
                    Text("Drag to move, corner to resize.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button(role: .destructive) { state.controller?.deleteSelected() } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityIdentifier("delete-item")
                }
            } else {
                Text("Tap a text box, picture or sticker.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .text:
            HStack(spacing: 6) {
                textControls
                swatches
            }
        default:
            HStack(spacing: 6) {
                swatches
                Divider().frame(height: 22).padding(.horizontal, 4)
                widths
            }
        }
    }

    private var swatches: some View {
        let settings = state.settings
        return HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Button { state.settings.selectColor(i) } label: {
                    Circle()
                        .fill(settings.palette[safe: i]?.color ?? .black)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                        .padding(3)
                        .overlay(Circle().strokeBorder(settings.colorIndex == i ? Theme.accent : .clear, lineWidth: 2))
                        .frame(width: 32, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("color-\(i)")
            }
            ColorPicker("Colour", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 32)
        }
    }

    private var widths: some View {
        let settings = state.settings
        return HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                Button { state.settings.selectWidth(i) } label: {
                    Circle()
                        .fill(settings.widthIndex == i ? Theme.accent : Color.primary.opacity(0.55))
                        .frame(width: CGFloat(5 + i * 4), height: CGFloat(5 + i * 4))
                        .frame(width: 28, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("width-\(i)")
            }
        }
    }

    private var textControls: some View {
        let style = state.settings.textStyle
        return HStack(spacing: 4) {
            Menu {
                Picker("Font", selection: $state.settings.textStyle.font) {
                    ForEach(ItemFont.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                Text(style.font.label)
                    .font(.footnote.weight(.medium))
                    .frame(width: 74, height: 30)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
            }
            Menu {
                Picker("Size", selection: $state.settings.textStyle.size) {
                    ForEach(TextStyle.sizes, id: \.self) { Text("\(Int($0)) pt").tag($0) }
                }
            } label: {
                Text("\(Int(style.size))")
                    .font(.footnote.monospacedDigit().weight(.medium))
                    .frame(width: 36, height: 30)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
            }
            Button { state.settings.textStyle.bold.toggle() } label: {
                Image(systemName: "bold")
                    .frame(width: 30, height: 30)
                    .foregroundStyle(style.bold ? Theme.accent : Color.primary)
                    .background(RoundedRectangle(cornerRadius: 7).fill(style.bold ? Theme.accent.opacity(0.15) : Color.clear))
            }
            .buttonStyle(.plain)
            Menu {
                Picker("Fill", selection: $state.settings.textStyle.fill) {
                    ForEach(TextFill.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                Image(systemName: style.fill == .none ? "note.text" : "note.text.badge.plus")
                    .frame(width: 30, height: 30)
            }
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { state.settings.currentColor.color },
            set: { state.settings.setCurrentColor(RGBA(UIColor($0))) }
        )
    }
}
