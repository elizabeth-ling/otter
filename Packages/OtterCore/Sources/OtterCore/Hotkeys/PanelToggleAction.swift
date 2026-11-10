/// What the toggle-panel hotkey does, given the panel's current state (T02 scope 7).
/// The panel controller (T03) asks this on every key press.
public enum PanelToggleAction: Equatable, Sendable {
    case showAndMakeKey
    /// Visible, whether or not it's key: with "Keep panel open" on, a click elsewhere leaves the
    /// panel open, and the hotkey is what closes it.
    case hide

    public init(panelIsVisible: Bool) {
        self = panelIsVisible ? .hide : .showAndMakeKey
    }
}
