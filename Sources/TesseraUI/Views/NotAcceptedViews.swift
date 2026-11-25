import SwiftUI
import Tessera

// TES-103: the three places a reading of a kind the app does not accept is stated - over the live preview, on
// its own screen after a photo, and as a note on the manual-entry screen. Two facts only: what kind was read,
// and what kinds the app accepts (``MrzScannerConfig/acceptedDocumentTypes``). The decisions and copy live in
// `Model/NotAcceptedDecisions.swift`. Mirrors the Android `NotAcceptedNotice.kt` composables.

/// The notice over the live preview after the frames agreed on a reading of `read` that the app does not
/// accept. Shown in the guide overlay's guidance region, white over the dark scrim like the other cues; the
/// camera keeps scanning under it. Announced when it appears (``ScannerModel`` posts both lines, the Android
/// polite live region). Mirrors the Android `NotAcceptedHint`.
internal struct NotAcceptedHint: View {
    @Environment(\.tesseraStringsBundle) private var stringsBundle
    let read: NotAcceptedKind
    let acceptedDocumentTypes: Set<DocumentCategory>

    var body: some View {
        VStack(spacing: 4) {
            Text(notAcceptedTitle(read, bundle: stringsBundle))
                .font(.headline)
            Text(notAcceptedBody(acceptedDocumentTypes, bundle: stringsBundle))
                .font(.callout)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tessera-mrz-not-accepted-hint")
    }
}

/// The screen after a picked photo read as `read`, a kind the app does not accept. States the two facts and
/// offers another photo (and manual entry when enabled), like the "no MRZ found" screen; its title is
/// announced on arrival (``announcementKey(for:)``). Mirrors the Android `SavedImageNotAcceptedContent`.
internal struct SavedImageNotAcceptedScreen: View {
    @Environment(\.tesseraStringsBundle) private var stringsBundle
    let read: NotAcceptedKind
    let acceptedDocumentTypes: Set<DocumentCategory>
    let onChooseDifferent: () -> Void
    let onManualEntry: () -> Void
    /// Hidden when the consumer's `enabledMethods` excludes manual entry.
    let showManualEntry: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(notAcceptedTitle(read, bundle: stringsBundle))
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Text(notAcceptedBody(acceptedDocumentTypes, bundle: stringsBundle))
                .font(.body)

            Spacer()

            Button(action: onChooseDifferent) {
                Text(ScannerControl.chooseDifferentPhoto.label(bundle: stringsBundle))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .scannerControl(.chooseDifferentPhoto, bundle: stringsBundle)

            if showManualEntry {
                Button(action: onManualEntry) {
                    Text(ScannerControl.savedImageManual.label(bundle: stringsBundle))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .scannerControl(.savedImageManual, bundle: stringsBundle)
            }
        }
        .padding(24)
        .frame(maxHeight: .infinity)
        .contentMaxWidth()
        // Compact height (iPhone landscape): the whole screen scrolls as one column, like the other photo screens.
        .scrollsInCompactHeight()
        .accessibilityIdentifier("tessera-saved-image-not-accepted")
    }
}

/// The inline note on the manual-entry screen after the typed lines read as `read`, a kind the app does not
/// accept. The typed text stays and the next edit clears the note. Announced when it appears (``ScannerModel``
/// posts both lines, the Android polite live region). Mirrors the Android `ManualNotAcceptedNote`.
internal struct ManualNotAcceptedNote: View {
    @Environment(\.tesseraStringsBundle) private var stringsBundle
    let read: NotAcceptedKind
    let acceptedDocumentTypes: Set<DocumentCategory>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(notAcceptedTitle(read, bundle: stringsBundle))
                .font(.subheadline.weight(.semibold))
            Text(notAcceptedBody(acceptedDocumentTypes, bundle: stringsBundle))
                .font(.caption)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tessera-mrz-manual-not-accepted")
    }
}
