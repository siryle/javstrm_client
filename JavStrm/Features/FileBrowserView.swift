import SwiftUI
import JavStrmCore

struct FileBrowserView: View {
    @Environment(AppSession.self) private var session
    let source: String
    let directory: String
    var selectionTitle: String?
    var selectDirectory: ((PanDirectory) async -> String?)?
    @State private var files: [ManagedFile] = []
    @State private var currentPath = ""
    @State private var page = 0
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?
    @State private var selectedFile: ManagedFile?
    @State private var path: [NamedEntity] = []
    @State private var selecting = false
    @State private var loaded = false
    @State private var selectionError: String?

    private var visibleFiles: [ManagedFile] {
        files.filter { selectDirectory == nil || $0.isDirectory }
    }

    var body: some View {
        List {
            Section {
                Text(currentPath.isEmpty ? directory : currentPath).font(.caption.monospaced()).textSelection(.enabled)
                Text(selectDirectory == nil
                     ? "此处浏览的是服务器目录。文件操作可从设置页的「文件复制、移动与管理」进入。"
                     : "进入目标文件夹后，选择当前目录。")
                    .font(.footnote).foregroundStyle(.secondary)
                if selectDirectory != nil, directory != (source == "pan" ? "0" : "/") {
                    NavigationLink("返回根目录") {
                        FileBrowserView(source: source, directory: source == "pan" ? "0" : "/",
                                        selectionTitle: selectionTitle, selectDirectory: selectDirectory)
                    }
                    .disabled(selecting)
                }
            }
            if let selectDirectory {
                Button {
                    Task {
                        guard !selecting else { return }
                        selecting = true
                        defer { selecting = false }
                        let name = source == "pan" ? (path.last?.name ?? (directory == "0" ? "根目录" : directory))
                            : URL(fileURLWithPath: currentPath).lastPathComponent
                        let fullPath = source == "pan" ? "/" + path.filter { $0.id != "0" }.map(\.name).joined(separator: "/")
                            : currentPath
                        selectionError = await selectDirectory(PanDirectory(id: source == "pan" ? directory : currentPath,
                                                                           name: name, path: fullPath))
                    }
                } label: {
                    if selecting { ProgressView("正在保存") }
                    else { Label("选择当前目录", systemImage: "folder.badge.checkmark") }
                }
                .disabled(!loaded || loading || selecting || error != nil)
            }
            if let selectionError { Text(selectionError).font(.footnote).foregroundStyle(.red) }
            if let error { ErrorPanel(message: error) { Task { await load(reset: true) } } }
            if loading && files.isEmpty { ProgressView("正在读取目录") }
            if visibleFiles.isEmpty && !loading && error == nil {
                ContentUnavailableView(selectDirectory == nil ? "空目录" : "没有子目录", systemImage: "folder")
            }
            ForEach(visibleFiles) { file in
                if file.isDirectory {
                    NavigationLink {
                        FileBrowserView(source: source, directory: file.id,
                                        selectionTitle: selectionTitle, selectDirectory: selectDirectory)
                    } label: { fileRow(file) }
                    .disabled(selecting)
                } else {
                    Button { selectedFile = file } label: { fileRow(file) }.buttonStyle(.plain)
                }
            }
            if hasMore {
                LoadMoreButton(isLoading: loading) { Task { await load(reset: false) } }
                    .disabled(selecting || error != nil)
            }
        }
        .navigationTitle(selectionTitle.map { "选择\($0)" } ?? (source == "pan" ? "115 网盘" : "本地文件"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load(reset: true) }
        .refreshable { await load(reset: true) }
        .sheet(item: $selectedFile) { file in
            NavigationStack {
                Form {
                    LabeledContent("文件名", value: file.name)
                    LabeledContent("标识 / 路径", value: file.id)
                    if let size = file.size { LabeledContent("大小", value: byteSize(size)) }
                }
                .textSelection(.enabled)
                .navigationTitle("文件信息")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { selectedFile = nil } } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func fileRow(_ file: ManagedFile) -> some View {
        HStack(spacing: 14) {
            Image(systemName: file.isDirectory ? "folder.fill" : "doc")
                .foregroundStyle(file.isDirectory ? Palette.gold : Palette.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 5) {
                Text(file.name).font(.subheadline)
                if let size = file.size, !file.isDirectory {
                    Text(byteSize(size)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }.padding(.vertical, 5)
    }

    private func load(reset: Bool) async {
        guard let api = session.client, !loading, !selecting else { return }
        let connectionID = session.connectionID
        loading = true
        error = nil
        selectionError = nil
        defer { loading = false }
        let next = reset ? 1 : page + 1
        do {
            let newFiles: [ManagedFile]
            if source == "pan" {
                let result: PanFiles = try await api.get("/api/pan/files", query: [
                    URLQueryItem(name: "directory_id", value: directory),
                    URLQueryItem(name: "page", value: String(next))
                ])
                guard !Task.isCancelled, connectionID == session.connectionID else { return }
                newFiles = result.files ?? []
                path = result.path ?? []
                currentPath = path.map(\.name).joined(separator: " / ")
                hasMore = result.hasMore
            } else {
                let result: LocalFiles = try await api.get("/api/files/local", query: [.init(name: "path", value: directory)])
                guard !Task.isCancelled, connectionID == session.connectionID else { return }
                newFiles = result.files ?? []
                currentPath = result.path
                hasMore = false
            }
            guard !Task.isCancelled, connectionID == session.connectionID else { return }
            if reset { files = [] }
            let existing = Set(files.map(\.id))
            files += newFiles.filter { !existing.contains($0.id) }
            page = next
            loaded = true
        } catch {
            guard !Task.isCancelled, connectionID == session.connectionID else { return }
            self.error = session.describe(error)
            session.handle(error)
        }
    }
}
