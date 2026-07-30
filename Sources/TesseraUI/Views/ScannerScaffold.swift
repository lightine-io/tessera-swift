import SwiftUI

/// The shared chrome — the iOS mirror of the Android `ScannerScaffold`. A top bar whose leading ✕ owns the
/// global cancel (reachable on every screen), a stable title, and — on the capture / entry screens only, and
/// only when at least two methods are enabled — the method switcher beneath the bar. The screen content
/// renders in the body underneath, so each screen keeps its own scroll / pinned-button behaviour.
///
/// Reader, not oracle (Principle 1): the switcher only chooses *how* to read (which method), never what a
/// reading means. The scaffold adds no judgement.
struct ScannerScaffold<Content: View>: View {
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

    var body: some View {
        NavigationStack {
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
            .navigationTitle(String(localized: "tessera_scanner_title", bundle: .module))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        // SF Symbol close glyph; the accessibility label carries the spoken name.
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "tessera_scanner_close", bundle: .module))
                    .accessibilityIdentifier("tessera-mrz-close")
                }
                // The scan-timeout countdown (TES-125), shown on EVERY screen while a finite `scanTimeout`
                // runs (the host set a session deadline) — so the user always knows there is a limit and how
                // long is left. Nothing shows when `scanTimeout` is `nil` (`timeRemaining == nil`). Mirrors
                // the Android top bar's `ScanCountdownChip` placement next to its privacy action; iOS has no
                // privacy action yet, so this sits alone in the trailing toolbar slot.
                if let timeRemaining {
                    ToolbarItem(placement: .topBarTrailing) {
                        ScanCountdownChip(remaining: timeRemaining)
                    }
                }
            }
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
                substituting(String(localized: "tessera_scanner_time_remaining", bundle: .module), text)
            )
            .accessibilityIdentifier("tessera-mrz-countdown")
    }
}

/// The segmented method switcher (mirrors the Android `MethodSwitcher`): one segment per enabled reading
/// method — Camera / Photo / Type, in that fixed order — with the method matching the current state selected.
/// When fewer than two methods are enabled there is nothing to switch between, so the whole row is hidden.
private struct MethodSwitcher: View {
    let enabledMethods: Set<ScanMethod>
    let currentState: ScannerState
    let onSelectMethod: (ScanMethod) -> Void

    var body: some View {
        let methods = switcherMethods(enabledMethods: enabledMethods)
        // Fewer than two enabled methods → nothing to switch between; hide the switcher entirely.
        if methods.count >= 2 {
            Picker(
                String(localized: "tessera_scanner_title", bundle: .module),
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
        case .camera: return String(localized: "tessera_scanner_method_camera", bundle: .module)
        case .savedImage: return String(localized: "tessera_scanner_method_photo", bundle: .module)
        case .manualEntry: return String(localized: "tessera_scanner_method_keyboard", bundle: .module)
        }
    }
}
