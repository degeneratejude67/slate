import UIKit
import PDFKit
import PencilKit

enum Thumbnailer {
    /// A page with its items and ink, `width` points wide. Safe to call off the main thread.
    static func image(page: PDFPage?, pageSize: CGSize, drawing: PKDrawing, width: CGFloat,
                      items: [PageItem] = [], imageLoader: ((String) -> UIImage?)? = nil) -> UIImage {
        let scale = width / max(pageSize.width, 1)
        let size = CGSize(width: width, height: max(1, (pageSize.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let c = ctx.cgContext
            if let cgPage = page?.pageRef {
                c.saveGState()
                c.translateBy(x: 0, y: size.height)
                c.scaleBy(x: 1, y: -1)
                c.concatenate(cgPage.getDrawingTransform(.cropBox, rect: CGRect(origin: .zero, size: size),
                                                         rotate: 0, preserveAspectRatio: true))
                c.drawPDFPage(cgPage)
                c.restoreGState()
            }
            if !items.isEmpty {
                c.saveGState()
                c.scaleBy(x: scale, y: scale)
                for item in items { ItemRenderer.draw(item, imageLoader: imageLoader) }
                c.restoreGState()
            }
            guard !drawing.strokes.isEmpty else { return }
            var ink: UIImage?
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                ink = drawing.image(from: CGRect(origin: .zero, size: pageSize), scale: scale * 2)
            }
            ink?.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// Draws a page item into the current UIKit context, in page coordinates.
enum ItemRenderer {
    static func draw(_ item: PageItem, imageLoader: ((String) -> UIImage?)?) {
        switch item.kind {
        case .text:
            let style = item.style ?? TextStyle()
            if let fill = style.fill.rgba {
                fill.uiColor.setFill()
                UIBezierPath(roundedRect: item.frame, cornerRadius: 4).fill()
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: item.uiFont,
                .foregroundColor: (item.color ?? RGBA(0.11, 0.11, 0.13)).uiColor,
            ]
            let inset = item.frame.insetBy(dx: PageItem.textInset, dy: PageItem.textInset)
            ((item.text ?? "") as NSString).draw(with: inset, options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                attributes: attrs, context: nil)
        case .image:
            if let name = item.image, let image = imageLoader?(name) { image.draw(in: item.frame) }
        case .sticker:
            if let id = item.sticker, let sticker = StickerCatalog.sticker(id) {
                StickerCatalog.image(for: sticker).draw(in: item.frame)
            }
        }
    }
}

/// Library cover images, keyed by file and modification date.
final class ThumbCache {
    static let shared = ThumbCache()
    private let cache = NSCache<NSString, UIImage>()

    func image(at url: URL) -> UIImage? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date else { return nil }
        let key = "\(url.path)#\(date.timeIntervalSince1970)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
