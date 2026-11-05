import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: String) {
        let value = UInt32(hex, radix: 16) ?? 0x27364B
        self.init(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}
struct DrawingCanvas: UIViewRepresentable {
    @ObservedObject var store: EditorStore
    func makeUIView(context: Context) -> CanvasView { CanvasView(store: store) }
    func updateUIView(_ view: CanvasView, context: Context) {
        if view.resetID != store.resetViewport { view.resetID = store.resetViewport; view.fitDrawing() }
        view.accessibilityValue = String(localized: "\(store.drawing.elements.count) elements")
        view.accessibilityHint = String(localized: "\(store.selectedIDs.count) selected. Drag in empty space to select an area.")
        view.syncTextEditor()
        view.setNeedsDisplay()
    }
}
final class CanvasView: UIView, UIGestureRecognizerDelegate, UITextViewDelegate {
    let store: EditorStore
    var scale: CGFloat = 1
    var offset = CGPoint(x: 32, y: 60)
    var resetID: UUID
    private var before: Drawing?
    private var origin = Point(0, 0)
    private var activeID: UUID?
    private var marquee: CGRect?
    private var selectionBeforeDrag: Set<UUID> = []
    private var movingIDs: Set<UUID> = []
    private var arrowEndpoint: ArrowEndpoint?
    private var resizeCorner: ResizeCorner?
    private var startingOffset = CGPoint.zero
    private var navigating = false
    private let shapeTextEditor = UITextView()
    private var editingShapeID: UUID?
    private var offsetBeforeText: CGPoint?
    init(store: EditorStore) {
        self.store = store; resetID = store.resetViewport
        super.init(frame: .zero)
        backgroundColor = .white; isMultipleTouchEnabled = true
        // Redraw at the new bounds on rotation instead of stretching the cached drawing.
        contentMode = .redraw
        let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
        pan.maximumNumberOfTouches = 1; addGestureRecognizer(pan)
        let navigation = UIPanGestureRecognizer(target: self, action: #selector(navigate(_:)))
        navigation.minimumNumberOfTouches = 2; navigation.delegate = self; addGestureRecognizer(navigation)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
        pinch.delegate = self; addGestureRecognizer(pinch)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:))); addGestureRecognizer(tap)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(editShapeText(_:)))
        doubleTap.numberOfTapsRequired = 2; addGestureRecognizer(doubleTap)
        tap.require(toFail: doubleTap)
        pan.delegate = self; tap.delegate = self; doubleTap.delegate = self
        shapeTextEditor.delegate = self
        shapeTextEditor.backgroundColor = .clear
        shapeTextEditor.textAlignment = .center
        shapeTextEditor.textContainer.lineFragmentPadding = 0
        shapeTextEditor.tintColor = UIColor(hex: "1E3A8A")
        shapeTextEditor.accessibilityIdentifier = "shapeTextEditor"
        shapeTextEditor.accessibilityLabel = String(localized: "Shape Text")
        shapeTextEditor.isHidden = true
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        toolbar.items = [.flexibleSpace(), UIBarButtonItem(title: String(localized: "Done"), style: .done, target: self, action: #selector(finishShapeText))]
        shapeTextEditor.inputAccessoryView = toolbar
        isAccessibilityElement = true
        accessibilityIdentifier = "drawingCanvas"
        accessibilityLabel = String(localized: "Diagram Canvas")
        accessibilityHint = String(localized: "Select a tool. Double-tap a shape to edit its text. Use two fingers to pan and pinch to zoom.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(touch.view?.isDescendant(of: shapeTextEditor) ?? false)
    }
    func syncTextEditor() {
        guard let id = store.inlineTextID, let shape = store.drawing.elements.first(where: { $0.id == id }) else {
            if editingShapeID != nil {
                editingShapeID = nil
                shapeTextEditor.resignFirstResponder()
                shapeTextEditor.isHidden = true
                shapeTextEditor.removeFromSuperview()
                isAccessibilityElement = true
                if let offsetBeforeText { offset = offsetBeforeText }
                offsetBeforeText = nil
            }
            return
        }
        if editingShapeID != id {
            editingShapeID = id
            offsetBeforeText = offset
            shapeTextEditor.text = shape.text
            shapeTextEditor.accessibilityIdentifier = shape.kind == .text ? "canvasTextEditor" : "shapeTextEditor"
            shapeTextEditor.accessibilityLabel = shape.kind == .text ? String(localized: "Canvas Text") : String(localized: "Shape Text")
            addSubview(shapeTextEditor)
            shapeTextEditor.isHidden = false
            isAccessibilityElement = false
            layoutTextEditor()
            shapeTextEditor.becomeFirstResponder()
            shapeTextEditor.selectedRange = NSRange(location: (shape.text as NSString).length, length: 0)
        }
        layoutTextEditor()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        layoutTextEditor()
    }
    private func layoutTextEditor() {
        guard let shape = store.drawing.elements.first(where: { $0.id == editingShapeID }) else { return }
        if shape.kind == .text {
            let font = UIFont.systemFont(ofSize: 20 * scale, weight: .medium)
            let height = min(max(44, shape.bounds.height * scale), max(44, bounds.height - 24))
            let width = 284 * scale
            var x = shape.start.x * scale + offset.x
            var y = shape.start.y * scale + offset.y
            let visibleX = max(12, min(x, bounds.width - width - 12))
            let visibleY = max(12, min(y, bounds.height - height - 12))
            offset.x += visibleX - x; offset.y += visibleY - y
            x = visibleX; y = visibleY
            shapeTextEditor.frame = CGRect(x: x, y: y, width: width, height: height)
            shapeTextEditor.font = font
            shapeTextEditor.textColor = UIColor(hex: shape.color)
            shapeTextEditor.textAlignment = .left
            shapeTextEditor.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 4 * scale)
            setNeedsDisplay()
            return
        }
        shapeTextEditor.textAlignment = .center
        let layout = shapeTextLayout(shape, color: UIColor(hex: shape.color))
        let box = layout.box
        // Keep the editing area above the keyboard as SwiftUI reduces the canvas height.
        let visibleHeight = max(44, bounds.height - 24)
        let editorHeight = min(box.height * scale, visibleHeight)
        var y = box.midY * scale + offset.y - editorHeight / 2
        let adjustedY = max(12, min(y, bounds.height - editorHeight - 12))
        offset.y += adjustedY - y; y = adjustedY
        shapeTextEditor.frame = CGRect(x: box.minX * scale + offset.x, y: y, width: max(1, box.width * scale), height: editorHeight)
        shapeTextEditor.font = UIFont.systemFont(ofSize: layout.fontSize * scale, weight: .medium)
        shapeTextEditor.textColor = UIColor(hex: shape.color)
        let textHeight = max(layout.measuredHeight, (shapeTextEditor.font?.lineHeight ?? 20) / scale) * scale
        let inset = max(0, (editorHeight - textHeight) / 2)
        shapeTextEditor.textContainerInset = UIEdgeInsets(top: inset, left: 0, bottom: inset, right: 0)
        setNeedsDisplay()
    }
    func textViewDidChange(_ textView: UITextView) {
        store.updateInlineText(textView.text)
        layoutTextEditor()
    }
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        (textView.text as NSString).replacingCharacters(in: range, with: text).count <= 2000
    }
    func textViewDidEndEditing(_ textView: UITextView) { store.finishTextEditing() }
    @objc private func finishShapeText() { store.finishTextEditing(); syncTextEditor(); setNeedsDisplay() }
    func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool {
        (a is UIPinchGestureRecognizer && (b as? UIPanGestureRecognizer)?.minimumNumberOfTouches == 2) || (b is UIPinchGestureRecognizer && (a as? UIPanGestureRecognizer)?.minimumNumberOfTouches == 2)
    }
    func world(_ p: CGPoint) -> Point { Point((p.x - offset.x) / scale, (p.y - offset.y) / scale) }
    func fitDrawing() {
        guard let first = store.drawing.elements.first else { scale = 1; offset = CGPoint(x: 32, y: 60); setNeedsDisplay(); return }
        let b = store.drawing.elements.dropFirst().reduce(first.bounds) { $0.union($1.bounds) }
        let visible = bounds.inset(by: UIEdgeInsets(top: 32, left: 32, bottom: 100, right: 32))
        scale = min(2, max(0.2, min(max(visible.width, 1) / max(b.width, 1), max(visible.height, 1) / max(b.height, 1))))
        offset = CGPoint(x: visible.midX - b.midX * scale, y: visible.midY - b.midY * scale)
        DispatchQueue.main.async { self.store.zoom = self.scale }; setNeedsDisplay()
    }
    func path(_ e: Element) -> UIBezierPath {
        let b = e.bounds
        switch e.kind {
        case .rectangle: return UIBezierPath(roundedRect: b, cornerRadius: 8)
        case .ellipse: return UIBezierPath(ovalIn: b)
        case .diamond:
            let p = UIBezierPath(); p.move(to: CGPoint(x: b.midX, y: b.minY)); p.addLine(to: CGPoint(x: b.maxX, y: b.midY)); p.addLine(to: CGPoint(x: b.midX, y: b.maxY)); p.addLine(to: CGPoint(x: b.minX, y: b.midY)); p.close(); return p
        case .arrow:
            let (a, z) = store.drawing.endpoints(for: e)
            let p = UIBezierPath(); p.move(to: a.cg); p.addLine(to: z.cg)
            let angle = atan2(z.y - a.y, z.x - a.x), length = 14.0
            p.move(to: Point(z.x - length * cos(angle - .pi / 6), z.y - length * sin(angle - .pi / 6)).cg)
            p.addLine(to: z.cg); p.addLine(to: Point(z.x - length * cos(angle + .pi / 6), z.y - length * sin(angle + .pi / 6)).cg); return p
        case .pen:
            let p = UIBezierPath(); p.move(to: (e.points.first ?? e.start).cg)
            for point in e.points.dropFirst() { p.addLine(to: point.cg) }; return p
        case .text: return UIBezierPath(rect: b)
        }
    }
    func hit(_ point: Point, shapesOnly: Bool = false) -> UUID? {
        store.drawing.elements.reversed().first { e in
            if shapesOnly && !e.isShape { return false }
            if e.kind == .arrow || e.kind == .pen {
                return path(e).cgPath.copy(strokingWithWidth: max(18 / scale, e.width + 8), lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point.cg)
            }
            return path(e).contains(point.cg) || path(e).cgPath.copy(strokingWithWidth: 12 / scale, lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point.cg)
        }?.id
    }
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.saveGState(); ctx.translateBy(x: offset.x, y: offset.y); ctx.scaleBy(x: scale, y: scale)
        for e in store.drawing.elements {
            let color = UIColor(hex: e.color), p = path(e)
            if e.kind == .text {
                if e.id != editingShapeID {
                    (e.text as NSString).draw(in: e.bounds, withAttributes: [.font: UIFont.systemFont(ofSize: 20, weight: .medium), .foregroundColor: color])
                }
            } else {
                if e.isShape { color.withAlphaComponent(0.06).setFill(); p.fill() }
                color.setStroke(); p.lineWidth = e.width; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
                if e.isShape && !e.text.isEmpty && e.id != editingShapeID { drawShapeText(e, color: color, context: ctx) }
            }
            if store.selectedIDs.contains(e.id) {
                let box = p.bounds.insetBy(dx: -7 / scale, dy: -7 / scale)
                let selection = UIBezierPath(roundedRect: box, cornerRadius: 5 / scale)
                UIColor(hex: "1E3A8A").setStroke(); selection.lineWidth = 1 / scale
                selection.stroke()
                if e.isShape && store.selectedIDs.count == 1 && marquee == nil {
                    for corner in ResizeCorner.allCases {
                        let point = corner.point(in: box)
                        let handle = UIBezierPath(ovalIn: CGRect(x: point.x - 4 / scale, y: point.y - 4 / scale, width: 8 / scale, height: 8 / scale))
                        UIColor.white.setFill(); handle.fill()
                        handle.lineWidth = 1.5 / scale; handle.stroke()
                    }
                }
            }
        }
        // Draw endpoint handles above every object so connected tips remain visible.
        if let arrow = store.drawing.elements.first(where: { $0.id == store.selected && $0.kind == .arrow }), marquee == nil {
            let ends = store.drawing.endpoints(for: arrow)
            for point in [ends.0, ends.1] {
                let handle = UIBezierPath(ovalIn: CGRect(x: point.x - 6 / scale, y: point.y - 6 / scale, width: 12 / scale, height: 12 / scale))
                UIColor.white.setFill(); handle.fill()
                UIColor(hex: "1E3A8A").setStroke(); handle.lineWidth = 2 / scale; handle.stroke()
            }
        }
        if let marquee {
            let area = UIBezierPath(rect: marquee)
            UIColor(hex: "1E3A8A").withAlphaComponent(0.08).setFill(); area.fill()
            UIColor(hex: "1E3A8A").setStroke(); area.lineWidth = 1 / scale; area.stroke()
        }
        ctx.restoreGState()
    }
    private func shapeTextLayout(_ element: Element, color: UIColor) -> (box: CGRect, fontSize: CGFloat, measuredHeight: CGFloat, attributes: [NSAttributedString.Key: Any]) {
        let bounds = element.bounds
        // Use a centered rectangle contained within each shape, leaving padding for its outline.
        let fraction: CGFloat = element.kind == .diamond ? 0.5 : (element.kind == .ellipse ? 0.707 : 1)
        let width = max(1, bounds.width * fraction - 16)
        let height = max(1, bounds.height * fraction - 16)
        let box = CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let text = element.text as NSString
        var fontSize: CGFloat = 20
        var attributes: [NSAttributedString.Key: Any] = [:]
        var measured = CGRect.zero
        repeat {
            attributes = [.font: UIFont.systemFont(ofSize: fontSize, weight: .medium), .foregroundColor: color, .paragraphStyle: paragraph]
            measured = text.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
            if ceil(measured.height) <= height || fontSize <= 8 { break }
            fontSize -= 1
        } while true
        return (box, fontSize, ceil(measured.height), attributes)
    }
    private func drawShapeText(_ element: Element, color: UIColor, context: CGContext) {
        let layout = shapeTextLayout(element, color: color)
        let box = layout.box
        let textHeight = min(box.height, layout.measuredHeight)
        let textRect = CGRect(x: box.minX, y: box.midY - textHeight / 2, width: box.width, height: textHeight)
        context.saveGState(); context.clip(to: box)
        (element.text as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine], attributes: layout.attributes, context: nil)
        context.restoreGState()
    }
    @objc func editShapeText(_ gesture: UITapGestureRecognizer) {
        let point = world(gesture.location(in: self))
        guard let id = hit(point), let shape = store.drawing.elements.first(where: { $0.id == id }), shape.isShape || shape.kind == .text else { return }
        store.selected = id
        store.tool = .select
        store.openText(at: point, id: id)
    }
    @objc func tap(_ gesture: UITapGestureRecognizer) {
        if editingShapeID != nil { finishShapeText(); return }
        let p = world(gesture.location(in: self))
        if store.tool == .text {
            let id = hit(p)
            store.openText(at: p, id: store.drawing.elements.first { $0.id == id && $0.kind == .text }?.id)
        } else if store.tool == .select { store.selected = hit(p) }
    }
    @objc func drag(_ g: UIPanGestureRecognizer) {
        let location = g.location(in: self), p = world(location)
        switch g.state {
        case .began:
            finishShapeText()
            let translation = g.translation(in: self)
            origin = world(CGPoint(x: location.x - translation.x, y: location.y - translation.y))
            before = store.drawing; startingOffset = offset; resizeCorner = nil; arrowEndpoint = nil; activeID = nil
            selectionBeforeDrag = store.selectedIDs; movingIDs = []; marquee = nil
            navigating = store.tool == .hand
            if navigating { return }
            if store.tool == .select {
                if let selected = store.drawing.elements.first(where: { $0.id == store.selected }), selected.isShape {
                    let box = selected.bounds.insetBy(dx: -7 / scale, dy: -7 / scale)
                    resizeCorner = ResizeCorner.allCases.min { a, b in
                        let pa = a.point(in: box), pb = b.point(in: box)
                        return hypot(origin.x - pa.x, origin.y - pa.y) < hypot(origin.x - pb.x, origin.y - pb.y)
                    }
                    if let corner = resizeCorner {
                        let handle = corner.point(in: box)
                        if hypot(origin.x - handle.x, origin.y - handle.y) > 22 / scale { resizeCorner = nil }
                    }
                }
                if let arrow = store.drawing.elements.first(where: { $0.id == store.selected && $0.kind == .arrow }) {
                    let ends = store.drawing.endpoints(for: arrow)
                    let startDistance = hypot(origin.x - ends.0.x, origin.y - ends.0.y)
                    let endDistance = hypot(origin.x - ends.1.x, origin.y - ends.1.y)
                    if min(startDistance, endDistance) <= 22 / scale {
                        arrowEndpoint = startDistance < endDistance ? .start : .end
                    }
                }
                if arrowEndpoint != nil {
                    activeID = store.selected
                    updateDraggedElement(at: p)
                } else if resizeCorner != nil {
                    activeID = store.selected
                } else if let id = hit(origin) {
                    if !store.selectedIDs.contains(id) { store.selected = id }
                    activeID = id
                    movingIDs = store.selectedIDs
                } else {
                    store.selected = nil
                    marquee = CGRect(origin: origin.cg, size: .zero)
                }
            } else if let kind = ElementKind(rawValue: store.tool.rawValue), kind != .text {
                var e = Element(kind: kind, start: origin, end: p, color: store.color)
                if kind == .pen { e.points = [origin, p] }
                if kind == .arrow { e.source = hit(origin, shapesOnly: true) }
                activeID = e.id; store.selected = nil; store.drawing.elements.append(e)
            }
        case .changed:
            if navigating {
                let t = g.translation(in: self); offset = CGPoint(x: startingOffset.x + t.x, y: startingOffset.y + t.y); setNeedsDisplay(); return
            }
            updateDraggedElement(at: p)
        case .ended:
            if !navigating { updateDraggedElement(at: p) }
            if let id = activeID, let e = store.drawing.elements.first(where: { $0.id == id }), store.tool != .select {
                if hypot(e.end.x - e.start.x, e.end.y - e.start.y) < 4 && e.kind != .pen { store.drawing.elements.removeAll { $0.id == id } }
                else {
                    store.selected = id
                    if e.kind != .pen { store.tool = .select }
                }
            }
            if let before { store.commit(from: before) }; before = nil; arrowEndpoint = nil; activeID = nil; marquee = nil; movingIDs = []
        case .cancelled, .failed:
            cancelEditing()
        default: break
        }
        setNeedsDisplay()
    }
    private func updateDraggedElement(at p: Point) {
        if let arrowEndpoint, let activeID, var drawing = before {
            drawing.reconnectArrow(activeID, endpoint: arrowEndpoint, at: p, shapeID: hit(p, shapesOnly: true))
            store.drawing = drawing
            return
        }
        if marquee != nil {
            let area = CGRect(x: min(origin.x, p.x), y: min(origin.y, p.y), width: abs(p.x - origin.x), height: abs(p.y - origin.y))
            marquee = area
            store.selectedIDs = store.drawing.elements(enclosedBy: area)
            return
        }
        if !movingIDs.isEmpty, var drawing = before {
            drawing.moveSelection(movingIDs, dx: p.x - origin.x, dy: p.y - origin.y)
            store.drawing = drawing
            return
        }
        guard let i = store.drawing.elements.firstIndex(where: { $0.id == activeID }) else { return }
        if store.tool == .select, var original = before?.elements.first(where: { $0.id == activeID }) {
            if original.kind == .arrow { let ends = before!.endpoints(for: original); original.start = ends.0; original.end = ends.1; original.source = nil; original.target = nil }
            if let resizeCorner {
                original.resize(corner: resizeCorner, dx: p.x - origin.x, dy: p.y - origin.y)
            } else {
                original.move(dx: p.x - origin.x, dy: p.y - origin.y)
            }
            store.drawing.elements[i] = original
        } else {
            store.drawing.elements[i].end = p
            if store.tool == .pen { store.drawing.elements[i].points.append(p) }
            if store.tool == .arrow { store.drawing.elements[i].target = hit(p, shapesOnly: true) }
        }
    }
    private func cancelEditing() {
        if let before { store.drawing = before; store.selectedIDs = selectionBeforeDrag }
        before = nil; arrowEndpoint = nil; activeID = nil; marquee = nil; movingIDs = []
    }
    @objc func navigate(_ g: UIPanGestureRecognizer) {
        if g.state == .began { finishShapeText(); cancelEditing() }
        let t = g.translation(in: self); offset.x += t.x; offset.y += t.y; g.setTranslation(.zero, in: self); setNeedsDisplay()
    }
    @objc func pinch(_ g: UIPinchGestureRecognizer) {
        if g.state == .began { finishShapeText(); cancelEditing() }
        let center = g.location(in: self), anchor = world(center)
        scale = min(4, max(0.2, scale * g.scale)); g.scale = 1
        offset = CGPoint(x: center.x - anchor.x * scale, y: center.y - anchor.y * scale)
        store.zoom = scale; setNeedsDisplay()
    }
}
