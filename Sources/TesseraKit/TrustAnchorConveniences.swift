import Foundation
import Tessera

extension TrustAnchors {
    /// Loads root certificates from bytes: a master list, one certificate (DER) or PEM certificates.
    /// Never throws: a problem is in the answer (``Tessera/TrustAnchorLoad/problem``).
    ///
    /// Copying `Data` into the reader's byte array is done byte by byte, which is slow for a large
    /// file: prefer ``load(contentsOf:heldRoots:)`` for a file on disk.
    ///
    /// - Parameter heldRoots: Roots you already trust, which a master list's own checks use.
    public func load(data: Data, heldRoots: [TrustAnchor] = []) -> TrustAnchorLoad {
        let bytes = KotlinByteArray(size: Int32(clamping: data.count))
        for (index, byte) in data.enumerated() {
            bytes.set(index: Int32(index), value: Int8(bitPattern: byte))
        }
        return load(bytes: bytes, heldRoots: heldRoots)
    }

    /// Loads root certificates from a file.
    ///
    /// - A **file URL** is read by the SDK from its path. If the URL is security-scoped (it came
    ///   from the document picker or a bookmark), access is started before the read and stopped after
    ///   it, so you do not call `startAccessingSecurityScopedResource()` yourself. A URL that is not
    ///   scoped is read as is.
    /// - A **web URL** (`https://`, or any other scheme) is never fetched: the answer is the SDK's
    ///   `.notALocalFile` problem. Download the file yourself and pass the local URL.
    ///
    /// The read is synchronous, so for a large file call it off the main thread. A file over 16 MiB
    /// is answered with `.tooLarge`. Never throws.
    public func load(contentsOf url: URL, heldRoots: [TrustAnchor] = []) -> TrustAnchorLoad {
        guard url.isFileURL else {
            // The SDK answers `.notALocalFile` for a string with a web scheme, and fetches nothing.
            return load(path: url.absoluteString, heldRoots: heldRoots)
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return load(path: url.path, heldRoots: heldRoots)
    }

    /// The loads joined into one: anchors in order, without a repeat.
    public func merge(_ loads: [TrustAnchorLoad]) -> TrustAnchorLoad {
        merge(loads: KotlinArray<TrustAnchorLoad>(size: Int32(loads.count)) { index in loads[Int(truncating: index)] })
    }
}

extension TrustAnchorLoad {
    /// How many root certificates were read.
    public var anchorCount: Int { anchors.count }
    /// How many certificates in the source could not be read.
    public var unreadableCount: Int { unreadable.count }
    /// `true` when no root certificate was read.
    public var isEmpty: Bool { anchors.isEmpty }
    /// The Kotlin name of the problem (`NOT_FOUND`, `NOT_A_LOCAL_FILE`, ...), or `nil` when the load
    /// had none. Stable names; `problem` is the object.
    public var problemName: String? { problem?.name }
    /// The Kotlin name of what the source was (`MASTER_LIST`, `CERTIFICATE`, ...).
    public var kindName: String { kind.name }
}
