import SwiftUI

#if canImport(UIKit)
import UIKit

typealias LeafyPlatformImage = UIImage

#elseif canImport(AppKit)
import AppKit

typealias LeafyPlatformImage = NSImage

// Transitional aliases keep shared feature code source-compatible while the
// platform boundary remains centralized in this file.
typealias UIImage = NSImage
typealias UIColor = NSColor

extension Color {
    init(uiColor: NSColor) {
        self.init(nsColor: uiColor)
    }
}

extension NSColor {
    static var systemBackground: NSColor { .windowBackgroundColor }
    static var systemGroupedBackground: NSColor { .windowBackgroundColor }
    static var secondarySystemGroupedBackground: NSColor { .controlBackgroundColor }
    static var tertiarySystemGroupedBackground: NSColor { .underPageBackgroundColor }
    static var secondarySystemBackground: NSColor { .controlBackgroundColor }
    static var separator: NSColor { .separatorColor }
    static var tertiaryLabel: NSColor { .tertiaryLabelColor }
}

extension Image {
    init(uiImage: NSImage) {
        self.init(nsImage: uiImage)
    }
}

extension NSImage {
    var cgImage: CGImage? {
        var proposedRect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }

    var scale: CGFloat { 1 }

    func pngData() -> Data? {
        guard let cgImage else { return nil }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        return representation.representation(using: .png, properties: [:])
    }

    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let cgImage else { return nil }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        return representation.representation(
            using: .jpeg,
            properties: [.compressionFactor: compressionQuality]
        )
    }
}

final class UIGraphicsImageRendererFormat {
    var scale: CGFloat = 1
    var opaque = false
}

struct UIGraphicsImageRendererContext {
    let cgContext: CGContext

    func fill(_ rect: CGRect) {
        cgContext.fill(rect)
    }
}

struct UIGraphicsImageRenderer {
    let size: CGSize
    let format: UIGraphicsImageRendererFormat

    init(size: CGSize, format: UIGraphicsImageRendererFormat = UIGraphicsImageRendererFormat()) {
        self.size = size
        self.format = format
    }

    func image(actions: (UIGraphicsImageRendererContext) -> Void) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocusFlipped(true)
        if let graphicsContext = NSGraphicsContext.current?.cgContext {
            actions(UIGraphicsImageRendererContext(cgContext: graphicsContext))
        }
        image.unlockFocus()
        return image
    }
}

enum UIKeyboardType {
    case `default`
    case URL
    case decimalPad
    case emailAddress
    case numberPad
}

extension View {
    func keyboardType(_ value: UIKeyboardType) -> some View { self }
}
#endif

extension ToolbarItemPlacement {
    static var leafyLeading: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    static var leafyTrailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }

    static var leafyKeyboard: ToolbarItemPlacement {
        #if os(iOS)
        .keyboard
        #else
        .automatic
        #endif
    }
}

extension View {
    @ViewBuilder
    func leafyInsetGroupedListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }

    @ViewBuilder
    func leafyCompactListSectionSpacing() -> some View {
        #if os(iOS)
        listSectionSpacing(.compact)
        #else
        self
        #endif
    }

    @ViewBuilder
    func leafyDisableAutocapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    @ViewBuilder
    func leafyUppercaseAutocapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.characters)
        #else
        self
        #endif
    }

    @ViewBuilder
    func leafyUsernameContentType() -> some View {
        #if os(iOS)
        textContentType(.username)
        #else
        self
        #endif
    }

    @ViewBuilder
    func leafyPasswordContentType() -> some View {
        #if os(iOS)
        textContentType(.password)
        #else
        self
        #endif
    }

    @ViewBuilder
    func leafyOneTimeCodeContentType() -> some View {
        #if os(iOS)
        textContentType(.oneTimeCode)
        #else
        self
        #endif
    }

    @ViewBuilder
    func leafyInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func leafyNavigationBarHidden() -> some View {
        #if os(iOS)
        toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    @ViewBuilder
    func leafyNavigationBarVisible() -> some View {
        #if os(iOS)
        toolbar(.visible, for: .navigationBar)
        #else
        self
        #endif
    }

    @ViewBuilder
    func leafyNavigationToolbarBackgroundHidden() -> some View {
        #if os(iOS)
        toolbarBackground(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }

    @ViewBuilder
    func leafyFullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, content: content)
        #else
        sheet(isPresented: isPresented, content: content)
        #endif
    }

    @ViewBuilder
    func leafyImagePreviewTabStyle(showsIndex: Bool) -> some View {
        #if os(iOS)
        tabViewStyle(.page(indexDisplayMode: showsIndex ? .always : .never))
        #else
        tabViewStyle(.automatic)
        #endif
    }
}

enum LeafyImageCodec {
    static func decode(_ data: Data) -> LeafyPlatformImage? {
        LeafyPlatformImage(data: data)
    }

    static var displayScale: CGFloat {
        #if canImport(UIKit)
        UIScreen.main.scale
        #elseif canImport(AppKit)
        NSScreen.main?.backingScaleFactor ?? 2
        #else
        1
        #endif
    }
}

enum LeafyDeviceInfo {
    static var model: String {
        #if canImport(UIKit)
        UIDevice.current.model
        #else
        "Mac"
        #endif
    }

    static var systemDescription: String {
        #if canImport(UIKit)
        "iOS \(UIDevice.current.systemVersion)"
        #else
        "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        #endif
    }
}

extension ImageRenderer {
    var leafyPlatformImage: LeafyPlatformImage? {
        #if canImport(UIKit)
        uiImage
        #elseif canImport(AppKit)
        nsImage
        #else
        nil
        #endif
    }
}

enum LeafyClipboard {
    static var string: String? {
        get {
            #if canImport(UIKit)
            UIPasteboard.general.string
            #elseif canImport(AppKit)
            NSPasteboard.general.string(forType: .string)
            #else
            nil
            #endif
        }
        set {
            #if canImport(UIKit)
            UIPasteboard.general.string = newValue
            #elseif canImport(AppKit)
            NSPasteboard.general.clearContents()
            if let newValue {
                NSPasteboard.general.setString(newValue, forType: .string)
            }
            #endif
        }
    }
}

enum LeafySystemSettings {
    static func openApplicationSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        let privacyURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        )
        if let privacyURL {
            NSWorkspace.shared.open(privacyURL)
        }
        #endif
    }
}

struct LeafyExternalBrowserView: View {
    @Environment(\.openURL) private var openURL
    let url: URL

    var body: some View {
        ContentUnavailableView {
            Label("在浏览器中打开", systemImage: "safari")
        } description: {
            Text(url.absoluteString)
                .textSelection(.enabled)
        } actions: {
            Button("打开网页") {
                openURL(url)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(minWidth: 480, minHeight: 300)
        .onAppear {
            #if canImport(AppKit)
            NSWorkspace.shared.open(url)
            #endif
        }
    }
}

struct LeafyDocumentPreview: View {
    let url: URL

    var body: some View {
        ContentUnavailableView {
            Label(url.lastPathComponent, systemImage: "doc")
        } description: {
            Text(url.deletingLastPathComponent().path(percentEncoded: false))
                .textSelection(.enabled)
        } actions: {
            #if canImport(AppKit)
            Button("打开文件") {
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.borderedProminent)

            Button("在访达中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            #else
            ShareLink(item: url) {
                Label("打开文件", systemImage: "square.and.arrow.up")
            }
            #endif
        }
        .frame(minWidth: 520, minHeight: 360)
    }
}
