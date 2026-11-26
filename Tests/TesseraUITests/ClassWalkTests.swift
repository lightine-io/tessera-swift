import Foundation
import ObjectiveC
import Testing
@testable import TesseraUI

/// `class_getName` taking the class as a raw pointer, so reading a name does not retain the class.
@_silgen_name("class_getName")
private func rawClassGetName(_ cls: UnsafeRawPointer) -> UnsafePointer<CChar>

/// TES-343: imitates what a library that walks every Objective-C class at start does.
///
/// On iOS 15 and 16 a class that is visible to Objective-C, and whose Swift code names a type that
/// iOS does not have yet, can crash the process when the runtime sets the class up. A walk over all
/// classes sets up every one of them, so it is the cheapest way to meet that crash in a test: if a
/// class of this package (Swift types that subclass NSObject, Swift classes, or the Kotlin framework's
/// classes) names a type missing on the running iOS, the walk dies here instead of in an app.
///
/// The test only means something on an old simulator. On the iOS the package was built on, it passes
/// and proves little. The workflow `.github/workflows/old-ios.yml` runs it on iOS 15, 16, 17 and 18.
struct ClassWalkTests {
    /// What the walk saw, so a failure message can say what was found.
    private struct Walk {
        var classCount = 0
        var packageClassNames: [String] = []
        var kotlinClassNames: [String] = []
        var methodCount = 0
        var delegateConformers = 0
    }

    /// Touches one class the way such a library does. Everything here makes the runtime set the class up.
    private static func touch(_ cls: AnyClass, into walk: inout Walk, imageFilter: String?) -> String {
        let name = String(cString: class_getName(cls))
        let image = class_getImageName(cls).map { String(cString: $0) } ?? ""
        if let imageFilter, !image.contains(imageFilter) { return name }

        _ = class_getSuperclass(cls)

        var methodCount: UInt32 = 0
        if let methods = class_copyMethodList(cls, &methodCount) {
            for index in 0 ..< Int(methodCount) {
                let method = methods[index]
                _ = method_getName(method)
                _ = method_getTypeEncoding(method)
            }
            walk.methodCount += Int(methodCount)
            free(methods)
        }

        for protocolName in ["NSURLSessionDelegate", "NSURLSessionTaskDelegate", "NSURLSessionDataDelegate"] {
            // Looked up by name: the protocol object is nil when nothing has loaded it yet.
            if let proto = objc_getProtocol(protocolName), class_conformsToProtocol(cls, proto) {
                walk.delegateConformers += 1
            }
        }

        // A selector lookup runs the class's `+initialize`. That is what a library's walk does to its own and
        // the app's classes, so it is done for the filtered walk only. On every class of the process it
        // would start system frameworks from a test thread (WebKit aborts: "Threading Violation").
        if imageFilter != nil {
            let selector = NSSelectorFromString("URLSession:dataTask:didReceiveResponse:completionHandler:")
            _ = class_getInstanceMethod(cls, selector)
            _ = class_respondsToSelector(cls, selector)
        }
        return name
    }

    /// Classes that cannot be held in a Swift variable. Found by running the walk: `__NSGenericDeallocHandler`
    /// aborted it (TES-343).
    private static func isRuntimeInternal(name: String) -> Bool {
        name.hasPrefix("__NSGenericDeallocHandler") || name.hasPrefix("_NSZombie_") || name.hasPrefix("NSZombie")
    }

    /// Walks the whole class list. `imageFilter` limits the touching to classes whose image path
    /// contains the text; nil touches every class.
    private static func walk(imageFilter: String?) -> Walk {
        var walk = Walk()
        var count: UInt32 = 0
        guard let list = objc_copyClassList(&count) else { return walk }
        // The list is malloc'ed and owned by the caller.
        let rawList = UnsafeMutableRawPointer(list)
        defer { free(rawList) }
        walk.classCount = Int(count)
        let entries = rawList.assumingMemoryBound(to: UnsafeRawPointer?.self)
        for index in 0 ..< Int(count) {
            guard let entry = entries[index] else { continue }
            // Skip the runtime's root classes that do not answer `retain`: holding one in a Swift
            // variable sends it `retain` and aborts the process. The name is read without ARC.
            if Self.isRuntimeInternal(name: String(cString: rawClassGetName(entry))) { continue }
            let cls: AnyClass = unsafeBitCast(entry, to: AnyClass.self)
            let name = touch(cls, into: &walk, imageFilter: imageFilter)
            let image = class_getImageName(cls).map { String(cString: $0) } ?? ""
            if image.contains("TesseraUI") || name.contains("TesseraUI") {
                walk.packageClassNames.append(name)
            }
            // The Kotlin framework is linked in statically, so its classes sit in the same image. Its
            // Objective-C names start with the framework name (the Swift names drop it).
            if name.hasPrefix("Tessera") || name.hasPrefix("Kotlinx_") {
                walk.kotlinClassNames.append(name)
            }
        }
        return walk
    }

    @Test func walkOverThePackagesClassesCompletes() {
        let walk = Self.walk(imageFilter: "Tessera")
        #expect(
            !walk.packageClassNames.isEmpty,
            "No class of TesseraUI found among \(walk.classCount) classes; the filter or the build layout changed."
        )
        #expect(
            !walk.kotlinClassNames.isEmpty,
            "No Kotlin framework class found among \(walk.classCount) classes; its Objective-C prefix may have changed."
        )
        // Printed so the first run on a new iOS shows what was walked.
        print("class walk (package): \(walk.packageClassNames.count) TesseraUI classes, \(walk.kotlinClassNames.count) Kotlin classes, \(walk.methodCount) methods")
    }

    @Test func walkOverAllClassesCompletes() {
        let walk = Self.walk(imageFilter: nil)
        #expect(walk.classCount > 1000, "Only \(walk.classCount) classes in the process; the list looks wrong.")
        #expect(!walk.packageClassNames.isEmpty)
        print("class walk (all): \(walk.classCount) classes, \(walk.methodCount) methods, \(walk.delegateConformers) URLSession delegate conformances")
    }
}
