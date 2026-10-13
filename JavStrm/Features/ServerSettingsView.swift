import SwiftUI
import UniformTypeIdentifiers
import JavStrmCore

struct ServerSettingsView: View {
    var body: some View {
        List {
            Section("服务端配置") {
                NavigationLink("115 登录与目录") { PanSettingsView() }
                ForEach(ServerSetting.allCases.filter { $0 != .embyCover }) { setting in
                    NavigationLink(setting.title) { ServerSettingEditor(setting: setting) }
                }
                NavigationLink(ServerSetting.embyCover.title) { EmbyCoversView() }
            }
            Section("数据") {
                NavigationLink("配置导入导出与缓存") { ServerDataView() }
            }
        }
        .navigationTitle("服务端完整设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ServerSettingEditor: View {
    @Environment(AppSession.self) private var session
    let setting: ServerSetting
    var offersRun = false
    @State private var value: JSONValue = .object([:])
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    @State private var testResult: JSONValue?
    @State private var confirmRun = false
    @State private var groupID = ""

    var body: some View {
        Form {
            if !loaded && error == nil { ProgressView("正在读取设置") }
            if let error { ErrorPanel(message: error) { Task { await load() } } }
            if loaded {
                if setting == .scraping {
                    Section("数据源") {
                        ForEach(Array(value.arrayValue.indices), id: \.self) { index in
                            Toggle(sourceTitle(value.arrayValue[index]["id"].stringValue), isOn: sourceBinding(index))
                        }
                    }
                } else {
                    SettingFieldsView(fields: setting.fields, value: $value)
                }
                if setting == .network || setting == .emby {
                    Section {
                        Button("测试连接") { Task { await test() } }
                        if let testResult { testResults(testResult) }
                    }
                }
                if setting == .emby {
                    Section {
                        NavigationLink("媒体库封面生成与上传") { EmbyCoversView() }
                        Text("同步删除、收藏转移和后台预探测按已保存的配置自动执行。")
                            .font(.footnote).foregroundStyle(.secondary)
                        if let webhook = try? session.client?.address.endpoint("/api/webhook/emby") {
                            LabeledContent("Emby Webhook") {
                                Text(webhook.absoluteString).font(.caption).textSelection(.enabled)
                            }
                            ShareLink("分享 Webhook 地址", item: webhook)
                            Text("在 Emby 的 Webhook 插件中填写此地址，并启用删除及收藏事件。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if offersRun, setting.startEndpoint != nil {
                    Section("执行") {
                        if setting == .quickStrm {
                            Picker("生成范围", selection: $groupID) {
                                Text("全部配置组").tag("")
                                ForEach(value["groups"].arrayValue, id: \.selfIdentifier) { group in
                                    Text(group["name"].stringValue.isEmpty ? group["id"].stringValue : group["name"].stringValue)
                                        .tag(group["id"].stringValue)
                                }
                            }
                        }
                        Button(setting.startTitle) { confirmRun = true }
                        NavigationLink("查看任务进度") { TasksView() }
                    }
                }
            }
            if busy { ProgressView("正在处理") }
        }
        .disabled(busy)
        .navigationTitle(setting.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { Task { await save() } }.disabled(!loaded || busy)
            }
        }
        .task(id: session.connectionID) { await load() }
        .confirmationDialog(setting.startTitle, isPresented: $confirmRun, titleVisibility: .visible) {
            Button("保存并执行") { Task { await run() } }
        } message: {
            Text(setting == .emptyDirectory ? "清理整理目录下的空文件夹，任务可在任务页查看。"
                 : "先保存当前配置，再由服务器执行任务。")
        }
    }

    private func sourceTitle(_ id: String) -> String {
        ["fanza": "FANZA", "fc2": "FC2 官方", "heyzo": "HEYZO 官方", "pacopacomama": "Pacopacomama 官方"][id] ?? id
    }

    private func sourceBinding(_ index: Int) -> Binding<Bool> {
        Binding {
            value.arrayValue.indices.contains(index) && value.arrayValue[index]["enabled"].boolValue
        } set: { enabled in
            var sources = value.arrayValue
            guard sources.indices.contains(index) else { return }
            sources[index]["enabled"] = .bool(enabled)
            value = .array(sources)
        }
    }

    @ViewBuilder private func testResults(_ result: JSONValue) -> some View {
        if setting == .network {
            ForEach(["javdb", "javbus"], id: \.self) { key in
                VStack(alignment: .leading, spacing: 5) {
                    Label("\(key == "javdb" ? "JavDB" : "JavBus")：\(result[key]["available"].boolValue ? "可连接" : "不可连接")",
                          systemImage: result[key]["available"].boolValue ? "checkmark.circle" : "xmark.circle")
                    if result[key]["latency_ms"] != .null {
                        Text("延迟 \(result[key]["latency_ms"].numberValue.formatted()) 毫秒").font(.caption)
                    }
                    if !result[key]["error"].stringValue.isEmpty {
                        Text(result[key]["error"].stringValue).font(.caption).foregroundStyle(.red)
                    }
                }
            }
        } else {
            LabeledContent("服务器", value: result["server_name"].stringValue)
            LabeledContent("版本", value: result["version"].stringValue)
        }
    }

    private func load() async {
        guard let api = session.client, !busy else { return }
        let connection = session.connectionID
        busy = true
        loaded = false
        error = nil
        defer { busy = false }
        do {
            let result = try await api.serverSettings(setting)
            guard connection == session.connectionID, !Task.isCancelled else { return }
            value = result
            loaded = true
        } catch { report(error, connection: connection) }
    }

    @discardableResult private func save() async -> Bool {
        guard let api = session.client, loaded, !busy else { return false }
        let connection = session.connectionID
        busy = true
        error = nil
        defer { busy = false }
        do {
            let result = try await api.saveServerSettings(setting, value: value)
            guard connection == session.connectionID, !Task.isCancelled else { return false }
            value = result
            session.notice = .init(message: "设置已保存。")
            return true
        } catch { report(error, connection: connection); return false }
    }

    private func test() async {
        guard let api = session.client, loaded, !busy else { return }
        let connection = session.connectionID
        let candidate = value
        busy = true
        error = nil
        testResult = nil
        defer { busy = false }
        do {
            let result: JSONValue = try await api.sendValue("POST", setting.endpoint + "/test", value: candidate)
            guard connection == session.connectionID, !Task.isCancelled else { return }
            testResult = result
        } catch { report(error, connection: connection) }
    }

    private func run() async {
        guard let endpoint = setting.startEndpoint, let api = session.client else { return }
        let connection = session.connectionID
        guard await save(), connection == session.connectionID else { return }
        busy = true
        let body: [String: JSONValue]? = setting == .quickStrm ? ["id": .string(groupID)] : nil
        defer { busy = false }
        do {
            let _: JSONValue = try await api.send("POST", endpoint, body: body)
            guard connection == session.connectionID, !Task.isCancelled else { return }
            session.notice = .init(message: "任务已创建，可在任务页查看进度。")
            await session.refreshTasks()
        } catch { report(error, connection: connection) }
    }

    private func report(_ failure: Error, connection: UUID) {
        guard connection == session.connectionID, !Task.isCancelled else { return }
        error = session.describe(failure)
        session.handle(failure)
    }
}

private extension JSONValue {
    var selfIdentifier: String { self["id"].stringValue }
}

struct SettingFieldsView: View {
    let fields: [SettingField]
    @Binding var value: JSONValue

    var body: some View {
        ForEach(fields) { field in
            SettingFieldEditor(field: field, value: Binding(
                get: { value[field.id] == .null ? field.defaultValue : value[field.id] },
                set: { value[field.id] = $0 }
            ))
        }
    }
}

private struct SettingFieldEditor: View {
    let field: SettingField
    @Binding var value: JSONValue
    @State private var choosingDirectory = false

    private var text: Binding<String> {
        Binding(get: { value.stringValue }, set: { value = .string($0) })
    }

    var body: some View {
        Group {
            switch field.kind {
            case .toggle:
                Toggle(field.title, isOn: Binding(get: { value.boolValue }, set: { value = .bool($0) }))
            case .number:
                TextField(field.title, value: Binding(get: { value.numberValue }, set: { value = .number($0) }), format: .number)
                    .keyboardType(.numbersAndPunctuation)
            case .choices(let choices):
                Picker(field.title, selection: text) {
                    ForEach(choices) { choice in Text(choice.title).tag(choice.id) }
                }
            case .secret:
                SecureField(field.title, text: text).textInputAutocapitalization(.never).autocorrectionDisabled()
            case .multiline:
                VStack(alignment: .leading) {
                    Text(field.title).font(.subheadline)
                    TextEditor(text: text).frame(minHeight: 100).font(.caption.monospaced())
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel(field.title)
                }
            case .object(let fields):
                NavigationLink(field.title) {
                    AnyView(Form { SettingFieldsView(fields: fields, value: $value) }.navigationTitle(field.title))
                }
            case .list(let fields):
                NavigationLink {
                    AnyView(SettingListEditor(title: field.title, fields: fields, value: $value))
                } label: {
                    LabeledContent(field.title, value: "\(value.arrayValue.count) 组")
                }
            case .panDirectory:
                Button { choosingDirectory = true } label: {
                    LabeledContent(field.title, value: value["path"].stringValue.isEmpty
                                   ? (value["name"].stringValue.isEmpty ? "选择目录" : value["name"].stringValue)
                                   : value["path"].stringValue)
                }
            case .localDirectory:
                VStack(alignment: .leading, spacing: 8) {
                    TextField(field.title, text: text).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("浏览并选择目录") { choosingDirectory = true }.font(.caption).buttonStyle(.borderless)
                }
            case .text:
                TextField(field.title, text: text).textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            if !field.hint.isEmpty { Text(field.hint).font(.caption).foregroundStyle(.secondary) }
        }
        .sheet(isPresented: $choosingDirectory) {
            NavigationStack {
                DirectoryPicker(source: isPanDirectory ? .pan : .local, title: field.title) { directory in
                    if isPanDirectory {
                        var selected = value.objectValue
                        selected["id"] = .string(directory.id)
                        selected["name"] = .string(directory.name)
                        selected["path"] = .string(directory.path ?? "")
                        value = .object(selected)
                    } else {
                        value = .string(directory.id)
                    }
                    choosingDirectory = false
                }
            }
        }
    }

    private var isPanDirectory: Bool {
        if case .panDirectory = field.kind { return true }
        return false
    }
}

private struct SettingListEditor: View {
    let title: String
    let fields: [SettingField]
    @Binding var value: JSONValue

    var body: some View {
        List {
            ForEach(Array(value.arrayValue.indices), id: \.self) { index in
                NavigationLink {
                    AnyView(Form {
                        SettingFieldsView(fields: fields, value: Binding(
                            get: { value.arrayValue.indices.contains(index) ? value.arrayValue[index] : .object([:]) },
                            set: { updated in
                                var array = value.arrayValue
                                guard array.indices.contains(index) else { return }
                                array[index] = updated
                                value = .array(array)
                            }
                        ))
                    }.navigationTitle("配置 \(index + 1)"))
                } label: {
                    Text(value.arrayValue[index]["name"].stringValue.isEmpty ? "配置 \(index + 1)" : value.arrayValue[index]["name"].stringValue)
                }
            }
            .onDelete { offsets in
                var array = value.arrayValue
                array.remove(atOffsets: offsets)
                value = .array(array)
            }
            Button("添加配置") {
                var item = Dictionary(uniqueKeysWithValues: fields.map { ($0.id, $0.defaultValue) })
                if fields.contains(where: { $0.id == "id" }) { item["id"] = .string(UUID().uuidString) }
                value = .array(value.arrayValue + [.object(item)])
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DirectoryPicker: View {
    @Environment(\.dismiss) private var dismiss
    let source: FileSource
    let title: String
    let onSelect: (PanDirectory) -> Void

    var body: some View {
        FileBrowserView(source: source.rawValue, directory: source.root, selectionTitle: title) { directory in
            onSelect(directory)
            return nil
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
    }
}

private struct ConfigurationDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw ManagementError.invalidArchive }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct ServerDataView: View {
    @Environment(AppSession.self) private var session
    @State private var info: JSONValue?
    @State private var error: String?
    @State private var busy = false
    @State private var document: ConfigurationDocument?
    @State private var exporting = false
    @State private var importing = false
    @State private var pendingArchive: JSONValue?
    @State private var confirmImport = false
    @State private var confirmCache = false

    var body: some View {
        Form {
            if let info {
                Section("数据与缓存") {
                    LabeledContent("数据目录", value: info["data_directory"].stringValue)
                    LabeledContent("数据库", value: byteSize(Int64(info["database_size_bytes"].numberValue)))
                    LabeledContent("图片缓存", value: byteSize(Int64(info["cache"]["size_bytes"].numberValue)))
                    LabeledContent("可清理图片", value: "\(info["cache"]["unused_entry_count"].numberValue.formatted()) 个")
                    Button("清理未使用图片缓存", role: .destructive) { confirmCache = true }
                }
            }
            Section("配置文件") {
                Button("导出服务端配置") { Task { await export() } }
                Button("导入配置文件") { importing = true }
            }
            if busy { ProgressView("正在处理") }
            if let error { ErrorPanel(message: error) { Task { await load() } } }
        }
        .disabled(busy)
        .navigationTitle("数据与缓存")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.connectionID) { await load() }
        .refreshable { await load() }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "javstrm-settings") { result in
            if case .failure(let failure) = result { error = session.describe(failure) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 16 * 1024 * 1024 else { throw ManagementError.invalidArchive }
                let archive = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
                try validateConfigurationArchive(archive)
                pendingArchive = archive
                confirmImport = true
            } catch { self.error = session.describe(error) }
        }
        .confirmationDialog("导入配置并覆盖服务端设置？", isPresented: $confirmImport, titleVisibility: .visible) {
            Button("导入配置", role: .destructive) { Task { await importArchive() } }
        } message: { Text("配置文件中的设置和订阅将写入服务器。") }
        .confirmationDialog("清理未使用图片缓存？", isPresented: $confirmCache, titleVisibility: .visible) {
            Button("清理缓存", role: .destructive) { Task { await load(clear: true) } }
        }
    }

    private func load(clear: Bool = false) async {
        await request { api in
            let result: JSONValue = try await api.send(clear ? "DELETE" : "GET", clear ? "/api/settings/cache" : "/api/settings/system")
            return result
        } receive: { info = $0 }
    }

    private func export() async {
        await request { try await $0.exportConfiguration() } receive: { archive in
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            document = ConfigurationDocument(data: try encoder.encode(archive))
            exporting = true
        }
    }

    private func importArchive() async {
        guard let archive = pendingArchive else { return }
        await request { try await $0.importConfiguration(archive) } receive: { result in
            pendingArchive = nil
            session.notice = .init(message: result["restart_required"].boolValue
                                   ? "配置已导入，请重启服务端使配置生效。" : "配置已导入。")
        }
    }

    private func request(_ operation: (APIClient) async throws -> JSONValue,
                         receive: (JSONValue) throws -> Void) async {
        guard let api = session.client, !busy else { return }
        let connection = session.connectionID
        busy = true
        error = nil
        defer { busy = false }
        do {
            let result = try await operation(api)
            guard connection == session.connectionID, !Task.isCancelled else { return }
            try receive(result)
        } catch {
            guard connection == session.connectionID, !Task.isCancelled else { return }
            self.error = session.describe(error)
            session.handle(error)
        }
    }
}
