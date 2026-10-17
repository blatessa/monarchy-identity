@AGENTS.md

## Claude Code notes
- Shell state doesn't persist: use absolute paths, and run the lab's long VM boots in the background (`setsid`, never `pkill -f`).
- Prefer reading code over docs when they disagree; fix the docs.
- Ask before anything outward-facing (pushing tags, releases, repo settings, publishing the site).
