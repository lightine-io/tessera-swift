import Foundation
import Tessera
import Testing
@testable import TesseraUI

/// TES-103: `MrzScannerConfig.acceptedDocumentTypes`, the app's intake rule, across the three reading methods.
/// The iOS mirror of the Android `AcceptedDocumentTypesTest`, case for case.
///
/// The pure seams (``routeDecode(_:reviewMode:acceptedDocumentTypes:)``, ``stepLiveDecode(_:alreadyRouted:consensus:acceptedDocumentTypes:)``,
/// ``notAcceptedState(for:read:current:manualDraft:)``) are tested directly; manual entry and the camera are
/// driven through ``ScannerModel`` (the camera by feeding frames to ``ScannerModel/onCameraResult(_:)``, since
/// the simulator has no camera).
///
/// Fixtures: the project's own TD3 specimen (UTO, the reserved test issuer) as the passport, and lines built
/// with the SDK's own `MrzGenerator` for an ID card (TD1, code `I`, the project's TD1 specimen) and for a code
/// with no category (`X`).
@MainActor
struct AcceptedDocumentTypesTests {
    static let passportLines = [
        "P<UTOSPECIMEN<<ALEX<MORGAN<<<<<<<<<<<<<<<<<<",
        "T220001293UTO9003152F3403141S98765432<<<<<20",
    ]

    static let idCardLines: [String] = generated(MrzGenerator.shared.generateTD1(
        documentType: "I", issuingState: "UTO", documentNumber: "T42000137",
        primaryIdentifier: "SPECIMEN", secondaryIdentifier: "ALEX MORGAN", nationality: "UTO",
        dateOfBirth: Kotlinx_datetimeLocalDate(year: 1990, month: 3, day: 15), sex: .female,
        dateOfExpiry: Kotlinx_datetimeLocalDate(year: 2034, month: 3, day: 14),
        optionalData1: "", optionalData2: "", transliteration: nil))

    // A document type code whose first letter is none of P, I, A, C, V: broadCategory is nil.
    static let uncategorizedLines: [String] = generated(MrzGenerator.shared.generateTD3(
        documentType: "X", issuingState: "UTO", documentNumber: "T22000129",
        primaryIdentifier: "SPECIMEN", secondaryIdentifier: "ALEX MORGAN", nationality: "UTO",
        dateOfBirth: Kotlinx_datetimeLocalDate(year: 1990, month: 3, day: 15), sex: .female,
        dateOfExpiry: Kotlinx_datetimeLocalDate(year: 2034, month: 3, day: 14),
        personalNumber: "", transliteration: nil))

    private static func generated(_ result: GenerationResult) -> [String] {
        (result as? GenerationResult.Success)?.mrz ?? []
    }

    private static func text(_ lines: [String]) -> String { lines.joined(separator: "\n") }

    private var passport: MrzScanResultDecoded { assembleManualDecoded(text: Self.text(Self.passportLines)) }
    private var idCard: MrzScanResultDecoded { assembleManualDecoded(text: Self.text(Self.idCardLines)) }
    private var uncategorized: MrzScanResultDecoded { assembleManualDecoded(text: Self.text(Self.uncategorizedLines)) }

    private let passportOnly: Set<DocumentCategory> = [DocumentCategory.passport]
    private let idCardOnly: Set<DocumentCategory> = [DocumentCategory.identityCard]

    // MARK: - Fixtures and config

    @Test func fixturesParseToTheCategoriesTheTestsRelyOn() {
        for decoded in [passport, idCard, uncategorized] {
            #expect(!(decoded.parse is ParseResult.Failure), "fixture must parse: \(decoded.parse)")
        }
        #expect(documentCategory(of: passport) === DocumentCategory.passport)
        #expect(documentCategory(of: idCard) === DocumentCategory.identityCard)
        #expect(documentCategory(of: uncategorized) == nil)
    }

    @Test func defaultAcceptsEveryCategoryAndASetIsStoredAsGiven() {
        #expect(MrzScannerConfig().acceptedDocumentTypes == Set(DocumentCategory.entries))
        #expect(MrzScannerConfig().acceptedDocumentTypes.count == 5)
        #expect(MrzScannerConfig(acceptedDocumentTypes: passportOnly).acceptedDocumentTypes == passportOnly)
        var config = MrzScannerConfig()
        config.acceptedDocumentTypes = idCardOnly
        #expect(config.acceptedDocumentTypes == idCardOnly)
        #expect(ScannerModel(config: config, onResult: { _ in }).acceptedDocumentTypes == idCardOnly)
    }

    /// The rule the initializer's and the setter's precondition apply. The trap itself is not run: exit tests
    /// are not available on the iOS Simulator.
    @Test func anEmptySetIsAConfigurationError() {
        #expect(!isAcceptableDocumentTypeSet([]))
        #expect(isAcceptableDocumentTypeSet(passportOnly))
        #expect(isAcceptableDocumentTypeSet(allDocumentCategories))
        #expect(emptyAcceptedDocumentTypesMessage.contains("acceptedDocumentTypes must not be empty"))
    }

    // MARK: - routeDecode: saved image and manual entry route through it

    @Test func defaultRoutingIsUnchanged() {
        if case .showReview = routeDecode(passport, reviewMode: .review) {} else { Issue.record("default review") }
        if case .returnConfirmed = routeDecode(passport, reviewMode: .instantReturn) {} else { Issue.record("default instant") }
        if case .showReview = routeDecode(idCard, reviewMode: .review, acceptedDocumentTypes: allDocumentCategories) {} else {
            Issue.record("every category accepted reviews an ID card")
        }
    }

    @Test func aReadingTheAppDoesNotAcceptIsNeitherReviewedNorReturned() {
        for mode in [ReviewMode.review, .instantReturn] {
            if case let .notAccepted(read) = routeDecode(passport, reviewMode: mode, acceptedDocumentTypes: idCardOnly) {
                #expect(read === DocumentCategory.passport)
            } else {
                Issue.record("a passport under an ID-card-only rule must not route on in \(mode)")
            }
        }
        if case .showReview = routeDecode(idCard, reviewMode: .review, acceptedDocumentTypes: idCardOnly) {} else {
            Issue.record("an accepted ID card reviews")
        }
        if case .returnConfirmed = routeDecode(idCard, reviewMode: .instantReturn, acceptedDocumentTypes: idCardOnly) {} else {
            Issue.record("an accepted ID card returns under instant-return")
        }
    }

    @Test func aReadingWithNoCategoryIsNotFiltered() {
        if case .showReview = routeDecode(uncategorized, reviewMode: .review, acceptedDocumentTypes: passportOnly) {} else {
            Issue.record("unknown category reviews")
        }
        if case .returnConfirmed = routeDecode(uncategorized, reviewMode: .instantReturn, acceptedDocumentTypes: passportOnly) {} else {
            Issue.record("unknown category returns")
        }
    }

    @Test func aParseFailureStillShowsReadFailed() {
        let garbled = assembleManualDecoded(text: "P<UTO\nNOT AN MRZ")
        #expect(garbled.parse is ParseResult.Failure)
        if case .showReadFailed = routeDecode(garbled, reviewMode: .review, acceptedDocumentTypes: idCardOnly) {} else {
            Issue.record("a parse failure routes as before")
        }
    }

    @Test func eachMethodLandsOnItsOwnNotAcceptedState() {
        let camera = notAcceptedState(for: .camera, read: .passport,
                                      current: .scanning(struggling: true, gathering: true), manualDraft: "")
        if case let .scanning(struggling, gathering, read) = camera {
            #expect(struggling && !gathering && read === DocumentCategory.passport)
        } else { Issue.record("camera stays on the live preview") }

        if case let .savedImageNotAccepted(read) = notAcceptedState(for: .savedImage, read: .passport,
                                                                    current: .savedImageAnalyzing, manualDraft: "") {
            #expect(read === DocumentCategory.passport)
        } else { Issue.record("photo gets its own screen") }

        if case let .manualRaw(text, parseFailed, read) = notAcceptedState(for: .manualEntry, read: .passport,
                                                                           current: .manualRaw(text: "typed", parseFailed: false),
                                                                           manualDraft: "typed") {
            #expect(text == "typed" && !parseFailed && read === DocumentCategory.passport)
        } else { Issue.record("manual entry stays on the entry screen") }
    }

    // MARK: - Live camera: consensus and the decode latch

    @Test func liveDefaultGathersThenRoutesAsBefore() throws {
        let consensus = try MrzDecodeConsensus(threshold: 2)
        let all = allDocumentCategories
        #expect(stepLiveDecode(passport, alreadyRouted: false, consensus: consensus, acceptedDocumentTypes: all) == .gathering)
        if case .route = stepLiveDecode(passport, alreadyRouted: false, consensus: consensus, acceptedDocumentTypes: all) {} else {
            Issue.record("two agreeing frames route")
        }
        #expect(stepLiveDecode(passport, alreadyRouted: true, consensus: consensus, acceptedDocumentTypes: all) == .ignore)
    }

    @Test func liveNotAcceptedReadingDoesNotLatchAndALaterAcceptedDocumentRoutes() throws {
        let consensus = try MrzDecodeConsensus(threshold: 2)
        var routed = false
        func step(_ decoded: MrzScanResultDecoded) -> LiveDecodeStep {
            let result = stepLiveDecode(decoded, alreadyRouted: routed, consensus: consensus, acceptedDocumentTypes: passportOnly)
            if case .route = result { routed = true }
            return result
        }
        // The ID card gathers (no "hold steady" cue), then the frames agree: a notice, not a route.
        #expect(step(idCard) == .notAcceptedGathering(read: .identityCard))
        #expect(step(idCard) == .notAccepted(read: .identityCard))
        #expect(!routed, "a not-accepted reading must not latch the session")
        // The consensus was reset: one more ID card frame gathers again rather than confirming at once.
        #expect(step(idCard) == .notAcceptedGathering(read: .identityCard))
        // A passport now: gathers, then routes.
        #expect(step(passport) == .gathering)
        if case .route = step(passport) {} else { Issue.record("the passport routes") }
        #expect(routed)
    }

    @Test func liveSingleFrameConsensusAndUnknownCategory() throws {
        let consensus = try MrzDecodeConsensus(threshold: 1)
        #expect(stepLiveDecode(idCard, alreadyRouted: false, consensus: consensus, acceptedDocumentTypes: passportOnly)
            == .notAccepted(read: .identityCard))
        #expect(stepLiveDecode(idCard, alreadyRouted: false, consensus: consensus, acceptedDocumentTypes: passportOnly)
            == .notAccepted(read: .identityCard))
        if case .route = stepLiveDecode(uncategorized, alreadyRouted: false, consensus: consensus, acceptedDocumentTypes: passportOnly) {} else {
            Issue.record("an unknown category routes")
        }
    }

    @Test func liveNoticeKeepsStrugglingAndDropsTheGatheringCue() {
        if case let .scanning(struggling, gathering, read) = showNotAcceptedNotice(.scanning(struggling: true, gathering: true), read: .visa) {
            #expect(struggling && !gathering && read === DocumentCategory.visa)
        } else { Issue.record("stays scanning") }
        // Off the live preview it changes nothing.
        if case .cameraInUse = showNotAcceptedNotice(.cameraInUse, read: .visa) {} else { Issue.record("unchanged") }
    }

    @Test func theNoticeRanksBelowGatheringAndAboveStruggling() {
        #expect(guidanceMessage(gathering: true, struggling: true, notAccepted: true) == .gathering)
        #expect(guidanceMessage(gathering: false, struggling: true, notAccepted: true) == .notAccepted)
        #expect(guidanceMessage(gathering: false, struggling: true) == .struggling)
        #expect(guidanceMessage(gathering: false, struggling: false) == .framingHint)
    }

    // MARK: - Live camera through the model

    private final class Results {
        var values: [TesseraUIResult] = []
        var confirmed: [MrzScanResultDecoded] {
            values.compactMap { if case let .confirmed(d) = $0 { d } else { nil } }
        }
    }

    private func noMrz() -> MrzScanResultNoMrzFound {
        MrzScanResultNoMrzFound(
            recognizedText: RecognizedText(lines: []),
            quality: ScanQuality(mrzRegionFound: false, ocrConfidence: nil, recognizedLineCount: 0))
    }

    private func liveNotice(_ model: ScannerModel) -> DocumentCategory? {
        if case let .scanning(_, _, read) = model.state { return read }
        return nil
    }

    @Test func cameraShowsTheNoticeKeepsScanningAndClearsItAfterTheLinger() {
        let results = Results()
        let model = ScannerModel(config: MrzScannerConfig(acceptedDocumentTypes: passportOnly),
                                 onResult: { results.values.append($0) })
        var now = Date(timeIntervalSince1970: 0)
        model.notAcceptedClock = { now }

        model.onCameraResult(idCard)
        #expect(liveNotice(model) == nil, "no notice before the frames agree")
        model.onCameraResult(idCard)
        #expect(liveNotice(model) === DocumentCategory.identityCard)
        #expect(model.confirmedReadHaptic == 0, "no haptic for a not-accepted reading")
        #expect(results.values.isEmpty)

        // The document is still near: a miss within the linger keeps the notice.
        now += 1
        model.onCameraResult(noMrz())
        #expect(liveNotice(model) === DocumentCategory.identityCard)
        // 3 seconds after the last filtered frame it clears.
        now += 2.5
        model.onCameraResult(noMrz())
        #expect(liveNotice(model) == nil)
        if case .scanning = model.state {} else { Issue.record("still scanning") }
    }

    @Test func cameraFilteredReadingFollowedByAnAcceptedOneRoutesTheAcceptedOne() {
        let results = Results()
        let model = ScannerModel(config: MrzScannerConfig(acceptedDocumentTypes: passportOnly),
                                 onResult: { results.values.append($0) })
        model.onCameraResult(idCard)
        model.onCameraResult(idCard)
        #expect(liveNotice(model) === DocumentCategory.identityCard)

        // An accepted reading starting to gather replaces the notice with the "hold steady" cue.
        model.onCameraResult(passport)
        if case let .scanning(_, gathering, read) = model.state {
            #expect(gathering && read == nil)
        } else { Issue.record("still scanning") }
        model.onCameraResult(passport)
        if case let .review(decoded, _, source) = model.state {
            #expect(decoded.recognizedText.lines.map(\.text) == Self.passportLines)
            #expect(source == .camera)
        } else { Issue.record("the passport goes to review, got \(model.state)") }
        #expect(model.confirmedReadHaptic == 1)
        #expect(results.values.isEmpty)
    }

    @Test func cameraUnderInstantReturnReturnsOnlyTheAcceptedDocument() {
        let results = Results()
        let model = ScannerModel(config: MrzScannerConfig(reviewMode: .instantReturn, acceptedDocumentTypes: passportOnly),
                                 onResult: { results.values.append($0) })
        for _ in 0..<4 { model.onCameraResult(idCard) }
        #expect(results.values.isEmpty, "a not-accepted reading must not be returned under instant-return")
        model.onCameraResult(passport)
        model.onCameraResult(passport)
        #expect(results.confirmed.count == 1)
        #expect(results.confirmed.first?.recognizedText.lines.map(\.text) == Self.passportLines)
    }

    @Test func cameraWithTheDefaultRoutesAnyCategory() {
        let model = ScannerModel(config: MrzScannerConfig(), onResult: { _ in })
        model.onCameraResult(idCard)
        model.onCameraResult(idCard)
        if case .review = model.state {} else { Issue.record("default config reviews an ID card, got \(model.state)") }
    }

    // MARK: - Manual entry through the model

    private func manualModel(_ accepted: Set<DocumentCategory>, mode: ReviewMode = .review, results: Results) -> ScannerModel {
        ScannerModel(config: MrzScannerConfig(enabledMethods: [.manualEntry], reviewMode: mode, acceptedDocumentTypes: accepted),
                     onResult: { results.values.append($0) })
    }

    private func type(_ lines: [String], into model: ScannerModel) {
        model.updateManualText(Self.text(lines))
        model.readManual(text: Self.text(lines))
    }

    @Test func manualEntryStaysOnTheEntryScreenThenAcceptsAnAcceptedDocument() {
        let results = Results()
        let model = manualModel(idCardOnly, results: results)
        type(Self.passportLines, into: model)
        if case let .manualRaw(text, parseFailed, read) = model.state {
            #expect(text == Self.text(Self.passportLines), "the typed text stays")
            #expect(!parseFailed)
            #expect(read === DocumentCategory.passport)
        } else { Issue.record("stays on the entry screen, got \(model.state)") }
        #expect(results.values.isEmpty)

        // An edit clears the note.
        model.updateManualText(Self.text(Self.passportLines) + "<")
        if case let .manualRaw(_, _, read) = model.state { #expect(read == nil) } else { Issue.record("manual") }

        // An ID card then goes to review as usual.
        type(Self.idCardLines, into: model)
        if case let .review(_, _, source) = model.state { #expect(source == .manualEntry) } else {
            Issue.record("the ID card goes to review, got \(model.state)")
        }
        #expect(results.values.isEmpty)
    }

    @Test func manualEntryUnderInstantReturnReturnsOnlyTheAcceptedDocument() {
        let results = Results()
        let model = manualModel(idCardOnly, mode: .instantReturn, results: results)
        type(Self.passportLines, into: model)
        #expect(results.values.isEmpty, "a not-accepted reading must not be returned under instant-return")
        type(Self.idCardLines, into: model)
        #expect(results.confirmed.count == 1)
        #expect(results.confirmed.first?.recognizedText.lines.map(\.text) == Self.idCardLines)
    }

    @Test func manualEntryWithAnUnknownCategoryGoesToReview() {
        let model = manualModel(passportOnly, results: Results())
        type(Self.uncategorizedLines, into: model)
        if case .review = model.state {} else { Issue.record("unknown category reviews, got \(model.state)") }
    }

    @Test func manualEntryDefaultConfigReviewsAnyCategory() {
        let model = ScannerModel(config: MrzScannerConfig(enabledMethods: [.manualEntry]), onResult: { _ in })
        type(Self.idCardLines, into: model)
        if case .review = model.state {} else { Issue.record("default reviews an ID card, got \(model.state)") }
    }

    // MARK: - Photo screen state

    @Test func thePhotoNotAcceptedScreenBehavesLikeTheOtherPhotoPrompts() {
        let state = ScannerState.savedImageNotAccepted(read: .passport)
        #expect(showsMethodSwitcher(state))
        #expect(activeMethod(state) == .savedImage)
        #expect(announcementKey(for: state) == "tessera_scanner_not_accepted_title_passport")
        #expect(dismissReason(for: state) == .userDismissed)
    }

    // MARK: - Copy

    nonisolated static let newKeys = [
        "tessera_scanner_not_accepted_title_passport",
        "tessera_scanner_not_accepted_title_identity_card",
        "tessera_scanner_not_accepted_title_residence_permit",
        "tessera_scanner_not_accepted_title_visa",
        "tessera_scanner_not_accepted_title_other",
        "tessera_scanner_not_accepted_body",
        "tessera_scanner_not_accepted_separator",
    ]

    @Test(arguments: newKeys)
    func theStringKeyExistsAndStatesFactsOnly(_ key: String) {
        let value = TesseraStrings.string(key, bundle: nil)
        #expect(value != key, "\(key) is in the catalog")
        for word in ["invalid", "wrong", "reject"] {
            #expect(!value.lowercased().contains(word), "\(key): \(value)")
        }
    }

    @Test func eachCategoryHasItsTitle() {
        let expected: [(DocumentCategory, String)] = [
            (.passport, "This looks like a passport"),
            (.identityCard, "This looks like an ID card"),
            (.residencePermit, "This looks like a residence permit"),
            (.visa, "This looks like a visa"),
            (.other, "This looks like another kind of document"),
        ]
        for (category, title) in expected {
            #expect(notAcceptedTitle(category, bundle: nil) == title)
        }
    }

    @Test func theBodyListsTheAcceptedKindsInCategoryOrder() {
        #expect(notAcceptedBody([DocumentCategory.visa, DocumentCategory.passport], bundle: nil) == "This app accepts: passport, visa.")
        #expect(notAcceptedBody(idCardOnly, bundle: nil) == "This app accepts: ID card.")
        #expect(notAcceptedAnnouncement(.identityCard, acceptedDocumentTypes: passportOnly, bundle: nil)
            == "This looks like an ID card\nThis app accepts: passport.")
    }
}
