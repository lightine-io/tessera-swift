// Sample for TES-A-168 "Read a passport chip on iPhone".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-168 block 1: Info.plist and entitlements (property list text, not Swift)

// region TES-A-168 block 2
import Tessera
// endregion

// region TES-A-168 block 3
func makeKey(scanned: ParseResult) -> ChipAccessKey? {
    do {
        // A key is used up by one read: build a new one for every read.
        return try ChipAccessKey.from(parse: scanned)
    } catch let error as ChipAccessKeyError {
        // The error names the field and the problem, never the value.
        print("No key: \(error)")
        return nil
    } catch {
        return nil
    }
}
// endregion

// region TES-A-168 block 4
func loadRoots(from file: URL) -> TrustAnchorLoad {
    // A file URL from the document picker works as it is.
    let roots = TrustAnchors.shared.load(contentsOf: file)
    if let problem = roots.problemName { print("Roots: \(problem), unreadable: \(roots.unreadableCount)") }
    return roots
}
// endregion

// region TES-A-168 block 5
func makeOptions(key: ChipAccessKey, roots: TrustAnchorLoad, scanned: ParseResult) throws -> ChipReadOptions {
    try ChipReadOptions.Builder(accessKey: key)
        .dataGroups([1, 2])
        .trustAnchors(roots)
        .printedDocument(parse: scanned)
        .checkTime(Date())
        .build()
}
// endregion

// region TES-A-168 block 6
func readOnce(options: ChipReadOptions) async -> ChipRead? {
    let reading = ChipReading.start(options: options)
    let finish = await reading.ending
    return finish.read
}
// endregion

// region TES-A-168 block 7
func showProgress(of reading: ChipReading) async {
    for await update in reading.updates {
        print(ChipReadTexts.progressBar(for: update.progress))
        if case .linkLost(let restartsLeft) = update.phase {
            print("Connection lost, \(restartsLeft) tries left")
        }
    }
}
// endregion

// region TES-A-168 block 8
func describe(_ outcome: ChipReadOutcome) -> String {
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
// endregion

// region TES-A-168 block 9
func readUntilLeft(options: ChipReadOptions) async -> ChipReadFinish {
    let reading = ChipReading.start(options: options)
    // Cancelling the task cancels the read.
    return await withTaskCancellationHandler {
        await reading.ending
    } onCancel: {
        reading.cancel()
    }
}
// endregion

// region TES-A-168 block 10
func startWithSettings(options: ChipReadOptions) -> ChipReading {
    let texts = ChipReadTexts(
        text: { snapshot in
            if case .waitingForDocument = snapshot.phase { return "Hold the top of the phone on the document" }
            return nil // the built-in line for every other update
        },
        ending: { _ in nil }
    )
    let settings = ChipReadSettings(linkLoss: .resume(2), commandTimeout: 6)
    return ChipReading.start(options: options, texts: texts, settings: settings)
}
// endregion

// region TES-A-168 block 11
func makeKeyFromTypedValues(documentNumber: String, dateOfBirth: String, dateOfExpiry: String) -> ChipAccessKey? {
    // Dates are six digits, YYMMDD. The check digits are worked out for you.
    // Normalising trims spaces and upper-cases letters; nothing else changes.
    let typed = ChipAccessKey.normalizeTypedFields(
        documentNumber: documentNumber, dateOfBirth: dateOfBirth, dateOfExpiry: dateOfExpiry)
    do {
        return try ChipAccessKey.fromTypedFields(
            documentNumber: typed.documentNumber,
            dateOfBirth: typed.dateOfBirth,
            dateOfExpiry: typed.dateOfExpiry)
    } catch let error as ChipAccessKeyError {
        print("No key: \(error)")
        return nil
    } catch {
        return nil
    }
}
// endregion

// region TES-A-168 block 12
func summary(of finish: ChipReadFinish) -> String {
    // `read` is set for a complete or a partial read, `error` for every ending that has one.
    if let read = finish.read { return "Read \(read.files.count) files" }
    if let error = finish.outcome.error { return "No data (\(error.code))" }
    return "No data"
}
// endregion

// region TES-A-168 block 13
func readWhileVisible(options: ChipReadOptions) async -> ChipReadFinish {
    let reading = ChipReading.start(options: options)
    // result() cancels the read when this task is cancelled, for example when a SwiftUI
    // .task ends because the screen went away.
    return await reading.result()
}
// endregion
