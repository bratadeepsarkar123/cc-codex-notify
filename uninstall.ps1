# Removes the click handler registered by install.ps1.
# Does not edit Claude Code or Codex settings.

$key = 'HKCU:\Software\Classes\ccnotify-focus'
if (Test-Path -LiteralPath $key -ErrorAction Stop) {
    Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction Stop
    Write-Output "Removed $key (ccnotify-focus://)."
} else {
    Write-Output "Nothing to remove; ccnotify-focus:// is not registered for this user."
}
