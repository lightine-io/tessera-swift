import Foundation
import Tessera

// TES-103: the app's intake rule (`MrzScannerConfig.acceptedDocumentTypes`). A reading whose category is not in
// the accepted set does not go to review and is not returned. The screen states two facts - what kind was read
// and what kinds the app accepts - and lets the person go on. The SDK does not judge the document: the copy
// never says invalid, wrong or rejected, and a reading whose category the SDK cannot place
// (`broadCategory` is `nil`) is never filtered. The iOS mirror of the Android `NotAcceptedNotice.kt`.

/// Every ``DocumentCategory``, worked out from the enum so a later category is in the default.
var allDocumentCategories: Set<DocumentCategory> { Set(DocumentCategory.entries) }

/// How long the live notice stays after the last frame that read a not-accepted document, so it does not
/// strobe between frames but drops once that document has left the view. Mirrors the Android
/// `NOT_ACCEPTED_NOTICE_LINGER_MS`.
let notAcceptedNoticeLinger: TimeInterval = 3

/// The accepted set the screen applies. An empty set is a configuration slip, not a request to accept nothing
/// (that would leave a screen that can never return): it is treated as every category, the same defensive
/// fallback the screen applies to an empty ``MrzScannerConfig/enabledMethods`` (see ``initialState(enabledMethods:)``).
func effectiveAcceptedDocumentTypes(_ configured: Set<DocumentCategory>) -> Set<DocumentCategory> {
    configured.isEmpty ? allDocumentCategories : configured
}

/// The broad category of a parsed reading, or `nil` when it did not parse or its type code has no category.
/// `documentType` is a Kotlin value class erased to its raw code `String`, so the category is looked up through
/// the exported table - the same answer as mrz-core's `DocumentType.broadCategory`.
func documentCategory(of decoded: MrzScanResultDecoded) -> DocumentCategory? {
    let document: MrzDocument
    if let success = decoded.parse as? ParseResult.Success {
        document = success.document
    } else if let partial = decoded.parse as? ParseResult.PartialSuccess {
        document = partial.document
    } else {
        return nil
    }
    let documentType: Any = document.commonFields.documentType
    let rawCode = (documentType as? String) ?? "\(documentType)"
    return DocumentTypeCodeTable.shared.broadCategory(code: rawCode)
}

/// The category of `decoded` when the app does not accept it, otherwise `nil`. `nil` also when the reading did
/// not parse, or when its type code has no category: the SDK filters only on a category it has. Mirrors the
/// Android `notAcceptedCategory`.
func notAcceptedCategory(
    _ decoded: MrzScanResultDecoded,
    acceptedDocumentTypes: Set<DocumentCategory>
) -> DocumentCategory? {
    guard let category = documentCategory(of: decoded) else { return nil }
    return acceptedDocumentTypes.contains(category) ? nil : category
}

// MARK: - Live camera

/// What one live-camera frame means for the flow, decided by ``stepLiveDecode(_:alreadyRouted:consensus:acceptedDocumentTypes:)``.
/// Mirrors the Android `LiveDecodeStep`.
enum LiveDecodeStep: Equatable {
    /// Nothing to do: the session already routed a reading, or the frame did not parse.
    case ignore

    /// The frames agreed on an accepted reading: latch the session and route it.
    case route(decoded: MrzScanResultDecoded)

    /// An accepted (or unplaceable) reading is gathering agreement: show the "hold steady" cue.
    case gathering

    /// A not-accepted frame, agreement not reached yet: keep any notice alive, show no cue.
    case notAcceptedGathering(read: DocumentCategory)

    /// The frames agreed on a reading the app does not accept. The consensus has been reset so a later
    /// document can still be agreed on; the session is NOT latched.
    case notAccepted(read: DocumentCategory)
}

/// Offers one live frame to `consensus` and decides what it means under `acceptedDocumentTypes`. A frame that
/// did not parse, or any frame after the session routed (`alreadyRouted`), is ignored without touching the
/// consensus, exactly as before TES-103. A confirmed reading the app does not accept resets `consensus` and
/// returns ``LiveDecodeStep/notAccepted(read:)``: it never latches the session. With every category accepted
/// (the default) the result is ``LiveDecodeStep/route(decoded:)`` or ``LiveDecodeStep/gathering``, as before.
/// Mirrors the Android `stepLiveDecode`.
func stepLiveDecode(
    _ decoded: MrzScanResultDecoded,
    alreadyRouted: Bool,
    consensus: MrzDecodeConsensus,
    acceptedDocumentTypes: Set<DocumentCategory>
) -> LiveDecodeStep {
    if alreadyRouted || decoded.parse is ParseResult.Failure { return .ignore }
    switch consensus.offer(decoded: decoded) {
    case is ConsensusVerdictConfirmed:
        guard let read = notAcceptedCategory(decoded, acceptedDocumentTypes: acceptedDocumentTypes) else {
            return .route(decoded: decoded)
        }
        consensus.reset()
        return .notAccepted(read: read)
    case is ConsensusVerdictGathering:
        guard let read = notAcceptedCategory(decoded, acceptedDocumentTypes: acceptedDocumentTypes) else {
            return .gathering
        }
        return .notAcceptedGathering(read: read)
    default:
        return .ignore
    }
}

/// The live state after the frames agreed on a not-accepted reading: a scanning state shows the notice for
/// `read` (and drops the gathering cue, which described that reading); any other state is unchanged. Mirrors
/// the Android `showNotAcceptedNotice`.
func showNotAcceptedNotice(_ current: ScannerState, read: DocumentCategory) -> ScannerState {
    guard case let .scanning(struggling, _, _) = current else { return current }
    return .scanning(struggling: struggling, gathering: false, notAccepted: read)
}

/// Where a reading the app does not accept lands, per reading method: the camera keeps its live preview with
/// the notice over it (`current` when it is already scanning, so its struggling flag survives), a photo gets
/// its own screen with "Choose different photo", and manual entry stays on the entry screen with
/// `manualDraft` kept and an inline note. Mirrors the Android `notAcceptedStateFor`.
func notAcceptedState(
    for source: ScanMethod,
    read: DocumentCategory,
    current: ScannerState,
    manualDraft: String
) -> ScannerState {
    switch source {
    case .camera:
        if case .scanning = current { return showNotAcceptedNotice(current, read: read) }
        return showNotAcceptedNotice(.scanning(struggling: false, gathering: false), read: read)
    case .savedImage:
        return .savedImageNotAccepted(read: read)
    case .manualEntry:
        return .manualRaw(text: manualDraft, parseFailed: false, notAccepted: read)
    }
}

// MARK: - Copy

/// The notice title key for a reading of `category`, for example "This looks like an ID card". Kotlin enum
/// entries bridge as class singletons, so they are matched by identity.
func notAcceptedTitleKey(_ category: DocumentCategory) -> String {
    if category === DocumentCategory.passport { return "tessera_scanner_not_accepted_title_passport" }
    if category === DocumentCategory.identityCard { return "tessera_scanner_not_accepted_title_identity_card" }
    if category === DocumentCategory.residencePermit { return "tessera_scanner_not_accepted_title_residence_permit" }
    if category === DocumentCategory.visa { return "tessera_scanner_not_accepted_title_visa" }
    return "tessera_scanner_not_accepted_title_other"
}

/// The category name key used in the accepted list, for example "ID card" - the same keys the review screen
/// uses for "P - passport".
func categoryNameKey(_ category: DocumentCategory) -> String {
    if category === DocumentCategory.passport { return "tessera_scanner_category_passport" }
    if category === DocumentCategory.identityCard { return "tessera_scanner_category_identity_card" }
    if category === DocumentCategory.residencePermit { return "tessera_scanner_category_residence_permit" }
    if category === DocumentCategory.visa { return "tessera_scanner_category_visa" }
    return "tessera_scanner_category_other"
}

/// The notice title for a reading of `read`.
func notAcceptedTitle(_ read: DocumentCategory, bundle: Bundle?) -> String {
    TesseraStrings.string(notAcceptedTitleKey(read), bundle: bundle)
}

/// "This app accepts: passport, visa." - the accepted categories in ``DocumentCategory`` order, whatever the
/// set's order. Mirrors the Android `acceptedBody`.
func notAcceptedBody(_ acceptedDocumentTypes: Set<DocumentCategory>, bundle: Bundle?) -> String {
    let separator = TesseraStrings.string("tessera_scanner_not_accepted_separator", bundle: bundle)
    let names = DocumentCategory.entries
        .filter { acceptedDocumentTypes.contains($0) }
        .map { TesseraStrings.string(categoryNameKey($0), bundle: bundle) }
    return substituting(
        TesseraStrings.string("tessera_scanner_not_accepted_body", bundle: bundle),
        names.joined(separator: separator)
    )
}

/// What VoiceOver announces when the camera notice or the manual-entry note appears: both lines, as the
/// Android polite live region (merged descendants) reads them.
func notAcceptedAnnouncement(
    _ read: DocumentCategory,
    acceptedDocumentTypes: Set<DocumentCategory>,
    bundle: Bundle?
) -> String {
    "\(notAcceptedTitle(read, bundle: bundle))\n\(notAcceptedBody(acceptedDocumentTypes, bundle: bundle))"
}
