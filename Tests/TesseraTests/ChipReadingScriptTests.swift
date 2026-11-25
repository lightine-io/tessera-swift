import Foundation
import Testing
@testable import Tessera

/// The test aid `ChipReading.makeForTesting`, and with it the phase and outcome values that Swift
/// cannot get from the Kotlin reader: readingFile, linkLost, waitingForDocument, and the endings Swift can
/// build. A `complete` ending needs a `ChipRead`, which Swift cannot build: see the note in the test
/// for `complete`.
struct ChipReadingScriptTests {
    private let phases: [ChipReadPhase] = [
        .starting,
        .waitingForDocument(waited: 1.5),
        .documentFound,
        .noAnswerYet(tries: 2),
        .renewingSession(renewal: 1),
        .readingFile(dataGroup: 1, bytesRead: 10, bytesTotal: 100),
        .linkLost(restartsLeft: 1),
        .readingFile(dataGroup: nil, bytesRead: 0, bytesTotal: nil),
        .checkingFiles,
    ]

    @Test func theScriptedPhasesArriveInOrderThenTheEnding() async {
        let reading = ChipReading.makeForTesting(
            phases: phases, outcome: .cancelled(byPerson: true), attempts: 2, finalProgress: ChipProgress(fraction: 0.8))
        var seen: [ChipReadPhase] = []
        var lastFraction = 0.0
        for await snapshot in reading.updates {
            seen.append(snapshot.phase)
            #expect(snapshot.fraction >= lastFraction) // never goes back
            lastFraction = snapshot.fraction
            #expect(snapshot.attempt == 2)
            #expect(snapshot.raw == nil)
        }
        #expect(seen == phases)
        #expect(abs(lastFraction - 0.8) < 1e-9)
        let finish = await reading.ending
        guard case .cancelled(let byPerson) = finish.outcome else {
            Issue.record("expected cancelled, got \(finish.outcome)")
            return
        }
        #expect(byPerson)
        #expect(finish.attempts == 2)
        #expect(finish.progress.fraction == 0.8)
        #expect(finish.raw == nil)
    }

    @Test(arguments: [TimeInterval.nan, .infinity, -.infinity, -1])
    func aDelayThatIsNotAUsableNumberCountsAsNoDelay(delay: TimeInterval) async {
        let ending = ChipReadFinish(outcome: .cancelled(byPerson: true), attempts: 1, progress: .zero)
        let reading = ChipReading.makeForTesting(updates: [], ending: ending, delay: delay)
        #expect(await reading.ending.attempts == 1)
    }

    @Test func switchOverTheScriptedPhasesReachesEveryValueCase() async {
        let reading = ChipReading.makeForTesting(phases: phases, outcome: .cancelled(byPerson: false))
        var waited: TimeInterval?
        var file: (Int?, Int, Int?)?
        var restarts: Int?
        var tries: Int?
        for await snapshot in reading.updates {
            switch snapshot.phase {
            case .waitingForDocument(let time): waited = time
            case .readingFile(let group, let read, let total): file = file ?? (group, read, total)
            case .linkLost(let left): restarts = left
            case .noAnswerYet(let count): tries = count
            default: break
            }
        }
        #expect(waited == 1.5)
        #expect(file?.0 == 1 && file?.1 == 10 && file?.2 == 100)
        #expect(restarts == 1)
        #expect(tries == 2)
    }

    @Test func theEndingsSwiftCanBuildMapToTheirOutcomes() async throws {
        let denied = ChipAccessDenied(protocol: .bac, reason: .keyNotMatched, statusWord: KotlinInt(int: 0x6300))
        let mismatch = ChipKeyCheckDigitMismatch(fields: [.documentNumber])
        let cases: [(ChipReadOutcome, String)] = [
            (.keyNotAccepted(denied), "keyNotAccepted"),
            (.keyRejected(mismatch), "keyRejected"),
            (.failed(NfcTagLost(), access: nil), "failed"),
            (.endedBySystem(NfcTimeout(timeoutMillis: nil, limit: .session)), "endedBySystem"),
            (.notStarted(.notSupported), "notStarted"),
            (.cancelled(byPerson: false), "cancelled"),
        ]
        for (outcome, label) in cases {
            let reading = ChipReading.makeForTesting(phases: [.starting], outcome: outcome)
            let finish = await reading.ending
            switch (finish.outcome, label) {
            case (.keyNotAccepted(let error), "keyNotAccepted"):
                #expect(error === denied)
                #expect(finish.outcome.error?.statusWordInt == 0x6300)
                #expect(finish.outcome.error?.code == denied.code)
            case (.keyRejected(let error), "keyRejected"): #expect((error as? ChipKeyCheckDigitMismatch)?.fields == [.documentNumber])
            case (.failed(let error, let access), "failed"):
                #expect(error is NfcTagLost)
                #expect(access == nil)
                #expect(finish.outcome.error?.statusWordInt == nil)
            case (.endedBySystem(let error), "endedBySystem"): #expect(error is NfcTimeout)
            case (.notStarted(let reason), "notStarted"): #expect(reason === NfcUnavailable.Reason.notSupported)
            case (.cancelled(let byPerson), "cancelled"): #expect(!byPerson)
            default: Issue.record("\(label) mapped to \(finish.outcome)")
            }
            #expect(finish.read == nil)
        }
        // Note: `.complete` and `.partial` carry a `ChipRead`, which Swift cannot build (no public
        // constructor). The `complete` mapping is the one line `ChipReadEnding.Complete` -> `.complete(read)`
        // in `ChipReadOutcome.from`; it is covered by the Kotlin tests and by device runs.
    }

    @Test func aDelayedScriptCanBeCancelledAndThenEndsAsCancelledByTheApp() async throws {
        let reading = ChipReading.makeForTesting(
            phases: phases, outcome: .notStarted(.notSupported), delay: 0.05)
        reading.cancel()
        let finish = await reading.ending
        guard case .cancelled(let byPerson) = finish.outcome else {
            Issue.record("expected cancelled, got \(finish.outcome)")
            return
        }
        #expect(!byPerson)
        var count = 0
        for await _ in reading.updates { count += 1 }
        #expect(count <= phases.count)
    }

    @Test func aDelayedScriptPlaysToTheEnd() async {
        let reading = ChipReading.makeForTesting(phases: [.starting, .connecting], outcome: .notStarted(.disabled), delay: 0.01)
        var count = 0
        for await _ in reading.updates { count += 1 }
        #expect(count == 2)
        guard case .notStarted = await reading.ending.outcome else {
            Issue.record("expected notStarted")
            return
        }
    }

    @Test func snapshotsAndFinishCrossTasks() async {
        // Compiles only because the two types are Sendable (checked by the compiler in Swift 6 mode).
        let reading = ChipReading.makeForTesting(phases: [.starting], outcome: .cancelled(byPerson: true))
        let snapshots = await Task { () -> [ChipReadSnapshot] in
            var all: [ChipReadSnapshot] = []
            for await snapshot in reading.updates { all.append(snapshot) }
            return all
        }.value
        let finish = await Task { await reading.ending }.value
        #expect(snapshots.count == 1)
        guard case .cancelled = finish.outcome else { Issue.record("expected cancelled"); return }
    }
}
