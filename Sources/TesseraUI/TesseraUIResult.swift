import Tessera

// The result surface, the iOS analogue of the Android module's `MrzScannerResult`. Frozen at the 0.5.0 tag.

/// Tells why the scanner screen closed without a confirmed reading.
///
/// The close button is the only way to `.userDismissed`. The screen sets no swipe-down handling.
///
/// - Since: 0.5.0
public enum DismissReason: Sendable, Hashable {
    /// The user pressed the close button.
    ///
    /// This includes closing the "camera is in use" notice.
    case userDismissed

    /// ``MrzScannerConfig/scanTimeout`` ran out, on whichever screen was showing.
    case timedOut

    /// The camera could not start and the user closed that error screen.
    case cameraUnavailable

    /// The user closed a camera permission screen without granting access.
    case permissionDenied
}

/// The result `MrzScannerView` passes to its callback.
///
/// Not `Sendable`: `.confirmed` holds a Kotlin object. Keep the decoded value on the main actor.
///
/// - Since: 0.5.0
public enum TesseraUIResult {
    /// A decoded MRZ whose parse is a success or partial success.
    ///
    /// It is never a failure. A photo read inside the screen carries no capture metadata. The value holds document data.
    case confirmed(MrzScanResultDecoded)

    /// The screen closed without a confirmed reading; see ``DismissReason``.
    case cancelled(DismissReason)
}
