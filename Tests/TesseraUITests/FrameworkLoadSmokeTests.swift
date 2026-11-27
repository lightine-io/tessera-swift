import Foundation
import ObjectiveC
import Testing
import Tessera
@testable import TesseraUI

/// TES-372: proves the Kotlin framework (`TesseraCore`) is loaded and its code runs on the iOS the test runs
/// on, through each system framework it uses: Core NFC, Vision and AVFoundation.
///
/// The bug this guards against: release 1.0.0 needed a class that only iOS 26.4 has, so an app that linked
/// it could not start on older iOS. `TesseraCore` is a static framework, so its code and its imports of
/// system symbols are linked into this test bundle, as they would be into an app. When a symbol is missing,
/// dyld refuses to load the bundle, no test runs, and the log shows `Symbol not found` (the workflow
/// `.github/workflows/old-ios.yml` prints those lines). A symbol that is only weakly imported does not stop
/// the load: it fails when the code that uses it runs. These calls run that code: each one touches a
/// different system framework.
///
/// Nothing here needs a camera, an NFC reader or a chip: the scanner is built but never started, and a
/// simulator answers the NFC questions with "not available".
struct FrameworkLoadSmokeTests {
    private static let specimenLines = [
        "P<UTOSPECIMEN<<ALEX<MORGAN<<<<<<<<<<<<<<<<<<",
        "T220001293UTO9003152F3403141S98765432<<<<<20",
    ]

    @Test func theKotlinFrameworkIsLoadedAndParses() throws {
        // The Kotlin object is an Objective-C class of the loaded image.
        let image = try #require(class_getImageName(MrzParser.self).map { String(cString: $0) },
                                 "MrzParser has no loaded image")
        let parse = MrzParser.shared.parse(lines: Self.specimenLines, referenceTime: nowInstant())
        #expect(!(parse is ParseResult.Failure))
        print("old-ios-smoke: iOS \(ProcessInfo.processInfo.operatingSystemVersionString): Kotlin classes in \((image as NSString).lastPathComponent)")
    }

    @Test func chipReadingAsksCoreNfc() {
        // Core NFC's `NFCReaderSession.readingAvailable`, through the Kotlin reader. A simulator has no reader.
        let availability = ChipReading.availability
        let readiness = ChipReading.readiness
        switch readiness {
        case .unavailable(let reason): #expect(availability === reason)
        case .ready, .notYet, .readInProgress, .unknown: #expect(availability == nil)
        }
        print("old-ios-smoke: chip reading available: \(availability == nil)")
    }

    @Test func theCameraScannerAndVisionRecognizerBuild() {
        // Built the way TesseraUI's scanner builds them, then closed without starting: no camera is opened.
        let recognizer = VisionMrzTextRecognizer()
        recognizer.restrictToMrzBand()
        let scanner = AVCaptureMrzScanner(
            recognizer: recognizer,
            mode: ParsingMode.lenient,
            telemetry: NoOpTelemetrySink(),
            cameraPosition: 1 // AVCaptureDevicePositionBack
        )
        scanner.close()
        print("old-ios-smoke: camera scanner built and closed")
    }
}
