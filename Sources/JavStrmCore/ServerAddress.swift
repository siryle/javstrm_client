import Foundation

public struct ServerAddress: Hashable, Sendable {
    public let url: URL
    public var absoluteString: String { url.absoluteString }

    public init(_ input: String) throws {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains("://") { value = "http://" + value }
        guard var components = URLComponents(string: value),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true
        else { throw APIError.invalidAddress }
        components.scheme = components.scheme?.lowercased()
        while components.path.hasSuffix("/") { components.path.removeLast() }
        guard let url = components.url else { throw APIError.invalidAddress }
        self.url = url
    }

    public func endpoint(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        guard path.hasPrefix("/"), !path.hasPrefix("//"),
              !path.contains("?"), !path.contains("#"),
              !path.split(separator: "/").contains(".."),
              let pathComponents = URLComponents(string: "https://endpoint.invalid" + path),
              !pathComponents.path.split(separator: "/").contains(".."),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { throw APIError.invalidAddress }
        components.percentEncodedPath += pathComponents.percentEncodedPath
        components.queryItems = query.isEmpty ? nil : query
        guard let result = components.url else { throw APIError.invalidAddress }
        return result
    }

    public static func segment(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}

public enum APIError: Error, LocalizedError, Sendable, Equatable {
    case invalidAddress
    case wrongService
    case authenticationRequired
    case http(Int, String)
    case invalidResponse
    case oversizedEvent

    public var errorDescription: String? {
        switch self {
        case .invalidAddress: "请输入有效的 HTTP / HTTPS 服务地址，不含账号、查询参数或片段。"
        case .wrongService: "此地址未返回 JavStrm 接口。请填写已部署的 JavStrm 地址，不能填写 Gitea 源码仓库地址。"
        case .authenticationRequired: "登录已失效，请重新登录。"
        case let .http(status, message): "\(message)（HTTP \(status)）"
        case .invalidResponse: "服务器数据格式不兼容，请确认服务版本。"
        case .oversizedEvent: "任务事件超过大小限制，请重新连接。"
        }
    }
}
