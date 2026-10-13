import SwiftUI
import JavStrmCore

struct SubscriptionsView: View {
    @Environment(AppSession.self) private var session
    @State private var kind = "movie"
    @State private var subscriptions: [Subscription] = []
    @State private var page = 0
    @State private var hasMore = false
    @State private var loading = false
    @State private var busy = false
    @State private var error: String?
    @State private var requestID = UUID()
    @State private var removal: Subscription?
    @State private var confirmRemoval = false
    @State private var enqueue: Subscription?
    @State private var confirmEnqueue = false

    var body: some View {
        List {
            Section {
                BrandHeader(eyebrow: "Stay in the loop", title: "订阅", subtitle: "让服务端替你持续追踪。")
                    .listRowBackground(Color.clear)
                Picker("订阅类型", selection: $kind) {
                    Text("作品").tag("movie")
                    Text("演员").tag("actor")
                }
                .pickerStyle(.segmented)
            }.listRowSeparator(.hidden)
            if let error { Section { ErrorPanel(message: error) { Task { await load(reset: true) } } } }
            if loading && subscriptions.isEmpty { ProgressView("正在读取订阅") }
            if subscriptions.isEmpty && !loading && error == nil {
                ContentUnavailableView("还没有订阅", systemImage: "bookmark",
                                       description: Text("在发现页打开作品详情，订阅作品或演员。"))
            }
            ForEach(subscriptions) { item in
                Section {
                    NavigationLink {
                        if item.kind == "actor" {
                            ActorFeedView(subscription: item)
                        } else {
                            MovieDetailView(movieID: item.targetId)
                        }
                    } label: {
                        SubscriptionRow(item: item)
                    }
                    HStack {
                        if item.kind == "actor" {
                            Button(item.status == "paused" ? "恢复追踪" : "暂停追踪") { toggleActor(item) }
                        } else {
                            Button("检查并入库") { enqueue = item; confirmEnqueue = true }
                        }
                        Spacer()
                        Button(item.autoDownload ? "关闭自动下载" : "开启自动下载") { toggleDownload(item) }
                            .font(.caption)
                    }
                    .disabled(busy)
                }
                .swipeActions {
                    Button("取消订阅", role: .destructive) { removal = item; confirmRemoval = true }
                }
            }
            if hasMore {
                LoadMoreButton(isLoading: loading) { Task { await load(reset: false) } }
            }
            if !subscriptions.isEmpty {
                Text("已加载 \(subscriptions.count) 条订阅").font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("订阅")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: kind) { await load(reset: true) }
        .onChange(of: session.revisions?.monitor) { old, new in
            if old != nil, old != new { Task { await load(reset: true) } }
        }
        .refreshable { await load(reset: true) }
        .confirmationDialog("取消订阅？", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("取消订阅", role: .destructive) { remove() }
        } message: { Text(removal?.title ?? "") }
        .confirmationDialog("检查资源并提交入库？", isPresented: $confirmEnqueue, titleVisibility: .visible) {
            Button("检查并入库") { enqueueItem() }
        } message: { Text("发现符合服务端偏好的资源后，将提交 115 离线下载。") }
    }

    private func load(reset: Bool) async {
        guard let api = session.client, reset || !loading else { return }
        let request = UUID()
        requestID = request
        loading = true
        error = nil
        if reset { subscriptions = []; page = 0; hasMore = false }
        let nextPage = reset ? 1 : page + 1
        defer { if requestID == request { loading = false } }
        do {
            let result = try await api.list("/api/subscriptions", query: [
                URLQueryItem(name: "kind", value: kind), URLQueryItem(name: "page", value: String(nextPage)),
                URLQueryItem(name: "limit", value: "50")
            ], as: Subscription.self)
            guard !Task.isCancelled, requestID == request else { return }
            let existing = Set(subscriptions.map(\.id))
            subscriptions += result.filter { !existing.contains($0.id) }
            page = nextPage
            hasMore = result.count == 50
        } catch {
            guard !Task.isCancelled, requestID == request else { return }
            self.error = session.describe(error)
            session.handle(error)
        }
    }

    private func remove() {
        guard let id = removal?.id else { return }
        busy = true
        Task {
            await session.perform(success: "已取消订阅。") { api in
                try await api.discard("DELETE", "/api/subscriptions/\(id)")
            }
            await load(reset: true)
            busy = false
        }
    }

    private func toggleDownload(_ item: Subscription) {
        update(item, body: ["auto_download": .bool(!item.autoDownload)])
    }

    private func toggleActor(_ item: Subscription) {
        update(item, body: ["status": .string(item.status == "paused" ? "active" : "paused")])
    }

    private func update(_ item: Subscription, body: [String: JSONValue]) {
        let id = item.id
        busy = true
        Task {
            await session.perform { api in
                let _: Subscription = try await api.send("PATCH", "/api/subscriptions/\(id)", body: body)
            }
            await load(reset: true)
            busy = false
        }
    }

    private func enqueueItem() {
        guard let id = enqueue?.id else { return }
        busy = true
        Task {
            await session.perform(success: "已请求检查资源，结果可在订阅和任务页查看。") { api in
                let _: Subscription = try await api.send("POST", "/api/subscriptions/\(id)/enqueue")
            }
            await load(reset: true)
            busy = false
        }
    }
}

private struct SubscriptionRow: View {
    let item: Subscription

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PosterView(source: item.cover, code: item.kind == "actor" ? "ACTOR" : item.code)
                .frame(width: 64)
            VStack(alignment: .leading, spacing: 8) {
                if !item.code.isEmpty { Text(item.code).font(.system(.subheadline, design: .monospaced).weight(.bold)) }
                Text(item.title).font(.subheadline).lineLimit(2)
                HStack {
                    StatusPill(value: item.status)
                    if item.autoDownload { Image(systemName: "arrow.down.circle.fill").foregroundStyle(Palette.accent) }
                }
                if let error = item.error, !error.isEmpty {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct ActorFeedView: View {
    @Environment(AppSession.self) private var session
    let subscription: Subscription
    @State private var items: [Subscription] = []
    @State private var error: String?
    @State private var loading = false
    @State private var page = 0
    @State private var hasMore = false

    var body: some View {
        List {
            if let error { ErrorPanel(message: error) { Task { await load(reset: true) } } }
            if loading && items.isEmpty { ProgressView() }
            if items.isEmpty && !loading && error == nil {
                ContentUnavailableView("暂时没有新作", systemImage: "person.crop.rectangle",
                                       description: Text("服务端将定期检查演员更新。"))
            }
            ForEach(items) { item in
                NavigationLink { MovieDetailView(movieID: item.targetId) } label: { SubscriptionRow(item: item) }
            }
            if hasMore { LoadMoreButton(isLoading: loading) { Task { await load(reset: false) } } }
        }
        .navigationTitle(subscription.title)
        .task { await load(reset: true) }
        .refreshable { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        guard let api = session.client, !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        let next = reset ? 1 : page + 1
        do {
            let result = try await api.list("/api/subscriptions/actors/\(subscription.id)/feed", query: [
                URLQueryItem(name: "page", value: String(next)), URLQueryItem(name: "limit", value: "50")
            ], as: Subscription.self)
            guard !Task.isCancelled else { return }
            if reset { items = [] }
            let existing = Set(items.map(\.id))
            items += result.filter { !existing.contains($0.id) }
            page = next
            hasMore = result.count == 50
        } catch {
            guard !Task.isCancelled else { return }
            self.error = session.describe(error)
            session.handle(error)
        }
    }
}
