import Foundation
import Testing
@testable import TesseraUI

/// TES-58: what VoiceOver says for each control of the scanner screens.
///
/// The screens take every control name from ``ScannerControl``, so these tests check that table: each control
/// has a name from the catalog, the name is the right one, and two controls on one screen never share a name.
/// The rendered accessibility tree itself is not read here: SwiftUI builds it only while VoiceOver or UI-test
/// automation asks for it, and the package has no UI test host. Roles (button, text field) come from the
/// SwiftUI control types the screens use and are not checked here.
struct ScannerAccessibilityLabelTests {
    /// The English name VoiceOver reads for each control.
    private static let expectedSpokenName: [ScannerControl: String] = [
        .close: "Close",
        .privacy: "Privacy",
        .privacyDismiss: "Got it",
        .method(.camera): "Camera",
        .method(.savedImage): "Photo",
        .method(.manualEntry): "Manual",
        .torch: "Flashlight",
        .explainer: "What's the MRZ?",
        .explainerDismiss: "Got it",
        .strugglingManual: "Enter details manually",
        .permissionContinue: "Continue",
        .permissionOpenSettings: "Open Settings",
        .cameraManual: "Enter details manually",
        .readFailedTryAgain: "Try again",
        .readFailedManual: "Enter details manually",
        .choosePhoto: "Choose photo",
        .chooseDifferentPhoto: "Choose different photo",
        .savedImageManual: "Enter details manually",
        .manualField: "MRZ lines",
        .manualRead: "Read",
        .keyboardDone: "Done",
        .reviewShowAll: "Show all fields and MRZ text",
        .reviewShowLess: "Show less",
        .reviewUse: "Use this result",
        .reviewSecondary(.camera): "Rescan",
        .reviewSecondary(.savedImage): "Try another photo",
        .reviewSecondary(.manualEntry): "Edit entry",
    ]

    /// The controls that can be on screen together, by screen.
    private static let screens: [String: [ScannerControl]] = [
        "top bar": [.close, .privacy],
        "method switcher": [.method(.camera), .method(.savedImage), .method(.manualEntry)],
        "camera preview": [.torch, .explainer, .strugglingManual],
        "permission, needs grant": [.permissionContinue, .cameraManual],
        "permission, denied": [.permissionOpenSettings, .cameraManual],
        "read failed": [.readFailedTryAgain, .readFailedManual],
        "saved image, no MRZ": [.chooseDifferentPhoto, .savedImageManual],
        "manual entry": [.manualField, .manualRead, .keyboardDone],
        "review, camera": [.reviewShowAll, .reviewUse, .reviewSecondary(.camera)],
        "review, photo": [.reviewShowAll, .reviewUse, .reviewSecondary(.savedImage)],
        "review, manual": [.reviewShowAll, .reviewUse, .reviewSecondary(.manualEntry)],
        "review, all fields": [.reviewShowLess, .reviewUse, .reviewSecondary(.camera)],
    ]

    @Test func theExpectationsCoverEveryControlOnce() {
        #expect(Set(ScannerControl.all).count == ScannerControl.all.count)
        #expect(Set(Self.expectedSpokenName.keys) == Set(ScannerControl.all))
    }

    @Test(arguments: ScannerControl.all)
    func eachControlHasItsName(_ control: ScannerControl) {
        #expect(control.spokenLabel(bundle: nil) == Self.expectedSpokenName[control])
    }

    @Test(arguments: ScannerControl.all)
    func eachControlNameComesFromTheCatalog(_ control: ScannerControl) {
        // A key the catalog lacks resolves to the key itself.
        let label = control.label(bundle: nil)
        #expect(label != control.labelKey)
        #expect(!label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(!control.spokenLabel(bundle: nil).isEmpty)
    }

    @Test(arguments: screens.keys.sorted())
    func controlsOnOneScreenHaveDifferentNames(_ screen: String) throws {
        let controls = try #require(Self.screens[screen])
        let names = controls.map { $0.spokenLabel(bundle: nil) }
        #expect(Set(names).count == names.count, "\(screen): \(names)")
    }

    @Test func theDisclosureArrowsAreShownButNotSpoken() {
        #expect(ScannerControl.reviewShowAll.label(bundle: nil).contains("▾"))
        #expect(ScannerControl.reviewShowLess.label(bundle: nil).contains("▴"))
        for control in ScannerControl.all {
            let spoken = control.spokenLabel(bundle: nil)
            #expect(!spoken.contains("▾") && !spoken.contains("▴") && !spoken.contains("ⓘ"), "\(control): \(spoken)")
        }
    }

    @Test func aHostOverrideReachesTheSpokenName() {
        let host = FakeHostBundle(overrides: ["tessera_scanner_close": "Schließen", "tessera_scanner_review_show_less": "Weniger ▴"])
        #expect(ScannerControl.close.spokenLabel(bundle: host) == "Schließen")
        #expect(ScannerControl.reviewShowLess.spokenLabel(bundle: host) == "Weniger")
    }

    // MARK: - Values that change with state

    @Test func theTorchSaysWhetherItIsOnOrOff() {
        #expect(torchAccessibilityValue(on: true, bundle: nil) == "On")
        #expect(torchAccessibilityValue(on: false, bundle: nil) == "Off")
    }

    @Test func theCountdownSaysWhatTheTimeIsFor() {
        #expect(countdownAccessibilityLabel(shown: "1:05", bundle: nil) == "Scan time left: 1:05")
    }

    @Test func anObservationSaysItsToneInWordsNotItsSymbol() {
        let text = "Expiry date has passed"
        let cases: [(ObservationTone, String, String)] = [
            (.matches, "✓", "Match: \(text)"),
            (.mismatch, "‼", "Attention: \(text)"),
            (.info, "ⓘ", "Note: \(text)"),
        ]
        for (tone, symbol, expected) in cases {
            let observation = ReviewObservation(symbol: symbol, text: text, tone: tone)
            let spoken = observationAccessibilityLabel(observation, bundle: nil)
            #expect(spoken == expected)
            #expect(!spoken.contains(symbol))
        }
    }

    /// A stand-in host bundle: an override for the keys in `overrides`, the key itself (the documented miss) for
    /// anything else.
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
