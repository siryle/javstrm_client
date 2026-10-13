import Foundation
import Darwin
import JavStrmCore

// Command Line Tools do not ship XCTest; this executable needs no dependencies.
@main
struct CoreVerification {
    static func main() async {
        do {
            if CommandLine.arguments.count > 1 {
                guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--probe" else {
                    throw Failure("Usage: JavStrmVerification --probe <server-address>")
                }
                let client = APIClient(address: try ServerAddress(CommandLine.arguments[2]))
                let config: AccessConfig = try await client.get("/api/auth/config")
                await client.close()
                print("JavStrm detected. Login enabled: \(config.enabled), authenticated: \(config.authenticated)")
                return
            }
            try addresses()
            print("PASS: server addresses")
            try parser()
            print("PASS: SSE parser")
            try fixtures()
            print("PASS: backend fixtures")
            try artwork()
            try posterCrops()
            print("PASS: library artwork sources and poster crop geometry")
            try await transport()
            try await cropTransport()
            print("PASS: authenticated poster crop requests, empty success responses and server errors")
            try await events()
            print("PASS: address validation, SSE parser/transport, 7 backend fixtures, login cookies, auth expiration/isolation, service detection, null lists, image proxy")
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    static func addresses() throws {
        let address = try ServerAddress(" https://example.com/javstrm/// ")
        let url = try address.endpoint("/api/discover/search", query: [.init(name: "q", value: "测试 & + /")])
        try check(url.path == "/javstrm/api/discover/search")
        try check(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "测试 & + /")
        try check(ServerAddress("10.10.10.10:8080").absoluteString == "http://10.10.10.10:8080")
        try check(ServerAddress.segment("a/b?#") == "a%2Fb%3F%23")
        for invalid in ["file:///tmp/test", "https://user:secret@example.com", "https://example.com?q=1"] {
            do { _ = try ServerAddress(invalid); throw Failure("Accepted invalid address") }
            catch APIError.invalidAddress {}
        }
        for invalid in ["//evil.example/api", "/api/../auth", "/api/%2E%2E/auth"] {
            do { _ = try address.endpoint(invalid); throw Failure("Accepted invalid endpoint") }
            catch APIError.invalidAddress {}
        }
        try check(address.endpoint("/api/a b%zz").absoluteString.contains("a%20b%25zz"))
    }

    static func parser() throws {
        var parser = EventStreamParser()
        try check(parser.consume(": heartbeat") == nil)
        _ = try parser.consume("event: tasks")
        _ = try parser.consume("data: [")
        _ = try parser.consume("data: ]")
        let event = try parser.consume("")
        try check(event?.name == "tasks" && event?.data == "[\n]")
        try check(parser.consume("") == nil)
        _ = try parser.consume("data: next")
        try check(parser.consume("")?.name == "message")
        var limited = EventStreamParser(limit: 3)
        do { _ = try limited.consume("data: 1234"); throw Failure("Missing size limit") }
        catch APIError.oversizedEvent {}
    }

    static func fixtures() throws {
        let decoder = WireJSON.decoder()
        let library = try decoder.decode(LibraryPage.self, from: fixture("library_movies"))
        try check(library.movies?.first?.javdbId == "movie-exact")
        try check(library.movies?.last?.actors?.isEmpty == true)
        let movie = try decoder.decode(DiscoverMovie.self, from: fixture("discover_movie"))
        try check(movie.actors?.first?.displayName == "演員")
        let tasks = try decoder.decode([ServerTask].self, from: fixture("tasks"))
        try check(tasks.first?.fraction == 0.5 && tasks.first?.canPause == false)
        try check(tasks.first?.details["current_path"]?.text == "/Movies")
        let subscriptions = try decoder.decode([Subscription].self, from: fixture("subscriptions"))
        try check(subscriptions.first?.targetId == "movie-upcoming")
        let pan = try decoder.decode(PanStatus.self, from: fixture("pan_account"))
        try check(pan.account?.space?.total.bytes == 1099511627776)
        let magnets = try decoder.decode([Magnet].self, from: fixture("discover_magnets"))
        try check(!magnets.isEmpty)
        let offline = try decoder.decode(OfflineActivity.self, from: fixture("offline_tasks"))
        try check(offline.tasks?.isEmpty == false)
    }

    static func transport() async throws {
        let client = try mockClient()
        MockURLProtocol.handler = { request in
            try check(request.httpMethod == "POST")
            try check(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let body = try JSONDecoder().decode([String: JSONValue].self, from: requestBody(request))
            try check(body["password"] == .string("password"))
            return (200, ["Set-Cookie": "miyabi_token=fixture-token; Path=/; Max-Age=3600; HttpOnly; SameSite=Strict"],
                    Data(#"{"success":true,"username":"admin"}"#.utf8))
        }
        let _: LoginResult = try await client.send("POST", "/api/auth/login", body: [
            "username": .string("admin"), "password": .string("password")
        ])
        let token = await client.currentToken()
        try check(token?.value == "fixture-token")
        MockURLProtocol.handler = { request in
            try check(request.value(forHTTPHeaderField: "Cookie") == "miyabi_token=fixture-token")
            return (401, [:], Data(#"{"error":"pan disconnected"}"#.utf8))
        }
        try await expect(.http(401, "pan disconnected")) {
            let _: PanStatus = try await client.get("/api/pan/account")
        }
        let preserved = await client.currentToken()
        try check(preserved?.value == "fixture-token")
        MockURLProtocol.handler = { _ in (401, [:], Data(#"{"code":"AUTH_REQUIRED","error":"login"}"#.utf8)) }
        try await expect(.authenticationRequired) { let _: AccessConfig = try await client.get("/api/auth/config") }
        let expired = await client.currentToken()
        try check(expired == nil)
        MockURLProtocol.handler = { _ in (200, [:], Data("<html>Gitea</html>".utf8)) }
        try await expect(.wrongService) { let _: AccessConfig = try await client.get("/api/auth/config") }
        MockURLProtocol.handler = { _ in (404, [:], Data()) }
        try await expect(.wrongService) { let _: AccessConfig = try await client.get("/api/auth/config") }
        MockURLProtocol.handler = { _ in (200, [:], Data("null".utf8)) }
        let list = try await client.list("/api/tasks", as: ServerTask.self)
        try check(list.isEmpty)
        MockURLProtocol.handler = { request in
            try check(request.url?.host == "example.test" && request.url?.path == "/api/image")
            let query = URLComponents(url: try require(request.url), resolvingAgainstBaseURL: false)?.queryItems
            try check(query?.first(where: { $0.name == "url" })?.value == "https://cdn.test/a.jpg?x=1&y=2")
            return (200, [:], Data([1, 2, 3]))
        }
        let image = try await client.imageData("https://cdn.test/a.jpg?x=1&y=2")
        try check(image == Data([1, 2, 3]))
        await client.adoptBrowserToken(SessionToken(value: "browser-session"))
        let browserToken = await client.currentToken()
        try check(browserToken?.value == "browser-session")
        await client.adoptBrowserToken(nil)
        let loggedOut = await client.currentToken()
        try check(loggedOut == nil)
        await client.close()
    }

    static func artwork() throws {
        let decoder = WireJSON.decoder()
        let page = try decoder.decode(LibraryPage.self, from: fixture("library_movies"))
        let movie = try require(page.movies?.first)
        try check(movie.artwork == movie.poster)
        try check(movie.landscapeArtwork == movie.fanart)
        try check(movie.cropArtwork == movie.fanart)
        var payload = try require(JSONSerialization.jsonObject(with: fixture("library_movies")) as? [String: Any])
        var movies = try require(payload["movies"] as? [[String: Any]])
        movies[0]["poster"] = ""
        movies[0]["fanart"] = ""
        payload["movies"] = movies
        let fallback = try require(decoder.decode(
            LibraryPage.self, from: JSONSerialization.data(withJSONObject: payload)).movies?.first)
        try check(fallback.artwork == movie.cover)
        try check(fallback.landscapeArtwork == movie.cover)
        try check(fallback.cropArtwork == movie.cover)
        movies[0]["cover"] = ""
        movies[0]["poster"] = "/api/library/artwork/poster-only"
        payload["movies"] = movies
        let posterOnly = try require(decoder.decode(
            LibraryPage.self, from: JSONSerialization.data(withJSONObject: payload)).movies?.first)
        try check(posterOnly.landscapeArtwork == "/api/library/artwork/poster-only")
        try check(posterOnly.cropArtwork.isEmpty)
        let empty = try require(page.movies?.last)
        try check(empty.artwork.isEmpty && empty.landscapeArtwork.isEmpty && empty.cropArtwork.isEmpty)
    }

    static func posterCrops() throws {
        let initial = try require(PosterCropSelection(imageWidth: 900, imageHeight: 600))
        try check(initial.crop == PosterCrop(x: 500, y: 0, width: 400, height: 600))
        let smaller = initial.resized(widthDelta: -200)
        try check(smaller.crop.width == 200 && smaller.crop.height == 300)
        let moved = smaller.moved(dx: -1000, dy: 1000)
        try check(moved.crop.x == 0 && moved.crop.y == 300)
        try check(moved.resized(widthDelta: 1000).crop.width == 200)
        let minimum = initial.resized(widthDelta: -1000)
        try check(minimum.crop.width == 2 && minimum.crop.height == 3)
        let portrait = try require(PosterCropSelection(imageWidth: 200, imageHeight: 900))
        try check(portrait.crop.width == 200 && portrait.crop.height == 300)
        try check(PosterCropSelection(imageWidth: 1, imageHeight: 600) == nil)
        try check(PosterCropSelection(imageWidth: 600, imageHeight: 2) == nil)
        for width in [2, 49, 199, 601, 901, 1920] {
            for height in [3, 51, 301, 599, 1080] {
                let selection = try require(PosterCropSelection(imageWidth: width, imageHeight: height))
                for delta in [-10000.0, -48.5, 0, 27.3, 10000] {
                    let adjusted = selection.resized(widthDelta: delta)
                        .moved(dx: delta, dy: -delta)
                        .resized(widthDelta: -delta, minimumWidth: 48)
                    let crop = adjusted.crop
                    try check(crop.x >= 0 && crop.y >= 0 && crop.width >= 2 && crop.height >= 2)
                    try check(crop.x + crop.width <= width && crop.y + crop.height <= height)
                    try check(abs(adjusted.width / adjusted.height - PosterCropSelection.ratio) < 0.000001)
                }
            }
        }
    }

    static func cropTransport() async throws {
        let client = try mockClient()
        await client.adoptBrowserToken(SessionToken(value: "crop-session"))
        let crop = try require(PosterCropSelection(imageWidth: 900, imageHeight: 600)).crop
        MockURLProtocol.handler = { request in
            try check(request.httpMethod == "POST" && request.url?.path == "/api/library/movies/7/crop-poster")
            try check(request.value(forHTTPHeaderField: "Cookie") == "miyabi_token=crop-session")
            let body = try JSONDecoder().decode([String: Int].self, from: requestBody(request))
            try check(body == ["x": 500, "y": 0, "width": 400, "height": 600])
            return (204, [:], Data())
        }
        try await client.cropLibraryPoster(movieID: 7, crop: crop)
        MockURLProtocol.handler = { _ in (409, [:], Data(#"{"error":"no source artwork"}"#.utf8)) }
        try await expect(.http(409, "no source artwork")) {
            try await client.cropLibraryPoster(movieID: 7, crop: crop)
        }
        await client.close()
    }

    static func events() async throws {
        let client = try mockClient()
        let recorder = EventRecorder()
        MockURLProtocol.handler = { request in
            try check(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
            return (200, ["Content-Type": "text/event-stream"],
                    Data("event: tasks\ndata: []\n\nevent: ping\ndata: null\n\n".utf8))
        }
        do { try await client.consumeEvents { await recorder.append($0) } }
        catch let error as URLError { try check(error.code == .networkConnectionLost) }
        let snapshot = await recorder.events
        try check(snapshot.count == 2 && snapshot.first?.name == "tasks" && snapshot.last?.name == "ping")
        await client.close()
    }

    static func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
    }

    static func mockClient() throws -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return APIClient(address: try ServerAddress("https://example.test"), configuration: config)
    }
}

private struct Failure: Error, CustomStringConvertible, LocalizedError {
    let description: String
    init(_ description: String) { self.description = description }
    var errorDescription: String? { description }
}

private func requestBody(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    let stream = try require(request.httpBodyStream)
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count >= 0 else { throw stream.streamError ?? Failure("Cannot read request body") }
        if count == 0 { break }
        data.append(contentsOf: buffer.prefix(count))
    }
    return data
}

private func check(_ condition: @autoclosure () throws -> Bool, file: StaticString = #fileID, line: UInt = #line) throws {
    guard try condition() else { throw Failure("\(file):\(line): check failed") }
}

private func require<T>(_ value: T?) throws -> T {
    guard let value else { throw Failure("Required value is nil") }
    return value
}

private func expect(_ expected: APIError, _ operation: () async throws -> Void) async throws {
    do { try await operation() }
    catch let actual as APIError { try check(actual == expected); return }
    throw Failure("Expected \(expected)")
}

private actor EventRecorder {
    var events: [ServerEvent] = []
    func append(_ event: ServerEvent) { events.append(event) }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, [String: String], Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, headers, data) = try require(Self.handler)(request)
            let response = try require(HTTPURLResponse(url: require(request.url), statusCode: status,
                                                       httpVersion: "HTTP/1.1", headerFields: headers))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
