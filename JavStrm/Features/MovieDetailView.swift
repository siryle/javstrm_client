import SwiftUI
import JavStrmCore

struct MovieDetailView: View {
    @Environment(AppSession.self) private var session
    let movieID: String
    var initialMovie: DiscoverMovie?
    @State private var movie: DiscoverMovie?
    @State private var subscription: Subscription?
    @State private var subscriptionReady = false
    @State private var autoDownload = true
    @State private var error: String?
    @State private var subscriptionError: String?
    @State private var loading = false
    @State private var busy = false
    @State private var showMagnets = false
    @State private var confirmRemove = false
    @State private var followedActors = Set<String>()

    private var displayed: DiscoverMovie? { movie ?? initialMovie }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let movie = displayed {
                    PosterView(source: movie.artwork, code: movie.code, layout: .landscape)
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(movie.code).font(.system(.title, design: .monospaced).weight(.bold))
                        Text(movie.title).font(.title3.weight(.semibold)).textSelection(.enabled)
                        HStack {
                            if let state = movie.state, state != "not_in_library" { StatusPill(value: state) }
                            if movie.hasSubtitle == true {
                                Label("中文字幕", systemImage: "captions.bubble").font(.caption)
                            }
                        }
                    }
                    if let error { ErrorPanel(message: error) { Task { await load() } } }
                    VStack(alignment: .leading, spacing: 16) {
                        if let subscriptionError {
                            ErrorPanel(message: subscriptionError) { Task { await loadSubscription() } }
                        }
                        if let subscription {
                            HStack {
                                Label("已订阅", systemImage: "bookmark.fill")
                                Spacer()
                                StatusPill(value: subscription.status)
                            }
                            Button("取消作品订阅", role: .destructive) { confirmRemove = true }
                                .disabled(busy)
                        } else {
                            Toggle("发现资源后自动下载", isOn: $autoDownload)
                                .font(.subheadline)
                            Button {
                                subscribeMovie()
                            } label: {
                                Label("订阅作品", systemImage: "bookmark")
                                    .frame(maxWidth: .infinity).padding(6)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(busy || !subscriptionReady)
                        }
                        Button {
                            showMagnets = true
                        } label: {
                            Label("查看磁力资源", systemImage: "link")
                                .frame(maxWidth: .infinity).padding(6)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(18)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 18))
                    HStack(spacing: 12) {
                        MetricView(value: movie.rating > 0 ? movie.rating.formatted(.number.precision(.fractionLength(1))) : "—",
                                   label: "评分")
                        MetricView(value: movie.duration > 0 ? "\(movie.duration)" : "—", label: "分钟")
                    }
                    metadata("发行日期", movie.releaseDate ?? "未知")
                    metadata("制作商", movie.maker?.name ?? "未知")
                    metadata("系列", movie.series?.name ?? "暂无")
                    metadata("导演", movie.director?.name ?? "暂无")
                    if let actors = movie.actors, !actors.isEmpty {
                        Text("演员").font(.headline)
                        ForEach(actors) { actor in
                            HStack {
                                Text(actor.displayName).font(.subheadline)
                                Spacer()
                                Button(followedActors.contains(actor.id) ? "已订阅" : "订阅演员") {
                                    subscribeActor(actor)
                                }
                                .buttonStyle(.bordered)
                                .font(.caption)
                                .disabled(busy || followedActors.contains(actor.id))
                            }
                        }
                    }
                    if let tags = movie.tags, !tags.isEmpty {
                        Text("标签").font(.headline)
                        Text(tags.map(\.displayName).joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else if loading {
                    ProgressView("正在读取作品资料").frame(maxWidth: .infinity).padding(60)
                } else if let error {
                    ErrorPanel(message: error) { Task { await load() } }
                }
            }
            .padding(24)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.canvas)
        .navigationTitle(displayed?.code ?? "作品资料")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            async let detail: Void = load()
            async let subscription: Void = loadSubscription()
            _ = await (detail, subscription)
        }
        .refreshable {
            async let detail: Void = load()
            async let subscription: Void = loadSubscription()
            _ = await (detail, subscription)
        }
        .sheet(isPresented: $showMagnets) {
            NavigationStack { MagnetsView(movieID: movieID, code: displayed?.code ?? "") }
        }
        .confirmationDialog("取消此作品的订阅？", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("取消订阅", role: .destructive) { removeSubscription() }
        }
    }

    private func metadata(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            Text(value).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.subheadline)
    }

    private func load() async {
        guard let api = session.client else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let result: DiscoverMovie = try await api.get("/api/discover/movies/\(ServerAddress.segment(movieID))")
            guard !Task.isCancelled else { return }
            movie = result
        } catch {
            guard !Task.isCancelled else { return }
            self.error = session.describe(error)
            session.handle(error)
        }
    }

    private func loadSubscription() async {
        guard let api = session.client else { return }
        subscriptionReady = false
        subscriptionError = nil
        do {
            let result = try await api.findSubscription(kind: "movie", targetID: movieID)
            guard !Task.isCancelled else { return }
            subscription = result
            subscriptionReady = true
        } catch {
            guard !Task.isCancelled else { return }
            subscriptionError = session.describe(error)
            session.handle(error)
        }
    }

    private func subscribeMovie() {
        let id = movieID
        let auto = autoDownload
        busy = true
        Task {
            defer { busy = false }
            guard let api = session.client else { return }
            let connection = session.connectionID
            do {
                let item = try await api.subscribeMovie(targetID: id, autoDownload: auto)
                guard connection == session.connectionID, !Task.isCancelled else { return }
                subscription = item
                subscriptionReady = true
                subscriptionError = nil
                var message = "作品已订阅。"
                if auto {
                    let checked = try await api.checkSubscription(id: item.id)
                    guard connection == session.connectionID, !Task.isCancelled else { return }
                    switch checked {
                    case .updated(let updated):
                        subscription = updated
                        message = updated.status == "added" ? "已加入离线下载。" : "已订阅，后续会自动检查资源。"
                    case .imported:
                        subscription = nil
                        message = "作品已入库。"
                        await load()
                    }
                }
                guard connection == session.connectionID, !Task.isCancelled else { return }
                session.notice = .init(message: message)
                await session.refreshTasks()
            } catch {
                guard connection == session.connectionID, !Task.isCancelled else { return }
                session.handle(error)
                subscriptionError = subscription == nil ? session.describe(error)
                    : "作品已订阅，立即检查失败：\(session.describe(error))"
            }
        }
    }

    private func removeSubscription() {
        guard let subscription else { return }
        let id = subscription.id
        busy = true
        Task {
            await session.perform(success: "已取消订阅。") { api in
                try await api.discard("DELETE", "/api/subscriptions/\(id)")
            }
            await loadSubscription()
            busy = false
        }
    }

    private func subscribeActor(_ actor: DiscoverActor) {
        busy = true
        Task {
            defer { busy = false }
            let success = await session.perform(success: "已订阅演员 \(actor.displayName)。") { api in
                let _: Subscription = try await api.send("POST", "/api/subscriptions", body: [
                    "kind": .string("actor"), "target_id": .string(actor.id),
                    "title": .string(actor.displayName), "auto_download": .bool(false)
                ])
            }
            if success { followedActors.insert(actor.id) }
        }
    }
}

private struct MagnetsView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let movieID: String
    let code: String
    @State private var magnets: [Magnet] = []
    @State private var loading = false
    @State private var busy = false
    @State private var error: String?
    @State private var pendingMagnet: Magnet?
    @State private var confirmDownload = false

    var body: some View {
        List {
            Section {
                Text("提交后，资源将由服务端下载到当前 115 下载目录。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if loading { ProgressView("正在获取资源") }
            if let error { ErrorPanel(message: error) { Task { await load() } }.listRowSeparator(.hidden) }
            if !loading && magnets.isEmpty && error == nil {
                ContentUnavailableView("暂无磁力资源", systemImage: "link",
                                       description: Text("可订阅此作品，稍后由服务端继续检查。"))
            }
            ForEach(magnets) { magnet in
                VStack(alignment: .leading, spacing: 12) {
                    Text(magnet.name).font(.subheadline.weight(.medium)).textSelection(.enabled)
                    HStack {
                        Text(byteSize(magnet.size))
                        Text("\(magnet.filesCount) 个文件")
                        if magnet.hasSubtitle { Text("中字").foregroundStyle(Palette.accent) }
                        if magnet.hd { Text("HD") }
                    }.font(.caption).foregroundStyle(.secondary)
                    HStack {
                        ShareLink(item: magnet.uri) { Label("分享", systemImage: "square.and.arrow.up") }
                        Spacer()
                        Button("提交 115") {
                            pendingMagnet = magnet
                            confirmDownload = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy)
                    }
                }.padding(.vertical, 8)
            }
        }
        .navigationTitle("\(code) 资源")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog("提交到 115 离线下载？", isPresented: $confirmDownload, titleVisibility: .visible) {
            Button("提交下载") { submit() }
        } message: {
            Text(pendingMagnet?.name ?? "")
        }
    }

    private func load() async {
        guard let api = session.client else { return }
        loading = true
        error = nil
        defer { loading = false }
        do { magnets = try await api.list("/api/discover/movies/\(ServerAddress.segment(movieID))/magnets", as: Magnet.self) }
        catch {
            guard !Task.isCancelled else { return }
            self.error = session.describe(error)
            session.handle(error)
        }
    }

    private func submit() {
        guard let magnet = pendingMagnet else { return }
        let id = movieID
        let hash = magnet.hash
        busy = true
        Task {
            await session.perform(success: "资源已提交，请在任务页查看状态。") { api in
                let _: OfflineTask = try await api.send(
                    "POST", "/api/discover/movies/\(ServerAddress.segment(id))/offline",
                    body: ["hash": .string(hash)]
                )
            }
            busy = false
        }
    }
}
