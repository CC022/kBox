import SwiftUI

/// The handful of things that differ between macOS and iPadOS.
enum Platform {
    /// A pointer can hover: reveal-on-hover controls need an always-visible fallback on touch.
    static let supportsHover: Bool = {
        #if os(macOS)
        true
        #else
        false
        #endif
    }()
}

extension Color {
    /// Card background that sits above the window / grouped background.
    static var cardBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    /// Background behind the result / comparison canvas.
    static var canvasBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    /// Hairline border colour.
    static var hairline: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor)
        #else
        Color(uiColor: .separator)
        #endif
    }
}
