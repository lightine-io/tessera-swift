import Foundation
import Testing
import Tessera
@testable import TesseraKit

/// `ChipReadSettings`, `LinkLoss` and the step sink. The values are checked against what the Kotlin
/// side reports, so a change of a Kotlin default shows up here.
struct ChipReadSettingsTests {
    @Test func theDefaultsAreTheKotlinDefaults() {
        let swift = ChipReadSettings()
        let kotlin = ChipReadSettings(CoreNfcReadSettings())
        #expect(swift.linkLoss == kotlin.linkLoss)
        #expect(swift.settleDelay == kotlin.settleDelay)
        #expect(swift.commandTimeout == kotlin.commandTimeout)
        #expect(swift.waitAfterSystemEnd == kotlin.waitAfterSystemEnd)
        #expect(swift.linkLoss == .resume(Int(CoreNfcReadSettings.companion.DEFAULT_RESTARTS)))
    }

    @Test func oneValueCanChangeAndTheRestStayDefault() {
        let settings = ChipReadSettings(linkLoss: .end)
        #expect(settings.linkLoss == .end)
        #expect(settings.commandTimeout == 5)
        let kotlin = settings.kotlinSettings()
        #expect(kotlin.linkLoss is LinkLossPolicy.End)
        #expect(kotlin.commandTimeoutMillis == 5_000)
    }

    @Test func theSettingsBuildTheKotlinSettings() {
        let kotlin = ChipReadSettings(
            linkLoss: .readAgain(3), settleDelay: 0.25, commandTimeout: 7.5, waitAfterSystemEnd: 2
        ).kotlinSettings()
        #expect(kotlin.linkLoss is LinkLossPolicy.ReadAgain)
        #expect(kotlin.linkLoss.maxRestarts == 3)
        #expect(kotlin.settleDelayMillis == 250)
        #expect(kotlin.commandTimeoutMillis == 7_500)
        #expect(kotlin.waitAfterSystemEndMillis == 2_000)
    }

    @Test func resumeBuildsAResumePolicy() {
        let kotlin = ChipReadSettings(linkLoss: .resume(1)).kotlinSettings()
        #expect(kotlin.linkLoss is LinkLossPolicy.Resume)
        #expect(kotlin.linkLoss.maxRestarts == 1)
    }

    @Test func invalidValuesAreClampedNotRefused() {
        let wild = ChipReadSettings(
            linkLoss: .resume(99), settleDelay: -3, commandTimeout: -1, waitAfterSystemEnd: .nan)
        let normal = wild.normalized
        #expect(normal.linkLoss == .resume(3))
        #expect(normal.settleDelay == 0)
        #expect(normal.commandTimeout == 0.001)
        #expect(normal.waitAfterSystemEnd == 0)
        let kotlin = wild.kotlinSettings() // does not fall back to the defaults: the clamped values are used
        #expect(kotlin.linkLoss.maxRestarts == 3)
        #expect(kotlin.commandTimeoutMillis == 1)
        #expect(kotlin.settleDelayMillis == 0)
        #expect(ChipReadSettings(linkLoss: .readAgain(0)).normalized.linkLoss == .readAgain(1))
    }

    @Test func aHugeTimeoutIsCappedAtADay() {
        #expect(ChipReadSettings(commandTimeout: .infinity).kotlinSettings().commandTimeoutMillis == 86_400_000)
        #expect(ChipReadSettings(commandTimeout: 1e12).normalized.commandTimeout == 86_400)
    }

    @Test func theTelemetrySinkReachesTheKotlinSettings() {
        let sink = ChipReadStepSink { _ in }
        let kotlin = ChipReadSettings(telemetry: sink).kotlinSettings()
        #expect(kotlin.telemetry === sink)
        #expect(ChipReadSettings().kotlinSettings().telemetry == nil)
    }

    @Test func linkLossRoundTripsThroughKotlin() {
        for loss in [LinkLoss.end, .readAgain(2), .resume(3)] {
            #expect(LinkLoss(kotlin: loss.kotlinPolicy()) == loss)
        }
    }

    @Test func theStepSinkIgnoresEventsThatAreNotReadSteps() {
        final class Other: NSObject, TelemetryEvent {
            var name: String { "other" }
        }
        let count = Locked(0)
        let sink = ChipReadStepSink { _ in count.withLock { $0 += 1 } }
        sink.record(event: Other())
        #expect(count.withLock { $0 } == 0)
    }

    @Test func aStepEventHoldsPlainValues() {
        let event = ChipReadStepEvent(step: "READ_FILE", outcome: .failed, protocol: "BAC", fileId: 257, byteCount: 12, statusWord: 0x6982, durationMillis: 40)
        #expect(event.statusWord == 0x6982)
        #expect(event.outcome == .failed)
    }
}
