// Sample for TES-A-77 "Read your first MRZ on iOS with the ready-made screen": the app's ContentView.swift.
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// Blocks 1, 2 and 4 are not code: the specimen, the camera usage text, the expected output.

// region TES-A-77 block 3
import AVFoundation
import SwiftUI
import Tessera
import TesseraUI

struct ContentView: View {
    @State private var showScanner = false
    @State private var summary = "No scan yet"

    var body: some View {
        VStack(spacing: 16) {
            Button("Scan a document") { showScanner = true }
            Text(summary)
        }
        .padding(24)
        .fullScreenCover(isPresented: $showScanner) {
            MrzScannerView(
                config: MrzScannerConfig(
                    onRequestPermission: { AVCaptureDevice.requestAccess(for: .video) { _ in } }
                )
            ) { result in
                switch result {
                case let .confirmed(decoded): summary = summarize(decoded)
                case let .cancelled(reason): summary = "Closed: \(reason)"
                }
                showScanner = false
            }
        }
    }

    private func summarize(_ decoded: MrzScanResultDecoded) -> String {
        let document: MrzDocument
        if let success = decoded.parse as? ParseResult.Success {
            document = success.document
        } else if let partial = decoded.parse as? ParseResult.PartialSuccess {
            document = partial.document
        } else {
            return "Not a readable MRZ"
        }
        let fields = document.commonFields
        return "Name: \(fields.primaryIdentifier), \(fields.secondaryIdentifier)\n" +
            "Document number: \(fields.documentNumber)\n" +
            "Format: \(document.format.name)\n" +
            "Read by: \(decoded.parse.metadata.readMethod.name)"
    }
}
// endregion
