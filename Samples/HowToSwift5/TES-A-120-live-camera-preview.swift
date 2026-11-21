// Sample for TES-A-120 "Show a live camera preview on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// Swift 5 language mode, the settings of TES-A-18 that this page builds on. In Swift 6 mode block 4 does not compile.
// skip TES-A-120 block 1: Package.swift dependency lines

// region TES-A-120 block 2
import AVFoundation
import SwiftUI
import Tessera

func startWithPreview(_ scanner: AVCaptureMrzScanner) {
    scanner.enablePreview()   // before start()
    scanner.start()
}
// endregion

// region TES-A-120 block 3
final class SessionCollector: NSObject, Kotlinx_coroutines_coreFlowCollector {
    private let onSession: (AVCaptureSession?) -> Void
    init(_ onSession: @escaping (AVCaptureSession?) -> Void) { self.onSession = onSession }

    func emit(value: Any?) async throws { onSession(value as? AVCaptureSession) }
}
// endregion

// region TES-A-120 block 4
func watchPreview(of scanner: AVCaptureMrzScanner, update: @escaping @MainActor (AVCaptureSession?) -> Void) -> Task<Void, Never> {
    let collector = SessionCollector { session in
        Task { @MainActor in update(session) }
    }
    return Task { try? await scanner.previewSession.collect(collector: collector) }
}
// endregion

// region TES-A-120 block 5
final class PreviewUIView: UIView {
    override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession?

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewUIView, context: Context) {
        if view.previewLayer.session !== session { view.previewLayer.session = session }
    }
}
// endregion

// region TES-A-120 block 6
@MainActor
final class PreviewState: ObservableObject {
    @Published var session: AVCaptureSession?
    var watcher: Task<Void, Never>?

    func attach(to scanner: AVCaptureMrzScanner) {
        watcher = watchPreview(of: scanner) { [weak self] session in self?.session = session }
    }
}

struct ScannerScreen: View {
    @ObservedObject var state: PreviewState

    var body: some View {
        CameraPreview(session: state.session).ignoresSafeArea()
    }
}
// endregion

// region TES-A-120 block 7
@MainActor
func showWholeFrame(_ view: PreviewUIView) {
    view.previewLayer.videoGravity = .resizeAspect
}
// endregion
