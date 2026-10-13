import SwiftUI
import JavStrmCore

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @AppStorage("hideArtwork") private var hideArtwork = true
    @AppStorage("hideInBackground") private var hideInBackground = true
    @State private var pan: PanStatus?
    @State private var panError: String?
    @State private var portal: WebDestination?
    @State private var confirmLogout = false

    var body: some View {
        List {
            Section {
                BrandHeader(eyebrow: "Make it yours", title: "设置", subtitle: "连接你的服务，设定你的习惯。")
                    .listRowBackground(Color.clear)
            }.listRowSeparator(.hidden)
            Section("服务器") {
                LabeledContent("当前地址") {
                    Text(session.serverInput).font(.caption).textSelection(.enabled)
                }
                LabeledContent("账户", value: session.username)
                LabeledContent("同步", value: session.streamState.rawValue)
                Button("更换服务器") { Task { await session.changeServer() } }
            }
            Section("隐私") {
                Toggle("隐藏封面", isOn: $hideArtwork)
                Toggle("进入后台时隐藏内容", isOn: $hideInBackground)
                Text("隐藏封面时不请求图片；后台遮罩会隐藏应用切换器中的内容。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("115 网盘") {
                if let pan, pan.connected, let account = pan.account {
                    LabeledContent("账户", value: account.name)
                    LabeledContent("等级", value: account.level)
                    if let space = account.space {
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: space.total.bytes > 0
                                         ? min(1, Double(space.used.bytes) / Double(space.total.bytes)) : 0)
                            Text("已用 \(space.used.formatted) / \(space.total.formatted)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("下载目录", value: pan.directory?.name ?? "未设置")
                    LabeledContent("整理目录", value: pan.organizeDirectory?.name ?? "未设置")
                    NavigationLink {
                        FileBrowserView(source: "pan", directory: "0")
                    } label: { Label("浏览网盘文件", systemImage: "externaldrive") }
                } else {
                    Label("网盘尚未连接", systemImage: "icloud.slash").foregroundStyle(.secondary)
                }
                if let panError { Text(panError).font(.caption).foregroundStyle(.red) }
                Button("登录网盘与配置目录") {
                    portal = .init(title: "115 网盘设置", path: "/settings", query: [.init(name: "tab", value: "pan")])
                }
            }
            Section("管理") {
                NavigationLink { FileBrowserView(source: "local", directory: "/") } label: {
                    Label("浏览服务端本地文件", systemImage: "folder")
                }
                NavigationLink { LogsView() } label: { Label("系统日志", systemImage: "text.alignleft") }
                Button { portal = .init(title: "服务端工具", path: "/tools") } label: {
                    Label("STRM 与 Emby 工具", systemImage: "wrench.and.screwdriver")
                }
                Button { portal = .init(title: "高级设置", path: "/settings") } label: {
                    Label("服务端完整设置", systemImage: "slider.horizontal.3")
                }
                Button { portal = .init(title: "文件管理", path: "/files") } label: {
                    Label("文件复制、移动与管理", systemImage: "doc.on.doc")
                }
            }
            Section("关于") {
                LabeledContent("应用", value: "JavStrm")
                LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                Text("原生 iOS 客户端 · iPhone / iPad\n高级配置使用服务端管理页面。")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("退出登录", role: .destructive) { confirmLogout = true }
            }
        }
        .navigationTitle("设置")
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadPan() }
        .refreshable { await loadPan() }
        .sheet(item: $portal, onDismiss: { Task { await loadPan() } }) { WebPortalView(destination: $0) }
        .confirmationDialog("退出 JavStrm 登录？", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) { Task { await session.logout() } }
        } message: { Text("本机会移除保存的会话。服务端正在运行的任务会继续执行。") }
    }

    private func loadPan() async {
        guard let api = session.client else { return }
        panError = nil
        do { pan = try await api.get("/api/pan/account") }
        catch {
            guard !Task.isCancelled else { return }
            panError = session.describe(error)
            session.handle(error)
        }
    }
}
