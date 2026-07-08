import Testing
@testable import TesseraUI

/// Scaffold-level coverage of the frozen 0.5.0 public surface: config defaults and the result/dismiss
/// shapes. Screen behavior is tested in the later iOS slices as the screens land.
struct PublicSurfaceTests {
    @Test func configDefaultsMatchTheContract() {
        let config = MrzScannerConfig()
        #expect(config.enabledMethods == [.camera, .manualEntry]) // saved-image opt-in, off by default
        #expect(config.reviewMode == .review)
        #expect(config.showTorchButton == true)
        #expect(config.torchOnByDefault == false)
        #expect(config.struggleTimeout == .seconds(10))
        #expect(config.scanTimeout == nil) // never times out by default
        #expect(config.theme.brandColor == nil)
        #expect(config.theme.darkMode == .auto)
        #expect(config.onRequestPermission == nil)
    }

    @Test func configPassesValuesThroughVerbatim() {
        let config = MrzScannerConfig(
            enabledMethods: [.camera, .savedImage, .manualEntry],
            reviewMode: .instantReturn,
            showTorchButton: false,
            torchOnByDefault: true,
            struggleTimeout: .seconds(3),
            scanTimeout: .seconds(30),
            theme: MrzScannerTheme(darkMode: .on)
        )
        #expect(config.enabledMethods.contains(.savedImage))
        #expect(config.reviewMode == .instantReturn)
        #expect(config.showTorchButton == false)
        #expect(config.torchOnByDefault == true)
        #expect(config.struggleTimeout == .seconds(3))
        #expect(config.scanTimeout == .seconds(30))
        #expect(config.theme.darkMode == .on)
    }

    @Test func dismissReasonCasesAreDistinct() {
        let all: Set<DismissReason> = [.userDismissed, .timedOut, .cameraUnavailable, .permissionDenied]
        #expect(all.count == 4)
    }

    /// Both timeouts express "never" as `nil` (Swift `Duration` has no infinity sentinel) — a config that
    /// disables both the struggle hint and the scan deadline is accepted verbatim (TES-85).
    @Test func timeoutsCanBeDisabledWithNil() {
        let config = MrzScannerConfig(struggleTimeout: nil, scanTimeout: nil)
        #expect(config.struggleTimeout == nil) // never struggle
        #expect(config.scanTimeout == nil) // never time out
    }
}
