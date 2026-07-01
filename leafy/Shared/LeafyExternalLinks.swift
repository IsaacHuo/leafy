import Foundation

/// Centralized, validated external links used across the app.
///
/// Each link is a non-optional `URL` built from a compile-time-constant string.
/// `make(_:)` validates the literal once at initialization and traps with a clear
/// message if it is ever edited into a malformed value — surfacing the problem at
/// the definition site instead of via an anonymous force-unwrap at the call site.
nonisolated enum LeafyExternalLinks {
    /// Library seat reservation portal.
    static let librarySeat = make("https://seat.bjfu.edu.cn/jsq-v/#/main/index")

    /// Author's personal blog.
    static let authorBlog = make("https://huoweifang.cn/zh/")

    private static func make(_ string: String) -> URL {
        guard let url = URL(string: string) else {
            preconditionFailure("Invalid LeafyExternalLinks URL literal: \(string)")
        }
        return url
    }
}
