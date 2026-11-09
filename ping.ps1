# Plays a chosen Windows sound and shows a balloon tip for an agent event.
# -Sound: path to a .wav file (default: Windows tada, used for "finished").
# Used by the Claude Code Stop and Notification hooks and the Codex notify wrapper.
param(
  [string]$Title = 'Agent finished',
  [string]$Text = 'Your reply is ready in the terminal.',
  [string]$Sound = 'C:/Windows/Media/tada.wav'
)
try {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  $icon = New-Object System.Windows.Forms.NotifyIcon
  $icon.Icon = [System.Drawing.SystemIcons]::Information
  $icon.Visible = $true
  $icon.ShowBalloonTip(4000, $Title, $Text, [System.Windows.Forms.ToolTipIcon]::Info)
  $player = New-Object System.Media.SoundPlayer $Sound
  $player.PlaySync()
  $icon.Dispose()
} catch {
  [System.Media.SystemSounds]::Exclamation.Play()
  Start-Sleep -Seconds 1
}
exit 0
