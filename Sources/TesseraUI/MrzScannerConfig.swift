import SwiftUI

// The default-UI configuration surface, the iOS analogue of the Android module's `MrzScannerConfig`.
//
// Unlike Android — where the public API freezes as a *binary* signature under ADR-007, forcing a DSL
// builder so new options can be added without breaking the ABI — Swift ships as **source** (ADR-026) and
// recompiles at the consumer, so a plain `struct` with defaulted properties is safe to grow additively.
// A new property with a default is source-compatible. So the iOS config is a struct-with-defaults, not a
// builder. It still freezes at the 0.5.0 tag: every property here is a promise the SDK keeps.
//
// Reader, not oracle (Principle 1): nothing here lets the UI make a trust decision about a document. The
// knobs govern which methods appear, the review step, appearance, timing, and the permission hand-off.

/// A reading method the default scanner UI can offer. A consumer restricts the UI to a subset via
/// ``MrzScannerConfig/enabledMethods``; the method switcher shows only the enabled ones.
public enum ScanMethod: Sendable, Hashable {
    /// Live camera capture (the default primary method).
    case camera

    /// Pick an existing photo and decode its MRZ. **Opt-in — not enabled by default** (saved-image reading
    /// is opt-in because a saved image carries more risk than a live capture, ADR-023 / KB TES-A-62).
    /// Adding it to ``MrzScannerConfig/enabledMethods`` is the consumer's acknowledgement of that risk;
    /// there is no separate acknowledgement screen.
    case savedImage

    /// Type the MRZ by hand — the accessible fallback.
    case manualEntry
}

/// What the screen does the moment the reader decodes an MRZ.
public enum ReviewMode: Sendable, Hashable {
    /// Show the review screen (parsed fields + observations); the user accepts or rescans. The default.
    case review

    /// Return the decoded result immediately, with no review step.
    case instantReturn
}

/// The dark/light disposition of the module's own theme (it never reads the host app's theme).
public enum DarkMode: Sendable, Hashable {
    /// Follow the system setting. The default.
    case auto

    /// Always dark.
    case on

    /// Always light.
    case off
}

/// The theming seam — the *bounded* surface a consumer can brand without reskinning. The module keeps its
/// own base theme (ADR-026); these options tint it and set the light/dark disposition, they do not hand
/// the consumer the whole palette.
public struct MrzScannerTheme: Sendable {
    /// An optional accent. When set it tints the theme's primary/accent color; `nil` (the default) keeps
    /// the module's baseline accent.
    public var brandColor: Color?

    /// Auto (default) / on / off.
    public var darkMode: DarkMode

    public init(brandColor: Color? = nil, darkMode: DarkMode = .auto) {
        self.brandColor = brandColor
        self.darkMode = darkMode
    }
}

/// Consumer configuration for ``MrzScannerView`` — the one place a host app tunes the default UI without
/// forking it. Every option freezes at the 0.5.0 tag under ADR-007.
///
/// ```swift
/// let config = MrzScannerConfig(
///     enabledMethods: [.camera, .manualEntry],
///     theme: MrzScannerTheme(brandColor: .teal)
/// )
/// ```
public struct MrzScannerConfig: Sendable {
    /// Which reading methods the UI offers. **Default: camera + manual entry.** Saved-image is opt-in
    /// (off by default) per scope (KB TES-A-62) — adding ``ScanMethod/savedImage`` is the consumer's
    /// acknowledgement of the higher saved-image risk (ADR-023). The switcher shows only enabled methods.
    public var enabledMethods: Set<ScanMethod>

    /// Review (default) vs instant-return once an MRZ decodes.
    public var reviewMode: ReviewMode

    /// Show the torch toggle over the live preview (default `true`).
    public var showTorchButton: Bool

    /// Start with the torch on (default `false`).
    public var torchOnByDefault: Bool

    /// How long with no decode before the "still looking / type it instead" hint appears (default 10s).
    /// `nil` never shows the hint — the "never struggle" option, mirroring ``scanTimeout``'s `nil` convention
    /// (Swift's `Duration` has no infinity sentinel, so absence is expressed as `nil`, not a magic value).
    public var struggleTimeout: Duration?

    /// Total time before the scanner gives up and reports ``TesseraUIResult/cancelled(_:)`` with
    /// ``DismissReason/timedOut``. `nil` (the default) never times out.
    public var scanTimeout: Duration?

    /// Fire a short confirming haptic the moment a live-camera read is accepted (default `true`) — the
    /// hands-free "it scanned" cue. Honours the device's system haptic setting. Camera path only
    /// (manual/saved-image get their own interaction feedback). Mirrors the Android `hapticFeedback`.
    public var hapticFeedback: Bool

    /// The bounded theming seam; see ``MrzScannerTheme``.
    public var theme: MrzScannerTheme

    /// Invoked when the UI needs the camera permission it does not hold — the host requests it (the SDK
    /// never requests a permission itself). `nil` (default) means the host owns it entirely.
    public var onRequestPermission: (@Sendable () -> Void)?

    /// The host's string-override seam (TES-139) — the iOS counterpart to Android's resource-merge override.
    /// `nil` (the default) renders the module's own bundled strings, unchanged.
    ///
    /// To override one or more of the module's strings, set this to a bundle that defines an entry — under
    /// the **same key**, in a **`Localizable` table** (`Localizable.strings` or `Localizable.xcstrings`,
    /// standard Xcode string-catalog mechanics) — for each key to change; typically `Bundle.main`. Every key
    /// not defined there falls back to the module's own catalog (`Resources/Localizable.xcstrings`), so a
    /// host only needs to override the handful of keys it actually wants to change. See ``TesseraStrings``
    /// for the full lookup contract.
    public var stringsBundle: Bundle?

    public init(
        enabledMethods: Set<ScanMethod> = [.camera, .manualEntry],
        reviewMode: ReviewMode = .review,
        showTorchButton: Bool = true,
        torchOnByDefault: Bool = false,
        struggleTimeout: Duration? = .seconds(10),
        scanTimeout: Duration? = nil,
        hapticFeedback: Bool = true,
        theme: MrzScannerTheme = MrzScannerTheme(),
        onRequestPermission: (@Sendable () -> Void)? = nil,
        stringsBundle: Bundle? = nil
    ) {
        self.enabledMethods = enabledMethods
        self.reviewMode = reviewMode
        self.showTorchButton = showTorchButton
        self.torchOnByDefault = torchOnByDefault
        self.struggleTimeout = struggleTimeout
        self.scanTimeout = scanTimeout
        self.hapticFeedback = hapticFeedback
        self.theme = theme
        self.onRequestPermission = onRequestPermission
        self.stringsBundle = stringsBundle
    }
}
