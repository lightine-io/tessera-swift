import SwiftUI
import Testing
import UIKit
@testable import TesseraUI

/// TES-344: the "What's the MRZ?" picture follows the Android drawing - the document (photo placeholder,
/// detail bars, small MRZ band), a "look closer" arrow, and the magnified zone with its caption.
///
/// Each part is laid out by SwiftUI in a hosting controller, on the narrowest iPhone width iOS 15 runs on, at
/// the default and the largest accessibility text size, in light and dark. It must fit the phone's width (the
/// MRZ lines scroll sideways rather than widen it), have a finite, non-zero height, and grow with the text
/// size. The old-iOS path of the dialog around it is in `CompatLegacyPathTests`. How it looks stays a manual
/// check on a device.
@MainActor
struct MrzExplainerPictureTests {
    /// The narrowest iPhone screen width the package's minimum, iOS 15, supports (iPhone SE, 1st generation).
    private static let narrowestWidth: CGFloat = 320

    private func fittedSize(_ view: some View, _ textSize: DynamicTypeSize, _ scheme: ColorScheme) -> CGSize {
        let host = UIHostingController(rootView: view
            .environment(\.dynamicTypeSize, textSize)
            .environment(\.colorScheme, scheme))
        return host.sizeThatFits(in: CGSize(width: Self.narrowestWidth, height: .greatestFiniteMagnitude))
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func thePictureFitsTheNarrowestPhoneAtEveryTextSize(_ scheme: ColorScheme) {
        for textSize in [DynamicTypeSize.large, .accessibility5] {
            let size = fittedSize(MrzExplainerPicture(), textSize, scheme)
            #expect(size.width <= Self.narrowestWidth + 0.5, "\(scheme) at \(textSize): \(size.width) points wide")
            #expect(size.height.isFinite && size.height > 0, "\(scheme) at \(textSize): \(size.height) points tall")
        }
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func thePictureHoldsTheDocumentTheArrowAndTheMagnifiedZone(_ scheme: ColorScheme) {
        for textSize in [DynamicTypeSize.large, .accessibility5] {
            let document = fittedSize(ExplainerDocumentGraphic(), textSize, scheme).height
            let zoom = fittedSize(ExplainerZoomDetail(), textSize, scheme).height
            let picture = fittedSize(MrzExplainerPicture(), textSize, scheme).height
            #expect(document > 0 && zoom > 0, "\(scheme) at \(textSize): document \(document), zoom \(zoom)")
            // The arrow and the two 16-point gaps sit between the document and the zoom.
            #expect(picture > document + zoom + 32, "\(scheme) at \(textSize): \(picture) vs \(document) + \(zoom)")
        }
    }

    @Test func theMagnifiedZoneGrowsWithTheTextSize() {
        let standard = fittedSize(ExplainerZoomDetail(), .large, .light).height
        let largest = fittedSize(ExplainerZoomDetail(), .accessibility5, .light).height
        #expect(largest > standard * 1.5, "\(standard) points tall at the default size, \(largest) at the largest")
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func theDialogLaysOutAtTheNarrowestWidthAndLargestTextSize(_ scheme: ColorScheme) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: Self.narrowestWidth, height: 568))
        let controller = UIHostingController(rootView: MrzExplainerDialog(onDismiss: {})
            .environment(\.dynamicTypeSize, .accessibility5)
            .environment(\.colorScheme, scheme))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        for _ in 0..<4 {
            controller.view.setNeedsLayout()
            window.layoutIfNeeded()
        }
        window.isHidden = true
        let size = controller.view.bounds.size
        #expect(size.width == Self.narrowestWidth && size.height.isFinite && size.height > 0, "\(size)")
    }
}
