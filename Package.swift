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
            url: "https://github.com/lightine-io/tessera/releases/download/v0.2.1/Tessera.xcframework.zip",
            checksum: "de91d7bcb51756e924f34b468396c9e8fc8eac941ca4bca0f33983458bdebf2d"
        ),
    ]
)
