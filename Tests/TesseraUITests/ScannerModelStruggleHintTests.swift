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

    /// Polls (main actor) until the hint shows or `limit` passes, so a slow runner cannot flake the test.
    private func waitForHint(_ model: ScannerModel, limit: Duration = .seconds(30)) async throws -> Bool {
        let deadline = ContinuousClock.now + limit
        while ContinuousClock.now < deadline {
            if isStruggling(model) { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return isStruggling(model)
    }

    @Test func hintAppearsAfterTheTimeoutWithNoTextEverSeen() async throws {
        let model = makeModel(timeout: .milliseconds(100))
        model.armStruggleTimeout()
        let shown = try await waitForHint(model)
        withExtendedLifetime(model) {}
        #expect(shown, "the hint shows on the timer alone, even if the recognizer never returned text")
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
