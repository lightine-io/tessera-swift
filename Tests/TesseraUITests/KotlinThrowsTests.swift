import Testing
import Tessera
@testable import TesseraUI

/// TES-238: Kotlin functions that reject bad input carry `@Throws`, so Swift sees a thrown error
/// instead of a crash. Synthetic specimen data only.
struct KotlinThrowsTests {
    @Test func computeCheckDigitReturnsTheSpecimenDigit() throws {
        // The project's TD3 specimen document number "T22000129" has check digit 3.
        let digit = try CheckDigitKt.computeCheckDigit(input: "T22000129")
        #expect(digit == UInt16(Character("3").asciiValue!))
    }

    @Test func computeCheckDigitThrowsOnCharacterOutsideAlphabet() {
        #expect(throws: (any Error).self) {
            try CheckDigitKt.computeCheckDigit(input: "T22*00129")
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
