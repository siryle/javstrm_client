import SwiftUI
import JavStrmCore

struct TasksView: View {
    @Environment(AppSession.self) private var session
    @State private var filter = "active"
    @State private var busy = false
    @State private var pendingAction: PendingAction?
    @State private var showConfirmation = false
    @State private var portal: WebDestination?

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
                BrandHeader(eyebrow: "The engine room", title: "任务",
                            subtitle: "下载、整理和刮削，一眼掌握进度。")
                    .listRowBackground(Color.clear)
                taskTools
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
                Button {
                    portal = WebDestination(title: "完整任务历史", path: "/tasks")
                } label: {
                    Label("查看完整任务历史与处理结果", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .navigationTitle("任务")
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await session.refreshTasks() }
        .confirmationDialog(pendingAction?.title ?? "执行操作", isPresented: $showConfirmation, titleVisibility: .visible) {
            Button(pendingAction?.title ?? "确认", role: pendingAction?.path.contains("terminate") == true
                   || pendingAction?.path.contains("cancel") == true ? .destructive : nil) { execute() }
        } message: { Text(pendingAction?.description ?? "") }
        .sheet(item: $portal) { WebPortalView(destination: $0) }
    }

    private var taskTools: some View {
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
            Button("配置工具") { portal = .init(title: "服务端工具", path: "/tools") }
        } label: {
            Label("整理与生成工具", systemImage: "plus.circle")
                .padding(.vertical, 6)
        }
        .buttonStyle(.bordered)
        .disabled(busy)
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
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
            }
        }.padding(.vertical, 8)
    }
}

private struct TaskDetailView: View {
    @Environment(AppSession.self) private var session
    let taskID: Int
    let initialTask: ServerTask
    @State private var busy = false
    @State private var confirmStop = false
    private var task: ServerTask { session.tasks.first { $0.id == taskID } ?? initialTask }
    private let labels = [
        "stage": "当前阶段", "current_path": "当前路径", "current_code": "当前番号",
        "files": "文件", "files_scanned": "已扫描文件", "directories_scanned": "已扫描目录",
        "directories_discovered": "发现目录", "video_files": "视频文件", "matched_files": "匹配文件",
        "unmatched_files": "未匹配文件", "movies": "作品", "removed_files": "移除文件",
        "removed_movies": "移除作品", "metadata_total": "元数据总数", "metadata_completed": "完成元数据",
        "moved": "移动", "renamed": "重命名", "skipped": "跳过", "deleted": "删除",
        "failed": "失败", "generated": "已生成", "matched": "已识别", "written": "已写入",
        "subtitle_missing": "缺少字幕", "total": "总数", "processed": "已处理",
        "submitted": "已提交", "imported": "已入库", "waiting": "等待",
        "scanned": "已扫描", "missing": "缺失", "uploaded": "上传", "removed": "移除",
        "succeeded": "成功", "directories": "目录"
    ]

    var body: some View {
        List {
            Section { TaskRow(task: task) }
            if task.canPause {
                Section {
                    Button(task.paused == true ? "恢复任务" : "暂停任务") { pauseOrResume() }.disabled(busy)
                    Button("终止任务", role: .destructive) { confirmStop = true }.disabled(busy)
                }
            }
            Section("处理详情") {
                ForEach(task.details.keys.sorted(), id: \.self) { key in
                    let value = task.details[key]?.text ?? ""
                    if !value.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(labels[key] ?? key).font(.caption).foregroundStyle(.secondary)
                            Text(value).font(.subheadline).textSelection(.enabled)
                        }.padding(.vertical, 2)
                    }
                }
            }
            Section("时间") {
                LabeledContent("创建", value: task.createdAt)
                LabeledContent("更新", value: task.updatedAt)
            }.font(.caption)
        }
        .navigationTitle(task.title)
        .toolbar(.visible, for: .navigationBar)
        .confirmationDialog("终止当前任务？", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("终止任务", role: .destructive) { act("terminate") }
        } message: { Text("已处理的文件会保留，任务后续处理将停止。") }
    }

    private func pauseOrResume() { act(task.paused == true ? "resume" : "pause") }

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
