// swift-tools-version:6.0
import PackageDescription

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
let package = Package(
    name: "Tessera",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(name: "Tessera", targets: ["Tessera"]),
        .library(name: "TesseraUI", targets: ["TesseraUI"]),
    ],
    targets: [
        .binaryTarget(
            name: "Tessera",
            url: "https://github.com/lightine-io/tessera/releases/download/v0.4.0/Tessera.xcframework.zip",
            checksum: "1c9c6a7e2d61ffb99c282a302cc712259904fc392b1732d67da66322bbec46b3"
        ),
        .target(
            name: "TesseraUI",
            dependencies: ["Tessera"],
            path: "Sources/TesseraUI"
        ),
        .testTarget(
            name: "TesseraUITests",
            dependencies: ["TesseraUI"],
            path: "Tests/TesseraUITests"
        ),
    ]
)