import Foundation
import Security

/// Lưu khóa Gemini trong Keychain. Khóa cũ trong UserDefaults của App Group được chuyển sang một lần.
public enum GeminiKeyStore {
    private static let service = "com.hope.app.gemini"
    private static let account = "api-key"
    private static let legacyKey = "GEMINI_API_KEY"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public static var hasKey: Bool { load() != nil }

    public static func load() -> String? {
        migrateLegacyIfNeeded()
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { return nil }
        return key
    }

    @discardableResult
    public static func save(_ key: String) -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(key.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    public static func remove() {
        SecItemDelete(baseQuery as CFDictionary)
        UserDefaults(suiteName: SharedModelContainer.appGroupID)?.removeObject(forKey: legacyKey)
    }

    private static func migrateLegacyIfNeeded() {
        let defaults = UserDefaults(suiteName: SharedModelContainer.appGroupID)
        guard let old = defaults?.string(forKey: legacyKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !old.isEmpty else { return }
        if save(old) { defaults?.removeObject(forKey: legacyKey) }
    }
}
