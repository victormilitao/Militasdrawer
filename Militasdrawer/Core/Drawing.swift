import Foundation
import CoreGraphics

enum ElementKind: String, Codable, CaseIterable { case rectangle, ellipse, diamond, arrow, pen, text }
enum ResizeCorner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
    func point(in bounds: CGRect) -> Point {
        Point(self == .topLeft || self == .bottomLeft ? bounds.minX : bounds.maxX,
              self == .topLeft || self == .topRight ? bounds.minY : bounds.maxY)
    }
    var opposite: ResizeCorner {
        switch self {
        case .topLeft: .bottomRight
        case .topRight: .bottomLeft
        case .bottomLeft: .topRight
        case .bottomRight: .topLeft
        }
    }
}
struct Point: Codable, Equatable {
    var x: Double; var y: Double
    init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    var cg: CGPoint { CGPoint(x: x, y: y) }
    func moved(_ dx: Double, _ dy: Double) -> Point { Point(x + dx, y + dy) }
}
struct Element: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: ElementKind
    var start: Point
    var end: Point
    var points: [Point] = []
    var text = ""
    var color = "27364B"
    var width: Double = 2.5
    var source: UUID?
    var target: UUID?
    var bounds: CGRect {
        let ps = kind == .pen && !points.isEmpty ? points : [start, end]
        let xs = ps.map(\.x), ys = ps.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }
    var isShape: Bool { [.rectangle, .ellipse, .diamond].contains(kind) }
    mutating func resize(corner: ResizeCorner, dx: Double, dy: Double) {
        guard isShape else { return }
        let fixed = corner.opposite.point(in: bounds)
        let dragged = corner.point(in: bounds).moved(dx, dy)
        start = fixed
        end = dragged
    }
    mutating func move(dx: Double, dy: Double) {
        start = start.moved(dx, dy); end = end.moved(dx, dy)
        points = points.map { $0.moved(dx, dy) }
    }
    func anchor(toward p: Point) -> Point {
        let b = bounds, cx = b.midX, cy = b.midY
        let dx = p.x - cx, dy = p.y - cy
        let rx = max(b.width / 2, 1), ry = max(b.height / 2, 1)
        guard abs(dx) + abs(dy) > 0.001 else { return Point(cx, cy) }
        let divisor: Double
        switch kind {
        case .ellipse: divisor = sqrt(pow(dx / rx, 2) + pow(dy / ry, 2))
        case .diamond: divisor = abs(dx) / rx + abs(dy) / ry
        default: divisor = max(abs(dx) / rx, abs(dy) / ry)
        }
        return Point(cx + dx / divisor, cy + dy / divisor)
    }
}
struct Drawing: Codable, Equatable {
    var version = 1
    var elements: [Element] = []
    func selectionBounds(for element: Element) -> CGRect {
        guard element.kind == .arrow else { return element.bounds }
        let (a, b) = endpoints(for: element)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
    func elements(enclosedBy area: CGRect) -> Set<UUID> {
        Set(elements.filter { element in
            let b = selectionBounds(for: element)
            return area.minX <= b.minX && area.maxX >= b.maxX && area.minY <= b.minY && area.maxY >= b.maxY
        }.map(\.id))
    }
    mutating func moveSelection(_ ids: Set<UUID>, dx: Double, dy: Double) {
        let original = self
        for i in elements.indices where ids.contains(elements[i].id) {
            if elements[i].kind == .arrow {
                let ends = original.endpoints(for: elements[i])
                elements[i].start = ends.0
                elements[i].end = ends.1
                if let source = elements[i].source, !ids.contains(source) { elements[i].source = nil }
                if let target = elements[i].target, !ids.contains(target) { elements[i].target = nil }
            }
            elements[i].move(dx: dx, dy: dy)
        }
    }
    func endpoints(for e: Element) -> (Point, Point) {
        let source = elements.first { $0.id == e.source && $0.isShape }
        let target = elements.first { $0.id == e.target && $0.isShape }
        let a = source.map { Point($0.bounds.midX, $0.bounds.midY) } ?? e.start
        let b = target.map { Point($0.bounds.midX, $0.bounds.midY) } ?? e.end
        return (source?.anchor(toward: b) ?? a, target?.anchor(toward: a) ?? b)
    }
    mutating func remove(_ id: UUID) {
        // Freeze connected endpoints before deleting the shape.
        for i in elements.indices where elements[i].source == id || elements[i].target == id {
            let (a, b) = endpoints(for: elements[i])
            elements[i].start = a; elements[i].end = b
            if elements[i].source == id { elements[i].source = nil }
            if elements[i].target == id { elements[i].target = nil }
        }
        elements.removeAll { $0.id == id }
    }
}
struct History {
    private(set) var past: [Drawing] = []
    private(set) var future: [Drawing] = []
    mutating func record(_ before: Drawing, after: Drawing) {
        guard before != after else { return }
        past.append(before); if past.count > 100 { past.removeFirst() }; future.removeAll()
    }
    mutating func undo(_ current: Drawing) -> Drawing {
        guard let previous = past.popLast() else { return current }
        future.append(current); return previous
    }
    mutating func redo(_ current: Drawing) -> Drawing {
        guard let next = future.popLast() else { return current }
        past.append(current); return next
    }
}
