import SwiftUI

// The compact-height layout rule for the content screens (TES-153). Each content screen pins its action
// buttons below a scrolling body. In regular height (portrait phone, iPad) that keeps the actions always
// reachable. In compact height (iPhone landscape) the nav bar, method switcher, title, pinned buttons and
// footer leave the scrolling body a viewport of roughly 90pt — too small for the manual-entry field or more
// than a few review rows, and with the keyboard up the field disappears entirely. So in compact height the
// whole screen becomes ONE vertical scroll (title, body, then the actions at the end): the viewport is the
// full available height and SwiftUI's keyboard avoidance has room to scroll a focused field into view.

/// Whether a content screen pins its action buttons below a scrolling body (`true`) or scrolls everything,
/// actions included, as one column (`false`). Only compact vertical size (iPhone landscape) unpins; regular
/// height and an unknown size class (`nil`) keep the pinned layout, so portrait and iPad never change.
func pinsActions(verticalSizeClass: UserInterfaceSizeClass?) -> Bool {
    verticalSizeClass != .compact
}

/// The shared title / scrolling body / actions layout of the content screens (manual entry, review, read
/// failed). Regular height: `header` on top, `scrolling` in its own `ScrollView`, `actions` pinned below —
/// exactly the pre-TES-153 layout. Compact height: one `ScrollView` holding `header`, `scrolling` and
/// `actions` in that order (see ``pinsActions(verticalSizeClass:)``). Both keep the 24pt padding, the
/// ``ContentMaxWidth`` cap and the leading-aligned 16pt column; `header` and `actions` may hold several views
/// (each becomes its own column row, spaced like before).
struct PinnedActionsLayout<Header: View, Scrolling: View, Actions: View>: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ViewBuilder let header: () -> Header
    @ViewBuilder let scrolling: () -> Scrolling
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        if pinsActions(verticalSizeClass: verticalSizeClass) {
            VStack(alignment: .leading, spacing: 16) {
                header()
                ScrollView {
                    scrolling()
                }
                actions()
            }
            .padding(24)
            .contentMaxWidth()
            .frame(maxHeight: .infinity)
        } else {
            // The padding sits INSIDE the scroll so the viewport is the full height the scaffold leaves; the
            // centred, capped column keeps the portrait reading width.
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header()
                    scrolling()
                    actions()
                }
                .padding(24)
                .contentMaxWidth()
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

extension View {
    /// For a screen whose actions are pinned with a `Spacer` rather than a scrolling body (the saved-image
    /// prompt and empty screens): regular height leaves it untouched; compact height wraps the whole screen in
    /// one vertical `ScrollView`, so the text keeps its natural height instead of being squeezed into the
    /// leftover space (the spacers collapse to their minimum and the actions follow the text).
    func scrollsInCompactHeight() -> some View {
        modifier(CompactHeightScroll())
    }
}

private struct CompactHeightScroll: ViewModifier {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    func body(content: Content) -> some View {
        if pinsActions(verticalSizeClass: verticalSizeClass) {
            content
        } else {
            ScrollView {
                content
                    .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
    }
}
