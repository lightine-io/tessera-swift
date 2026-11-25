# tessera-swift

This repository is the Swift package for Tessera, the open-source SDK that reads, validates, and generates MRZ data. An MRZ (machine-readable zone) is the block of text lines printed at the bottom of a passport or ID card page. The package vends three products: `Tessera`, the XCFramework with the Kotlin core and the headless readers, `TesseraKit`, the headless Swift layer for reading a chip, and `TesseraUI`, the SwiftUI scanner screen. The current release is 0.7.0. The Kotlin source and the releases live in the [main repository](https://github.com/lightine-io/tessera). The SDK reports what it read, and your app decides what to do with it.

## Install

In Xcode, choose **File > Add Package Dependencies**. Enter `https://github.com/lightine-io/tessera-swift` and set the dependency rule to **Exact Version** `0.7.0`. Add the products you use to your app target: `TesseraUI` for the scanner screen, `TesseraKit` for chip reading (next release, see below), and `Tessera` for the core types (`ParseResult`, `MrzDocument`). The table under [What is in the package](#what-is-in-the-package) says what each one gives you.

In a `Package.swift`, the same setup looks like this:

```swift
.package(url: "https://github.com/lightine-io/tessera-swift", exact: "0.7.0"),
// In your target's dependencies:
.product(name: "Tessera", package: "tessera-swift"),
.product(name: "TesseraUI", package: "tessera-swift"),
// For chip reading, from the next release (not in 0.7.0):
// .product(name: "TesseraKit", package: "tessera-swift"),
```

## Show the scanner

Import both modules in the file that uses the scanner. `TesseraUI` does not re-export `Tessera`.

```swift
import AVFoundation
import SwiftUI
import Tessera
import TesseraUI

@main
struct ScannerApp: App {
    var body: some Scene {
        WindowGroup {
            MrzScannerView(
                config: MrzScannerConfig(
                    onRequestPermission: { AVCaptureDevice.requestAccess(for: .video) { _ in } }
                )
            ) { result in
                switch result {
                case let .confirmed(decoded):
                    print("Confirmed: \(decoded.parse.metadata.readMethod.name)")
                case let .cancelled(reason):
                    print("Closed: \(reason)")
                }
                // Your app decides what happens next.
            }
        }
    }
}
```

For the full walkthrough, with the output you should see, read [Read your first MRZ on iOS with the ready-made screen](https://lightine.youtrack.cloud/articles/TES-A-77). To parse an MRZ string in Swift, read [Parse an MRZ string on iOS](https://lightine.youtrack.cloud/articles/TES-A-113).

## Read a chip (headless)

`TesseraKit` reads the chip of a document with no screen of its own: the system NFC sheet is the only interface. It is not part of release 0.7.0; it arrives with the next release. Add the `TesseraKit` product to your target, next to `Tessera` (see [What is in the package](#what-is-in-the-package)), and import both:

```swift
import Tessera
import TesseraKit
```

Everything below is copied from code that is compiled in this repository (`Samples/HowToChipReading`).

**1. Build the key.** A key opens the chip. It is used up by one read, so build a new one for every read. From a scanned MRZ:

```swift
func makeKey(scanned: ParseResult) -> ChipAccessKey? {
    do {
        // A key is used up by one read: build a new one for every read.
        return try ChipAccessKey.from(parse: scanned)
    } catch let error as ChipAccessKeyError {
        // The error names the field and the problem, never the value.
        print("No key: \(error)")
        return nil
    } catch {
        return nil
    }
}
```

From values a person typed in (document number, date of birth, date of expiry; dates are six digits, `YYMMDD`). Every key builder `throws` a `ChipAccessKeyError` that names the field and the problem, never the value:

```swift
func makeKeyFromTypedValues(documentNumber: String, dateOfBirth: String, dateOfExpiry: String) -> ChipAccessKey? {
    // Dates are six digits, YYMMDD. The check digits are worked out for you.
    // Normalising trims spaces and upper-cases letters; nothing else changes.
    let typed = ChipAccessKey.normalizeTypedFields(
        documentNumber: documentNumber, dateOfBirth: dateOfBirth, dateOfExpiry: dateOfExpiry)
    do {
        return try ChipAccessKey.fromTypedFields(
            documentNumber: typed.documentNumber,
            dateOfBirth: typed.dateOfBirth,
            dateOfExpiry: typed.dateOfExpiry)
    } catch let error as ChipAccessKeyError {
        print("No key: \(error)")
        return nil
    } catch {
        return nil
    }
}
```

For the card access number, use `try ChipAccessKey.fromCan("123456")`.

**2. Load root certificates (optional).** Your app chooses the roots it trusts; the SDK bundles none. `load(contentsOf:)` reads a file synchronously and never throws, so call it off the main actor (for example in a `Task.detached` or a nonisolated `async` function):

```swift
func loadRoots(from file: URL) -> TrustAnchorLoad {
    // A file URL from the document picker works as it is.
    let roots = TrustAnchors.shared.load(contentsOf: file)
    if let problem = roots.problemName { print("Roots: \(problem), unreadable: \(roots.unreadableCount)") }
    return roots
}
```

**3. Build the options.** Without `checkTime` the validity checks (a signer certificate's validity period, the issue date, and the dates in DG1) are reported as not run, and `ChipRead.dg1` is `nil`; the raw DG1 is still read. The SDK never reads the clock: pass `Date()` or a time you trust.

```swift
func makeOptions(key: ChipAccessKey, roots: TrustAnchorLoad, scanned: ParseResult) throws -> ChipReadOptions {
    try ChipReadOptions.Builder(accessKey: key)
        .dataGroups([1, 2])
        .trustAnchors(roots)
        .printedDocument(parse: scanned)
        .checkTime(Date())
        .build()
}
```

**4. Start and wait for the ending.** The system NFC sheet opens at once.

```swift
func readOnce(options: ChipReadOptions) async -> ChipRead? {
    let reading = ChipReading.start(options: options)
    let finish = await reading.ending
    return finish.read
}
```

Settings are optional: `ChipReading.start(options:settings:)` takes a `ChipReadSettings`, and every value has a default. The time limits (in seconds): `commandTimeout` (5, only the heavy cryptographic steps), `readTimeout` (2, ordinary commands after access), `commandTimeoutBeforeAccess` (1.5); `settleDelay` (0.4) and `waitAfterSystemEnd` (1); `linkLoss` (resume, 2 restarts); `searchRestart` (4: while the system reports no document, the read asks it to search again on this period; `nil` or 0 turns it off, any other value is at least 2); and `telemetry`. Invalid values are clamped, never refused.

**5. Show progress (optional).** `reading.updates` is an `AsyncStream<ChipReadSnapshot>`. Each snapshot has `.phase` (a `ChipReadPhase`), `.progress`, `.fraction` and `.percent`. The cases of `ChipReadPhase` are `waitingForDocument(waited:)`, `documentFound`, `connecting`, `openingAccess`, `readingFile(dataGroup:bytesRead:bytesTotal:)`, `authenticatingChip`, `checkingFiles`, `noAnswerYet(tries:)` (found, but the chip has not answered yet: show "Move the document slowly"), `linkLost(restartsLeft:)`, `starting`, `stopping` and `unknown`.

```swift
func showProgress(of reading: ChipReading) async {
    for await update in reading.updates {
        print(ChipReadTexts.progressBar(for: update.progress))
        if case .linkLost(let restartsLeft) = update.phase {
            print("Connection lost, \(restartsLeft) tries left")
        }
    }
}
```

**6. Handle every ending.** `finish.outcome` is a `ChipReadOutcome`. Keep an `.unknown` case, because the type may grow.

```swift
func describe(_ outcome: ChipReadOutcome) -> String {
    switch outcome {
    case .complete: return "Done"
    case .partial: return "Some files could not be read"
    case .failed(let error, _): return "The read failed (\(error.code))"
    case .keyNotAccepted: return "The chip did not accept the key"
    case .keyRejected(let error): return "The key was refused before the read (\(error.code))"
    case .cancelled(let byPerson): return byPerson ? "Cancelled" : "Stopped by the app"
    case .endedBySystem: return "The system ended the session"
    case .notStarted: return "NFC is not available"
    case .unknown: return "The read ended in a way this version does not know"
    }
}
```

**No answer.** When the document was found but the chip never got past the first commands, the ending is `.failed` with `NfcNoAnswer` (code `no-answer`). Check it with `outcome.isNoAnswer` (or `error.isNoAnswer`). Tell the person to try another position of the document on the phone: usually the chip gets too little power where it lies.

The payloads: `complete(ChipRead)`, `partial(ChipRead, stoppedBy: ChipError, stoppedIn: ChipReadPhase?)`, `failed(ChipError, access: AccessReport?)`, `keyNotAccepted(ChipAccessDenied)`, `keyRejected(ChipError)`, `cancelled(byPerson: Bool)`, `endedBySystem(NfcError)`, `notStarted(NfcUnavailable.Reason)` and `unknown`. If you do not want to match all of them, use the accessors: `outcome.read` is the `ChipRead?` of a complete or partial read, and `outcome.error` is the `ChipError?` of every ending that has one. `finish.read` is a shortcut for `finish.outcome.read`.

```swift
func summary(of finish: ChipReadFinish) -> String {
    // `read` is set for a complete or a partial read, `error` for every ending that has one.
    if let read = finish.read { return "Read \(read.files.count) files" }
    if let error = finish.outcome.error { return "No data (\(error.code))" }
    return "No data"
}
```

**7. Cancel.** Call `reading.cancel()`; the ending is then `.cancelled(byPerson: false)`. Cancelling the Swift task that awaits `reading.ending` or loops over `reading.updates` does **not** cancel the read: the wait goes on, so tie the task to the read yourself:

```swift
func readUntilLeft(options: ChipReadOptions) async -> ChipReadFinish {
    let reading = ChipReading.start(options: options)
    // Cancelling the task cancels the read.
    return await withTaskCancellationHandler {
        await reading.ending
    } onCancel: {
        reading.cancel()
    }
}
```

`await reading.result()` does this for you: it returns the same ending as `ending`, and cancels the read when its calling task is cancelled (for example a SwiftUI `.task` that ends when the screen goes away).

```swift
func readWhileVisible(options: ChipReadOptions) async -> ChipReadFinish {
    let reading = ChipReading.start(options: options)
    // result() cancels the read when this task is cancelled, for example when a SwiftUI
    // .task ends because the screen went away.
    return await reading.result()
}
```

**8. Set up the app.** Reading a chip needs a paid developer program team and a device with NFC (iPhone 7 or later); the simulator has none, and `ChipReading.availability` tells you why a read cannot start. Add the "Near Field Communication Tag Reading" capability in Xcode, then add the `PACE` value, so the entitlement `com.apple.developer.nfc.readersession.formats` holds `TAG` and `PACE`. In Info.plist add a usage text and the identifier of the passport application, or the system ends the app when it opens the reader:

```xml
<key>NFCReaderUsageDescription</key>
<string>The app reads the chip of your identity document.</string>
<key>com.apple.developer.nfc.readersession.iso7816.select-identifiers</key>
<array>
    <string>A0000002471001</string>
</array>
```

## Requirements

- A deployment target of iOS 15 or higher from the next release (the minimum set in `Package.swift` on `main`). Release 0.7.0 needs iOS 18. Reading a chip needs a device with NFC; the simulator has none.
- Xcode 16 or higher.
- An `NSCameraUsageDescription` entry in your target's Info.plist, or iOS ends the app when it opens the camera:

```xml
<key>NSCameraUsageDescription</key>
<string>The scanner reads the machine-readable zone of identity documents.</string>
```

## What is in the package

| Product | What it gives you |
|---|---|
| `Tessera` | The Kotlin core as an XCFramework: MRZ parsing, validation, and generation, plus the headless camera, saved-image, and manual-entry readers. |
| `TesseraKit` | Headless chip reading in Swift (next release): `ChipReading`, the `ChipAccessKey` builders, `ChipReadOptions.Builder` helpers, `TrustAnchors.shared.load(contentsOf:)`, and the `ChipReadOutcome` enum. It draws nothing and imports no UI framework. It depends on `Tessera`, but does not re-export it: import both. |
| `TesseraUI` | The SwiftUI scanner screen: `MrzScannerView`, `MrzScannerConfig`, and the result it returns. |

Compatibility within 0.x:

- `TesseraUI` is written in Swift, and its API is strict: no breaking change in 0.x. The API baseline check in this repository's CI guards it.
- The Swift form of the `Tessera` framework is generated by Kotlin/Native from the Kotlin API. It may change before 1.0.0, so its rough edges can be fixed (crashing calls, values typed as `Any`, mangled names). Every such change gets its own line under a "Swift" heading in the [CHANGELOG](https://github.com/lightine-io/tessera/blob/main/CHANGELOG.md), with what to change in calling code.
- The Kotlin API underneath is strict: no breaking change in 0.x.

## Documentation

- [Start here](https://lightine.youtrack.cloud/articles/TES-A-16) - what works on iOS, tutorials, how-to guides, and reference.
- [Install Tessera on iOS](https://lightine.youtrack.cloud/articles/TES-A-110) - add the package and its requirements.
- [Show the scanner screen on iOS](https://lightine.youtrack.cloud/articles/TES-A-121) - set the reading methods, review step, theme, and text.
- [Read an MRZ from the live camera on iOS](https://lightine.youtrack.cloud/articles/TES-A-18) - the camera behind your own UI.
- [Release 0.7.0](https://github.com/lightine-io/tessera/releases/tag/v0.7.0) - the release notes and the XCFramework.

## Contributing

To help build Tessera, read [CONTRIBUTING.md](https://github.com/lightine-io/tessera/blob/main/CONTRIBUTING.md) in the main repository. The [Contribute to Tessera](https://lightine.youtrack.cloud/articles/TES-A-78) pages cover setup, architecture, testing, and conventions.

## License

Apache License 2.0. See [LICENSE](LICENSE).
