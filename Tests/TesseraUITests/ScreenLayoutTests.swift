import SwiftUI
import Testing
@testable import TesseraUI

/// Host tests for the compact-height layout rule (TES-153). The content screens pin their action buttons
/// below a scrolling body only in regular height; in compact height (iPhone landscape) they scroll as one
/// column so the manual-entry field and the review rows keep a usable viewport. The rendered layout itself is
/// verified on the simulator; here we lock in the pure decision every screen reads.
struct ScreenLayoutTests {
    @Test func compactHeightUnpinsTheActions() {
        #expect(pinsActions(verticalSizeClass: .compact) == false)
    }

    @Test func regularHeightKeepsTheActionsPinned() {
        #expect(pinsActions(verticalSizeClass: .regular) == true)
    }

    @Test func unknownHeightKeepsTheActionsPinned() {
        // No size class (e.g. before the environment resolves) must fall back to the portrait layout.
        #expect(pinsActions(verticalSizeClass: nil) == true)
    }
}
