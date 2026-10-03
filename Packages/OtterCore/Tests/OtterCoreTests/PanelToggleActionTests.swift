import Testing
@testable import OtterCore

@Test func hiddenPanelShowsAndBecomesKey() {
    #expect(PanelToggleAction(panelIsVisible: false, panelIsKey: false) == .showAndMakeKey)
    // A hidden window can't really be key; still treat it as hidden.
    #expect(PanelToggleAction(panelIsVisible: false, panelIsKey: true) == .showAndMakeKey)
}

@Test func visibleKeyPanelHides() {
    #expect(PanelToggleAction(panelIsVisible: true, panelIsKey: true) == .hide)
}

@Test func visibleButNotKeyPanelBecomesKey() {
    #expect(PanelToggleAction(panelIsVisible: true, panelIsKey: false) == .makeKey)
}
