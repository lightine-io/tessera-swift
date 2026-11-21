// Sample for TES-A-106 "Choose the reading methods of the scanner screen on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-106 block 1: Package.swift dependency lines

// region TES-A-106 block 2
import SwiftUI
import Tessera
import TesseraUI
// endregion

struct ReadingMethodsScreen: View {
    // region TES-A-106 block 3
    let config = MrzScannerConfig(
        enabledMethods: [.camera, .savedImage, .manualEntry]
    )
    // endregion

    var body: some View {
        // region TES-A-106 block 4
        MrzScannerView(config: config) { result in /* handle the result */ }
        // endregion
    }
}

// region TES-A-106 block 5
func readMethodName(of decoded: MrzScanResultDecoded) -> String {
    decoded.parse.metadata.readMethod.name
}
// endregion

struct CameraOnlyConfig {
    // region TES-A-106 block 6
    let config = MrzScannerConfig(
        enabledMethods: [.camera]   // camera only: no photo, no typing
    )
    // endregion
}
