import SwiftUI
import JavStrmCore

struct TasksView: View {
    @Environment(AppSession.self) private var session
    @State private var filter = "active"
    @State private var busy = false
    @State private var pendingAction: PendingAction?
    @State private var showConfirmation = false

    private struct PendingAction {
        let title: String
        let path: String
        let body: [String: JSONValue]?
        let description: String
    }

    private var workflows: [ServerTask] { session.tasks.filter { matches($0.status) } }
    private var offline: [OfflineTask] { session.offlineTasks.filter { matches($0.status) } }
    private var quick: [QuickJob] { session.quickJobs.filter { matches($0.status) } }

    var body: some View {
        List {
            Section {
                HStack {
                    Circle().fill(session.streamState == .live ? Palette.accent : Palette.gold)
                        .frame(width: 7, height: 7)
                    Text(session.streamState.rawValue).font(.caption)
                    Spacer()
                    if let date = session.lastSynced {
                        Text(date, style: .time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                Picker("任务状态", selection: $filter) {
                    Text("进行中").tag("active")
                    Text("全部").tag("all")
                    Text("异常").tag("failed")
                }.pickerStyle(.segmented)
            }.listRowSeparator(.hidden)
            if let error = session.taskError {
                Section("工作流连接") { ErrorPanel(message: error) { Task { await session.refreshTasks() } } }
            }
            if !workflows.isEmpty {
                Section("工作流") {
                    ForEach(workflows) { task in
                        NavigationLink { TaskDetailView(taskID: task.id, initialTask: task) } label: {
                            TaskRow(task: task)
                        }
                    }
                }
            }
            if let error = session.offlineError {
                Section("115 离线下载") { ErrorPanel(message: error) { Task { await session.refreshTasks() } } }
            }
            if !offline.isEmpty {
                Section("115 离线下载") {
                    ForEach(offline) { task in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(task.code).font(.system(.headline, design: .monospaced))
                                Spacer()
                                StatusPill(value: task.status)
                            }
                            ProgressView(value: min(1, max(0, task.progress / 100)))
                            HStack {
                                StatusPill(value: task.phase)
                                Spacer()
                                Text("\(Int(task.progress))%").font(.caption.monospacedDigit())
                            }
                            if let error = task.error, !error.isEmpty {
                                Text(error).font(.caption).foregroundStyle(.red)
                            }
                            if task.isActive {
                                Button("终止离线任务", role: .destructive) {
                                    confirm(title: "终止离线任务", path: "/api/offline/tasks/\(task.id)/terminate",
                                            description: "停止 \(task.code) 当前的离线下载及后续处理。")
                                }.disabled(busy)
                            }
                        }.padding(.vertical, 8)
                    }
                }
            }
            if let error = session.quickError {
                Section("STRM 快速生成") { ErrorPanel(message: error) { Task { await session.refreshTasks() } } }
            }
            if !quick.isEmpty {
                Section("STRM 快速生成") {
                    ForEach(quick) { job in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("快速生成").font(.headline)
                                Spacer()
                                StatusPill(value: job.status)
                            }
                            ProgressView(value: job.fraction)
                            Text("已处理 \(job.processed) / \(job.files) · 生成 \(job.generated) · 跳过 \(job.skipped) · 失败 \(job.failed)")
                                .font(.caption).foregroundStyle(.secondary)
                            if let errors = job.errors, !errors.isEmpty {
                                Text(errors.prefix(3).joined(separator: "\n")).font(.caption).foregroundStyle(.red)
                            }
                            if job.status == "running" {
                                Button("停止生成", role: .destructive) {
                                    confirm(title: "停止 STRM 生成",
                                            path: "/api/quick-strm/jobs/\(ServerAddress.segment(job.id))/cancel",
                                            description: "已生成的文件会保留。")
                                }.disabled(busy)
                            }
                        }.padding(.vertical, 8)
                    }
                }
            }
            if workflows.isEmpty && offline.isEmpty && quick.isEmpty
                && session.taskError == nil && session.offlineError == nil && session.quickError == nil {
                ContentUnavailableView(filter == "failed" ? "没有异常任务" : "暂无任务",
                                       systemImage: "checkmark.circle",
                                       description: Text("服务端任务会在这里自动更新。"))
            }
            Section {
                NavigationLink {
                    TaskHistoryView()
                } label: {
                    Label("查看完整任务历史与处理结果", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .navigationTitle("任务")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("115 媒体整理") {
                        confirm(title: "启动 115 媒体整理", path: "/api/organize",
                                description: "使用服务端已保存的源目录、目标目录及整理规则。")
                    }
                    Button("本地媒体整理") {
                        confirm(title: "启动本地媒体整理", path: "/api/local/organize",
                                description: "使用服务端已保存的本地媒体整理配置。")
                    }
                    Button("STRM 元数据刮削") {
                        confirm(title: "启动 STRM 刮削", path: "/api/strm-scrape",
                                description: "使用服务端已保存的刮削目录和设置。")
                    }
                    Button("全部 STRM 快速生成") {
                        confirm(title: "启动 STRM 快速生成", path: "/api/quick-strm/generate",
                                body: ["id": .string("")],
                                description: "执行服务端已配置的全部生成组，使用各组的覆盖及清理规则。")
                    }
                    NavigationLink("配置工具") { ServerToolsView() }
                } label: { Image(systemName: "plus.circle") }
                .disabled(busy)
            }
        }
        .refreshable { await session.refreshTasks() }
        .confirmationDialog(pendingAction?.title ?? "执行操作", isPresented: $showConfirmation, titleVisibility: .visible) {
            Button(pendingAction?.title ?? "确认", role: pendingAction?.path.contains("terminate") == true
                   || pendingAction?.path.contains("cancel") == true ? .destructive : nil) { execute() }
        } message: { Text(pendingAction?.description ?? "") }
    }

    private func matches(_ status: String) -> Bool {
        switch filter {
        case "active": ["running", "queued"].contains(status)
        case "failed": ["failed", "interrupted"].contains(status)
        default: true
        }
    }

    private func confirm(title: String, path: String, body: [String: JSONValue]? = nil, description: String) {
        pendingAction = PendingAction(title: title, path: path, body: body, description: description)
        showConfirmation = true
    }

    private func execute() {
        guard let action = pendingAction else { return }
        busy = true
        Task {
            await session.perform(success: "操作已提交。") { api in
                try await api.discard("POST", action.path, body: action.body)
            }
            busy = false
        }
    }
}

private struct TaskRow: View {
    let task: ServerTask
    var errorLineLimit: Int? = 3
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(task.title).font(.headline)
                Spacer()
                StatusPill(value: task.paused == true ? "paused" : task.status)
            }
            if let code = task.code { Text(code).font(.caption.monospaced()) }
            ProgressView(value: task.fraction)
            HStack {
                Text("#\(task.id)").font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(task.progress))%").font(.caption.monospacedDigit())
            }
            if let error = task.error, !error.isEmpty {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(errorLineLimit)
                    .textSelection(.enabled)
            }
        }.padding(.vertical, 8)
    }
}

struct TaskDetailView: View {
    @Environment(AppSession.self) private var session
    let taskID: Int
    let initialTask: ServerTask
    @State private var busy = false
    @State private var confirmStop = false
    @State private var results: [WorkflowResult] = []
    @State private var resultPage = 0
    @State private var resultTotal = 0
    @State private var hasMoreResults = false
    @State private var loadingResults = false
    @State private var resultError: String?
    @State private var resultRequestID = UUID()
    private var task: ServerTask { session.tasks.first { $0.id == taskID } ?? initialTask }
    private var visibleResults: [WorkflowResult] {
        task.resultsPath == nil ? task.embeddedResults : results
    }

    var body: some View {
        List {
            Section { TaskRow(task: task, errorLineLimit: nil) }
            if task.canPause {
                Section {
                    Button(task.paused == true ? "恢复任务" : "暂停任务") { pauseOrResume() }.disabled(busy)
                    Button("终止任务", role: .destructive) { confirmStop = true }.disabled(busy)
                }
            }
            Section("处理进度") {
                if task.detailFields.isEmpty {
                    Text(task.isActive ? "任务等待服务端报告处理进度。" : "服务端未提供处理进度。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(task.detailFields) { field in
                    TaskDetailFieldView(field: field)
                }
            }
            if task.resultsPath != nil || !visibleResults.isEmpty {
                Section {
                    if let resultError {
                        ErrorPanel(message: resultError) { Task { await loadResults(reset: true) } }
                    }
                    if loadingResults && results.isEmpty {
                        ProgressView("正在读取处理详情")
                    } else if visibleResults.isEmpty && resultError == nil {
                        Text(task.isActive ? "尚未产生处理结果，完成的条目会自动显示。" : "服务端没有保存逐项处理结果。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(Array(visibleResults.enumerated()), id: \.offset) { _, result in
                        WorkflowResultRow(result: result)
                    }
                    if hasMoreResults {
                        LoadMoreButton(isLoading: loadingResults) { Task { await loadResults(reset: false) } }
                    }
                } header: {
                    Text(resultTotal > 0 ? "处理详情（\(resultTotal)）" : "处理详情")
                }
            }
            Section("时间") {
                LabeledContent("创建", value: task.createdAt)
                LabeledContent("更新", value: task.updatedAt)
            }.font(.caption)
        }
        .navigationTitle(task.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.connectionID) {
            guard task.resultsPath != nil else { return }
            while !Task.isCancelled {
                await loadResults(reset: true)
                if !task.isActive && !loadingResults { return }
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }
            }
        }
        .refreshable {
            await session.refreshTasks()
            await loadResults(reset: true)
        }
        .confirmationDialog("终止当前任务？", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("终止任务", role: .destructive) { act("terminate") }
        } message: { Text("已处理的文件会保留，任务后续处理将停止。") }
    }

    private func pauseOrResume() { act(task.paused == true ? "resume" : "pause") }

    private func loadResults(reset: Bool) async {
        guard let api = session.client, task.resultsPath != nil, !loadingResults else { return }
        let request = UUID()
        resultRequestID = request
        let connection = session.connectionID
        let currentTask = task
        let nextPage = reset ? 1 : resultPage + 1
        let lastPage = reset ? max(1, resultPage) : nextPage
        loadingResults = true
        resultError = nil
        defer { if resultRequestID == request { loadingResults = false } }
        do {
            var loaded: [WorkflowResult] = []
            var last: WorkflowResultsPage?
            // Refresh every loaded page so growing results do not erase older visible entries.
            for page in nextPage...lastPage {
                let response = try await api.taskResults(currentTask, page: page)
                guard !Task.isCancelled, connection == session.connectionID,
                      resultRequestID == request else { return }
                guard response.taskId == taskID else { throw APIError.invalidResponse }
                loaded += response.items ?? []
                last = response
                if !response.hasMore { break }
            }
            guard let last else { return }
            results = reset ? loaded : results + loaded
            resultPage = last.page
            resultTotal = last.total
            hasMoreResults = last.hasMore
        } catch {
            guard !Task.isCancelled, connection == session.connectionID,
                  resultRequestID == request else { return }
            resultError = session.describe(error)
            session.handle(error)
        }
    }

    private func act(_ action: String) {
        let id = taskID
        busy = true
        Task {
            await session.perform { api in
                let _: ServerTask = try await api.send("POST", "/api/tasks/\(id)/\(action)")
            }
            busy = false
        }
    }
}

private struct TaskDetailFieldView: View {
    let field: TaskDetailField

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(field.label).font(.caption).foregroundStyle(.secondary)
            Text(field.value).font(.subheadline).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

private struct WorkflowResultRow: View {
    let result: WorkflowResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                if !result.title.isEmpty {
                    Text(result.title).font(.subheadline.weight(.semibold)).textSelection(.enabled)
                }
                Spacer()
                StatusPill(value: result.status)
            }
            ForEach(result.detailFields) { field in
                TaskDetailFieldView(field: field)
            }
            if !result.error.isEmpty {
                Text(result.error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
        }
        .padding(.vertical, 8)
    }
}
