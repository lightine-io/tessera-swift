import Testing
@testable import TesseraUI

/// Host tests for the "struggling" hint timer (TES-151): the hint shows on the timer alone, with no text
/// ever seen by the recognizer, and not before the timeout. Drives the timer directly through
/// ``ScannerModel/armStruggleTimeout()`` (the camera normally arms it) — no camera, no frames.
@MainActor
struct ScannerModelStruggleHintTests {
    private func makeModel(timeout: Duration?) -> ScannerModel {
        ScannerModel(config: MrzScannerConfig(struggleTimeout: timeout), onResult: { _ in })
    }

    private func isStruggling(_ model: ScannerModel) -> Bool {
        if case let .scanning(struggling, _) = model.state { return struggling }
        return false
    }

    @Test func hintAppearsAfterTheTimeoutWithNoTextEverSeen() async throws {
        let model = makeModel(timeout: .milliseconds(100))
        model.armStruggleTimeout()
        try await Task.sleep(for: .milliseconds(600))
        #expect(isStruggling(model), "the hint shows on the timer alone, even if the recognizer never returned text")
    }

    @Test func hintDoesNotAppearBeforeTheTimeout() async throws {
        let model = makeModel(timeout: .seconds(30))
        model.armStruggleTimeout()
        try await Task.sleep(for: .milliseconds(300))
        #expect(!isStruggling(model))
    }

    @Test func aNilTimeoutNeverShowsTheHint() async throws {
        let model = makeModel(timeout: nil)
        model.armStruggleTimeout()
        try await Task.sleep(for: .milliseconds(300))
        #expect(!isStruggling(model))
    }
}
