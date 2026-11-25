# TesseraUI compatibility layer

TesseraUI supports iOS 15 and later. Every place where iOS 15 or 16 needs a different call lives in this folder, grouped by the iOS version that makes it unnecessary. The views call one clearly named shim each (`CompatNavigationStack { ... }`, `.compatScrollDismissesKeyboard()`, and so on), so dropping an old iOS is a mechanical job.

Every shim has a doc comment in a fixed form:

```
/// COMPAT(iOS 16): <what the old-iOS path does>. When the minimum is iOS 16, replace calls with <the modern call> and delete this.
```

List them with `grep -rn "COMPAT(iOS" Sources/TesseraUI`. Notes on code that is not a shim, but could change once an old iOS is dropped, start with `COMPAT-NOTE(iOS N)`: `grep -rn "COMPAT-NOTE" Sources/TesseraUI`.

## Shims

`BelowIOS16.swift` - goes when the minimum is iOS 16:

| Shim | Modern call |
|---|---|
| `CompatNavigationStack { ... }` | `NavigationStack { ... }` |
| `.compatTopBar(leading:countdown:trailing:)` | `.toolbar { ... }` with an `if let` item (the iOS 16 branch of the shim) |
| `.compatScrollDismissesKeyboard()` | `.scrollDismissesKeyboard(.interactively)` |
| `.compatOnGlobalFrameChange(_:)` | `.onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action:)` |
| `CompatMonoLineFit(text:) { rung }` | `ViewThatFits(in: .horizontal) { ForEach(MonoLineFit.ladder, id: \.self) { rung($0) } }` |
| `.compatSavedImagePicker(isPresented:onPick:)` | `.modifier(SavedImagePhotosPicker(isPresented:onPick:))` |

`BelowIOS17.swift` - goes when the minimum is iOS 17:

| Shim | Modern call |
|---|---|
| `.compatOnChange(of:perform:)` | `.onChange(of: value) { _, newValue in ... }` |
| `.compatSuccessHaptic(trigger:enabled:likelySoon:)` | `.sensoryFeedback(trigger: trigger) { _, _ in enabled ? .success : nil }` |

Not shims, because the iOS SDK marks them available on iOS 15: `Text.tracking(_:)` (on `Text` since iOS 13; only the `View` form needs iOS 16), `.autocorrectionDisabled(_:)` (iOS 13), and the `.topBarLeading` / `.topBarTrailing` toolbar placements (iOS 14, back-deployed). Check the SDK's availability before adding a shim.

`Compat.swift` holds the switch (`Compat.forceLegacy`) and the list of shims (`CompatShim`). It goes with the last shim.

## Running the old paths on a current iOS

In a debug build, `Compat.forceLegacy` makes every shim take its old-iOS path, so the fallbacks run on a current simulator or iPhone. Turn it on with the launch argument `-TesseraForceLegacyUI YES` (Xcode: Edit Scheme > Run > Arguments), or set it in a test. `Tests/TesseraUITests/CompatLegacyPathTests.swift` hosts each screen with it on. In a release build it is the constant `false` and the launch argument is never read.

## Dropping iOS 15

1. Delete `BelowIOS16.swift`.
2. Build. At each compile error, use the modern call that the deleted shim's doc comment named (the table above).
3. In `Package.swift`, change `.iOS(.v15)` to `.iOS(.v16)`.
4. Remove the `@available(iOS 16, *)` marks that are now redundant (`grep -rn "@available(iOS 16" Sources Tests Samples`), including the ones on the `Duration` properties and initializers in `MrzScannerConfig.swift`. The two `@available(iOS 16, *)` `Duration` initializers there can then merge back into one with defaults (`struggleTimeout: Duration? = .seconds(10)`, `scanTimeout: Duration? = nil`); keep the seconds initializer.
5. Remove the `CompatShim` cases of the deleted shims, and the tests in `CompatLegacyPathTests.swift` for them (the `monoLineLegacyFit` tests, the old photo picker tests).
6. In `Package.swift`, remove the `exclude: ["Compat/README.md"]` entry when the `Compat` folder goes away.
7. In `scripts/check-public-api.sh`, change `TARGET_TRIPLE` to `ios16.0`, then update the API baseline with `--update` and review the diff.

## Dropping iOS 16

Drop iOS 15 first. Then the same steps with `BelowIOS17.swift`, `.iOS(.v17)`, the `@available(iOS 17, *)` marks, and `ios17.0`. At that point `Compat.swift` and this folder can go, and `CompatLegacyPathTests.swift` with them.

## What must not be deleted

- The seconds settings in `MrzScannerConfig` (`struggleTimeoutInterval`, `scanTimeoutInterval`, and the initializer that takes them) are public API since 1.0.0. They stay after iOS 15 is dropped, and so does the bridge between seconds and `Duration` in that file. Only its `@available` marks go.
- `ScannerModel` is an `ObservableObject` and the timing is in seconds (`TimeInterval`, `monotonicNow()`). These are not shims: they are the one implementation for every iOS version. Their `COMPAT-NOTE` says what could change later; nothing forces it.
- `SavedImagePhotosPicker` and `PickedImageLoader` in `Views/RootScannerView.swift` are the modern picker, not part of the shim.
