import Foundation

public enum WireJSON {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

public enum JSONValue: Codable, Sendable, Equatable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue])
    case array([JSONValue]), null

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let array = try? value.decode([JSONValue].self) { self = .array(array) }
        else { self = .object(try value.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case let .string(item): try value.encode(item)
        case let .number(item): try value.encode(item)
        case let .bool(item): try value.encode(item)
        case let .object(item): try value.encode(item)
        case let .array(item): try value.encode(item)
        case .null: try value.encodeNil()
        }
    }

    public var text: String {
        switch self {
        case let .string(value): value
        case let .number(value): value.formatted()
        case let .bool(value): value ? "true" : "false"
        default: ""
        }
    }
}

public struct AccessConfig: Decodable, Sendable {
    public let enabled: Bool
    public let authenticated: Bool
    public let username: String?
}

public struct LoginResult: Decodable, Sendable {
    public let success: Bool
    public let username: String?
    public let expiresAt: Int?
}

public struct NamedEntity: Decodable, Sendable, Hashable {
    public let id: String?
    public let name: String
}

public struct LibraryTab: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let directory: String
}

public struct LibraryTag: Decodable, Sendable {
    public let id: Int
    public let name: String
}

public struct LibraryMovie: Decodable, Identifiable, Sendable {
    public let id: Int
    public let code: String
    public let title: String
    public let javdbId: String?
    public let cover: String?
    public let poster: String?
    public let fanart: String?
    public let releaseDate: String?
    public let duration: Int
    public let rating: Double
    public let maker: NamedEntity?
    public let series: NamedEntity?
    public let director: NamedEntity?
    public let actors: [NamedEntity]?
    public let tags: [LibraryTag]?
    public let scrapeStatus: String
    public let watched: Bool
    public var artwork: String { firstArtwork(poster, cover, fanart) }
    public var landscapeArtwork: String { firstArtwork(fanart, cover, poster) }
    public var cropArtwork: String { firstArtwork(fanart, cover) }

    private func firstArtwork(_ sources: String?...) -> String {
        sources.compactMap { $0 }.first { !$0.isEmpty } ?? ""
    }
}

public struct LibraryPage: Decodable, Sendable {
    public let movies: [LibraryMovie]?
    public let total: Int
    public let page: Int
    public let hasMore: Bool
}

public struct DiscoverActor: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let nameZht: String?
    public let avatar: String?
    public var displayName: String { nameZht.flatMap { $0.isEmpty ? nil : $0 } ?? name }
}

public struct DiscoverTag: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let nameZht: String?
    public var displayName: String { nameZht.flatMap { $0.isEmpty ? nil : $0 } ?? name }
}

public struct DiscoverMovie: Decodable, Identifiable, Sendable {
    public let id: String
    public let libraryId: Int?
    public let code: String
    public let title: String
    public let originTitle: String?
    public let releaseDate: String?
    public let duration: Int
    public let rating: Double
    public let thumbnail: String?
    public let cover: String?
    public let magnetsCount: Int?
    public let hasSubtitle: Bool?
    public let actors: [DiscoverActor]?
    public let tags: [DiscoverTag]?
    public let maker: NamedEntity?
    public let series: NamedEntity?
    public let director: NamedEntity?
    public let state: String?
    public let zone: String?
    public var artwork: String { cover ?? thumbnail ?? "" }
}

public struct Magnet: Decodable, Identifiable, Sendable {
    public var id: String { hash }
    public let hash: String
    public let name: String
    public let size: Int64
    public let hasSubtitle: Bool
    public let hd: Bool
    public let filesCount: Int
    public let uri: String
}

public struct Subscription: Decodable, Identifiable, Sendable {
    public let id: Int
    public let kind: String
    public let targetId: String
    public let code: String
    public let title: String
    public let cover: String
    public let autoDownload: Bool
    public let status: String
    public let checks: Int
    public let error: String?
    public let nextCheckAt: String?
}

public struct ServerTask: Decodable, Identifiable, Sendable {
    public let id: Int
    public let type: String
    public let status: String
    public let progress: Double
    public let paused: Bool?
    public let error: String?
    public let createdAt: String
    public let updatedAt: String
    public let code: String?
    public let origin: String?
    public let source: [String: JSONValue]?
    public let scan: [String: JSONValue]?
    public let organize: [String: JSONValue]?
    public let strmGenerate: [String: JSONValue]?
    public let strmScrape: [String: JSONValue]?
    public let batch: [String: JSONValue]?
    public let embyActorSync: [String: JSONValue]?
    public let emptyDirectory: [String: JSONValue]?
    public let favoriteTransfer: [String: JSONValue]?
    public let strmProbe: [String: JSONValue]?
    public let syncDelete: [String: JSONValue]?

    public var isActive: Bool { status == "running" || status == "queued" }
    public var fraction: Double { min(1, max(0, progress / 100)) }
    public var canPause: Bool {
        isActive && ["organize", "strm_scrape", "emby_actor_sync", "empty_directory"].contains(type)
    }
    public var canTerminate: Bool { canPause }
    public var details: [String: JSONValue] {
        // The server includes an empty scan object even for other workflow types.
        switch type {
        case "scan": scan ?? [:]
        case "organize": organize ?? [:]
        case "strm_generate": strmGenerate ?? [:]
        case "strm_scrape": strmScrape ?? [:]
        case "subscription_batch": batch ?? [:]
        case "emby_actor_sync": embyActorSync ?? [:]
        case "empty_directory": emptyDirectory ?? [:]
        case "favorite_transfer": favoriteTransfer ?? [:]
        case "strm_probe": strmProbe ?? [:]
        case "sync_delete": syncDelete ?? [:]
        default: [:]
        }
    }
    public var title: String {
        switch type {
        case "scan": "媒体库扫描"
        case "organize": "媒体整理"
        case "strm_generate": "STRM 生成"
        case "strm_scrape": "元数据刮削"
        case "subscription_batch": "订阅批量入库"
        case "emby_actor_sync": "Emby 演员同步"
        case "empty_directory": "空目录清理"
        case "favorite_transfer": "收藏转移"
        case "strm_probe": "播放检查"
        case "sync_delete": "Emby 同步删除"
        default: type
        }
    }
}

public struct TaskRevisions: Decodable, Sendable, Equatable {
    public let library: Int
    public let offline: Int
    public let monitor: Int
}

public struct OfflineTask: Decodable, Identifiable, Sendable {
    public var id: Int { taskId }
    public let taskId: Int
    public let code: String
    public let javdbId: String
    public let status: String
    public let phase: String
    public let progress: Double
    public let error: String?
    public var isActive: Bool { status == "running" || status == "queued" }
}

public struct OfflineActivity: Decodable, Sendable {
    public let tasks: [OfflineTask]?
}

public struct QuickJob: Decodable, Identifiable, Sendable {
    public let id: String
    public let status: String
    public let stage: String
    public let files: Int
    public let processed: Int
    public let generated: Int
    public let skipped: Int
    public let failed: Int
    public let errors: [String]?
    public let startedAt: String
    public var fraction: Double {
        files > 0 ? min(1, Double(processed) / Double(files)) : (status == "done" ? 1 : 0)
    }
}

public struct PanDirectory: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let path: String?
}

public struct SpaceAmount: Decodable, Sendable {
    public let bytes: Int64
    public let formatted: String
}

public struct PanAccount: Decodable, Sendable {
    public struct Space: Decodable, Sendable {
        public let total: SpaceAmount
        public let used: SpaceAmount
        public let remaining: SpaceAmount
    }
    public let id: String
    public let name: String
    public let level: String
    public let space: Space?
}

public struct PanStatus: Decodable, Sendable {
    public let connected: Bool
    public let account: PanAccount?
    public let directory: PanDirectory?
    public let organizeDirectory: PanDirectory?
}

public struct ManagedFile: Decodable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let isDirectory: Bool
    public let size: Int64?
}

public struct LocalFiles: Decodable, Sendable {
    public let files: [ManagedFile]?
    public let path: String
    public let parent: String?
}

public struct PanFiles: Decodable, Sendable {
    public let files: [ManagedFile]?
    public let path: [NamedEntity]?
    public let total: Int
    public let hasMore: Bool
}

public struct LogEntry: Decodable, Identifiable, Sendable {
    public var id: String { "\(time)|\(level)|\(component)|\(message)" }
    public let time: String
    public let level: String
    public let message: String
    public let component: String
}
