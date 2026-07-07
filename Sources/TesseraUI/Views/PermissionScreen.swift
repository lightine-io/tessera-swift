import SwiftUI

// The adaptive camera-permission screen (mockups 04 / 04b) — the iOS mirror of the Android
// `PermissionContent` + `PermissionScaffold`. ONE screen whose primary action tracks ``PermissionScreenState``:
//
//  * `.needsGrant` (04): the permission is not held and a request can still succeed. The primary action hands
//    the request to the host (`onGrant`, which the model routes to `config.onRequestPermission`) — the SDK
//    NEVER requests a permission itself. If the host supplied no handler (``hasRequestHandler`` false), no
//    dead Grant button is drawn — only the rationale and the manual-entry escape.
//  * `.permanentlyDenied` (04b): the permission is denied with "don't ask again", so a request would show no
//    dialog. The primary action opens this app's OS Settings page — that is NAVIGATION, not a permission
//    request, so the UI owns it and it is always available in this mode.
//
// Both faces share the secondary "Enter details manually" escape. This view only renders and calls back — it
// never requests a permission itself (scope permission boundary); the ask stays with the host.

/// The adaptive camera-permission screen. Renders one of two faces from ``state``:
///
///  * ``PermissionScreenState/needsGrant`` → mockup 04: title "Camera permission needed", the on-device
///    privacy body, a primary "Grant access" that fires ``onGrant`` — but ONLY when ``hasRequestHandler`` is
///    true; if the host supplied no permission handler, no dead Grant button is drawn, leaving just the
///    rationale and the manual-entry escape.
///  * ``PermissionScreenState/permanentlyDenied`` → mockup 04b: title "Camera access is off", the Settings +
///    privacy body, a primary "Open Settings" that fires ``onOpenSettings`` (always available in this mode).
///
/// Both faces share the secondary "Enter details manually" (``onManualEntry``). ``PermissionScreenState/granted``
/// is never passed here (the gate shows the live preview instead); guarded defensively as a no-op. Mirrors the
/// Android `PermissionContent` / `PermissionScaffold`.
internal struct PermissionScreen: View {
    let state: PermissionScreenState
    let onGrant: () -> Void
    let onOpenSettings: () -> Void
    let onManualEntry: () -> Void
    let hasRequestHandler: Bool

    var body: some View {
        switch state {
        case .needsGrant:
            PermissionScaffold(
                accessibilityIdentifier: "tessera-mrz-permission-grant",
                title: String(localized: "tessera_scanner_permission_grant_title", bundle: .module),
                bodyText: String(localized: "tessera_scanner_permission_grant_body", bundle: .module),
                // Grant hands the request to the host; without a handler there is nothing to call, so no dead
                // button is drawn (only the rationale + the manual-entry escape remain).
                primaryLabel: hasRequestHandler ? String(localized: "tessera_scanner_permission_grant_action", bundle: .module) : nil,
                onPrimary: onGrant,
                onManualEntry: onManualEntry
            )

        case .permanentlyDenied:
            PermissionScaffold(
                accessibilityIdentifier: "tessera-mrz-permission-denied",
                title: String(localized: "tessera_scanner_permission_denied_title", bundle: .module),
                bodyText: String(localized: "tessera_scanner_permission_denied_body", bundle: .module),
                // Open Settings is the UI's own navigation — always available in this mode.
                primaryLabel: String(localized: "tessera_scanner_permission_open_settings", bundle: .module),
                onPrimary: onOpenSettings,
                onManualEntry: onManualEntry
            )

        // The gate never dispatches .granted here (it shows the live preview instead); defensively a no-op.
        case .granted:
            EmptyView()
        }
    }
}

/// The shared layout of both permission faces (mockups 04 / 04b): a centred title + body, a primary action
/// pinned at the bottom (omitted when ``primaryLabel`` is `nil` — the no-handler Grant case), and the secondary
/// "Enter details manually" escape beneath it. The two faces differ only in their accessibility identifier,
/// copy, and which callback the primary action fires — everything structural is shared here. Mirrors the
/// Android private `PermissionScaffold`.
private struct PermissionScaffold: View {
    let accessibilityIdentifier: String
    let title: String
    let bodyText: String
    let primaryLabel: String?
    let onPrimary: () -> Void
    let onManualEntry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            // Title + body sit centred in the available space; the actions stay pinned below.
            VStack(spacing: 12) {
                Spacer()
                Text(title)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(bodyText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity)

            if let primaryLabel {
                Button {
                    onPrimary()
                } label: {
                    Text(primaryLabel)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                onManualEntry()
            } label: {
                Text(String(localized: "tessera_scanner_camera_manual", bundle: .module))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .contentMaxWidth()
        .frame(maxHeight: .infinity)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
