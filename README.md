# tessera-swift

Swift Package Manager (SPM) distribution of **Tessera** — a vendor-neutral SDK for reading and validating identity-document data (Machine Readable Zones) — for iOS / Swift consumers.

> **Current release: `0.2.1`.** Headless live-camera MRZ reading (AVFoundation + Apple Vision) plus the ICAO Doc 9303 parsing / validation / generation core, vended as the `Tessera` XCFramework.

## What this repository is

Tessera is built from a single Kotlin Multiplatform codebase. JVM and Android consumers get it from Maven Central; **iOS / Swift consumers get it here**, through Swift Package Manager. This repository hosts the `Package.swift` that vends the `Tessera` XCFramework — the iOS binary, attached as an asset to a release of the [main project](https://github.com/lightine-io/tessera).

## Using it

In Xcode: **File → Add Package Dependencies…**, enter this repository's URL and choose version **`0.2.1`** (or "Up to Next Major"). Then:

```swift
import Tessera
```

Or in a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/lightine-io/tessera-swift", from: "0.2.1"),
]
```

Minimum deployment target: **iOS 18**.

> **The Swift surface is provisional through the `0.x` line.** How the Kotlin API projects to Swift — notably the camera scanner's result stream and `suspend` functions — may change before `1.0.0` as an idiomatic-Swift adapter is added. The underlying capabilities are stable; the Swift-facing shapes are not yet frozen.

## Links

- **Main project & source:** https://github.com/lightine-io/tessera
- **Release & XCFramework:** https://github.com/lightine-io/tessera/releases/tag/v0.2.1
- **License:** [Apache-2.0](LICENSE)
