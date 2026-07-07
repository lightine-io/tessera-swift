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
/// - Note: **Scaffold.** This 0.5.0 slice (TES-55) establishes the frozen public surface, the SPM product,
///   and the CI/test/API-guard machinery. The actual screens — live preview, review, manual, saved-image,
///   the method switcher, and the state machine mirroring Android — land in later iOS slices
///   (TES-56/59/60/72/73/74/75) and require the K/N live-preview seam tracked in TES-82.
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
        // Placeholder scaffold body — replaced by the real state-machine-driven UI in later slices.
        VStack(spacing: 16) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 48))
            Text("Tessera scanner")
                .font(.headline)
            Button("Cancel") { onResult(.cancelled(.userDismissed)) }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
