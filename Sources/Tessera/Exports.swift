// The one re-export: `import Tessera` gives an app the whole generated API (MRZ, camera, chip reading:
// the `TesseraCore` binary) together with the Swift layer in this target. Where both define a name,
// the Swift layer's declaration wins for code that imports `Tessera` (for example `ChipReadReadiness`).
@_exported import TesseraCore
