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
            try discoverCardActions()
            try await discoverActionsTransport()
            print("PASS: discovery card states, paginated subscriptions, automatic download defaults and batched movie states")
            try taskDetails()
            print("PASS: workflow progress selection, Chinese labels and per-item result fields")
            try artwork()
            try posterCrops()
            print("PASS: library artwork sources and poster crop geometry")
            try await transport()
            try await cropTransport()
            print("PASS: authenticated poster crop requests, empty success responses and server errors")
            try await taskResultsTransport()
            print("PASS: workflow result endpoints, pagination, authentication and server errors")
            try panLoginModels()
            try await panSettingsTransport()
            print("PASS: native pan QR sessions, scan methods, login states, directory settings and auth isolation")
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

    static func workflowTask(type: String, details: [String: JSONValue]) throws -> ServerTask {
        var payload: [String: JSONValue] = [
            "id": .number(42), "type": .string(type), "status": .string("running"), "progress": .number(50),
            "created_at": .string("2026-10-13T12:00:00Z"), "updated_at": .string("2026-10-13T12:01:00Z"),
            "scan": .object(["stage": .string(""), "movies": .number(0)])
        ]
        payload[type == "subscription_batch" ? "batch" : type] = .object(details)
        return try WireJSON.decoder().decode(ServerTask.self, from: JSONEncoder().encode(payload))
    }

    static func discoverCardActions() throws {
        var payload = try require(JSONSerialization.jsonObject(with: fixture("discover_movie")) as? [String: Any])
        func movie() throws -> DiscoverMovie {
            try WireJSON.decoder().decode(DiscoverMovie.self, from: JSONSerialization.data(withJSONObject: payload))
        }
        try check(movie().cardAction(subscriptionStatus: nil) == .addedOffline)
        payload["state"] = "processing"
        try check(movie().cardAction(subscriptionStatus: "waiting") == .addedOffline)
        payload["state"] = "in_library"
        try check(movie().cardAction(subscriptionStatus: "added") == .inLibrary)
        payload["state"] = "not_in_library"
        try check(movie().cardAction(subscriptionStatus: nil) == .subscribe)
        try check(movie().cardAction(subscriptionStatus: "waiting") == .subscribed)
        try check(movie().cardAction(subscriptionStatus: "added") == .addedOffline)
        for status in ["stale", "error"] {
            try check(movie().cardAction(subscriptionStatus: status) == .subscribe)
        }
        try check(movie().cardAction(subscriptionStatus: "waiting", currentState: "in_library") == .inLibrary)
        try check(movie().cardAction(subscriptionStatus: nil, currentState: "saving") == .addedOffline)
        payload["state"] = "in_library"
        try check(movie().cardAction(subscriptionStatus: nil, currentState: "not_in_library") == .subscribe)
        payload["state"] = "not_in_library"
        payload["magnets_count"] = 0
        try check(movie().cardAction(subscriptionStatus: "waiting") == .subscribed)
        try check(movie().cardAction(subscriptionStatus: "added") == .addedOffline)
        for releaseStatus in ["released", "upcoming", "unknown"] {
            payload["release_status"] = releaseStatus
            try check(movie().cardAction(subscriptionStatus: nil) == .subscribe)
            for status in ["stale", "error"] {
                try check(movie().cardAction(subscriptionStatus: status) == .subscribe)
            }
        }
        payload["magnets_count"] = NSNull()
        try check(movie().cardAction(subscriptionStatus: nil) == .subscribe)
        payload.removeValue(forKey: "release_status")
        payload.removeValue(forKey: "magnets_count")
        payload.removeValue(forKey: "state")
        try check(movie().cardAction(subscriptionStatus: nil) == .subscribe)
    }

    static func discoverActionsTransport() async throws {
        let client = try mockClient()
        await client.adoptBrowserToken(SessionToken(value: "discover-session"))
        let records = try require(JSONSerialization.jsonObject(with: fixture("subscriptions")) as? [[String: Any]])
        let subscription = try require(records.first)
        let response = try JSONSerialization.data(withJSONObject: subscription)
        for automatic in [true, false] {
            MockURLProtocol.handler = { request in
                try check(request.httpMethod == "POST" && request.url?.path == "/api/subscriptions")
                try check(request.value(forHTTPHeaderField: "Cookie") == "miyabi_token=discover-session")
                let body = try JSONDecoder().decode([String: JSONValue].self, from: requestBody(request))
                try check(body["kind"] == .string("movie") && body["target_id"] == .string("movie-upcoming"))
                try check(body["auto_download"] == .bool(automatic))
                return (201, [:], response)
            }
            if automatic {
                let result = try await client.subscribeMovie(targetID: "movie-upcoming")
                try check(result.targetId == "movie-upcoming")
            } else {
                let _ = try await client.subscribeMovie(targetID: "movie-upcoming", autoDownload: false)
            }
        }
        let firstPage = try JSONSerialization.data(withJSONObject: (1...100).map { id in
            var item = subscription
            item["id"] = id
            item["target_id"] = "movie-\(id)"
            return item
        })
        let lastPage = try JSONSerialization.data(withJSONObject: records)
        MockURLProtocol.handler = { request in
            try check(request.httpMethod == "GET" && request.url?.path == "/api/subscriptions")
            try check(request.value(forHTTPHeaderField: "Cookie") == "miyabi_token=discover-session")
            let query = URLComponents(url: try require(request.url), resolvingAgainstBaseURL: false)?.queryItems
            try check(query?.first { $0.name == "kind" }?.value == "movie")
            try check(query?.first { $0.name == "limit" }?.value == "100")
            let page = query?.first { $0.name == "page" }?.value
            try check(page == "1" || page == "2")
            return (200, [:], page == "1" ? firstPage : lastPage)
        }
        let items = try await client.subscriptions(kind: "movie")
        try check(items.count == 102 && items.last?.status == "added")
        MockURLProtocol.handler = { _ in (200, [:], Data("null".utf8)) }
        let empty = try await client.subscriptions(kind: "movie")
        try check(empty.isEmpty)

        let movie = try WireJSON.decoder().decode(DiscoverMovie.self, from: fixture("discover_movie"))
        MockURLProtocol.handler = { request in
            try check(request.httpMethod == "POST" && request.url?.path == "/api/discover/movie-states")
            try check(request.value(forHTTPHeaderField: "Cookie") == "miyabi_token=discover-session")
            let body = try JSONDecoder().decode([String: JSONValue].self, from: requestBody(request))
            guard case let .array(movies) = body["movies"] else { throw Failure("Missing movie identities") }
            try check(movies.count == 100 || movies.count == 1)
            try check(movies.allSatisfy { $0 == .object(["id": .string(movie.id), "code": .string(movie.code)]) })
            let states = movies.map { _ in ["id": movie.id, "library_id": 7, "state": "in_library"] as [String: Any] }
            return (200, [:], try JSONSerialization.data(withJSONObject: states))
        }
        let states = try await client.movieStates(Array(repeating: movie, count: 101))
        try check(states.count == 101 && states.first?.libraryId == 7 && states.last?.state == "in_library")
        MockURLProtocol.handler = { _ in throw Failure("Empty movie list must not request states") }
        let emptyStates = try await client.movieStates([])
        try check(emptyStates.isEmpty)
        MockURLProtocol.handler = { _ in (503, [:], Data(#"{"error":"unavailable"}"#.utf8)) }
        try await expect(.http(503, "unavailable")) { _ = try await client.subscriptions(kind: "movie") }
        try await expect(.http(503, "unavailable")) { _ = try await client.subscribeMovie(targetID: movie.id) }
        try await expect(.http(503, "unavailable")) { _ = try await client.movieStates([movie]) }
        await client.close()
    }

    static func taskDetails() throws {
        let types = [
            "scan", "organize", "strm_generate", "strm_scrape", "subscription_batch",
            "emby_actor_sync", "empty_directory", "favorite_transfer", "strm_probe", "sync_delete"
        ]
        let progress: [String: JSONValue] = [
            "stage": .string("scraping"), "current_code": .string("ABC-123"),
            "processed": .number(3), "failed": .number(0), "current_path": .string(""),
            "extra_paths": .array([.string("/media/one.strm"), .string("/media/two.strm")])
        ]
        for type in types {
            let task = try workflowTask(type: type, details: progress)
            try check(task.details == progress)
            try check(task.detailFields.first?.id == "stage" && task.detailFields.first?.value == "刮削中")
            try check(task.detailFields.first { $0.id == "current_code" }?.label == "当前番号")
            try check(task.detailFields.first { $0.id == "failed" }?.value == "0")
            try check(!task.detailFields.contains { $0.id == "current_path" })
            try check(task.detailFields.first { $0.id == "extra_paths" }?.value == "/media/one.strm\n/media/two.strm")
            let unsupported = ["scan", "subscription_batch"].contains(type)
            try check((task.resultsPath == nil) == unsupported)
        }
        let scan = try require(WireJSON.decoder().decode([ServerTask].self, from: fixture("tasks")).first)
        try check(scan.detailFields.first { $0.id == "source" }?.value == "/Movies")
        let unknown = try workflowTask(type: "future_workflow", details: progress)
        try check(unknown.details.isEmpty && unknown.resultsPath == nil)
        let batch = try workflowTask(type: "subscription_batch", details: [
            "total": .number(1), "failures": .array([
                .object(["code": .string("ABC-123"), "error": .string("没有可用资源")])
            ])
        ])
        try check(batch.embeddedResults.first?.status == "failed")
        try check(batch.embeddedResults.first?.error == "没有可用资源")
        try check(!batch.detailFields.contains { $0.id == "failures" })
        try check(JSONValue.object(["error": .string("失败")]).detailText == "错误信息：失败")
        try check(JSONValue.null.detailText.isEmpty)

        let resultPage = try WireJSON.decoder().decode(WorkflowResultsPage.self, from: fixture("workflow_results"))
        let results = try require(resultPage.items)
        try check(resultPage.taskId == 42 && resultPage.total == 8 && resultPage.page == 1 && !resultPage.hasMore)
        try check(results.count == 8)
        try check(results[0].title == "ABC-123" && results[0].status == "success")
        try check(results[0].detailFields.map(\.label) == ["源文件", "目标文件"])
        try check(results[1].detailFields.first?.label == "删除目录")
        try check(results[2].status == "subtitle_missing" && results[2].error == "字幕下载失败")
        try check(results[2].detailFields.first?.value == "/media/a.strm\n/media/b.strm")
        try check(results[2].detailFields.last?.label == "元数据")
        try check(results[3].detailFields.map(\.label) == ["源文件", "STRM 文件"])
        try check(results[4].title == "演员" && results[4].detailFields.first?.label == "演员 ID")
        try check(results[5].detailFields.first?.label == "目录")
        try check(results[6].detailFields.map(\.label) == ["源文件", "目标 STRM", "115 路径"])
        try check(results[7].detailFields.map(\.label) == ["STRM 文件", "媒体项 ID", "媒体源 ID"])
        let generate = try workflowTask(type: "strm_generate", details: [
            "results": .array([.object(results[3].fields)])
        ])
        try check(generate.embeddedResults == [results[3]] && generate.detailFields.isEmpty)
    }

    static func taskResultsTransport() async throws {
        let client = try mockClient()
        await client.adoptBrowserToken(SessionToken(value: "task-session"))
        var payload = try require(JSONSerialization.jsonObject(with: fixture("workflow_results")) as? [String: Any])
        payload["page"] = 2
        payload["total"] = 58
        let data = try JSONSerialization.data(withJSONObject: payload)
        for type in [
            "organize", "strm_scrape", "strm_generate", "emby_actor_sync",
            "empty_directory", "favorite_transfer", "strm_probe", "sync_delete"
        ] {
            let task = try workflowTask(type: type, details: [:])
            let expectedPath = "/api/tasks/\(type.replacingOccurrences(of: "_", with: "-"))/42/results"
            MockURLProtocol.handler = { request in
                try check(request.httpMethod == "GET" && request.url?.path == expectedPath)
                try check(request.value(forHTTPHeaderField: "Cookie") == "miyabi_token=task-session")
                let query = URLComponents(url: try require(request.url), resolvingAgainstBaseURL: false)?.queryItems
                try check(query?.first { $0.name == "page" }?.value == "2")
                return (200, [:], data)
            }
            let result = try await client.taskResults(task, page: 2)
            try check(result.items?.count == 8 && result.taskId == task.id && result.page == 2 && result.total == 58)
        }
        let task = try workflowTask(type: "organize", details: [:])
        MockURLProtocol.handler = { _ in
            (200, [:], Data(#"{"task_id":42,"items":null,"total":0,"page":1,"has_more":false}"#.utf8))
        }
        let empty = try await client.taskResults(task)
        try check(empty.items == nil && !empty.hasMore)
        MockURLProtocol.handler = { _ in
            (200, [:], Data(#"{"task_id":42,"items":[],"total":51,"page":1,"has_more":true}"#.utf8))
        }
        let more = try await client.taskResults(task)
        try check(more.hasMore && more.page == 1 && more.total == 51)
        MockURLProtocol.handler = { _ in (404, [:], Data(#"{"error":"任务不存在"}"#.utf8)) }
        try await expect(.http(404, "任务不存在")) { _ = try await client.taskResults(task) }
        MockURLProtocol.handler = { _ in (401, [:], Data(#"{"code":"AUTH_REQUIRED","error":"login"}"#.utf8)) }
        try await expect(.authenticationRequired) { _ = try await client.taskResults(task) }
        let scan = try workflowTask(type: "scan", details: [:])
        MockURLProtocol.handler = { _ in throw Failure("Unsupported task must not request a results endpoint") }
        try await expect(.invalidResponse) { _ = try await client.taskResults(scan) }
        await client.close()
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

    static func panLoginModels() throws {
        let decoder = WireJSON.decoder()
        let login = try decoder.decode(PanLoginSession.self, from: Data(
            #"{"id":"qr-session","qr_code":"data:image/png;base64,iVBORw0KGgo=","client_type":"115ios"}"#.utf8))
        try check(login.id == "qr-session" && login.clientType == "115ios")
        try check(login.qrCodeData == Data([137, 80, 78, 71, 13, 10, 26, 10]))
        for code in ["data:image/png;base64,???", "data:image/png;base64,", "https://example.test/qr.png"] {
            let data = try JSONEncoder().encode(["id": "qr-session", "qr_code": code])
            try check(decoder.decode(PanLoginSession.self, from: data).qrCodeData == nil)
        }
        for raw in ["waiting", "scanned", "authorized", "expired", "canceled"] {
            let data = try JSONEncoder().encode(["state": raw])
            let status = try decoder.decode(PanLoginStatus.self, from: data)
            try check(status.state.rawValue == raw)
            try check(status.state.isPending == (raw == "waiting" || raw == "scanned"))
        }
        let root = PanDirectory(id: "0", name: "根目录", path: "/")
        try check(root.id == "0" && root.path == "/")
    }

    static func panSettingsTransport() async throws {
        let client = try mockClient()
        await client.adoptBrowserToken(SessionToken(value: "pan-settings-token"))
        for method in PanScanMethod.allCases {
            MockURLProtocol.handler = { request in
                try check(request.httpMethod == "POST" && request.url?.path == "/api/pan/cookie/login")
                try check(request.value(forHTTPHeaderField: "Cookie") == "miyabi_token=pan-settings-token")
                let body = try JSONDecoder().decode([String: JSONValue].self, from: requestBody(request))
                try check(body == ["client_type": .string(method.rawValue)])
                return (200, [:], Data(#"{"id":"qr-session","qr_code":"data:image/png;base64,iVBORw0KGgo="}"#.utf8))
            }
            let login = try await client.beginPanLogin(method: method)
            try check(login.id == "qr-session" && login.qrCodeData != nil)
        }
        for state in ["waiting", "scanned", "authorized", "expired", "canceled"] {
            MockURLProtocol.handler = { request in
                try check(request.httpMethod == "GET" && request.url?.path == "/api/pan/cookie/login/qr-session")
                try check(request.value(forHTTPHeaderField: "Cookie") == "miyabi_token=pan-settings-token")
                return (200, [:], try JSONEncoder().encode(["state": state]))
            }
            let result = try await client.panLoginStatus(id: "qr-session")
            try check(result.rawValue == state)
        }
        MockURLProtocol.handler = { request in
            try check(request.url?.absoluteString.contains("id%2Fwith%3Freserved") == true)
            return (200, [:], Data(#"{"state":"waiting"}"#.utf8))
        }
        _ = try await client.panLoginStatus(id: "id/with?reserved")
        for kind in PanDirectoryKind.allCases {
            let endpoint = kind == .download ? "/api/pan/directory" : "/api/pan/organize-directory"
            for id in ["42", "0"] {
                MockURLProtocol.handler = { request in
                    try check(request.httpMethod == "PUT" && request.url?.path == endpoint)
                    try check(request.value(forHTTPHeaderField: "Cookie") == "miyabi_token=pan-settings-token")
                    let body = try JSONDecoder().decode([String: JSONValue].self, from: requestBody(request))
                    try check(body == ["id": .string(id)])
                    return (200, [:], try JSONEncoder().encode(["id": id, "name": "Movies", "path": "/Movies"]))
                }
                let directory = try await client.selectPanDirectory(id: id, kind: kind)
                try check(directory.id == id && directory.path == "/Movies")
            }
            MockURLProtocol.handler = { request in
                try check(request.httpMethod == "DELETE" && request.url?.path == endpoint)
                try check(request.value(forHTTPHeaderField: "Cookie") == "miyabi_token=pan-settings-token")
                return (200, [:], Data("null".utf8))
            }
            try await client.clearPanDirectory(kind: kind)
        }
        MockURLProtocol.handler = { request in
            try check(request.httpMethod == "DELETE" && request.url?.path == "/api/pan/cookie")
            return (200, [:], Data(#"{"connected":false,"last_event_id":0}"#.utf8))
        }
        try await client.logoutPan()
        let appToken = await client.currentToken()
        try check(appToken?.value == "pan-settings-token")
        MockURLProtocol.handler = { _ in (401, [:], Data(#"{"error":"115 Cookie expired"}"#.utf8)) }
        try await expect(.http(401, "115 Cookie expired")) {
            _ = try await client.selectPanDirectory(id: "42", kind: .download)
        }
        let preserved = await client.currentToken()
        try check(preserved?.value == "pan-settings-token")
        MockURLProtocol.handler = { _ in (500, [:], Data(#"{"error":"save failed"}"#.utf8)) }
        try await expect(.http(500, "save failed")) { try await client.clearPanDirectory(kind: .organize) }
        MockURLProtocol.handler = { _ in (401, [:], Data(#"{"code":"AUTH_REQUIRED","error":"login"}"#.utf8)) }
        try await expect(.authenticationRequired) { _ = try await client.panLoginStatus(id: "qr-session") }
        let expired = await client.currentToken()
        try check(expired == nil)
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
