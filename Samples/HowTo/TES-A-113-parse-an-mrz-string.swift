// Sample for TES-A-113 "Parse an MRZ string on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-113 block 1: Package.swift dependency lines

// region TES-A-113 block 2
import Foundation
import Tessera

let specimen = """
P<UTOSPECIMEN<<ALEX<MORGAN<<<<<<<<<<<<<<<<<<
T220001293UTO9003152F3403141S98765432<<<<<20
"""
// endregion

/// Namespace: TES-A-126 declares a top-level referenceTime() of its own.
struct ParseAnMrzString {
    // region TES-A-113 block 3
    func referenceTime() -> KotlinInstant {
        KotlinInstant.companion.fromEpochMilliseconds(epochMilliseconds: 1_795_219_200_000)
    }
    // endregion

    // region TES-A-113 block 4
    func parseAnyFormat() -> ParseResult {
        MrzParser.shared.parse(input: specimen, referenceTime: referenceTime())
    }
    // endregion

    // region TES-A-113 block 5
    func parsePassport() -> ParseResult {
        MrzParser.shared.parseTD3(input: specimen, referenceTime: referenceTime())
    }
    // endregion

    // region TES-A-113 block 6
    func readTyped() -> ParseResult {
        ManualMrzReader.shared.read(input: specimen, referenceTime: referenceTime())
    }
    // endregion

    // region TES-A-113 block 7
    func show() {
        print(parseAnyFormat().metadata.readMethod.name)   // BACKEND_STRING_INPUT
        print(readTyped().metadata.readMethod.name)        // MANUAL_ENTRY
    }
    // endregion

    // region TES-A-113 block 8
    func parseLines() -> ParseResult {
        let lines = specimen.split(separator: "\n").map(String.init)
        let now = KotlinInstant.companion.fromEpochMilliseconds(
            epochMilliseconds: Int64(Date().timeIntervalSince1970 * 1000)
        )
        return MrzParser.shared.parse(lines: lines, referenceTime: now)
    }
    // endregion
}
