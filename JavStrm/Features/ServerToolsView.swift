import SwiftUI
import UIKit
import JavStrmCore

struct ServerToolsView: View {
    var body: some View {
        List {
            Section("STRM 与整理") {
                tool(.quickStrm)
                tool(.strmScrape)
                tool(.organize)
                tool(.localOrganize)
                tool(.emptyDirectory)
            }
            Section("Emby") {
                tool(.emby)
                NavigationLink("媒体库封面生成与上传") { EmbyCoversView() }
            }
            Section("任务") {
                NavigationLink("任务进度与处理详情") { TasksView() }
            }
        }
        .navigationTitle("STRM 与 Emby 工具")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func tool(_ setting: ServerSetting) -> some View {
        NavigationLink(setting.title) { ServerSettingEditor(setting: setting, offersRun: true) }
    }
}

struct EmbyCoversView: View {
    @Environment(AppSession.self) private var session
    @AppStorage("hideArtwork") private var hideArtwork = true
    @State private var value: JSONValue = .object([:])
    @State private var loaded = false
    @State private var libraries: [EmbyCoverLibrary] = []
    @State private var serverID = ""
    @State private var previews: [CoverPreview] = []
    @State private var uploaded = Set<String>()
    @State private var error: String?
    @State private var busy = false
    @State private var progress = ""
    @State private var worker: Task<Void, Never>?

    private struct CoverPreview: Identifiable {
        var id: String { library.id }
        let library: EmbyCoverLibrary
        let serverID: String
        let data: Data
    }

    private var draft: Binding<JSONValue> {
        Binding(get: { value }, set: { value = $0; invalidatePreviews() })
    }

    var body: some View {
        Form {
            if loaded {
                SettingFieldsView(fields: ServerSetting.embyCover.fields, value: draft)
                Section("媒体库") {
                    Button("刷新媒体库") { start { await load() } }
                    ForEach(libraries) { library in
                        Toggle(library.name, isOn: selection(library.id))
                        if value["library_ids"].arrayValue.contains(.string(library.id)) {
                            TextField("封面标题", text: title(library, key: "title"))
                            TextField("副标题", text: title(library, key: "subtitle"))
                        }
                    }
                }
                Section {
                    Button("保存设置") { start { _ = await save() } }
                    Button("生成封面预览") { start { await generate() } }
                        .disabled(serverID.isEmpty || value["library_ids"].arrayValue.isEmpty || hideArtwork)
                    if !previews.isEmpty {
                        Button("上传封面到 Emby") { start { await upload() } }
                            .disabled(uploaded.count == previews.count)
                    }
                    if hideArtwork { Text("显示封面后可生成和查看预览。").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            if busy { ProgressView(progress.isEmpty ? "正在处理" : progress) }
            if let error { ErrorPanel(message: error) { start { await load() } } }
            if !hideArtwork {
                ForEach(previews) { preview in
                    Section(preview.library.name) {
                        if let image = UIImage(data: preview.data) {
                            Image(uiImage: image).resizable().scaledToFit()
                        }
                        if uploaded.contains(preview.id) { Label("已上传", systemImage: "checkmark.circle") }
                    }
                }
            }
        }
        .disabled(busy)
        .navigationTitle("Emby 媒体库封面")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.connectionID) { await load() }
        .onChange(of: hideArtwork) { _, hidden in
            if hidden { worker?.cancel(); invalidatePreviews() }
        }
        .onDisappear { worker?.cancel() }
    }

    private func start(_ operation: @escaping @MainActor () async -> Void) {
        guard !busy else { return }
        worker = Task { await operation() }
    }

    private func invalidatePreviews() {
        previews = []
        uploaded = []
    }

    private func selection(_ id: String) -> Binding<Bool> {
        Binding { value["library_ids"].arrayValue.contains(.string(id)) } set: { selected in
            var ids = value["library_ids"].arrayValue.filter { $0 != .string(id) }
            if selected && ids.count < 32 { ids.append(.string(id)) }
            value["library_ids"] = .array(ids)
            invalidatePreviews()
        }
    }

    private func title(_ library: EmbyCoverLibrary, key: String) -> Binding<String> {
        Binding {
            value["titles"].arrayValue.first { $0["library_id"].stringValue == library.id }?[key].stringValue ?? ""
        } set: { text in
            var titles = value["titles"].arrayValue
            let index = titles.firstIndex { $0["library_id"].stringValue == library.id }
            var item = index.map { titles[$0] } ?? .object(["library_id": .string(library.id),
                                                          "title": .string(""), "subtitle": .string("")])
            item[key] = .string(text)
            if let index { titles[index] = item } else { titles.append(item) }
            value["titles"] = .array(titles)
            invalidatePreviews()
        }
    }

    private func load() async {
        guard let api = session.client, !busy else { return }
        let connection = session.connectionID
        busy = true
        progress = "正在读取媒体库"
        error = nil
        serverID = ""
        invalidatePreviews()
        defer { busy = false }
        do {
            let config = try await api.serverSettings(.embyCover)
            guard connection == session.connectionID, !Task.isCancelled else { return }
            value = config
            loaded = true
            let response: EmbyCoverLibraries = try await api.get("/api/emby/covers/libraries")
            guard connection == session.connectionID, !Task.isCancelled else { return }
            libraries = response.libraries
            serverID = response.serverId
        } catch { report(error, connection: connection) }
    }

    private func save() async -> Bool {
        guard let api = session.client, loaded, !busy else { return false }
        let connection = session.connectionID
        busy = true
        error = nil
        progress = "正在保存"
        defer { busy = false }
        do {
            let result = try await api.saveServerSettings(.embyCover, value: value)
            guard connection == session.connectionID, !Task.isCancelled else { return false }
            if result != value { invalidatePreviews() }
            value = result
            session.notice = .init(message: "封面设置已保存。")
            return true
        } catch { report(error, connection: connection); return false }
    }

    private func generate() async {
        let connection = session.connectionID
        guard !hideArtwork, !serverID.isEmpty, await save(),
              connection == session.connectionID, !Task.isCancelled, let api = session.client else { return }
        let config = value
        let selected = libraries.filter { config["library_ids"].arrayValue.contains(.string($0.id)) }
        invalidatePreviews()
        busy = true
        defer { busy = false }
        for library in selected {
            guard connection == session.connectionID, !Task.isCancelled, !hideArtwork else { return }
            progress = "正在生成 \(library.name)"
            do {
                let prepared: EmbyCoverPrepared = try await api.send("POST", "/api/emby/covers/prepare", body: [
                    "library_id": .string(library.id), "server_id": .string(serverID), "config": config
                ])
                guard connection == session.connectionID, !Task.isCancelled, !hideArtwork else { return }
                guard prepared.library.id == library.id, prepared.serverId == serverID else { throw APIError.invalidResponse }
                let custom = config["titles"].arrayValue.first { $0["library_id"].stringValue == library.id }
                let images = prepared.images.compactMap { source -> UIImage? in
                    let prefix = "data:image/jpeg;base64,"
                    guard source.hasPrefix(prefix), let data = Data(base64Encoded: String(source.dropFirst(prefix.count))) else { return nil }
                    return UIImage(data: data)
                }
                let mainTitle = custom?["title"].stringValue ?? ""
                let data = try CoverRenderer.render(images: images, title: mainTitle.isEmpty ? library.name : mainTitle,
                                                    subtitle: custom?["subtitle"].stringValue ?? "",
                                                    count: config["show_count"].boolValue ? prepared.total : nil)
                previews.append(.init(library: library, serverID: prepared.serverId, data: data))
            } catch {
                report(error, connection: connection)
                guard connection == session.connectionID, !Task.isCancelled else { return }
                self.error = "\(library.name)：\(session.describe(error))"
            }
        }
    }

    private func upload() async {
        guard let api = session.client, !busy else { return }
        let connection = session.connectionID
        busy = true
        error = nil
        defer { busy = false }
        do {
            for preview in previews where !uploaded.contains(preview.id) {
                guard connection == session.connectionID, !Task.isCancelled else { return }
                progress = "正在上传 \(preview.library.name)"
                let response: JSONValue = try await api.send("POST", "/api/emby/covers/upload", body: [
                    "library_id": .string(preview.id), "server_id": .string(preview.serverID),
                    "image": .string(preview.data.base64EncodedString())
                ])
                guard connection == session.connectionID, !Task.isCancelled else { return }
                guard response["uploaded"].boolValue else { throw APIError.invalidResponse }
                uploaded.insert(preview.id)
            }
            session.notice = .init(message: "封面已上传到 Emby。")
        } catch { report(error, connection: connection) }
    }

    private func report(_ failure: Error, connection: UUID) {
        guard connection == session.connectionID, !Task.isCancelled else { return }
        error = session.describe(failure)
        session.handle(failure)
    }
}

@MainActor
private enum CoverRenderer {
    static func render(images: [UIImage], title: String, subtitle: String, count: Int?) throws -> Data {
        guard !images.isEmpty else { throw APIError.invalidResponse }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1920, height: 1080), format: format)
        let image = renderer.image { rendererContext in
            let context = rendererContext.cgContext
            let colors = [UIColor(red: 0.05, green: 0.19, blue: 0.23, alpha: 1).cgColor,
                          UIColor(red: 0.18, green: 0.48, blue: 0.43, alpha: 1).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1]) {
                context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 1920, y: 1080), options: [])
            }
            let order = [2, 0, 4, 3, 1, 5, 8, 7, 6]
            for column in 0..<3 {
                context.saveGState()
                context.translateBy(x: CGFloat([1040, 1500, 2020][column]), y: column == 2 ? 420 : 575)
                context.rotate(by: 15.8 * .pi / 180)
                for row in 0..<3 {
                    let rect = CGRect(x: -185, y: CGFloat(-917 + row * 632), width: 410, height: 610)
                    context.saveGState()
                    UIBezierPath(roundedRect: rect, cornerRadius: 46).addClip()
                    let poster = images[order[column * 3 + row] % images.count]
                    let scale = max(rect.width / poster.size.width, rect.height / poster.size.height)
                    let size = CGSize(width: poster.size.width * scale, height: poster.size.height * scale)
                    poster.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2,
                                           width: size.width, height: size.height))
                    context.restoreGState()
                }
                context.restoreGState()
            }
            (title as NSString).draw(in: CGRect(x: 73, y: 427, width: 940, height: 190),
                                     withAttributes: [.font: UIFont.boldSystemFont(ofSize: 136), .foregroundColor: UIColor.white])
            (subtitle as NSString).draw(in: CGRect(x: 125, y: 635, width: 820, height: 300),
                                        withAttributes: [.font: UIFont.systemFont(ofSize: 50), .foregroundColor: UIColor.white])
            if let count {
                let text = count > 9999 ? "9999+" : String(count)
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 130),
                                                                 .foregroundColor: UIColor.white]
                let size = (text as NSString).size(withAttributes: attributes)
                UIColor(red: 0.32, green: 0.71, blue: 0.29, alpha: 1).setFill()
                UIBezierPath(roundedRect: CGRect(x: 40, y: 40, width: size.width + 60, height: size.height + 60),
                             cornerRadius: 42).fill()
                (text as NSString).draw(at: CGPoint(x: 70, y: 70), withAttributes: attributes)
            }
        }
        guard let data = image.jpegData(compressionQuality: 0.85), data.count <= 2 * 1024 * 1024 else {
            throw APIError.invalidResponse
        }
        return data
    }
}
