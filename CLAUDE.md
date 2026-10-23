# Dumpster – notes for Claude

## The web version (source of truth)

The correct web version is the live site: https://dumpster-web-manus.vercel.app/
(Vercel project `dumpster-web-manus`). Use it, not `src/` in this repo, as the reference
when asked to make the native iOS app "match the web". `src/` here is an older web
codebase (its `SettingsPanel.tsx` is NOT what's deployed).

How to inspect it from a cloud session: the sandbox proxy blocks `*.vercel.app`, so use the
Vercel MCP tool `web_fetch_vercel_url` (fetches HTML/JS only, no rendering). The app is a
code-split Vite bundle; the Main Menu lives in `assets/Home-*.js`. Large responses are
saved to a file; grep that file instead of reading it whole.

Web Main Menu (verified from the live bundle, 2026-10-23): header "MAIN MENU" /
"Tap a folder to open", an account card (Sign In or user + PRO/FREE · credits), then
folders in this order — AI TOOLS (Taste Profile · Instagram Scrub · Dump Styles),
FRIENDS (Find friends · Profiles · Comments), APPEARANCE (Accent color),
YOUR AI KEYS (Add & verify your own keys), SOCIAL MEDIA (Connect & export),
ABOUT / HELP (Dumpster · Version 1.0) — then a "DUMPSTER v1.0" footer.
