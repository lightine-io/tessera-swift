import AVFoundation
import Foundation
import Testing
@testable import TesseraUI

/// Host tests for the camera-permission hand-over (TES-343): the screen never requests the permission, so it
/// must notice the answer by itself and start the camera on a grant without any further action. The status is
/// played through ``ScannerModel/authorizationStatus`` and the camera start is seen through
/// ``ScannerModel/cameraStartOverride`` - no AVFoundation, no dialog.
@MainActor
struct ScannerModelPermissionTests {
    /// A permission status the test changes, as the system dialog would.
    final class FakeAuthorization {
        var status: AVAuthorizationStatus
        init(_ status: AVAuthorizationStatus) { self.status = status }
    }

    /// Set `TESSERA_PERMISSION_TRACE=1` in the test process (`TEST_RUNNER_TESSERA_PERMISSION_TRACE=1` for
    /// `xcodebuild test`) to print each status read, camera start and wait outcome. Fact-only: test names,
    /// status codes, counts and times; no document data exists here. Used by `.github/workflows/old-ios.yml`.
    private static let tracing = ProcessInfo.processInfo.environment["TESSERA_PERMISSION_TRACE"] == "1"

    private static func trace(_ test: String, _ message: @autoclosure () -> String) {
        guard tracing else { return }
        let seconds = Double(DispatchTime.now().uptimeNanoseconds) / 1e9
        print("permission-trace \(String(format: "%.3f", seconds)) \(test): \(message())")
    }

    private func makeModel(
        status: FakeAuthorization,
        onRequest: (@Sendable () -> Void)? = {},
        test: String = #function
    ) -> (ScannerModel, () -> Int) {
        let model = ScannerModel(config: MrzScannerConfig(onRequestPermission: onRequest), onResult: { _ in })
        var reads = 0
        model.authorizationStatus = {
            reads += 1
            let read = status.status
            Self.trace(test, "status read \(reads) = \(read.rawValue), main thread \(Thread.isMainThread)")
            return read
        }
        model.permissionPollInterval = 10_000_000
        var starts = 0
        model.cameraStartOverride = {
            starts += 1
            Self.trace(test, "camera start \(starts)")
        }
        return (model, { starts })
    }

    private func isScanning(_ model: ScannerModel) -> Bool {
        if case .scanning = model.state { return true }
        return false
    }

    /// Re-checks `condition` on the main actor every 10 ms until it holds, at most `checks` times.
    ///
    /// Counts checks, not wall-clock time (TES-343). Other `@MainActor` tests running in parallel can hold the
    /// main actor for a long time on a slow simulator (61 s on the iOS 16.4 cloud run, 27 s on iOS 17.5). A
    /// wall-clock deadline then runs out while this test waits for its turn, and the loop ends with one check
    /// made before the model's own main-actor work (the permission watcher) has had its turn. Counting checks
    /// gives the model a turn between every two checks however long the main actor was held.
    private func wait(
        checks: Int = 3_000,
        _ test: String = #function,
        _ model: ScannerModel,
        _ condition: () -> Bool
    ) async throws -> Bool {
        let start = DispatchTime.now().uptimeNanoseconds
        var last = start
        Self.trace(test, "wait begins, watcher running \(model.permissionWatchTask != nil), state \(model.state)")
        for check in 1 ... checks {
            if condition() {
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
                Self.trace(test, "met at check \(check) after \(String(format: "%.3f", elapsed)) s, state \(model.state)")
                return true
            }
            try await Task.sleep(nanoseconds: 10_000_000)
            let now = DispatchTime.now().uptimeNanoseconds
            if now - last > 500_000_000 {
                let gap = Double(now - last) / 1e9
                Self.trace(test, "check \(check): a 10 ms sleep took \(String(format: "%.3f", gap)) s (main actor held)")
            }
            last = now
        }
        let met = condition()
        Self.trace(test, "after \(checks) checks met \(met), watcher running \(model.permissionWatchTask != nil), state \(model.state)")
        return met
    }

    @Test func anUndecidedPermissionShowsTheGrantScreenAndDoesNotStartTheCamera() {
        let auth = FakeAuthorization(.notDetermined)
        let (model, starts) = makeModel(status: auth)
        model.onAppear()
        guard case .permissionNeeded = model.state else {
            Issue.record("an undecided permission must show the grant screen, got \(model.state)")
            return
        }
        #expect(starts() == 0)
        model.onDisappear()
    }

    @Test func aGrantAfterTheRequestStartsTheCameraWithNoFurtherAction() async throws {
        let auth = FakeAuthorization(.notDetermined)
        let (model, starts) = makeModel(status: auth)
        model.onAppear()
        model.requestPermission()
        // The person taps Allow in the system dialog. No scene-phase change, no second tap.
        auth.status = .authorized
        let started = try await wait(#function, model) { isScanning(model) && starts() == 1 }
        #expect(started, "the camera must start once the permission is granted; state \(model.state)")
        model.onDisappear()
    }

    @Test func aDenialAfterTheRequestShowsTheSettingsScreen() async throws {
        let auth = FakeAuthorization(.notDetermined)
        let (model, starts) = makeModel(status: auth)
        model.onAppear()
        model.requestPermission()
        auth.status = .denied
        let denied = try await wait(#function, model) {
            if case .permissionPermanentlyDenied = model.state { return true }
            return false
        }
        #expect(denied, "a denial must show the Settings screen; state \(model.state)")
        #expect(starts() == 0)
        model.onDisappear()
    }

    @Test func aGrantSeenWhenTheAppBecomesActiveStartsTheCamera() {
        // The host callback is present; the grant lands while the app is inactive behind the dialog.
        let auth = FakeAuthorization(.notDetermined)
        let (model, starts) = makeModel(status: auth)
        model.onAppear()
        model.requestPermission()
        auth.status = .authorized
        model.setForeground(false)
        model.setForeground(true)
        model.recheckPermissionOnForeground()
        #expect(isScanning(model), "state \(model.state)")
        #expect(starts() == 1)
        model.onDisappear()
    }

    @Test func becomingActiveBeforeTheStatusIsDecidedKeepsTheGrantScreenThenTheGrantStartsTheCamera() async throws {
        // The device report: Continue, the dialog, Allow, and the app is active again while the status still
        // reads undecided. That must not show the Settings face, and the grant that lands a moment later
        // must start the camera with no further action.
        let auth = FakeAuthorization(.notDetermined)
        let (model, starts) = makeModel(status: auth)
        model.onAppear()
        model.requestPermission()
        model.setForeground(false)
        model.setForeground(true)
        model.recheckPermissionOnForeground()
        guard case .permissionNeeded = model.state else {
            Issue.record("an undecided status after the request must keep the grant screen, got \(model.state)")
            model.onDisappear()
            return
        }
        auth.status = .authorized
        let started = try await wait(#function, model) { isScanning(model) && starts() == 1 }
        #expect(started, "state \(model.state)")
        model.onDisappear()
    }

    @Test func aRequestAnsweredBeforeTheCallbackReturnsStartsTheCameraAtOnce() {
        // A host whose request completes synchronously, or a status decided before the tap.
        let auth = FakeAuthorization(.notDetermined)
        let model = ScannerModel(
            config: MrzScannerConfig(onRequestPermission: {}),
            onResult: { _ in }
        )
        model.authorizationStatus = { auth.status }
        var starts = 0
        model.cameraStartOverride = { starts += 1 }
        model.onAppear()
        auth.status = .authorized
        model.requestPermission()
        #expect(isScanning(model), "state \(model.state)")
        #expect(starts == 1)
        model.onDisappear()
    }

    @Test func aGrantMadeOutsideTheScreenWithNoCallbackStartsTheCamera() async throws {
        // No host callback: the app asks for the permission its own way while the grant screen shows.
        let auth = FakeAuthorization(.notDetermined)
        let (model, starts) = makeModel(status: auth, onRequest: nil)
        model.onAppear()
        auth.status = .authorized
        let started = try await wait(#function, model) { isScanning(model) && starts() == 1 }
        #expect(started, "state \(model.state)")
        model.onDisappear()
    }

    @Test func anAlreadyGrantedPermissionStartsTheCameraOnAppear() {
        let auth = FakeAuthorization(.authorized)
        let (model, starts) = makeModel(status: auth)
        model.onAppear()
        #expect(isScanning(model))
        #expect(starts() == 1)
        model.onDisappear()
    }

    @Test func noTransitionOutOfAPermissionScreenCountsAsTheSameScreen() {
        // `updateState` skips a write only when `showsSameScreen` says so: every way out of a permission
        // face must count as a different screen, so it is never swallowed.
        let permissionFaces: [ScannerState] = [.permissionNeeded, .permissionPermanentlyDenied]
        let targets: [ScannerState] = [
            .scanning(struggling: false, gathering: false),
            .scanning(struggling: true, gathering: false),
            .scanning(struggling: false, gathering: true),
            .cameraInUse,
            .cameraUnavailable,
            .awaitingSavedImagePick,
            .savedImageAnalyzing,
            .savedImageEmpty,
            .manualRaw(text: "", parseFailed: false),
        ]
        for face in permissionFaces {
            for target in targets {
                #expect(!face.showsSameScreen(as: target), "\(face) -> \(target) must not be skipped")
                #expect(!target.showsSameScreen(as: face), "\(target) -> \(face) must not be skipped")
            }
        }
        #expect(!ScannerState.permissionNeeded.showsSameScreen(as: .permissionPermanentlyDenied))
        #expect(!ScannerState.permissionPermanentlyDenied.showsSameScreen(as: .permissionNeeded))
    }
}
