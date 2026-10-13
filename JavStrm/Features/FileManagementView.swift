import SwiftUI
import JavStrmCore

struct FileManagementView: View {
    @Environment(AppSession.self) private var session
    @State private var pan: PanStatus?
    @State private var error: String?

    var body: some View {
        List {
            Section("文件位置") {
                NavigationLink("服务端本地文件") { ManagedFilesView(source: .local) }
                if let pan, pan.connected, let account = pan.account {
                    NavigationLink("115 网盘文件") { ManagedFilesView(source: .pan, accountID: account.id) }
                } else {
                    NavigationLink("登录 115 网盘") { PanSettingsView() }
                }
            }
            if let error { ErrorPanel(message: error) { Task { await load() } } }
        }
        .navigationTitle("文件复制、移动与管理")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.connectionID) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let api = session.client else { return }
        let connection = session.connectionID
        do {
            let result: PanStatus = try await api.get("/api/pan/account")
            guard connection == session.connectionID, !Task.isCancelled else { return }
            pan = result
            error = nil
        } catch {
            guard connection == session.connectionID, !Task.isCancelled else { return }
            self.error = session.describe(error)
            session.handle(error)
        }
    }
}

private struct ManagedFilesView: View {
    @Environment(AppSession.self) private var session
    let source: FileSource
    let accountID: String
    @State private var directory: String
    @State private var parent: String?
    @State private var currentPath = ""
    @State private var breadcrumbs: [NamedEntity] = []
    @State private var files: [ManagedFile] = []
    @State private var selected = Set<String>()
    @State private var selecting = false
    @State private var loading = false
    @State private var loaded = false
    @State private var page = 0
    @State private var hasMore = false
    @State private var error: String?
    @State private var requestID = UUID()
    @State private var pendingOperation: PendingOperation?
    @State private var fileInfo: ManagedFile?

    private struct PendingOperation: Identifiable {
        let id = UUID()
        let action: FileAction
        let files: [ManagedFile]
        let directory: String
    }

    init(source: FileSource, accountID: String = "") {
        self.source = source
        self.accountID = accountID
        _directory = State(initialValue: source.root)
    }

    private var selectedFiles: [ManagedFile] { files.filter { selected.contains($0.id) } }

    var body: some View {
        List {
            Section {
                Text(currentPath.isEmpty ? directory : currentPath).font(.caption.monospaced()).textSelection(.enabled)
                HStack {
                    Button("根目录") { navigate(source.root) }.disabled(directory == source.root)
                    Spacer()
                    Button("上级目录") { if let parent { navigate(parent) } }.disabled(parent == nil || directory == source.root)
                }
                .buttonStyle(.borderless)
                if selecting {
                    HStack {
                        Text("已选 \(selected.count) 项")
                        Spacer()
                        Button("选择已加载项目") { selected = Set(files.prefix(100).map(\.id)) }
                        Button("清空") { selected = [] }
                    }.font(.caption)
                        .buttonStyle(.borderless)
                }
            }
            .disabled(loading)
            if let error { ErrorPanel(message: error) { Task { await load(reset: true) } } }
            if loading && files.isEmpty { ProgressView("正在读取文件") }
            if loaded && files.isEmpty && error == nil { ContentUnavailableView("空目录", systemImage: "folder") }
            ForEach(files) { file in
                Button {
                    if selecting {
                        if selected.contains(file.id) { selected.remove(file.id) }
                        else if selected.count < 100 { selected.insert(file.id) }
                    } else if file.isDirectory {
                        navigate(file.id)
                    } else {
                        fileInfo = file
                    }
                } label: {
                    HStack(spacing: 12) {
                        if selecting {
                            Image(systemName: selected.contains(file.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(Palette.accent)
                        }
                        Image(systemName: file.isDirectory ? "folder.fill" : "doc")
                            .foregroundStyle(file.isDirectory ? Palette.gold : Palette.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.name).foregroundStyle(.primary)
                            if let size = file.size, !file.isDirectory {
                                Text(byteSize(size)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if file.isDirectory && !selecting { Image(systemName: "chevron.right").font(.caption) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(loading)
                .contextMenu {
                    ForEach(FileAction.allCases) { operation in
                        Button(operation.title, role: operation == .delete ? .destructive : nil) {
                            selected = [file.id]
                            pendingOperation = .init(action: operation, files: [file], directory: directory)
                        }
                    }
                }
            }
            if hasMore { LoadMoreButton(isLoading: loading) { Task { await load(reset: false) } } }
        }
        .navigationTitle(source.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(selecting ? "完成选择" : "选择") {
                    selecting.toggle()
                    if !selecting { selected = [] }
                }
                .disabled(!loaded || loading)
                Menu {
                    ForEach(FileAction.allCases) { operation in
                        Button(operation.title, role: operation == .delete ? .destructive : nil) {
                            pendingOperation = .init(action: operation, files: selectedFiles, directory: directory)
                        }
                            .disabled(operation == .rename && selected.count != 1)
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .disabled(selected.isEmpty || loading)
            }
        }
        .task(id: directory) { await load(reset: true) }
        .refreshable { await load(reset: true) }
        .sheet(item: $pendingOperation) { operation in
            NavigationStack {
                FileOperationView(source: source, action: operation.action, directory: operation.directory,
                                  accountID: accountID, files: operation.files) { result in
                    await load(reset: true)
                    selected = Set(result.failed.map(\.id)).intersection(files.map(\.id))
                    selecting = !selected.isEmpty
                }
            }
        }
        .sheet(item: $fileInfo) { file in
            NavigationStack {
                Form {
                    LabeledContent("文件名", value: file.name)
                    LabeledContent("路径 / 标识", value: file.id)
                    if let size = file.size { LabeledContent("大小", value: byteSize(size)) }
                }
                .textSelection(.enabled)
                .navigationTitle("文件信息")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { fileInfo = nil } } }
            }
        }
    }

    private func navigate(_ target: String) {
        selected = []
        selecting = false
        loaded = false
        directory = target
    }

    private func load(reset: Bool) async {
        guard let api = session.client, reset || !loading else { return }
        let request = UUID()
        requestID = request
        let connection = session.connectionID
        let target = directory
        let next = reset ? 1 : page + 1
        loading = true
        error = nil
        if reset { files = []; page = 0; hasMore = false }
        defer { if requestID == request { loading = false } }
        do {
            let incoming: [ManagedFile]
            if source == .pan {
                let account: PanStatus = try await api.get("/api/pan/account")
                guard account.connected, account.account?.id == accountID else { throw APIError.http(409, "网盘账户已改变，请返回文件管理页重新打开。") }
                let result: PanFiles = try await api.get("/api/pan/files", query: [
                    .init(name: "directory_id", value: target), .init(name: "page", value: String(next))
                ])
                guard requestID == request, connection == session.connectionID, !Task.isCancelled else { return }
                incoming = result.files ?? []
                breadcrumbs = result.path ?? []
                parent = breadcrumbs.dropLast().last?.id
                currentPath = breadcrumbs.map(\.name).joined(separator: " / ")
                hasMore = result.hasMore
            } else {
                let result: LocalFiles = try await api.get("/api/files/local", query: [.init(name: "path", value: target)])
                guard requestID == request, connection == session.connectionID, !Task.isCancelled else { return }
                incoming = result.files ?? []
                parent = result.parent
                currentPath = result.path
                hasMore = false
            }
            let existing = Set(files.map(\.id))
            files += incoming.filter { !existing.contains($0.id) }
            if reset { selected.formIntersection(files.map(\.id)) }
            page = next
            loaded = true
        } catch {
            guard requestID == request, connection == session.connectionID, !Task.isCancelled else { return }
            self.error = session.describe(error)
            session.handle(error)
        }
    }
}

private struct FileOperationView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    let source: FileSource
    let action: FileAction
    let directory: String
    let accountID: String
    let files: [ManagedFile]
    let onComplete: (FileOperationResult) async -> Void
    @State private var destination = ""
    @State private var destinationName = ""
    @State private var name = ""
    @State private var choosingDirectory = false
    @State private var confirmDelete = false
    @State private var busy = false
    @State private var error: String?
    @State private var result: FileOperationResult?

    private var operation: FileOperation {
        FileOperation(source: source, action: action, ids: files.map(\.id), directory: directory,
                      destination: destination, name: name, accountID: accountID)
    }

    var body: some View {
        Form {
            Section("已选项目（\(files.count)）") {
                ForEach(files) { file in Text(file.name) }
            }
            if action == .copy || action == .move {
                Section("目标目录") {
                    if source == .local {
                        TextField("目标绝对路径", text: $destination).textInputAutocapitalization(.never).autocorrectionDisabled()
                    } else if !destinationName.isEmpty {
                        Text(destinationName)
                    }
                    Button("浏览并选择目录") { choosingDirectory = true }
                }
            }
            if action == .rename {
                Section("新名称") { TextField("文件或文件夹名称", text: $name).autocorrectionDisabled() }
            }
            if let result {
                Section("处理结果") {
                    Text("已完成 \(result.completed.count) 项，失败 \(result.failed.count) 项")
                    ForEach(Array(result.failed.enumerated()), id: \.offset) { _, failure in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(files.first { $0.id == failure.id }?.name ?? failure.id)
                            Text(failure.message).font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            if busy { ProgressView("正在\(action.title)") }
            if result == nil {
                Button(action.title, role: action == .delete ? .destructive : nil) {
                    if action == .delete { confirmDelete = true }
                    else { Task { await execute() } }
                }
                .disabled(!operation.isValid)
            }
        }
        .disabled(busy)
        .navigationTitle(action.title)
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(busy)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() }.disabled(busy) } }
        .onAppear { if name.isEmpty { name = files.first?.name ?? "" } }
        .sheet(isPresented: $choosingDirectory) {
            NavigationStack {
                DirectoryPicker(source: source, title: "目标目录") { selected in
                    destination = selected.id
                    destinationName = selected.path ?? selected.name
                    choosingDirectory = false
                }
            }
        }
        .confirmationDialog("删除所选 \(files.count) 个项目？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) { Task { await execute() } }
        } message: { Text("所选文件夹及其内容也会被删除。") }
    }

    private func execute() async {
        guard let api = session.client, operation.isValid, !busy, result == nil else { return }
        let connection = session.connectionID
        let request = operation
        busy = true
        error = nil
        defer { busy = false }
        do {
            let response = try await api.operateFiles(request)
            guard connection == session.connectionID, !Task.isCancelled else { return }
            result = response
            await onComplete(response)
            guard connection == session.connectionID, !Task.isCancelled else { return }
            await session.refreshTasks()
            if response.failed.isEmpty {
                session.notice = .init(message: "已\(action.title) \(response.completed.count) 个项目。")
                dismiss()
            }
        } catch {
            guard connection == session.connectionID, !Task.isCancelled else { return }
            self.error = session.describe(error)
            session.handle(error)
        }
    }
}
