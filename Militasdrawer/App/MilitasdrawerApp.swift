import SwiftUI

@main struct MilitasdrawApp: App {
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
    @State private var drawingToDelete: SavedDrawing?
    @State private var drawingActionsID: UUID?
    @State private var drawerWidth: CGFloat = 360
    @GestureState(resetTransaction: Transaction(animation: .easeOut(duration: 0.2)))
    private var drawerTranslation: CGFloat = 0
    @State private var isEditingName = false
    @FocusState private var nameIsFocused: Bool
    @State private var proposedName = ""
    @State private var titleFrame: CGRect = .zero
    private let accent = Color(uiColor: UIColor(hex: "1E3A8A"))
    var body: some View {
        ZStack(alignment: .leading) {
            VStack(spacing: 0) {
                header.zIndex(1)
                ZStack(alignment: .topLeading) {
                    DrawingCanvas(store: store)
                        .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
                    if store.drawing.elements.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "Space for your\nnext idea.")).font(.system(size: sizeClass == .regular ? 28 : 22, weight: .semibold, design: .rounded))
                            Text(String(localized: "Choose a shape and drag to get started.")).font(.caption).foregroundStyle(.secondary)
                        }.padding(24).padding(.top, 24).allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .leading) {
                    if !showsDrawings {
                        // Reserve only the edge for navigation so a swipe cannot draw a stroke.
                        Color.clear
                            .frame(width: 24)
                            .contentShape(Rectangle())
                            .accessibilityHidden(true)
                            .gesture(drawerGesture)
                    }
                }
                .overlay(alignment: .bottom) {
                    if store.inlineTextID == nil { bottomBar }
                }
            }
            .allowsHitTesting(!showsDrawings)
            .accessibilityHidden(showsDrawings)

            GeometryReader { geometry in
                let width = min(360, max(0, geometry.size.width - 24))
                let visibleWidth = min(width, max(0, (showsDrawings ? width : 0) + drawerTranslation))
                let fullHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
                ZStack(alignment: .leading) {
                    Button { showsDrawings = false } label: {
                        Color.black.opacity(0.2 * (width > 0 ? visibleWidth / width : 0))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Close Recent Drawings"))
                    recentDrawingsSheet
                        .padding(.top, geometry.safeAreaInsets.top)
                        .padding(.bottom, geometry.safeAreaInsets.bottom)
                        .frame(width: width)
                        .frame(maxHeight: .infinity)
                        .background(Color.white)
                        .shadow(color: .black.opacity(0.15), radius: 16, x: 4)
                        .offset(x: visibleWidth - width)
                        .simultaneousGesture(drawerGesture)
                }
                .frame(width: geometry.size.width, height: fullHeight)
                .clipped()
                .offset(y: -geometry.safeAreaInsets.top)
                // Keep the edge gesture alive until release; the panel takes input once open.
                .allowsHitTesting(showsDrawings)
                .accessibilityHidden(!showsDrawings)
                .opacity(visibleWidth > 0 ? 1 : 0)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    min(360, max(0, proxy.size.width - 24))
                } action: { drawerWidth = $0 }
            }
            .zIndex(2)
        }
        .animation(.easeOut(duration: 0.2), value: showsDrawings)
        .simultaneousGesture(SpatialTapGesture(coordinateSpace: .global).onEnded { event in
            if isEditingName && !titleFrame.contains(event.location) {
                finishRenaming()
            }
        })
        .background(Color.white).tint(accent).preferredColorScheme(.light)
        .alert(String(localized: "Unable to Complete"), isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    private var drawerGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .updating($drawerTranslation) { value, translation, transaction in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                transaction.disablesAnimations = true
                translation = showsDrawings ? min(0, value.translation.width) : max(0, value.translation.width)
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let projectedWidth = (showsDrawings ? drawerWidth : 0) + value.predictedEndTranslation.width
                if projectedWidth > drawerWidth / 2 {
                    if !showsDrawings { openDrawings() }
                } else {
                    showsDrawings = false
                }
            }
    }
    private func openDrawings() {
        store.finishTextEditing()
        finishRenaming()
        showsDrawings = true
    }
    private func finishRenaming() {
        guard isEditingName else { return }
        isEditingName = false
        nameIsFocused = false
        if !proposedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.renameDrawing(proposedName)
        }
    }
    private var header: some View {
        HStack(spacing: 8) {
            Button {
                openDrawings()
            } label: {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 18))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .foregroundStyle(accent)
                .accessibilityLabel(String(localized: "Recent Drawings"))
                .accessibilityIdentifier("recentDrawingsButton")
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if isEditingName {
                        TextField(String(localized: "Drawing Name"), text: $proposedName)
                            .textFieldStyle(.plain)
                            .focused($nameIsFocused)
                            .submitLabel(.done)
                            .onSubmit { finishRenaming() }
                            .onChange(of: nameIsFocused) { _, focused in
                                if !focused { finishRenaming() }
                            }
                            .onAppear { nameIsFocused = true }
                            .accessibilityLabel(String(localized: "Drawing Name"))
                    } else {
                        Button {
                            store.finishTextEditing()
                            proposedName = store.drawingName
                            isEditingName = true
                        } label: {
                            Text(store.drawingName).lineLimit(1)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Rename Drawing"))
                        .accessibilityValue(store.drawingName)
                    }
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .frame(minHeight: 44)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .global)
                } action: { titleFrame = $0 }
            }
            Spacer(minLength: 4)
            Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward").font(.system(size: 16)).frame(width: 44, height: 44) }.disabled(store.history.past.isEmpty).accessibilityLabel(String(localized: "Undo")).keyboardShortcut("z", modifiers: .command)
            Button { store.redo() } label: { Image(systemName: "arrow.uturn.forward").font(.system(size: 16)).frame(width: 44, height: 44) }.disabled(store.history.future.isEmpty).accessibilityLabel(String(localized: "Redo")).keyboardShortcut("z", modifiers: [.command, .shift])
            if store.selected != nil {
                Button { store.duplicateSelection() } label: {
                    Image(systemName: "plus.square.on.square").font(.system(size: 16)).frame(width: 44, height: 44)
                }.accessibilityLabel(String(localized: "Duplicate Object")).accessibilityIdentifier("duplicateObjectButton").help(String(localized: "Duplicate Object"))
            }
        }.padding(.horizontal, 12).padding(.vertical, 2)
    }
    private var recentDrawingsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                Text(verbatim: "Militasdraw")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                Spacer()
                Button { showsDrawings = false } label: {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }.accessibilityLabel(String(localized: "Close Recent Drawings"))
            }
            Button {
                if store.newDrawing() { showsDrawings = false }
            } label: {
                Label(String(localized: "New Drawing"), systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .foregroundStyle(.white)
                    .background(accent, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(accent, lineWidth: 1))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.recentDrawings) { entry in
                        Button {
                            if store.openDrawing(entry.id) { showsDrawings = false }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(entry.name).font(.body.weight(.medium))
                                    Text(entry.updatedAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption).foregroundStyle(Color(uiColor: .darkGray))
                                }
                                Spacer(minLength: 8)
                                if entry.id == store.archive.activeID {
                                    Image(systemName: "checkmark").accessibilityLabel(String(localized: "Current Drawing"))
                                }
                            }
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(entry.id == store.archive.activeID ? accent.opacity(0.08) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(entry.id == store.archive.activeID ? .isSelected : [])
                            .highPriorityGesture(
                                LongPressGesture(minimumDuration: 0.25, maximumDistance: 10)
                                    .exclusively(before: TapGesture())
                                    .onEnded { gesture in
                                        switch gesture {
                                        case .first(true):
                                            drawingActionsID = entry.id
                                        case .second:
                                            if store.openDrawing(entry.id) { showsDrawings = false }
                                        default:
                                            break
                                        }
                                    }
                            )
                            .accessibilityAction(named: String(localized: "Delete Drawing")) {
                                drawingToDelete = entry
                            }
                            .popover(isPresented: Binding(
                                get: { drawingActionsID == entry.id },
                                set: { if !$0 { drawingActionsID = nil } }
                            )) {
                                Button(role: .destructive) {
                                    drawingActionsID = nil
                                    drawingToDelete = entry
                                } label: {
                                    Label(String(localized: "Delete Drawing"), systemImage: "trash")
                                        .padding(16)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.red)
                                .presentationCompactAdaptation(.popover)
                            }
                    }
                }
            }
        }.padding(16)
            .accessibilityAddTraits(.isModal)
            .alert(String(localized: "Delete Drawing?"), isPresented: Binding(
                get: { drawingToDelete != nil },
                set: { if !$0 { drawingToDelete = nil } }
            ), presenting: drawingToDelete) { entry in
                Button(String(localized: "Delete"), role: .destructive) {
                    store.deleteDrawing(entry.id)
                    drawingToDelete = nil
                }
                Button(String(localized: "Cancel"), role: .cancel) { drawingToDelete = nil }
            } message: { entry in
                Text(String(localized: "The drawing “\(entry.name)” will be permanently deleted. This cannot be undone."))
            }
    }
    private var bottomBar: some View {
        HStack(spacing: 0) {
            ColorPaletteButton(store: store)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Tool.allCases.filter { $0 != .ellipse && $0 != .diamond }, id: \.self) { tool in
                        if tool == .rectangle {
                            ShapePickerButton(store: store)
                        } else {
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
                }
            }.accessibilityIdentifier("toolBar").frame(maxWidth: 360)
            if let selected = store.drawing.elements.first(where: { $0.id == store.selected }), selected.kind == .text || selected.isShape {
                Button { store.openText(at: selected.start, id: selected.id) } label: {
                    Image(systemName: "square.and.pencil").frame(width: 44, height: 44)
                }.accessibilityLabel(String(localized: "Edit Text"))
            }
            Button(role: .destructive) { store.deleteSelection() } label: {
                Image(systemName: "trash").frame(width: 44, height: 44)
            }.disabled(store.selectedIDs.isEmpty).accessibilityLabel(String(localized: "Delete Selection"))
        }.padding(.horizontal, 4).padding(.vertical, 4)
            .frame(maxWidth: 380)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.07), lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 8, y: 2)
            .padding(.horizontal, 6).padding(.bottom, 4)
    }
}

// Keep presentation state local so opening the palette does not invalidate the canvas.
private struct ColorPaletteButton: View {
    @ObservedObject var store: EditorStore
    @State private var isPalettePresented = false
    private let palette = ["27364B", "6253D9", "277C77", "D45F49", "C68A20"]
    private let accent = Color(uiColor: UIColor(hex: "1E3A8A"))

    private func presentPalette(_ presented: Bool) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { isPalettePresented = presented }
    }

    var body: some View {
        Button { presentPalette(!isPalettePresented) } label: {
            Circle().fill(.black).frame(width: 16, height: 16)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(String(localized: "Choose Color"))
        .accessibilityValue(colorName(store.color))
        .accessibilityIdentifier("colorPaletteButton")
        .popover(isPresented: $isPalettePresented, arrowEdge: .bottom) {
            HStack(spacing: 0) {
                ForEach(palette, id: \.self) { hex in
                    Button {
                        store.setColor(hex)
                        presentPalette(false)
                    } label: {
                        Circle().fill(Color(uiColor: UIColor(hex: hex))).frame(width: 16, height: 16)
                            .padding(4)
                            .overlay(Circle().stroke(store.color == hex ? accent : .clear, lineWidth: 1.5))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(String(localized: "Color \(colorName(hex))"))
                    .accessibilityAddTraits(store.color == hex ? .isSelected : [])
                }
            }
            .padding(8)
            .presentationCompactAdaptation(.popover)
        }
    }
    private func colorName(_ hex: String) -> String {
        switch hex { case "6253D9": String(localized: "purple"); case "277C77": String(localized: "green"); case "D45F49": String(localized: "coral"); case "C68A20": String(localized: "yellow"); default: String(localized: "graphite") }
    }
}

private struct ShapePickerButton: View {
    @ObservedObject var store: EditorStore
    @State private var selectedShape: Tool = .rectangle
    @State private var isPresented = false
    private let shapes: [Tool] = [.rectangle, .ellipse, .diamond]
    private let accent = Color(uiColor: UIColor(hex: "1E3A8A"))
    private var isActive: Bool { shapes.contains(store.tool) }

    var body: some View {
        Button {
            store.finishTextEditing()
            store.tool = selectedShape
            store.selected = nil
            isPresented.toggle()
        } label: {
            Image(systemName: selectedShape.icon)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 36, height: 36)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 7, weight: .bold))
                        .offset(x: 2, y: 1)
                }
                .foregroundStyle(isActive ? accent : Color(uiColor: UIColor(hex: "526078")))
                .background(isActive ? accent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(selectedShape.title)
        .accessibilityHint(String(localized: "Choose a shape"))
        .accessibilityIdentifier("shapePickerButton")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            HStack(spacing: 4) {
                ForEach(shapes, id: \.self) { shape in
                    Button {
                        selectedShape = shape
                        store.finishTextEditing()
                        store.tool = shape
                        store.selected = nil
                        isPresented = false
                    } label: {
                        Image(systemName: shape.icon)
                            .font(.system(size: 20, weight: .medium))
                            .frame(width: 44, height: 44)
                            .foregroundStyle(selectedShape == shape ? accent : Color(uiColor: UIColor(hex: "526078")))
                            .background(selectedShape == shape ? accent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(shape.title)
                    .accessibilityIdentifier("shapeOption_\(shape.rawValue)")
                    .accessibilityAddTraits(selectedShape == shape ? .isSelected : [])
                }
            }
            .padding(8)
            .presentationCompactAdaptation(.popover)
        }
        .onChange(of: store.tool) { _, tool in
            if shapes.contains(tool) { selectedShape = tool }
        }
    }
}
