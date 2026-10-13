import SwiftUI
import JavStrmCore

struct LogsView: View {
    @Environment(AppSession.self) private var session
    @State private var component = "system"
    @State private var logs: [LogEntry] = []
    @State private var error: String?
    @State private var loading = false
    @State private var search = ""
    private let components = [
        ("system", "系统"), ("offline", "离线下载"), ("organize", "整理"),
        ("strm_scrape", "刮削"), ("strm_generate", "STRM"),
        ("emby", "Emby"), ("drive", "网盘")
    ]

    var body: some View {
        List {
            Section {
                Picker("日志来源", selection: $component) {
                    ForEach(components, id: \.0) { item in Text(item.1).tag(item.0) }
                }
            }
            if let error { ErrorPanel(message: error) { Task { await load() } } }
            if loading { ProgressView() }
            if logs.isEmpty && !loading && error == nil {
                ContentUnavailableView("暂无日志", systemImage: "text.alignleft")
            }
            ForEach(Array(logs.enumerated()), id: \.offset) { _, log in
                if search.isEmpty || log.message.localizedCaseInsensitiveContains(search) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(log.level).font(.caption.monospaced().weight(.bold))
                                .foregroundStyle(log.level.uppercased() == "ERROR" ? .red : Palette.accent)
                            Spacer()
                            Text(log.time).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        }
                        Text(log.message).font(.subheadline).textSelection(.enabled)
                    }.padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("系统日志")
        .toolbar(.visible, for: .navigationBar)
        .searchable(text: $search, prompt: "筛选日志")
        .task(id: component) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let api = session.client else { return }
        let selected = component
        loading = true
        error = nil
        defer { if component == selected { loading = false } }
        do {
            let result = try await api.list("/api/logs", query: [.init(name: "component", value: selected)], as: LogEntry.self)
            guard !Task.isCancelled, component == selected else { return }
            logs = result
        } catch {
            guard !Task.isCancelled, component == selected else { return }
            self.error = session.describe(error)
            session.handle(error)
        }
    }
}
