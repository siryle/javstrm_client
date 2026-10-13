import SwiftUI
import JavStrmCore

struct TaskHistoryView: View {
    var body: some View {
        List {
            ForEach(WorkflowHistoryKind.allCases) { kind in
                NavigationLink(kind.title) { WorkflowHistoryView(kind: kind) }
            }
            NavigationLink("STRM 快速生成") { QuickJobHistoryView() }
        }
        .navigationTitle("任务历史")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WorkflowHistoryView: View {
    @Environment(AppSession.self) private var session
    let kind: WorkflowHistoryKind
    @State private var items: [ServerTask] = []
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var page = 0
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?
    @State private var requestID = UUID()

    var body: some View {
        List {
            if let error { ErrorPanel(message: error) { Task { await load(reset: true) } } }
            if loading && items.isEmpty { ProgressView("正在读取历史") }
            if !loading && items.isEmpty && error == nil {
                ContentUnavailableView("没有任务记录", systemImage: "clock")
            }
            ForEach(items) { task in
                NavigationLink {
                    TaskDetailView(taskID: task.id, initialTask: task)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(task.code ?? task.title)
                            Spacer()
                            StatusPill(value: task.status)
                        }
                        Text(task.createdAt).font(.caption).foregroundStyle(.secondary)
                        if let error = task.error, !error.isEmpty {
                            Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
                        }
                    }
                }
            }
            if hasMore { LoadMoreButton(isLoading: loading) { Task { await load(reset: false) } } }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜索任务记录")
        .onSubmit(of: .search) { submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines) }
        .onChange(of: query) { _, text in if text.isEmpty { submittedQuery = "" } }
        .task(id: "\(session.connectionID)|\(submittedQuery)") { await load(reset: true) }
        .refreshable { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        guard let api = session.client, reset || !loading else { return }
        let request = UUID()
        requestID = request
        let connection = session.connectionID
        let next = reset ? 1 : page + 1
        loading = true
        error = nil
        if reset { items = []; page = 0; hasMore = false }
        defer { if requestID == request { loading = false } }
        do {
            let result: WorkflowHistoryPage = try await api.get(kind.endpoint, query: [
                .init(name: "page", value: String(next)), .init(name: "q", value: submittedQuery)
            ])
            guard connection == session.connectionID, requestID == request, !Task.isCancelled else { return }
            let existing = Set(items.map(\.id))
            items += (result.items ?? []).filter { !existing.contains($0.id) }
            page = result.page
            hasMore = result.hasMore
        } catch {
            guard connection == session.connectionID, requestID == request, !Task.isCancelled else { return }
            self.error = session.describe(error)
            session.handle(error)
        }
    }
}

private struct QuickJobHistoryView: View {
    @Environment(AppSession.self) private var session
    @State private var jobs: [QuickJob] = []
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        List {
            if let error { ErrorPanel(message: error) { Task { await load() } } }
            if loading && jobs.isEmpty { ProgressView("正在读取历史") }
            if !loading && jobs.isEmpty && error == nil { ContentUnavailableView("没有任务记录", systemImage: "clock") }
            ForEach(jobs) { job in
                NavigationLink {
                    QuickJobResultsView(job: job)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text(job.startedAt); Spacer(); StatusPill(value: job.status) }
                        Text("生成 \(job.generated)，跳过 \(job.skipped)，失败 \(job.failed)").font(.caption)
                    }
                }
            }
        }
        .navigationTitle("STRM 快速生成历史")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.connectionID) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let api = session.client, !loading else { return }
        let connection = session.connectionID
        loading = true
        error = nil
        defer { loading = false }
        do {
            let result = try await api.list("/api/quick-strm/jobs/history", as: QuickJob.self)
            guard connection == session.connectionID, !Task.isCancelled else { return }
            jobs = result
        } catch {
            guard connection == session.connectionID, !Task.isCancelled else { return }
            self.error = session.describe(error)
            session.handle(error)
        }
    }
}

private struct QuickJobResultsView: View {
    @Environment(AppSession.self) private var session
    let job: QuickJob
    @State private var results: [WorkflowResult] = []
    @State private var page = 0
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                StatusPill(value: job.status)
                Text("生成 \(job.generated)，跳过 \(job.skipped)，失败 \(job.failed)")
            }
            if let error { ErrorPanel(message: error) { Task { await load(reset: true) } } }
            if loading { ProgressView() }
            ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(result.title); Spacer(); StatusPill(value: result.status) }
                    ForEach(result.detailFields) { field in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.label).font(.caption).foregroundStyle(.secondary)
                            Text(field.value).font(.subheadline).textSelection(.enabled)
                        }
                    }
                    if !result.error.isEmpty { Text(result.error).font(.caption).foregroundStyle(.red) }
                }
            }
            if hasMore { LoadMoreButton(isLoading: loading) { Task { await load(reset: false) } } }
        }
        .navigationTitle("生成结果")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load(reset: true) }
        .refreshable { await load(reset: true) }
    }

    private func load(reset: Bool) async {
        guard let api = session.client, !loading else { return }
        let connection = session.connectionID
        let next = reset ? 1 : page + 1
        loading = true
        error = nil
        defer { loading = false }
        do {
            let result: QuickJobResultsPage = try await api.get("/api/quick-strm/jobs/\(ServerAddress.segment(job.id))/results",
                                                               query: [.init(name: "page", value: String(next))])
            guard connection == session.connectionID, !Task.isCancelled else { return }
            results = reset ? (result.items ?? []) : results + (result.items ?? [])
            page = result.page
            hasMore = result.hasMore
        } catch {
            guard connection == session.connectionID, !Task.isCancelled else { return }
            self.error = session.describe(error)
            session.handle(error)
        }
    }
}
