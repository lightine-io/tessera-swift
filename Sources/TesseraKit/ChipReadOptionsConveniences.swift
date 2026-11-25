import Foundation
import Tessera

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
    @discardableResult
    public func dataGroups(_ numbers: [Int]) -> ChipReadOptions.Builder {
        dataGroups(numbers: Set(numbers.map { KotlinInt(int: Int32(clamping: $0)) }))
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
