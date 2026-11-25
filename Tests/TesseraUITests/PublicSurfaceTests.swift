import Testing
@testable import TesseraUI

/// Coverage of the frozen 0.5.0 public surface: config defaults and the result/dismiss shapes. Screen
/// behavior is covered by the decision/state tests (`ScannerDecisionsTests`, `ReviewFieldMappingTests`).
// The package supports iOS 15; the tests that use the `Duration` timeouts need iOS 16 (Swift Testing takes
// `@available` on each test, not on the suite). The seconds forms are covered by `TimeoutIntervalSurfaceTests`.
struct PublicSurfaceTests {
    @available(iOS 16, *)
    @Test func configDefaultsMatchTheContract() {
        let config = MrzScannerConfig()
        #expect(config.enabledMethods == [.camera, .manualEntry]) // saved-image opt-in, off by default
        #expect(config.reviewMode == .review)
        #expect(config.showTorchButton == true)
        #expect(config.torchOnByDefault == false)
        #expect(config.struggleTimeout == .seconds(10))
        #expect(config.scanTimeout == nil) // never times out by default
        #expect(config.hapticFeedback == true) // the accepted-read confirm haptic is on unless opted out
        #expect(config.theme.brandColor == nil)
        #expect(config.theme.darkMode == .auto)
        #expect(config.onRequestPermission == nil)
    }

    @available(iOS 16, *)
    @Test func configPassesValuesThroughVerbatim() {
        let config = MrzScannerConfig(
            enabledMethods: [.camera, .savedImage, .manualEntry],
            reviewMode: .instantReturn,
            showTorchButton: false,
            torchOnByDefault: true,
            struggleTimeout: .seconds(3),
            scanTimeout: .seconds(30),
            hapticFeedback: false,
            theme: MrzScannerTheme(darkMode: .on)
        )
        #expect(config.enabledMethods.contains(.savedImage))
        #expect(config.reviewMode == .instantReturn)
        #expect(config.showTorchButton == false)
        #expect(config.torchOnByDefault == true)
        #expect(config.struggleTimeout == .seconds(3))
        #expect(config.scanTimeout == .seconds(30))
        #expect(config.hapticFeedback == false)
        #expect(config.theme.darkMode == .on)
    }

    @Test func dismissReasonCasesAreDistinct() {
        let all: Set<DismissReason> = [.userDismissed, .timedOut, .cameraUnavailable, .permissionDenied]
        #expect(all.count == 4)
    }

    /// Both timeouts express "never" as `nil` (Swift `Duration` has no infinity sentinel) — a config that
    /// disables both the struggle hint and the scan deadline is accepted verbatim (TES-85).
    @available(iOS 16, *)
    @Test func timeoutsCanBeDisabledWithNil() {
        let config = MrzScannerConfig(struggleTimeout: nil, scanTimeout: nil)
        #expect(config.struggleTimeout == nil) // never struggle
        #expect(config.scanTimeout == nil) // never time out
    }
}

/// The seconds forms of the timeouts (`struggleTimeoutInterval`, `scanTimeoutInterval`), usable on iOS 15, and
/// their agreement with the `Duration` forms on iOS 16 and later.
struct TimeoutIntervalSurfaceTests {
    @Test func intervalDefaultsMatchTheContract() {
        let config = MrzScannerConfig()
        #expect(config.struggleTimeoutInterval == 10)
        #expect(config.scanTimeoutInterval == nil)
    }

    @Test func intervalsPassThroughVerbatim() {
        let config = MrzScannerConfig(struggleTimeoutInterval: 3.5, scanTimeoutInterval: 30)
        #expect(config.struggleTimeoutInterval == 3.5)
        #expect(config.scanTimeoutInterval == 30)
        let never = MrzScannerConfig(struggleTimeoutInterval: nil, scanTimeoutInterval: nil)
        #expect(never.struggleTimeoutInterval == nil)
        #expect(never.scanTimeoutInterval == nil)
    }

    @available(iOS 16, *)
    @Test func durationAndIntervalFormsAreOneSetting() {
        var config = MrzScannerConfig(struggleTimeout: .milliseconds(1500), scanTimeout: .seconds(90))
        #expect(config.struggleTimeoutInterval == 1.5)
        #expect(config.scanTimeoutInterval == 90)
        #expect(config.struggleTimeout == .milliseconds(1500)) // reads back equal, not rounded off

        config.scanTimeoutInterval = 45
        #expect(config.scanTimeout == .seconds(45))
        config.struggleTimeout = nil
        #expect(config.struggleTimeoutInterval == nil)
    }
}

/// Every call shape the 0.7.0 initializer accepted still compiles and resolves to exactly one initializer
/// (an ambiguous call would not compile), with the meaning it had: no timeout named, other labels only,
/// `struggleTimeout` alone, `scanTimeout` alone, and both.
struct ConfigInitCallShapeTests {
    @Test func noArguments() {
        let config = MrzScannerConfig()
        #expect(config.struggleTimeoutInterval == 10)
        #expect(config.scanTimeoutInterval == nil)
    }

    @Test func otherLabelsOnly() {
        let config = MrzScannerConfig(reviewMode: .instantReturn, hapticFeedback: false, stringsBundle: nil)
        #expect(config.reviewMode == .instantReturn)
        #expect(config.hapticFeedback == false)
        #expect(config.struggleTimeoutInterval == 10)
        #expect(config.scanTimeoutInterval == nil)
    }

    @available(iOS 16, *)
    @Test func struggleTimeoutAlone() {
        let config = MrzScannerConfig(struggleTimeout: .seconds(10))
        #expect(config.struggleTimeout == .seconds(10))
        #expect(config.scanTimeout == nil)
        let never = MrzScannerConfig(struggleTimeout: nil)
        #expect(never.struggleTimeout == nil)
        #expect(never.scanTimeout == nil)
    }

    @available(iOS 16, *)
    @Test func scanTimeoutAloneKeepsTheDefaultStruggleTimeout() {
        let config = MrzScannerConfig(scanTimeout: .seconds(30))
        #expect(config.scanTimeout == .seconds(30))
        #expect(config.struggleTimeout == .seconds(10))
        let withOthers = MrzScannerConfig(
            enabledMethods: [.camera],
            torchOnByDefault: true,
            scanTimeout: .seconds(5),
            acceptedDocumentTypes: [.passport]
        )
        #expect(withOthers.scanTimeout == .seconds(5))
        #expect(withOthers.torchOnByDefault == true)
        #expect(withOthers.struggleTimeout == .seconds(10))
    }

    @available(iOS 16, *)
    @Test func bothTimeouts() {
        let config = MrzScannerConfig(struggleTimeout: .seconds(4), scanTimeout: .seconds(30))
        #expect(config.struggleTimeout == .seconds(4))
        #expect(config.scanTimeout == .seconds(30))
    }
}
