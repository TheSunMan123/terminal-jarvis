# Windows Credential Manager access for Terminal Jarvis (API keys never touch a file). Dot-source this file.
if (-not ("TJCred" -as [type])) {
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public static class TJCred {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public struct CREDENTIAL { public int Flags; public int Type; public string TargetName; public string Comment;
    public long LastWritten; public int CredentialBlobSize; public IntPtr CredentialBlob; public int Persist;
    public int AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName; }
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool CredRead(string t, int type, int f, out IntPtr c);
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool CredWrite(ref CREDENTIAL c, int f);
  [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern bool CredDelete(string t, int type, int f);
  [DllImport("advapi32.dll")] static extern void CredFree(IntPtr p);
  public static string Read(string target) {
    IntPtr p; if (!CredRead(target, 1, 0, out p)) return null;
    try { var c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL));
      if (c.CredentialBlobSize == 0) return "";
      return Marshal.PtrToStringUni(c.CredentialBlob, c.CredentialBlobSize / 2).TrimEnd('\0'); }
    finally { CredFree(p); }
  }
  public static bool Write(string target, string user, string secret) {
    byte[] b = Encoding.Unicode.GetBytes(secret);
    var c = new CREDENTIAL { Type = 1, TargetName = target, UserName = user, Persist = 2, CredentialBlobSize = b.Length,
      CredentialBlob = Marshal.AllocHGlobal(b.Length) };
    try { Marshal.Copy(b, 0, c.CredentialBlob, b.Length); return CredWrite(ref c, 0); }
    finally { Marshal.FreeHGlobal(c.CredentialBlob); }
  }
  public static bool Delete(string target) { return CredDelete(target, 1, 0); }
}
"@
}
