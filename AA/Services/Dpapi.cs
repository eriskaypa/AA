using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace AA.Services;

/// <summary>Thin wrapper over Windows DPAPI (CryptProtectData / CryptUnprotectData) at the CurrentUser
/// scope, via P/Invoke so no extra NuGet package is needed. Encrypted blobs are tied to the current
/// Windows account and machine — exactly right for a cached credential or a per-PC at-rest data file,
/// and deliberately NOT portable to another machine.</summary>
internal static class Dpapi
{
    [StructLayout(LayoutKind.Sequential)]
    private struct DATA_BLOB
    {
        public int cbData;
        public IntPtr pbData;
    }

    [DllImport("crypt32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CryptProtectData(ref DATA_BLOB pDataIn, string? szDataDescr, IntPtr pOptionalEntropy,
        IntPtr pvReserved, IntPtr pPromptStruct, int dwFlags, ref DATA_BLOB pDataOut);

    [DllImport("crypt32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CryptUnprotectData(ref DATA_BLOB pDataIn, IntPtr ppszDataDescr, IntPtr pOptionalEntropy,
        IntPtr pvReserved, IntPtr pPromptStruct, int dwFlags, ref DATA_BLOB pDataOut);

    [DllImport("kernel32.dll")]
    private static extern IntPtr LocalFree(IntPtr hMem);

    private const int CRYPTPROTECT_UI_FORBIDDEN = 0x1;

    public static byte[] Protect(byte[] data) => Run(data, encrypt: true);
    public static byte[] Unprotect(byte[] data) => Run(data, encrypt: false);

    private static byte[] Run(byte[] data, bool encrypt)
    {
        var inBlob = new DATA_BLOB();
        var outBlob = new DATA_BLOB();
        // AllocHGlobal(0) is undefined; use 1 byte for an empty input.
        var pin = Marshal.AllocHGlobal(data.Length == 0 ? 1 : data.Length);
        try
        {
            if (data.Length > 0) Marshal.Copy(data, 0, pin, data.Length);
            inBlob.cbData = data.Length;
            inBlob.pbData = pin;

            bool ok = encrypt
                ? CryptProtectData(ref inBlob, "AA", IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, CRYPTPROTECT_UI_FORBIDDEN, ref outBlob)
                : CryptUnprotectData(ref inBlob, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, CRYPTPROTECT_UI_FORBIDDEN, ref outBlob);
            if (!ok) throw new Win32Exception(Marshal.GetLastWin32Error());

            var outBytes = new byte[outBlob.cbData];
            if (outBlob.cbData > 0) Marshal.Copy(outBlob.pbData, outBytes, 0, outBlob.cbData);
            return outBytes;
        }
        finally
        {
            if (pin != IntPtr.Zero) Marshal.FreeHGlobal(pin);
            if (outBlob.pbData != IntPtr.Zero) LocalFree(outBlob.pbData);
        }
    }
}
