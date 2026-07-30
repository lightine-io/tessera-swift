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
    @State private var showDialog = false

    var body: some View {
        Button {
            showDialog = true
        } label: {
            HStack(spacing: 4) {
                // Decorative glyph (like the scaffold's ✕): hidden from accessibility so the screen reader
                // announces only "Privacy", not the circled-i character.
                Text("ⓘ").accessibilityHidden(true)
                Text(String(localized: "tessera_scanner_privacy_action", bundle: .module))
            }
        }
        .accessibilityIdentifier("tessera-mrz-privacy-action")
        .alert(
            String(localized: "tessera_scanner_privacy_dialog_title", bundle: .module),
            isPresented: $showDialog
        ) {
            Button(String(localized: "tessera_scanner_privacy_dialog_dismiss", bundle: .module)) {}
        } message: {
            Text(String(localized: "tessera_scanner_privacy_dialog_body", bundle: .module))
        }
    }
}
