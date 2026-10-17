import SwiftUI
import Tessera

/// Shows the ready-made MRZ scanner screen.
///
/// Reports one ``TesseraUIResult`` through `onResult`. The screen does not remove itself; remove it in the callback.
/// Present it with `fullScreenCover`: the close button is the only way to `.cancelled(.userDismissed)`.
/// Reads the camera permission and never requests it; see ``MrzScannerConfig/onRequestPermission``.
/// Not configurable: lenient line matching and 2 agreeing frames. Telemetry goes to the sink registered with
/// `TelemetrySinkRegistry`, read when the scanner opens.
/// The configuration is read when the scanner opens; changes while it is open apply the next time it opens.
///
/// - Since: 0.5.0
public struct MrzScannerView: View {
    private let config: MrzScannerConfig
    private let onResult: (TesseraUIResult) -> Void

    /// Creates the scanner screen.
    ///
    /// - Parameters:
    ///   - config: The screen's settings. Default: `MrzScannerConfig()`. Read when the scanner opens; changes
    ///     while it is open apply the next time it opens.
    ///   - onResult: Called on the main actor with the result when the screen confirms a read or closes.
    public init(
        config: MrzScannerConfig = MrzScannerConfig(),
        onResult: @escaping (TesseraUIResult) -> Void
    ) {
        self.config = config
        self.onResult = onResult
    }

    /// The scanner screen.
    public var body: some View {
        // The state-machine-driven UI: RootScannerView owns the ScannerModel, dispatches the matching screen
        // under the shared ScannerScaffold chrome, applies the theme, and injects the strings-bundle override
        // (TES-139). It reads the config only through the model, so the config is fixed per presentation (TES-155).
        RootScannerView(config: config, onResult: onResult)
    }
}
