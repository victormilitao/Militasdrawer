import SwiftUI
import Combine

enum Tool: String, CaseIterable {
    case select, hand, rectangle, ellipse, diamond, arrow, pen, text
    var title: String {
        switch self { case .select: String(localized: "Select"); case .hand: String(localized: "Pan"); case .rectangle: String(localized: "Rectangle"); case .ellipse: String(localized: "Ellipse"); case .diamond: String(localized: "Diamond"); case .arrow: String(localized: "Arrow"); case .pen: String(localized: "Draw"); case .text: String(localized: "Text") }
    }
    var icon: String {
        switch self { case .select: "cursorarrow"; case .hand: "hand.draw"; case .rectangle: "rectangle"; case .ellipse: "circle"; case .diamond: "diamond"; case .arrow: "arrow.up.right"; case .pen: "pencil.tip"; case .text: "textformat" }
    }
}
@MainActor final class EditorStore: ObservableObject {
    @Published var drawing = Drawing()
    @Published var tool: Tool = .select
    @Published var selectedIDs: Set<UUID> = []
    var selected: UUID? {
        get { selectedIDs.count == 1 ? selectedIDs.first : nil }
        set { selectedIDs = newValue.map { [$0] } ?? [] }
    }
    @Published var color = "27364B"
    @Published var history = History()
    @Published var saveMessage = String(localized: "Saved on this device")
    @Published var error: String?
    @Published var inlineTextID: UUID?
    private var beforeInlineText: Drawing?
    @Published var zoom: Double = 1
    @Published var resetViewport = UUID()
    private var pendingSave: Task<Void, Never>?
    private var canSave = true
    private let fileURL: URL
    init() {
        fileURL = URL.documentsDirectory.appending(path: "quadro.militasdrawer.json")
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-reset") { return }
        #endif
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let loaded = try JSONDecoder().decode(Drawing.self, from: Data(contentsOf: fileURL))
                guard loaded.version == 1 else { throw CocoaError(.fileReadUnknown) }
                drawing = loaded
            }
        } catch {
            canSave = false
            self.error = String(localized: "Unable to open the saved drawing. The original file has been preserved. \(error.localizedDescription)")
            saveMessage = String(localized: "Unable to open file")
        }
    }
    func commit(from before: Drawing) {
        history.record(before, after: drawing)
        guard before != drawing else { return }
        scheduleSave()
    }
    func scheduleSave() {
        guard canSave else { return }
        saveMessage = String(localized: "Saving…")
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            self?.saveNow()
        }
    }
    func saveNow() {
        pendingSave?.cancel()
        guard canSave else { return }
        do {
            let data = try JSONEncoder().encode(drawing)
            try data.write(to: fileURL, options: .atomic)
            saveMessage = String(localized: "Saved on this device")
        } catch { saveMessage = String(localized: "Unable to save"); self.error = error.localizedDescription }
    }
    func undo() { finishTextEditing(); drawing = history.undo(drawing); selected = nil; scheduleSave() }
    func redo() { finishTextEditing(); drawing = history.redo(drawing); selected = nil; scheduleSave() }
    func duplicateSelection() {
        finishTextEditing()
        guard let id = selected else { return }
        let before = drawing
        guard let copyID = drawing.duplicate(id) else { return }
        drawing.moveSelection([copyID], dx: 24 / zoom, dy: 24 / zoom)
        selected = copyID
        tool = .select
        commit(from: before)
    }
    func deleteSelection() {
        finishTextEditing()
        guard !selectedIDs.isEmpty else { return }; let before = drawing
        for id in selectedIDs { drawing.remove(id) }
        selected = nil; commit(from: before)
    }
    func setColor(_ value: String) {
        finishTextEditing()
        color = value
        let before = drawing
        for i in drawing.elements.indices where selectedIDs.contains(drawing.elements[i].id) { drawing.elements[i].color = value }
        commit(from: before)
    }
    func openText(at point: Point, id: UUID? = nil) {
        finishTextEditing()
        beforeInlineText = drawing
        let target: UUID
        if let element = drawing.elements.first(where: { $0.id == id && ($0.isShape || $0.kind == .text) }) {
            target = element.id
        } else {
            let element = Element(kind: .text, start: point, end: point.moved(30, 26), color: color)
            drawing.elements.append(element)
            target = element.id
        }
        selected = target
        tool = .select
        inlineTextID = target
    }
    func updateInlineText(_ text: String) {
        guard let i = drawing.elements.firstIndex(where: { $0.id == inlineTextID }) else { return }
        drawing.elements[i].text = text
        if drawing.elements[i].kind == .text {
            let size = (text as NSString).boundingRect(with: CGSize(width: 280, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: UIFont.systemFont(ofSize: 20, weight: .medium)], context: nil).size
            drawing.elements[i].end = drawing.elements[i].start.moved(max(ceil(size.width), 30) + 4, max(ceil(size.height), 26) + 4)
        }
        scheduleSave()
    }
    func finishTextEditing() {
        guard let id = inlineTextID else { return }
        inlineTextID = nil
        if let element = drawing.elements.first(where: { $0.id == id }), element.kind == .text,
           element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            drawing.remove(id)
            selected = nil
        }
        if let beforeInlineText { commit(from: beforeInlineText) }
        beforeInlineText = nil
    }
}
