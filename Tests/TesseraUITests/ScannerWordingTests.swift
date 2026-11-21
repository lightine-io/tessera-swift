import Testing
import Tessera
@testable import TesseraUI

/// Wording decisions of TES-112: the manual-entry button, the camera permission screen button, and the
/// date shown when its century cannot be resolved. Synthetic specimen data only.
struct ScannerWordingTests {
    @Test func manualReadButtonSaysRead() {
        #expect(TesseraStrings.string("tessera_scanner_manual_read", bundle: nil) == "Read")
    }

    @Test func permissionButtonSaysContinue() {
        #expect(TesseraStrings.string("tessera_scanner_permission_grant_action", bundle: nil) == "Continue")
    }

    @Test func unresolvedCenturyShowsDayFirstPrintedPartsOnly() {
        // The project's TD3 specimen, generated with a past expiry (2013-03-14, printed 130314). Read today,
        // a year 13 fits neither 2013 (more than 10 years back) nor 1913, so the century stays unresolved and
        // the display falls back to the raw components.
        let generated = MrzGenerator.shared.generateTD3(
            documentType: "P", issuingState: "UTO", documentNumber: "T22000129",
            primaryIdentifier: "SPECIMEN", secondaryIdentifier: "ALEX MORGAN", nationality: "UTO",
            dateOfBirth: Kotlinx_datetimeLocalDate(year: 1990, month: 3, day: 15), sex: .female,
            dateOfExpiry: Kotlinx_datetimeLocalDate(year: 2013, month: 3, day: 14),
            personalNumber: "S98765432", transliteration: nil)
        guard let lines = (generated as? GenerationResult.Success)?.mrz else {
            Issue.record("the past-expiry specimen must generate; got \(type(of: generated))")
            return
        }
        let decoded = assembleManualDecoded(text: lines.joined(separator: "\n"))
        guard let s = decoded.parse as? ParseResult.Success else {
            Issue.record("the specimen must parse; got \(type(of: decoded.parse))")
            return
        }
        let expiry = s.document.commonFields.dateOfExpiry
        #expect(expiry.computedDate == nil, "precondition: century must be unresolved")
        #expect(dateDisplay(expiry, bundle: nil) == "14 03 13")
    }
}
