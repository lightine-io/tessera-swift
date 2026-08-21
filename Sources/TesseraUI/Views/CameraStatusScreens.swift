import SwiftUI

// The camera-status screens (mockups 05 / 05b) and the struggling-hint overlay (mockup 02) — the iOS mirror
// of the Android `CameraStatusScreen.kt` (`CameraInUseContent` / `CameraUnavailableContent`) and the
// `StrugglingHint` composable in `MrzScannerScreen.kt`.
//
//  * CameraInUseScreen (05, recoverable): another app holds the camera. The platform camera framework
//    auto-resumes the stream once the other holder releases it, so this screen offers NO retry — it
//    self-resumes (see `ScannerModel`'s state transitions: a subsequent non-error result flips the flow back
//    to `.scanning`). The only action is the manual-entry escape.
//  * CameraUnavailableScreen (05b, terminal): the camera cannot be started at all. No auto-recovery, no
//    retry — the only forward path is manual entry.
//  * StrugglingHint (02): a neutral advisory overlaid on the live preview. Never an error or a verdict — the
//    camera keeps scanning underneath. Just a "Type it instead" escape alongside the hint text.
//  * GatheringHint: the "hold steady" cue overlaid on the live preview while the frame-agreement consensus
//    gate confirms a read across several frames. Advisory only — a small activity indicator plus text.
//
// All three are honest statements of a capture condition, never a verdict about a document (Principle 1).
// The meaning lives in the text, not in colour or motion alone.

/// The camera-in-use screen (mockup 05). Shown when another app holds the camera. This is **recoverable**:
/// the scanner keeps its session bound underneath and the platform camera framework auto-resumes the stream
/// once the other holder releases it, so the flow returns to scanning on its own. There is therefore **no
/// retry action** — only ``onManualEntry``, the escape into manual entry for a user who would rather not
/// wait. The "Reconnecting…" indicator states the recoverable status in words. Mirrors the Android
/// `CameraInUseContent`.
internal struct CameraInUseScreen: View {
    @Environment(\.tesseraStringsBundle) private var stringsBundle
    let onManualEntry: () -> Void
    /// Hidden when the consumer's `enabledMethods` excludes manual entry (a camera-only config must not
    /// route the user into a screen it disabled). Mirrors the Android `showManualEntry` gating.
    let showManualEntry: Bool

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            VStack(spacing: 12) {
                Text(TesseraStrings.string("tessera_scanner_camera_in_use_title", bundle: stringsBundle))
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    // The screen arrives via an auto-transition (another app grabs the camera), so the
                    // recoverable status is announced on appearance without the user moving focus to it.
                    .accessibilityAddTraits(.updatesFrequently)
                Text(TesseraStrings.string("tessera_scanner_camera_in_use_body", bundle: stringsBundle))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                ReconnectingIndicator()
            }

            Spacer()

            if showManualEntry {
                Button(action: onManualEntry) {
                    Text(TesseraStrings.string("tessera_scanner_camera_manual", bundle: stringsBundle))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentMaxWidth()
        .accessibilityIdentifier("tessera-mrz-camera-in-use")
    }
}

/// The camera-unavailable screen (mockup 05b). Shown when the camera cannot be started for a non-recoverable
/// reason. This is **terminal**: there is no auto-recovery and no retry — the only forward path is
/// ``onManualEntry``, typing the details by hand. Mirrors the Android `CameraUnavailableContent`.
internal struct CameraUnavailableScreen: View {
    @Environment(\.tesseraStringsBundle) private var stringsBundle
    let onManualEntry: () -> Void
    /// Hidden when the consumer's `enabledMethods` excludes manual entry (a camera-only config must not
    /// route the user into a screen it disabled). Mirrors the Android `showManualEntry` gating.
    let showManualEntry: Bool

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            VStack(spacing: 12) {
                Text(TesseraStrings.string("tessera_scanner_camera_unavailable_title", bundle: stringsBundle))
                    .font(.title2)
                    .multilineTextAlignment(.center)
                Text(TesseraStrings.string("tessera_scanner_camera_unavailable_body", bundle: stringsBundle))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            if showManualEntry {
                Button(action: onManualEntry) {
                    Text(TesseraStrings.string("tessera_scanner_camera_manual", bundle: stringsBundle))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentMaxWidth()
        .accessibilityIdentifier("tessera-mrz-camera-unavailable")
    }
}

/// The "Reconnecting…" indicator on the camera-in-use screen: a pulsing dot beside the reconnecting label.
/// The label carries the meaning; the pulse is purely decorative (the recoverable status is stated in the
/// text, so nothing is lost with reduce-motion on — SwiftUI's `.repeatForever` animation already honours the
/// platform's reduce-motion setting via `UIAccessibility.isReduceMotionEnabled`, mirroring the Android
/// `animationsEnabled()` gate). Mirrors the Android `ReconnectingIndicator`.
private struct ReconnectingIndicator: View {
    @Environment(\.tesseraStringsBundle) private var stringsBundle
    @State private var pulsed = false

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(.orange)
                .frame(width: 7, height: 7)
                .opacity(pulsed ? 1 : 0.25)
                .accessibilityHidden(true) // Decorative — cleared so a screen reader does not read a bare dot.
                .onAppear {
                    guard !UIAccessibility.isReduceMotionEnabled else { return }
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        pulsed = true
                    }
                }
            Text(TesseraStrings.string("tessera_scanner_camera_reconnecting", bundle: stringsBundle))
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

/// The struggling hint overlaid on the live preview (mockup 02): a neutral advisory line ("still looking —
/// try more light or move closer") and a "Type it instead" affordance into manual entry. Advisory only — it
/// never states an error or a verdict, and the camera keeps scanning underneath (a decode arriving after the
/// hint still routes normally). ``onManualEntry`` switches to manual raw entry. Mirrors the Android
/// `StrugglingHint`.
internal struct StrugglingHint: View {
    @Environment(\.tesseraStringsBundle) private var stringsBundle
    let onManualEntry: () -> Void
    /// Hidden when the consumer's `enabledMethods` excludes manual entry (a camera-only config must not
    /// route the user into a screen it disabled). Mirrors the Android `showManualEntry` gating.
    let showManualEntry: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(TesseraStrings.string("tessera_scanner_struggling_hint", bundle: stringsBundle))
                .font(.callout)
                .multilineTextAlignment(.center)
                // The hint overlays the preview via a struggle-timeout auto-transition, so it is announced on
                // appearance without the user needing to move focus to it.
                .accessibilityAddTraits(.updatesFrequently)
            if showManualEntry {
                Button(action: onManualEntry) {
                    Text(TesseraStrings.string("tessera_scanner_struggling_manual", bundle: stringsBundle))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
        .padding(24)
        .accessibilityIdentifier("tessera-mrz-struggling-hint")
    }
}

/// The "hold steady" gathering cue overlaid on the live preview while the frame-agreement consensus gate
/// (``MrzDecodeConsensus``) confirms a read across several frames. Gives the consensus wait visible feedback
/// — a small activity indicator plus "Hold steady…" — so a multi-frame confirmation reads as active progress
/// rather than lag. Advisory only — it states no error and no verdict (Principle 1); the camera keeps
/// scanning underneath and a confirmed read routes on normally. Takes render precedence over
/// ``StrugglingHint`` in the single live-preview guidance region (``guidanceMessage(gathering:struggling:)``)
/// — getting a decode at all is better news than "still looking". Mirrors the Android `GatheringHint`.
internal struct GatheringHint: View {
    @Environment(\.tesseraStringsBundle) private var stringsBundle

    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .tint(.white)
                .accessibilityHidden(true) // Decorative — the text carries the meaning.
            Text(TesseraStrings.string("tessera_scanner_gathering_hint", bundle: stringsBundle))
                .font(.callout)
                .multilineTextAlignment(.center)
                // Appears on an auto-transition (a read starting to confirm), so it is announced on
                // appearance without the user needing to move focus to it.
                .accessibilityAddTraits(.updatesFrequently)
        }
        .padding(24)
        .accessibilityIdentifier("tessera-mrz-gathering")
    }
}
