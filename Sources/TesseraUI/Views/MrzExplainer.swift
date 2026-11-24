import SwiftUI

// The MRZ explainer — the iOS mirror of the Android `MrzExplainer.kt`. A first-time user meets the term
// "MRZ" across the flow ("Enter the MRZ manually", "Couldn't read this MRZ") without necessarily knowing
// what it is. This is the plain-language answer: an always-visible "ⓘ What's the MRZ?" link pinned at the
// bottom of the live camera preview opens an illustrated dialog - a stylised document with the
// machine-readable zone highlighted, the zone magnified so its characters are legible, and a short "where to
// find it" note. Purely informational; it makes no trust judgement about any document (Principle 1).
//
// The illustration is drawn from SwiftUI shapes (not a baked image) so it adapts to light / dark and scales
// with the system font, and the specimen text is the project's own fictional specimen — never real data.

/// The project's own TD3 specimen (fictional Utopia, code UTO / SPECIMEN ALEX MORGAN), made with the SDK's
/// generator rules - synthetic, never a real document. Hard-coded in the drawing,
/// not overridable copy: it illustrates the MRZ's *shape*, so translating it would make no sense. Mirrors the
/// Android `SPECIMEN_LINE_1` / `SPECIMEN_LINE_2`.
private let explainerSpecimenLine1 = "P<UTOSPECIMEN<<ALEX<MORGAN<<<<<<<<<<<<<<<<<<"
private let explainerSpecimenLine2 = "T220001293UTO9003152F3403141S98765432<<<<<20"

/// The "What's the MRZ?" affordance shown pinned at the bottom of the live camera preview, over the scrim.
/// Owns the dialog's open/closed state locally, so it can be dropped into the preview overlay with no
/// plumbing. White for legibility over the guide overlay's dark scrim (like the framing hint). Mirrors the
/// Android `MrzExplainerLink`.
struct MrzExplainerLink: View {
    @Environment(\.tesseraStringsBundle) private var stringsBundle
    @State private var showDialog = false

    var body: some View {
        Button {
            showDialog = true
        } label: {
            HStack(spacing: 4) {
                Text("ⓘ").accessibilityHidden(true)
                Text(ScannerControl.explainer.label(bundle: stringsBundle))
            }
            .foregroundStyle(.white)
        }
        .scannerControl(.explainer, bundle: stringsBundle)
        .accessibilityIdentifier("tessera-mrz-explainer-action")
        .sheet(isPresented: $showDialog) {
            MrzExplainerDialog(onDismiss: { showDialog = false })
        }
    }
}

/// The explainer dialog itself: a plain intro, the illustrated document with the MRZ highlighted, the zone
/// magnified, and a "where to find it" note. Scrollable so it fits small screens and large system font sizes. Split from
/// ``MrzExplainerLink`` so it is host-presentable directly. Mirrors the Android `MrzExplainerDialog`.
struct MrzExplainerDialog: View {
    @Environment(\.tesseraStringsBundle) private var stringsBundle
    let onDismiss: () -> Void

    var body: some View {
        CompatNavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(TesseraStrings.string("tessera_scanner_explainer_intro", bundle: stringsBundle))
                        .font(.body)
                    MrzExplainerPicture()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(TesseraStrings.string("tessera_scanner_explainer_where_title", bundle: stringsBundle))
                            .font(.subheadline.weight(.semibold))
                        Text(TesseraStrings.string("tessera_scanner_explainer_where_body", bundle: stringsBundle))
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
            }
            .navigationTitle(TesseraStrings.string("tessera_scanner_explainer_title", bundle: stringsBundle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ScannerControl.explainerDismiss.label(bundle: stringsBundle), action: onDismiss)
                }
            }
        }
        .accessibilityIdentifier("tessera-mrz-explainer-dialog")
    }
}

/// The explainer's picture: the stylised document with the MRZ band in place, a small "look closer" arrow,
/// and the zone magnified so its characters are legible, with a caption. Split out so it is host-testable on
/// its own (the dialog sits in a navigation container, which reports a fixed size). Mirrors the middle of the
/// Android `MrzExplainerDialog`: `DocumentGraphic`, the "▾" cue, and `MrzZoomDetail`.
struct MrzExplainerPicture: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ExplainerDocumentGraphic()
            // A quiet "zoom to the detail below" cue between the document and its magnified band.
            Text(verbatim: "▾")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
            ExplainerZoomDetail()
        }
    }
}

/// A stylised document (a passport data page): a type label, a photo placeholder with a simple silhouette, a
/// few faint detail bars, and - highlighted - the MRZ band along the bottom, small. It conveys *where* the
/// zone sits; ``ExplainerZoomDetail`` magnifies *what* it says. Drawn from system colours and the scanner
/// tint so it adapts to light / dark. Mirrors the Android `DocumentGraphic`.
struct ExplainerDocumentGraphic: View {
    @Environment(\.tesseraStringsBundle) private var stringsBundle
    // The on-document band is deliberately tiny (it is the magnified copy below that is read), but it still
    // grows with the system text size. Mirrors the Android 6.5.sp.
    @ScaledMetric(relativeTo: .caption2) private var bandFontSize: CGFloat = 6.5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(TesseraStrings.string("tessera_scanner_explainer_doc_label", bundle: stringsBundle))
                .font(.caption2)
                .tracking(1.5)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                ExplainerPhotoPlaceholder()
                VStack(alignment: .leading, spacing: 8) {
                    ExplainerDetailBar(fraction: 0.85)
                    ExplainerDetailBar(fraction: 0.6)
                    ExplainerDetailBar(fraction: 0.7)
                }
                .padding(.top, 4)
            }

            // The MRZ band on the document - highlighted, small (the magnified, legible copy is below).
            ExplainerMrzLines(fontSize: bandFontSize)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 7).fill(.tint.opacity(0.15)))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator), lineWidth: 1))
    }
}

/// The photo box with a simple head-and-shoulders silhouette, drawn from shapes (not an image asset). Purely
/// decorative, so hidden from VoiceOver. Mirrors the Android `PhotoPlaceholder`.
private struct ExplainerPhotoPlaceholder: View {
    var body: some View {
        GeometryReader { box in
            let width = box.size.width
            let height = box.size.height
            ZStack(alignment: .topLeading) {
                Color(.tertiarySystemFill)
                // Head, then shoulders - placed in fractions of the box, as on Android.
                Circle()
                    .fill(Color(.systemGray3))
                    .frame(width: width * 0.44, height: width * 0.44)
                    .offset(x: width * 0.28, y: height * 0.34 - width * 0.22)
                Ellipse()
                    .fill(Color(.systemGray3))
                    .frame(width: width * 0.68, height: height * 0.6)
                    .offset(x: width * 0.16, y: height * 0.6)
            }
        }
        .frame(width: 56, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityHidden(true)
    }
}

/// One faint placeholder detail bar, `fraction` of the available width - a simple stand-in for a line of
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

/// The magnified MRZ: the same specimen lines at a legible size in a highlighted panel, with a one-line
/// caption. Mirrors the Android `MrzZoomDetail`.
struct ExplainerZoomDetail: View {
    @Environment(\.tesseraStringsBundle) private var stringsBundle
    // Mirrors the Android 13.sp; grows with the system text size.
    @ScaledMetric(relativeTo: .footnote) private var zoomFontSize: CGFloat = 13

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ExplainerMrzLines(fontSize: zoomFontSize)
            Text(TesseraStrings.string("tessera_scanner_explainer_zone_caption", bundle: stringsBundle))
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(.tint.opacity(0.15)))
    }
}

/// The two specimen MRZ lines in monospace, used twice: small on the document and magnified in the zoom
/// detail. The lines never wrap - they share one horizontal scroll so the fixed-width MRZ stays intact on a
/// narrow phone and at any text size. The specimen is decorative illustration, not meaningful copy: the
/// intro, the zone caption and the "where to find it" text carry the meaning, so it is hidden from VoiceOver
/// (mirrors the Android `clearAndSetSemantics`). Mirrors the Android `MrzBand` / `MrzLine`.
private struct ExplainerMrzLines: View {
    let fontSize: CGFloat

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: explainerSpecimenLine1)
                Text(verbatim: explainerSpecimenLine2)
            }
            .font(.system(size: fontSize, weight: .medium, design: .monospaced))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityHidden(true)
    }
}
