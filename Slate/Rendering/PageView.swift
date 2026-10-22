import UIKit
import PDFKit

/// One page behind the ink: white sheet, shadow, and the PDF content in a tiled layer so it
/// stays sharp at any zoom without holding a full-page bitmap per zoom level.
final class PageView: UIView {
    private let tiles = PDFTileLayer()

    init(page: PDFPage?, frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        isUserInteractionEnabled = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.14
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 1.5)
        layer.shadowPath = UIBezierPath(rect: bounds).cgPath

        tiles.configure(page: page, size: frame.size)
        tiles.frame = bounds
        tiles.contentsScale = UIScreen.main.scale
        layer.addSublayer(tiles)
        tiles.setNeedsDisplay()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

final class PDFTileLayer: CATiledLayer {
    override class func fadeDuration() -> CFTimeInterval { 0.08 }

    private var cgPage: CGPDFPage?
    /// Held so the page's document outlives a reload of the notebook PDF.
    private var cgDocument: CGPDFDocument?
    private var pageSize: CGSize = .zero

    override init() {
        super.init()
        levelsOfDetail = 4
        levelsOfDetailBias = 4
        tileSize = CGSize(width: 512, height: 512)
        backgroundColor = UIColor.white.cgColor
    }

    override init(layer: Any) {
        super.init(layer: layer)
        if let other = layer as? PDFTileLayer {
            cgPage = other.cgPage
            cgDocument = other.cgDocument
            pageSize = other.pageSize
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(page: PDFPage?, size: CGSize) {
        cgPage = page?.pageRef
        cgDocument = page?.pageRef?.document
        pageSize = size
    }

    // Called on background threads; reads only state set before the first draw.
    override func draw(in ctx: CGContext) {
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(ctx.boundingBoxOfClipPath)
        guard let cgPage else { return }
        ctx.saveGState()
        ctx.translateBy(x: 0, y: pageSize.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.concatenate(cgPage.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: pageSize),
                                                   rotate: 0, preserveAspectRatio: true))
        ctx.interpolationQuality = .high
        ctx.drawPDFPage(cgPage)
        ctx.restoreGState()
    }
}
