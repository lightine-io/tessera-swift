import Testing
import Tessera
@testable import TesseraUI

/// Diagnostic: drives the same decode → document → field extraction the review screen uses, and prints the
/// value each summary row would show, so a field-mapping bug (e.g. a name appearing in the expiry row) is
/// visible as text without rendering the UI.
struct ReviewFieldDiagnostic {
    @Test func dumpSummaryRowValues() {
        // ICAO Doc 9303 published TD3 specimen (fictional Utopia) — a permitted test vector.
        let mrz = """
        P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<
        L898902C36UTO7408122F1204159ZE184226B<<<<<10
        """
        let decoded = assembleManualDecoded(text: mrz)
        let doc: MrzDocument
        if let s = decoded.parse as? ParseResult.Success { doc = s.document }
        else if let p = decoded.parse as? ParseResult.PartialSuccess { doc = p.document }
        else { print("DIAG| parse produced no document: \(type(of: decoded.parse))"); return }

        let f = doc.commonFields
        func date(_ d: MrzDate) -> String { d.computedDate?.description() ?? "\(d.rawYear)\(d.rawMonth)\(d.rawDay)" }
        print("DIAG| primaryIdentifier   = '\(f.primaryIdentifier)'")
        print("DIAG| secondaryIdentifier = '\(f.secondaryIdentifier)'")
        print("DIAG| documentNumber      = '\(f.documentNumber)'")
        print("DIAG| dateOfBirth         = '\(date(f.dateOfBirth))'")
        print("DIAG| dateOfExpiry        = '\(date(f.dateOfExpiry))'")
        print("DIAG| rawSex(unichar)     = \(f.rawSex)")
        // What the four summary rows would show (label -> value), mirroring reviewSummaryRows:
        print("DIAG| ROW Document = documentType erased = '\(f.documentType)'")
        print("DIAG| ROW Name     = '\(f.primaryIdentifier), \(f.secondaryIdentifier)'")
        print("DIAG| ROW Number   = '\(f.documentNumber)'")
        print("DIAG| ROW Expiry   = '\(date(f.dateOfExpiry))'")
    }
}
