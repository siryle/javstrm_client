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
    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                BrandHeader(eyebrow: "Discover & follow", title: "发现",
                            subtitle: submittedSearch.isEmpty ? "浏览新作，关注你喜欢的作品。" : "搜索「\(submittedSearch)」")
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
                if loading && movies.isEmpty {
                    ProgressView("正在请求数据源").frame(maxWidth: .infinity).padding(40)
                } else if movies.isEmpty && error == nil {
                    ContentUnavailableView("没有找到作品", systemImage: "magnifyingglass",
                                           description: Text("尝试其他关键词，或检查服务端数据源和代理配置。"))
                } else {
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(movies) { movie in
                            NavigationLink {
                                MovieDetailView(movieID: movie.id, initialMovie: movie)
                            } label: {
                                MovieCard(code: movie.code, title: movie.title, artwork: movie.artwork,
                                          rating: movie.rating, artworkLayout: .landscape)
                            }
                            .buttonStyle(.plain)
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
        if reset { movies = []; page = 0; hasMore = false }
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
            guard !Task.isCancelled, requestID == request else { return }
            let existing = Set(movies.map(\.id))
            movies += result.filter { !existing.contains($0.id) }
            page = nextPage
            hasMore = result.count == 20
        } catch {
            guard !Task.isCancelled, requestID == request else { return }
            self.error = session.describe(error)
            session.handle(error)
        }
    }
}
