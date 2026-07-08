---
name: rebuild
description: Rebuild WisprOwn.app, replace the running instance, relaunch it, and verify from logs that it reaches the ready state. Use when the user asks to rebuild, reload, restart, or "get the new version running" of the WisprOwn app.
---

# Rebuild & relaunch WisprOwn

Run the full build-replace-verify cycle for `dist/WisprOwn.app`:

1. **Check the signing identity first**: `security find-identity -v -p codesigning | grep -c "WisprOwn Dev"`.
   - If it is missing, WARN the user before proceeding: the rebuild will be ad-hoc signed, macOS will drop the Accessibility grant, and they will have to remove/re-add WisprOwn in System Settings → Privacy & Security → Accessibility afterwards. Recommend running `./Scripts/make-signing-cert.sh` first (they must run it themselves — it touches the keychain).
2. Build and relaunch: `make reload` (equivalent to `make app && pkill -f 'WisprOwn.app/Contents/MacOS/WisprOwn' && open dist/WisprOwn.app`).
3. Wait ~8 seconds, then verify from logs (NOTE: use `/usr/bin/log`, not `log` — zsh shadows it with a builtin):
   `/usr/bin/log show --process WisprOwn --last 1m --style compact | grep -E 'app:|ui:|hotkey:'`
4. Report the outcome to the user:
   - `app: ready` + `hotkey: listening` → all good, say so.
   - `app: waiting for permissions (… ax=false)` → the Accessibility grant was dropped (ad-hoc build); walk them through remove/re-add in System Settings; the app picks it up within 2 s of the grant, no restart needed.
   - No log lines / process missing (`pgrep -lf WisprOwn`) → investigate crash reports in `~/Library/Logs/DiagnosticReports/WisprOwn*`.

Models and CoreML caches are never touched by a rebuild — startup after reload is fast.
