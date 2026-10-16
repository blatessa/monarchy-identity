# omarchy-identity-shell (omarchy-identity.status)

Optional Omarchy bar widget that shows the output of `omarchy-identity status --json`:

- `not enrolled`: the machine is on the `local` provider.
- `enrolled`: provider name, login mode, no warnings.
- warning (urgent colour): enrolled, but autologin is on or local `wheel` members exist.
- `identity: unavailable`: the CLI is missing, errored, timed out, or printed bad JSON.

Click for the full posture panel; middle-click to refresh. Poll interval is
`refreshIntervalSec` (default 60).

## This is NOT a security boundary

The plugin lives in `~/.config/omarchy/plugins/`, which the user owns. It is a
display only: it never runs a privileged command and enforces nothing. Real
enforcement is the root-owned config in `/etc` managed by `omarchy-identity`.
Hiding or editing this widget changes nothing about who can sign in.

## Requires

The `omarchy-identity` package (provides `omarchy-identity` on `PATH`). Without
it the widget shows `identity: unavailable` and the shell is unaffected.

## Files

- `manifest.json`: plugin manifest (`kinds: ["bar-widget"]`, entry point `Panel.qml`).
- `Panel.qml`: bar button, poller and popup.
- `Model.js`: pure JSON-to-view-model parsing (unit-tested under node).
- `tests/run.sh`: manifest check, Model.js tests, `qmllint` when available.
