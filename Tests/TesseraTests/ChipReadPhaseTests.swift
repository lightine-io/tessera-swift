import Foundation
import Testing
@testable import Tessera
import TesseraCore

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

    @Test func noAnswerYetCarriesTheTries() {
        #expect(ChipReadPhase.noAnswer(tries: 3) == .noAnswerYet(tries: 3))
        #expect(ChipReadPhase.noAnswer(tries: 1) != .noAnswerYet(tries: 2))
    }

    @Test func renewingSessionCarriesTheRenewal() {
        #expect(ChipReadPhase.renewing(renewal: 2) == .renewingSession(renewal: 2))
        #expect(ChipReadPhase.renewing(renewal: 1) != .renewingSession(renewal: 2))
    }

    @Test func readinessMapsFromTheKotlinValues() {
        #expect(Tessera.ChipReadReadiness(TesseraCore.ChipReadReadiness.Ready.shared) == .ready)
        #expect(Tessera.ChipReadReadiness(TesseraCore.ChipReadReadiness.ReadInProgress.shared) == .readInProgress)
        #expect(Tessera.ChipReadReadiness.notYet(remainingMillis: 1_500) == .notYet(remaining: 1.5))
        #expect(Tessera.ChipReadReadiness.notYet(remainingMillis: 1) != .ready)
    }

    @Test func readinessNowIsReadyOrExplainsWhy() {
        // A simulator has no NFC: the same reason as `availability`.
        switch ChipReading.readiness {
        case .unavailable(let reason): #expect(ChipReading.availability === reason)
        case .ready, .notYet, .readInProgress, .unknown: #expect(ChipReading.availability == nil)
        }
    }

    @Test func theReadinessStreamStartsWithTheValueNow() async {
        var first: Tessera.ChipReadReadiness?
        for await value in ChipReading.readinessUpdates {
            first = value
            break // ending the loop ends the stream, which removes the Kotlin listener
        }
        #expect(first == ChipReading.readiness)
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

    @Test func theReadinessStreamLetsOnlyChangesThrough() {
        let changes = ReadinessChanges()
        #expect(changes.isNew(.ready))
        #expect(!changes.isNew(.ready))
        #expect(changes.isNew(.readInProgress))
        #expect(!changes.isNew(.readInProgress))
        #expect(changes.isNew(.notYet(remaining: 1.5)))
        #expect(!changes.isNew(.notYet(remaining: 1.5)))
        #expect(changes.isNew(.notYet(remaining: 0.5)))
        #expect(changes.isNew(.unavailable(.notSupported)))
        #expect(!changes.isNew(.unavailable(.notSupported)))
        #expect(changes.isNew(.unavailable(.disabled)))
        #expect(changes.isNew(.ready))
    }

    @Test func theFinishCarriesTheSystemCodeOfItsKotlinEnding() async throws {
        let real = try await RealReading.sample()
        #expect(real.ending.systemCode == real.rawEnding.systemCode.map { Int($0.int32Value) })
        #expect(ChipReadFinish(outcome: .notStarted(.notEligible)).systemCode == nil)
        #expect(ChipReadFinish(outcome: .notStarted(.notEligible), systemCode: 7).systemCode == 7)
    }

    @Test func aScriptedReadKeepsTheSystemCodeOfItsEnding() async {
        let reading = ChipReading.makeForTesting(
            updates: [], ending: ChipReadFinish(outcome: .notStarted(.accessNotAnswered), systemCode: 8))
        let finish = await reading.ending
        #expect(finish.systemCode == 8)
    }

    @Test func aTimeoutSaysWhichLimitPassed() {
        let outcome = ChipReadOutcome.endedBySystem(NfcTimeout(timeoutMillis: KotlinLong(value: 60_000), limit: .session))
        let timeout = outcome.error as? NfcTimeout
        #expect(timeout?.limit == NfcTimeout.Limit.session)
        #expect(timeout?.code == "timeout.session")
        #expect(!outcome.isNoAnswer)
        #expect((NfcTimeout(timeoutMillis: nil, limit: .command) as ChipError).code == "timeout.command")
        #expect(NfcTimeout(timeoutMillis: nil, limit: .waitForDocument).code == "timeout.wait-for-document")
    }

    @Test func theNewReasonsReachTheOutcomeUnchanged() async {
        let reasons: [NfcUnavailable.Reason] = [
            .tagReadingDisabled, .commandTooLong, .notEligible, .accessNotAnswered, .unexpectedFault,
        ]
        for reason in reasons {
            let finish = await ChipReading.makeForTesting(phases: [.starting], outcome: .notStarted(reason)).ending
            guard case .notStarted(let got) = finish.outcome else {
                Issue.record("expected notStarted for \(reason)")
                continue
            }
            #expect(got === reason)
        }
    }

    // MARK: the readiness stream, with a fake listener seam

    /// Counts adds and removes of the Kotlin listener, and lets a test send changes by hand.
    private final class FakeReadinessSource: @unchecked Sendable {
        private let lock = NSLock()
        private var listener: TesseraCore.ChipReadReadinessListener?
        private var removed = 0
        private var added = 0
        var now: Tessera.ChipReadReadiness = .ready
        var removeCount: Int { lock.withLock { removed } }
        var addCount: Int { lock.withLock { added } }

        func stream() -> AsyncStream<Tessera.ChipReadReadiness> {
            ChipReading.makeReadinessStream(
                addListener: { listener in
                    self.lock.withLock { self.listener = listener; self.added += 1 }
                    return FakeRegistration { self.lock.withLock { self.removed += 1 } }
                },
                current: { self.now })
        }

        func send(_ value: TesseraCore.ChipReadReadiness) {
            listener?.onReadinessChanged(readiness: value)
        }
    }

    private final class FakeRegistration: NSObject, TesseraCore.ChipReadReadinessRegistration, @unchecked Sendable {
        private let onRemove: @Sendable () -> Void
        init(_ onRemove: @escaping @Sendable () -> Void) { self.onRemove = onRemove }
        func remove() { onRemove() }
    }

    @Test func aSlowConsumerSeesEveryChangeOnceAndNeverTheSameValueTwice() async {
        let source = FakeReadinessSource()
        let stream = source.stream()
        // The consumer has not started: the changes pile up, with repeats between them.
        source.send(TesseraCore.ChipReadReadiness.ReadInProgress.shared)
        source.send(TesseraCore.ChipReadReadiness.ReadInProgress.shared)
        source.send(TesseraCore.ChipReadReadiness.Ready.shared)
        source.send(TesseraCore.ChipReadReadiness.ReadInProgress.shared)
        source.send(TesseraCore.ChipReadReadiness.Ready.shared)
        source.send(TesseraCore.ChipReadReadiness.Ready.shared)
        var seen: [Tessera.ChipReadReadiness] = []
        for await value in stream {
            seen.append(value)
            if seen.count == 5 { break }
        }
        #expect(seen == [.ready, .readInProgress, .ready, .readInProgress, .ready])
    }

    @Test func aStreamThatIsNeverIteratedRemovesItsListenerWhenDropped() {
        let source = FakeReadinessSource()
        do {
            let stream = source.stream()
            _ = stream
            #expect(source.addCount == 1)
            #expect(source.removeCount == 0)
        }
        #expect(source.removeCount == 1)
    }

    @Test func aStreamEndedByItsLoopRemovesItsListenerOnce() async {
        let source = FakeReadinessSource()
        for await _ in source.stream() { break }
        #expect(source.removeCount == 1)
    }
}
