import Combine
import PhotosUI
import SwiftUI
import Tessera
import Testing
import UIKit
@testable import TesseraUI

/// The old-iOS paths of the shims in `Sources/TesseraUI/Compat/`, run on a current iOS through
/// ``Compat/forceLegacy``. Each screen that uses a shim is hosted and laid out with the switch on; the test
/// checks it renders and that the shim's old path ran (``Compat/legacyPathsTaken``). How the old path looks on
/// a real iOS 15 or 16 device stays a manual check.
///
/// Every test here is synchronous on the main actor and turns the switch off again before it returns, so no
/// other suite's main-actor work can run while it is on.
@MainActor
@Suite(.serialized)
struct CompatLegacyPathTests {
    // The project's own TD3 specimen (synthetic).
    private static let specimen = """
    P<UTOSPECIMEN<<ALEX<MORGAN<<<<<<<<<<<<<<<<<<
    T220001293UTO9003152F3403141S98765432<<<<<20
    """
    private static let specimenLine = "P<UTOSPECIMEN<<ALEX<MORGAN<<<<<<<<<<<<<<<<<<"

    /// Runs `body` with every shim on its old path, starting from an empty record, and turns the switch off
    /// again. Returns the shims whose old path ran.
    @discardableResult
    private func withLegacyPaths(_ body: () throws -> Void) rethrows -> Set<CompatShim> {
        Compat.legacyPathsTaken = []
        Compat.forceLegacy = true
        defer {
            Compat.forceLegacy = false
        }
        try body()
        return Compat.legacyPathsTaken
    }

    /// Hosts `view` in a window of `width` points and lays it out a few times, so state set by a layout
    /// callback (a measured width, a preference) is applied. Returns the hosting controller.
    @discardableResult
    private func host(_ view: some View, width: CGFloat = 402, height: CGFloat = 874) -> UIViewController {
        // The package test host has no window scene; a scene-less window still lays out and renders SwiftUI.
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
        let controller = UIHostingController(rootView: view)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        for _ in 0..<4 {
            controller.view.setNeedsLayout()
            window.layoutIfNeeded()
        }
        window.isHidden = true
        return controller
    }

    // MARK: - The switch

    @Test func theSwitchIsOffByDefaultAndTheModernPathsRun() {
        #expect(Compat.forceLegacy == false)
        Compat.legacyPathsTaken = []
        host(ManualEntryScreen(text: Self.specimen, parseFailed: false, onTextChange: { _ in }, onRead: {}))
        host(MonoLine(Self.specimenLine), width: 320)
        // Check the check: with the switch off, a current iOS takes no old path at all.
        #expect(Compat.legacyPathsTaken.isEmpty)
    }

    // MARK: - Screens

    @Test func theScaffoldRendersWithTheOldNavigationAndToolbar() {
        for timeRemaining in [nil, 30] as [TimeInterval?] {
            let taken = withLegacyPaths {
                host(ScannerScaffold(
                    enabledMethods: [.camera, .manualEntry],
                    currentState: .scanning(struggling: false, gathering: false),
                    onClose: {},
                    onSelectMethod: { _ in },
                    timeRemaining: timeRemaining
                ) {
                    Text(verbatim: "content")
                })
            }
            #expect(taken.isSuperset(of: [.navigationStack, .toolbarOptionalItem]),
                    "countdown \(String(describing: timeRemaining)): \(taken)")
        }
    }

    @Test func theExplainerRendersWithTheOldNavigation() {
        let taken = withLegacyPaths {
            host(MrzExplainerDialog(onDismiss: {}))
        }
        #expect(taken.contains(.navigationStack), "\(taken)")
    }

    /// TES-344: the explainer, with its magnified zone, on the old navigation at the narrowest width and the
    /// largest text size, in light and dark.
    @Test(arguments: [ColorScheme.light, .dark])
    func theExplainerPictureRendersOnTheOldPathAtTheLargestTextSize(_ scheme: ColorScheme) {
        var dialog = CGSize.zero
        var picture = CGSize.zero
        let taken = withLegacyPaths {
            let controller = host(
                MrzExplainerDialog(onDismiss: {})
                    .environment(\.dynamicTypeSize, .accessibility5)
                    .environment(\.colorScheme, scheme),
                width: 320, height: 568
            )
            dialog = controller.view.bounds.size
            let pictureHost = UIHostingController(rootView: MrzExplainerPicture()
                .environment(\.dynamicTypeSize, .accessibility5)
                .environment(\.colorScheme, scheme))
            picture = pictureHost.sizeThatFits(in: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude))
        }
        #expect(taken.contains(.navigationStack), "\(taken)")
        #expect(dialog.width == 320 && dialog.height > 0, "\(dialog)")
        #expect(picture.width <= 320.5 && picture.height.isFinite && picture.height > 0, "\(picture)")
    }

    @Test func manualEntryRendersWithTheOldKeyboardDismissal() {
        let taken = withLegacyPaths {
            host(ManualEntryScreen(text: Self.specimen, parseFailed: true, onTextChange: { _ in }, onRead: {}))
        }
        #expect(taken.contains(.scrollDismissesKeyboard), "\(taken)")
    }

    @Test func reviewAndReadFailedRenderTheRawLinesWithTheOldFit() {
        let decoded = assembleManualDecoded(text: Self.specimen)
        let captured = RecognizedText(lines: Self.specimen.split(separator: "\n").map {
            RecognizedLine(text: String($0), confidence: nil)
        })
        let taken = withLegacyPaths {
            host(ReviewScreen(decoded: decoded, expanded: true, source: .camera,
                              onToggleExpanded: {}, onUse: {}, onRescan: {}))
            host(ReadFailedScreen(capturedText: captured, onTryAgain: {}, onManualEntry: {}, showManualEntry: true))
        }
        #expect(taken.contains(.viewThatFits), "\(taken)")
    }

    @Test func theRootScreenRendersWithTheOldHapticPickerAndChangeHandlers() {
        let config = MrzScannerConfig(enabledMethods: [.savedImage, .manualEntry])
        let taken = withLegacyPaths {
            host(MrzScannerView(config: config) { _ in })
        }
        #expect(taken.isSuperset(of: [.sensoryFeedback, .photosPicker, .onChange, .navigationStack]), "\(taken)")
    }

    // MARK: - MonoLine at a narrow and a wide width

    /// The old path measures the offered width, then renders again with the rung that fits (SwiftUI applies
    /// that second render within the same layout pass). It must pick the rung `ViewThatFits` picks: the
    /// line's height tells the rungs apart (each text style has its own line height).
    @Test(arguments: [320, 1024] as [CGFloat])
    func theRawLinePicksTheSameRungOnTheOldPath(_ width: CGFloat) {
        let modern = host(MonoLine(Self.specimenLine), width: width)
        let modernSize = modern.view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        var legacySize = CGSize.zero
        let taken = withLegacyPaths {
            let legacy = host(MonoLine(Self.specimenLine), width: width)
            legacySize = legacy.view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        }
        #expect(taken.contains(.viewThatFits))
        #expect(legacySize.width <= width + 0.5, "\(legacySize.width) points wide in \(width)")
        #expect(abs(legacySize.height - modernSize.height) < 0.5,
                "old path \(legacySize.height) points tall, ViewThatFits \(modernSize.height), in \(width)")
    }

    // MARK: - The old path's fit choice (pure)

    @Test func theOldFitPicksTheWidestRungThatFits() {
        #expect(monoLineLegacyFit(text: Self.specimenLine, offeredWidth: 2000, contentSize: .large) == .body)
        let phone = monoLineLegacyFit(text: Self.specimenLine, offeredWidth: 300, contentSize: .large)
        #expect(phone != .body && phone != .scroll, "\(phone)")
        #expect(monoLineLegacyFit(text: Self.specimenLine, offeredWidth: 50, contentSize: .large) == .scroll)
    }

    @Test func theOldFitShowsTheFootnoteRungUntilTheWidthIsKnown() {
        #expect(monoLineLegacyFit(text: Self.specimenLine, offeredWidth: nil, contentSize: .large) == .footnote)
        #expect(monoLineLegacyFit(text: Self.specimenLine, offeredWidth: 0, contentSize: .large) == .footnote)
    }

    @Test func theOldFitMeasuresAtTheHostsTextSize() {
        // One width, two text sizes: what fits at the smallest size does not at the largest.
        let width: CGFloat = 400
        let small = monoLineLegacyFit(text: Self.specimenLine, offeredWidth: width, contentSize: .extraSmall)
        let large = monoLineLegacyFit(
            text: Self.specimenLine, offeredWidth: width, contentSize: .accessibilityExtraExtraExtraLarge)
        #expect(small == .body)
        #expect(large == .scroll)
        // The environment's text size reaches the measurement as the matching UIKit category.
        #expect(UIContentSizeCategory(DynamicTypeSize.accessibility5) == .accessibilityExtraExtraExtraLarge)
    }

    @Test func theOldFitFollowsTheLadderItIsGiven() {
        #expect(monoLineLegacyFit(text: "AB", offeredWidth: 2000, contentSize: .large, ladder: [.caption2, .scroll])
            == .caption2)
        #expect(monoLineLegacyFit(text: Self.specimenLine, offeredWidth: 1, contentSize: .large, ladder: [.body])
            == .scroll)
    }

    // MARK: - Global frame and photo picker

    @Test func theOldGlobalFrameReportDeliversTheFrame() {
        var reported: CGRect?
        let taken = withLegacyPaths {
            host(Color.red.frame(width: 100, height: 50).compatOnGlobalFrameChange { reported = $0 })
        }
        #expect(taken.contains(.onGeometryChange))
        #expect(reported?.size == CGSize(width: 100, height: 50), "\(String(describing: reported))")
    }

    @Test func theOldPhotoPickerIsBuilt() {
        let controller = withLegacyPathsReturning {
            host(LegacyPhotoPicker(isPresented: .constant(true), onPick: { _ in }))
        }
        #expect(containsPicker(controller), "no PHPickerViewController under \(controller)")
    }

    @Test func aCancelledOldPickerDismissesWithoutAPick() {
        var presented = true
        var picks = 0
        let picker = LegacyPhotoPicker(
            isPresented: Binding(get: { presented }, set: { presented = $0 }),
            onPick: { _ in picks += 1 }
        )
        let coordinator = picker.makeCoordinator()
        let controller = PHPickerViewController(configuration: PHPickerConfiguration())
        coordinator.picker(controller, didFinishPicking: [])
        #expect(presented == false)
        #expect(picks == 0)
    }

    private func withLegacyPathsReturning(_ body: () -> UIViewController) -> UIViewController {
        var result: UIViewController?
        withLegacyPaths { result = body() }
        return result!
    }

    private func containsPicker(_ controller: UIViewController) -> Bool {
        controller is PHPickerViewController || controller.children.contains { containsPicker($0) }
    }
}

/// TES-343 review: a camera result that repeats at frame rate must not republish an unchanged screen.
@MainActor
struct ScannerStatePublishTests {
    private func inUseFrame() -> MrzScanResult {
        MrzScanResultCaptureError(
            error: CameraErrorCameraInUse(message: "x"),
            quality: ScanQuality(mrzRegionFound: false, ocrConfidence: nil, recognizedLineCount: 0)
        )
    }

    @Test func aRepeatedInUseFramePublishesOnce() {
        let model = ScannerModel(config: MrzScannerConfig(), onResult: { _ in })
        var publishes = 0
        let subscription = model.objectWillChange.sink { publishes += 1 }
        defer { subscription.cancel() }
        for _ in 0..<5 { model.onCameraResult(inUseFrame()) }
        if case .cameraInUse = model.state {} else { Issue.record("not in use: \(model.state)") }
        #expect(publishes == 1)
    }

    @Test func sameScreenComparesByCaseAndFlags() {
        #expect(ScannerState.cameraInUse.showsSameScreen(as: .cameraInUse))
        #expect(!ScannerState.cameraInUse.showsSameScreen(as: .cameraUnavailable))
        let scanning = ScannerState.scanning(struggling: true, gathering: false, notAccepted: .ofCategory(.visa))
        #expect(scanning.showsSameScreen(as: .scanning(struggling: true, gathering: false, notAccepted: .ofCategory(.visa))))
        #expect(!scanning.showsSameScreen(as: .scanning(struggling: true, gathering: false, notAccepted: .ofCategory(.passport))))
        #expect(!scanning.showsSameScreen(as: .scanning(struggling: false, gathering: false, notAccepted: .ofCategory(.visa))))
        #expect(ScannerState.savedImageNotAccepted(read: .ofCategory(.visa))
            .showsSameScreen(as: .savedImageNotAccepted(read: .ofCategory(.visa))))
    }

    @Test func aStateWithDocumentDataNeverCountsAsTheSame() {
        // Never compared, so an assignment always goes through.
        let manual = ScannerState.manualRaw(text: "A", parseFailed: false)
        #expect(!manual.showsSameScreen(as: manual))
        let decoded = assembleManualDecoded(text: "P<UTOSPECIMEN<<ALEX<MORGAN<<<<<<<<<<<<<<<<<<\nT220001293UTO9003152F3403141S98765432<<<<<20")
        let review = ScannerState.review(decoded: decoded, expanded: false, source: .camera)
        #expect(!review.showsSameScreen(as: review))
    }
}

/// Which type the iOS 15 photo picker asks a picked photo for.
struct LegacyPickerTypeTests {
    @Test func aProviderWithOnlyAConcreteImageTypeIsAskedForThatType() {
        #expect(legacyPickerImageTypeIdentifier(registered: ["public.heic"]) == "public.heic")
    }

    @Test func theFirstImageTypeWinsWhenJpegAndHeicAreBothRegistered() {
        #expect(legacyPickerImageTypeIdentifier(registered: ["public.jpeg", "public.heic"]) == "public.jpeg")
        #expect(legacyPickerImageTypeIdentifier(registered: ["public.heic", "public.jpeg"]) == "public.heic")
    }

    @Test func nonImageTypesAreSkipped() {
        #expect(legacyPickerImageTypeIdentifier(registered: ["public.plain-text", "public.png"]) == "public.png")
    }

    @Test func noImageTypeFallsBackToTheAbstractImageType() {
        #expect(legacyPickerImageTypeIdentifier(registered: ["public.plain-text"]) == "public.image")
        #expect(legacyPickerImageTypeIdentifier(registered: []) == "public.image")
    }

    @Test func onlyTheAbstractImageTypeIsAskedForThatType() {
        #expect(legacyPickerImageTypeIdentifier(registered: ["public.image"]) == "public.image")
    }
}
