import UIKit
import PencilKit
import PDFKit
import Combine

/// The writing surface: one PKCanvasView holding the ink of every page, over a backdrop of
/// page views and page items that follows the canvas's scroll and zoom. PencilKit handles
/// pen input, palm rejection, zoom-sharp ink, lasso and undo; pages stay plain PDF pages.
final class NotebookCanvasController: UIViewController, PKCanvasViewDelegate, UITextViewDelegate,
                                      UIEditMenuInteractionDelegate {
    let document: NotebookDocument
    let state: EditorState
    let canvas = PKCanvasView()

    private let settingsStore = AppSettings.shared
    private var prefs: Prefs { settingsStore.prefs }
    private var axis: ScrollAxis

    private let backdropHost = UIView()
    private let backdrop = UIView()
    private let overlay = SelectionOverlay()
    private lazy var editMenu = UIEditMenuInteraction(delegate: self)
    private var pageViews: [PageView] = []
    private var itemViews: [UUID: ItemView] = [:]
    private(set) var layout = PageLayout(sizes: [])

    private var savedInk: [UUID: Data] = [:]
    private var saveTimer: Timer?
    private var metaTimer: Timer?
    private var dirty = false
    private var thumbNeeded = false
    private var fitScale: CGFloat = 0
    private var pendingScrollPage: Int?
    private var lastStrokeCount = 0
    private var replacingDrawing = false
    private var lastSettings: ToolSettings?
    private var bag = Set<AnyCancellable>()

    private var undoTap: UITapGestureRecognizer!
    private var redoTap: UITapGestureRecognizer!
    private var itemTap: UITapGestureRecognizer!

    private struct Selection { let page: Int; let id: UUID }
    private struct TextEdit { let page: Int; let id: UUID; let view: UITextView; let baseline: [PageItem] }
    private var selection: Selection?
    private var textEdit: TextEdit?
    private var dragStart: (pageID: UUID, items: [PageItem])?

    init(document: NotebookDocument, state: EditorState) {
        self.document = document
        self.state = state
        axis = AppSettings.shared.prefs.scroll
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        saveTimer?.invalidate()
        metaTimer?.invalidate()
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = prefs.desk.uiColor

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
        canvas.alwaysBounceVertical = axis == .vertical
        canvas.alwaysBounceHorizontal = axis == .horizontal
        canvas.showsHorizontalScrollIndicator = axis == .horizontal
        canvas.accessibilityIdentifier = "canvas"
        view.addSubview(canvas)

        overlay.frame = view.bounds
        overlay.addInteraction(editMenu)
        overlay.onDrag = { [weak self] delta, resizing in self?.dragSelected(by: delta, resizing: resizing) }
        overlay.onDragEnded = { [weak self] in self?.finishDrag() }
        overlay.onTap = { [weak self] point in self?.selectionTapped(at: point) }
        view.addSubview(overlay)

        undoTap = UITapGestureRecognizer(target: self, action: #selector(undoTapped))
        undoTap.numberOfTouchesRequired = 2
        redoTap = UITapGestureRecognizer(target: self, action: #selector(redoTapped))
        redoTap.numberOfTouchesRequired = 3
        undoTap.require(toFail: redoTap)
        itemTap = UITapGestureRecognizer(target: self, action: #selector(itemTapped(_:)))
        itemTap.isEnabled = false
        canvas.addGestureRecognizer(undoTap)
        canvas.addGestureRecognizer(redoTap)
        canvas.addGestureRecognizer(itemTap)

        state.controller = self
        var drawings: [PKDrawing] = []
        for page in document.meta.pages {
            let data = document.inkData(for: page.id)
            if let data { savedInk[page.id] = data }
            drawings.append(data.flatMap { try? PKDrawing(data: $0) } ?? PKDrawing())
        }
        pendingScrollPage = min(max(document.meta.lastPage, 0), max(document.pageCount - 1, 0))
        rebuild(with: drawings)

        state.$settings
            .removeDuplicates()
            .sink { [weak self] settings in self?.apply(settings) }
            .store(in: &bag)
        settingsStore.$prefs
            .removeDuplicates()
            .sink { [weak self] prefs in self?.applyPrefs(prefs) }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.saveNow() }
            .store(in: &bag)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        saveNow()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdropHost.frame = view.bounds
        overlay.frame = view.bounds
        if canvas.frame != view.bounds { canvas.frame = view.bounds }
        guard view.bounds.width > 0, layout.contentSize.width > 0 else { return }

        let fit = fittingScale()
        if abs(fit - fitScale) > 0.0001 {
            let relative = fitScale > 0 ? canvas.zoomScale / fitScale : 1
            let focusPage = fitScale > 0 ? currentPageIndex : nil
            fitScale = fit
            canvas.minimumZoomScale = fit * 0.5
            canvas.maximumZoomScale = fit * 6
            canvas.zoomScale = min(max(fit * relative, canvas.minimumZoomScale), canvas.maximumZoomScale)
            updateContentSize()
            if let page = pendingScrollPage ?? focusPage {
                pendingScrollPage = nil
                scrollToPage(page, animated: false)
            }
        }
        updateContentSize()
        syncBackdrop()
        updatePageLabel()
    }

    private func fittingScale() -> CGFloat {
        switch axis {
        case .vertical:
            return view.bounds.width / layout.contentSize.width
        case .horizontal:
            let widest = (layout.frames.map(\.width).max() ?? 600) + 2 * PageLayout.margin
            return min(view.bounds.width / widest, view.bounds.height / layout.contentSize.height)
        }
    }

    // MARK: Pages and layout

    private func rebuild(with drawings: [PKDrawing]) {
        endTextEditing()
        selection = nil
        layout = PageLayout(sizes: document.pageSizes, axis: axis)
        pageViews.forEach { $0.removeFromSuperview() }
        itemViews.values.forEach { $0.removeFromSuperview() }
        itemViews = [:]
        pageViews = layout.frames.enumerated().map { index, frame in
            let pageView = PageView(page: document.pdf.page(at: index), frame: frame)
            backdrop.addSubview(pageView)
            return pageView
        }
        for page in document.meta.pages.indices { syncItemViews(page: page) }
        backdrop.transform = .identity
        backdrop.bounds = CGRect(origin: .zero, size: layout.contentSize)

        let merged = InkLayout.merge(drawings, origins: layout.frames.map(\.origin))
        replacingDrawing = true
        canvas.drawing = merged
        replacingDrawing = false
        lastStrokeCount = merged.strokes.count
        view.setNeedsLayout()
        refreshSelection()
        updateStrokeCount()
        updateItemCount()
        updatePageLabel()
    }

    private func relayout(axis newAxis: ScrollAxis) {
        let drawings = pageDrawings()
        let page = currentPageIndex
        axis = newAxis
        canvas.alwaysBounceVertical = axis == .vertical
        canvas.alwaysBounceHorizontal = axis == .horizontal
        canvas.showsHorizontalScrollIndicator = axis == .horizontal
        fitScale = 0
        pendingScrollPage = page
        rebuild(with: drawings)
        canvas.undoManager?.removeAllActions()
    }

    private func updateContentSize() {
        let z = canvas.zoomScale
        let size = CGSize(width: layout.contentSize.width * z, height: layout.contentSize.height * z)
        if canvas.contentSize != size { canvas.contentSize = size }
        let insetX = max(0, (canvas.bounds.width - size.width) / 2)
        let insetY = axis == .horizontal ? max(0, (canvas.bounds.height - size.height) / 2) : 0
        let inset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
        if canvas.contentInset != inset { canvas.contentInset = inset }
    }

    private func syncBackdrop() {
        let z = canvas.zoomScale
        backdrop.transform = CGAffineTransform(scaleX: z, y: z)
        backdrop.layer.position = CGPoint(x: -canvas.contentOffset.x, y: -canvas.contentOffset.y)
        refreshSelection()
        layoutTextEditor()
    }

    var currentPageIndex: Int {
        let z = max(canvas.zoomScale, 0.01)
        switch axis {
        case .vertical:
            return layout.index(along: (canvas.contentOffset.y + canvas.bounds.height * 0.35) / z)
        case .horizontal:
            return layout.index(along: (canvas.contentOffset.x + canvas.bounds.width / 2) / z)
        }
    }

    private func offset(forPage index: Int) -> CGPoint {
        let z = canvas.zoomScale
        let frame = layout.frames[index]
        let inset = canvas.contentInset
        switch axis {
        case .vertical:
            let maxY = max(-inset.top, canvas.contentSize.height - canvas.bounds.height + inset.bottom)
            let y = min(max((frame.minY - PageLayout.gap / 2) * z, -inset.top), maxY)
            return CGPoint(x: canvas.contentOffset.x, y: y)
        case .horizontal:
            let maxX = max(-inset.left, canvas.contentSize.width - canvas.bounds.width + inset.right)
            let x = min(max(frame.midX * z - canvas.bounds.width / 2, -inset.left), maxX)
            return CGPoint(x: x, y: canvas.contentOffset.y)
        }
    }

    func scrollToPage(_ index: Int, animated: Bool) {
        guard layout.frames.indices.contains(index) else { return }
        canvas.setContentOffset(offset(forPage: index), animated: animated)
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

    private func updateItemCount() {
        let count = document.meta.pages.reduce(0) { $0 + $1.items.count }
        if state.itemCount != count { state.itemCount = count }
    }

    func pageDrawings() -> [PKDrawing] {
        InkLayout.split(canvas.drawing, layout: layout)
    }

    func insertPage(paper: Paper?, after index: Int? = nil) {
        saveNow()
        let base = min(max(index ?? currentPageIndex, 0), max(document.pageCount - 1, 0))
        let at = base + 1
        var drawings = pageDrawings()
        let newPaper = paper ?? document.meta.pages[safe: base]?.paper ?? prefs.defaultPaper
        let size = TemplateRenderer.pageSize(for: newPaper, default: document.pageSize(at: base))
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

    /// Adds a page at the end without touching the ink, so undo history survives.
    private func appendPageQuietly() {
        let last = document.pageCount - 1
        guard last >= 0, let paper = document.meta.pages[last].paper else { return }
        let size = document.pageSize(at: last)
        do {
            try document.insertTemplatePage(paper: paper, size: size, at: last + 1)
        } catch {
            return
        }
        let newLayout = PageLayout(sizes: document.pageSizes, axis: axis)
        guard Array(newLayout.frames.prefix(layout.frames.count)) == layout.frames else {
            let drawings = pageDrawings() + [PKDrawing()]
            rebuild(with: drawings)
            return
        }
        layout = newLayout
        let pageView = PageView(page: document.pdf.page(at: last + 1), frame: layout.frames[last + 1])
        backdrop.insertSubview(pageView, at: pageViews.count)
        pageViews.append(pageView)
        backdrop.bounds = CGRect(origin: .zero, size: layout.contentSize)
        updateContentSize()
        syncBackdrop()
        updatePageLabel()
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

    // MARK: Tools and preferences

    private func apply(_ settings: ToolSettings) {
        canvas.drawingPolicy = (prefs.fingerDraws || AppEnv.isUITest) ? .anyInput : .pencilOnly
        canvas.tool = settings.pkTool
        let itemsMode = settings.tool.editsItems
        canvas.drawingGestureRecognizer.isEnabled = !itemsMode
        itemTap.isEnabled = itemsMode
        if !itemsMode {
            endTextEditing()
            selection = nil
            refreshSelection()
        }
        if let old = lastSettings, old.textStyle != settings.textStyle || old.inkColor != settings.inkColor {
            applyTextStyle(settings)
        }
        lastSettings = settings
    }

    private func applyPrefs(_ p: Prefs) {
        view.backgroundColor = p.desk.uiColor
        undoTap.isEnabled = p.twoFingerUndo
        redoTap.isEnabled = p.twoFingerUndo
        canvas.drawingPolicy = (p.fingerDraws || AppEnv.isUITest) ? .anyInput : .pencilOnly
        if p.scroll != axis { relayout(axis: p.scroll) }
    }

    @objc private func undoTapped() { undo() }
    @objc private func redoTapped() { redo() }

    func undo() {
        endTextEditing()
        canvas.undoManager?.undo()
    }

    func redo() {
        endTextEditing()
        canvas.undoManager?.redo()
    }

    // MARK: Canvas and scrolling

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        syncBackdrop()
        updatePageLabel()
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateContentSize()
        syncBackdrop()
        styleTextEditor()
    }

    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        let renderScale = UIScreen.main.scale * scale
        itemViews.values.forEach { $0.setRenderScale(renderScale) }
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard axis == .horizontal, fitScale > 0, abs(canvas.zoomScale - fitScale) / fitScale < 0.05,
              !layout.frames.isEmpty else { return }
        let current = currentPageIndex
        var target = current
        if velocity.x > 0.25 {
            target = current + 1
        } else if velocity.x < -0.25 {
            target = current - 1
        } else {
            target = layout.index(along: (targetContentOffset.pointee.x + canvas.bounds.width / 2) / canvas.zoomScale)
        }
        target = min(max(target, 0), layout.frames.count - 1)
        targetContentOffset.pointee.x = offset(forPage: target).x
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        let strokes = canvasView.drawing.strokes
        let added = strokes.count > lastStrokeCount
        lastStrokeCount = strokes.count
        if added && !replacingDrawing, let newest = strokes.last {
            if state.settings.tool == .shape {
                DispatchQueue.main.async { [weak self] in self?.snapShape(newest) }
            }
            if prefs.autoAddPage && layout.index(for: newest.renderBounds) == document.pageCount - 1 {
                DispatchQueue.main.async { [weak self] in self?.appendPageQuietly() }
            }
        }
        dirty = true
        updateStrokeCount()
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.saveNow()
        }
    }

    // MARK: Shapes

    private func snapShape(_ rough: PKStroke) {
        guard let last = canvas.drawing.strokes.last, last.renderBounds == rough.renderBounds,
              let shape = ShapeRecognizer.recognize(ShapeRecognizer.points(of: rough)) else { return }
        let before = canvas.drawing
        var after = before
        after.strokes.removeLast()
        after.strokes.append(contentsOf: ShapeRecognizer.strokes(for: shape, like: rough))
        setDrawing(after, undoTo: before)
    }

    private func setDrawing(_ drawing: PKDrawing, undoTo previous: PKDrawing) {
        replacingDrawing = true
        canvas.drawing = drawing
        replacingDrawing = false
        lastStrokeCount = drawing.strokes.count
        canvas.undoManager?.registerUndo(withTarget: self) { target in
            target.setDrawing(previous, undoTo: drawing)
        }
        dirty = true
        updateStrokeCount()
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in self?.saveNow() }
    }

    // MARK: Items: geometry

    private func notebookPoint(fromView p: CGPoint) -> CGPoint {
        let z = canvas.zoomScale
        return CGPoint(x: (p.x + canvas.contentOffset.x) / z, y: (p.y + canvas.contentOffset.y) / z)
    }

    private func viewRect(fromNotebook r: CGRect) -> CGRect {
        let z = canvas.zoomScale
        return CGRect(x: r.minX * z - canvas.contentOffset.x, y: r.minY * z - canvas.contentOffset.y,
                      width: r.width * z, height: r.height * z)
    }

    private func notebookFrame(of item: PageItem, page: Int) -> CGRect {
        guard layout.frames.indices.contains(page) else { return item.frame }
        return item.frame.offsetBy(dx: layout.frames[page].minX, dy: layout.frames[page].minY)
    }

    private func item(_ id: UUID, page: Int) -> PageItem? {
        document.items(onPage: page).first { $0.id == id }
    }

    private func hitItem(at point: CGPoint) -> (page: Int, item: PageItem)? {
        let page = layout.index(at: point)
        for item in document.items(onPage: page).reversed()
        where notebookFrame(of: item, page: page).insetBy(dx: -6, dy: -6).contains(point) {
            return (page, item)
        }
        return nil
    }

    private func loadImage(for item: PageItem) -> UIImage? {
        switch item.kind {
        case .text:
            return nil
        case .image:
            return item.image.flatMap { document.image(named: $0) }
        case .sticker:
            return item.sticker.flatMap(StickerCatalog.sticker).map { StickerCatalog.image(for: $0, width: 480) }
        }
    }

    /// Makes the item views of a page match the document.
    private func syncItemViews(page: Int) {
        guard document.meta.pages.indices.contains(page), layout.frames.indices.contains(page) else { return }
        let items = document.items(onPage: page)
        let ids = Set(items.map(\.id))
        for (id, view) in itemViews where view.tag == page && !ids.contains(id) {
            view.removeFromSuperview()
            itemViews[id] = nil
        }
        for item in items {
            let frame = notebookFrame(of: item, page: page)
            if let existing = itemViews[item.id] {
                if existing.item != item { existing.update(item: item, image: loadImage(for: item)) }
                existing.frame = frame
                existing.tag = page
                backdrop.bringSubviewToFront(existing)
            } else {
                let view = ItemView(item: item, image: loadImage(for: item))
                view.frame = frame
                view.tag = page
                view.setRenderScale(UIScreen.main.scale * max(canvas.zoomScale, 1))
                backdrop.addSubview(view)
                itemViews[item.id] = view
            }
        }
    }

    // MARK: Items: changes with undo

    private func setItems(_ items: [PageItem], pageID: UUID, undoTo old: [PageItem], actionName: String) {
        guard let page = document.meta.pages.firstIndex(where: { $0.id == pageID }) else { return }
        document.setItems(items, onPage: page)
        syncItemViews(page: page)
        if page == 0 { thumbNeeded = true }
        scheduleMetaSave()
        canvas.undoManager?.registerUndo(withTarget: self) { target in
            target.setItems(old, pageID: pageID, undoTo: items, actionName: actionName)
        }
        canvas.undoManager?.setActionName(actionName)
        if let sel = selection, item(sel.id, page: sel.page) == nil { selection = nil }
        refreshSelection()
        updateItemCount()
    }

    private func mutateItems(page: Int, actionName: String, _ change: (inout [PageItem]) -> Void) {
        guard document.meta.pages.indices.contains(page) else { return }
        let old = document.items(onPage: page)
        var new = old
        change(&new)
        guard new != old else { return }
        setItems(new, pageID: document.meta.pages[page].id, undoTo: old, actionName: actionName)
    }

    private func scheduleMetaSave() {
        metaTimer?.invalidate()
        metaTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            try? self?.document.saveMeta()
        }
    }

    // MARK: Items: selection

    private func select(page: Int, id: UUID) {
        selection = Selection(page: page, id: id)
        if let item = item(id, page: page), item.kind == .text, let style = item.style,
           state.settings.textStyle != style {
            state.settings.textStyle = style
        }
        refreshSelection()
    }

    private func refreshSelection() {
        guard textEdit == nil, let sel = selection, let item = item(sel.id, page: sel.page) else {
            overlay.selectionRect = nil
            if state.selectedKind != nil { state.selectedKind = nil }
            return
        }
        overlay.selectionRect = viewRect(fromNotebook: notebookFrame(of: item, page: sel.page))
        if state.selectedKind != item.kind { state.selectedKind = item.kind }
    }

    @objc private func itemTapped(_ g: UITapGestureRecognizer) {
        if textEdit != nil {
            endTextEditing()
            return
        }
        let point = notebookPoint(fromView: g.location(in: view))
        if let hit = hitItem(at: point) {
            select(page: hit.page, id: hit.item.id)
            if state.settings.tool == .text && hit.item.kind == .text {
                beginTextEditing(page: hit.page, id: hit.item.id)
            }
            return
        }
        selection = nil
        refreshSelection()
        if state.settings.tool == .text { createTextItem(at: point) }
    }

    private func selectionTapped(at point: CGPoint) {
        guard let sel = selection, let item = item(sel.id, page: sel.page) else { return }
        if item.kind == .text && state.settings.tool == .text {
            beginTextEditing(page: sel.page, id: sel.id)
        } else {
            editMenu.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: point))
        }
    }

    func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
                             suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let sel = selection, let item = item(sel.id, page: sel.page) else { return nil }
        var actions: [UIMenuElement] = []
        if item.kind == .text {
            actions.append(UIAction(title: "Edit Text") { [weak self] _ in self?.beginTextEditing(page: sel.page, id: sel.id) })
        }
        actions.append(UIAction(title: "Duplicate") { [weak self] _ in self?.duplicateSelected() })
        actions.append(UIAction(title: "Bring to Front") { [weak self] _ in self?.reorderSelected(toFront: true) })
        actions.append(UIAction(title: "Send to Back") { [weak self] _ in self?.reorderSelected(toFront: false) })
        actions.append(UIAction(title: "Delete", attributes: .destructive) { [weak self] _ in self?.deleteSelected() })
        return UIMenu(children: actions)
    }

    func deleteSelected() {
        guard let sel = selection else { return }
        selection = nil
        mutateItems(page: sel.page, actionName: "Delete") { $0.removeAll { $0.id == sel.id } }
    }

    private func duplicateSelected() {
        guard let sel = selection, var copy = item(sel.id, page: sel.page) else { return }
        copy.id = UUID()
        copy.frame = copy.frame.offsetBy(dx: 18, dy: 18)
        mutateItems(page: sel.page, actionName: "Duplicate") { $0.append(copy) }
        select(page: sel.page, id: copy.id)
    }

    private func reorderSelected(toFront: Bool) {
        guard let sel = selection else { return }
        mutateItems(page: sel.page, actionName: toFront ? "Bring to Front" : "Send to Back") { items in
            guard let i = items.firstIndex(where: { $0.id == sel.id }) else { return }
            let moved = items.remove(at: i)
            if toFront { items.append(moved) } else { items.insert(moved, at: 0) }
        }
    }

    private func dragSelected(by delta: CGPoint, resizing: Bool) {
        guard let sel = selection, document.meta.pages.indices.contains(sel.page) else { return }
        var items = document.items(onPage: sel.page)
        guard let i = items.firstIndex(where: { $0.id == sel.id }) else { return }
        if dragStart == nil { dragStart = (document.meta.pages[sel.page].id, items) }
        let z = canvas.zoomScale
        let d = CGPoint(x: delta.x / z, y: delta.y / z)
        let page = layout.frames[sel.page].size
        var item = items[i]
        if resizing {
            if item.kind == .text {
                item.frame.size.width = min(max(60, item.frame.width + d.x), page.width)
                item.frame.size.height = item.fittedTextHeight()
            } else {
                let aspect = item.frame.width / max(item.frame.height, 1)
                let width = min(max(24, item.frame.width + d.x), page.width * 1.2)
                item.frame.size = CGSize(width: width, height: width / aspect)
            }
        } else {
            item.frame.origin.x = min(max(item.frame.minX + d.x, -item.frame.width / 2), page.width - item.frame.width / 2)
            item.frame.origin.y = min(max(item.frame.minY + d.y, -item.frame.height / 2), page.height - item.frame.height / 2)
        }
        items[i] = item
        document.setItems(items, onPage: sel.page)
        syncItemViews(page: sel.page)
        refreshSelection()
    }

    private func finishDrag() {
        guard let start = dragStart else { return }
        dragStart = nil
        guard let page = document.meta.pages.firstIndex(where: { $0.id == start.pageID }) else { return }
        let now = document.items(onPage: page)
        guard now != start.items else { return }
        if page == 0 { thumbNeeded = true }
        scheduleMetaSave()
        canvas.undoManager?.registerUndo(withTarget: self) { target in
            target.setItems(start.items, pageID: start.pageID, undoTo: now, actionName: "Move")
        }
        canvas.undoManager?.setActionName("Move")
    }

    // MARK: Items: inserting

    private func place(_ item: PageItem) {
        let page = currentPageIndex
        guard layout.frames.indices.contains(page) else { return }
        let frame = layout.frames[page]
        let visible = CGRect(origin: notebookPoint(fromView: .zero),
                             size: CGSize(width: view.bounds.width / canvas.zoomScale,
                                          height: view.bounds.height / canvas.zoomScale))
        let area = visible.intersection(frame).isNull ? frame : visible.intersection(frame)
        var placed = item
        let maxWidth = frame.width * 0.8
        if placed.frame.width > maxWidth {
            placed.frame.size = CGSize(width: maxWidth, height: maxWidth * placed.frame.height / max(placed.frame.width, 1))
        }
        placed.frame.origin = CGPoint(x: area.midX - placed.frame.width / 2 - frame.minX,
                                      y: area.midY - placed.frame.height / 2 - frame.minY)
        mutateItems(page: page, actionName: "Insert") { $0.append(placed) }
        if state.settings.tool != .select { state.settings.tool = .select }
        select(page: page, id: placed.id)
    }

    func insertImage(_ image: UIImage) {
        do {
            let name = try document.saveImage(image)
            let aspect = image.size.width / max(image.size.height, 1)
            let width: CGFloat = 300
            place(PageItem(kind: .image, frame: CGRect(x: 0, y: 0, width: width, height: width / aspect), image: name))
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    func insertSticker(_ sticker: Sticker) {
        let width = sticker.defaultWidth
        place(PageItem(kind: .sticker, frame: CGRect(x: 0, y: 0, width: width, height: width / sticker.aspect),
                       sticker: sticker.id))
    }

    // MARK: Items: text

    private func createTextItem(at point: CGPoint) {
        let page = layout.index(at: point)
        guard layout.frames.indices.contains(page) else { return }
        let frame = layout.frames[page]
        let local = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
        let width = min(280, max(140, frame.width - local.x - 16))
        var item = PageItem(kind: .text, frame: CGRect(x: max(0, min(local.x, frame.width - width)), y: local.y - 16,
                                                      width: width, height: 32),
                            text: "", style: state.settings.textStyle, color: state.settings.inkColor)
        item.frame.size.height = item.fittedTextHeight()
        let baseline = document.items(onPage: page)
        document.setItems(baseline + [item], onPage: page)
        syncItemViews(page: page)
        updateItemCount()
        beginTextEditing(page: page, id: item.id, baseline: baseline)
    }

    private func beginTextEditing(page: Int, id: UUID, baseline: [PageItem]? = nil) {
        endTextEditing()
        guard let item = item(id, page: page) else { return }
        let editor = UITextView()
        editor.delegate = self
        editor.isScrollEnabled = false
        editor.backgroundColor = item.style?.fill.rgba?.uiColor ?? UIColor.white.withAlphaComponent(0.85)
        editor.layer.borderColor = UIColor.systemBlue.cgColor
        editor.layer.borderWidth = 1.5
        editor.layer.cornerRadius = 4
        editor.textContainer.lineFragmentPadding = 0
        editor.text = item.text
        editor.accessibilityIdentifier = "text-editor"
        view.insertSubview(editor, belowSubview: overlay)
        textEdit = TextEdit(page: page, id: id, view: editor, baseline: baseline ?? document.items(onPage: page))
        selection = Selection(page: page, id: id)
        itemViews[id]?.isHidden = true
        refreshSelection()
        styleTextEditor()
        layoutTextEditor()
        editor.becomeFirstResponder()
    }

    private func styleTextEditor() {
        guard let edit = textEdit, let item = item(edit.id, page: edit.page) else { return }
        let z = canvas.zoomScale
        let style = item.style ?? TextStyle()
        edit.view.font = style.font.font(size: CGFloat(style.size) * z, bold: style.bold)
        edit.view.textColor = (item.color ?? RGBA(0.11, 0.11, 0.13)).uiColor
        edit.view.backgroundColor = style.fill.rgba?.uiColor ?? UIColor.white.withAlphaComponent(0.85)
        let inset = PageItem.textInset * z
        edit.view.textContainerInset = UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
    }

    private func layoutTextEditor() {
        guard let edit = textEdit, let item = item(edit.id, page: edit.page) else { return }
        var rect = viewRect(fromNotebook: notebookFrame(of: item, page: edit.page))
        let fit = edit.view.sizeThatFits(CGSize(width: rect.width, height: .greatestFiniteMagnitude))
        rect.size.height = max(rect.height, fit.height)
        edit.view.frame = rect
    }

    func textViewDidChange(_ textView: UITextView) {
        layoutTextEditor()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        if textEdit?.view === textView { endTextEditing() }
    }

    func endTextEditing() {
        guard let edit = textEdit else { return }
        textEdit = nil
        let text = edit.view.text ?? ""
        edit.view.delegate = nil
        edit.view.resignFirstResponder()
        edit.view.removeFromSuperview()
        itemViews[edit.id]?.isHidden = false

        var items = document.items(onPage: edit.page)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = items.firstIndex(where: { $0.id == edit.id }) {
            if trimmed.isEmpty {
                items.remove(at: i)
                selection = nil
            } else {
                items[i].text = text
                items[i].frame.size.height = items[i].fittedTextHeight()
            }
        }
        if items != edit.baseline, document.meta.pages.indices.contains(edit.page) {
            setItems(items, pageID: document.meta.pages[edit.page].id, undoTo: edit.baseline,
                     actionName: trimmed.isEmpty ? "Delete Text" : "Text")
        } else {
            document.setItems(items, onPage: edit.page)
            syncItemViews(page: edit.page)
            updateItemCount()
        }
        refreshSelection()
    }

    private func applyTextStyle(_ settings: ToolSettings) {
        if let edit = textEdit {
            var items = document.items(onPage: edit.page)
            if let i = items.firstIndex(where: { $0.id == edit.id }) {
                items[i].style = settings.textStyle
                items[i].color = settings.inkColor
                document.setItems(items, onPage: edit.page)
                syncItemViews(page: edit.page)
                styleTextEditor()
                layoutTextEditor()
            }
            return
        }
        guard let sel = selection, let current = item(sel.id, page: sel.page), current.kind == .text else { return }
        mutateItems(page: sel.page, actionName: "Text Style") { items in
            guard let i = items.firstIndex(where: { $0.id == sel.id }) else { return }
            items[i].style = settings.textStyle
            items[i].color = settings.inkColor
            items[i].frame.size.height = items[i].fittedTextHeight()
        }
    }

    // MARK: Saving

    /// Writes each page whose ink changed since the last save, then the metadata.
    func saveNow() {
        endTextEditing()
        saveTimer?.invalidate()
        saveTimer = nil
        metaTimer?.invalidate()
        metaTimer = nil
        state.persistSettings()

        var firstPageChanged = thumbNeeded
        thumbNeeded = false
        var drawings: [PKDrawing] = []
        if dirty {
            dirty = false
            drawings = pageDrawings()
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
        }
        if firstPageChanged {
            let first = drawings.first ?? (pageDrawings().first ?? PKDrawing())
            document.writeThumbnail(firstPageInk: first)
        }
        document.meta.lastPage = currentPageIndex
        try? document.saveMeta()
    }
}
