# Claude Code and Codex notifications for Windows

Side notifications (Windows toasts) when a Claude Code or Codex chat finishes, needs permission, or asks a question. Each toast shows the chat name, the project folder and the last reply. Clicking it brings back the exact Windows Terminal window and tab, or the plain console window, and switches to that window's virtual desktop.

## What it does

- **Stop and permission toasts for Claude Code**, with the chat name, folder and last reply.
- **Turn-end toasts for Codex** through its `notify` setting.
- **Click to focus:** a `ccnotify-focus://` link brings back the right window. For Windows Terminal it selects the tab by its title and follows the virtual desktop.
- **No toast when you are already looking at that chat.**
- **Dismiss on reply:** the toast is removed when you send the next message.
- **Fallback:** a simple balloon (`ping.ps1`) if toasts fail.

## Requirements

- Windows 10 or 11
- PowerShell 5.1 (built in)
- Node.js (for the Codex wrapper only)
- Claude Code and/or Codex installed

## Install

1. Clone or download this folder somewhere permanent, for example `C:\Tools\cc-codex-notify`.
2. Open PowerShell in that folder and run:
   ```
   powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
   ```
   This registers the `ccnotify-focus://` link for your user account only. It prints the hook block to add.
3. Merge the printed hooks into `%USERPROFILE%\.claude\settings.json`.
4. For Codex, set `notify` in `%USERPROFILE%\.codex\config.toml` as printed.
5. Start a new Claude Code or Codex chat, let it finish, and a toast should appear.

## Files

| File              | Purpose                                                                                  |
| ----------------- | ---------------------------------------------------------------------------------------- |
| `notify.ps1`      | Claude Code Stop, permission and question toasts. Works out which window the chat is in. |
| `wt-map.ps1`      | Remembers which Terminal window and tab a chat is in.                                    |
| `focus.ps1`       | Handles the click. Brings the window or tab forward and follows the desktop.             |
| `dismiss.ps1`     | Removes a chat's toast when you reply.                                                   |
| `codex-notify.js` | Codex `notify` wrapper. Shows the toast, then runs your original Codex notify program.   |
| `codex-toast.ps1` | Builds the Codex toast and its click link.                                               |
| `ping.ps1`        | Phase 1 balloon fallback.                                                                |
| `install.ps1`     | Registers the click link and prints the settings to add.                                 |

Runtime files are written next to the scripts (`*.log`, `wt-map\`, `wt-windows.json`, `queue\`). They are ignored by git and contain window titles, so keep them private.

## Limits

- The window link uses the Terminal tab title. Two tabs with the same title in one window can be confused.
- Codex runs started with `codex exec` exit before the notify step, so they cannot be linked back to a window.
- Virtual desktop switching uses the Windows shortcut keys (Win+Ctrl+Left/Right). It only changes the view; windows are never moved.
- Tested on Windows 11 with Windows Terminal and the plain console. Not tested on other setups.

## Notes

- The link name `ccnotify-focus://` is only a name. To change it, edit `install.ps1`, `notify.ps1`, `codex-toast.ps1` and `focus.ps1` together, then run `install.ps1` again.
- Nothing here sends data anywhere. Everything runs on your machine.

## License

MIT. See `LICENSE`.
