import Foundation
import Observation
import JavStrmCore

@MainActor @Observable
final class AppSession {
    enum Phase { case setup, login, connected }
    enum StreamState: String {
        case connecting = "正在连接"
        case live = "实时同步"
        case retrying = "正在重连"
        case paused = "同步暂停"
    }
    struct Notice: Identifiable {
        let id = UUID()
        let message: String
    }

    var phase: Phase = .setup
    var serverInput = UserDefaults.standard.string(forKey: "serverAddress") ?? ""
    var username = UserDefaults.standard.string(forKey: "username") ?? "admin"
    var isConnecting = false
    var connectionError: String?
    var notice: Notice?
    var client: APIClient?
    var connectionID = UUID()
    var streamState: StreamState = .paused
    var tasks: [ServerTask] = []
    var offlineTasks: [OfflineTask] = []
    var quickJobs: [QuickJob] = []
    var revisions: TaskRevisions?
    var lastSynced: Date?
    var taskError: String?
    var offlineError: String?
    var quickError: String?
    var isForeground = true
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    var activeCount: Int {
        tasks.filter(\.isActive).count + offlineTasks.filter(\.isActive).count
        + quickJobs.filter { $0.status == "running" }.count
    }

    func bootstrap() async {
        guard !serverInput.isEmpty, client == nil else { return }
        await connect()
    }

    func connect() async {
        guard !isConnecting else { return }
        isConnecting = true
        connectionError = nil
        defer { isConnecting = false }
        do {
            let address = try ServerAddress(serverInput)
            stopSync()
            if let old = client { await old.close() }
            connectionID = UUID()
            clearData()
            let api = APIClient(address: address, token: CredentialStore.load(for: address.absoluteString))
            client = api
            let config: AccessConfig = try await api.get("/api/auth/config")
            serverInput = address.absoluteString
            UserDefaults.standard.set(serverInput, forKey: "serverAddress")
            if config.authenticated {
                username = config.username ?? username
                try CredentialStore.save(await api.currentToken(), for: serverInput)
                phase = .connected
                startSync()
            } else {
                try CredentialStore.delete(for: serverInput)
                phase = .login
            }
        } catch {
            connectionError = describe(error)
            phase = .setup
        }
    }

    func login(password: String) async {
        guard !isConnecting, let client else { return }
        isConnecting = true
        connectionError = nil
        defer { isConnecting = false }
        do {
            let result: LoginResult = try await client.send("POST", "/api/auth/login", body: [
                "username": .string(username.trimmingCharacters(in: .whitespacesAndNewlines)),
                "password": .string(password)
            ])
            guard result.success else { throw APIError.authenticationRequired }
            try CredentialStore.save(await client.currentToken(), for: serverInput)
            username = result.username ?? username
            UserDefaults.standard.set(username, forKey: "username")
            connectionID = UUID()
            phase = .connected
            startSync()
        } catch { connectionError = describe(error) }
    }

    func logout() async {
        stopSync()
        if let client {
            do { try await client.discard("POST", "/api/auth/logout") }
            catch { notice = Notice(message: "已退出本机登录。服务端退出请求失败：\(describe(error))") }
            await client.close()
        }
        do { try CredentialStore.delete(for: serverInput) }
        catch { notice = Notice(message: describe(error)) }
        client = nil
        connectionID = UUID()
        clearData()
        connectionError = nil
        phase = .setup
    }

    func changeServer() async {
        stopSync()
        if let client { await client.close() }
        client = nil
        connectionID = UUID()
        clearData()
        connectionError = nil
        phase = .setup
    }

    func adoptBrowserToken(_ token: SessionToken?, connection id: UUID) async {
        guard id == connectionID, phase == .connected, let client else { return }
        await client.adoptBrowserToken(token)
        do {
            let config: AccessConfig = try await client.get("/api/auth/config")
            guard id == connectionID else { return }
            try CredentialStore.save(await client.currentToken(), for: serverInput)
            if !config.authenticated { handle(APIError.authenticationRequired) }
            else { await refreshTasks() }
        } catch {
            guard id == connectionID else { return }
            handle(error)
        }
    }

    func setForeground(_ value: Bool) {
        isForeground = value
        if value { startSync() } else { stopSync() }
    }

    func startSync() {
        guard phase == .connected, isForeground, streamTask == nil, let client else { return }
        let id = connectionID
        streamTask = Task { [weak self] in
            var attempt = 0
            while !Task.isCancelled {
                guard let self, self.connectionID == id, self.phase == .connected else { return }
                self.streamState = attempt == 0 ? .connecting : .retrying
                do {
                    try await client.consumeEvents { [weak self] event in
                        await self?.receive(event, connection: id)
                    }
                } catch {
                    guard !Task.isCancelled, self.connectionID == id else { return }
                    if error as? APIError == .authenticationRequired {
                        self.handle(error)
                        return
                    }
                    self.streamState = .retrying
                    // Reconcile once on interruption; polling continues while SSE reconnects.
                    await self.refreshTasks()
                    attempt += 1
                    do { try await Task.sleep(for: .seconds(min(15, attempt * 3))) }
                    catch { return }
                }
            }
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.connectionID == id, self.phase == .connected else { return }
                await self.refreshTasks()
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }
            }
        }
    }

    func stopSync() {
        streamTask?.cancel()
        pollTask?.cancel()
        streamTask = nil
        pollTask = nil
        streamState = .paused
    }

    func refreshTasks() async {
        guard let client, phase == .connected else { return }
        let id = connectionID
        async let workflows: Void = refreshWorkflows(client, connection: id)
        async let offline: Void = refreshOffline(client, connection: id)
        async let quick: Void = refreshQuick(client, connection: id)
        _ = await (workflows, offline, quick)
    }

    @discardableResult func perform(
        success: String? = nil,
        _ operation: @Sendable (APIClient) async throws -> Void
    ) async -> Bool {
        guard let client, phase == .connected else { return false }
        let id = connectionID
        do {
            try await operation(client)
            guard id == connectionID else { return false }
            if let success { notice = Notice(message: success) }
            await refreshTasks()
            return id == connectionID
        } catch {
            guard id == connectionID else { return false }
            handle(error)
            if error as? APIError != .authenticationRequired { notice = Notice(message: describe(error)) }
            return false
        }
    }

    func handle(_ error: Error) {
        guard error as? APIError == .authenticationRequired else { return }
        stopSync()
        try? CredentialStore.delete(for: serverInput)
        connectionID = UUID()
        clearData()
        phase = .login
        connectionError = describe(error)
    }

    func describe(_ error: Error) -> String {
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet: return "无法连接网络，请检查 Wi-Fi、VPN 以及系统设置中的本地网络权限。"
            case .cannotConnectToHost, .cannotFindHost: return "无法连接服务器，请检查服务地址、端口和网络。"
            case .timedOut: return "连接超时，请检查服务器状态后重试。"
            default: break
            }
        }
        return error.localizedDescription
    }

    private func receive(_ event: ServerEvent, connection id: UUID) {
        guard id == connectionID, phase == .connected, isForeground else { return }
        do {
            switch event.name {
            case "tasks":
                tasks = try WireJSON.decoder().decode([ServerTask]?.self, from: Data(event.data.utf8)) ?? []
                lastSynced = Date()
                taskError = nil
            case "changes":
                revisions = try WireJSON.decoder().decode(TaskRevisions.self, from: Data(event.data.utf8))
            case "ping": break
            default: return
            }
            streamState = .live
        } catch { taskError = describe(APIError.invalidResponse) }
    }

    private func refreshWorkflows(_ api: APIClient, connection id: UUID) async {
        guard streamState != .live else { return }
        do {
            let result = try await api.list("/api/tasks", as: ServerTask.self)
            guard id == connectionID, !Task.isCancelled else { return }
            tasks = result
            lastSynced = Date()
            taskError = nil
        } catch {
            guard id == connectionID, !Task.isCancelled else { return }
            taskError = describe(error)
            handle(error)
        }
    }

    private func refreshOffline(_ api: APIClient, connection id: UUID) async {
        do {
            let result: OfflineActivity = try await api.get("/api/offline/tasks")
            guard id == connectionID, !Task.isCancelled else { return }
            offlineTasks = result.tasks ?? []
            offlineError = nil
        } catch {
            guard id == connectionID, !Task.isCancelled else { return }
            offlineError = describe(error)
            handle(error)
        }
    }

    private func refreshQuick(_ api: APIClient, connection id: UUID) async {
        do {
            let result = try await api.list("/api/quick-strm/jobs", as: QuickJob.self)
            guard id == connectionID, !Task.isCancelled else { return }
            quickJobs = result
            quickError = nil
        } catch {
            guard id == connectionID, !Task.isCancelled else { return }
            quickError = describe(error)
            handle(error)
        }
    }

    private func clearData() {
        tasks = []
        offlineTasks = []
        quickJobs = []
        revisions = nil
        lastSynced = nil
        taskError = nil
        offlineError = nil
        quickError = nil
    }
}
