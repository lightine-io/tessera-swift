// swift-tools-version:6.0
import PackageDescription

// Tessera iOS distribution: vends the `Tessera` XCFramework (built from the Kotlin Multiplatform
// codebase in lightine-io/tessera and attached to that project's GitHub release) as a Swift package.
// The url/checksum below are produced by the main project's release workflow; `swift package
// compute-checksum Tessera.xcframework.zip` reproduces the checksum.
let package = Package(
    name: "Tessera",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(name: "Tessera", targets: ["Tessera"]),
    ],
    targets: [
        .binaryTarget(
            name: "Tessera",
            url: "https://github.com/lightine-io/tessera/releases/download/v0.4.0/Tessera.xcframework.zip",
            checksum: "1c9c6a7e2d61ffb99c282a302cc712259904fc392b1732d67da66322bbec46b3"
        ),
    ]
)