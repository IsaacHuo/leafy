import SwiftUI

#if os(iOS)
import SafariServices

private struct CampusAIInAppBrowserPage: Identifiable {
    let url: URL

    var id: String { url.absoluteString }
}

private struct CampusAIInAppBrowserModifier: ViewModifier {
    @State private var page: CampusAIInAppBrowserPage?

    func body(content: Content) -> some View {
        content
            .environment(\.openURL, OpenURLAction { url in
                guard Self.isWebURL(url) else { return .systemAction }
                page = CampusAIInAppBrowserPage(url: url)
                return .handled
            })
            .sheet(item: $page) { page in
                CampusAISafariView(url: page.url)
                    .ignoresSafeArea()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
    }

    private static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}

private struct CampusAISafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.barCollapsingEnabled = true
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
#endif

extension View {
    @ViewBuilder
    func campusAIInAppBrowser() -> some View {
        #if os(iOS)
        modifier(CampusAIInAppBrowserModifier())
        #else
        self
        #endif
    }
}
