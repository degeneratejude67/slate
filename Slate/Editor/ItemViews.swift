import UIKit

/// Shows one page item. Lives in the backdrop, under the ink, in notebook coordinates.
final class ItemView: UIView {
    private(set) var item: PageItem
    private let label = UILabel()
    private let imageView = UIImageView()

    init(item: PageItem, image: UIImage?) {
        self.item = item
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        imageView.contentMode = .scaleToFill
        addSubview(imageView)
        addSubview(label)
        update(item: item, image: image)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func update(item: PageItem, image: UIImage?) {
        self.item = item
        switch item.kind {
        case .text:
            let style = item.style ?? TextStyle()
            label.isHidden = false
            imageView.isHidden = true
            label.font = item.uiFont
            label.textColor = (item.color ?? RGBA(0.11, 0.11, 0.13)).uiColor
            label.text = item.text
            backgroundColor = style.fill.rgba?.uiColor ?? .clear
            layer.cornerRadius = style.fill == .none ? 0 : 4
            layer.shadowOpacity = style.fill == .none ? 0 : 0.12
            layer.shadowRadius = 2
            layer.shadowOffset = CGSize(width: 0, height: 1)
        case .image, .sticker:
            label.isHidden = true
            imageView.isHidden = false
            backgroundColor = .clear
            layer.shadowOpacity = 0
            imageView.image = image
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        label.frame = bounds.insetBy(dx: PageItem.textInset, dy: PageItem.textInset)
    }

    /// Re-renders text at the current zoom so it stays sharp.
    func setRenderScale(_ scale: CGFloat) {
        let s = min(max(scale, 1), 8)
        guard abs(label.contentScaleFactor - s) > 0.01 else { return }
        label.contentScaleFactor = s
        label.layer.contentsScale = s
        label.setNeedsDisplay()
    }
}

/// The selection box over the canvas, in screen (view) coordinates. It only claims touches
/// on the selected item, so everything else still reaches the canvas.
final class SelectionOverlay: UIView {
    var selectionRect: CGRect? { didSet { updateChrome() } }
    var onDrag: ((_ delta: CGPoint, _ resizing: Bool) -> Void)?
    var onDragEnded: (() -> Void)?
    var onTap: ((CGPoint) -> Void)?

    private let border = CAShapeLayer()
    private let handle = UIView()
    private var resizing = false
    private var lastPoint: CGPoint = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        border.fillColor = UIColor.clear.cgColor
        border.strokeColor = UIColor.systemBlue.cgColor
        border.lineWidth = 1.5
        border.lineDashPattern = [6, 4]
        layer.addSublayer(border)
        handle.backgroundColor = .white
        handle.layer.borderColor = UIColor.systemBlue.cgColor
        handle.layer.borderWidth = 2
        handle.layer.cornerRadius = 9
        handle.frame = CGRect(x: 0, y: 0, width: 18, height: 18)
        handle.isUserInteractionEnabled = false
        addSubview(handle)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        accessibilityIdentifier = "selection"
        updateChrome()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func updateChrome() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let rect = selectionRect {
            border.isHidden = false
            handle.isHidden = false
            border.path = UIBezierPath(rect: rect.insetBy(dx: -3, dy: -3)).cgPath
            handle.center = CGPoint(x: rect.maxX + 3, y: rect.maxY + 3)
        } else {
            border.isHidden = true
            handle.isHidden = true
        }
        CATransaction.commit()
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard let rect = selectionRect else { return false }
        return rect.insetBy(dx: -16, dy: -16).contains(point)
    }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        let p = g.location(in: self)
        switch g.state {
        case .began:
            lastPoint = p
            if let rect = selectionRect {
                resizing = hypot(p.x - rect.maxX, p.y - rect.maxY) < 30
            }
        case .changed:
            onDrag?(CGPoint(x: p.x - lastPoint.x, y: p.y - lastPoint.y), resizing)
            lastPoint = p
        case .ended, .cancelled, .failed:
            onDragEnded?()
        default:
            break
        }
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        onTap?(g.location(in: self))
    }
}
