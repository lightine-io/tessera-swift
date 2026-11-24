import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Shims for iOS 15. Every declaration here exists only because the package supports iOS 15; when the
// minimum is iOS 16 this whole file goes (see Compat/README.md). Each shim's doc comment starts with
// `COMPAT(iOS 16):` and names the modern call that replaces it.

// MARK: - Navigation container

/// COMPAT(iOS 16): on iOS 15, a `NavigationView` with the stack style, which gives the same single-screen bar,
/// title and toolbar. When the minimum is iOS 16, replace calls with `NavigationStack { ... }` and delete this.
struct CompatNavigationStack<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 16, *), !Compat.forceLegacy {
            NavigationStack { content() }
        } else {
            let _ = Compat.tookLegacyPath(.navigationStack)
            NavigationView { content() }
                .navigationViewStyle(.stack)
        }
    }
}

// MARK: - Toolbar with an optional item

extension View {
    /// COMPAT(iOS 16): iOS 15's toolbar builder cannot take an `if`, so there the countdown and the trailing
    /// item share one trailing `ToolbarItemGroup`, in the same order. When the minimum is iOS 16, replace calls
    /// with `.toolbar { ToolbarItem(placement: .topBarLeading) { leading }; if let countdown {
    /// ToolbarItem(placement: .topBarTrailing) { countdown } }; ToolbarItem(placement: .topBarTrailing) {
    /// trailing } }` (the iOS 16 branch below) and delete this.
    @ViewBuilder
    func compatTopBar<Leading: View, Countdown: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        countdown: Countdown?,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let leading = leading()
        let trailing = trailing()
        if #available(iOS 16, *), !Compat.forceLegacy {
            toolbar {
                ToolbarItem(placement: .topBarLeading) { leading }
                if let countdown {
                    ToolbarItem(placement: .topBarTrailing) { countdown }
                }
                ToolbarItem(placement: .topBarTrailing) { trailing }
            }
        } else {
            let _ = Compat.tookLegacyPath(.toolbarOptionalItem)
            toolbar {
                ToolbarItem(placement: .topBarLeading) { leading }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let countdown { countdown }
                    trailing
                }
            }
        }
    }
}

// MARK: - Keyboard and text input

extension View {
    /// COMPAT(iOS 16): iOS 15 has no such modifier, so there only a tap outside the field and the keyboard's
    /// Done button dismiss the keyboard. When the minimum is iOS 16, replace calls with
    /// `.scrollDismissesKeyboard(.interactively)` and delete this.
    @ViewBuilder
    func compatScrollDismissesKeyboard() -> some View {
        if #available(iOS 16, *), !Compat.forceLegacy {
            scrollDismissesKeyboard(.interactively)
        } else {
            let _ = Compat.tookLegacyPath(.scrollDismissesKeyboard)
            self
        }
    }
}

// MARK: - Global frame

extension View {
    /// COMPAT(iOS 16): on iOS 15, a background `GeometryReader` and a preference deliver the same rectangle, in
    /// the same (global) space, on first layout and on each change. When the minimum is iOS 16, replace calls
    /// with `.onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: action)` and delete
    /// this.
    @ViewBuilder
    func compatOnGlobalFrameChange(_ action: @escaping (CGRect) -> Void) -> some View {
        if #available(iOS 16, *), !Compat.forceLegacy {
            onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: action)
        } else {
            let _ = Compat.tookLegacyPath(.onGeometryChange)
            background(
                GeometryReader { proxy in
                    Color.clear.preference(key: CompatGlobalFrameKey.self, value: proxy.frame(in: .global))
                }
            )
            .onPreferenceChange(CompatGlobalFrameKey.self, perform: action)
        }
    }
}

/// Part of ``View/compatOnGlobalFrameChange(_:)``'s iOS 15 path; goes with it.
private struct CompatGlobalFrameKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

// MARK: - The raw MRZ line's fit ladder

/// COMPAT(iOS 16): iOS 15 has no `ViewThatFits`, so there the offered width is measured and the first rung of
/// `ladder` whose one-line text fits is shown (``monoLineLegacyFit(text:offeredWidth:contentSize:ladder:)``),
/// measured at the text size SwiftUI's environment holds. When the minimum is iOS 16, replace calls with
/// `ViewThatFits(in: .horizontal) { ForEach(MonoLineFit.ladder, id: \.self) { rung($0) } }` and delete this.
struct CompatMonoLineFit<Rung: View>: View {
    let text: String
    var ladder: [MonoLineFit] = MonoLineFit.ladder
    @ViewBuilder let rung: (MonoLineFit) -> Rung

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var offeredWidth: CGFloat?

    var body: some View {
        if #available(iOS 16, *), !Compat.forceLegacy {
            ViewThatFits(in: .horizontal) {
                ForEach(ladder, id: \.self) { fit in
                    rung(fit)
                }
            }
        } else {
            let _ = Compat.tookLegacyPath(.viewThatFits)
            let fit = monoLineLegacyFit(
                text: text,
                offeredWidth: offeredWidth,
                contentSize: UIContentSizeCategory(dynamicTypeSize),
                ladder: ladder
            )
            // The size comes from a hidden copy of the line squeezed to zero width: it gives the height, and
            // the flexible frame then takes exactly the offered width, which the background measures. The
            // visible line is an overlay, so a line that is (for one render) too wide cannot widen the
            // measurement and make the too-wide rung look as if it fits.
            rung(fit)
                .hidden()
                .frame(width: 0, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: CompatOfferedWidthKey.self, value: proxy.size.width)
                    }
                )
                .overlay(alignment: .leading) { rung(fit) }
                .onPreferenceChange(CompatOfferedWidthKey.self) { offeredWidth = $0 }
        }
    }
}

/// Part of ``CompatMonoLineFit``'s iOS 15 path; goes with it. The first rung of `ladder` whose one-line
/// monospaced text is no wider than `offeredWidth`, measured with the UIKit font of the rung's text style at
/// `contentSize` (the host's text size, not the system's); `.scroll` when none is (it always fits). Until the
/// width is known (`nil` or not positive), the `.footnote` rung shows. Pure, so it is host-tested.
@MainActor
func monoLineLegacyFit(
    text: String,
    offeredWidth: CGFloat?,
    contentSize: UIContentSizeCategory,
    ladder: [MonoLineFit] = MonoLineFit.ladder
) -> MonoLineFit {
    guard let offeredWidth, offeredWidth > 0 else { return .footnote }
    let traits = UITraitCollection(preferredContentSizeCategory: contentSize)
    for fit in ladder {
        guard let style = fit.legacyTextStyle else { return fit }
        let size = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits).pointSize
        let font = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        if (text as NSString).size(withAttributes: [.font: font]).width <= offeredWidth { return fit }
    }
    return .scroll
}

extension MonoLineFit {
    /// Part of ``CompatMonoLineFit``'s iOS 15 path; goes with it. The UIKit text style of a one-line rung, for
    /// measuring; `nil` for `.scroll`.
    var legacyTextStyle: UIFont.TextStyle? {
        switch self {
        case .body: return .body
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        case .scroll: return nil
        }
    }
}

/// Part of ``CompatMonoLineFit``'s iOS 15 path; goes with it.
private struct CompatOfferedWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    // The widest value wins: only the one measuring layer sets it, and a sibling that does not set it must
    // not reset it to the default.
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// MARK: - Photo picker

extension View {
    /// COMPAT(iOS 16): on iOS 15, a `PHPickerViewController` (images only, one photo) in a sheet, its data
    /// loaded through the result's `NSItemProvider`. When the minimum is iOS 16, replace calls with
    /// `.modifier(SavedImagePhotosPicker(isPresented: isPresented, onPick: onPick))` and delete this.
    @ViewBuilder
    func compatSavedImagePicker(
        isPresented: Binding<Bool>,
        onPick: @escaping (@escaping PickedImageLoader) -> Void
    ) -> some View {
        if #available(iOS 16, *), !Compat.forceLegacy {
            modifier(SavedImagePhotosPicker(isPresented: isPresented, onPick: onPick))
        } else {
            let _ = Compat.tookLegacyPath(.photosPicker)
            sheet(isPresented: isPresented) {
                LegacyPhotoPicker(isPresented: isPresented, onPick: onPick)
                    .ignoresSafeArea()
            }
        }
    }
}

/// Part of ``View/compatSavedImagePicker(isPresented:onPick:)``'s iOS 15 path; goes with it.
/// `PHPickerViewController` (iOS 14), images only, one photo. The picker reports a cancel as an empty result
/// list: it only dismisses.
struct LegacyPhotoPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (@escaping PickedImageLoader) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: PHPickerViewController, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var parent: LegacyPhotoPicker
        init(parent: LegacyPhotoPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false
            guard let provider = results.first?.itemProvider else { return }
            let box = ItemProviderBox(provider: provider)
            parent.onPick { await box.loadImageData() }
        }
    }
}

/// Part of ``View/compatSavedImagePicker(isPresented:onPick:)``'s iOS 15 path; goes with it. Carries the
/// picked `NSItemProvider` into the loader. `@unchecked Sendable`: the provider is used once, by that loader,
/// and `NSItemProvider` loads are safe to start from any thread.
private struct ItemProviderBox: @unchecked Sendable {
    let provider: NSItemProvider

    /// The image's data in its original representation (what `loadTransferable(type: Data.self)` gives),
    /// or `nil` when it cannot be loaded.
    func loadImageData() async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
