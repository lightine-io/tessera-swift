import Foundation
import Testing
import Tessera
@testable import TesseraKit

/// The builder conveniences, the root-certificate loading, the sheet texts and the check helpers.
/// The certificate is a throwaway self-signed one made for this test: no private key is kept.
struct ChipReadConveniencesTests {
    private static let pem = """
        -----BEGIN CERTIFICATE-----
        MIIBhTCCASygAwIBAgIUCoURBCyPn5NBH75XaMuabaEBKkEwCgYIKoZIzj0EAwIw
        KTELMAkGA1UEBhMCVVQxGjAYBgNVBAMMEVRlc3NlcmEgVGVzdCBSb290MB4XDTI2
        MTEyNTAxMzQxM1oXDTM2MTEyMjAxMzQxM1owKTELMAkGA1UEBhMCVVQxGjAYBgNV
        BAMMEVRlc3NlcmEgVGVzdCBSb290MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE
        txuYJNACMIqUeJtpfuLQjPf7SLmdWP29k0ivsfVSyqpWQPrLkcbJM0hVxadsfA3L
        Y7Xxzrs4atHhyQj9unhoMKMyMDAwHQYDVR0OBBYEFL40NQZhdlbeciZa1WvJC0CA
        oYLIMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDRwAwRAIgIL4FNWJuhY1a
        RrPF3IJUm5nWKdEQ9QrO1JbTjN7KefICIAjO3sAJnTboquQcdtyPgkzymG3oUhTo
        1Y4qNXOljydw
        -----END CERTIFICATE-----

        """

    private func key() throws -> ChipAccessKey { try ChipAccessKey.fromCan("123456") }

    // MARK: options

    @Test func checkTimeTakesADate() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000.789)
        let options = try ChipReadOptions.Builder(accessKey: key()).checkTime(date).build()
        #expect(options.checkTime?.toEpochMilliseconds() == 1_700_000_000_789)
    }

    @Test func withoutACheckTimeThereIsNone() throws {
        #expect(try ChipReadOptions.Builder(accessKey: key()).build().checkTime == nil)
    }

    @Test func checkTimeNowIsNearNow() throws {
        let options = try ChipReadOptions.Builder(accessKey: key()).checkTimeNow().build()
        let millis = try #require(options.checkTime?.toEpochMilliseconds())
        #expect(abs(Double(millis) / 1000 - Date().timeIntervalSince1970) < 60)
    }

    @Test func dataGroupsTakeAnIntArray() throws {
        let options = try ChipReadOptions.Builder(accessKey: key()).dataGroups([2, 1, 1]).build()
        #expect(Set(options.dataGroups.map { Int($0.int32Value) }) == [1, 2])
    }

    @Test func aDataGroupOutOfRangeIsRefusedByBuild() throws {
        let builder = try ChipReadOptions.Builder(accessKey: key()).dataGroups([99])
        #expect(throws: Error.self) { _ = try builder.build() }
    }

    @Test func trustAnchorsTakeALoadOrAnArray() throws {
        let load = TrustAnchors.shared.load(data: Data(Self.pem.utf8))
        let fromLoad = try ChipReadOptions.Builder(accessKey: key()).trustAnchors(load).build()
        #expect(fromLoad.trustAnchors.count == 1)
        let fromArray = try ChipReadOptions.Builder(accessKey: key()).trustAnchors(load.anchors).build()
        #expect(fromArray.trustAnchors.count == 1)
    }

    // MARK: trust anchors

    @Test func pemBytesLoadOneAnchor() {
        let load = TrustAnchors.shared.load(data: Data(Self.pem.utf8))
        #expect(load.anchorCount == 1)
        #expect(load.unreadableCount == 0)
        #expect(!load.isEmpty)
        #expect(load.problemName == nil)
        #expect(load.kindName == "PEM_CERTIFICATES")
        #expect(load.anchors.first?.subjectCommonName == "Tessera Test Root")
    }

    @Test func aFileUrlIsRead() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tessera-roots-\(UUID().uuidString).pem")
        try Data(Self.pem.utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let load = TrustAnchors.shared.load(contentsOf: url)
        #expect(load.anchorCount == 1)
        #expect(load.problemName == nil)
    }

    @Test func aMissingFileIsAProblemNotAThrow() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-\(UUID().uuidString).pem")
        let load = TrustAnchors.shared.load(contentsOf: url)
        #expect(load.isEmpty)
        #expect(load.problemName == "NOT_FOUND")
    }

    @Test func aWebUrlIsAnsweredNotALocalFileWithoutFetching() throws {
        // The host does not resolve: if anything fetched it, the answer would be a different problem.
        let url = try #require(URL(string: "https://roots.invalid/masterlist.ml"))
        let load = TrustAnchors.shared.load(contentsOf: url)
        #expect(load.problemName == "NOT_A_LOCAL_FILE")
        #expect(load.isEmpty)
    }

    @Test func bytesThatAreNotCertificatesAreNotRecognised() {
        let load = TrustAnchors.shared.load(data: Data("not a certificate".utf8))
        #expect(load.isEmpty)
        #expect(load.problemName == "NOT_RECOGNIZED")
        #expect(TrustAnchors.shared.load(data: Data()).isEmpty)
    }

    @Test func mergeJoinsLoadsWithoutARepeat() {
        let one = TrustAnchors.shared.load(data: Data(Self.pem.utf8))
        let again = TrustAnchors.shared.load(data: Data(Self.pem.utf8))
        #expect(TrustAnchors.shared.merge([one, again]).anchorCount == 1)
        #expect(one.plus(other: again).anchorCount == 1)
        #expect(TrustAnchors.shared.merge([]).isEmpty)
    }

    // MARK: sheet texts

    @Test func aClosureReplacesALineAndNilKeepsTheBuiltInOne() async throws {
        let real = try await RealReading.sample()
        let update = try #require(real.rawUpdates.first)
        let custom = ChipReadTexts(text: { _ in "custom line" }, ending: { _ in "custom end" })
        #expect(custom.textFor(update: update) == "custom line")
        #expect(custom.textForEnding(ending: real.rawEnding) == "custom end")
        let kept = ChipReadTexts(text: { _ in nil }, ending: { _ in nil })
        #expect(kept.textFor(update: update) == CoreNfcDefaultSheetTexts.shared.textFor(update: update))
        #expect(kept.textForEnding(ending: real.rawEnding) == CoreNfcDefaultSheetTexts.shared.textForEnding(ending: real.rawEnding))
        #expect(ChipReadTexts.builtIn.textFor(update: update) == kept.textFor(update: update))
    }

    @Test func theClosureGetsSwiftValues() async throws {
        let real = try await RealReading.sample()
        let update = try #require(real.rawUpdates.first)
        let seen = Locked<ChipReadPhase?>(nil)
        let texts = ChipReadTexts(text: { snapshot in seen.withLock { $0 = snapshot.phase }; return "x" }, ending: { _ in nil })
        _ = texts.textFor(update: update)
        #expect(seen.withLock { $0 } == update.phase)
    }

    @Test func builtInTextsAreAvailableForRealAndEmptyForScripted() async throws {
        let real = try await RealReading.sample()
        let snapshot = try #require(real.updates.first)
        #expect(!ChipReadTexts.builtIn.builtInText(for: snapshot).isEmpty)
        #expect(!ChipReadTexts.builtIn.builtInText(for: real.ending).isEmpty)
        #expect(ChipReadTexts.builtIn.builtInText(for: ChipReadSnapshot(phase: .starting)) == "")
        #expect(ChipReadTexts.builtIn.builtInText(for: ChipReadFinish(outcome: .cancelled(byPerson: true))) == "")
    }

    @Test func theProgressBarIsTheKotlinOneForARealProgressAndWidthIsClamped() async throws {
        let real = try await RealReading.sample()
        let progress = real.ending.progress
        let raw = try #require(progress.kotlin)
        #expect(ChipReadTexts.progressBar(for: progress) == CoreNfcDefaultSheetTexts.shared.progressBar(progress: raw))
        let wide = ChipReadTexts.progressBar(for: progress, width: 500)
        #expect(wide.filter { $0 == "\u{2593}" || $0 == "\u{2591}" }.count == 40)
        let narrow = ChipReadTexts.progressBar(for: progress, width: 0)
        #expect(narrow.filter { $0 == "\u{2593}" || $0 == "\u{2591}" }.count == 1)
    }

    @Test func aScriptedProgressDrawsABarInTheSameStyle() {
        let bar = ChipReadTexts.progressBar(for: ChipProgress(fraction: 0.45), width: 10)
        #expect(bar == "\u{2593}\u{2593}\u{2593}\u{2593}\u{2591}\u{2591}\u{2591}\u{2591}\u{2591}\u{2591} 45%")
        #expect(ChipReadTexts.progressBarWidth == 10)
    }

    // MARK: errors and checks

    @Test func errorsGiveCodeAndStatusWord() {
        let denied = ChipAccessDenied(protocol: .pace, reason: .keyNotMatched, statusWord: KotlinInt(int: 0x6300))
        #expect(denied.statusWordInt == 0x6300)
        #expect(!denied.code.isEmpty)
        let tag: ChipError = NfcTagLost()
        #expect(tag.statusWordInt == nil)
    }

    @Test func aCheckOutcomeBecomesASwiftEnum() {
        #expect(ChipCheckResult.from(CheckOutcomePassed.shared) == .passed)
        #expect(ChipCheckResult.from(CheckOutcomeFailed(reason: ChipCheckReason.hashDiffers)) == .failed(reason: "HASH_DIFFERS"))
        #expect(ChipCheckResult.from(CheckOutcomeNotRun(reason: ChipCheckReason.noTimeGiven)) == .notRun(reason: "NO_TIME_GIVEN"))
        #expect(ChipCheckResult.from(CheckOutcomeNotApplicable(reason: nil)) == .notApplicable(reason: nil))
    }
}
