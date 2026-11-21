// Sample for TES-A-123 "Theme the iOS scanner screen".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-123 block 1: Package.swift dependency lines

// region TES-A-123 block 2
import SwiftUI
import Tessera
import TesseraUI
// endregion

struct ThemedScreen: View {
    // region TES-A-123 block 3
    let config = MrzScannerConfig(
        theme: MrzScannerTheme(brandColor: Color(red: 0.0, green: 0.41, blue: 0.36), darkMode: .on)   // always dark
    )
    // endregion

    var body: some View {
        // region TES-A-123 block 4
        MrzScannerView(config: config) { result in /* handle the result */ }
        // endregion
    }
}

struct DarkDefaultAccentConfig {
    // region TES-A-123 block 5
    let config = MrzScannerConfig(
        theme: MrzScannerTheme(darkMode: .on)   // always dark, default accent
    )
    // endregion
}
