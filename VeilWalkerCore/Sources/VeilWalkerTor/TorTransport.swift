import Foundation
import VeilWalkerCore

/// The onion service over embedded Arti. Starts Tor on first use; if it can't connect, the request
/// fails and the caller retries later. There is no clearnet fallback.
public struct TorTransport: Transport {
    public let isOnion = true
    private let arti: Arti
    private let baseURL: URL
    private let bootTimeout: Duration
    private let requestTimeout: Duration

    /// Android uses 45 s to bootstrap and 50 s per call; background refresh passes a shorter boot budget.
    public init(arti: Arti = .shared, baseURL: URL = Backend.onion,
                bootTimeout: Duration = .seconds(45), requestTimeout: Duration = .seconds(50)) {
        self.arti = arti
        self.baseURL = baseURL
        self.bootTimeout = bootTimeout
        self.requestTimeout = requestTimeout
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try await arti.start(timeout: bootTimeout)
        var url = baseURL.absoluteString + request.path
        if let query = request.query {
            url += "?" + query
        }
        let headers = request.headers.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        let r = try await arti.http(method: request.method, url: url, headers: headers, body: request.body, timeout: requestTimeout)
        return HTTPResponse(status: r.status, body: r.body)
    }

    /// GET /health on the onion service: true if it answered "ok".
    public func health() async throws -> Bool {
        let r = try await send(HTTPRequest(method: "GET", path: "/health", headers: [:], body: Data()))
        return r.status == 200 && String(decoding: r.body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "ok"
    }
}

/// HTTPS through a Tor exit, for the one clearnet service the app uses: the US National Weather Service.
/// The Rust side refuses any other host (TLS_HOSTS in rust/vw-tor), so this can't become a general proxy.
public enum TorExit {
    public static func get(_ url: URL, headers: [String: String], arti: Arti = .shared,
                           timeout: Duration = .seconds(45)) async throws -> (status: Int, body: Data) {
        try await arti.start()
        let lines = headers.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        return try await arti.http(method: "GET", url: url.absoluteString, headers: lines, body: Data(), timeout: timeout)
    }
}
