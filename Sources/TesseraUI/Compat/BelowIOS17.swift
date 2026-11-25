import SwiftUI
import UIKit

// Shims for iOS 15 and 16. Every declaration here exists only because the package supports iOS versions
// below 17; when the minimum is iOS 17 this whole file goes (see Compat/README.md). Each shim's doc comment
// starts with `COMPAT(iOS 17):` and names the modern call that replaces it.

// MARK: - Value change

extension View {
    /// COMPAT(iOS 17): below iOS 17, the one-parameter `onChange(of:perform:)` (deprecated from iOS 17), which
    /// behaves the same for a caller that only needs the new value. When the minimum is iOS 17, replace calls
    /// with `.onChange(of: value) { _, newValue in action(newValue) }` and delete this.
    @ViewBuilder
    func compatOnChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(iOS 17, *), !Compat.forceLegacy {
            onChange(of: value) { _, newValue in action(newValue) }
        } else {
            let _ = Compat.tookLegacyPath(.onChange)
            onChange(of: value) { newValue in action(newValue) }
        }
    }
}

// MARK: - Success haptic

extension View {
    /// COMPAT(iOS 17): below iOS 17, a `UINotificationFeedbackGenerator` plays the same success haptic when
    /// `trigger` changes and `enabled` is on; it is prepared on appear and when `likelySoon` turns on (a read is
    /// about to be confirmed), so the haptic is not late. Both paths honour the system
    /// haptic setting. When the minimum is iOS 17, replace calls with
    /// `.sensoryFeedback(trigger: trigger) { _, _ in enabled ? .success : nil }` and delete this.
    @ViewBuilder
    func compatSuccessHaptic(trigger: Int, enabled: Bool, likelySoon: Bool) -> some View {
        if #available(iOS 17, *), !Compat.forceLegacy {
            sensoryFeedback(trigger: trigger) { _, _ in
                enabled ? .success : nil
            }
        } else {
            let _ = Compat.tookLegacyPath(.sensoryFeedback)
            modifier(LegacySuccessHaptic(trigger: trigger, enabled: enabled, likelySoon: likelySoon))
        }
    }
}

/// Part of ``View/compatSuccessHaptic(trigger:enabled:likelySoon:)``'s path below iOS 17; goes with it.
private struct LegacySuccessHaptic: ViewModifier {
    let trigger: Int
    let enabled: Bool
    let likelySoon: Bool
    // `StateObject`, so one generator lives as long as the view; a plain `@State` default would build a new
    // generator on every re-render of the parent.
    @StateObject private var haptics = LegacyHapticGenerator()

    func body(content: Content) -> some View {
        content
            .onAppear { if enabled { haptics.prepare() } }
            .compatOnChange(of: likelySoon) { soon in
                if soon, enabled { haptics.prepare() }
            }
            .compatOnChange(of: trigger) { _ in
                guard enabled else { return }
                haptics.playSuccess()
            }
    }
}

/// Part of ``View/compatSuccessHaptic(trigger:enabled:likelySoon:)``'s path below iOS 17; goes with it. Holds
/// one `UINotificationFeedbackGenerator` for the view's lifetime.
@MainActor
private final class LegacyHapticGenerator: ObservableObject {
    private let generator = UINotificationFeedbackGenerator()

    /// Wakes the Taptic Engine so the next haptic plays without delay (it stays ready for a few seconds).
    func prepare() { generator.prepare() }

    /// Plays the success haptic.
    func playSuccess() { generator.notificationOccurred(.success) }
}
