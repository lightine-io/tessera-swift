import Foundation
import Testing
@testable import TesseraUI

/// Coverage for the host string-override seam (TES-139): ``TesseraStrings/string(_:bundle:)`` must check the
/// host's ``MrzScannerConfig/stringsBundle`` first and fall back to the module's own catalog whenever that
/// bundle is `nil` or does not define the key. A real `.strings`/`.xcstrings` resource is awkward to stand up
/// inside a test target, so a ``Bundle`` subclass stands in for the host bundle — it overrides
/// `localizedString(forKey:value:table:)` directly, which is exactly the seam ``TesseraStrings`` calls.
struct TesseraStringsTests {
    /// A stand-in host bundle: returns a fixed override for the keys in `overrides`, and — mirroring the real
    /// `Bundle.localizedString(forKey:value:table:)` "miss" contract — the key itself, unchanged, for anything
    /// else.
    private final class FakeHostBundle: Bundle, @unchecked Sendable {
        let overrides: [String: String]

        init(overrides: [String: String]) {
            self.overrides = overrides
            super.init()
        }

        override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
            overrides[key] ?? key
        }
    }

    /// A key the module's own `Localizable.xcstrings` actually defines, so the module-fallback path resolves
    /// to a real (non-empty, not-just-the-key) string rather than another "miss".
    private static let realModuleKey = "tessera_scanner_title"

    @Test func nilBundleFallsBackToTheModuleString() {
        let resolved = TesseraStrings.string(Self.realModuleKey, bundle: nil)
        #expect(resolved != Self.realModuleKey) // the module catalog actually defines this key
        #expect(!resolved.isEmpty)
    }

    @Test func hostOverrideWinsForAnOverriddenKey() {
        let host = FakeHostBundle(overrides: [Self.realModuleKey: "Custom Title"])
        #expect(TesseraStrings.string(Self.realModuleKey, bundle: host) == "Custom Title")
    }

    @Test func unoverriddenKeyFallsBackToTheModuleStringEvenWithAHostBundleSet() {
        // The host bundle is set (unlike the nil case above) but defines no entry for this key, so
        // `localizedString` returns the key itself — the documented "miss" — and TesseraStrings falls through
        // to the module's own catalog exactly as it would with no host bundle at all.
        let host = FakeHostBundle(overrides: [:])
        let resolved = TesseraStrings.string(Self.realModuleKey, bundle: host)
        #expect(resolved != Self.realModuleKey)
        #expect(!resolved.isEmpty)
    }
}
