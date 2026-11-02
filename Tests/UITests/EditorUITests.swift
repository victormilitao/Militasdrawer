import XCTest

final class EditorUITests: XCTestCase {
    @MainActor func testStandaloneTextEditsInlineAndDiscardsEmptyDrafts() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset"]
        app.launch()
        let canvas = app.otherElements["drawingCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        app.buttons["Texto"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.2)).tap()
        let editor = app.textViews["canvasTextEditor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        if app.buttons["Continue"].firstMatch.exists { app.buttons["Continue"].firstMatch.tap() }
        XCTAssertFalse(app.buttons["Salvar"].exists)
        app.buttons["Concluir"].tap()
        XCTAssertEqual(canvas.value as? String, "0 elementos")
        app.buttons["Texto"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.2)).tap()
        editor.typeText("Texto livre\nSegunda linha")
        XCTAssertEqual(editor.value as? String, "Texto livre\nSegunda linha")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Texto livre direto no quadro"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Concluir"].tap()
        XCTAssertEqual(canvas.value as? String, "1 elementos")
        app.buttons["Desfazer"].tap()
        XCTAssertEqual(canvas.value as? String, "0 elementos")
        app.buttons["Refazer"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.21)).doubleTap()
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        XCTAssertEqual(editor.value as? String, "Texto livre\nSegunda linha")
        editor.tap()
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(editor.value as? String, "")
        app.buttons["Concluir"].tap()
        XCTAssertEqual(canvas.value as? String, "0 elementos")
        app.buttons["Desfazer"].tap()
        XCTAssertEqual(canvas.value as? String, "1 elementos")
    }
    @MainActor func testMarqueeSelectionMovesAndDeletesMultipleObjects() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset"]
        app.launch()
        let canvas = app.otherElements["drawingCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        func drag(_ x: Double, _ y: Double, _ endX: Double, _ endY: Double) {
            canvas.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: endY)))
        }
        app.buttons["Retângulo"].tap(); drag(0.15, 0.2, 0.3, 0.35)
        app.buttons["Elipse"].tap(); drag(0.5, 0.2, 0.65, 0.35)
        app.buttons["Losango"].tap(); drag(0.7, 0.7, 0.85, 0.85)
        drag(0.1, 0.15, 0.68, 0.4)
        XCTAssertTrue(app.buttons["Excluir seleção"].isEnabled)
        XCTAssertFalse(app.buttons["Editar texto"].exists)
        drag(0.22, 0.27, 0.3, 0.52)
        // Old area is now empty; the selection gesture must not create an undo entry.
        drag(0.1, 0.15, 0.68, 0.4)
        XCTAssertFalse(app.buttons["Excluir seleção"].isEnabled)
        // Reverse-direction marquee encloses both moved shapes, excluding the diamond.
        drag(0.76, 0.64, 0.2, 0.43)
        XCTAssertTrue(app.buttons["Excluir seleção"].isEnabled)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Seleção múltipla"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Excluir seleção"].tap()
        XCTAssertEqual(canvas.value as? String, "1 elementos")
        app.buttons["Desfazer"].tap()
        XCTAssertEqual(canvas.value as? String, "3 elementos")
        app.buttons["Desfazer"].tap()
        drag(0.1, 0.15, 0.68, 0.4)
        app.buttons["Excluir seleção"].tap()
        XCTAssertEqual(canvas.value as? String, "1 elementos")
    }
    @MainActor func testDoubleTapEditsCenteredShapeText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset"]
        app.launch()
        let canvas = app.otherElements["drawingCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        for tool in ["Retângulo", "Elipse", "Losango"] {
            app.buttons[tool].tap()
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.15)).press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.65)))
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.4)).doubleTap()
            let editor = app.textViews["shapeTextEditor"]
            XCTAssertTrue(editor.waitForExistence(timeout: 3))
            if app.buttons["Continue"].firstMatch.exists { app.buttons["Continue"].firstMatch.tap() }
            XCTAssertFalse(app.buttons["Salvar"].exists)
            editor.typeText("Ideia\ncentral")
            XCTAssertEqual(editor.value as? String, "Ideia\ncentral")
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "Digitação na forma - \(tool)"; shot.lifetime = .keepAlways; add(shot)
            app.buttons["Concluir"].tap()
            XCTAssertTrue(canvas.waitForExistence(timeout: 3))
            XCTAssertEqual(canvas.value as? String, "1 elementos")
            app.buttons["Desfazer"].tap()
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.4)).doubleTap()
            XCTAssertEqual(editor.value as? String, "")
            app.buttons["Concluir"].tap()
            app.buttons["Refazer"].tap()
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.4)).doubleTap()
            XCTAssertEqual(editor.value as? String, "Ideia\ncentral")
            editor.typeKey("a", modifierFlags: .command)
            editor.typeText(XCUIKeyboardKey.delete.rawValue)
            app.buttons["Concluir"].tap()
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.4)).doubleTap()
            XCTAssertEqual(editor.value as? String, "")
            // Tapping outside finishes inline editing and dismisses the keyboard.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.2)).tap()
            let dismissed = NSPredicate { _, _ in (!editor.exists || !editor.isHittable) && !app.keyboards.firstMatch.exists }
            expectation(for: dismissed, evaluatedWith: app)
            waitForExpectations(timeout: 3)
            XCTAssertEqual(canvas.value as? String, "1 elementos")
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.4)).tap()
            app.buttons["Excluir seleção"].tap()
            XCTAssertEqual(canvas.value as? String, "0 elementos")
        }
    }
    @MainActor func testShapesSwitchToSelectionAndResizeWithoutCreatingObjects() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset"]
        app.launch()
        let canvas = app.otherElements["drawingCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        for tool in ["Selecionar", "Navegar", "Retângulo", "Elipse", "Losango", "Seta", "Desenhar", "Texto"] {
            XCTAssertTrue(app.buttons[tool].isHittable, "Ferramenta deve caber na tela: \(tool)")
        }
        for tool in ["Retângulo", "Elipse", "Losango"] {
            app.buttons[tool].tap()
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2)).press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
            XCTAssertTrue(app.buttons["Selecionar"].isSelected)
            XCTAssertEqual(canvas.value as? String, "1 elementos")
            // The lower-right handle extends the existing shape.
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.75)))
            XCTAssertEqual(canvas.value as? String, "1 elementos")
            // This point is inside the enlarged shape but outside its old bounds.
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.58, dy: 0.58)).tap()
            XCTAssertTrue(app.buttons["Excluir seleção"].isEnabled)
            // Undo must restore the original bounds.
            app.buttons["Desfazer"].tap()
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.58, dy: 0.58)).tap()
            XCTAssertFalse(app.buttons["Excluir seleção"].isEnabled)
            // Dragging empty space must not create another shape.
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.8)).press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)))
            XCTAssertEqual(canvas.value as? String, "1 elementos")
            app.buttons["Desfazer"].tap()
            XCTAssertEqual(canvas.value as? String, "0 elementos")
        }
    }
    @MainActor func testDrawingUndoTextAndPersistence() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset"]
        app.launch()
        let canvas = app.otherElements["drawingCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        XCTAssertEqual(canvas.value as? String, "0 elementos")
        app.buttons["Retângulo"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.25)).press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.45)))
        XCTAssertEqual(canvas.value as? String, "1 elementos")
        app.buttons["Desfazer"].tap()
        XCTAssertEqual(canvas.value as? String, "0 elementos")
        app.buttons["Refazer"].tap()
        XCTAssertEqual(canvas.value as? String, "1 elementos")
        app.buttons["Elipse"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.6)).press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.8)))
        XCTAssertEqual(canvas.value as? String, "2 elementos")
        app.buttons["Seta"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35)).press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.7)))
        XCTAssertEqual(canvas.value as? String, "3 elementos")
        app.buttons["Texto"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.1)).tap()
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap(); editor.typeText("Minha primeira ideia")
        app.buttons["Concluir"].tap()
        XCTAssertEqual(canvas.value as? String, "4 elementos")
        XCTAssertTrue(app.staticTexts["Salvo neste dispositivo"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "Editor com diagrama"; shot.lifetime = .keepAlways; add(shot)
        app.terminate(); app.launchArguments = []; app.launch()
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        XCTAssertEqual(canvas.value as? String, "4 elementos")
    }
    @MainActor func testInkSelectionZoomAndLandscape() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset"]
        app.launch()
        let canvas = app.otherElements["drawingCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        app.buttons["Losango"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2)).press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        app.buttons["Desenhar"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.65)).press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.8)))
        XCTAssertEqual(canvas.value as? String, "2 elementos")
        app.buttons["Selecionar"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35)).press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.4)))
        app.buttons["Excluir seleção"].tap()
        XCTAssertEqual(canvas.value as? String, "1 elementos")
        app.buttons["Desfazer"].tap()
        XCTAssertEqual(canvas.value as? String, "2 elementos")
        canvas.pinch(withScale: 1.5, velocity: 1)
        XCTAssertEqual(canvas.value as? String, "2 elementos")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let landscape = NSPredicate { _, _ in app.frame.width > app.frame.height }
        expectation(for: landscape, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.buttons["Desfazer"].isHittable)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Editor em paisagem"; shot.lifetime = .keepAlways; add(shot)
    }

}
