// Sample for TES-A-108 "Hand the camera permission to your app from the iOS scanner screen".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-108 block 1: Package.swift dependency lines

// region TES-A-108 block 2
import AVFoundation
import SwiftUI
import Tessera
import TesseraUI
// endregion

struct PermissionHandlerScreen: View {
    // region TES-A-108 block 3
    let config = MrzScannerConfig(
        onRequestPermission: { AVCaptureDevice.requestAccess(for: .video) { _ in } }
    )
    // endregion

    var body: some View {
        // region TES-A-108 block 4
        MrzScannerView(config: config) { result in /* handle the result */ }
        // endregion
    }
}

func askBeforeShowingTheScreen() {
    // region TES-A-108 block 5
    let config = MrzScannerConfig()   // no handler
    AVCaptureDevice.requestAccess(for: .video) { _ in }   // ask before you show the screen
    // endregion
}
