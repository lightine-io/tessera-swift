# tessera-swift

Swift Package Manager (SPM) distribution of **Tessera** — a vendor-neutral SDK for reading and validating identity-document data (Machine Readable Zones) — for iOS / Swift consumers.

> **Current release: `0.5.0`.** The optional SwiftUI default scanner UI (`TesseraUI`), plus headless live-camera, saved-image (pre-captured), and manual-entry MRZ reading (AVFoundation + Apple Vision) and the ICAO Doc 9303 parsing / validation / generation core, vended as the `Tessera` XCFramework.

## What this repository is

Tessera is built from a single Kotlin Multiplatform codebase. JVM and Android consumers get it from Maven Central; **iOS / Swift consumers get it here**, through Swift Package Manager. This repository hosts the `Package.swift` that vends the iOS products, and — from `0.5.0` — the hand-written SwiftUI default UI.

## Products

This package vends two library products:

| Product | What it is |
|---|---|
| **`Tessera`** | The headless SDK: MRZ parsing / validation / generation plus the AVFoundation + Apple Vision live-camera scanner, vended as the `Tessera` XCFramework (built from the [main project](https://github.com/lightine-io/tessera) and attached to its GitHub release). |
| **`TesseraUI`** | *(shipped in `0.5.0`)* The optional default MRZ scanner UI — hand-written SwiftUI layered over the headless `Tessera` APIs. A single entry view (`MrzScannerView`) plus `MrzScannerConfig` and a result callback; live-camera, saved-photo, and manual-entry reading with a review step, localized copy, and VoiceOver support. Its public surface is frozen as of the `0.5.0` tag ([ADR-007](https://lightine.youtrack.cloud/articles/TES-A-37)), lockstep-versioned with `Tessera`. |

Import only what you need — `import Tessera` for the headless SDK, `import TesseraUI` for the default UI (which re-exports the headless types it hands back).

## Using it

In Xcode: **File → Add Package Dependencies…**, enter this repository's URL and choose version **`0.5.0`** (or "Up to Next Major"). Then:

```swift
import Tessera
```

Or in a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/lightine-io/tessera-swift", from: "0.5.0"),
]
```

Minimum deployment target: **iOS 18**.

> **The Swift surface is provisional through the `0.x` line.** How the Kotlin API projects to Swift — notably the camera scanner's result stream and `suspend` functions — may change before `1.0.0` as an idiomatic-Swift adapter is added. The underlying capabilities are stable; the Swift-facing shapes are not yet frozen.

## Links

- **Main project & source:** https://github.com/lightine-io/tessera
- **Release & XCFramework:** https://github.com/lightine-io/tessera/releases/tag/v0.5.0
- **License:** [Apache-2.0](LICENSE)
