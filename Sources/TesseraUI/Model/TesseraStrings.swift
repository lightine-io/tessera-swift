import SwiftUI

// The host string-override seam (TES-139) — the iOS counterpart to Android's resource-merge override, where
// a host app's own `strings.xml` entry silently wins over the module's. SwiftUI/Foundation give no built-in
// equivalent for a `.xcstrings` catalog bundled inside a Swift package, so this file builds one explicitly:
// every string this module renders is required to go through ``TesseraStrings/string(_:bundle:)`` rather than
// calling `String(localized:bundle:.module)` directly, so the override check always runs first.

/// Resolves every `tessera_scanner_*` string this module renders, checking a host-supplied override bundle
/// before falling back to the module's own catalog.
///
/// ## Override contract
/// A host app opts in by setting ``MrzScannerConfig/stringsBundle`` to its own bundle (typically
/// `Bundle.main`). To override a string, the host defines an entry for the **same key** the module uses (see
/// `Resources/Localizable.xcstrings` for the full catalog) in its own **`Localizable` table** — either a
/// `Localizable.strings` file or a `Localizable.xcstrings` catalog, standard Xcode string-catalog mechanics,
/// looked up the same way `NSLocalizedString` / `Bundle.localizedString(forKey:value:table:)` would. Any key
/// the host does not define falls through to the module's own bundled string, so a host only ever needs to
/// override the handful of keys it actually wants to change — this is additive, not a full replacement of the
/// catalog.
enum TesseraStrings {
    /// Looks `key` up in `bundle` (the host's ``MrzScannerConfig/stringsBundle``) first; if that bundle has
    /// no entry for it — or `bundle` is `nil`, the default — falls back to the module's own `.module` catalog.
    ///
    /// `Bundle.localizedString(forKey:value:table:)` returns `key` itself, unchanged, when the table has no
    /// entry for it; that is the framework's documented "miss" signal, and is how a real override (whose
    /// value happens to equal its key) is distinguished from no override at all — an edge case not worth
    /// guarding against since a key and its display value are never expected to collide in practice.
    static func string(_ key: String, bundle: Bundle?) -> String {
        if let bundle {
            let candidate = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
            if candidate != key {
                return candidate
            }
        }
        return Bundle.module.localizedString(forKey: key, value: nil, table: "Localizable")
    }
}

/// The environment seam that carries ``MrzScannerConfig/stringsBundle`` down to every screen without
/// threading it through each view's initializer. Set once, at the top (``MrzScannerView``), and read wherever
/// a screen calls ``TesseraStrings/string(_:bundle:)``.
private struct TesseraStringsBundleKey: EnvironmentKey {
    static let defaultValue: Bundle? = nil
}

extension EnvironmentValues {
    var tesseraStringsBundle: Bundle? {
        get { self[TesseraStringsBundleKey.self] }
        set { self[TesseraStringsBundleKey.self] = newValue }
    }
}
