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

    // TES-341: a document type code whose first character is a digit, as when the camera misreads the first
    // letter: broadCategory is nil.
    static let digitCodeLines: [String] = generated(MrzGenerator.shared.generateTD3(
        documentType: "1", issuingState: "UTO", documentNumber: "T22000129",
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

    private var digitCode: MrzScanResultDecoded { assembleManualDecoded(text: Self.text(Self.digitCodeLines)) }

    private let passportOnly: Set<DocumentCategory> = [DocumentCategory.passport]
    private let idCardOnly: Set<DocumentCategory> = [DocumentCategory.identityCard]

    // MARK: - Fixtures and config

    @Test func fixturesParseToTheCategoriesTheTestsRelyOn() {
        for decoded in [passport, idCard, uncategorized, digitCode] {
            #expect(!(decoded.parse is ParseResult.Failure), "fixture must parse: \(decoded.parse)")
        }
        #expect(documentCategory(of: passport) === DocumentCategory.passport)
        #expect(documentCategory(of: idCard) === DocumentCategory.identityCard)
        #expect(documentCategory(of: uncategorized) == nil)
        #expect(documentCategory(of: digitCode) == nil)
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
                #expect(read == .ofCategory(.passport))
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

    @Test func aReadingWithNoCategoryIsRefusedWhenTheSetIsLimited() {
        for mode in [ReviewMode.review, .instantReturn] {
            for decoded in [digitCode, uncategorized] {
                if case let .notAccepted(read) = routeDecode(decoded, reviewMode: mode, acceptedDocumentTypes: passportOnly) {
                    #expect(read == .unknown)
                } else { Issue.record("no category with a limited set is refused in \(mode)") }
            }
        }
        #expect(notAcceptedKind(digitCode, acceptedDocumentTypes: idCardOnly) == .unknown)
        #expect(notAcceptedKind(passport, acceptedDocumentTypes: passportOnly) == nil)
    }

    @Test func aReadingWithNoCategoryGoesOnWithTheDefaultSet() {
        if case .showReview = routeDecode(digitCode, reviewMode: .review, acceptedDocumentTypes: allDocumentCategories) {} else {
            Issue.record("no category with the default set reviews")
        }
        if case .returnConfirmed = routeDecode(digitCode, reviewMode: .instantReturn, acceptedDocumentTypes: allDocumentCategories) {} else {
            Issue.record("no category with the default set returns")
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
        let camera = notAcceptedState(for: .camera, read: .ofCategory(.passport),
                                      current: .scanning(struggling: true, gathering: true), manualDraft: "")
        if case let .scanning(struggling, gathering, read) = camera {
            #expect(struggling && !gathering && read == .ofCategory(.passport))
        } else { Issue.record("camera stays on the live preview") }

        if case let .savedImageNotAccepted(read) = notAcceptedState(for: .savedImage, read: .ofCategory(.passport),
                                                                    current: .savedImageAnalyzing, manualDraft: "") {
            #expect(read == .ofCategory(.passport))
        } else { Issue.record("photo gets its own screen") }

        if case let .manualRaw(text, parseFailed, read) = notAcceptedState(for: .manualEntry, read: .ofCategory(.passport),
                                                                           current: .manualRaw(text: "typed", parseFailed: false),
                                                                           manualDraft: "typed") {
            #expect(text == "typed" && !parseFailed && read == .ofCategory(.passport))
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
        #expect(step(idCard) == .notAcceptedGathering(read: .ofCategory(.identityCard)))
        #expect(step(idCard) == .notAccepted(read: .ofCategory(.identityCard)))
        #expect(!routed, "a not-accepted reading must not latch the session")
        // The consensus was reset: one more ID card frame gathers again rather than confirming at once.
        #expect(step(idCard) == .notAcceptedGathering(read: .ofCategory(.identityCard)))
        // A passport now: gathers, then routes.
        #expect(step(passport) == .gathering)
        if case .route = step(passport) {} else { Issue.record("the passport routes") }
        #expect(routed)
    }

    @Test func liveSingleFrameConsensusAndUnknownCategory() throws {
        let consensus = try MrzDecodeConsensus(threshold: 1)
        #expect(stepLiveDecode(idCard, alreadyRouted: false, consensus: consensus, acceptedDocumentTypes: passportOnly)
            == .notAccepted(read: .ofCategory(.identityCard)))
        #expect(stepLiveDecode(idCard, alreadyRouted: false, consensus: consensus, acceptedDocumentTypes: passportOnly)
            == .notAccepted(read: .ofCategory(.identityCard)))
        #expect(stepLiveDecode(digitCode, alreadyRouted: false, consensus: consensus, acceptedDocumentTypes: passportOnly)
            == .notAccepted(read: .unknown))
        if case .route = stepLiveDecode(digitCode, alreadyRouted: false, consensus: consensus, acceptedDocumentTypes: allDocumentCategories) {} else {
            Issue.record("an unknown category routes with the default set")
        }
    }

    @Test func liveNoticeKeepsStrugglingAndDropsTheGatheringCue() {
        if case let .scanning(struggling, gathering, read) = showNotAcceptedNotice(.scanning(struggling: true, gathering: true), read: .ofCategory(.visa)) {
            #expect(struggling && !gathering && read == .ofCategory(.visa))
        } else { Issue.record("stays scanning") }
        // Off the live preview it changes nothing.
        if case .cameraInUse = showNotAcceptedNotice(.cameraInUse, read: .ofCategory(.visa)) {} else { Issue.record("unchanged") }
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

    private func liveNotice(_ model: ScannerModel) -> NotAcceptedKind? {
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
        #expect(liveNotice(model) == .ofCategory(.identityCard))
        #expect(model.confirmedReadHaptic == 0, "no haptic for a not-accepted reading")
        #expect(results.values.isEmpty)

        // The document is still near: a miss within the linger keeps the notice.
        now += 1
        model.onCameraResult(noMrz())
        #expect(liveNotice(model) == .ofCategory(.identityCard))
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
        #expect(liveNotice(model) == .ofCategory(.identityCard))

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

    @Test func cameraRefusesANoCategoryReadingWithALimitedSetAndClearsTheNotice() {
        let results = Results()
        let model = ScannerModel(config: MrzScannerConfig(acceptedDocumentTypes: passportOnly),
                                 onResult: { results.values.append($0) })
        var now = Date(timeIntervalSince1970: 0)
        model.notAcceptedClock = { now }
        model.onCameraResult(digitCode)
        model.onCameraResult(digitCode)
        #expect(liveNotice(model) == .unknown)
        #expect(results.values.isEmpty)
        if case .scanning = model.state {} else { Issue.record("still scanning, got \(model.state)") }
        now += 3.5
        model.onCameraResult(noMrz())
        #expect(liveNotice(model) == nil)
    }

    @Test func cameraWithTheDefaultRoutesANoCategoryReading() {
        let model = ScannerModel(config: MrzScannerConfig(), onResult: { _ in })
        model.onCameraResult(digitCode)
        model.onCameraResult(digitCode)
        if case .review = model.state {} else { Issue.record("default config reviews, got \(model.state)") }
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
            #expect(read == .ofCategory(.passport))
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

    @Test func manualEntryRefusesANoCategoryReadingWithALimitedSetAndAnEditClearsIt() {
        let results = Results()
        let model = manualModel(passportOnly, results: results)
        type(Self.digitCodeLines, into: model)
        if case let .manualRaw(text, parseFailed, read) = model.state {
            #expect(text == Self.text(Self.digitCodeLines) && !parseFailed)
            #expect(read == .unknown)
        } else { Issue.record("stays on the entry screen, got \(model.state)") }
        #expect(results.values.isEmpty)
        model.updateManualText(Self.text(Self.digitCodeLines) + "<")
        if case let .manualRaw(_, _, read) = model.state { #expect(read == nil) } else { Issue.record("manual") }
    }

    @Test func manualEntryWithANoCategoryReadingAndTheDefaultSetGoesToReview() {
        let model = manualModel(allDocumentCategories, results: Results())
        type(Self.digitCodeLines, into: model)
        if case .review = model.state {} else { Issue.record("default set reviews, got \(model.state)") }
    }

    @Test func manualEntryWithAnAcceptedCategoryGoesToReview() {
        let model = manualModel(passportOnly, results: Results())
        type(Self.passportLines, into: model)
        if case .review = model.state {} else { Issue.record("accepted category reviews, got \(model.state)") }
    }

    @Test func photoRefusesANoCategoryReadingWithALimitedSet() {
        // The photo path routes through the same decision, then lands on its own screen.
        guard case let .notAccepted(read) = routeDecode(digitCode, reviewMode: .review, acceptedDocumentTypes: passportOnly) else {
            Issue.record("refused"); return
        }
        if case let .savedImageNotAccepted(kind) = notAcceptedState(for: .savedImage, read: read, current: .savedImageAnalyzing, manualDraft: "") {
            #expect(kind == .unknown)
        } else { Issue.record("photo gets the not-accepted screen") }
    }

    // MARK: - Photo screen state

    @Test func thePhotoNotAcceptedScreenBehavesLikeTheOtherPhotoPrompts() {
        let state = ScannerState.savedImageNotAccepted(read: .ofCategory(.passport))
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
        "tessera_scanner_not_accepted_title_unknown",
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

    @Test func theUnknownKindHasItsTitleAndAnnouncement() {
        #expect(notAcceptedTitle(.unknown, bundle: nil) == "We could not tell what kind of document this is")
        #expect(notAcceptedAnnouncement(.unknown, acceptedDocumentTypes: passportOnly, bundle: nil)
            == "We could not tell what kind of document this is\nThis app accepts: passport.")
        #expect(announcementKey(for: .savedImageNotAccepted(read: .unknown)) == "tessera_scanner_not_accepted_title_unknown")
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
            #expect(notAcceptedTitle(.ofCategory(category), bundle: nil) == title)
        }
    }

    @Test func theBodyListsTheAcceptedKindsInCategoryOrder() {
        #expect(notAcceptedBody([DocumentCategory.visa, DocumentCategory.passport], bundle: nil) == "This app accepts: passport, visa.")
        #expect(notAcceptedBody(idCardOnly, bundle: nil) == "This app accepts: ID card.")
        #expect(notAcceptedAnnouncement(.ofCategory(.identityCard), acceptedDocumentTypes: passportOnly, bundle: nil)
            == "This looks like an ID card\nThis app accepts: passport.")
    }
}
