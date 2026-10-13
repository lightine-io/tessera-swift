# tessera-swift

This repository is the Swift package for Tessera, the open-source SDK that reads, validates, and generates MRZ data. An MRZ (machine-readable zone) is the block of text lines printed at the bottom of a passport or ID card page. The package vends two products: `Tessera`, the XCFramework with the Kotlin core and the headless readers, and `TesseraUI`, the SwiftUI scanner screen. The current release is 0.5.1. The Kotlin source and the releases live in the [main repository](https://github.com/lightine-io/tessera). The SDK reports what it read, and your app decides what to do with it.

## Install

In Xcode, choose **File > Add Package Dependencies**. Enter `https://github.com/lightine-io/tessera-swift` and set the dependency rule to **Exact Version** `0.5.1`. Add both products, `Tessera` and `TesseraUI`, to your app target.

In a `Package.swift`, the same setup looks like this:

```swift
.package(url: "https://github.com/lightine-io/tessera-swift", exact: "0.5.1"),
// In your target's dependencies:
.product(name: "Tessera", package: "tessera-swift"),
.product(name: "TesseraUI", package: "tessera-swift"),
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

For the full walkthrough, with parsing and the output you should see, read [Read your first MRZ on iOS](https://lightine.youtrack.cloud/articles/TES-A-77). To parse every MRZ format and read the fields, read [MRZ parsing](https://lightine.youtrack.cloud/articles/TES-A-25).

## Requirements

- An iOS 18 or higher deployment target.
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
| `TesseraUI` | The SwiftUI scanner screen: `MrzScannerView`, `MrzScannerConfig`, and the result it returns. |

The Swift form of the `Tessera` API is provisional through 0.x. Swift sees the Kotlin shapes, and they may change before 1.0.0. The `TesseraUI` API is written in Swift.

## Documentation

- [Use the SDK](https://lightine.youtrack.cloud/articles/TES-A-16) - guides and reference for every feature.
- [Default scanner UI](https://lightine.youtrack.cloud/articles/TES-A-74) - set the reading methods, review step, theme, and text.
- [Release 0.5.1](https://github.com/lightine-io/tessera/releases/tag/v0.5.1) - the release notes and the XCFramework.

## Contributing

To help build Tessera, read [CONTRIBUTING.md](https://github.com/lightine-io/tessera/blob/main/CONTRIBUTING.md) in the main repository. The [Contribute](https://lightine.youtrack.cloud/articles/TES-A-78) pages cover setup, architecture, testing, and conventions.

## License

Apache License 2.0. See [LICENSE](LICENSE).
