// Sample for TES-A-112 "Override the text of the iOS scanner screen".
// Each region is one code block of the page, as published. scripts/check-samples.py compares them.
// Blocks 1, 2 and 4 are Localizable.strings lines, not Swift.

// DIFFERS from the page: block 3 adds `import Foundation`; `Bundle` is not in scope with `import TesseraUI` alone.
// region TES-A-112 block 3
import Foundation
import TesseraUI

let config = MrzScannerConfig(stringsBundle: Bundle.main)
// endregion
