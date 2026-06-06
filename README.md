# tessera-swift

Swift Package Manager (SPM) distribution of **Tessera** — a vendor-neutral SDK for reading and validating identity-document data (Machine Readable Zones) — for iOS / Swift consumers.

> **Status: first release (`0.2.0`) pending.** The Swift package manifest (`Package.swift`) and the `Tessera` XCFramework binary land here when `0.2.0` ships.

## What this repository is

Tessera is built from a single Kotlin Multiplatform codebase. JVM and Android consumers get it from Maven Central; **iOS / Swift consumers get it here**, through Swift Package Manager. This repository hosts the `Package.swift` that vends the `Tessera` XCFramework — the iOS binary, attached as an asset to a release of the main project.

## Using it (once released)

In Xcode: **File → Add Package Dependencies…**, enter this repository's URL, and choose the version. Then `import Tessera`.

## Links

- **Main project & source:** https://github.com/lightine-io/tessera
- **License:** [Apache-2.0](LICENSE)
