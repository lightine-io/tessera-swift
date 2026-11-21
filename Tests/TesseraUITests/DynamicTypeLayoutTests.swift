import SwiftUI
import Tessera
import Testing
import UIKit
@testable import TesseraUI

/// TES-58: the scanner screens at large Dynamic Type sizes.
///
/// Each screen is laid out by SwiftUI in a hosting controller, on the narrowest iPhone width iOS 18 runs on, at
/// the largest text sizes. Two things must hold: the screen's text grows with the text size, and nothing makes
/// the screen wider than the phone (text that cannot wrap would be cut off at the edge). A raw MRZ line is
/// exempt by design: `MonoLine` scrolls it sideways rather than wrapping it, inside the screen's width.
///
/// Not covered: the shared top bar and the "What's the MRZ?" sheet (both sit in a system navigation stack, which
/// reports a fixed size here), the camera preview (it needs a camera), and how the result looks; that stays a
/// manual check on a device.
@MainActor
struct DynamicTypeLayoutTests {
    /// The narrowest iPhone screen width iOS 18 supports, in points.
    private static let narrowestWidth: CGFloat = 375

    // The published ICAO Doc 9303 TD3 specimen.
    private static let specimen = """
    P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<
    L898902C36UTO7408122F1204159ZE184226B<<<<<10
    """

    private static var capturedSpecimen: RecognizedText {
        RecognizedText(lines: specimen.split(separator: "\n").map { RecognizedLine(text: String($0), confidence: nil) })
    }

    enum Screen: String, CaseIterable {
        case permissionNeedsGrant, permissionDenied, cameraInUse, cameraUnavailable
        case readFailed, choosePhoto, analyzingPhoto, noMrzInPhoto
        case manualEntry, review, reviewAllFields
        case initializing, strugglingHint, gatheringHint
    }

    private func view(_ screen: Screen) -> AnyView {
        switch screen {
        case .permissionNeedsGrant:
            AnyView(PermissionScreen(state: .needsGrant, onGrant: {}, onOpenSettings: {}, onManualEntry: {},
                                     hasRequestHandler: true, showManualEntry: true))
        case .permissionDenied:
            AnyView(PermissionScreen(state: .permanentlyDenied, onGrant: {}, onOpenSettings: {}, onManualEntry: {},
                                     hasRequestHandler: true, showManualEntry: true))
        case .cameraInUse:
            AnyView(CameraInUseScreen(onManualEntry: {}, showManualEntry: true))
        case .cameraUnavailable:
            AnyView(CameraUnavailableScreen(onManualEntry: {}, showManualEntry: true))
        case .readFailed:
            AnyView(ReadFailedScreen(capturedText: Self.capturedSpecimen, onTryAgain: {},
                                     onManualEntry: {}, showManualEntry: true))
        case .choosePhoto:
            AnyView(AwaitingSavedImagePickScreen(onChoosePhoto: {}))
        case .analyzingPhoto:
            AnyView(SavedImageAnalyzingScreen())
        case .noMrzInPhoto:
            AnyView(SavedImageEmptyScreen(onChooseDifferent: {}, onManualEntry: {}, showManualEntry: true))
        case .manualEntry:
            AnyView(ManualEntryScreen(text: Self.specimen, parseFailed: true, onTextChange: { _ in }, onRead: {}))
        case .review:
            AnyView(ReviewScreen(decoded: assembleManualDecoded(text: Self.specimen), expanded: false,
                                 source: .camera, onToggleExpanded: {}, onUse: {}, onRescan: {}))
        case .reviewAllFields:
            AnyView(ReviewScreen(decoded: assembleManualDecoded(text: Self.specimen), expanded: true,
                                 source: .camera, onToggleExpanded: {}, onUse: {}, onRescan: {}))
        case .initializing:
            AnyView(InitializingContent())
        case .strugglingHint:
            AnyView(StrugglingHint(onManualEntry: {}, showManualEntry: true))
        case .gatheringHint:
            AnyView(GatheringHint())
        }
    }

    /// The size SwiftUI gives the screen at `textSize`, offered the narrowest width and unlimited height.
    private func fittedSize(_ screen: Screen, _ textSize: DynamicTypeSize) -> CGSize {
        let host = UIHostingController(rootView: view(screen).environment(\.dynamicTypeSize, textSize))
        return host.sizeThatFits(in: CGSize(width: Self.narrowestWidth, height: .greatestFiniteMagnitude))
    }

    @Test(arguments: Screen.allCases)
    func theScreenStaysWithinThePhoneWidthAtLargeTextSizes(_ screen: Screen) {
        // Two sizes, the largest standard one and the largest accessibility one: every layout here runs on the
        // main actor, and on a slow CI runner four sizes per screen kept it busy long enough to time out
        // other suites' waits.
        for textSize in [DynamicTypeSize.xxxLarge, .accessibility5] {
            let width = fittedSize(screen, textSize).width
            #expect(width <= Self.narrowestWidth + 0.5, "\(screen) at \(textSize) is \(width) points wide")
        }
    }

    @Test(arguments: Screen.allCases)
    func theScreenTextGrowsWithTheTextSize(_ screen: Screen) {
        let standard = fittedSize(screen, .large).height
        let largest = fittedSize(screen, .accessibility5).height
        #expect(largest > standard * 1.5, "\(screen): \(standard) points tall at the default size, \(largest) at the largest")
    }

    @Test func theCheckCatchesTextThatCannotWrap() {
        // Check the check: a line that refuses to wrap is wider than the phone at a large text size.
        let line = Text(ScannerControl.reviewShowAll.label(bundle: nil)).lineLimit(1).fixedSize()
        let host = UIHostingController(rootView: line.environment(\.dynamicTypeSize, .accessibility5))
        let size = host.sizeThatFits(in: CGSize(width: Self.narrowestWidth, height: .greatestFiniteMagnitude))
        #expect(size.width > Self.narrowestWidth)
    }
}
