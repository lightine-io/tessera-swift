// Sample for TES-A-107 "Aim autofocus at the MRZ guide on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-107 block 1: Package.swift dependency lines

// region TES-A-107 block 2
import AVFoundation
import Tessera
// endregion

// region TES-A-107 block 3
func metadataRegion(of guide: CGRect, in preview: AVCaptureVideoPreviewLayer) -> CGRect? {
    guard preview.connection != nil else { return nil }
    let region = preview.metadataOutputRectConverted(fromLayerRect: guide)
    return region.isNull || region.isEmpty ? nil : region
}
// endregion

// region TES-A-107 block 4
func aimFocus(_ scanner: AVCaptureMrzScanner, at region: CGRect) {
    scanner.focusOnRegion(
        x: region.origin.x,
        y: region.origin.y,
        width: region.size.width,
        height: region.size.height
    )
}
// endregion

// region TES-A-107 block 5
func onSessionStart(_ session: AVCaptureSession, perform action: @escaping @Sendable () -> Void) -> NSObjectProtocol {
    NotificationCenter.default.addObserver(
        forName: AVCaptureSession.didStartRunningNotification,
        object: session,
        queue: .main
    ) { _ in action() }
}
// endregion

// region TES-A-107 block 6
func aimBoth(_ scanner: AVCaptureMrzScanner, _ recognizer: VisionMrzTextRecognizer, at region: CGRect) {
    aimFocus(scanner, at: region)
    recognizer.restrictToMrzBand(x: region.origin.x, y: region.origin.y, width: region.size.width, height: region.size.height)
}
// endregion
