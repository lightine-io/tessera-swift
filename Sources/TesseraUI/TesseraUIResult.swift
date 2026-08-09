import Tessera

// The result surface, the iOS analogue of the Android module's `MrzScannerResult`. Frozen at the 0.5.0 tag.

/// Why the scanner UI dismissed without a confirmed result. Mirrors the Android `DismissReason`.
public enum DismissReason: Sendable, Hashable {
    /// The user dismissed the scanner (the ✕/back affordance).
    case userDismissed

    /// ``MrzScannerConfig/scanTimeout`` elapsed with no decode.
    case timedOut

    /// The camera could not be started (a terminal capture error) and the user closed the flow from that
    /// screen. The recoverable camera-in-use notice is NOT this — closing from it is ``userDismissed``.
    case cameraUnavailable

    /// The camera permission was not granted and the user closed the flow from a permission screen (grant
    /// or permanently-denied) rather than granting it or continuing another way.
    case permissionDenied
}

/// The outcome the scanner UI hands back to the host. The iOS analogue of the Android
/// `MrzScannerResult` (`Confirmed` / `Cancelled`).
///
/// - ``confirmed(_:)`` carries the decoded MRZ verbatim — the same `MrzScanResult.Decoded` the headless
///   SDK produces (full `ParseResult`, recognized text, and scan quality). Reader, not oracle: the UI
///   reports what was read; it makes no trust decision.
/// - ``cancelled(_:)`` carries the reason the UI closed without a confirmed result.
///
/// Not `Sendable`: ``confirmed(_:)`` wraps the SDK's `MrzScanResult.Decoded`, a Kotlin/Native-exported
/// reference type that is not `Sendable`. The result is delivered on the main actor via ``MrzScannerView``.
public enum TesseraUIResult {
    /// The user confirmed a decoded MRZ. Carries the SDK's own `MrzScanResult.Decoded`.
    case confirmed(MrzScanResultDecoded)

    /// The UI closed without a confirmed result; see ``DismissReason``.
    case cancelled(DismissReason)
}
