import SwiftUI
import Tessera

// The saved-image (photo) reading screens (mockups 07c → 07 / 07b) — the iOS mirror of the Android
// `SavedImageScreen.kt`. A picked photo takes its one best strict read straight to review — no tolerant
// candidate enumeration and no "choose the reading" screen (mirroring the shipped Android behaviour; a
// misread ambiguous glyph surfaces on review as a check-digit observation and the user re-picks). The state
// mapping (`SavedImageOutcome`) lives in `Model/ScannerDecisions.swift`; these are the display views only.

// MARK: - Awaiting pick

/// The await-saved-image-pick prompt. Shown when the saved-image method is the entry point and the picker
/// was dismissed with no photo — so the screen is never left blank. Neutral copy ("Choose a photo" + the
/// on-device privacy fact) and a single action that re-opens the picker. Mirrors the Android
/// `AwaitingSavedImagePickContent`.
internal struct AwaitingSavedImagePickScreen: View {
    let onChoosePhoto: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 12) {
                Spacer()
                Text(String(localized: "tessera_scanner_saved_image_prompt_title", bundle: .module))
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(String(localized: "tessera_scanner_saved_image_prompt_body", bundle: .module))
                    .font(.body)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity)

            Button(action: onChoosePhoto) {
                Text(String(localized: "tessera_scanner_saved_image_prompt_action", bundle: .module))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxHeight: .infinity)
        .contentMaxWidth()
        .accessibilityIdentifier("tessera-saved-image-awaiting-pick")
    }
}

// MARK: - Analyzing

/// The "analyzing photo" screen (mockup 07c) — shown while the picked photo is being read on-device. A
/// loading indicator over a title and neutral sub-text, stating the on-device privacy fact plainly rather
/// than implying anything about the image. The title is announced to VoiceOver on arrival (this screen is
/// reached via an auto-transition, not a user tap), mirroring the Android polite live region; the spinner is
/// decorative and hidden from the accessibility tree. Mirrors the Android `SavedImageAnalyzingContent`.
internal struct SavedImageAnalyzingScreen: View {
    var body: some View {
        VStack(spacing: 16) {
            Text(String(localized: "tessera_scanner_saved_image_analyzing_title", bundle: .module))
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.updatesFrequently)

            ProgressView()
                .controlSize(.large)
                .accessibilityHidden(true)

            Text(String(localized: "tessera_scanner_saved_image_analyzing_reading", bundle: .module))
                .font(.body)

            Text(String(localized: "tessera_scanner_saved_image_analyzing_on_device", bundle: .module))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxHeight: .infinity)
        .contentMaxWidth()
        .accessibilityIdentifier("tessera-saved-image-analyzing")
    }
}

// MARK: - Empty

/// The "no MRZ found in this photo" screen (mockup 07b). Stated honestly — the MRZ *couldn't be located*, not
/// that the document is "invalid" — with a neutral hint about why, a privacy note that the photo stays
/// on-device, and two escapes: pick a different photo (primary) or type the details by hand (secondary).
/// Mirrors the Android `SavedImageEmptyContent`.
///
/// - Parameters:
///   - onChooseDifferent: re-launch the photo picker.
///   - onManualEntry: switch to manual raw-MRZ entry.
internal struct SavedImageEmptyScreen: View {
    let onChooseDifferent: () -> Void
    let onManualEntry: () -> Void
    /// Hidden when the consumer's `enabledMethods` excludes manual entry. Mirrors Android's `showManualEntry`.
    let showManualEntry: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "tessera_scanner_saved_image_empty_title", bundle: .module))
                .font(.title2.weight(.semibold))
            Text(String(localized: "tessera_scanner_saved_image_empty_body", bundle: .module))
                .font(.body)
            Text(String(localized: "tessera_scanner_saved_image_empty_privacy", bundle: .module))
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button(action: onChooseDifferent) {
                Text(String(localized: "tessera_scanner_saved_image_choose_different", bundle: .module))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            if showManualEntry {
                Button(action: onManualEntry) {
                    Text(String(localized: "tessera_scanner_saved_image_manual", bundle: .module))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxHeight: .infinity)
        .contentMaxWidth()
        .accessibilityIdentifier("tessera-saved-image-empty")
    }
}
