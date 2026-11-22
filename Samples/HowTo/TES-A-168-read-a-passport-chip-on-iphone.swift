// Sample for TES-A-168 "Read a passport chip on iPhone".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-168 block 1: Package.swift dependency lines
// skip TES-A-168 block 3: App.entitlements
// skip TES-A-168 block 4: Info.plist

// region TES-A-168 block 2
import Foundation
import Tessera

func checkTimeNow() -> KotlinInstant {
    KotlinInstant.companion.fromEpochMilliseconds(
        epochMilliseconds: Int64((Date().timeIntervalSince1970 * 1000).rounded())
    )
}

// Kotlin `Char` is a `unichar` in Swift.
func mrzChar(_ c: Character) -> unichar {
    c.utf16.first!
}
// endregion

// region TES-A-168 block 5
// Replace the values with the ones printed in your document's MRZ.
func makeKey() throws -> ChipAccessKey.Mrz {
    try ChipAccessKey.Mrz(
        documentNumber: "T22000129",
        documentNumberCheckDigit: mrzChar("3"),
        dateOfBirth: "900315",
        dateOfBirthCheckDigit: mrzChar("2"),
        dateOfExpiry: "340314",
        dateOfExpiryCheckDigit: mrzChar("1")
    )
}

func makeOptions(key: ChipAccessKey) throws -> ChipReadOptions {
    try ChipReadOptions.Builder(accessKey: key)
        .checkTime(time: checkTimeNow())
        .build()
}
// endregion

// region TES-A-168 block 6
func readChip(key: ChipAccessKey) async throws -> ChipReadResult {
    let session = CoreNfcSession(alertMessage: "Hold the top of your iPhone on the document.")
    do {
        let transport = try await session.connect()
        let reader = ChipReader(telemetry: NoOpTelemetrySink())
        let result = try await reader.read(transport: transport, options: makeOptions(key: key))
        session.end()
        return result
    } catch {
        session.end(errorMessage: "Reading failed.")
        throw error
    }
}
// endregion

// region TES-A-168 block 7
func describe(_ result: ChipReadResult) -> String {
    switch result {
    case let complete as ChipReadResult.Complete:
        return "Read \(complete.read.files.count) files, \(complete.read.checks.count) checks"
    case let partial as ChipReadResult.Partial:
        return "Stopped: \(partial.stoppedBy)"
    case let failed as ChipReadResult.Failed:
        return "Not read: \(failed.error)"
    default:
        return ""
    }
}

func describe(checks read: ChipRead) -> [String] {
    read.checks.map { "\($0.kind): \($0.outcome)" }
}
// endregion

// region TES-A-168 block 8
func transportError(from error: Error) -> NfcError? {
    let thrown = (error as NSError).userInfo["KotlinException"]
    return (thrown as? ApduTransportException)?.error
}
// endregion

// region TES-A-168 block 9
func finish(key: ChipAccessKey) {
    key.clear()
}
// endregion

// region TES-A-168 block 10
func makeOptionsWithMoreFiles(key: ChipAccessKey) throws -> ChipReadOptions {
    let groups = Set([1, 2, 11].map { KotlinInt(int: Int32($0)) })
    return try ChipReadOptions.Builder(accessKey: key)
        .dataGroups(numbers: groups)
        .checkTime(time: checkTimeNow())
        .build()
}

func updateSheet(_ session: CoreNfcSession) {
    session.alertMessage = "Reading the photo. Keep holding."
}
// endregion
