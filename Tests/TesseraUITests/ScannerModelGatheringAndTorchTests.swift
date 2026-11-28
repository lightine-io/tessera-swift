import AVFoundation
import Foundation
import Tessera
import Testing
@testable import TesseraUI

/// TES-336: two scanner behaviours the simulator cannot show (it has no camera): the "hold steady" cue that
/// clears 0.6 s after the last decode, and the torch switch with its icon. Both run through ``ScannerModel``
/// with stand-ins: a fake clock (``ScannerModel/notAcceptedClock``) and a fake torch device
/// (``ScannerModel/torchDeviceOverride``).
@MainActor
struct ScannerModelGatheringAndTorchTests {
    private final class FakeTorch: TorchDevice {
        var hasTorch = true
        var isTorchAvailable = true
        var torchMode: AVCaptureDevice.TorchMode = .off
        var failLock = false
        var lockCalls = 0
        var unlockCalls = 0
        struct LockFailed: Error {}
        func lockForConfiguration() throws {
            lockCalls += 1
            if failLock { throw LockFailed() }
        }
        func unlockForConfiguration() { unlockCalls += 1 }
    }

    private func model(_ device: FakeTorch?, torchOnByDefault: Bool = false) -> ScannerModel {
        let model = ScannerModel(config: MrzScannerConfig(torchOnByDefault: torchOnByDefault), onResult: { _ in })
        model.torchDeviceOverride = { device }
        return model
    }

    // MARK: - Gathering cue

    private var passport: MrzScanResultDecoded {
        assembleManualDecoded(text: AcceptedDocumentTypesTests.passportLines.joined(separator: "\n"))
    }

    private func noMrz() -> MrzScanResultNoMrzFound {
        MrzScanResultNoMrzFound(
            recognizedText: RecognizedText(lines: []),
            quality: ScanQuality(mrzRegionFound: false, ocrConfidence: nil, recognizedLineCount: 0))
    }

    private func gathering(_ model: ScannerModel) -> Bool {
        if case let .scanning(_, gathering, _) = model.state { return gathering }
        return false
    }

    @Test func theHoldSteadyCueStaysForHalfASecondAndClearsAfterSixTenths() {
        let model = ScannerModel(config: MrzScannerConfig(), onResult: { _ in })
        var now = Date(timeIntervalSince1970: 0)
        model.notAcceptedClock = { now }

        model.onCameraResult(passport)
        #expect(gathering(model), "the first agreeing-so-far frame shows the cue")

        now += 0.5
        model.onCameraResult(noMrz())
        #expect(gathering(model), "a miss within the linger keeps it")

        now += 0.2 // 0.7 s after the last decode
        model.onCameraResult(noMrz())
        #expect(!gathering(model), "more than 0.6 s with no decode clears it")
        if case .scanning = model.state {} else { Issue.record("still scanning") }
    }

    // MARK: - Torch

    @Test func withNoDeviceThereIsNoTorch() {
        let model = ScannerModel(config: MrzScannerConfig(), onResult: { _ in })
        #expect(!model.hasTorch)
        model.toggleTorch()
        #expect(!model.torchOn)
    }

    @Test func togglingSwitchesTheDeviceAndTheModelOnAndOff() {
        let device = FakeTorch()
        let model = model(device)
        #expect(model.hasTorch)
        model.toggleTorch()
        #expect(device.torchMode == .on && model.torchOn)
        #expect(device.lockCalls == 1 && device.unlockCalls == 1)
        model.toggleTorch()
        #expect(device.torchMode == .off && !model.torchOn)
    }

    @Test func aFailedLockLeavesTheTorchOffAndTheDeviceUntouched() {
        let device = FakeTorch()
        device.failLock = true
        let model = model(device)
        model.toggleTorch()
        #expect(!model.torchOn)
        #expect(device.torchMode == .off)
        #expect(device.unlockCalls == 0)
    }

    @Test func anUnavailableTorchIsNotTouched() {
        let device = FakeTorch()
        device.isTorchAvailable = false
        let model = model(device)
        model.toggleTorch()
        #expect(!model.torchOn)
        #expect(device.torchMode == .off && device.lockCalls == 0)

        let noTorch = FakeTorch()
        noTorch.hasTorch = false
        let other = self.model(noTorch)
        #expect(!other.hasTorch)
        other.toggleTorch()
        #expect(!other.torchOn && noTorch.lockCalls == 0)
    }

    @Test func torchOnByDefaultTurnsItOnOnceAndStoppingResetsIt() {
        let device = FakeTorch()
        let model = model(device, torchOnByDefault: true)
        model.applyPreviewSession(AVCaptureSession())
        #expect(model.torchOn && device.torchMode == .on)

        // Turned off by the user, a later session update does not force it back on.
        model.toggleTorch()
        #expect(!model.torchOn)
        model.applyPreviewSession(AVCaptureSession())
        #expect(!model.torchOn && device.torchMode == .off)

        model.toggleTorch()
        #expect(model.torchOn)
        model.onDisappear()
        #expect(!model.torchOn, "stopping resets the flag")

        // A fresh start applies the default again.
        model.applyPreviewSession(AVCaptureSession())
        #expect(model.torchOn)
        model.onDisappear()
    }

    @Test func theIconIsTheFilledBoltWhenOnAndTheSlashedBoltWhenOff() {
        #expect(torchIconName(on: true) == "bolt.fill")
        #expect(torchIconName(on: false) == "bolt.slash.fill")
    }
}
