// Sample for TES-A-125 "Tune timing and extras of the iOS scanner screen".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-125 block 1: Package.swift dependency lines

// region TES-A-125 block 2
import SwiftUI
import Tessera
import TesseraUI
// endregion

// Outside the page's blocks: the `Duration` timeouts need iOS 16, and the package supports iOS 15.
@available(iOS 16, *)
struct TunedScreen: View {
    // region TES-A-125 block 3
    let config = MrzScannerConfig(
        showTorchButton: false,
        struggleTimeout: .seconds(20),
        scanTimeout: .seconds(90),
        hapticFeedback: false
    )
    // endregion

    var body: some View {
        // region TES-A-125 block 4
        MrzScannerView(config: config) { result in /* handle the result */ }
        // endregion
    }
}

@available(iOS 16, *)
struct NoStruggleHintConfig {
    // region TES-A-125 block 5
    let config = MrzScannerConfig(
        struggleTimeout: nil   // never show the hint
    )
    // endregion
}
