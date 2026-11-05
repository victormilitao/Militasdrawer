import SwiftUI

@main struct MilitasdrawerApp: App {
    @StateObject private var store = EditorStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            EditorView(store: store)
                .onChange(of: phase) { _, value in if value != .active { store.finishTextEditing(); store.saveNow() } }
        }
    }
}
struct EditorView: View {
    @ObservedObject var store: EditorStore
    @Environment(\.horizontalSizeClass) var sizeClass
    @State private var showsDrawings = false
    @State private var showsRename = false
    @State private var proposedName = ""
    private let palette = ["27364B", "6253D9", "277C77", "D45F49", "C68A20"]
    private let accent = Color(uiColor: UIColor(hex: "1E3A8A"))
    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack(alignment: .topLeading) {
                DrawingCanvas(store: store)
                if store.drawing.elements.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Espaço para sua\npróxima ideia.").font(.system(size: sizeClass == .regular ? 28 : 22, weight: .semibold, design: .rounded))
                        Text("Escolha uma forma e arraste para começar.").font(.caption).foregroundStyle(.secondary)
                    }.padding(24).padding(.top, 24).allowsHitTesting(false)
                }
            }
            if store.inlineTextID == nil { bottomBar }
        }
        .accessibilityHidden(showsDrawings)
        .overlay {
            if showsDrawings {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Color.black.opacity(0.2).ignoresSafeArea()
                            .onTapGesture { showsDrawings = false }
                            .accessibilityLabel("Fechar desenhos recentes")
                            .accessibilityAddTraits(.isButton)
                        recentDrawingsSheet
                            .frame(width: min(360, geometry.size.width - 24))
                            .frame(maxHeight: .infinity)
                            .background(.regularMaterial)
                            .shadow(color: .black.opacity(0.15), radius: 16, x: 4)
                    }
                }
            }
        }
        .background(Color.white).tint(accent).preferredColorScheme(.light)
        .alert("Não foi possível concluir", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    private var header: some View {
        HStack(spacing: 8) {
            Button {
                store.finishTextEditing()
                store.saveNow()
                showsDrawings = true
            } label: {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 18)).frame(width: 44, height: 44)
            }.accessibilityLabel("Desenhos recentes")
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    store.finishTextEditing()
                    proposedName = store.drawingName
                    showsRename = true
                } label: {
                    Text(store.drawingName).lineLimit(1).font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel("Renomear desenho")
                    .accessibilityValue(store.drawingName)
                    .alert("Renomear desenho", isPresented: $showsRename) {
                        TextField("Nome do desenho", text: $proposedName)
                        Button("Cancelar", role: .cancel) { }
                        Button("Salvar") { store.renameDrawing(proposedName) }
                            .disabled(proposedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                Text(store.saveMessage).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward").font(.system(size: 16)).frame(width: 44, height: 44) }.disabled(store.history.past.isEmpty).accessibilityLabel("Desfazer").keyboardShortcut("z", modifiers: .command)
            Button { store.redo() } label: { Image(systemName: "arrow.uturn.forward").font(.system(size: 16)).frame(width: 44, height: 44) }.disabled(store.history.future.isEmpty).accessibilityLabel("Refazer").keyboardShortcut("z", modifiers: [.command, .shift])
        }.padding(.horizontal, 12).padding(.vertical, 2)
    }
    private var recentDrawingsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Desenhos recentes").font(.headline).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { showsDrawings = false } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }.accessibilityLabel("Fechar desenhos recentes")
            }
            Button {
                if store.newDrawing() { showsDrawings = false }
            } label: {
                Label("Novo desenho", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.borderedProminent)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.recentDrawings) { entry in
                        Button {
                            if store.openDrawing(entry.id) { showsDrawings = false }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(entry.name).font(.body.weight(.medium))
                                    Text("Atualizado em \(entry.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                if entry.id == store.archive.activeID {
                                    Image(systemName: "checkmark").accessibilityLabel("Desenho atual")
                                }
                            }
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(entry.id == store.archive.activeID ? accent.opacity(0.08) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(entry.id == store.archive.activeID ? .isSelected : [])
                    }
                }
            }
        }.padding(16)
            .accessibilityAddTraits(.isModal)
    }
    private var bottomBar: some View {
        VStack(spacing: 2) {
            HStack {
                HStack(spacing: 0) {
                    ForEach(palette, id: \.self) { hex in
                        Button { store.setColor(hex) } label: {
                            Circle().fill(Color(uiColor: UIColor(hex: hex))).frame(width: 16, height: 16)
                                .padding(4).overlay(Circle().stroke(store.color == hex ? accent : .clear, lineWidth: 1.5)).frame(width: 44, height: 44)
                        }.accessibilityLabel("Cor \(colorName(hex))").accessibilityAddTraits(store.color == hex ? .isSelected : [])
                    }
                }
                Spacer(minLength: 0)
                if let selected = store.drawing.elements.first(where: { $0.id == store.selected }), selected.kind == .text || selected.isShape {
                    Button { store.openText(at: selected.start, id: selected.id) } label: { Image(systemName: "square.and.pencil").frame(width: 44, height: 44) }.accessibilityLabel("Editar texto")
                }
                Button(role: .destructive) { store.deleteSelection() } label: { Image(systemName: "trash").frame(width: 44, height: 44) }.disabled(store.selectedIDs.isEmpty).accessibilityLabel("Excluir seleção")
            }.padding(.horizontal, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Tool.allCases, id: \.self) { tool in
                        Button { store.finishTextEditing(); store.tool = tool; store.selected = nil } label: {
                            Image(systemName: tool.icon)
                                .font(.system(size: 17, weight: .medium))
                                .frame(width: 36, height: 36)
                                .foregroundStyle(store.tool == tool ? accent : Color(uiColor: UIColor(hex: "526078")))
                                .background(store.tool == tool ? accent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }.accessibilityLabel(tool.title).help(tool.title).accessibilityAddTraits(store.tool == tool ? .isSelected : [])
                    }
                }
            }.accessibilityIdentifier("toolBar").frame(maxWidth: 360)
        }.padding(.horizontal, 4).padding(.vertical, 4)
            .frame(maxWidth: 380)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.07), lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
            .padding(.horizontal, 6).padding(.bottom, 4)
    }
    private func colorName(_ hex: String) -> String {
        switch hex { case "6253D9": "roxo"; case "277C77": "verde"; case "D45F49": "coral"; case "C68A20": "amarelo"; default: "grafite" }
    }
}
