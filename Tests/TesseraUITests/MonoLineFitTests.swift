import Testing
@testable import TesseraUI

/// TES-150: the raw MRZ line fit ladder. Order matters - widest look first, scrolling last.
struct MonoLineFitTests {
    @Test func ladderOrderIsWidestFirstThenScroll() {
        // Each rung must fit a 44-character line in a narrower column than the one before it (402 / 393 /
        // 375pt-wide iPhones at the default text size), so a device-width regression shows up here as text.
        #expect(MonoLineFit.ladder == [.body, .footnote, .caption, .caption2, .scroll])
    }

    @Test func scrollIsLastAndTheOnlyRungWithAnAffordance() {
        #expect(MonoLineFit.ladder.last == .scroll)
        #expect(MonoLineFit.ladder.filter { $0 == .scroll }.count == 1)
    }

    @Test func ladderCoversEveryFitExactlyOnce() {
        #expect(Set(MonoLineFit.ladder) == Set(MonoLineFit.allCases))
        #expect(MonoLineFit.ladder.count == MonoLineFit.allCases.count)
    }
}
