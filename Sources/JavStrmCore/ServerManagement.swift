import Foundation

extension JSONValue {
    public var objectValue: [String: JSONValue] {
        if case .object(let value) = self { return value }
        return [:]
    }

    public var arrayValue: [JSONValue] {
        if case .array(let value) = self { return value }
        return []
    }

    public var stringValue: String {
        if case .string(let value) = self { return value }
        return ""
    }

    public var boolValue: Bool {
        if case .bool(let value) = self { return value }
        return false
    }

    public var numberValue: Double {
        if case .number(let value) = self { return value }
        return 0
    }

    public subscript(key: String) -> JSONValue {
        get { objectValue[key] ?? .null }
        set {
            var object = objectValue
            object[key] = newValue
            self = .object(object)
        }
    }
}

public struct SettingChoice: Identifiable, Sendable {
    public let id: String
    public let title: String
    public init(_ id: String, _ title: String) { self.id = id; self.title = title }
}

public indirect enum SettingFieldKind: Sendable {
    case text, secret, multiline, number, toggle, localDirectory, panDirectory
    case choices([SettingChoice])
    case object([SettingField])
    case list([SettingField])
}

public struct SettingField: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let kind: SettingFieldKind
    public let hint: String
    public let initial: JSONValue?

    public init(_ id: String, _ title: String, _ kind: SettingFieldKind = .text,
                hint: String = "", initial: JSONValue? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.hint = hint
        self.initial = initial
    }

    public var defaultValue: JSONValue {
        if let initial { return initial }
        switch kind {
        case .toggle: return .bool(false)
        case .number: return .number(0)
        case .list: return .array([])
        case .object(let fields): return .object(Dictionary(uniqueKeysWithValues: fields.map { ($0.id, $0.defaultValue) }))
        case .panDirectory: return .object(["id": .string(""), "name": .string(""), "path": .string("")])
        case .choices(let choices): return .string(choices.first?.id ?? "")
        default: return .string("")
        }
    }
}

public enum ServerSetting: String, CaseIterable, Identifiable, Sendable {
    case network, scraping, organize
    case localOrganize = "local-organize"
    case strmScrape = "strm-scrape"
    case quickStrm = "quick-strm"
    case subscription, emby
    case embyCover = "emby/cover"
    case emptyDirectory = "empty-directory"

    public var id: String { rawValue }
    public var endpoint: String { "/api/settings/\(rawValue)" }
    public var title: String {
        switch self {
        case .network: "网络代理"
        case .scraping: "刮削数据源"
        case .organize: "网盘与 CloudDrive2 整理"
        case .localOrganize: "本地媒体整理"
        case .strmScrape: "STRM 刮削与字幕"
        case .quickStrm: "STRM 快速生成"
        case .subscription: "订阅与下载偏好"
        case .emby: "Emby 集成"
        case .embyCover: "Emby 媒体库封面"
        case .emptyDirectory: "网盘空目录清理"
        }
    }

    public var startEndpoint: String? {
        switch self {
        case .organize: "/api/organize"
        case .localOrganize: "/api/local/organize"
        case .strmScrape: "/api/strm-scrape"
        case .quickStrm: "/api/quick-strm/generate"
        case .emby: "/api/settings/emby/actors/sync"
        case .emptyDirectory: "/api/pan/organize-directory/empty"
        default: nil
        }
    }

    public var startTitle: String {
        switch self {
        case .quickStrm: "保存并生成 STRM"
        case .strmScrape: "保存并开始刮削"
        case .emby: "保存并补全演员"
        case .emptyDirectory: "保存并清理空目录"
        default: "保存并开始整理"
        }
    }

    private var schedule: [SettingField] {
        [.init("schedule_enabled", "每日定时运行", .toggle),
         .init("schedule_time", "运行时间", hint: "服务器本地时间，格式 HH:MM", initial: .string("00:00"))]
    }

    public var fields: [SettingField] {
        let preferences = [SettingChoice("preferred", "优先"), .init("required", "必须"), .init("any", "不限")]
        switch self {
        case .network:
            return [.init("enabled", "启用代理", .toggle),
                    .init("url", "代理地址", hint: "支持 HTTP、HTTPS、SOCKS5")]
        case .scraping: return []
        case .organize:
            return [.init("mode", "整理方式", .choices([.init("pan", "115 网盘"), .init("clouddrive2", "CloudDrive2")])),
                    .init("source", "网盘来源目录", .panDirectory),
                    .init("destination", "网盘目标目录", .panDirectory),
                    .init("local_source", "CloudDrive2 来源", .localDirectory),
                    .init("local_destination", "CloudDrive2 目标", .localDirectory),
                    .init("strm_enabled", "整理后生成 STRM", .toggle),
                    .init("strm_directory", "STRM 输出目录", .localDirectory),
                    .init("minimum_size", "最小文件大小（字节）", .number),
                    .init("local_schedule_enabled", "每日定时整理 CloudDrive2", .toggle),
                    .init("local_schedule_time", "定时整理时间", hint: "HH:MM", initial: .string("00:00"))]
        case .localOrganize:
            return [.init("source", "来源目录", .localDirectory),
                    .init("destination", "目标目录", .localDirectory),
                    .init("minimum_size", "最小文件大小（字节）", .number)] + schedule
        case .strmScrape:
            return [.init("directory", "STRM 目录", .localDirectory),
                    .init("scrape_subtitles", "下载字幕", .toggle)] + schedule
        case .quickStrm:
            return [.init("proxy_enabled", "使用 JavStrm 播放代理", .toggle),
                    .init("playback_mode", "播放模式", .choices([.init("redirect", "重定向"), .init("proxy", "代理")])),
                    .init("address", "JavStrm 播放地址", hint: "设备可以访问的 HTTP(S) 地址"),
                    .init("clean_strm", "清理失效 STRM", .toggle),
                    .init("clean_dirs", "清理空目录", .toggle),
                    .init("clean_media", "清理关联元数据", .toggle),
                    .init("groups", "生成配置组", .list([
                        .init("id", "配置标识"), .init("name", "名称"),
                        .init("source", "115 来源目录", .panDirectory),
                        .init("directory", "输出目录", .localDirectory),
                        .init("prefix", "播放路径前缀"),
                        .init("overwrite", "覆盖已有文件", .toggle),
                        .init("download_metadata", "下载元数据", .toggle),
                        .init("scrape_after_generate", "生成后刮削", .toggle),
                        .init("schedule_enabled", "启用定时运行", .toggle),
                        .init("schedule_cron", "运行计划", hint: "五位 Cron 表达式", initial: .string("0 3 * * *"))
                    ]))]
        case .subscription:
            return [.init("movie_auto_download", "作品默认自动下载", .toggle),
                    .init("actor_auto_download", "演员新作自动下载", .toggle),
                    .init("check_time", "每天检查时间", hint: "HH:MM"),
                    .init("preferences", "磁力偏好", .object([
                        .init("subtitle", "中文字幕", .choices(preferences)),
                        .init("hd", "高清", .choices(preferences)),
                        .init("uncensored", "破解资源", .choices(preferences + [.init("exclude", "排除")]))
                    ])),
                    .init("download", "下载设置", .object([.init("auto_switch", "自动切换资源", .toggle)]))]
        case .emptyDirectory: return schedule
        case .embyCover:
            return [.init("sort_by", "取图排序", .choices([.init("Random", "随机"), .init("DateCreated", "最近入库"),
                                                       .init("PremiereDate", "最近上映")])),
                    .init("show_count", "显示媒体数量角标", .toggle),
                    .init("monitor_enabled", "Emby 入库后自动更新", .toggle)] + schedule
        case .emby:
            return [.init("enabled", "启用 Emby", .toggle),
                    .init("server_url", "服务器地址"), .init("api_key", "API Key", .secret),
                    .init("media_path", "Emby 媒体库路径"),
                    .init("playback_probe_enabled", "后台 STRM 预探测", .toggle),
                    .init("reverse_proxy_enabled", "启用反向代理", .toggle),
                    .init("reverse_proxy_port", "反向代理端口", .number),
                    .init("reverse_proxy_local_mappings", "反向代理本地映射", .multiline, hint: "每行一组：本地路径#Emby 路径"),
                    .init("reverse_proxy_p115_mappings", "反向代理 115 映射", .multiline),
                    .init("reverse_proxy_strm_mappings", "反向代理 STRM 映射", .multiline),
                    .init("sync_actors", "自动补全演员", .toggle),
                    .init("overwrite_actors", "覆盖已有演员信息", .toggle),
                    .init("actor_schedule_enabled", "每日定时补全演员", .toggle),
                    .init("actor_schedule_time", "演员补全时间", hint: "HH:MM"),
                    .init("sync_delete_enabled", "启用同步删除", .toggle),
                    .init("sync_delete_source", "同时删除源文件", .toggle),
                    .init("sync_delete_local_mappings", "删除本地映射", .multiline),
                    .init("sync_delete_p115_mappings", "删除 115 映射", .multiline),
                    .init("sync_delete_p115_force", "强制删除 115 文件", .toggle),
                    .init("sync_delete_mappings", "删除路径映射", .list([
                        .init("local_path", "本地路径", .localDirectory), .init("emby_path", "Emby 路径")
                    ])),
                    .init("favorite_transfer_enabled", "启用收藏转移", .toggle),
                    .init("favorite_transfer_groups", "收藏转移配置组", .list([
                        .init("local_mappings", "本地映射", .multiline),
                        .init("strm_mappings", "STRM 映射", .multiline),
                        .init("target_mapping", "目标映射", .multiline,
                              hint: "115 目录 ID#本地目录#Emby 目录[#STRM 前缀]")
                    ]))]
        }
    }
}

public enum ManagementError: Error, LocalizedError, Sendable {
    case invalidFileOperation, invalidArchive, invalidSetting
    public var errorDescription: String? {
        switch self {
        case .invalidFileOperation: "请选择 1 到 100 个项目，并填写有效的目标目录或文件名。"
        case .invalidArchive: "配置文件格式或版本不受支持。"
        case .invalidSetting: "服务端返回的设置格式不正确。"
        }
    }
}

public enum FileSource: String, CaseIterable, Identifiable, Sendable {
    case local, pan
    public var id: String { rawValue }
    public var title: String { self == .pan ? "115 网盘" : "服务端本地" }
    public var root: String { self == .pan ? "0" : "/" }
}

public enum FileAction: String, CaseIterable, Identifiable, Sendable {
    case copy, move, rename, delete
    public var id: String { rawValue }
    public var title: String {
        switch self { case .copy: "复制"; case .move: "移动"; case .rename: "重命名"; case .delete: "删除" }
    }
}

public struct FileOperation: Sendable {
    public let source: FileSource
    public let action: FileAction
    public let ids: [String]
    public let directory: String
    public let destination: String
    public let name: String
    public let accountID: String

    public init(source: FileSource, action: FileAction, ids: [String], directory: String,
                destination: String = "", name: String = "", accountID: String = "") {
        self.source = source; self.action = action; self.ids = ids; self.directory = directory
        self.destination = destination; self.name = name; self.accountID = accountID
    }

    public var isValid: Bool {
        guard !directory.isEmpty, (1...100).contains(ids.count), Set(ids).count == ids.count,
              ids.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 4096 }),
              directory.utf8.count <= 4096, destination.utf8.count <= 4096,
              source == .local || !accountID.isEmpty else { return false }
        switch action {
        case .copy, .move: return !destination.isEmpty
        case .rename:
            return ids.count == 1 && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && name != "." && name != ".." && name.utf8.count <= 255
                && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
        case .delete: return true
        }
    }

    public var body: [String: JSONValue] {
        var value: [String: JSONValue] = ["action": .string(action.rawValue), "ids": .array(ids.map(JSONValue.string)),
                                        "directory": .string(directory)]
        if action == .copy || action == .move { value["destination"] = .string(destination) }
        if action == .rename { value["name"] = .string(name) }
        if source == .pan { value["account_id"] = .string(accountID) }
        return value
    }
}

public struct FileOperationResult: Decodable, Sendable {
    public struct Failure: Decodable, Sendable {
        public let id: String
        public let message: String
    }
    public let completed: [String]
    public let failed: [Failure]
}

public struct EmbyCoverLibrary: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let collectionType: String
}

public struct EmbyCoverLibraries: Decodable, Sendable {
    public let libraries: [EmbyCoverLibrary]
    public let serverId: String
}

public struct EmbyCoverPrepared: Decodable, Sendable {
    public let library: EmbyCoverLibrary
    public let serverId: String
    public let images: [String]
    public let total: Int
}

public enum WorkflowHistoryKind: String, CaseIterable, Identifiable, Sendable {
    case organize
    case strmScrape = "strm-scrape"
    case strmGenerate = "strm-generate"
    case actorSync = "emby-actor-sync"
    case emptyDirectory = "empty-directory"
    case syncDelete = "sync-delete"
    case favoriteTransfer = "favorite-transfer"
    case strmProbe = "strm-probe"
    public var id: String { rawValue }
    public var endpoint: String { "/api/tasks/\(rawValue)/history" }
    public var title: String {
        switch self {
        case .organize: "媒体整理"
        case .strmScrape: "STRM 刮削"
        case .strmGenerate: "STRM 生成"
        case .actorSync: "Emby 演员补全"
        case .emptyDirectory: "空目录清理"
        case .syncDelete: "Emby 同步删除"
        case .favoriteTransfer: "Emby 收藏转移"
        case .strmProbe: "STRM 预探测"
        }
    }
}

public struct WorkflowHistoryPage: Decodable, Sendable {
    public let items: [ServerTask]?
    public let total: Int
    public let page: Int
    public let hasMore: Bool
}

public struct QuickJobResultsPage: Decodable, Sendable {
    public let items: [WorkflowResult]?
    public let total: Int
    public let page: Int
    public let hasMore: Bool
}

extension APIClient {
    public func serverSettings(_ setting: ServerSetting) async throws -> JSONValue {
        let value: JSONValue = try await get(setting.endpoint)
        try validateSettings(value, setting: setting)
        return value
    }

    public func saveServerSettings(_ setting: ServerSetting, value: JSONValue) async throws -> JSONValue {
        try validateSettings(value, setting: setting)
        let result: JSONValue = try await sendValue("PUT", setting.endpoint, value: value)
        try validateSettings(result, setting: setting)
        return result
    }

    private func validateSettings(_ value: JSONValue, setting: ServerSetting) throws {
        if setting == .scraping {
            guard case .array = value else { throw ManagementError.invalidSetting }
        } else {
            guard case .object = value else { throw ManagementError.invalidSetting }
        }
    }

    public func operateFiles(_ operation: FileOperation) async throws -> FileOperationResult {
        guard operation.isValid else { throw ManagementError.invalidFileOperation }
        return try await send("POST", "/api/files/\(operation.source.rawValue)/operations", body: operation.body)
    }

    public func exportConfiguration() async throws -> JSONValue {
        try await get("/api/settings/export")
    }

    public func importConfiguration(_ archive: JSONValue) async throws -> JSONValue {
        try validateConfigurationArchive(archive)
        return try await sendValue("POST", "/api/settings/import", value: archive)
    }
}

public func validateConfigurationArchive(_ archive: JSONValue) throws {
    guard ["javstrm-settings", "miyabi-settings"].contains(archive["format"].stringValue),
          archive["version"] == .number(1),
          case .array = archive["settings"], case .array = archive["subscriptions"] else {
        throw ManagementError.invalidArchive
    }
    if archive["browser"] != .null {
        guard ["system", "light", "dark"].contains(archive["browser"]["theme"].stringValue),
              case .bool = archive["browser"]["nsfw_mode"] else { throw ManagementError.invalidArchive }
    }
}
