import SwiftUI
// `@preconcurrency`: `DocumentCategory` is a Kotlin enum bridged as a class the compiler cannot see is Sendable.
// Its entries are immutable singletons, safe to share across threads, so the config stays `Sendable` (TES-103).
@preconcurrency import Tessera

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
    /// Default: `.seconds(10)`. Counted from when the preview is live. The hint shows when the time is up, whatever the camera sees.
    /// `nil` never shows the hint.
    /// The same setting as ``struggleTimeoutInterval``, as a `Duration`.
    @available(iOS 16, *)
    public var struggleTimeout: Duration? {
        get { struggleTimeoutInterval.map(durationFromSeconds) }
        set { struggleTimeoutInterval = newValue.map(secondsFromDuration) }
    }

    /// Sets the deadline for the whole session, across every screen.
    ///
    /// Default: `nil`. At expiry the screen reports `.cancelled(.timedOut)`. A finite value shows a countdown.
    /// The clock pauses while the app is not active and continues where it stopped.
    /// A camera held by another app does not pause it. `nil` never times out.
    /// The same setting as ``scanTimeoutInterval``, as a `Duration`.
    @available(iOS 16, *)
    public var scanTimeout: Duration? {
        get { scanTimeoutInterval.map(durationFromSeconds) }
        set { scanTimeoutInterval = newValue.map(secondsFromDuration) }
    }

    /// Sets the scan time with no read before the "still looking" hint, in seconds.
    ///
    /// Default: `10`. Counted from when the preview is live. The hint shows when the time is up, whatever the camera sees.
    /// `nil` never shows the hint.
    /// The same setting as ``struggleTimeout``, for iOS 15, where `Duration` is not available.
    ///
    /// - Since: 1.0.0
    public var struggleTimeoutInterval: TimeInterval?

    /// Sets the deadline for the whole session, across every screen, in seconds.
    ///
    /// Default: `nil`. At expiry the screen reports `.cancelled(.timedOut)`. A finite value shows a countdown.
    /// The clock pauses while the app is not active and continues where it stopped.
    /// A camera held by another app does not pause it. `nil` (or an infinite value) never times out.
    /// The same setting as ``scanTimeout``, for iOS 15, where `Duration` is not available.
    ///
    /// - Since: 1.0.0
    public var scanTimeoutInterval: TimeInterval?

    /// Plays a short haptic when a live camera read is accepted.
    ///
    /// Default: `true`. Camera path only. Follows the system haptic setting.
    public var hapticFeedback: Bool

    /// The accent color and light or dark mode.
    ///
    /// Default: `MrzScannerTheme()`.
    public var theme: MrzScannerTheme

    /// Called when the user taps "Continue" on the permission screen.
    ///
    /// Default: `nil`. The screen reads the camera permission and never requests it. With `nil` the screen has no
    /// grant button and your app owns the request. The closure must be `@Sendable`.
    /// Ask for the permission in the closure, for example with `AVCaptureDevice.requestAccess(for: .video)`; you
    /// need not report the answer. The screen keeps reading the permission and starts the camera once it is
    /// granted, or shows the Settings face once it is denied.
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

    /// The kinds of document your app takes.
    ///
    /// Default: every ``DocumentCategory``. This is your app's intake rule; the SDK does not judge the document.
    /// A reading whose category is not in the set does not go to review and is not returned. The screen says
    /// what kind it read and what kinds your app accepts, and lets the person go on: the camera keeps scanning,
    /// a photo can be swapped, and typed lines stay on the entry screen.
    /// The category is the document type code's broad category (`DocumentTypeCodeTable.broadCategory(code:)`).
    /// A code with no category is refused like a kind outside the set when the set is limited (not every
    /// category): the screen says the kind could not be told. With the default (every category) it is not
    /// filtered.
    /// An empty set is a configuration error: setting one stops the program with a precondition failure.
    ///
    /// - Since: 0.8.0
    public var acceptedDocumentTypes: Set<DocumentCategory> {
        didSet { requireAcceptableDocumentTypeSet(acceptedDocumentTypes) }
    }

    /// Creates a configuration, with the timeouts in seconds.
    ///
    /// Works on every supported iOS version. On iOS 16 and later the same configuration can be made with
    /// `Duration` timeouts.
    ///
    /// - Parameters:
    ///   - enabledMethods: The reading methods to offer. Default: `[.camera, .manualEntry]`.
    ///   - reviewMode: Review step or instant return. Default: `.review`.
    ///   - showTorchButton: Show the torch button. Default: `true`.
    ///   - torchOnByDefault: Start with the torch on. Default: `false`.
    ///   - struggleTimeoutInterval: Seconds before the "still looking" hint. Default: `10`; `nil` never.
    ///     Since 1.0.0.
    ///   - scanTimeoutInterval: Deadline for the whole session, in seconds. Default: `nil`, which never times
    ///     out. Since 1.0.0.
    ///   - hapticFeedback: Haptic on an accepted live read. Default: `true`.
    ///   - theme: Accent color and light or dark mode. Default: `MrzScannerTheme()`.
    ///   - onRequestPermission: Called to request the camera permission. Default: `nil`.
    ///   - stringsBundle: Bundle with string overrides. Default: `nil`. Since 0.5.1.
    ///   - acceptedDocumentTypes: The kinds of document your app takes. Default: every category. Must not be
    ///     empty: an empty set stops the program with a precondition failure. Since 0.8.0.
    public init(
        enabledMethods: Set<ScanMethod> = [.camera, .manualEntry],
        reviewMode: ReviewMode = .review,
        showTorchButton: Bool = true,
        torchOnByDefault: Bool = false,
        struggleTimeoutInterval: TimeInterval? = 10,
        scanTimeoutInterval: TimeInterval? = nil,
        hapticFeedback: Bool = true,
        theme: MrzScannerTheme = MrzScannerTheme(),
        onRequestPermission: (@Sendable () -> Void)? = nil,
        stringsBundle: Bundle? = nil,
        acceptedDocumentTypes: Set<DocumentCategory> = Set(DocumentCategory.entries)
    ) {
        self.enabledMethods = enabledMethods
        self.reviewMode = reviewMode
        self.showTorchButton = showTorchButton
        self.torchOnByDefault = torchOnByDefault
        self.struggleTimeoutInterval = struggleTimeoutInterval
        self.scanTimeoutInterval = scanTimeoutInterval
        self.hapticFeedback = hapticFeedback
        self.theme = theme
        self.onRequestPermission = onRequestPermission
        self.stringsBundle = stringsBundle
        // A property observer does not run during init, so the initializer checks the value itself.
        requireAcceptableDocumentTypeSet(acceptedDocumentTypes)
        self.acceptedDocumentTypes = acceptedDocumentTypes
    }

    // The two `Duration` initializers below each REQUIRE the timeout they are named for, so every call
    // resolves to exactly one initializer with no overload ranking: a call that names no timeout reaches
    // only the seconds initializer above, a call that names `struggleTimeout` (with or without
    // `scanTimeout`) only the first, and a call that names `scanTimeout` alone only the second. Together
    // they accept every call the 0.7.0 initializer (`struggleTimeout: Duration? = .seconds(10)`,
    // `scanTimeout: Duration? = nil`) accepted, in the same parameter order.

    /// Creates a configuration with `Duration` timeouts.
    ///
    /// - Parameters:
    ///   - enabledMethods: The reading methods to offer. Default: `[.camera, .manualEntry]`.
    ///   - reviewMode: Review step or instant return. Default: `.review`.
    ///   - showTorchButton: Show the torch button. Default: `true`.
    ///   - torchOnByDefault: Start with the torch on. Default: `false`.
    ///   - struggleTimeout: Time before the "still looking" hint; `nil` never. Leave it out for the default,
    ///     `.seconds(10)`.
    ///   - scanTimeout: Deadline for the whole session. Default: `nil`, which never times out.
    ///   - hapticFeedback: Haptic on an accepted live read. Default: `true`.
    ///   - theme: Accent color and light or dark mode. Default: `MrzScannerTheme()`.
    ///   - onRequestPermission: Called to request the camera permission. Default: `nil`.
    ///   - stringsBundle: Bundle with string overrides. Default: `nil`. Since 0.5.1.
    ///   - acceptedDocumentTypes: The kinds of document your app takes. Default: every category. Must not be
    ///     empty: an empty set stops the program with a precondition failure. Since 0.8.0.
    @available(iOS 16, *)
    public init(
        enabledMethods: Set<ScanMethod> = [.camera, .manualEntry],
        reviewMode: ReviewMode = .review,
        showTorchButton: Bool = true,
        torchOnByDefault: Bool = false,
        struggleTimeout: Duration?,
        scanTimeout: Duration? = nil,
        hapticFeedback: Bool = true,
        theme: MrzScannerTheme = MrzScannerTheme(),
        onRequestPermission: (@Sendable () -> Void)? = nil,
        stringsBundle: Bundle? = nil,
        acceptedDocumentTypes: Set<DocumentCategory> = Set(DocumentCategory.entries)
    ) {
        self.init(
            enabledMethods: enabledMethods,
            reviewMode: reviewMode,
            showTorchButton: showTorchButton,
            torchOnByDefault: torchOnByDefault,
            struggleTimeoutInterval: struggleTimeout.map(secondsFromDuration),
            scanTimeoutInterval: scanTimeout.map(secondsFromDuration),
            hapticFeedback: hapticFeedback,
            theme: theme,
            onRequestPermission: onRequestPermission,
            stringsBundle: stringsBundle,
            acceptedDocumentTypes: acceptedDocumentTypes
        )
    }

    /// Creates a configuration with a `Duration` session deadline and the default "still looking" time
    /// (10 seconds).
    ///
    /// - Parameters:
    ///   - enabledMethods: The reading methods to offer. Default: `[.camera, .manualEntry]`.
    ///   - reviewMode: Review step or instant return. Default: `.review`.
    ///   - showTorchButton: Show the torch button. Default: `true`.
    ///   - torchOnByDefault: Start with the torch on. Default: `false`.
    ///   - scanTimeout: Deadline for the whole session; `nil` never times out.
    ///   - hapticFeedback: Haptic on an accepted live read. Default: `true`.
    ///   - theme: Accent color and light or dark mode. Default: `MrzScannerTheme()`.
    ///   - onRequestPermission: Called to request the camera permission. Default: `nil`.
    ///   - stringsBundle: Bundle with string overrides. Default: `nil`. Since 0.5.1.
    ///   - acceptedDocumentTypes: The kinds of document your app takes. Default: every category. Must not be
    ///     empty: an empty set stops the program with a precondition failure. Since 0.8.0.
    @available(iOS 16, *)
    public init(
        enabledMethods: Set<ScanMethod> = [.camera, .manualEntry],
        reviewMode: ReviewMode = .review,
        showTorchButton: Bool = true,
        torchOnByDefault: Bool = false,
        scanTimeout: Duration?,
        hapticFeedback: Bool = true,
        theme: MrzScannerTheme = MrzScannerTheme(),
        onRequestPermission: (@Sendable () -> Void)? = nil,
        stringsBundle: Bundle? = nil,
        acceptedDocumentTypes: Set<DocumentCategory> = Set(DocumentCategory.entries)
    ) {
        self.init(
            enabledMethods: enabledMethods,
            reviewMode: reviewMode,
            showTorchButton: showTorchButton,
            torchOnByDefault: torchOnByDefault,
            scanTimeoutInterval: scanTimeout.map(secondsFromDuration),
            hapticFeedback: hapticFeedback,
            theme: theme,
            onRequestPermission: onRequestPermission,
            stringsBundle: stringsBundle,
            acceptedDocumentTypes: acceptedDocumentTypes
        )
    }
}

// MARK: - Duration and seconds (iOS 15 support)

// COMPAT-NOTE(iOS 16): not a shim. The seconds properties are public API (since 1.0.0) and stay when the
// minimum is iOS 16, so this bridge stays too; only its `@available(iOS 16, *)` marks become redundant.

/// Seconds in `duration`, to the attosecond as far as a `Double` holds it.
@available(iOS 16, *)
private func secondsFromDuration(_ duration: Duration) -> TimeInterval {
    let (seconds, attoseconds) = duration.components
    return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
}

/// `seconds` as a `Duration`, rounded to the nanosecond so a value set as a `Duration` reads back equal.
/// A value too large for the nanosecond count (or infinite) is capped; NaN reads as zero.
@available(iOS 16, *)
private func durationFromSeconds(_ seconds: TimeInterval) -> Duration {
    guard !seconds.isNaN else { return .zero }
    let nanos = (seconds * 1e9).rounded()
    if nanos >= 9.2e18 { return .nanoseconds(Int64.max) }
    if nanos <= -9.2e18 { return .nanoseconds(Int64.min) }
    return .nanoseconds(Int64(nanos))
}

// MARK: - Accepted document types validation (TES-103)

/// The message of the precondition failure an empty ``MrzScannerConfig/acceptedDocumentTypes`` triggers.
let emptyAcceptedDocumentTypesMessage =
    "acceptedDocumentTypes must not be empty; pass the kinds of document the app accepts, or leave the default"

/// Whether `types` is a valid ``MrzScannerConfig/acceptedDocumentTypes`` value: an empty set is a configuration
/// error (an app that accepts nothing could never get a result), the same rule as the Android builder's
/// `require`. Pure, so a host test checks the rule; the trap itself cannot run in a simulator test.
func isAcceptableDocumentTypeSet(_ types: Set<DocumentCategory>) -> Bool {
    !types.isEmpty
}

/// Stops the program when `types` is not a valid accepted set - a programming error, not a runtime condition.
private func requireAcceptableDocumentTypeSet(_ types: Set<DocumentCategory>) {
    precondition(isAcceptableDocumentTypeSet(types), emptyAcceptedDocumentTypesMessage)
}
