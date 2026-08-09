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
    /// Reports the guide box's on-screen region converted into AVFoundation's metadata-output space
    /// (normalized against the unrotated capture buffer, top-left origin — what
    /// `metadataOutputRectOfInterest(for:)` returns), whenever layout resolves or changes. The model feeds
    /// it to the recognizer so OCR reads exactly the band the user sees — the iOS mirror of Android's
    /// ViewPort WYSIWYG alignment (an aspect-fill preview crops the frame and the guide sits low, so the
    /// on-screen band is NOT a centred fraction of the buffer). Defaults to a no-op so chrome-focused call
    /// sites don't need to thread it.
    var onMetadataGuideRegion: (CGRect) -> Void = { _ in }

    /// The guide box's current frame in global (window) coordinates, measured by the overlay and consumed
    /// by the preview layer view, which converts it into metadata-output space (only that view holds the
    /// `AVCaptureVideoPreviewLayer` the conversion needs).
    @State private var guideGlobalFrame: CGRect?

    var body: some View {
        ZStack {
            if let session {
                // Full-bleed viewfinder — deliberately NOT width-capped (only its overlaid controls are); it
                // stays immersive for scanning.
                PreviewLayerView(
                    session: session,
                    guideGlobalFrame: guideGlobalFrame,
                    onMetadataGuideRegion: onMetadataGuideRegion
                )
                    .ignoresSafeArea()
                    .accessibilityIdentifier("tessera-mrz-viewfinder")
                // The MRZ guide (mockup 01): a dashed frame + the single guidance message below it, telling
                // the user to line up the document's bottom lines (the MRZ band). Apple Vision reads all text
                // in frame and the reader isolates the MRZ downstream; framing just the band gives a cleaner,
                // faster read — this guides that.
                // Expanded as a WHOLE (not just its scrim): the scrim, dashed frame, and guidance must
                // share one coordinate space or the punched hole and the frame drift apart; and with the
                // preview itself full-bleed, the guide window centres on the full screen exactly like the
                // image behind it.
                MrzGuideOverlay(
                    gathering: gathering,
                    struggling: struggling,
                    onManualEntry: onManualEntry,
                    showManualEntry: showManualEntry,
                    onGuideFrame: { guideGlobalFrame = $0 }
                )
                .ignoresSafeArea()
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

/// The MRZ framing guide overlaid on the live preview (mockup 01) — a ~70%-black scrim covering the whole
/// preview with the guide window punched out (even-odd fill), a dashed rounded frame on the window, and ONE
/// guidance message below it (``guidanceMessage(gathering:struggling:)``): the "hold steady" gathering cue,
/// the "still looking" struggle hint, or the plain framing hint — never more than one at a time. The window
/// is horizontally inset, a fixed band height, and vertically CENTRED — the shared geometry Android's
/// overlay derives everything from (`MrzScannerScreen.kt` `MrzGuideOverlay`), so the scrim, frame, and
/// guidance can never drift apart, and the OCR band + focus region follow the window wherever layout puts
/// it (the WYSIWYG plumbing reports its real frame). Purely advisory — it never gates capture. The scrim
/// and frame are decorative (hidden from assistive tech); the guidance message carries the meaning.
private struct MrzGuideOverlay: View {
    var gathering: Bool = false
    var struggling: Bool = false
    var onManualEntry: () -> Void = {}
    var showManualEntry: Bool = true
    /// Reports the guide box's frame in global (window) coordinates whenever layout resolves or changes,
    /// so the preview layer can align the OCR band and the focus region with what the user actually sees.
    var onGuideFrame: (CGRect) -> Void = { _ in }

    private let horizontalMargin: CGFloat = 24
    private let bandHeight: CGFloat = 96
    private let cornerRadius: CGFloat = 10

    var body: some View {
        GeometryReader { geometry in
            let window = CGRect(
                x: horizontalMargin,
                y: (geometry.size.height - bandHeight) / 2,
                width: geometry.size.width - horizontalMargin * 2,
                height: bandHeight
            )
            ZStack(alignment: .topLeading) {
                // The dimmed surround with the guide window punched out — Android's 70%-black even-odd
                // scrim, so the MRZ target stands out and the guidance reads against a consistent dark
                // backdrop rather than the live image.
                // No .ignoresSafeArea() HERE: expanding only the scrim shifts the shape's drawing rect
                // relative to the geometry the window was computed in, so the punched hole lands ~a
                // nav-bar-height above the dashed frame (device-verified in the camera-only config). The
                // whole overlay expands together at the call site instead — one shared coordinate space.
                CutoutScrimShape(window: window, cornerRadius: cornerRadius)
                    .fill(Color.black.opacity(0.7), style: FillStyle(eoFill: true))
                    .accessibilityHidden(true)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        Color.white.opacity(0.9),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                    )
                    .frame(width: window.width, height: window.height)
                    // Measure the SIZED box (before .position wraps it): the geometry here is the box's
                    // real global frame after placement.
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: onGuideFrame)
                    // .position, NOT .offset: offset translates only the RENDERING and leaves the layout
                    // frame behind at the stack origin — the geometry measurement would then report the box
                    // at the top-left corner and aim the OCR band + focus there (device-verified TES-132: a
                    // dead-centre window measured as x≈0.07 in buffer space).
                    .position(x: window.midX, y: window.midY)
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    Color.clear.frame(height: window.maxY + 12)
                    guidanceRegion
                        .padding(.horizontal, 24)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// The full-cover rect plus the guide window's rounded rect — filled even-odd, the window is punched
    /// out of the scrim (the SwiftUI mirror of Android's `PathFillType.EvenOdd` scrim path).
    private struct CutoutScrimShape: Shape {
        let window: CGRect
        let cornerRadius: CGFloat

        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.addRect(rect)
            path.addRoundedRect(in: window, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
            return path
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
    /// The guide box's frame in global (window) coordinates, or `nil` while its layout hasn't resolved.
    var guideGlobalFrame: CGRect?
    /// Receives the guide frame converted into metadata-output space (see `CameraPreviewView`).
    var onMetadataGuideRegion: (CGRect) -> Void = { _ in }

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        view.observeSessionStart(session)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // Rebind only when the session identity changes — avoids tearing down a live connection on every
        // SwiftUI update.
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
            uiView.observeSessionStart(session)
        }
        uiView.guideGlobalFrame = guideGlobalFrame
        uiView.onMetadataGuideRegion = onMetadataGuideRegion
    }
}

/// A `UIView` whose `layerClass` is `AVCaptureVideoPreviewLayer`, so the view's own layer renders the camera
/// feed directly. It also owns the guide-region conversion: only this view holds the preview layer, and only
/// `metadataOutputRectOfInterest(for:)` knows how the layer's `videoGravity` crop and the connection's
/// rotation map on-screen points to buffer coordinates — so the conversion happens here, re-run on layout
/// and re-checked until the layer's connection exists (before that the conversion has no camera geometry to
/// use and returns garbage).
private final class PreviewUIView: UIView {
    override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    // Force-cast is safe: `layerClass` above guarantees the backing layer's type.
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    /// The guide box's frame in global (window) coordinates; setting it (re)attempts the conversion.
    var guideGlobalFrame: CGRect? {
        didSet { if guideGlobalFrame != oldValue { convertGuideRegion() } }
    }

    /// Receives the successfully converted metadata-output rect.
    var onMetadataGuideRegion: (CGRect) -> Void = { _ in }

    /// The last rect delivered, so layout passes that change nothing don't re-fire the callback.
    private var lastDelivered: CGRect?

    /// Re-converts once the capture session actually STARTS RUNNING. A conversion made while the
    /// connection's geometry is still settling returns garbage (device-verified TES-132: a dead-centre
    /// window converted to a focus point at x≈0.07), and the change-dedupe would then pin that stale rect
    /// forever — layout alone is not a reliable retrigger because session start does not necessarily
    /// relayout the hosting view. The stored rect is invalidated so the fresh conversion always re-fires.
    // nonisolated(unsafe): deinit is nonisolated in Swift 6 and only reads the token to unregister it; the
    // view is main-actor-bound, so there is no concurrent access in practice.
    private nonisolated(unsafe) var sessionStartObserver: NSObjectProtocol?

    func observeSessionStart(_ session: AVCaptureSession) {
        if let observer = sessionStartObserver { NotificationCenter.default.removeObserver(observer) }
        sessionStartObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionDidStartRunning,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.lastDelivered = nil
            self?.convertGuideRegion()
        }
        // The scanner publishes the session only after starting it, so it may already be running when the
        // viewfinder attaches — no DidStartRunning will ever fire then. Re-convert on the next main-queue
        // hop (after the layer binds its connection) with the same invalidation.
        if session.isRunning {
            DispatchQueue.main.async { [weak self] in
                self?.lastDelivered = nil
                self?.convertGuideRegion()
            }
        }
    }

    deinit {
        if let observer = sessionStartObserver { NotificationCenter.default.removeObserver(observer) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The layer's connection appears only once the session wires up; retrying here covers layout
        // changes, and observeSessionStart covers the connection's geometry becoming valid.
        convertGuideRegion()
    }

    private func convertGuideRegion() {
        guard let globalFrame = guideGlobalFrame, previewLayer.connection != nil, window != nil else { return }
        // SwiftUI's `.global` space is the window's coordinate space; `convert(_:from: nil)` converts from
        // the window/screen base space into this view's — which IS the preview layer's coordinate space
        // (the layer backs this view directly via `layerClass`).
        let layerRect = convert(globalFrame, from: nil)
        let metadataRect = previewLayer.metadataOutputRectConverted(fromLayerRect: layerRect)
        guard !metadataRect.isNull, !metadataRect.isEmpty, metadataRect != lastDelivered else { return }
        lastDelivered = metadataRect
        onMetadataGuideRegion(metadataRect)
    }
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
