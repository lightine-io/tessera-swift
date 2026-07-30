import AVFoundation
import SwiftUI
import UIKit

/// The live preview. The scanner (`AVCaptureMrzScanner`) owns the camera session and lifecycle; this view
/// only draws and observes — the iOS analogue of the Android `CameraPreview`/`CameraXViewfinder`. It attaches
/// an `AVCaptureVideoPreviewLayer` to the running `AVCaptureSession` the scanner publishes on `previewSession`.
///
/// While the session is `nil`, the camera and on-device text reader are still warming up (mockup 01b): the
/// ``InitializingContent`` state shows rather than a blank dark box that reads as frozen. It auto-swaps to the
/// live viewfinder the moment the session arrives — the session's nullness *is* the initializing signal
/// (there is no separate flow state for it), mirroring how the Android preview keys the initializing state on
/// a null surface.
struct CameraPreviewView: View {
    /// The running `AVCaptureSession` to draw, or `nil` while the scanner is still warming up / torn down.
    let session: AVCaptureSession?
    /// Whether the "hold steady" gathering cue should show in the single guidance region — takes precedence
    /// over `struggling`. Defaults to `false` so chrome-focused call sites don't need to thread it.
    var gathering: Bool = false
    /// Whether the "still looking / type it instead" struggling hint should show in the single guidance
    /// region — shown only when `gathering` is `false`. Defaults to `false`.
    var struggling: Bool = false
    /// The struggling hint's "type it instead" escape into manual entry. Defaults to a no-op so
    /// chrome-focused call sites don't need to thread it.
    var onManualEntry: () -> Void = {}
    /// Whether that escape is offered at all — mirrors the Android `showManualEntry` gating. Defaults to
    /// `true`.
    var showManualEntry: Bool = true

    var body: some View {
        ZStack {
            if let session {
                // Full-bleed viewfinder — deliberately NOT width-capped (only its overlaid controls are); it
                // stays immersive for scanning.
                PreviewLayerView(session: session)
                    .ignoresSafeArea()
                    .accessibilityIdentifier("tessera-mrz-viewfinder")
                // The MRZ guide (mockup 01): a dashed frame + the single guidance message below it, telling
                // the user to line up the document's bottom lines (the MRZ band). Apple Vision reads all text
                // in frame and the reader isolates the MRZ downstream; framing just the band gives a cleaner,
                // faster read — this guides that.
                MrzGuideOverlay(
                    gathering: gathering,
                    struggling: struggling,
                    onManualEntry: onManualEntry,
                    showManualEntry: showManualEntry
                )
            } else {
                InitializingContent()
            }
        }
        // Pinned to the bottom of the live preview and ALWAYS visible: the "What's the MRZ?" explainer.
        // Deliberately separate from the guidance region above (which swaps content by scan state), so the
        // explainer is never replaced and stays reachable in every scanning state. Only over a live preview
        // (once the session exists), sitting over the guide overlay's dark scrim so its text is light —
        // mirrors the Android `CameraPreview`'s `MrzExplainerLink` placement, `.align(Alignment.BottomCenter)`
        // after the guide overlay. ("Powered by Tessera" is the shared scaffold footer, below this screen.)
        .overlay(alignment: .bottom) {
            if session != nil {
                MrzExplainerLink()
                    .padding(.bottom, 12)
            }
        }
    }
}

/// The MRZ framing guide overlaid on the live preview (mockup 01) — a dashed rounded frame sitting low in the
/// view, where the machine-readable zone lands on a document held upright, plus ONE guidance message below it
/// (``guidanceMessage(gathering:struggling:)``): the "hold steady" gathering cue, the "still looking" struggle
/// hint, or the plain framing hint — never more than one at a time. Purely advisory — it never gates capture,
/// and the reader still isolates the MRZ from wherever it appears. The frame is decorative (hidden from
/// assistive tech); the guidance message carries the meaning as a spoken label. The message sits inside a
/// translucent dark rounded region (the same dimmed-scrim look the frame sits over) so it reads clearly
/// regardless of the live image behind it. Mirrors the Android `MrzGuideOverlay`
/// (`MrzScannerScreen.kt:1595-1694`).
private struct MrzGuideOverlay: View {
    var gathering: Bool = false
    var struggling: Bool = false
    var onManualEntry: () -> Void = {}
    var showManualEntry: Bool = true

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    Color.white.opacity(0.9),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
                .frame(height: 96)
                .padding(.horizontal, 24)
                .accessibilityHidden(true)

            guidanceRegion
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
        }
    }

    /// The ONE guidance message, in its translucent dark rounded region — gathering beats struggling beats
    /// the plain framing hint (the pure ``guidanceMessage(gathering:struggling:)`` decision).
    @ViewBuilder
    private var guidanceRegion: some View {
        Group {
            switch guidanceMessage(gathering: gathering, struggling: struggling) {
            case .gathering:
                GatheringHint()
            case .struggling:
                StrugglingHint(onManualEntry: onManualEntry, showManualEntry: showManualEntry)
            case .framingHint:
                Text(String(localized: "tessera_scanner_camera_guide", bundle: .module))
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(24)
                    .accessibilityIdentifier("tessera-mrz-guide-hint")
            }
        }
        .foregroundStyle(.white)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// A `UIViewRepresentable` wrapping a `UIView` whose backing layer *is* an `AVCaptureVideoPreviewLayer`
/// (via `layerClass`), so the preview draws with no extra sublayer to size. The layer's `session` is bound to
/// the scanner's session and `videoGravity` is `.resizeAspectFill` (per current AVFoundation guidance).
private struct PreviewLayerView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // Rebind only when the session identity changes — avoids tearing down a live connection on every
        // SwiftUI update.
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }
}

/// A `UIView` whose `layerClass` is `AVCaptureVideoPreviewLayer`, so the view's own layer renders the camera
/// feed directly.
private final class PreviewUIView: UIView {
    override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    // Force-cast is safe: `layerClass` above guarantees the backing layer's type.
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

/// The camera-initializing loading state (mockup 01b), shown while the scanner has not yet published a
/// session. A centred progress indicator over a title and an on-device honesty sub-line, so the moment before
/// the first frame is a clear "starting up" state. It auto-swaps to the live viewfinder the instant the
/// session arrives (no button, no timeout). Mirrors the Android `InitializingContent`.
struct InitializingContent: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .accessibilityHidden(true) // Decorative — the title carries the meaning.
            Text(String(localized: "tessera_scanner_initializing_title", bundle: .module))
                .font(.title2)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.updatesFrequently)
            Text(String(localized: "tessera_scanner_initializing_body", bundle: .module))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentMaxWidth()
        .accessibilityIdentifier("tessera-mrz-initializing")
    }
}
