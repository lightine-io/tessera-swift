import SwiftUI

// The module's own theming, resolved from the consumer's `MrzScannerTheme` seam — the iOS mirror of the
// Android `TesseraScannerTheme` + `AdaptiveLayout`. The default UI keeps a stable appearance regardless of
// where it is embedded (ADR-026): the brand color tints the accent and the dark-mode disposition sets the
// color scheme; nothing is read from the host app's environment.

extension View {
    /// Applies the consumer's ``MrzScannerTheme``: the brand color tints the accent (via `.tint`) and the
    /// dark-mode disposition sets the color scheme (via `.preferredColorScheme`; ``DarkMode/auto`` follows the
    /// system). A tint, not a reskin — the rest of the palette stays the module's own. Mirrors the Android
    /// `TesseraScannerTheme`.
    func scannerTheme(_ theme: MrzScannerTheme) -> some View {
        modifier(ScannerThemeModifier(theme: theme))
    }

    /// Caps a content column's width at ``ContentMaxWidth`` and centres it — the adaptive-layout foundation
    /// for the single-pane scanner content screens (mirrors the Android `Modifier.contentMaxWidth`). On a
    /// phone the screen is always narrower than the cap, so it is a no-op; on a tablet / unfolded foldable it
    /// keeps the content a readable width instead of stretching edge-to-edge. The live viewfinder is
    /// deliberately NOT capped (only its overlaid controls are).
    func contentMaxWidth() -> some View {
        frame(maxWidth: ContentMaxWidth)
    }
}

/// The content-width cap for the single-pane scanner screens — about a comfortable phone's width. Mirrors the
/// Android `ContentMaxWidth` (480.dp).
let ContentMaxWidth: CGFloat = 480

private struct ScannerThemeModifier: ViewModifier {
    let theme: MrzScannerTheme

    func body(content: Content) -> some View {
        content
            .tint(theme.brandColor)
            .preferredColorScheme(colorScheme)
    }

    private var colorScheme: ColorScheme? {
        switch theme.darkMode {
        case .auto: return nil
        case .on: return .dark
        case .off: return .light
        }
    }
}
