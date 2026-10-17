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

/// A way to read an MRZ that the scanner screen can offer.
///
/// Turn methods on with ``MrzScannerConfig/enabledMethods``.
///
/// - Since: 0.5.0
public enum ScanMethod: Sendable, Hashable {
    /// Reads from the live camera.
    ///
    /// On by default.
    case camera

    /// Reads from a photo the user picks.
    ///
    /// Off by default. Adding it to ``MrzScannerConfig/enabledMethods`` accepts the higher risk of a saved image.
    /// A photo read inside the screen carries no capture metadata.
    case savedImage

    /// Reads an MRZ the user types.
    ///
    /// On by default. Typed input that fails to parse stays on the manual screen, with the text kept.
    case manualEntry
}

/// Sets whether the scanner screen shows a review step after a read.
///
/// The same in both modes: a saved photo that fails to parse shows the read-failed screen, and a photo
/// with no MRZ shows "No MRZ found in this photo". Typed input that fails to parse stays on the manual
/// screen with a note. The live camera skips a frame that fails to parse and keeps looking.
///
/// - Since: 0.5.0
public enum ReviewMode: Sendable, Hashable {
    /// Shows the parsed fields and observations, and the user accepts or rescans.
    ///
    /// The default.
    case review

    /// Returns the decoded result at once, with no review step.
    case instantReturn
}

/// Sets whether the scanner screen uses light or dark appearance.
///
/// - Since: 0.5.0
public enum DarkMode: Sendable, Hashable {
    /// Follows the color scheme the screen inherits, normally the system setting.
    ///
    /// The default.
    case auto

    /// Always dark.
    case on

    /// Always light.
    case off
}

/// The brand color and light or dark mode of the scanner screen.
///
/// Tints the screen's own theme. It does not reskin it.
///
/// - Since: 0.5.0
public struct MrzScannerTheme: Sendable {
    /// The accent color applied with `.tint`.
    ///
    /// Default: `nil`, which sets no tint.
    public var brandColor: Color?

    /// Whether the screen is light, dark, or follows the system.
    ///
    /// Default: `.auto`.
    public var darkMode: DarkMode

    /// Creates a theme.
    ///
    /// - Parameters:
    ///   - brandColor: The accent color. Default: `nil`.
    ///   - darkMode: The light or dark setting. Default: `.auto`.
    public init(brandColor: Color? = nil, darkMode: DarkMode = .auto) {
        self.brandColor = brandColor
        self.darkMode = darkMode
    }
}

/// The settings for ``MrzScannerView``.
///
/// Every property has a default, so `MrzScannerConfig()` is valid.
/// Not configurable: lenient line matching, OCR limited to the MRZ band, the live preview,
/// 2 agreeing frames, and no telemetry events.
/// The configuration is read when the scanner opens; changes while it is open apply the next time it opens.
///
/// - Since: 0.5.0
public struct MrzScannerConfig: Sendable {
    /// The reading methods the screen offers.
    ///
    /// Default: `[.camera, .manualEntry]`. Add `.savedImage` to opt in to photo reading.
    /// The method switcher shows only when two or more methods are enabled.
    public var enabledMethods: Set<ScanMethod>

    /// Whether a read goes to a review step.
    ///
    /// Default: `.review`.
    public var reviewMode: ReviewMode

    /// Shows the torch button over the live preview.
    ///
    /// Default: `true`. The button appears only on a device with a torch.
    public var showTorchButton: Bool

    /// Turns the torch on once the camera opens.
    ///
    /// Default: `false`.
    public var torchOnByDefault: Bool

    /// Sets the scan time with no read before the "still looking" hint.
    ///
    /// Default: `.seconds(10)`. Counted from when the preview is live. The hint shows only after OCR has read some text.
    /// `nil` never shows the hint.
    public var struggleTimeout: Duration?

    /// Sets the deadline for the whole session, across every screen.
    ///
    /// Default: `nil`. At expiry the screen reports `.cancelled(.timedOut)`. A finite value shows a countdown.
    /// The clock pauses while the app is not active and continues where it stopped.
    /// A camera held by another app does not pause it. `nil` never times out.
    public var scanTimeout: Duration?

    /// Plays a short haptic when a live camera read is accepted.
    ///
    /// Default: `true`. Camera path only. Follows the system haptic setting.
    public var hapticFeedback: Bool

    /// The accent color and light or dark mode.
    ///
    /// Default: `MrzScannerTheme()`.
    public var theme: MrzScannerTheme

    /// Called when the user taps "Grant access" on the permission screen.
    ///
    /// Default: `nil`. The screen reads the camera permission and never requests it. With `nil` the screen has no
    /// grant button and your app owns the request. The closure must be `@Sendable`.
    /// iOS shows its permission dialog once; after a denial the screen offers Settings.
    public var onRequestPermission: (@Sendable () -> Void)?

    /// A bundle with your own `Localizable` strings.
    ///
    /// Default: `nil`, which uses the screen's strings. Each `tessera_scanner_*` key is looked up in this bundle first, then in the screen's catalog.
    /// The keys `tessera_scanner_grant_permission` and `tessera_scanner_permission_rationale` are in
    /// the catalog but never read; overriding them changes nothing.
    ///
    /// - Since: 0.5.1
    public var stringsBundle: Bundle?

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - enabledMethods: The reading methods to offer. Default: `[.camera, .manualEntry]`.
    ///   - reviewMode: Review step or instant return. Default: `.review`.
    ///   - showTorchButton: Show the torch button. Default: `true`.
    ///   - torchOnByDefault: Start with the torch on. Default: `false`.
    ///   - struggleTimeout: Time before the "still looking" hint. Default: `.seconds(10)`; `nil` never.
    ///   - scanTimeout: Deadline for the whole session. Default: `nil`, which never times out.
    ///   - hapticFeedback: Haptic on an accepted live read. Default: `true`.
    ///   - theme: Accent color and light or dark mode. Default: `MrzScannerTheme()`.
    ///   - onRequestPermission: Called to request the camera permission. Default: `nil`.
    ///   - stringsBundle: Bundle with string overrides. Default: `nil`. Since 0.5.1.
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
