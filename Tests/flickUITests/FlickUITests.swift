#if canImport(UIKit)
@testable import flickUI
import SwiftUI
import Testing

@Suite("Background colour schemes")
struct FlickContentColorSchemeTests {
    @Test func darkAndLightColours() {
        #expect(Color.black.flickContentColorScheme == .dark)
        #expect(Color.white.flickContentColorScheme == .light)
        #expect(Color.black.opacity(0.55).flickContentColorScheme == .dark)
    }

    @Test func transparentColoursKeepTheAppScheme() {
        #expect(Color.clear.flickContentColorScheme == nil)
        #expect(Color.black.opacity(0.2).flickContentColorScheme == nil)
    }

    @Test @MainActor func typeErasureKeepsTheScheme() {
        #expect(AnyFlickMenuBackgroundStyle(FlickColorBackgroundStyle(.black)).contentColorScheme == .dark)
        #expect(AnyFlickMenuBackgroundStyle(FlickColorBackgroundStyle(.black, contentColorScheme: .light)).contentColorScheme == .light)
        #expect(AnyFlickMenuBackgroundStyle(FlickMaterialBackgroundStyle()).contentColorScheme == nil)
    }

    @Test @MainActor func containedBackgrounds() {
        #expect(FlickPanelBackgroundStyle.panel.contentColorScheme == nil)
        #expect(FlickPanelBackgroundStyle.glassPanel.contentColorScheme == nil)
        #expect(FlickPanelBackgroundStyle.drawer(.color(.black)).contentColorScheme == .dark)
        #expect(FlickPanelBackgroundStyle(.color(.white), contentColorScheme: .dark).contentColorScheme == .dark)
        #expect(FlickHaloBackgroundStyle.halo.contentColorScheme == .dark)
    }
}

@Suite("Events and actions")
@MainActor
struct FlickMenuEventTests {
    @Test func handlersRunOutermostFirst() {
        var received: [String] = []
        let outer = FlickMenuEventHandler()
        outer.handle = { received.append("outer \($0)") }
        let inner = FlickMenuEventHandler()
        inner.handle = { received.append("inner \($0)") }
        var settings = FlickMenuSettings()
        settings.eventHandlers = [outer, inner]

        settings.send(.chose(2))
        #expect(received == ["outer chose(2)", "inner chose(2)"])
    }

    @Test func nestedMenusKeepStylesButNotHandlersOrInputs() {
        var settings = FlickMenuSettings()
        settings.eventHandlers = [FlickMenuEventHandler()]
        settings.keyboardShortcut = KeyboardShortcut("m")
        settings.opensOnPencilSqueeze = true
        settings.boomerang.set(.origin, for: .all)

        let nested = settings.forNestedMenus
        #expect(nested.eventHandlers.isEmpty)
        #expect(nested.keyboardShortcut == nil)
        #expect(!nested.opensOnPencilSqueeze)
        #expect(nested.boomerang == settings.boomerang)
    }

    @Test func actionsReachTheirMenu() {
        var commands: [String] = []
        let controller = FlickMenuController()
        controller.perform = { commands.append("\($0)") }
        let action = FlickMenuAction(controller: controller)

        action.open()
        action.open(from: .bottom)
        action.toggle()
        action.dismiss()
        #expect(commands == ["open(nil)", "open(Optional(FlickCore.FlickEdge.bottom))", "toggle(nil)", "dismiss"])
    }

    @Test func theDefaultActionDoesNothing() {
        // Outside a menu's content, there is no controller to reach.
        EnvironmentValues().flickMenu.open()
        #expect(EnvironmentValues().flickMenu.controller == nil)
    }
}

@Suite("Indicator morphs")
struct FlickIndicatorMorphTests {
    @Test func formsFollowTheMenuState() {
        let morph = FlickIndicatorMorph.drop
        #expect(morph.form(isOpen: false, velocity: 0) == .drop)
        #expect(morph.form(isOpen: true, velocity: 0) == .round)
    }

    @Test func speedStretchesUpToTheMaximum() {
        let morph = FlickIndicatorMorph.liquid
        #expect(morph.form(isOpen: true, velocity: 1000).stretch == 0.25)
        #expect(morph.form(isOpen: true, velocity: -4000).stretch == 0.5)
        #expect(FlickIndicatorMorph.still.form(isOpen: true, velocity: 4000) == .drop)
    }
}

@Suite("Symbol effects")
struct FlickSymbolEffectTests {
    @Test func repeatingKeepsTheKind() {
        #expect(FlickSymbolEffect.bounce.repeating.kind == .bounce)
        #expect(FlickSymbolEffect.bounce.repeating.repeats)
        #expect(!FlickSymbolEffect.bounce.repeats)
    }
}
#endif
