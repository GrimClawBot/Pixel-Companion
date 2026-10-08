import Foundation

/// A read-only Paperclip connection never inherits browser/session cookies,
/// cached responses or shared authentication. HTTP redirects are denied so
/// a local SSH tunnel cannot silently redirect requests outside localhost.
enum PaperclipNetworkPolicy {
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(
            configuration: configuration,
            delegate: PaperclipNoRedirectDelegate(),
            delegateQueue: nil
        )
    }

    /// Server-returned identifiers must remain a single unreserved path
    /// segment, not become query, fragment, percent encoding or traversal.
    static func validRelativePath(_ path: String) -> Bool {
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        return !segments.isEmpty && segments.allSatisfy { segment in
            !segment.isEmpty && segment != "." && segment != ".."
                && segment.utf8.allSatisfy { byte in
                    (65...90).contains(byte) || (97...122).contains(byte)
                        || (48...57).contains(byte) || byte == 45
                        || byte == 46 || byte == 95 || byte == 126
                }
        }
    }
}

/// Never forward a redirect to a different host, scheme or URL path.
/// Refusing all redirects is simpler and safer for fixed Paperclip APIs.
final class PaperclipNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
