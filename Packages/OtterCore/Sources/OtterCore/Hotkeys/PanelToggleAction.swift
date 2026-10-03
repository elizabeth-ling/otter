/// What the toggle-panel hotkey does, given the panel's current state (T02 scope 7).
/// The panel controller (T03) asks this on every key press.
public enum PanelToggleAction: Equatable, Sendable {
    case showAndMakeKey
    case hide
    /// Visible but not key: the user clicked elsewhere with "Keep panel open" on.
    case makeKey

    public init(panelIsVisible: Bool, panelIsKey: Bool) {
        switch (panelIsVisible, panelIsKey) {
        case (false, _):
            self = .showAndMakeKey
        case (true, true):
            self = .hide
        case (true, false):
            self = .makeKey
        }
    }
}
