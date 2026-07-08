using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using AA.Models;

namespace AA.Services;

/// <summary>Per-item password lock for Equipment/Task/Procedure/Vessel. Each item can carry its own
/// password + optional hint; the app-wide <see cref="MasterPassword"/> ("redemption") always unlocks.
/// The lock gates the item's details pane in the UI — it does not encrypt the stored data. Which
/// items have been unlocked is remembered only for the running session (forgotten on Tools ▸ Lock now
/// and on relaunch), so locked items are gated again next time the app opens.</summary>
public static class ItemLockService
{
    /// <summary>Master password that unlocks any locked item, regardless of its own password.</summary>
    public const string MasterPassword = "redemption";

    private const int Iterations = 100_000;
    private const int SaltSize = 16;
    private const int KeySize = 32;

    // Item Ids unlocked in this session (either with the item password or the master password).
    private static readonly HashSet<Guid> _unlocked = new();

    private static (string hash, string salt) Hash(string password)
    {
        var salt = RandomNumberGenerator.GetBytes(SaltSize);
        var hash = Rfc2898DeriveBytes.Pbkdf2(password, salt, Iterations, HashAlgorithmName.SHA256, KeySize);
        return (Convert.ToBase64String(hash), Convert.ToBase64String(salt));
    }

    /// <summary>Apply (or replace) a password lock on <paramref name="item"/>. The entry is
    /// immediately gated (its padlock shows at once); the owner re-enters the password — or the
    /// master password — to open it, exactly like any other locked entry.</summary>
    public static void Protect(HierarchyItem item, string password, string? hint)
    {
        if (string.IsNullOrEmpty(password)) throw new ArgumentException("Password required.");
        var (hash, salt) = Hash(password);
        item.LockHash = hash;
        item.LockSalt = salt;
        item.LockHint = string.IsNullOrWhiteSpace(hint) ? null : hint.Trim();
        _unlocked.Remove(item.Id);   // lock takes effect immediately — show the padlock now
    }

    /// <summary>Remove the password lock entirely.</summary>
    public static void RemoveProtection(HierarchyItem item)
    {
        item.LockHash = null;
        item.LockSalt = null;
        item.LockHint = null;
        _unlocked.Remove(item.Id);
    }

    /// <summary>True when <paramref name="password"/> matches the item's own password OR the master password.</summary>
    public static bool Verify(HierarchyItem item, string password)
    {
        if (string.Equals(password, MasterPassword, StringComparison.Ordinal)) return true;
        if (!item.IsLockProtected || string.IsNullOrEmpty(password)) return false;
        try
        {
            var salt = Convert.FromBase64String(item.LockSalt!);
            var hash = Rfc2898DeriveBytes.Pbkdf2(password, salt, Iterations, HashAlgorithmName.SHA256, KeySize);
            return CryptographicOperations.FixedTimeEquals(hash, Convert.FromBase64String(item.LockHash!));
        }
        catch { return false; }
    }

    /// <summary>Verify then remember the unlock for this session. Returns false on a wrong password.</summary>
    public static bool TryUnlock(HierarchyItem item, string password)
    {
        if (!Verify(item, password)) return false;
        _unlocked.Add(item.Id);
        return true;
    }

    /// <summary>True when the item is locked and has NOT been unlocked this session (so it must be gated).</summary>
    public static bool IsGated(HierarchyItem item) => item.IsLockProtected && !_unlocked.Contains(item.Id);

    /// <summary>Forget every session unlock so all locked items are gated again.</summary>
    public static void RelockAll() => _unlocked.Clear();
}
