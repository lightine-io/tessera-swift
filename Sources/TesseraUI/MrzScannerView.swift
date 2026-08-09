import SwiftUI
import Tessera

/// The default MRZ scanner UI — the single SwiftUI entry point a host embeds. The iOS analogue of the
/// Android `MrzScannerScreen`. Its signature (this view + ``MrzScannerConfig`` + ``TesseraUIResult``)
/// freezes at the 0.5.0 tag under ADR-007.
///
/// ```swift
/// MrzScannerView(config: MrzScannerConfig()) { result in
///     switch result {
///     case let .confirmed(decoded): // decoded.parse — the read MRZ
///     case let .cancelled(reason):  // reason — why it closed
///     }
/// }
/// ```
///
/// - Note: All screens are implemented — live preview, review, manual raw entry, saved-image, the camera
///   status/permission screens, and the method switcher (TES-55/56/57/59/60/72/73/74/75), with full ADR-027
///   state coverage. Field-by-field manual entry (mockup 06b) was decided against entirely (TES-79,
///   won't-do: typed fields are a host-app form, not a document read).
public struct MrzScannerView: View {
    private let config: MrzScannerConfig
    private let onResult: (TesseraUIResult) -> Void

    /// - Parameters:
    ///   - config: how the UI is tuned; see ``MrzScannerConfig``. Defaults to all-defaults.
    ///   - onResult: invoked once with the ``TesseraUIResult`` when the UI confirms a decode or closes.
    public init(
        config: MrzScannerConfig = MrzScannerConfig(),
        onResult: @escaping (TesseraUIResult) -> Void
    ) {
        self.config = config
        self.onResult = onResult
    }

    public var body: some View {
        // The state-machine-driven UI: RootScannerView owns the ScannerModel, dispatches the matching screen
        // under the shared ScannerScaffold chrome, and applies the theme.
        RootScannerView(config: config, onResult: onResult)
    }
}
