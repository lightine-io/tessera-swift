import SwiftUI

// The privacy / transparency notice — the iOS mirror of the Android `PrivacyNotice.kt`. One coherent,
// always-reachable explanation of what the scanner does with the document: it reads on-device, keeps
// nothing, and hands the result back to the host app, which then decides what happens. Surfaced as a compact
// "ⓘ Privacy" affordance in the shared top bar (`ScannerScaffold`), so it rides along on every screen without
// being a banner that nags on each one — the user taps it when they want to know, and a dialog states the
// full plain-language explanation.
//
// Reader, not oracle (Principle 1): this only *describes* the SDK's own data handling; it makes no claim
// about the document. It is honest about the boundary — Tessera is a pass-through reader, the host is the
// controller of whatever it returns.

/// The top-bar privacy affordance: a compact "ⓘ Privacy" button that opens ``PrivacyNoticeDialog``. Owns the
/// dialog's open/closed state locally (a self-contained disclosure — no flow state involved), so
/// ``ScannerScaffold`` can drop it into the trailing toolbar with no plumbing. Mirrors the Android
/// `PrivacyNoticeAction`.
struct PrivacyNoticeAction: View {
    @Environment(\.tesseraStringsBundle) private var stringsBundle
    @State private var showDialog = false

    var body: some View {
        Button {
            showDialog = true
        } label: {
            // Icon-only, the iOS toolbar idiom (like the scaffold's ✕ and every stock app): an SF Symbol
            // never gets the system's tappable-text underline treatment, scales with Dynamic Type, and
            // carries the localized "Privacy" as its spoken label below. The Android top bar keeps its
            // "ⓘ Privacy" text form — parity is the affordance (privacy notice reachable from the top bar
            // on every screen), presentation follows each platform's idiom.
            Image(systemName: "info.circle")
        }
        .accessibilityLabel(TesseraStrings.string("tessera_scanner_privacy_action", bundle: stringsBundle))
        .accessibilityIdentifier("tessera-mrz-privacy-action")
        .alert(
            TesseraStrings.string("tessera_scanner_privacy_dialog_title", bundle: stringsBundle),
            isPresented: $showDialog
        ) {
            Button(TesseraStrings.string("tessera_scanner_privacy_dialog_dismiss", bundle: stringsBundle)) {}
        } message: {
            Text(TesseraStrings.string("tessera_scanner_privacy_dialog_body", bundle: stringsBundle))
        }
    }
}
