// Compile-only guard (TES-346): an app that writes only `import Tessera` and gets the whole API: the
// generated core types and the Swift chip-reading layer. `ChipReadReadiness` exists in both modules;
// unqualified it must be the Swift enum (`.notYet(remaining:)` exists only there), with no ambiguity.
// Not a sample of any page; nothing ships.
import Foundation
import Tessera

enum OneImport {
    static func parse(_ text: String) -> ParseResult {
        let now = KotlinInstant.companion.fromEpochMilliseconds(epochMilliseconds: 1_795_219_200_000)
        return MrzParser.shared.parse(input: text, referenceTime: now)
    }

    static func canPressRead() -> Bool {
        let readiness: ChipReadReadiness = ChipReading.readiness
        switch readiness {
        case .ready: return true
        case .notYet(let remaining): return remaining <= 0
        case .readInProgress, .unavailable, .unknown: return false
        }
    }

    static func watchReadiness() async -> ChipReadReadiness? {
        for await value in ChipReading.readinessUpdates { return value }
        return nil
    }

    static func read(scanned: ParseResult) async throws -> String {
        let key = try ChipAccessKey.from(parse: scanned)
        let options = try ChipReadOptions.Builder(accessKey: key).dataGroups([1, 2]).build()
        let reading = ChipReading.start(options: options)
        for await update in reading.updates {
            if case .linkLost(let restartsLeft) = update.phase { _ = restartsLeft }
        }
        let finish: ChipReadFinish = await reading.ending
        switch finish.outcome {
        case .complete(let read): return "complete \(read.files.count)"
        case .notStarted(let reason): return "not started \(reason.name)"
        default: return "other"
        }
    }

    // The generated type is still reachable by its module name when an app needs it.
    static func kotlinReadiness() -> TesseraCore.ChipReadReadiness {
        CoreNfcChipRead.companion.readiness()
    }
}
