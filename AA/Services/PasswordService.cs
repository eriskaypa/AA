using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

namespace AA.Services;

/// <summary>App-wide password used to lock/unlock <see cref="AA.Models.Container"/> rich-text.
/// One password protects every lockable container; the in-memory <see cref="CurrentPassword"/>
/// lives only for the running session, so closing the app re-locks everything until the
/// user unlocks again. Passwords are stored as PBKDF2 hashes in settings.json; the rich-text
/// itself is encrypted with AES-256-CBC + HMAC-SHA256 (encrypt-then-MAC) using keys derived
/// from the password + a per-app salt.</summary>
public static class PasswordService
{
    private const int Iterations = 100_000;
    private const int SaltSize = 16;
    private const int KeySize = 32;
    private const int IvSize = 16;
    private const int HmacSize = 32;
    private const string Prefix = "enc:";

    private static byte[]? _salt;
    private static string? _passwordHashBase64;
    private static string? _currentPassword;

    public static bool HasPassword => !string.IsNullOrEmpty(_passwordHashBase64) && _salt != null;
    public static bool IsUnlocked => _currentPassword != null;
    public static string? CurrentPassword => _currentPassword;

    public static void LoadFrom(string? hash, string? saltBase64)
    {
        _passwordHashBase64 = string.IsNullOrEmpty(hash) ? null : hash;
        _salt = string.IsNullOrEmpty(saltBase64) ? null : Convert.FromBase64String(saltBase64);
        _currentPassword = null;
    }

    public static (string hash, string salt) SetPassword(string password)
    {
        if (string.IsNullOrEmpty(password)) throw new ArgumentException("Password required.");
        var salt = RandomNumberGenerator.GetBytes(SaltSize);
        var hash = Rfc2898DeriveBytes.Pbkdf2(password, salt, Iterations, HashAlgorithmName.SHA256, KeySize);
        _salt = salt;
        _passwordHashBase64 = Convert.ToBase64String(hash);
        _currentPassword = password;
        return (_passwordHashBase64, Convert.ToBase64String(salt));
    }

    public static bool Verify(string password)
    {
        if (!HasPassword || _salt == null || _passwordHashBase64 == null) return false;
        var hash = Rfc2898DeriveBytes.Pbkdf2(password, _salt, Iterations, HashAlgorithmName.SHA256, KeySize);
        return CryptographicOperations.FixedTimeEquals(hash, Convert.FromBase64String(_passwordHashBase64));
    }

    public static bool Unlock(string password)
    {
        if (!Verify(password)) return false;
        _currentPassword = password;
        return true;
    }

    public static void Lock() => _currentPassword = null;

    public static bool IsEncrypted(string? value) =>
        !string.IsNullOrEmpty(value) && value!.StartsWith(Prefix, StringComparison.Ordinal);

    /// <summary>Encrypt plaintext using the current unlocked password. Throws if not unlocked.</summary>
    public static string Encrypt(string plaintext)
    {
        if (_currentPassword == null || _salt == null)
            throw new InvalidOperationException("Password vault is locked.");
        var (encKey, macKey) = DeriveKeys(_currentPassword, _salt);
        var iv = RandomNumberGenerator.GetBytes(IvSize);

        using var aes = Aes.Create();
        aes.Key = encKey; aes.IV = iv; aes.Mode = CipherMode.CBC; aes.Padding = PaddingMode.PKCS7;
        using var ms = new MemoryStream();
        using (var cs = new CryptoStream(ms, aes.CreateEncryptor(), CryptoStreamMode.Write))
        using (var sw = new StreamWriter(cs, Encoding.UTF8))
            sw.Write(plaintext);
        var ciphertext = ms.ToArray();

        // Encrypt-then-MAC over IV||ciphertext using a separate HMAC key.
        using var hmac = new HMACSHA256(macKey);
        var macInput = new byte[iv.Length + ciphertext.Length];
        Buffer.BlockCopy(iv, 0, macInput, 0, iv.Length);
        Buffer.BlockCopy(ciphertext, 0, macInput, iv.Length, ciphertext.Length);
        var mac = hmac.ComputeHash(macInput);

        var combined = new byte[iv.Length + ciphertext.Length + mac.Length];
        Buffer.BlockCopy(iv, 0, combined, 0, iv.Length);
        Buffer.BlockCopy(ciphertext, 0, combined, iv.Length, ciphertext.Length);
        Buffer.BlockCopy(mac, 0, combined, iv.Length + ciphertext.Length, mac.Length);

        return Prefix + Convert.ToBase64String(combined);
    }

    /// <summary>Decrypt a blob produced by <see cref="Encrypt"/>. Returns null on auth failure.</summary>
    public static string? Decrypt(string blob)
    {
        if (_currentPassword == null || _salt == null || !IsEncrypted(blob)) return null;
        try
        {
            var combined = Convert.FromBase64String(blob.Substring(Prefix.Length));
            if (combined.Length < IvSize + HmacSize + 16) return null;
            var iv = new byte[IvSize];
            Buffer.BlockCopy(combined, 0, iv, 0, IvSize);
            var mac = new byte[HmacSize];
            Buffer.BlockCopy(combined, combined.Length - HmacSize, mac, 0, HmacSize);
            var ciphertext = new byte[combined.Length - IvSize - HmacSize];
            Buffer.BlockCopy(combined, IvSize, ciphertext, 0, ciphertext.Length);

            var (encKey, macKey) = DeriveKeys(_currentPassword, _salt);
            using var hmac = new HMACSHA256(macKey);
            var macInput = new byte[iv.Length + ciphertext.Length];
            Buffer.BlockCopy(iv, 0, macInput, 0, iv.Length);
            Buffer.BlockCopy(ciphertext, 0, macInput, iv.Length, ciphertext.Length);
            var expected = hmac.ComputeHash(macInput);
            if (!CryptographicOperations.FixedTimeEquals(expected, mac)) return null;

            using var aes = Aes.Create();
            aes.Key = encKey; aes.IV = iv; aes.Mode = CipherMode.CBC; aes.Padding = PaddingMode.PKCS7;
            using var ms = new MemoryStream(ciphertext);
            using var cs = new CryptoStream(ms, aes.CreateDecryptor(), CryptoStreamMode.Read);
            using var sr = new StreamReader(cs, Encoding.UTF8);
            return sr.ReadToEnd();
        }
        catch { return null; }
    }

    private static (byte[] encKey, byte[] macKey) DeriveKeys(string password, byte[] salt)
    {
        // Derive 2*KeySize bytes deterministically, then split into enc+mac keys so each
        // key is independent. (Equivalent to the previous successive GetBytes calls.)
        var combined = Rfc2898DeriveBytes.Pbkdf2(password, salt, Iterations, HashAlgorithmName.SHA256, KeySize * 2);
        var enc = new byte[KeySize]; var mac = new byte[KeySize];
        Buffer.BlockCopy(combined, 0, enc, 0, KeySize);
        Buffer.BlockCopy(combined, KeySize, mac, 0, KeySize);
        return (enc, mac);
    }
}
