// swift-tools-version:6.0
import PackageDescription
import Foundation

// Tessera for iOS ships TWO products from this package:
//
//   • `Tessera`   — the headless SDK: MRZ parsing / validation / generation plus the AVFoundation +
//                   Apple Vision live-camera scanner, vended as the `Tessera` XCFramework. Built from the
//                   Kotlin Multiplatform codebase in lightine-io/tessera and attached to that project's
//                   GitHub release. The url/checksum below come from the main project's release workflow;
//                   `swift package compute-checksum Tessera.xcframework.zip` reproduces the checksum.
//
//   • `TesseraUI` — the default SwiftUI scanner UI (hand-written Swift/SwiftUI per ADR-026), layered over
//                   the headless `Tessera` XCFramework. Its public surface freezes at the 0.5.0 tag under
//                   ADR-007, lockstep-versioned with the main project.
// Dev-only escape hatch: when TESSERA_LOCAL_XCFRAMEWORK is set, consume a locally-built, unreleased
// Tessera.xcframework (e.g. one carrying an additive K/N change not yet in a published release) from
// `.local-xcframework/` instead of the release asset. The committed DEFAULT always points at the release
// URL so CI and consumers are unaffected. See TES-82: while the 0.5.0 live-preview seam is unreleased,
// TesseraUI is developed with this set; the release URL/checksum below is bumped when the seam ships.
let tesseraBinary: Target = {
    if ProcessInfo.processInfo.environment["TESSERA_LOCAL_XCFRAMEWORK"] != nil {
        return .binaryTarget(name: "Tessera", path: ".local-xcframework/Tessera.xcframework")
    }
    return .binaryTarget(
        name: "Tessera",
        url: "https://github.com/lightine-io/tessera/releases/download/v0.4.0/Tessera.xcframework.zip",
        checksum: "1c9c6a7e2d61ffb99c282a302cc712259904fc392b1732d67da66322bbec46b3"
    )
}()

let package = Package(
    name: "Tessera",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(name: "Tessera", targets: ["Tessera"]),
        .library(name: "TesseraUI", targets: ["TesseraUI"]),
    ],
    targets: [
        tesseraBinary,
        .target(
            name: "TesseraUI",
            dependencies: ["Tessera"],
            path: "Sources/TesseraUI",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "TesseraUITests",
            dependencies: ["TesseraUI"],
            path: "Tests/TesseraUITests"
        ),
    ]
)