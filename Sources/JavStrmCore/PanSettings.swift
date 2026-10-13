import Foundation

public enum PanScanMethod: String, CaseIterable, Sendable {
    case alipay = "alipaymini"
    case wechat = "wechatmini"
    case android = "115android"
    case ios = "115ios"
    case web
    case ipad = "115ipad"
    case tv

    public var title: String {
        switch self {
        case .alipay: "支付宝"
        case .wechat: "微信"
        case .android: "115 安卓"
        case .ios: "115 iOS"
        case .web: "115 网页"
        case .ipad: "115 iPad"
        case .tv: "115 TV"
        }
    }
}

public struct PanLoginSession: Decodable, Sendable {
    public let id: String
    public let qrCode: String
    public let clientType: String?

    public var qrCodeData: Data? {
        let prefix = "data:image/png;base64,"
        guard qrCode.hasPrefix(prefix),
              let data = Data(base64Encoded: String(qrCode.dropFirst(prefix.count))),
              !data.isEmpty else { return nil }
        return data
    }
}

public enum PanLoginState: String, Decodable, Sendable {
    case waiting, scanned, authorized, expired, canceled

    public var isPending: Bool { self == .waiting || self == .scanned }

    public var message: String {
        switch self {
        case .waiting: "等待扫码"
        case .scanned: "已扫码，请在对应客户端确认登录"
        case .authorized: "登录成功"
        case .expired: "二维码已过期，请重新获取"
        case .canceled: "已取消授权，可以重新扫码"
        }
    }
}

public struct PanLoginStatus: Decodable, Sendable {
    public let state: PanLoginState
}

public enum PanDirectoryKind: String, CaseIterable, Identifiable, Sendable {
    case download, organize

    public var id: String { rawValue }
    public var title: String { self == .download ? "下载目录" : "整理目录" }
    public var endpoint: String {
        self == .download ? "/api/pan/directory" : "/api/pan/organize-directory"
    }
}

extension APIClient {
    public func beginPanLogin(method: PanScanMethod) async throws -> PanLoginSession {
        try await send("POST", "/api/pan/cookie/login", body: ["client_type": .string(method.rawValue)])
    }

    public func panLoginStatus(id: String) async throws -> PanLoginState {
        let status: PanLoginStatus = try await get("/api/pan/cookie/login/\(ServerAddress.segment(id))")
        return status.state
    }

    public func selectPanDirectory(id: String, kind: PanDirectoryKind) async throws -> PanDirectory {
        try await send("PUT", kind.endpoint, body: ["id": .string(id)])
    }

    public func clearPanDirectory(kind: PanDirectoryKind) async throws {
        try await discard("DELETE", kind.endpoint)
    }

    public func logoutPan() async throws {
        try await discard("DELETE", "/api/pan/cookie")
    }
}
