using System;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using Google.Apis.Json;
using Google.Apis.Util.Store;

namespace AA.Services;

/// <summary>An <see cref="IDataStore"/> for the Google auth library that encrypts each stored value with
/// Windows DPAPI (CurrentUser) at rest, instead of the default plaintext <c>FileDataStore</c>. The OAuth
/// refresh token is the most valuable secret the app holds (it grants Drive access to every backup), so it
/// should not sit in cleartext in the user's profile. Filenames match FileDataStore's scheme so an existing
/// plaintext token is detected and transparently migrated (re-encrypted) on first read.</summary>
public sealed class DpapiDataStore : IDataStore
{
    private readonly string _folder;
    private static readonly byte[] Magic = Encoding.ASCII.GetBytes("AADPAPI1");

    public DpapiDataStore(string folder)
    {
        _folder = folder;
        Directory.CreateDirectory(folder);
    }

    // Same key layout FileDataStore uses ("<TypeFullName>-<key>"), so a token cached by the old plaintext
    // store lands on the same path and is picked up for migration.
    private string FileFor<T>(string key) => Path.Combine(_folder, $"{typeof(T).FullName}-{key}");

    public Task StoreAsync<T>(string key, T value)
    {
        var json = NewtonsoftJsonSerializer.Instance.Serialize(value);
        var enc = Dpapi.Protect(Encoding.UTF8.GetBytes(json));
        var buf = new byte[Magic.Length + enc.Length];
        Buffer.BlockCopy(Magic, 0, buf, 0, Magic.Length);
        Buffer.BlockCopy(enc, 0, buf, Magic.Length, enc.Length);
        File.WriteAllBytes(FileFor<T>(key), buf);
        return Task.CompletedTask;
    }

    public Task<T> GetAsync<T>(string key)
    {
        var path = FileFor<T>(key);
        if (!File.Exists(path)) return Task.FromResult<T>(default!);
        try
        {
            var raw = File.ReadAllBytes(path);
            if (StartsWithMagic(raw))
            {
                var enc = new byte[raw.Length - Magic.Length];
                Buffer.BlockCopy(raw, Magic.Length, enc, 0, enc.Length);
                var json = Encoding.UTF8.GetString(Dpapi.Unprotect(enc));
                return Task.FromResult(NewtonsoftJsonSerializer.Instance.Deserialize<T>(json));
            }
            // Legacy plaintext token from the old FileDataStore — read it, then re-store encrypted so
            // the cleartext copy is replaced on disk.
            var plainJson = Encoding.UTF8.GetString(raw);
            var value = NewtonsoftJsonSerializer.Instance.Deserialize<T>(plainJson);
            try { _ = StoreAsync(key, value); } catch { /* migration is best-effort */ }
            return Task.FromResult(value);
        }
        catch
        {
            return Task.FromResult<T>(default!);
        }
    }

    public Task DeleteAsync<T>(string key)
    {
        var path = FileFor<T>(key);
        try { if (File.Exists(path)) File.Delete(path); } catch { }
        return Task.CompletedTask;
    }

    public Task ClearAsync()
    {
        try
        {
            if (Directory.Exists(_folder))
                foreach (var f in Directory.EnumerateFiles(_folder))
                    try { File.Delete(f); } catch { }
        }
        catch { }
        return Task.CompletedTask;
    }

    private static bool StartsWithMagic(byte[] data)
    {
        if (data.Length < Magic.Length) return false;
        for (int i = 0; i < Magic.Length; i++) if (data[i] != Magic[i]) return false;
        return true;
    }
}
