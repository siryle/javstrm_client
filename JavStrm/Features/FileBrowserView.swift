import SwiftUI
import JavStrmCore

struct FileBrowserView: View {
    @Environment(AppSession.self) private var session
    let source: String
    let directory: String
    @State private var files: [ManagedFile] = []
    @State private var currentPath = ""
    @State private var page = 0
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?
    @State private var selectedFile: ManagedFile?

    var body: some View {
        List {
            Section {
                Text(currentPath.isEmpty ? directory : currentPath).font(.caption.monospaced()).textSelection(.enabled)
                Text("此处浏览的是服务器目录。文件操作可从设置页的「文件复制、移动与管理」进入。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let error { ErrorPanel(message: error) { Task { await load(reset: true) } } }
            if loading && files.isEmpty { ProgressView("正在读取目录") }
            if files.isEmpty && !loading && error == nil {
                ContentUnavailableView("空目录", systemImage: "folder")
            }
            ForEach(files) { file in
                if file.isDirectory {
                    NavigationLink {
                        FileBrowserView(source: source, directory: file.id)
                    } label: { fileRow(file) }
                } else {
                    Button { selectedFile = file } label: { fileRow(file) }.buttonStyle(.plain)
                }
            }
            if hasMore { LoadMoreButton(isLoading: loading) { Task { await load(reset: false) } } }
        }
        .navigationTitle(source == "pan" ? "115 网盘" : "本地文件")
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
        guard let api = session.client, !loading else { return }
        loading = true
        error = nil
        defer { loading = false }
        let next = reset ? 1 : page + 1
        do {
            let newFiles: [ManagedFile]
            if source == "pan" {
                let result: PanFiles = try await api.get("/api/pan/files", query: [
                    URLQueryItem(name: "directory_id", value: directory),
                    URLQueryItem(name: "page", value: String(next))
                ])
                newFiles = result.files ?? []
                currentPath = (result.path ?? []).map(\.name).joined(separator: " / ")
                hasMore = result.hasMore
            } else {
                let result: LocalFiles = try await api.get("/api/files/local", query: [.init(name: "path", value: directory)])
                newFiles = result.files ?? []
                currentPath = result.path
                hasMore = false
            }
            guard !Task.isCancelled else { return }
            if reset { files = [] }
            let existing = Set(files.map(\.id))
            files += newFiles.filter { !existing.contains($0.id) }
            page = next
        } catch {
            guard !Task.isCancelled else { return }
            self.error = session.describe(error)
            session.handle(error)
        }
    }
}
