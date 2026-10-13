import SwiftUI
import JavStrmCore

struct PanSettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var pan: PanStatus?
    @State private var loading = false
    @State private var saving = false
    @State private var error: String?
    @State private var directoryKind: PanDirectoryKind?
    @State private var confirmLogout = false

    var body: some View {
        List {
            Section("115 账户") {
                if let pan, pan.connected {
                    if let account = pan.account {
                        LabeledContent("账户", value: account.name)
                        LabeledContent("等级", value: account.level)
                        if let space = account.space {
                            ProgressView(value: space.total.bytes > 0
                                         ? min(1, Double(space.used.bytes) / Double(space.total.bytes)) : 0)
                            Text("已用 \(space.used.formatted) / \(space.total.formatted)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        ProgressView("已登录，正在读取账号信息")
                    }
                } else {
                    Label("网盘尚未连接", systemImage: "icloud.slash").foregroundStyle(.secondary)
                }
                NavigationLink {
                    PanLoginView { await loadAccount() }
                } label: {
                    Label(pan?.connected == true ? "重新扫码登录" : "扫码登录网盘", systemImage: "qrcode")
                }
                .disabled(loading || saving)
                if pan?.connected == true {
                    Button("退出网盘登录", role: .destructive) { confirmLogout = true }
                        .disabled(loading || saving)
                }
            }
            if pan?.connected == true, pan?.account != nil {
                Section {
                    ForEach(PanDirectoryKind.allCases) { kind in
                        let directory = configuredDirectory(kind)
                        Button { directoryKind = kind } label: {
                            LabeledContent(kind.title) {
                                HStack {
                                    Text(directory?.path ?? directory?.name ?? "未设置")
                                        .foregroundStyle(.secondary).lineLimit(2)
                                    Image(systemName: "chevron.right").font(.caption)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(loading || saving)
                        if directory != nil {
                            Button("清除\(kind.title)", role: .destructive) {
                                Task { await clearDirectory(kind) }
                            }
                            .disabled(loading || saving)
                        }
                    }
                } header: {
                    Text("目录配置")
                } footer: {
                    Text("下载目录接收离线下载文件；整理目录保存整理入库后的影片。进入目标文件夹后选择当前目录，配置会保存到服务器。")
                }
            }
            if loading { ProgressView("正在读取网盘状态") }
            if saving { ProgressView("正在保存") }
            if let error { ErrorPanel(message: error) { Task { await loadAccount() } } }
        }
        .navigationTitle("115 网盘设置")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await loadAccount()
            while pan?.connected == true, pan?.account == nil, error == nil {
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }
                await loadAccount()
            }
        }
        .refreshable { await loadAccount() }
        .navigationDestination(item: $directoryKind) { kind in
            FileBrowserView(
                source: "pan", directory: configuredDirectory(kind)?.id ?? "0",
                selectionTitle: kind.title,
                selectDirectory: { directory in
                    await saveDirectory(directory, kind: kind)
                }
            )
        }
        .confirmationDialog("退出 115 网盘登录？", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出网盘登录", role: .destructive) { Task { await logout() } }
        } message: {
            Text("服务器将退出当前 115 账号，依赖网盘的操作需要重新扫码登录后才能继续。")
        }
    }

    private func configuredDirectory(_ kind: PanDirectoryKind) -> PanDirectory? {
        kind == .download ? pan?.directory : pan?.organizeDirectory
    }

    private func loadAccount() async {
        guard let api = session.client, !loading, !Task.isCancelled else { return }
        let connectionID = session.connectionID
        loading = true
        defer { loading = false }
        do {
            let result: PanStatus = try await api.get("/api/pan/account")
            guard !Task.isCancelled, connectionID == session.connectionID else { return }
            pan = result
            error = nil
        } catch {
            guard !Task.isCancelled, connectionID == session.connectionID else { return }
            if case APIError.http(401, _) = error { pan = nil }
            self.error = session.describe(error)
            session.handle(error)
        }
    }

    private func saveDirectory(_ directory: PanDirectory, kind: PanDirectoryKind) async -> String? {
        let succeeded = await update {
            _ = try await $0.selectPanDirectory(id: directory.id, kind: kind)
        }
        if succeeded {
            directoryKind = nil
            return nil
        }
        return error ?? "目录保存未完成，请重试。"
    }

    private func clearDirectory(_ kind: PanDirectoryKind) async {
        await update { try await $0.clearPanDirectory(kind: kind) }
    }

    private func logout() async {
        await update { try await $0.logoutPan() }
    }

    @discardableResult
    private func update(_ operation: (APIClient) async throws -> Void) async -> Bool {
        guard let api = session.client, !saving, !loading else { return false }
        let connectionID = session.connectionID
        saving = true
        error = nil
        defer { saving = false }
        do {
            try await operation(api)
            guard !Task.isCancelled, connectionID == session.connectionID else { return false }
            await loadAccount()
            await session.refreshTasks()
            return connectionID == session.connectionID
        } catch {
            guard !Task.isCancelled, connectionID == session.connectionID else { return false }
            self.error = session.describe(error)
            session.handle(error)
            return false
        }
    }
}
