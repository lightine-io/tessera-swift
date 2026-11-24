import Foundation

/// The switch every availability shim in `Compat/` reads, so the old-iOS path of each shim can run on a
/// current iOS (the iOS 27 simulator, a current iPhone). Each shim checks
/// `if #available(iOS N, *), !Compat.forceLegacy { modern } else { legacy }`. See `Compat/README.md`.
///
/// Debug builds only: the initial value comes from the launch argument `-TesseraForceLegacyUI YES` (read
/// through `UserDefaults`, whose argument domain holds launch arguments), and tests set it directly. In a
/// release build `forceLegacy` is the constant `false` and the launch argument is never read, so a shipped
/// binary has no hidden switch: the old path runs only on the old iOS it exists for.
@MainActor
enum Compat {
    #if DEBUG
    /// The launch argument (without its leading dash) that turns ``forceLegacy`` on in a debug build.
    static let forceLegacyLaunchArgument = "TesseraForceLegacyUI"

    /// When `true`, every shim takes its old-iOS path. Debug builds only; see the type's comment.
    static var forceLegacy: Bool = UserDefaults.standard.bool(forKey: forceLegacyLaunchArgument)

    /// The shims whose old-iOS path has run in this process, so a test can see the path it forced was taken.
    static var legacyPathsTaken: Set<CompatShim> = []
    #else
    /// Always `false` in a release build: the old-iOS path runs only on the iOS it exists for.
    static let forceLegacy = false
    #endif

    /// Records that `shim` took its old-iOS path. Debug builds only; a no-op in a release build.
    static func tookLegacyPath(_ shim: CompatShim) {
        #if DEBUG
        legacyPathsTaken.insert(shim)
        #endif
    }
}

/// Every availability shim in `Compat/`, named for what it replaces. The iOS version in each comment is the
/// minimum at which the shim can go (its `COMPAT(iOS N)` doc comment says how).
enum CompatShim: String, CaseIterable, Sendable {
    // BelowIOS16.swift
    /// iOS 16: `NavigationStack`.
    case navigationStack
    /// iOS 16: `.photosPicker`.
    case photosPicker
    /// iOS 16: `ViewThatFits` for the raw MRZ line.
    case viewThatFits
    /// iOS 16: `.scrollDismissesKeyboard`.
    case scrollDismissesKeyboard
    /// iOS 16: `.onGeometryChange`.
    case onGeometryChange
    /// iOS 16: an `if` inside a `.toolbar` builder.
    case toolbarOptionalItem

    // BelowIOS17.swift
    /// iOS 17: `.sensoryFeedback`.
    case sensoryFeedback
    /// iOS 17: the two-parameter `.onChange(of:)`.
    case onChange
}
