import Foundation

public struct TaskDetailField: Identifiable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let value: String
}

private let detailLabels = [
    "stage": "当前阶段", "current_path": "当前路径", "current_code": "当前番号",
    "files": "文件总数", "files_scanned": "已扫描文件", "directories_scanned": "已扫描目录",
    "directories_discovered": "发现目录", "video_files": "视频文件", "matched_files": "匹配文件",
    "unmatched_files": "未匹配文件", "movies": "作品", "removed_files": "移除文件",
    "removed_movies": "移除作品", "metadata_total": "元数据总数", "metadata_completed": "完成元数据",
    "moved": "已移动", "renamed": "已重命名", "skipped": "已跳过", "deleted": "已删除",
    "failed": "失败", "generated": "已生成", "matched": "已识别", "written": "已写入",
    "subtitle_missing": "缺少字幕", "total": "总数", "processed": "已处理",
    "submitted": "已提交", "imported": "已入库", "waiting": "等待资源",
    "scanned": "已扫描", "missing": "缺失", "uploaded": "已上传", "removed": "已移除",
    "succeeded": "成功", "directories": "目录总数", "cleaned_strm": "清理 STRM",
    "cleaned_dirs": "清理目录", "cleaned_media": "清理媒体文件",
    "source_path": "源文件", "target_path": "目标文件", "path": "STRM 文件",
    "strm_paths": "媒体文件", "metadata_paths": "元数据", "directory_path": "目录",
    "emby_path": "Emby 路径", "miyabi_path": "JavStrm 路径", "p115_path": "115 路径",
    "item_id": "媒体项 ID", "source_id": "媒体源 ID", "person_id": "演员 ID",
    "code": "番号", "name": "名称",
    "error": "错误信息"
]

private let stageLabels = [
    "queued": "等待处理", "running": "处理中", "preparing": "准备中",
    "scanning": "扫描中", "reconciling": "核对中", "scraping": "刮削中",
    "artwork": "写入元数据", "organizing": "整理中", "generating": "生成中",
    "cleaning": "清理中", "transferring": "转移中", "refreshing": "刷新中",
    "probing": "检查中", "done": "已完成", "failed": "失败"
]

extension JSONValue {
    public var detailText: String {
        switch self {
        case let .array(values):
            values.map(\.detailText).filter { !$0.isEmpty }.joined(separator: "\n")
        case let .object(values):
            values.keys.sorted().compactMap { key in
                guard let text = values[key]?.detailText, !text.isEmpty else { return nil }
                return "\(detailLabels[key] ?? key)：\(text)"
            }.joined(separator: "\n")
        case let .bool(value):
            value ? "是" : "否"
        default:
            text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

extension ServerTask {
    public var detailFields: [TaskDetailField] {
        let preferred = ["stage", "current_code", "current_path", "total", "processed"]
        let keys = preferred.filter { details[$0] != nil }
            + details.keys.filter { !preferred.contains($0) && !["results", "failures"].contains($0) }.sorted()
        var fields = keys.compactMap { key -> TaskDetailField? in
            guard let value = details[key], !value.detailText.isEmpty else { return nil }
            let text = key == "stage" ? stageLabels[value.text] ?? value.detailText : value.detailText
            return TaskDetailField(id: key, label: detailLabels[key] ?? key, value: text)
        }
        if case let .object(directory)? = source?["directory"] {
            let path = directory["path"]?.detailText ?? ""
            let name = directory["name"]?.detailText ?? ""
            if !path.isEmpty || !name.isEmpty {
                fields.insert(TaskDetailField(id: "source", label: "源目录",
                                              value: path.isEmpty ? name : path), at: 0)
            }
        }
        if origin == "local_media" {
            fields.insert(TaskDetailField(id: "origin", label: "来源", value: "本地媒体"), at: 0)
        }
        return fields
    }

    public var resultsPath: String? {
        switch type {
        case "organize", "strm_scrape", "strm_generate", "emby_actor_sync",
             "empty_directory", "favorite_transfer", "strm_probe", "sync_delete":
            return "/api/tasks/\(type.replacingOccurrences(of: "_", with: "-"))/\(id)/results"
        default:
            return nil
        }
    }

    public var embeddedResults: [WorkflowResult] {
        let key = type == "subscription_batch" ? "failures" : "results"
        guard case let .array(items)? = details[key] else { return [] }
        return items.compactMap {
            guard case var .object(fields) = $0 else { return nil }
            if key == "failures" { fields["status"] = .string("failed") }
            return WorkflowResult(fields: fields)
        }
    }
}

public struct WorkflowResultsPage: Decodable, Sendable {
    public let taskId: Int
    public let items: [WorkflowResult]?
    public let total: Int
    public let page: Int
    public let hasMore: Bool
}

public struct WorkflowResult: Decodable, Sendable, Equatable {
    public let fields: [String: JSONValue]

    public init(fields: [String: JSONValue]) {
        self.fields = fields
    }

    public init(from decoder: Decoder) throws {
        fields = try decoder.singleValueContainer().decode([String: JSONValue].self)
    }

    public var status: String { fields["status"]?.text ?? "" }
    public var title: String { fields["code"]?.text ?? fields["name"]?.text ?? "" }
    public var error: String { fields["error"]?.detailText ?? "" }

    public var detailFields: [TaskDetailField] {
        let preferred = [
            "source_path", "target_path", "path", "strm_paths", "metadata_paths", "directory_path",
            "emby_path", "miyabi_path", "p115_path", "item_id", "source_id"
        ]
        let hidden = ["status", "code", "name", "error", "kind", "action"]
        let keys = preferred.filter { fields[$0] != nil }
            + fields.keys.filter { !preferred.contains($0) && !hidden.contains($0) }.sorted()
        return keys.compactMap { key in
            guard let value = fields[key]?.detailText, !value.isEmpty else { return nil }
            var label = detailLabels[key] ?? key
            if key == "source_path" {
                switch fields["action"]?.text {
                case "delete": label = "删除文件"
                case "delete_directory": label = "删除目录"
                default:
                    if fields["kind"]?.text == "strm_probe" { label = "STRM 文件" }
                }
            }
            if key == "target_path", fields["kind"]?.text == "favorite_transfer" { label = "目标 STRM" }
            return TaskDetailField(id: key, label: label, value: value)
        }
    }
}
