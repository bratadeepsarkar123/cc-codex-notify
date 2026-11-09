# Registers the click handler and prints the settings you add by hand.
# Run once from this folder:  powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
# Only writes under HKCU (your user account). Does not edit settings.json.

$here = $PSScriptRoot
$focus = Join-Path $here 'focus.ps1'
if (-not (Test-Path -LiteralPath $focus)) { throw "focus.ps1 not found next to install.ps1" }

$key = 'HKCU:\Software\Classes\campusmeet-focus'
New-Item -Path $key -Force | Out-Null
Set-ItemProperty -Path $key -Name '(default)' -Value 'URL:campusmeet-focus protocol'
New-ItemProperty -Path $key -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
New-Item -Path "$key\shell\open\command" -Force | Out-Null
$cmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $focus + '" "%1"'
Set-ItemProperty -Path "$key\shell\open\command" -Name '(default)' -Value $cmd
Write-Output "Registered campusmeet-focus:// -> $focus"

$snippet = @"

Add these hooks to $env:USERPROFILE\.claude\settings.json (merge into the existing "hooks" block):

  "Stop": [ { "hooks": [
    { "type": "command", "shell": "powershell", "timeout": 10,
      "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"$here\notify.ps1\"" },
    { "type": "command", "shell": "powershell", "timeout": 10,
      "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"$here\wt-map.ps1\"" } ] } ],
  "Notification": [ { "matcher": "permission_prompt|elicitation_dialog", "hooks": [
    { "type": "command", "shell": "powershell", "timeout": 10,
      "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"$here\notify.ps1\"" } ] } ],
  "UserPromptSubmit": [ { "hooks": [
    { "type": "command", "shell": "powershell", "timeout": 10,
      "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"$here\dismiss.ps1\"" } ] } ]

For Codex, set notify in $env:USERPROFILE\.codex\config.toml to:
  notify = ["node", "$here\codex-notify.js", "<your original notify program>", "turn-ended"]

Optional: write "balloon" (no quotes) into mode.txt in this folder to use the simple Phase 1 balloon instead of toasts.
"@
Write-Output $snippet
