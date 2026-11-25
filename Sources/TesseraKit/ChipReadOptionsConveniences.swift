import Foundation
import Tessera

/// Why the options builder refused a value before the reader saw it.
///
/// - Since: 1.0.0
public enum ChipReadOptionsError: Error, Sendable, Equatable, CustomStringConvertible {
    /// `dataGroups([])`: an empty list would read no data group. Leave `dataGroups` out to read the
    /// default ones.
    case noDataGroupsChosen

    public var description: String {
        switch self {
        case .noDataGroupsChosen:
            return "no data group chosen: pass at least one number from 1 to 16, or leave dataGroups out for the default ones"
        }
    }
}

extension ChipReadOptions.Builder {
    /// The time the validity checks use, as a `Date`.
    ///
    /// **Without a check time the validity checks are reported as not run**
    /// (`ChipCheckReason.noTimeGiven`): the SDK never reads the clock itself, so a signer
    /// certificate's validity period and the issue date check need a time from you. Pass `Date()`
    /// for "now", or the time you trust (a server time, for example).
    ///
    /// The time is passed to the reader in whole milliseconds.
    ///
    /// - Returns: The builder, for chaining.
    @discardableResult
    public func checkTime(_ date: Date) -> ChipReadOptions.Builder {
        let millis = Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
        return checkTime(time: KotlinInstant.companion.fromEpochMilliseconds(epochMilliseconds: millis))
    }

    /// The validity checks use the current time (`checkTime(Date())`).
    @discardableResult
    public func checkTimeNow() -> ChipReadOptions.Builder { checkTime(Date()) }

    /// The data groups to read, by number: `[1, 2]` for the MRZ and the photo.
    /// A number outside 1 to 16 is refused by `build()`.
    ///
    /// - Throws: ``ChipReadOptionsError/noDataGroupsChosen`` for an empty list (the reader would
    ///   refuse it at `build()` with a message from the Kotlin side). To read the default data groups,
    ///   leave this call out.
    @discardableResult
    public func dataGroups(_ numbers: [Int]) throws -> ChipReadOptions.Builder {
        guard !numbers.isEmpty else { throw ChipReadOptionsError.noDataGroupsChosen }
        return dataGroups(numbers: Set(numbers.map { KotlinInt(int: Int32(clamping: $0)) }))
    }

    /// The scanned document to compare the chip's DG1 with. Adds the `Dg1MatchesPrintedMrz` check:
    /// per field, `same`, `different` or `notComparable`, never a value (see
    /// ``Tessera/ChipCheck/printedComparison``). Without it the check is not added. Only a fact is
    /// reported; whether a difference matters is your decision.
    ///
    /// ```swift
    /// let options = try ChipReadOptions.Builder(accessKey: key).printedDocument(scanned).build()
    /// ```
    @discardableResult
    public func printedDocument(_ document: MrzDocument) -> ChipReadOptions.Builder {
        printedDocument(document: document)
    }

    /// As ``printedDocument(_:)`` with the scanner's parse result: a success or a partial success
    /// holds a document and is used; a failure holds none and adds nothing.
    @discardableResult
    public func printedDocument(parse result: ParseResult) -> ChipReadOptions.Builder {
        printedDocument(document: (result as? ParseResult.Success)?.document
            ?? (result as? ParseResult.PartialSuccess)?.document)
    }

    /// The root certificates for the signer checks, as the result of `TrustAnchors.shared.load(...)`.
    /// A load that found no certificate adds none, and the signer checks say so.
    @discardableResult
    public func trustAnchors(_ load: TrustAnchorLoad) -> ChipReadOptions.Builder {
        trustAnchors(anchors: load.anchors)
    }

    /// The root certificates for the signer checks.
    @discardableResult
    public func trustAnchors(_ anchors: [TrustAnchor]) -> ChipReadOptions.Builder {
        trustAnchors(anchors: anchors)
    }
}
