import Foundation

public struct SessionToken: Codable, Sendable {
    public let value: String
    public let expiresAt: Date?

    public init(value: String, expiresAt: Date? = nil) {
        self.value = value
        self.expiresAt = expiresAt
    }

    public var isValid: Bool { !value.isEmpty && (expiresAt.map { $0 > Date() } ?? true) }
}

public actor APIClient {
    public nonisolated let address: ServerAddress
    private let session: URLSession
    private var token: SessionToken?

    public init(address: ServerAddress, token: SessionToken? = nil, configuration: URLSessionConfiguration? = nil) {
        self.address = address
        self.token = token?.isValid == true ? token : nil
        let config = configuration ?? .ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 24 * 60 * 60
        session = URLSession(configuration: config, delegate: SameOriginRedirects(address: address), delegateQueue: nil)
    }

    public func currentToken() -> SessionToken? { token }

    public func adoptBrowserToken(_ value: SessionToken?) {
        token = value?.isValid == true ? value : nil
    }

    public func findSubscription(kind: String, targetID: String) async throws -> Subscription? {
        var page = 1
        while true {
            try Task.checkCancellation()
            let items = try await list("/api/subscriptions", query: [
                URLQueryItem(name: "kind", value: kind),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: "100")
            ], as: Subscription.self)
            if let match = items.first(where: { $0.targetId == targetID }) { return match }
            if items.count < 100 { return nil }
            page += 1
        }
    }

    public func close() {
        token = nil
        session.invalidateAndCancel()
    }

    public func get<T: Decodable & Sendable>(
        _ path: String, query: [URLQueryItem] = [], as: T.Type = T.self
    ) async throws -> T {
        try await send("GET", path, query: query, as: T.self)
    }

    public func list<T: Decodable & Sendable>(
        _ path: String, query: [URLQueryItem] = [], as: T.Type = T.self
    ) async throws -> [T] {
        let result = try await get(path, query: query, as: Optional<[T]>.self)
        return result ?? []
    }

    public func send<T: Decodable & Sendable>(
        _ method: String, _ path: String, query: [URLQueryItem] = [],
        body: [String: JSONValue]? = nil, as: T.Type = T.self
    ) async throws -> T {
        let request = try makeRequest(method, path, query: query, body: body)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data, endpoint: path)
        storeCookie(response)
        do { return try WireJSON.decoder().decode(T.self, from: data) }
        catch { throw path == "/api/auth/config" ? APIError.wrongService : APIError.invalidResponse }
    }

    public func discard(
        _ method: String, _ path: String, body: [String: JSONValue]? = nil
    ) async throws {
        let request = try makeRequest(method, path, body: body)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data, endpoint: path)
        storeCookie(response)
    }

    public func cropLibraryPoster(movieID: Int, crop: PosterCrop) async throws {
        try await discard("POST", "/api/library/movies/\(movieID)/crop-poster", body: crop.body)
    }

    public func imageData(_ source: String) async throws -> Data {
        let request: URLRequest
        if source.hasPrefix("/api/library/artwork/") {
            request = try makeRequest("GET", source, query: [URLQueryItem(name: "v", value: "auth1")])
        } else {
            guard let url = URL(string: source), ["http", "https"].contains(url.scheme ?? "") else {
                throw APIError.invalidResponse
            }
            request = try makeRequest("GET", "/api/image", query: [
                URLQueryItem(name: "v", value: "4"), URLQueryItem(name: "url", value: source)
            ])
        }
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        return data
    }

    public func consumeEvents(
        _ receive: @Sendable (ServerEvent) async -> Void
    ) async throws {
        var request = try makeRequest("GET", "/api/tasks/events")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 45
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard http.statusCode == 200 else {
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count >= 65536 { break }
            }
            try validate(response, data: data)
            throw APIError.invalidResponse
        }
        guard http.mimeType == "text/event-stream" else { throw APIError.wrongService }
        var parser = EventStreamParser()
        var line = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            if byte == 10 {
                if line.last == 13 { line.removeLast() }
                guard let text = String(data: line, encoding: .utf8) else { throw APIError.invalidResponse }
                if let event = try parser.consume(text) { await receive(event) }
                line.removeAll(keepingCapacity: true)
            } else {
                line.append(byte)
                guard line.count <= 8 * 1024 * 1024 else { throw APIError.oversizedEvent }
            }
        }
        throw URLError(.networkConnectionLost)
    }

    private func makeRequest(
        _ method: String, _ path: String, query: [URLQueryItem] = [],
        body: [String: JSONValue]? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: try address.endpoint(path, query: query))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, token.isValid {
            request.setValue("miyabi_token=\(token.value)", forHTTPHeaderField: "Cookie")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func validate(_ response: URLResponse, data: Data, endpoint: String = "") throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if (200..<300).contains(http.statusCode) { return }
        if endpoint == "/api/auth/config" && [404, 405].contains(http.statusCode) {
            throw APIError.wrongService
        }
        struct ErrorPayload: Decodable { let error: String?; let code: String? }
        let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data)
        if http.statusCode == 401, payload?.code == "AUTH_REQUIRED" {
            token = nil
            throw APIError.authenticationRequired
        }
        throw APIError.http(http.statusCode, payload?.error ?? "服务请求失败")
    }

    private func storeCookie(_ response: URLResponse) {
        guard let http = response as? HTTPURLResponse, let url = http.url else { return }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String { result[key] = value }
        }
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
        where cookie.name == "miyabi_token" {
            token = SessionToken(value: cookie.value, expiresAt: cookie.expiresDate)
            if token?.isValid != true { token = nil }
        }
    }
}

// A reverse proxy may redirect to another host. Never send the session cookie there.
private final class SameOriginRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    private let address: ServerAddress

    init(address: ServerAddress) { self.address = address }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let next = request.url,
              next.scheme?.lowercased() == address.url.scheme?.lowercased(),
              next.host?.lowercased() == address.url.host?.lowercased(),
              effectivePort(next) == effectivePort(address.url)
        else { completionHandler(nil); return }
        completionHandler(request)
    }

    private func effectivePort(_ url: URL) -> Int {
        url.port ?? (url.scheme == "https" ? 443 : 80)
    }
}
