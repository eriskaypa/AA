// Spec: 01 §6.5, DATA-215 (Keychain registry); ARCHITECTURE.md §6.3 (file-based login keychain, generic
//       passwords, no data-protection keychain, not synchronizable).
import Foundation
import Security

public enum SecretStoreError: Error, Sendable, Equatable, CustomStringConvertible {
    case keychain(OSStatus)
    public var description: String { "Keychain error \(self.status)" }
    var status: OSStatus { if case .keychain(let s) = self { return s }; return 0 }
}

public protocol SecretStore: Sendable {
    func read(service: String, account: String) throws -> Data?
    func write(_ data: Data, service: String, account: String) throws
    func delete(service: String, account: String) throws
}

/// Generic-password items in the login keychain. No `kSecUseDataProtectionKeychain` and no `kSecAttrAccessible`
/// (both need entitlements ad-hoc signing and `swift run` cannot provide → errSecMissingEntitlement -34018).
/// Not synced. The ACL is bound to the code signature, so a rebuild may show one "allow access" prompt again.
public struct KeychainSecretStore: SecretStore {
    public init() {}

    private func baseQuery(_ service: String, _ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func read(service: String, account: String) throws -> Data? {
        var q = baseQuery(service, account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status) }
        return result as? Data
    }

    public func write(_ data: Data, service: String, account: String) throws {
        let q = baseQuery(service, account)
        let update = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw SecretStoreError.keychain(update) }
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrSynchronizable as String] = false
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status) }
    }

    public func delete(service: String, account: String) throws {
        let status = SecItemDelete(baseQuery(service, account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecretStoreError.keychain(status) }
    }
}

/// Process-local secret store (tests, previews). Thread-safe.
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]
    /// Test hook: when true every call fails like a denied Keychain.
    public var failAll = false

    public init() {}

    private func key(_ s: String, _ a: String) -> String { s + "\u{0}" + a }

    public func read(service: String, account: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        if failAll { throw SecretStoreError.keychain(errSecAuthFailed) }
        return items[key(service, account)]
    }

    public func write(_ data: Data, service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        if failAll { throw SecretStoreError.keychain(errSecAuthFailed) }
        items[key(service, account)] = data
    }

    public func delete(service: String, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        if failAll { throw SecretStoreError.keychain(errSecAuthFailed) }
        items[key(service, account)] = nil
    }
}
