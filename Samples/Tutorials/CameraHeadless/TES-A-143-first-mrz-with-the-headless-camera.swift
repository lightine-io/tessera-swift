// Sample for TES-A-143 "Read your first MRZ on iOS with the headless camera": FirstReader.swift, then ContentView.swift.
// The target builds in the Swift 5 language mode, as step 2 of the page sets it.
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// Blocks 1 and 4 are not code: the specimen and the expected output.

// region TES-A-143 block 2
import AVFoundation
import Tessera

final class ResultCollector: NSObject, Kotlinx_coroutines_coreFlowCollector {
    private let onResult: (MrzScanResult) -> Void
    init(_ onResult: @escaping (MrzScanResult) -> Void) { self.onResult = onResult }

    func emit(value: Any?) async throws {
        if let result = value as? MrzScanResult { onResult(result) }
    }
}

@MainActor
final class FirstReader {
    private var scanner: AVCaptureMrzScanner?
    private var collectTask: Task<Void, Never>?

    func begin() {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                Task { @MainActor in self?.startScanner() }
            }
        } else {
            startScanner()
        }
    }

    private func startScanner() {
        let scanner = AVCaptureMrzScanner(
            recognizer: VisionMrzTextRecognizer(),
            mode: ParsingMode.lenient,
            telemetry: NoOpTelemetrySink(),
            cameraPosition: 1 // AVCaptureDevicePositionBack
        )
        self.scanner = scanner
        let collector = ResultCollector { [weak self] result in
            Task { @MainActor in self?.handle(result) }   // hop to the main actor
        }
        collectTask = Task { try? await scanner.results.collect(collector: collector) }
        scanner.start()
    }

    private func handle(_ result: MrzScanResult) {
        guard let decoded = result as? MrzScanResultDecoded else { return }
        let document: MrzDocument
        if let success = decoded.parse as? ParseResult.Success {
            document = success.document
        } else if let partial = decoded.parse as? ParseResult.PartialSuccess {
            document = partial.document
        } else {
            return
        }
        let fields = document.commonFields
        print("Name: \(fields.primaryIdentifier), \(fields.secondaryIdentifier)")
        print("Document number: \(fields.documentNumber)")
        print("Format: \(document.format.name)")
        collectTask?.cancel()
        scanner?.stop()
        scanner?.close()
        scanner = nil
    }
}
// endregion

// region TES-A-143 block 3
import SwiftUI

struct ContentView: View {
    @State private var reader = FirstReader()

    var body: some View {
        Text("Reading. Watch the Xcode console.")
            .onAppear { reader.begin() }
    }
}
// endregion
