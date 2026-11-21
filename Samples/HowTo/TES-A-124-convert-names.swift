// Sample for TES-A-124 "Convert names to the MRZ alphabet on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-124 block 1: Package.swift dependency lines

// region TES-A-124 block 2
import Tessera
// endregion

// region TES-A-124 block 3
func icao(_ name: String) -> TransliterationOutcome {
    TransliterateKt.transliterate(IcaoDefaultTransliterationProfile.shared, input: name)
}
// endregion

// region TES-A-124 block 4
func text(_ outcome: TransliterationOutcome) -> String {
    switch outcome.result {
    case let ok as TransliterationResult.Success:
        return ok.output
    case let failed as TransliterationResult.Failure:
        return "unmapped: \(failed.unmappedCharacters.count)"
    default:
        return ""
    }
}
// text(icao("MÜLLER")) is "MULLER". text(icao("ALEX MORGAN")) is "ALEX<MORGAN".
// endregion

// region TES-A-124 block 5
func aze(_ name: String) -> String {
    text(TransliterateKt.transliterate(AzeTransliterationProfile.shared, input: name))
}
// aze("ŞƏKİ") is "SHAKI". text(icao("ŞƏKİ")) is "S<KI".
// endregion

// region TES-A-124 block 6
func profile(_ identifier: String) -> (any TransliterationProfile)? {
    TransliterationProfileRegistry.shared.lookup(identifier: identifier)
}
// "ICAO" and "AZE" are registered. Other identifiers return nil.
// endregion
