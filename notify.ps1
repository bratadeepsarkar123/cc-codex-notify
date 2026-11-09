# Phase 2 Stage 1: Claude Code Stop and Notification hook.
# Hook mode (no -Worker): reads the hook JSON from stdin, saves it to a queue file, starts a hidden
# worker, and exits at once. It prints nothing and always exits 0, so the reply is never delayed.
# Worker mode: decides whether to show, then shows a Windows toast (or the Phase 1 balloon if switched).
#
# Switch: notify\mode.txt contains "toast" (default) or "balloon" (Phase 1 balloon fallback).
param(
  [switch]$Worker,
  [string]$PayloadFile = ''
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$logFile = Join-Path $here 'notify.log'
function Log([string]$m) {
  try { Add-Content -LiteralPath $logFile -Value ('{0} {1}' -f (Get-Date -Format o), $m) -Encoding utf8 } catch {}
}

if (-not $Worker) {
  try {
    $raw = [Console]::In.ReadToEnd()
    if ($raw) {
      $obj = $raw | ConvertFrom-Json
      $obj | Add-Member -NotePropertyName wt_session -NotePropertyValue ([string]$env:WT_SESSION) -Force
      # Record the console window this chat runs in (plain console windows only; Windows Terminal uses a hidden one).
      # The hook itself has no console, so walk up the parent processes and attach to the first one that has a plain console.
      $conHwnd = 0; $conClass = ''
      try {
        Add-Type -TypeDefinition 'using System; using System.Text; using System.Runtime.InteropServices; public static class ConHook { [DllImport("kernel32.dll")] public static extern bool AttachConsole(uint pid); [DllImport("kernel32.dll")] public static extern bool FreeConsole(); [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow(); [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n); }' -ErrorAction SilentlyContinue
        $cur = [int]$PID
        for ($depth = 0; $depth -lt 6 -and $conHwnd -eq 0; $depth++) {
          $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$cur" -ErrorAction SilentlyContinue
          if (-not $proc) { break }
          $cur = [int]$proc.ParentProcessId
          if ($cur -le 0) { break }
          [void][ConHook]::FreeConsole()
          if ([ConHook]::AttachConsole([uint32]$cur)) {
            $ch = [ConHook]::GetConsoleWindow()
            if ($ch -ne [IntPtr]::Zero) {
              $cb = New-Object System.Text.StringBuilder 256
              [void][ConHook]::GetClassName($ch, $cb, 256)
              $conHwnd = [int64]$ch; $conClass = $cb.ToString()
            }
            [void][ConHook]::FreeConsole()
          }
        }
      } catch {}
      $obj | Add-Member -NotePropertyName console_hwnd -NotePropertyValue ([string]$conHwnd) -Force
      $obj | Add-Member -NotePropertyName console_class -NotePropertyValue $conClass -Force
      $queue = Join-Path $here 'queue'
      New-Item -ItemType Directory -Path $queue -Force | Out-Null
      $file = Join-Path $queue ([guid]::NewGuid().ToString('N') + '.json')
      ($obj | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $file -Encoding utf8
      Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath), '-Worker', '-PayloadFile', ('"{0}"' -f $file)
      ) | Out-Null
    }
  } catch {
    try { Log ('HOOK ERROR ' + $_.Exception.Message) } catch {}
  }
  exit 0
}

# ---------------- Worker ----------------
function Get-Chat-Title([string]$sid, [string]$wt) {
  $t = ''
  $tr = Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE '.claude\projects') -Filter "$sid.jsonl" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($tr) {
    $line = Select-String -LiteralPath $tr.FullName -Pattern '"type":"ai-title"' -ErrorAction SilentlyContinue | Select-Object -Last 1
    if ($line) { $t = [string](($line.Line | ConvertFrom-Json).aiTitle) }
  }
  if (-not $t -and $wt) {
    $m = Join-Path $here ("wt-map\{0}.json" -f $wt)
    if (Test-Path -LiteralPath $m) { $t = [string]((Get-Content -Raw -LiteralPath $m | ConvertFrom-Json).title) }
  }
  return $t
}
function Get-Last-Text([string]$sid) {
  $tr = Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE '.claude\projects') -Filter "$sid.jsonl" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $tr) { return '' }
  $lines = Get-Content -LiteralPath $tr.FullName -Tail 400 -ErrorAction SilentlyContinue
  for ($i = $lines.Count - 1; $i -ge 0; $i--) {
    $l = $lines[$i]
    if ($l -notmatch '"type":"assistant"') { continue }
    try {
      $o = $l | ConvertFrom-Json
      $texts = @($o.message.content | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text })
      if ($texts.Count -gt 0) { return [string]($texts -join ' ') }
    } catch {}
  }
  return ''
}
function Norm([string]$s) { return ([regex]::Replace($s, '^[^\p{L}\p{N}]+', '')).Trim() }

$switchFile = Join-Path $here 'mode.txt'
$mode = 'toast'
if (Test-Path -LiteralPath $switchFile) { $mode = (Get-Content -Raw -LiteralPath $switchFile).Trim() }
try {
  $p = Get-Content -Raw -LiteralPath $PayloadFile | ConvertFrom-Json
  Remove-Item -LiteralPath $PayloadFile -ErrorAction SilentlyContinue
  $event = [string]$p.hook_event_name
  $sid = [string]$p.session_id
  $cwd = [string]$p.cwd
  $msg = [string]$p.message
  $wt = [string]$p.wt_session
  if ($wt -notmatch '^[0-9a-fA-F-]{36}$') { $wt = '' }

  if ($mode -eq 'balloon') {
    if ($event -eq 'Notification') {
      & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'ping.ps1') -Title 'Claude needs you' -Text 'Claude is asking a question or needs a permission.' -Sound 'C:/Windows/Media/Ring02.wav'
    } else {
      & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'ping.ps1') -Sound 'C:/Windows/Media/tada.wav'
    }
    exit 0
  }

  $title = Get-Chat-Title $sid $wt
  if (-not $title) { $title = 'Claude Code chat' }
  $folder = if ($cwd) { Split-Path -Leaf $cwd } else { '' }

  # Suppression: skip when the owner is already looking at this chat's tab.
  $looking = $false
  if ($wt) {
    try {
      Add-Type -AssemblyName UIAutomationClient
      Add-Type -AssemblyName UIAutomationTypes
      Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class FgWin { [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n); }' -ErrorAction SilentlyContinue
      $fg = [FgWin]::GetForegroundWindow()
      $sb = New-Object System.Text.StringBuilder 256
      [void][FgWin]::GetClassName($fg, $sb, 256)
      if ($sb.ToString() -eq 'CASCADIA_HOSTING_WINDOW_CLASS') {
        $w = [System.Windows.Automation.AutomationElement]::FromHandle($fg)
        $sel = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) | Where-Object {
          $_.Current.ControlType.ProgrammaticName -match 'TabItem' -and $_.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected }
        foreach ($s in @($sel)) { if ((Norm $s.Current.Name) -eq (Norm $title)) { $looking = $true } }
      }
    } catch { Log ('LOOK CHECK SKIPPED ' + $_.Exception.Message) }
  }
  # Plain console chat (not Windows Terminal): suppress when that console window is already in front.
  $conHwndW = [string]$p.console_hwnd; $conClassW = [string]$p.console_class
  if (-not $wt -and $conClassW -eq 'ConsoleWindowClass' -and $conHwndW -match '^\d+$') {
    try {
      Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class FgCon { [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); }' -ErrorAction SilentlyContinue
      if ([int64][FgCon]::GetForegroundWindow() -eq [int64]$conHwndW) { $looking = $true }
    } catch { Log ('CONSOLE LOOK CHECK SKIPPED ' + $_.Exception.Message) }
  }
  if ($looking) { Log ("SUPPRESSED event=$event title=[$title] (owner is looking at this chat)"); exit 0 }

  # Learn where this chat's tab is while it is readable (this worker runs detached, so the reply is not delayed).
  # Records the window handle in the chat's tab map and refreshes the tab-name cache used by focus.ps1.
  if ($wt -and $title -ne 'Claude Code chat') {
    try {
      Add-Type -AssemblyName UIAutomationClient
      Add-Type -AssemblyName UIAutomationTypes
      Add-Type -TypeDefinition 'using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices; public static class WtList { public delegate bool EnumProc(IntPtr h, IntPtr p); [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc f, IntPtr p); [DllImport("user32.dll")] static extern int GetClassName(IntPtr h, StringBuilder s, int n); [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h); public static List<IntPtr> Visible() { var r = new List<IntPtr>(); EnumWindows((h, p) => { if (!IsWindowVisible(h)) return true; var c = new StringBuilder(256); GetClassName(h, c, 256); if (c.ToString() == "CASCADIA_HOSTING_WINDOW_CLASS") r.Add(h); return true; }, IntPtr.Zero); return r; } }' -ErrorAction SilentlyContinue
      $cacheFile = Join-Path $here 'wt-windows.json'
      $tabsCache = @{}; $lastMap = @{}
      if (Test-Path -LiteralPath $cacheFile) {
        $co = Get-Content -Raw -LiteralPath $cacheFile | ConvertFrom-Json
        if ($co.tabs) { foreach ($pp in $co.tabs.PSObject.Properties) { $tabsCache[$pp.Name] = @($pp.Value) } }
        if ($co.last) { foreach ($pp in $co.last.PSObject.Properties) { $lastMap[$pp.Name] = [string]$pp.Value } }
      }
      $learned = $null
      foreach ($h in [WtList]::Visible()) {
        $el = [System.Windows.Automation.AutomationElement]::FromHandle($h)
        $tabs = @($el.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) | Where-Object { $_.Current.ControlType.ProgrammaticName -match 'TabItem' })
        $tabsCache[([string][int64]$h)] = @($tabs | ForEach-Object { $_.Current.Name })
        foreach ($t in $tabs) { if ((Norm $t.Current.Name) -eq (Norm $title)) { $learned = [int64]$h } }
      }
      $co2 = [pscustomobject]@{ tabs = $tabsCache; last = $lastMap }
      if ($learned) { $lastMap[$wt] = [string]$learned; $co2.last = $lastMap }
      ($co2 | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $cacheFile -Encoding utf8
      if ($learned) {
        $mapFile = Join-Path $here ("wt-map\{0}.json" -f $wt)
        $me = [ordered]@{ wt_session = $wt; session_id = $sid; title = $title; cwd = $cwd; updated = (Get-Date).ToString('o') }
        if (Test-Path -LiteralPath $mapFile) { $old = Get-Content -Raw -LiteralPath $mapFile | ConvertFrom-Json; $me.cwd = [string]$old.cwd }
        $me['hwnd'] = [string]$learned
        New-Item -ItemType Directory -Path (Split-Path -Parent $mapFile) -Force | Out-Null
        ($me | ConvertTo-Json) | Set-Content -LiteralPath $mapFile -Encoding utf8
        Log ("LEARNED tab [{0}] in hwnd={1} for wt={2}" -f $title, $learned, $wt)
      }
    } catch { Log ('TAB LEARN SKIPPED ' + $_.Exception.Message) }
  }

  $locked = [bool](Get-Process -Name LogonUI -ErrorAction SilentlyContinue)
  if ($event -eq 'Stop') {
    $body = if ($locked) { 'Reply is ready. Open Windows Terminal to read it.' } else {
      $t = (Get-Last-Text $sid) -replace '\s+', ' '
      if ($t.Length -gt 160) { $t = $t.Substring(0, 157) + '...' }
      if ($t) { 'Finished: ' + $t } else { 'Reply is ready.' }
    }
  } else {
    $body = if ($locked) { 'Claude needs your attention. Open Windows Terminal.' } else { if ($msg) { $msg } else { 'Claude needs your attention.' } }
  }

  $launchUri = 'campusmeet-focus://focus?title=' + [uri]::EscapeDataString($title)
  if ($wt) { $launchUri = 'campusmeet-focus://focus?wt=' + $wt + '&title=' + [uri]::EscapeDataString($title) }
  # Plain console window (not Windows Terminal): the link carries its handle so the click can bring it back.
  $conHwnd = [string]$p.console_hwnd; $conClass = [string]$p.console_class
  if (-not $wt -and $conHwnd -match '^\d+$' -and $conHwnd -ne '0' -and $conClass -eq 'ConsoleWindowClass') {
    $launchUri += '&ch=' + $conHwnd
  }
  # Windows Terminal tab (the hook sees the tab's pseudo-console, not a plain console): read the Terminal window that
  # holds that tab, so the click can bring the window back (wh=). Same method as codex-toast.ps1.
  if (-not $wt -and $conClass -eq 'PseudoConsoleWindow' -and $conHwnd -match '^\d+$' -and $conHwnd -ne '0') {
    try {
      Add-Type -TypeDefinition 'using System; using System.Text; using System.Runtime.InteropServices; public static class ClaudeWtParent { [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr h); [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n); }' -ErrorAction SilentlyContinue
      $pw = [ClaudeWtParent]::GetParent([IntPtr]::new([int64]$conHwnd))
      if ($pw -ne [IntPtr]::Zero) {
        $sbw = New-Object System.Text.StringBuilder 256
        [void][ClaudeWtParent]::GetClassNameW($pw, $sbw, 256)
        if ($sbw.ToString() -eq 'CASCADIA_HOSTING_WINDOW_CLASS') { $launchUri += '&wh=' + [int64]$pw }
      }
    } catch { Log ('LINK WT PARENT SKIPPED ' + $_.Exception.Message) }
  }
  Log ("LINK event=$event wt=[$wt] console_class=[$conClass] console_hwnd=[$conHwnd] wh=[$(if ($launchUri -match '&wh=(\d+)') { $Matches[1] } else { '0' })] ch=[$(if ($launchUri -match '&ch=') { 'yes' } else { 'no' })]")
  $xmlText = @"
<toast launch="$([System.Security.SecurityElement]::Escape($launchUri))" activationType="protocol">
  <visual><binding template="ToastGeneric">
    <text>$([System.Security.SecurityElement]::Escape($title))</text>
    <text>$([System.Security.SecurityElement]::Escape("Project: $folder"))</text>
    <text>$([System.Security.SecurityElement]::Escape($body))</text>
  </binding></visual>
</toast>
"@
  [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
  [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
  $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
  $doc.LoadXml($xmlText)
  $toast = [Windows.UI.Notifications.ToastNotification]::new($doc)
  # One tag per chat (16 characters max): dismiss.ps1 removes it when the owner replies in that chat.
  $toast.Tag = ('s' + (($sid -replace '-', '') + '000000000000000').Substring(0, 15))
  $toast.Group = 'claude-code'
  [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe').Show($toast)
  Log ("SHOWN event=$event title=[$title] folder=[$folder] wt=[$wt] locked=$locked")
} catch {
  Log ('WORKER ERROR ' + $_.Exception.Message)
}
exit 0
