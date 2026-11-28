// swift-tools-version:6.0
import PackageDescription
import Foundation

// Tessera for iOS ships THREE products from this package:
//
//   • `Tessera`   — everything headless, behind one `import Tessera`: MRZ parsing / validation /
//                   generation, the AVFoundation + Apple Vision live-camera scanner and chip reading.
//                   A hand-written Swift target (Sources/Tessera: the `async` chip-reading layer) that
//                   re-exports the `TesseraCore` binary target, so an app sees both through one import.
//
//   • `TesseraUI` — the default SwiftUI scanner UI (hand-written Swift/SwiftUI per ADR-026), layered over
//                   `Tessera`. Its public surface freezes at the 0.5.0 tag under ADR-007, lockstep-versioned
//                   with the main project.
//
//   • `TesseraLogging` — opt-in, for debugging: one sink that prints each SDK diagnostic event to Apple's
//                   unified log (TES-367). `Tessera` and `TesseraUI` contain no log-writing code.
//
// `TesseraCore` is the XCFramework built from the Kotlin Multiplatform codebase in lightine-io/tessera and
// attached to that project's GitHub release (named `Tessera.xcframework.zip` up to 0.7.0). It is a target,
// not a product: apps reach it through `Tessera`. The url/checksum below come from the main project's
// release workflow; `swift package compute-checksum TesseraCore.xcframework.zip` reproduces the checksum.
//
// Dev-only escape hatch: when TESSERA_LOCAL_XCFRAMEWORK is set, consume a locally-built, unreleased
// TesseraCore.xcframework (e.g. one carrying an additive K/N change not yet in a published release) from
// `.local-xcframework/` instead of the release asset. The committed DEFAULT always points at the release
// URL so CI and consumers are unaffected. The url names the new asset ahead of the release that uploads it:
// until then only the local framework builds (the release workflow rewrites the version and checksum).
let tesseraCoreBinary: Target = {
    if ProcessInfo.processInfo.environment["TESSERA_LOCAL_XCFRAMEWORK"] != nil {
        return .binaryTarget(name: "TesseraCore", path: ".local-xcframework/TesseraCore.xcframework")
    }
    return .binaryTarget(
        name: "TesseraCore",
        url: "https://github.com/lightine-io/tessera/releases/download/v1.1.0/TesseraCore.xcframework.zip",
        checksum: "c2b599dea34e4e989c5bb796ee3bf8c67a767c9ac8c920c482fc6c31412e3ff0"
    )
}()

let package = Package(
    name: "Tessera",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        .library(name: "Tessera", targets: ["Tessera"]),
        .library(name: "TesseraUI", targets: ["TesseraUI"]),
        .library(name: "TesseraLogging", targets: ["TesseraLogging"]),
    ],
    targets: [
        tesseraCoreBinary,
        // Tessera (TES-346): hand-written Swift over the `TesseraCore` binary, no UI imports. One file
        // (Exports.swift) re-exports TesseraCore; the rest is the `async` chip-reading layer.
        .target(
            name: "Tessera",
            dependencies: ["TesseraCore"],
            path: "Sources/Tessera"
        ),
        .target(
            name: "TesseraUI",
            dependencies: ["Tessera"],
            path: "Sources/TesseraUI",
            // The compatibility layer's notes for maintainers: not a resource, not shipped.
            exclude: ["Compat/README.md"],
            resources: [.process("Resources")]
        ),
        // TesseraLogging (TES-367): opt-in sink that logs telemetry events to the unified log.
        .target(
            name: "TesseraLogging",
            dependencies: ["Tessera"],
            path: "Sources/TesseraLogging"
        ),
        // Compiled samples (TES-230): every Swift code block of the public iOS how-to pages and
        // tutorials, one file per page under Samples/. How-tos build in the package's Swift 6
        // mode unless the page states Swift 5. Not in `products`, so nothing ships to
        // consumers. Each tutorial builds an app of its own, so it gets a target of its own.
        // scripts/check-samples.py compares the samples with the live pages.
        // The test action builds only what the tests depend on, so
        // TesseraUITests depends on the samples targets: that is what makes CI compile them.
        .target(
            name: "TesseraSamples",
            dependencies: ["Tessera", "TesseraUI"],
            path: "Samples/HowTo"
        ),
        .target(
            name: "TesseraSamplesSwift5",
            dependencies: ["Tessera"],
            path: "Samples/HowToSwift5",
            // TES-A-18 states the Swift 5 language mode; TES-A-120 builds on it.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "TesseraSamplesFirstMrz",
            dependencies: ["Tessera", "TesseraUI"],
            path: "Samples/Tutorials/FirstMrz"
        ),
        .target(
            name: "TesseraSamplesCameraHeadless",
            dependencies: ["Tessera"],
            path: "Samples/Tutorials/CameraHeadless",
            // TES-A-143 step 2 sets the app to the Swift 5 language mode.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // NEW, mirrors a documentation page that does not exist yet (TES-346).
        .target(
            name: "TesseraSamplesChipReading",
            dependencies: ["Tessera"],
            path: "Samples/HowToChipReading"
        ),
        // Compile-only guards for the import shape (TES-346): an app written for 0.7.0 (`import Tessera`
        // plus `import TesseraUI`, core types unqualified, the scanner view) and an app that imports only
        // `Tessera` and reads a chip. A name that turns ambiguous or drops out of `import Tessera` fails here.
        .target(
            name: "TesseraSamplesImports070",
            dependencies: ["Tessera", "TesseraUI"],
            path: "Tests/ImportShape/App070"
        ),
        .target(
            name: "TesseraSamplesImportsOne",
            dependencies: ["Tessera"],
            path: "Tests/ImportShape/OneImport"
        ),
        .testTarget(
            name: "TesseraTests",
            dependencies: ["Tessera", "TesseraSamplesChipReading", "TesseraSamplesImports070", "TesseraSamplesImportsOne"],
            path: "Tests/TesseraTests"
        ),
        .testTarget(
            name: "TesseraLoggingTests",
            dependencies: ["Tessera", "TesseraLogging"],
            path: "Tests/TesseraLoggingTests"
        ),
        .testTarget(
            name: "TesseraUITests",
            dependencies: [
                "TesseraUI",
                "TesseraSamples", "TesseraSamplesSwift5", "TesseraSamplesFirstMrz", "TesseraSamplesCameraHeadless",
            ],
            path: "Tests/TesseraUITests"
        ),
    ]
)