import Foundation
import Testing
import Tessera
@testable import TesseraUI

/// TES-298: VoiceOver is told when the scanner switches to a new screen.
///
/// The notification itself is posted by the root view, and a package test cannot read what VoiceOver does with
/// it (the same limit as ``ScannerAccessibilityLabelTests``). These tests check the decision: which state
/// changes are a new screen, and which title each new screen speaks.
struct ScannerScreenChangeTests {
    private static var decoded: MrzScanResultDecoded { assembleManualDecoded(text: "not an mrz at all") }
    private static var camera: ScannerState { ScannerState.scanning(struggling: false, gathering: false) }
    private static var review: ScannerState { ScannerState.review(decoded: decoded, expanded: false, source: .camera) }
    private static var readFailed: ScannerState { ScannerState.readFailed(capturedText: RecognizedText(lines: [])) }
    private static var manual: ScannerState { ScannerState.manualRaw(text: "", parseFailed: false) }

    /// The English title each screen speaks on arrival (nil: the live camera has none).
    private static var expectedTitle: [(ScannerState, String?)] { [
        (camera, nil),
        (.permissionNeeded, "Camera permission needed"),
        (.permissionPermanentlyDenied, "Camera access is off"),
        (.cameraInUse, "Camera is in use"),
        (.cameraUnavailable, "Camera unavailable"),
        (review, "Check the details"),
        (readFailed, "Couldn't read this MRZ"),
        (.awaitingSavedImagePick, "Choose a photo of your document"),
        (.savedImageAnalyzing, "Analyzing photo…"),
        (.savedImageEmpty, "No MRZ found in this photo"),
        (manual, "Enter the MRZ manually"),
    ] }

    @Test func everyNewScreenIsAScreenChangeWithItsTitle() throws {
        for (state, expected) in Self.expectedTitle {
            // From a different screen: the manual screen, or the camera when the target is the manual screen.
            let from = screen(of: state) == .manualEntry ? Self.camera : Self.manual
            let change = try #require(screenChange(from: from, to: state), "\(state)")
            let spoken = change.titleKey.map { TesseraStrings.string($0, bundle: nil) }
            #expect(spoken == expected, "\(state)")
        }
    }

    @Test func everyScreenTitleKeyExistsInTheCatalog() {
        for (state, _) in Self.expectedTitle {
            guard let key = screenTitleKey(for: state) else { continue }
            #expect(TesseraStrings.string(key, bundle: nil) != key, "missing string for \(key)")
        }
    }

    @Test func aHostOverrideReachesTheSpokenTitle() throws {
        let host = FakeHostBundle(overrides: ["tessera_scanner_review_title": "Prüfen"])
        let key = try #require(screenChange(from: Self.camera, to: Self.review)?.titleKey)
        #expect(TesseraStrings.string(key, bundle: host) == "Prüfen")
    }

    @Test func stayingOnOneScreenIsNotAScreenChange() {
        // Overlays on the camera.
        #expect(screenChange(from: Self.camera, to: .scanning(struggling: true, gathering: false)) == nil)
        #expect(screenChange(from: .scanning(struggling: true, gathering: false),
                             to: .scanning(struggling: false, gathering: true)) == nil)
        // Expanding the review.
        let expanded = ScannerState.review(decoded: Self.decoded, expanded: true, source: .camera)
        #expect(screenChange(from: Self.review, to: expanded) == nil)
        // An inline note on manual entry.
        #expect(screenChange(from: Self.manual, to: .manualRaw(text: "x", parseFailed: true)) == nil)
    }

    @Test func movingBetweenCameraReviewManualAndErrorScreensIsAScreenChange() {
        #expect(screenChange(from: Self.camera, to: Self.review) != nil)
        #expect(screenChange(from: Self.review, to: Self.camera) != nil)
        #expect(screenChange(from: Self.camera, to: Self.manual) != nil)
        #expect(screenChange(from: Self.manual, to: Self.review) != nil)
        #expect(screenChange(from: Self.camera, to: Self.readFailed) != nil)
        #expect(screenChange(from: Self.camera, to: .cameraInUse) != nil)
        #expect(screenChange(from: .cameraInUse, to: Self.camera) != nil)
    }

    /// A stand-in host bundle: an override for the keys in `overrides`, the key itself for anything else.
    private final class FakeHostBundle: Bundle, @unchecked Sendable {
        let overrides: [String: String]
        init(overrides: [String: String]) {
            self.overrides = overrides
            super.init()
        }
        override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
            overrides[key] ?? key
        }
    }
}
