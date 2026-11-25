import Foundation
import Testing
import Tessera
@testable import TesseraKit

/// The `enum` mirrors. Swift cannot build the Kotlin cases that carry values (`ReadingFile`,
/// `LinkLost`, `WaitingForDocument`, `Complete` and the like), so the value conversions behind them are
/// separate functions that take plain values, and are tested here with real boxed Kotlin numbers. The
/// type switch itself is covered by every case that can be had (the shared objects and the real
/// `NotStarted` ending); the cases that carry values are covered by the Kotlin tests and by device runs.
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

    @Test func waitingForDocumentTurnsMillisecondsIntoSeconds() {
        #expect(ChipReadPhase.waiting(waitedMillis: 0) == .waitingForDocument(waited: 0))
        #expect(ChipReadPhase.waiting(waitedMillis: 2_500) == .waitingForDocument(waited: 2.5))
    }

    @Test func readingFileUnboxesTheDataGroupAndTheTotal() {
        #expect(
            ChipReadPhase.reading(dataGroup: KotlinInt(int: 2), bytesRead: 300, bytesTotal: KotlinInt(int: 4_000))
                == .readingFile(dataGroup: 2, bytesRead: 300, bytesTotal: 4_000))
    }

    @Test func readingFileKeepsNilForAFileThatIsNotADataGroupAndAnUnknownSize() {
        #expect(
            ChipReadPhase.reading(dataGroup: nil, bytesRead: 0, bytesTotal: nil)
                == .readingFile(dataGroup: nil, bytesRead: 0, bytesTotal: nil))
    }

    @Test func linkLostCarriesTheRestartsLeft() {
        #expect(ChipReadPhase.lost(restartsLeft: 2) == .linkLost(restartsLeft: 2))
        #expect(ChipReadPhase.lost(restartsLeft: 0) == .linkLost(restartsLeft: 0))
    }

    @Test func theRealStatesOfARealReadMapToACaseTheEnumKnows() async throws {
        let real = try await RealReading.sample()
        for snapshot in real.updates {
            #expect(snapshot.phase != .unknown)
            #expect(snapshot.phase == snapshot.raw?.state.phase)
            #expect(snapshot.phase == snapshot.raw?.phase)
        }
    }

    @Test func aSnapshotCarriesTheValuesOfItsKotlinUpdate() async throws {
        let real = try await RealReading.sample()
        for snapshot in real.updates {
            let raw = try #require(snapshot.raw)
            #expect(snapshot.attempt == Int(raw.attempt))
            #expect(snapshot.maxAttempts == Int(raw.maxAttempts))
            #expect(snapshot.fraction == raw.progress.fraction)
            #expect(snapshot.percent == Int(raw.progress.percent))
            #expect(snapshot.progress.filesDone == Int(raw.progress.filesDone))
        }
    }

    @Test func theRealNotStartedEndingMapsAndKeepsItsRawObject() async throws {
        let real = try await RealReading.sample()
        guard case .notStarted = real.ending.outcome else {
            Issue.record("expected notStarted on a simulator without NFC, got \(real.ending.outcome)")
            return
        }
        #expect(real.rawEnding is ChipReadEnding.NotStarted)
    }

    @Test func theFinishCarriesAttemptsAndProgressNextToTheOutcome() async throws {
        let real = try await RealReading.sample()
        let raw = real.rawEnding
        #expect(real.ending.attempts == Int(raw.attempts))
        #expect(real.ending.progress.percent == Int(raw.progress.percent))
        #expect(real.ending.progress.fraction == raw.progress.fraction)
        #expect(real.ending.read == nil)
        #expect(real.ending.outcome.error == nil)
    }

    @Test func anObjectThatIsNotAKnownEndingIsUnknown() {
        guard case .unknown = ChipReadOutcome.from(NSObject()) else {
            Issue.record("expected unknown")
            return
        }
    }

    @Test func percentIsAnIntAndFractionIsADouble() async throws {
        let real = try await RealReading.sample()
        let progress = real.rawEnding.progress
        #expect(progress.percentInt == Int(progress.percent))
        #expect(progress.fraction >= 0 && progress.fraction <= 1)
    }

    @Test func aProgressFromSwiftValuesIsClamped() {
        #expect(ChipProgress(fraction: 1.7).fraction == 1)
        #expect(ChipProgress(fraction: -1).fraction == 0)
        #expect(ChipProgress(fraction: .nan).fraction == 0)
        #expect(ChipProgress(fraction: 0.456).percent == 45)
    }

    @Test func availabilityIsTheReasonARealReadWouldGive() async throws {
        let real = try await RealReading.sample()
        // A simulator has no NFC: the read does not start, and the same reason is available up front.
        guard case .notStarted(let reason) = real.ending.outcome else {
            Issue.record("expected notStarted")
            return
        }
        #expect(ChipReading.availability === reason)
    }
}
