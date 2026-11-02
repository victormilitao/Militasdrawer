import SwiftUI

@main struct MilitasdrawerApp: App {
    @StateObject private var store = EditorStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            EditorView(store: store)
                .onChange(of: phase) { _, value in if value != .active { store.saveNow() } }
        }
    }
}
struct EditorView: View {
    @ObservedObject var store: EditorStore
    @Environment(\.horizontalSizeClass) var sizeClass
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
        .background(Color.white).tint(accent).preferredColorScheme(.light)
        .alert("Não foi possível concluir", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up.fill").font(.system(size: 18)).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Militasdrawer").font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(store.saveMessage).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward").font(.system(size: 16)).frame(width: 44, height: 44) }.disabled(store.history.past.isEmpty).accessibilityLabel("Desfazer").keyboardShortcut("z", modifiers: .command)
            Button { store.redo() } label: { Image(systemName: "arrow.uturn.forward").font(.system(size: 16)).frame(width: 44, height: 44) }.disabled(store.history.future.isEmpty).accessibilityLabel("Refazer").keyboardShortcut("z", modifiers: [.command, .shift])
        }.padding(.horizontal, 12).padding(.vertical, 2)
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
