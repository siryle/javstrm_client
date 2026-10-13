import Foundation
import Security
import JavStrmCore

enum CredentialStore {
    private static let service = "app.javstrm.ios.session"

    static func load(for server: String) -> SessionToken? {
        var query = baseQuery(server)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = try? JSONDecoder().decode(SessionToken.self, from: data),
              token.isValid else { return nil }
        return token
    }

    static func save(_ token: SessionToken?, for server: String) throws {
        guard let token, token.isValid else { try delete(for: server); return }
        let data = try JSONEncoder().encode(token)
        let query = baseQuery(server)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw StoreError(status: status) }
    }

    static func delete(for server: String) throws {
        let status = SecItemDelete(baseQuery(server) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError(status: status) }
    }

    private static func baseQuery(_ server: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: server]
    }

    private struct StoreError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "无法保存安全会话（Keychain \(status)）。" }
    }
}
