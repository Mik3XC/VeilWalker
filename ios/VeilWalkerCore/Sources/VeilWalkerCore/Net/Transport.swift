import Foundation

/// The VeilWalker API endpoints. Same server as Android.
public enum Backend {
    public static let clearnet = URL(string: "https://feisty-presence-production-b8ec.up.railway.app")!
    /// Plain HTTP inside Tor. Only reachable through the Rust (Arti) transport.
    public static let onion = URL(string: "http://6y62fbzjvat43ep2wukogoszr2wtzc2lkzf2bp22wuixkw4lgwxl6cid.onion")!
}

public struct HTTPRequest: Sendable {
    public var method: String
    public var path: String
    public var query: String?
    public var headers: [String: String]
    public var body: Data

    public init(method: String, path: String, query: String? = nil, headers: [String: String], body: Data) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

/// Moves bytes. Swift does signing and JSON; the transport only carries the request.
/// Clearnet is URLSession; Tor will be the Rust `vw_http` over Arti (build step 2).
public protocol Transport: Sendable {
    /// True if responses from this transport came over the onion service.
    var isOnion: Bool { get }
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// Clearnet HTTPS. Only used when the user has turned Tor off (and in dev builds until Arti lands).
public struct ClearnetTransport: Transport {
    public let isOnion = false
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = Backend.clearnet) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var components = URLComponents(url: baseURL.appending(path: request.path), resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = request.query
        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = request.method
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        if request.method != "GET" {
            urlRequest.httpBody = request.body
        }
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return HTTPResponse(status: http.statusCode, body: data)
    }
}
