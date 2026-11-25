import SwiftUI
import UIKit

// What VoiceOver says for each control of the scanner screens (TES-58), kept in one place so a test can check it.
//
// A package test cannot read the rendered accessibility tree: SwiftUI builds it only while an assistive
// technology or UI-test automation asks for it, and the package has no UI test host. So the screens take their
// control labels from here, and the tests check this table. Roles come from the SwiftUI control types the
// screens use (Button, TextEditor, a segmented Picker), which already report the button / text field roles.

/// One control on a scanner screen. Each screen builds the control's visible text from ``label(bundle:)`` and
/// its spoken name from ``spokenLabel(bundle:)``, so a missing or wrong catalog key shows up in the tests.
enum ScannerControl: Hashable {
    // The shared top bar and its dialog.
    case close
    case privacy
    case privacyDismiss
    /// One segment of the method switcher.
    case method(ScanMethod)
    // The live camera preview.
    case torch
    case explainer
    case explainerDismiss
    case strugglingManual
    // Permission and camera-status screens.
    case permissionContinue
    case permissionOpenSettings
    /// "Enter details manually" on the permission, camera-in-use and camera-unavailable screens.
    case cameraManual
    // Read-failed screen.
    case readFailedTryAgain
    case readFailedManual
    // Saved-image screens.
    case choosePhoto
    case chooseDifferentPhoto
    case savedImageManual
    // Manual entry.
    case manualField
    case manualRead
    case keyboardDone
    // Review.
    case reviewShowAll
    case reviewShowLess
    case reviewUse
    /// "Rescan" / "Try another photo" / "Edit entry", by the method that produced the reading.
    case reviewSecondary(ScanMethod)

    /// Every control, each method-dependent one once per method.
    static let all: [ScannerControl] = [
        .close, .privacy, .privacyDismiss,
        .method(.camera), .method(.savedImage), .method(.manualEntry),
        .torch, .explainer, .explainerDismiss, .strugglingManual,
        .permissionContinue, .permissionOpenSettings, .cameraManual,
        .readFailedTryAgain, .readFailedManual,
        .choosePhoto, .chooseDifferentPhoto, .savedImageManual,
        .manualField, .manualRead, .keyboardDone,
        .reviewShowAll, .reviewShowLess, .reviewUse,
        .reviewSecondary(.camera), .reviewSecondary(.savedImage), .reviewSecondary(.manualEntry),
    ]

    /// The catalog key of the control's name.
    var labelKey: String {
        switch self {
        case .close: "tessera_scanner_close"
        case .privacy: "tessera_scanner_privacy_action"
        case .privacyDismiss: "tessera_scanner_privacy_dialog_dismiss"
        case .method(.camera): "tessera_scanner_method_camera"
        case .method(.savedImage): "tessera_scanner_method_photo"
        case .method(.manualEntry): "tessera_scanner_method_keyboard"
        case .torch: "tessera_scanner_torch"
        case .explainer: "tessera_scanner_explainer_action"
        case .explainerDismiss: "tessera_scanner_explainer_dismiss"
        case .strugglingManual: "tessera_scanner_struggling_manual"
        case .permissionContinue: "tessera_scanner_permission_grant_action"
        case .permissionOpenSettings: "tessera_scanner_permission_open_settings"
        case .cameraManual: "tessera_scanner_camera_manual"
        case .readFailedTryAgain: "tessera_scanner_read_failed_try_again"
        case .readFailedManual: "tessera_scanner_read_failed_manual"
        case .choosePhoto: "tessera_scanner_saved_image_prompt_action"
        case .chooseDifferentPhoto: "tessera_scanner_saved_image_choose_different"
        case .savedImageManual: "tessera_scanner_saved_image_manual"
        case .manualField: "tessera_scanner_manual_field_label"
        case .manualRead: "tessera_scanner_manual_read"
        case .keyboardDone: "tessera_scanner_done"
        case .reviewShowAll: "tessera_scanner_review_show_all"
        case .reviewShowLess: "tessera_scanner_review_show_less"
        case .reviewUse: "tessera_scanner_review_use"
        case .reviewSecondary(.camera): "tessera_scanner_review_rescan"
        case .reviewSecondary(.savedImage): "tessera_scanner_review_try_another_photo"
        case .reviewSecondary(.manualEntry): "tessera_scanner_review_edit_entry"
        }
    }

    /// The name as shown on screen, a host override included.
    func label(bundle: Bundle?) -> String {
        TesseraStrings.string(labelKey, bundle: bundle)
    }

    /// The name VoiceOver reads: the shown name without decorative glyphs such as the ▾ / ▴ disclosure arrows,
    /// which VoiceOver would otherwise read out as "down-pointing triangle".
    func spokenLabel(bundle: Bundle?) -> String {
        spokenText(label(bundle: bundle))
    }
}

/// Glyphs that only decorate a label. VoiceOver reads them by their Unicode names, so spoken text drops them.
private let decorativeGlyphs: Set<Character> = ["▾", "▴", "ⓘ"]

/// `text` without decorative glyphs and the spaces around them.
func spokenText(_ text: String) -> String {
    String(text.filter { !decorativeGlyphs.contains($0) })
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// The torch button's spoken state: "On" or "Off".
func torchAccessibilityValue(on: Bool, bundle: Bundle?) -> String {
    TesseraStrings.string(on ? "tessera_scanner_torch_state_on" : "tessera_scanner_torch_state_off", bundle: bundle)
}

/// The countdown chip's spoken name, for example "Scan time left: 1:05". `shown` is the chip's visible text.
func countdownAccessibilityLabel(shown: String, bundle: Bundle?) -> String {
    substituting(TesseraStrings.string("tessera_scanner_time_remaining", bundle: bundle), shown)
}

/// An observation row's spoken text: the tone in words, then the observation, for example "Attention: Expiry
/// date has passed". The ✓ / ‼ / ⓘ symbol is not read; the tone word carries its meaning.
func observationAccessibilityLabel(_ observation: ReviewObservation, bundle: Bundle?) -> String {
    let toneKey = switch observation.tone {
    case .matches: "tessera_scanner_obs_tone_match"
    case .mismatch: "tessera_scanner_obs_tone_mismatch"
    case .info: "tessera_scanner_obs_tone_info"
    }
    return "\(TesseraStrings.string(toneKey, bundle: bundle)) \(observation.text)"
}

extension View {
    /// Gives this control the spoken name from ``ScannerControl/spokenLabel(bundle:)``.
    func scannerControl(_ control: ScannerControl, bundle: Bundle?) -> some View {
        accessibilityLabel(control.spokenLabel(bundle: bundle))
    }
}

/// Tells VoiceOver a new screen arrived (TES-298): it moves to the new content and, when `title` is given,
/// speaks it. The scanner swaps screens inside one presented view, so the system sends no such signal itself.
/// The post is deferred one turn so the new screen is in the accessibility tree when VoiceOver looks.
@MainActor
func postScreenChanged(title: String?) {
    DispatchQueue.main.async {
        // The UIKit call, not `AccessibilityNotification` (iOS 17): the package runs on iOS 15.
        UIAccessibility.post(notification: .screenChanged, argument: title)
    }
}
