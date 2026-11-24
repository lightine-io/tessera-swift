import Foundation
import Testing
@testable import TesseraUI

/// Host tests for the "struggling" hint timer (TES-151): the hint shows on the timer alone, with no text
/// ever seen by the recognizer, and not before the timeout. Drives the timer directly through
/// ``ScannerModel/armStruggleTimeout()`` (the camera normally arms it) — no camera, no frames. Times are in
/// seconds (the iOS 15 form of the setting).
@MainActor
struct ScannerModelStruggleHintTests {
    private func makeModel(timeout: TimeInterval?) -> ScannerModel {
        ScannerModel(config: MrzScannerConfig(struggleTimeoutInterval: timeout), onResult: { _ in })
    }

    private func isStruggling(_ model: ScannerModel) -> Bool {
        if case let .scanning(struggling, _, _) = model.state { return struggling }
        return false
    }

    /// Polls (main actor) until the hint shows or `limit` seconds pass, so a slow runner cannot flake the test.
    private func waitForHint(_ model: ScannerModel, limit: TimeInterval = 120) async throws -> Bool {
        let deadline = Date().addingTimeInterval(limit)
        while Date() < deadline {
            if isStruggling(model) { return true }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        return isStruggling(model)
    }

    @Test func hintAppearsAfterTheTimeoutWithNoTextEverSeen() async throws {
        let model = makeModel(timeout: 0.1)
        model.armStruggleTimeout()
        let shown = try await waitForHint(model)
        withExtendedLifetime(model) {}
        #expect(shown, "the hint shows on the timer alone, even if the recognizer never returned text")
    }

    @Test func hintDoesNotAppearBeforeTheTimeout() async throws {
        let model = makeModel(timeout: 30)
        model.armStruggleTimeout()
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(!isStruggling(model))
    }

    @Test func aNilTimeoutNeverShowsTheHint() async throws {
        let model = makeModel(timeout: nil)
        model.armStruggleTimeout()
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(!isStruggling(model))
    }
}
