# Stop-hook helper for Phase 2: records which Windows Terminal tab (WT_SESSION) holds which chat.
# Writes one small file per WT_SESSION. Prints nothing, always exits 0, never blocks the reply.
$ErrorActionPreference = 'Stop'
$logFile = Join-Path $PSScriptRoot 'wt-map.log'
try {
  $wt = $env:WT_SESSION
  if (-not $wt) { exit 0 }
  $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
  $sid = [string]$payload.session_id
  if ($sid -notmatch '^[0-9a-f-]{36}$') { exit 0 }
  if ($wt -notmatch '^[0-9a-f-]{36}$') { exit 0 }
  $projects = (Join-Path $env:USERPROFILE '.claude\projects')
  $transcript = Get-ChildItem -LiteralPath $projects -Filter "$sid.jsonl" -Recurse -File | Select-Object -First 1
  $title = ''
  if ($transcript) {
    $line = Select-String -LiteralPath $transcript.FullName -Pattern '"type":"ai-title"' | Select-Object -Last 1
    if ($line) { $title = [string](($line.Line | ConvertFrom-Json).aiTitle) }
  }
  $dir = Join-Path $PSScriptRoot 'wt-map'
  New-Item -ItemType Directory -Path $dir -Force | Out-Null
  $entry = [ordered]@{
    wt_session = $wt
    session_id = $sid
    title      = $title
    cwd        = [string]$payload.cwd
    updated    = (Get-Date).ToString('o')
  }
  $target = Join-Path $dir "$wt.json"
  # Keep the window handle learned by notify.ps1, and the last known title, if the entry is for the same chat.
  if (Test-Path -LiteralPath $target) {
    $old = Get-Content -Raw -LiteralPath $target | ConvertFrom-Json
    if ($old.hwnd -and [string]$old.session_id -eq $sid) { $entry['hwnd'] = [string]$old.hwnd }
    # A new chat has no title until its transcript gets one: keep the old title rather than blanking it.
    if (-not $title -and [string]$old.session_id -eq $sid -and $old.title) { $entry['title'] = [string]$old.title }
  }
  $tmp = "$target.tmp"
  ($entry | ConvertTo-Json) | Set-Content -LiteralPath $tmp -Encoding utf8
  Move-Item -LiteralPath $tmp -Destination $target -Force
} catch {
  try { Add-Content -LiteralPath $logFile -Value ('{0} ERROR {1}' -f (Get-Date -Format o), $_.Exception.Message) -Encoding utf8 } catch {}
}
exit 0
