/// Values the app can preset at launch to put views into a specific state for UI checks.
/// Only set by the debug launch hooks in KBoxApp; always nil in normal use.
@MainActor
public enum DebugOverrides {
    /// Pretend the pointer hovers the comparison charts at this year.
    public static var hoverYear: Double?
    /// Show the per-card actions that normally appear on hover.
    public static var showCardActions = false
}
