import SwiftUI
import JavStrmCore

struct DiscoverView: View {
    @Environment(AppSession.self) private var session
    @State private var search = ""
    @State private var submittedSearch = ""
    @State private var zone = "censored"
    @State private var sort = "hit"
    @State private var movies: [DiscoverMovie] = []
    @State private var page = 0
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?
    @State private var requestID = UUID()
    @State private var subscriptions: [String: Subscription] = [:]
    @State private var movieStates: [String: DiscoverMovieState] = [:]
    @State private var actionsReady = false
    @State private var actionError: String?
    @State private var actionRequestID = UUID()
    @State private var subscribing = Set<String>()
    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Menu {
                        Picker("分类", selection: $zone) {
                            Text("有码").tag("censored")
                            Text("无码").tag("uncensored")
                            Text("欧美").tag("western")
                            Text("FC2").tag("fc2")
                            Text("动画").tag("anime")
                        }
                    } label: { Label(zoneName, systemImage: "line.3.horizontal.decrease.circle") }
                    .buttonStyle(.bordered)
                    Spacer()
                    Picker("排序", selection: $sort) {
                        Text("热门").tag("hit")
                        Text("最新").tag("release")
                        Text("高分").tag("score")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 230)
                }
                .disabled(!submittedSearch.isEmpty)
                if let error { ErrorPanel(message: error) { Task { await load(reset: true) } } }
                if let actionError {
                    ErrorPanel(message: actionError) { Task { await refreshActions() } }
                }
                if loading && movies.isEmpty {
                    ProgressView("正在请求数据源").frame(maxWidth: .infinity).padding(40)
                } else if movies.isEmpty && error == nil {
                    ContentUnavailableView("没有找到作品", systemImage: "magnifyingglass",
                                           description: Text("尝试其他关键词，或检查服务端数据源和代理配置。"))
                } else {
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(movies) { movie in
                            ZStack(alignment: .topTrailing) {
                                NavigationLink {
                                    MovieDetailView(movieID: movie.id, initialMovie: movie)
                                        .onDisappear { Task { await refreshActions() } }
                                } label: {
                                    MovieCard(code: movie.code, title: movie.title, artwork: movie.artwork,
                                              rating: movie.rating, artworkLayout: .landscape)
                                }
                                .buttonStyle(.plain)
                                if let action = movie.cardAction(
                                    subscriptionStatus: subscriptions[movie.id]?.status,
                                    currentState: movieStates[movie.id]?.state
                                ) {
                                    DiscoverCardButton(action: action, isLoading: subscribing.contains(movie.id),
                                                       isReady: actionsReady) {
                                        subscribe(movie)
                                    }
                                    .padding(8)
                                }
                            }
                        }
                    }
                }
                if hasMore {
                    LoadMoreButton(isLoading: loading) { Task { await load(reset: false) } }
                }
            }
            .padding(20)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.canvas)
        .navigationTitle("发现")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "搜索番号、作品或演员")
        .onSubmit(of: .search) { submittedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines) }
        .onChange(of: search) { _, value in if value.isEmpty { submittedSearch = "" } }
        .task(id: "\(zone)|\(sort)|\(submittedSearch)") { await load(reset: true) }
        .onChange(of: session.revisions) { _, _ in
            Task { await refreshActions() }
        }
        .refreshable { await load(reset: true) }
    }

    private var zoneName: String {
        ["censored": "有码", "uncensored": "无码", "western": "欧美", "fc2": "FC2", "anime": "动画"][zone] ?? "分类"
    }

    private func load(reset: Bool) async {
        guard let api = session.client, reset || !loading else { return }
        let request = UUID()
        requestID = request
        loading = true
        error = nil
        if reset {
            movies = []
            page = 0
            hasMore = false
            actionsReady = false
            actionError = nil
            movieStates = [:]
            actionRequestID = UUID()
        }
        let connection = session.connectionID
        let nextPage = reset ? 1 : page + 1
        var query = [URLQueryItem(name: "page", value: String(nextPage)), URLQueryItem(name: "limit", value: "20")]
        let path: String
        if submittedSearch.isEmpty {
            path = "/api/discover/movies"
            query += [URLQueryItem(name: "zone", value: zone), URLQueryItem(name: "sort", value: sort)]
        } else {
            path = "/api/discover/search"
            query.append(URLQueryItem(name: "q", value: submittedSearch))
        }
        defer { if requestID == request { loading = false } }
        do {
            let result = try await api.list(path, query: query, as: DiscoverMovie.self)
            guard !Task.isCancelled, requestID == request, connection == session.connectionID else { return }
            let existing = Set(movies.map(\.id))
            movies += result.filter { !existing.contains($0.id) }
            page = nextPage
            hasMore = result.count == 20
            await refreshActions()
        } catch {
            guard !Task.isCancelled, requestID == request, connection == session.connectionID else { return }
            self.error = session.describe(error)
            session.handle(error)
        }
    }

    private func refreshActions() async {
        guard let api = session.client, !movies.isEmpty else { return }
        let request = UUID()
        actionRequestID = request
        let connection = session.connectionID
        let currentMovies = movies
        actionsReady = false
        actionError = nil
        do {
            async let subscriptions = api.subscriptions(kind: "movie")
            async let states = api.movieStates(currentMovies)
            let (items, currentStates) = try await (subscriptions, states)
            guard !Task.isCancelled, actionRequestID == request, connection == session.connectionID else { return }
            self.subscriptions = items.reduce(into: [:]) { $0[$1.targetId] = $1 }
            movieStates = currentStates.reduce(into: [:]) { $0[$1.id] = $1 }
            actionsReady = true
        } catch {
            guard !Task.isCancelled, actionRequestID == request, connection == session.connectionID else { return }
            actionError = "无法读取作品订阅和入库状态：\(session.describe(error))"
            session.handle(error)
        }
    }

    private func subscribe(_ movie: DiscoverMovie) {
        guard actionsReady, !subscribing.contains(movie.id),
              movie.cardAction(subscriptionStatus: subscriptions[movie.id]?.status,
                               currentState: movieStates[movie.id]?.state) == .subscribe else { return }
        subscribing.insert(movie.id)
        Task {
            defer { subscribing.remove(movie.id) }
            let success = await session.perform(success: "作品已订阅，符合偏好的资源出现后会自动下载。") { api in
                let _ = try await api.subscribeMovie(targetID: movie.id)
            }
            if success { await refreshActions() }
        }
    }
}

private struct DiscoverCardButton: View {
    let action: DiscoverMovieCardAction
    let isLoading: Bool
    let isReady: Bool
    let subscribe: () -> Void

    private var title: String {
        switch action {
        case .subscribe: "订阅"
        case .subscribed: "已订阅"
        case .inLibrary: "已入库"
        case .addedOffline: "已加入离线"
        }
    }

    private var symbol: String {
        switch action {
        case .subscribe: "bell.badge"
        case .subscribed: "bell.fill"
        case .inLibrary: "checkmark.seal.fill"
        case .addedOffline: "arrow.down.circle.fill"
        }
    }

    var body: some View {
        Button(action: subscribe) {
            HStack(spacing: 5) {
                if isLoading { ProgressView().tint(.white) }
                else { Image(systemName: symbol) }
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(minHeight: 36)
            .background(action == .subscribe ? Palette.ink.opacity(0.85) : Palette.accent,
                        in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(action != .subscribe || isLoading || !isReady)
        .accessibilityLabel(title)
        .accessibilityHint(action == .subscribe ? "订阅此作品，发现符合偏好的资源后自动下载" : "")
    }
}
