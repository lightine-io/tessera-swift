import Testing
@testable import TesseraUI

/// TES-150: the raw MRZ line fit ladder. Order matters - widest look first, scrolling last.
struct MonoLineFitTests {
    @Test func ladderOrderIsBodyThenFootnoteThenScroll() {
        #expect(MonoLineFit.ladder == [.body, .footnote, .scroll])
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
