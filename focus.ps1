# Phase 2 Stage 2: handles a click on a ccnotify-focus:// toast.
# 1. Works out the chat's current title: the live title from its transcript, then the tab map entry,
#    then the title in the link. Each candidate is tried in turn.
# 2. Finds Windows Terminal windows with the Win32 window list (this also sees windows on other
#    virtual desktops; UI Automation does not).
# 3. Reads tab names WITHOUT bringing windows forward where Windows allows it, and uses a cache of
#    tab names from earlier clicks to pick the likely window first. Only the chosen window is brought
#    forward, so the screen does not jump between desktops.
# 4. Falls back to the window this chat last used (remembered per WT_SESSION), not the first found.
# Logs every step to focus.log.
param([string]$Uri = '')
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$logFile = Join-Path $here 'focus.log'
$stateFile = Join-Path $here 'wt-windows.json'
function Log([string]$m) { try { Add-Content -LiteralPath $logFile -Value ('{0} {1}' -f (Get-Date -Format o), $m) -Encoding utf8 } catch {} }
function Norm([string]$s) { return ([regex]::Replace($s, '^[^\p{L}\p{N}]+', '')).Trim() }
function Read-State {
  $st = @{ tabs = @{}; last = @{} }
  if (Test-Path -LiteralPath $stateFile) {
    try {
      $o = Get-Content -Raw -LiteralPath $stateFile | ConvertFrom-Json
      if ($o.tabs) { foreach ($p in $o.tabs.PSObject.Properties) { $st.tabs[$p.Name] = @($p.Value) } }
      if ($o.last) { foreach ($p in $o.last.PSObject.Properties) { $st.last[$p.Name] = [string]$p.Value } }
    } catch { Log ("state file unreadable, starting empty: {0}" -f $_.Exception.Message) }
  }
  return $st
}
function Write-State($st) {
  try { ([pscustomobject]@{ tabs = $st.tabs; last = $st.last } | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $stateFile -Encoding utf8 } catch { Log ("state write failed: {0}" -f $_.Exception.Message) }
}
function Live-Title([string]$sid) {
  if ($sid -notmatch '^[0-9a-f-]{36}$') { return '' }
  $f = Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE '.claude\projects') -Filter "$sid.jsonl" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $f) { return '' }
  $line = Select-String -LiteralPath $f.FullName -Pattern '"type":"ai-title"' | Select-Object -Last 1
  if ($line) { return [string](($line.Line | ConvertFrom-Json).aiTitle) }
  return ''
}
try {
  Log ("start uri=[{0}]" -f $Uri)
  # Windows may add a slash before the query ("focus/?wt=..."); accept both shapes.
  if ($Uri -notmatch '^ccnotify-focus://focus/?\?') { Log 'REJECT scheme/path'; exit 0 }
  $wt = ''; $uriTitle = ''
  if ($Uri -match '[?&]wt=([0-9a-fA-F-]{36})(?:&|$)') { $wt = $Matches[1] }
  if ($Uri -match '[?&]title=([^&]*)') { $uriTitle = [Uri]::UnescapeDataString($Matches[1]) }
  $chHwnd = 0
  if ($Uri -match '[?&]ch=(\d{1,20})(?:&|$)') { $chHwnd = [int64]$Matches[1] }
  $whHwnd = 0
  if ($Uri -match '[?&]wh=(\d{1,20})(?:&|$)') { $whHwnd = [int64]$Matches[1] }
  if ($uriTitle.Length -gt 200) { $uriTitle = $uriTitle.Substring(0, 200) }
  # Terminal tab name recorded at turn end (the Codex console title, which Windows Terminal shows on the tab).
  $uriTab = ''
  if ($Uri -match '[?&]tab=([^&]*)') { $uriTab = [Uri]::UnescapeDataString($Matches[1]) }
  if ($uriTab.Length -gt 200) { $uriTab = $uriTab.Substring(0, 200) }

  $candidates = New-Object System.Collections.Generic.List[string]
  if ($wt) {
    $mapFile = Join-Path $here ("wt-map\{0}.json" -f $wt)
    if (Test-Path -LiteralPath $mapFile) {
      $entry = Get-Content -Raw -LiteralPath $mapFile | ConvertFrom-Json
      $live = Live-Title ([string]$entry.session_id)
      if ($live) { $candidates.Add($live) }
      if ($entry.title) { $candidates.Add([string]$entry.title) }
    }
  }
  if ($uriTitle) { $candidates.Add($uriTitle) }
  if ($uriTab) { $candidates.Add($uriTab) }
  $candidates = @($candidates | ForEach-Object { Norm $_ } | Where-Object { $_ } | Select-Object -Unique)
  Log ("resolved wt=[{0}] candidates=[{1}]" -f $wt, ($candidates -join ' | '))
  if ($candidates.Count -eq 0) { Log 'REJECT no title'; exit 0 }

  Add-Type -AssemblyName UIAutomationClient
  Add-Type -AssemblyName UIAutomationTypes
  Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class FocusWin {
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr p);
  [DllImport("user32.dll")] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
  [DllImport("user32.dll")] static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  // Standard workaround: attach to the current foreground thread so Windows accepts the focus change.
  public static bool ForceForeground(IntPtr h) {
    IntPtr fg = GetForegroundWindow();
    uint fgThread = GetWindowThreadProcessId(fg, IntPtr.Zero);
    uint me = GetCurrentThreadId();
    bool attached = fgThread != 0 && fgThread != me && AttachThreadInput(me, fgThread, true);
    // Foreground lock: Windows accepts SetForegroundWindow only after recent input. A harmless Alt tap counts as input.
    keybd_event(0x12, 0, 0, UIntPtr.Zero); keybd_event(0x12, 0, 0x2, UIntPtr.Zero);
    try { return SetForegroundWindow(h); }
    finally { if (attached) AttachThreadInput(me, fgThread, false); }
  }
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  // The Windows Terminal window caption shows the active tab's name. Reading it does not bring the window forward.
  public static string Caption(IntPtr h) {
    var s = new StringBuilder(512); GetWindowText(h, s, 512); return s.ToString();
  }
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  public static string ClassOf(IntPtr h) {
    var s = new StringBuilder(256); GetClassNameW(h, s, 256); return s.ToString();
  }
  public static List<IntPtr> TerminalWindows() {
    var r = new List<IntPtr>();
    EnumWindows((h, p) => {
      if (!IsWindowVisible(h)) return true;
      var c = new StringBuilder(256); GetClassName(h, c, 256);
      if (c.ToString() == "CASCADIA_HOSTING_WINDOW_CLASS") r.Add(h);
      return true;
    }, IntPtr.Zero);
    return r;
  }
}
'@
  $sp = [System.Windows.Automation.SelectionItemPattern]::Pattern
  $handles = @([FocusWin]::TerminalWindows())
  Log ("terminal windows found: {0}" -f $handles.Count)
  if ($handles.Count -eq 0) { Log 'NO TERMINAL WINDOW found'; exit 0 }

  function Bring([IntPtr]$h) {
    if ([FocusWin]::IsIconic($h)) { [void][FocusWin]::ShowWindow($h, 9) }
    $ok = [FocusWin]::ForceForeground($h)
    Log ("SetForegroundWindow hwnd={0} ok={1}" -f $h, $ok)
    return $ok
  }
  function Tab-Names($h) {
    $el = [System.Windows.Automation.AutomationElement]::FromHandle($h)
    $tabs = @($el.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) | Where-Object { $_.Current.ControlType.ProgrammaticName -match 'TabItem' })
    return $tabs
  }
  function Pick-Tab($tabs, [string]$want) {
    return @($tabs | Where-Object { (Norm $_.Current.Name) -eq $want })[0]
  }

  # Windows Terminal window named in the link (wh=, recorded when the Codex turn ended): bring that window forward,
  # then select the tab whose name matches the chat title, if the tab names can be read. No other window is touched.
  if ($whHwnd -gt 0) {
    $wp = [IntPtr]::new($whHwnd)
    if ([FocusWin]::IsWindow($wp) -and ([FocusWin]::ClassOf($wp) -eq 'CASCADIA_HOSTING_WINDOW_CLASS')) {
      [void](Bring $wp)
      Start-Sleep -Milliseconds 400
      # The window is on another virtual desktop: switch the screen to that desktop (the window itself is not moved).
      # Steps with Win+Ctrl+Right, then Win+Ctrl+Left, and checks after each step. Returns to the start if no match.
      try {
        Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Threading;
[ComImport, Guid("A5CD92FF-29BE-454C-8D04-D82879FB3F1B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IVdmFollow { [PreserveSig] int IsWindowOnCurrentVirtualDesktop(IntPtr h, [MarshalAs(UnmanagedType.Bool)] out bool on); [PreserveSig] int GetWindowDesktopId(IntPtr h, out Guid g); }
[ComImport, Guid("AA509086-5CA9-4C25-8F95-589D3C07B48A")] public class VdmFollowClass { }
public static class DeskFollow {
  [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  public static bool OnCurrent(IntPtr h) { var m = (IVdmFollow)new VdmFollowClass(); bool b; Marshal.ThrowExceptionForHR(m.IsWindowOnCurrentVirtualDesktop(h, out b)); return b; }
  static void Combo(byte key) {
    keybd_event(0x5B, 0, 0, UIntPtr.Zero); keybd_event(0x11, 0, 0, UIntPtr.Zero); keybd_event(key, 0, 0, UIntPtr.Zero);
    keybd_event(key, 0, 2, UIntPtr.Zero); keybd_event(0x11, 0, 2, UIntPtr.Zero); keybd_event(0x5B, 0, 2, UIntPtr.Zero);
  }
  public static string Follow(IntPtr h) {
    if (OnCurrent(h)) return "already";
    int moved = 0;
    for (int i = 0; i < 4; i++) { Combo(0x27); moved++; Thread.Sleep(400); if (OnCurrent(h)) return "right" + moved; }
    for (int i = 0; i < moved; i++) { Combo(0x25); Thread.Sleep(400); }
    moved = 0;
    for (int i = 0; i < 4; i++) { Combo(0x25); moved++; Thread.Sleep(400); if (OnCurrent(h)) return "left" + moved; }
    for (int i = 0; i < moved; i++) { Combo(0x27); Thread.Sleep(400); }
    return "none";
  }
}
'@ -ErrorAction Stop
        $where = [DeskFollow]::Follow($wp)
        Log ("DESKTOP follow wh={0} result={1}" -f $whHwnd, $where)
        if ($where -like 'right*' -or $where -like 'left*') { [void](Bring $wp); Start-Sleep -Milliseconds 300 }
      } catch { Log ('DESKTOP follow SKIPPED ' + $_.Exception.Message) }
      $tabNamed = $false
      $tabsW = Tab-Names $wp
      foreach ($c in $candidates) {
        $mw = Pick-Tab $tabsW $c
        if ($mw) { $mw.GetCurrentPattern($sp).Select(); $tabNamed = $true; Log ("WT tab selected [{0}] in wh={1}" -f $c, $whHwnd); break }
      }
      Log ("WT window wh={0} brought forward (pseudo-console link) tabNamed={1}" -f $whHwnd, $tabNamed)
      exit 0
    }
    Log ("WT window wh={0} is gone or not a Terminal window; falling through" -f $whHwnd)
  }
  # Plain console window named in the link (not Windows Terminal): bring that exact window back, nothing else.
  if ($chHwnd -gt 0) {
    $cp = [IntPtr]::new($chHwnd)
    if ([FocusWin]::IsWindow($cp) -and ([FocusWin]::ClassOf($cp) -eq 'ConsoleWindowClass')) {
      [void](Bring $cp)
      Log ("CONSOLE window hwnd={0} brought forward (plain console link)" -f $chHwnd)
      exit 0
    }
    Log ("CONSOLE window hwnd={0} is gone or not a console; falling through to title matching" -f $chHwnd)
  }

  $st = Read-State
  $key ={ param($h) [string][int64]$h }
  # Order: the window this chat last used first, then windows whose cached tab names match, then the rest.
  $lastHwnd = if ($wt -and $st.last.ContainsKey($wt)) { $st.last[$wt] } else { '' }
  if ($wt) {
    $mf = Join-Path $here ("wt-map\{0}.json" -f $wt)
    if (Test-Path -LiteralPath $mf) { $me = Get-Content -Raw -LiteralPath $mf | ConvertFrom-Json; if ($me.hwnd) { $lastHwnd = [string]$me.hwnd } }
  }
  $ordered = New-Object System.Collections.Generic.List[IntPtr]
  $h0 = @($handles | Where-Object { ([string][int64]$_) -eq $lastHwnd })
  foreach ($h in $h0) { $ordered.Add($h) }
  foreach ($h in $handles) {
    if ($ordered.Contains($h)) { continue }
    $cached = @($st.tabs[([string][int64]$h)])
    if (@($cached | Where-Object { $candidates -contains (Norm $_) }).Count -gt 0) { $ordered.Add($h) }
  }
  foreach ($h in $handles) { if (-not $ordered.Contains($h)) { $ordered.Add($h) } }

  # Pass 1: read tab names without bringing windows forward (works only for windows on the current desktop).
  # Pass 0: the caption shows the active tab's name. Matching it needs no window brought forward first,
  # so only the one correct window is brought forward.
  $chosen = $null; $chosenTitle = ''
  foreach ($h in $ordered) {
    $cap = Norm ([FocusWin]::Caption($h))
    if ($cap -and ($candidates -contains $cap)) {
      $chosenTitle = $cap
      [void](Bring $h)
      Start-Sleep -Milliseconds 300
      $m = Pick-Tab (Tab-Names $h) $cap
      if ($m) { $chosen = @{ h = $h; tab = $m } }
      Log ("pass 0 caption hwnd={0} tabFound={1}" -f $h, [bool]$m)
      break
    }
  }
  # Pass 1 runs only when pass 0 did not find the tab.
  foreach ($h in $(if ($chosen) { @() } else { @($ordered) })) {
    $tabs = Tab-Names $h
    if ($tabs.Count -eq 0) { continue }
    $names = @($tabs | ForEach-Object { $_.Current.Name })
    $st.tabs[([string][int64]$h)] = $names
    foreach ($c in $candidates) {
      $m = Pick-Tab $tabs $c
      if ($m) { $chosen = @{ h = $h; tab = $m }; $chosenTitle = $c; break }
    }
    if ($chosen) { break }
  }
  Log ("pass 1 (no bring) chosen={0}" -f [bool]$chosen)

  # Pass 2: bring only the windows that could hold the tab, in order, and check again.
  if (-not $chosen) {
    foreach ($h in $ordered) {
      $cachedOk = @($st.tabs[([string][int64]$h)] | Where-Object { $candidates -contains (Norm $_) }).Count -gt 0
      $isLast = ([string][int64]$h) -eq $lastHwnd
      if (-not ($cachedOk -or $isLast)) { continue }
      [void](Bring $h)
      Start-Sleep -Milliseconds 1000
      $tabs = Tab-Names $h
      $st.tabs[([string][int64]$h)] = @($tabs | ForEach-Object { $_.Current.Name })
      foreach ($c in $candidates) {
        $m = Pick-Tab $tabs $c
        if ($m) { $chosen = @{ h = $h; tab = $m }; $chosenTitle = $c; break }
      }
      Log ("pass 2 hwnd={0} tabs={1} chosen={2}" -f $h, $tabs.Count, [bool]$chosen)
      if ($chosen) { break }
    }
  }

  if ($chosen) {
    [void](Bring $chosen.h)
    $chosen.tab.GetCurrentPattern($sp).Select()
    Log ("SELECTED tab [{0}] in hwnd={1}" -f $chosenTitle, $chosen.h)
    if ($wt) { $st.last[$wt] = [string][int64]$chosen.h }
  } else {
    # Only the window this chat last used is brought forward. With no saved window, nothing is brought forward,
    # so the screen does not jump to an unrelated window (vote 2 of 3 for this rule, 2026-11-09).
    $savedWin = @($handles | Where-Object { $lastHwnd -and ([string][int64]$_) -eq $lastHwnd })
    if ($savedWin.Count -gt 0) {
      [void](Bring $savedWin[0])
      Log ("FALLBACK window-level only: no tab matched {0}; brought last-used hwnd={1}" -f ($candidates -join ' | '), $savedWin[0])
    } else {
      Log ("NO MATCH and no saved window for this chat; nothing brought forward. candidates={0}" -f ($candidates -join ' | '))
    }
  }
  Write-State $st
} catch { Log ("ERROR {0}" -f $_.Exception.Message) }
exit 0
