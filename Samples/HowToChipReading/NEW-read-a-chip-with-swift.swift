// NEW sample for a documentation page that does not exist yet (TES-346): "Read a chip on iOS, headless".
// It has no region markers, so scripts/check-samples.py ignores it until the page exists; then add
// `// region TES-A-NNN block N` lines and the page id.
import SwiftUI
import Tessera
import TesseraKit

// The shortest use: three lines, then branch on the one ending.
func readChipShortest(key: ChipAccessKey) async throws -> ChipRead? {
    let options = try ChipReadOptions.Builder(accessKey: key).build()
    let reading = ChipReading.start(options: options)
    if case .complete(let read) = await reading.ending.outcome { return read }
    return nil
}

// Making the key from the printed values, with Swift errors.
func makeKeys() throws -> [ChipAccessKey] {
    [
        try ChipAccessKey.fromMrz(
            documentNumber: "L898902C3", documentNumberCheckDigit: "6",
            dateOfBirth: "740812", dateOfBirthCheckDigit: "2",
            dateOfExpiry: "120415", dateOfExpiryCheckDigit: "9"
        ),
        try ChipAccessKey.fromCan("123456"),
    ]
}

// A progress bar and every ending handled.
@MainActor
final class ChipReadModel: ObservableObject {
    @Published var fraction = 0.0
    @Published var message = "Hold the phone on the document"
    private var reading: ChipReading?

    func read(key: ChipAccessKey) async {
        do {
            let options = try ChipReadOptions.Builder(accessKey: key).build()
            let reading = ChipReading.start(options: options)
            self.reading = reading
            // Leaving the screen cancels this task, and the handler cancels the read.
            await withTaskCancellationHandler {
                for await update in reading.updates {
                    fraction = update.progress.fraction
                    if case .linkLost(let restartsLeft) = update.phase {
                        message = "Connection lost, \(restartsLeft) tries left"
                    }
                }
            } onCancel: {
                reading.cancel()
            }
            message = Self.describe(await reading.ending.outcome)
        } catch {
            message = "The read could not be set up"
        }
    }

    func stop() { reading?.cancel() }

    private static func describe(_ outcome: ChipReadOutcome) -> String {
        switch outcome {
        case .complete: return "Done"
        case .partial: return "Some files could not be read"
        case .failed: return "The read failed"
        case .keyNotAccepted: return "The chip did not accept the key"
        case .keyRejected: return "The key has a wrong check digit"
        case .cancelled(let byPerson): return byPerson ? "Cancelled" : "Stopped by the app"
        case .endedBySystem: return "The system ended the session"
        case .notStarted: return "NFC is not available"
        case .unknown: return "The read ended in a way this version does not know"
        }
    }
}
