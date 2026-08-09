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
            url: "https://github.com/lightine-io/tessera/releases/download/v0.5.0/Tessera.xcframework.zip",
            checksum: "821f9a1fed16dd3136b350065eb48f1adb474708fe55fd9d00ba903c7321b527"
        ),
    ]
)