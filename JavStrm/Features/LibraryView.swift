import SwiftUI
import JavStrmCore

struct LibraryView: View {
    @Environment(AppSession.self) private var session
    @AppStorage("hideArtwork") private var hideArtwork = true
    @State private var movies: [LibraryMovie] = []
    @State private var tabs: [LibraryTab] = []
    @State private var selectedTab = ""
    @State private var recentOnly = false
    @State private var search = ""
    @State private var page = 0
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?
    @State private var requestID = UUID()
    @State private var confirmScan = false
    @State private var scanning = false
    @State private var croppingMovie: LibraryMovie?
    private let columns = [GridItem(.adaptive(minimum: 145, maximum: 220), spacing: 16)]

    private var filtered: [LibraryMovie] {
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return movies }
        return movies.filter {
            $0.code.localizedCaseInsensitiveContains(text) || $0.title.localizedCaseInsensitiveContains(text)
            || ($0.actors ?? []).contains { $0.name.localizedCaseInsensitiveContains(text) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Menu {
                        Button("全部目录") { selectedTab = "" }
                        ForEach(tabs) { tab in Button(tab.name) { selectedTab = tab.id } }
                    } label: {
                        Label(tabs.first { $0.id == selectedTab }?.name ?? "全部目录", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Picker("范围", selection: $recentOnly) {
                        Text("全部").tag(false)
                        Text("新入库").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 180)
                }
                if !search.isEmpty {
                    Text("筛选已加载的 \(movies.count) 部作品；可继续加载更多。")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error { ErrorPanel(message: error) { Task { await load(reset: true) } } }
                if loading && movies.isEmpty {
                    ProgressView("正在读取媒体库").padding(40)
                } else if filtered.isEmpty && error == nil {
                    ContentUnavailableView(search.isEmpty ? "媒体库还没有作品" : "没有匹配作品",
                                           systemImage: "square.stack",
                                           description: Text(search.isEmpty ? "在服务端配置媒体目录后扫描入库。" : "尝试其他关键词，或继续加载媒体库。"))
                } else {
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(filtered) { movie in
                            NavigationLink {
                                LibraryDetailView(movie: movie)
                                    .toolbar {
                                        ToolbarItem(placement: .topBarTrailing) {
                                            cropButton(for: movie)
                                        }
                                    }
                            } label: {
                                MovieCard(code: movie.code, title: movie.title, artwork: movie.artwork,
                                          rating: movie.rating, artworkLayout: .portrait, showsRating: false)
                            }
                            .buttonStyle(.plain)
                            .overlay(alignment: .top) {
                                VStack {
                                    Spacer(minLength: 0)
                                    HStack {
                                        Spacer(minLength: 0)
                                        cropButton(for: movie)
                                            .labelStyle(.iconOnly)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.white)
                                            .frame(width: 36, height: 36)
                                            .background(.black.opacity(0.6), in: Capsule())
                                            .buttonStyle(.plain)
                                            .padding(8)
                                    }
                                }
                                .aspectRatio(ArtworkLayout.portrait.aspectRatio, contentMode: .fit)
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
        .navigationTitle("媒体库")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "筛选已加载的番号、标题或演员")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    hideArtwork.toggle()
                } label: {
                    Image(systemName: hideArtwork ? "eye.slash" : "eye")
                }
                .accessibilityLabel(hideArtwork ? "显示封面" : "隐藏封面")
                Button { confirmScan = true } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                    .disabled(scanning)
                    .accessibilityLabel("扫描媒体库")
            }
        }
        .confirmationDialog("扫描媒体库", isPresented: $confirmScan, titleVisibility: .visible) {
            Button("开始扫描") {
                let tab = selectedTab
                scanning = true
                Task {
                    await session.perform(success: "扫描任务已创建，可在任务页查看进度。") { api in
                        let query = tab.isEmpty ? [] : [URLQueryItem(name: "tab", value: tab)]
                        let _: ServerTask = try await api.send("POST", "/api/library/scan", query: query)
                    }
                    scanning = false
                }
            }
        } message: {
            Text("扫描所选目录并更新媒体元数据，可能需要一些时间。")
        }
        .task {
            guard let api = session.client else { return }
            do { tabs = try await api.list("/api/library/tabs", as: LibraryTab.self) }
            catch { session.handle(error) }
        }
        .task(id: "\(selectedTab)|\(recentOnly)") { await load(reset: true) }
        .onChange(of: session.revisions?.library) { old, new in
            if old != nil, old != new {
                Task { await load(reset: true, preservingLoadedPages: true) }
            }
        }
        .refreshable { await load(reset: true) }
        .sheet(item: $croppingMovie) { movie in
            NavigationStack {
                PosterCropView(movie: movie) {
                    await load(reset: true, preservingLoadedPages: true)
                }
            }
        }
    }

    private func cropButton(for movie: LibraryMovie) -> some View {
        Button {
            croppingMovie = movie
        } label: {
            Label("裁切封面", systemImage: "crop")
        }
        .disabled(hideArtwork || movie.cropArtwork.isEmpty)
        .accessibilityLabel("裁切 \(movie.code) 封面")
    }

    private func load(reset: Bool, preservingLoadedPages: Bool = false) async {
        guard let api = session.client, reset || !loading else { return }
        let request = UUID()
        requestID = request
        loading = true
        error = nil
        let lastPage = reset && preservingLoadedPages ? max(1, page) : 1
        if reset && !preservingLoadedPages { movies = []; page = 0; hasMore = false }
        let nextPage = reset ? 1 : page + 1
        let connection = session.connectionID
        let tab = selectedTab
        let recent = recentOnly
        defer { if requestID == request { loading = false } }
        do {
            var refreshed: [LibraryMovie] = []
            var result: LibraryPage?
            for currentPage in nextPage...max(nextPage, lastPage) {
                var query = [
                    URLQueryItem(name: "page", value: String(currentPage)),
                    URLQueryItem(name: "limit", value: "30")
                ]
                if recent { query.append(URLQueryItem(name: "view", value: "new")) }
                if !tab.isEmpty { query.append(URLQueryItem(name: "tab", value: tab)) }
                let current: LibraryPage = try await api.get("/api/library/movies", query: query)
                guard !Task.isCancelled, requestID == request, connection == session.connectionID else { return }
                refreshed += current.movies ?? []
                result = current
                if !current.hasMore { break }
            }
            guard let result else { return }
            if reset { movies = [] }
            let existing = Set(movies.map(\.id))
            movies += refreshed.filter { !existing.contains($0.id) }
            page = result.page
            hasMore = result.hasMore
        } catch {
            guard !Task.isCancelled, requestID == request, connection == session.connectionID else { return }
            self.error = session.describe(error)
            session.handle(error)
        }
    }
}

private struct LibraryDetailView: View {
    let movie: LibraryMovie
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PosterView(source: movie.landscapeArtwork, code: movie.code, layout: .landscape)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                Text(movie.code).font(.system(.title, design: .monospaced).weight(.bold))
                Text(movie.title.isEmpty ? "等待元数据" : movie.title).font(.title3.weight(.semibold))
                HStack {
                    StatusPill(value: "in_library")
                    if movie.watched { Label("已观看", systemImage: "checkmark.circle").font(.caption) }
                }
                metadata("发行日期", movie.releaseDate ?? "未知")
                metadata("时长", movie.duration > 0 ? "\(movie.duration) 分钟" : "未知")
                metadata("评分", movie.rating > 0 ? movie.rating.formatted() : "暂无")
                metadata("制作商", movie.maker?.name ?? "未知")
                metadata("演员", (movie.actors ?? []).map(\.name).joined(separator: " / "))
                metadata("标签", (movie.tags ?? []).map(\.name).joined(separator: " · "))
                if let id = movie.javdbId, !id.isEmpty {
                    NavigationLink {
                        MovieDetailView(movieID: id)
                    } label: {
                        Label("查看完整资料与资源", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity).padding(8)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Text("媒体播放由现有 Emby / Infuse 等播放器负责。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 650)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.canvas)
        .navigationTitle(movie.code)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func metadata(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            Text(value.isEmpty ? "暂无" : value).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.subheadline)
    }
}
