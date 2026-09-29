// Spec: 01 §I (DATA-090–094), §4.8, 04 §F / §7.8 (lock vectors, hint trimming, gate transitions);
//       ARCHITECTURE.md §6.3. Locks gate the UI; they never encrypt.
import Foundation
import Observation

@MainActor @Observable
public final class ItemLockService {
    /// Items unlocked this session (not cleared by reloads — ids are stable; forgotten on relaunch).
    public private(set) var unlockedIDs: Set<UUID> = []

    public init() {}

    /// Protected and not unlocked this session.
    public func isGated(_ item: HierarchyItem) -> Bool { item.isLockProtected && !unlockedIDs.contains(item.id) }

    /// New random salt + PBKDF2 hash; hint trimmed, blank → nil; the item is gated at once. An empty password
    /// changes nothing (the UI enforces the 4-character minimum first).
    public func protect(_ item: HierarchyItem, password: String, hint: String?) {
        guard !password.isEmpty else { return }
        let salt = PasswordHashing.newSalt()
        item.lockHash = NetBase64.encode(PasswordHashing.hash(password: password, salt: salt))
        item.lockSalt = NetBase64.encode(salt)
        item.lockHint = NetText.isBlank(hint) ? nil : NetText.trim(hint!)
        unlockedIDs.remove(item.id)
    }

    public func removeProtection(_ item: HierarchyItem) {
        item.lockHash = nil
        item.lockSalt = nil
        item.lockHint = nil
        unlockedIDs.remove(item.id)
    }

    /// PBKDF2 runs off the main actor; remembers the unlock on success.
    public func tryUnlock(_ item: HierarchyItem, password: String) async -> Bool {
        let hash = item.lockHash ?? "", salt = item.lockSalt ?? "", protected = item.isLockProtected
        let id = item.id
        let ok = await Task.detached(priority: .userInitiated) {
            PasswordHashing.isMaster(password) || (protected && ItemLockService.verify(password: password, hashBase64: hash, saltBase64: salt))
        }.value
        if ok { unlockedIDs.insert(id) }
        return ok
    }

    public func relock(_ id: UUID) { unlockedIDs.remove(id) }
    public func relockAll() { unlockedIDs.removeAll() }

    /// Master password (ordinal) → true; empty password or an unprotected item → false; else PBKDF2 compare in
    /// constant time; any decode error → false.
    public nonisolated static func verify(password: String, hashBase64: String, saltBase64: String) -> Bool {
        if PasswordHashing.isMaster(password) { return true }
        guard !password.isEmpty, !hashBase64.isEmpty, !saltBase64.isEmpty,
              let salt = NetBase64.decode(saltBase64), let stored = NetBase64.decode(hashBase64) else { return false }
        return ConstantTime.equals(PasswordHashing.hash(password: password, salt: salt), stored)
    }
}
