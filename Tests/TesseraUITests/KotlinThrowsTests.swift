import Testing
import Tessera
@testable import TesseraUI

/// TES-238: Kotlin functions that reject bad input carry `@Throws`, so Swift sees a thrown error
/// instead of a crash. Synthetic / ICAO specimen data only.
struct KotlinThrowsTests {
    @Test func computeCheckDigitReturnsTheSpecimenDigit() throws {
        // ICAO Doc 9303 specimen document number "L898902C3" has check digit 6.
        let digit = try CheckDigitKt.computeCheckDigit(input: "L898902C3")
        #expect(digit == UInt16(Character("6").asciiValue!))
    }

    @Test func computeCheckDigitThrowsOnCharacterOutsideAlphabet() {
        #expect(throws: (any Error).self) {
            try CheckDigitKt.computeCheckDigit(input: "L89*902C3")
        }
    }

    @Test func decodeConsensusAcceptsValidThreshold() throws {
        let consensus = try MrzDecodeConsensus(threshold: 2)
        #expect(consensus.threshold == 2)
    }

    @Test func decodeConsensusThrowsOnThresholdBelowOne() {
        #expect(throws: (any Error).self) {
            try MrzDecodeConsensus(threshold: 0)
        }
    }
}
