import Observation
import SwiftUI
import Testing
import UIKit
@testable import TesseraUI

/// Host tests for TES-155: the configuration is fixed per presentation. The scanner reads it when it opens;
/// a change while it is open applies the next time it opens.
///
/// Opening the scanner is modelled as inserting ``MrzScannerView`` into a hosted hierarchy, which gives it a new
/// view identity, as each `fullScreenCover` presentation does. No modal presentation is involved: UIKit
/// presentation and dismissal in a package test host are slow and timing-dependent. Each render of the scanner
/// is reported through ``EnvironmentValues/scannerRenderProbe``.
@MainActor
@Suite(.serialized)
struct ScannerConfigPresentationTests {
    private static let everyMethod: Set<ScanMethod> = [.camera, .savedImage, .manualEntry]
    private static let noCamera: Set<ScanMethod> = [.savedImage, .manualEntry]

    @MainActor
    @Observable
    final class Host {
        var config: MrzScannerConfig
        var open = false
        @ObservationIgnored var lastRender: ScannerRender?
        /// The config the host's own body last rendered with.
        @ObservationIgnored var hostRenderedMethods: Set<ScanMethod>?
        @ObservationIgnored private(set) lazy var probe = ScannerRenderProbe { [unowned self] in self.lastRender = $0 }
        init(config: MrzScannerConfig) { self.config = config }
    }

    struct HostView: View {
        let host: Host
        var body: some View {
            let config = host.config
            let _ = { host.hostRenderedMethods = config.enabledMethods }()
            ZStack {
                Color.clear
                if host.open {
                    MrzScannerView(config: config) { _ in host.open = false }
                        .environment(\.scannerRenderProbe, host.probe)
                }
            }
        }
    }

    @Test func theScannerUsesTheConfigGivenWhenItOpens() async throws {
        let host = Host(config: MrzScannerConfig(enabledMethods: Self.everyMethod))
        let window = show(HostView(host: host))
        defer { window.isHidden = true }
        try await update(window) { host.hostRenderedMethods == Self.everyMethod }

        // The host is built with the first config; the config changes before the scanner opens.
        host.config = MrzScannerConfig(enabledMethods: Self.noCamera)
        try await update(window) { host.hostRenderedMethods == Self.noCamera }
        host.open = true
        try await update(window) { host.lastRender != nil }

        let render = try #require(host.lastRender)
        #expect(render.model.config.enabledMethods == Self.noCamera)
        #expect(render.switcherMethods == Self.noCamera)
        #expect(!render.model.state.isCameraState)
    }

    @Test func aChangeWhileOpenWaitsForTheNextOpening() async throws {
        let host = Host(config: MrzScannerConfig(enabledMethods: Self.noCamera))
        let window = show(HostView(host: host))
        defer { window.isHidden = true }
        host.open = true
        try await update(window) { host.lastRender != nil }
        let opened = try #require(host.lastRender)
        #expect(opened.switcherMethods == Self.noCamera)

        // Changed while open: the open scanner keeps its config, the switcher included. SwiftUI may skip the
        // scanner's render when nothing it reads has changed; any render that does happen must use the old config.
        host.lastRender = nil
        host.config = MrzScannerConfig(enabledMethods: Self.everyMethod)
        try await update(window) { host.hostRenderedMethods == Self.everyMethod }
        try await flush(window)
        if let afterChange = host.lastRender {
            #expect(afterChange.model === opened.model)
            #expect(afterChange.model.config.enabledMethods == Self.noCamera)
            #expect(afterChange.switcherMethods == Self.noCamera)
        }

        // Closed, then opened again: the new opening uses the new config.
        host.open = false
        try await flush(window)
        host.lastRender = nil
        host.open = true
        try await update(window) { host.lastRender != nil }
        let reopened = try #require(host.lastRender)
        #expect(reopened.model !== opened.model)
        #expect(reopened.model.config.enabledMethods == Self.everyMethod)
        #expect(reopened.switcherMethods == Self.everyMethod)
    }

    // MARK: - Hosting

    private func show(_ view: some View) -> UIWindow {
        // The package test host has no window scene; a scene-less window still lays out and renders SwiftUI.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        return window
    }

    /// Lets SwiftUI apply pending updates until `condition` holds; fails the test after 10 seconds.
    private func update(_ window: UIWindow, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("SwiftUI did not apply the update in time")
                throw CancellationError()
            }
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Lets SwiftUI apply any further pending updates.
    private func flush(_ window: UIWindow) async throws {
        for _ in 0..<20 {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private extension ScannerState {
    var isCameraState: Bool {
        switch self {
        case .scanning, .permissionNeeded, .permissionPermanentlyDenied, .cameraInUse, .cameraUnavailable:
            return true
        default:
            return false
        }
    }
}
