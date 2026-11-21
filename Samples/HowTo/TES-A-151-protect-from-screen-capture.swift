// Sample for TES-A-151 "Protect the iOS scanner screen from screen capture".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.

import TesseraUI

// region TES-A-151 block 1
import SwiftUI
import UIKit

struct ScreenShield<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isCaptured = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .overlay { if isCaptured || scenePhase != .active { Color.black.ignoresSafeArea() } }
            .onAppear { isCaptured = Self.screenIsCaptured() }
            .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
                isCaptured = Self.screenIsCaptured()
            }
    }

    private static func screenIsCaptured() -> Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .contains { $0.screen.isCaptured }
    }
}
// endregion

struct ShieldedScanner: View {
    let config: MrzScannerConfig

    var body: some View {
        // region TES-A-151 block 2
        ScreenShield { MrzScannerView(config: config) { result in /* handle result */ } }
        // endregion
    }
}
