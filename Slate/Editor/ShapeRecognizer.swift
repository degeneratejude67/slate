import UIKit
import PencilKit

/// Turns a rough hand-drawn stroke into a clean line, triangle, rectangle/quadrilateral,
/// circle or ellipse. Anything else is left alone (returns nil).
enum ShapeRecognizer {
    enum Shape: Equatable {
        case line(CGPoint, CGPoint)
        case polygon([CGPoint])
        case ellipse(CGRect)
    }

    static func recognize(_ points: [CGPoint]) -> Shape? {
        guard points.count >= 4 else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        let box = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        let diag = hypot(box.width, box.height)
        guard diag >= 14 else { return nil }

        var length: CGFloat = 0
        for i in 1..<points.count { length += distance(points[i - 1], points[i]) }
        let first = points.first!, last = points.last!
        let closed = distance(first, last) < max(0.18 * length, 0.2 * diag)

        if !closed {
            // A line if nothing strays far from the chord.
            let chord = distance(first, last)
            guard chord > 0.7 * length else { return nil }
            let worst = points.map { perpendicular($0, first, last) }.max() ?? 0
            return worst < max(0.07 * chord, 3) ? .line(first, last) : nil
        }

        let ring = points + [first]
        let epsilon = 0.09 * diag
        let corners = removeCollinear(Array(douglasPeucker(ring, epsilon: epsilon).dropLast()), epsilon: epsilon)
        let vertexCount = corners.count

        if vertexCount == 3 {
            return .polygon(corners)
        }
        if vertexCount == 4 {
            if isAxisAligned(corners, box: box) {
                return .polygon([CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                                 CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)])
            }
            return .polygon(corners)
        }

        // Ellipse: how far points sit from the ellipse inscribed in the bounding box.
        let rx = box.width / 2, ry = box.height / 2
        guard rx > 4, ry > 4 else { return nil }
        let cx = box.midX, cy = box.midY
        let error = points.map { p -> CGFloat in
            let v = pow((p.x - cx) / rx, 2) + pow((p.y - cy) / ry, 2)
            return abs(sqrt(v) - 1)
        }.reduce(0, +) / CGFloat(points.count)
        guard error < 0.14 else { return nil }
        if abs(rx - ry) / max(rx, ry) < 0.15 {
            let r = (rx + ry) / 2
            return .ellipse(CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
        }
        return .ellipse(box)
    }

    /// Clean strokes for a shape, drawn with the ink and width of the rough stroke.
    static func strokes(for shape: Shape, like rough: PKStroke) -> [PKStroke] {
        let sample = rough.path.first
        let width = sample?.size.width ?? 2.5
        func point(_ p: CGPoint, _ t: TimeInterval) -> PKStrokePoint {
            PKStrokePoint(location: p, timeOffset: t, size: CGSize(width: width, height: width),
                          opacity: sample?.opacity ?? 1, force: sample?.force ?? 1,
                          azimuth: sample?.azimuth ?? 0, altitude: sample?.altitude ?? .pi / 2)
        }
        func stroke(_ pts: [CGPoint]) -> PKStroke {
            let controls = pts.enumerated().map { point($0.element, TimeInterval($0.offset) * 0.005) }
            return PKStroke(ink: rough.ink, path: PKStrokePath(controlPoints: controls, creationDate: Date()),
                            transform: .identity, mask: nil)
        }

        switch shape {
        case .line(let a, let b):
            return [stroke(densify([a, b], step: 6))]
        case .polygon(let corners):
            // Corners repeated so the spline keeps them sharp.
            var pts: [CGPoint] = []
            let closed = corners + [corners[0]]
            for i in 0..<(closed.count - 1) {
                let segment = densify([closed[i], closed[i + 1]], step: 6)
                pts += [closed[i], closed[i]] + segment.dropFirst().dropLast()
            }
            pts += [closed[0], closed[0], closed[0]]
            return [stroke(pts)]
        case .ellipse(let rect):
            let steps = 96
            let pts = (0...steps).map { i -> CGPoint in
                let a = CGFloat(i) / CGFloat(steps) * 2 * .pi - .pi / 2
                return CGPoint(x: rect.midX + rect.width / 2 * cos(a), y: rect.midY + rect.height / 2 * sin(a))
            }
            return [stroke(pts)]
        }
    }

    /// The points a stroke passes through, in drawing coordinates.
    static func points(of stroke: PKStroke) -> [CGPoint] {
        stroke.path.interpolatedPoints(by: .distance(3)).map { $0.location.applying(stroke.transform) }
    }

    // MARK: Geometry

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private static func perpendicular(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let len = distance(a, b)
        guard len > 0 else { return distance(p, a) }
        return abs((b.x - a.x) * (a.y - p.y) - (a.x - p.x) * (b.y - a.y)) / len
    }

    static func douglasPeucker(_ pts: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        var index = 0
        var worst: CGFloat = 0
        for i in 1..<(pts.count - 1) {
            let d = perpendicular(pts[i], pts[0], pts[pts.count - 1])
            if d > worst { worst = d; index = i }
        }
        // A closed ring has identical ends; split at the farthest point from the start.
        if distance(pts[0], pts[pts.count - 1]) < 0.5 {
            var far = 0
            var farDist: CGFloat = 0
            for i in 1..<(pts.count - 1) where distance(pts[i], pts[0]) > farDist {
                farDist = distance(pts[i], pts[0]); far = i
            }
            guard far > 0 else { return [pts[0], pts[pts.count - 1]] }
            let left = douglasPeucker(Array(pts[0...far]), epsilon: epsilon)
            let right = douglasPeucker(Array(pts[far...]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        }
        if worst > epsilon {
            let left = douglasPeucker(Array(pts[0...index]), epsilon: epsilon)
            let right = douglasPeucker(Array(pts[index...]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        }
        return [pts[0], pts[pts.count - 1]]
    }

    /// Drops vertices that sit on the line between their neighbours, such as the point
    /// where the pen started in the middle of an edge.
    private static func removeCollinear(_ corners: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        var pts = corners
        var changed = true
        while changed && pts.count > 3 {
            changed = false
            for i in 0..<pts.count {
                let prev = pts[(i - 1 + pts.count) % pts.count], next = pts[(i + 1) % pts.count]
                if perpendicular(pts[i], prev, next) < epsilon * 0.8 {
                    pts.remove(at: i)
                    changed = true
                    break
                }
            }
        }
        return pts
    }

    private static func isAxisAligned(_ corners: [CGPoint], box: CGRect) -> Bool {
        let tolerance = 0.18 * max(box.width, box.height)
        let boxCorners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                          CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
        return corners.allSatisfy { c in boxCorners.contains { distance($0, c) < tolerance } }
    }

    private static func densify(_ pts: [CGPoint], step: CGFloat) -> [CGPoint] {
        guard pts.count == 2 else { return pts }
        let (a, b) = (pts[0], pts[1])
        let n = max(2, Int(distance(a, b) / step))
        return (0...n).map { i in
            let t = CGFloat(i) / CGFloat(n)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
    }
}
