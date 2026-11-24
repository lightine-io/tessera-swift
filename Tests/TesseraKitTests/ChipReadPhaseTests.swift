import Foundation
import Testing
import Tessera
@testable import TesseraKit

/// The `enum` mirrors. Swift code cannot build the Kotlin cases that carry values (`ReadingFile`,
/// `LinkLost`, `Complete` and the like), so those are covered by the Kotlin tests and by device runs.
/// Here: every case that can be had (the shared objects, and the real `NotStarted` ending), and the
/// fallback to `unknown` for anything else.
struct ChipReadPhaseTests {
    @Test func everyStateWithoutValuesMapsToItsCase() {
        #expect(ChipReadState.Starting.shared.phase == .starting)
        #expect(ChipReadState.Connecting.shared.phase == .connecting)
        #expect(ChipReadState.DocumentFound.shared.phase == .documentFound)
        #expect(ChipReadState.CheckingFiles.shared.phase == .checkingFiles)
        #expect(ChipReadState.Stopping.shared.phase == .stopping)
    }

    @Test func anObjectThatIsNotAKnownStateIsUnknown() {
        #expect(ChipReadPhase.from(NSObject()) == .unknown)
        #expect(ChipReadPhase.from("not a state") == .unknown)
    }

    @Test func theRealStatesOfARealReadMapToACaseTheEnumKnows() async throws {
        let real = try await RealReading.sample()
        for update in real.updates {
            #expect(update.phase != .unknown)
            #expect(update.phase == update.state.phase)
        }
    }

    @Test func theRealNotStartedEndingMapsAndKeepsItsRawObject() async throws {
        let real = try await RealReading.sample()
        guard case .notStarted = real.ending.outcome else {
            Issue.record("expected notStarted on a simulator without NFC, got \(real.ending.outcome)")
            return
        }
        #expect(real.ending is ChipReadEnding.NotStarted)
    }

    @Test func anObjectThatIsNotAKnownEndingIsUnknown() {
        guard case .unknown = ChipReadOutcome.from(NSObject()) else {
            Issue.record("expected unknown")
            return
        }
    }

    @Test func percentIsAnIntAndFractionIsADouble() async throws {
        let real = try await RealReading.sample()
        let progress = real.ending.progress
        #expect(progress.percentInt == Int(progress.percent))
        #expect(progress.fraction >= 0 && progress.fraction <= 1)
    }
}
