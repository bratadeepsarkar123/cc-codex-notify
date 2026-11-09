# Phase 2 Stage 5: Codex turn-end toast. Shows a Windows toast with the chat name, project folder and
# last reply, and a click link that uses the same ccnotify-focus:// handler as Claude Code.
# Called by codex-notify.js. Always exits 0; the wrapper falls back to ping.ps1 if this fails.
param(
  [string]$Title = 'Codex chat',
  [string]$Folder = '',
  [string]$Body = 'Your reply is ready in the terminal.',
  [string]$Wt = '',
  [string]$Cwd = ''
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$logFile = Join-Path $here 'codex-notify.log'
function Log([string]$m) { try { Add-Content -LiteralPath $logFile -Value ('{0} {1}' -f (Get-Date -Format o), $m) -Encoding utf8 } catch {} }
try {
  if ($Wt -notmatch '^[0-9a-fA-F-]{36}$') { $Wt = '' }
  if ($Body.Length -gt 160) { $Body = $Body.Substring(0, 157) + '...' }
  # Plain console window (no Windows Terminal): find the Codex chat's console by walking up the parent processes
  # (this script runs under node, which runs under Codex), so the click can bring that window back. Same method as notify.ps1.
  $conHwnd = [int64]0; $conClass = ''; $conTitle = ''
  # Console title of the Codex process's console: Windows Terminal shows it as the tab name, so the link can select that tab (tab=).
  try {
    Add-Type -TypeDefinition 'using System; using System.Text; using System.Runtime.InteropServices; public static class CodexTitle { [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern uint GetConsoleTitleW(StringBuilder s, uint n); }' -ErrorAction SilentlyContinue
  } catch {}
  # Runs for Windows Terminal turns too: the walk records the tab's pseudo-console, from which the Terminal window is read (wh=).
  if ($true) {
    try {
      Add-Type -TypeDefinition 'using System; using System.Text; using System.Runtime.InteropServices; public static class CodexConHook { [DllImport("kernel32.dll")] public static extern bool AttachConsole(uint pid); [DllImport("kernel32.dll")] public static extern bool FreeConsole(); [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow(); [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n); }' -ErrorAction SilentlyContinue
      # Own console first: when this script runs directly in a Windows Terminal tab, the tab is our own console.
      $ownH = [CodexConHook]::GetConsoleWindow()
      if ($ownH -ne [IntPtr]::Zero) {
        $ownCb = New-Object System.Text.StringBuilder 256
        [void][CodexConHook]::GetClassName($ownH, $ownCb, 256)
        if ($ownCb.ToString() -eq 'ConsoleWindowClass' -or $ownCb.ToString() -eq 'PseudoConsoleWindow') {
          $conHwnd = [int64]$ownH; $conClass = $ownCb.ToString()
          $otsb = New-Object System.Text.StringBuilder 1024
          if ([CodexTitle]::GetConsoleTitleW($otsb, 1024) -gt 0) { $conTitle = $otsb.ToString() }
        }
      }
      $cur = [int]$PID
      for ($depth = 0; $depth -lt 8 -and $conHwnd -eq 0; $depth++) {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$cur" -ErrorAction SilentlyContinue
        if (-not $proc) { break }
        $cur = [int]$proc.ParentProcessId
        if ($cur -le 0) { break }
        [void][CodexConHook]::FreeConsole()
        $attached = [CodexConHook]::AttachConsole([uint32]$cur)
        $walkName = (Get-CimInstance Win32_Process -Filter "ProcessId=$cur" -ErrorAction SilentlyContinue).Name
        Log ("CODEX WALK depth={0} pid={1} name=[{2}] attached={3}" -f $depth, $cur, $walkName, $attached)
        if ($attached) {
          # The title is taken only from the console whose window is recorded below, so the tab name matches the handle.
          $tsb = New-Object System.Text.StringBuilder 1024
          $tTmp = ''; if ([CodexTitle]::GetConsoleTitleW($tsb, 1024) -gt 0) { $tTmp = $tsb.ToString() }
          $ch = [CodexConHook]::GetConsoleWindow()
          if ($ch -ne [IntPtr]::Zero) {
            $cb = New-Object System.Text.StringBuilder 256
            [void][CodexConHook]::GetClassName($ch, $cb, 256)
            $conHwnd = [int64]$ch; $conClass = $cb.ToString(); $conTitle = $tTmp
          }
          [void][CodexConHook]::FreeConsole()
        }
      }
    } catch { Log ('CODEX CONSOLE WALK SKIPPED ' + $_.Exception.Message) }
  }
  # Fallback when the hook's own parent chain is gone (seen on most turns): find the live codex.exe process
  # that runs in this project folder (its current directory is read from its process memory), then walk up
  # from it to a plain console window. Only ConsoleWindowClass counts; Windows Terminal tabs are not matched here.
  if ($Cwd -eq 'none') { $Cwd = '' }
  # Windows Terminal tab: the tab's pseudo-console window is a child of the Terminal window that holds the tab.
  # Checked on live tabs: both tabs' pseudo-consoles had the same parent window. Recorded as wh=<window> in the link.
  $wtWinHwnd = [int64]0
  if ($conClass -eq 'PseudoConsoleWindow' -and $conHwnd -gt 0) {
    try {
      Add-Type -TypeDefinition 'using System; using System.Text; using System.Runtime.InteropServices; public static class CodexWtParent { [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h); [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n); }' -ErrorAction SilentlyContinue
      $pw = [CodexWtParent]::GetParent([IntPtr]::new($conHwnd))
      if ($pw -ne [IntPtr]::Zero) {
        $sbp = New-Object System.Text.StringBuilder 256
        [void][CodexWtParent]::GetClassNameW($pw, $sbp, 256)
        if ($sbp.ToString() -eq 'CASCADIA_HOSTING_WINDOW_CLASS') { $wtWinHwnd = [int64]$pw }
      }
      Log ("CODEX WT PARENT pseudo_hwnd={0} terminal_window={1}" -f $conHwnd, $wtWinHwnd)
    } catch { Log ('CODEX WT PARENT SKIPPED ' + $_.Exception.Message) }
  }
  # The first walk may have stopped at a Windows Terminal pseudo-console; only a plain console window counts here.
  if ($conClass -ne 'ConsoleWindowClass') { $conHwnd = [int64]0; $conClass = '' }
  if ($conHwnd -eq 0 -and $wtWinHwnd -eq 0) { $conTitle = '' }
  # Also runs for Windows Terminal turns when the walk found no tab (the hook's parent chain is gone on real turns).
  if ($wtWinHwnd -eq 0 -and $conHwnd -eq 0 -and $Cwd) {
    try {
      Add-Type -TypeDefinition @'
using System; using System.Text; using System.Runtime.InteropServices;
public static class CodexPeb {
  [StructLayout(LayoutKind.Sequential)] public struct PBI { public IntPtr R1; public IntPtr Peb; public IntPtr R2a; public IntPtr R2b; public IntPtr Pid; public IntPtr R3; }
  [DllImport("ntdll.dll")] static extern int NtQueryInformationProcess(IntPtr h, int cls, ref PBI pbi, int len, out int ret);
  [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
  [DllImport("kernel32.dll")] static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
  static bool Rd(IntPtr h, long addr, byte[] buf) { IntPtr r; return ReadProcessMemory(h, new IntPtr(addr), buf, new IntPtr(buf.Length), out r) && r.ToInt64() == buf.Length; }
  static long Ptr(IntPtr h, long addr) { var b = new byte[8]; return Rd(h, addr, b) ? BitConverter.ToInt64(b, 0) : 0; }
  // Current directory of a 64-bit process: PEB -> ProcessParameters -> CurrentDirectory.DosPath (offsets for 64-bit Windows).
  public static string Cwd(int pid) {
    IntPtr h = OpenProcess(0x0410, false, (uint)pid);
    if (h == IntPtr.Zero) return null;
    try {
      var pbi = new PBI(); int ret;
      if (NtQueryInformationProcess(h, 0, ref pbi, Marshal.SizeOf(typeof(PBI)), out ret) != 0) return null;
      long peb = pbi.Peb.ToInt64(); if (peb == 0) return null;
      long pp = Ptr(h, peb + 0x20); if (pp == 0) return null;
      var lb = new byte[2]; if (!Rd(h, pp + 0x38, lb)) return null;
      int len = BitConverter.ToUInt16(lb, 0);
      long buf = Ptr(h, pp + 0x40);
      if (buf == 0 || len <= 0 || len > 4096) return null;
      var sb = new byte[len]; if (!Rd(h, buf, sb)) return null;
      return Encoding.Unicode.GetString(sb);
    } finally { CloseHandle(h); }
  }
}
'@ -ErrorAction SilentlyContinue
      $want = $Cwd.TrimEnd('\').ToLowerInvariant()
      $codexProcs = @(Get-CimInstance Win32_Process -Filter "Name='codex.exe'" -ErrorAction SilentlyContinue | Sort-Object CreationDate -Descending)
      $matched = 0
      foreach ($cp in $codexProcs) {
        $pcwd = [CodexPeb]::Cwd([int]$cp.ProcessId)
        if (-not $pcwd -or $pcwd.TrimEnd('\').ToLowerInvariant() -ne $want) { continue }
        $matched++
        $cur = [int]$cp.ProcessId
        for ($d = 0; $d -lt 8 -and $conHwnd -eq 0; $d++) {
          [void][CodexConHook]::FreeConsole()
          if ([CodexConHook]::AttachConsole([uint32]$cur)) {
            $tsb2 = New-Object System.Text.StringBuilder 1024
            $tTmp2 = ''; if ([CodexTitle]::GetConsoleTitleW($tsb2, 1024) -gt 0) { $tTmp2 = $tsb2.ToString() }
            $ch2 = [CodexConHook]::GetConsoleWindow()
            if ($ch2 -ne [IntPtr]::Zero) {
              $cb2 = New-Object System.Text.StringBuilder 256
              [void][CodexConHook]::GetClassName($ch2, $cb2, 256)
              if ($cb2.ToString() -eq 'ConsoleWindowClass' -or $cb2.ToString() -eq 'PseudoConsoleWindow') { $conHwnd = [int64]$ch2; $conClass = $cb2.ToString(); $conTitle = $tTmp2 }
            }
            [void][CodexConHook]::FreeConsole()
          }
          if ($conHwnd -ne 0) { break }
          $par = Get-CimInstance Win32_Process -Filter "ProcessId=$cur" -ErrorAction SilentlyContinue
          if (-not $par -or [int]$par.ParentProcessId -le 0) { break }
          $cur = [int]$par.ParentProcessId
        }
        if ($conHwnd -ne 0) { Log ("CODEX CWD-MATCH codex pid={0} console_hwnd={1}" -f $cp.ProcessId, $conHwnd); break }
      }
      Log ("CODEX CWD-MATCH scanned={0} matched_folder={1} found={2}" -f $codexProcs.Count, $matched, ($conHwnd -ne 0))
    } catch { Log ('CODEX CWD-MATCH SKIPPED ' + $_.Exception.Message) }
  }
  # Windows Terminal tab found by the folder match: read its Terminal window the same way as the walk does.
  if ($conClass -eq 'PseudoConsoleWindow' -and $conHwnd -gt 0 -and $wtWinHwnd -eq 0) {
    try {
      Add-Type -TypeDefinition 'using System; using System.Text; using System.Runtime.InteropServices; public static class CodexWtParent2 { [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h); [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n); }' -ErrorAction SilentlyContinue
      $pw2 = [CodexWtParent2]::GetParent([IntPtr]::new($conHwnd))
      if ($pw2 -ne [IntPtr]::Zero) {
        $sbq = New-Object System.Text.StringBuilder 256
        [void][CodexWtParent2]::GetClassNameW($pw2, $sbq, 256)
        if ($sbq.ToString() -eq 'CASCADIA_HOSTING_WINDOW_CLASS') { $wtWinHwnd = [int64]$pw2 }
      }
      Log ("CODEX WT PARENT (folder match) pseudo_hwnd={0} terminal_window={1}" -f $conHwnd, $wtWinHwnd)
    } catch { Log ('CODEX WT PARENT (folder match) SKIPPED ' + $_.Exception.Message) }
  }
  $launchUri = 'ccnotify-focus://focus?title=' + [uri]::EscapeDataString($Title)
  if ($Wt) { $launchUri = 'ccnotify-focus://focus?wt=' + $Wt + '&title=' + [uri]::EscapeDataString($Title) }
  if (-not $Wt -and $conHwnd -gt 0 -and $conClass -eq 'ConsoleWindowClass') { $launchUri += '&ch=' + $conHwnd }
  if ($wtWinHwnd -gt 0) { $launchUri += '&wh=' + $wtWinHwnd }
  # Tab name for the Terminal window: the Codex console's title (what Windows Terminal shows on the tab).
  if ($wtWinHwnd -gt 0 -and $conTitle) { $launchUri += '&tab=' + [uri]::EscapeDataString($conTitle) }
  Log ("CODEX LINK console_class=[{0}] console_hwnd=[{1}] ch=[{2}] wh=[{3}] tab=[{4}]" -f $conClass, $conHwnd, $(if ($launchUri -match '&ch=') { 'yes' } else { 'no' }), $wtWinHwnd, $conTitle)
  $xmlText = @"
<toast launch="$([System.Security.SecurityElement]::Escape($launchUri))" activationType="protocol">
  <visual><binding template="ToastGeneric">
    <text>$([System.Security.SecurityElement]::Escape($Title))</text>
    <text>$([System.Security.SecurityElement]::Escape("Project: $Folder"))</text>
    <text>$([System.Security.SecurityElement]::Escape($Body))</text>
  </binding></visual>
</toast>
"@
  [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
  [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
  $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
  $doc.LoadXml($xmlText)
  $toast = [Windows.UI.Notifications.ToastNotification]::new($doc)
  $toast.Tag = if ($Wt) { $Wt.Substring(0, 36) } else { 'codex' }
  $toast.Group = 'codex-code'
  [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe').Show($toast)
  Log ("CODEX TOAST shown title=[{0}] folder=[{1}] wt=[{2}]" -f $Title, $Folder, $Wt)
} catch {
  Log ('CODEX TOAST ERROR ' + $_.Exception.Message)
  exit 1
}
exit 0
