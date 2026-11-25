import Foundation
import Tessera

// Swift `Int` and `String` views of facts the Kotlin types give as boxed numbers or enums. The
// names follow the existing ones (`statusWordInt`, `percentInt`): the Kotlin property keeps its name,
// the Swift view ends in `Int` or `Name`. The names are the stable Kotlin names of the enum entries.

extension ChipFile {
    /// The data group number (1 to 16), or `nil` for a file that is not a data group.
    public var dataGroupInt: Int? { dataGroup.map { Int($0.int32Value) } }
    /// The byte the file was continued at after a lost link, or `nil` when it was read in one go.
    public var continuedAtInt: Int? { continuedAt.map { Int($0.int32Value) } }
}

extension ChipFileRef {
    /// The data group number (1 to 16), or `nil` for a file that is not a data group.
    public var dataGroupInt: Int? { dataGroup.map { Int($0.int32Value) } }
}

extension AccessReport {
    /// How access was gained: `NONE`, `BAC` or `PACE`.
    public var protocolName: String { self.protocol.name }
    /// The kind of key that opened the chip (`MRZ` or `CAN`), or `nil` when none did.
    public var passwordName: String? { password?.name }
    /// The PACE parameter id as an `Int`, or `nil`.
    public var paceParameterIdInt: Int? { paceParameterId.map { Int($0.int32Value) } }
    /// The name of the PACE mapping, or `nil`.
    public var paceMappingName: String? { paceMapping?.name }
}

extension MasterListCheck {
    /// The stable name of what the master-list fact is about (`SIGNATURE_VERIFIES`, ...). Same as
    /// `kind.name`.
    public var kindName: String { kind.name }
    /// How the fact came out, as a Swift `enum`.
    public var result: ChipCheckResult { ChipCheckResult.from(outcome) }
}

extension UnreadableSignerCertificate {
    /// The place of the certificate in the security object, from 0.
    public var positionInt: Int { Int(position) }
    /// The length of the certificate's bytes.
    public var lengthInt: Int { Int(length) }
    /// The offset in the certificate's bytes where reading stopped.
    public var offsetInt: Int { Int(offset) }
    /// The stable name of the problem (`MALFORMED_ENCODING`, `INVALID_CERTIFICATE_FIELD`).
    public var problemName: String { problem.name }
}

extension SecurityObjectView {
    /// How many signer certificates could not be read, as an `Int`. `unreadableCertificates` lists them.
    public var unreadableCertificateTotal: Int { Int(unreadableCertificateCount) }
}
