import SwiftUI

// The MRZ explainer — the iOS mirror of the Android `MrzExplainer.kt`. A first-time user meets the term
// "MRZ" across the flow ("Enter the MRZ manually", "Couldn't read this MRZ") without necessarily knowing
// what it is. This is the plain-language answer: an always-visible "ⓘ What's the MRZ?" link pinned at the
// bottom of the live camera preview opens an illustrated dialog — a stylised document with the
// machine-readable zone highlighted, and a short "where to find it" note. Purely informational; it makes no
// trust judgement about any document (Principle 1).
//
// The illustration is drawn from SwiftUI shapes (not a baked image) so it adapts to light / dark and scales
// with the system font, and the specimen text is the ICAO Doc 9303 published example — never real data.

/// The ICAO Doc 9303 published TD3 specimen (fictional UTOPIA / ERIKSSON ANNA MARIA). Synthetic by
/// definition — this is the standards body's own example, never a real document. Hard-coded in the drawing,
/// not overridable copy: it illustrates the MRZ's *shape*, so translating it would make no sense. Mirrors the
/// Android `SPECIMEN_LINE_1` / `SPECIMEN_LINE_2`.
private let explainerSpecimenLine1 = "P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<"
private let explainerSpecimenLine2 = "L898902C36UTO7408122F1204159ZE184226B<<<<<10"

/// The "What's the MRZ?" affordance shown pinned at the bottom of the live camera preview, over the scrim.
/// Owns the dialog's open/closed state locally, so it can be dropped into the preview overlay with no
/// plumbing. White for legibility over the guide overlay's dark scrim (like the framing hint). Mirrors the
/// Android `MrzExplainerLink`.
struct MrzExplainerLink: View {
    @State private var showDialog = false

    var body: some View {
        Button {
            showDialog = true
        } label: {
            HStack(spacing: 4) {
                Text("ⓘ").accessibilityHidden(true)
                Text(String(localized: "tessera_scanner_explainer_action", bundle: .module))
            }
            .foregroundStyle(.white)
        }
        .accessibilityIdentifier("tessera-mrz-explainer-action")
        .sheet(isPresented: $showDialog) {
            MrzExplainerDialog(onDismiss: { showDialog = false })
        }
    }
}

/// The explainer dialog itself: a plain intro, the illustrated document with the MRZ highlighted, and a
/// "where to find it" note. Scrollable so it fits small screens and large system font sizes. Split from
/// ``MrzExplainerLink`` so it is host-presentable directly. Mirrors the Android `MrzExplainerDialog`.
struct MrzExplainerDialog: View {
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: "tessera_scanner_explainer_intro", bundle: .module))
                        .font(.body)
                    ExplainerDocumentGraphic()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "tessera_scanner_explainer_where_title", bundle: .module))
                            .font(.subheadline.weight(.semibold))
                        Text(String(localized: "tessera_scanner_explainer_where_body", bundle: .module))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            }
            .navigationTitle(String(localized: "tessera_scanner_explainer_title", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "tessera_scanner_explainer_dismiss", bundle: .module), action: onDismiss)
                }
            }
        }
        .accessibilityIdentifier("tessera-mrz-explainer-dialog")
    }
}

/// A modest stylised document (a passport data page): a type label, a couple of faint detail bars, and —
/// highlighted — the MRZ band along the bottom. It conveys *where* the zone sits, with the zone caption
/// stating *what* it says. Drawn from theme colours so it adapts to light / dark. Mirrors the Android
/// `DocumentGraphic` (kept modest — no separate magnified zoom panel).
private struct ExplainerDocumentGraphic: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "tessera_scanner_explainer_doc_label", bundle: .module))
                .font(.caption2)
                .tracking(1.5)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ExplainerDetailBar(fraction: 0.85)
                ExplainerDetailBar(fraction: 0.6)
                ExplainerDetailBar(fraction: 0.7)
            }

            // The highlighted, magnified MRZ band — the specimen lines never wrap, sharing a horizontal
            // scroll so a narrow phone still shows them at full, legible size.
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(explainerSpecimenLine1)
                    Text(explainerSpecimenLine2)
                }
                .font(.system(.footnote, design: .monospaced).weight(.medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.15)))
            // The specimen MRZ is decorative illustration, not meaningful copy — the intro / zone caption /
            // "where to find it" text already carry the meaning (mirrors the Android `clearAndSetSemantics`).
            .accessibilityHidden(true)

            Text(String(localized: "tessera_scanner_explainer_zone_caption", bundle: .module))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }
}

/// One faint placeholder detail bar, `fraction` of the available width — a simple stand-in for a line of
/// document text. Mirrors the Android `DetailLine`.
private struct ExplainerDetailBar: View {
    let fraction: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.secondary.opacity(0.25))
            .frame(height: 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .scaleEffect(x: fraction, y: 1, anchor: .leading)
    }
}
