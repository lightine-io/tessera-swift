// Compile-only guard (TES-346): app code as written for release 0.7.0, when `Tessera` was the
// generated framework itself. It must keep compiling now that `Tessera` is the Swift target that
// re-exports `TesseraCore`. Not a sample of any page; nothing ships.
import AVFoundation
import SwiftUI
import Tessera
import TesseraUI

struct App070ContentView: View {
    @State private var showScanner = false
    @State private var summary = "No scan yet"

    var body: some View {
        VStack(spacing: 16) {
            Button("Scan a document") { showScanner = true }
            Text(summary)
        }
        .fullScreenCover(isPresented: $showScanner) {
            MrzScannerView(
                config: MrzScannerConfig(
                    onRequestPermission: { AVCaptureDevice.requestAccess(for: .video) { _ in } }
                )
            ) { result in
                switch result {
                case let .confirmed(decoded): summary = App070.summarize(decoded)
                case let .cancelled(reason): summary = "Closed: \(reason)"
                }
                showScanner = false
            }
        }
    }
}

enum App070 {
    // Core types, unqualified, as 0.7.0 apps use them.
    static func summarize(_ decoded: MrzScanResultDecoded) -> String {
        let document: MrzDocument
        if let success = decoded.parse as? ParseResult.Success {
            document = success.document
        } else if let partial = decoded.parse as? ParseResult.PartialSuccess {
            document = partial.document
        } else {
            return "Not a readable MRZ"
        }
        return "\(document.commonFields.documentNumber) \(document.format.name) \(decoded.parse.metadata.readMethod.name)"
    }

    static func parse(_ text: String) -> ParseResult {
        let now = KotlinInstant.companion.fromEpochMilliseconds(epochMilliseconds: 1_795_219_200_000)
        return MrzParser.shared.parse(input: text, referenceTime: now)
    }

    static func isPassport(_ document: MrzDocument) -> Bool { document is TD3 }

    // A module-qualified name, as an app may have written it against 0.7.0.
    static func qualified(_ result: ParseResult) -> Tessera.MrzDocument? {
        (result as? Tessera.ParseResult.Success)?.document
    }
}
