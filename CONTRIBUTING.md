# Contributing

Thanks for looking at this. It is a small Windows-only tool, so the bar is simple: keep it working, keep it readable, and keep private data out.

## Before you start

- Check the [open issues](https://github.com/bratadeepsarkar123/cc-codex-notify/issues). Issues marked **good first issue** are a good place to start.
- For anything bigger than a small fix, open an issue first and describe the problem. This saves you from building something that will not be merged.

## Setup

1. Windows 10 or 11, with PowerShell 5.1 (built in) and Node.js (only for the Codex wrapper).
2. Clone the repo and run `install.ps1` as the README describes.
3. Use a separate test chat. Do not test with your real working chats.

## Checks before a pull request

Every change must pass these checks:

- Every `.ps1` file parses with no errors. In PowerShell, run:
  ```
  [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path .\focus.ps1), [ref]$null, [ref]$null)
  ```
  Repeat for each `.ps1` file you changed. Check that the error list is empty.
- `codex-notify.js` passes `node --check codex-notify.js`.
- You have tested the behaviour you changed, and you say how in the pull request (for example: "clicked a Codex toast, window and tab came forward").

## Rules for the code

- **No personal data.** Never add personal folder paths, real chat titles, log files, window titles from your machine, API keys, or tokens. Runtime files (`*.log`, `wt-map\`, `wt-windows.json`, `queue\`) are git-ignored for this reason.
- **No network calls.** The tool runs only on your machine. Do not add anything that sends data out.
- **Only HKCU.** Registry writes go under `HKCU:` only. `install.ps1` must not edit `settings.json` or anything outside your user account.
- **Plain language.** Comments and the README should be readable by someone who is not a PowerShell expert.

## Pull requests

- Use a short title that says what changed.
- Link the issue it fixes, if there is one.
- Keep one topic per pull request.
- Update `README.md` if you change behaviour, install steps or the file list.

## Reporting bugs

Use the bug report template. Include what you expected, what happened, your Windows version, whether you use Windows Terminal or the plain console, and the relevant lines from the log file. Remove any paths or chat names from the log before you paste it.

## Licence

By contributing you agree that your contribution is released under the MIT licence in `LICENSE`.
