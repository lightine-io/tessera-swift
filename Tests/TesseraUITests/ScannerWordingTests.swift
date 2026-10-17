import Testing
import Tessera
@testable import TesseraUI

/// Wording decisions of TES-112: the manual-entry button, the camera permission screen button, and the
/// date shown when its century cannot be resolved. Synthetic / ICAO specimen data only.
struct ScannerWordingTests {
    @Test func manualReadButtonSaysRead() {
        #expect(TesseraStrings.string("tessera_scanner_manual_read", bundle: nil) == "Read")
    }

    @Test func permissionButtonSaysContinue() {
        #expect(TesseraStrings.string("tessera_scanner_permission_grant_action", bundle: nil) == "Continue")
    }

    @Test func unresolvedCenturyShowsDayFirstPrintedPartsOnly() {
        // The published ICAO TD3 specimen: its expiry (120415) has no resolvable century (see
        // ReviewFieldMappingTests), so the display falls back to the raw components.
        let mrz = """
        P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<
        L898902C36UTO7408122F1204159ZE184226B<<<<<10
        """
        let decoded = assembleManualDecoded(text: mrz)
        guard let s = decoded.parse as? ParseResult.Success else {
            Issue.record("the specimen must parse; got \(type(of: decoded.parse))")
            return
        }
        let expiry = s.document.commonFields.dateOfExpiry
        #expect(expiry.computedDate == nil, "precondition: century must be unresolved")
        #expect(dateDisplay(expiry, bundle: nil) == "15 04 12")
    }
}
