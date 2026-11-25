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

// Making the key. From a scanned document (the result of the scanner), from the three values a person
// typed, from the printed values with their check digits, or from the card access number. Every
// one throws a Swift error that names the field and the problem, never the value.
func makeKeys(scanned: ParseResult) throws -> [ChipAccessKey] {
    // Text from a text field: let the SDK trim the spaces and upper-case the letters, and see what it did.
    let typed = ChipAccessKey.normalizeTypedFields(documentNumber: " l898902c3", dateOfBirth: "740812", dateOfExpiry: "120415")
    if typed.wasChanged { print("tidied: \(typed.changedFields.map(\.rawValue))") } // field names, never values
    return [
        try ChipAccessKey.from(parse: scanned),
        try ChipAccessKey.fromTypedFields(
            documentNumber: typed.documentNumber, dateOfBirth: typed.dateOfBirth, dateOfExpiry: typed.dateOfExpiry),
        try ChipAccessKey.fromMrz(
            documentNumber: "L898902C3", documentNumberCheckDigit: "6",
            dateOfBirth: "740812", dateOfBirthCheckDigit: "2",
            dateOfExpiry: "120415", dateOfExpiryCheckDigit: "9"
        ),
        try ChipAccessKey.fromCan("123456"),
    ]
}

// Compare the chip's DG1 with the MRZ the scanner read. The answer is a fact per field, never a value.
func readAndCompare(scanned: ParseResult) async throws -> [PrintedFieldComparison] {
    let key = try ChipAccessKey.from(parse: scanned)
    let options = try ChipReadOptions.Builder(accessKey: key).printedDocument(parse: scanned).build()
    let finish = await ChipReading.start(options: options).ending
    let check = finish.read?.checks.compactMap(\.printedComparison).first
    return check?.fields ?? [] // each field: .same, .different or .notComparable
}

// The full use: a scanned document as the key, root certificates from a file, a check time, custom
// texts on the system sheet, settings, a progress bar, and every outcome handled.
@MainActor
final class ChipReadModel: ObservableObject {
    @Published var bar = ""
    @Published var message = "Hold the phone on the document"
    private var reading: ChipReading?

    /// Ask first: `nil` means a read can start on this device.
    var unavailable: NfcUnavailable.Reason? { ChipReading.availability }

    func read(scanned: ParseResult, rootsFile: URL) async {
        do {
            // A key is used up by one read: build a new one for every read.
            let key = try ChipAccessKey.from(parse: scanned)
            // A file URL from the document picker works as it is: access is started and stopped for you.
            let roots = TrustAnchors.shared.load(contentsOf: rootsFile)
            let options = try ChipReadOptions.Builder(accessKey: key)
                .dataGroups([1, 2])
                .trustAnchors(roots)
                .printedDocument(parse: scanned) // adds the printed-versus-chip comparison
                .checkTime(Date()) // without it the validity checks are reported as not run
                .build()
            let texts = ChipReadTexts(
                text: { snapshot in
                    if case .waitingForDocument = snapshot.phase { return "Hold the top of the phone on the document" }
                    return nil // the built-in line for every other update
                },
                ending: { _ in nil }
            )
            let reading = ChipReading.start(
                options: options,
                texts: texts,
                settings: ChipReadSettings(linkLoss: .resume(2), commandTimeout: 6)
            )
            self.reading = reading
            // Leaving the screen cancels this task, and the handler cancels the read.
            await withTaskCancellationHandler {
                for await update in reading.updates {
                    bar = ChipReadTexts.progressBar(for: update.progress)
                    if case .linkLost(let restartsLeft) = update.phase {
                        message = "Connection lost, \(restartsLeft) tries left"
                    }
                }
            } onCancel: {
                reading.cancel()
            }
            let finish = await reading.ending
            message = Self.describe(finish.outcome) + " (attempts: \(finish.attempts), \(finish.progress.percent)%)"
        } catch {
            message = "The read could not be set up"
        }
    }

    func stop() { reading?.cancel() }

    private static func describe(_ outcome: ChipReadOutcome) -> String {
        switch outcome {
        case .complete: return "Done"
        case .partial: return "Some files could not be read"
        case .failed(let error, _): return "The read failed (\(error.code))"
        case .keyNotAccepted: return "The chip did not accept the key"
        case .keyRejected(let error): return "The key was refused before the read (\(error.code))"
        case .cancelled(let byPerson): return byPerson ? "Cancelled" : "Stopped by the app"
        case .endedBySystem: return "The system ended the session"
        case .notStarted: return "NFC is not available"
        case .unknown: return "The read ended in a way this version does not know"
        }
    }
}
