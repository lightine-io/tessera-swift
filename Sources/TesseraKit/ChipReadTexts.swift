import Foundation
import Tessera

/// The words on the system NFC sheet, from Swift closures.
///
/// Return `nil` from a closure to use the built-in English line for that update or ending, so you
/// change only the lines you care about:
///
/// ```swift
/// let texts = ChipReadTexts(
///     text: { snapshot in
///         if case .waitingForDocument = snapshot.phase { return "Hold the top of the phone on the card" }
///         return nil
///     },
///     ending: { finish in
///         if case .complete = finish.outcome { return "Done" }
///         return nil
///     }
/// )
/// let reading = ChipReading.start(options: options, texts: texts)
/// ```
///
/// The built-in lines and the progress bar: ``builtIn``, and ``progressBar(for:width:)``.
///
/// The closures run on the reader's background queue, so they are `@Sendable`: touch no main-actor
/// state in them.
///
/// - Since: 1.0.0
public final class ChipReadTexts: NSObject, CoreNfcSheetTexts, @unchecked Sendable {
    // `@unchecked Sendable` on our own type: both fields are immutable, and the closures are `@Sendable`.
    private let textForSnapshot: @Sendable (ChipReadSnapshot) -> String?
    private let textForFinish: @Sendable (ChipReadFinish) -> String?

    /// - Parameters:
    ///   - text: The line for an update. `nil` uses the built-in line.
    ///   - ending: The line for the ending. `nil` uses the built-in line.
    public init(
        text: @escaping @Sendable (ChipReadSnapshot) -> String?,
        ending: @escaping @Sendable (ChipReadFinish) -> String?
    ) {
        self.textForSnapshot = text
        self.textForFinish = ending
    }

    /// The built-in English texts, the ones used when you pass none.
    public static let builtIn = ChipReadTexts(text: { _ in nil }, ending: { _ in nil })

    /// The built-in line for an update. An update that did not come from the reader (a scripted
    /// one) has no Kotlin object to ask, and gets an empty string.
    public func builtInText(for snapshot: ChipReadSnapshot) -> String {
        guard let raw = snapshot.raw else { return "" }
        return CoreNfcDefaultSheetTexts.shared.textFor(update: raw)
    }

    /// The built-in line for an ending. A scripted ending gets an empty string.
    public func builtInText(for finish: ChipReadFinish) -> String {
        guard let raw = finish.raw else { return "" }
        return CoreNfcDefaultSheetTexts.shared.textForEnding(ending: raw)
    }

    /// The built-in progress bar, for example `▓▓▓▓░░░░░░ 45%`, for use in your own lines.
    ///
    /// - Parameter width: How many characters the bar has, 1 to 40; a value outside that range is
    ///   clamped. `nil` uses the built-in width (10).
    /// - Returns: The bar and the percent. For a progress that did not come from the reader (a
    ///   scripted one) the bar is drawn here in the same style.
    public static func progressBar(for progress: ChipProgress, width: Int? = nil) -> String {
        let defaults = CoreNfcDefaultSheetTexts.shared
        let chosen = width.map { min(max($0, 1), 40) }
        if let raw = progress.kotlin {
            guard let chosen else { return defaults.progressBar(progress: raw) }
            return (try? defaults.progressBar(progress: raw, width: Int32(chosen))) ?? defaults.progressBar(progress: raw)
        }
        let size = chosen ?? Int(defaults.BAR_WIDTH)
        let filled = min(size, Int(progress.fraction * Double(size)))
        return String(repeating: "\u{2593}", count: filled) + String(repeating: "\u{2591}", count: size - filled)
            + " \(progress.percent)%"
    }

    /// The width of the built-in progress bar.
    public static var progressBarWidth: Int { Int(CoreNfcDefaultSheetTexts.shared.BAR_WIDTH) }

    // MARK: CoreNfcSheetTexts

    public func textFor(update: ChipReadUpdate) -> String {
        let snapshot = ChipReadSnapshot(update)
        return textForSnapshot(snapshot) ?? CoreNfcDefaultSheetTexts.shared.textFor(update: update)
    }

    public func textForEnding(ending: ChipReadEnding) -> String {
        textForFinish(ChipReadFinish(ending)) ?? CoreNfcDefaultSheetTexts.shared.textForEnding(ending: ending)
    }
}
