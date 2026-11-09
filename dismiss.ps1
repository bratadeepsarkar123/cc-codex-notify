# Phase 2 Stage 4: when the owner sends a message in a chat, remove that chat's toast from Action Center.
# Runs from the UserPromptSubmit hook. Reads the hook JSON from stdin. Prints nothing, always exits 0.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$logFile = Join-Path $here 'notify.log'
function Log([string]$m) { try { Add-Content -LiteralPath $logFile -Value ('{0} {1}' -f (Get-Date -Format o), $m) -Encoding utf8 } catch {} }
try {
  $raw = [Console]::In.ReadToEnd()
  if (-not $raw) { exit 0 }
  $sid = [string](($raw | ConvertFrom-Json).session_id)
  if ($sid -notmatch '^[0-9a-f-]{36}$') { exit 0 }
  # Same tag rule as notify.ps1: 's' plus the first 15 hex characters of the session id.
  $tag = 's' + (($sid -replace '-', '') + '000000000000000').Substring(0, 15)
  [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
  $history = [Windows.UI.Notifications.ToastNotificationManager]::History
  $history.Remove($tag, 'claude-code', '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe')
  Log ("DISMISS tag=$tag (chat replied)")
} catch {
  Log ('DISMISS ERROR ' + $_.Exception.Message)
}
exit 0
