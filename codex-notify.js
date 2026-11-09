// Codex notify wrapper: plays the Windows ping, then runs the original notify program
// with exactly the arguments Codex passed (so the existing computer-use helper still runs).
// Usage (config.toml): notify = ["node", "<this file>", "<original exe>", "turn-ended"]
// The ping runs synchronously: a detached child was not reliably finishing under Codex.
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const logFile = path.join(__dirname, "codex-notify.log");
const logLine = (m) =>
  fs.appendFileSync(logFile, new Date().toISOString() + " " + m + "\n");

const [, , original, ...rest] = process.argv;
logLine("called: " + JSON.stringify(process.argv.slice(2)).slice(0, 200));

// Stage 5: a toast with the project folder and last reply (codex-toast.ps1). The Phase 1 balloon is the fallback.
let payload = {};
try {
  payload = JSON.parse(rest.find((a) => a.trim().startsWith("{")) || "{}");
} catch (e) {
  logLine("payload parse error " + e.message);
}
const cwd = String(payload.cwd || "");
const folder = cwd ? path.basename(cwd) : "";
const lastMsg = String(payload["last-assistant-message"] || "")
  .replace(/\s+/g, " ")
  .trim();
const wt = /^[0-9a-fA-F-]{36}$/.test(process.env.WT_SESSION || "")
  ? process.env.WT_SESSION
  : "";
const toast = spawnSync(
  "powershell",
  [
    "-NoProfile",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    path.join(__dirname, "codex-toast.ps1"),
    "-Title",
    folder ? "Codex: " + folder : "Codex chat",
    "-Folder",
    folder || "(no folder)",
    "-Body",
    lastMsg || "Your reply is ready in the terminal.",
    "-Wt",
    // PowerShell drops empty arguments, so send a placeholder; codex-toast.ps1 turns a non-GUID into "".
    wt || "none",
    "-Cwd",
    // Placeholder for the same reason as -Wt: codex-toast.ps1 uses the project folder to find the console.
    cwd || "none",
  ],
  { stdio: "ignore", windowsHide: true, timeout: 20000 },
);
logLine(
  "toast exit " +
    toast.status +
    (toast.error ? " error " + toast.error.message : ""),
);
if (toast.status !== 0) {
  const ping = spawnSync(
    "powershell",
    [
      "-NoProfile",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      path.join(__dirname, "ping.ps1"),
      "-Title",
      "Codex finished",
      "-Text",
      "Your reply is ready in the terminal.",
    ],
    { stdio: "ignore", windowsHide: true, timeout: 20000 },
  );
  logLine("fallback ping exit " + ping.status);
}

if (original) {
  const r = spawnSync(original, rest, { stdio: "inherit", windowsHide: true });
  logLine("original exit " + r.status);
  process.exitCode = r.status ?? 0;
}
