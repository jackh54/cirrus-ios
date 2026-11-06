import Foundation
import JMAPKit
import Security

/// One signed-in server login (a user can belong to several mailboxes; each is a JMAP account under this login).
struct Login: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var credentials: Credentials
}

/// Logins live in the Keychain only (never UserDefaults): one generic-password item per login, holding the JSON credentials.
enum LoginStore {
    private static let service = "org.jackh54.Cirrus.login"

    static func load() -> [Login] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let id = item[kSecAttrAccount as String] as? String, let data = item[kSecValueData as String] as? Data,
                  let credentials = try? JSONDecoder().decode(Credentials.self, from: data) else { return nil }
            return Login(id: id, credentials: credentials)
        }
        .sorted { $0.credentials.email < $1.credentials.email }
    }

    static func save(_ login: Login) throws {
        let data = try JSONEncoder().encode(login.credentials)
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: login.id,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(match as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = match
            add[kSecValueData as String] = data
            // Readable after first unlock so background refresh can sync while the phone is locked.
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    static func delete(id: String) {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
        ]
        SecItemDelete(match as CFDictionary)
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "The Keychain refused to save the login (error \(status))." }
}
