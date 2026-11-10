import Testing
@testable import OtterCore

@Test func hiddenPanelShowsAndBecomesKey() {
    #expect(PanelToggleAction(panelIsVisible: false) == .showAndMakeKey)
}

@Test func visiblePanelHides() {
    #expect(PanelToggleAction(panelIsVisible: true) == .hide)
}
