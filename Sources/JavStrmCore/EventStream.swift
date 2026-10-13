import Foundation

public struct ServerEvent: Sendable, Equatable {
    public let name: String
    public let data: String
}

public struct EventStreamParser: Sendable {
    private var name = ""
    private var lines: [String] = []
    private var size = 0
    private let limit: Int

    public init(limit: Int = 8 * 1024 * 1024) { self.limit = limit }

    public mutating func consume(_ line: String) throws -> ServerEvent? {
        if line.isEmpty {
            defer { name = ""; lines = []; size = 0 }
            guard !lines.isEmpty else { return nil }
            return ServerEvent(name: name.isEmpty ? "message" : name, data: lines.joined(separator: "\n"))
        }
        if line.hasPrefix(":") { return nil }
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let key = String(parts[0])
        var value = parts.count > 1 ? String(parts[1]) : ""
        if value.hasPrefix(" ") { value.removeFirst() }
        if key == "event" { name = value }
        if key == "data" {
            size += value.utf8.count
            guard size <= limit else { throw APIError.oversizedEvent }
            lines.append(value)
        }
        return nil
    }
}
