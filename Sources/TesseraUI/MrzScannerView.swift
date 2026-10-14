import SwiftUI
import Tessera

/// Shows the ready-made MRZ scanner screen.
///
/// Reports one ``TesseraUIResult`` through `onResult`. The screen does not remove itself; remove it in the callback.
/// Present it with `fullScreenCover`: the close button is the only way to `.cancelled(.userDismissed)`.
/// Reads the camera permission and never requests it; see ``MrzScannerConfig/onRequestPermission``.
/// Not configurable: lenient line matching, 2 agreeing frames, and no telemetry events.
///
/// - Since: 0.5.0
public struct MrzScannerView: View {
    private let config: MrzScannerConfig
    private let onResult: (TesseraUIResult) -> Void

    /// Creates the scanner screen.
    ///
    /// - Parameters:
    ///   - config: The screen's settings. Default: `MrzScannerConfig()`.
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
        // under the shared ScannerScaffold chrome, and applies the theme. The strings-bundle override (TES-139)
        // is injected here, once, so every descendant screen's ``TesseraStrings/string(_:bundle:)`` call sees
        // it without config being threaded through each view's initializer.
        RootScannerView(config: config, onResult: onResult)
            .environment(\.tesseraStringsBundle, config.stringsBundle)
    }
}
