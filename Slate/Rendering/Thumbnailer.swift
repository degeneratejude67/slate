import UIKit
import PDFKit
import PencilKit

enum Thumbnailer {
    /// A page with its ink, `width` points wide. Safe to call off the main thread.
    static func image(page: PDFPage?, pageSize: CGSize, drawing: PKDrawing, width: CGFloat) -> UIImage {
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
            guard !drawing.strokes.isEmpty else { return }
            var ink: UIImage?
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                ink = drawing.image(from: CGRect(origin: .zero, size: pageSize), scale: scale * 2)
            }
            ink?.draw(in: CGRect(origin: .zero, size: size))
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
