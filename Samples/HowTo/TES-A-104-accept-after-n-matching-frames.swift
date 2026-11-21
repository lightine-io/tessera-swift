// Sample for TES-A-104 "Accept a read after N matching frames on iOS".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// skip TES-A-104 block 1: Package.swift dependency lines

// region TES-A-104 block 2
import Tessera
// endregion

// region TES-A-104 block 3
@MainActor
final class AgreementGate {
    private let consensus = try! MrzDecodeConsensus(threshold: 2)   // a fixed, valid threshold
    private(set) var progress = ""

    func offer(_ result: MrzScanResult) -> MrzScanResultDecoded? {
        guard let decoded = result as? MrzScanResultDecoded,
              !(decoded.parse is ParseResult.Failure) else { return nil }
        switch consensus.offer(decoded: decoded) {
        case let confirmed as ConsensusVerdictConfirmed:
            return confirmed.decoded
        case let gathering as ConsensusVerdictGathering:
            progress = "\(gathering.agreement) of \(gathering.threshold)"
            return nil
        default:
            return nil
        }
    }

    func reset() { consensus.reset() }
}
// endregion

/// Stands in for the CameraReader of TES-A-18, which block 4 extends.
@MainActor
final class AgreementCameraReader {
    var scanner: AVCaptureMrzScanner?
    var collectTask: Task<Void, Never>?
    let onAgreed: (MrzScanResultDecoded) -> Void

    init(onAgreed: @escaping (MrzScanResultDecoded) -> Void) { self.onAgreed = onAgreed }

    // region TES-A-104 block 4
    // In CameraReader, next to scanner and collectTask:
    let gate = AgreementGate()

    func handle(_ result: MrzScanResult) {
        guard let agreed = gate.offer(result) else { return }
        onAgreed(agreed)   // your handler
    }
    // endregion

    func beginNewSession() {
        // region TES-A-104 block 5
        gate.reset()
        // endregion
    }
}

@MainActor
final class AgreementGateOfThree {
    // region TES-A-104 block 6
    private let consensus = try! MrzDecodeConsensus(threshold: 3)
    // endregion
}
