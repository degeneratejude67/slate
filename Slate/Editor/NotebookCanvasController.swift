import UIKit
import PencilKit
import PDFKit
import Combine

/// The writing surface: one PKCanvasView holding the ink of every page, over a backdrop of
/// page views that follows the canvas's scroll and zoom. PencilKit then handles pen input,
/// palm rejection, zoom-sharp ink, lasso and undo, and pages stay plain PDF pages.
final class NotebookCanvasController: UIViewController, PKCanvasViewDelegate {
    let document: NotebookDocument
    let state: EditorState
    let canvas = PKCanvasView()

    private let backdropHost = UIView()
    private let backdrop = UIView()
    private var pageViews: [PageView] = []
    private(set) var layout = PageLayout(sizes: [])
    private var savedInk: [UUID: Data] = [:]
    private var saveTimer: Timer?
    private var dirty = false
    private var fitScale: CGFloat = 0
    private var pendingScrollPage: Int?
    private var bag = Set<AnyCancellable>()

    init(document: NotebookDocument, state: EditorState) {
        self.document = document
        self.state = state
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { saveTimer?.invalidate() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.desk

        backdropHost.isUserInteractionEnabled = false
        backdropHost.clipsToBounds = true
        view.addSubview(backdropHost)
        backdrop.layer.anchorPoint = .zero
        backdropHost.addSubview(backdrop)

        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light   // keep ink colours true on white paper
        canvas.delegate = self
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.alwaysBounceVertical = true
        canvas.showsHorizontalScrollIndicator = false
        canvas.accessibilityIdentifier = "canvas"
        view.addSubview(canvas)

        let undoTap = UITapGestureRecognizer(target: self, action: #selector(undoTapped))
        undoTap.numberOfTouchesRequired = 2
        let redoTap = UITapGestureRecognizer(target: self, action: #selector(redoTapped))
        redoTap.numberOfTouchesRequired = 3
        undoTap.require(toFail: redoTap)
        canvas.addGestureRecognizer(undoTap)
        canvas.addGestureRecognizer(redoTap)

        state.controller = self
        state.$settings
            .removeDuplicates()
            .sink { [weak self] settings in self?.apply(settings) }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.saveNow() }
            .store(in: &bag)

        var drawings: [PKDrawing] = []
        for page in document.meta.pages {
            let data = document.inkData(for: page.id)
            if let data { savedInk[page.id] = data }
            drawings.append(data.flatMap { try? PKDrawing(data: $0) } ?? PKDrawing())
        }
        pendingScrollPage = min(max(document.meta.lastPage, 0), max(document.pageCount - 1, 0))
        rebuild(with: drawings)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveNow()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdropHost.frame = view.bounds
        if canvas.frame != view.bounds { canvas.frame = view.bounds }
        let width = view.bounds.width
        guard width > 0, layout.contentSize.width > 0 else { return }

        let fit = width / layout.contentSize.width
        if abs(fit - fitScale) > 0.0001 {
            let relative = fitScale > 0 ? canvas.zoomScale / fitScale : 1
            let focusY: CGFloat? = fitScale > 0
                ? (canvas.contentOffset.y + canvas.bounds.height / 2) / canvas.zoomScale
                : nil
            fitScale = fit
            canvas.minimumZoomScale = fit * 0.5
            canvas.maximumZoomScale = fit * 6
            canvas.zoomScale = min(max(fit * relative, canvas.minimumZoomScale), canvas.maximumZoomScale)
            updateContentSize()
            if let page = pendingScrollPage {
                pendingScrollPage = nil
                scrollToPage(page, animated: false)
            } else if let focusY {
                let y = focusY * canvas.zoomScale - canvas.bounds.height / 2
                canvas.contentOffset = CGPoint(x: canvas.contentOffset.x, y: clampedOffsetY(y))
            }
        }
        updateContentSize()
        syncBackdrop()
        updatePageLabel()
    }

    // MARK: Pages and layout

    private func rebuild(with drawings: [PKDrawing]) {
        layout = PageLayout(sizes: document.pageSizes)
        pageViews.forEach { $0.removeFromSuperview() }
        pageViews = layout.frames.enumerated().map { index, frame in
            let pageView = PageView(page: document.pdf.page(at: index), frame: frame)
            backdrop.addSubview(pageView)
            return pageView
        }
        backdrop.transform = .identity
        backdrop.bounds = CGRect(origin: .zero, size: layout.contentSize)
        canvas.drawing = InkLayout.merge(drawings, origins: layout.frames.map(\.origin))
        view.setNeedsLayout()
        updateStrokeCount()
        updatePageLabel()
    }

    private func updateContentSize() {
        let z = canvas.zoomScale
        let size = CGSize(width: layout.contentSize.width * z, height: layout.contentSize.height * z)
        if canvas.contentSize != size { canvas.contentSize = size }
        let insetX = max(0, (canvas.bounds.width - size.width) / 2)
        let inset = UIEdgeInsets(top: 0, left: insetX, bottom: 0, right: insetX)
        if canvas.contentInset != inset { canvas.contentInset = inset }
    }

    private func syncBackdrop() {
        let z = canvas.zoomScale
        backdrop.transform = CGAffineTransform(scaleX: z, y: z)
        backdrop.layer.position = CGPoint(x: -canvas.contentOffset.x, y: -canvas.contentOffset.y)
    }

    private func clampedOffsetY(_ y: CGFloat) -> CGFloat {
        let maxY = max(0, canvas.contentSize.height - canvas.bounds.height)
        return min(max(y, 0), maxY)
    }

    var currentPageIndex: Int {
        let z = max(canvas.zoomScale, 0.01)
        return layout.index(atY: (canvas.contentOffset.y + canvas.bounds.height * 0.35) / z)
    }

    func scrollToPage(_ index: Int, animated: Bool) {
        guard layout.frames.indices.contains(index) else { return }
        let y = (layout.frames[index].minY - PageLayout.gap / 2) * canvas.zoomScale
        canvas.setContentOffset(CGPoint(x: canvas.contentOffset.x, y: clampedOffsetY(y)), animated: animated)
        syncBackdrop()
        updatePageLabel()
    }

    private func updatePageLabel() {
        let label = "\(currentPageIndex + 1) / \(document.pageCount)"
        if state.pageLabel != label { state.pageLabel = label }
    }

    private func updateStrokeCount() {
        let count = canvas.drawing.strokes.count
        if state.strokeCount != count { state.strokeCount = count }
    }

    func pageDrawings() -> [PKDrawing] {
        InkLayout.split(canvas.drawing, layout: layout)
    }

    func insertPage(paper: Paper?, after index: Int? = nil) {
        saveNow()
        let base = min(max(index ?? currentPageIndex, 0), max(document.pageCount - 1, 0))
        let at = base + 1
        var drawings = pageDrawings()
        let size = document.pageSize(at: base)
        let newPaper = paper ?? document.meta.pages[safe: base]?.paper ?? .ruled
        do {
            try document.insertTemplatePage(paper: newPaper, size: size, at: at)
        } catch {
            state.errorMessage = error.localizedDescription
            return
        }
        drawings.insert(PKDrawing(), at: min(at, drawings.count))
        rebuild(with: drawings)
        canvas.undoManager?.removeAllActions()
        view.layoutIfNeeded()
        scrollToPage(at, animated: true)
        state.pagesRevision += 1
    }

    func deletePage(at index: Int) {
        guard document.pageCount > 1, document.meta.pages.indices.contains(index) else { return }
        saveNow()
        var drawings = pageDrawings()
        let id = document.meta.pages[index].id
        do {
            try document.deletePage(at: index)
        } catch {
            state.errorMessage = error.localizedDescription
            return
        }
        drawings.remove(at: index)
        savedInk[id] = nil
        rebuild(with: drawings)
        canvas.undoManager?.removeAllActions()
        state.pagesRevision += 1
    }

    func movePage(from: Int, to: Int) {
        guard document.meta.pages.indices.contains(from), document.meta.pages.indices.contains(to), from != to else { return }
        saveNow()
        var drawings = pageDrawings()
        do {
            try document.movePage(from: from, to: to)
        } catch {
            state.errorMessage = error.localizedDescription
            return
        }
        drawings.insert(drawings.remove(at: from), at: to)
        rebuild(with: drawings)
        canvas.undoManager?.removeAllActions()
        state.pagesRevision += 1
    }

    // MARK: Tools

    private func apply(_ settings: ToolSettings) {
        canvas.drawingPolicy = (settings.fingerDraws || AppEnv.isUITest) ? .anyInput : .pencilOnly
        canvas.tool = settings.pkTool
    }

    @objc private func undoTapped() { undo() }
    @objc private func redoTapped() { redo() }

    func undo() { canvas.undoManager?.undo() }
    func redo() { canvas.undoManager?.redo() }

    // MARK: Saving

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        syncBackdrop()
        updatePageLabel()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateContentSize()
        syncBackdrop()
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        dirty = true
        updateStrokeCount()
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.saveNow()
        }
    }

    /// Writes each page whose ink changed since the last save, then the metadata.
    func saveNow() {
        saveTimer?.invalidate()
        saveTimer = nil
        state.persistSettings()
        let lastPage = currentPageIndex
        guard dirty || document.meta.lastPage != lastPage else { return }

        if dirty {
            dirty = false
            let drawings = pageDrawings()
            var firstPageChanged = false
            for (i, drawing) in drawings.enumerated() {
                guard let id = document.meta.pages[safe: i]?.id else { continue }
                let data = drawing.dataRepresentation()
                guard savedInk[id] != data else { continue }
                do {
                    try document.writeInk(data, for: id)
                    savedInk[id] = data
                    if i == 0 { firstPageChanged = true }
                } catch {
                    state.errorMessage = "Could not save the ink on page \(i + 1): \(error.localizedDescription)"
                }
            }
            if firstPageChanged { document.writeThumbnail(firstPageInk: drawings.first ?? PKDrawing()) }
        }
        document.meta.lastPage = lastPage
        try? document.saveMeta()
    }
}
