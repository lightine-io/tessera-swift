import SwiftUI
import UIKit

/// The shared chrome — the iOS mirror of the Android `ScannerScaffold`. A top bar whose leading ✕ owns the
/// global cancel (reachable on every screen), a stable title, and — on the capture / entry screens only, and
/// only when at least two methods are enabled — the method switcher beneath the bar. The screen content
/// renders in the body underneath, so each screen keeps its own scroll / pinned-button behaviour.
///
/// Reader, not oracle (Principle 1): the switcher only chooses *how* to read (which method), never what a
/// reading means. The scaffold adds no judgement.
struct ScannerScaffold<Content: View>: View {
    @Environment(\.tesseraStringsBundle) private var stringsBundle
    let enabledMethods: Set<ScanMethod>
    let currentState: ScannerState
    let onClose: () -> Void
    let onSelectMethod: (ScanMethod) -> Void
    /// The scan-timeout time left, shown as a countdown chip in the top bar on every screen; `nil` when the
    /// host left `scanTimeout` at `nil` (no deadline → no chip). Defaults to `nil` so screen-focused call
    /// sites don't need to thread a deadline. Mirrors the Android `ScannerScaffold`'s `timeRemaining`
    /// parameter / ``ScanCountdownChip``.
    var timeRemaining: Duration? = nil
    @ViewBuilder let content: () -> Content

    /// Whether a docked keyboard (or its hardware-keyboard shortcut bar) covers the bottom of the screen.
    /// Driven by the keyboard frame notifications: SwiftUI geometry readings could not tell the two apart
    /// here: on the simulator the body area and a keyboard-ignoring layer measured the same height.
    @State private var keyboardCoversFooter = false

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    if showsMethodSwitcher(currentState) {
                        MethodSwitcher(
                            enabledMethods: enabledMethods,
                            currentState: currentState,
                            onSelectMethod: onSelectMethod
                        )
                    }
                    content()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // "Powered by Tessera" attribution, shown once on every screen — a quiet, theme-coloured
                // footer that respects the safe area. The content reserves the footer's exact height with a
                // hidden copy in `.safeAreaInset` (the SwiftUI idiom for a persistent bottom bar that never
                // overlaps scrollable content, mirroring the Android Scaffold's `bottomBar`); the visible
                // footer is drawn in the layer below. Overridable like every `tessera_*` key: a blank
                // resolved string renders nothing at all (`PoweredByFooter`), so the opt-out actually
                // reclaims the space.
                //
                // While the keyboard is up the reservation is dropped, so the content still avoids the
                // keyboard exactly (TES-153) without a blank band above it — the keyboard is part of the
                // safe area, and an inset would otherwise stack on top of it.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if !keyboardCoversFooter {
                        PoweredByFooter().hidden()
                    }
                }

                // The visible footer ignores ONLY the keyboard safe area, so it stays at the physical
                // bottom of the screen (behind the keyboard) instead of riding on the keyboard's top edge —
                // matching the Android footer, which stays below the IME (TES-156). The container safe area
                // (home indicator) is still respected, so with the keyboard down it sits exactly where the
                // hidden copy reserves space.
                PoweredByFooter()
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) {
                keyboardCoversFooter = keyboardReachesScreenBottom($0)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardCoversFooter = false
            }
            .navigationTitle(TesseraStrings.string("tessera_scanner_title", bundle: stringsBundle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        // SF Symbol close glyph; the accessibility label carries the spoken name.
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(TesseraStrings.string("tessera_scanner_close", bundle: stringsBundle))
                    .accessibilityIdentifier("tessera-mrz-close")
                }
                // The scan-timeout countdown (TES-125), shown on EVERY screen while a finite `scanTimeout`
                // runs (the host set a session deadline) — so the user always knows there is a limit and how
                // long is left. Nothing shows when `scanTimeout` is `nil` (`timeRemaining == nil`).
                if let timeRemaining {
                    ToolbarItem(placement: .topBarTrailing) {
                        ScanCountdownChip(remaining: timeRemaining)
                    }
                }
                // The privacy / transparency notice, reachable on every screen from the shared chrome rather
                // than repeated as ad-hoc copy per screen — one coherent, opt-in explanation of what the
                // scanner does with the document. Placed AFTER the countdown chip, mirroring the Android top
                // bar's `actions { ScanCountdownChip(...); PrivacyNoticeAction() }` order.
                ToolbarItem(placement: .topBarTrailing) {
                    PrivacyNoticeAction()
                }
            }
        }
    }
}

/// Whether the keyboard's end frame in a keyboard-frame notification is on screen AND reaches the bottom
/// edge — a docked keyboard or a hardware-keyboard shortcut bar, which cover the footer. A floating (iPad)
/// keyboard does not reach the edge, so the footer stays reserved and visible. The notification's object is
/// the screen the keyboard is on; without it the frame is treated as on-screen only if it has height.
@MainActor
private func keyboardReachesScreenBottom(_ note: Notification) -> Bool {
    guard let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
          frame.height > 0 else { return false }
    guard let screen = note.object as? UIScreen else { return true }
    let bottom = screen.bounds.maxY
    return frame.minY < bottom && frame.maxY >= bottom - 1
}

/// The "Powered by Tessera" attribution footer, shown once on every screen at the bottom of the scaffold. A
/// quiet, secondary-styled line so it adapts to light / dark and never competes with the content.
/// Overridable like every `tessera_*` key — a consumer can set an empty string to remove it: this renders
/// nothing at all when the resolved string is blank, so the opt-out actually reclaims the space rather than
/// leaving a blank, padded band. Mirrors the Android `PoweredByFooter`.
private struct PoweredByFooter: View {
    @Environment(\.tesseraStringsBundle) private var stringsBundle

    var body: some View {
        let text = TesseraStrings.string("tessera_scanner_powered_by", bundle: stringsBundle)
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyView()
        } else {
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .accessibilityIdentifier("tessera-mrz-powered-by")
        }
    }
}

/// The scan-timeout countdown chip (TES-125): a small pill in the top bar showing the time left as `M:SS`
/// while a finite `scanTimeout` runs, present on every screen — the iOS mirror of the Android
/// `ScanCountdownChip`. The visible `M:SS` uses monospaced digits so it doesn't jitter as it counts down; a
/// spoken accessibility label gives VoiceOver the meaning. Deliberately NOT `.updatesFrequently` — a
/// per-second VoiceOver announcement would spam VoiceOver, so it is read on focus only, matching the Android
/// chip's non-live-region semantics (`liveRegion` is intentionally absent there too).
private struct ScanCountdownChip: View {
    @Environment(\.tesseraStringsBundle) private var stringsBundle
    let remaining: Duration

    var body: some View {
        let text = formatCountdown(remaining)
        Text(text)
            .font(.callout.monospacedDigit())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.secondary.opacity(0.15), in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                substituting(TesseraStrings.string("tessera_scanner_time_remaining", bundle: stringsBundle), text)
            )
            .accessibilityIdentifier("tessera-mrz-countdown")
    }
}

/// The segmented method switcher (mirrors the Android `MethodSwitcher`): one segment per enabled reading
/// method — Camera / Photo / Type, in that fixed order — with the method matching the current state selected.
/// When fewer than two methods are enabled there is nothing to switch between, so the whole row is hidden.
private struct MethodSwitcher: View {
    @Environment(\.tesseraStringsBundle) private var stringsBundle
    let enabledMethods: Set<ScanMethod>
    let currentState: ScannerState
    let onSelectMethod: (ScanMethod) -> Void

    var body: some View {
        let methods = switcherMethods(enabledMethods: enabledMethods)
        // Fewer than two enabled methods → nothing to switch between; hide the switcher entirely.
        if methods.count >= 2 {
            Picker(
                TesseraStrings.string("tessera_scanner_title", bundle: stringsBundle),
                selection: Binding(
                    get: { activeMethod(currentState) ?? methods.first! },
                    set: { onSelectMethod($0) }
                )
            ) {
                ForEach(methods, id: \.self) { method in
                    Text(methodLabel(method)).tag(method)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .contentMaxWidth()
            .accessibilityIdentifier("tessera-mrz-method-switcher")
        }
    }

    private func methodLabel(_ method: ScanMethod) -> String {
        switch method {
        case .camera: return TesseraStrings.string("tessera_scanner_method_camera", bundle: stringsBundle)
        case .savedImage: return TesseraStrings.string("tessera_scanner_method_photo", bundle: stringsBundle)
        case .manualEntry: return TesseraStrings.string("tessera_scanner_method_keyboard", bundle: stringsBundle)
        }
    }
}
