import SwiftUI
import Combine

enum Tool: String, CaseIterable {
    case select, hand, rectangle, ellipse, diamond, arrow, pen, text
    var title: String {
        switch self { case .select: "Selecionar"; case .hand: "Navegar"; case .rectangle: "Retângulo"; case .ellipse: "Elipse"; case .diamond: "Losango"; case .arrow: "Seta"; case .pen: "Desenhar"; case .text: "Texto" }
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
    @Published var saveMessage = "Salvo neste dispositivo"
    @Published var error: String?
    @Published var inlineTextID: UUID?
    private var beforeInlineText: Drawing?
    @Published var zoom: Double = 1
    @Published var resetViewport = UUID()
    private var pendingSave: Task<Void, Never>?
    private var canSave = true
    @Published private(set) var archive = DrawingArchive()
    var recentDrawings: [SavedDrawing] { archive.recent }
    var drawingName: String { archive.active?.name ?? "Novo desenho" }
    private let fileURL: URL
    init() {
        fileURL = URL.documentsDirectory.appending(path: "desenhos.militasdrawer.json")
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-reset") {
            archive.create()
            return
        }
        #endif
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                archive = try JSONDecoder().decode(DrawingArchive.self, from: Data(contentsOf: fileURL))
                try archive.validate()
            } else {
                let legacyURL = URL.documentsDirectory.appending(path: "quadro.militasdrawer.json")
                if FileManager.default.fileExists(atPath: legacyURL.path) {
                    let loaded = try JSONDecoder().decode(Drawing.self, from: Data(contentsOf: legacyURL))
                    guard loaded.version == 1 else { throw CocoaError(.fileReadUnknown) }
                    archive.create(drawing: loaded)
                }
            }
            if archive.drawings.isEmpty { archive.create() }
            drawing = archive.active?.drawing ?? Drawing()
            saveNow()
        } catch {
            canSave = false
            self.error = "Não foi possível abrir os desenhos salvos. Os arquivos originais foram preservados. \(error.localizedDescription)"
            saveMessage = "Falha ao abrir arquivo"
        }
    }
    @discardableResult
    func newDrawing() -> Bool {
        switchDrawing(to: nil)
    }
    @discardableResult
    func openDrawing(_ id: UUID) -> Bool {
        guard archive.drawings.contains(where: { $0.id == id }) else { return false }
        return switchDrawing(to: id)
    }
    func renameDrawing(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSave, !trimmed.isEmpty, trimmed != drawingName,
              let index = archive.drawings.firstIndex(where: { $0.id == archive.activeID }) else { return }
        finishTextEditing()
        guard saveNow() else { return }
        let previous = archive
        archive.drawings[index].name = trimmed
        archive.drawings[index].updatedAt = Date()
        if !saveNow() { archive = previous }
    }
    private func switchDrawing(to id: UUID?) -> Bool {
        finishTextEditing()
        guard saveNow() else { return false }
        let previous = archive
        if let id { archive.activeID = id } else { archive.create() }
        do {
            try JSONEncoder().encode(archive).write(to: fileURL, options: .atomic)
        } catch {
            archive = previous
            saveMessage = "Falha ao salvar"
            self.error = error.localizedDescription
            return false
        }
        drawing = archive.active?.drawing ?? Drawing()
        history = History()
        selectedIDs = []
        tool = .select
        zoom = 1
        resetViewport = UUID()
        return true
    }
    func commit(from before: Drawing) {
        history.record(before, after: drawing)
        guard before != drawing else { return }
        scheduleSave()
    }
    func scheduleSave() {
        guard canSave else { return }
        saveMessage = "Salvando…"
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            self?.saveNow()
        }
    }
    @discardableResult
    func saveNow() -> Bool {
        pendingSave?.cancel()
        guard canSave else { return false }
        do {
            archive.update(drawing)
            let data = try JSONEncoder().encode(archive)
            try data.write(to: fileURL, options: .atomic)
            saveMessage = "Salvo neste dispositivo"
            return true
        } catch { saveMessage = "Falha ao salvar"; self.error = error.localizedDescription; return false }
    }
    func undo() { finishTextEditing(); drawing = history.undo(drawing); selected = nil; scheduleSave() }
    func redo() { finishTextEditing(); drawing = history.redo(drawing); selected = nil; scheduleSave() }
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
