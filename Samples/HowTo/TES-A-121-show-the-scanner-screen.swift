// Sample for TES-A-121 "Show the scanner screen on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// Blocks 3 and 4 are one declaration split across two blocks on the page.
// skip TES-A-121 block 1: Package.swift dependency lines

// region TES-A-121 block 2
import SwiftUI
import Tessera
import TesseraUI
// endregion

// region TES-A-121 block 3
struct ScannerRoute: View {
    let onConfirmed: (MrzScanResultDecoded) -> Void
    let onClosed: (DismissReason) -> Void

    var body: some View {
        MrzScannerView(config: MrzScannerConfig()) { result in
// endregion
// region TES-A-121 block 4
            switch result {
            case let .confirmed(decoded): onConfirmed(decoded)
            case let .cancelled(reason): onClosed(reason)
            }
        }
    }
}
// endregion

// region TES-A-121 block 5
func notes(of decoded: MrzScanResultDecoded) -> [String] {
    let metadata = decoded.parse.metadata
    return metadata.validationFailures.map { "Validation failure: \($0.description_)" }
        + metadata.warnings.map { "Warning: \($0.description_)" }
}
// endregion

// region TES-A-121 block 6
import SwiftUI
import Tessera
import TesseraUI

struct HomeView: View {
    @State private var showScanner = false

    var body: some View {
        Button("Scan a document") { showScanner = true }
            .fullScreenCover(isPresented: $showScanner) {
                ScannerRoute(onConfirmed: { _ in showScanner = false },
                             onClosed: { _ in showScanner = false })
            }
    }
}
// endregion

@MainActor
func routeWithTimeoutHandling() -> ScannerRoute {
    ScannerRoute(
        onConfirmed: { _ in },
        // region TES-A-121 block 7
        onClosed: { reason in
            switch reason {
            case .timedOut: break   // tell the user time ran out
            default: break          // go back
            }
        }
        // endregion
    )
}
