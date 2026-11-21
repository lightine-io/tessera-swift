// Sample for TES-A-119 "Choose review or instant return on the iOS scanner screen".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-119 block 1: Package.swift dependency lines

// region TES-A-119 block 2
import SwiftUI
import Tessera
import TesseraUI
// endregion

struct InstantReturnScreen: View {
    // region TES-A-119 block 3
    let config = MrzScannerConfig(
        reviewMode: .instantReturn
    )
    // endregion

    var body: some View {
        // region TES-A-119 block 4
        MrzScannerView(config: config) { result in /* handle the result */ }
        // endregion
    }
}

// region TES-A-119 block 5
func failureCount(of decoded: MrzScanResultDecoded) -> Int {
    decoded.parse.metadata.validationFailures.count
}
// endregion

struct ReviewConfig {
    // region TES-A-119 block 6
    let config = MrzScannerConfig(
        reviewMode: .review   // the default, written out
    )
    // endregion
}
